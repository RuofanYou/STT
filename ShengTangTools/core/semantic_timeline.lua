local select, unpack = select, unpack
local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()
local C_Timer, CreateFrame, GetTime = C_Timer, CreateFrame, GetTime
local ipairs, pairs, pcall, select, type = ipairs, pairs, pcall, select, type
local tonumber, tostring = tonumber, tostring
local math, string, table = math, string, table

local previousSemanticTimeline = T.SemanticTimeline
if previousSemanticTimeline
    and previousSemanticTimeline.__isRuntimeFacade
    and previousSemanticTimeline.OnDisable then
    previousSemanticTimeline:OnDisable()
end

local SemanticTimeline = {}
T.SemanticTimeline = SemanticTimeline

local MODE_OVERRIDE = "override"
local MODE_COMBINE = "combine"
local MODE_CENTER = "center"

local TRIGGER_HIGHLIGHT = "highlight"
local TRIGGER_DUE = "due"

local WORKBENCH_SCOPE_BY_BOSS = "by_boss"
local WORKBENCH_SCOPE_GLOBAL = "global"

local WORKBENCH_INSTANCE_RAID = "raid"
local WORKBENCH_INSTANCE_DUNGEON = "dungeon"
local PLAN_FORMAT_TIMELINE = "timeline"
local PLAN_FORMAT_TRIGGER = "trigger"
local RESOLVE_SOURCE_TEAM = "team"
local RESOLVE_SOURCE_PERSONAL = "personal"
local RESOLVE_SOURCE_TEAM_PLUS_PERSONAL = "team_plus_personal"

local WORKBENCH_ROW_SPELL = "spell"
local WORKBENCH_ROW_TEXT = "text"
local WORKBENCH_ROW_COUNTDOWN = "countdown"
local WORKBENCH_ROW_COMMENT = "comment"

local ENCOUNTER_SOURCE = (Enum and Enum.EncounterTimelineEventSource and Enum.EncounterTimelineEventSource.Encounter) or 0
local EVENT_STATE_FINISHED = (Enum and Enum.EncounterTimelineEventState and Enum.EncounterTimelineEventState.Finished) or 2

local function GetProfileTimeMs()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end
    return nil
end

local function LogPlanEvent(eventName, fields)
    if T and T.LogDebugEvent then
        T.LogDebugEvent(eventName, fields)
    end
end

SemanticTimeline.LogPlanEvent = LogPlanEvent

function SemanticTimeline.ComputeContentDigest(content)
    local text = tostring(content or "")
    if text == "" then return 0 end
    local LD = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if LD and LD.Adler32 then
        return LD:Adler32(text)
    end
    return #text * 65599 + (string.byte(text, 1) or 0) * 256 + (string.byte(text, -1) or 0)
end

local ComputeContentDigest = SemanticTimeline.ComputeContentDigest
local partialTimelineCompileLogSeen = {}

local function IsUsableTemplateBody(info, expectedBodyKind)
    return T.STNTemplate and T.STNTemplate.IsBodyUsable and T.STNTemplate.IsBodyUsable(info, expectedBodyKind) or false
end

local function LogPartialTimelineCompileOnce(bossKey, planID, text, templateInfo, cause)
    if not (C and C.DB and C.DB.debugMode and T and T.debug) then
        return
    end

    local bossKeyText = SemanticTimeline.SerializeBossSelectorKey and SemanticTimeline:SerializeBossSelectorKey(bossKey) or ""
    local digest = ComputeContentDigest(text)
    local key = table.concat({
        tostring(bossKeyText or ""),
        tostring(planID or 0),
        tostring(digest or 0),
        tostring(#(templateInfo and templateInfo.errors or {})),
    }, "|")
    if partialTimelineCompileLogSeen[key] then
        return
    end
    partialTimelineCompileLogSeen[key] = true

    T.debug(string.format(
        "[SemanticTemplate] compile_partial_timeline: boss=%s planID=%s len=%d errors=%d cause=%s",
        tostring(bossKeyText or ""),
        tostring(planID or ""),
        #(tostring(text or "")),
        #(templateInfo and templateInfo.errors or {}),
        tostring(cause or "")
    ))
end

local function IsValidEncounterName(name)
    return type(name) == "string" and name ~= "" and not name:match("^Encounter%-%d+$")
end

local function BuildKey(encounterID, spellID, occurrence)
    return string.format("%d:%d:%d", tonumber(encounterID) or 0, tonumber(spellID) or 0, tonumber(occurrence) or 0)
end

local function ParseKey(key)
    if type(key) ~= "string" then
        return nil, nil, nil
    end
    local encounterID, spellID, occurrence = key:match("^(%d+):(%d+):(%d+)$")
    return tonumber(encounterID), tonumber(spellID), tonumber(occurrence)
end

local function BuildSpellOccurrenceKey(spellID, occurrence)
    return string.format("%d:%d", tonumber(spellID) or 0, tonumber(occurrence) or 0)
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
    if db.resolveSource ~= RESOLVE_SOURCE_TEAM
        and db.resolveSource ~= RESOLVE_SOURCE_PERSONAL
        and db.resolveSource ~= RESOLVE_SOURCE_TEAM_PLUS_PERSONAL then
        db.resolveSource = RESOLVE_SOURCE_TEAM_PLUS_PERSONAL
    end
    if type(db.personalOverridesTeam) ~= "boolean" then
        db.personalOverridesTeam = true
    end
    if type(db.notes) ~= "table" then
        db.notes = {}
    end
    if type(db.editor) ~= "table" then
        db.editor = {}
    end
    if type(db.editor.recentSkills) ~= "table" then
        db.editor.recentSkills = {}
    end
    if type(db.ui) ~= "table" then
        db.ui = {}
    end
    if type(db.ui.cellWidth) ~= "number" then
        db.ui.cellWidth = 120
    end
    if type(db.ui.rowHeight) ~= "number" then
        db.ui.rowHeight = 26
    end
    if type(db.ui.iconSize) ~= "number" then
        db.ui.iconSize = 16
    end
    if type(db.ui.cellGap) ~= "number" then
        db.ui.cellGap = 2
    end
    if type(db.ui.durationBarHeight) ~= "number" then
        db.ui.durationBarHeight = 6
    end
    if type(db.ui.durationBarColor) ~= "table" then
        db.ui.durationBarColor = { 0.4, 0.7, 1.0, 0.55 }
    end
    if db.ui.viewMode ~= "vertical" and db.ui.viewMode ~= "horizontal" then
        db.ui.viewMode = "horizontal"
    end
    if type(db.ui.perViewMode) ~= "table" then
        db.ui.perViewMode = {}
    end
    if type(db.ui.perViewMode.vertical) ~= "table" then
        db.ui.perViewMode.vertical = {}
    end
    if type(db.ui.perViewMode.horizontal) ~= "table" then
        db.ui.perViewMode.horizontal = {}
    end

    local vertical = db.ui.perViewMode.vertical
    if type(vertical.dividerRatio) ~= "number" then
        vertical.dividerRatio = type(db.ui.dividerRatio) == "number" and db.ui.dividerRatio or 0.5
    end
    if type(vertical.cellWidth) ~= "number" then vertical.cellWidth = db.ui.cellWidth end
    if type(vertical.rowHeight) ~= "number" then vertical.rowHeight = db.ui.rowHeight end
    if type(vertical.iconSize) ~= "number" then vertical.iconSize = db.ui.iconSize end
    if type(vertical.cellGap) ~= "number" then vertical.cellGap = db.ui.cellGap end
    if type(vertical.scrollY) ~= "number" then vertical.scrollY = 0 end

    local horizontal = db.ui.perViewMode.horizontal
    if type(horizontal.dividerRatio) ~= "number" then horizontal.dividerRatio = 0.8 end
    if type(horizontal.pxPerSecond) ~= "number" then horizontal.pxPerSecond = 50 end
    if type(horizontal.scrollX) ~= "number" then horizontal.scrollX = 0 end
    if type(horizontal.scrollY) ~= "number" then horizontal.scrollY = 0 end
    if type(horizontal.firstColMinW) ~= "number" then horizontal.firstColMinW = 80 end
    if type(horizontal.firstColMaxW) ~= "number" then horizontal.firstColMaxW = 200 end
    if type(horizontal.rowHeight) ~= "number" then horizontal.rowHeight = 28 end
    if type(horizontal.iconSize) ~= "number" then horizontal.iconSize = 24 end
    if type(db.ui.playerCacheById) ~= "table" then
        db.ui.playerCacheById = {}
    end
    if type(db.ui.bossPortraitCache) ~= "table" then
        db.ui.bossPortraitCache = {}
    end
    if type(db.captured) ~= "table" then
        db.captured = {}
    end
    if type(db.captured.encounters) ~= "table" then
        db.captured.encounters = {}
    end
    if type(db.templateVersion) ~= "string" or db.templateVersion == "" then
        db.templateVersion = "mn_s1_text_v2"
    end
    if type(db.workbench) ~= "table" then
        db.workbench = {}
    end

    local wb = db.workbench
    if type(wb.selection) ~= "table" then
        wb.selection = {}
    end
    if type(wb.nextRowSeq) ~= "number" or wb.nextRowSeq < 1 then
        wb.nextRowSeq = 1
    end
    if type(wb.planRowBindings) ~= "table" then
        wb.planRowBindings = {}
    end
    if type(wb.bossTemplateVer) ~= "table" then
        wb.bossTemplateVer = {}
    end
    if type(wb.bossTemplateDigest) ~= "table" then
        wb.bossTemplateDigest = {}
    end
    if type(wb.plansInitialized) ~= "boolean" then
        wb.plansInitialized = false
    end

    wb.globalBaseline = nil
    wb.bossOverrides = nil

    STT_DB.semanticTimeline = db
    return db
end

local function EscapeNote(text)
    local value = tostring(text or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("=", "\\=")
    value = value:gsub("\n", "\\n")
    return value
end

local function UnescapeNote(text)
    local value = tostring(text or "")
    local out = {}
    local i = 1

    while i <= #value do
        local ch = value:sub(i, i)
        if ch ~= "\\" then
            out[#out + 1] = ch
            i = i + 1
        else
            local nextCh = value:sub(i + 1, i + 1)
            if nextCh == "n" then
                out[#out + 1] = "\n"
                i = i + 2
            elseif nextCh == "=" then
                out[#out + 1] = "="
                i = i + 2
            elseif nextCh == "\\" then
                out[#out + 1] = "\\"
                i = i + 2
            elseif nextCh == "" then
                out[#out + 1] = "\\"
                i = i + 1
            else
                out[#out + 1] = "\\"
                out[#out + 1] = nextCh
                i = i + 2
            end
        end
    end

    return table.concat(out)
end

local function FormatClock(timeSec)
    local timeValue = tonumber(timeSec)
    if not timeValue then
        return L["动态"] or "--:--"
    end
    if timeValue < 0 then
        timeValue = 0
    end
    local whole = math.floor(timeValue + 0.5)
    local m = math.floor(whole / 60)
    local s = whole % 60
    return string.format("%02d:%02d", m, s)
end

local function TrimText(text)
    if type(text) ~= "string" then
        return ""
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeInstanceType(value)
    if value == WORKBENCH_INSTANCE_DUNGEON then
        return WORKBENCH_INSTANCE_DUNGEON
    end
    return WORKBENCH_INSTANCE_RAID
end

local function NormalizeResolveSource(value)
    if value == RESOLVE_SOURCE_TEAM or value == RESOLVE_SOURCE_PERSONAL then
        return value
    end
    return RESOLVE_SOURCE_TEAM_PLUS_PERSONAL
end

local function NormalizeEditorTab(value)
    if value == RESOLVE_SOURCE_PERSONAL then
        return RESOLVE_SOURCE_PERSONAL
    end
    return RESOLVE_SOURCE_TEAM
end

local function NormalizeRowType(value)
    if value == WORKBENCH_ROW_COMMENT then
        return WORKBENCH_ROW_COMMENT
    end
    if value == WORKBENCH_ROW_TEXT then
        return WORKBENCH_ROW_TEXT
    end
    if value == WORKBENCH_ROW_COUNTDOWN then
        return WORKBENCH_ROW_COUNTDOWN
    end
    return WORKBENCH_ROW_SPELL
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

local function CopySlotVisualHints(hints)
    if type(hints) ~= "table" then
        return nil
    end

    local out = {}
    local hasAny = false
    for playerName, hint in pairs(hints) do
        if type(hint) == "table" then
            out[tostring(playerName or "")] = {
                classFile = hint.classFile ~= nil and tostring(hint.classFile) or nil,
                specID = tonumber(hint.specID),
            }
            hasAny = true
        end
    end
    return hasAny and out or nil
end

local function CopyPlainTable(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, item in pairs(value) do
        out[CopyPlainTable(key)] = CopyPlainTable(item)
    end
    return out
end

local function CopyInlineModifiers(modifiers)
    if type(modifiers) ~= "table" or not next(modifiers) then
        return nil
    end
    return CopyPlainTable(modifiers)
end

local function CopyTargetIndicators(targetIndicators)
    if type(targetIndicators) ~= "table" or not next(targetIndicators) then
        return nil
    end
    local copied = {}
    for name, enabled in pairs(targetIndicators) do
        local normalizedName = TrimText(name)
        if enabled == true and normalizedName ~= "" then
            copied[normalizedName] = true
        end
    end
    if not next(copied) then
        return nil
    end
    return copied
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

local function CopyRow(row)
    if type(row) ~= "table" then
        return nil
    end
    local copiedSegments = nil
    if type(row.segments) == "table" then
        copiedSegments = {}
        for index, segment in ipairs(row.segments) do
            if type(segment) == "table" then
                local copiedSegmentSpellTokens = nil
                if type(segment.spellTokens) == "table" then
                    copiedSegmentSpellTokens = {}
                    for tokenIndex, token in ipairs(segment.spellTokens) do
                        if type(token) == "table" then
                            copiedSegmentSpellTokens[tokenIndex] = {
                                raw = token.raw ~= nil and tostring(token.raw) or "",
                                spellID = tonumber(token.spellID),
                                spellName = token.spellName ~= nil and tostring(token.spellName) or "",
                                spellIcon = token.spellIcon,
                                isPrimarySpell = token.isPrimarySpell == true,
                            }
                        end
                    end
                end
                copiedSegments[index] = {
                    text = segment.text ~= nil and tostring(segment.text) or "",
                    cellText = segment.cellText ~= nil and tostring(segment.cellText) or "",
                    rawText = segment.rawText ~= nil and tostring(segment.rawText) or "",
                    condition = segment.condition ~= nil and tostring(segment.condition) or "",
                    players = type(segment.players) == "table" and { unpack(segment.players) } or nil,
                    primarySpellID = tonumber(segment.primarySpellID),
                    spellTokens = copiedSegmentSpellTokens,
                }
            end
        end
    end

    local copiedSpellTokens = nil
    if type(row.spellTokens) == "table" then
        copiedSpellTokens = {}
        for index, token in ipairs(row.spellTokens) do
            if type(token) == "table" then
                copiedSpellTokens[index] = {
                    raw = token.raw ~= nil and tostring(token.raw) or "",
                    spellID = tonumber(token.spellID),
                    spellName = token.spellName ~= nil and tostring(token.spellName) or "",
                    spellIcon = token.spellIcon,
                    isPrimarySpell = token.isPrimarySpell == true,
                }
            end
        end
    end

    return {
        rowID = tostring(row.rowID or ""),
        key = CopyBossKey(row.key),
        timeSec = tonumber(row.timeSec),
        phase = row.phase,
        rowType = NormalizeRowType(row.rowType),
        spellID = tonumber(row.spellID),
        label = tostring(row.label or ""),
        textPayload = row.textPayload ~= nil and tostring(row.textPayload) or nil,
        countdownFrom = tonumber(row.countdownFrom),
        source = row.source == "preset" and "preset" or "override",
        enabled = row.enabled ~= false,
        sortIndex = tonumber(row.sortIndex),
        triggerMode = row.triggerMode ~= nil and tostring(row.triggerMode) or nil,
        isConfigured = row.isConfigured == true,
        occurrenceCount = tonumber(row.occurrenceCount),
        formatKind = row.formatKind ~= nil and tostring(row.formatKind) or nil,
        rawContent = row.rawContent ~= nil and tostring(row.rawContent) or nil,
        editorTab = row.editorTab ~= nil and tostring(row.editorTab) or nil,
        sourcePlanID = tonumber(row.sourcePlanID),
        segments = copiedSegments,
        spellTokens = copiedSpellTokens,
        modifiers = CopyInlineModifiers(row.modifiers),
        targetIndicators = CopyTargetIndicators(row.targetIndicators),
        slotVisualHints = CopySlotVisualHints(row.slotVisualHints),
        phaseDisplaySpans = CopyPlainTable(row.phaseDisplaySpans),
    }
end

local function BuildRowSignature(row)
    if type(row) ~= "table" then
        return ""
    end
    return table.concat({
        tostring(tonumber(row.timeSec) or 0),
        tostring(NormalizeRowType(row.rowType)),
        tostring(tonumber(row.spellID) or 0),
        tostring(row.label or ""),
        tostring(row.textPayload or ""),
        tostring(tonumber(row.countdownFrom) or 0),
        tostring(row.triggerMode or ""),
        tostring(row.isConfigured == true),
        tostring(tonumber(row.occurrenceCount) or 0),
        tostring(row.formatKind or ""),
        tostring(row.rawContent or ""),
    }, "|")
end

local function RowEquals(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end
    return BuildRowSignature(left) == BuildRowSignature(right) and (left.enabled ~= false) == (right.enabled ~= false)
end

local function BuildBossSelectorKeyText(key)
    local normalized = CopyBossKey(key) or {
        instanceType = WORKBENCH_INSTANCE_RAID,
        instanceID = 0,
        encounterID = 0,
    }
    if T.BuildSemanticBossKeyText then
        return T.BuildSemanticBossKeyText(normalized.instanceType, normalized.instanceID, normalized.encounterID)
    end
    return string.format("%s:%d:%d", normalized.instanceType, normalized.instanceID, normalized.encounterID)
end

function SemanticTimeline:IsMythicDifficulty(difficultyID)
    return difficultyID == 16 or difficultyID == 8
end

function SemanticTimeline:GetMode()
    local db = EnsureSemanticDB()
    return db.mode
end

function SemanticTimeline:SetMode(mode)
    if mode ~= MODE_OVERRIDE and mode ~= MODE_COMBINE and mode ~= MODE_CENTER then
        return false
    end
    local db = EnsureSemanticDB()
    db.mode = mode
    return true
end

function SemanticTimeline:GetCenterTrigger()
    local db = EnsureSemanticDB()
    return db.centerTrigger
end

function SemanticTimeline:SetCenterTrigger(trigger)
    if trigger ~= TRIGGER_HIGHLIGHT and trigger ~= TRIGGER_DUE then
        return false
    end
    local db = EnsureSemanticDB()
    db.centerTrigger = trigger
    return true
end

function SemanticTimeline:GetResolveSource()
    local db = EnsureSemanticDB()
    return NormalizeResolveSource(db.resolveSource)
end

function SemanticTimeline:SetResolveSource(resolveSource)
    local db = EnsureSemanticDB()
    db.resolveSource = NormalizeResolveSource(resolveSource)
    return db.resolveSource
end

function SemanticTimeline:BuildBossSelectorKey(instanceType, instanceID, encounterID)
    return {
        instanceType = NormalizeInstanceType(instanceType),
        instanceID = tonumber(instanceID) or 0,
        encounterID = tonumber(encounterID) or 0,
    }
end

function SemanticTimeline:SerializeBossSelectorKey(key)
    return BuildBossSelectorKeyText(key)
end

function SemanticTimeline:ParseBossSelectorKey(text)
    local parsed = T.ParseSemanticBossKeyText and T.ParseSemanticBossKeyText(text) or nil
    if not parsed then
        return nil
    end

    return self:BuildBossSelectorKey(parsed.instanceType, parsed.instanceID, parsed.encounterID)
end

function SemanticTimeline:BuildPresetRowID(encounterID, spellID, occurrence)
    return string.format("preset:%d:%d:%d", tonumber(encounterID) or 0, tonumber(spellID) or 0, tonumber(occurrence) or 0)
end

function SemanticTimeline:GenerateRowID()
    local db = EnsureSemanticDB()
    local wb = db.workbench
    local seq = wb.nextRowSeq
    wb.nextRowSeq = seq + 1
    return string.format("override:%d:%d", tonumber(time()) or 0, seq)
end

function SemanticTimeline:GetWorkbenchScopeMode()
    return WORKBENCH_SCOPE_BY_BOSS
end

function SemanticTimeline:SetWorkbenchScopeMode(scopeMode)
    return true
end

function SemanticTimeline:GetWorkbenchScopeOptions()
    return {
        { value = WORKBENCH_SCOPE_BY_BOSS, text = L["按Boss"] or "按Boss" },
    }
end

function SemanticTimeline:EnsureTemplateReady()
    if self._buildingTemplate then
        return
    end

    if type(self.instances) == "table" and #self.instances > 0 then
        return
    end

    self:RebuildTemplateIndexes(true)
end

function SemanticTimeline:RebuildTemplateIndexes(force)
    if self._buildingTemplate then
        return false
    end

    if force ~= true and type(self.instances) == "table" and #self.instances > 0 then
        return true
    end

    self._buildingTemplate = true
    local ok, err = pcall(function()
        self:BuildTemplateIndexes()
    end)
    self._buildingTemplate = false

    if not ok then
        error(err)
    end
    return true
end

function SemanticTimeline:GetWorkbenchInstanceTypeOptions()
    self:EnsureTemplateReady()
    local hasRaid = false
    local hasDungeon = false
    for _, instance in ipairs(self.instances or {}) do
        local normalizedType = NormalizeInstanceType(instance.type)
        if normalizedType == WORKBENCH_INSTANCE_RAID then
            hasRaid = true
        elseif normalizedType == WORKBENCH_INSTANCE_DUNGEON then
            hasDungeon = true
        end
    end

    local out = {}
    if hasRaid then
        out[#out + 1] = { value = WORKBENCH_INSTANCE_RAID, text = L["团本"] or "团本" }
    end
    if hasDungeon then
        out[#out + 1] = { value = WORKBENCH_INSTANCE_DUNGEON, text = L["大秘境"] or "大秘境" }
    end
    if #out == 0 then
        out[1] = { value = WORKBENCH_INSTANCE_RAID, text = L["团本"] or "团本" }
    end
    return out
end

function SemanticTimeline:GetWorkbenchInstanceList(instanceType)
    self:EnsureTemplateReady()
    local normalizedType = NormalizeInstanceType(instanceType)
    local out = {}
    for _, instance in ipairs(self.instances or {}) do
        if NormalizeInstanceType(instance.type) == normalizedType then
            out[#out + 1] = {
                instanceID = instance.instanceID,
                name = self:GetLocalizedInstanceName(instance) or instance.name or tostring(instance.instanceID),
                type = NormalizeInstanceType(instance.type),
                encounterCount = #instance.encounters,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.instanceID < b.instanceID
    end)
    return out
end

function SemanticTimeline:GetWorkbenchEncounterList(instanceType, instanceID)
    self:EnsureTemplateReady()
    local normalizedType = NormalizeInstanceType(instanceType)
    local out = {}
    local encounters = self.encountersByInstanceID[tonumber(instanceID) or 0] or {}
    for _, encounter in ipairs(encounters) do
        local parentInstance = self.instancesByID[encounter.instanceID]
        if parentInstance and NormalizeInstanceType(parentInstance.type) == normalizedType then
            out[#out + 1] = {
                encounterID = encounter.encounterID,
                name = self:GetLocalizedEncounterName(encounter) or encounter.name or tostring(encounter.encounterID),
                eventCount = #encounter.events,
            }
        end
    end
    return out
end

function SemanticTimeline:NormalizeWorkbenchSelection()
    local db = EnsureSemanticDB()
    local wb = db.workbench
    local selection = wb.selection

    local typeOptions = self:GetWorkbenchInstanceTypeOptions()
    local selectedType = NormalizeInstanceType(selection.instanceType)
    local hasType = false
    for _, option in ipairs(typeOptions) do
        if option.value == selectedType then
            hasType = true
            break
        end
    end
    if not hasType then
        selectedType = typeOptions[1] and typeOptions[1].value or WORKBENCH_INSTANCE_RAID
    end

    local instanceList = self:GetWorkbenchInstanceList(selectedType)
    local selectedInstanceID = tonumber(selection.instanceID) or 0
    local hasInstance = false
    for _, item in ipairs(instanceList) do
        if item.instanceID == selectedInstanceID then
            hasInstance = true
            break
        end
    end
    if not hasInstance then
        selectedInstanceID = (instanceList[1] and instanceList[1].instanceID) or 0
    end

    local encounterList = self:GetWorkbenchEncounterList(selectedType, selectedInstanceID)
    local selectedEncounterID = tonumber(selection.encounterID) or 0
    local hasEncounter = false
    for _, item in ipairs(encounterList) do
        if item.encounterID == selectedEncounterID then
            hasEncounter = true
            break
        end
    end
    if not hasEncounter then
        selectedEncounterID = (encounterList[1] and encounterList[1].encounterID) or 0
    end

    selection.instanceType = selectedType
    selection.instanceID = selectedInstanceID
    selection.encounterID = selectedEncounterID
    selection.difficulty = nil
end

function SemanticTimeline:GetWorkbenchSelection()
    self:EnsureTemplateReady()
    self:NormalizeWorkbenchSelection()
    local db = EnsureSemanticDB()
    return CopyBossKey(db.workbench.selection)
end

function SemanticTimeline:SetWorkbenchSelection(instanceType, instanceID, encounterID, options)
    local opts = type(options) == "table" and options or {}
    local db = EnsureSemanticDB()
    local selection = db.workbench.selection
    local prevType, prevInstance, prevEncounter = selection.instanceType, selection.instanceID, selection.encounterID

    if instanceType ~= nil then
        selection.instanceType = NormalizeInstanceType(instanceType)
    end
    if instanceID ~= nil then
        selection.instanceID = tonumber(instanceID) or 0
    end
    if encounterID ~= nil then
        selection.encounterID = tonumber(encounterID) or 0
    end

    self:NormalizeWorkbenchSelection()
    local changed = (selection.instanceType ~= prevType)
        or (selection.instanceID ~= prevInstance)
        or (selection.encounterID ~= prevEncounter)
    if changed and T.events then
        T.events:Fire("STT_BOSS_SELECTION_CHANGED", selection.encounterID, selection.instanceID, selection.instanceType)
    end
    if opts.suppressCurrentBossContext ~= true and T.Note and T.Note.SetCurrentBossKey then
        local bossKeyText = self:SerializeBossSelectorKey(selection)
        local parsedBossKey = self:ParseBossSelectorKey(bossKeyText)
        if parsedBossKey and tonumber(parsedBossKey.instanceID) and tonumber(parsedBossKey.instanceID) > 0
            and tonumber(parsedBossKey.encounterID) and tonumber(parsedBossKey.encounterID) > 0 then
            T.Note:SetCurrentBossKey(bossKeyText, "workbench_selection")
        end
    end
    return self:GetWorkbenchSelection()
end

function SemanticTimeline:SwitchWorkbenchToBossKeyText(bossKeyText, cause, options)
    local opts = type(options) == "table" and options or {}
    local bossKey = self:ParseBossSelectorKey(bossKeyText)
    if not bossKey then
        return false, "invalid_boss_key", false, false
    end

    self:SetWorkbenchSelection(
        bossKey.instanceType,
        bossKey.instanceID,
        bossKey.encounterID,
        opts
    )

    local guiShown = T.GUI and T.GUI:IsShown() or false
    local didSwitchTab = false
    if guiShown and T.SwitchToSemanticTab then
        T.SwitchToSemanticTab()
        didSwitchTab = true
    end

    if guiShown and T.SemanticTimelineGUI then
        if T.SemanticTimelineGUI.SwitchEditorDocumentToBossKey then
            T.SemanticTimelineGUI.SwitchEditorDocumentToBossKey(
                bossKeyText,
                self:GetCurrentEditorTab(),
                cause or "boss_change",
                opts
            )
        elseif T.SemanticTimelineGUI.RefreshData then
            T.SemanticTimelineGUI.RefreshData(cause or "boss_change")
        end
    end

    return true, nil, guiShown, didSwitchTab
end

function SemanticTimeline:GetCurrentBossSelectorKey()
    return self:GetWorkbenchSelection()
end

-- 阶段排序键：返回 (roundWeight, segWeight) 两层。
-- 期望顺序：先所有 round 1 的段（p1→i1→p2→i2→p3），再 round 2（p1r2→i1r2→p2r2），依此类推。
-- 无阶段标记 (nil/"") 返回 (0, 0),排在最前。
-- 原先只返回单权重且忽略 roundIndex,会让 p1/p1r2/p1r3 全部 weight=1，排序后按时间交错，导致 GUI 分隔条为每一行重复插入（奇美鲁斯等多轮 BOSS 受影响）。
local function PhaseOrderWeight(phase)
    if not phase or phase == "" then return 0, 0 end
    local raw = tostring(phase)
    local pType, pIndex, rIndex = raw:match("^([pi])(%d+)r(%d+)$")
    if not pType then
        pType, pIndex = raw:match("^([pi])(%d+)$")
        rIndex = "1"
    end
    if not pType then return 0, 0 end
    local pi = tonumber(pIndex) or 0
    local ri = tonumber(rIndex) or 1
    local segWeight
    if pType == "p" then
        segWeight = (pi - 1) * 2 + 1  -- p1=1, p2=3, p3=5
    else
        segWeight = pi * 2  -- i1=2, i2=4
    end
    return ri, segWeight
end

function SemanticTimeline:SortWorkbenchRows(rows)
    table.sort(rows, function(a, b)
        -- 先按 (轮次, 阶段) 分组;同轮内 p1→i1→p2→i2→p3;轮次内按 time 排序
        local roundA, segA = PhaseOrderWeight(a.phase)
        local roundB, segB = PhaseOrderWeight(b.phase)
        if roundA ~= roundB then
            return roundA < roundB
        end
        if segA ~= segB then
            return segA < segB
        end
        -- 组内按时间排序
        local ta = tonumber(a.timeSec)
        local tb = tonumber(b.timeSec)
        if ta and tb and ta ~= tb then
            return ta < tb
        end
        local oa = tonumber(a.sortIndex)
        local ob = tonumber(b.sortIndex)
        if oa and ob and oa ~= ob then
            return oa < ob
        end
        if ta and not tb then
            return true
        end
        if tb and not ta then
            return false
        end
        return tostring(a.rowID or "") < tostring(b.rowID or "")
    end)
end

function SemanticTimeline:BuildBuiltinLineRowID(bossKey, lineNumber)
    return string.format("builtin:%s:%d", self:SerializeBossSelectorKey(bossKey), tonumber(lineNumber) or 0)
end

function SemanticTimeline:BuildTriggerSpellRowID(bossKey, spellID)
    return string.format("trigger:%s:%d", self:SerializeBossSelectorKey(bossKey), tonumber(spellID) or 0)
end

local function SameBossKey(left, right)
    local a = CopyBossKey(left)
    local b = CopyBossKey(right)
    if not a or not b then
        return false
    end
    return a.instanceType == b.instanceType
        and a.instanceID == b.instanceID
        and a.encounterID == b.encounterID
end

local function BuildSemanticPlanName(encounterName)
    local prefix = L["语义前缀"] or "[语义]"
    local normalizedName = TrimText(encounterName)
    if normalizedName == "" then
        normalizedName = L["未命名Boss"] or "未命名Boss"
    end
    return string.format("%s %s", prefix, normalizedName)
end

local function BuildPersonalSemanticPlanName(encounterName)
    return string.format("%s (%s)", BuildSemanticPlanName(encounterName), L["个人方案"] or "个人方案")
end

function SemanticTimeline:IsSemanticBossPlansInitialized()
    local db = EnsureSemanticDB()
    return db.workbench and db.workbench.plansInitialized == true
end

function SemanticTimeline:ResetSemanticBossPlansInitialization()
    local db = EnsureSemanticDB()
    if db.workbench then
        db.workbench.plansInitialized = false
    end
end

function SemanticTimeline:ScheduleSemanticBossPlansInitialization(cause, delay, force)
    if self.semanticInitTimer and self.semanticInitTimer.Cancel then
        self.semanticInitTimer:Cancel()
    end
    self.semanticInitTimer = C_Timer.NewTimer(delay or 0, function()
        self.semanticInitTimer = nil
        self:EnsureSemanticBossPlansInitialized({
            cause = cause,
            force = force == true,
        })
    end)
end

function SemanticTimeline:GetPreferredEditorTab()
    local db = EnsureSemanticDB()
    local tab = db.ui and db.ui.activeEditorTab or RESOLVE_SOURCE_TEAM
    if tab == RESOLVE_SOURCE_PERSONAL then
        return RESOLVE_SOURCE_PERSONAL
    end
    return RESOLVE_SOURCE_TEAM
end

function SemanticTimeline:BuildWorkbenchRowFromParsedLine(parsed, normalizedBossKey, lineNo, rowID, source)
    local content = TrimText(parsed.content or "")
    local displayText = TrimText(parsed.displayText or content)
    local rowType = WORKBENCH_ROW_TEXT
    local spellID = nil
    local label = displayText
    local payload = displayText
    local countdownFrom = nil

    local parsedSpellID = parsed.primarySpellID or (parsed.rawLine or content):match("{spell:(%d+):?%d*}")
    local parsedCountdown = parsed.modifiers and parsed.modifiers.ct and tonumber(parsed.modifiers.ct.value) or nil
    if parsedCountdown then
        rowType = WORKBENCH_ROW_COUNTDOWN
        countdownFrom = parsedCountdown
        spellID = parsedSpellID and tonumber(parsedSpellID) or nil
        payload = content
        label = displayText
    elseif parsedSpellID then
        rowType = WORKBENCH_ROW_SPELL
        spellID = tonumber(parsedSpellID)
        label = displayText
        if label == "" and spellID then
            label = self:GetSpellName(spellID)
        end
        payload = nil
    end

    return {
        rowID = tostring(rowID or ""),
        key = CopyBossKey(normalizedBossKey),
        timeSec = tonumber(parsed.time),
        phase = parsed.phase,
        rowType = rowType,
        spellID = spellID,
        label = label,
        textPayload = payload,
        countdownFrom = countdownFrom,
        source = source == "preset" and "preset" or "override",
        enabled = true,
        sortIndex = tonumber(lineNo) or 0,
        rawLine = parsed.rawLine,
        timePayload = parsed.rawLine and parsed.rawLine:match("{time:([^}]+)}") or nil,
        rawContent = parsed.content,
        segments = parsed.segments,
        spellTokens = parsed.spellTokens,
        modifiers = CopyInlineModifiers(parsed.modifiers),
        targetIndicators = CopyTargetIndicators(parsed.targetIndicators),
    }
end

function SemanticTimeline:BuildWorkbenchCommentRow(text, normalizedBossKey, lineNo, rowID, source)
    local payload = TrimText(text)
    return {
        rowID = tostring(rowID or ""),
        key = CopyBossKey(normalizedBossKey),
        timeSec = nil,
        rowType = WORKBENCH_ROW_COMMENT,
        spellID = nil,
        label = payload,
        textPayload = payload,
        countdownFrom = nil,
        source = source == "preset" and "preset" or "override",
        enabled = true,
        sortIndex = tonumber(lineNo) or 0,
    }
end

function SemanticTimeline:GetPlanFormat(text)
    if T.TriggerSyntax and T.TriggerSyntax.GetPlanFormat then
        return T.TriggerSyntax.GetPlanFormat(text)
    end
    return PLAN_FORMAT_TIMELINE
end

local function BuildStructuredBuiltinTemplate(bossKey, bodyKind, bodyText, encounterName)
    local normalizedBossKey = CopyBossKey(bossKey) or SemanticTimeline:GetCurrentBossSelectorKey()
    local resolvedEncounterName = TrimText(encounterName)
    if resolvedEncounterName == "" and normalizedBossKey then
        local keyText = SemanticTimeline:SerializeBossSelectorKey(normalizedBossKey)
        local meta = SemanticTimeline.builtinBossMetaByBossKey and SemanticTimeline.builtinBossMetaByBossKey[keyText] or nil
        local locale = GetLocale and GetLocale() or ""
        if locale == "zhTW" then
            resolvedEncounterName = TrimText((meta and meta.encounterNameZhTW) or "")
        elseif locale == "zhCN" then
            resolvedEncounterName = TrimText((meta and meta.encounterNameZh) or "")
        else
            resolvedEncounterName = TrimText((meta and meta.encounterName) or "")
        end
    end
    if resolvedEncounterName == "" and normalizedBossKey then
        resolvedEncounterName = SemanticTimeline:GetEncounterName(normalizedBossKey.encounterID)
            or (L["未命名Boss"] or "未命名Boss")
    end
    if resolvedEncounterName == "" then
        resolvedEncounterName = L["未命名Boss"] or "未命名Boss"
    end

    -- 12.0 下 spell 阶段锚点不能作为通用降级承诺，新模板不再自动写入 [设置]。
    local settingsText = ""

    if T.STNTemplate and T.STNTemplate.BuildTemplate then
        return T.STNTemplate.BuildTemplate({
            name = resolvedEncounterName,
            author = "STT",
            bodyKind = bodyKind,
            slots = {},
            settingsText = settingsText,
            bodyText = bodyText or "",
        })
    end
    return tostring(bodyText or "")
end

local function AppendEncounterSpellCatalogItem(out, bySpellID, spellID, firstOccurrence)
    local normalizedSpellID = tonumber(spellID)
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return
    end

    local item = bySpellID[normalizedSpellID]
    if not item then
        item = {
            spellID = normalizedSpellID,
            spellName = SemanticTimeline:GetSpellName(normalizedSpellID),
            occurrenceCount = 0,
            firstOccurrence = tonumber(firstOccurrence) or 0,
        }
        bySpellID[normalizedSpellID] = item
        out[#out + 1] = item
    end

    item.occurrenceCount = item.occurrenceCount + 1
    if tonumber(firstOccurrence) and ((tonumber(item.firstOccurrence) or 0) == 0 or tonumber(firstOccurrence) < tonumber(item.firstOccurrence)) then
        item.firstOccurrence = tonumber(firstOccurrence)
    end
end

local function AppendEncounterEventMappedSpells(out, bySpellID, encounterID)
    local encounterMap = T.SemanticEncounterEventMapS14 and T.SemanticEncounterEventMapS14[tonumber(encounterID) or 0] or nil
    if type(encounterMap) ~= "table" then
        return
    end

    local order = 100000
    for canonicalSpellID in pairs(encounterMap) do
        AppendEncounterSpellCatalogItem(out, bySpellID, canonicalSpellID, order)
        order = order + 1
    end
end

local function ExtractBuiltinTimelineEvent(line)
    local timePayload = tostring(line or ""):match("{time:([^}]+)}")
    if not timePayload then
        return nil
    end

    local spellPayload = tostring(line or ""):match("{spell:([^}]+)}")
    local spellID = spellPayload and tonumber(tostring(spellPayload):match("^(%d+)")) or nil
    if not spellID or spellID <= 0 then
        return nil
    end

    local timeSec = nil
    local parseTime = T.TimelineSyntax and T.TimelineSyntax.ParseTimeToSeconds or nil
    if parseTime then
        local coreTime = TrimText(tostring(timePayload):match("^%s*([^,]+)") or "")
        timeSec = parseTime(coreTime)
    end

    return spellID, timeSec
end

local function BuildBuiltinEncounterEventsFromText(text)
    local events = {}
    local occurrenceBySpell = {}
    local raw = tostring(text or ""):gsub("\r\n", "\n")

    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = TrimText(line)
        if trimmed ~= "" then
            local spellID, timeSec = ExtractBuiltinTimelineEvent(trimmed)
            if spellID and spellID > 0 then
                local occurrence = (occurrenceBySpell[spellID] or 0) + 1
                occurrenceBySpell[spellID] = occurrence
                events[#events + 1] = {
                    spellID = spellID,
                    timeSec = timeSec,
                    occurrence = occurrence,
                    eventType = "BUILTIN_TEXT",
                }
            end
        end
    end

    return events
end

local function BuildEncounterSpellCatalogFromRawText(text)
    local out = {}
    local bySpellID = {}

    for _, event in ipairs(BuildBuiltinEncounterEventsFromText(text)) do
        AppendEncounterSpellCatalogItem(out, bySpellID, event.spellID, event.occurrence)
    end

    table.sort(out, function(a, b)
        if (tonumber(a.firstOccurrence) or 0) ~= (tonumber(b.firstOccurrence) or 0) then
            return (tonumber(a.firstOccurrence) or 0) < (tonumber(b.firstOccurrence) or 0)
        end
        return (tonumber(a.spellID) or 0) < (tonumber(b.spellID) or 0)
    end)

    return out
end

-- 规范化内置模板 value:裸字符串视为 mythic 单档;table 形式 { mythic, heroic[, mplus] } 原样保留。
local function NormalizeBuiltinPlanValue(value)
    if type(value) == "table" then
        local out = {}
        if type(value.mythic) == "string" then out.mythic = value.mythic end
        if type(value.heroic) == "string" then out.heroic = value.heroic end
        if type(value.mplus)  == "string" then out.mplus  = value.mplus  end
        return out
    elseif type(value) == "string" then
        return { mythic = value }
    end
    return {}
end

local function BuildBuiltinPlanCaches(self)
    local builtinPlans = T.SemanticBuiltinPlansS14 or {}
    local builtinMeta = T.SemanticBuiltinBossMetaS14 or {}

    self.builtinPlanTextByBossKey = {}
    self.builtinBossMetaByBossKey = {}

    for bossKeyText, value in pairs(builtinPlans) do
        local bossKey = self:ParseBossSelectorKey(bossKeyText)
        if bossKey then
            local normalizedKeyText = self:SerializeBossSelectorKey(bossKey)
            self.builtinPlanTextByBossKey[normalizedKeyText] = NormalizeBuiltinPlanValue(value)
            self.builtinBossMetaByBossKey[normalizedKeyText] = builtinMeta[bossKeyText] or builtinMeta[normalizedKeyText] or {}
        end
    end
end

-- 从规范化 table 中按 difficulty 取对应档文本;缺失目标档时回落 mythic。
local function PickBuiltinPlanText(planTable, difficulty)
    if type(planTable) ~= "table" then return "" end
    local wanted = difficulty or "mythic"
    local text = planTable[wanted]
    if type(text) ~= "string" or text == "" then
        text = planTable.mythic
    end
    return type(text) == "string" and text or ""
end

local function NormalizeBuiltinBody(text)
    local lines = {}
    local normalized = tostring(text or ""):gsub("\r\n", "\n")
    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    while #lines > 0 and TrimText(lines[1]) == "" do
        table.remove(lines, 1)
    end
    while #lines > 0 and TrimText(lines[#lines]) == "" do
        table.remove(lines, #lines)
    end
    return table.concat(lines, "\n")
end

local function CopyPhaseDisplaySpans(spans)
    if type(spans) ~= "table" then
        return nil
    end
    local out = {}
    for phaseKey, span in pairs(spans) do
        local number = tonumber(span)
        if number and number > 0 then
            out[tostring(phaseKey)] = number
        end
    end
    return next(out) and out or nil
end

function SemanticTimeline:GetEmbeddedTemplateText(canonicalSpellID, context)
    local normalizedSpellID = tonumber(canonicalSpellID)
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return ""
    end

    local normalizedContext = type(context) == "table" and context or {}
    local encounterID = tonumber(normalizedContext.encounterID)
    local embedded = T.SemanticEmbeddedTriggerTemplatesS14 or {}
    local encounterTexts = type(embedded.textByEncounterID) == "table" and embedded.textByEncounterID[encounterID or 0] or nil
    local text = encounterTexts and encounterTexts[normalizedSpellID] or nil
    if type(text) == "string" and text ~= "" then
        return text
    end

    text = type(embedded.textBySpellID) == "table" and embedded.textBySpellID[normalizedSpellID] or nil
    if type(text) == "string" and text ~= "" then
        return text
    end

    text = T.SemanticSpellTextsS14 and T.SemanticSpellTextsS14[normalizedSpellID] or nil
    if type(text) == "string" and text ~= "" then
        return text
    end

    return ""
end

function SemanticTimeline:GetEmbeddedRetimeAction(canonicalSpellID, context)
    local normalizedSpellID = tonumber(canonicalSpellID)
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return nil
    end

    local normalizedContext = type(context) == "table" and context or {}
    local encounterID = tonumber(normalizedContext.encounterID)
    local embedded = T.SemanticEmbeddedTriggerTemplatesS14 or {}
    local encounterRules = type(embedded.retimeByEncounterID) == "table" and embedded.retimeByEncounterID[encounterID or 0] or nil
    local rule = encounterRules and encounterRules[normalizedSpellID] or nil
    if type(rule) ~= "table" then
        return nil
    end

    return {
        action = tostring(rule.action or ""),
        phase = rule.phase ~= nil and tostring(rule.phase) or nil,
    }
end

function SemanticTimeline:BuildTriggerTemplateTextForBoss(bossKey)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local cacheKey = self:SerializeBossSelectorKey(normalizedBossKey)

    self._triggerTemplateCache = self._triggerTemplateCache or {}
    if self._triggerTemplateCache[cacheKey] then
        return self._triggerTemplateCache[cacheKey]
    end

    local builder = T.TriggerSyntax and T.TriggerSyntax.BuildRuleLine
    local lines = {}
    local catalog = self:GetEncounterSpellCatalog(normalizedBossKey)
    if #catalog == 0 then
        local planTable = self.builtinPlanTextByBossKey and self.builtinPlanTextByBossKey[cacheKey] or nil
        local rawText = PickBuiltinPlanText(planTable, "mythic")
        catalog = BuildEncounterSpellCatalogFromRawText(rawText)
    end

    for _, item in ipairs(catalog or {}) do
        local spellID = tonumber(item.spellID)
        if spellID and spellID > 0 then
            local semanticText = self:GetEmbeddedTemplateText(spellID, {
                encounterID = normalizedBossKey and normalizedBossKey.encounterID or 0,
                bossKey = normalizedBossKey,
            })
            if builder then
                lines[#lines + 1] = builder(spellID, nil, nil, semanticText)
            else
                if semanticText ~= "" then
                    lines[#lines + 1] = string.format("{on:spell:%d} {所有人}%s", spellID, semanticText)
                else
                    lines[#lines + 1] = string.format("{on:spell:%d}", spellID)
                end
            end
        end
    end

    -- 追加 event 规则（与 spell 规则共存）
    local eventPlans = T.SemanticBuiltinEventPlansS14
    local eventText = eventPlans and eventPlans[cacheKey] or ""
    for eventLine in eventText:gmatch("[^\n]+") do
        local trimmed = eventLine:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            lines[#lines + 1] = trimmed
        end
    end

    local result = BuildStructuredBuiltinTemplate(normalizedBossKey, "trigger", table.concat(lines, "\n"))
    self._triggerTemplateCache[cacheKey] = result
    return result
end

local function BuildErrorPayload(err)
    return {
        line = tonumber(err and err.line) or 0,
        reason = tostring(err and err.reason or ""),
        content = tostring(err and err.content or ""),
        message = tostring(err and err.message or ""),
        fix = tostring(err and err.fix or ""),
        severity = tostring(err and err.severity or "error"),
    }
end

local function BuildTimelineParseError(line, content)
    return {
        line = tonumber(line) or 0,
        reason = L["时间格式无效"] or "时间格式无效",
        content = tostring(content or ""),
        message = "时间格式不对",
        fix = "写成 {time:00:12} 或 {time:12}",
        severity = "error",
    }
end

function SemanticTimeline:CompileTextToRows(text, bossKey, lineToRowID, existingRows, options)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local normalizedBindings = lineToRowID or {}
    local existingBySignature = {}
    local usedRowIDs = {}
    local rows = {}
    local errors = {}
    local newLineToRowID = {}
    local lineNo = 0
    local opts = options or {}
    local source = opts.defaultSource == "preset" and "preset" or "override"
    local templateOpts = opts.relaxed == true and { relaxed = true } or nil
    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text, templateOpts) or nil
    local slotVisualHints = T.BuildSlotVisualHints and T.BuildSlotVisualHints(template and template.slots, template and template.usedSlots, template and template.slotVisualSpecs) or nil
    local raw = tostring(template and template.processedText or text or ""):gsub("\r\n", "\n")
    local lineMap = template and template.bodyLineMap or nil

    for _, err in ipairs(template and template.errors or {}) do
        errors[#errors + 1] = BuildErrorPayload(err)
    end

    if not template or not IsUsableTemplateBody(template, "timeline") then
        return rows, errors, newLineToRowID
    end

    for _, row in ipairs(existingRows or {}) do
        if row and row.rowID then
            local signature = BuildRowSignature(row)
            existingBySignature[signature] = existingBySignature[signature] or {}
            local rowIDs = existingBySignature[signature]
            rowIDs[#rowIDs + 1] = row.rowID
        end
    end

    local function AcquireRowID(preferredLine, signature)
        if opts.fixedRowIDs then
            local fixed = self:BuildBuiltinLineRowID(normalizedBossKey, preferredLine)
            usedRowIDs[fixed] = true
            return fixed
        end

        local candidate = normalizedBindings[preferredLine]
        if type(candidate) == "string" and candidate ~= "" and not usedRowIDs[candidate] then
            usedRowIDs[candidate] = true
            return candidate
        end

        local pool = existingBySignature[signature]
        if pool then
            for _, rowID in ipairs(pool) do
                if not usedRowIDs[rowID] then
                    usedRowIDs[rowID] = true
                    return rowID
                end
            end
        end

        local generated = self:GenerateRowID()
        usedRowIDs[generated] = true
        return generated
    end

    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        lineNo = lineNo + 1
        local trimmed = TrimText(line)
        local actualLineNo = tonumber(lineMap and lineMap[lineNo]) or lineNo
        if trimmed ~= "" then
            local parsed = T.TimelineSyntax and T.TimelineSyntax.ParseTimelineLine and T.TimelineSyntax.ParseTimelineLine(trimmed) or nil
            if not parsed then
                if trimmed:find("{time:", 1, true) then
                    errors[#errors + 1] = BuildTimelineParseError(actualLineNo, trimmed)
                else
                    local probe = self:BuildWorkbenchCommentRow(trimmed, normalizedBossKey, actualLineNo, "probe", source)
                    local signature = BuildRowSignature(probe)
                    local rowID = AcquireRowID(actualLineNo, signature)
                    local row = self:BuildWorkbenchCommentRow(trimmed, normalizedBossKey, actualLineNo, rowID, source)
                    row.slotVisualHints = slotVisualHints
                    rows[#rows + 1] = row
                    newLineToRowID[actualLineNo] = rowID
                end
            else
                local probe = self:BuildWorkbenchRowFromParsedLine(parsed, normalizedBossKey, actualLineNo, "probe", source)
                local signature = BuildRowSignature(probe)
                local rowID = AcquireRowID(actualLineNo, signature)
                local row = self:BuildWorkbenchRowFromParsedLine(parsed, normalizedBossKey, actualLineNo, rowID, source)
                row.slotVisualHints = slotVisualHints
                row.phaseDisplaySpans = CopyPhaseDisplaySpans(opts.phaseDisplaySpans)
                rows[#rows + 1] = row
                newLineToRowID[actualLineNo] = rowID
            end
        end
    end

    self:SortWorkbenchRows(rows)
    return rows, errors, newLineToRowID
end

function SemanticTimeline:GetEncounterSpellCatalog(bossKey)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local encounter = self.encountersByID and self.encountersByID[tonumber(normalizedBossKey.encounterID) or 0] or nil
    local out = {}
    local bySpellID = {}

    for _, event in ipairs(encounter and encounter.events or {}) do
        AppendEncounterSpellCatalogItem(out, bySpellID, event.spellID, event.occurrence)
    end
    AppendEncounterEventMappedSpells(out, bySpellID, normalizedBossKey.encounterID)

    table.sort(out, function(a, b)
        if (tonumber(a.firstOccurrence) or 0) ~= (tonumber(b.firstOccurrence) or 0) then
            return (tonumber(a.firstOccurrence) or 0) < (tonumber(b.firstOccurrence) or 0)
        end
        return (tonumber(a.spellID) or 0) < (tonumber(b.spellID) or 0)
    end)

    return out
end

function SemanticTimeline:CompileTriggerTextToRows(text, bossKey, options)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local opts = options or {}
    local parsed = T.TriggerSyntax and T.TriggerSyntax.ParseTriggerText and T.TriggerSyntax.ParseTriggerText(text, opts.relaxed == true and { relaxed = true } or nil) or {
        rules = {},
        errors = {},
        defaultRules = {},
    }

    local rows = {}
    local lineToRowID = {}
    if not parsed or not parsed.templateInfo or parsed.templateInfo.isValid ~= true or parsed.templateInfo.bodyKind ~= "trigger" then
        local errors = {}
        for _, err in ipairs(parsed and parsed.errors or {}) do
            errors[#errors + 1] = BuildErrorPayload(err)
        end
        return rows, errors, lineToRowID, parsed
    end

    local catalog = self:GetEncounterSpellCatalog(normalizedBossKey)
    for index, item in ipairs(catalog) do
        local defaultRule = parsed.defaultRules and parsed.defaultRules[item.spellID] or nil
        local rowID = self:BuildTriggerSpellRowID(normalizedBossKey, item.spellID)
        rows[#rows + 1] = {
            rowID = rowID,
            key = CopyBossKey(normalizedBossKey),
            timeSec = nil,
            rowType = WORKBENCH_ROW_SPELL,
            spellID = item.spellID,
            label = item.spellName,
            textPayload = defaultRule and tostring(defaultRule.payload or "") or "",
            countdownFrom = nil,
            source = "override",
            enabled = true,
            sortIndex = index,
            triggerMode = defaultRule and tostring(defaultRule.mode or "") or nil,
            isConfigured = defaultRule ~= nil,
            occurrenceCount = tonumber(item.occurrenceCount) or 0,
            formatKind = PLAN_FORMAT_TRIGGER,
        }
        if defaultRule and tonumber(defaultRule.line) then
            lineToRowID[tonumber(defaultRule.line)] = rowID
        end
    end

    local errors = {}
    for _, err in ipairs(parsed.errors or {}) do
        errors[#errors + 1] = BuildErrorPayload(err)
    end

    return rows, errors, lineToRowID, parsed
end

function SemanticTimeline:GetBuiltinPhaseDisplaySpans(bossKey, difficulty)
    self:EnsureTemplateReady()
    local normalizedBossKey = type(bossKey) == "string" and self:ParseBossSelectorKey(bossKey)
        or (CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey())
    local keyText = self:SerializeBossSelectorKey(normalizedBossKey)
    local meta = self.builtinBossMetaByBossKey and self.builtinBossMetaByBossKey[keyText] or nil
    local allSpans = type(meta) == "table" and meta.phaseDisplaySpans or nil
    if type(allSpans) ~= "table" then
        return nil
    end
    local wanted = difficulty or "mythic"
    local spans = allSpans[wanted]
    if type(spans) ~= "table" and difficulty == nil then
        spans = allSpans.mythic
    end
    return CopyPhaseDisplaySpans(spans)
end

function SemanticTimeline:ResolveBuiltinDifficultyForText(bossKey, text)
    self:EnsureTemplateReady()
    local normalizedBossKey = type(bossKey) == "string" and self:ParseBossSelectorKey(bossKey)
        or (CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey())
    local keyText = self:SerializeBossSelectorKey(normalizedBossKey)
    local planTable = self.builtinPlanTextByBossKey and self.builtinPlanTextByBossKey[keyText] or nil
    if type(planTable) ~= "table" then
        return nil
    end

    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text) or nil
    local body = NormalizeBuiltinBody(template and template.processedText or text)
    for _, difficulty in ipairs({ "mythic", "heroic", "mplus" }) do
        local builtinBody = NormalizeBuiltinBody(PickBuiltinPlanText(planTable, difficulty))
        if builtinBody ~= "" and body == builtinBody then
            return difficulty
        end
    end
    return nil
end

function SemanticTimeline:CompileBuiltinPlanText(bossKey, text, difficulty)
    local builtinText = self:GetBuiltinPlanText(bossKey, difficulty)
    local sourceText = builtinText ~= "" and builtinText or text
    if self:GetPlanFormat(sourceText) == PLAN_FORMAT_TRIGGER then
        local rows = self:CompileTriggerTextToRows(sourceText, bossKey)
        return rows or {}
    end
    return self:CompileTextToRows(sourceText, bossKey, nil, nil, {
        fixedRowIDs = true,
        defaultSource = "preset",
        phaseDisplaySpans = self:GetBuiltinPhaseDisplaySpans(bossKey, difficulty),
    })
end

function SemanticTimeline:BuildWorkbenchTemplateRows()
    self.workbenchTemplateRowsByBossKey = {}

    for bossKeyText, planTable in pairs(self.builtinPlanTextByBossKey or {}) do
        local bossKey = self:ParseBossSelectorKey(bossKeyText)
        if bossKey then
            local normalizedKeyText = self:SerializeBossSelectorKey(bossKey)
            local rows = self:CompileBuiltinPlanText(bossKey, PickBuiltinPlanText(planTable, "mythic"))
            self.workbenchTemplateRowsByBossKey[normalizedKeyText] = rows
        end
    end
end

-- difficulty 可选,取值 "mythic" / "heroic" / "mplus";省略时默认 "mythic"。
-- 本参数来自未来"战术方案难度区分"feature 的自动切档;当前所有调用方未传入时沿用 mythic 行为。
function SemanticTimeline:GetBuiltinPlanText(bossKey, difficulty)
    self:EnsureTemplateReady()
    local normalizedBossKey
    local keyText
    if type(bossKey) == "string" then
        keyText = bossKey
        normalizedBossKey = self:ParseBossSelectorKey(keyText)
    else
        normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
        keyText = self:SerializeBossSelectorKey(normalizedBossKey)
    end

    local planTable = self.builtinPlanTextByBossKey and self.builtinPlanTextByBossKey[keyText] or nil
    local raw = PickBuiltinPlanText(planTable, difficulty)
    return BuildStructuredBuiltinTemplate(normalizedBossKey, "timeline", raw)
end

function SemanticTimeline:GetLegacyBuiltinTimelineText(bossKey, difficulty)
    self:EnsureTemplateReady()
    local keyText
    if type(bossKey) == "string" then
        keyText = bossKey
    else
        keyText = self:SerializeBossSelectorKey(CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey())
    end
    local planTable = self.builtinPlanTextByBossKey and self.builtinPlanTextByBossKey[keyText] or nil
    return PickBuiltinPlanText(planTable, difficulty)
end

function SemanticTimeline:GetWorkbenchBossCatalogFromBuiltinText()
    self:EnsureTemplateReady()
    local out = {}
    for _, instance in ipairs(self.instances or {}) do
        for _, encounter in ipairs(instance.encounters or {}) do
            local bossKey = self:BuildBossSelectorKey(instance.type, instance.instanceID, encounter.encounterID)
            local keyText = self:SerializeBossSelectorKey(bossKey)
            local meta = self.builtinBossMetaByBossKey and self.builtinBossMetaByBossKey[keyText] or nil
            out[#out + 1] = {
                key = CopyBossKey(bossKey),
                keyText = keyText,
                instanceType = instance.type,
                instanceID = instance.instanceID,
                instanceName = self:GetLocalizedInstanceName(instance) or instance.name or "",
                encounterID = encounter.encounterID,
                encounterName = self:GetLocalizedEncounterName(encounter) or encounter.name or "",
                hasExactTime = meta and meta.hasExactTime == true or false,
            }
        end
    end
    return out
end

function SemanticTimeline:GetTemplateRowsByBossKey(bossKey)
    local keyText = self:SerializeBossSelectorKey(CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey())
    local sourceRows = self.workbenchTemplateRowsByBossKey and self.workbenchTemplateRowsByBossKey[keyText] or nil
    local out = {}
    for _, row in ipairs(sourceRows or {}) do
        out[#out + 1] = CopyRow(row)
    end
    return out
end

local function GetPlanCacheKey(planID, options)
    local planKey = tostring(planID or "")
    if planKey == "" then
        return ""
    end

    local relaxed = false
    if type(options) == "table" then
        relaxed = options.relaxed == true
    else
        relaxed = options == true
    end
    return planKey .. (relaxed and ":relaxed" or ":strict")
end

function SemanticTimeline:GetCompiledPlanCache(planID, options)
    local key = GetPlanCacheKey(planID, options)
    if key == "" then
        return nil
    end
    self.planCompiledCache = self.planCompiledCache or {}
    local cached = self.planCompiledCache[key]
    if cached then
        -- 更新 LRU 访问顺序
        local order = self.planCompiledCacheOrder or {}
        for i = #order, 1, -1 do
            if order[i] == key then
                table.remove(order, i)
                break
            end
        end
        order[#order + 1] = key
        self.planCompiledCacheOrder = order
    end
    return cached
end

local PLAN_CACHE_MAX = 30

function SemanticTimeline:SetCompiledPlanCache(planID, payload, options)
    local key = GetPlanCacheKey(planID, options)
    if key == "" then
        return
    end
    self.planCompiledCache = self.planCompiledCache or {}
    self.planCompiledCacheOrder = self.planCompiledCacheOrder or {}

    -- 更新访问顺序
    local order = self.planCompiledCacheOrder
    for i = #order, 1, -1 do
        if order[i] == key then
            table.remove(order, i)
            break
        end
    end
    order[#order + 1] = key

    -- 存入缓存
    self.planCompiledCache[key] = payload

    -- LRU 淘汰
    while #order > PLAN_CACHE_MAX do
        local evictKey = table.remove(order, 1)
        self.planCompiledCache[evictKey] = nil
    end
end

function SemanticTimeline:InvalidateCompiledPlanCache(planID)
    if not self.planCompiledCache then
        return
    end
    local planKey = tostring(planID or "")
    if planKey == "" then
        return
    end
    local keys = {
        GetPlanCacheKey(planID, false),
        GetPlanCacheKey(planID, true),
    }
    for _, key in ipairs(keys) do
        self.planCompiledCache[key] = nil
    end
    if self.planCompiledCacheOrder then
        for i = #self.planCompiledCacheOrder, 1, -1 do
            local key = self.planCompiledCacheOrder[i]
            if key == keys[1] or key == keys[2] then
                table.remove(self.planCompiledCacheOrder, i)
            end
        end
    end
end

function SemanticTimeline:WipeCompiledPlanCache()
    self.planCompiledCache = nil
    self.planCompiledCacheOrder = nil
    self._triggerTemplateCache = nil
end

function SemanticTimeline:BuildRowsCopy(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do
        out[#out + 1] = CopyRow(row)
    end
    return out
end

function SemanticTimeline:BuildErrorsCopy(errors)
    local out = {}
    for _, err in ipairs(errors or {}) do
        out[#out + 1] = BuildErrorPayload(err)
    end
    return out
end

function SemanticTimeline:GetBaseRowsForScope(scopeMode, bossKey)
    return self:GetTemplateRowsByBossKey(bossKey)
end

function SemanticTimeline:GetEffectiveRows(scopeMode, bossKey)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local currentBossKey = self:GetCurrentBossSelectorKey()
    if SameBossKey(normalizedBossKey, currentBossKey) then
        return self:GetCurrentEffectiveRows()
    end

    local plan = self:EnsurePlanBindingForKey(WORKBENCH_SCOPE_BY_BOSS, normalizedBossKey)
    if not plan then
        return self:GetTemplateRowsByBossKey(normalizedBossKey)
    end

    local compiled = self:CompilePlanContentForBoss(tostring(plan.content or ""), normalizedBossKey, plan.id)
    return compiled.rows or {}
end

local function IsStructuredTemplateContent(text)
    local info = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text or "") or nil
    return info and info.hasBlocks == true
end

function SemanticTimeline:SetRowsForScope(scopeMode, bossKey, rows)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local plan = self:EnsurePlanBindingForKey(WORKBENCH_SCOPE_BY_BOSS, normalizedBossKey)
    if not plan then
        return false, "plan_unavailable"
    end
    if IsStructuredTemplateContent(plan.content or "") then
        return false, "structured_template_manual_only"
    end

    local orderedRows = self:BuildRowsCopy(rows)
    self:SortWorkbenchRows(orderedRows)
    local text, lineToRowID = self:BuildRowsToTimelineText(orderedRows)
    self:SetPlanRowBindings(plan.id, lineToRowID)
    self:SetCompiledPlanCache(plan.id, {
        bossKey = CopyBossKey(normalizedBossKey),
        content = text,
        rows = self:BuildRowsCopy(orderedRows),
        errors = {},
        lineToRowID = lineToRowID,
    })

    local note = T.Note
    if note and note.UpdatePlan then
        note:UpdatePlan(plan.id, { content = text })
    end
    return true
end

function SemanticTimeline:UpsertRowByID(rowID, patch)
    local normalizedRowID = tostring(rowID or "")
    if normalizedRowID == "" then
        return false, "invalid_row_id"
    end

    local compiled = self:CompileCurrentPlanText()
    local rows = self:BuildRowsCopy(compiled and compiled.rows or {})
    local bossKey = self:GetCurrentBossSelectorKey()
    local found = false

    for _, row in ipairs(rows) do
        if row.rowID == normalizedRowID then
            if patch.timeSec ~= nil then row.timeSec = tonumber(patch.timeSec) end
            if patch.rowType ~= nil then row.rowType = NormalizeRowType(patch.rowType) end
            if patch.spellID ~= nil then row.spellID = tonumber(patch.spellID) end
            if patch.label ~= nil then row.label = tostring(patch.label) end
            if patch.textPayload ~= nil then row.textPayload = tostring(patch.textPayload) end
            if patch.countdownFrom ~= nil then row.countdownFrom = tonumber(patch.countdownFrom) end
            row.enabled = true
            row.key = CopyBossKey(bossKey)
            found = true
            break
        end
    end

    if not found then
        rows[#rows + 1] = {
            rowID = normalizedRowID,
            key = CopyBossKey(bossKey),
            timeSec = tonumber(patch.timeSec),
            rowType = NormalizeRowType(patch.rowType),
            spellID = tonumber(patch.spellID),
            label = tostring(patch.label or ""),
            textPayload = patch.textPayload ~= nil and tostring(patch.textPayload) or nil,
            countdownFrom = tonumber(patch.countdownFrom),
            source = "override",
            enabled = true,
            sortIndex = #rows + 1,
        }
    end

    return self:SetRowsForScope(WORKBENCH_SCOPE_BY_BOSS, bossKey, rows)
end

function SemanticTimeline:DeleteRowByID(rowID)
    local normalizedRowID = tostring(rowID or "")
    if normalizedRowID == "" then
        return false, "invalid_row_id"
    end

    local compiled = self:CompileCurrentPlanText()
    local rows = {}
    local removed = false
    for _, row in ipairs(compiled and compiled.rows or {}) do
        if row.rowID ~= normalizedRowID then
            rows[#rows + 1] = CopyRow(row)
        else
            removed = true
        end
    end
    if not removed then
        return false, "missing_row"
    end

    return self:SetRowsForScope(WORKBENCH_SCOPE_BY_BOSS, self:GetCurrentBossSelectorKey(), rows)
end

function SemanticTimeline:InsertRowForCurrent(rowData)
    local rowID = rowData and rowData.rowID
    if type(rowID) ~= "string" or rowID == "" then
        rowID = self:GenerateRowID()
    end

    local compiled = self:CompileCurrentPlanText()
    local rows = self:BuildRowsCopy(compiled and compiled.rows or {})
    rows[#rows + 1] = {
        rowID = rowID,
        key = CopyBossKey(self:GetCurrentBossSelectorKey()),
        timeSec = rowData and tonumber(rowData.timeSec),
        rowType = NormalizeRowType(rowData and rowData.rowType),
        spellID = rowData and tonumber(rowData.spellID),
        label = tostring((rowData and rowData.label) or ""),
        textPayload = rowData and rowData.textPayload ~= nil and tostring(rowData.textPayload) or nil,
        countdownFrom = rowData and tonumber(rowData.countdownFrom),
        source = "override",
        enabled = true,
        sortIndex = #rows + 1,
    }

    local ok = self:SetRowsForScope(WORKBENCH_SCOPE_BY_BOSS, self:GetCurrentBossSelectorKey(), rows)
    if not ok then
        return nil, "upsert_failed"
    end
    return rowID
end

function SemanticTimeline:DeleteRowForCurrent(rowID)
    return self:DeleteRowByID(rowID)
end

local function TrimOuterBlankLines(text)
    local lines = {}
    local normalized = tostring(text or ""):gsub("\r\n", "\n")
    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end

    while #lines > 0 and TrimText(lines[1]) == "" do
        table.remove(lines, 1)
    end
    while #lines > 0 and TrimText(lines[#lines]) == "" do
        table.remove(lines, #lines)
    end

    return table.concat(lines, "\n")
end

local function ExtractLegacyTriggerBody(text)
    local lines = {}
    local normalized = tostring(text or ""):gsub("\r\n", "\n")
    local firstMeaningfulSeen = false
    local legacyHeaderStripped = false

    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = TrimText(line)
        if not firstMeaningfulSeen then
            if trimmed == "" then
                -- 跳过头部空行
            else
                firstMeaningfulSeen = true
                if trimmed == "STN_TRIGGER_V1" then
                    legacyHeaderStripped = true
                else
                    lines[#lines + 1] = line
                end
            end
        else
            lines[#lines + 1] = line
        end
    end

    return TrimOuterBlankLines(table.concat(lines, "\n")), legacyHeaderStripped
end

function SemanticTimeline:NormalizeSemanticBossPlanContent(bossKey, content, builtinText, encounterName)
    local rawContent = tostring(content or "")

    -- 团队方案允许用户主动清空；仅首次建档时由调用方决定是否注入内置模板
    if rawContent == "" then
        return "", false
    end

    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local expectedKind = PLAN_FORMAT_TIMELINE
    local info = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(rawContent) or nil

    if info and info.isValid == true and info.bodyKind == expectedKind then
        return rawContent, false
    end

    -- 尝试 wrap legacy 格式（兼容旧格式迁移）
    local wrapped = nil
    if expectedKind == PLAN_FORMAT_TIMELINE then
        local legacyBody = TrimOuterBlankLines(rawContent)
        if legacyBody ~= "" and legacyBody:find("{time:", 1, true) then
            wrapped = BuildStructuredBuiltinTemplate(normalizedBossKey, "timeline", legacyBody, encounterName)
        end
    else
        local legacyBody = ExtractLegacyTriggerBody(rawContent)
        if legacyBody ~= "" and legacyBody:find("{spell:", 1, true) and legacyBody:find("|", 1, true) then
            wrapped = BuildStructuredBuiltinTemplate(normalizedBossKey, "trigger", legacyBody, encounterName)
        end
    end

    if wrapped then
        local wrappedInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(wrapped) or nil
        if wrappedInfo and wrappedInfo.isValid == true and wrappedInfo.bodyKind == expectedKind then
            return wrapped, true
        end
    end

    -- 用户有内容但格式不合法 → 保留用户内容，不回退到内置模板
    return rawContent, false
end

function SemanticTimeline:NormalizePersonalBossPlanContent(bossKey, content)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local rawContent = tostring(content or "")
    if rawContent == "" then
        return "", false
    end

    local expectedKind = normalizedBossKey.instanceType == WORKBENCH_INSTANCE_DUNGEON and PLAN_FORMAT_TRIGGER or PLAN_FORMAT_TIMELINE
    local templateOpts = expectedKind == PLAN_FORMAT_TIMELINE and { relaxed = true } or nil
    local info = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(rawContent, templateOpts) or nil
    if info and info.isValid == true and info.bodyKind == expectedKind then
        return rawContent, false
    end

    if expectedKind == PLAN_FORMAT_TRIGGER then
        local legacyBody = ExtractLegacyTriggerBody(rawContent)
        if legacyBody ~= "" and legacyBody:find("{spell:", 1, true) and legacyBody:find("|", 1, true) then
            local wrapped = BuildStructuredBuiltinTemplate(normalizedBossKey, "trigger", legacyBody)
            local wrappedInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(wrapped) or nil
            if wrappedInfo and wrappedInfo.isValid == true and wrappedInfo.bodyKind == expectedKind then
                return wrapped, true
            end
        end
    end

    return rawContent, false
end

function SemanticTimeline:EnsureSemanticBossPlansInitialized(options)
    self:EnsureTemplateReady()

    local note = T.Note
    if not (note and note.GetPlan and note.GetSemanticBossPlanID and note.UpsertSemanticBossPlan and note.UpsertPersonalBossPlan) then
        return false
    end

    local db = EnsureSemanticDB()
    local wb = db.workbench
    local opts = type(options) == "table" and options or nil
    if wb.plansInitialized == true and not (opts and opts.force == true) then
        return true
    end

    local legacyBossPlanMap = type(wb.bossPlanMap) == "table" and wb.bossPlanMap or nil
    local claimedPlanIDs = {}

    local catalog = self:GetWorkbenchBossCatalogFromBuiltinText()
    for _, bossInfo in ipairs(catalog) do
        local bossKeyText = tostring(bossInfo.keyText or "")
        if bossKeyText ~= "" then
            local existingSemanticID = note:GetSemanticBossPlanID(bossKeyText)
            if existingSemanticID then
                claimedPlanIDs[existingSemanticID] = true
            end
        end
    end

    for _, bossInfo in ipairs(catalog) do
        local bossKey = CopyBossKey(bossInfo.key)
        local bossKeyText = self:SerializeBossSelectorKey(bossKey)
        local encounterName = bossInfo.encounterName
            or self:GetEncounterName(bossInfo.encounterID)
            or (L["未命名Boss"] or "未命名Boss")
        local planName = BuildSemanticPlanName(encounterName)
        local personalPlanName = BuildPersonalSemanticPlanName(encounterName)
        local builtinText = self:GetBuiltinPlanText(bossKeyText)
        local semanticPlanID = note:GetSemanticBossPlanID(bossKeyText)

        if semanticPlanID then
            local semanticPlan = note:GetPlan(semanticPlanID)
            local currentContent = semanticPlan and semanticPlan.content or ""
            local currentVersion = T.SemanticBuiltinPlansVersionS14 or ""
            local storedVersion = wb.bossTemplateVer[bossKeyText] or ""
            local needsUpgrade = (currentVersion ~= "" and currentVersion ~= storedVersion)
            local legacyBuiltin = bossKey.instanceType == WORKBENCH_INSTANCE_DUNGEON
                and self:GetLegacyBuiltinTimelineText(bossKey)
                or ""

            local forceContent = false
            if needsUpgrade then
                local storedDigest = wb.bossTemplateDigest[bossKeyText]
                if storedDigest ~= nil then
                    local playerDigest = ComputeContentDigest(currentContent)
                    if playerDigest == storedDigest then
                        forceContent = true
                    end
                elseif currentContent ~= "" then
                    wb.bossTemplateDigest[bossKeyText] = ComputeContentDigest(currentContent)
                end
            end
            if legacyBuiltin ~= "" and currentContent == legacyBuiltin then
                forceContent = true
            end
            local legacyTriggerBuiltin = bossKey.instanceType == WORKBENCH_INSTANCE_DUNGEON
                and self:BuildTriggerTemplateTextForBoss(bossKey)
                or ""
            if legacyTriggerBuiltin ~= "" and currentContent == legacyTriggerBuiltin then
                forceContent = true
            end

            local normalizedContent, _ = self:NormalizeSemanticBossPlanContent(
                bossKey,
                forceContent and builtinText or currentContent,
                builtinText,
                encounterName
            )
            note:UpsertSemanticBossPlan(bossKeyText, planName, normalizedContent, {
                planID = semanticPlanID,
                forceContent = forceContent,
                onlyIfEmpty = not forceContent,
            })

            if forceContent then
                wb.bossTemplateVer[bossKeyText] = currentVersion
                if normalizedContent ~= "" then
                    wb.bossTemplateDigest[bossKeyText] = ComputeContentDigest(normalizedContent)
                else
                    wb.bossTemplateDigest[bossKeyText] = nil
                end
            elseif needsUpgrade then
                wb.bossTemplateVer[bossKeyText] = currentVersion
            elseif storedVersion == "" then
                wb.bossTemplateVer[bossKeyText] = currentVersion
                if currentContent ~= "" then
                    wb.bossTemplateDigest[bossKeyText] = ComputeContentDigest(currentContent)
                else
                    wb.bossTemplateDigest[bossKeyText] = nil
                end
            end

            claimedPlanIDs[semanticPlanID] = true
        else
            local planIDToUse = nil
            local seedContent = ""
            local legacyPlanID = legacyBossPlanMap and tonumber(legacyBossPlanMap[bossKeyText]) or nil
            local legacyPlan = legacyPlanID and note:GetPlan(legacyPlanID) or nil

            if legacyPlan then
                seedContent = tostring(legacyPlan.content or "")
                if not claimedPlanIDs[legacyPlanID] then
                    planIDToUse = legacyPlanID
                end
            end

            local normalizedContent, shouldForceContent = self:NormalizeSemanticBossPlanContent(
                bossKey,
                seedContent,
                builtinText,
                encounterName
            )
            local createdPlanID = note:UpsertSemanticBossPlan(bossKeyText, planName, normalizedContent, {
                planID = planIDToUse,
                forceContent = planIDToUse == nil or shouldForceContent == true,
                onlyIfEmpty = planIDToUse ~= nil and shouldForceContent ~= true,
            })
            if createdPlanID then
                if builtinText ~= "" and normalizedContent == builtinText and T.debug then
                    T.debug(string.format(
                        "[SemanticTemplate] InitBuiltinTeamPlan: boss=%s planID=%s",
                        tostring(bossKeyText),
                        tostring(createdPlanID)
                    ))
                end
                claimedPlanIDs[createdPlanID] = true
                wb.bossTemplateVer[bossKeyText] = T.SemanticBuiltinPlansVersionS14 or ""
                if normalizedContent ~= "" then
                    wb.bossTemplateDigest[bossKeyText] = ComputeContentDigest(normalizedContent)
                else
                    wb.bossTemplateDigest[bossKeyText] = nil
                end
            end
        end

        local personalPlanID = note.GetPersonalBossPlanID and note:GetPersonalBossPlanID(bossKeyText) or nil
        local personalPlan = personalPlanID and note:GetPlan(personalPlanID) or nil
        local normalizedPersonalContent, shouldForcePersonalContent = self:NormalizePersonalBossPlanContent(
            bossKey,
            personalPlan and personalPlan.content or ""
        )
        note:UpsertPersonalBossPlan(bossKeyText, personalPlanName, normalizedPersonalContent, {
            planID = personalPlan and personalPlan.id or nil,
            forceContent = shouldForcePersonalContent == true,
            onlyIfEmpty = shouldForcePersonalContent ~= true,
        })
    end

    wb.scopeMode = nil
    wb.bossPlanMap = nil
    wb.globalPlanID = nil
    wb.plansInitialized = true
    return true
end

function SemanticTimeline:EnsureEditorWorkbenchReady(cause, force)
    self:EnsureTemplateReady()
    if force == true then
        self:ResetSemanticBossPlansInitialization()
    end
    self:NormalizeUISelection()
    return self:EnsureSemanticBossPlansInitialized({
        cause = cause or "editor_workbench_ready",
        force = force == true,
    })
end

function SemanticTimeline:GetSemanticNoteIDByBossKey(bossKey)
    if not self:IsSemanticBossPlansInitialized() then
        return nil
    end
    local note = T.Note
    if not (note and note.GetSemanticBossPlanID) then
        return nil
    end

    local keyText
    if type(bossKey) == "string" then
        keyText = bossKey
    else
        keyText = self:SerializeBossSelectorKey(CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey())
    end
    return note:GetSemanticBossPlanID(keyText)
end

function SemanticTimeline:GetSemanticPlanByBossKey(bossKey)
    local note = T.Note
    if not (note and note.GetPlan) then
        return nil
    end

    local planID = self:GetSemanticNoteIDByBossKey(bossKey)
    return planID and note:GetPlan(planID) or nil
end

function SemanticTimeline:GetPersonalNoteIDByBossKey(bossKey)
    if not self:IsSemanticBossPlansInitialized() then
        return nil
    end
    local note = T.Note
    if not (note and note.GetPersonalBossPlanID) then
        return nil
    end

    local keyText
    if type(bossKey) == "string" then
        keyText = bossKey
    else
        keyText = self:SerializeBossSelectorKey(CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey())
    end
    return note:GetPersonalBossPlanID(keyText)
end

function SemanticTimeline:GetPersonalPlanByBossKey(bossKey)
    local note = T.Note
    if not (note and note.GetPlan) then
        return nil
    end

    local planID = self:GetPersonalNoteIDByBossKey(bossKey)
    return planID and note:GetPlan(planID) or nil
end

function SemanticTimeline:UpdateSemanticPlanByBossKey(bossKey, content)
    local note = T.Note
    if not (note and note.UpdatePlan) then
        return false
    end

    local planID = self:GetSemanticNoteIDByBossKey(bossKey)
    if not planID then
        return false
    end

    local ok = note:UpdatePlan(planID, { content = tostring(content or "") })
    return ok
end

function SemanticTimeline:UpdatePersonalPlanByBossKey(bossKey, content)
    local note = T.Note
    if not (note and note.UpdatePlan) then
        return false
    end

    local planID = self:GetPersonalNoteIDByBossKey(bossKey)
    if not planID then
        return false
    end

    return note:UpdatePlan(planID, { content = tostring(content or "") }) == true
end

function SemanticTimeline:GetCurrentPersonalPlan()
    return self:GetPersonalPlanByBossKey(self:GetCurrentBossSelectorKey())
end

function SemanticTimeline:EnsureCurrentPersonalPlanPrepared()
    local bossKey = self:GetCurrentBossSelectorKey()
    local plan = self:GetPersonalPlanByBossKey(bossKey)
    if plan then
        local content = tostring(plan.content or "")
        if content ~= "" then
            self:CompilePlanContentForBoss(content, bossKey, plan.id, {
                relaxed = true,
            })
        end
        return plan
    end
    return nil
end

function SemanticTimeline:GetCurrentPlanForTab(tab)
    if NormalizeEditorTab(tab) == RESOLVE_SOURCE_PERSONAL then
        return self:EnsureCurrentPersonalPlanPrepared()
    end
    return self:GetCurrentPlan()
end

function SemanticTimeline:PreparePlanForTab(tab)
    if NormalizeEditorTab(tab) == RESOLVE_SOURCE_PERSONAL then
        return self:EnsureCurrentPersonalPlanPrepared()
    end
    return self:EnsureCurrentPlanPrepared()
end

local function BuildPlanDocument(self, bossKeyText, tab, plan)
    if not plan then
        return nil
    end

    return {
        bossKeyText = tostring(bossKeyText or ""),
        tab = NormalizeEditorTab(tab),
        planID = tonumber(plan.id),
        name = tostring(plan.name or ""),
        content = tostring(plan.content or ""),
    }
end

local function ParsePlanDocumentBossKey(self, document)
    local bossKeyText = type(document) == "table" and tostring(document.bossKeyText or "") or ""
    if bossKeyText == "" then
        return nil, ""
    end
    return self:ParseBossSelectorKey(bossKeyText), bossKeyText
end

function SemanticTimeline:GetPlanDocumentForBossTab(bossKey, tab)
    local normalizedTab = NormalizeEditorTab(tab)
    local normalizedBossKey
    local bossKeyText
    if type(bossKey) == "string" then
        bossKeyText = bossKey
        normalizedBossKey = self:ParseBossSelectorKey(bossKeyText)
    else
        normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
        bossKeyText = self:SerializeBossSelectorKey(normalizedBossKey)
    end
    if not normalizedBossKey or bossKeyText == "" then
        return nil
    end

    local plan
    if normalizedTab == RESOLVE_SOURCE_PERSONAL then
        plan = self:GetPersonalPlanByBossKey(normalizedBossKey)
    else
        plan = self:GetSemanticPlanByBossKey(normalizedBossKey)
    end
    return BuildPlanDocument(self, bossKeyText, normalizedTab, plan)
end

function SemanticTimeline:GetCurrentPlanDocument(tab)
    return self:GetPlanDocumentForBossTab(self:GetCurrentBossSelectorKey(), tab)
end

function SemanticTimeline:EnsurePlanDocumentForBossTab(bossKey, tab)
    local normalizedTab = NormalizeEditorTab(tab)
    local normalizedBossKey = CopyBossKey(bossKey)
    if not normalizedBossKey and type(bossKey) == "string" then
        normalizedBossKey = self:ParseBossSelectorKey(bossKey)
    end
    normalizedBossKey = normalizedBossKey or self:GetCurrentBossSelectorKey()
    if not normalizedBossKey then
        return nil
    end

    local bossKeyText = self:SerializeBossSelectorKey(normalizedBossKey)
    if bossKeyText == "" then
        return nil
    end

    local document = self:GetPlanDocumentForBossTab(normalizedBossKey, normalizedTab)
    if document then
        return document
    end

    local note = T.Note
    if not note then
        return nil
    end

    local encounterName = self:GetEncounterName(normalizedBossKey.encounterID) or (L["未命名Boss"] or "未命名Boss")
    local planID
    if normalizedTab == RESOLVE_SOURCE_PERSONAL then
        if not note.UpsertPersonalBossPlan then
            return nil
        end
        local normalizedContent = self:NormalizePersonalBossPlanContent(normalizedBossKey, "")
        planID = note:UpsertPersonalBossPlan(
            bossKeyText,
            BuildPersonalSemanticPlanName(encounterName),
            normalizedContent,
            { forceContent = true }
        )
    else
        if not note.UpsertSemanticBossPlan then
            return nil
        end
        local normalizedContent = self:NormalizeSemanticBossPlanContent(
            normalizedBossKey,
            "",
            "",
            encounterName
        )
        planID = note:UpsertSemanticBossPlan(
            bossKeyText,
            BuildSemanticPlanName(encounterName),
            normalizedContent,
            { forceContent = true }
        )
    end

    local plan = planID and note:GetPlan(planID) or nil
    return BuildPlanDocument(self, bossKeyText, normalizedTab, plan)
end

function SemanticTimeline:EnsurePlanBindingForKey(scopeMode, bossKey)
    local _ = scopeMode
    local note = T.Note
    if not (note and note.GetPlan) then
        return nil
    end

    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    return self:GetSemanticPlanByBossKey(normalizedBossKey)
end

function SemanticTimeline:CompilePlanContentForBoss(content, bossKey, planID, options)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    local text = tostring(content or "")
    local opts = options or {}
    local startedAt = GetProfileTimeMs()
    local templateOpts = opts.relaxed == true and { relaxed = true } or nil
    local format = self:GetPlanFormat(text)
    local cache = planID and self:GetCompiledPlanCache(planID, opts) or nil
    if cache and cache.content == text and cache.format == format and SameBossKey(cache.bossKey, normalizedBossKey) then
        return {
            bossKey = CopyBossKey(cache.bossKey),
            content = cache.content,
            format = cache.format,
            rows = cache.rows or {},
            errors = cache.errors or {},
            lineToRowID = cache.lineToRowID or {},
            parsedTrigger = cache.parsedTrigger,
            templateInfo = cache.templateInfo,
        }
    end

    local bindings = planID and self:GetPlanRowBindings(planID) or nil
    local lineToRowID = bindings and bindings.lineToRowID or nil
    local existingRows = cache and cache.rows or nil
    local rows
    local errors
    local newLineToRowID
    local parsedTrigger = nil
    local templateInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text, templateOpts) or nil
    if format == PLAN_FORMAT_TIMELINE and templateInfo and templateInfo.isValid ~= true and IsUsableTemplateBody(templateInfo, PLAN_FORMAT_TIMELINE) then
        LogPartialTimelineCompileOnce(normalizedBossKey, planID, text, templateInfo, opts.cause)
    end
    if format == PLAN_FORMAT_TRIGGER then
        rows, errors, newLineToRowID, parsedTrigger = self:CompileTriggerTextToRows(text, normalizedBossKey, opts)
    else
        local builtinDifficulty = self:ResolveBuiltinDifficultyForText(normalizedBossKey, text)
        rows, errors, newLineToRowID = self:CompileTextToRows(text, normalizedBossKey, lineToRowID, existingRows, {
            defaultSource = "override",
            relaxed = opts.relaxed == true,
            phaseDisplaySpans = builtinDifficulty and self:GetBuiltinPhaseDisplaySpans(normalizedBossKey, builtinDifficulty) or nil,
        })
    end

    local payload = {
        bossKey = CopyBossKey(normalizedBossKey),
        content = text,
        format = format,
        rows = self:BuildRowsCopy(rows),
        errors = self:BuildErrorsCopy(errors),
        lineToRowID = newLineToRowID,
        parsedTrigger = parsedTrigger,
        templateInfo = templateInfo,
    }

    if planID then
        self:SetPlanRowBindings(planID, newLineToRowID)
        self:SetCompiledPlanCache(planID, payload, opts)
    end

    if #(payload.errors or {}) > 0 then
        LogPlanEvent("STT_PLAN_COMPILE", {
            bossKey = self:SerializeBossSelectorKey(normalizedBossKey),
            planID = planID,
            len = #text,
            costMs = startedAt and math.floor((GetProfileTimeMs() - startedAt) + 0.5) or nil,
            rowCount = #(payload.rows or {}),
            errorCount = #(payload.errors or {}),
            cause = opts.cause or (opts.relaxed == true and "relaxed" or "compile"),
        })
    end

    return {
        bossKey = CopyBossKey(normalizedBossKey),
        content = text,
        format = format,
        rows = payload.rows or {},
        errors = payload.errors or {},
        lineToRowID = newLineToRowID,
        parsedTrigger = parsedTrigger,
        templateInfo = templateInfo,
    }
end

local function BuildRuntimeTemplateInfo(rawText, templateInfo, bossKey)
    if not templateInfo or not IsUsableTemplateBody(templateInfo, templateInfo.bodyKind) or templateInfo.bodyKind == nil then
        return nil
    end

    local raw = tostring(rawText or "")
    if templateInfo.isValid == true and templateInfo.hasBlocks == true and raw ~= "" then
        return raw
    end

    return BuildStructuredBuiltinTemplate(bossKey, templateInfo.bodyKind, templateInfo.processedText or "")
end

local function AnnotateCompiledRows(compiled, editorTab, planID)
    if type(compiled) ~= "table" or type(compiled.rows) ~= "table" then
        return compiled
    end
    local normalizedTab = NormalizeEditorTab(editorTab)
    for _, row in ipairs(compiled.rows) do
        if type(row) == "table" then
            row.editorTab = normalizedTab
            row.sourcePlanID = tonumber(planID)
        end
    end
    return compiled
end

local function AppendCompiledRows(targetRows, targetErrors, compiled, editorTab, planID)
    for _, row in ipairs(compiled and compiled.rows or {}) do
        local copied = CopyRow(row)
        if copied then
            if editorTab ~= nil then
                copied.editorTab = NormalizeEditorTab(editorTab)
            end
            if planID ~= nil then
                copied.sourcePlanID = tonumber(planID)
            end
            targetRows[#targetRows + 1] = copied
        end
    end
    for _, err in ipairs(compiled and compiled.errors or {}) do
        targetErrors[#targetErrors + 1] = BuildErrorPayload(err)
    end
end

function SemanticTimeline:ResolveRuntimeBossKey(options)
    local opts = options or {}
    local bossKey = CopyBossKey(opts.bossKey)
    if not bossKey and type(opts.bossKey) == "string" then
        bossKey = CopyBossKey(self:ParseBossSelectorKey(opts.bossKey))
    end
    if bossKey then
        return bossKey
    end

    local encounterID = tonumber(opts.encounterID)
    if encounterID and encounterID > 0 then
        bossKey = self:ResolveBossKeyByEncounterID(encounterID)
        if bossKey then
            return bossKey
        end
    end

    local bossKeyText = T.Note and T.Note.GetCurrentBossKey and T.Note:GetCurrentBossKey() or nil
    return CopyBossKey(self:ParseBossSelectorKey(bossKeyText))
end

function SemanticTimeline:GetResolvedPlanTexts(options)
    local opts = type(options) == "table" and options or {}
    local bossKey = self:ResolveRuntimeBossKey(options)
    local bossKeyText = bossKey and self:SerializeBossSelectorKey(bossKey) or ""
    local explicitBoss = opts.bossKey ~= nil or opts.encounterID ~= nil
    local bundle = T.Note and T.Note.GetCurrentPlanBundle and T.Note:GetCurrentPlanBundle({
        bossKeyText = bossKeyText,
        allowActiveFallback = (not explicitBoss) and opts.allowActiveFallback ~= false,
    }) or {}
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

function SemanticTimeline:_LogPersonalOverrideDebug(scope, overrideSet, dropped)
end

function SemanticTimeline:_CollectTimelineOverrideSpellIDs(personalText)
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

local function SegmentHasAudienceLocal(segment)
    if type(segment) ~= "table" then
        return false
    end
    if type(segment.condition) == "string" and segment.condition ~= "" then
        return true
    end
    return type(segment.players) == "table" and #segment.players > 0
end

local function SegmentTargetsCurrentPlayer(segment)
    if not SegmentHasAudienceLocal(segment) then
        return false
    end
    local passGroup = (not T.ShouldBroadcastToPlayer) and true or T.ShouldBroadcastToPlayer(segment.condition)
    local passName = (not T.ShouldBroadcastForNames) and true or T.ShouldBroadcastForNames(segment.players)
    return passGroup and passName
end

local function GetSegmentPrimarySpellIDLocal(segment)
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

local function FilterTimelineSegmentsByPersonalOverride(segments, overrideSet)
    local keptSegments = {}
    local suppressed = 0

    for _, segment in ipairs(type(segments) == "table" and segments or {}) do
        local spellID = GetSegmentPrimarySpellIDLocal(segment)
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

local function GetFirstSegmentPrimarySpellID(segments)
    for _, segment in ipairs(type(segments) == "table" and segments or {}) do
        local spellID = GetSegmentPrimarySpellIDLocal(segment)
        if spellID and spellID > 0 then
            return spellID
        end
    end
    return nil
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
    local compact = phaseText:match("^([pi]%d+)r1$")
    return compact or phaseText
end

function SemanticTimeline:_SerializeTimelineSegment(segment)
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

function SemanticTimeline:_SerializeTimelineContentFromSegments(segments)
    local parts = {}
    for _, segment in ipairs(type(segments) == "table" and segments or {}) do
        local part = self:_SerializeTimelineSegment(segment)
        if part ~= "" then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts)
end

local function SerializeTimelineModifiers(event)
    local modifiers = type(event) == "table" and event.modifiers or nil
    if type(modifiers) ~= "table" then
        return ""
    end
    if T.InlineModifier and T.InlineModifier.Compose then
        return T.InlineModifier.Compose(modifiers)
    end
    return ""
end

function SemanticTimeline:_SerializeTimelineEvent(event)
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
    local modifiers = SerializeTimelineModifiers(event)
    local targetIndicators = SerializeTargetIndicators(event.targetIndicators)
    if phaseText and phaseText ~= "" then
        return string.format("{time:%s,%s}%s%s %s", timeText, phaseText, targetIndicators, modifiers, content)
    end
    return string.format("{time:%s}%s%s %s", timeText, targetIndicators, modifiers, content)
end

function SemanticTimeline:_FilterTimelineTeamTextByPersonal(teamText, personalText, teamInfo)
    if not (T.NoteParser and T.NoteParser.ParseNote and T.NoteParser.GetResolvedEventText) then
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
        local keptSegments, eventSuppressed, hasAudience = FilterTimelineSegmentsByPersonalOverride(event.segments, overrideSet)

        if eventSuppressed == 0 then
            lines[#lines + 1] = self:_SerializeTimelineEvent(event)
        else
            local filteredEvent = {}
            for key, value in pairs(event) do
                filteredEvent[key] = value
            end
            filteredEvent.segments = keptSegments
            filteredEvent.content = self:_SerializeTimelineContentFromSegments(keptSegments)
            filteredEvent.displayText = nil
            filteredEvent.originalText = nil
            filteredEvent.rawLine = nil
            filteredEvent.hasAudience = hasAudience

            if filteredEvent.hasAudience then
                lines[#lines + 1] = self:_SerializeTimelineEvent(filteredEvent)
                suppressedSegments = suppressedSegments + eventSuppressed
            else
                suppressedSegments = suppressedSegments + eventSuppressed
                droppedRows = droppedRows + 1
            end
        end
    end

    return table.concat(lines, "\n"), overrideSet, {
        suppressedSegments = suppressedSegments,
        droppedRows = droppedRows,
    }
end

function SemanticTimeline:_CollectTriggerOverrideSpellIDs(personalText)
    local rawText = tostring(personalText or "")
    if rawText == "" then
        return {}
    end

    local syntax = T.TriggerSyntax
    if not (syntax and syntax.ParseTriggerText and syntax.BuildSpeakText) then
        return {}
    end

    local parsed = syntax.ParseTriggerText(rawText)
    if type(parsed) ~= "table" or type(parsed.rules) ~= "table" then
        return {}
    end

    local overrideSet = {}
    for _, rule in ipairs(parsed.rules) do
        local spellID = tonumber(rule and rule.spellID)
        if rule and rule.triggerKind ~= "event" and spellID and spellID > 0 then
            local spellName = self:GetSpellName(spellID)
            local speakText = syntax.BuildSpeakText(rule, spellName)
            if speakText and speakText ~= "" then
                overrideSet[spellID] = true
            end
        end
    end

    return overrideSet
end

function SemanticTimeline:_FilterTeamTextByPersonal(teamText, personalText)
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
        if not (IsUsableTemplateBody(teamInfo, "timeline") and IsUsableTemplateBody(personalInfo, "timeline") and T.TimelineSyntax and T.TimelineSyntax.ParseTimelineLine) then
            return rawTeamText, {}, 0
        end
        return self:_FilterTimelineTeamTextByPersonal(rawTeamText, rawPersonalText, teamInfo)
    end

    local overrideSet = {}
    local dropLine = nil

    if teamInfo.bodyKind == "trigger" then
        if not (IsUsableTemplateBody(teamInfo, "trigger") and IsUsableTemplateBody(personalInfo, "trigger") and T.TriggerSyntax and T.TriggerSyntax.ParseRuleLine) then
            return rawTeamText, {}, 0
        end
        overrideSet = self:_CollectTriggerOverrideSpellIDs(rawPersonalText)
        dropLine = function(line)
            local rule = T.TriggerSyntax.ParseRuleLine(line)
            local spellID = tonumber(rule and rule.spellID) or nil
            return rule and rule.triggerKind ~= "event" and spellID and overrideSet[spellID] == true
        end
    else
        return rawTeamText, {}, 0
    end

    if not next(overrideSet) or type(dropLine) ~= "function" then
        return rawTeamText, overrideSet, 0
    end

    local cleaned = {}
    local dropped = 0
    for line in (rawTeamText .. "\n"):gmatch("([^\n]*)\n") do
        if dropLine(line) then
            dropped = dropped + 1
        else
            cleaned[#cleaned + 1] = line
        end
    end

    return table.concat(cleaned, "\n"), overrideSet, dropped
end

function SemanticTimeline:_FilterCompiledTimelineRowsByPersonal(compiled, personalText)
    if type(compiled) ~= "table" or compiled.format ~= PLAN_FORMAT_TIMELINE then
        return compiled, {}, { suppressedSegments = 0, droppedRows = 0 }
    end

    local overrideSet = self:_CollectTimelineOverrideSpellIDs(personalText)
    if not next(overrideSet) then
        return compiled, overrideSet, { suppressedSegments = 0, droppedRows = 0 }
    end

    local filtered = {
        bossKey = CopyBossKey(compiled.bossKey),
        content = compiled.content,
        format = compiled.format,
        rows = {},
        errors = self:BuildErrorsCopy(compiled.errors),
        lineToRowID = compiled.lineToRowID or {},
        parsedTrigger = compiled.parsedTrigger,
        templateInfo = compiled.templateInfo,
    }
    local stats = {
        suppressedSegments = 0,
        droppedRows = 0,
    }

    for _, row in ipairs(compiled.rows or {}) do
        if type(row) == "table" and type(row.segments) == "table" then
            local keptSegments, suppressed, hasAudience = FilterTimelineSegmentsByPersonalOverride(row.segments, overrideSet)
            if suppressed <= 0 then
                filtered.rows[#filtered.rows + 1] = CopyRow(row)
            elseif hasAudience then
                local copied = CopyRow(row)
                copied.segments = keptSegments
                copied.rawContent = self:_SerializeTimelineContentFromSegments(keptSegments)
                copied.label = copied.rawContent
                copied.spellID = GetFirstSegmentPrimarySpellID(keptSegments)
                copied.rowType = copied.spellID and WORKBENCH_ROW_SPELL or WORKBENCH_ROW_TEXT
                filtered.rows[#filtered.rows + 1] = copied
                stats.suppressedSegments = stats.suppressedSegments + suppressed
            else
                stats.suppressedSegments = stats.suppressedSegments + suppressed
                stats.droppedRows = stats.droppedRows + 1
            end
        else
            filtered.rows[#filtered.rows + 1] = CopyRow(row)
        end
    end

    return filtered, overrideSet, stats
end

function SemanticTimeline:GetResolvedRuntimePlan(options)
    local perf = T.CreatePerfProfile and T.CreatePerfProfile("GetResolvedRuntimePlan") or nil
    local texts = self:GetResolvedPlanTexts(options)
    if perf then perf:Mark("GetResolvedPlanTexts") end
    local bossKey = texts.bossKey or self:ParseBossSelectorKey(texts.bossKeyText)
    local semanticDB = EnsureSemanticDB()
    local resolveSource = self:GetResolveSource()
    local teamInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(texts.teamText or "") or nil
    if perf then perf:Mark("PreprocessText_team") end
    local runtimeTeamText = tostring(texts.teamText or "")
    local runtimeTeamInfo = teamInfo
    local personalInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(texts.personalText or "", { relaxed = true }) or nil
    if perf then perf:Mark("PreprocessText_personal") end
    local bundle = {
        bossKey = CopyBossKey(bossKey),
        bossKeyText = bossKey and self:SerializeBossSelectorKey(bossKey) or "",
        resolveSource = resolveSource,
        teamText = texts.teamText or "",
        runtimeTeamText = runtimeTeamText,
        personalText = texts.personalText or "",
        teamName = texts.teamName or "",
        personalName = texts.personalName or "",
        teamPlanID = texts.teamPlanID,
        personalPlanID = texts.personalPlanID,
        teamInfo = teamInfo,
        personalInfo = personalInfo,
        personalOverrideSpellIDs = {},
        personalOverrideDropped = 0,
        personalOverrideSuppressedSegments = 0,
        bodyKind = nil,
        runtimeText = nil,
    }

    if resolveSource == RESOLVE_SOURCE_TEAM_PLUS_PERSONAL
        and semanticDB.personalOverridesTeam ~= false
        and texts.teamText ~= ""
        and texts.personalText ~= "" then
        local cleanedTeamText, overrideSet, stats = self:_FilterTeamTextByPersonal(texts.teamText, texts.personalText)
        bundle.personalOverrideSpellIDs = overrideSet
        bundle.personalOverrideDropped = tonumber(type(stats) == "table" and stats.droppedRows or stats) or 0
        bundle.personalOverrideSuppressedSegments = tonumber(type(stats) == "table" and stats.suppressedSegments or 0) or 0
        if cleanedTeamText ~= texts.teamText then
            runtimeTeamText = cleanedTeamText
            runtimeTeamInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(cleanedTeamText) or nil
            bundle.runtimeTeamText = runtimeTeamText
            bundle.teamInfo = runtimeTeamInfo
        end
        self:_LogPersonalOverrideDebug(
            string.format("STN:%s", tostring(bundle.bossKeyText or "")),
            overrideSet,
            stats
        )
    end

    local parts = {}
    local activeInfos
    if resolveSource == RESOLVE_SOURCE_TEAM then
        activeInfos = { runtimeTeamInfo }
    elseif resolveSource == RESOLVE_SOURCE_PERSONAL then
        activeInfos = { personalInfo }
    else
        activeInfos = { runtimeTeamInfo, personalInfo }
    end

    for _, info in ipairs(activeInfos) do
        if IsUsableTemplateBody(info, info and info.bodyKind) and info.bodyKind and info.processedText and info.processedText ~= "" then
            if not bundle.bodyKind then
                bundle.bodyKind = info.bodyKind
            end
            if info.bodyKind == bundle.bodyKind then
                parts[#parts + 1] = info.processedText
            end
        end
    end

    if #parts > 0 and bundle.bodyKind then
        bundle.runtimeText = BuildStructuredBuiltinTemplate(bossKey, bundle.bodyKind, table.concat(parts, "\n"))
    end
    bundle.title = bundle.teamName ~= "" and bundle.teamName or bundle.personalName

    if not bundle.runtimeText then
        local fallbackInfo = nil
        if resolveSource == RESOLVE_SOURCE_TEAM then
            fallbackInfo = runtimeTeamInfo
        elseif resolveSource == RESOLVE_SOURCE_PERSONAL then
            fallbackInfo = personalInfo
        elseif IsUsableTemplateBody(runtimeTeamInfo, runtimeTeamInfo and runtimeTeamInfo.bodyKind) then
            fallbackInfo = runtimeTeamInfo
        elseif IsUsableTemplateBody(personalInfo, personalInfo and personalInfo.bodyKind) then
            fallbackInfo = personalInfo
        end
        bundle.bodyKind = fallbackInfo and fallbackInfo.bodyKind or bundle.bodyKind
        bundle.runtimeText = BuildRuntimeTemplateInfo(
            fallbackInfo == personalInfo and texts.personalText or runtimeTeamText,
            fallbackInfo,
            bossKey
        )
    end
    if perf then perf:Mark("BuildTemplate") end
    if perf then perf:Finish() end

    return bundle
end

function SemanticTimeline:GetCurrentPlanBundle(options)
    return self:GetResolvedRuntimePlan(options)
end

function SemanticTimeline:GetCurrentRuntimePlanTitle()
    local bundle = self:GetCurrentPlanBundle()
    return bundle and bundle.title ~= "" and bundle.title or nil
end

function SemanticTimeline:GetCurrentEditorTab()
    local db = C and C.DB and C.DB.semanticTimeline
    local ui = db and db.ui
    if ui and ui.activeEditorTab == RESOLVE_SOURCE_PERSONAL then
        return RESOLVE_SOURCE_PERSONAL
    end
    return RESOLVE_SOURCE_TEAM
end

function SemanticTimeline:CompileResolvedPlanContent()
    local bossKey = self:GetCurrentBossSelectorKey()
    local resolveSource = self:GetResolveSource()
    local texts = self:GetResolvedPlanTexts()
    local teamPlan = self:GetCurrentPlan()
    local personalPlan = self:GetCurrentPersonalPlan()
    local rows = {}
    local errors = {}

    local function CompileSource(content, planID, relaxed, editorTab)
        return AnnotateCompiledRows(self:CompilePlanContentForBoss(content, bossKey, planID, {
            relaxed = relaxed == true,
        }), editorTab, planID)
    end

    if resolveSource == RESOLVE_SOURCE_TEAM then
        return CompileSource(texts.teamText, teamPlan and teamPlan.id or nil, false, RESOLVE_SOURCE_TEAM)
    end
    if resolveSource == RESOLVE_SOURCE_PERSONAL then
        return CompileSource(texts.personalText, personalPlan and personalPlan.id or nil, true, RESOLVE_SOURCE_PERSONAL)
    end

    local teamCompiled = CompileSource(texts.teamText, teamPlan and teamPlan.id or nil, false, RESOLVE_SOURCE_TEAM)
    local personalCompiled = CompileSource(texts.personalText, personalPlan and personalPlan.id or nil, true, RESOLVE_SOURCE_PERSONAL)
    local effectiveFormat = teamCompiled.format or personalCompiled.format or PLAN_FORMAT_TIMELINE

    if effectiveFormat == PLAN_FORMAT_TIMELINE and (EnsureSemanticDB().personalOverridesTeam ~= false) then
        local filteredTeam, overrideSet, stats = self:_FilterCompiledTimelineRowsByPersonal(teamCompiled, texts.personalText)
        teamCompiled = filteredTeam or teamCompiled
        self:_LogPersonalOverrideDebug(
            string.format("GUI:%s", tostring(self:SerializeBossSelectorKey(bossKey) or "")),
            overrideSet,
            stats
        )
    end

    AppendCompiledRows(rows, errors, teamCompiled, RESOLVE_SOURCE_TEAM, teamPlan and teamPlan.id or nil)
    AppendCompiledRows(rows, errors, personalCompiled, RESOLVE_SOURCE_PERSONAL, personalPlan and personalPlan.id or nil)
    self:SortWorkbenchRows(rows)

    return {
        bossKey = CopyBossKey(bossKey),
        content = table.concat({ texts.teamText or "", texts.personalText or "" }, "\n"),
        format = effectiveFormat,
        rows = rows,
        errors = errors,
        lineToRowID = {},
        parsedTrigger = nil,
        templateInfo = nil,
    }
end

function SemanticTimeline:EnsureCurrentPlanBinding()
    return self:EnsurePlanBindingForKey(WORKBENCH_SCOPE_BY_BOSS, self:GetCurrentBossSelectorKey())
end

function SemanticTimeline:GetCurrentPlan()
    local plan = self:EnsureCurrentPlanBinding()
    return plan
end

function SemanticTimeline:GetCurrentPlanFormat()
    local plan = self:GetCurrentPlan()
    if not plan then
        return PLAN_FORMAT_TIMELINE
    end
    return self:GetPlanFormat(plan.content or "")
end

function SemanticTimeline:EnsureCurrentPlanPrepared()
    local plan = self:EnsureCurrentPlanBinding()
    if not plan then
        return nil
    end

    local bossKey = self:GetCurrentBossSelectorKey()
    local content = tostring(plan.content or "")
    self:CompilePlanContentForBoss(content, bossKey, plan.id, {
        cause = "ensure_current_plan",
    })

    return plan
end

function SemanticTimeline:GetCurrentPlanContent()
    local plan = self:GetCurrentPlan()
    return plan and tostring(plan.content or "") or ""
end

function SemanticTimeline:GetPlanContentForTab(tab)
    local plan = self:GetCurrentPlanForTab(tab)
    return plan and tostring(plan.content or "") or ""
end

function SemanticTimeline:SaveCurrentPlanContent(content)
    local note = T.Note
    local plan = self:GetCurrentPlan()
    if not (note and plan and note.UpdatePlan) then
        return false
    end
    return note:UpdatePlan(plan.id, { content = tostring(content or "") })
end

local function SyncRuntimePlanDocument(note, document, normalizedTab, planID, text, planName, reason)
    if not (note and document and planID) then
        return
    end
    local bossKeyText = tostring(document.bossKeyText or "")
    if bossKeyText == "" then
        return
    end

    local name = tostring(planName or "")
    local syncedPlanID = nil
    if note.UpsertBossPlan then
        syncedPlanID = note:UpsertBossPlan(bossKeyText, normalizedTab, text, {
            planID = planID,
            forceContent = true,
            name = name,
        })
    elseif normalizedTab == RESOLVE_SOURCE_PERSONAL then
        syncedPlanID = note.UpsertPersonalBossPlan and note:UpsertPersonalBossPlan(bossKeyText, name, text, {
            planID = planID,
            forceContent = true,
        }) or nil
    else
        syncedPlanID = note.UpsertSemanticBossPlan and note:UpsertSemanticBossPlan(bossKeyText, name, text, {
            planID = planID,
            forceContent = true,
        }) or nil
    end

    if normalizedTab ~= RESOLVE_SOURCE_PERSONAL and syncedPlanID and note.SetActivePlan then
        note:SetActivePlan(syncedPlanID, {
            manual = true,
            contextKey = "boss:" .. bossKeyText,
        })
    end

end

function SemanticTimeline:SavePlanDocument(document, content, cause)
    local note = T.Note
    if not (note and note.UpdatePlan and note.GetPlan) then
        return false
    end

    local planID = document and tonumber(document.planID)
    if not planID then
        return false
    end

    local existingPlan = note:GetPlan(planID)
    if not existingPlan then
        LogPlanEvent("STT_PLAN_SAVE", {
            bossKey = document and document.bossKeyText or nil,
            tab = document and NormalizeEditorTab(document.tab) or nil,
            planID = planID,
            cause = cause or "unknown",
            result = "missing_plan",
        })
        return false
    end

    local normalizedTab = NormalizeEditorTab(document.tab)
    local text = tostring(content or "")
    local oldText = tostring(existingPlan.content or "")
    local syncReason = cause == "editor" and "editor_save" or (cause or "editor_save")
    if oldText == text then
        SyncRuntimePlanDocument(note, document, normalizedTab, planID, text, existingPlan.name, syncReason)
        LogPlanEvent("STT_PLAN_SAVE", {
            bossKey = document and document.bossKeyText or nil,
            tab = normalizedTab,
            planID = planID,
            oldLen = #oldText,
            newLen = #text,
            digest = ComputeContentDigest(text),
            cause = cause or "unknown",
            result = "noop",
        })
        return true
    end

    local ok = note:UpdatePlan(planID, { content = text }) == true
    if ok then
        SyncRuntimePlanDocument(note, document, normalizedTab, planID, text, existingPlan.name, syncReason)
    end
    if ok and normalizedTab ~= RESOLVE_SOURCE_PERSONAL and oldText ~= "" and text == "" and T.debug then
        T.debug(string.format(
            "[SemanticTemplate] KeepEmptyTeamPlan: boss=%s planID=%s",
            tostring(document and document.bossKeyText or ""),
            tostring(planID)
        ))
    end

    LogPlanEvent("STT_PLAN_SAVE", {
        bossKey = document and document.bossKeyText or nil,
        tab = normalizedTab,
        planID = planID,
        oldLen = #oldText,
        newLen = #text,
        digest = ComputeContentDigest(text),
        cause = cause or "unknown",
        result = ok and "saved" or "failed",
    })
    return ok
end

function SemanticTimeline:SavePlanContentForTab(tab, content)
    local document = self:GetCurrentPlanDocument(tab)
    if not document then
        return false
    end
    return self:SavePlanDocument(document, content, "editor")
end

function SemanticTimeline:GetCurrentEffectiveRows()
    local compiled = self:CompileCurrentPlanText()
    return compiled and compiled.rows or {}
end

function SemanticTimeline:CompileCurrentPlanText()
    local plan = self:EnsureCurrentPlanPrepared()
    if not plan then
        return {
            rows = {},
            errors = {},
            lineToRowID = {},
        }
    end

    local compiled = self:CompilePlanContentForBoss(plan.content or "", self:GetCurrentBossSelectorKey(), plan.id)
    return {
        planID = plan.id,
        format = compiled.format,
        rows = compiled.rows or {},
        errors = compiled.errors or {},
        lineToRowID = compiled.lineToRowID or {},
        parsedTrigger = compiled.parsedTrigger,
        templateInfo = compiled.templateInfo,
    }
end

function SemanticTimeline:ApplyCurrentPlanText(content)
    local plan = self:EnsureCurrentPlanBinding()
    if not plan then
        return nil, "plan_unavailable"
    end

    local text = tostring(content or "")
    local note = T.Note
    if note and note.UpdatePlan then
        note:UpdatePlan(plan.id, { content = text })
    end
    plan.content = text
    local compiled = self:CompilePlanContentForBoss(text, self:GetCurrentBossSelectorKey(), plan.id)

    return {
        planID = plan.id,
        format = compiled.format,
        rows = compiled.rows or {},
        errors = compiled.errors or {},
        lineToRowID = compiled.lineToRowID or {},
        parsedTrigger = compiled.parsedTrigger,
        templateInfo = compiled.templateInfo,
    }
end

function SemanticTimeline:RebuildCurrentPlanTextFromRows()
    local plan = self:EnsureCurrentPlanBinding()
    if not plan then
        return nil, "plan_unavailable"
    end
    if IsStructuredTemplateContent(plan.content or "") then
        return nil, "structured_template_manual_only"
    end

    if self:GetPlanFormat(plan.content or "") == PLAN_FORMAT_TRIGGER then
        return nil, "trigger_plan_manual_only"
    end

    local rows = self:GetCurrentEffectiveRows()
    local bodyText, lineToRowID = self:BuildRowsToTimelineText(rows)
    local text = bodyText
    if T.STNTemplate and T.STNTemplate.ReplaceTimelineBody then
        text = T.STNTemplate.ReplaceTimelineBody(plan.content or "", bodyText)
    end
    self:SetPlanRowBindings(plan.id, lineToRowID)
    self:SaveCurrentPlanContent(text)
    self:SetCompiledPlanCache(plan.id, {
        bossKey = CopyBossKey(self:GetCurrentBossSelectorKey()),
        content = text,
        format = PLAN_FORMAT_TIMELINE,
        rows = self:BuildRowsCopy(rows),
        errors = {},
        lineToRowID = lineToRowID,
        templateInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text) or nil,
    })

    return {
        planID = plan.id,
        text = text,
        rows = rows,
        lineToRowID = lineToRowID,
    }
end

local function ResolveTriggerDocumentPlan(self, document)
    local note = T.Note
    if not (note and note.GetPlan) then
        return nil, nil, nil, "plan_unavailable"
    end

    local bossKey = ParsePlanDocumentBossKey(self, document)
    local planID = document and tonumber(document.planID)
    local normalizedTab = NormalizeEditorTab(document and document.tab)
    if not bossKey or not planID then
        return nil, nil, nil, "plan_unavailable"
    end

    local plan = note:GetPlan(planID)
    if not plan then
        return nil, nil, nil, "plan_unavailable"
    end
    if self:GetPlanFormat(plan.content or "") ~= PLAN_FORMAT_TRIGGER then
        return nil, nil, nil, "not_trigger_plan"
    end

    return plan, bossKey, normalizedTab, nil
end

function SemanticTimeline:GetTriggerDefaultRuleForDocument(document, spellID)
    local plan, bossKey, normalizedTab = ResolveTriggerDocumentPlan(self, document)
    if not plan then
        return nil
    end

    local compiled = self:CompilePlanContentForBoss(
        plan.content or "",
        bossKey,
        plan.id,
        {
            relaxed = normalizedTab == RESOLVE_SOURCE_PERSONAL,
            cause = "trigger_form_read",
        }
    )
    if not compiled or compiled.format ~= PLAN_FORMAT_TRIGGER then
        return nil
    end
    local parsed = compiled.parsedTrigger
    if not parsed or type(parsed.defaultRules) ~= "table" then
        return nil
    end
    return parsed.defaultRules[tonumber(spellID) or 0]
end

function SemanticTimeline:UpsertTriggerDefaultRuleForDocument(document, spellID, mode, payload)
    local plan, bossKey, normalizedTab, err = ResolveTriggerDocumentPlan(self, document)
    if not plan then
        return nil, err
    end
    if not (T.TriggerSyntax and T.TriggerSyntax.UpsertDefaultRule) then
        return nil, "trigger_syntax_missing"
    end

    local updatedText = T.TriggerSyntax.UpsertDefaultRule(plan.content or "", spellID, mode, payload)
    local ok = self:SavePlanDocument({
        bossKeyText = tostring(document.bossKeyText or ""),
        tab = normalizedTab,
        planID = plan.id,
    }, updatedText, "trigger_form")
    if not ok then
        return nil, "save_failed"
    end

    return self:CompilePlanContentForBoss(updatedText, bossKey, plan.id, {
        relaxed = normalizedTab == RESOLVE_SOURCE_PERSONAL,
        cause = "trigger_form_write",
    })
end

function SemanticTimeline:SetPlanRowBindings(planID, lineToRowID)
    local db = EnsureSemanticDB()
    local wb = db.workbench
    local key = tostring(planID or "")
    if key == "" then
        return
    end

    local rowToLine = {}
    local normalizedLineToRowID = {}
    for line, rowID in pairs(lineToRowID or {}) do
        local lineNum = tonumber(line)
        if lineNum and type(rowID) == "string" and rowID ~= "" then
            normalizedLineToRowID[lineNum] = rowID
            rowToLine[rowID] = lineNum
        end
    end

    wb.planRowBindings[key] = {
        lineToRowID = normalizedLineToRowID,
        rowToLine = rowToLine,
    }
end

function SemanticTimeline:GetPlanRowBindings(planID)
    local db = EnsureSemanticDB()
    local wb = db.workbench
    local key = tostring(planID or "")
    if key == "" then
        return nil
    end
    return wb.planRowBindings[key]
end

function SemanticTimeline:GetCurrentPlanLineByRowID(rowID)
    local plan = self:GetCurrentPlan()
    if not plan then
        return nil
    end
    local binding = self:GetPlanRowBindings(plan.id)
    if not (binding and binding.rowToLine) then
        return nil
    end
    return binding.rowToLine[rowID]
end

function SemanticTimeline:GetPlanLineByRowIDForTab(tab, rowID)
    local plan = self:GetCurrentPlanForTab(tab)
    if not plan then
        return nil
    end
    local binding = self:GetPlanRowBindings(plan.id)
    if not (binding and binding.rowToLine) then
        return nil
    end
    return binding.rowToLine[rowID]
end

function SemanticTimeline:BuildRowsToTimelineText(rows)
    local lines = {}
    local lineToRowID = {}
    local sorted = {}
    for _, row in ipairs(rows or {}) do
        sorted[#sorted + 1] = CopyRow(row)
    end
    self:SortWorkbenchRows(sorted)

    for index, row in ipairs(sorted) do
        local line

        if row.rowType == WORKBENCH_ROW_COMMENT then
            line = TrimText(row.textPayload or row.label or "")
        elseif row.rowType == WORKBENCH_ROW_SPELL and tonumber(row.spellID) and tonumber(row.spellID) > 0 then
            local timeText = FormatClock(row.timeSec)
            local targetIndicators = SerializeTargetIndicators(row.targetIndicators)
            local spellToken = string.format("{spell:%d}", row.spellID)
            local spellName = self:GetSpellName(row.spellID)
            local extraLabel = TrimText(row.label or "")
            if extraLabel ~= "" and extraLabel ~= spellName then
                line = string.format("{time:%s}%s %s %s", timeText, targetIndicators, spellToken, extraLabel)
            else
                line = string.format("{time:%s}%s %s", timeText, targetIndicators, spellToken)
            end
        elseif row.rowType == WORKBENCH_ROW_COUNTDOWN then
            local timeText = FormatClock(row.timeSec)
            local targetIndicators = SerializeTargetIndicators(row.targetIndicators)
            local countdown = tonumber(row.countdownFrom) or 5
            local payload = TrimText(row.textPayload or row.label or "")
            line = string.format("{time:%s}%s{ct:%d} %s", timeText, targetIndicators, countdown, payload)
        else
            local timeText = FormatClock(row.timeSec)
            local targetIndicators = SerializeTargetIndicators(row.targetIndicators)
            local payload = TrimText(row.textPayload or row.label or "")
            line = string.format("{time:%s}%s %s", timeText, targetIndicators, payload)
        end

        line = TrimText(line)
        lines[#lines + 1] = line
        lineToRowID[index] = row.rowID
    end

    return table.concat(lines, "\n"), lineToRowID
end

function SemanticTimeline:ParseTimelineTextToRows(text, bossKey, lineToRowID, existingRows)
    return self:CompileTextToRows(text, bossKey, lineToRowID, existingRows, {
        defaultSource = "override",
    })
end

function SemanticTimeline:GetNote(encounterID, spellID, occurrence)
    local db = EnsureSemanticDB()
    return db.notes[BuildKey(encounterID, spellID, occurrence)]
end

function SemanticTimeline:SetNote(encounterID, spellID, occurrence, text)
    local db = EnsureSemanticDB()
    local key = BuildKey(encounterID, spellID, occurrence)
    local value = tostring(text or ""):gsub("\r\n", "\n")

    if value == "" then
        db.notes[key] = nil
        return
    end

    db.notes[key] = value
end

function SemanticTimeline:ClearEncounter(encounterID)
    local db = EnsureSemanticDB()
    local prefix = tostring(tonumber(encounterID) or 0) .. ":"
    local removed = 0

    for key in pairs(db.notes) do
        if key:sub(1, #prefix) == prefix then
            db.notes[key] = nil
            removed = removed + 1
        end
    end

    return removed
end

function SemanticTimeline:GetSpellName(spellID)
    self.spellNameCache = self.spellNameCache or {}
    local cached = self.spellNameCache[spellID]
    if cached then
        return cached
    end

    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        name = info and info.name
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end

    if type(name) ~= "string" or name == "" then
        name = tostring(spellID)
    end

    self.spellNameCache[spellID] = name
    return name
end

function SemanticTimeline:SortEncounterEvents(encounterRecord)
    table.sort(encounterRecord.events, function(a, b)
        local aHasTime = tonumber(a.timeSec) ~= nil
        local bHasTime = tonumber(b.timeSec) ~= nil
        if aHasTime ~= bHasTime then
            return aHasTime
        end
        if aHasTime and bHasTime and a.timeSec ~= b.timeSec then
            return a.timeSec < b.timeSec
        end
        if a.spellID ~= b.spellID then
            return a.spellID < b.spellID
        end
        if a.occurrence ~= b.occurrence then
            return a.occurrence < b.occurrence
        end
        return a.eventType < b.eventType
    end)
end

function SemanticTimeline:HasEncounterEvent(encounterRecord, spellID, occurrence)
    for _, event in ipairs(encounterRecord.events or {}) do
        if event.spellID == spellID and event.occurrence == occurrence then
            return event
        end
    end
    return nil
end

function SemanticTimeline:EnsureEncounterRecord(instanceRecord, encounterID, name, nameZh, nameZhTW, journalOrder, encounterIcon)
    local normalizedEncounterID = tonumber(encounterID) or 0
    local existing = self.encountersByID[normalizedEncounterID]
    if existing then
        if IsValidEncounterName(name) then
            existing.name = name
        end
        if type(nameZh) == "string" and nameZh ~= "" then
            existing.nameZh = nameZh
        end
        if type(nameZhTW) == "string" and nameZhTW ~= "" then
            existing.nameZhTW = nameZhTW
        end
        if tonumber(journalOrder) and tonumber(journalOrder) > 0 then
            existing.journalOrder = tonumber(journalOrder)
        end
        if tonumber(encounterIcon) and tonumber(encounterIcon) > 0 then
            existing.encounterIcon = tonumber(encounterIcon)
        end
        return existing
    end

    if not IsValidEncounterName(name) then
        return nil
    end

    local record = {
        encounterID = normalizedEncounterID,
        instanceID = instanceRecord.instanceID,
        name = tostring(name),
        nameZh = tostring(nameZh or ""),
        nameZhTW = tostring(nameZhTW or ""),
        journalOrder = tonumber(journalOrder) or 0,
        encounterIcon = tonumber(encounterIcon) or 0,
        events = {},
    }

    self.encountersByID[normalizedEncounterID] = record
    instanceRecord.encounters[#instanceRecord.encounters + 1] = record
    return record
end

function SemanticTimeline:ApplyEncounterJournalMetadata(instanceRecord)
    self:EnsureEncounterJournalLoaded()
    if type(EJ_GetEncounterInfoByIndex) ~= "function" then
        return
    end

    local journalInstanceID = tonumber(instanceRecord.journalInstanceID)
    if not journalInstanceID or journalInstanceID <= 0 then
        return
    end

    if EJ_SelectInstance then
        pcall(EJ_SelectInstance, journalInstanceID)
    end

    for index = 1, 30 do
        local encounterName, _, encounterID = EJ_GetEncounterInfoByIndex(index, journalInstanceID)
        if (type(encounterName) ~= "string" or encounterName == "") and type(EJ_GetEncounterInfoByIndex) == "function" then
            encounterName, _, encounterID = EJ_GetEncounterInfoByIndex(index)
        end
        if type(encounterName) ~= "string" or encounterName == "" then
            break
        end

        local normalizedEncounterID = tonumber(encounterID)
        if normalizedEncounterID and normalizedEncounterID > 0 then
            local existing = self.encountersByID[normalizedEncounterID]
            if existing and existing.instanceID == instanceRecord.instanceID then
                self:EnsureEncounterRecord(instanceRecord, normalizedEncounterID, encounterName, "", "", index)
            end
        end
    end
end

function SemanticTimeline:ResolveEncounterName(encounterID)
    local normalizedEncounterID = tonumber(encounterID) or 0
    if normalizedEncounterID <= 0 then
        return nil
    end

    self:EnsureEncounterJournalLoaded()
    if EJ_GetEncounterInfo then
        local journalName = EJ_GetEncounterInfo(normalizedEncounterID)
        if IsValidEncounterName(journalName) then
            return journalName
        end
    end

    return nil
end

function SemanticTimeline:BuildTemplateIndexes()
    local db = EnsureSemanticDB()
    db.templateVersion = tostring(T.SemanticBuiltinPlansVersionS14 or db.templateVersion or "mn_s1_text_v2")

    self.template = {
        version = db.templateVersion,
        instances = {},
    }
    self.instances = {}
    self.instancesByID = {}
    self.instanceByChallengeMapID = {}
    self.encountersByID = {}
    self.encountersByInstanceID = {}

    BuildBuiltinPlanCaches(self)

    local instanceRecordsByKey = {}
    for keyText, rawText in pairs(self.builtinPlanTextByBossKey or {}) do
        local bossKey = self:ParseBossSelectorKey(keyText)
        if bossKey and (NormalizeInstanceType(bossKey.instanceType) == WORKBENCH_INSTANCE_RAID or NormalizeInstanceType(bossKey.instanceType) == WORKBENCH_INSTANCE_DUNGEON) then
            local meta = (self.builtinBossMetaByBossKey and self.builtinBossMetaByBossKey[keyText]) or {}
            local normalizedType = NormalizeInstanceType(bossKey.instanceType)
            local instanceID = tonumber(meta.instanceID) or tonumber(bossKey.instanceID) or 0
            local instanceKey = string.format("%s:%d", normalizedType, instanceID)
            local instanceRecord = instanceRecordsByKey[instanceKey]

            if not instanceRecord then
                instanceRecord = {
                    instanceID = instanceID,
                    name = tostring(meta.instanceName or ""),
                    nameZh = tostring(meta.instanceNameZh or ""),
                    nameZhTW = tostring(meta.instanceNameZhTW or ""),
                    journalInstanceID = tonumber(meta.journalInstanceID) or instanceID,
                    challengeMapID = tonumber(meta.challengeMapID) or 0,
                    instanceIcon = tonumber(meta.instanceIcon) or 0,
                    type = normalizedType,
                    encounters = {},
                }
                instanceRecordsByKey[instanceKey] = instanceRecord
                self.instancesByID[instanceRecord.instanceID] = instanceRecord
                self.encountersByInstanceID[instanceRecord.instanceID] = instanceRecord.encounters
                if instanceRecord.challengeMapID > 0 then
                    self.instanceByChallengeMapID[instanceRecord.challengeMapID] = instanceRecord
                end
                self.instances[#self.instances + 1] = instanceRecord
            else
                if instanceRecord.name == "" and type(meta.instanceName) == "string" then
                    instanceRecord.name = meta.instanceName
                end
                if instanceRecord.nameZh == "" and type(meta.instanceNameZh) == "string" then
                    instanceRecord.nameZh = meta.instanceNameZh
                end
                if instanceRecord.nameZhTW == "" and type(meta.instanceNameZhTW) == "string" then
                    instanceRecord.nameZhTW = meta.instanceNameZhTW
                end
            end

            local encounterName = tostring(meta.encounterName or "")
            if not IsValidEncounterName(encounterName) then
                encounterName = self:ResolveEncounterName(bossKey.encounterID) or string.format("%s %d", L["Boss"] or "Boss", tonumber(bossKey.encounterID) or 0)
            end

            local encounterRecord = self:EnsureEncounterRecord(
                instanceRecord,
                bossKey.encounterID,
                encounterName,
                tostring(meta.encounterNameZh or ""),
                tostring(meta.encounterNameZhTW or ""),
                tonumber(meta.journalOrder) or 0,
                tonumber(meta.encounterIcon) or 0
            )

            if encounterRecord then
                encounterRecord.events = BuildBuiltinEncounterEventsFromText(rawText)
                self:SortEncounterEvents(encounterRecord)
            end
        end
    end

    table.sort(self.instances, function(a, b)
        local leftName = self:GetLocalizedInstanceName(a) or a.name or ""
        local rightName = self:GetLocalizedInstanceName(b) or b.name or ""
        if leftName ~= rightName then
            return leftName < rightName
        end
        return (tonumber(a.instanceID) or 0) < (tonumber(b.instanceID) or 0)
    end)

    for _, instanceRecord in ipairs(self.instances) do
        table.sort(instanceRecord.encounters, function(a, b)
            local leftOrder = tonumber(a.journalOrder) or 0
            local rightOrder = tonumber(b.journalOrder) or 0
            if leftOrder > 0 or rightOrder > 0 then
                if leftOrder <= 0 then
                    return false
                end
                if rightOrder <= 0 then
                    return true
                end
                if leftOrder ~= rightOrder then
                    return leftOrder < rightOrder
                end
            end
            return (tonumber(a.encounterID) or 0) < (tonumber(b.encounterID) or 0)
        end)
    end

    self.template.instances = self.instances
    self:BuildWorkbenchTemplateRows()
    self:NormalizeWorkbenchSelection()
end

function SemanticTimeline:EnsureEncounterJournalLoaded()
    if self._ejLoadTried then
        return
    end
    self._ejLoadTried = true

    local loaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        loaded = C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
    elseif IsAddOnLoaded then
        loaded = IsAddOnLoaded("Blizzard_EncounterJournal")
    end
    if loaded then
        return
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_EncounterJournal")
    end

    if type(_G.EncounterJournal_LoadUI) == "function" then
        pcall(_G.EncounterJournal_LoadUI)
    end
end

function SemanticTimeline:GetLocalizedInstanceName(instance)
    if type(instance) ~= "table" then
        return nil
    end

    local locale = GetLocale and GetLocale() or ""

    if locale == "zhCN" and type(instance.nameZh) == "string" and instance.nameZh ~= "" then
        return instance.nameZh
    elseif locale == "zhTW" and type(instance.nameZhTW) == "string" and instance.nameZhTW ~= "" then
        return instance.nameZhTW
    end

    local challengeMapID = tonumber(instance.challengeMapID)
    if challengeMapID and challengeMapID > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local mapName = C_ChallengeMode.GetMapUIInfo(challengeMapID)
        if type(mapName) == "string" and mapName ~= "" then
            return mapName
        end
    end

    if locale == "zhCN" or locale == "zhTW" then
        self:EnsureEncounterJournalLoaded()
        if EJ_GetInstanceInfo then
            local journalName = EJ_GetInstanceInfo(tonumber(instance.journalInstanceID) or tonumber(instance.instanceID) or 0)
            if type(journalName) == "string" and journalName ~= "" then
                return journalName
            end
        end
    end

    if locale == "zhCN" and type(instance.nameZh) == "string" and instance.nameZh ~= "" then
        return instance.nameZh
    end

    if type(instance.name) == "string" and instance.name ~= "" then
        return instance.name
    end
    return nil
end

function SemanticTimeline:GetLocalizedEncounterName(encounter)
    if type(encounter) ~= "table" then
        return nil
    end

    local locale = GetLocale and GetLocale() or ""

    if locale == "zhCN" and type(encounter.nameZh) == "string" and encounter.nameZh ~= "" then
        return encounter.nameZh
    elseif locale == "zhTW" and type(encounter.nameZhTW) == "string" and encounter.nameZhTW ~= "" then
        return encounter.nameZhTW
    end

    if locale == "zhCN" or locale == "zhTW" then
        local journalName = self:ResolveEncounterName(encounter.encounterID)
        if type(journalName) == "string" and journalName ~= "" then
            return journalName
        end
    end

    if locale == "zhCN" and type(encounter.nameZh) == "string" and encounter.nameZh ~= "" then
        return encounter.nameZh
    end

    if type(encounter.name) == "string" and encounter.name ~= "" then
        return encounter.name
    end

    return nil
end

function SemanticTimeline:NormalizeUISelection()
    local db = EnsureSemanticDB()
    local ui = db.ui

    if type(ui.selectedInstanceID) ~= "number" or not self.instancesByID[ui.selectedInstanceID] then
        ui.selectedInstanceID = (self.instances[1] and self.instances[1].instanceID) or nil
    end

    local encounters = ui.selectedInstanceID and self.encountersByInstanceID[ui.selectedInstanceID] or nil
    local hasEncounter = false
    if encounters and type(ui.selectedEncounterID) == "number" then
        for _, encounter in ipairs(encounters) do
            if encounter.encounterID == ui.selectedEncounterID then
                hasEncounter = true
                break
            end
        end
    end

    if not hasEncounter then
        ui.selectedEncounterID = (encounters and encounters[1] and encounters[1].encounterID) or nil
    end
end

function SemanticTimeline:GetInstanceList()
    local out = {}
    for _, instance in ipairs(self.instances or {}) do
        out[#out + 1] = {
            instanceID = instance.instanceID,
            name = self:GetLocalizedInstanceName(instance) or instance.name,
            type = instance.type,
            encounterCount = #instance.encounters,
        }
    end
    return out
end

function SemanticTimeline:GetEncounterList(instanceID)
    local out = {}
    local encounters = self.encountersByInstanceID[tonumber(instanceID) or 0] or {}
    for _, encounter in ipairs(encounters) do
        out[#out + 1] = {
            encounterID = encounter.encounterID,
            name = self:GetLocalizedEncounterName(encounter) or encounter.name,
            eventCount = #encounter.events,
        }
    end
    return out
end

function SemanticTimeline:GetEncounterName(encounterID)
    local encounter = self.encountersByID[tonumber(encounterID) or 0]
    return encounter and (self:GetLocalizedEncounterName(encounter) or encounter.name)
end

function SemanticTimeline:GetEncounterRows(encounterID)
    local db = EnsureSemanticDB()
    local encounter = self.encountersByID[tonumber(encounterID) or 0]
    local out = {}

    if not encounter then
        return out
    end

    for _, event in ipairs(encounter.events) do
        local key = BuildKey(encounter.encounterID, event.spellID, event.occurrence)
        out[#out + 1] = {
            encounterID = encounter.encounterID,
            timeSec = event.timeSec,
            timeText = FormatClock(event.timeSec),
            spellID = event.spellID,
            spellName = self:GetSpellName(event.spellID),
            occurrence = event.occurrence,
            eventType = event.eventType,
            durationSec = event.durationSec,
            note = db.notes[key] or "",
            key = key,
        }
    end

    return out
end

function SemanticTimeline:GetUISelection()
    local db = EnsureSemanticDB()
    return db.ui.selectedInstanceID, db.ui.selectedEncounterID
end

function SemanticTimeline:SetUISelection(instanceID, encounterID)
    local db = EnsureSemanticDB()
    if instanceID then
        db.ui.selectedInstanceID = tonumber(instanceID)
    end
    if encounterID then
        db.ui.selectedEncounterID = tonumber(encounterID)
    end
    self:NormalizeUISelection()
end

function SemanticTimeline:ExportText(scope, encounterID)
    if scope ~= "encounter" then
        return nil, "unsupported_scope"
    end

    local encounter = self.encountersByID[tonumber(encounterID) or 0]
    if not encounter then
        return nil, "invalid_encounter"
    end

    local db = EnsureSemanticDB()
    local lines = {
        "STT_SEMANTIC_V1",
        "scope=encounter",
        string.format("encounter_id=%d", encounter.encounterID),
        string.format("mode=%s", db.mode),
    }

    local hasAny = false
    for _, event in ipairs(encounter.events) do
        local note = db.notes[BuildKey(encounter.encounterID, event.spellID, event.occurrence)]
        if type(note) == "string" and note ~= "" then
            hasAny = true
            lines[#lines + 1] = string.format("%d#%d=%s", event.spellID, event.occurrence, EscapeNote(note))
        end
    end

    if not hasAny then
        lines[#lines + 1] = "# empty"
    end

    return table.concat(lines, "\n")
end

function SemanticTimeline:ImportText(text)
    local raw = tostring(text or ""):gsub("\r\n", "\n")
    if raw == "" then
        return nil, "empty"
    end

    local lines = {}
    for line in raw:gmatch("([^\n]*)\n?") do
        if line == nil then
            break
        end
        lines[#lines + 1] = line
        if #lines > 5000 then
            break
        end
    end

    local firstNonEmpty
    for _, line in ipairs(lines) do
        if line ~= "" then
            firstNonEmpty = line
            break
        end
    end

    if firstNonEmpty ~= "STT_SEMANTIC_V1" then
        return nil, "invalid_header"
    end

    local metadata = {}
    local updates = {}

    for _, line in ipairs(lines) do
        if line ~= "" and line ~= "STT_SEMANTIC_V1" and line:sub(1, 1) ~= "#" then
            local spellID, occurrence, value = line:match("^(%d+)#(%d+)=(.*)$")
            if spellID and occurrence then
                updates[#updates + 1] = {
                    spellID = tonumber(spellID),
                    occurrence = tonumber(occurrence),
                    value = UnescapeNote(value),
                }
            else
                local k, v = line:match("^([%a_]+)%=(.*)$")
                if k and v then
                    metadata[k] = v
                end
            end
        end
    end

    if metadata.scope and metadata.scope ~= "encounter" then
        return nil, "unsupported_scope"
    end

    local encounterID = tonumber(metadata.encounter_id)
    if not encounterID then
        return nil, "missing_encounter_id"
    end

    if not self.encountersByID[encounterID] then
        return nil, "invalid_encounter"
    end

    local db = EnsureSemanticDB()
    local upserted = 0
    local deleted = 0

    for _, item in ipairs(updates) do
        local key = BuildKey(encounterID, item.spellID, item.occurrence)
        if item.value == "" then
            if db.notes[key] ~= nil then
                db.notes[key] = nil
                deleted = deleted + 1
            end
        else
            db.notes[key] = item.value
            upserted = upserted + 1
        end
    end

    if metadata.mode then
        self:SetMode(metadata.mode)
    end

    return {
        encounterID = encounterID,
        upserted = upserted,
        deleted = deleted,
    }
end

function SemanticTimeline:IsRuntimeEnabled()
    local db = EnsureSemanticDB()
    if db.runtimeEnabled == false then
        return false
    end
    if not self.activeEncounterID then
        return false
    end
    if not self.activeIsMythic then
        return false
    end
    return true
end

function SemanticTimeline:ResetRuntimeState()
    if self.runtimeGUIRefreshTimer and self.runtimeGUIRefreshTimer.Cancel then
        self.runtimeGUIRefreshTimer:Cancel()
    end
    self.runtimeGUIRefreshTimer = nil
    self.runtimeGUIRefreshCause = nil
    self.runtimeGUIRefreshCount = 0
    self.runtimeGUIRefreshHiddenLogged = false
    self.activeEncounterID = nil
    self.activeEncounterName = nil
    self.activeInstanceID = nil
    self.activeStartTime = nil
    self.activeIsMythic = false
    self.occurrenceBySpell = {}
    self.eventIDToKey = {}
    self.centerShownEvents = {}
end

function SemanticTimeline:RequestRuntimeGUIRefresh(cause)
    local gui = T.SemanticTimelineGUI
    if not (gui and gui.RefreshData) then
        return
    end

    local refreshCause = type(cause) == "string" and cause or "runtime"
    local isVisible = true
    if gui.IsVisible then
        isVisible = gui.IsVisible()
    end
    if not isVisible then
        if self.runtimeGUIRefreshTimer and self.runtimeGUIRefreshTimer.Cancel then
            self.runtimeGUIRefreshTimer:Cancel()
        end
        self.runtimeGUIRefreshTimer = nil
        self.runtimeGUIRefreshCause = nil
        self.runtimeGUIRefreshCount = 0
        if not self.runtimeGUIRefreshHiddenLogged and T.debug and C and C.DB and C.DB.debugMode then
            T.debug(string.format(
                "[SemanticTimeline] RuntimeGUIRefreshSkipped cause=%s reason=gui_hidden",
                refreshCause
            ))
        end
        self.runtimeGUIRefreshHiddenLogged = true
        return
    end

    self.runtimeGUIRefreshHiddenLogged = false
    self.runtimeGUIRefreshCause = self.runtimeGUIRefreshCause or refreshCause
    self.runtimeGUIRefreshCount = (tonumber(self.runtimeGUIRefreshCount) or 0) + 1
    if self.runtimeGUIRefreshTimer then
        return
    end

    local function FlushRuntimeGUIRefresh()
        self.runtimeGUIRefreshTimer = nil
        local pendingCause = self.runtimeGUIRefreshCause or refreshCause
        local pendingCount = tonumber(self.runtimeGUIRefreshCount) or 0
        self.runtimeGUIRefreshCause = nil
        self.runtimeGUIRefreshCount = 0

        local currentGUI = T.SemanticTimelineGUI
        if not (currentGUI and currentGUI.RefreshData) then
            return
        end
        if currentGUI.IsVisible and not currentGUI.IsVisible() then
            if not self.runtimeGUIRefreshHiddenLogged and T.debug and C and C.DB and C.DB.debugMode then
                T.debug(string.format(
                    "[SemanticTimeline] RuntimeGUIRefreshSkipped cause=%s reason=gui_hidden",
                    pendingCause
                ))
            end
            self.runtimeGUIRefreshHiddenLogged = true
            return
        end

        if pendingCount > 1 and T.debug and C and C.DB and C.DB.debugMode then
            T.debug(string.format(
                "[SemanticTimeline] RuntimeGUIRefreshCoalesced cause=%s count=%d",
                pendingCause,
                pendingCount
            ))
        end
        currentGUI.RefreshData(pendingCause)
    end

    if C_Timer and C_Timer.NewTimer then
        self.runtimeGUIRefreshTimer = C_Timer.NewTimer(0.05, FlushRuntimeGUIRefresh)
    else
        FlushRuntimeGUIRefresh()
    end
end

function SemanticTimeline:GetCurrentPlayerMapID()
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = tonumber(C_Map.GetBestMapForUnit("player"))
        if mapID and mapID > 0 then
            return mapID
        end
    end
    return nil
end

function SemanticTimeline:GetActiveChallengeMapID()
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local mapID = tonumber(C_ChallengeMode.GetActiveChallengeMapID())
        if mapID and mapID > 0 then
            return mapID
        end
    end
    return nil
end

function SemanticTimeline:ResolveInstanceIDForEncounter(encounterID)
    local existing = self.encountersByID and self.encountersByID[tonumber(encounterID) or 0]
    if existing then
        return existing.instanceID
    end

    local challengeMapID = self:GetActiveChallengeMapID()
    local instanceRecord = challengeMapID and self.instanceByChallengeMapID and self.instanceByChallengeMapID[challengeMapID] or nil
    return instanceRecord and instanceRecord.instanceID or nil
end

function SemanticTimeline:ResolveInstanceIDForMap(mapID)
    local normalizedMapID = tonumber(mapID)
    if not normalizedMapID or normalizedMapID <= 0 then
        return nil
    end

    local challengeRecord = self.instanceByChallengeMapID and self.instanceByChallengeMapID[normalizedMapID] or nil
    if challengeRecord and challengeRecord.instanceID then
        return challengeRecord.instanceID
    end

    self:EnsureEncounterJournalLoaded()

    local journalInstanceID = nil
    if C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap then
        journalInstanceID = tonumber(C_EncounterJournal.GetInstanceForGameMap(normalizedMapID))
    elseif EJ_GetInstanceForMap then
        journalInstanceID = tonumber(EJ_GetInstanceForMap(normalizedMapID))
    end
    if not journalInstanceID or journalInstanceID <= 0 then
        return nil
    end

    for _, instanceRecord in ipairs(self.instances or {}) do
        if tonumber(instanceRecord.journalInstanceID) == journalInstanceID
            or tonumber(instanceRecord.instanceID) == journalInstanceID then
            return tonumber(instanceRecord.instanceID)
        end
    end
    return nil
end

function SemanticTimeline:GetLastKnownEncounterID()
    local encounterID = tonumber(self.activeEncounterID)
    if encounterID and encounterID > 0 then
        return encounterID
    end

    encounterID = tonumber(self.lastEncounterID)
    if encounterID and encounterID > 0 then
        return encounterID
    end
    return nil
end

function SemanticTimeline:ResolveBossKeyByEncounterID(encounterID)
    local normalizedEncounterID = tonumber(encounterID)
    if not normalizedEncounterID or normalizedEncounterID <= 0 then
        return nil
    end

    local instanceID = self:ResolveInstanceIDForEncounter(normalizedEncounterID)
    if not instanceID or instanceID <= 0 then
        return nil
    end

    local instanceRecord = self.instancesByID and self.instancesByID[instanceID] or nil
    if not instanceRecord then
        return nil
    end

    return self:BuildBossSelectorKey(
        instanceRecord.type,
        instanceID,
        normalizedEncounterID
    )
end

function SemanticTimeline:ResolveBossKeyByMapID(mapID)
    local normalizedMapID = tonumber(mapID)
    if not normalizedMapID or normalizedMapID <= 0 then
        return nil, nil
    end

    local note = T.Note and T.Note.GetPlanByMapID and T.Note:GetPlanByMapID(normalizedMapID) or nil
    local noteEncounterID = note and tonumber(note.encounterID) or nil
    if noteEncounterID and noteEncounterID > 0 then
        local bossKey = self:ResolveBossKeyByEncounterID(noteEncounterID)
        if bossKey then
            return bossKey, "map_plan"
        end
    end

    local instanceID = self:ResolveInstanceIDForMap(normalizedMapID)
    if not instanceID or instanceID <= 0 then
        return nil, nil
    end

    local instanceRecord = self.instancesByID and self.instancesByID[instanceID] or nil
    if instanceRecord and #(instanceRecord.encounters or {}) == 1 then
        local encounter = instanceRecord.encounters[1]
        if encounter and tonumber(encounter.encounterID) and tonumber(encounter.encounterID) > 0 then
            return self:BuildBossSelectorKey(
                instanceRecord.type,
                instanceID,
                encounter.encounterID
            ), "map_unique_instance"
        end
    end

    return nil, instanceRecord and "map_instance_only" or nil
end

function SemanticTimeline:ResolveAutoBossContext()
    local mapID = self:GetCurrentPlayerMapID()
    local bossKey, mapSource = self:ResolveBossKeyByMapID(mapID)
    if bossKey then
        local bossKeyText = self:SerializeBossSelectorKey(bossKey)
        return {
            source = tostring(mapSource or "map"),
            mapID = mapID,
            encounterID = tonumber(bossKey.encounterID) or nil,
            bossKey = bossKey,
            bossKeyText = bossKeyText,
            contextKey = "boss:" .. bossKeyText,
        }
    end

    local encounterID = self:GetLastKnownEncounterID()
    bossKey = self:ResolveBossKeyByEncounterID(encounterID)
    if bossKey then
        local bossKeyText = self:SerializeBossSelectorKey(bossKey)
        return {
            source = "encounter",
            mapID = mapID,
            encounterID = tonumber(encounterID) or nil,
            bossKey = bossKey,
            bossKeyText = bossKeyText,
            contextKey = "boss:" .. bossKeyText,
        }
    end

    return nil
end

function SemanticTimeline:RecordManualBossSelection(bossKey)
    local normalizedBossKey = CopyBossKey(bossKey) or self:GetCurrentBossSelectorKey()
    if not normalizedBossKey then
        return
    end

    local keyText = self:SerializeBossSelectorKey(normalizedBossKey)
    self.autoSwitchState = self.autoSwitchState or {}
    self.autoSwitchState.lastManualEditorBossKeyText = keyText
end

function SemanticTimeline:ClearManualBossSelection()
    if not self.autoSwitchState then
        return
    end
    self.autoSwitchState.lastManualEditorBossKeyText = nil
end

function SemanticTimeline:ApplyAutoBossSelection(reason)
    local context = self:ResolveAutoBossContext()
    if not context or not context.bossKeyText then
        return false, "no_target"
    end

    self.autoSwitchState = self.autoSwitchState or {}
    local state = self.autoSwitchState

    local currentBossKeyText = self:SerializeBossSelectorKey(self:GetCurrentBossSelectorKey())

    state.lastResolvedSource = tostring(reason or context.source or "")
    state.lastResolvedContextKey = context.contextKey
    state.lastResolvedMapID = tonumber(context.mapID) or nil
    state.lastResolvedEncounterID = tonumber(context.encounterID) or nil

    if currentBossKeyText == context.bossKeyText then
        if C and C.DB and C.DB.debugMode then
            T.debug(string.format(
                "AutoSelectBoss: reason=%s source=%s boss=%s result=already_selected",
                tostring(reason or ""),
                tostring(context.source or ""),
                tostring(context.bossKeyText)
            ))
        end
        state.lastContextKey = context.contextKey
        state.lastAutoBossKeyText = context.bossKeyText
        return false, "already_selected"
    end

    self:SwitchWorkbenchToBossKeyText(context.bossKeyText)
    state.lastContextKey = context.contextKey
    state.lastAutoBossKeyText = context.bossKeyText

    if C and C.DB and C.DB.debugMode then
        T.debug(string.format(
            "AutoSelectBoss: reason=%s source=%s context=%s boss=%s",
            tostring(reason or ""),
            tostring(context.source or ""),
            tostring(context.contextKey),
            tostring(context.bossKeyText)
        ))
    end
    return true, context
end

function SemanticTimeline:ScheduleAutoBossSelection(reason, delay)
    self.autoSwitchState = self.autoSwitchState or {}
    if self.autoSwitchState.refreshTimer and self.autoSwitchState.refreshTimer.Cancel then
        self.autoSwitchState.refreshTimer:Cancel()
    end
    self.autoSwitchState.refreshTimer = C_Timer.NewTimer(delay or 0.2, function()
        if self.autoSwitchState then
            self.autoSwitchState.refreshTimer = nil
        end
        self:ApplyAutoBossSelection(reason)
    end)
end

function SemanticTimeline:GetRuntimeEncounterName(encounterID, fallbackName)
    local name = tostring(fallbackName or "")
    if IsValidEncounterName(name) then
        return name
    end

    return self:ResolveEncounterName(encounterID)
end

function SemanticTimeline:PersistCapturedEncounter(encounterID, instanceID, encounterName)
    local db = EnsureSemanticDB()
    local key = tostring(tonumber(encounterID) or 0)
    local record = db.captured.encounters[key]

    if type(record) ~= "table" then
        record = {
            instanceID = tonumber(instanceID) or 0,
            name = IsValidEncounterName(encounterName) and tostring(encounterName) or "",
            nameZh = "",
            events = {},
        }
        db.captured.encounters[key] = record
    end

    if type(record.events) ~= "table" then
        record.events = {}
    end
    if tonumber(instanceID) and tonumber(instanceID) > 0 then
        record.instanceID = tonumber(instanceID)
    end
    if IsValidEncounterName(encounterName) then
        record.name = encounterName
    end

    return record
end

function SemanticTimeline:EnsureRuntimeEncounterVisible()
    if not self.activeIsMythic or not self.activeEncounterID or not self.activeInstanceID then
        return nil
    end

    local instanceRecord = self.instancesByID and self.instancesByID[self.activeInstanceID]
    if not instanceRecord then
        return nil
    end

    local encounterName = self:GetRuntimeEncounterName(self.activeEncounterID, self.activeEncounterName)
    local encounterRecord = self:EnsureEncounterRecord(instanceRecord, self.activeEncounterID, encounterName, "", "")
    if not encounterRecord then
        return nil
    end
    table.sort(instanceRecord.encounters, function(a, b)
        return a.encounterID < b.encounterID
    end)
    return encounterRecord
end

function SemanticTimeline:CaptureRuntimeEvent(eventInfo, occurrence, spellMeta)
    if not self.activeIsMythic or not self.activeEncounterID or not self.activeInstanceID then
        return
    end

    if not spellMeta then
        spellMeta = T.EncounterEventResolver and T.EncounterEventResolver.ResolveEncounterSpellMeta
            and T.EncounterEventResolver.ResolveEncounterSpellMeta(eventInfo, self.activeEncounterID)
            or nil
    end
    local spellID = spellMeta and spellMeta.spellID or 0
    local normalizedOccurrence = tonumber(occurrence) or 0
    if spellID <= 0 or normalizedOccurrence <= 0 then
        return
    end

    local durationSec = tonumber(eventInfo and eventInfo.duration) or 0
    local elapsedSec = 0
    if self.activeStartTime then
        elapsedSec = math.max(0, GetTime() - self.activeStartTime)
    end

    local timeSec = math.floor((elapsedSec + durationSec) * 10 + 0.5) / 10
    local eventType = tostring((eventInfo and eventInfo.eventType) or "RUNTIME")
    local encounterName = self:GetRuntimeEncounterName(self.activeEncounterID, self.activeEncounterName)

    local capturedEncounter = self:PersistCapturedEncounter(self.activeEncounterID, self.activeInstanceID, encounterName)
    local eventKey = BuildSpellOccurrenceKey(spellID, normalizedOccurrence)
    local capturedRow

    for _, row in ipairs(capturedEncounter.events) do
        if BuildSpellOccurrenceKey(row.spellID, row.occurrence) == eventKey then
            capturedRow = row
            break
        end
    end

    local changedCapture = false
    if capturedRow then
        if capturedRow.timeSec == nil and timeSec ~= nil then
            capturedRow.timeSec = timeSec
            changedCapture = true
        end
        if capturedRow.durationSec == nil and durationSec > 0 then
            capturedRow.durationSec = durationSec
            changedCapture = true
        end
        if (not capturedRow.eventType or capturedRow.eventType == "") and eventType ~= "" then
            capturedRow.eventType = eventType
            changedCapture = true
        end
    else
        capturedEncounter.events[#capturedEncounter.events + 1] = {
            spellID = spellID,
            occurrence = normalizedOccurrence,
            timeSec = timeSec,
            eventType = eventType,
            durationSec = durationSec > 0 and durationSec or nil,
        }
        changedCapture = true
    end

    local encounterRecord = self:EnsureRuntimeEncounterVisible()
    local changedView = false
    if encounterRecord then
        local viewRow = self:HasEncounterEvent(encounterRecord, spellID, normalizedOccurrence)
        if viewRow then
            if viewRow.timeSec == nil and timeSec ~= nil then
                viewRow.timeSec = timeSec
                changedView = true
            end
            if viewRow.durationSec == nil and durationSec > 0 then
                viewRow.durationSec = durationSec
                changedView = true
            end
            if (not viewRow.eventType or viewRow.eventType == "") and eventType ~= "" then
                viewRow.eventType = eventType
                changedView = true
            end
        else
            encounterRecord.events[#encounterRecord.events + 1] = {
                spellID = spellID,
                occurrence = normalizedOccurrence,
                timeSec = timeSec,
                eventType = eventType,
                durationSec = durationSec > 0 and durationSec or nil,
            }
            changedView = true
        end
        if changedView then
            self:SortEncounterEvents(encounterRecord)
        end
    end

    if changedCapture or changedView then
        self:RequestRuntimeGUIRefresh("timeline_event_runtime")
    end
end

function SemanticTimeline:EnsureNoticeFrame()
    if self.noticeFrame then
        return self.noticeFrame
    end

    local frame = CreateFrame("Frame", "STT_SemanticNoticeFrame", UIParent, "BackdropTemplate")
    frame:SetSize(700, 56)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(30)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.75)
        frame:SetBackdropBorderColor(0.9, 0.75, 0.2, 0.85)
    end

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetTextColor(1, 0.9, 0.25, 1)
    text:SetJustifyH("CENTER")
    text:SetText("")

    frame.text = text
    frame:Hide()

    self.noticeFrame = frame
    return frame
end

function SemanticTimeline:HideNotice()
    local frame = self.noticeFrame
    if frame then
        frame.token = (frame.token or 0) + 1
        frame:Hide()
    end
end

function SemanticTimeline:ShowNotice(text, opts)
    if type(text) ~= "string" or text == "" then
        return
    end
    local options = type(opts) == "table" and opts or nil

    if T.TacticalNotice and C.DB.screenReminder and C.DB.screenReminder.enabled ~= false then
        T.TacticalNotice:ShowReminder({
            text = text,
            duration = (options and tonumber(options.duration)) or 2.5,
            severity = options and options.severity or nil,
        })
        return
    end

    local frame = self:EnsureNoticeFrame()
    frame.text:SetText(text)
    frame:SetAlpha(1)
    frame:Show()

    frame.token = (frame.token or 0) + 1
    local token = frame.token

    C_Timer.After(2.3, function()
        if not frame or frame.token ~= token then
            return
        end
        -- 自建 OnUpdate 淡出，避免把 frame 推入 Blizzard 全局 FADEFRAMES 导致聊天窗 fadeInfo taint
        local startTime = GetTime()
        local duration = 0.25
        frame:SetScript("OnUpdate", function(self, _)
            if self.token ~= token then
                self:SetScript("OnUpdate", nil)
                return
            end
            local elapsed = GetTime() - startTime
            if elapsed >= duration then
                self:SetAlpha(0)
                self:Hide()
                self:SetScript("OnUpdate", nil)
            else
                self:SetAlpha(1 - elapsed / duration)
            end
        end)
    end)
end

function SemanticTimeline:MaybeShowCenterByEventID(eventID)
    local db = EnsureSemanticDB()
    if db.mode ~= MODE_CENTER then
        return
    end

    local key = self.eventIDToKey[eventID]
    if not key then
        return
    end

    if self.centerShownEvents[eventID] then
        return
    end

    local note = db.notes[key]
    if type(note) ~= "string" or note == "" then
        return
    end

    self.centerShownEvents[eventID] = true
    self:ShowNotice(note)
end

local function ApplyTimelineFrameText(frame, text, color)
    if type(text) ~= "string" or text == "" then
        return false
    end

    if type(frame.SetNameText) == "function" then
        frame:SetNameText(text, color)
        return true
    end

    if type(frame.GetNameFontString) == "function" then
        local fs = frame:GetNameFontString()
        if fs and fs.SetText then
            fs:SetText(text)
            if color and fs.SetTextColor and type(color.GetRGB) == "function" then
                fs:SetTextColor(color:GetRGB())
            end
            if fs.Show then
                fs:Show()
            end
            return true
        end
    end

    return false
end

function SemanticTimeline:ApplyTextOverride(frame)
    if type(frame) ~= "table" or type(frame.GetEventID) ~= "function" then
        return
    end

    local eventID = frame:GetEventID()
    local eventInfo = frame.GetEventInfo and frame:GetEventInfo() or nil
    local frameColor = eventInfo and eventInfo.color or nil

    if T.TriggerRunner and T.TriggerRunner.IsRunning and T.TriggerRunner:IsRunning() then
        -- 触发轴运行时不再改写 Blizzard EncounterTimeline 名字文本，
        -- 避免 12.x 下把 secret value 带进 AutoScalingFontStringMixin 触发 taint。
        return
    end

    if not self:IsRuntimeEnabled() then
        return
    end

    local db = EnsureSemanticDB()
    if db.mode ~= MODE_OVERRIDE and db.mode ~= MODE_COMBINE then
        return
    end

    local key = self.eventIDToKey[eventID]
    if not key then
        return
    end

    local note = db.notes[key]
    if type(note) ~= "string" or note == "" then
        return
    end

    local text = note
    if db.mode == MODE_COMBINE then
        local original = ""
        local spellMeta = T.EncounterEventResolver and T.EncounterEventResolver.ResolveEncounterSpellMeta
            and T.EncounterEventResolver.ResolveEncounterSpellMeta(eventID, self.activeEncounterID)
            or nil
        if spellMeta and type(spellMeta.spellName) == "string" then
            original = spellMeta.spellName
        end
        if original ~= "" then
            text = string.format("%s（%s）", original, note)
        end
    end

    ApplyTimelineFrameText(frame, text, frameColor)
end

function SemanticTimeline:TryInstallHooks()
    if self.hooksInstalled then
        return
    end

    if type(hooksecurefunc) ~= "function" then
        return
    end

    local installedAny = false

    if type(EncounterTimelineTrackEventMixin) == "table" and type(EncounterTimelineTrackEventMixin.UpdateNameText) == "function" then
        hooksecurefunc(EncounterTimelineTrackEventMixin, "UpdateNameText", function(frame)
            SemanticTimeline:ApplyTextOverride(frame)
        end)
        installedAny = true
    end

    if type(EncounterTimelineTimerEventMixin) == "table" and type(EncounterTimelineTimerEventMixin.UpdateNameText) == "function" then
        hooksecurefunc(EncounterTimelineTimerEventMixin, "UpdateNameText", function(frame)
            SemanticTimeline:ApplyTextOverride(frame)
        end)
        installedAny = true
    end

    self.hooksInstalled = installedAny
end

function SemanticTimeline:OnEncounterStart(encounterID, _encounterName, difficultyID)
    local perf = T.CreatePerfProfile and T.CreatePerfProfile("OnEncounterStart_semantic") or nil
    self:ResetRuntimeState()
    if perf then perf:Mark("ResetRuntimeState") end
    self.activeEncounterID = tonumber(encounterID)
    self.lastEncounterID = tonumber(encounterID) or self.lastEncounterID
    self.activeEncounterName = tostring(_encounterName or "")
    self.activeIsMythic = self:IsMythicDifficulty(tonumber(difficultyID))
    self.activeStartTime = GetTime()
    local encounterBossKey = self:ResolveBossKeyByEncounterID(self.activeEncounterID)
    if encounterBossKey and T.Note and T.Note.SetCurrentBossKey then
        T.Note:SetCurrentBossKey(encounterBossKey, "encounter_start")
    end
    local syncOK, syncReason = self:ApplyAutoBossSelection("encounter_start_sync")
    if perf then perf:Mark("ApplyAutoBossSelection") end
    if not syncOK and syncReason == "no_target" then
        -- 同步解析不到目标时再降级重试，避免对已命中/手动锁定重复调度。
        self:ScheduleAutoBossSelection("encounter_start", 0.1)
    end

    if not self.activeEncounterID or not self.activeIsMythic then
        if perf then perf:Finish() end
        return
    end

    self.activeInstanceID = self:ResolveInstanceIDForEncounter(self.activeEncounterID)
    if perf then perf:Mark("ResolveInstanceID") end
    if self.activeInstanceID then
        local name = self:GetRuntimeEncounterName(self.activeEncounterID, self.activeEncounterName)
        if IsValidEncounterName(name) then
            self:PersistCapturedEncounter(self.activeEncounterID, self.activeInstanceID, name)
            if perf then perf:Mark("PersistCapturedEncounter") end
            local encounterRecord = self:EnsureRuntimeEncounterVisible()
            if perf then perf:Mark("EnsureRuntimeEncounterVisible") end
            if encounterRecord then
                self:RequestRuntimeGUIRefresh("encounter_start_runtime")
                if perf then perf:Mark("RequestRuntimeGUIRefresh") end
            end
        end
    end
    if perf then perf:Finish() end
end

function SemanticTimeline:RebuildIndexesAndRefreshUI()
    self:RebuildTemplateIndexes(true)
    self:EnsureSemanticBossPlansInitialized({
        force = true,
        cause = "rebuild_indexes",
    })
    self:NormalizeUISelection()
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.RefreshData then
        T.SemanticTimelineGUI.RefreshData("rebuild_indexes")
    end
end

function SemanticTimeline:OnEncounterEnd()
    if tonumber(self.activeEncounterID) and tonumber(self.activeEncounterID) > 0 then
        self.lastEncounterID = tonumber(self.activeEncounterID)
    end
    self:ResetRuntimeState()
    self:HideNotice()
end

function SemanticTimeline:OnTimelineEventAdded(eventInfo)
    if not self:IsRuntimeEnabled() then
        return
    end

    if type(eventInfo) ~= "table" then
        return
    end

    if eventInfo.source ~= ENCOUNTER_SOURCE then
        return
    end

    local spellMeta = T.EncounterEventResolver and T.EncounterEventResolver.ResolveEncounterSpellMeta
        and T.EncounterEventResolver.ResolveEncounterSpellMeta(eventInfo, self.activeEncounterID)
        or nil
    if not spellMeta then
        return
    end

    local eventID = spellMeta.eventID
    local spellID = spellMeta.spellID

    local occurrence = (self.occurrenceBySpell[spellID] or 0) + 1
    self.occurrenceBySpell[spellID] = occurrence

    self.eventIDToKey[eventID] = BuildKey(self.activeEncounterID, spellID, occurrence)
    self:CaptureRuntimeEvent(eventInfo, occurrence, spellMeta)
end

function SemanticTimeline:OnTimelineEventRemoved(eventID)
    eventID = tonumber(eventID)
    if not eventID then
        return
    end
    self.eventIDToKey[eventID] = nil
    self.centerShownEvents[eventID] = nil
end

function SemanticTimeline:OnTimelineEventStateChanged(eventID)
    if not self:IsRuntimeEnabled() then
        return
    end

    local db = EnsureSemanticDB()
    if db.mode ~= MODE_CENTER or db.centerTrigger ~= TRIGGER_DUE then
        return
    end

    if not C_EncounterTimeline or not C_EncounterTimeline.GetEventState then
        return
    end

    eventID = tonumber(eventID)
    if not eventID then
        return
    end

    local state = C_EncounterTimeline.GetEventState(eventID)
    if state == EVENT_STATE_FINISHED then
        self:MaybeShowCenterByEventID(eventID)
    end
end

function SemanticTimeline:OnTimelineEventHighlight(eventID)
    if not self:IsRuntimeEnabled() then
        return
    end

    local db = EnsureSemanticDB()
    if db.mode ~= MODE_CENTER or db.centerTrigger ~= TRIGGER_HIGHLIGHT then
        return
    end

    eventID = tonumber(eventID)
    if not eventID then
        return
    end

    self:MaybeShowCenterByEventID(eventID)
end

function SemanticTimeline:OnEvent(event, ...)
    if event == "ENCOUNTER_START" then
        self:OnEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        self:OnEncounterEnd()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        if not IsInInstance or not select(1, IsInInstance()) then
            self.lastEncounterID = nil
        end
        self:ScheduleAutoBossSelection(string.lower(event), 0.5)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        self:OnTimelineEventAdded(...)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        self:OnTimelineEventRemoved(...)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        self:OnTimelineEventStateChanged(...)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT" then
        self:OnTimelineEventHighlight(...)
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_EncounterTimeline" then
            self:TryInstallHooks()
        end
    elseif event == "PLAYER_LOGIN" then
        self:TryInstallHooks()
    end
end

local function OnProfileChanged(self, _, previousProfileID)
    if not self.profileChangedActive then
        return
    end
    if self.WipeCompiledPlanCache then
        self:WipeCompiledPlanCache()
    end
    if self.ResetSemanticBossPlansInitialization then
        self:ResetSemanticBossPlansInitialization()
    end
    if self.NormalizeUISelection then
        self:NormalizeUISelection()
    end
    if previousProfileID ~= nil then
        if self.semanticInitTimer and self.semanticInitTimer.Cancel then
            self.semanticInitTimer:Cancel()
            self.semanticInitTimer = nil
        end
        if self.EnsureSemanticBossPlansInitialized then
            self:EnsureSemanticBossPlansInitialized({
                cause = "profile_changed",
                force = true,
            })
        end
    elseif self.ScheduleSemanticBossPlansInitialization then
        self:ScheduleSemanticBossPlansInitialization("profile_changed", 0.1, true)
    end
end

local function RegisterProfileChanged()
    if SemanticTimeline.profileChangedRegistered or not T.events then
        return
    end
    T.events:Register("STT_PROFILE_CHANGED", SemanticTimeline, OnProfileChanged)
    SemanticTimeline.profileChangedRegistered = true
end

function SemanticTimeline:Init()
    if self.initialized == true then
        return
    end
    self.initialized = true
    self.profileChangedActive = true
    RegisterProfileChanged()
    EnsureSemanticDB()
    self:ResetRuntimeState()
    self:TryInstallHooks()

    if not self.eventFrame then
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_LOGIN")
        frame:RegisterEvent("ADDON_LOADED")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frame:RegisterEvent("ZONE_CHANGED_INDOORS")
        frame:RegisterEvent("ENCOUNTER_START")
        frame:RegisterEvent("ENCOUNTER_END")
        frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
        frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED")
        frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
        frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT")
        frame:SetScript("OnEvent", function(_, event, ...)
            SemanticTimeline:OnEvent(event, ...)
        end)
        self.eventFrame = frame
    end

end

function SemanticTimeline:OnEnable()
    self:Init()
end

function SemanticTimeline:OnDisable()
    self.initialized = false
    self.profileChangedActive = false
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    self:ResetRuntimeState()
end

T.GetEmbeddedTemplateText = function(canonicalSpellID, context)
    if T.SemanticTimeline and T.SemanticTimeline.GetEmbeddedTemplateText then
        return T.SemanticTimeline:GetEmbeddedTemplateText(canonicalSpellID, context)
    end
    return ""
end

T.GetEmbeddedRetimeAction = function(canonicalSpellID, context)
    if T.SemanticTimeline and T.SemanticTimeline.GetEmbeddedRetimeAction then
        return T.SemanticTimeline:GetEmbeddedRetimeAction(canonicalSpellID, context)
    end
    return nil
end

end)
