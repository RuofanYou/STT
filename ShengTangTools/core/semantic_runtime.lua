local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({ { "semanticTimeline.runtimeEnabled", true }, "semanticTimeline.editorLoaded" }, function()
local C_Timer, CreateFrame, GetTime = C_Timer, CreateFrame, GetTime
local ipairs, pairs, type = ipairs, pairs, type
local tonumber, tostring = tonumber, tostring
local math, string, table = math, string, table

local Runtime = T.SemanticTimeline or {}
T.SemanticTimeline = Runtime
Runtime.__isRuntimeFacade = true

local MODE_OVERRIDE = "override"
local MODE_COMBINE = "combine"
local MODE_CENTER = "center"
local TRIGGER_HIGHLIGHT = "highlight"
local TRIGGER_DUE = "due"
local INSTANCE_RAID = "raid"
local INSTANCE_DUNGEON = "dungeon"
local PLAN_FORMAT_TIMELINE = "timeline"
local RESOLVE_SOURCE_TEAM = "team"
local RESOLVE_SOURCE_PERSONAL = "personal"
local RESOLVE_SOURCE_TEAM_PLUS_PERSONAL = "team_plus_personal"
local EVENT_STATE_FINISHED = (Enum and Enum.EncounterTimelineEventState and Enum.EncounterTimelineEventState.Finished) or 2

local function TrimText(text)
    if type(text) ~= "string" then
        return ""
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeInstanceType(value)
    if value == INSTANCE_DUNGEON then
        return INSTANCE_DUNGEON
    end
    return INSTANCE_RAID
end

local function NormalizeResolveSource(value)
    if value == RESOLVE_SOURCE_TEAM or value == RESOLVE_SOURCE_PERSONAL then
        return value
    end
    return RESOLVE_SOURCE_TEAM_PLUS_PERSONAL
end

local function EnsureSemanticDB()
    if type(C.DB.semanticTimeline) ~= "table" then
        C.DB.semanticTimeline = {}
    end
    local db = C.DB.semanticTimeline
    if type(db.runtimeEnabled) ~= "boolean" then
        db.runtimeEnabled = true
    end
    if type(db.enabled) ~= "boolean" then
        db.enabled = false
    end
    if db.mode ~= MODE_OVERRIDE and db.mode ~= MODE_COMBINE and db.mode ~= MODE_CENTER then
        db.mode = MODE_COMBINE
    end
    if db.centerTrigger ~= TRIGGER_HIGHLIGHT and db.centerTrigger ~= TRIGGER_DUE then
        db.centerTrigger = TRIGGER_HIGHLIGHT
    end
    db.resolveSource = NormalizeResolveSource(db.resolveSource)
    if type(db.personalOverridesTeam) ~= "boolean" then
        db.personalOverridesTeam = true
    end
    if type(db.notes) ~= "table" then
        db.notes = {}
    end
    STT_DB.semanticTimeline = db
    return db
end

local function CopyBossKey(key)
    if type(key) ~= "table" then
        return nil
    end
    return {
        instanceType = NormalizeInstanceType(key.instanceType),
        instanceID = tonumber(key.instanceID) or 0,
        encounterID = tonumber(key.encounterID) or 0,
    }
end

local function BuildBossKeyText(key)
    local normalized = CopyBossKey(key)
    if not normalized then
        return nil
    end
    if T.BuildSemanticBossKeyText then
        return T.BuildSemanticBossKeyText(normalized.instanceType, normalized.instanceID, normalized.encounterID)
    end
    return string.format("%s:%d:%d", normalized.instanceType, normalized.instanceID, normalized.encounterID)
end

local function ParseBossKeyText(text)
    if T.ParseSemanticBossKeyText then
        return T.ParseSemanticBossKeyText(text)
    end
    if type(text) ~= "string" then
        return nil
    end
    local instanceType, instanceID, encounterID = text:match("^(%a+):(%-?%d+):(%-?%d+)$")
    if not instanceType then
        return nil
    end
    return {
        instanceType = NormalizeInstanceType(instanceType),
        instanceID = tonumber(instanceID) or 0,
        encounterID = tonumber(encounterID) or 0,
    }
end

local function GetActiveData()
    if T.Profile and T.Profile.GetActiveData then
        local ok, data = pcall(T.Profile.GetActiveData, T.Profile)
        if ok and type(data) == "table" then
            return data
        end
    end
    return type(STT_DB) == "table" and STT_DB or nil
end

function Runtime.ComputeContentDigest(content)
    local text = tostring(content or "")
    if text == "" then return 0 end
    local LD = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if LD and LD.Adler32 then
        return LD:Adler32(text)
    end
    return #text * 65599 + (string.byte(text, 1) or 0) * 256 + (string.byte(text, -1) or 0)
end

function Runtime:IsMythicDifficulty(difficultyID)
    return difficultyID == 16 or difficultyID == 8
end

function Runtime:GetMode()
    return EnsureSemanticDB().mode
end

function Runtime:SetMode(mode)
    if mode ~= MODE_OVERRIDE and mode ~= MODE_COMBINE and mode ~= MODE_CENTER then
        return false
    end
    EnsureSemanticDB().mode = mode
    return true
end

function Runtime:GetCenterTrigger()
    return EnsureSemanticDB().centerTrigger
end

function Runtime:SetCenterTrigger(trigger)
    if trigger ~= TRIGGER_HIGHLIGHT and trigger ~= TRIGGER_DUE then
        return false
    end
    EnsureSemanticDB().centerTrigger = trigger
    return true
end

function Runtime:GetResolveSource()
    return NormalizeResolveSource(EnsureSemanticDB().resolveSource)
end

function Runtime:SetResolveSource(resolveSource)
    local db = EnsureSemanticDB()
    db.resolveSource = NormalizeResolveSource(resolveSource)
    return db.resolveSource
end

function Runtime:BuildBossSelectorKey(instanceType, instanceID, encounterID)
    return {
        instanceType = NormalizeInstanceType(instanceType),
        instanceID = tonumber(instanceID) or 0,
        encounterID = tonumber(encounterID) or 0,
    }
end

function Runtime:SerializeBossSelectorKey(key)
    return BuildBossKeyText(key)
end

function Runtime:ParseBossSelectorKey(text)
    return CopyBossKey(ParseBossKeyText(text))
end

function Runtime:GetPlanFormat(text)
    if T.TriggerSyntax and T.TriggerSyntax.GetPlanFormat then
        return T.TriggerSyntax.GetPlanFormat(text)
    end
    return PLAN_FORMAT_TIMELINE
end

local function FindBossKeyByEncounterID(encounterID)
    local normalizedEncounterID = tonumber(encounterID)
    if not normalizedEncounterID or normalizedEncounterID <= 0 then
        return nil
    end
    local data = GetActiveData()
    local maps = {
        data and data.SemanticPlanIDByBossKey,
        data and data.PersonalBossPlans,
    }
    for _, map in ipairs(maps) do
        if type(map) == "table" then
            for bossKeyText, planID in pairs(map) do
                if planID ~= nil then
                    local bossKey = ParseBossKeyText(bossKeyText)
                    if bossKey and tonumber(bossKey.encounterID) == normalizedEncounterID then
                        if C.DB and C.DB.debugMode and T.debug then
                            T.debug(string.format(
                                "[STT_RUNTIME_BOSSKEY_BY_ENCOUNTER] encounterID=%s bossKey=%s result=matched",
                                tostring(normalizedEncounterID),
                                tostring(bossKeyText)
                            ))
                        end
                        return CopyBossKey(bossKey)
                    end
                end
            end
        end
    end
    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format(
            "[STT_RUNTIME_BOSSKEY_BY_ENCOUNTER] encounterID=%s result=missing",
            tostring(normalizedEncounterID)
        ))
    end
    return nil
end

function Runtime:GetLastKnownEncounterID()
    local encounterID = tonumber(self.activeEncounterID)
    if encounterID and encounterID > 0 then
        return encounterID
    end
    encounterID = tonumber(self.lastEncounterID)
    return encounterID and encounterID > 0 and encounterID or nil
end

function Runtime:ResolveBossKeyByEncounterID(encounterID)
    return FindBossKeyByEncounterID(encounterID)
end

function Runtime:GetCurrentBossSelectorKey()
    local activeEncounterID = tonumber(self.activeEncounterID)
    local bossKey = activeEncounterID and self:ResolveBossKeyByEncounterID(activeEncounterID) or nil
    if bossKey then
        self.currentBossKey = CopyBossKey(bossKey)
        self.lastBossKeyResolveSource = "encounter"
        return bossKey
    end
    local note = T.Note
    local currentBossKeyText = note and note.GetCurrentBossKey and note:GetCurrentBossKey() or nil
    bossKey = ParseBossKeyText(currentBossKeyText)
    if bossKey then
        self.lastBossKeyResolveSource = "runtime_context"
        return CopyBossKey(bossKey)
    end
    self.lastBossKeyResolveSource = "none"
    return nil
end

function Runtime:ResolveRuntimeBossKey(options)
    local opts = type(options) == "table" and options or {}
    local bossKey = CopyBossKey(opts.bossKey)
    if not bossKey and type(opts.bossKey) == "string" then
        bossKey = CopyBossKey(ParseBossKeyText(opts.bossKey))
    end
    if bossKey then
        self.lastBossKeyResolveSource = "option_bossKey"
        return bossKey
    end
    local encounterID = tonumber(opts.encounterID)
    if encounterID and encounterID > 0 then
        bossKey = self:ResolveBossKeyByEncounterID(encounterID)
        if bossKey then
            self.lastBossKeyResolveSource = "option_encounter"
            return bossKey
        end
    end
    return self:GetCurrentBossSelectorKey()
end

function Runtime:GetSemanticNoteIDByBossKey(bossKey)
    local note = T.Note
    if not (note and note.GetSemanticBossPlanID) then
        return nil
    end
    local keyText = type(bossKey) == "string" and bossKey or self:SerializeBossSelectorKey(CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey())
    return keyText and note:GetSemanticBossPlanID(keyText) or nil
end

function Runtime:GetSemanticPlanByBossKey(bossKey)
    local note = T.Note
    local planID = self:GetSemanticNoteIDByBossKey(bossKey)
    return planID and note and note.GetPlan and note:GetPlan(planID) or nil
end

function Runtime:GetPersonalNoteIDByBossKey(bossKey)
    local note = T.Note
    if not (note and note.GetPersonalBossPlanID) then
        return nil
    end
    local keyText = type(bossKey) == "string" and bossKey or self:SerializeBossSelectorKey(CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey())
    return keyText and note:GetPersonalBossPlanID(keyText) or nil
end

function Runtime:GetPersonalPlanByBossKey(bossKey)
    local note = T.Note
    local planID = self:GetPersonalNoteIDByBossKey(bossKey)
    return planID and note and note.GetPlan and note:GetPlan(planID) or nil
end

function Runtime:GetResolvedPlanTexts(options)
    local opts = type(options) == "table" and options or {}
    local bossKey = self:ResolveRuntimeBossKey(options)
    local note = T.Note
    local bossKeyText = bossKey and self:SerializeBossSelectorKey(bossKey) or ""
    local explicitBoss = opts.bossKey ~= nil or opts.encounterID ~= nil
    local bundle = note and note.GetCurrentPlanBundle and note:GetCurrentPlanBundle({
        bossKeyText = bossKeyText,
        allowActiveFallback = (not explicitBoss) and opts.allowActiveFallback ~= false,
    }) or {}
    if C.DB and C.DB.debugMode and T.debug then
        local activePlan = note and note.GetActivePlan and note:GetActivePlan() or nil
        T.debug(string.format(
            "[STT_RUNTIME_RESOLVE] bossKey=%s source=%s currentBossKey=%s teamPlanID=%s teamLen=%d personalPlanID=%s personalLen=%d activePlanID=%s fallbackActive=%s",
            tostring(bossKeyText),
            tostring(self.lastBossKeyResolveSource or ""),
            tostring(note and note.GetCurrentBossKey and note:GetCurrentBossKey() or ""),
            tostring(bundle.teamPlanID or ""),
            #(tostring(bundle.teamText or "")),
            tostring(bundle.personalPlanID or ""),
            #(tostring(bundle.personalText or "")),
            tostring(activePlan and activePlan.id or ""),
            tostring(bundle.fallbackActive == true)
        ))
    end
    return {
        bossKey = CopyBossKey(bossKey),
        bossKeyText = tostring(bundle.bossKeyText or bossKeyText or ""),
        teamText = tostring(bundle.teamText or ""),
        personalText = tostring(bundle.personalText or ""),
        teamName = tostring(bundle.teamName or ""),
        personalName = tostring(bundle.personalName or ""),
        teamPlanID = bundle.teamPlanID,
        personalPlanID = bundle.personalPlanID,
        fallbackActive = bundle.fallbackActive == true,
    }
end

function Runtime:GetCurrentPlanContent(options)
    local texts = self:GetResolvedPlanTexts(options)
    return tostring(texts and texts.teamText or "")
end

local function IsUsableTemplateBody(info, expectedBodyKind)
    return T.STNTemplate and T.STNTemplate.IsBodyUsable and T.STNTemplate.IsBodyUsable(info, expectedBodyKind) or false
end

function Runtime:_LogPersonalOverrideDebug()
end

local function SegmentHasAudience(segment)
    if type(segment) ~= "table" then
        return false
    end
    if type(segment.condition) == "string" and segment.condition ~= "" then
        return true
    end
    return type(segment.players) == "table" and #segment.players > 0
end

local function SegmentTargetsCurrentPlayer(segment)
    if not SegmentHasAudience(segment) then
        return false
    end
    local passGroup = (not T.ShouldBroadcastToPlayer) and true or T.ShouldBroadcastToPlayer(segment.condition)
    local passName = (not T.ShouldBroadcastForNames) and true or T.ShouldBroadcastForNames(segment.players)
    return passGroup and passName
end

local function GetSegmentPrimarySpellID(segment)
    local spellID = tonumber(segment and segment.primarySpellID) or nil
    if spellID and spellID > 0 then
        return spellID
    end
    for _, token in ipairs(type(segment and segment.spellTokens) == "table" and segment.spellTokens or {}) do
        local tokenSpellID = tonumber(token and token.spellID) or nil
        if tokenSpellID and tokenSpellID > 0 then
            return tokenSpellID
        end
    end
    return nil
end

function Runtime:_CollectTimelineOverrideSpellIDs(personalText)
    local rawText = tostring(personalText or "")
    if rawText == "" then
        return {}
    end
    if not (T.STNTemplate and T.STNTemplate.PreprocessText and T.NoteParser and T.NoteParser.ParseNote and T.NoteParser.GetResolvedEventTTSPayload) then
        return {}
    end
    local templateInfo = T.STNTemplate.PreprocessText(rawText, { relaxed = true })
    if not IsUsableTemplateBody(templateInfo, "timeline") then
        return {}
    end
    local parsed = T.NoteParser:ParseNote(rawText, {
        relaxed = true,
        templateInfo = templateInfo,
    }) or {}
    local overrideSet = {}
    for _, event in ipairs(parsed) do
        event.isPersonal = true
        local payload = T.NoteParser:GetResolvedEventTTSPayload(event)
        local spellID = tonumber(payload and payload.spellID) or nil
        if spellID and spellID > 0 and payload and payload.text and payload.text ~= "" then
            overrideSet[spellID] = true
        end
    end
    return overrideSet
end

local function FilterTimelineSegmentsByPersonalOverride(segments, overrideSet)
    local keptSegments = {}
    local suppressed = 0
    for _, segment in ipairs(type(segments) == "table" and segments or {}) do
        local spellID = GetSegmentPrimarySpellID(segment)
        if spellID and overrideSet[spellID] and SegmentTargetsCurrentPlayer(segment) then
            suppressed = suppressed + 1
        else
            keptSegments[#keptSegments + 1] = segment
        end
    end
    local hasAudience = T.TimelineSyntax and T.TimelineSyntax.HasAudienceSegments
        and T.TimelineSyntax.HasAudienceSegments(keptSegments) or false
    return keptSegments, suppressed, hasAudience
end

local function NormalizeTimelineTimeText(timeSec)
    local total = tonumber(timeSec)
    if not total then
        return nil
    end
    if total < 0 then
        total = 0
    end
    local minutes = math.floor(total / 60)
    local seconds = total - minutes * 60
    local roundedTenths = math.floor(seconds * 10 + 0.5) / 10
    if roundedTenths >= 60 then
        minutes = minutes + 1
        roundedTenths = 0
    end
    local wholeSeconds = math.floor(roundedTenths + 0.0001)
    if math.abs(roundedTenths - wholeSeconds) < 0.0001 then
        return string.format("%02d:%02d", minutes, wholeSeconds)
    end
    local secondsText = string.format("%06.3f", roundedTenths):gsub("0+$", ""):gsub("%.$", "")
    return string.format("%02d:%s", minutes, secondsText)
end

local function NormalizeTimelinePhaseText(phase)
    local phaseText = tostring(phase or "")
    if phaseText == "" then
        return nil
    end
    return phaseText:match("^([pi]%d+)r1$") or phaseText
end

local function SerializeTargetIndicators(targetIndicators)
    local names = {}
    for name, enabled in pairs(targetIndicators or {}) do
        local normalizedName = TrimText(name)
        if enabled == true and normalizedName ~= "" then
            names[#names + 1] = normalizedName
        end
    end
    if #names == 0 then
        return ""
    end
    table.sort(names)
    return "{to:" .. table.concat(names, ",") .. "}"
end

function Runtime:_SerializeTimelineSegment(segment)
    if type(segment) ~= "table" then
        return ""
    end
    local parts = {}
    local condition = TrimText(segment.condition or "")
    if condition ~= "" then
        parts[#parts + 1] = string.format("{%s}", condition)
    end
    for _, name in ipairs(type(segment.players) == "table" and segment.players or {}) do
        local normalizedName = TrimText(name)
        if normalizedName ~= "" then
            parts[#parts + 1] = string.format("{%s}", normalizedName)
        end
    end
    local rawText = TrimText(segment.rawText or "")
    if rawText == "" then
        return table.concat(parts)
    end
    parts[#parts + 1] = rawText
    return table.concat(parts)
end

function Runtime:_SerializeTimelineContentFromSegments(segments)
    local parts = {}
    for _, segment in ipairs(type(segments) == "table" and segments or {}) do
        local part = self:_SerializeTimelineSegment(segment)
        if part ~= "" then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts)
end

function Runtime:_SerializeTimelineEvent(event)
    if type(event) ~= "table" then
        return nil
    end
    local timeText = NormalizeTimelineTimeText(event.time)
    if not timeText then
        return nil
    end
    local content = TrimText(self:_SerializeTimelineContentFromSegments(event.segments))
    if content == "" then
        return nil
    end
    local phaseText = NormalizeTimelinePhaseText(event.phase)
    local modifiers = type(event.modifiers) == "table" and T.InlineModifier and T.InlineModifier.Compose and T.InlineModifier.Compose(event.modifiers) or ""
    local targetIndicators = SerializeTargetIndicators(event.targetIndicators)
    if phaseText and phaseText ~= "" then
        return string.format("{time:%s,%s}%s%s %s", timeText, phaseText, targetIndicators, modifiers, content)
    end
    return string.format("{time:%s}%s%s %s", timeText, targetIndicators, modifiers, content)
end

function Runtime:_FilterTimelineTeamTextByPersonal(teamText, personalText, teamInfo)
    if not (T.NoteParser and T.NoteParser.ParseNote) then
        return tostring(teamText or ""), {}, { suppressedSegments = 0, droppedRows = 0 }
    end
    local rawTeamText = tostring(teamText or "")
    local overrideSet = self:_CollectTimelineOverrideSpellIDs(personalText)
    if rawTeamText == "" or not next(overrideSet) then
        return rawTeamText, overrideSet, { suppressedSegments = 0, droppedRows = 0 }
    end
    local parsed = T.NoteParser:ParseNote(rawTeamText, {
        templateInfo = teamInfo,
    }) or {}
    local lines = {}
    local suppressedSegments = 0
    local droppedRows = 0
    for _, event in ipairs(parsed) do
        local keptSegments, suppressed, hasAudience = FilterTimelineSegmentsByPersonalOverride(event.segments, overrideSet)
        if suppressed == 0 then
            lines[#lines + 1] = self:_SerializeTimelineEvent(event)
        elseif hasAudience then
            event.segments = keptSegments
            lines[#lines + 1] = self:_SerializeTimelineEvent(event)
            suppressedSegments = suppressedSegments + suppressed
        else
            suppressedSegments = suppressedSegments + suppressed
            droppedRows = droppedRows + 1
        end
    end
    return table.concat(lines, "\n"), overrideSet, {
        suppressedSegments = suppressedSegments,
        droppedRows = droppedRows,
    }
end

function Runtime:_CollectTriggerOverrideSpellIDs(personalText)
    local rawText = tostring(personalText or "")
    if rawText == "" then
        return {}
    end
    local syntax = T.TriggerSyntax
    if not (syntax and syntax.ParseTriggerText and syntax.BuildSpeakText) then
        return {}
    end
    local parsed = syntax.ParseTriggerText(rawText)
    local overrideSet = {}
    for _, rule in ipairs(parsed and parsed.rules or {}) do
        local spellID = tonumber(rule and rule.spellID)
        if rule and rule.triggerKind ~= "event" and spellID and spellID > 0 then
            local speakText = syntax.BuildSpeakText(rule, self:GetSpellName(spellID))
            if speakText and speakText ~= "" then
                overrideSet[spellID] = true
            end
        end
    end
    return overrideSet
end

function Runtime:_FilterTeamTextByPersonal(teamText, personalText)
    local rawTeamText = tostring(teamText or "")
    local rawPersonalText = tostring(personalText or "")
    if rawTeamText == "" or rawPersonalText == "" then
        return rawTeamText, {}, 0
    end
    local preprocess = T.STNTemplate and T.STNTemplate.PreprocessText
    if not preprocess then
        return rawTeamText, {}, 0
    end
    local teamInfo = preprocess(rawTeamText)
    local personalInfo = preprocess(rawPersonalText, { relaxed = true })
    if not (teamInfo and personalInfo and teamInfo.bodyKind and teamInfo.bodyKind == personalInfo.bodyKind) then
        return rawTeamText, {}, 0
    end
    if teamInfo.bodyKind == "timeline" then
        if not (IsUsableTemplateBody(teamInfo, "timeline") and IsUsableTemplateBody(personalInfo, "timeline")) then
            return rawTeamText, {}, 0
        end
        return self:_FilterTimelineTeamTextByPersonal(rawTeamText, rawPersonalText, teamInfo)
    end
    if teamInfo.bodyKind ~= "trigger" then
        return rawTeamText, {}, 0
    end
    local overrideSet = self:_CollectTriggerOverrideSpellIDs(rawPersonalText)
    if not next(overrideSet) or not (T.TriggerSyntax and T.TriggerSyntax.ParseRuleLine) then
        return rawTeamText, overrideSet, 0
    end
    local cleaned = {}
    local dropped = 0
    for line in (rawTeamText .. "\n"):gmatch("([^\n]*)\n") do
        local rule = T.TriggerSyntax.ParseRuleLine(line)
        local spellID = tonumber(rule and rule.spellID) or nil
        if rule and rule.triggerKind ~= "event" and spellID and overrideSet[spellID] == true then
            dropped = dropped + 1
        else
            cleaned[#cleaned + 1] = line
        end
    end
    return table.concat(cleaned, "\n"), overrideSet, dropped
end

local function BuildRuntimeTemplate(bossKey, bodyKind, bodyText, fallbackName)
    local name = TrimText(fallbackName)
    if name == "" and bossKey then
        name = string.format("Encounter-%d", tonumber(bossKey.encounterID) or 0)
    end
    if name == "" then
        name = L["未命名Boss"] or "未命名Boss"
    end
    if T.STNTemplate and T.STNTemplate.BuildTemplate then
        return T.STNTemplate.BuildTemplate({
            name = name,
            author = "STT",
            bodyKind = bodyKind,
            slots = {},
            settingsText = "",
            bodyText = bodyText or "",
        })
    end
    return tostring(bodyText or "")
end

function Runtime:GetResolvedRuntimePlan(options)
    local texts = self:GetResolvedPlanTexts(options)
    local bossKey = texts.bossKey or self:ParseBossSelectorKey(texts.bossKeyText)
    local resolveSource = self:GetResolveSource()
    local teamInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(texts.teamText or "") or nil
    local runtimeTeamText = tostring(texts.teamText or "")
    local runtimeTeamInfo = teamInfo
    local personalInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(texts.personalText or "", { relaxed = true }) or nil
    local semanticDB = EnsureSemanticDB()
    local personalOverrideSpellIDs = {}
    local personalOverrideDropped = 0
    local personalOverrideSuppressedSegments = 0
    if resolveSource == RESOLVE_SOURCE_TEAM_PLUS_PERSONAL
        and semanticDB.personalOverridesTeam ~= false
        and texts.teamText ~= ""
        and texts.personalText ~= "" then
        local cleanedTeamText, overrideSet, stats = self:_FilterTeamTextByPersonal(texts.teamText, texts.personalText)
        personalOverrideSpellIDs = overrideSet
        personalOverrideDropped = tonumber(type(stats) == "table" and stats.droppedRows or stats) or 0
        personalOverrideSuppressedSegments = tonumber(type(stats) == "table" and stats.suppressedSegments or 0) or 0
        if cleanedTeamText ~= texts.teamText then
            runtimeTeamText = cleanedTeamText
            runtimeTeamInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(cleanedTeamText) or nil
        end
    end
    local activeInfos
    if resolveSource == RESOLVE_SOURCE_TEAM then
        activeInfos = { runtimeTeamInfo }
    elseif resolveSource == RESOLVE_SOURCE_PERSONAL then
        activeInfos = { personalInfo }
    else
        activeInfos = { runtimeTeamInfo, personalInfo }
    end

    local parts = {}
    local bodyKind
    for _, info in ipairs(activeInfos) do
        if info and info.bodyKind and IsUsableTemplateBody(info, info.bodyKind) and info.processedText ~= "" then
            bodyKind = bodyKind or info.bodyKind
            if info.bodyKind == bodyKind then
                parts[#parts + 1] = info.processedText
            end
        end
    end

    local runtimeText = ""
    if #parts > 0 and bodyKind then
        runtimeText = BuildRuntimeTemplate(bossKey, bodyKind, table.concat(parts, "\n"), texts.teamName ~= "" and texts.teamName or texts.personalName)
    end
    return {
        bossKey = CopyBossKey(bossKey),
        bossKeyText = bossKey and self:SerializeBossSelectorKey(bossKey) or "",
        resolveSource = resolveSource,
        teamText = texts.teamText,
        runtimeTeamText = runtimeTeamText,
        personalText = texts.personalText,
        teamName = texts.teamName,
        personalName = texts.personalName,
        teamPlanID = texts.teamPlanID,
        personalPlanID = texts.personalPlanID,
        teamInfo = runtimeTeamInfo,
        personalInfo = personalInfo,
        bodyKind = bodyKind,
        runtimeText = runtimeText,
        title = texts.teamName ~= "" and texts.teamName or texts.personalName,
        personalOverrideSpellIDs = personalOverrideSpellIDs,
        personalOverrideDropped = personalOverrideDropped,
        personalOverrideSuppressedSegments = personalOverrideSuppressedSegments,
    }
end

function Runtime:GetCurrentPlanBundle(options)
    return self:GetResolvedRuntimePlan(options)
end

function Runtime:GetCurrentRuntimePlanTitle()
    local bundle = self:GetCurrentPlanBundle()
    return bundle and bundle.title ~= "" and bundle.title or nil
end

function Runtime:GetSpellName(spellID)
    self.spellNameCache = self.spellNameCache or {}
    local normalizedSpellID = tonumber(spellID)
    if not normalizedSpellID then
        return tostring(spellID or "")
    end
    local cached = self.spellNameCache[normalizedSpellID]
    if cached then
        return cached
    end
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(normalizedSpellID)
        name = info and info.name
    elseif GetSpellInfo then
        name = GetSpellInfo(normalizedSpellID)
    end
    if type(name) ~= "string" or name == "" then
        name = tostring(normalizedSpellID)
    end
    self.spellNameCache[normalizedSpellID] = name
    return name
end

function Runtime:GetEncounterSpellCatalog(bossKey)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local encounterID = tonumber(normalizedBossKey and normalizedBossKey.encounterID) or 0
    local encounterMap = T.SemanticEncounterEventMapS14 and T.SemanticEncounterEventMapS14[encounterID] or nil
    local out, seen = {}, {}
    if type(encounterMap) == "table" then
        for canonicalSpellID in pairs(encounterMap) do
            local spellID = tonumber(canonicalSpellID)
            if spellID and spellID > 0 and not seen[spellID] then
                seen[spellID] = true
                out[#out + 1] = {
                    spellID = spellID,
                    spellName = self:GetSpellName(spellID),
                    occurrenceCount = 1,
                    firstOccurrence = 100000 + #out,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        return (tonumber(a.spellID) or 0) < (tonumber(b.spellID) or 0)
    end)
    return out
end

function Runtime:IsRuntimeEnabled()
    local db = EnsureSemanticDB()
    if db.runtimeEnabled == false then
        return false
    end
    if not self.activeEncounterID or not self.activeIsMythic then
        return false
    end
    return true
end

function Runtime:ResetRuntimeState()
    self.activeEncounterID = nil
    self.activeEncounterName = nil
    self.activeStartTime = nil
    self.activeIsMythic = false
    self.currentBossKey = nil
    self.centerShownEvents = {}
end

function Runtime:ShowNotice(text, opts)
    if type(text) ~= "string" or text == "" then
        return
    end
    if T.TacticalNotice and C.DB.screenReminder and C.DB.screenReminder.enabled ~= false then
        T.TacticalNotice:ShowReminder({
            text = text,
            duration = (opts and tonumber(opts.duration)) or 2.5,
            severity = opts and opts.severity or nil,
        })
        return
    end
    T.msg(text)
end

function Runtime:HideNotice()
end

function Runtime:OnEncounterStart(encounterID, encounterName, difficultyID)
    self:ResetRuntimeState()
    self.activeEncounterID = tonumber(encounterID)
    self.lastEncounterID = tonumber(encounterID) or self.lastEncounterID
    self.activeEncounterName = tostring(encounterName or "")
    self.activeIsMythic = self:IsMythicDifficulty(tonumber(difficultyID))
    self.activeStartTime = GetTime()
    self.currentBossKey = self:ResolveBossKeyByEncounterID(self.activeEncounterID)
    if self.currentBossKey and T.Note and T.Note.SetCurrentBossKey then
        T.Note:SetCurrentBossKey(self.currentBossKey, "encounter_start")
    end
end

function Runtime:OnEncounterEnd()
    if tonumber(self.activeEncounterID) and tonumber(self.activeEncounterID) > 0 then
        self.lastEncounterID = tonumber(self.activeEncounterID)
    end
    self:ResetRuntimeState()
end

function Runtime:OnTimelineEventStateChanged(eventID)
    if not self:IsRuntimeEnabled() then
        return
    end
    local db = EnsureSemanticDB()
    if db.mode ~= MODE_CENTER or db.centerTrigger ~= TRIGGER_DUE then
        return
    end
    if C_EncounterTimeline and C_EncounterTimeline.GetEventState and C_EncounterTimeline.GetEventState(eventID) == EVENT_STATE_FINISHED then
        self.centerShownEvents[eventID] = true
    end
end

function Runtime:OnEvent(event, ...)
    if event == "ENCOUNTER_START" then
        self:OnEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        self:OnEncounterEnd()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        if not IsInInstance or not select(1, IsInInstance()) then
            self.lastEncounterID = nil
            self.currentBossKey = nil
        end
    elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        self:OnTimelineEventStateChanged(...)
    end
end

function Runtime:Init()
    EnsureSemanticDB()
    self:ResetRuntimeState()
    if not self.eventFrame then
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frame:RegisterEvent("ZONE_CHANGED_INDOORS")
        frame:RegisterEvent("ENCOUNTER_START")
        frame:RegisterEvent("ENCOUNTER_END")
        frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
        frame:SetScript("OnEvent", function(_, event, ...)
            Runtime:OnEvent(event, ...)
        end)
        self.eventFrame = frame
    end
end

function Runtime:OnEnable()
    self:Init()
end

function Runtime:OnDisable()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    self:ResetRuntimeState()
end

T.GetEmbeddedTemplateText = function()
    return ""
end

T.GetEmbeddedRetimeAction = function()
    return nil
end

end)
