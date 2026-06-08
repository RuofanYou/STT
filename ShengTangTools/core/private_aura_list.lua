-- 个人光环列表（Beta）
-- 目标：验证 C_UnitAuras.AddPrivateAuraAnchor 的 parent frame 在客户端渲染图标时
-- 是否会在 frame 层级里增加 child / region，从而判断"此团员当前有私密光环"。
-- 仅在 debugMode + 启用主开关 + ENCOUNTER_START~END 之间激活，进入战斗外自动释放 anchor。

local T, C = unpack(select(2, ...))
T.RegisterColdFile("privateAuraList.enabled", function()

local DB_KEY = "privateAuraList"

local AddPrivateAuraAnchor = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor

local M = T.ModuleLoader:NewModule({
    name = "PrivateAuraList",
    dbKey = DB_KEY .. ".enabled",
    defaultEnabled = false,
})
T.PrivateAuraList = M

local PROBE_INTERVAL = 0.1
local FRAME_STRATA = "MEDIUM"
local FRAME_LEVEL = 1000

-- 模块状态
local rows = {}              -- rows[unit] = { frame, anchorFrames={af1,af2,...}, anchorIds={...}, lastProbeKey={}, unit, name }
local rowOrder = {}          -- 按团员索引顺序的 unit 列表（用于稳定布局）
local listFrame              -- 主容器（可拖动）
local listTitle              -- 标题/拖动条
local active = false         -- 是否在 ENCOUNTER 内
local testMode = false       -- 测试模式：忽略 ENCOUNTER 限制
local probeFrame             -- OnUpdate 探针
local probeAccum = 0

----------------------------------------------------------------------
-- DB 访问
----------------------------------------------------------------------

local function GetDB()
    if type(C.DB) ~= "table" then
        return nil
    end
    if type(C.DB[DB_KEY]) ~= "table" then
        C.DB[DB_KEY] = {}
    end
    return C.DB[DB_KEY]
end

local function WriteSavedVar(key, value)
    if type(STT_DB) ~= "table" then
        return
    end
    STT_DB[DB_KEY] = STT_DB[DB_KEY] or {}
    STT_DB[DB_KEY][key] = value
end

local function IsDebugOn()
    return C.DB and C.DB.debugMode == true
end

function M:IsEnabled()
    local db = GetDB()
    return db ~= nil and db.enabled == true and IsDebugOn()
end

----------------------------------------------------------------------
-- 团队遍历（参照 core/buff_check.lua:587）
----------------------------------------------------------------------

local function IterateGroupUnits()
    local units = {}
    if IsInRaid() then
        for index = 1, 40 do
            local unit = "raid" .. index
            if UnitExists(unit) then
                units[#units + 1] = unit
            end
        end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        for index = 1, 4 do
            local unit = "party" .. index
            if UnitExists(unit) then
                units[#units + 1] = unit
            end
        end
    else
        units[#units + 1] = "player"
    end
    return units
end

----------------------------------------------------------------------
-- listFrame 构建
----------------------------------------------------------------------

local function SavePosition()
    if not listFrame then return end
    local point, _, relPoint, x, y = listFrame:GetPoint(1)
    local pos = {
        point = point or "CENTER",
        relPoint = relPoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
    local db = GetDB()
    if db then
        db.pos = pos
        WriteSavedVar("pos", pos)
    end
    T.debug(string.format("[PAL][POS] save point=%s rel=%s x=%.0f y=%.0f",
        pos.point, pos.relPoint, pos.x, pos.y))
end

local function ApplyPosition()
    if not listFrame then return end
    local db = GetDB() or {}
    local pos = db.pos or { point = "CENTER", relPoint = "CENTER", x = 200, y = 0 }
    listFrame:ClearAllPoints()
    listFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function CreateListFrame()
    if listFrame then return end
    listFrame = CreateFrame("Frame", "STT_PrivateAuraListFrame", UIParent, "BackdropTemplate")
    listFrame:SetFrameStrata(FRAME_STRATA)
    listFrame:SetFrameLevel(FRAME_LEVEL)
    listFrame:SetMovable(true)
    listFrame:SetClampedToScreen(true)
    listFrame:SetSize(220, 60)

    if listFrame.SetBackdrop then
        listFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        listFrame:SetBackdropColor(0, 0, 0, 0.35)
        listFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)
    end

    listTitle = CreateFrame("Button", nil, listFrame)
    listTitle:SetHeight(18)
    listTitle:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, -2)
    listTitle:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, -2)
    listTitle:RegisterForDrag("LeftButton")
    listTitle:SetScript("OnDragStart", function() listFrame:StartMoving() end)
    listTitle:SetScript("OnDragStop", function()
        listFrame:StopMovingOrSizing()
        SavePosition()
    end)

    local titleText = listTitle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", listTitle, "LEFT", 4, 0)
    titleText:SetText("个人光环列表 (Beta) — 拖动")
    titleText:SetTextColor(1, 0.82, 0)
    listTitle.text = titleText

    ApplyPosition()
    listFrame:Hide()
end

local function HideTitleIfHasIcons()
    -- 战斗中希望只看到团员行；标题仅在 testMode 或空闲时显示，便于拖动
    if not listTitle then return end
    if testMode then
        listTitle:Show()
        if listTitle.text then listTitle.text:Show() end
    else
        -- 战斗中也保留小标题条以便拖动，但是文字浅化
        listTitle:Show()
    end
end

----------------------------------------------------------------------
-- Row（每个团员一行）
----------------------------------------------------------------------

local function CreateRow(unit)
    local db = GetDB() or {}
    local iconSize = db.iconSize or 36
    local rowHeight = db.rowHeight or 40
    local maxIcons = db.maxIconsPerUnit or 2

    local row = CreateFrame("Frame", nil, listFrame)
    row:SetHeight(rowHeight)
    row:SetWidth(listFrame:GetWidth() - 8)

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
    nameText:SetWidth(80)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local anchorFrames = {}
    local lastX = 86
    for i = 1, maxIcons do
        local af = CreateFrame("Frame", nil, row)
        af:SetSize(iconSize, iconSize)
        af:SetPoint("LEFT", row, "LEFT", lastX, 0)
        -- 测试探针：给一个边框便于肉眼观察 anchor 位置
        if not af.bg then
            local tex = af:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(true)
            tex:SetColorTexture(1, 1, 1, 0.05)
            af.bg = tex
        end
        anchorFrames[i] = af
        lastX = lastX + iconSize + 4
    end

    return {
        frame = row,
        nameText = nameText,
        anchorFrames = anchorFrames,
        anchorIds = {},
        lastProbeKey = {},
        lastShown = false,
        unit = unit,
        name = UnitName(unit) or unit,
    }
end

local function DestroyRow(row)
    if not row then return end
    -- 释放 anchor
    for i, aid in ipairs(row.anchorIds) do
        if aid and RemovePrivateAuraAnchor then
            pcall(RemovePrivateAuraAnchor, aid)
        end
        row.anchorIds[i] = nil
    end
    if row.frame then
        row.frame:Hide()
        row.frame:ClearAllPoints()
        row.frame:SetParent(nil)
    end
end

----------------------------------------------------------------------
-- anchor 挂载
----------------------------------------------------------------------

local function AttachAnchorsForRow(row)
    if not AddPrivateAuraAnchor then
        if T.debugOnce then
            T.debugOnce("PAL_ADD_API_MISSING", "[PAL][ADD] AddPrivateAuraAnchor API not available")
        end
        return
    end
    local db = GetDB() or {}
    local iconSize = db.iconSize or 36

    for i, af in ipairs(row.anchorFrames) do
        if row.anchorIds[i] and RemovePrivateAuraAnchor then
            pcall(RemovePrivateAuraAnchor, row.anchorIds[i])
            row.anchorIds[i] = nil
        end
        local ok, aid = pcall(AddPrivateAuraAnchor, {
            unitToken = row.unit,
            auraIndex = i,
            parent = af,
            showCountdownFrame = true,
            showCountdownNumbers = true,
            isContainer = false,
            iconInfo = {
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = af,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
                iconWidth = iconSize,
                iconHeight = iconSize,
                borderScale = 0.01,
            },
        })
        if ok then
            row.anchorIds[i] = aid
        else
            T.debug(string.format("[PAL][ADD] unit=%s name=%s slot=%d FAILED err=%s",
                row.unit, row.name, i, tostring(aid)))
        end
        row.lastProbeKey[i] = nil
    end
end

----------------------------------------------------------------------
-- 探针：检测 anchor parent frame 的 DOM 变化
----------------------------------------------------------------------

local function ProbeRow(row, verbose)
    local anyHasIcon = false
    for i, af in ipairs(row.anchorFrames) do
        local nChildren = af:GetNumChildren() or 0
        local nRegions = af:GetNumRegions() or 0
        -- 自己创建的 bg texture 占一个 region，从计数中扣除
        local effectiveRegions = nRegions - (af.bg and 1 or 0)
        local isShown = af:IsShown()
        local hasIcon = (nChildren > 0) or (effectiveRegions > 0)
        local key = string.format("%d|%d|%s", nChildren, effectiveRegions, tostring(isShown))
        if row.lastProbeKey[i] ~= key then
            row.lastProbeKey[i] = key
            if verbose and nChildren > 0 then
                for c = 1, nChildren do
                    local child = select(c, af:GetChildren())
                    if child then
                        local ok1, otype = pcall(function() return child:GetObjectType() end)
                        local ok2, cname = pcall(function() return child:GetName() end)
                        local ok3, cshown = pcall(function() return child:IsShown() end)
                        T.debug(string.format("[PAL][CHILD] unit=%s slot=%d c=%d type=%s name=%s shown=%s",
                            row.unit, i, c,
                            ok1 and tostring(otype) or "?",
                            ok2 and tostring(cname) or "?",
                            ok3 and tostring(cshown) or "?"))
                    end
                end
            end
            if verbose and effectiveRegions > 0 then
                local startIdx = af.bg and 2 or 1
                for r = startIdx, nRegions do
                    local region = select(r, af:GetRegions())
                    if region then
                        local ok1, otype = pcall(function() return region:GetObjectType() end)
                        local ok2, rname = pcall(function() return region:GetName() end)
                        T.debug(string.format("[PAL][REGION] unit=%s slot=%d r=%d type=%s name=%s",
                            row.unit, i, r,
                            ok1 and tostring(otype) or "?",
                            ok2 and tostring(rname) or "?"))
                    end
                end
            end
        end
        if hasIcon then
            anyHasIcon = true
        end
    end
    return anyHasIcon
end

----------------------------------------------------------------------
-- 布局：动态收缩
----------------------------------------------------------------------

function M:RelayoutVisible()
    if not listFrame then return end
    local db = GetDB() or {}
    local rowHeight = db.rowHeight or 40
    local spacing = db.spacing or 4
    local growUp = (db.growthDirection == "UP")

    local titleH = (listTitle and listTitle:IsShown()) and 20 or 0
    local visibleCount = 0
    local lastAnchor

    for _, unit in ipairs(rowOrder) do
        local row = rows[unit]
        if row and row.frame:IsShown() then
            row.frame:ClearAllPoints()
            if not lastAnchor then
                if growUp then
                    row.frame:SetPoint("BOTTOM", listFrame, "BOTTOM", 0, 4)
                else
                    row.frame:SetPoint("TOP", listFrame, "TOP", 0, -(titleH + 2))
                end
            else
                if growUp then
                    row.frame:SetPoint("BOTTOM", lastAnchor, "TOP", 0, spacing)
                else
                    row.frame:SetPoint("TOP", lastAnchor, "BOTTOM", 0, -spacing)
                end
            end
            lastAnchor = row.frame
            visibleCount = visibleCount + 1
        end
    end

    -- 自适应高度
    local newH = math.max(40, titleH + 4 + visibleCount * (rowHeight + spacing) + (visibleCount > 0 and -spacing or 0))
    listFrame:SetHeight(newH)
end

----------------------------------------------------------------------
-- 重建：根据当前 group 创建/销毁 row + 挂 anchor
----------------------------------------------------------------------

function M:RebuildAnchors()
    if not listFrame then return end
    local units = IterateGroupUnits()

    -- 销毁不再存在的 row
    local seen = {}
    for _, unit in ipairs(units) do seen[unit] = true end
    for unit, row in pairs(rows) do
        if not seen[unit] then
            DestroyRow(row)
            rows[unit] = nil
        end
    end

    -- 创建新 row
    rowOrder = {}
    for _, unit in ipairs(units) do
        rowOrder[#rowOrder + 1] = unit
        local row = rows[unit]
        if not row then
            row = CreateRow(unit)
            rows[unit] = row
        else
            row.name = UnitName(unit) or unit
            row.nameText:SetText(row.name)
        end
        row.nameText:SetText(row.name)
        row.frame:Hide()       -- 默认隐藏，等探针发现 child 后 Show
        row.lastShown = false
        AttachAnchorsForRow(row)
    end

    self:RelayoutVisible()
end

----------------------------------------------------------------------
-- OnUpdate 探针
----------------------------------------------------------------------

local function StartProbe()
    if not probeFrame then
        probeFrame = CreateFrame("Frame")
        probeFrame:SetScript("OnUpdate", function(_, elapsed)
            probeAccum = probeAccum + elapsed
            if probeAccum < PROBE_INTERVAL then return end
            probeAccum = 0

            local db = GetDB() or {}
            local verbose = db.verboseProbeLog == true
            local layoutDirty = false

            for _, unit in ipairs(rowOrder) do
                local row = rows[unit]
                if row then
                    local anyHasIcon = ProbeRow(row, verbose)
                    if anyHasIcon ~= row.lastShown then
                        row.lastShown = anyHasIcon
                        if anyHasIcon then
                            row.frame:Show()
                        else
                            row.frame:Hide()
                        end
                        layoutDirty = true
                    end
                end
            end

            if layoutDirty then
                M:RelayoutVisible()
            end
        end)
    end
    probeFrame:Show()
    probeAccum = 0
end

local function StopProbe()
    if probeFrame then
        probeFrame:Hide()
    end
end

----------------------------------------------------------------------
-- 激活/反激活
----------------------------------------------------------------------

function M:Activate(reason)
    if active then return end
    if not self:IsEnabled() and not testMode then
        return
    end
    CreateListFrame()
    listFrame:Show()
    HideTitleIfHasIcons()
    self:RebuildAnchors()
    StartProbe()
    active = true
end

function M:Deactivate(reason)
    if not active then return end
    StopProbe()
    local removed = 0
    for _, row in pairs(rows) do
        for i, aid in ipairs(row.anchorIds) do
            if aid and RemovePrivateAuraAnchor then
                pcall(RemovePrivateAuraAnchor, aid)
                removed = removed + 1
            end
            row.anchorIds[i] = nil
        end
        row.frame:Hide()
        row.lastShown = false
        row.lastProbeKey = {}
    end
    if listFrame then
        listFrame:Hide()
    end
    active = false
end

function M:ApplySettings()
    -- 设置变化时（主开关、滑条）：先 Deactivate，若仍处于 active 场景则重激活
    self:Deactivate("ApplySettings")
    -- 若启用 且 当前在 encounter 内 或 测试模式 → 重激活
    if (self:IsEnabled() and self._inEncounter) or testMode then
        self:Activate("ApplySettings")
    end
end

----------------------------------------------------------------------
-- 测试模式：不依赖 ENCOUNTER，强制激活；图标位置由 anchor 显示假图标说明
----------------------------------------------------------------------

function M:ToggleTestMode()
    testMode = not testMode
    if testMode then
        -- 强制激活
        self:Deactivate("EnterTestMode")
        testMode = true  -- Deactivate 不改 testMode 但这里再确认
        CreateListFrame()
        listFrame:Show()
        self:RebuildAnchors()
        -- 测试模式下立即把所有 row 都显示出来，方便观察布局
        for _, row in pairs(rows) do
            row.frame:Show()
            row.lastShown = true
        end
        self:RelayoutVisible()
        StartProbe()
        active = true
        T.debug("[PAL][TOGGLE] enter test mode (force show all rows)")
    else
        self:Deactivate("ExitTestMode")
        T.debug("[PAL][TOGGLE] exit test mode")
    end
end

----------------------------------------------------------------------
-- 手动 dump 快照
----------------------------------------------------------------------

function M:DumpSnapshot()
    T.debug("[PAL][SNAP] ===== begin snapshot =====")
    T.debug(string.format("[PAL][SNAP] active=%s testMode=%s enabled=%s debug=%s rowCount=%d",
        tostring(active), tostring(testMode), tostring(self:IsEnabled()),
        tostring(IsDebugOn()), (function() local n=0 for _ in pairs(rows) do n=n+1 end return n end)()))
    for _, unit in ipairs(rowOrder) do
        local row = rows[unit]
        if row then
            for i, af in ipairs(row.anchorFrames) do
                local nC = af:GetNumChildren() or 0
                local nR = af:GetNumRegions() or 0
                local effR = nR - (af.bg and 1 or 0)
                local aid = row.anchorIds[i]
                T.debug(string.format("[PAL][SNAP] unit=%s name=%s slot=%d anchorId=%s children=%d regions=%d(eff=%d) shown=%s rowShown=%s",
                    row.unit, row.name, i, tostring(aid), nC, nR, effR,
                    tostring(af:IsShown()), tostring(row.frame:IsShown())))
            end
        end
    end
    T.debug("[PAL][SNAP] ===== end snapshot =====")
end

----------------------------------------------------------------------
-- 事件
----------------------------------------------------------------------

function M:OnRegister()
    T.PrivateAuraList = self
end

function M:OnFirstLoad()
    self._inEncounter = false
end

function M:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN", "OnEvent")
    self:RegisterEvent("ENCOUNTER_START", "OnEvent")
    self:RegisterEvent("ENCOUNTER_END", "OnEvent")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnEvent")
    if IsLoggedIn and IsLoggedIn() then
        CreateListFrame()
    end
end

function M:OnDisable()
    testMode = false
    self:Deactivate("ModuleDisable")
    if listFrame then
        listFrame:Hide()
    end
end

function M:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        -- 创建 frame 但不显示
        CreateListFrame()
    elseif event == "ENCOUNTER_START" then
        M._inEncounter = true
        if M:IsEnabled() and not testMode then
            M:Activate("ENCOUNTER_START")
        end
    elseif event == "ENCOUNTER_END" then
        M._inEncounter = false
        if not testMode then
            M:Deactivate("ENCOUNTER_END")
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if active then
            M:RebuildAnchors()
        end
    end
end

end)
