-- 个人光环提醒
-- 基于 ENCOUNTER_WARNING 的个人警告规则；不读取 private aura 或隐藏光环 ID。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("personalAuraAlert.enabled", function()

local DB_KEY = "personalAuraAlert"
local DEFAULT_INDICATOR_NAME = "环形#1"
local DEFAULT_RULE_ID = "starsplinter_default"
local DEFAULT_ENCOUNTER_ID = 3183
local DEFAULT_SEVERITY = 1
local DEFAULT_DURATION = 2.9
local DEFAULT_TEXT = "星辰裂片"
local UNKNOWN_WARNING_TEXT = "未知个人警告"
local MAX_OBSERVED_WARNINGS = 80
local PRESET_ID_PREFIX = "preset:"

local M = T.ModuleLoader:NewModule({
    name = "PersonalAuraAlert",
    dbKey = DB_KEY .. ".enabled",
    defaultEnabled = false,
})
T.PersonalAuraAlert = M

local currentEncounterID = nil
local currentDifficultyID = nil
local encounterStartTime = nil
local inEncounter = false
local countdownTimers = {}
local NormalizeRule

local function Debug(fmt, ...)
    if not (T.debug and C and C.DB and C.DB.debugMode == true) then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[PersonalAuraAlert] " .. tostring(fmt), ...))
    else
        T.debug("[PersonalAuraAlert] " .. tostring(fmt))
    end
end

local function GetDB()
    if type(C.DB) ~= "table" then
        return nil
    end
    if type(C.DB[DB_KEY]) ~= "table" then
        C.DB[DB_KEY] = {}
    end
    return C.DB[DB_KEY]
end

local function IsSecretValue(value)
    local resolver = T.EncounterEventResolver
    if resolver and resolver.IsSecretValue then
        return resolver.IsSecretValue(value) == true
    end
    if value == nil then
        return false
    end
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        if ok and result == true then
            return true
        end
    end
    if type(issecrettable) == "function" then
        local ok, result = pcall(issecrettable, value)
        if ok and result == true then
            return true
        end
    end
    return false
end

local function SafeNumber(value)
    if value == nil or IsSecretValue(value) then
        return nil
    end
    local normalized = tonumber(value)
    if type(normalized) ~= "number" or IsSecretValue(normalized) then
        return nil
    end
    return normalized
end

local function SafeText(value)
    if value == nil or IsSecretValue(value) or type(value) ~= "string" then
        return nil
    end
    if value == "" then
        return nil
    end
    return value
end

local function SpellNameFromID(spellID)
    local id = SafeNumber(spellID)
    if not id then
        return nil
    end
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        local name = info and info.name
        if type(name) == "string" and name ~= "" then
            return name
        end
    elseif GetSpellInfo then
        local name = GetSpellInfo(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

local function CopyDifficultyIDs(ids)
    local out = {}
    if type(ids) == "table" then
        for _, value in ipairs(ids) do
            local id = tonumber(value)
            if id and id > 0 then
                out[#out + 1] = id
            end
        end
    end
    table.sort(out)
    return out
end

local function CopyTimeWindows(windows)
    local out = {}
    if type(windows) == "table" then
        for _, window in ipairs(windows) do
            local startSec = tonumber(window and window.startSec)
            local endSec = tonumber(window and window.endSec)
            if startSec and endSec and startSec >= 0 and endSec >= startSec then
                out[#out + 1] = {
                    startSec = startSec,
                    endSec = endSec,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.startSec == b.startSec then
            return a.endSec < b.endSec
        end
        return a.startSec < b.startSec
    end)
    return out
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(item, seen)
    end
    return out
end

local function LocalizedText(key, fallback)
    if type(key) == "string" and key ~= "" and L and L[key] and L[key] ~= key then
        return L[key]
    end
    return fallback or key or ""
end

local function GetPresetBosses()
    return T.Data and T.Data.PersonalAuraPresetBosses or {}
end

local function GetPresetBossOrder()
    return T.Data and T.Data.PersonalAuraPresetBossOrder or {}
end

local function GetPresetByKey(presetKey)
    local target = tostring(presetKey or "")
    if target == "" then
        return nil, nil
    end
    for encounterID, boss in pairs(GetPresetBosses()) do
        for _, preset in ipairs(boss.presets or {}) do
            if preset.key == target then
                return preset, tonumber(encounterID), boss
            end
        end
    end
    return nil, nil, nil
end

local function EnsurePresetState(db)
    if type(db.presetState) ~= "table" then
        db.presetState = {}
    end
    return db.presetState
end

local function CopyPresetState(state)
    if type(state) ~= "table" then
        return {}
    end
    local out = {}
    if state.enabled ~= nil then
        out.enabled = state.enabled == true
    end
    if state.difficultyIDs ~= nil then
        out.difficultyIDs = CopyDifficultyIDs(state.difficultyIDs)
    end
    if state.severity ~= nil then
        local severity = tonumber(state.severity)
        if severity then
            out.severity = severity
        end
    end
    if state.text ~= nil then
        local text = tostring(state.text or "")
        if text ~= "" then
            out.text = text
        end
    end
    if state.durationSec ~= nil then
        local duration = tonumber(state.durationSec)
        if duration and duration > 0 then
            out.durationSec = duration
        end
    end
    if state.indicatorName ~= nil then
        local indicatorName = tostring(state.indicatorName or "")
        out.indicatorName = indicatorName ~= "" and indicatorName or DEFAULT_INDICATOR_NAME
    end
    if state.timeWindows ~= nil then
        out.timeWindows = CopyTimeWindows(state.timeWindows)
    end
    if state.countdownAudioEnabled ~= nil then
        out.countdownAudioEnabled = state.countdownAudioEnabled == true
    end
    if state.requireShouldPlaySound ~= nil then
        out.requireShouldPlaySound = state.requireShouldPlaySound == true
    end
    return out
end

local function ResolvePresetEnabled(preset, state)
    if type(state) == "table" and state.enabled ~= nil then
        return state.enabled == true
    end
    return preset and preset.enabledDefault == true
end

local function SameNumberList(left, right)
    local a = CopyDifficultyIDs(left)
    local b = CopyDifficultyIDs(right)
    if #a ~= #b then
        return false
    end
    for index, value in ipairs(a) do
        if value ~= b[index] then
            return false
        end
    end
    return true
end

local function SameTimeWindows(left, right)
    local a = CopyTimeWindows(left)
    local b = CopyTimeWindows(right)
    if #a ~= #b then
        return false
    end
    for index, value in ipairs(a) do
        local other = b[index]
        if not other or value.startSec ~= other.startSec or value.endSec ~= other.endSec then
            return false
        end
    end
    return true
end

local function PrunePresetState(preset, state)
    local out = CopyPresetState(state)
    if type(preset) ~= "table" then
        return out
    end
    if out.enabled ~= nil and out.enabled == (preset.enabledDefault == true) then
        out.enabled = nil
    end
    if out.difficultyIDs ~= nil and SameNumberList(out.difficultyIDs, preset.difficultyIDs) then
        out.difficultyIDs = nil
    end
    if out.severity ~= nil and out.severity == (tonumber(preset.severity) or DEFAULT_SEVERITY) then
        out.severity = nil
    end
    if out.text ~= nil then
        local defaultText = LocalizedText(preset.nameKey, preset.fallbackName or DEFAULT_TEXT)
        if out.text == defaultText or out.text == preset.fallbackName then
            out.text = nil
        end
    end
    if out.durationSec ~= nil and math.abs(out.durationSec - (tonumber(preset.durationSec) or DEFAULT_DURATION)) < 0.0001 then
        out.durationSec = nil
    end
    if out.indicatorName == DEFAULT_INDICATOR_NAME then
        out.indicatorName = nil
    end
    if out.timeWindows ~= nil and SameTimeWindows(out.timeWindows, preset.timeWindows) then
        out.timeWindows = nil
    end
    if out.countdownAudioEnabled == false then
        out.countdownAudioEnabled = nil
    end
    if out.requireShouldPlaySound == false then
        out.requireShouldPlaySound = nil
    end
    return out
end

local function PruneAllPresetStates(db)
    local presetState = EnsurePresetState(db)
    for key, value in pairs(presetState) do
        local preset = GetPresetByKey(key)
        local pruned = PrunePresetState(preset, value)
        if next(pruned) then
            presetState[key] = pruned
        else
            presetState[key] = nil
        end
    end
    return presetState
end

local function DifficultyIDsToText(ids)
    local normalized = CopyDifficultyIDs(ids)
    if #normalized == 0 then
        return "all"
    end
    local parts = {}
    for _, id in ipairs(normalized) do
        parts[#parts + 1] = tostring(id)
    end
    return table.concat(parts, "/")
end

local function FormatSeconds(seconds)
    local value = math.max(0, tonumber(seconds) or 0)
    local precision = math.abs(value - math.floor(value + 0.5)) < 0.0001 and 0 or 1
    if precision == 0 then
        value = math.floor(value + 0.5)
        local minutes = math.floor(value / 60)
        local sec = value - minutes * 60
        return string.format("%d:%02d", minutes, sec)
    end
    local rounded = math.floor(value * 10 + 0.5) / 10
    local minutes = math.floor(rounded / 60)
    local sec = rounded - minutes * 60
    return string.format("%d:%04.1f", minutes, sec)
end

local function TimeWindowsToText(windows)
    local normalized = CopyTimeWindows(windows)
    if #normalized == 0 then
        return ""
    end
    local parts = {}
    for _, window in ipairs(normalized) do
        parts[#parts + 1] = FormatSeconds(window.startSec) .. "-" .. FormatSeconds(window.endSec)
    end
    return table.concat(parts, ", ")
end

local function TimeWindowsToDebugText(windows)
    local text = TimeWindowsToText(windows)
    return text ~= "" and text or "all"
end

local function ParseTimeWindows(text)
    local raw = tostring(text or "")
    raw = raw:gsub("，", ","):gsub("；", ","):gsub("：", ":"):gsub("%s+", "")
    if raw == "" then
        return {}
    end
    local parser = T.TimelineSyntax and T.TimelineSyntax.ParseTimeToSeconds
    if not parser then
        return nil, "parser_missing"
    end
    local windows = {}
    for segment in raw:gmatch("[^,]+") do
        local startText, endText = segment:match("^([^-]+)%-(.+)$")
        if not startText or not endText or startText == "" or endText == "" then
            return nil, "format"
        end
        local startSec = parser(startText)
        local endSec = parser(endText)
        if not startSec or not endSec then
            return nil, "format"
        end
        if endSec < startSec then
            return nil, "range"
        end
        windows[#windows + 1] = {
            startSec = startSec,
            endSec = endSec,
        }
    end
    return CopyTimeWindows(windows)
end

local function CancelCountdownAudio()
    for _, timer in ipairs(countdownTimers) do
        if timer and timer.Cancel then
            timer:Cancel()
        end
    end
    wipe(countdownTimers)
end

local function ScheduleCountdownAudio(duration)
    CancelCountdownAudio()
    if not T.PlayCountdownMp3 then
        return 0
    end
    local countdownValue = math.ceil((tonumber(duration) or 0) - 0.0001)
    if countdownValue < 1 then
        return 0
    elseif countdownValue > 10 then
        countdownValue = 10
    end

    local scheduled = 0
    for offset = 0, countdownValue - 1 do
        local number = countdownValue - offset
        local timer = C_Timer.NewTimer(offset, function()
            T.PlayCountdownMp3(number)
        end)
        countdownTimers[#countdownTimers + 1] = timer
        scheduled = scheduled + 1
    end
    return scheduled
end

local function NewDefaultRule(indicatorName)
    return {
        id = DEFAULT_RULE_ID,
        enabled = true,
        encounterID = DEFAULT_ENCOUNTER_ID,
        difficultyIDs = {},
        severity = DEFAULT_SEVERITY,
        text = DEFAULT_TEXT,
        durationSec = DEFAULT_DURATION,
        indicatorName = indicatorName ~= "" and indicatorName or DEFAULT_INDICATOR_NAME,
        timeWindows = {},
        countdownAudioEnabled = false,
        requireShouldPlaySound = false,
    }
end

NormalizeRule = function(rule, index)
    local normalized = type(rule) == "table" and rule or {}
    local id = tostring(normalized.id or "")
    if id == "" then
        id = "rule_" .. tostring(index or 1)
    end
    local text = tostring(normalized.text or "")
    if text == "" then
        text = DEFAULT_TEXT
    end
    local indicatorName = tostring(normalized.indicatorName or "")
    if indicatorName == "" then
        indicatorName = DEFAULT_INDICATOR_NAME
    end
    local duration = tonumber(normalized.durationSec)
    if not duration or duration <= 0 then
        duration = DEFAULT_DURATION
    end
    return {
        id = id,
        enabled = normalized.enabled ~= false,
        encounterID = tonumber(normalized.encounterID) or DEFAULT_ENCOUNTER_ID,
        difficultyIDs = CopyDifficultyIDs(normalized.difficultyIDs),
        severity = tonumber(normalized.severity) or DEFAULT_SEVERITY,
        text = text,
        durationSec = duration,
        indicatorName = indicatorName,
        timeWindows = CopyTimeWindows(normalized.timeWindows),
        countdownAudioEnabled = normalized.countdownAudioEnabled == true,
        requireShouldPlaySound = normalized.requireShouldPlaySound == true,
    }
end

local function BuildPresetRule(preset, encounterID, state)
    if type(preset) ~= "table" then
        return nil
    end
    state = CopyPresetState(state)
    local base = {
        id = PRESET_ID_PREFIX .. tostring(preset.key or ""),
        enabled = ResolvePresetEnabled(preset, state),
        encounterID = tonumber(encounterID) or DEFAULT_ENCOUNTER_ID,
        difficultyIDs = CopyDifficultyIDs(preset.difficultyIDs),
        severity = tonumber(preset.severity) or DEFAULT_SEVERITY,
        text = LocalizedText(preset.nameKey, preset.fallbackName or DEFAULT_TEXT),
        durationSec = tonumber(preset.durationSec) or DEFAULT_DURATION,
        indicatorName = DEFAULT_INDICATOR_NAME,
        timeWindows = CopyTimeWindows(preset.timeWindows),
        countdownAudioEnabled = false,
        requireShouldPlaySound = false,
    }

    for key, value in pairs(state) do
        if key ~= "id" and key ~= "presetKey" and key ~= "encounterID" then
            base[key] = DeepCopy(value)
        end
    end

    local rule = NormalizeRule(base)
    rule.id = PRESET_ID_PREFIX .. tostring(preset.key or "")
    rule.presetKey = tostring(preset.key or "")
    rule.source = "preset"
    rule.isPreset = true
    rule.canDelete = false
    rule.calibrated = preset.calibrated == true
    return rule
end

local function RuleImportKey(rule)
    local normalized = NormalizeRule(rule)
    return table.concat({
        tostring(normalized.encounterID),
        DifficultyIDsToText(normalized.difficultyIDs),
        tostring(normalized.severity),
        tostring(normalized.text),
        TimeWindowsToDebugText(normalized.timeWindows),
    }, "|")
end

local function AppendImportedRule(db, source, stats)
    local nextID = tonumber(db.nextRuleID) or (#db.rules + 1)
    db.nextRuleID = nextID + 1
    local rule = NormalizeRule(source, nextID)
    rule.id = "rule_" .. tostring(nextID)
    db.rules[#db.rules + 1] = rule
    stats.added = stats.added + 1
    stats.touchedIDs[#stats.touchedIDs + 1] = rule.id
    stats.details[#stats.details + 1] = {
        action = "add",
        sourceKey = RuleImportKey(source),
        localID = rule.id,
        text = rule.text,
    }
    return rule
end

local function RuleDebugText(rule)
    local normalized = NormalizeRule(rule)
    return string.format("rule=%s enabled=%s encounter=%s difficulties=%s severity=%s windows=%s duration=%.1f countdownAudio=%s requireShouldPlaySound=%s indicator=%s text=%s",
        tostring(normalized.id),
        tostring(normalized.enabled),
        tostring(normalized.encounterID),
        DifficultyIDsToText(normalized.difficultyIDs),
        tostring(normalized.severity),
        TimeWindowsToDebugText(normalized.timeWindows),
        normalized.durationSec,
        tostring(normalized.countdownAudioEnabled),
        tostring(normalized.requireShouldPlaySound),
        tostring(normalized.indicatorName),
        tostring(normalized.text))
end

local function DifficultyMatches(rule)
    local ids = rule and rule.difficultyIDs
    if type(ids) ~= "table" or #ids == 0 then
        return true
    end
    local current = tonumber(currentDifficultyID) or 0
    for _, id in ipairs(ids) do
        if tonumber(id) == current then
            return true
        end
    end
    return false
end

local function TimeWindowMatches(rule, elapsedSec)
    local windows = rule and rule.timeWindows
    if type(windows) ~= "table" or #windows == 0 then
        return true
    end
    local elapsed = tonumber(elapsedSec)
    if not elapsed then
        return false
    end
    for _, window in ipairs(windows) do
        local startSec = tonumber(window.startSec)
        local endSec = tonumber(window.endSec)
        if startSec and endSec and elapsed >= startSec and elapsed <= endSec then
            return true
        end
    end
    return false
end

local function RuleMissReason(rule, severity, elapsedSec, shouldPlaySound)
    if rule.enabled == false then
        return "rule_disabled"
    end
    if tonumber(rule.encounterID) ~= tonumber(currentEncounterID) then
        return "encounter"
    end
    if tonumber(rule.severity) ~= tonumber(severity) then
        return "severity"
    end
    if rule.requireShouldPlaySound == true and shouldPlaySound ~= true then
        return "should_play_sound"
    end
    if not DifficultyMatches(rule) then
        return "difficulty"
    end
    if not TimeWindowMatches(rule, elapsedSec) then
        return "time_window"
    end
    return nil
end

local function BuildObservedKey(item)
    return table.concat({
        tostring(item.encounterID or ""),
        tostring(item.difficultyID or ""),
        tostring(item.severity or ""),
        tostring(item.tooltipSpellID or ""),
        tostring(item.text or ""),
        tostring(item.name or ""),
    }, "|")
end

local function EnsureObservedSession(encounterID, difficultyID, reset)
    local db = GetDB()
    if not db then
        return nil
    end
    if reset or type(db.observedWarnings) ~= "table" or type(db.observedWarnings.items) ~= "table" then
        db.observedWarnings = {
            encounterID = tonumber(encounterID),
            difficultyID = tonumber(difficultyID),
            startedAt = GetTime(),
            endedAt = nil,
            items = {},
        }
    end
    return db.observedWarnings
end

local function FindObservedItem(session, key)
    if type(session) ~= "table" or type(session.items) ~= "table" then
        return nil
    end
    for _, item in ipairs(session.items) do
        if item.key == key then
            return item
        end
    end
    return nil
end

function M:EnsureRules()
    local db = GetDB()
    if not db then
        return {}
    end
    local presetState = EnsurePresetState(db)

    if type(db.rules) ~= "table" then
        local oldIndicator = tostring(db.indicatorName or "")
        local preset = GetPresetByKey("lura_starsplinter")
        presetState.lura_starsplinter = presetState.lura_starsplinter or PrunePresetState(preset, NewDefaultRule(oldIndicator))
        db.rules = {}
        db.nextRuleID = 2
        Debug("migrate_default_rule_to_preset oldIndicator=%s", tostring(oldIndicator))
    end
    db.indicatorName = nil

    local nextIndex = 1
    for _, rule in ipairs(db.rules) do
        local normalized = NormalizeRule(rule, nextIndex)
        if normalized.id == DEFAULT_RULE_ID then
            local preset = GetPresetByKey("lura_starsplinter")
            presetState.lura_starsplinter = presetState.lura_starsplinter or PrunePresetState(preset, normalized)
            Debug("remove_legacy_default_rule %s", RuleDebugText(normalized))
        else
            db.rules[nextIndex] = normalized
            nextIndex = nextIndex + 1
        end
    end
    for index = #db.rules, nextIndex, -1 do
        db.rules[index] = nil
    end
    PruneAllPresetStates(db)
    db.nextRuleID = math.max(tonumber(db.nextRuleID) or (#db.rules + 1), #db.rules + 1)
    return db.rules
end

function M:GetRules()
    return self:EnsureRules()
end

function M:GetRuleByID(ruleID)
    local target = tostring(ruleID or "")
    if target == "" then
        return nil
    end
    local presetKey = target:match("^" .. PRESET_ID_PREFIX .. "(.+)$")
    if presetKey then
        return self:GetPresetRule(presetKey)
    end
    for _, rule in ipairs(self:GetRules()) do
        if rule.id == target then
            return rule
        end
    end
    return nil
end

function M:GetPresetRule(presetKey)
    local preset, encounterID = GetPresetByKey(presetKey)
    if not preset then
        return nil
    end
    local db = GetDB()
    local state = db and EnsurePresetState(db)[preset.key] or nil
    return BuildPresetRule(preset, encounterID, state)
end

function M:GetPresetRules()
    local db = GetDB()
    local presetState = db and EnsurePresetState(db) or {}
    local out = {}
    for _, encounterID in ipairs(GetPresetBossOrder()) do
        local boss = GetPresetBosses()[encounterID]
        for _, preset in ipairs(boss and boss.presets or {}) do
            out[#out + 1] = BuildPresetRule(preset, encounterID, presetState[preset.key])
        end
    end
    return out
end

function M:GetRuntimeRules()
    local out = {}
    for _, rule in ipairs(self:GetPresetRules()) do
        out[#out + 1] = rule
    end
    for _, rule in ipairs(self:GetRules()) do
        out[#out + 1] = rule
    end
    return out
end

local function EnsureEncounterJournalLoaded()
    local loaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        loaded = C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
    elseif IsAddOnLoaded then
        loaded = IsAddOnLoaded("Blizzard_EncounterJournal")
    end
    if not loaded then
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
        elseif LoadAddOn then
            pcall(LoadAddOn, "Blizzard_EncounterJournal")
        end
    end
    if type(_G.EncounterJournal_LoadUI) == "function" then
        pcall(_G.EncounterJournal_LoadUI)
    end
end

local function ResolveClientEncounterName(encounterID)
    local id = tonumber(encounterID)
    if not id then
        return nil
    end
    EnsureEncounterJournalLoaded()
    if EJ_GetEncounterInfo then
        local ok, name = pcall(EJ_GetEncounterInfo, id)
        if ok and type(name) == "string" and name ~= "" and name ~= tostring(id) then
            return name
        end
    end
    local sem = T.SemanticTimeline
    if sem and sem.EnsureTemplateReady and sem.GetEncounterName then
        pcall(sem.EnsureTemplateReady, sem)
        local ok, name = pcall(sem.GetEncounterName, sem, id)
        if ok and type(name) == "string" and name ~= "" and name ~= tostring(id) then
            return name
        end
    end
    if sem and sem.ResolveEncounterName then
        local ok, name = pcall(sem.ResolveEncounterName, sem, id)
        if ok and type(name) == "string" and name ~= "" and name ~= tostring(id) then
            return name
        end
    end
    return nil
end

local function ResolveBossDisplayName(encounterID, customName)
    local id = tonumber(encounterID)
    if type(customName) == "string" and customName ~= "" and customName ~= tostring(id or "") then
        return customName
    end
    local presetBoss = GetPresetBosses()[id]
    if presetBoss then
        return LocalizedText(presetBoss.nameKey, presetBoss.fallbackName)
    end
    local clientName = ResolveClientEncounterName(id)
    if clientName then
        return clientName
    end
    local bossData = T.Data and T.Data.BossSpells and T.Data.BossSpells[id]
    if bossData then
        local locale = GetLocale and GetLocale() or ""
        if locale == "zhTW" then
            return bossData.nameZhTW or bossData.nameZh or bossData.name or tostring(id)
        elseif locale == "zhCN" then
            return bossData.nameZh or bossData.name or tostring(id)
        end
        return bossData.name or bossData.nameZh or tostring(id)
    end
    return tostring(id or encounterID)
end

function M:ListRulesForBoss(encounterID)
    local target = tonumber(encounterID)
    local rows = {}
    if not target then
        return rows
    end
    for _, rule in ipairs(self:GetPresetRules()) do
        if tonumber(rule.encounterID) == target then
            rows[#rows + 1] = rule
        end
    end
    for _, rule in ipairs(self:GetRules()) do
        if tonumber(rule.encounterID) == target then
            local row = DeepCopy(rule)
            row.source = "custom"
            row.isPreset = false
            row.canDelete = true
            rows[#rows + 1] = row
        end
    end
    return rows
end

function M:ListBossGroups()
    self:EnsureRules()
    local db = GetDB()
    local seen = {}
    local groups = {}
    local function addGroup(encounterID, customName, isCustomBossGroup)
        local id = tonumber(encounterID)
        if not id or seen[id] then
            if id and isCustomBossGroup and groups[seen[id]] then
                groups[seen[id]].isCustomBossGroup = true
            end
            return
        end
        seen[id] = #groups + 1
        groups[#groups + 1] = {
            encounterID = id,
            name = ResolveBossDisplayName(id, customName),
            isCustomBossGroup = isCustomBossGroup == true,
        }
    end
    for _, encounterID in ipairs(GetPresetBossOrder()) do
        addGroup(encounterID)
    end
    for _, item in ipairs(type(db.customBosses) == "table" and db.customBosses or {}) do
        addGroup(item.encounterID, item.name, true)
    end
    for _, rule in ipairs(db.rules or {}) do
        addGroup(rule.encounterID)
    end
    for _, group in ipairs(groups) do
        local rules = self:ListRulesForBoss(group.encounterID)
        local presetCount, customCount, enabledCount = 0, 0, 0
        for _, rule in ipairs(rules) do
            if rule.isPreset then
                presetCount = presetCount + 1
            else
                customCount = customCount + 1
            end
            if rule.enabled ~= false then
                enabledCount = enabledCount + 1
            end
        end
        group.presetCount = presetCount
        group.customCount = customCount
        group.enabledCount = enabledCount
        group.totalCount = #rules
    end
    return groups
end

function M:DeleteCustomBossGroup(encounterID)
    local id = tonumber(encounterID)
    if not id then
        return false, 0
    end
    local db = GetDB()
    if not db then
        return false, 0
    end
    local removedGroup = false
    if type(db.customBosses) == "table" then
        for index = #db.customBosses, 1, -1 do
            if tonumber(db.customBosses[index] and db.customBosses[index].encounterID) == id then
                table.remove(db.customBosses, index)
                removedGroup = true
            end
        end
    end
    local removedRules = 0
    self:EnsureRules()
    for index = #db.rules, 1, -1 do
        if tonumber(db.rules[index] and db.rules[index].encounterID) == id then
            table.remove(db.rules, index)
            removedRules = removedRules + 1
        end
    end
    if removedGroup or removedRules > 0 then
        self:RefreshConfig("delete_custom_boss_group")
        return true, removedRules
    end
    return false, 0
end

local function FindBossByText(text)
    local query = tostring(text or "")
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then
        return nil, nil
    end
    local directID = tonumber(query)
    if directID then
        return directID, ResolveBossDisplayName(directID)
    end
    local bossSpells = T.Data and T.Data.BossSpells or {}
    for encounterID, boss in pairs(bossSpells) do
        local candidates = {
            boss.name,
            boss.nameZh,
            boss.nameZhTW,
        }
        for _, alias in ipairs(type(boss.aliases) == "table" and boss.aliases or {}) do
            candidates[#candidates + 1] = alias
        end
        for _, candidate in ipairs(candidates) do
            if type(candidate) == "string" and candidate ~= "" and candidate:find(query, 1, true) then
                return tonumber(encounterID), ResolveBossDisplayName(encounterID)
            end
        end
    end
    return nil, nil
end

function M:ResolveBossInput(nameText, idText)
    local idFromText, nameFromText = FindBossByText(idText)
    if idFromText then
        return idFromText, nameFromText
    end
    return FindBossByText(nameText)
end

function M:EnsureCustomBossGroup(encounterID, displayName)
    local id = tonumber(encounterID)
    if not id then
        return nil
    end
    local db = GetDB()
    if not db then
        return nil
    end
    if type(db.customBosses) ~= "table" then
        db.customBosses = {}
    end
    for _, item in ipairs(db.customBosses) do
        if tonumber(item.encounterID) == id then
            if type(displayName) == "string" and displayName ~= "" then
                item.name = displayName
            elseif type(item.name) ~= "string" or item.name == "" or item.name == tostring(id) then
                item.name = ResolveBossDisplayName(id)
            end
            return item
        end
    end
    local item = {
        encounterID = id,
        name = ResolveBossDisplayName(id, displayName),
    }
    db.customBosses[#db.customBosses + 1] = item
    return item
end

function M:BuildRuleTemplate(encounterID)
    local rules = self:GetRuntimeRules()
    local indicatorName = (rules[1] and rules[1].indicatorName) or DEFAULT_INDICATOR_NAME
    local template = NormalizeRule(NewDefaultRule(indicatorName), 1)
    template.id = nil
    template.encounterID = tonumber(encounterID) or DEFAULT_ENCOUNTER_ID
    template.enabled = true
    return template
end

function M:ParseTimeWindows(text)
    return ParseTimeWindows(text)
end

function M:FormatTimeWindows(windows)
    return TimeWindowsToText(windows)
end

function M:BuildImportPayload(ruleID)
    local rules = {}
    local db = GetDB()
    if ruleID then
        local rule = self:GetRuleByID(ruleID)
        if not rule then
            return nil
        end
        rules[#rules + 1] = DeepCopy(rule)
    else
        self:EnsureRules()
        for _, rule in ipairs(self:GetRules()) do
            rules[#rules + 1] = DeepCopy(rule)
        end
    end
    local payload = {
        enabled = self:IsEnabled(),
        applyModuleFields = ruleID == nil,
        rules = rules,
    }
    if ruleID == nil and db then
        payload.presetState = DeepCopy(PruneAllPresetStates(db))
        payload.customBosses = DeepCopy(type(db.customBosses) == "table" and db.customBosses or {})
    end
    return payload
end

local function ApplyPresetStatePayload(db, payload, mode, stats)
    if type(payload.presetState) ~= "table" then
        return
    end
    local target = EnsurePresetState(db)
    if mode == "replace" then
        for key in pairs(target) do
            target[key] = nil
        end
    end
    for key, value in pairs(payload.presetState) do
        if type(key) == "string" and type(value) == "table" then
            local preset = GetPresetByKey(key)
            local pruned = PrunePresetState(preset, value)
            if next(pruned) then
                target[key] = pruned
            else
                target[key] = nil
            end
            stats.presetTouched = (stats.presetTouched or 0) + 1
        end
    end
end

local function ApplyCustomBossPayload(db, payload, mode, stats)
    if type(payload.customBosses) ~= "table" then
        return
    end
    if mode == "replace" then
        db.customBosses = {}
    elseif type(db.customBosses) ~= "table" then
        db.customBosses = {}
    end
    local byID = {}
    for _, item in ipairs(db.customBosses) do
        local id = tonumber(item and item.encounterID)
        if id then
            byID[id] = item
        end
    end
    for _, source in ipairs(payload.customBosses) do
        local id = tonumber(source and source.encounterID)
        if id then
            local item = byID[id]
            local name = ResolveBossDisplayName(id, source.name)
            if item then
                item.name = name
            else
                item = { encounterID = id, name = name }
                db.customBosses[#db.customBosses + 1] = item
                byID[id] = item
            end
            stats.customBossTouched = (stats.customBossTouched or 0) + 1
        end
    end
end

function M:ApplyImportPayload(payload, mode)
    if type(payload) ~= "table" then
        return nil
    end
    local sourceRules = type(payload.rules) == "table" and payload.rules or {}
    local db = GetDB()
    if not db then
        return nil
    end
    self:EnsureRules()

    mode = mode == "replace" and "replace" or "merge"
    local stats = {
        mode = mode,
        sourceCount = 0,
        added = 0,
        replaced = 0,
        presetTouched = 0,
        customBossTouched = 0,
        touchedIDs = {},
        details = {},
    }

    local localByKey = {}
    for index, rule in ipairs(db.rules) do
        local key = RuleImportKey(rule)
        if not localByKey[key] then
            localByKey[key] = { index = index, id = rule.id }
        end
    end

    for _, source in ipairs(sourceRules) do
        if type(source) == "table" then
            stats.sourceCount = stats.sourceCount + 1
            local key = RuleImportKey(source)
            local existing = mode == "replace" and localByKey[key] or nil
            if existing and db.rules[existing.index] then
                local updated = NormalizeRule(source, existing.index)
                updated.id = existing.id
                db.rules[existing.index] = updated
                stats.replaced = stats.replaced + 1
                stats.touchedIDs[#stats.touchedIDs + 1] = updated.id
                stats.details[#stats.details + 1] = {
                    action = "replace",
                    sourceKey = key,
                    localID = updated.id,
                    text = updated.text,
                }
            else
                local rule = AppendImportedRule(db, source, stats)
                localByKey[key] = { index = #db.rules, id = rule.id }
            end
        end
    end

    if payload.applyModuleFields == true and payload.enabled ~= nil then
        db.enabled = payload.enabled == true
    end
    if payload.applyModuleFields == true then
        ApplyPresetStatePayload(db, payload, mode, stats)
        ApplyCustomBossPayload(db, payload, mode, stats)
    end
    self:RefreshConfig("option_push_import")
    return stats
end

function M:UpdatePresetRule(presetKey, values, mergeExisting)
    local preset = GetPresetByKey(presetKey)
    if not preset then
        return nil
    end
    local db = GetDB()
    if not db then
        return nil
    end
    local presetState = EnsurePresetState(db)
    local normalized = CopyPresetState(values or {})
    if mergeExisting == true and type(presetState[preset.key]) == "table" then
        local merged = CopyPresetState(presetState[preset.key])
        for key, value in pairs(normalized) do
            merged[key] = value
        end
        normalized = merged
    end
    local pruned = PrunePresetState(preset, normalized)
    if next(pruned) then
        presetState[preset.key] = pruned
    else
        presetState[preset.key] = nil
    end
    Debug("preset_updated key=%s %s", tostring(preset.key), RuleDebugText(self:GetPresetRule(preset.key)))
    self:RefreshConfig("update_preset")
    return self:GetPresetRule(preset.key)
end

function M:SetRuleIndicator(ruleID, indicatorName)
    local rule = self:GetRuleByID(ruleID)
    if not rule then
        return nil
    end
    local nextIndicator = tostring(indicatorName or "")
    if nextIndicator == "" then
        nextIndicator = DEFAULT_INDICATOR_NAME
    end
    rule.indicatorName = nextIndicator
    if rule.isPreset and rule.presetKey then
        return self:UpdatePresetRule(rule.presetKey, { indicatorName = nextIndicator }, true)
    end
    return self:UpdateRule(rule.id, rule)
end

function M:SetRuleEnabled(ruleID, enabled)
    local rule = self:GetRuleByID(ruleID)
    if not rule then
        return nil
    end
    rule.enabled = enabled == true
    if rule.isPreset and rule.presetKey then
        return self:UpdatePresetRule(rule.presetKey, { enabled = rule.enabled }, true)
    end
    return self:UpdateRule(rule.id, rule)
end

function M:CreateRule(values)
    local db = GetDB()
    if not db then
        return nil
    end
    self:EnsureRules()
    local nextID = tonumber(db.nextRuleID) or 1
    db.nextRuleID = nextID + 1
    local rule = NormalizeRule(values or {}, nextID)
    rule.id = "rule_" .. tostring(nextID)
    db.rules[#db.rules + 1] = rule
    Debug("rule_created %s", RuleDebugText(rule))
    self:RefreshConfig("create_rule")
    return rule
end

function M:UpdateRule(ruleID, values)
    local target = tostring(ruleID or "")
    if target == "" then
        return nil
    end
    local rules = self:GetRules()
    for index, rule in ipairs(rules) do
        if rule.id == target then
            local updated = NormalizeRule(values or {}, index)
            updated.id = target
            rules[index] = updated
            Debug("rule_updated oldRule=%s %s", tostring(target), RuleDebugText(updated))
            self:RefreshConfig("update_rule")
            return updated
        end
    end
    return nil
end

function M:DeleteRule(ruleID)
    local target = tostring(ruleID or "")
    if target == "" then
        return false
    end
    local rules = self:GetRules()
    for index, rule in ipairs(rules) do
        if rule.id == target then
            Debug("rule_deleted %s", RuleDebugText(rule))
            table.remove(rules, index)
            self:RefreshConfig("delete_rule")
            return true
        end
    end
    return false
end

function M:ResetObservedWarnings(encounterID, difficultyID)
    local session = EnsureObservedSession(encounterID, difficultyID, true)
    Debug("observed_reset encounter=%s difficulty=%s",
        tostring(encounterID),
        tostring(difficultyID))
    return session
end

function M:FinishObservedWarnings(encounterID)
    local db = GetDB()
    local session = db and db.observedWarnings
    if type(session) ~= "table" then
        return
    end
    session.endedAt = GetTime()
    Debug("observed_summary encounter=%s difficulty=%s count=%d",
        tostring(encounterID or session.encounterID),
        tostring(session.difficultyID),
        #(session.items or {}))
end

function M:GetObservedWarnings()
    local db = GetDB()
    return db and db.observedWarnings or nil
end

function M:RecordObservedWarning(info, severity)
    if not currentEncounterID then
        return
    end
    local session = EnsureObservedSession(currentEncounterID, currentDifficultyID, false)
    if not session then
        return
    end

    local tooltipSpellID = type(info) == "table" and SafeNumber(info.tooltipSpellID) or nil
    local iconFileID = type(info) == "table" and SafeNumber(info.iconFileID) or nil
    local duration = type(info) == "table" and SafeNumber(info.duration) or nil
    local text = type(info) == "table" and SafeText(info.text) or nil
    local name = SpellNameFromID(tooltipSpellID) or text or UNKNOWN_WARNING_TEXT
    local now = GetTime()
    local item = {
        encounterID = tonumber(currentEncounterID),
        difficultyID = tonumber(currentDifficultyID),
        severity = SafeNumber(severity),
        tooltipSpellID = tooltipSpellID,
        iconFileID = iconFileID,
        duration = duration,
        text = text,
        name = name,
        firstSeen = now,
        lastSeen = now,
        count = 0,
    }
    item.key = BuildObservedKey(item)

    local existing = FindObservedItem(session, item.key)
    if existing then
        existing.count = (tonumber(existing.count) or 0) + 1
        existing.lastSeen = now
    else
        item.count = 1
        session.items[#session.items + 1] = item
        while #session.items > MAX_OBSERVED_WARNINGS do
            table.remove(session.items, 1)
        end
        Debug("warning_observed_new encounter=%s difficulty=%s severity=%s name=%s spellID=%s icon=%s duration=%s",
            tostring(item.encounterID),
            tostring(item.difficultyID),
            tostring(item.severity),
            tostring(item.name),
            tostring(item.tooltipSpellID),
            tostring(item.iconFileID),
            tostring(item.duration))
    end

end

function M:IsEnabled()
    local db = GetDB()
    return db ~= nil and db.enabled == true
end

function M:ShowRule(rule, source, ignoreEnabled, elapsedSec)
    local normalized = NormalizeRule(rule)
    if not ignoreEnabled and not self:IsEnabled() then
        Debug("skip source=%s reason=disabled", tostring(source or "unknown"))
        return false
    end
    if not (T.ScreenReminder and T.ScreenReminder.Show) then
        Debug("skip source=%s reason=screen_reminder_missing", tostring(source or "unknown"))
        return false
    end

    if not (T.ScreenReminderAlert and T.ScreenReminderAlert.ShowImmediateCountdown) then
        Debug("skip source=%s reason=screen_reminder_alert_missing", tostring(source or "unknown"))
        return false
    end
    local shown = T.ScreenReminderAlert:ShowImmediateCountdown({
        text = normalized.text,
        durationSec = normalized.durationSec,
        indicatorName = normalized.indicatorName,
    })
    if not shown then
        Debug("skip source=%s reason=screen_reminder_alert_failed", tostring(source or "unknown"))
        return false
    end

    Debug("show source=%s rule=%s encounter=%s difficulty=%s severity=%s elapsed=%s duration=%.1f indicator=%s text=%s",
        tostring(source or "unknown"),
        tostring(normalized.id),
        tostring(currentEncounterID),
        tostring(currentDifficultyID),
        tostring(normalized.severity),
        elapsedSec ~= nil and string.format("%.1f", tonumber(elapsedSec) or 0) or "nil",
        normalized.durationSec,
        tostring(normalized.indicatorName),
        tostring(normalized.text))
    if normalized.countdownAudioEnabled == true then
        ScheduleCountdownAudio(normalized.durationSec)
    end
    return true
end

local function NotifyRuleShown(info, rule, elapsedSec, severity)
    local enhancer = T.LuraStarsplinterDirection
    if not (enhancer and enhancer.OnPersonalAuraAlertShown) then
        return
    end
    enhancer:OnPersonalAuraAlertShown({
        info = info,
        rule = NormalizeRule(rule),
        encounterID = currentEncounterID,
        difficultyID = currentDifficultyID,
        severity = severity,
        elapsedSec = elapsedSec,
    })
end

function M:RunTest(ruleID)
    local rule = self:GetRuleByID(ruleID) or self:GetRuntimeRules()[1]
    Debug("test_request ruleID=%s found=%s", tostring(ruleID), tostring(rule ~= nil))
    if not rule then
        if T.msg then
            T.msg("个人光环提醒：没有可测试的规则")
        end
        return false
    end
    local shown = self:ShowRule(rule, "test", true)
    if T.msg then
        if shown then
            T.msg(string.format("个人光环提醒：已模拟 %s %.1f 秒倒计时", tostring(rule.text), tonumber(rule.durationSec) or DEFAULT_DURATION))
        else
            T.msg("个人光环提醒：未显示。请确认屏幕提醒已启用且样式存在。")
        end
    end
    return shown
end

function M:HandleEncounterWarning(info)
    local severity = type(info) == "table" and tonumber(info.severity) or nil
    local shouldPlaySound = type(info) == "table" and info.shouldPlaySound == true or false
    local enabled = self:IsEnabled()
    local rules = self:GetRuntimeRules()
    local elapsedSec = encounterStartTime and math.max(0, GetTime() - encounterStartTime) or nil
    self:RecordObservedWarning(info, severity)
    Debug("warning_received active=%s enabled=%s encounter=%s difficulty=%s severity=%s shouldPlaySound=%s elapsed=%s rules=%d",
        tostring(inEncounter),
        tostring(enabled),
        tostring(currentEncounterID),
        tostring(currentDifficultyID),
        tostring(severity),
        tostring(shouldPlaySound),
        elapsedSec ~= nil and string.format("%.1f", elapsedSec) or "nil",
        #rules)
    if not (inEncounter and currentEncounterID) then
        Debug("warning_skip reason=not_in_encounter severity=%s", tostring(severity))
        return
    end
    if not enabled then
        Debug("warning_skip reason=module_disabled severity=%s", tostring(severity))
        return
    end
    local matched = 0
    for _, rule in ipairs(rules) do
        local missReason = RuleMissReason(rule, severity, elapsedSec, shouldPlaySound)
        if not missReason then
            matched = matched + 1
            Debug("rule_match elapsed=%s %s",
                elapsedSec ~= nil and string.format("%.1f", elapsedSec) or "nil",
                RuleDebugText(rule))
            if self:ShowRule(rule, "encounter_warning", false, elapsedSec) then
                NotifyRuleShown(info, rule, elapsedSec, severity)
            end
        end
    end
    if matched == 0 then
        Debug("warning_no_match encounter=%s difficulty=%s severity=%s shouldPlaySound=%s elapsed=%s",
            tostring(currentEncounterID),
            tostring(currentDifficultyID),
            tostring(severity),
            tostring(shouldPlaySound),
            elapsedSec ~= nil and string.format("%.1f", elapsedSec) or "nil")
    end
end

function M:RefreshConfig(reason)
    self:EnsureRules()
end

function M:OnRegister()
    T.PersonalAuraAlert = self
end

function M:OnEnable()
    self:RegisterEvent("ENCOUNTER_START", "OnEvent")
    self:RegisterEvent("ENCOUNTER_END", "OnEvent")
    self:RegisterEvent("ENCOUNTER_WARNING", "OnEvent")
    self:RefreshConfig("enable")
end

function M:OnDisable()
    CancelCountdownAudio()
    inEncounter = false
    currentEncounterID = nil
    currentDifficultyID = nil
    encounterStartTime = nil
end

function M:OnEvent(event, ...)
    if event == "ENCOUNTER_START" then
        local encounterID, _, difficultyID = ...
        currentEncounterID = tonumber(encounterID)
        currentDifficultyID = tonumber(difficultyID)
        encounterStartTime = GetTime()
        inEncounter = currentEncounterID ~= nil
        M:ResetObservedWarnings(currentEncounterID, currentDifficultyID)
        Debug("encounter_start id=%s difficulty=%s start=%.3f active=%s",
            tostring(currentEncounterID),
            tostring(currentDifficultyID),
            encounterStartTime or 0,
            tostring(inEncounter))
    elseif event == "ENCOUNTER_END" then
        local encounterID = tonumber((...))
        Debug("encounter_end id=%s difficulty=%s active=%s",
            tostring(encounterID),
            tostring(currentDifficultyID),
            tostring(inEncounter))
        M:FinishObservedWarnings(encounterID)
        if encounterID == currentEncounterID or currentEncounterID == nil then
            inEncounter = false
            currentEncounterID = nil
            currentDifficultyID = nil
            encounterStartTime = nil
        end
        CancelCountdownAudio()
    elseif event == "ENCOUNTER_WARNING" then
        self:HandleEncounterWarning(...)
    end
end

end)
