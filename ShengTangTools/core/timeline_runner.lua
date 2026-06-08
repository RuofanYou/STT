local select, unpack = select, unpack
local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()
local C_Timer, CreateFrame, GetTime = C_Timer, CreateFrame, GetTime
local ipairs, next, pairs, pcall, type = ipairs, next, pairs, pcall, type
local tonumber, tostring, xpcall = tonumber, tostring, xpcall
local math, string, table = math, string, table

-- 时间轴统一调度器（MRT / STN 共用；12.0 合规：仅时间轴驱动，不依赖战斗日志/团队通讯）
local Runner = {}
T.TimelineRunner = Runner

-- 内部状态
local schedulerOnUpdate
local scheduler = {
    elapsed = 0,
    startTime = 0,
    index = 1,
    isTest = false,
    encounterID = 0,
    testAutoStopAt = 0,
    currentTime = 0,
    paused = false,
    isStaticPreview = false,
    _shown = false,
}

function scheduler:Hide()
    self._shown = false
end

function scheduler:Show()
    self._shown = true
end

function scheduler:IsShown()
    return self._shown == true
end

local function EnsureSchedulerFrame()
    if scheduler._isFrame == true then
        return scheduler
    end

    local state = scheduler
    local frame = CreateFrame("Frame")
    for key, value in pairs(state) do
        if type(value) ~= "function" and key ~= "_shown" then
            frame[key] = value
        end
    end
    frame._isFrame = true
    frame:SetScript("OnUpdate", schedulerOnUpdate)
    frame:Hide()
    scheduler = frame
    return scheduler
end
local transportLoop = {
    enabled = false,
    startTime = 0,
    endTime = 0,
}

-- 过滤后的时间轴仍是播报与提醒的单一权威。
local timeline = {}
-- 展示版时间轴仅供实时战术板使用，保留全部原始行文本。
local boardTimeline = {}
T.BoardTimeline = boardTimeline
local timelineMaxTime = 0
local timelinePreviewMaxTime = 0
local boardPreviewMaxTime = 0
local previewTransportMaxTime = 0
local transportMaxTimeCache = 0
local phaseWarned = {}
local pendingCountdownTimers = {}
local pendingBarTimers = {}
local TTS_AUDIO_COMPENSATION = 0.3
local subscribers = {}
local nextSubscriberID = 0
local runtimeReloadToken = 0

local function GetEventDurationValue(event)
    local modifiers = type(event and event.modifiers) == "table" and event.modifiers or nil
    local duration = modifiers and modifiers.dur and tonumber(modifiers.dur.value) or nil
    return duration and duration > 0 and duration or 0
end

local function ResetTransportRangeCache()
    timelineMaxTime = 0
    timelinePreviewMaxTime = 0
    boardPreviewMaxTime = 0
    previewTransportMaxTime = 0
    transportMaxTimeCache = 0
end

local function GetTimelineMaxTime()
    return timelineMaxTime
end

local function ShouldKeepBoardTransport()
    local db = C.DB and C.DB.realtimeBoard
    return not scheduler.isTest
        and #boardTimeline > 0
        and type(db) == "table"
        and db.enabled ~= false
        and db.showAllEvents == true
end

local function IsLoopRangeValid()
    return (tonumber(transportLoop.endTime) or 0) > (tonumber(transportLoop.startTime) or 0)
end

local function ClampLoopRangeToTransport()
    local maxTime = tonumber(transportMaxTimeCache) or 0
    if maxTime <= 0 or not IsLoopRangeValid() then
        return
    end
    transportLoop.startTime = math.max(0, math.min(tonumber(transportLoop.startTime) or 0, maxTime))
    transportLoop.endTime = math.max(0, math.min(tonumber(transportLoop.endTime) or 0, maxTime))
    if not IsLoopRangeValid() then
        transportLoop.enabled = false
    end
end

local function RefreshTransportMaxTimeCache()
    if scheduler.isTest and previewTransportMaxTime > 0 then
        transportMaxTimeCache = previewTransportMaxTime
    elseif scheduler.isTest and #boardTimeline > 0 then
        transportMaxTimeCache = boardPreviewMaxTime
    elseif ShouldKeepBoardTransport() then
        transportMaxTimeCache = previewTransportMaxTime > 0 and previewTransportMaxTime or boardPreviewMaxTime
    else
        transportMaxTimeCache = timelineMaxTime
    end
    ClampLoopRangeToTransport()
    return transportMaxTimeCache
end

local function GetTransportMaxTime()
    return transportMaxTimeCache
end

local function GetCurrentRunnerTime()
    if scheduler:IsShown() and not scheduler.paused then
        return math.max(0, GetTime() - (tonumber(scheduler.startTime) or GetTime()))
    end
    return math.max(0, tonumber(scheduler.currentTime) or 0)
end

local function HasRuntimeTimeline()
    return #timeline > 0 or #boardTimeline > 0
end

local function BuildRunnerState()
    return {
        playing = scheduler:IsShown() and not scheduler.paused,
        currentTime = GetCurrentRunnerTime(),
        totalTime = GetTransportMaxTime(),
        isTest = scheduler.isTest and true or false,
        loopEnabled = transportLoop.enabled == true and IsLoopRangeValid(),
        loopStart = tonumber(transportLoop.startTime) or 0,
        loopEnd = tonumber(transportLoop.endTime) or 0,
    }
end

local function NotifySubscribers()
    if not next(subscribers) then
        return
    end
    local state = BuildRunnerState()
    for id, item in pairs(subscribers) do
        local ok, err = pcall(item.callback, state)
        if not ok then
            item.failures = (item.failures or 0) + 1
            if item.failures >= 3 then
                subscribers[id] = nil
                if T.debug then
                    T.debug("[STT_RUNNER_SUBSCRIBER_DISABLED] " .. tostring(err))
                end
            end
        else
            item.failures = 0
        end
    end
end

local function RefreshTestAutoStopAt()
    local maxKnownEventTime = GetTransportMaxTime()
    scheduler.testAutoStopAt = scheduler.startTime + maxKnownEventTime + math.max(3, tonumber(C.DB.ttsAdvanceTime) or 0) + 1
end

local function DebugTransportRange(reason)
    if not (C.DB and C.DB.debugMode and T.debug) then
        return
    end
    T.debug(string.format(
        "[STT_RUNNER_TRANSPORT_RANGE] reason=%s triggerMax=%.1f transportMax=%.1f timeline=%d board=%d isTest=%s",
        tostring(reason or "unknown"),
        GetTimelineMaxTime(),
        GetTransportMaxTime(),
        #timeline,
        #boardTimeline,
        tostring(scheduler.isTest == true)
    ))
end

local function ResetEventRuntimeFlags(targetTime)
    local current = math.max(0, tonumber(targetTime) or 0)
    for _, event in ipairs(timeline) do
        local eventTime = scheduler.isTest and (tonumber(event.previewTime) or tonumber(event.time) or 0) or (tonumber(event.time) or 0)
        local eventPassed = eventTime <= current
        event.triggered = eventPassed
        event.reminderCreated = eventPassed
        event.countdownScheduled = false
        event.barScheduled = false
        event.ignored = false
    end
end

local function CancelAllPendingCountdownTimers()
    for _, timer in ipairs(pendingCountdownTimers) do
        if timer and timer.Cancel then
            timer:Cancel()
        end
    end
    wipe(pendingCountdownTimers)
end

local function CancelAllPendingBarTimers()
    for _, timer in ipairs(pendingBarTimers) do
        if timer and timer.Cancel then
            timer:Cancel()
        end
    end
    wipe(pendingBarTimers)
end

local function ApplyTransportPosition(nextTime)
    scheduler.currentTime = math.max(0, tonumber(nextTime) or 0)
    scheduler.startTime = GetTime() - scheduler.currentTime
    ResetEventRuntimeFlags(scheduler.currentTime)
    CancelAllPendingCountdownTimers()
    CancelAllPendingBarTimers()
    if T.ClearAllBars then
        T.ClearAllBars()
    end
    wipe(phaseWarned)
    RefreshTestAutoStopAt()
end

-- 清空时间轴
T.ClearTimeline = function()
    CancelAllPendingCountdownTimers()
    CancelAllPendingBarTimers()
    if T.ClearAllBars then
        T.ClearAllBars()
    end
    wipe(timeline)
    wipe(boardTimeline)
    ResetTransportRangeCache()
end

-- 获取时间轴文本（MRT/STN），可用于运行或恢复
T.GetTimelineSourceText = function(opts)
    local options = opts or {}
    local silent = options.silent
    local source = C.DB.dataSource or "STN"
    local text = nil
    local bundle = nil

    if source == "MRT" then
        local MRT = _G.VMRT or _G.VExRT
        if MRT and MRT.Note then
            local raid = (C.DB.useRaidNote and MRT.Note.Text1) or nil
            local selfNote = (C.DB.useSelfNote and MRT.Note.SelfText) or nil
            local semantic = T.SemanticTimeline
            local semanticDB = C.DB and C.DB.semanticTimeline

            if raid and selfNote
                and semantic
                and semanticDB
                and semanticDB.personalOverridesTeam ~= false
                and semantic._FilterTeamTextByPersonal then
                local cleanedRaid, overrideSet, dropped = semantic:_FilterTeamTextByPersonal(raid, selfNote)
                raid = cleanedRaid
                if semantic._LogPersonalOverrideDebug then
                    semantic:_LogPersonalOverrideDebug("MRT", overrideSet, dropped)
                end
            end

            if raid then
                text = (text and (text .. "\n") or "") .. raid
            end
            if selfNote then
                text = (text and (text .. "\n") or "") .. selfNote
            end
        end
        if not text or text == "" then
            if not silent then
                T.msg(L["MRT数据不可用"])
            end
            return nil, source
        end
    else
        local semantic = T.SemanticTimeline
        if semantic and semantic.GetCurrentPlanBundle then
            if options.bossKey or options.encounterID then
                bundle = semantic:GetCurrentPlanBundle({
                    bossKey = options.bossKey,
                    encounterID = options.encounterID,
                    allowActiveFallback = false,
                })
            else
                bundle = semantic:GetCurrentPlanBundle()
            end
            text = bundle and bundle.runtimeText or ""
        end
        if not text or text == "" then
            if not silent and not bundle then
                T.msg("没有找到可用的STN方案")
            end
            return nil, source, bundle
        end
    end

    return text, source, bundle
end

local function BuildTemplateRejectReason(info)
    if not info then
        return L["仅支持结构化模板"] or "仅支持结构化模板"
    end
    if info.errors and #info.errors > 0 then
        local first = info.errors[1]
        local line = tonumber(first and first.line) or 0
        local reason = tostring(first and first.reason or "")
        local content = tostring(first and first.content or "")
        local detail = line > 0 and string.format("第%d行 %s", line, reason) or reason
        if content ~= "" then
            detail = detail .. "：" .. content
        end
        return string.format("%s %d，%s", L["模板解析错误"] or "模板解析错误", #info.errors, detail)
    end
    if not info or info.hasBlocks ~= true then
        return L["仅支持结构化模板"] or "仅支持结构化模板"
    end
    return L["仅支持结构化模板"] or "仅支持结构化模板"
end

local function HasFatalTemplateError(info)
    return T.STNTemplate and T.STNTemplate.HasFatalErrors and T.STNTemplate.HasFatalErrors(info) == true
end

local function BuildRuntimeError(err)
    local message = tostring(err or "unknown")
    if type(debugstack) == "function" then
        return message .. "\n" .. tostring(debugstack(2))
    end
    return message
end

local function RunOptionalRuntimeStep(stepName, fn)
    local ok, err = xpcall(fn, BuildRuntimeError)
    if ok then
        return true
    end
    if T.debug then
        T.debug("[STT_RUNNER_START_ERROR] step=" .. tostring(stepName) .. " err=" .. tostring(err))
    end
    return false
end

local function DebugPartialTemplateWarning(label, templateInfo)
    if not (C and C.DB and C.DB.debugMode and T and T.debug) then
        return
    end
    if not templateInfo or not templateInfo.errors or #templateInfo.errors == 0 then
        return
    end
    local first = templateInfo.errors[1]
    T.debug(string.format(
        "[TimelineRunner] partial_template_warning source=%s errorCount=%d firstLine=%d firstReason=%s",
        tostring(label or ""),
        #(templateInfo.errors or {}),
        tonumber(first and first.line) or 0,
        tostring(first and first.reason or "")
    ))
end

local function ParseTimelineSourceText(text, opts)
    local perf = T.CreatePerfProfile and T.CreatePerfProfile("ParseTimelineSourceText") or nil
    local rawText = tostring(text or "")
    if rawText == "" then
        if perf then perf:Mark("EmptyText") end
        if perf then perf:Finish() end
        return nil, nil
    end
    local plog = T.PerfLog and T.PerfLog:Begin(((C.DB and C.DB.dataSource) == "MRT") and "mrt:parse" or "stn:parse")

    local templateInfo = type(opts) == "table" and opts.templateInfo or nil
    if templateInfo then
        if perf then perf:Mark("ReusePreprocessText") end
    else
        templateInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(rawText, opts) or nil
        if perf then perf:Mark("PreprocessText") end
    end
    if not (T.STNTemplate and T.STNTemplate.IsBodyUsable and T.STNTemplate.IsBodyUsable(templateInfo, "timeline")) then
        if perf then perf:Finish() end
        if plog then plog:Finish({ chars = #rawText, result = "body_unusable" }) end
        return nil, templateInfo
    end

    local parserOpts = {}
    if type(opts) == "table" then
        for key, value in pairs(opts) do
            parserOpts[key] = value
        end
    end
    parserOpts.templateInfo = templateInfo
    local parsed = T.NoteParser and T.NoteParser.ParseNote and T.NoteParser:ParseNote(rawText, parserOpts) or nil
    if perf then perf:Mark("ParseNote") end
    if perf then perf:Finish() end
    if plog then plog:Finish({ chars = #rawText }) end
    return parsed, templateInfo
end

local RESOLVE_SOURCE_TEAM = "team"
local RESOLVE_SOURCE_PERSONAL = "personal"
local RESOLVE_SOURCE_TEAM_PLUS_PERSONAL = "team_plus_personal"

local function NormalizeResolveSource(resolveSource)
    if resolveSource == RESOLVE_SOURCE_TEAM or resolveSource == RESOLVE_SOURCE_PERSONAL then
        return resolveSource
    end
    return RESOLVE_SOURCE_TEAM_PLUS_PERSONAL
end

-- 构建播报片段（统一委托 TimelineSyntax）
local function ExtractSpellIDFromEvent(event)
    if not event then return nil end
    if tonumber(event.spellID) and tonumber(event.spellID) > 0 then
        return tonumber(event.spellID)
    end
    if tonumber(event.primarySpellID) and tonumber(event.primarySpellID) > 0 then
        return tonumber(event.primarySpellID)
    end
    local text = event.rawLine or event.originalText or event.content or ""
    local id = text:match("{spell:(%d+):?%d*}")
    return id and tonumber(id) or nil
end

local function BuildReminderDebugText(text)
    local value = T.TimelineSyntax and T.TimelineSyntax.NormalizeASCIIWhitespace and T.TimelineSyntax.NormalizeASCIIWhitespace(text) or tostring(text or "")
    if #value > 48 then
        return value:sub(1, 48) .. "..."
    end
    return value
end

local function ExtractReminderSeverity(text)
    if type(text) ~= "string" then
        return nil, text
    end
    local normalized = T.TimelineSyntax and T.TimelineSyntax.NormalizeASCIIWhitespace and T.TimelineSyntax.NormalizeASCIIWhitespace(text) or text
    if normalized:sub(1, 2) == "!!" then
        local stripped = normalized:sub(3):match("^%s*(.-)%s*$") or ""
        return "critical", stripped
    end
    return nil, text
end

local function GetBarValues(event)
    return T.InlineModifier and T.InlineModifier.GetBarValues and T.InlineModifier.GetBarValues(event) or nil
end

local function ResolveSpellName(spellID)
    local id = tonumber(spellID)
    if not id or id <= 0 then
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
        local name = type(info) == "table" and info.name or nil
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

local function ResolveBarDisplayText(bar, fallbackText)
    local label = tostring(bar and (bar.labelOverride or bar.label) or "")
    label = label:gsub("^%s+", ""):gsub("%s+$", "")
    if label ~= "" then
        return label
    end

    local spellName = ResolveSpellName(bar and bar.spellID)
    if spellName then
        return spellName
    end

    local fallback = tostring(fallbackText or "")
    fallback = fallback:gsub("^%s+", ""):gsub("%s+$", "")
    return fallback
end

local function BuildBarDisplayCell(segment, ev)
    local bar = GetBarValues(ev)
    bar = type(bar) == "table" and bar[1] or nil
    if type(bar) ~= "table" or not (T.TimelineSyntax and T.TimelineSyntax.BuildCellWho) then
        return nil
    end

    local who, whoType = T.TimelineSyntax.BuildCellWho(segment)
    if (not who or who == "") and ev and ev.isPersonal == true then
        who, whoType = "自己", "player"
    end
    local text = ResolveBarDisplayText(bar, ev and (ev.displayText or ev.content or ""))
    if not who or who == "" or text == "" then
        return nil
    end

    local spellID = tonumber(bar.spellID)
    local spellIcon = bar.iconOverride
    if not spellIcon and spellID and T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        spellIcon = T.TimelineSyntax.ResolveSpellIcon(spellID)
    end

    return {
        who = who,
        whoType = whoType,
        actionText = text,
        spellHiddenActionText = text,
        spellID = spellID,
        spellIcon = spellIcon,
        fullText = text,
    }
end

-- 从 segments 构建 cells（复用 TimelineSyntax 单一权威）和回退 screenText。
local function BuildCellsFromSegments(ev)
    local segments = ev.segments
    if type(segments) ~= "table" or #segments == 0 then
        return nil, nil
    end
    local cells = {}
    for _, seg in ipairs(segments) do
        local cell = T.TimelineSyntax.BuildDisplayCell(seg, {
            personalUntargeted = ev.isPersonal == true,
        })
        if cell then
            cells[#cells + 1] = cell
        else
            local barCell = BuildBarDisplayCell(seg, ev)
            if barCell then
                cells[#cells + 1] = barCell
            end
        end
    end
    if #cells == 0 then
        return nil, nil
    end
    -- 拼接纯文本 screenText 用于 TTS 和回退
    local parts = {}
    for _, c in ipairs(cells) do
        parts[#parts + 1] = (c.who or "") .. " " .. (c.actionText or "")
    end
    return cells, table.concat(parts, "  ")
end

local function GetCountdownValue(event)
    local modifier = type(event) == "table" and event.modifiers and event.modifiers.ct or nil
    local value = modifier and tonumber(modifier.value) or nil
    if value and value >= 1 and value <= 10 and value == math.floor(value) then
        return value
    end
    return nil
end

local function GetScreenReminderLeadValue(event)
    local modifier = type(event) == "table" and event.modifiers and event.modifiers.sr or nil
    local value = modifier and tonumber(modifier.value) or nil
    if value and value >= 0 and value <= 10 then
        return value
    end
    return nil
end

local function HasBarModifier(event)
    local values = GetBarValues(event)
    return type(values) == "table" and #values > 0
end

local function GetInlineSound(event)
    local modifier = type(event) == "table" and event.modifiers and event.modifiers.sound or nil
    if type(modifier) == "table" and type(modifier.path) == "string" and modifier.path ~= "" then
        return modifier
    end
    return nil
end

local function HasVisualBoards(event)
    return type(event) == "table" and type(event.visualBoards) == "table" and #event.visualBoards > 0
end

local function GetSelectedEncounterID()
    local semantic = T.SemanticTimeline
    if semantic and semantic.GetCurrentPlanBundle then
        local bundle = semantic:GetCurrentPlanBundle({ allowActiveFallback = false })
        local bossKey = bundle and bundle.bossKey
        if type(bossKey) == "table" then
            return tonumber(bossKey.encounterID) or 0
        end
    end
    return 0
end

local function ResolveEncounterID(encounterID)
    local normalized = tonumber(encounterID)
    if normalized and normalized > 0 then
        return normalized
    end
    return GetSelectedEncounterID()
end

local function HasPhaseEvents(events)
    for _, event in ipairs(events or {}) do
        if type(event.phase) == "string" and event.phase ~= "" then
            return true
        end
    end
    return false
end

local function WarnSettingsErrors(templateInfo)
    local count = templateInfo and templateInfo.settingsErrors and #templateInfo.settingsErrors or 0
    if count > 0 then
        T.msg(string.format("阶段设置解析错误 %d", count))
    end
end

local function CopyPhaseRules(from, to)
    if type(from) ~= "table" or type(to) ~= "table" then
        return
    end
    for phaseKey, rule in pairs(from) do
        if to[phaseKey] == nil then
            to[phaseKey] = rule
        end
    end
end

-- 将 NoteParser 事件转换为内部 timeline。
-- opts.showAll=true 时跳过受众过滤，从 segments 构建 cells 给实时战术板展示。
local function BuildTimelineEvents(parsed, out, opts)
    local list = out or {}
    wipe(list)
    opts = opts or {}
    local showAll = opts.showAll == true
    local seq = 0 -- 保序序号：用于相同时间/显示时间下保持插入顺序
    local maxTime = 0
    for _, ev in ipairs(parsed or {}) do
        local t = tonumber(ev.time) or 0
        local fallbackSpellID = ExtractSpellIDFromEvent(ev)
        local spellID = fallbackSpellID
        local resolvedText
        local screenText
        local ttsText
        local spellIcon
        local screenMatchedSegments
        local screenSpellFromMatchedSegment = false
        local spellHiddenScreenText
        local cells
        local targetIndicators = ev.targetIndicators
        if showAll then
            cells, screenText = BuildCellsFromSegments(ev)
            if not screenText or screenText == "" then
                screenText = ev.displayText or ev.originalText or ev.content or ""
            end
            resolvedText = screenText
            ttsText = screenText
            spellIcon = T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon and T.TimelineSyntax.ResolveSpellIcon(spellID) or nil
        else
            resolvedText = T.NoteParser and T.NoteParser.GetResolvedEventText and T.NoteParser:GetResolvedEventText(ev) or (ev.displayText or ev.content or "")
            local screenPayload = T.NoteParser and T.NoteParser.GetResolvedEventScreenPayload and T.NoteParser:GetResolvedEventScreenPayload(ev) or nil
            if screenPayload then
                screenText = screenPayload.text or ""
                spellID = tonumber(screenPayload.spellID) or fallbackSpellID
                spellIcon = screenPayload.spellIcon
                screenSpellFromMatchedSegment = screenPayload.spellFromMatchedSegment == true
                screenMatchedSegments = screenPayload.matchedSegments
                if T.TimelineSyntax and T.TimelineSyntax.BuildScreenTextWithoutSpellTokensFromSegments then
                    spellHiddenScreenText = T.TimelineSyntax.BuildScreenTextWithoutSpellTokensFromSegments(screenMatchedSegments, "")
                end
            else
                screenText = T.NoteParser and T.NoteParser.GetResolvedEventScreenText and T.NoteParser:GetResolvedEventScreenText(ev) or resolvedText
                spellID = fallbackSpellID
            end
            ttsText = T.NoteParser and T.NoteParser.GetResolvedEventTTSText and T.NoteParser:GetResolvedEventTTSText(ev) or screenText or resolvedText
            if not spellIcon and spellID and T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
                spellIcon = T.TimelineSyntax.ResolveSpellIcon(spellID)
            end
        end
        local shouldInclude = showAll
        if not shouldInclude then
            shouldInclude = not T.NoteParser or not T.NoteParser.ShouldTriggerEvent or T.NoteParser:ShouldTriggerEvent(ev)
        end
        local inlineSound = GetInlineSound(ev)
        local hasVisualBoards = HasVisualBoards(ev)
        local hasBar = HasBarModifier(ev)
        if ((resolvedText and resolvedText ~= "") or inlineSound or hasVisualBoards or hasBar) and shouldInclude then
            local countdownValue = GetCountdownValue(ev)
            local screenLeadTime = GetScreenReminderLeadValue(ev)
            local screenAdvance = (T.ScreenReminderSchema and T.ScreenReminderSchema.GetMaxLeadTime
                and T.ScreenReminderSchema.GetMaxLeadTime(screenLeadTime)) or 0
            if screenAdvance < 0.5 then screenAdvance = 0.5 end
            local severity
            severity, screenText = ExtractReminderSeverity(screenText or resolvedText)
            local hiddenSeverity
            hiddenSeverity, spellHiddenScreenText = ExtractReminderSeverity(spellHiddenScreenText)
            severity = severity or hiddenSeverity
            local textSeverity
            textSeverity, resolvedText = ExtractReminderSeverity(resolvedText)
            severity = severity or textSeverity
            local ttsSeverity
            ttsSeverity, ttsText = ExtractReminderSeverity(ttsText or resolvedText)
            severity = severity or ttsSeverity
            if screenText == "" then
                screenText = resolvedText
            end
            -- 注意：不要给 ttsText == "" 做 fallback。`~~xxx~~` 静默标记
            -- 经 StripSilentMarkers 后 ttsText 正确为空，代表"显示但不播报"；
            -- 若 fallback 到 resolvedText（走 UnwrapSilentMarkers 保留"xxx"），
            -- 会让静默标记失效直接把 xxx 念出来。isSilent 下面就靠它判定。
            seq = seq + 1
            list[#list + 1] = {
                time = t,
                phase = ev.phase,
                showTime = math.max(0, t - screenAdvance),
                text = resolvedText,
                screenText = screenText,
                spellHiddenScreenText = spellHiddenScreenText,
                ttsText = ttsText,
                seq = seq,
                reminderCreated = inlineSound and (not screenText or screenText == "") and true or false,
                triggered = false,
                spellID = spellID,
                spellIcon = spellIcon,
                isSilent = (ttsText == nil or ttsText == ""),
                originalText = ev.originalText,
                content = ev.content,
                screenMatchedSegments = screenMatchedSegments,
                modifiers = ev.modifiers,
                ttsAdvanceOverride = ev.ttsAdvanceOverride,
                visualBoards = ev.visualBoards,
                inlineSound = inlineSound,
                countdownValue = countdownValue,
                screenLeadTime = screenLeadTime,
                countdownScheduled = false,
                barScheduled = false,
                targetIndicators = targetIndicators,
                segments = ev.segments,
                cells = cells,
                severity = severity,
                screenSpellFromMatchedSegment = screenSpellFromMatchedSegment,
            }
            maxTime = math.max(maxTime, t)
        end
    end
    table.sort(list, function(a, b)
        if a.showTime ~= b.showTime then return a.showTime < b.showTime end
        if a.time ~= b.time then return a.time < b.time end
        return (a.seq or 0) < (b.seq or 0)
    end)
    return list, maxTime
end

T.BuildTimelineEvents = BuildTimelineEvents

local function TrackPreviewMaxTime(list)
    local maxTime = 0
    for _, event in ipairs(list) do
        local eventTime = tonumber(event.previewTime) or tonumber(event.time) or 0
        maxTime = math.max(maxTime, eventTime + GetEventDurationValue(event))
    end
    return maxTime
end

local function ApplyPreviewTimelineTimes(encounterID)
    previewTransportMaxTime = 0

    local data = T.HorizontalTimelineData
    if not (data and data.BuildPhaseDisplayOffsets and data.ParsePhaseKey) then
        for _, list in ipairs({ timeline, boardTimeline }) do
            for _, event in ipairs(list) do
                event.previewTime = tonumber(event.time) or 0
            end
        end
        timelinePreviewMaxTime = TrackPreviewMaxTime(timeline)
        boardPreviewMaxTime = TrackPreviewMaxTime(boardTimeline)
        previewTransportMaxTime = math.max(
            timelinePreviewMaxTime,
            boardPreviewMaxTime
        )
        return
    end

    local rows = {}
    local source = #boardTimeline > 0 and boardTimeline or timeline
    for index, event in ipairs(source) do
        rows[#rows + 1] = {
            timeSec = tonumber(event.time) or 0,
            phase = event.phase,
            modifiers = event.modifiers,
            key = { encounterID = tonumber(encounterID) or 0 },
            sortIndex = tonumber(event.seq) or index,
            timePayload = event.originalText or event.content or "",
        }
    end

    local phaseOffsets, phaseStats = data.BuildPhaseDisplayOffsets(rows)
    phaseOffsets = type(phaseOffsets) == "table" and phaseOffsets or {}

    for _, list in ipairs({ timeline, boardTimeline }) do
        for _, event in ipairs(list) do
            local parsedPhase = data.ParsePhaseKey(event.phase)
            local phaseOffset = parsedPhase and (tonumber(phaseOffsets[parsedPhase.key]) or 0) or 0
            event.previewTime = (tonumber(event.time) or 0) + phaseOffset
        end
    end

    timelinePreviewMaxTime = TrackPreviewMaxTime(timeline)
    boardPreviewMaxTime = TrackPreviewMaxTime(boardTimeline)
    previewTransportMaxTime = math.max(
        tonumber(phaseStats and phaseStats.maxDisplayTime) or 0,
        timelinePreviewMaxTime,
        boardPreviewMaxTime
    )
end

-- 运行态同时保留过滤版与展示版时间轴，支持战术板在运行中实时切换显示范围。
local function RebuildRuntimeTimelines(parsed, encounterID)
    timelineMaxTime = select(2, BuildTimelineEvents(parsed, timeline))
    BuildTimelineEvents(parsed, boardTimeline, { showAll = true })
    ApplyPreviewTimelineTimes(encounterID)
    RefreshTransportMaxTimeCache()
end

local function CleanupFailedRuntimeStart()
    scheduler:Hide()
    scheduler.paused = false
    scheduler.currentTime = 0
    scheduler.isStaticPreview = false
    scheduler.index = 1
    scheduler.elapsed = 0
    scheduler.encounterID = 0
    scheduler.testAutoStopAt = 0
    CancelAllPendingCountdownTimers()
    CancelAllPendingBarTimers()
    wipe(timeline)
    wipe(boardTimeline)
    ResetTransportRangeCache()
    if T.ClearAllBars then
        T.ClearAllBars()
    end
    if T.ClearTTSQueue then
        T.ClearTTSQueue()
    end
    if T.RealtimeBoard and T.RealtimeBoard.Stop then
        T.RealtimeBoard:Stop("start_error")
    end
    if T.TacticalNotice and T.TacticalNotice.ClearAll then
        T.TacticalNotice:ClearAll({ silent = true })
    end
    if T.VisualBoardOverlay and T.VisualBoardOverlay.ClearAll then
        T.VisualBoardOverlay:ClearAll()
    end
    if T.BlizzardTimeline and T.BlizzardTimeline.ClearInjected then
        T.BlizzardTimeline:ClearInjected()
    end
    if T.PhaseDetector and T.PhaseDetector.Stop then
        T.PhaseDetector:Stop()
    end
    wipe(phaseWarned)
    NotifySubscribers()
end

local function TryRebuildRuntimeTimelines(parsed, encounterID)
    local ok, err = xpcall(function()
        RebuildRuntimeTimelines(parsed, encounterID)
    end, BuildRuntimeError)
    if ok then
        return true
    end
    if T.debug then
        T.debug("[STT_RUNNER_START_ERROR] step=RebuildRuntimeTimelines err=" .. tostring(err))
    end
    T.msg("战术方案格式错误，已停止本次播报启动")
    CleanupFailedRuntimeStart()
    return false
end

-- 运行时快照：向只读消费者暴露当前时间轴引用和开战时间，避免复制第二份数据。
function Runner:GetRuntimeState()
    local playing = scheduler:IsShown() and not scheduler.paused
    return {
        timeline = timeline,
        boardTimeline = boardTimeline,
        startTime = scheduler.startTime,
        isTest = scheduler.isTest and true or false,
        isRunning = scheduler:IsShown() and true or false,
        isActive = playing or scheduler.paused == true,
        playing = playing,
        currentTime = GetCurrentRunnerTime(),
        nextIndex = scheduler.index,
        loopEnabled = transportLoop.enabled == true and IsLoopRangeValid(),
        loopStart = tonumber(transportLoop.startTime) or 0,
        loopEnd = tonumber(transportLoop.endTime) or 0,
    }
end

function Runner:GetState()
    return BuildRunnerState()
end

function Runner:GetTransportState()
    local state = BuildRunnerState()
    return {
        playing = state.playing,
        playheadTime = state.currentTime,
        currentTime = state.currentTime,
        maxTime = state.totalTime,
        totalTime = state.totalTime,
        isTest = state.isTest,
        loopEnabled = state.loopEnabled,
        loopStart = state.loopStart,
        loopEnd = state.loopEnd,
    }
end

function Runner:SetLoopRange(startTime, endTime)
    local loopStart = math.max(0, tonumber(startTime) or 0)
    local loopEnd = math.max(0, tonumber(endTime) or 0)
    local maxTime = tonumber(RefreshTransportMaxTimeCache()) or 0
    if maxTime > 0 then
        loopStart = math.min(loopStart, maxTime)
        loopEnd = math.min(loopEnd, maxTime)
    end
    if loopEnd <= loopStart then
        return false, "invalid_range"
    end
    transportLoop.startTime = loopStart
    transportLoop.endTime = loopEnd
    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format("[STT_TRANSPORT_LOOP_SET] enabled=%s start=%.2f end=%.2f", tostring(transportLoop.enabled == true), loopStart, loopEnd))
    end
    NotifySubscribers()
    return true
end

function Runner:SetLoopEnabled(enabled)
    local nextEnabled = enabled == true
    if nextEnabled and not IsLoopRangeValid() then
        return false, "missing_range"
    end
    transportLoop.enabled = nextEnabled
    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format("[STT_TRANSPORT_LOOP_SET] enabled=%s start=%.2f end=%.2f", tostring(transportLoop.enabled == true), tonumber(transportLoop.startTime) or 0, tonumber(transportLoop.endTime) or 0))
    end
    NotifySubscribers()
    return true
end

function Runner:ClearLoopRange()
    transportLoop.enabled = false
    transportLoop.startTime = 0
    transportLoop.endTime = 0
    if C.DB and C.DB.debugMode and T.debug then
        T.debug("[STT_TRANSPORT_LOOP_SET] enabled=false start=0.00 end=0.00")
    end
    NotifySubscribers()
    return true
end

function Runner:Subscribe(callback)
    if type(callback) ~= "function" then
        return function() end
    end
    nextSubscriberID = nextSubscriberID + 1
    local id = nextSubscriberID
    subscribers[id] = {
        callback = callback,
        failures = 0,
    }
    callback(BuildRunnerState())
    return function()
        subscribers[id] = nil
    end
end

function Runner:Pause()
    scheduler.currentTime = GetCurrentRunnerTime()
    scheduler.paused = true
    scheduler:Hide()
    CancelAllPendingCountdownTimers()
    CancelAllPendingBarTimers()
    if T.ClearAllBars then
        T.ClearAllBars()
    end
    if T.ClearTTSQueue then
        T.ClearTTSQueue()
    end
    NotifySubscribers()
    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format("[STT_RUNNER_TRANSPORT] action=pause time=%.2f", scheduler.currentTime or 0))
    end
end

function Runner:Seek(targetTime, opts)
    opts = type(opts) == "table" and opts or {}
    local wasPlaying = scheduler:IsShown() and not scheduler.paused
    local totalTime = GetTransportMaxTime()
    local maxSeekTime = totalTime > 0 and totalTime or math.max(0, tonumber(targetTime) or 0)
    local nextTime = math.max(0, math.min(tonumber(targetTime) or 0, maxSeekTime))

    ApplyTransportPosition(nextTime)

    if wasPlaying and opts.preserveState ~= false then
        scheduler.paused = false
        scheduler:Show()
    else
        scheduler.paused = true
        scheduler:Hide()
    end

    NotifySubscribers()
    if opts.silent ~= true and C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format("[STT_RUNNER_TRANSPORT] action=seek time=%.2f playing=%s", nextTime, tostring(wasPlaying and opts.preserveState ~= false)))
    end
end

function Runner:Play(fromTime)
    if #timeline == 0 then
        local targetTime = tonumber(fromTime) or tonumber(scheduler.currentTime) or 0
        local ok = self:StartTest()
        if not ok then
            return false
        end
        if targetTime > 0 then
            self:Seek(targetTime, { silent = true, preserveState = false })
        end
    elseif fromTime ~= nil then
        self:Seek(fromTime, { silent = true, preserveState = false })
    end

    scheduler.currentTime = GetCurrentRunnerTime()
    scheduler.startTime = GetTime() - (tonumber(scheduler.currentTime) or 0)
    scheduler.paused = false
    RefreshTestAutoStopAt()
    scheduler:Show()
    NotifySubscribers()
    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format("[STT_RUNNER_TRANSPORT] action=play time=%.2f", scheduler.currentTime or 0))
    end
    return true
end

local function ResolveEventAbsoluteTime(event)
    local eventTime = tonumber(event and event.time) or 0
    if type(event) ~= "table" or not event.phase then
        return scheduler.startTime + eventTime
    end
    if scheduler.isTest then
        return scheduler.startTime + (tonumber(event.previewTime) or eventTime)
    end
    local phaseStart = T.PhaseDetector and T.PhaseDetector.GetPhaseStartTime and T.PhaseDetector:GetPhaseStartTime(event.phase) or nil
    if not phaseStart then
        return nil
    end
    return phaseStart + eventTime
end

local function ScheduleCountdownEvent(event, absoluteEventTime)
    local countdownValue = GetCountdownValue(event)
    if not countdownValue or event.countdownScheduled or C.DB.CountdownEnabled == false then
        return
    end
    event.countdownScheduled = true

    local now = GetTime()
    local scheduled = 0
    for number = countdownValue, 1, -1 do
        local fireDelay = absoluteEventTime - number - 0.1 - now
        if fireDelay > 0 then
            local current = number
            local timer = C_Timer.NewTimer(fireDelay, function()
                if T.PlayCountdownMp3 then
                    T.PlayCountdownMp3(current)
                end
            end)
            pendingCountdownTimers[#pendingCountdownTimers + 1] = timer
            scheduled = scheduled + 1
        end
    end

    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format(
            "[CountdownSchedule] time=%.1f ct=%d timers=%d text=%s",
            tonumber(event.time) or 0,
            countdownValue,
            scheduled,
            BuildReminderDebugText(event.ttsText or event.text or "")
        ))
    end
end

local function ScheduleBarEvent(event, absoluteEventTime)
    local bars = GetBarValues(event)
    if not bars or event.barScheduled or (C.DB.Bar and C.DB.Bar.Enabled == false) then
        return
    end
    event.barScheduled = true

    local now = GetTime()
    local scheduled = 0
    for index, bar in ipairs(bars) do
        local duration = tonumber(bar.duration)
        if duration and duration > 0 then
            local startTime = absoluteEventTime
            local finishTime = startTime + duration
            if now < finishTime then
                local function fire()
                    if T.ShowBar then
                        T.ShowBar({
                            duration = duration,
                            tickInterval = bar.tickInterval,
                            spellID = bar.spellID,
                            iconOverride = bar.iconOverride,
                            labelOverride = bar.labelOverride,
                            fallbackLabel = event.screenText or event.text or "",
                            eventID = event.id or event.seq or index,
                            phase = event.phase,
                            startTime = startTime,
                        })
                    end
                end
                local fireDelay = startTime - now
                if fireDelay > 0 then
                    local timer = C_Timer.NewTimer(fireDelay, fire)
                    pendingBarTimers[#pendingBarTimers + 1] = timer
                    scheduled = scheduled + 1
                else
                    fire()
                    scheduled = scheduled + 1
                end
            end
        end
    end

    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format(
            "[BarSchedule] time=%.1f bars=%d scheduled=%d text=%s",
            tonumber(event.time) or 0,
            #bars,
            scheduled,
            BuildReminderDebugText(event.ttsText or event.text or "")
        ))
    end
end

local function BuildInjectedTimeline()
    local injected = {}

    for _, event in ipairs(timeline) do
        local absoluteEventTime = ResolveEventAbsoluteTime(event)
        if absoluteEventTime then
            local relativeEventTime = math.max(0, absoluteEventTime - scheduler.startTime)
            local copy = {}
            for key, value in pairs(event) do
                copy[key] = value
            end
            local advance = (T.ScreenReminderSchema and T.ScreenReminderSchema.GetMaxLeadTime
                and T.ScreenReminderSchema.GetMaxLeadTime(event.screenLeadTime)) or 0
            if advance < 0.5 then advance = 0.5 end
            copy.time = relativeEventTime
            copy.showTime = math.max(0, relativeEventTime - advance)
            injected[#injected + 1] = copy
        end
    end

    table.sort(injected, function(a, b)
        if a.showTime ~= b.showTime then return a.showTime < b.showTime end
        if a.time ~= b.time then return a.time < b.time end
        return (a.seq or 0) < (b.seq or 0)
    end)

    return injected
end

local function RefreshInjectedTimeline(reason)
    if not (T.BlizzardTimeline and T.BlizzardTimeline.InjectEvents) then
        return
    end

    local injected = BuildInjectedTimeline()
    if #injected == 0 then
        return
    end

    T.BlizzardTimeline:InjectEvents(injected, {
        reason = reason or "timeline_refresh",
        isTest = scheduler.isTest and true or false,
    })
end

local function StartPhaseDetector(encounterID, templateInfo, parsed)
    if not (T.PhaseDetector and T.PhaseDetector.Start) then
        return
    end

    local phaseRules = templateInfo and templateInfo.phaseRules or nil
    if type(phaseRules) == "table" and next(phaseRules) == nil then
        phaseRules = nil
    end

    local resolvedEncounterID = ResolveEncounterID(encounterID)
    local hasPhaseEvents = HasPhaseEvents(parsed)

    if not hasPhaseEvents and not phaseRules then
        T.PhaseDetector:Stop()
        return
    end

    T.PhaseDetector:Start(resolvedEncounterID, phaseRules, function(newPhase, source)
        if C.DB and C.DB.debugMode then
            T.debug(string.format("[TimelinePhase] phase=%s source=%s", tostring(newPhase), tostring(source)))
        end
        RunOptionalRuntimeStep("RefreshInjectedTimeline", function()
            RefreshInjectedTimeline("phase_" .. tostring(source or "changed"))
        end)
    end)
end

function Runner:StartFromText(text, isTest, encounterID, opts)
    EnsureSchedulerFrame()
    if not T.NoteParser or not T.NoteParser.ParseNote then
        T.msg("NoteParser 未加载")
        return false
    end
    local isStaticPreview = type(opts) == "table" and opts.staticPreview == true

    local templateInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text or "") or nil
    if not (T.STNTemplate and T.STNTemplate.IsBodyUsable and T.STNTemplate.IsBodyUsable(templateInfo, "timeline")) then
        if not templateInfo or templateInfo.hasBlocks ~= true then
            T.msg(L["仅支持结构化模板"] or "仅支持结构化模板")
        elseif templateInfo.errors and #templateInfo.errors > 0 then
            T.msg(string.format("%s %d", L["模板解析错误"] or "模板解析错误", #templateInfo.errors))
        end
        return false
    end

    local parsed = T.NoteParser:ParseNote(text or "")
    if C.DB and C.DB.debugMode then
        T.debug("Parser: 事件数量=" .. tostring(parsed and #parsed or 0))
    end
    DebugPartialTemplateWarning("start_from_text", templateInfo)
    WarnSettingsErrors(templateInfo)
    if not parsed or #parsed == 0 then
        T.msg(L["没有时间轴数据"])
        return false
    end

    local resolvedEncounterID = ResolveEncounterID(encounterID)
    if not TryRebuildRuntimeTimelines(parsed, resolvedEncounterID) then
        return false
    end
    CancelAllPendingCountdownTimers()
    wipe(phaseWarned)

    scheduler.index = 1
    scheduler.elapsed = 0
    scheduler.startTime = GetTime()
    scheduler.isTest = (not isStaticPreview) and isTest and true or false
    scheduler.encounterID = resolvedEncounterID
    scheduler.bossKeyText = tostring(type(opts) == "table" and opts.bossKeyText or "")
    scheduler.testAutoStopAt = 0
    scheduler.currentTime = 0
    scheduler.paused = isStaticPreview and true or false
    RefreshTransportMaxTimeCache()

    if not isStaticPreview then
        StartPhaseDetector(scheduler.encounterID, templateInfo, parsed)
        RefreshTestAutoStopAt()
    end
    DebugTransportRange(isStaticPreview and "start_static_preview_text" or "start_from_text")

    if T.RealtimeBoard then
        local boardSource = (C.DB.realtimeBoard and C.DB.realtimeBoard.showAllEvents and #boardTimeline > 0) and boardTimeline or timeline
        RunOptionalRuntimeStep("RealtimeBoard_Start", function()
            T.RealtimeBoard:Start(boardSource, scheduler.startTime, scheduler.isTest, { staticPreview = isStaticPreview })
        end)
    end
    scheduler.isStaticPreview = isStaticPreview
    if isStaticPreview then
        scheduler:Hide()
    else
        scheduler:Show()
    end
    NotifySubscribers()
    if not isStaticPreview then
        RunOptionalRuntimeStep("RefreshInjectedTimeline", function()
            RefreshInjectedTimeline(isTest and "test" or "encounter_start")
        end)
    end
    return true
end

function Runner:StartFromResolvedTexts(bundle, isTest, encounterID, opts)
    EnsureSchedulerFrame()
    local perf = T.CreatePerfProfile and T.CreatePerfProfile("StartFromResolvedTexts") or nil
    if not T.NoteParser or not T.NoteParser.ParseNote then
        T.msg("NoteParser 未加载")
        if perf then perf:Finish() end
        return false
    end
    if type(bundle) ~= "table" then
        if perf then perf:Finish() end
        return false
    end
    local isStaticPreview = type(opts) == "table" and opts.staticPreview == true

    local resolveSource = NormalizeResolveSource(bundle.resolveSource)
    local teamText = bundle.runtimeTeamText or bundle.teamText or ""
    local personalText = bundle.personalText or ""
    local allParsed = {}
    local totalEvents = 0
    local mergedTemplateInfo = {
        phaseRules = {},
        settingsErrors = {},
    }
    local sourceStats = {
        team = { attempted = false, accepted = false, events = 0, reusedTemplate = false, textLen = #(teamText or "") },
        personal = { attempted = false, accepted = false, events = 0, reusedTemplate = false, textLen = #(personalText or "") },
    }
    local rejectMessages = {}
    local fatalRejectMessage = nil

    local function AppendParsed(parsed, isPersonal, sourceKey)
        local added = 0
        for _, event in ipairs(parsed or {}) do
            if isPersonal then
                event.isPersonal = true
            end
            allParsed[#allParsed + 1] = event
            added = added + 1
        end
        if sourceKey and sourceStats[sourceKey] then
            sourceStats[sourceKey].events = sourceStats[sourceKey].events + added
        end
        totalEvents = #allParsed
    end

    local function ParseOne(sourceKey, label, text, opts, templateInfo)
        if sourceStats[sourceKey] then
            sourceStats[sourceKey].attempted = true
            sourceStats[sourceKey].reusedTemplate = type(templateInfo) == "table"
        end
        if tostring(text or "") == "" then
            return false
        end
        local parseOpts = {}
        if type(opts) == "table" then
            for key, value in pairs(opts) do
                parseOpts[key] = value
            end
        end
        if templateInfo then
            parseOpts.templateInfo = templateInfo
        end
        local parsed, resolvedTemplateInfo = ParseTimelineSourceText(text, parseOpts)
        if not parsed then
            local message = string.format("%s%s", label, BuildTemplateRejectReason(resolvedTemplateInfo))
            rejectMessages[#rejectMessages + 1] = message
            if HasFatalTemplateError(resolvedTemplateInfo) then
                fatalRejectMessage = fatalRejectMessage or message
            end
            return false
        end
        DebugPartialTemplateWarning(label, resolvedTemplateInfo)
        if resolvedTemplateInfo then
            CopyPhaseRules(resolvedTemplateInfo.phaseRules, mergedTemplateInfo.phaseRules)
            for _, item in ipairs(resolvedTemplateInfo.settingsErrors or {}) do
                mergedTemplateInfo.settingsErrors[#mergedTemplateInfo.settingsErrors + 1] = item
            end
        end
        if sourceStats[sourceKey] then
            sourceStats[sourceKey].accepted = true
        end
        AppendParsed(parsed, opts and opts.isPersonal, sourceKey)
        return true
    end

    local hasTeam = false
    local hasPersonal = false
    if resolveSource == RESOLVE_SOURCE_TEAM then
        hasTeam = ParseOne("team", (L["团队方案"] or "团队方案") .. "：", teamText, nil, bundle.teamInfo)
    elseif resolveSource == RESOLVE_SOURCE_PERSONAL then
        hasPersonal = ParseOne("personal", (L["个人方案"] or "个人方案") .. "：", personalText, { relaxed = true, isPersonal = true }, bundle.personalInfo)
    else
        hasTeam = ParseOne("team", (L["团队方案"] or "团队方案") .. "：", teamText, nil, bundle.teamInfo)
        if perf then perf:Mark("ParseOne_team") end
        hasPersonal = ParseOne("personal", (L["个人方案"] or "个人方案") .. "：", personalText, { relaxed = true, isPersonal = true }, bundle.personalInfo)
    end
    if perf then perf:Mark("ParseOne_all") end

    if fatalRejectMessage then
        T.msg("战术方案格式错误，已停止本次播报启动：" .. tostring(fatalRejectMessage))
        if T.debug then
            T.debug("[STT_RUNNER_START_ERROR] step=ParseTimelineSourceText err=" .. tostring(fatalRejectMessage))
        end
        CleanupFailedRuntimeStart()
        if perf then perf:Finish() end
        return false
    end

    if C.DB and C.DB.debugMode then
        T.debug(string.format(
            "[ResolvedTimelineStart] resolve=%s team(attempted=%s accepted=%s reused=%s len=%d events=%d) personal(attempted=%s accepted=%s reused=%s len=%d events=%d) total=%d",
            tostring(resolveSource),
            tostring(sourceStats.team.attempted),
            tostring(sourceStats.team.accepted),
            tostring(sourceStats.team.reusedTemplate),
            tonumber(sourceStats.team.textLen) or 0,
            tonumber(sourceStats.team.events) or 0,
            tostring(sourceStats.personal.attempted),
            tostring(sourceStats.personal.accepted),
            tostring(sourceStats.personal.reusedTemplate),
            tonumber(sourceStats.personal.textLen) or 0,
            tonumber(sourceStats.personal.events) or 0,
            tonumber(totalEvents) or 0
        ))
    end

    if not hasTeam and not hasPersonal then
        if rejectMessages[1] then
            T.msg(rejectMessages[1])
        end
        CleanupFailedRuntimeStart()
        if perf then perf:Finish() end
        return false
    end
    if totalEvents == 0 then
        if rejectMessages[1] then
            T.msg(rejectMessages[1])
        end
        T.msg(L["没有时间轴数据"])
        CleanupFailedRuntimeStart()
        if perf then perf:Finish() end
        return false
    end

    local resolvedEncounterID = ResolveEncounterID(encounterID)
    if not TryRebuildRuntimeTimelines(allParsed, resolvedEncounterID) then
        if perf then perf:Finish() end
        return false
    end
    CancelAllPendingCountdownTimers()
    CancelAllPendingBarTimers()
    if T.ClearAllBars then
        T.ClearAllBars()
    end
    if perf then perf:Mark("RebuildRuntimeTimelines") end
    wipe(phaseWarned)

    scheduler.index = 1
    scheduler.elapsed = 0
    scheduler.startTime = GetTime()
    scheduler.isTest = (not isStaticPreview) and isTest and true or false
    scheduler.encounterID = resolvedEncounterID
    scheduler.bossKeyText = tostring(bundle.bossKeyText or "")
    scheduler.testAutoStopAt = 0
    scheduler.currentTime = 0
    scheduler.paused = isStaticPreview and true or false
    RefreshTransportMaxTimeCache()

    WarnSettingsErrors(mergedTemplateInfo)
    if not isStaticPreview then
        StartPhaseDetector(scheduler.encounterID, mergedTemplateInfo, allParsed)
        if perf then perf:Mark("StartPhaseDetector") end
        RefreshTestAutoStopAt()
    end
    DebugTransportRange(isStaticPreview and "start_static_preview_resolved" or "start_from_resolved")

    if T.RealtimeBoard then
        local boardSource = (C.DB.realtimeBoard and C.DB.realtimeBoard.showAllEvents and #boardTimeline > 0) and boardTimeline or timeline
        RunOptionalRuntimeStep("RealtimeBoard_Start", function()
            T.RealtimeBoard:Start(boardSource, scheduler.startTime, scheduler.isTest, { staticPreview = isStaticPreview })
        end)
    end
    if perf then perf:Mark("RealtimeBoard_Start") end
    scheduler.isStaticPreview = isStaticPreview
    if isStaticPreview then
        scheduler:Hide()
    else
        scheduler:Show()
    end
    NotifySubscribers()
    if not isStaticPreview then
        RunOptionalRuntimeStep("RefreshInjectedTimeline", function()
            RefreshInjectedTimeline(isTest and "test" or "encounter_start")
        end)
        if perf then perf:Mark("RefreshInjectedTimeline") end
    end
    if perf then perf:Finish() end
    return true
end

-- 启动当前 STN 方案
function Runner:StartFromCurrent(isTest, encounterID, opts)
    local perf = T.CreatePerfProfile and T.CreatePerfProfile("StartFromCurrent") or nil
    local options = type(opts) == "table" and opts or {}
    local text, source, bundle = T.GetTimelineSourceText({
        encounterID = encounterID,
        silent = options.silent,
    })
    if perf then perf:Mark("GetTimelineSourceText") end
    if C.DB and C.DB.debugMode then
        local sem = T.SemanticTimeline
        local currentKey = bundle and bundle.bossKeyText
        if not currentKey or currentKey == "" then
            currentKey = T.Note and T.Note.GetCurrentBossKey and T.Note:GetCurrentBossKey() or "?"
        end
        T.debug(string.format(
            "Runner:StartFromCurrent bossKey=%s source=%s hasText=%s encounterID=%s isTest=%s",
            tostring(currentKey),
            tostring(source),
            tostring(text and text ~= "" or false),
            tostring(encounterID),
            tostring(isTest)
        ))
    end
    if source == "STN" and bundle then
        if bundle.bodyKind == "trigger" then
            if T.TriggerRunner and T.TriggerRunner.StartFromCurrent then
                if perf then perf:Finish() end
                return T.TriggerRunner:StartFromCurrent(isTest, {
                    encounterID = encounterID,
                    bossKey = bundle.bossKey,
                })
            end
            if perf then perf:Finish() end
            return false
        end
        local result = self:StartFromResolvedTexts(bundle, isTest, encounterID)
        if perf then perf:Mark("StartFromResolvedTexts") end
        if perf then perf:Finish() end
        return result
    end
    if not text or text == "" then
        if encounterID then
            CleanupFailedRuntimeStart()
        end
        if perf then perf:Finish() end
        return false
    end
    local result = self:StartFromText(text, isTest, encounterID)
    if perf then perf:Mark("StartFromText") end
    if perf then perf:Finish() end
    return result
end

function Runner:RequestRuntimeReloadFromCurrent(cause, context)
    if not HasRuntimeTimeline() then
        return
    end

    local wasPlaying = scheduler:IsShown() and not scheduler.paused
    local wasPaused = scheduler.paused == true
    local currentTime = GetCurrentRunnerTime()
    local wasTest = scheduler.isTest == true
    local encounterID = scheduler.encounterID
    local reloadCause = type(cause) == "string" and cause or "unknown"
    local reloadContext = type(context) == "table" and context or {}

    if reloadContext.stopBefore == true then
        Runner:Stop()
    end

    if not wasPlaying and not wasPaused then
        if C.DB and C.DB.debugMode and T.debug then
            T.debug(string.format(
                "[STT_RUNTIME_RELOAD] cause=%s result=skipped_idle time=%.2f",
                tostring(reloadCause),
                currentTime or 0
            ))
        end
        return
    end

    runtimeReloadToken = runtimeReloadToken + 1
    local token = runtimeReloadToken

    C_Timer.After(0, function()
        if token ~= runtimeReloadToken then
            return
        end

        local ok = Runner:StartFromCurrent(wasTest, encounterID, { silent = true })
        if not ok then
            if C.DB and C.DB.debugMode and T.debug then
                T.debug(string.format(
                    "[STT_RUNTIME_RELOAD] cause=%s result=failed time=%.2f wasPlaying=%s wasPaused=%s isTest=%s profileID=%s previousProfileID=%s",
                    tostring(reloadCause),
                    currentTime,
                    tostring(wasPlaying),
                    tostring(wasPaused),
                    tostring(wasTest),
                    tostring(reloadContext.profileID),
                    tostring(reloadContext.previousProfileID)
                ))
            end
            return
        end

        local reloadedTimeline = HasRuntimeTimeline()
        if reloadedTimeline then
            Runner:Seek(currentTime, { preserveState = false })
            if wasPlaying then
                Runner:Play()
            end
        elseif not wasPlaying and T.TriggerRunner and T.TriggerRunner.Stop then
            T.TriggerRunner:Stop()
        end

        if C.DB and C.DB.debugMode and T.debug then
            T.debug(string.format(
                "[STT_RUNTIME_RELOAD] cause=%s result=%s time=%.2f wasPlaying=%s wasPaused=%s isTest=%s profileID=%s previousProfileID=%s",
                tostring(reloadCause),
                reloadedTimeline and "reloaded" or "delegated",
                currentTime,
                tostring(wasPlaying),
                tostring(wasPaused),
                tostring(wasTest),
                tostring(reloadContext.profileID),
                tostring(reloadContext.previousProfileID)
            ))
        end
    end)
end

local function ReloadRuntimeAfterProfileChanged(profileID, previousProfileID)
    Runner:RequestRuntimeReloadFromCurrent("profile_changed", {
        profileID = profileID,
        previousProfileID = previousProfileID,
        stopBefore = true,
    })
end

local function MaybeStartStaticPreview(reason)
    if InCombatLockdown() then
        return
    end
    if not (C.DB and C.DB.realtimeBoard and C.DB.realtimeBoard.persistentOutOfCombat) then
        return
    end
    Runner:StartStaticPreview()
end

if T.events then
    T.events:Register("STT_PROFILE_CHANGED", Runner, function(_, profileID, previousProfileID)
        if Runner:IsStaticPreview() then
            Runner:Stop()
            C_Timer.After(0, function()
                MaybeStartStaticPreview("profile_changed")
            end)
            return
        end
        ReloadRuntimeAfterProfileChanged(profileID, previousProfileID)
    end)
    T.events:Register("STT_BOSS_SELECTION_CHANGED", Runner, function()
        if Runner:IsStaticPreview() or (not scheduler:IsShown() and not scheduler.paused) then
            if Runner:IsStaticPreview() then
                Runner:Stop()
            end
            C_Timer.After(0, function()
                MaybeStartStaticPreview("boss_selection_changed")
            end)
        end
    end)
end

-- 手动测试入口（供 /st test 与 GUI 调用）
function Runner:StartTest()
    local text, source, bundle = T.GetTimelineSourceText()
    if source == "STN" and bundle then
        if bundle.bodyKind == "trigger" then
            if T.TriggerRunner and T.TriggerRunner.StartTest then
                return T.TriggerRunner:StartTest()
            end
            return false
        end
        return self:StartFromResolvedTexts(bundle, true, ResolveEncounterID(nil))
    end
    if not text or text == "" then
        return false
    end
    local templateInfo = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text) or nil
    if templateInfo and templateInfo.bodyKind == "trigger" then
        if T.TriggerRunner and T.TriggerRunner.StartFromText then
            return T.TriggerRunner:StartTest()
        end
        return false
    end
    return self:StartFromText(text, true, ResolveEncounterID(nil))
end

-- 战斗外常驻：解析当前选中 boss 的方案，把完整时间轴静态推送给战术板，但不启动调度器。
function Runner:StartStaticPreview(encounterID)
    if InCombatLockdown() then
        return false
    end
    local text, source, bundle = T.GetTimelineSourceText({
        encounterID = encounterID,
        silent = true,
    })
    if source == "STN" and bundle then
        if bundle.bodyKind == "trigger" then
            return false
        end
        return self:StartFromResolvedTexts(bundle, false, ResolveEncounterID(encounterID), { staticPreview = true })
    end
    if not text or text == "" then
        return false
    end
    return self:StartFromText(text, false, ResolveEncounterID(encounterID), { staticPreview = true })
end

function Runner:IsStaticPreview()
    return scheduler.isStaticPreview == true
end

function Runner:StopStaticPreview()
    if scheduler.isStaticPreview ~= true then
        return false
    end
    self:Stop()
    return true
end

function Runner:Stop()
    runtimeReloadToken = runtimeReloadToken + 1
    scheduler:Hide()
    scheduler.paused = false
    scheduler.currentTime = 0
    scheduler.isStaticPreview = false
    CancelAllPendingCountdownTimers()
    CancelAllPendingBarTimers()
    T.ClearTTSQueue()
    T.ClearTimeline()
    wipe(phaseWarned)
    if T.RealtimeBoard then
        T.RealtimeBoard:Stop()
    end
    if T.TacticalNotice then
        T.TacticalNotice:ClearAll()
    end
    if T.VisualBoardOverlay then
        T.VisualBoardOverlay:ClearAll()
    end
    if T.BlizzardTimeline and T.BlizzardTimeline.ClearInjected then
        T.BlizzardTimeline:ClearInjected()
    end
    if T.PhaseDetector and T.PhaseDetector.Stop then
        T.PhaseDetector:Stop()
    end
    scheduler.encounterID = 0
    scheduler.testAutoStopAt = 0
    NotifySubscribers()
end

function Runner:DelayPhaseEvents(phaseKey, delay)
    local normalizedDelay = tonumber(delay)
    if type(phaseKey) ~= "string" or phaseKey == "" or not normalizedDelay or normalizedDelay <= 0 then
        return 0
    end

    CancelAllPendingCountdownTimers()
    CancelAllPendingBarTimers()

    local resetCount = 0
    for _, event in ipairs(timeline) do
        if not event.ignored then
            if not event.triggered then
                event.countdownScheduled = false
            end
            local eventID = event.id or event.seq
            if not (T.HasActiveBarEvent and T.HasActiveBarEvent(eventID)) then
                event.barScheduled = false
            end
            if event.phase == phaseKey then
                resetCount = resetCount + 1
            end
        end
    end

    local delayedBars = 0
    if T.DelayActiveBars then
        delayedBars = T.DelayActiveBars(phaseKey, normalizedDelay) or 0
    end
    local delayedNotices = 0
    if T.TacticalNotice and T.TacticalNotice.DelayActive then
        delayedNotices = T.TacticalNotice:DelayActive(phaseKey, normalizedDelay) or 0
    end
    RunOptionalRuntimeStep("RefreshInjectedTimeline", function()
        RefreshInjectedTimeline("phase_delay")
    end)

    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format(
            "[TimelineDelay] phase=%s delay=%.2f events=%d activeBars=%d activeNotices=%d",
            tostring(phaseKey),
            normalizedDelay,
            resetCount,
            delayedBars,
            delayedNotices
        ))
    end
    return resetCount
end

-- OnUpdate 调度：创建屏幕提醒并在触发点播报
schedulerOnUpdate = function(self, elapsed)
    if self.paused then
        return
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.05 then return end
    self.elapsed = 0
    local plog = T.PerfLog and T.PerfLog:Begin("timeline:tick")

    local now = GetTime()
    self.currentTime = math.max(0, now - (tonumber(self.startTime) or now))
    local transportMaxTime = GetTransportMaxTime()
    if transportLoop.enabled == true and IsLoopRangeValid() and self.currentTime >= (tonumber(transportLoop.endTime) or 0) then
        local loopStart = math.max(0, tonumber(transportLoop.startTime) or 0)
        ApplyTransportPosition(loopStart)
        self.paused = false
        self:Show()
        self.currentTime = loopStart
        now = GetTime()
        if C.DB and C.DB.debugMode and T.debug then
            T.debug(string.format("[STT_TRANSPORT_LOOP_WRAP] start=%.2f end=%.2f", loopStart, tonumber(transportLoop.endTime) or 0))
        end
        NotifySubscribers()
    end

    if #timeline == 0 then
        if (self.isTest or ShouldKeepBoardTransport()) and transportMaxTime > 0 and self.currentTime < transportMaxTime then
            NotifySubscribers()
            if plog then plog:Finish({ events = 0, mode = "transport" }) end
            return
        end
        self.currentTime = transportMaxTime
        self:Hide()
        NotifySubscribers()
        if self.isTest then
            T.msg(L["测试结束"]) -- 兼容旧文案
        end
        if plog then plog:Finish({ events = 0, mode = "empty" }) end
        return
    end

    -- 屏幕提醒提前量按每条事件计算：自定义 indicator 固定用自身提前量；全局 indicator 可被 {sr:N} 覆盖。
    local ttsAdvance = math.max(0, tonumber(C.DB.ttsAdvanceTime) or 0)

    local firstPendingIndex = nil
    local hasPending = false

    for i, e in ipairs(timeline) do
        local eventTime = tonumber(e.time) or 0
        local actualEvent = ResolveEventAbsoluteTime(e)
        if not actualEvent then
            if not e.triggered and not e.ignored then
                hasPending = true
                if not firstPendingIndex then
                    firstPendingIndex = i
                end
                if e.phase and not phaseWarned[e.phase] then
                    local count = 0
                    for _, pendingEvent in ipairs(timeline) do
                        if pendingEvent.phase == e.phase and not pendingEvent.triggered and not pendingEvent.ignored then
                            count = count + 1
                        end
                    end
                    phaseWarned[e.phase] = true
                    T.msg(string.format(
                        "阶段 %s 未检测到，%d 条事件等待中；可用 /st phase %s 手动推进",
                        tostring(e.phase),
                        count,
                        tostring(e.phase)
                    ))
                end
                if self.isTest and self.testAutoStopAt > 0 and now >= self.testAutoStopAt then
                    e.ignored = true
                end
            end
        else
            local advance = (T.ScreenReminderSchema and T.ScreenReminderSchema.GetMaxLeadTime
                and T.ScreenReminderSchema.GetMaxLeadTime(e.screenLeadTime)) or 0
            if advance < 0.5 then advance = 0.5 end
            local actualShow = math.max(self.startTime, actualEvent - advance)
            local actualTrigger = actualEvent - (e.ttsAdvanceOverride ~= nil and e.ttsAdvanceOverride or ttsAdvance)
            local countdownValue = GetCountdownValue(e)
            local countdownActive = countdownValue and C.DB.CountdownEnabled ~= false
            if countdownActive then
                ScheduleCountdownEvent(e, actualEvent)
                actualTrigger = actualEvent - TTS_AUDIO_COMPENSATION
            end
            ScheduleBarEvent(e, actualEvent)

            if not e.reminderCreated and now >= actualShow then
                if T.ScreenReminder and C.DB.screenReminder and C.DB.screenReminder.enabled ~= false and ((e.screenText or e.text or "") ~= "") then
                    if C.DB and C.DB.debugMode and T.debug then
                        T.debug(string.format(
                            "[STT_ScreenReminder] text=%s spellID=%s matchedSpell=%s",
                            BuildReminderDebugText(e.screenText or e.text or ""),
                            tostring(tonumber(e.spellID) or 0),
                            tostring(e.screenSpellFromMatchedSegment == true)
                        ))
                    end
                    local ctx = {
                        text = e.screenText or e.text,
                        duration = math.max(0.1, actualEvent - now),
                        actualEvent = actualEvent,
                        spellID = e.spellID,
                        spellIcon = e.spellIcon,
                        isSilent = e.isSilent,
                        ttsText = e.ttsText,
                        severity = e.severity,
                        phase = e.phase,
                        targetIndicators = e.targetIndicators,
                        screenMatchedSegments = e.screenMatchedSegments,
                        screenLeadTime = e.screenLeadTime,
                    }
                    if T.ScreenReminder and T.ScreenReminder.Show then
                        T.ScreenReminder:Show(ctx)
                    end
                end
                e.reminderCreated = true
            end

            if not e.triggered and now >= actualTrigger then
                if e.visualBoards and T.VisualBoardOverlay then
                    for _, invoke in ipairs(e.visualBoards) do
                        T.VisualBoardOverlay:PlayByRef(invoke.boardRef, invoke.offset, { source = "timeline", bossKeyText = scheduler.bossKeyText })
                    end
                end
                if e.inlineSound and T.PlayInlineSound then
                    T.PlayInlineSound(e.inlineSound.path, e.inlineSound.label)
                end
                local ttsContent = e.ttsText or e.text or ""
                if ttsContent ~= "" then
                    T.PlayTTS(ttsContent)
                end
                e.triggered = true
            end

            if not e.triggered and not e.ignored then
                hasPending = true
                if not firstPendingIndex then
                    firstPendingIndex = i
                end
            end
        end
    end

    self.index = firstPendingIndex or (#timeline + 1)
    NotifySubscribers()

    if self.isTest and self.currentTime < transportMaxTime then
        hasPending = true
    end
    if ShouldKeepBoardTransport() and self.currentTime < transportMaxTime then
        hasPending = true
    end

    if not hasPending then
        self.currentTime = transportMaxTime
        self.paused = false
        self:Hide()
        NotifySubscribers()
        if self.isTest then
            T.msg(L["测试结束"]) -- 兼容旧文案
        end
    end
    if plog then
        plog:Finish({
            events = #timeline,
            pending = hasPending and 1 or 0,
            phase = T.PhaseDetector and T.PhaseDetector.GetCurrentPhase and T.PhaseDetector:GetCurrentPhase() or "",
        })
    end
end

-- 事件：正式模式使用 ENCOUNTER_START/END；开发模式可用 任意战斗开始/结束
local autoEventFrame
local function TimelineAutoEventsDesired()
    local db = C.DB or {}
    local screenReminder = type(db.screenReminder) == "table" and db.screenReminder.enabled ~= false
    local realtimeBoard = type(db.realtimeBoard) == "table" and db.realtimeBoard.enabled ~= false
    local timelineNotice = type(db.timelineNotice) == "table" and db.timelineNotice.enabled ~= false
    return db.ttsEnabled == true
        or db.CountdownEnabled == true
        or (type(db.Bar) == "table" and db.Bar.Enabled == true)
        or screenReminder == true
        or realtimeBoard == true
        or timelineNotice == true
        or db.devMode == true
end

local function OnTimelineAutoEvent(_, event, ...)
    local function StopAll()
        Runner:Stop()
        if T.TriggerRunner and T.TriggerRunner.Stop then
            T.TriggerRunner:Stop()
        end
    end

    if event == "ENCOUNTER_START" then
        local perf = T.CreatePerfProfile and T.CreatePerfProfile("ENCOUNTER_START_runner") or nil
        local _encounterID = tonumber((...)) or 0
        if C.DB.onlyInRaid then
            local _, instType = GetInstanceInfo()
            if instType ~= "raid" then
                if perf then perf:Finish() end
                return
            end
        end
        Runner:StartFromCurrent(false, _encounterID)
        if perf then perf:Mark("StartFromCurrent") end
        if perf then perf:Finish() end
    elseif event == "ENCOUNTER_END" then
        StopAll()
        C_Timer.After(0, function()
            MaybeStartStaticPreview("encounter_end")
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- 开发模式：任意战斗也能触发
        if C.DB.devMode then
            Runner:StartFromCurrent(true)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if C.DB.devMode then
            StopAll()
            C_Timer.After(0, function()
                MaybeStartStaticPreview("regen_enabled")
            end)
        end
    elseif event == "PLAYER_LOGOUT" then
        StopAll()
    end
end

function Runner:RefreshAutoEvents()
    local desired = TimelineAutoEventsDesired()
    if T.NoteParser and T.NoteParser.SetCombatTrackingEnabled then
        T.NoteParser:SetCombatTrackingEnabled(desired)
    end
    if not desired then
        if autoEventFrame then
            autoEventFrame:UnregisterAllEvents()
        end
        return
    end

    if not autoEventFrame then
        autoEventFrame = CreateFrame("Frame")
        autoEventFrame:SetScript("OnEvent", OnTimelineAutoEvent)
    end
    autoEventFrame:RegisterEvent("ENCOUNTER_START")
    autoEventFrame:RegisterEvent("ENCOUNTER_END")
    autoEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    autoEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    autoEventFrame:RegisterEvent("PLAYER_LOGOUT")
end

if T.RegisterInitCallback then
    T.RegisterInitCallback(function()
        Runner:RefreshAutoEvents()
    end)
end

-- 提供统一的测试函数，兼容旧调用
T.StartVoiceTest = function()
    Runner:StartTest()
end
T.GetTimelineRuntimeState = function()
    return Runner:GetRuntimeState()
end

end)
