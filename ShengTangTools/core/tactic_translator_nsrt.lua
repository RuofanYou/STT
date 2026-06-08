local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("tacticTranslator.enabled", function()

-- NSRT (NorthernSkyRaidTools) 格式 adapter
-- 通过 T.TacticTranslator:Register 注册到通用翻译器注册表

if not T.TacticTranslator then return end

local floor = math.floor

local function FormatTime(seconds)
    local s = tonumber(seconds) or 0
    if s < 0 then s = 0 end
    local m = floor(s / 60)
    local r = floor(s % 60)
    return string.format("%02d:%02d", m, r)
end

local TAG_ALIAS = {
    everyone = "所有人",
    all      = "所有人",
    group1   = "g1",
    group2   = "g2",
    group3   = "g3",
    group4   = "g4",
    group5   = "g5",
    group6   = "g6",
    group7   = "g7",
    group8   = "g8",
}

local function NormalizeTagToken(token)
    if not token or token == "" then return nil end
    local lower = string.lower(token)
    return TAG_ALIAS[lower] or token
end

local function ParseTagList(tagRaw)
    local tokens = {}
    if not tagRaw then return tokens end
    for token in string.gmatch(tagRaw, "[^%s,]+") do
        local norm = NormalizeTagToken(token)
        if norm then
            tokens[#tokens + 1] = norm
        end
    end
    return tokens
end

local function BuildAudience(tokens)
    if not tokens or #tokens == 0 then
        return "{所有人}"
    end
    return "{" .. table.concat(tokens, ",") .. "}"
end

local function ResolvePhaseTag(encounterID, phase)
    local normalizedPhase = tonumber(phase)
    if not normalizedPhase or normalizedPhase <= 0 then
        return nil
    end

    if tonumber(encounterID) == 3183 then
        local phaseIndex = floor(normalizedPhase)
        if phaseIndex ~= normalizedPhase then
            return nil
        end
        local phaseMap = { "p1", "i1", "p2", "p3", "p4" }
        return phaseMap[phaseIndex]
    end

    if tonumber(encounterID) == 3182 then
        local phaseIndex = floor(normalizedPhase)
        if phaseIndex ~= normalizedPhase then
            return nil
        end
        local basePhase = (phaseIndex % 2 == 1) and "p1" or "p2"
        local roundIndex = floor((phaseIndex + 1) / 2)
        return string.format("%sr%d", basePhase, roundIndex)
    end

    return "p" .. tostring(normalizedPhase)
end

local function StripTrailingSemicolon(value)
    if not value then return nil end
    local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil end
    return trimmed
end

local function ParseHeaderLine(line)
    if not line:find("EncounterID:", 1, true) then return nil end
    return {
        encounterID = tonumber(line:match("EncounterID:(%d+)")),
        difficulty  = StripTrailingSemicolon(line:match("Difficulty:([^;]+)")),
        name        = StripTrailingSemicolon(line:match("Name:([^;]+)")),
    }
end

local function IsNSRTFormat(content)
    if type(content) ~= "string" then
        return false
    end

    local normalized = content:gsub("\r\n", "\n"):gsub("\r", "\n")
    local firstLine = normalized:match("^([^\n]*)") or ""
    firstLine = firstLine:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return firstLine:match("EncounterID:%d+") ~= nil
end

local function ParseEventLine(line)
    local time    = line:match("time:(%d*%.?%d+)")
    local tag     = line:match("tag:([^;]+)")
    local spellID = line:match("spellid:(%d+)")
    local text    = line:match("text:([^;]+)")
    local phase   = line:match("ph:(%d+)")

    if not time then return nil end
    if not tag then return nil end
    if not (spellID or text) then return nil end

    return {
        time    = tonumber(time),
        tag     = StripTrailingSemicolon(tag),
        spellID = spellID and tonumber(spellID) or nil,
        text    = StripTrailingSemicolon(text),
        phase   = tonumber(phase) or 1,
    }
end

local function BuildTimelineLine(event, encounterID)
    local timeStr = FormatTime(event.time)
    local phasePart = ""
    local phaseTag = ResolvePhaseTag(encounterID, event.phase)
    if phaseTag then
        phasePart = "," .. phaseTag
    end

    local tokens = ParseTagList(event.tag)
    local audience = BuildAudience(tokens)

    local body = ""
    if event.text and event.text ~= "" then
        body = event.text
        if event.spellID then
            body = body .. "{spell:" .. tostring(event.spellID) .. "}"
        end
    elseif event.spellID then
        body = "{spell:" .. tostring(event.spellID) .. "}"
    end

    return string.format("{time:%s%s} %s%s", timeStr, phasePart, audience, body)
end

-- NSRT 单行模式：整段是一长串 `;`-分隔字段，没有 \n
-- 切分规则：每个事件以 `time:N` 字段为锚点；两个相邻 `time:` 之间的字段属于同一个事件
-- header 字段（EncounterID/Difficulty/Name）出现在第一个 `time:` 之前
local function ParseSingleLineText(text, result)
    result.header = ParseHeaderLine(text)

    local positions = {}
    local searchFrom = 1
    while true do
        local s, e = text:find("time:%d", searchFrom)
        if not s then break end
        positions[#positions + 1] = s
        searchFrom = e + 1
    end

    if #positions == 0 then
        return result
    end

    for i, startPos in ipairs(positions) do
        local endPos = positions[i + 1] and positions[i + 1] - 1 or #text
        local chunk = text:sub(startPos, endPos)
        result.totalLines = result.totalLines + 1
        local event = ParseEventLine(chunk)
        if event then
            result.events[#result.events + 1] = event
        else
            result.skipped = result.skipped + 1
        end
    end

    return result
end

local function Parse(text)
    local result = {
        header     = nil,
        events     = {},
        skipped    = 0,
        totalLines = 0,
    }

    if type(text) ~= "string" or text == "" then
        return result
    end

    local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- 数一下 \n：若整段没有换行符，走单行 ;-分隔模式（NSRT 的紧凑导出格式）
    local hasNewline = normalized:find("\n", 1, true) ~= nil
    if not hasNewline then
        return ParseSingleLineText(normalized, result)
    end

    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            result.totalLines = result.totalLines + 1

            local header = ParseHeaderLine(trimmed)
            if header then
                result.header = header
            else
                local event = ParseEventLine(trimmed)
                if event then
                    result.events[#result.events + 1] = event
                else
                    result.skipped = result.skipped + 1
                end
            end
        end
    end

    return result
end

local function Format(parsed)
    if type(parsed) ~= "table" then
        return { stn = "", eventCount = 0, phaseCount = 0, skipped = 0, totalLines = 0 }
    end

    local header = parsed.header
    local events = parsed.events or {}

    local lines = {}

    lines[#lines + 1] = "[方案]"
    local planName = "NSRT 导入"
    if header and header.name and header.name ~= "" then
        planName = header.name
        if header.difficulty and header.difficulty ~= "" then
            planName = planName .. " (" .. header.difficulty .. ")"
        end
    end
    lines[#lines + 1] = "名称 = " .. planName
    lines[#lines + 1] = "作者 = NSRT 导入"
    lines[#lines + 1] = ""

    lines[#lines + 1] = "[时间轴]"
    if header and header.encounterID then
        lines[#lines + 1] = "-- EncounterID: " .. tostring(header.encounterID)
    end

    local encounterID = header and header.encounterID or nil
    for _, event in ipairs(events) do
        lines[#lines + 1] = BuildTimelineLine(event, encounterID)
    end

    local phaseSet = {}
    for _, event in ipairs(events) do
        phaseSet[event.phase] = true
    end
    local phaseCount = 0
    for _ in pairs(phaseSet) do
        phaseCount = phaseCount + 1
    end

    return {
        stn         = table.concat(lines, "\n"),
        eventCount  = #events,
        phaseCount  = phaseCount,
        skipped     = parsed.skipped or 0,
        totalLines  = parsed.totalLines or 0,
        header      = header,
    }
end

T.TacticTranslator:Register({
    id       = "nsrt",
    name     = "NSRT (NorthernSkyRaidTools)",
    nameKey  = "TACTIC_TRANSLATOR_NSRT_NAME",
    sampleKey = "TACTIC_TRANSLATOR_NSRT_SAMPLE",
    sample   = "EncounterID:3178;Difficulty:Heroic;Name:Vaelgor & Ezzorak;\nph:1;time:19.9;tag:瑟瑟;spellid:322118;\nph:1;time:35.8;tag:瑟瑟;spellid:115310;",
    detect   = IsNSRTFormat,
    parse    = Parse,
    format   = Format,
})

end)
