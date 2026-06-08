local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded", "dreadElegy.enabled"}, function()

-- 暴雪首领事件解析单一权威：统一过滤 secret value，并把 Timeline / EncounterWarnings 归一到 spellID。
local Resolver = {}
T.EncounterEventResolver = Resolver

local function IsSecretValue(value)
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

local function NormalizeNumber(value)
    if value == nil or IsSecretValue(value) then
        return nil
    end

    local normalized = tonumber(value)
    if type(normalized) ~= "number" or IsSecretValue(normalized) then
        return nil
    end
    return normalized
end

local function IsPositiveNumber(value)
    if type(value) ~= "number" or IsSecretValue(value) then
        return false
    end
    local ok, result = pcall(function()
        return value > 0
    end)
    return ok and result == true
end

local function NormalizePositiveNumber(value)
    local normalized = NormalizeNumber(value)
    if not IsPositiveNumber(normalized) then
        return nil
    end
    return normalized
end

local function NormalizePublicNonEmptyString(value)
    if value == nil or IsSecretValue(value) then
        return nil
    end
    if type(value) ~= "string" then
        return nil
    end
    if value == "" then
        return nil
    end
    return value
end

local function ResolveCanonicalSpellName(spellID)
    local normalizedSpellID = NormalizePositiveNumber(spellID)
    if not normalizedSpellID then
        return nil
    end

    local name = nil
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(normalizedSpellID)
    end
    if type(name) == "string" and name ~= "" then
        return name
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(normalizedSpellID)
        name = info and info.name or nil
    elseif GetSpellInfo then
        name = GetSpellInfo(normalizedSpellID)
    end

    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function GetSpellName(spellID, fallbackName)
    local canonicalName = ResolveCanonicalSpellName(spellID)
    if canonicalName then
        return canonicalName
    end

    local normalizedFallbackName = NormalizePublicNonEmptyString(fallbackName)
    if normalizedFallbackName then
        return normalizedFallbackName
    end

    return tostring(spellID or "")
end

local function BuildEventIDToSpellMap(encounterID)
    local map = {}
    local encounterMap = T.SemanticEncounterEventMapS14
        and T.SemanticEncounterEventMapS14[tonumber(encounterID) or 0] or nil
    if type(encounterMap) ~= "table" then return map end
    for canonicalSpellID, entry in pairs(encounterMap) do
        local norm = NormalizePositiveNumber(canonicalSpellID)
        if norm then
            for _, eventID in ipairs(entry.encounterEventIDs or {}) do
                local normEventID = NormalizePositiveNumber(eventID)
                if normEventID then
                    map[normEventID] = norm
                end
            end
        end
    end
    return map
end

local function BuildEncounterSpellAliasMap(encounterID)
    local map = {}
    local encounterMap = T.SemanticEncounterEventMapS14 and T.SemanticEncounterEventMapS14[tonumber(encounterID) or 0] or nil
    if type(encounterMap) ~= "table" then
        return map
    end

    for canonicalSpellID, entry in pairs(encounterMap) do
        local normalizedCanonicalSpellID = NormalizePositiveNumber(canonicalSpellID)
        if normalizedCanonicalSpellID then
            map[normalizedCanonicalSpellID] = normalizedCanonicalSpellID
            for _, triggerSpellID in ipairs(entry.triggerSpellIDs or {}) do
                local normalizedTriggerSpellID = NormalizePositiveNumber(triggerSpellID)
                if normalizedTriggerSpellID then
                    map[normalizedTriggerSpellID] = normalizedCanonicalSpellID
                end
            end
        end
    end

    return map
end

local function NormalizeSpellName(value)
    return NormalizePublicNonEmptyString(value)
end

function Resolver.IsSecretValue(value)
    return IsSecretValue(value)
end

function Resolver.NormalizeNumber(value)
    return NormalizeNumber(value)
end

function Resolver.IsPositiveNumber(value)
    return IsPositiveNumber(value)
end

function Resolver.NormalizePositiveNumber(value)
    return NormalizePositiveNumber(value)
end

function Resolver.BuildEventIDToSpellMap(encounterID)
    return BuildEventIDToSpellMap(encounterID)
end

function Resolver.NormalizeEventID(eventInfoOrID)
    local rawValue = type(eventInfoOrID) == "table" and eventInfoOrID.id or eventInfoOrID
    return NormalizePositiveNumber(rawValue)
end

function Resolver.GetSpellName(spellID, fallbackName)
    return GetSpellName(spellID, fallbackName)
end

function Resolver.MapEncounterSpellID(encounterID, observedSpellID)
    local normalizedObservedSpellID = NormalizePositiveNumber(observedSpellID)
    if not normalizedObservedSpellID then
        return nil
    end

    local aliasMap = BuildEncounterSpellAliasMap(encounterID)
    return aliasMap[normalizedObservedSpellID] or normalizedObservedSpellID
end

function Resolver.ResolveCanonicalSpellID(observedEvent, encounterID)
    if type(observedEvent) == "table" then
        local timelineMeta = Resolver.ResolveTimelineSpellMeta(observedEvent, encounterID)
        if timelineMeta and timelineMeta.spellID then
            return timelineMeta.spellID
        end

        local warningMeta = Resolver.ResolveWarningSpellMeta(observedEvent, encounterID)
        if warningMeta and warningMeta.spellID then
            return warningMeta.spellID
        end

        local observedSpellID = NormalizePositiveNumber(observedEvent.spellID)
            or NormalizePositiveNumber(observedEvent.tooltipSpellID)
            or NormalizePositiveNumber(observedEvent.observedSpellID)
        if observedSpellID then
            return Resolver.MapEncounterSpellID(encounterID, observedSpellID)
        end

        local eventID = Resolver.NormalizeEventID(observedEvent.id or observedEvent.eventID)
        if eventID then
            local meta = Resolver.ResolveTimelineSpellMeta(eventID, encounterID)
            if meta and meta.spellID then
                return meta.spellID
            end
        end
        return nil
    end

    local timelineMeta = Resolver.ResolveTimelineSpellMeta(observedEvent, encounterID)
    if timelineMeta and timelineMeta.spellID then
        return timelineMeta.spellID
    end

    local observedSpellID = NormalizePositiveNumber(observedEvent)
    if observedSpellID then
        return Resolver.MapEncounterSpellID(encounterID, observedSpellID)
    end

    return nil
end

function Resolver.ResolveTimelineSpellMeta(eventInfoOrID, encounterID)
    local eventID = Resolver.NormalizeEventID(eventInfoOrID)
    if not eventID then
        return nil
    end

    local observedSpellID = nil
    local fallbackName = nil
    if type(eventInfoOrID) == "table" then
        observedSpellID = NormalizePositiveNumber(eventInfoOrID.spellID)
        fallbackName = NormalizeSpellName(eventInfoOrID.spellName)
    end

    if (not observedSpellID or observedSpellID <= 0) and C_EncounterTimeline and type(C_EncounterTimeline.GetEventInfo) == "function" then
        local ok, info = pcall(C_EncounterTimeline.GetEventInfo, eventID)
        if ok and type(info) == "table" then
            observedSpellID = NormalizePositiveNumber(info.spellID)
            fallbackName = fallbackName or NormalizeSpellName(info.spellName)
        end
    end

    if not observedSpellID and C_EncounterEvents and type(C_EncounterEvents.GetEventInfo) == "function" then
        local hasInfo = true
        if type(C_EncounterEvents.HasEventInfo) == "function" then
            local ok, result = pcall(C_EncounterEvents.HasEventInfo, eventID)
            hasInfo = ok and result == true
        end
        if hasInfo then
            local ok, info = pcall(C_EncounterEvents.GetEventInfo, eventID)
            if ok and type(info) == "table" then
                observedSpellID = NormalizePositiveNumber(info.spellID)
                fallbackName = fallbackName or NormalizeSpellName(info.spellName)
            end
        end
    end

    local spellID = Resolver.MapEncounterSpellID(encounterID, observedSpellID)

    -- secret value 回退：spellID 为 nil 时，通过 eventID→spellID 映射表反查
    if not spellID and eventID then
        local eventMap = BuildEventIDToSpellMap(encounterID)
        spellID = eventMap[eventID]
    end

    if not spellID then
        return nil
    end

    return {
        eventID = eventID,
        observedSpellID = observedSpellID or spellID,
        spellID = spellID,
        spellName = GetSpellName(spellID, fallbackName),
    }
end

function Resolver.ResolveWarningSpellMeta(encounterWarningInfo, encounterID)
    if type(encounterWarningInfo) ~= "table" then
        return nil
    end

    local observedSpellID = NormalizePositiveNumber(encounterWarningInfo.tooltipSpellID)
    if not observedSpellID then
        return nil
    end

    local spellID = Resolver.MapEncounterSpellID(encounterID, observedSpellID)
    if not spellID then
        return nil
    end

    return {
        observedSpellID = observedSpellID,
        spellID = spellID,
        spellName = GetSpellName(spellID, nil),
    }
end

function Resolver.ResolveEncounterSpellMeta(eventInfoOrID, encounterID)
    return Resolver.ResolveTimelineSpellMeta(eventInfoOrID, encounterID)
end

T.ResolveCanonicalSpellID = function(observedEvent, encounterID)
    return Resolver.ResolveCanonicalSpellID(observedEvent, encounterID)
end

end)
