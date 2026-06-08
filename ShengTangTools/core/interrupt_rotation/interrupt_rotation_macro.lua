local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("interruptRotation.enabled", function()

local M = {}
T.InterruptRotationMacro = M

local MACRO_NAME = "STT鲁拉打断"
local DEFAULT_GROUP = 1
local DEFAULT_KICK = 1
local MIN_BOSS_ID = 2
local MAX_BOSS_ID = 4
local MAX_ACCOUNT_MACRO_FALLBACK = 120
local MACRO_DRAG_TEMP_STRATA = "LOW"

local CLASS_INTERRUPT_SPELLS = {
    DEATHKNIGHT = { default = { 47528 } },
    DEMONHUNTER = { default = { 183752 } },
    DRUID = { default = { 106839, 78675 } },
    EVOKER = { default = { 351338 } },
    HUNTER = {
        default = { 147362, 187707 },
        specs = {
            [255] = { 187707, 147362 },
        },
    },
    MAGE = { default = { 2139 } },
    MONK = { default = { 116705 } },
    PALADIN = { default = { 96231 } },
    PRIEST = { default = { 15487 } },
    ROGUE = { default = { 1766 } },
    SHAMAN = { default = { 57994 } },
    WARLOCK = {
        default = { 19647 },
        specs = {
            [266] = { 119914, 19647 },
        },
    },
    WARRIOR = { default = { 6552 } },
}

local pendingRefresh = false
local macroDragRestoreStrata = nil
local frame

local function Debug(fmt, ...)
    if C and C.DB and C.DB.debugMode == true and T.debug then
        T.debug(string.format("[IRMacro] " .. fmt, ...))
    end
end

local function GetDB()
    C.DB.interruptRotation = C.DB.interruptRotation or {}
    return C.DB.interruptRotation
end

local function WriteDBValue(key, value)
    local db = GetDB()
    db[key] = value
    if type(STT_DB) == "table" then
        STT_DB.interruptRotation = STT_DB.interruptRotation or {}
        STT_DB.interruptRotation[key] = value
    end
end

local function ClampInt(value, minValue, maxValue, defaultValue)
    value = tonumber(value) or defaultValue
    value = math.floor(value)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function GetSelectedGroup()
    return ClampInt(GetDB().midnightMacroGroup, 1, 3, DEFAULT_GROUP)
end

local function GetSelectedKick()
    return ClampInt(GetDB().midnightMacroKick, 1, 4, DEFAULT_KICK)
end

local function NotifyOptionsRefresh()
    if T.OptionEngine and T.OptionEngine.RefreshWidgetValues then
        T.OptionEngine:RefreshWidgetValues()
    end
end

local function GetSpellInfoSafe(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            return info.name, info.iconID
        end
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
end

local function GetSpellIconSafe(spellID, fallbackIcon)
    if C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(spellID)
        if icon then
            return icon
        end
    end
    return fallbackIcon or 136243
end

local function IsKnownSpell(spellID)
    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end
    if IsSpellKnown and IsSpellKnown(spellID) then
        return true
    end
    return false
end

local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization() or nil
    if not specIndex then
        return nil
    end

    if GetSpecializationInfo then
        local ok, specID = pcall(GetSpecializationInfo, specIndex)
        if ok and specID then
            return tonumber(specID)
        end
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local ok, id = pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex, false)
        if ok then
            if type(id) == "table" then
                return tonumber(id.specID or id.id)
            end
            return tonumber(id)
        end
    end
end

local function GetInterruptCandidates(classFile, specID)
    local entry = classFile and CLASS_INTERRUPT_SPELLS[classFile]
    if type(entry) ~= "table" then
        return nil
    end
    if specID and type(entry.specs) == "table" and type(entry.specs[specID]) == "table" then
        return entry.specs[specID]
    end
    return entry.default
end

local function ResolveInterruptSpell()
    local _, classFile = UnitClass("player")
    local candidates = GetInterruptCandidates(classFile, GetPlayerSpecID())
    if type(candidates) ~= "table" or #candidates == 0 then
        return nil, nil, nil
    end

    for _, spellID in ipairs(candidates) do
        if IsKnownSpell(spellID) then
            local name, icon = GetSpellInfoSafe(spellID)
            if name and name ~= "" then
                return spellID, name, GetSpellIconSafe(spellID, icon)
            end
        end
    end

    local fallbackID = candidates[1]
    local name, icon = GetSpellInfoSafe(fallbackID)
    if name and name ~= "" then
        return fallbackID, name, GetSpellIconSafe(fallbackID, icon)
    end
end

local function BuildConditionText(group, kick)
    local bossID = group + 1
    if kick ~= 4 then
        return string.format("[@boss%d,harm,nodead]", bossID)
    end

    local parts = {}
    for id = bossID, MIN_BOSS_ID, -1 do
        parts[#parts + 1] = string.format("[@boss%d,harm,nodead]", id)
    end
    return table.concat(parts, "")
end

local function BuildMacroBody(spellName, group, kick)
    return string.format(
        "#showtooltip %s\n/cast %s %s",
        spellName,
        BuildConditionText(group, kick),
        spellName
    )
end

local function FindMacro()
    if not GetMacroInfo then
        return nil
    end
    local accountCount = GetNumMacros()
    for index = 1, tonumber(accountCount) or 0 do
        local name = GetMacroInfo(index)
        if name == MACRO_NAME then
            return index
        end
    end
end

local function IsAccountMacroFull()
    local accountCount = GetNumMacros()
    local maxAccount = MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACRO_FALLBACK
    return (tonumber(accountCount) or 0) >= maxAccount
end

local function RestoreMacroDragGui(reason)
    local gui = T.GUI
    if gui and macroDragRestoreStrata then
        gui:SetFrameStrata(macroDragRestoreStrata)
    end
    macroDragRestoreStrata = nil
end

local function BeginMacroDragGui()
    local gui = T.GUI
    if not gui or not gui:IsShown() or macroDragRestoreStrata then
        return false
    end

    macroDragRestoreStrata = gui:GetFrameStrata()
    gui:SetFrameStrata(MACRO_DRAG_TEMP_STRATA)
    return true
end

local function ShowMacroWarning(msg)
    if not msg or msg == "" then
        return
    end
    T.msg(msg)

    local plain = tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if T.TacticalNotice and T.TacticalNotice.ShowBanner then
        local shown = T.TacticalNotice:ShowBanner({
            text = plain,
            duration = 3.5,
            severity = "warning",
            bypassCooldown = true,
        })
        if shown then
            return
        end
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(plain, 1, 0.82, 0)
    end
end

local function UpdateMacro(createMissing)
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        Debug("refresh deferred reason=combat")
        return nil, false
    end

    local spellID, spellName, icon = ResolveInterruptSpell()
    if not spellName then
        T.msg(L["OPT_IR_MACRO_NO_SPELL"] or "当前职业未识别到可用打断技能，无法生成鲁拉打断宏。")
        Debug("refresh skipped reason=no_spell")
        return nil, false
    end

    local group = GetSelectedGroup()
    local kick = GetSelectedKick()
    local body = BuildMacroBody(spellName, group, kick)
    local macroID = FindMacro()

    if macroID then
        local currentName, currentIcon = GetMacroInfo(macroID)
        local currentBody = GetMacroBody(macroID) or ""
        if currentName ~= MACRO_NAME or currentIcon ~= icon or currentBody ~= body then
            EditMacro(macroID, MACRO_NAME, icon, body)
            Debug("updated macroID=%s group=%s kick=%s spell=%s", tostring(macroID), tostring(group), tostring(kick), tostring(spellID))
            return macroID, true
        end
        return macroID, false
    end

    if not createMissing then
        return nil, false
    end
    if IsAccountMacroFull() then
        ShowMacroWarning(L["OPT_IR_MACRO_SLOTS_FULL"] or "通用宏槽位已满，无法创建鲁拉打断宏。")
        Debug("create blocked reason=account_slots_full")
        return nil, false
    end

    macroID = CreateMacro(MACRO_NAME, icon, body, false)
    if macroID then
        Debug("created macroID=%s group=%s kick=%s spell=%s", tostring(macroID), tostring(group), tostring(kick), tostring(spellID))
        return macroID, true
    end

    T.msg(L["OPT_IR_MACRO_CREATE_FAILED"] or "创建鲁拉打断宏失败。")
    Debug("create failed reason=create_macro_nil")
    return nil, false
end

function M:GetSelection()
    return GetSelectedGroup(), GetSelectedKick()
end

function M:GetSpellMeta()
    local spellID, spellName, icon = ResolveInterruptSpell()
    return spellID, spellName, icon
end

function M:GetMacroPreview()
    local _, spellName = ResolveInterruptSpell()
    if not spellName then
        return L["OPT_IR_MACRO_NO_SPELL"] or "当前职业未识别到可用打断技能。"
    end
    return BuildMacroBody(spellName, GetSelectedGroup(), GetSelectedKick())
end

function M:SetManualSelection(group, kick)
    local normalizedGroup = ClampInt(group, 1, 3, DEFAULT_GROUP)
    local normalizedKick = ClampInt(kick, 1, 4, DEFAULT_KICK)
    WriteDBValue("midnightMacroGroup", normalizedGroup)
    WriteDBValue("midnightMacroKick", normalizedKick)
    UpdateMacro(false)
    NotifyOptionsRefresh()
    Debug("manual group=%s kick=%s", tostring(normalizedGroup), tostring(normalizedKick))
end

function M:ApplyAssignment(interrupts)
    local trackedID = tonumber(interrupts and interrupts.myTrackedID) or 0
    local kick = tonumber(interrupts and interrupts.myKick) or 0
    if trackedID < MIN_BOSS_ID or trackedID > MAX_BOSS_ID or kick < 1 or kick > 4 then
        return false
    end

    local group = trackedID - 1
    local changed = GetSelectedGroup() ~= group or GetSelectedKick() ~= kick
    WriteDBValue("midnightMacroGroup", group)
    WriteDBValue("midnightMacroKick", kick)
    UpdateMacro(false)
    if changed then
        NotifyOptionsRefresh()
        Debug("assignment group=%s kick=%s", tostring(group), tostring(kick))
    end
    return true
end

function M:RefreshExistingMacro()
    return UpdateMacro(false)
end

function M:PickupMacro()
    if InCombatLockdown and InCombatLockdown() then
        T.msg(L["OPT_IR_MACRO_COMBAT"] or "战斗中无法更新或拖拽鲁拉打断宏。")
        Debug("pickup blocked reason=combat")
        return false
    end

    local macroID = UpdateMacro(true)
    if not macroID then
        return false
    end

    PickupMacro(macroID)
    local cursorType = GetCursorInfo and GetCursorInfo()
    if not cursorType then
        T.msg(L["OPT_IR_MACRO_PICKUP_FAILED"] or "拖拽鲁拉打断宏失败。")
        RestoreMacroDragGui("pickup_empty")
        Debug("pickup failed macroID=%s reason=empty_cursor", tostring(macroID))
        return false
    end

    if BeginMacroDragGui() then
        frame:RegisterEvent("CURSOR_CHANGED")
    end
    Debug("picked macroID=%s cursorType=%s", tostring(macroID), tostring(cursorType))
    return true
end

local function OnMacroEvent(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            M:RefreshExistingMacro()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" and pendingRefresh then
        pendingRefresh = false
        M:RefreshExistingMacro()
    elseif event == "CURSOR_CHANGED" and macroDragRestoreStrata and not GetCursorInfo() then
        frame:UnregisterEvent("CURSOR_CHANGED")
        RestoreMacroDragGui("cursor_clear")
    end
end

function M:SetAutoRefreshEnabled(enabled)
    if not enabled then
        if frame then
            frame:UnregisterEvent("PLAYER_LOGIN")
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnMacroEvent)
    end
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

end)
