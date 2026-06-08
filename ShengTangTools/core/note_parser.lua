local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

-- 时间轴解析引擎（薄封装）
-- 解析规则统一委托给 T.TimelineSyntax，避免多处并行实现
local Parser = {}
T.NoteParser = Parser

local parsedEvents = {}
local lastTemplateInfo = nil
local currentCombatTime = 0
local combatStartTime = 0
local isInCombat = false

local function EnsureLegacyFields(event)
    event.players = event.players or {}
    event.classes = event.classes or {}
    event.roles = event.roles or {}
    event.groups = event.groups or {}
    if event.triggered == nil then
        event.triggered = false
    end
end

function Parser:ParseNote(content, opts)
    parsedEvents = {}

    local parseOpts = type(opts) == "table" and opts or nil
    local template = parseOpts and parseOpts.templateInfo or nil

    if not content or content == "" then
        if not template then
            template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(content, parseOpts) or nil
        end
        lastTemplateInfo = template
        return parsedEvents
    end
    if not (T.TimelineSyntax and T.TimelineSyntax.ParseTimelineText) then
        T.debug("TimelineSyntax 未加载，ParseNote 返回空")
        return parsedEvents
    end

    if not template then
        template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(content or "", parseOpts) or nil
    end
    lastTemplateInfo = template
    if not (T.STNTemplate and T.STNTemplate.IsBodyUsable and T.STNTemplate.IsBodyUsable(template, "timeline")) then
        return parsedEvents
    end

    local parseText = template.processedText or ""
    local events = T.TimelineSyntax.ParseTimelineText(parseText)
    for _, event in ipairs(events or {}) do
        EnsureLegacyFields(event)
        table.insert(parsedEvents, event)
    end
    return parsedEvents
end

-- 统一条件判断：任一分片命中即视为该事件应对当前玩家触发
function Parser:ShouldTriggerEvent(event)
    if type(event) ~= "table" then
        return false
    end
    -- 个人方案无受众标记 → 所有事件对当前玩家触发（"给自己看的"）
    if event.isPersonal and event.hasAudience == false then
        return true
    end
    if type(event.visualBoards) == "table" and #event.visualBoards > 0 then
        return true
    end
    if event.hasAudience == false then
        return false
    end
    local segments = event.segments
    if type(segments) ~= "table" or #segments == 0 then
        return true
    end
    if T.TimelineSyntax and T.TimelineSyntax.ResolveSegmentsForCurrentPlayer then
        local modifiers = type(event.modifiers) == "table" and event.modifiers or nil
        local matched = T.TimelineSyntax.ResolveSegmentsForCurrentPlayer(segments, {
            requireAudience = true,
            skipUntargetedWhenAudience = true,
            allowEmptyResolved = modifiers and (modifiers.sound or modifiers.ct or modifiers.bar) and true or false,
        })
        return matched
    end
    return false
end

local function ExtractFallbackSpellID(event)
    if type(event) ~= "table" then
        return nil
    end

    local directSpellID = tonumber(event.spellID) or tonumber(event.primarySpellID)
    if directSpellID and directSpellID > 0 then
        return directSpellID
    end

    local content = event.content or event.displayText or event.originalText or event.rawLine or ""
    local spellID = content:match("{spell:(%d+):?%d*}")
    return spellID and tonumber(spellID) or nil
end

local function FinalizeResolvedPayload(event, payload, opts)
    if type(payload) ~= "table" then
        return nil
    end

    local text = tostring(payload.text or "")
    if opts and opts.stripPersonalPrefix then
        text = text:gsub("^%s*-%s*", "")
    end
    text = T.TimelineSyntax and T.TimelineSyntax.NormalizeASCIIWhitespace and T.TimelineSyntax.NormalizeASCIIWhitespace(text) or text
    if text == "" then
        return nil
    end

    local spellID = tonumber(payload.primarySpellID) or ExtractFallbackSpellID(event)
    local spellIcon = payload.spellIcon
    if not spellIcon and spellID and T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        spellIcon = T.TimelineSyntax.ResolveSpellIcon(spellID)
    end

    return {
        text = text,
        spellID = spellID,
        spellIcon = spellIcon,
        matchedSegments = payload.matchedSegments,
        spellFromMatchedSegment = tonumber(payload.primarySpellID) and true or false,
    }
end

local NO_RESOLVED_PAYLOAD = false

local function ReadResolvedPayloadCache(event, target)
    if type(event) ~= "table" or type(target) ~= "string" then
        return nil, false
    end

    local cache = event._resolvedPayloadByTarget
    if type(cache) ~= "table" then
        return nil, false
    end

    local cached = cache[target]
    if cached == nil then
        return nil, false
    end
    if cached == NO_RESOLVED_PAYLOAD then
        return nil, true
    end
    return cached, true
end

local function WriteResolvedPayloadCache(event, target, payload)
    if type(event) ~= "table" or type(target) ~= "string" then
        return payload
    end

    local cache = event._resolvedPayloadByTarget
    if type(cache) ~= "table" then
        cache = {}
        event._resolvedPayloadByTarget = cache
    end
    cache[target] = payload or NO_RESOLVED_PAYLOAD
    return payload
end

local function BuildFallbackResolvedPayload(event, target, opts)
    if type(event) ~= "table" then
        return nil
    end

    local content = event.content or event.displayText or event.originalText or ""
    if opts and opts.stripPersonalPrefix then
        content = content:gsub("^%s*-%s*", "")
    end

    local text = content
    if T.TimelineSyntax and T.TimelineSyntax.ResolveTextForCurrentPlayer then
        local matched, resolved = T.TimelineSyntax.ResolveTextForCurrentPlayer(content, opts)
        if matched then
            text = resolved or ""
        elseif opts and opts.requireAudience then
            return nil
        end
    elseif T.TimelineSyntax and T.TimelineSyntax.ResolveSpellTokens then
        text = T.TimelineSyntax.ResolveSpellTokens(text, { target = target })
    end

    text = T.TimelineSyntax and T.TimelineSyntax.NormalizeASCIIWhitespace and T.TimelineSyntax.NormalizeASCIIWhitespace(text) or text
    if text == "" then
        return nil
    end

    local spellID = ExtractFallbackSpellID(event)
    local spellIcon = nil
    if spellID and T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        spellIcon = T.TimelineSyntax.ResolveSpellIcon(spellID)
    end

    return {
        text = text,
        spellID = spellID,
        spellIcon = spellIcon,
        matchedSegments = nil,
        spellFromMatchedSegment = false,
    }
end

local function ResolveSyntaxPayloadForTarget(event, content, target, opts)
    local syntax = T.TimelineSyntax
    if not syntax then
        return false, nil
    end

    if target == "display_timeline"
        and syntax.ResolveSegmentsPayloadForCurrentPlayer
        and type(event.segments) == "table"
        and #event.segments > 0
    then
        return syntax.ResolveSegmentsPayloadForCurrentPlayer(event.segments, opts)
    end

    if syntax.ResolveTextPayloadForCurrentPlayer then
        return syntax.ResolveTextPayloadForCurrentPlayer(content, opts)
    end
    return false, nil
end

local function ResolveEventPayloadForTarget(event, target)
    if type(event) ~= "table" then
        return nil
    end

    local cached, hasCache = ReadResolvedPayloadCache(event, target)
    if hasCache then
        return cached
    end

    local content = event.content or event.displayText or event.originalText or ""
    local syntax = T.TimelineSyntax

    -- 个人方案无受众标记 → 直接展示整条内容，但技能图标仍跟随最终显示文本里的第一个技能。
    if event.isPersonal and event.hasAudience == false then
        if syntax then
            local matched, payload = ResolveSyntaxPayloadForTarget(event, content, target, { target = target })
            if matched then
                return WriteResolvedPayloadCache(event, target, FinalizeResolvedPayload(event, payload, { stripPersonalPrefix = true }))
            end
        end
        return WriteResolvedPayloadCache(event, target, BuildFallbackResolvedPayload(event, target, { target = target, stripPersonalPrefix = true }))
    end

    if event.hasAudience == false then
        return WriteResolvedPayloadCache(event, target, nil)
    end

    if syntax then
        local matched, payload = ResolveSyntaxPayloadForTarget(event, content, target, {
            target = target,
            requireAudience = true,
            skipUntargetedWhenAudience = true,
        })
        if matched then
            return WriteResolvedPayloadCache(event, target, FinalizeResolvedPayload(event, payload))
        end
        return WriteResolvedPayloadCache(event, target, nil)
    end

    return WriteResolvedPayloadCache(event, target, BuildFallbackResolvedPayload(event, target, {
        target = target,
        requireAudience = true,
        skipUntargetedWhenAudience = true,
    }))
end

function Parser:GetResolvedEventText(event)
    local payload = ResolveEventPayloadForTarget(event, "display_timeline")
    return payload and payload.text or ""
end

function Parser:GetResolvedEventScreenPayload(event)
    return ResolveEventPayloadForTarget(event, "display_screen")
end

function Parser:GetResolvedEventScreenText(event)
    local payload = self:GetResolvedEventScreenPayload(event)
    return payload and payload.text or ""
end

function Parser:GetResolvedEventTTSPayload(event)
    return ResolveEventPayloadForTarget(event, "tts")
end

function Parser:GetResolvedEventTTSText(event)
    local payload = self:GetResolvedEventTTSPayload(event)
    return payload and payload.text or ""
end

function Parser:GetLastTemplateInfo()
    return lastTemplateInfo
end

function Parser:UpdateCombatTime()
    if isInCombat and combatStartTime > 0 then
        currentCombatTime = GetTime() - combatStartTime
    end
end

function Parser:StartCombat()
    isInCombat = true
    combatStartTime = GetTime()
    currentCombatTime = 0
    for _, event in ipairs(parsedEvents) do
        event.triggered = false
    end
end

function Parser:EndCombat()
    isInCombat = false
    combatStartTime = 0
    currentCombatTime = 0
end

function Parser:GetUpcomingEvents(lookahead)
    lookahead = lookahead or 5
    local upcoming = {}
    self:UpdateCombatTime()

    for _, event in ipairs(parsedEvents) do
        if not event.triggered then
            local timeUntil = (tonumber(event.time) or 0) - currentCombatTime
            if timeUntil > 0 and timeUntil <= lookahead and self:ShouldTriggerEvent(event) then
                table.insert(upcoming, {
                    event = event,
                    timeUntil = timeUntil,
                })
            end
        end
    end

    table.sort(upcoming, function(a, b)
        return a.timeUntil < b.timeUntil
    end)
    return upcoming
end

function Parser:ProcessTriggeredEvents()
    local triggered = {}
    self:UpdateCombatTime()

    for _, event in ipairs(parsedEvents) do
        if not event.triggered and (tonumber(event.time) or 0) <= currentCombatTime then
            if self:ShouldTriggerEvent(event) then
                event.triggered = true
                table.insert(triggered, event)
            end
        end
    end
    return triggered
end

function Parser:FormatTime(seconds)
    if not seconds then return "00:00" end
    local total = tonumber(seconds) or 0
    local min = math.floor(total / 60)
    local sec = math.floor(total % 60)
    return string.format("%02d:%02d", min, sec)
end

function Parser:GetCombatTime()
    self:UpdateCombatTime()
    return currentCombatTime
end

function Parser:IsInCombat()
    return isInCombat
end

function Parser:GetParsedEvents()
    return parsedEvents
end

function Parser:SetCombatTime(time)
    currentCombatTime = tonumber(time) or 0
end

function Parser:Reset()
    parsedEvents = {}
    currentCombatTime = 0
    combatStartTime = 0
    isInCombat = false
end

local frame

local function OnCombatEvent(_, event)
    if event == "ENCOUNTER_START" or event == "PLAYER_REGEN_DISABLED" then
        Parser:StartCombat()
    elseif event == "ENCOUNTER_END" or event == "PLAYER_REGEN_ENABLED" then
        Parser:EndCombat()
    end
end

function Parser:SetCombatTrackingEnabled(enabled)
    if not enabled then
        if frame then
            frame:UnregisterAllEvents()
        end
        return
    end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnCombatEvent)
    end
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

end)
