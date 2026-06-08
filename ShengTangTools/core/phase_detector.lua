local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

-- 时间轴阶段检测单一权威：
-- 1) 内置 spell/event/duration 锚点优先；
-- 2) 用户规则只做兼容回退；
-- 3) BigWigs / DBM 外部阶段广播最后；
-- 4) 只维护一份 currentPhase / phaseStartTimes，供 TimelineRunner 查询。
local Detector = {}
T.PhaseDetector = Detector

local ENCOUNTER_SOURCE = (Enum and Enum.EncounterTimelineEventSource and Enum.EncounterTimelineEventSource.Encounter) or 0
local EVENT_STATE_FINISHED = (Enum and Enum.EncounterTimelineEventState and Enum.EncounterTimelineEventState.Finished) or 2
local EVENT_STATE_CANCELED = (Enum and Enum.EncounterTimelineEventState and Enum.EncounterTimelineEventState.Canceled) or 3
local DEBOUNCE_SECONDS = 5
local WINDOW_HISTORY_SECONDS = 5

Detector.activeEncounterID = 0
Detector.activeDifficultyID = 0
Detector.currentPhase = nil
Detector.phaseStartTimes = {}
Detector.phaseSwapTime = 0
Detector.onPhaseChanged = nil
Detector.userRules = nil
Detector.builtinConfig = nil
Detector.active = false
Detector.timelineEventCache = {}
Detector.timelineSignalHistory = {}
Detector.lastTimelineAddedAt = 0
Detector.delayedTimelineEventIDs = {}
Detector.engageUnitRetryTimer = nil

local external = {
    bigWigsRegistered = false,
    dbmRegistered = false,
}

local timelineFrame

local function DebugPhase(eventName, fields)
    if not (C and C.DB and C.DB.debugMode) then
        return
    end

    local parts = {
        "PhaseDetector",
        tostring(eventName or "event"),
    }
    for key, value in pairs(fields or {}) do
        if value ~= nil and value ~= "" then
            parts[#parts + 1] = string.format("%s=%s", tostring(key), tostring(value))
        end
    end
    T.debug(table.concat(parts, " "))
end

local function BuildAnchorDebugValue(value)
    if value == nil or value == "" then
        return "nil"
    end
    return tostring(value)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return true
    end
    local args = { ... }
    return xpcall(function()
        return fn(unpack(args))
    end, geterrorhandler())
end

local function CancelEngageUnitRetry(detector)
    if detector and detector.engageUnitRetryTimer then
        detector.engageUnitRetryTimer:Cancel()
        detector.engageUnitRetryTimer = nil
    end
end

local ParsePhaseKey

local function NormalizePhaseKey(phaseKey)
    local parsed = ParsePhaseKey and ParsePhaseKey(phaseKey) or nil
    return parsed and parsed.key or nil
end

function ParsePhaseKey(phaseKey)
    if type(phaseKey) ~= "string" then
        return nil
    end

    local phaseType, phaseIndex, roundIndex = phaseKey:match("^([pi])(%d+)r(%d+)$")
    local hasExplicitRound = phaseType ~= nil
    if not phaseType then
        phaseType, phaseIndex = phaseKey:match("^([pi])(%d+)$")
        roundIndex = "1"
    end
    if not phaseType then
        return nil
    end

    local normalizedPhaseIndex = tonumber(phaseIndex)
    local normalizedRoundIndex = tonumber(roundIndex)
    if not normalizedPhaseIndex or normalizedPhaseIndex <= 0 then
        return nil
    end
    if not normalizedRoundIndex or normalizedRoundIndex <= 0 then
        return nil
    end

    local baseKey = string.format("%s%d", phaseType, normalizedPhaseIndex)
    local roundKey = string.format("%sr%d", baseKey, normalizedRoundIndex)
    return {
        key = hasExplicitRound and roundKey or baseKey,
        baseKey = baseKey,
        roundKey = roundKey,
        phaseType = phaseType,
        phaseIndex = normalizedPhaseIndex,
        roundIndex = normalizedRoundIndex,
        hasExplicitRound = hasExplicitRound,
    }
end

local function AnchorGroupHasNextRound(anchorGroup)
    if type(anchorGroup) ~= "table" then
        return false
    end
    if anchorGroup.nextRound == true then
        return true
    end
    for _, anchor in ipairs(anchorGroup) do
        if type(anchor) == "table" and anchor.nextRound == true then
            return true
        end
    end
    return false
end

local function ConfigUsesRoundModel(config)
    local anchors = type(config) == "table" and config.anchors or nil
    if type(anchors) ~= "table" then
        return false
    end
    for _, anchorGroup in pairs(anchors) do
        if AnchorGroupHasNextRound(anchorGroup) then
            return true
        end
    end
    return false
end

local function NormalizeRuntimePhaseKey(phaseKey, opts)
    local parsed = ParsePhaseKey(phaseKey)
    if not parsed then
        return nil
    end
    opts = type(opts) == "table" and opts or {}
    if parsed.hasExplicitRound or opts.forceRound or ConfigUsesRoundModel(opts.config) then
        return parsed.roundKey
    end
    return parsed.baseKey
end

local function ResolveStageNumber(phaseKey)
    local parsed = ParsePhaseKey(phaseKey)
    if not parsed then
        return nil
    end
    if parsed.phaseType == "i" then
        return parsed.phaseIndex + 0.5
    end
    return parsed.phaseIndex
end

local function NormalizeEncounterID(encounterID)
    local normalized = tonumber(encounterID)
    if not normalized or normalized <= 0 then
        return 0
    end
    return normalized
end

local function GetCurrentDifficultyID()
    if type(GetInstanceInfo) ~= "function" then
        return 0
    end
    local _, _, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID)
    if not difficultyID or difficultyID <= 0 then
        return 0
    end
    return difficultyID
end

local function ResolveBuiltinConfig(encounterID, difficultyID)
    local baseConfig = type(T.PhaseAnchorsS14) == "table" and T.PhaseAnchorsS14[tonumber(encounterID) or 0] or nil
    if type(baseConfig) ~= "table" then
        return nil, nil
    end

    local difficultyOverrides = baseConfig.difficultyOverrides
    local overrideConfig = type(difficultyOverrides) == "table" and difficultyOverrides[tonumber(difficultyID) or 0] or nil
    if type(overrideConfig) ~= "table" then
        return baseConfig, baseConfig
    end

    return setmetatable({}, {
        __index = function(_, key)
            local overrideValue = overrideConfig[key]
            if overrideValue ~= nil then
                return overrideValue
            end
            return baseConfig[key]
        end,
    }), baseConfig
end

local function ArePhaseRulesEquivalent(left, right)
    if left == right then
        return true
    end
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    for phaseKey, leftRule in pairs(left) do
        local rightRule = right[phaseKey]
        if type(leftRule) ~= "table" or type(rightRule) ~= "table" then
            return false
        end
        if tostring(leftRule.type or "") ~= tostring(rightRule.type or "") then
            return false
        end
        if tonumber(leftRule.spellID) ~= tonumber(rightRule.spellID) then
            return false
        end
    end

    for phaseKey in pairs(right) do
        if left[phaseKey] == nil then
            return false
        end
    end

    return true
end

local function NormalizeStage(stage)
    local normalized = tonumber(stage)
    if not normalized then
        return nil
    end

    local integer = math.floor(normalized)
    if integer <= 0 then
        return nil
    end

    if normalized == integer then
        return NormalizePhaseKey("p" .. integer)
    end
    if normalized == integer + 0.5 then
        return NormalizePhaseKey("i" .. integer)
    end
    return nil
end

function Detector:_ResetState()
    CancelEngageUnitRetry(self)
    self.activeEncounterID = 0
    self.activeDifficultyID = 0
    self.currentPhase = nil
    self.phaseSwapTime = 0
    self.onPhaseChanged = nil
    self.userRules = nil
    self.builtinConfig = nil
    self.active = false
    self.lastTimelineAddedAt = 0
    self.engageUnitRetryTimer = nil
    wipe(self.phaseStartTimes)
    wipe(self.timelineEventCache)
    wipe(self.timelineSignalHistory)
    wipe(self.delayedTimelineEventIDs)
end

function Detector:_TryUserRules(spellID)
    local normalizedSpellID = tonumber(spellID)
    if not normalizedSpellID or type(self.userRules) ~= "table" then
        return nil
    end

    for phaseKey, rule in pairs(self.userRules) do
        if type(rule) == "table" and rule.type == "spell" and tonumber(rule.spellID) == normalizedSpellID then
            return NormalizePhaseKey(phaseKey)
        end
    end
    return nil
end

function Detector:_GetBuiltinAnchorGroup()
    local config = self.builtinConfig
    if type(config) ~= "table" or type(config.anchors) ~= "table" then
        return nil
    end

    local currentPhase = NormalizePhaseKey(self.currentPhase)
    if not currentPhase then
        return nil
    end

    local exactGroup = config.anchors[currentPhase]
    if exactGroup ~= nil then
        return exactGroup
    end

    local parsed = ParsePhaseKey(currentPhase)
    if parsed then
        return config.anchors[parsed.baseKey]
    end
    return nil
end

function Detector:_GetEngageUnitAnchorGroup()
    local config = self.builtinConfig
    if type(config) ~= "table" or type(config.engageUnitAnchors) ~= "table" then
        return nil
    end

    local currentPhase = NormalizePhaseKey(self.currentPhase)
    if not currentPhase then
        return nil
    end

    local exactGroup = config.engageUnitAnchors[currentPhase]
    if exactGroup ~= nil then
        return exactGroup
    end

    local parsed = ParsePhaseKey(currentPhase)
    if parsed then
        return config.engageUnitAnchors[parsed.baseKey]
    end
    return nil
end

local function IsAnchorRecord(anchor)
    return type(anchor) == "table"
        and (
            anchor.toPhase ~= nil
            or anchor.duration ~= nil
            or anchor.spellID ~= nil
            or anchor.eventID ~= nil
            or anchor.nextRound ~= nil
        )
end

local function NormalizeAnchorList(anchorGroup)
    if IsAnchorRecord(anchorGroup) then
        return { anchorGroup }
    end
    if type(anchorGroup) ~= "table" then
        return nil
    end

    local list = {}
    for _, anchor in ipairs(anchorGroup) do
        if IsAnchorRecord(anchor) then
            list[#list + 1] = anchor
        end
    end
    if #list == 0 then
        return nil
    end
    return list
end

function Detector:_ResolveAnchorTarget(anchor)
    if type(anchor) ~= "table" then
        return nil
    end

    local rawToPhase = tostring(anchor.toPhase or "")
    local targetParsed = ParsePhaseKey(rawToPhase)
    if not targetParsed then
        return nil
    end

    local hasExplicitRound = rawToPhase:match("^([pi]%d+)r(%d+)$") ~= nil
    if hasExplicitRound then
        return targetParsed.roundKey
    end

    local currentParsed = ParsePhaseKey(self.currentPhase)
    local roundIndex = currentParsed and currentParsed.roundIndex or 1
    if anchor.nextRound == true then
        roundIndex = roundIndex + 1
    end

    if ConfigUsesRoundModel(self.builtinConfig) or anchor.nextRound == true or (currentParsed and currentParsed.hasExplicitRound) then
        return NormalizeRuntimePhaseKey(string.format("%sr%d", targetParsed.baseKey, roundIndex), { forceRound = true })
    end
    return targetParsed.baseKey
end

local function NormalizeMatchEvent(value)
    if value == "finished" then
        return "finished"
    end
    if value == "canceled" then
        return "canceled"
    end
    if value == "ended" then
        return "ended"
    end
    return "added"
end

local function MatchTimelineState(anchorMatchEvent, normalizedTimelineState)
    if anchorMatchEvent == "ended" then
        return normalizedTimelineState == "finished" or normalizedTimelineState == "canceled"
    end
    return anchorMatchEvent == normalizedTimelineState
end

local function MatchDurationList(list, value, tolerance)
    if type(list) ~= "table" then
        return false
    end

    local normalizedValue = tonumber(value)
    if not normalizedValue then
        return false
    end

    for _, candidate in ipairs(list) do
        local normalizedCandidate = tonumber(candidate)
        if normalizedCandidate and math.abs(normalizedValue - normalizedCandidate) <= tolerance then
            return true
        end
    end

    return false
end

local function MatchNumberList(list, value)
    if type(list) ~= "table" then
        return false
    end

    local normalizedValue = tonumber(value)
    if not normalizedValue then
        return false
    end

    for _, candidate in ipairs(list) do
        if tonumber(candidate) == normalizedValue then
            return true
        end
    end

    return false
end

function Detector:_RememberTimelineSignal(timestamp, duration, spellMeta, timelineState, eventID)
    local now = tonumber(timestamp) or 0
    local cutoff = now - WINDOW_HISTORY_SECONDS

    local writeIndex = 1
    for readIndex = 1, #self.timelineSignalHistory do
        local entry = self.timelineSignalHistory[readIndex]
        if type(entry) == "table" and tonumber(entry.timestamp) and entry.timestamp >= cutoff then
            self.timelineSignalHistory[writeIndex] = entry
            writeIndex = writeIndex + 1
        end
    end
    for index = writeIndex, #self.timelineSignalHistory do
        self.timelineSignalHistory[index] = nil
    end

    self.timelineSignalHistory[#self.timelineSignalHistory + 1] = {
        timestamp = now,
        duration = tonumber(duration),
        spellID = spellMeta and tonumber(spellMeta.spellID) or nil,
        resolvedEventID = spellMeta and tonumber(spellMeta.eventID) or nil,
        eventID = tonumber(eventID),
        timelineState = NormalizeMatchEvent(timelineState),
    }
end

function Detector:_AnchorSignalMatches(anchor, duration, spellMeta, normalizedTimelineState, context)
    local anchorMatchEvent = NormalizeMatchEvent(anchor.matchEvent)
    local eventSpellID = spellMeta and tonumber(spellMeta.spellID) or nil
    local eventID = spellMeta and tonumber(spellMeta.eventID) or nil
    local normalizedDuration = tonumber(duration)
    local tolerance = tonumber(anchor.durationTolerance)
        or tonumber(self.builtinConfig and self.builtinConfig.durationTolerance)
        or 0.75

    if not MatchTimelineState(anchorMatchEvent, normalizedTimelineState) then
        return false, "timeline_state_mismatch"
    end

    if anchor.spellID and tonumber(anchor.spellID) ~= eventSpellID then
        return false, "spell_id_mismatch"
    end
    if anchor.spellIDOneOf and not MatchNumberList(anchor.spellIDOneOf, eventSpellID) then
        return false, "spell_id_list_mismatch"
    end
    if anchor.eventID and tonumber(anchor.eventID) ~= eventID then
        return false, "event_id_mismatch"
    end
    if anchor.eventIDOneOf and not MatchNumberList(anchor.eventIDOneOf, eventID) then
        return false, "event_id_list_mismatch"
    end

    if anchor.duration ~= nil then
        if not normalizedDuration then
            return false, "duration_missing"
        end
        if math.abs(normalizedDuration - tonumber(anchor.duration)) > tolerance then
            return false, "duration_mismatch"
        end
    end

    if anchor.durationOneOf ~= nil then
        if not MatchDurationList(anchor.durationOneOf, normalizedDuration, tolerance) then
            return false, "duration_list_mismatch"
        end
    end

    if anchor.minPhaseDuration then
        local minDuration = tonumber(anchor.minPhaseDuration)
        if minDuration and minDuration > 0 then
            local phaseStart = self.phaseStartTimes[self.currentPhase]
            local now = (type(context) == "table" and tonumber(context.timestamp))
                or (GetTime and tonumber(GetTime()) or 0)
            if phaseStart and (now - phaseStart) < minDuration then
                return false, "min_phase_duration"
            end
        end
    end

    if anchor.minGapSincePreviousAdded then
        local requiredGap = tonumber(anchor.minGapSincePreviousAdded)
        local gapValue = type(context) == "table" and tonumber(context.gapSincePreviousAdded) or nil
        if not requiredGap or requiredGap <= 0 or not gapValue or gapValue < requiredGap then
            return false, "previous_added_gap"
        end
    end

    if anchor.maxRecentAddedCount then
        local maxCount = tonumber(anchor.maxRecentAddedCount)
        local windowSeconds = tonumber(anchor.windowSeconds) or 0
        local now = (type(context) == "table" and tonumber(context.timestamp))
            or (GetTime and tonumber(GetTime()) or 0)
        local count = 0
        for _, entry in ipairs(self.timelineSignalHistory) do
            if type(entry) == "table"
                and tonumber(entry.timestamp)
                and entry.timelineState == "added"
                and (now - entry.timestamp) < windowSeconds then
                count = count + 1
            end
        end
        if not maxCount or count > maxCount then
            return false, "recent_added_count_miss", count
        end
    end

    if anchor.requiredCount then
        local requiredCount = tonumber(anchor.requiredCount)
        local windowSeconds = tonumber(anchor.windowSeconds) or 0
        local now = (type(context) == "table" and tonumber(context.timestamp))
            or (GetTime and tonumber(GetTime()) or 0)
        local count = 0
        for _, entry in ipairs(self.timelineSignalHistory) do
            if type(entry) == "table"
                and tonumber(entry.timestamp)
                and (now - entry.timestamp) <= windowSeconds then
                local entrySpellMeta = {
                    spellID = entry.spellID,
                    eventID = entry.resolvedEventID,
                }
                local matchedEntry = self:_AnchorSignalMatches(
                    {
                        matchEvent = anchor.matchEvent,
                        spellID = anchor.spellID,
                        spellIDOneOf = anchor.spellIDOneOf,
                        eventID = anchor.eventID,
                        eventIDOneOf = anchor.eventIDOneOf,
                        duration = anchor.duration,
                        durationOneOf = anchor.durationOneOf,
                        durationTolerance = anchor.durationTolerance,
                    },
                    entry.duration,
                    entrySpellMeta,
                    entry.timelineState,
                    { timestamp = entry.timestamp }
                )
                if matchedEntry then
                    count = count + 1
                end
            end
        end
        if not requiredCount or count < requiredCount then
            return false, "window_count_miss", count
        end
        return true, "matched", count
    end

    return true, "matched"
end

function Detector:_TryBuiltinAnchors(duration, spellMeta, timelineState, context)
    local anchorList = NormalizeAnchorList(self:_GetBuiltinAnchorGroup())
    local normalizedTimelineState = NormalizeMatchEvent(timelineState)
    if not anchorList then
        DebugPhase("builtin_anchor_skip", {
            currentPhase = self.currentPhase,
            duration = BuildAnchorDebugValue(duration),
            timelineState = normalizedTimelineState,
            difficultyID = self.activeDifficultyID,
            reason = "no_anchor_group",
        })
        return nil, nil
    end

    for _, anchor in ipairs(anchorList) do
        local anchorSpellID = tonumber(anchor.spellID)
        local anchorEventID = tonumber(anchor.eventID)
        local anchorDuration = tonumber(anchor.duration)
        local anchorMatchEvent = NormalizeMatchEvent(anchor.matchEvent)
        local eventSpellID = spellMeta and tonumber(spellMeta.spellID) or nil
        local eventID = spellMeta and tonumber(spellMeta.eventID) or nil
        local normalizedDuration = tonumber(duration)
        local matched, reason, matchedCount = self:_AnchorSignalMatches(anchor, duration, spellMeta, normalizedTimelineState, context)

        DebugPhase("builtin_anchor_compare", {
            currentPhase = self.currentPhase,
            duration = BuildAnchorDebugValue(normalizedDuration),
            eventID = BuildAnchorDebugValue(eventID),
            spellID = BuildAnchorDebugValue(eventSpellID),
            timelineState = normalizedTimelineState,
            difficultyID = self.activeDifficultyID,
            anchorToPhase = BuildAnchorDebugValue(anchor.toPhase),
            anchorDuration = BuildAnchorDebugValue(anchorDuration),
            anchorEventID = BuildAnchorDebugValue(anchorEventID),
            anchorSpellID = BuildAnchorDebugValue(anchorSpellID),
            anchorMatchEvent = anchorMatchEvent,
            anchorRequiredCount = BuildAnchorDebugValue(anchor.requiredCount),
            anchorMaxRecentAddedCount = BuildAnchorDebugValue(anchor.maxRecentAddedCount),
            anchorWindowSeconds = BuildAnchorDebugValue(anchor.windowSeconds),
            matchedCount = BuildAnchorDebugValue(matchedCount),
            result = reason,
        })

        if matched then
            local targetPhase = self:_ResolveAnchorTarget(anchor)
            if targetPhase then
                DebugPhase("builtin_anchor_match", {
                    currentPhase = self.currentPhase,
                    nextPhase = targetPhase,
                    duration = BuildAnchorDebugValue(normalizedDuration),
                    eventID = BuildAnchorDebugValue(eventID),
                    spellID = BuildAnchorDebugValue(eventSpellID),
                    timelineState = normalizedTimelineState,
                    difficultyID = self.activeDifficultyID,
                    matchEvent = anchorMatchEvent,
                    anchorToPhase = BuildAnchorDebugValue(anchor.toPhase),
                    matchedCount = BuildAnchorDebugValue(matchedCount),
                })
                return targetPhase, anchor
            end
            DebugPhase("builtin_anchor_compare", {
                currentPhase = self.currentPhase,
                duration = BuildAnchorDebugValue(normalizedDuration),
                eventID = BuildAnchorDebugValue(eventID),
                spellID = BuildAnchorDebugValue(eventSpellID),
                timelineState = normalizedTimelineState,
                anchorMatchEvent = anchorMatchEvent,
                anchorToPhase = BuildAnchorDebugValue(anchor.toPhase),
                difficultyID = self.activeDifficultyID,
                result = "target_invalid",
            })
        end
    end

    return nil, nil
end

function Detector:_SetPhase(phaseKey, source, extra)
    local normalizedPhase = NormalizeRuntimePhaseKey(phaseKey, { config = self.builtinConfig })
    if not normalizedPhase then
        return false
    end

    local now = GetTime and (tonumber(GetTime()) or 0) or 0
    local oldPhase = self.currentPhase
    if self.currentPhase == normalizedPhase then
        return false
    end
    if self.phaseSwapTime > 0 and (now - self.phaseSwapTime) < DEBOUNCE_SECONDS then
        DebugPhase("debounce_skip", {
            currentPhase = self.currentPhase,
            nextPhase = normalizedPhase,
            source = source,
        })
        return false
    end

    local plog = T.PerfLog and T.PerfLog:Begin("phase:set")
    CancelEngageUnitRetry(self)
    self.currentPhase = normalizedPhase
    self.phaseStartTimes[normalizedPhase] = now
    self.phaseSwapTime = now

    local payload = type(extra) == "table" and extra or {}
    payload.phase = normalizedPhase
    payload.source = source
    payload.encounterID = self.activeEncounterID
    DebugPhase("phase_changed", payload)

    if self.onPhaseChanged then
        SafeCall(self.onPhaseChanged, normalizedPhase, source)
    end
    if T.PerfLog then
        T.PerfLog:RecordEvent("phase", {
            from = oldPhase or "",
            to = normalizedPhase,
            source = source,
            encounter = self.activeEncounterID or 0,
        })
    end
    if plog then plog:Finish({ from = oldPhase or "", to = normalizedPhase }) end
    return true
end

function Detector:Start(encounterID, phaseRules, callback)
    self:_ResetState()
    self:EnsureEventFrame()

    self.activeEncounterID = NormalizeEncounterID(encounterID)
    self.activeDifficultyID = GetCurrentDifficultyID()
    self.onPhaseChanged = callback
    self.active = true

    local baseBuiltinConfig = nil
    if self.activeEncounterID > 0 then
        self.builtinConfig, baseBuiltinConfig = ResolveBuiltinConfig(self.activeEncounterID, self.activeDifficultyID)
    end

    if type(phaseRules) == "table" and next(phaseRules) ~= nil then
        local shouldSuppressBuiltinRules = false
        local builtinTemplateRules = (self.builtinConfig and self.builtinConfig.templateRules)
            or (baseBuiltinConfig and baseBuiltinConfig.templateRules)
        if self.builtinConfig
            and self.builtinConfig.ignoreBuiltinTemplateRules
            and ArePhaseRulesEquivalent(phaseRules, builtinTemplateRules) then
            shouldSuppressBuiltinRules = true
        end
        if shouldSuppressBuiltinRules then
            DebugPhase("suppress_builtin_template_rules", {
                encounterID = self.activeEncounterID,
                difficultyID = self.activeDifficultyID,
            })
        else
            self.userRules = phaseRules
        end
    end

    local initialPhase = nil
    if type(self.builtinConfig) == "table" then
        initialPhase = NormalizeRuntimePhaseKey(self.builtinConfig.initialPhase, { config = self.builtinConfig })
    end
    if not initialPhase then
        initialPhase = "p1"
    end

    self:_SetPhase(initialPhase, "initial", {})
    DebugPhase("start", {
        encounterID = self.activeEncounterID,
        difficultyID = self.activeDifficultyID,
        hasUserRules = self.userRules and "true" or "false",
        hasBuiltin = self.builtinConfig and "true" or "false",
        initialPhase = initialPhase,
    })
end

function Detector:Stop()
    if self.active then
        DebugPhase("stop", {
            encounterID = self.activeEncounterID,
            currentPhase = self.currentPhase,
        })
    end
    self:DisableEventFrame()
    self:_ResetState()
end

function Detector:GetPhaseStartTime(phaseKey)
    local parsed = ParsePhaseKey(phaseKey)
    if not parsed then
        return nil
    end
    return self.phaseStartTimes[parsed.key]
        or self.phaseStartTimes[parsed.baseKey]
        or self.phaseStartTimes[parsed.roundKey]
end

function Detector:GetCurrentPhase()
    return self.currentPhase
end

function Detector:IsRunning()
    return self.active == true
end

function Detector:_TryBuiltinDelay(duration, timelineState, context)
    local config = self.builtinConfig
    if type(config) ~= "table" or type(config.delayRules) ~= "table" then
        return false
    end
    if NormalizeMatchEvent(timelineState) ~= "added" then
        return false
    end

    local currentParsed = ParsePhaseKey(self.currentPhase)
    if not currentParsed then
        return false
    end

    local normalizedDuration = tonumber(duration)
    local now = (type(context) == "table" and tonumber(context.timestamp))
        or (GetTime and tonumber(GetTime()) or 0)
    if not normalizedDuration or not now or now <= 0 then
        return false
    end

    local eventID = type(context) == "table" and tonumber(context.eventID) or nil
    if eventID and self.delayedTimelineEventIDs[eventID] then
        return false
    end

    for _, rule in ipairs(config.delayRules) do
        if type(rule) == "table" then
            local phaseBase = tostring(rule.phase or "")
            local tolerance = tonumber(rule.durationTolerance) or tonumber(config.durationTolerance) or 0
            local targetDuration = tonumber(rule.duration)
            if phaseBase == currentParsed.baseKey
                and targetDuration
                and math.abs(normalizedDuration - targetDuration) <= tolerance then
                local phaseStart = self.phaseSwapTime
                if not phaseStart or phaseStart <= 0 then
                    phaseStart = self.phaseStartTimes[self.currentPhase]
                end
                local diff = phaseStart and (now - phaseStart) or nil
                local baseline = tonumber(rule.baseline)
                local maxDiff = tonumber(rule.maxDiff)
                local minDelay = tonumber(rule.minDelay) or 0
                if diff and baseline and (not maxDiff or diff <= maxDiff) then
                    local delay = diff - baseline
                    if delay > minDelay then
                        if eventID then
                            self.delayedTimelineEventIDs[eventID] = true
                        end
                        self.phaseStartTimes[self.currentPhase] = (self.phaseStartTimes[self.currentPhase] or phaseStart) + delay
                        if T.TimelineRunner and T.TimelineRunner.DelayPhaseEvents then
                            SafeCall(T.TimelineRunner.DelayPhaseEvents, T.TimelineRunner, self.currentPhase, delay)
                        end
                        DebugPhase("phase_delay_applied", {
                            currentPhase = self.currentPhase,
                            duration = BuildAnchorDebugValue(normalizedDuration),
                            eventID = BuildAnchorDebugValue(eventID),
                            diff = string.format("%.2f", diff),
                            baseline = string.format("%.2f", baseline),
                            delay = string.format("%.2f", delay),
                            difficultyID = self.activeDifficultyID,
                        })
                        return true
                    end
                end
            end
        end
    end

    return false
end

function Detector:_ProcessTimelineInput(duration, spellMeta, timelineState, context)
    local normalizedTimelineState = NormalizeMatchEvent(timelineState)

    if self.builtinConfig then
        self:_TryBuiltinDelay(duration, normalizedTimelineState, context)
        local phaseKey, anchor = self:_TryBuiltinAnchors(duration, spellMeta, normalizedTimelineState, context)
        if phaseKey then
            self:_SetPhase(phaseKey, "builtin_anchor", {
                duration = duration,
                eventID = spellMeta and spellMeta.eventID or nil,
                spellID = spellMeta and spellMeta.spellID or nil,
                anchorToPhase = anchor and anchor.toPhase or nil,
                timelineState = normalizedTimelineState,
                matchEvent = anchor and NormalizeMatchEvent(anchor.matchEvent) or normalizedTimelineState,
                difficultyID = self.activeDifficultyID,
            })
            return true
        end
    end

    if normalizedTimelineState ~= "added" then
        return false
    end

    if spellMeta and self.userRules then
        local phaseKey = self:_TryUserRules(spellMeta.spellID)
        if phaseKey then
            DebugPhase("user_rule_match", {
                currentPhase = self.currentPhase,
                nextPhase = phaseKey,
                eventID = spellMeta.eventID,
                spellID = spellMeta.spellID,
                timelineState = normalizedTimelineState,
                difficultyID = self.activeDifficultyID,
            })
            self:_SetPhase(phaseKey, "user_rule", {
                eventID = spellMeta.eventID,
                spellID = spellMeta.spellID,
                timelineState = normalizedTimelineState,
                difficultyID = self.activeDifficultyID,
            })
            return true
        end
        DebugPhase("user_rule_miss", {
            currentPhase = self.currentPhase,
            eventID = spellMeta.eventID,
            spellID = spellMeta.spellID,
            timelineState = normalizedTimelineState,
            difficultyID = self.activeDifficultyID,
        })
    end

    return false
end

function Detector:OnTimelineEventAdded(eventInfo)
    if not self.active or type(eventInfo) ~= "table" then
        return
    end
    if tonumber(eventInfo.source) ~= ENCOUNTER_SOURCE then
        return
    end

    local spellMeta = T.EncounterEventResolver
        and T.EncounterEventResolver.ResolveTimelineSpellMeta
        and T.EncounterEventResolver.ResolveTimelineSpellMeta(eventInfo, self.activeEncounterID)
        or nil
    local duration = tonumber(eventInfo.duration)
    local eventID = tonumber(eventInfo.id)
    local now = GetTime and tonumber(GetTime()) or 0
    local gapSincePreviousAdded = nil
    if self.lastTimelineAddedAt and self.lastTimelineAddedAt > 0 and now > 0 then
        gapSincePreviousAdded = now - self.lastTimelineAddedAt
    end
    self.lastTimelineAddedAt = now

    if eventID then
        self.timelineEventCache[eventID] = {
            source = tonumber(eventInfo.source),
            duration = duration,
            spellMeta = spellMeta,
        }
    end
    self:_RememberTimelineSignal(now, duration, spellMeta, "added", eventID)

    DebugPhase("timeline_event", {
        eventID = BuildAnchorDebugValue(eventID),
        duration = BuildAnchorDebugValue(duration),
        source = BuildAnchorDebugValue(eventInfo.source),
        currentPhase = BuildAnchorDebugValue(self.currentPhase),
        spellResolved = spellMeta and BuildAnchorDebugValue(spellMeta.spellID) or "nil",
        resolvedEventID = spellMeta and BuildAnchorDebugValue(spellMeta.eventID) or "nil",
        timelineState = "added",
        difficultyID = self.activeDifficultyID,
        gapSincePreviousAdded = BuildAnchorDebugValue(gapSincePreviousAdded),
    })

    self:_ProcessTimelineInput(duration, spellMeta, "added", {
        eventID = eventID,
        timestamp = now,
        gapSincePreviousAdded = gapSincePreviousAdded,
    })
end

function Detector:OnTimelineEventStateChanged(eventID)
    if not self.active or not C_EncounterTimeline or not C_EncounterTimeline.GetEventState then
        return
    end

    local normalizedEventID = tonumber(eventID)
    if not normalizedEventID then
        return
    end

    local state = C_EncounterTimeline.GetEventState(normalizedEventID)
    if state == EVENT_STATE_CANCELED then
        -- 取消同样可能是阶段条真正结束，不能提前丢弃。
    elseif state ~= EVENT_STATE_FINISHED then
        return
    end

    local cached = self.timelineEventCache[normalizedEventID]
    local duration = cached and tonumber(cached.duration) or nil
    local eventSource = cached and tonumber(cached.source) or nil
    local spellMeta = cached and cached.spellMeta or nil

    if not spellMeta then
        spellMeta = T.EncounterEventResolver
            and T.EncounterEventResolver.ResolveTimelineSpellMeta
            and T.EncounterEventResolver.ResolveTimelineSpellMeta(normalizedEventID, self.activeEncounterID)
            or nil
    end

    if duration == nil and C_EncounterTimeline.GetEventInfo then
        local ok, info = pcall(C_EncounterTimeline.GetEventInfo, normalizedEventID)
        if ok and type(info) == "table" then
            duration = tonumber(info.duration)
            eventSource = eventSource or tonumber(info.source)
        end
    end
    if eventSource and eventSource ~= ENCOUNTER_SOURCE then
        self.timelineEventCache[normalizedEventID] = nil
        return
    end

    local normalizedTimelineState = (state == EVENT_STATE_CANCELED) and "canceled" or "finished"
    local now = GetTime and tonumber(GetTime()) or 0
    self:_RememberTimelineSignal(now, duration, spellMeta, normalizedTimelineState, normalizedEventID)

    DebugPhase("timeline_event", {
        eventID = BuildAnchorDebugValue(normalizedEventID),
        duration = BuildAnchorDebugValue(duration),
        source = BuildAnchorDebugValue(eventSource),
        currentPhase = BuildAnchorDebugValue(self.currentPhase),
        spellResolved = spellMeta and BuildAnchorDebugValue(spellMeta.spellID) or "nil",
        resolvedEventID = spellMeta and BuildAnchorDebugValue(spellMeta.eventID) or "nil",
        timelineState = normalizedTimelineState,
        difficultyID = self.activeDifficultyID,
    })

    self:_ProcessTimelineInput(duration, spellMeta, normalizedTimelineState, {
        eventID = normalizedEventID,
        timestamp = now,
    })
    self.timelineEventCache[normalizedEventID] = nil
end

function Detector:OnExternalPhase(stage, source)
    if not self.active then
        return
    end

    if self.builtinConfig and self.builtinConfig.ignoreExternalPhase then
        DebugPhase("external_phase_ignored", {
            currentPhase = self.currentPhase,
            stage = stage,
            source = source or "external_stage",
            encounterID = self.activeEncounterID,
            difficultyID = self.activeDifficultyID,
        })
        return
    end

    local phaseKey = NormalizeStage(stage)
    if not phaseKey then
        return
    end

    local currentStage = ResolveStageNumber(self.currentPhase)
    local targetStage = ResolveStageNumber(phaseKey)
    local currentParsed = ParsePhaseKey(self.currentPhase)
    local targetParsed = ParsePhaseKey(phaseKey)
    if currentStage and targetStage and currentParsed and targetParsed then
        if ConfigUsesRoundModel(self.builtinConfig) then
            local roundIndex = currentParsed.roundIndex
            if targetStage < currentStage then
                roundIndex = roundIndex + 1
            end
            phaseKey = string.format("%sr%d", targetParsed.baseKey, roundIndex)
        end
    end

    self:_SetPhase(phaseKey, source or "external_stage", {
        stage = stage,
    })
end

function Detector:OnEngageUnitChanged()
    if not self.active then
        return
    end
    local anchors = NormalizeAnchorList(self:_GetEngageUnitAnchorGroup())
    if not anchors then
        CancelEngageUnitRetry(self)
        return
    end
    local now = GetTime and (tonumber(GetTime()) or 0) or 0
    local elapsed = now - (self.phaseSwapTime or 0)
    local retryAfter = nil
    for _, anchor in ipairs(anchors) do
        local minDur = tonumber(anchor.minPhaseDuration) or 0
        local unitMissing = anchor.unitMissing
        local missingOk = (not unitMissing) or (UnitExists and not UnitExists(unitMissing))
        local phaseDurationOk = elapsed >= minDur
        local targetPhase = self:_ResolveAnchorTarget(anchor)
        if phaseDurationOk and missingOk and targetPhase then
            self:_SetPhase(targetPhase, "engage_unit", {
                unitMissing = unitMissing,
                phaseDuration = elapsed,
            })
            return
        end
        if missingOk and targetPhase and not phaseDurationOk then
            local wait = (minDur - elapsed) + 0.05
            retryAfter = retryAfter and math.min(retryAfter, wait) or wait
        end
    end
    if retryAfter and not self.engageUnitRetryTimer and C_Timer and C_Timer.NewTimer then
        local expectedPhase = self.currentPhase
        self.engageUnitRetryTimer = C_Timer.NewTimer(retryAfter, function()
            self.engageUnitRetryTimer = nil
            if self.active and self.currentPhase == expectedPhase then
                self:OnEngageUnitChanged()
            end
        end)
        DebugPhase("engage_unit_retry_scheduled", {
            currentPhase = self.currentPhase,
            retryAfter = string.format("%.2f", retryAfter),
            phaseDuration = string.format("%.2f", elapsed),
        })
    end
end

local function TryRegisterBigWigs()
    if external.bigWigsRegistered then
        return
    end
    if type(BigWigsLoader) ~= "table" or type(BigWigsLoader.RegisterMessage) ~= "function" then
        return
    end

    BigWigsLoader.RegisterMessage(Detector, "BigWigs_SetStage", function(_, _, stage)
        SafeCall(Detector.OnExternalPhase, Detector, stage, "BigWigs")
    end)
    external.bigWigsRegistered = true
    DebugPhase("register_bigwigs", {})
end

local function TryRegisterDBM()
    if external.dbmRegistered then
        return
    end
    if type(DBM) ~= "table" or type(DBM.RegisterCallback) ~= "function" then
        return
    end

    DBM:RegisterCallback("DBM_SetStage", function(_, _, _, stage)
        SafeCall(Detector.OnExternalPhase, Detector, stage, "DBM")
    end)
    external.dbmRegistered = true
    DebugPhase("register_dbm", {})
end

local function OnDetectorEvent(_, event, arg1)
    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        SafeCall(Detector.OnTimelineEventAdded, Detector, arg1)
        return
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        SafeCall(Detector.OnTimelineEventStateChanged, Detector, arg1)
        return
    end
    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        SafeCall(Detector.OnEngageUnitChanged, Detector)
        return
    end

    TryRegisterBigWigs()
    TryRegisterDBM()
end

function Detector:EnsureEventFrame()
    if not timelineFrame then
        timelineFrame = CreateFrame("Frame")
        timelineFrame:SetScript("OnEvent", OnDetectorEvent)
    end
    timelineFrame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
    timelineFrame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
    timelineFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    timelineFrame:RegisterEvent("ADDON_LOADED")
    TryRegisterBigWigs()
    TryRegisterDBM()
end

function Detector:DisableEventFrame()
    if timelineFrame then
        timelineFrame:UnregisterAllEvents()
    end
end

end)
