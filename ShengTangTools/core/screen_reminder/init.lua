-- screen_reminder/init.lua
-- 屏幕提醒 V2 主入口：ScreenReminder
--
-- 锚点设计：
--   每个 indicator 拥有一个**持久 anchor frame**作为容器。
--   indicator 实例显示时 SetParent(anchorFrame) + SetPoint("CENTER", anchorFrame, "CENTER")，
--   随 anchorFrame 一起移动。
--   解锁时给 anchorFrame 开启 movable + 边框/标签；锁定时只是把这些视觉关掉，位置不变。
--   拖完 anchorFrame，正在显示的 instance 因父子关系自动跟随 — 不需要同步代码。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

local Schema = T.ScreenReminderSchema

local ScreenReminder = {
    active = {},           -- 活动 instance 列表 { {ind, instance, kind, anchorFrame} }
    anchorFrames = {},     -- ind.id -> 持久 anchor frame
    groups = {},           -- ind.id -> { records = { record, ... } }
}
T.ScreenReminder = ScreenReminder

local function GetIndicatorModule(kind)
    return T.ScreenReminderIndicators and T.ScreenReminderIndicators[kind]
end

-- ──────────────────────────────────────────────────────────────────────
-- 应用 anchor 数据到 frame（点 / 偏移）
-- ──────────────────────────────────────────────────────────────────────
local function ApplyAnchorData(frame, anchor)
    frame:ClearAllPoints()
    local data = anchor or {}
    frame:SetPoint(
        data.point or "CENTER",
        _G[data.relativeTo or "UIParent"] or UIParent,
        data.relativePoint or data.point or "CENTER",
        tonumber(data.x) or 0,
        tonumber(data.y) or 0
    )
end

-- 估算 indicator 实际显示区域尺寸，让 anchor frame 视觉匹配
-- text 的字号变化会让 anchor frame 跟着大/小，避免拖拽 box 误导玩家
local function EstimateIndicatorSize(ind)
    local kind = ind.kind
    local style = ind.style or {}
    if kind == "text" then
        local fs = math.max(8, tonumber(style.fontSize) or 28)
        local scale = math.max(0.5, math.min(3, tonumber(style.scale) or 1))
        -- 经验估算：每个汉字 ~ 1.0 fs，"3.0s 测试文案" 约 7 字符宽
        return math.max(120, math.floor(fs * 6 * scale + 0.5)),
               math.max(24, math.floor((fs + 12) * scale + 0.5))
    elseif kind == "icon" then
        local size = math.max(16, tonumber(style.size) or 36)
        return size + 4, size + 4
    elseif kind == "bar" then
        return math.max(80, tonumber(style.width) or 240),
               math.max(12, tonumber(style.height) or 20)
    elseif kind == "circle" then
        local r = math.max(12, tonumber(style.radius) or 32)
        return r * 2, r * 2
    end
    return 120, 36
end

local function NormalizeStackDir(value)
    if value == "DOWN" or value == "LEFT" or value == "RIGHT" then
        return value
    end
    return "UP"
end

-- ──────────────────────────────────────────────────────────────────────
-- 获取/创建 indicator 的 anchor frame（持久）
-- ──────────────────────────────────────────────────────────────────────
function ScreenReminder:EnsureAnchorFrame(ind)
    local frame = self.anchorFrames[ind.id]
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("HIGH")
        frame:SetMovable(true)
        frame:Show()
        self.anchorFrames[ind.id] = frame
    end

    frame.__ind = ind
    -- 尺寸跟随 indicator 实际显示区域（字号变了 anchor 框也跟着变）
    local w, h = EstimateIndicatorSize(ind)
    frame:SetSize(w, h)
    ApplyAnchorData(frame, ind.anchor)

    -- 注册到 T.EditMode（单一权威拖拽/视觉），重复 Register 内部会先 Unregister 旧的
    if T.EditMode and T.EditMode.Register then
        T.EditMode:Register({
            frame = frame,
            displayName = ind.name or ind.kind,
            saveFunc = function(point, relPoint, x, y)
                ind.anchor = ind.anchor or {}
                ind.anchor.point = point
                ind.anchor.relativeTo = "UIParent"
                ind.anchor.relativePoint = relPoint or point
                ind.anchor.x = math.floor(x + 0.5)
                ind.anchor.y = math.floor(y + 0.5)
                if ScreenReminder.onAnchorChanged then
                    ScreenReminder.onAnchorChanged(ind.id)
                end
            end,
            onEnter = function(anchorFrame)
                local overlay = T.EditMode and T.EditMode.GetOverlay and T.EditMode:GetOverlay(anchorFrame)
                if overlay and UIFrameFadeIn then
                    overlay:SetAlpha(0)
                    UIFrameFadeIn(overlay, (T.SR_MORPH and T.SR_MORPH.ANCHOR_FADE_IN) or 0.16, 0, 1)
                end
            end,
            onClick = function(anchorFrame)
                if Schema and Schema.SetSelectedIndicator then
                    Schema.SetSelectedIndicator(ind.id)
                end
                if ScreenReminder.onAnchorClicked then
                    ScreenReminder.onAnchorClicked(ind.id, anchorFrame)
                end
            end,
            group = "solo",
        })
    end

    -- 当前是否处于解锁态，立即应用
    if not Schema.IsLocked() and T.EditMode and T.EditMode.Enter then
        T.EditMode:Enter(frame)
    end

    return frame
end

-- ──────────────────────────────────────────────────────────────────────
-- 多实例动态堆叠（参考 TimelineReminders 的 RegionGroup:PositionRegions）
-- text/icon/bar：沿 stackDir 累计偏移；circle：所有实例叠在 anchor 中心。
-- ──────────────────────────────────────────────────────────────────────
function ScreenReminder:RepositionGroup(indID)
    local group = self.groups[indID]
    if not group or not group.records then return end
    local anchorFrame = self.anchorFrames[indID]
    if not anchorFrame then return end
    local ind = Schema and Schema.GetIndicator(indID)
    if not ind then return end

    local style = ind.style or {}

    -- circle 不堆叠：全部叠在 anchor 中心（与 TimelineReminders CircleAnchor 一致）
    if ind.kind == "circle" then
        for _, record in ipairs(group.records) do
            local frm = record.instance and record.instance.frame
            if frm then
                frm:ClearAllPoints()
                frm:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)
            end
        end
        return
    end

    local stackDir = NormalizeStackDir(style.stackDir)
    local spacing = tonumber(style.stackSpacing) or 2

    local offsetX, offsetY = 0, 0
    local point, anchorPoint
    if stackDir == "UP" then
        point, anchorPoint = "BOTTOM", "BOTTOM"
    elseif stackDir == "DOWN" then
        point, anchorPoint = "TOP", "TOP"
    elseif stackDir == "LEFT" then
        point, anchorPoint = "RIGHT", "RIGHT"
    elseif stackDir == "RIGHT" then
        point, anchorPoint = "LEFT", "LEFT"
    else
        point, anchorPoint = "BOTTOM", "BOTTOM"
    end

    for _, record in ipairs(group.records) do
        local frm = record.instance and record.instance.frame
        if frm then
            frm:ClearAllPoints()
            frm:SetPoint(point, anchorFrame, anchorPoint, offsetX, offsetY)
            local h = frm:GetHeight() or 0
            local w = frm:GetWidth() or 0
            if stackDir == "UP" then
                offsetY = offsetY + h + spacing
            elseif stackDir == "DOWN" then
                offsetY = offsetY - h - spacing
            elseif stackDir == "LEFT" then
                offsetX = offsetX - w - spacing
            elseif stackDir == "RIGHT" then
                offsetX = offsetX + w + spacing
            end
        end
    end
end

-- GUI 改值后调用：把最新 ind 数据同步到 anchor frame + 所有该 ind 的活动 instance
function ScreenReminder:SyncIndicator(id)
    if not id then return end
    local ind = Schema and Schema.GetIndicator(id)
    if not ind then return end

    local frame = self.anchorFrames[id]
    if frame then
        local w, h = EstimateIndicatorSize(ind)
        frame:SetSize(w, h)
        if T.EditMode and T.EditMode.SetDisplayName then
            T.EditMode:SetDisplayName(frame, ind.name or ind.kind)
        end
        ApplyAnchorData(frame, ind.anchor)
    end

    for _, record in ipairs(self.active) do
        if record.ind == ind or record.ind.id == id then
            record.instance:SetData(ind)
            record.instance:Refresh()
            -- 因 instance 是 anchorFrame 的 child，位置自动跟随 anchorFrame
        end
    end

    -- 字号/方向变了，重新排列
    self:RepositionGroup(id)
end

-- 编辑态视觉与拖拽完全由 T.EditMode 接管（core/editmode.lua）

-- ──────────────────────────────────────────────────────────────────────
-- Show(ctx)：时间轴触发入口
-- ──────────────────────────────────────────────────────────────────────
local function BuildIndicatorNameList(indicators)
    local names = {}
    for _, ind in ipairs(indicators or {}) do
        names[#names + 1] = tostring(ind.name or "")
    end
    return table.concat(names, ",")
end

local function BuildTargetNameList(targets)
    local names = {}
    for name in pairs(targets or {}) do
        names[#names + 1] = tostring(name)
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function IndicatorPassesRoute(ind, targets)
    if type(targets) == "table" then
        return targets[ind.name] == true
    end
    return ind.exclusiveMode ~= true
end

local function NormalizeSpellTokenDisplay(mode)
    local value = tostring(mode or "text")
    if value == "icon" or value == "iconText" then
        return value
    end
    return "text"
end

local function HasSpellTokenInSegments(segments)
    if type(segments) ~= "table" then
        return false
    end
    for _, segment in ipairs(segments) do
        if type(segment) == "table" and type(segment.spellTokens) == "table" and #segment.spellTokens > 0 then
            return true
        end
    end
    return false
end

local function BuildIndicatorContext(ind, ctx)
    local out = {}
    for k, v in pairs(ctx or {}) do
        out[k] = v
    end

    local style = ind and ind.style or {}
    local displayMode = NormalizeSpellTokenDisplay(style.spellTokenDisplay)
    local segments = type(ctx) == "table" and ctx.screenMatchedSegments or nil
    local hasSpellToken = HasSpellTokenInSegments(segments)
    if displayMode ~= "text"
        and T.TimelineSyntax
        and T.TimelineSyntax.BuildScreenTextFromSegments
        and type(segments) == "table"
        and #segments > 0 then
        out.text = T.TimelineSyntax.BuildScreenTextFromSegments(segments, displayMode, ctx.text or "")
    else
        out.text = ctx and ctx.text or ""
    end
    out.spellTokenDisplay = displayMode
    out.spellTokenDisplayApplies = hasSpellToken
    return out
end

function ScreenReminder:Show(ctx)
    if type(ctx) ~= "table" then return end
    if not Schema or not Schema.IsEnabled() then return end

    local now = GetTime()
    local actualEvent = tonumber(ctx.actualEvent) or now
    local targets = type(ctx.targetIndicators) == "table" and ctx.targetIndicators or nil
    local indicators = Schema.ListIndicators()
    local matchedRoute = false

    for _, ind in ipairs(indicators) do
        if ind.enabled ~= false and IndicatorPassesRoute(ind, targets) then
            matchedRoute = true
            local leadTime = Schema.ResolveIndicatorLeadTime and Schema.ResolveIndicatorLeadTime(ind, ctx.screenLeadTime) or (tonumber(ind.leadTimeSec) or 0)
            local delay = ctx.forceImmediate == true and 0 or ((actualEvent - leadTime) - now)
            if delay <= 0.05 then
                self:SpawnInstance(ind, BuildIndicatorContext(ind, ctx))
            else
                local indID = ind.id
                C_Timer.After(delay, function()
                    -- 延迟期间可能被禁用/删除/清空
                    if not Schema or not Schema.IsEnabled() then return end
                    local cur = Schema.GetIndicator(indID)
                    if not cur or cur.enabled == false then return end
                    if not IndicatorPassesRoute(cur, targets) then return end
                    self:SpawnInstance(cur, BuildIndicatorContext(cur, ctx))
                end)
            end
        end
    end

    if targets and not matchedRoute and T.debug then
        T.debug(string.format("[STT_SCREEN_TO_MISS] targets=%s available=%s",
            BuildTargetNameList(targets),
            BuildIndicatorNameList(indicators)))
    end
end

function ScreenReminder:SpawnInstance(ind, ctx)
    local module = GetIndicatorModule(ind.kind)
    if not module then
        if T.debug then
            T.debug(string.format("[STT_SCREEN_INDICATOR_FAILED] id=%s kind=%s err=module_missing",
                tostring(ind.id), tostring(ind.kind)))
        end
        return
    end

    -- duration 永远跟随事件实际时间（actualEvent - now），延迟 spawn 后必须重算
    local duration
    local ae = tonumber(ctx.actualEvent)
    if ae then
        duration = math.max(0.1, ae - GetTime())
    else
        duration = math.max(0.1, tonumber(ctx.duration) or 0)
    end

    local anchorFrame = self:EnsureAnchorFrame(ind)
    local instance = module.Acquire(anchorFrame)
    instance:SetData(ind)
    instance.lingerSec = math.max(0, tonumber(ind.lingerSec) or 0)
    instance.lingerFadeEnabled = ind.lingerFadeEnabled ~= false
    -- instance 作为 anchorFrame 的 child；具体定位交给 RepositionGroup
    instance.frame:ClearAllPoints()
    instance.frame:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)

    local activeRecord = { ind = ind, kind = ind.kind, instance = instance, anchorFrame = anchorFrame }
    self.active[#self.active + 1] = activeRecord

    local group = self.groups[ind.id]
    if not group then
        group = { records = {} }
        self.groups[ind.id] = group
    end
    group.records[#group.records + 1] = activeRecord

    instance:SetOnFinish(function()
        self:ReleaseInstance(activeRecord)
    end)
    instance:Start(ctx, duration)
    self:RepositionGroup(ind.id)

    if T.debug then
        local text = T.TimelineSyntax and T.TimelineSyntax.NormalizeASCIIWhitespace and T.TimelineSyntax.NormalizeASCIIWhitespace(ctx and ctx.text or "") or tostring(ctx and ctx.text or "")
        if #text > 48 then
            text = text:sub(1, 48) .. "..."
        end
        T.debug(string.format("[STT_SCREEN_INDICATOR_SPAWN] id=%s name=%s kind=%s dur=%.1f text=%s",
            tostring(ind.id), tostring(ind.name or ""), tostring(ind.kind), duration, text))
    end
end

function ScreenReminder:ReleaseInstance(record)
    if not record then return end
    local module = GetIndicatorModule(record.kind)
    if module then
        module.Release(record.instance)
    end
    for i, r in ipairs(self.active) do
        if r == record then
            table.remove(self.active, i)
            break
        end
    end
    local indID = record.ind and record.ind.id
    if indID then
        local group = self.groups[indID]
        if group and group.records then
            for i, r in ipairs(group.records) do
                if r == record then
                    table.remove(group.records, i)
                    break
                end
            end
            self:RepositionGroup(indID)
        end
    end
end

function ScreenReminder:ClearAll()
    for i = #self.active, 1, -1 do
        local record = self.active[i]
        local module = GetIndicatorModule(record.kind)
        if module then
            module.Release(record.instance)
        end
        self.active[i] = nil
    end
    for k in pairs(self.groups) do
        self.groups[k] = nil
    end
end

-- ──────────────────────────────────────────────────────────────────────
-- 测试
-- ──────────────────────────────────────────────────────────────────────
function ScreenReminder:RunTest()
    self:ClearAll()
    local baseText = L["SR_TEST_TEXT"] or "Test message"
    for i = 1, 3 do
        self:Show({
            text = string.format("%s %d", baseText, i),
            duration = 5,
            spellID = 116014,
            spellIcon = 538040,
            severity = "normal",
            phase = "p1",
        })
    end
end

-- ──────────────────────────────────────────────────────────────────────
-- 锚点锁定 / 解锁
-- ──────────────────────────────────────────────────────────────────────
function ScreenReminder:IsLocked()
    return Schema and Schema.IsLocked()
end

function ScreenReminder:SetLocked(locked)
    if not Schema then return end
    Schema.SetLocked(locked)
    local indicators = Schema.ListIndicators() or {}
    if T.debug then
        T.debug(string.format("[ScreenReminder] SetLocked locked=%s indicators=%d editMode=%s",
            tostring(locked), #indicators, tostring(T.EditMode ~= nil)))
    end
    if locked then
        if T.EditMode and T.EditMode.Exit then
            for _, frame in pairs(self.anchorFrames) do
                T.EditMode:Exit(frame)
            end
        end
    else
        for _, ind in ipairs(indicators) do
            local frame = self:EnsureAnchorFrame(ind)
            if T.EditMode and T.EditMode.Enter then
                T.EditMode:Enter(frame)
            end
        end
    end
end

-- 清理被删除 indicator 的 anchor frame 引用，避免长期 leak
function ScreenReminder:CleanupOrphans()
    local valid = {}
    for _, ind in ipairs(Schema.ListIndicators()) do
        valid[ind.id] = true
    end
    for id, frame in pairs(self.anchorFrames) do
        if not valid[id] then
            frame:Hide()
            frame:SetParent(nil)
            self.anchorFrames[id] = nil
        end
    end
end

function ScreenReminder:NotifyAnchorChanged(indicatorID)
    if self.onAnchorChanged then
        self.onAnchorChanged(indicatorID)
    end
end

function ScreenReminder:SetOnAnchorChanged(callback)
    self.onAnchorChanged = callback
end

function ScreenReminder:SetOnAnchorClicked(callback)
    self.onAnchorClicked = callback
end

end)
