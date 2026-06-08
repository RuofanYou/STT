local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("dreadElegy.enabled", function()

local BUTTON_COUNT = 5
local BUTTON_SIZE = 56
local BUTTON_GAP = 6
local BAR_PANEL_GAP = 10
local FRAME_NAME = "STT_LuraButtonsMVPBar"
local DEFAULT_POS = { point = "TOP", relPoint = "TOP", x = 0, y = -180 }
-- 进军奎尔丹纳斯团本（Midnight Falls）：instanceMapID = 2913
-- 来源：MRT/Data.lua（encounter 3182/3183 -> 2913）、BigWigs_MarchOnQuelDanas/MidnightFalls.lua（NewBoss "Midnight Falls" 2913）
local LURA_INSTANCE_MAP_ID = 2913
local LURA_ENCOUNTER_ID = 3183

local bar
local resizer
local buttons = {}
local activeColumns = BUTTON_COUNT
local pendingApply = false
local regenFrame
local luraEncounterActive = false

-- 直接复用 dread_elegy 维护的 5 个符文账号宏
local MACRO_NAMES = { "◇STT", "△STT", "TSTT", "○STT", "XSTT" }
local RUNE_TEXTURES = {
    "Interface\\AddOns\\ShengTangTools\\media\\rune_rhom.tga",
    "Interface\\AddOns\\ShengTangTools\\media\\rune_tran.tga",
    "Interface\\AddOns\\ShengTangTools\\media\\rune_t.tga",
    "Interface\\AddOns\\ShengTangTools\\media\\rune_circle.tga",
    "Interface\\AddOns\\ShengTangTools\\media\\rune_x.tga",
}

local M = {}
T.LuraButtonsMVP = M

local function Debug(message)
    if T and T.debug then
        T.debug("[LuraButtonsMVP] " .. tostring(message))
    end
end

local function Locale(key)
    return (L and L[key]) or key
end

local function GetDB()
    C.DB = C.DB or {}
    C.DB.dreadElegy = C.DB.dreadElegy or {}
    return C.DB.dreadElegy
end

local function IsModuleEnabled()
    return GetDB().enabled == true  -- 鲁拉符文助手主开关，默认关闭
end

local function IsEnabled()
    -- 子开关默认关闭；已有 SavedVariables 明确开启的角色继续保持开启
    return IsModuleEnabled() and GetDB().lurabuttonsMVP == true
end

local function IsZoneOnly()
    return GetDB().lurabuttonsMVPZoneOnly ~= false  -- 默认 true
end

local function IsEncounterOnly()
    return IsZoneOnly() and GetDB().lurabuttonsMVPEncounterOnly == true
end

local function IsInLuraInstance()
    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    return instanceMapID == LURA_INSTANCE_MAP_ID
end

local function ShouldShow()
    if not IsEnabled() then return false end
    if IsZoneOnly() and not IsInLuraInstance() then return false end
    if IsEncounterOnly() and not luraEncounterActive then return false end
    return true
end

local function ClampColumns(columns)
    columns = tonumber(columns)
    if not columns then return BUTTON_COUNT end
    return math.max(1, math.min(BUTTON_COUNT, math.floor(columns + 0.5)))
end

local function GetColumns()
    return ClampColumns(GetDB().lurabuttonsMVPColumns)
end

local function GetWidthForColumns(columns)
    columns = ClampColumns(columns)
    return columns * BUTTON_SIZE + (columns - 1) * BUTTON_GAP
end

local function GetHeightForColumns(columns)
    columns = ClampColumns(columns)
    local rows = math.ceil(BUTTON_COUNT / columns)
    return rows * BUTTON_SIZE + (rows - 1) * BUTTON_GAP
end

local function GetColumnsForWidth(width)
    width = tonumber(width) or GetWidthForColumns(BUTTON_COUNT)
    return ClampColumns(math.floor((width + BUTTON_GAP) / (BUTTON_SIZE + BUTTON_GAP)))
end

local function GetDefaultPos()
    local width = GetWidthForColumns(BUTTON_COUNT)
    if T.DreadElegy and T.DreadElegy.GetLuraButtonBarDefaultPoint then
        return T.DreadElegy:GetLuraButtonBarDefaultPoint(width, BAR_PANEL_GAP)
    end
    return DEFAULT_POS
end

local function LoadPosition()
    if not bar then return end
    local pos = GetDB().lurabuttonsMVPPos or GetDefaultPos()
    bar:ClearAllPoints()
    bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function ApplyLayout(columnsOverride)
    if not bar then return end
    local columns = ClampColumns(columnsOverride or GetColumns())
    activeColumns = columns
    local width = GetWidthForColumns(columns)
    local height = GetHeightForColumns(columns)
    bar:SetSize(width, height)

    for i = 1, BUTTON_COUNT do
        local btn = buttons[i]
        if btn then
            local index = i - 1
            local col = index % columns
            local row = math.floor(index / columns)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (BUTTON_SIZE + BUTTON_GAP), -row * (BUTTON_SIZE + BUTTON_GAP))
        end
    end
end

local function SetColumns(columns, persist)
    local nextColumns = ClampColumns(columns)
    if persist and GetDB().lurabuttonsMVPColumns ~= nextColumns then
        GetDB().lurabuttonsMVPColumns = nextColumns
    end
    ApplyLayout(nextColumns)
    if persist then
        Debug("列数已保存: " .. nextColumns)
    end
end

local function SetResizerShown(shown)
    if resizer then
        resizer:SetShown(shown == true)
    end
end

local function CreateBar()
    if bar then return end
    if InCombatLockdown and InCombatLockdown() then
        Debug("战斗中跳过 CreateBar")
        return
    end

    bar = CreateFrame("Frame", FRAME_NAME, UIParent)
    bar:SetClampedToScreen(true)
    ApplyLayout()
    LoadPosition()
    bar:Hide()

    for i = 1, BUTTON_COUNT do
        local btn = CreateFrame(
            "Button",
            FRAME_NAME .. "Button" .. i,
            bar,
            "SecureActionButtonTemplate"
        )
        btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(RUNE_TEXTURES[i])

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.18)

        local pushed = btn:CreateTexture(nil, "ARTWORK")
        pushed:SetAllPoints()
        pushed:SetTexture(RUNE_TEXTURES[i])
        pushed:SetVertexColor(0.7, 0.7, 0.7)
        pushed:Hide()
        btn:SetScript("OnMouseDown", function() icon:Hide(); pushed:Show() end)
        btn:SetScript("OnMouseUp",   function() pushed:Hide(); icon:Show() end)

        btn:RegisterForClicks("AnyDown")
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macro", MACRO_NAMES[i])
        buttons[i] = btn
    end

    ApplyLayout()

    resizer = CreateFrame("Button", FRAME_NAME .. "Resizer", bar)
    resizer:SetSize(18, 18)
    resizer:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or M:IsLocked() then return end
        local startX = GetCursorPosition()
        local startWidth = GetWidthForColumns(GetColumns())
        self:SetScript("OnUpdate", function()
            local currentX = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale() or 1
            local width = startWidth + ((currentX - startX) / scale)
            SetColumns(GetColumnsForWidth(width), false)
        end)
    end)
    resizer:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        SetColumns(activeColumns, true)
    end)
    SetResizerShown(false)

    -- 单一权威：拖拽/解锁交给 T.EditMode（仓库统一抽象），不自造 mover
    if T.EditMode and T.EditMode.Register then
        local editEntry = T.EditMode:Register({
            frame = bar,
            displayName = Locale("DREAD_ELEGY_LURA_BUTTONS_DISPLAY_NAME"),
            group = "solo",
            saveFunc = function(point, relPoint, x, y)
                GetDB().lurabuttonsMVPPos = {
                    point = point, relPoint = relPoint, x = x, y = y,
                }
                Debug("位置已保存")
            end,
            onEnter = function()
                SetResizerShown(true)
            end,
            onExit = function()
                SetResizerShown(false)
            end,
        })
        if editEntry and editEntry.overlay then
            resizer:SetFrameStrata(editEntry.overlay:GetFrameStrata())
            resizer:SetFrameLevel(editEntry.overlay:GetFrameLevel() + 1)
        end
    end

    Debug("按钮组创建完成，共 " .. BUTTON_COUNT .. " 个")
end

local function EnsureRegenFrame()
    if regenFrame then
        return
    end
    regenFrame = CreateFrame("Frame")
    regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    regenFrame:SetScript("OnEvent", function()
        if pendingApply then M:ApplyEnabled() end
    end)
end

function M:ApplyEnabled()
    if InCombatLockdown and InCombatLockdown() then
        pendingApply = true
        EnsureRegenFrame()
        Debug("战斗中延后 ApplyEnabled")
        return
    end
    pendingApply = false
    if ShouldShow() then
        if not bar then CreateBar() end
        if bar then bar:Show() end
    else
        if bar then
            if T.EditMode and T.EditMode.Exit then
                T.EditMode:Exit(bar)
            end
            bar:Hide()
        end
    end
end

function M:IsLocked()
    if not bar or not T.EditMode or not T.EditMode.IsEditing then
        return true
    end
    return not T.EditMode:IsEditing(bar)
end

function M:SetLocked(locked)
    if not bar then return end
    if not T.EditMode then return end
    if locked then
        T.EditMode:Exit(bar)
    else
        T.EditMode:Enter(bar)
    end
    if T and T.msg then
        T.msg(string.format(
            Locale("DREAD_ELEGY_LURA_BUTTONS_LOCK_STATE_MSG"),
            locked
                and Locale("DREAD_ELEGY_LURA_BUTTONS_LOCKED")
                or Locale("DREAD_ELEGY_LURA_BUTTONS_UNLOCKED")
        ))
    end
end

function M:ResetPosition()
    local db = GetDB()
    db.lurabuttonsMVPPos = nil
    db.lurabuttonsMVPColumns = nil
    ApplyLayout(BUTTON_COUNT)
    LoadPosition()
    if T and T.msg then
        T.msg(Locale("DREAD_ELEGY_LURA_BUTTONS_RESET_DONE"))
    end
end

function M:CreateOrRebuildRuneMacros()
    if T.DreadElegy and T.DreadElegy.CreateOrRebuildRuneMacros then
        local ok = T.DreadElegy:CreateOrRebuildRuneMacros()
        if ok and T.msg then
            T.msg(Locale("DREAD_ELEGY_LURA_BUTTONS_MACROS_READY"))
        end
        return ok
    end
    if T and T.msg then
        T.msg(Locale("DREAD_ELEGY_LURA_BUTTONS_MACROS_NOT_READY"))
    end
    return false
end

function M:HasAllRuneMacros()
    if T.DreadElegy and T.DreadElegy.HasAllRuneMacros then
        return T.DreadElegy:HasAllRuneMacros()
    end
    return false
end

local function Init()
    M:ApplyEnabled()

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("ENCOUNTER_START")
    f:RegisterEvent("ENCOUNTER_END")
    f:SetScript("OnEvent", function(_, event, encounterID)
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingApply then M:ApplyEnabled() end
        elseif event == "ENCOUNTER_START" then
            luraEncounterActive = tonumber(encounterID) == LURA_ENCOUNTER_ID
            M:ApplyEnabled()
        elseif event == "ENCOUNTER_END" then
            if tonumber(encounterID) == LURA_ENCOUNTER_ID then
                luraEncounterActive = false
            end
            M:ApplyEnabled()
        else
            -- 区域变化：重新评估显隐
            if event == "PLAYER_ENTERING_WORLD" then
                luraEncounterActive = false
            end
            M:ApplyEnabled()
        end
    end)
end

if T and T.RegisterInitCallback then
    T.RegisterInitCallback(Init)
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Init()
    end)
end

end)
