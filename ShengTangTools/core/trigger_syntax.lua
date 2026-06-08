local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

-- STN 触发格式单一权威（SSOT）
-- 唯一格式：{on:spell:SPELLID[:-N]}[#N] [REST]；:-0 表示本行按触发点播报，不继承全局提前秒数。
-- REST 遵循团本规则：{谁} 前备注、{谁} 后播报、无 {谁} 不播报
local Syntax = {}
T.TriggerSyntax = Syntax

local LEGACY_HEADER = "STN_TRIGGER_V1"
local MODE_TEXT = "text"
local ASCII_SPACE_PATTERN = "[ \t\r\n]"
local ASCII_SPACE_RUN_PATTERN = "[ \t\r\n]+"
local ON_SPELL_PATTERN = "^" .. ASCII_SPACE_PATTERN .. "*{on:spell:(%d+):?([^}]*)}" .. ASCII_SPACE_PATTERN .. "*#?(%d*)(.*)" .. ASCII_SPACE_PATTERN .. "*$"
local ON_EVENT_PATTERN = "^" .. ASCII_SPACE_PATTERN .. "*{event:(%d+)}" .. ASCII_SPACE_PATTERN .. "*#?(%d*)(.*)" .. ASCII_SPACE_PATTERN .. "*$"

local function Trim(text)
    if type(text) ~= "string" then
        return ""
    end
    return text:gsub("^" .. ASCII_SPACE_RUN_PATTERN, ""):gsub(ASCII_SPACE_RUN_PATTERN .. "$", "")
end

local function CollapseWhitespace(text)
    if type(text) ~= "string" then
        return ""
    end
    return text:gsub(ASCII_SPACE_RUN_PATTERN, " ")
end

local function NormalizePositivePublicNumber(value)
    if T.EncounterEventResolver and T.EncounterEventResolver.NormalizePositiveNumber then
        return T.EncounterEventResolver.NormalizePositiveNumber(value)
    end

    local normalized = tonumber(value)
    if type(normalized) ~= "number" then
        return nil
    end
    local ok, positive = pcall(function()
        return normalized > 0
    end)
    if not ok or not positive then
        return nil
    end
    return normalized
end

local function TryParseNewFormat(trimmed)
    -- spell 规则
    local rawSpellID, rawAdvance, rawOcc, rest = trimmed:match(ON_SPELL_PATTERN)
    if rawSpellID then
        local spellID = tonumber(rawSpellID)
        if not spellID or spellID <= 0 then return nil, "spell_id_invalid" end

        rawAdvance = tostring(rawAdvance or "")
        local advance = nil
        local suppressGlobalAdvance = false
        if rawAdvance ~= "" then
            if rawAdvance:match("^%-%d+$") then
                advance = math.abs(tonumber(rawAdvance) or 0)
                suppressGlobalAdvance = advance == 0
            elseif not rawAdvance:match("^%d+$") then
                return nil, "advance_invalid"
            end
        end

        local occurrence = tonumber(rawOcc)
        if occurrence and occurrence <= 0 then return nil, "occurrence_invalid" end

        local payload = Trim(rest or "")
        local segments = {}
        if payload ~= "" and T.TimelineSyntax and T.TimelineSyntax.BuildSegments then
            segments = T.TimelineSyntax.BuildSegments(payload)
        end

        return {
            spellID = spellID,
            occurrence = occurrence,
            advance = advance,
            suppressGlobalAdvance = suppressGlobalAdvance,
            triggerKind = "spell",
            mode = MODE_TEXT,
            payload = payload,
            segments = segments,
            requireAudience = true,
        }
    end

    -- event 规则
    local rawEventID, rawOcc2, rest2 = trimmed:match(ON_EVENT_PATTERN)
    if rawEventID then
        local eventID = tonumber(rawEventID)
        if not eventID or eventID <= 0 then return nil, "event_id_invalid" end

        local occurrence = tonumber(rawOcc2)
        if occurrence and occurrence <= 0 then return nil, "occurrence_invalid" end

        local payload = Trim(rest2 or "")
        local segments = {}
        if payload ~= "" and T.TimelineSyntax and T.TimelineSyntax.BuildSegments then
            segments = T.TimelineSyntax.BuildSegments(payload)
        end

        return {
            eventID = eventID,
            spellID = nil,
            occurrence = occurrence,
            triggerKind = "event",
            mode = MODE_TEXT,
            payload = payload,
            segments = segments,
            requireAudience = true,
        }
    end

    return nil
end

function Syntax.GetHeader()
    return LEGACY_HEADER
end

function Syntax.IsTriggerText(text)
    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text) or nil
    if not template or template.hasBlocks ~= true then
        return false
    end
    return template.bodyKind == "trigger"
end

function Syntax.GetPlanFormat(text)
    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text) or nil
    if template and template.bodyKind == "trigger" then
        return "trigger"
    end
    return "timeline"
end

function Syntax.BuildRuleLine(spellID, occurrence, mode, payload, triggerKind, advance)
    local normalizedOccurrence = tonumber(occurrence)
    local normalizedPayload = Trim(tostring(payload or ""))
    local normalizedAdvance = tonumber(advance)

    local left
    if triggerKind == "event" then
        local normalizedEventID = tonumber(spellID) or 0
        left = string.format("{event:%d}", normalizedEventID)
    else
        local normalizedSpellID = tonumber(spellID) or 0
        if normalizedAdvance and normalizedAdvance > 0 then
            left = string.format("{on:spell:%d:-%d}", normalizedSpellID, normalizedAdvance)
        elseif normalizedAdvance == 0 then
            left = string.format("{on:spell:%d:-0}", normalizedSpellID)
        else
            left = string.format("{on:spell:%d}", normalizedSpellID)
        end
    end
    if normalizedOccurrence and normalizedOccurrence > 0 then
        left = string.format("%s#%d", left, normalizedOccurrence)
    end

    if normalizedPayload == "" then
        return left
    end

    -- 如果 payload 没有 {谁}，自动补 {所有人}
    local segments = T.TimelineSyntax and T.TimelineSyntax.BuildSegments
        and T.TimelineSyntax.BuildSegments(normalizedPayload) or {}
    local hasAudience = T.TimelineSyntax and T.TimelineSyntax.HasAudienceSegments
        and T.TimelineSyntax.HasAudienceSegments(segments)
    if not hasAudience and normalizedPayload ~= "" then
        normalizedPayload = "{所有人}" .. normalizedPayload
    end

    return string.format("%s %s", left, normalizedPayload)
end

function Syntax.ParseRuleLine(line)
    local rawLine = tostring(line or "")
    local trimmed = Trim(rawLine)
    if trimmed == "" then
        return nil
    end

    local rule, err = TryParseNewFormat(trimmed)
    if rule then
        rule.rawLine = rawLine
        return rule
    end
    return nil, err
end

function Syntax.ParseTriggerText(text)
    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text) or nil
    local rules = {}
    local errors = {}
    local defaultRules = {}
    local exactRules = {}
    local lineToRule = {}
    local lines = {}
    local lineNo = 0
    local lineMap = template and template.bodyLineMap or nil

    for _, err in ipairs(template and template.errors or {}) do
        errors[#errors + 1] = {
            line = tonumber(err.line) or 0,
            reason = tostring(err.reason or ""),
            content = tostring(err.content or ""),
        }
    end

    if not template or template.bodyKind ~= "trigger" or template.isValid ~= true then
        return {
            header = false,
            rules = rules,
            errors = errors,
            defaultRules = defaultRules,
            exactRules = exactRules,
            lineToRule = lineToRule,
            lines = lines,
            templateInfo = template,
        }
    end

    local raw = tostring(template.processedText or ""):gsub("\r\n", "\n")
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        lineNo = lineNo + 1
        lines[#lines + 1] = line
        local trimmed = Trim(line)
        local actualLine = tonumber(lineMap and lineMap[lineNo]) or lineNo
        if trimmed ~= "" then
            local rule, err = Syntax.ParseRuleLine(trimmed)
            if rule then
                rule.line = actualLine
                rules[#rules + 1] = rule
                lineToRule[lineNo] = rule

                local keyPrefix = (rule.triggerKind == "event") and "event" or "spell"
                local keyID = (rule.triggerKind == "event") and rule.eventID or rule.spellID
                local keySuffix = ""
                if rule.triggerKind ~= "event" and tonumber(rule.advance) and tonumber(rule.advance) > 0 then
                    keySuffix = ":pre"
                end
                if rule.occurrence then
                    exactRules[string.format("%s:%d%s#%d", keyPrefix, keyID, keySuffix, rule.occurrence)] = rule
                else
                    defaultRules[string.format("%s:%d%s", keyPrefix, keyID, keySuffix)] = rule
                end
            else
                local reason = L["触发规则格式无效"] or "触发规则格式无效"
                if err == "spell_id_invalid" then
                    reason = L["技能ID无效"] or "技能ID无效"
                elseif err == "event_id_invalid" then
                    reason = L["事件ID无效"] or "事件ID无效"
                elseif err == "occurrence_invalid" then
                    reason = L["第N次无效"] or "第N次无效"
                elseif err == "advance_invalid" then
                    reason = L["提前秒数无效"] or "提前秒数无效"
                end
                errors[#errors + 1] = {
                    line = actualLine,
                    reason = reason,
                    content = trimmed,
                }
            end
        end
    end

    return {
        header = true,
        rules = rules,
        errors = errors,
        defaultRules = defaultRules,
        exactRules = exactRules,
        lineToRule = lineToRule,
        lines = lines,
        templateInfo = template,
    }
end

local function BuildSpellRuleKey(spellID, occurrence, resolveMode)
    local normalizedSpellID = tonumber(spellID)
    if not normalizedSpellID or normalizedSpellID <= 0 then
        return nil
    end

    local key = string.format("spell:%d", normalizedSpellID)
    if resolveMode == "advance" then
        key = key .. ":pre"
    end

    local normalizedOccurrence = tonumber(occurrence)
    if normalizedOccurrence and normalizedOccurrence > 0 then
        key = string.format("%s#%d", key, normalizedOccurrence)
    end
    return key
end

function Syntax.ResolveRule(parsed, spellID, occurrence, resolveMode)
    if type(parsed) ~= "table" then
        return nil
    end

    local normalizedSpellID = NormalizePositivePublicNumber(spellID)
    local normalizedOccurrence = tonumber(occurrence)
    local normalizedResolveMode = (resolveMode == "advance") and "advance" or "normal"
    if not normalizedSpellID then
        return nil
    end

    if normalizedOccurrence and normalizedOccurrence > 0 then
        local exactKey = BuildSpellRuleKey(normalizedSpellID, normalizedOccurrence, normalizedResolveMode)
        local exact = parsed.exactRules and exactKey and parsed.exactRules[exactKey] or nil
        if exact then
            return exact, "exact"
        end
    end

    local defaultKey = BuildSpellRuleKey(normalizedSpellID, nil, normalizedResolveMode)
    local defaultRule = parsed.defaultRules and defaultKey and parsed.defaultRules[defaultKey] or nil
    if defaultRule then
        return defaultRule, "default"
    end

    return nil, "fallback"
end

function Syntax.ResolveEventRule(parsed, eventID, occurrence)
    if type(parsed) ~= "table" then
        return nil
    end

    local normalizedEventID = tonumber(eventID)
    if not normalizedEventID or normalizedEventID <= 0 then
        return nil
    end

    local normalizedOccurrence = tonumber(occurrence)
    if normalizedOccurrence and normalizedOccurrence > 0 then
        local exact = parsed.exactRules and parsed.exactRules[string.format("event:%d#%d", normalizedEventID, normalizedOccurrence)] or nil
        if exact then
            return exact, "exact"
        end
    end

    local defaultRule = parsed.defaultRules and parsed.defaultRules[string.format("event:%d", normalizedEventID)] or nil
    if defaultRule then
        return defaultRule, "default"
    end

    return nil, "fallback"
end

local function BuildPayloadText(rule, target)
    if type(rule) ~= "table" then
        return ""
    end

    local payload = tostring(rule.payload or "")
    if T.TimelineSyntax and T.TimelineSyntax.ResolveTextForCurrentPlayer then
        local opts = { target = target, requireAudience = true }
        local matched, resolved = T.TimelineSyntax.ResolveTextForCurrentPlayer(payload, opts)
        if type(rule.segments) == "table" and #rule.segments > 0 and not matched then
            return ""
        end
        return resolved or ""
    end

    if T.TimelineSyntax and T.TimelineSyntax.ResolveSpellTokens then
        payload = T.TimelineSyntax.ResolveSpellTokens(payload, { target = target })
    end
    payload = payload:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return Trim(CollapseWhitespace(payload))
end

local function RuleHasPayloadAudience(rule)
    if type(rule) ~= "table" or type(rule.segments) ~= "table" then
        return false
    end

    for _, seg in ipairs(rule.segments) do
        if type(seg) == "table" then
            if (type(seg.condition) == "string" and seg.condition ~= "")
                or (type(seg.players) == "table" and #seg.players > 0) then
                return true
            end
        end
    end
    return false
end

local function BuildResolvedTexts(rule, spellName)
    local normalizedSpellName = Trim(spellName or "")
    local payloadSpeakText = BuildPayloadText(rule, "tts")
    local payloadDisplayText = BuildPayloadText(rule, "display_timeline")
    local hasAudience = RuleHasPayloadAudience(rule)
    local effectivePayloadSpeakText = payloadSpeakText ~= "" and payloadSpeakText or payloadDisplayText
    local effectivePayloadDisplayText = payloadDisplayText ~= "" and payloadDisplayText or payloadSpeakText

    -- payload 解析出内容 → 播报
    if effectivePayloadDisplayText ~= "" or effectivePayloadSpeakText ~= "" then
        return effectivePayloadSpeakText, normalizedSpellName, effectivePayloadDisplayText
    end

    -- 有 {谁} 但当前玩家不匹配 → 不播报
    if hasAudience then
        return "", normalizedSpellName, ""
    end

    -- 无 {谁} → requireAudience 强制不播报
    return "", normalizedSpellName, ""
end

function Syntax.BuildSpeakText(rule, spellName)
    if type(rule) ~= "table" then
        return Trim(spellName or "")
    end

    local speakText = BuildResolvedTexts(rule, spellName)
    return speakText
end

function Syntax.BuildDisplayText(rule, spellName)
    local normalizedSpellName = Trim(spellName or "")
    if type(rule) ~= "table" then
        return normalizedSpellName
    end

    -- 无 payload 的纯触发标记：时间轴 UI 显示技能名
    if tostring(rule.payload or "") == "" then
        return normalizedSpellName
    end

    local _speakText, _spellText, payloadText = BuildResolvedTexts(rule, spellName)
    if payloadText ~= "" then
        return payloadText
    end
    -- payload 有内容但受众不匹配 → 不显示
    if _speakText == "" then
        return ""
    end
    return normalizedSpellName
end

function Syntax.UpsertDefaultRule(text, spellID, mode, payload)
    local normalizedSpellID = tonumber(spellID) or 0
    if normalizedSpellID <= 0 then
        return tostring(text or "")
    end

    local normalizedPayload = tostring(payload or "")
    local newLine = Syntax.BuildRuleLine(normalizedSpellID, nil, nil, normalizedPayload)

    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text) or nil
    if not template or template.bodyKind ~= "trigger" or template.isValid ~= true then
        return tostring(text or "")
    end

    local parsed = Syntax.ParseTriggerText(text)
    local output = {}
    local replaced = false

    for lineIndex, line in ipairs(parsed.lines or {}) do
        local trimmed = Trim(line)
        if trimmed ~= "" then
            local parsedRule = parsed.lineToRule and parsed.lineToRule[lineIndex] or nil
            if parsedRule and parsedRule.triggerKind ~= "event" and parsedRule.spellID == normalizedSpellID and not parsedRule.occurrence and not parsedRule.advance then
                if not replaced then
                    output[#output + 1] = newLine
                    replaced = true
                end
            else
                output[#output + 1] = line
            end
        else
            output[#output + 1] = line
        end
    end

    if not replaced then
        output[#output + 1] = newLine
    end

    local updatedBody = table.concat(output, "\n")
    if T.STNTemplate and T.STNTemplate.ReplaceBodyText then
        return T.STNTemplate.ReplaceBodyText(text, updatedBody)
    end
    return updatedBody
end

end)
