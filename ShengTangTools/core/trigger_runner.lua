local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

-- STN 技能触发调度器：统一处理暴雪原生 Encounter Timeline / EncounterWarnings，
-- 并在大秘境链路中消费 canonical spellID、内嵌模板文本与轻量修轴动作。
local Runner = {}
T.TriggerRunner = Runner

local ENCOUNTER_SOURCE = (Enum and Enum.EncounterTimelineEventSource and Enum.EncounterTimelineEventSource.Encounter) or 0
local EVENT_STATE_FINISHED = (Enum and Enum.EncounterTimelineEventState and Enum.EncounterTimelineEventState.Finished) or 2
local EVENT_STATE_CANCELED = (Enum and Enum.EncounterTimelineEventState and Enum.EncounterTimelineEventState.Canceled) or 3
local DUPLICATE_WINDOW_SEC = 1.0
local RING_BUFFER_SIZE = 50
local RETIME_ACTION_RESTART = "restart"
local RETIME_ACTION_PAUSE = "pause"
local RETIME_ACTION_RESUME = "resume"
local RETIME_ACTION_REPLACE_PHASE = "replace_phase"
local SOURCE_TIMELINE_EVENT = "TimelineEvent"
local SOURCE_ENCOUNTER_WARNING = "EncounterWarning"

local GetNow
local NormalizeEventID

local runtime = {
    active = false,
    isTest = false,
    parsed = nil,
    encounterID = 0,
    paused = false,
    phaseKey = nil,
    eventIDToInfo = {},
    occurrenceBySpell = {},
    occurrenceByEvent = {},
    warningOccurrenceBySpell = {},
    recentSpokenAt = {},
    scheduledTimers = {},
    allowedCanonicalSpells = {},
    allowedObservedSpells = {},
    allowedEventIDs = {},
}

local triggerLog = {}
local triggerLogIndex = 0
local triggerLogCount = 0

local function LogTriggerEvent(stage, fields)
    local now = GetTime and tonumber(GetTime()) or 0
    local entry = {
        stage = tostring(stage or "unknown"),
        timestamp = now or 0,
    }

    for key, value in pairs(fields or {}) do
        entry[key] = value
    end

    triggerLogIndex = (triggerLogIndex % RING_BUFFER_SIZE) + 1
    triggerLog[triggerLogIndex] = entry
    triggerLogCount = math.min(triggerLogCount + 1, RING_BUFFER_SIZE)
end

local function ClearTriggerLog()
    wipe(triggerLog)
    triggerLogIndex = 0
    triggerLogCount = 0
end

local function CancelScheduledTimer(eventID, reason, stageOverride)
    local normalizedEventID = tonumber(eventID)
    if not normalizedEventID then
        return false
    end

    local timer = runtime.scheduledTimers[normalizedEventID]
    if not timer then
        return false
    end

    if timer.Cancel then
        timer:Cancel()
    end
    runtime.scheduledTimers[normalizedEventID] = nil

    local info = runtime.eventIDToInfo[normalizedEventID]
    LogTriggerEvent(stageOverride or "canceled", {
        eventID = normalizedEventID,
        spellID = info and info.spellID or nil,
        occurrence = info and info.occurrence or nil,
        effectiveAdvance = info and info.effectiveAdvance or nil,
        advanceSource = info and info.advanceSource or nil,
        reason = reason,
    })
    return true
end

local function CancelAllScheduledTimers(reason, stageOverride)
    local eventIDs = {}
    for eventID in pairs(runtime.scheduledTimers) do
        eventIDs[#eventIDs + 1] = eventID
    end
    for _, eventID in ipairs(eventIDs) do
        CancelScheduledTimer(eventID, reason, stageOverride)
    end
end

local function ResetRuntime()
    CancelAllScheduledTimers("reset_runtime", "canceled")
    runtime.active = false
    runtime.isTest = false
    runtime.parsed = nil
    runtime.encounterID = 0
    runtime.paused = false
    runtime.phaseKey = nil
    wipe(runtime.eventIDToInfo)
    wipe(runtime.occurrenceBySpell)
    wipe(runtime.occurrenceByEvent)
    wipe(runtime.warningOccurrenceBySpell)
    wipe(runtime.recentSpokenAt)
    wipe(runtime.scheduledTimers)
    wipe(runtime.allowedCanonicalSpells)
    wipe(runtime.allowedObservedSpells)
    wipe(runtime.allowedEventIDs)
end

local function GetSpellName(spellID, fallbackName)
    if T.EncounterEventResolver and T.EncounterEventResolver.GetSpellName then
        return T.EncounterEventResolver.GetSpellName(spellID, fallbackName)
    end

    local name = nil
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    if type(name) == "string" and name ~= "" then
        return name
    end
    name = tostring(fallbackName or "")
    if name ~= "" then
        return name
    end
    return tostring(spellID or "")
end

NormalizeEventID = function(eventID)
    if T.EncounterEventResolver and T.EncounterEventResolver.NormalizeEventID then
        return T.EncounterEventResolver.NormalizeEventID(eventID)
    end
    return tonumber(eventID)
end

GetNow = function()
    if GetTime then
        return tonumber(GetTime()) or 0
    end
    return 0
end

local function GetSelectedEncounterID()
    local bossKeyText = T.Note and T.Note.GetCurrentBossKey and T.Note:GetCurrentBossKey() or nil
    local bossKey = bossKeyText and T.ParseSemanticBossKeyText and T.ParseSemanticBossKeyText(bossKeyText) or nil
    if type(bossKey) == "table" then
        return tonumber(bossKey.encounterID) or 0
    end
    return 0
end

local function DebugTriggerFlow(stage, fields)
    if not (C and C.DB and C.DB.debugMode) then
        return
    end

    local parts = {}
    for key, value in pairs(fields or {}) do
        if value ~= nil and value ~= "" then
            parts[#parts + 1] = string.format("%s=%s", tostring(key), tostring(value))
        end
    end
    table.sort(parts)
    parts[#parts + 1] = string.format("stage=%s", tostring(stage or "trigger"))
    T.debug(table.concat(parts, " | "))
end

local function BuildAllowedSpellSets(encounterID, parsed)
    local canonical = {}
    local observed = {}
    local allowedEvents = {}

    if T.SemanticTimeline and T.SemanticTimeline.GetEncounterSpellCatalog and encounterID > 0 then
        local catalog = T.SemanticTimeline:GetEncounterSpellCatalog({ encounterID = encounterID }) or {}
        for _, item in ipairs(catalog) do
            local spellID = tonumber(item and item.spellID)
            if spellID and spellID > 0 then
                canonical[spellID] = true
                observed[spellID] = true
            end
        end
    end

    local encounterMap = T.SemanticEncounterEventMapS14 and T.SemanticEncounterEventMapS14[encounterID] or nil
    if type(encounterMap) == "table" then
        for canonicalSpellID, entry in pairs(encounterMap) do
            local normalizedCanonicalSpellID = tonumber(canonicalSpellID)
            if normalizedCanonicalSpellID and normalizedCanonicalSpellID > 0 then
                canonical[normalizedCanonicalSpellID] = true
                observed[normalizedCanonicalSpellID] = true
            end

            for _, observedSpellID in ipairs(entry.triggerSpellIDs or {}) do
                local normalizedObservedSpellID = tonumber(observedSpellID)
                if normalizedObservedSpellID and normalizedObservedSpellID > 0 then
                    observed[normalizedObservedSpellID] = true
                end
            end

            for _, eid in ipairs(entry.encounterEventIDs or {}) do
                local normalizedEID = tonumber(eid)
                if normalizedEID and normalizedEID > 0 then
                    allowedEvents[normalizedEID] = true
                end
            end
        end
    end

    for _, rule in ipairs(parsed and parsed.rules or {}) do
        if rule.triggerKind == "event" then
            local eid = tonumber(rule.eventID)
            if eid and eid > 0 then
                allowedEvents[eid] = true
            end
        else
            local spellID = tonumber(rule and rule.spellID)
            if spellID and spellID > 0 then
                canonical[spellID] = true
                observed[spellID] = true
            end
        end
    end

    return canonical, observed, allowedEvents
end

local function IsAllowedEventID(eventID)
    local normalizedEventID = tonumber(eventID)
    if not normalizedEventID or normalizedEventID <= 0 then
        return false
    end
    return runtime.allowedEventIDs[normalizedEventID] == true
end

local function IsAllowedObservedSpell(spellID)
    local normalizedSpellID = tonumber(spellID)
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return false
    end
    return runtime.allowedObservedSpells[normalizedSpellID] == true
end

local function IsAllowedCanonicalSpell(spellID)
    local normalizedSpellID = tonumber(spellID)
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return false
    end
    return runtime.allowedCanonicalSpells[normalizedSpellID] == true
end

local function IsDuplicateWindowActive(spellID)
    local normalizedSpellID = tonumber(spellID)
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return false
    end

    local now = GetNow()
    local last = runtime.recentSpokenAt[normalizedSpellID]
    return type(last) == "number" and (now - last) <= DUPLICATE_WINDOW_SEC
end

local function ShouldSuppressDuplicate(spellID)
    local normalizedSpellID = tonumber(spellID)
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return false
    end

    if IsDuplicateWindowActive(normalizedSpellID) then
        return true
    end

    runtime.recentSpokenAt[normalizedSpellID] = GetNow()
    return false
end

local function FindPendingTimelineInfo(spellID)
    local normalizedSpellID = tonumber(spellID)
    local best = nil
    for _, info in pairs(runtime.eventIDToInfo) do
        if info and info.spellID == normalizedSpellID and info.spoken ~= true then
            if not best then
                best = info
            elseif (tonumber(info.occurrence) or 0) < (tonumber(best.occurrence) or 0) then
                best = info
            elseif (tonumber(info.occurrence) or 0) == (tonumber(best.occurrence) or 0) and (tonumber(info.addedAt) or 0) < (tonumber(best.addedAt) or 0) then
                best = info
            end
        end
    end
    return best
end

local function ResolveTimelineSpellMeta(eventInfo)
    local resolver = T.EncounterEventResolver
    if resolver and resolver.ResolveTimelineSpellMeta then
        return resolver.ResolveTimelineSpellMeta(eventInfo, runtime.encounterID)
    end
    return nil
end

local function ResolveWarningSpellMeta(encounterWarningInfo)
    local resolver = T.EncounterEventResolver
    if resolver and resolver.ResolveWarningSpellMeta then
        return resolver.ResolveWarningSpellMeta(encounterWarningInfo, runtime.encounterID)
    end
    return nil
end

local function NormalizeRetimeAction(action)
    local value = tostring(action or ""):lower()
    if value == RETIME_ACTION_RESTART or value == RETIME_ACTION_PAUSE or value == RETIME_ACTION_RESUME or value == RETIME_ACTION_REPLACE_PHASE then
        return value
    end
    return nil
end

local function GetEmbeddedRetimeRule(spellID)
    local action = T.GetEmbeddedRetimeAction and T.GetEmbeddedRetimeAction(spellID, {
        encounterID = runtime.encounterID,
        phaseKey = runtime.phaseKey,
    }) or nil
    if type(action) ~= "table" then
        return nil
    end

    local normalizedAction = NormalizeRetimeAction(action.action)
    if not normalizedAction then
        return nil
    end

    return {
        action = normalizedAction,
        phase = action.phase ~= nil and tostring(action.phase) or nil,
    }
end

local function CanProcessWhilePaused(retimeRule)
    if runtime.paused ~= true then
        return true
    end
    if type(retimeRule) ~= "table" then
        return false
    end
    local action = NormalizeRetimeAction(retimeRule.action)
    return action == RETIME_ACTION_RESUME or action == RETIME_ACTION_RESTART or action == RETIME_ACTION_REPLACE_PHASE
end

local function ResetRuntimeTracking(preserveSpellID)
    CancelAllScheduledTimers("reset_tracking", "retime")
    wipe(runtime.eventIDToInfo)
    wipe(runtime.occurrenceBySpell)
    wipe(runtime.occurrenceByEvent)
    wipe(runtime.warningOccurrenceBySpell)
    wipe(runtime.recentSpokenAt)
    wipe(runtime.scheduledTimers)

    local normalizedSpellID = tonumber(preserveSpellID)
    if normalizedSpellID and normalizedSpellID > 0 then
        runtime.recentSpokenAt[normalizedSpellID] = GetNow()
    end
end

local function ApplyRetimeRule(spellID, retimeRule, sourceTag)
    if type(retimeRule) ~= "table" then
        return
    end

    local normalizedSpellID = tonumber(spellID) or 0
    local action = NormalizeRetimeAction(retimeRule.action)
    if not action then
        return
    end

    if action == RETIME_ACTION_RESTART then
        runtime.paused = false
        ResetRuntimeTracking(normalizedSpellID)
    elseif action == RETIME_ACTION_PAUSE then
        runtime.paused = true
    elseif action == RETIME_ACTION_RESUME then
        runtime.paused = false
    elseif action == RETIME_ACTION_REPLACE_PHASE then
        runtime.phaseKey = retimeRule.phase or tostring(normalizedSpellID)
        runtime.paused = false
        ResetRuntimeTracking(normalizedSpellID)
    end

    DebugTriggerFlow("retime", {
        source = sourceTag,
        encounterID = runtime.encounterID,
        canonicalSpellID = normalizedSpellID,
        action = action,
        phase = runtime.phaseKey,
        paused = runtime.paused and "true" or "false",
    })
    LogTriggerEvent("retime", {
        source = sourceTag,
        spellID = normalizedSpellID,
        action = action,
        phase = runtime.phaseKey,
        paused = runtime.paused == true,
    })
end

local function GetGlobalTTSAdvance()
    return math.max(0, tonumber(C and C.DB and C.DB.ttsAdvanceTime) or 0)
end

local function ResolveScheduledAdvance(parsed, spellID, occurrence)
    local explicitRule = T.TriggerSyntax.ResolveRule(parsed, spellID, occurrence, "advance")
    if explicitRule and tonumber(explicitRule.advance) and tonumber(explicitRule.advance) > 0 then
        return explicitRule, math.max(0, tonumber(explicitRule.advance) or 0), "rule", "advance"
    end

    local globalAdvance = GetGlobalTTSAdvance()
    if globalAdvance <= 0 then
        return nil, 0, nil, nil
    end

    local normalRule = T.TriggerSyntax.ResolveRule(parsed, spellID, occurrence, "normal")
    if not normalRule then
        return nil, 0, nil, nil
    end
    if normalRule.suppressGlobalAdvance == true then
        return nil, 0, nil, nil
    end

    return normalRule, globalAdvance, "global", "normal"
end

local function SpeakRule(spellID, occurrence, spellName, runtimeInfo, context)
    if not runtime.active or not runtime.parsed then
        return false
    end

    local normalizedSpellID = tonumber(spellID)
    local normalizedResolveMode = context and context.resolveMode == "advance" and "advance" or "normal"
    local shouldApplyRetime = normalizedResolveMode == "normal"
    if context and context.applyRetime == false then
        shouldApplyRetime = false
    end
    local shouldMarkSpokenOnSkip = normalizedResolveMode == "normal"
    if context and context.markSpokenOnSkip == false then
        shouldMarkSpokenOnSkip = false
    end
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return false
    end

    local retimeRule = shouldApplyRetime and GetEmbeddedRetimeRule(normalizedSpellID) or nil
    if not CanProcessWhilePaused(retimeRule) then
        if runtimeInfo and shouldMarkSpokenOnSkip then
            runtimeInfo.spoken = true
        end
        DebugTriggerFlow("skip_paused", {
            source = context and context.source or "unknown",
            encounterID = runtime.encounterID,
            canonicalSpellID = normalizedSpellID,
            action = retimeRule and retimeRule.action or nil,
            phase = runtime.phaseKey,
        })
        LogTriggerEvent("skip_paused", {
            source = context and context.source or "unknown",
            eventID = context and context.eventID or nil,
            spellID = normalizedSpellID,
            occurrence = occurrence,
            resolveMode = normalizedResolveMode,
        })
        return false
    end

    local bypassDuplicateSuppression = normalizedResolveMode == "normal"
        and runtimeInfo
        and runtimeInfo.advanceSpoken == true
        and context
        and context.source == SOURCE_TIMELINE_EVENT
        and context.eventID ~= nil

    if not bypassDuplicateSuppression and ShouldSuppressDuplicate(normalizedSpellID) then
        if runtimeInfo and shouldMarkSpokenOnSkip then
            runtimeInfo.spoken = true
        end
        DebugTriggerFlow("skip_duplicate", {
            source = context and context.source or "unknown",
            encounterID = runtime.encounterID,
            canonicalSpellID = normalizedSpellID,
            occurrence = occurrence,
        })
        LogTriggerEvent("skip_duplicate", {
            source = context and context.source or "unknown",
            eventID = context and context.eventID or nil,
            spellID = normalizedSpellID,
            occurrence = occurrence,
            resolveMode = normalizedResolveMode,
        })
        return false
    end

    local rule, matchKind = T.TriggerSyntax.ResolveRule(runtime.parsed, normalizedSpellID, occurrence, normalizedResolveMode)
    local resolvedSpellName = GetSpellName(normalizedSpellID, spellName)
    local embeddedText = T.GetEmbeddedTemplateText and T.GetEmbeddedTemplateText(normalizedSpellID, {
        encounterID = runtime.encounterID,
        phaseKey = runtime.phaseKey,
    }) or ""
    if not rule then
        if runtimeInfo and shouldMarkSpokenOnSkip then
            runtimeInfo.spoken = true
        end
        DebugTriggerFlow("skip_rule_unmatched", {
            source = context and context.source or "unknown",
            eventID = context and context.eventID or nil,
            observedSpellID = context and context.observedSpellID or nil,
            canonicalSpellID = normalizedSpellID,
            occurrence = occurrence,
            resolveMode = normalizedResolveMode,
            phase = runtime.phaseKey,
        })
        LogTriggerEvent("skip_rule_unmatched", {
            source = context and context.source or "unknown",
            eventID = context and context.eventID or nil,
            spellID = normalizedSpellID,
            occurrence = occurrence,
            resolveMode = normalizedResolveMode,
        })
        return false
    end

    local speakText = T.TriggerSyntax.BuildSpeakText(rule, resolvedSpellName)
    if speakText == "" then
        if runtimeInfo and shouldMarkSpokenOnSkip then
            runtimeInfo.spoken = true
        end
        DebugTriggerFlow("skip_audience", {
            source = context and context.source or "unknown",
            eventID = context and context.eventID or nil,
            observedSpellID = context and context.observedSpellID or nil,
            canonicalSpellID = normalizedSpellID,
            occurrence = occurrence,
            match = matchKind,
            phase = runtime.phaseKey,
        })
        LogTriggerEvent("skip_audience", {
            source = context and context.source or "unknown",
            eventID = context and context.eventID or nil,
            spellID = normalizedSpellID,
            occurrence = occurrence,
            match = matchKind,
            resolveMode = normalizedResolveMode,
        })
        return false
    end
    if speakText ~= "" then
        T.PlayTTS(speakText)
    end

    local logStage = context and context.logStage or "speak"
    DebugTriggerFlow(logStage, {
        source = context and context.source or "unknown",
        eventID = context and context.eventID or nil,
        observedSpellID = context and context.observedSpellID or nil,
        canonicalSpellID = normalizedSpellID,
        occurrence = occurrence,
        match = matchKind,
        resolveMode = normalizedResolveMode,
        templateText = embeddedText,
        action = shouldApplyRetime and retimeRule and retimeRule.action or nil,
        finalText = speakText,
        phase = runtime.phaseKey,
    })
    LogTriggerEvent(logStage, {
        source = context and context.source or "unknown",
        eventID = context and context.eventID or nil,
        spellID = normalizedSpellID,
        occurrence = occurrence,
        match = matchKind,
        resolveMode = normalizedResolveMode,
        text = speakText,
        effectiveAdvance = context and context.effectiveAdvance or nil,
        advanceSource = context and context.advanceSource or nil,
    })

    if runtimeInfo then
        if normalizedResolveMode == "advance" then
            runtimeInfo.advanceSpoken = true
        else
            runtimeInfo.spoken = true
        end
    end

    if shouldApplyRetime then
        ApplyRetimeRule(normalizedSpellID, retimeRule, context and context.source or "unknown")
    end
    return true
end

-- event 规则的解析与播报统一走这里，避免 ADDED / FINISHED 两处各写一份同义逻辑。
local function SpeakEventRule(eventRuleID, runtimeInfo, context)
    if not runtime.active or not runtime.parsed then
        return false
    end

    local normalizedEventID = tonumber(eventRuleID)
    if not normalizedEventID or normalizedEventID <= 0 then
        if runtimeInfo and context and context.markSpoken then
            runtimeInfo.spoken = true
        end
        return false
    end
    if not (T.TriggerSyntax and T.TriggerSyntax.ResolveEventRule) then
        if runtimeInfo and context and context.markSpoken then
            runtimeInfo.spoken = true
        end
        return false
    end

    local eventOccurrence = runtimeInfo and tonumber(runtimeInfo.eventOccurrence) or nil
    if not eventOccurrence or eventOccurrence <= 0 then
        eventOccurrence = runtime.occurrenceByEvent[normalizedEventID] or 0
    end

    local eventRule, eventMatchKind = T.TriggerSyntax.ResolveEventRule(runtime.parsed, normalizedEventID, eventOccurrence)
    if not eventRule then
        DebugTriggerFlow("skip_event_rule_unmatched", {
            source = context and context.source or "unknown",
            eventID = normalizedEventID,
            eventOccurrence = eventOccurrence,
            stage = context and context.stage or nil,
            phase = runtime.phaseKey,
        })
        if runtimeInfo and context and context.markSpoken then
            runtimeInfo.spoken = true
        end
        LogTriggerEvent("skip_event_rule_unmatched", {
            source = context and context.source or "unknown",
            eventID = normalizedEventID,
            occurrence = eventOccurrence,
            stage = context and context.stage or nil,
        })
        return false
    end

    local spellName = runtimeInfo and runtimeInfo.spellID and GetSpellName(runtimeInfo.spellID) or ""
    local speakText = T.TriggerSyntax.BuildSpeakText(eventRule, spellName)
    if speakText == "" then
        DebugTriggerFlow("skip_event_rule_empty", {
            source = context and context.source or "unknown",
            eventID = normalizedEventID,
            eventOccurrence = eventOccurrence,
            match = eventMatchKind,
            stage = context and context.stage or nil,
            phase = runtime.phaseKey,
        })
        if runtimeInfo and context and context.markSpoken then
            runtimeInfo.spoken = true
        end
        LogTriggerEvent("skip_event_rule_empty", {
            source = context and context.source or "unknown",
            eventID = normalizedEventID,
            occurrence = eventOccurrence,
            match = eventMatchKind,
            stage = context and context.stage or nil,
        })
        return false
    end

    T.PlayTTS(speakText)
    if runtimeInfo then
        runtimeInfo.spoken = true
    end
    DebugTriggerFlow("speak_event_rule", {
        source = context and context.source or "unknown",
        eventID = normalizedEventID,
        eventOccurrence = eventOccurrence,
        match = eventMatchKind,
        finalText = speakText,
        stage = context and context.stage or nil,
        phase = runtime.phaseKey,
    })
    LogTriggerEvent("speak_event_rule", {
        source = context and context.source or "unknown",
        eventID = normalizedEventID,
        occurrence = eventOccurrence,
        match = eventMatchKind,
        stage = context and context.stage or nil,
        text = speakText,
    })
    return true
end

function Runner:IsRunning()
    return runtime.active == true
end

function Runner:ClearLog()
    ClearTriggerLog()
end

function Runner:DumpLog()
    if triggerLogCount <= 0 then
        T.msg(L["触发日志为空"] or "触发日志为空")
        return
    end

    local entries = {}
    local startIndex = triggerLogIndex - triggerLogCount + 1
    for offset = 0, triggerLogCount - 1 do
        local index = ((startIndex + offset - 1) % RING_BUFFER_SIZE) + 1
        entries[#entries + 1] = triggerLog[index]
    end

    local baseTimestamp = entries[1] and tonumber(entries[1].timestamp) or 0
    T.msg("=== " .. (L["触发日志"] or "触发日志") .. " ===")
    for _, entry in ipairs(entries) do
        local parts = {
            string.format("[+%.1fs]", math.max(0, (tonumber(entry.timestamp) or 0) - baseTimestamp)),
            tostring(entry.stage or "unknown"),
        }
        if entry.spellID then
            parts[#parts + 1] = string.format("spell:%d", tonumber(entry.spellID) or 0)
        end
        if entry.eventID then
            parts[#parts + 1] = string.format("event:%d", tonumber(entry.eventID) or 0)
        end
        if entry.occurrence then
            parts[#parts + 1] = string.format("#%d", tonumber(entry.occurrence) or 0)
        end
        if entry.duration ~= nil then
            parts[#parts + 1] = string.format("dur=%.1f", tonumber(entry.duration) or 0)
        end
        if entry.effectiveAdvance ~= nil then
            parts[#parts + 1] = string.format("adv=%s", tostring(entry.effectiveAdvance))
        elseif entry.advance ~= nil then
            parts[#parts + 1] = string.format("adv=%s", tostring(entry.advance))
        end
        if entry.advanceSource then
            parts[#parts + 1] = string.format("src=%s", tostring(entry.advanceSource))
        end
        if entry.delay ~= nil then
            parts[#parts + 1] = string.format("delay=%.1f", tonumber(entry.delay) or 0)
        end
        if entry.resolveMode then
            parts[#parts + 1] = tostring(entry.resolveMode)
        end
        if entry.reason then
            parts[#parts + 1] = string.format("reason=%s", tostring(entry.reason))
        end
        if entry.text then
            parts[#parts + 1] = string.format("text=%s", tostring(entry.text))
        end
        T.msg(table.concat(parts, " "))
    end
end

local eventFrame

local function EnsureEventFrame()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
                Runner:OnTimelineEventAdded(...)
            elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
                Runner:OnTimelineEventStateChanged(...)
            elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
                Runner:OnTimelineEventRemoved(...)
            elseif event == "ENCOUNTER_WARNING" then
                Runner:OnEncounterWarning(...)
            end
        end)
    end
    eventFrame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
    eventFrame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
    eventFrame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED")
    eventFrame:RegisterEvent("ENCOUNTER_WARNING")
end

local function DisableEventFrame()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

function Runner:StartFromText(text, isTest)
    if not (T.TriggerSyntax and T.TriggerSyntax.IsTriggerText and T.TriggerSyntax.ParseTriggerText) then
        return false
    end

    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text or "") or nil
    if not template or template.bodyKind ~= "trigger" or template.isValid ~= true then
        if not template or template.hasBlocks ~= true then
            T.msg(L["仅支持结构化模板"] or "仅支持结构化模板")
        elseif template.errors and #template.errors > 0 then
            T.msg(string.format("%s %d", L["模板解析错误"] or "模板解析错误", #template.errors))
        end
        return false
    end

    local parsed = T.TriggerSyntax.ParseTriggerText(text)
    if not parsed or not parsed.templateInfo or parsed.templateInfo.isValid ~= true then
        return false
    end
    local encounterID = GetSelectedEncounterID()
    local allowedCanonicalSpells, allowedObservedSpells, allowedEventIDs = BuildAllowedSpellSets(encounterID, parsed)

    CancelAllScheduledTimers("start_reinit", "canceled")
    EnsureEventFrame()
    runtime.active = true
    runtime.isTest = isTest == true
    runtime.parsed = parsed
    runtime.encounterID = encounterID
    runtime.paused = false
    runtime.phaseKey = nil
    wipe(runtime.eventIDToInfo)
    wipe(runtime.occurrenceBySpell)
    wipe(runtime.occurrenceByEvent)
    wipe(runtime.warningOccurrenceBySpell)
    wipe(runtime.recentSpokenAt)
    wipe(runtime.scheduledTimers)
    wipe(runtime.allowedCanonicalSpells)
    wipe(runtime.allowedObservedSpells)
    wipe(runtime.allowedEventIDs)

    for spellID in pairs(allowedCanonicalSpells) do
        runtime.allowedCanonicalSpells[spellID] = true
    end
    for spellID in pairs(allowedObservedSpells) do
        runtime.allowedObservedSpells[spellID] = true
    end
    for eid in pairs(allowedEventIDs) do
        runtime.allowedEventIDs[eid] = true
    end

    if parsed and parsed.errors and #parsed.errors > 0 then
        T.msg(string.format("%s %d", L["触发规则解析错误"] or "触发规则解析错误", #parsed.errors))
    end

    DebugTriggerFlow("start", {
        source = C and C.DB and C.DB.dataSource or "unknown",
        encounterID = encounterID,
        rules = parsed and parsed.rules and #parsed.rules or 0,
        errors = parsed and parsed.errors and #parsed.errors or 0,
        isTest = runtime.isTest and "true" or "false",
    })
    LogTriggerEvent("start", {
        encounterID = encounterID,
        isTest = runtime.isTest == true,
        rules = parsed and parsed.rules and #parsed.rules or 0,
        errors = parsed and parsed.errors and #parsed.errors or 0,
    })

    return true
end

function Runner:StartFromCurrent(isTest, opts)
    local options = opts or {}
    options.silent = true
    local text = T.GetTimelineSourceText and T.GetTimelineSourceText(options) or nil
    if not text or text == "" then
        return false
    end
    return self:StartFromText(text, isTest)
end

function Runner:Stop()
    if runtime.active then
        T.ClearTTSQueue()
    end
    DisableEventFrame()
    ResetRuntime()
end

function Runner:StartTest()
    local text = T.GetTimelineSourceText and T.GetTimelineSourceText({ silent = true }) or nil
    if not text or text == "" then
        return false
    end
    if not (T.TriggerSyntax and T.TriggerSyntax.IsTriggerText and T.TriggerSyntax.ParseTriggerText) then
        return false
    end
    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text or "") or nil
    if not template or template.bodyKind ~= "trigger" or template.isValid ~= true then
        if not template or template.hasBlocks ~= true then
            T.msg(L["仅支持结构化模板"] or "仅支持结构化模板")
        elseif template.errors and #template.errors > 0 then
            T.msg(string.format("%s %d", L["模板解析错误"] or "模板解析错误", #template.errors))
        end
        return false
    end

    local parsed = T.TriggerSyntax.ParseTriggerText(text)
    local spoken = 0
    for _, rule in ipairs(parsed.rules or {}) do
        if not rule.occurrence then
            local spellName = rule.spellID and GetSpellName(rule.spellID) or ""
            local speakText = T.TriggerSyntax.BuildSpeakText(rule, spellName)
            -- 测试模式要求优先给出可听反馈，纯 spell 规则没有 payload 时退回技能名。
            if speakText == "" and spellName ~= "" then
                speakText = spellName
            end
            if speakText ~= "" then
                T.PlayTTS(speakText)
                spoken = spoken + 1
            end
            if spoken >= 3 then
                break
            end
        end
    end

    if spoken == 0 then
        T.msg(L["没有可测试的触发规则"] or "没有可测试的触发规则")
        return false
    end
    return true
end

function Runner:OnTimelineEventAdded(eventInfo)
    if not runtime.active or type(eventInfo) ~= "table" then
        return
    end
    if tonumber(eventInfo.source) ~= ENCOUNTER_SOURCE then
        return
    end

    local rawEventID = NormalizeEventID(type(eventInfo) == "table" and eventInfo.id or eventInfo)

    local spellMeta = ResolveTimelineSpellMeta(eventInfo)
    local spellAllowed = spellMeta and (IsAllowedObservedSpell(spellMeta.observedSpellID) or IsAllowedCanonicalSpell(spellMeta.spellID))
    local eventAllowed = rawEventID and IsAllowedEventID(rawEventID)

    if not spellAllowed and not eventAllowed then
        return
    end

    -- spell 路径（现有逻辑）
    if spellMeta and spellAllowed then
        local retimeRule = GetEmbeddedRetimeRule(spellMeta.spellID)
        if not CanProcessWhilePaused(retimeRule) then
            DebugTriggerFlow("skip_add_paused", {
                source = SOURCE_TIMELINE_EVENT,
                eventID = spellMeta.eventID,
                observedSpellID = spellMeta.observedSpellID,
                canonicalSpellID = spellMeta.spellID,
                phase = runtime.phaseKey,
            })
            return
        end

        local occurrence = (runtime.occurrenceBySpell[spellMeta.spellID] or 0) + 1
        runtime.occurrenceBySpell[spellMeta.spellID] = occurrence
        CancelScheduledTimer(spellMeta.eventID, "event_readded", "canceled")
        runtime.eventIDToInfo[spellMeta.eventID] = {
            spellID = spellMeta.spellID,
            occurrence = occurrence,
            spoken = false,
            advanceSpoken = false,
            observedSpellID = spellMeta.observedSpellID,
            effectiveAdvance = nil,
            advanceSource = nil,
            addedAt = GetNow(),
        }
        local info = runtime.eventIDToInfo[spellMeta.eventID]
        local duration = tonumber(eventInfo.duration)
        DebugTriggerFlow("event_added", {
            source = SOURCE_TIMELINE_EVENT,
            eventID = spellMeta.eventID,
            observedSpellID = spellMeta.observedSpellID,
            canonicalSpellID = spellMeta.spellID,
            occurrence = occurrence,
            duration = duration,
            phase = runtime.phaseKey,
        })
        LogTriggerEvent("event_added", {
            source = SOURCE_TIMELINE_EVENT,
            eventID = spellMeta.eventID,
            spellID = spellMeta.spellID,
            occurrence = occurrence,
            duration = duration,
        })

        local scheduledRule, effectiveAdvance, advanceSource, resolveMode = ResolveScheduledAdvance(runtime.parsed, spellMeta.spellID, occurrence)
        if scheduledRule and effectiveAdvance > 0 then
            info.effectiveAdvance = effectiveAdvance
            info.advanceSource = advanceSource
            if not duration then
                LogTriggerEvent("skip_advance_duration", {
                    source = SOURCE_TIMELINE_EVENT,
                    eventID = spellMeta.eventID,
                    spellID = spellMeta.spellID,
                    occurrence = occurrence,
                    effectiveAdvance = effectiveAdvance,
                    advanceSource = advanceSource,
                    reason = "duration_unavailable",
                })
            else
                local delay = math.max(0, duration - effectiveAdvance)
                if delay <= 0 then
                    SpeakRule(info.spellID, info.occurrence, nil, info, {
                        source = SOURCE_TIMELINE_EVENT,
                        eventID = spellMeta.eventID,
                        observedSpellID = spellMeta.observedSpellID,
                        resolveMode = resolveMode,
                        markSpokenOnSkip = resolveMode == "advance" and false or nil,
                        applyRetime = resolveMode == "advance" and false or nil,
                        effectiveAdvance = effectiveAdvance,
                        advanceSource = advanceSource,
                        logStage = "advance_fired",
                    })
                else
                    runtime.scheduledTimers[spellMeta.eventID] = C_Timer.NewTimer(delay, function()
                        runtime.scheduledTimers[spellMeta.eventID] = nil
                        local pending = runtime.eventIDToInfo[spellMeta.eventID]
                        if not pending or pending.advanceSpoken == true then
                            LogTriggerEvent("skip_advance_missing", {
                                source = SOURCE_TIMELINE_EVENT,
                                eventID = spellMeta.eventID,
                                spellID = spellMeta.spellID,
                                occurrence = occurrence,
                                effectiveAdvance = effectiveAdvance,
                                advanceSource = advanceSource,
                                reason = pending and "advance_already_spoken" or "event_missing",
                            })
                            return
                        end
                        SpeakRule(pending.spellID, pending.occurrence, nil, pending, {
                            source = SOURCE_TIMELINE_EVENT,
                            eventID = spellMeta.eventID,
                            observedSpellID = pending.observedSpellID,
                            resolveMode = resolveMode,
                            markSpokenOnSkip = resolveMode == "advance" and false or nil,
                            applyRetime = resolveMode == "advance" and false or nil,
                            effectiveAdvance = pending.effectiveAdvance or effectiveAdvance,
                            advanceSource = pending.advanceSource or advanceSource,
                            logStage = "advance_fired",
                        })
                    end)
                    LogTriggerEvent("advance_scheduled", {
                        source = SOURCE_TIMELINE_EVENT,
                        eventID = spellMeta.eventID,
                        spellID = spellMeta.spellID,
                        occurrence = occurrence,
                        duration = duration,
                        effectiveAdvance = effectiveAdvance,
                        advanceSource = advanceSource,
                        delay = delay,
                    })
                end
            end
        end
    end

    -- event 规则路径：直接按 eventID 匹配 {event:xx} 规则
    if rawEventID and eventAllowed then
        local eventOccurrence = (runtime.occurrenceByEvent[rawEventID] or 0) + 1
        runtime.occurrenceByEvent[rawEventID] = eventOccurrence
        local existing = runtime.eventIDToInfo[rawEventID]
        if not existing then
            -- spellMeta 可能有也可能没有，如果有就复用 spellID 做显示
            local fallbackSpellID = spellMeta and spellMeta.spellID or nil
            runtime.eventIDToInfo[rawEventID] = {
                spellID = fallbackSpellID,
                eventRuleID = rawEventID,
                eventOccurrence = eventOccurrence,
                spoken = false,
                addedAt = GetNow(),
            }
        else
            existing.eventRuleID = rawEventID
            existing.eventOccurrence = eventOccurrence
            existing.addedAt = existing.addedAt or GetNow()
        end

        -- event 规则的价值是“事件出现就预警”，因此在 ADDED 阶段立即尝试播报。
        local spoke = SpeakEventRule(rawEventID, runtime.eventIDToInfo[rawEventID], {
            source = SOURCE_TIMELINE_EVENT,
            stage = "added",
        })
        DebugTriggerFlow("event_rule_added", {
            source = SOURCE_TIMELINE_EVENT,
            eventID = rawEventID,
            eventOccurrence = eventOccurrence,
            spoke = spoke and "true" or "false",
            phase = runtime.phaseKey,
        })
        LogTriggerEvent("event_rule_added", {
            source = SOURCE_TIMELINE_EVENT,
            eventID = rawEventID,
            occurrence = eventOccurrence,
            spoke = spoke == true,
        })
    end
end

function Runner:GetEventRuntimeInfo(eventID)
    local normalizedEventID = NormalizeEventID(eventID)
    if not normalizedEventID then
        return nil
    end
    return runtime.eventIDToInfo[normalizedEventID]
end

function Runner:OnTimelineEventStateChanged(eventID)
    if not runtime.active or not runtime.parsed then
        return
    end
    if not C_EncounterTimeline or not C_EncounterTimeline.GetEventState then
        return
    end

    local normalizedEventID = tonumber(eventID)
    if not normalizedEventID then
        return
    end

    local state = C_EncounterTimeline.GetEventState(normalizedEventID)
    if state == EVENT_STATE_CANCELED then
        CancelScheduledTimer(normalizedEventID, "event_canceled", "canceled")
        runtime.eventIDToInfo[normalizedEventID] = nil
        return
    end
    if state ~= EVENT_STATE_FINISHED then
        return
    end

    local info = runtime.eventIDToInfo[normalizedEventID]
    if not info or info.spoken then
        return
    end

    CancelScheduledTimer(normalizedEventID, "event_finished_cleanup", "canceled")

    -- 先尝试 spell 规则
    local spoke = false
    if info.spellID then
        spoke = SpeakRule(info.spellID, info.occurrence, nil, info, {
            source = SOURCE_TIMELINE_EVENT,
            eventID = normalizedEventID,
        })
    end

    -- 再尝试 event 规则（如果 spell 路径没播报）
    if not spoke and info.eventRuleID then
        SpeakEventRule(info.eventRuleID, info, {
            source = SOURCE_TIMELINE_EVENT,
            stage = "finished",
            markSpoken = true,
        })
    end
end

function Runner:OnTimelineEventRemoved(eventID)
    local normalizedEventID = NormalizeEventID(eventID)
    if not normalizedEventID then
        return
    end
    CancelScheduledTimer(normalizedEventID, "event_removed", "canceled")
    runtime.eventIDToInfo[normalizedEventID] = nil
end

function Runner:OnEncounterWarning(encounterWarningInfo)
    if not runtime.active or not runtime.parsed or type(encounterWarningInfo) ~= "table" then
        return
    end

    local spellMeta = ResolveWarningSpellMeta(encounterWarningInfo)
    if not spellMeta then
        return
    end
    if not (IsAllowedObservedSpell(spellMeta.observedSpellID) or IsAllowedCanonicalSpell(spellMeta.spellID)) then
        return
    end

    local pendingInfo = FindPendingTimelineInfo(spellMeta.spellID)
    if pendingInfo then
        SpeakRule(pendingInfo.spellID, pendingInfo.occurrence, nil, pendingInfo, {
            source = SOURCE_ENCOUNTER_WARNING,
            observedSpellID = spellMeta.observedSpellID,
        })
        return
    end

    if IsDuplicateWindowActive(spellMeta.spellID) then
        DebugTriggerFlow("skip_warning_duplicate", {
            source = SOURCE_ENCOUNTER_WARNING,
            observedSpellID = spellMeta.observedSpellID,
            canonicalSpellID = spellMeta.spellID,
        })
        LogTriggerEvent("skip_warning_duplicate", {
            source = SOURCE_ENCOUNTER_WARNING,
            spellID = spellMeta.spellID,
            observedSpellID = spellMeta.observedSpellID,
        })
        return
    end

    local occurrence = (runtime.warningOccurrenceBySpell[spellMeta.spellID] or 0) + 1
    runtime.warningOccurrenceBySpell[spellMeta.spellID] = occurrence
    SpeakRule(spellMeta.spellID, occurrence, spellMeta.spellName, nil, {
        source = SOURCE_ENCOUNTER_WARNING,
        observedSpellID = spellMeta.observedSpellID,
    })
end

end)
