local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

-- 时间轴语法单一权威（SSOT）
-- 目标：统一 {time:...}、{spell:...}、条件/玩家 token 的解析，避免多处重复实现
local Syntax = {}
T.TimelineSyntax = Syntax

local unpackFunc = unpack or table.unpack
local SPELL_TOKEN_FIND_PATTERN = "{spell:([^}]+)}"
local TARGET_DISPLAY_WORKBENCH = "display_workbench"
local TARGET_DISPLAY_TIMELINE = "display_timeline"
local TARGET_DISPLAY_SCREEN = "display_screen"
local TARGET_TTS = "tts"
local ASCII_SPACE_PATTERN = "[ \t\r\n]"
local ASCII_SPACE_RUN_PATTERN = "[ \t\r\n]+"

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return s:gsub("^" .. ASCII_SPACE_RUN_PATTERN, ""):gsub(ASCII_SPACE_RUN_PATTERN .. "$", "")
end

local function CollapseWhitespace(s)
    if type(s) ~= "string" then return "" end
    return s:gsub(ASCII_SPACE_RUN_PATTERN, " ")
end

function Syntax.NormalizeASCIIWhitespace(text)
    local value = tostring(text or "")
    return Trim(CollapseWhitespace(value))
end

local function NormalizePunct(s)
    if type(s) ~= "string" then return "" end
    return s
        :gsub("：", ":")
        :gsub("＝", "=")
        :gsub("【", "[")
        :gsub("】", "]")
        :gsub("（", "(")
        :gsub("）", ")")
        :gsub("｛", "{")
        :gsub("｝", "}")
        :gsub("＋", "+")
end

local function NormalizeLegacyTokens(s)
    if type(s) ~= "string" or s == "" then return s or "" end
    -- 旧版占位符平滑迁移到当前统一 token
    s = s:gsub("{p:([^}]+)}", "{%1}")
    s = s:gsub("{c:([^}]+)}", "{%1}")
    s = s:gsub("{r:([^}]+)}", "{%1}")
    s = s:gsub("{g:([1-8])}", "{g%1}")
    return s
end

function Syntax.ExtractTargetIndicators(text)
    if type(text) ~= "string" or text == "" then
        return text or "", nil
    end

    local targets = nil
    local hasTarget = false
    local cleaned = text:gsub("{to:([^}]*)}", function(payload)
        for name in tostring(payload or ""):gmatch("[^,]+") do
            local targetName = Trim(name)
            if targetName ~= "" then
                targets = targets or {}
                targets[targetName] = true
                hasTarget = true
            end
        end
        return ""
    end)

    return cleaned, hasTarget and targets or nil
end

local function ParseTimeToSeconds(rawTime)
    local t = NormalizePunct(Trim(rawTime))
    if t == "" then return nil end

    local min, sec = t:match("^(%d+):(%d+%.?%d*)$")
    if min and sec then
        local m = tonumber(min)
        local s = tonumber(sec)
        if m and s then
            return m * 60 + s
        end
    end

    local onlySec = t:match("^(%d+%.?%d*)$")
    if onlySec then
        return tonumber(onlySec)
    end

    return nil
end

Syntax.ParseTimeToSeconds = ParseTimeToSeconds

local function NormalizePhaseKey(rawPhase)
    if type(rawPhase) ~= "string" then
        return nil
    end

    local phaseType, phaseIndex, roundIndex = rawPhase:match("^([pi])(%d+)r(%d+)$")
    if not phaseType then
        phaseType, phaseIndex = rawPhase:match("^([pi])(%d+)$")
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

    return string.format("%s%dr%d", phaseType, normalizedPhaseIndex, normalizedRoundIndex)
end

local function ParseTimePayload(payload)
    local core, optTail = payload:match("^" .. ASCII_SPACE_PATTERN .. "*([^,]+)" .. ASCII_SPACE_PATTERN .. "*,?(.*)$")
    core = Trim(core or "")
    optTail = Trim(optTail or "")
    local seconds = ParseTimeToSeconds(core)
    if not seconds then
        return nil
    end

    local phase = nil
    local ttsAdvanceOverride = nil
    if optTail ~= "" then
        for seg in optTail:gmatch("[^,]+") do
            seg = Trim(seg)
            local advanceText = seg:match("^%-(%d+%.?%d*)$")
            if advanceText then
                if ttsAdvanceOverride ~= nil then
                    return nil
                end
                ttsAdvanceOverride = tonumber(advanceText)
            else
                local phaseKey = NormalizePhaseKey(seg)
                if not phaseKey or phase ~= nil then
                    return nil
                end
                phase = phaseKey
            end
        end
    end

    return seconds, phase, ttsAdvanceOverride
end

local function SplitTimeFormatPayload(payload)
    local original = tostring(payload or "")
    local leading = original:match("^%s*") or ""
    local trailing = original:match("%s*$") or ""
    local body = Trim(original)
    local suffix = ""
    local commaPos = body:find(",", 1, true)
    if commaPos then
        suffix = body:sub(commaPos)
        body = Trim(body:sub(1, commaPos - 1))
    end

    local prefix = ""
    local phasePrefix, timePart = body:match("^([pi]%d+r?%d*:)(%d+:%d+%.?%d*)$")
    if phasePrefix and timePart then
        prefix = phasePrefix
        body = timePart
    end

    return leading, prefix, body, suffix, trailing
end

function Syntax.FormatTimeLike(originalTimePayload, newSeconds, opts)
    local leading, prefix, timePart, suffix, trailing = SplitTimeFormatPayload(originalTimePayload)
    local secondsValue = math.max(0, tonumber(newSeconds) or 0)
    local decimalPart = tostring(timePart or ""):match("%.(%d+)")
    local precision = decimalPart and #decimalPart or 0
    local requestedPrecision = type(opts) == "table" and tonumber(opts.precision) or nil
    if requestedPrecision and requestedPrecision > precision and math.abs(secondsValue - math.floor(secondsValue + 0.5)) >= 0.0001 then
        precision = math.min(3, math.max(0, math.floor(requestedPrecision + 0.5)))
    end
    local hasColon = tostring(timePart or ""):find(":", 1, true) ~= nil
    local formatted

    if hasColon then
        local total = secondsValue
        if precision == 0 then
            total = math.floor(total + 0.5)
            local minutes = math.floor(total / 60)
            local seconds = total - minutes * 60
            formatted = string.format("%d:%02d", minutes, seconds)
        else
            local factor = 10 ^ precision
            total = math.floor(total * factor + 0.5) / factor
            local minutes = math.floor(total / 60)
            local seconds = total - minutes * 60
            formatted = string.format("%d:%0" .. tostring(precision + 3) .. "." .. tostring(precision) .. "f", minutes, seconds)
        end
    else
        if precision == 0 then
            formatted = tostring(math.floor(secondsValue + 0.5))
        else
            formatted = string.format("%." .. tostring(precision) .. "f", secondsValue)
        end
    end

    return leading .. prefix .. formatted .. suffix .. trailing
end

function Syntax.RewriteTimeInText(originalText, lineNum, newSeconds, opts)
    if type(originalText) ~= "string" then
        return { newText = originalText or "", newCaretPos = 0, changed = false, reason = "invalid_text" }
    end
    local targetLine = tonumber(lineNum)
    if not targetLine or targetLine <= 0 then
        return { newText = originalText, newCaretPos = 0, changed = false, reason = "line_not_found" }
    end

    local lineIndex = 1
    local lineStart = 1
    for line in (originalText .. "\n"):gmatch("([^\n]*)\n") do
        local lineEnd = lineStart + #line - 1
        if lineIndex == targetLine then
            local tokenStart, tokenEnd, payload = line:find("{time:([^}]+)}")
            if not tokenStart then
                return { newText = originalText, newCaretPos = math.max(0, lineStart - 1), changed = false, reason = "no_time_token" }
            end
            if not ParseTimePayload(payload) then
                return { newText = originalText, newCaretPos = math.max(0, lineStart - 1), changed = false, reason = "parse_failed" }
            end

            local replacementPayload = Syntax.FormatTimeLike(payload, newSeconds, opts)
            local replacement = "{time:" .. replacementPayload .. "}"
            local newLine = line:sub(1, tokenStart - 1) .. replacement .. line:sub(tokenEnd + 1)
            local newText = originalText:sub(1, lineStart - 1) .. newLine .. originalText:sub(lineEnd + 1)
            local newCaretPos = math.max(0, lineStart + tokenStart + #replacement - 2)
            return {
                newText = newText,
                newCaretPos = newCaretPos,
                changed = newText ~= originalText,
            }
        end
        lineStart = lineStart + #line + 1
        lineIndex = lineIndex + 1
    end

    return { newText = originalText, newCaretPos = #originalText, changed = false, reason = "line_not_found" }
end

function Syntax.RewriteEventLineInText(originalText, lineNum, newLineString, opts)
    if type(originalText) ~= "string" then
        return { newText = originalText or "", newCaretPos = 0, changed = false, reason = "invalid_text" }
    end
    local targetLine = tonumber(lineNum)
    if not targetLine or targetLine <= 0 then
        return { newText = originalText, newCaretPos = 0, changed = false, reason = "line_not_found" }
    end
    if type(newLineString) ~= "string" or Trim(newLineString) == "" then
        return { newText = originalText, newCaretPos = 0, changed = false, reason = "empty_line" }
    end

    local lineIndex = 1
    local lineStart = 1
    for line in (originalText .. "\n"):gmatch("([^\n]*)\n") do
        local lineEnd = lineStart + #line - 1
        if lineIndex == targetLine then
            local newText = originalText:sub(1, lineStart - 1) .. newLineString .. originalText:sub(lineEnd + 1)
            local newCaretPos = math.max(0, lineStart + #newLineString - 1)
            return {
                newText = newText,
                newCaretPos = newCaretPos,
                changed = newText ~= originalText,
            }
        end
        lineStart = lineStart + #line + 1
        lineIndex = lineIndex + 1
    end

    return { newText = originalText, newCaretPos = #originalText, changed = false, reason = "line_not_found" }
end

local function RemoveColorCodes(text)
    if type(text) ~= "string" then return "" end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local RAID_MARKER_MAP = {
    star = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t",
    rt1 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t",
    circle = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:0|t",
    rt2 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:0|t",
    diamond = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:0|t",
    rt3 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:0|t",
    triangle = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:0|t",
    rt4 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:0|t",
    moon = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:0|t",
    rt5 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:0|t",
    square = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:0|t",
    rt6 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:0|t",
    cross = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:0|t",
    rt7 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:0|t",
    skull = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t",
    rt8 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t",
}

local function ClearArray(arr)
    for i = #arr, 1, -1 do
        arr[i] = nil
    end
end

local function HasLegacyBlockTag(text)
    if not text:find("{/", 1, true) then
        return false
    end
    return text:find("{0}", 1, true)
        or text:find("{H}", 1, true) or text:find("{h}", 1, true)
        or text:find("{T}", 1, true) or text:find("{t}", 1, true)
        or text:find("{D}", 1, true) or text:find("{d}", 1, true)
        or text:find("{P:", 1, true) or text:find("{p:", 1, true)
        or text:find("{!P:", 1, true) or text:find("{!p:", 1, true)
        or text:find("{C:", 1, true) or text:find("{c:", 1, true)
        or text:find("{!C:", 1, true) or text:find("{!c:", 1, true)
        or text:find("{G", 1, true) or text:find("{g", 1, true)
        or text:find("{!G", 1, true) or text:find("{!g", 1, true)
end

local function NormalizeSpellRenderTarget(target)
    local value = tostring(target or ""):lower()
    if value == TARGET_DISPLAY_TIMELINE or value == "timeline" then
        return TARGET_DISPLAY_TIMELINE
    end
    if value == TARGET_DISPLAY_SCREEN or value == "screen" then
        return TARGET_DISPLAY_SCREEN
    end
    if value == TARGET_TTS then
        return TARGET_TTS
    end
    return TARGET_DISPLAY_WORKBENCH
end

local function ResolveRenderTarget(opts)
    if type(opts) == "string" then
        return NormalizeSpellRenderTarget(opts)
    end
    if type(opts) == "table" then
        if opts.target then
            return NormalizeSpellRenderTarget(opts.target)
        end
        if opts.mode == "tts" then
            return TARGET_TTS
        end
    end
    return TARGET_DISPLAY_WORKBENCH
end

local function NormalizeSpellTokenDisplay(mode)
    local value = tostring(mode or "text")
    if value == "icon" or value == "iconText" then
        return value
    end
    return "text"
end

local function ResolveSpellTokenDisplay(opts)
    if type(opts) == "table" then
        return NormalizeSpellTokenDisplay(opts.spellTokenDisplay)
    end
    return "text"
end

local function ResolveSpellName(spellID)
    local id = tonumber(spellID)
    if not id or id <= 0 then
        return ""
    end
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        local name = info and info.name or nil
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    local bossSpells = T.Data and T.Data.BossSpells
    if type(bossSpells) == "table" then
        for _, bossInfo in pairs(bossSpells) do
            local spellInfo = type(bossInfo) == "table" and type(bossInfo.spells) == "table" and bossInfo.spells[id] or nil
            local name = type(spellInfo) == "table" and spellInfo.name or nil
            if type(name) == "string" and name ~= "" then
                return name
            end
        end
    end
    return ""
end

local function BuildInlineSpellIcon(iconID)
    local id = tonumber(iconID)
    if not id or id <= 0 then
        return ""
    end
    return string.format("|T%d:0:0:0:0:64:64:5:59:5:59|t", id)
end

local function ParseSpellTokenPayload(payload)
    local text = Trim(payload)
    local idText, tail = text:match("^(%d+)(.*)$")
    if not idText then
        return nil
    end

    local spellID = tonumber(idText)
    if not spellID or spellID <= 0 then
        return nil
    end

    tail = Trim(tail or "")
    local occurrence = nil
    if tail ~= "" then
        local occurrenceText = tail:match("^:(%d+)")
        if occurrenceText then
            occurrence = tonumber(occurrenceText)
            tail = Trim(tail:gsub("^:%d+", "", 1))
        end
    end

    local duration = nil
    if tail ~= "" then
        local durationText = tail:match("^,%s*dur%s*:%s*(%d+%.?%d*)%s*$")
        if not durationText then
            return nil
        end
        duration = tonumber(durationText)
        if not duration or duration <= 0 then
            return nil
        end
    end

    return spellID, duration, occurrence
end

local function ParseSpellTokenRaw(raw)
    local payload = tostring(raw or ""):match("^{spell:([^}]+)}$")
    if not payload then
        return nil
    end
    return ParseSpellTokenPayload(payload)
end

local function IsSpellTokenRaw(raw)
    return ParseSpellTokenRaw(raw) ~= nil
end

local function BuildSpellTokenFragments(text)
    local value = tostring(text or "")
    local fragments = {}
    local spellCount = 0
    local pos = 1

    while true do
        local b, e, payload = value:find(SPELL_TOKEN_FIND_PATTERN, pos)
        if not b then
            if pos <= #value then
                fragments[#fragments + 1] = {
                    kind = "text",
                    text = value:sub(pos),
                }
            end
            break
        end

        if b > pos then
            fragments[#fragments + 1] = {
                kind = "text",
                text = value:sub(pos, b - 1),
            }
        end

        local raw = value:sub(b, e)
        local spellID, duration = ParseSpellTokenPayload(payload)
        if spellID then
            spellCount = spellCount + 1
            fragments[#fragments + 1] = {
                kind = "spell",
                raw = raw,
                spellID = spellID,
                spellName = ResolveSpellName(spellID),
                spellIcon = Syntax.ResolveSpellIcon(spellID),
                isPrimarySpell = spellCount == 1,
                duration = duration,
            }
        else
            fragments[#fragments + 1] = {
                kind = "text",
                text = raw,
            }
        end
        pos = e + 1
    end

    return fragments
end

function Syntax.ExtractSpellTokens(text)
    local out = {}
    for _, fragment in ipairs(BuildSpellTokenFragments(text)) do
        if fragment.kind == "spell" then
            out[#out + 1] = {
                raw = fragment.raw,
                spellID = fragment.spellID,
                spellName = fragment.spellName,
                spellIcon = fragment.spellIcon,
                isPrimarySpell = fragment.isPrimarySpell,
                duration = fragment.duration,
            }
        end
    end
    return out
end

local function RenderSpellFragment(fragment, target, spellTokenDisplay)
    if type(fragment) ~= "table" then
        return ""
    end
    if fragment.kind ~= "spell" then
        return fragment.text or ""
    end

    local spellName = tostring(fragment.spellName or "")
    if target == TARGET_TTS then
        return spellName
    end

    if target == TARGET_DISPLAY_SCREEN then
        local iconMarkup = BuildInlineSpellIcon(fragment.spellIcon)
        if spellTokenDisplay == "icon" and iconMarkup ~= "" then
            return iconMarkup
        end
        if spellTokenDisplay == "iconText" and iconMarkup ~= "" then
            if spellName ~= "" then
                return iconMarkup .. " " .. spellName
            end
            return iconMarkup
        end
        return spellName
    end

    if fragment.isPrimarySpell then
        return spellName
    end

    local iconMarkup = BuildInlineSpellIcon(fragment.spellIcon)
    if iconMarkup ~= "" and spellName ~= "" then
        return iconMarkup .. " " .. spellName
    end
    if iconMarkup ~= "" then
        return iconMarkup
    end
    return spellName
end

function Syntax.ResolveSpellTokens(text, opts)
    if type(text) ~= "string" or text == "" then
        return text or ""
    end

    local target = ResolveRenderTarget(opts)
    local spellTokenDisplay = ResolveSpellTokenDisplay(opts)
    local fragments = BuildSpellTokenFragments(text)
    if #fragments == 0 then
        return text
    end

    local out = {}
    for _, fragment in ipairs(fragments) do
        out[#out + 1] = RenderSpellFragment(fragment, target, spellTokenDisplay)
    end
    return table.concat(out)
end

function Syntax.ResolveSpellIcon(spellID)
    local id = tonumber(spellID)
    if not id or not C_Spell or not C_Spell.GetSpellInfo then
        return nil
    end
    local info = C_Spell.GetSpellInfo(id)
    return info and (info.iconID or info.originalIconID) or nil
end

function Syntax.StripLegacyBlockTags(text)
    if type(text) ~= "string" or text == "" then
        return text or ""
    end

    local out = text
    if HasLegacyBlockTag(out) then
        local patterns = {
            "{0}.-{/0}",
            "{[Hh]}.-{/[Hh]}",
            "{[Tt]}.-{/[Tt]}",
            "{[Dd]}.-{/[Dd]}",
            "{[Pp]:[^}]+}.-{/[Pp]}",
            "{![Pp]:[^}]+}.-{/[Pp]}",
            "{[Cc]:[^}]+}.-{/[Cc]}",
            "{![Cc]:[^}]+}.-{/[Cc]}",
            "{[Gg][^}]*}.-{/[Gg]}",
            "{![Gg][^}]*}.-{/[Gg]}",
        }

        local changed = true
        while changed do
            local before = out
            for _, pattern in ipairs(patterns) do
                out = out:gsub(pattern, "")
            end
            changed = before ~= out
        end
    end

    out = out:gsub("{self}", "")
    out = out:gsub("{icon:[^}]+}", "")
    out = out:gsub("||([cr])", "|%1")
    return out
end

function Syntax.ResolveRaidMarkers(text)
    if type(text) ~= "string" or text == "" then
        return text or ""
    end
    return text:gsub("{([%a%d]+)}", function(token)
        local key = tostring(token or ""):lower()
        return RAID_MARKER_MAP[key] or ("{" .. token .. "}")
    end)
end

function Syntax.StripRaidMarkers(text)
    if type(text) ~= "string" or text == "" then
        return text or ""
    end
    return text:gsub("{([%a%d]+)}", function(token)
        local key = tostring(token or ""):lower()
        if RAID_MARKER_MAP[key] then
            return ""
        end
        return "{" .. token .. "}"
    end)
end

function Syntax.UnwrapSilentMarkers(text)
    if type(text) ~= "string" or text == "" then
        return text or ""
    end
    local out = text
    -- `<xxx>` 是绝对注释：既不播报也不显示（StripSilentMarkers 已删，此处渲染路径同样删除）
    out = out:gsub("<[^<>]->", "")
    -- `~~xxx~~` 是静默标记：显示 xxx 但不播报（TTS 路径由 Strip 删除，此处保留文本）
    out = out:gsub("~~(.-)~~", "%1")
    return out
end

function Syntax.StripSilentMarkers(text)
    if type(text) ~= "string" or text == "" then
        return text or ""
    end
    local out = text
    out = out:gsub("<[^<>]+>", "")
    out = out:gsub("~~.-~~", "")
    return out
end

local function PrepareSourceText(text, opts)
    local src = NormalizePunct(text or "")
    src = NormalizeLegacyTokens(src)
    src = Syntax.ExtractTargetIndicators(src)
    src = Syntax.StripLegacyBlockTags(src)
    src = Syntax.ResolveSpellTokens(src, opts)
    if ResolveRenderTarget(opts) == TARGET_TTS then
        src = Syntax.StripRaidMarkers(src)
        src = Syntax.StripSilentMarkers(src)
    else
        src = Syntax.ResolveRaidMarkers(src)
        src = Syntax.UnwrapSilentMarkers(src)
    end
    return src
end

local function BuildSegmentSpellMetadata(text, opts)
    local src = NormalizePunct(text or "")
    src = NormalizeLegacyTokens(src)
    src = Syntax.StripLegacyBlockTags(src)

    local metadata = {}
    local rawParts = {}
    local pos = 1

    local function AppendRawText(raw)
        if type(raw) == "string" and raw ~= "" then
            rawParts[#rawParts + 1] = raw
        end
    end

    local function PushMetadata()
        if #rawParts == 0 then
            return
        end

        local raw = table.concat(rawParts)
        ClearArray(rawParts)
        if raw == "" or Trim(raw) == "" then
            return
        end

        local prepared = PrepareSourceText(raw, opts)
        prepared = Syntax.NormalizeASCIIWhitespace(prepared)
        if prepared == "" then
            return
        end

        local rawText = Syntax.NormalizeASCIIWhitespace(raw)

        local cellText = PrepareSourceText(raw, {
            mode = type(opts) == "table" and opts.mode or nil,
            target = TARGET_DISPLAY_SCREEN,
        })
        cellText = Syntax.NormalizeASCIIWhitespace(cellText)

        local spellTokens = Syntax.ExtractSpellTokens(raw)
        metadata[#metadata + 1] = {
            cellText = cellText,
            spellTokens = spellTokens,
            primarySpellID = spellTokens[1] and spellTokens[1].spellID or nil,
            rawText = rawText,
        }
    end

    while true do
        local b, e = src:find("%b{}", pos)
        if not b then
            AppendRawText(src:sub(pos))
            PushMetadata()
            break
        end

        AppendRawText(src:sub(pos, b - 1))

        local rawToken = src:sub(b, e)
        local token = Trim(src:sub(b + 1, e - 1))
        local raidMarker = RAID_MARKER_MAP[tostring(token or ""):lower()]
        if token ~= "" then
            if IsSpellTokenRaw(rawToken) or raidMarker then
                AppendRawText(rawToken)
            else
                PushMetadata()
            end
        end
        pos = e + 1
    end

    return metadata
end

function Syntax.BuildSegments(text, opts)
    local src = PrepareSourceText(text, opts)
    local spellMetadata = BuildSegmentSpellMetadata(text, opts)

    local segments = {}
    local curConds = {}
    local curPlayers = {}
    local pos = 1

    local function PushSegment(str)
        if type(str) ~= "string" or str == "" then
            return
        end

        local s = Syntax.NormalizeASCIIWhitespace(str or "")
        if s ~= "" then
            table.insert(segments, {
                text = s,
                condition = (#curConds > 0) and table.concat(curConds, ",") or "",
                players = (#curPlayers > 0) and { unpackFunc(curPlayers) } or nil,
            })
            -- token 仅作用于紧随其后的一个文本片段
            ClearArray(curConds)
            ClearArray(curPlayers)
        end
    end

    while true do
        local b, e = src:find("%b{}", pos)
        if not b then
            PushSegment(src:sub(pos))
            break
        end

        PushSegment(src:sub(pos, b - 1))

        local token = Trim(src:sub(b + 1, e - 1))
        if token ~= "" then
            if T.IsGroupConditionToken and T.IsGroupConditionToken(token) then
                table.insert(curConds, token)
            else
                table.insert(curPlayers, token)
            end
        end
        pos = e + 1
    end

    if #segments == 0 and (#curConds > 0 or #curPlayers > 0) then
        table.insert(segments, {
            text = "",
            condition = (#curConds > 0) and table.concat(curConds, ",") or "",
            players = (#curPlayers > 0) and { unpackFunc(curPlayers) } or nil,
        })
    end

    for index, segment in ipairs(segments) do
        local meta = spellMetadata[index]
        segment.cellText = meta and meta.cellText or ""
        segment.spellTokens = meta and meta.spellTokens or {}
        segment.primarySpellID = meta and meta.primarySpellID or nil
        segment.rawText = meta and meta.rawText or ""
    end

    return segments
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

local function CleanResolvedText(text)
    local value = Syntax.NormalizeASCIIWhitespace(text)
    value = value:gsub("^([,;]+)", "")
    value = value:gsub("([,;]+)$", "")
    return Syntax.NormalizeASCIIWhitespace(value)
end

local function BuildDisplayText(text, target)
    local prepared = PrepareSourceText(text, {
        mode = "display",
        target = target or TARGET_DISPLAY_WORKBENCH,
    })
    return CleanResolvedText(prepared)
end

local function BuildDisplayTextWithoutSpellTokens(text, target)
    local stripped = tostring(text or ""):gsub(SPELL_TOKEN_FIND_PATTERN, "")
    return BuildDisplayText(stripped, target or TARGET_DISPLAY_SCREEN)
end

function Syntax.BuildScreenTextFromSegments(segments, spellTokenDisplay, fallbackText)
    if type(segments) ~= "table" or #segments == 0 then
        return fallbackText or ""
    end

    local out = {}
    for _, segment in ipairs(segments) do
        local raw = type(segment) == "table" and tostring(segment.rawText or "") or ""
        if raw == "" and type(segment) == "table" then
            raw = tostring(segment.text or "")
        end
        local prepared = PrepareSourceText(raw, {
            mode = "display",
            target = TARGET_DISPLAY_SCREEN,
            spellTokenDisplay = spellTokenDisplay,
        })
        prepared = Syntax.NormalizeASCIIWhitespace(prepared)
        if prepared ~= "" then
            out[#out + 1] = prepared
        end
    end

    local resolved = CleanResolvedText(table.concat(out, " "))
    if resolved == "" then
        return fallbackText or ""
    end
    return resolved
end

function Syntax.BuildScreenTextWithoutSpellTokensFromSegments(segments, fallbackText)
    if type(segments) ~= "table" or #segments == 0 then
        return fallbackText or ""
    end

    local out = {}
    for _, segment in ipairs(segments) do
        local raw = type(segment) == "table" and tostring(segment.rawText or "") or ""
        if raw == "" and type(segment) == "table" then
            raw = tostring(segment.text or "")
        end
        local prepared = BuildDisplayTextWithoutSpellTokens(raw, TARGET_DISPLAY_SCREEN)
        if prepared ~= "" then
            out[#out + 1] = prepared
        end
    end

    local resolved = CleanResolvedText(table.concat(out, " "))
    if resolved == "" then
        return fallbackText or ""
    end
    return resolved
end

function Syntax.HasAudienceSegments(segments)
    if type(segments) ~= "table" then
        return false
    end

    for _, seg in ipairs(segments) do
        if SegmentHasAudience(seg) then
            return true
        end
    end
    return false
end

local function GetSegmentPrimarySpellMeta(segment)
    if type(segment) ~= "table" then
        return nil, nil
    end

    if type(segment.spellTokens) == "table" then
        for _, token in ipairs(segment.spellTokens) do
            local spellID = tonumber(token and token.spellID)
            if spellID and spellID > 0 then
                return spellID, token.spellIcon or Syntax.ResolveSpellIcon(spellID)
            end
        end
    end

    local spellID = tonumber(segment.primarySpellID)
    if spellID and spellID > 0 then
        return spellID, Syntax.ResolveSpellIcon(spellID)
    end
    return nil, nil
end

function Syntax.ResolveSegmentsPayloadForCurrentPlayer(segments, opts)
    if type(segments) ~= "table" or #segments == 0 then
        return false, nil
    end

    local hasTargetedSegment = Syntax.HasAudienceSegments(segments)
    local requireAudience = type(opts) == "table" and opts.requireAudience == true
    local skipUntargetedWhenAudience = not (type(opts) == "table" and opts.skipUntargetedWhenAudience == false)

    if requireAudience and not hasTargetedSegment then
        return false, nil
    end

    local matchedTargetedSegment = false
    local matchedSegments = {}
    local out = {}
    local primarySpellID = nil
    local spellIcon = nil

    local function AppendMatchedSegment(seg)
        local text = type(seg) == "table" and tostring(seg.text or "") or ""
        if text == "" then
            return
        end
        matchedSegments[#matchedSegments + 1] = seg
        out[#out + 1] = text
        if not primarySpellID then
            primarySpellID, spellIcon = GetSegmentPrimarySpellMeta(seg)
        end
    end

    for _, seg in ipairs(segments) do
        local text = type(seg) == "table" and tostring(seg.text or "") or ""
        if not hasTargetedSegment then
            if text ~= "" then
                AppendMatchedSegment(seg)
            end
        elseif SegmentHasAudience(seg) then
            local passGroup = (not T.ShouldBroadcastToPlayer) and true or T.ShouldBroadcastToPlayer(seg.condition)
            local passName = (not T.ShouldBroadcastForNames) and true or T.ShouldBroadcastForNames(seg.players)
            if passGroup and passName then
                matchedTargetedSegment = true
                if text ~= "" then
                    AppendMatchedSegment(seg)
                end
            end
        elseif not skipUntargetedWhenAudience then
            if text ~= "" then
                AppendMatchedSegment(seg)
            end
        end
    end

    if hasTargetedSegment and not matchedTargetedSegment then
        return false, nil
    end

    local resolved = CleanResolvedText(table.concat(out, " "))
    if resolved == "" then
        if type(opts) == "table" and opts.allowEmptyResolved == true and (not hasTargetedSegment or matchedTargetedSegment) then
            return true, {
                text = "",
                primarySpellID = nil,
                spellIcon = nil,
                matchedSegments = matchedSegments,
                matchedTargetedSegment = matchedTargetedSegment,
                hasTargetedSegment = hasTargetedSegment,
            }
        end
        return false, nil
    end

    return true, {
        text = resolved,
        primarySpellID = primarySpellID,
        spellIcon = spellIcon,
        matchedSegments = matchedSegments,
        matchedTargetedSegment = matchedTargetedSegment,
        hasTargetedSegment = hasTargetedSegment,
    }
end

function Syntax.ResolveSegmentsForCurrentPlayer(segments, opts)
    local matched, payload = Syntax.ResolveSegmentsPayloadForCurrentPlayer(segments, opts)
    return matched, payload and payload.text or ""
end

function Syntax.ResolveTextPayloadForCurrentPlayer(text, opts)
    local segments = Syntax.BuildSegments(text, opts)
    if #segments == 0 then
        local prepared = PrepareSourceText(text, opts)
        prepared = CleanResolvedText(prepared)
        if type(opts) == "table" and opts.requireAudience == true then
            return false, nil
        end
        if prepared == "" then
            return false, nil
        end

        local spellTokens = Syntax.ExtractSpellTokens(text)
        local primarySpell = spellTokens[1]
        local primarySpellID = primarySpell and tonumber(primarySpell.spellID) or nil
        return true, {
            text = prepared,
            primarySpellID = primarySpellID,
            spellIcon = primarySpell and (primarySpell.spellIcon or Syntax.ResolveSpellIcon(primarySpellID)) or nil,
            matchedSegments = nil,
            matchedTargetedSegment = false,
            hasTargetedSegment = false,
        }
    end
    return Syntax.ResolveSegmentsPayloadForCurrentPlayer(segments, opts)
end

function Syntax.ResolveTextForCurrentPlayer(text, opts)
    local matched, payload = Syntax.ResolveTextPayloadForCurrentPlayer(text, opts)
    return matched, payload and payload.text or ""
end

function Syntax.ParseTimelineLine(line)
    local rawLine = NormalizePunct(line or "")
    rawLine = Syntax.StripLegacyBlockTags(rawLine)
    rawLine = Trim(rawLine)
    if rawLine == "" then return nil end

    local payload = rawLine:match("{time:([^}]+)}")
    if not payload then return nil end

    local eventTime, eventPhase, ttsAdvanceOverride = ParseTimePayload(payload)
    if not eventTime then
        return nil
    end

    local content = rawLine:gsub("{time:[^}]+}", "", 1)
    content = NormalizeLegacyTokens(content)
    content = Trim(content)
    local modifiers = nil
    if T.InlineModifier and T.InlineModifier.Scan then
        local scanned = T.InlineModifier.Scan(content)
        if scanned then
            if type(scanned.modifiers) == "table" and next(scanned.modifiers) then
                modifiers = scanned.modifiers
            end
            content = Trim(scanned.stripped or "")
        end
    end
    local visualBoards = nil
    if T.VisualBoardParserHook and T.VisualBoardParserHook.ExtractInvokes then
        local stripped, invokes = T.VisualBoardParserHook.ExtractInvokes(content)
        content = stripped
        if type(invokes) == "table" and #invokes > 0 then
            visualBoards = invokes
        end
    end

    local targetIndicators
    content, targetIndicators = Syntax.ExtractTargetIndicators(content)
    content = Trim(content)

    local segments = Syntax.BuildSegments(content)
    local hasAudience = Syntax.HasAudienceSegments(segments)
    local spellTokens = Syntax.ExtractSpellTokens(content)
    local displayText = BuildDisplayText(content, TARGET_DISPLAY_WORKBENCH)

    return {
        time = eventTime,
        phase = eventPhase,
        ttsAdvanceOverride = ttsAdvanceOverride,
        rawLine = rawLine,
        originalText = rawLine,
        content = content,
        displayText = displayText,
        targetIndicators = targetIndicators,
        modifiers = modifiers,
        visualBoards = visualBoards,
        primarySpellID = spellTokens[1] and spellTokens[1].spellID or nil,
        spellTokens = spellTokens,
        segments = segments,
        hasAudience = hasAudience,
        players = {},
        classes = {},
        roles = {},
        groups = {},
        triggered = false,
    }
end

function Syntax.ParseTimelineText(text)
    local events = {}
    if type(text) ~= "string" or text == "" then
        return events
    end

    local lineNum = 0
    for line in text:gmatch("[^\n]+") do
        lineNum = lineNum + 1
        local event = Syntax.ParseTimelineLine(line)
        if event then
            event.line = lineNum
            table.insert(events, event)
        end
    end

    table.sort(events, function(a, b)
        local at = tonumber(a.time) or 0
        local bt = tonumber(b.time) or 0
        if at ~= bt then return at < bt end
        return (a.line or 0) < (b.line or 0)
    end)

    return events
end

-- segment → 单元格数据（单一权威）：解析区与实时战术板共用。
local function IsAllAudienceCondition(text)
    local value = Trim(text or "")
    local lower = value:lower()
    return lower == "all" or lower == "everyone" or value == "所有人" or value == "全团"
end

local function StripAllAudienceConditions(condition)
    local src = Trim(condition or "")
    if src == "" then
        return ""
    end

    local kept = {}
    for term in (src .. ","):gmatch("([^,]*),") do
        local value = Trim(term)
        if value ~= "" and not IsAllAudienceCondition(value) then
            kept[#kept + 1] = value
        end
    end
    return table.concat(kept, ",")
end

local function BuildPersonalDisplayWho(segment)
    if type(segment) ~= "table" then
        return "", "player"
    end

    local condition = StripAllAudienceConditions(segment.condition or "")
    local players = type(segment.players) == "table" and segment.players or nil
    local playerText = ""
    if players and #players > 0 then
        playerText = table.concat(players, "/")
    end

    if condition ~= "" and playerText ~= "" then
        return string.format("%s/%s", condition, playerText), "condition"
    end
    if condition ~= "" then
        return condition, "condition"
    end
    if playerText ~= "" then
        return playerText, "player"
    end
    return "", "player"
end

function Syntax.BuildCellWho(segment)
    if type(segment) ~= "table" then
        return "", "player"
    end

    local condition = Trim(segment.condition or "")
    local players = type(segment.players) == "table" and segment.players or nil
    local playerText = ""
    if players and #players > 0 then
        playerText = table.concat(players, "/")
    end

    if condition ~= "" and playerText ~= "" then
        return string.format("%s/%s", condition, playerText), "condition"
    end
    if condition ~= "" then
        return condition, "condition"
    end
    if playerText ~= "" then
        return playerText, "player"
    end
    return "", "player"
end

function Syntax.BuildDisplayCell(segment, opts)
    local personalUntargeted = type(opts) == "table" and opts.personalUntargeted == true
    local who, whoType
    if personalUntargeted then
        who, whoType = BuildPersonalDisplayWho(segment)
    else
        who, whoType = Syntax.BuildCellWho(segment)
    end
    local actionText = Trim(segment and segment.cellText or "")
    local segmentSpellTokens = segment and segment.spellTokens
    local hasSpellToken = type(segmentSpellTokens) == "table" and #segmentSpellTokens > 0
    local spellHiddenActionText = hasSpellToken and BuildDisplayTextWithoutSpellTokens(segment and segment.rawText or "") or actionText
    if personalUntargeted and who == "" then
        actionText = Trim(actionText:gsub("^%s*%-%s*", ""))
        spellHiddenActionText = Trim(spellHiddenActionText:gsub("^%s*%-%s*", ""))
        if actionText ~= "" then
            who = "自己"
            whoType = "player"
        end
    end
    if who == "" or actionText == "" then
        return nil
    end

    local spellID = tonumber(segment and segment.primarySpellID) or nil
    local spellIcon = nil
    if spellID then
        spellIcon = Syntax.ResolveSpellIcon(spellID)
    end

    -- 扫描 actionText 找未转 token 的裸中文技能名。
    -- 守卫：segment.spellTokens 非空说明源 raw 已经有 {spell:ID}，actionText 里的
    -- 中文是 token 解析后的名字（不是玩家原文），不应再建议。
    -- 注：segment.text 是 PrepareSourceText 之后的结果（spell token 已解析），
    -- 不能扫它；spellTokens 是基于原始 text 提取的 metadata，可靠。
    local aliasSuggestions = nil
    if not hasSpellToken and T.SpellAliasScanner and T.SpellAliasScanner.Scan then
        local hits = T.SpellAliasScanner.Scan(actionText)
        if type(hits) == "table" and #hits > 0 then
            aliasSuggestions = hits
        end
    end

    return {
        who = who,
        whoType = whoType,
        actionText = actionText,
        spellHiddenActionText = spellHiddenActionText,
        spellID = spellID,
        spellIcon = spellIcon,
        fullText = actionText,
        aliasSuggestions = aliasSuggestions,
    }
end

end)
