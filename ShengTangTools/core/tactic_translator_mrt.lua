local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("tacticTranslator.enabled", function()

-- MRT 明文时间轴格式 adapter
-- 仅处理可直接复制的明文，不处理 MRTCDP1 编码字符串。

if not T.TacticTranslator then return end

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function IsMRTFormat(content)
    if type(content) ~= "string" then
        return false
    end
    local normalized = content:gsub("\r\n", "\n"):gsub("\r", "\n")
    local firstLine = Trim(normalized:match("^([^\n]*)") or "")
    if firstLine:match("^!TR:") then
        return false
    end
    if firstLine:match("^EncounterID:%d+") then
        return false
    end
    if firstLine:match("^MRTCDP1") then
        return false
    end
    if normalized:find("[方案]", 1, true) or normalized:find("[时间轴]", 1, true) then
        return false
    end
    if not normalized:find("{time:", 1, true) then
        return false
    end

    return normalized:match(",%s*pg%d+") ~= nil
        or normalized:match("{time:[^}]+}%s*%-") ~= nil
        or normalized:match(",%s*SCC:") ~= nil
        or normalized:match(",%s*SCS:") ~= nil
        or normalized:match(",%s*SAA:") ~= nil
        or normalized:match(",%s*SAR:") ~= nil
        or normalized:match(",%s*wa:") ~= nil
        or normalized:match(",%s*e%s*,") ~= nil
        or normalized:match(",%s*glow") ~= nil
        or normalized:match(",%s*all") ~= nil
        or normalized:match("{spell:%d+:%d+}") ~= nil
        or normalized:match("{self}") ~= nil
        or normalized:match("|c%x%x%x%x%x%x%x%x[^|]+|r") ~= nil
end

local function HasNextRoundFlag(def)
    if type(def) ~= "table" or type(def.anchors) ~= "table" then
        return false
    end
    for _, rules in pairs(def.anchors) do
        if type(rules) == "table" then
            for _, rule in ipairs(rules) do
                if type(rule) == "table" and rule.nextRound then
                    return true
                end
            end
        end
    end
    return false
end

local function GetBossPhaseExpansion(encounterID)
    local id = tonumber(encounterID) or 0
    if id <= 0 then
        return { mode = "naive" }
    end

    local def = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[id]
    if type(def) ~= "table" then
        return { mode = "naive" }
    end
    if HasNextRoundFlag(def) then
        return { mode = "rotation" }
    end
    return {
        mode = "linear",
        phaseOrder = def.phaseOrder,
    }
end

local function ResolvePgN(pgIndex, expansion)
    local index = tonumber(pgIndex)
    if not index or index <= 0 then
        return nil
    end

    local exp = type(expansion) == "table" and expansion or { mode = "naive" }
    if exp.mode == "rotation" then
        if index % 2 == 1 then
            return string.format("p1r%d", (index + 1) / 2)
        end
        return string.format("p2r%d", index / 2)
    end
    if exp.mode == "linear" and type(exp.phaseOrder) == "table" and exp.phaseOrder[index] then
        return exp.phaseOrder[index]
    end
    return "p" .. tostring(index)
end

local function IsNativePhaseSegment(seg)
    return seg:match("^[pi]%d+$") ~= nil or seg:match("^[pi]%d+r%d+$") ~= nil
end

local function IsAdvanceSegment(seg)
    return seg:match("^%-%d+%.?%d*$") ~= nil
end

local function IsUnsupportedSegment(seg)
    if seg == "glow" or seg == "glowall" or seg == "all" or seg == "e" then
        return true
    end
    if seg:match("^SCC:") or seg:match("^SCS:") or seg:match("^SAA:") or seg:match("^SAR:") then
        return true
    end
    if seg:match("^wa:") then
        return true
    end
    return false
end

local function TransformTimeBlock(timeBody, expansion)
    local segs = {}
    for seg in tostring(timeBody or ""):gmatch("[^,]+") do
        local trimmed = Trim(seg)
        if trimmed ~= "" then
            segs[#segs + 1] = trimmed
        end
    end
    if #segs == 0 then
        return Trim(timeBody)
    end

    local keep = { segs[1] }
    for i = 2, #segs do
        local seg = segs[i]
        local pgN = seg:match("^pg(%d+)$")
        if pgN then
            local resolved = ResolvePgN(tonumber(pgN), expansion)
            if resolved then
                keep[#keep + 1] = resolved
            end
        elseif IsNativePhaseSegment(seg) or IsAdvanceSegment(seg) then
            keep[#keep + 1] = seg
        elseif IsUnsupportedSegment(seg) then
            -- 静默丢弃 STT 时间轴不支持的 MRT 段。
        else
            -- 未识别段不进入结果，避免下游 parser 拒绝整行。
        end
    end
    return table.concat(keep, ",")
end

local function IsHexChar(ch)
    if not ch or ch == "" then
        return false
    end
    return (ch >= "0" and ch <= "9")
        or (ch >= "a" and ch <= "f")
        or (ch >= "A" and ch <= "F")
end

local function IsColorCodeAt(source, pos)
    if source:sub(pos, pos + 1) ~= "|c" then
        return false
    end
    for i = pos + 2, pos + 9 do
        if not IsHexChar(source:sub(i, i)) then
            return false
        end
    end
    return true
end

local function ConvertColoredAudienceTokens(line)
    local source = tostring(line or "")
    local parts = {}
    local pos = 1

    while true do
        local startPos = source:find("|c", pos, true)
        if not startPos then
            parts[#parts + 1] = source:sub(pos)
            break
        end

        parts[#parts + 1] = source:sub(pos, startPos - 1)
        if not IsColorCodeAt(source, startPos) then
            parts[#parts + 1] = source:sub(startPos, startPos)
            pos = startPos + 1
        else
            local resetStart, resetEnd = source:find("|r", startPos + 10, true)
            if not resetStart then
                parts[#parts + 1] = source:sub(startPos)
                break
            end

            local alreadyWrapped = source:sub(startPos - 1, startPos - 1) == "{"
                and source:sub(resetEnd + 1, resetEnd + 1) == "}"
            if alreadyWrapped and parts[#parts] then
                parts[#parts] = parts[#parts]:sub(1, -2)
            end

            local playerName = Trim(source:sub(startPos + 10, resetStart - 1))
            if playerName ~= "" then
                parts[#parts + 1] = "{" .. playerName .. "}"
            else
                parts[#parts + 1] = source:sub(startPos, resetEnd)
            end

            pos = resetEnd + (alreadyWrapped and 2 or 1)
        end
    end

    local result = table.concat(parts)
    result = result:gsub("|{([^{}|]-)%s*|r}", "{%1}")
    result = result:gsub("|{([^{}|]-)%s*|}", "{%1}")
    result = result:gsub("{%s*([^{}|]-)%s*}", "{%1}")
    return result
end

local function IsAudienceToken(token)
    local value = Trim(token)
    if value == "" then
        return false
    end
    if value:match("^spell:%d+") then
        return false
    end
    if value:match("^rt:?%d*$") then
        return false
    end
    if value:match("^icon:") then
        return false
    end
    if value:match("^to:") then
        return false
    end
    if value:match("^sr:") or value:match("^ct:") or value:match("^dur:") then
        return false
    end
    if value:match("^@") then
        return false
    end
    return true
end

local function StartsWithAudienceToken(text)
    local token = Trim(text):match("^{([^}]+)}")
    return token ~= nil and IsAudienceToken(token)
end

local function ConvertSpellTrailingTextToNotes(line)
    local source = tostring(line or "")
    local parts = {}
    local pos = 1

    while true do
        local startPos, endPos, spellToken = source:find("({spell:%d+})", pos)
        if not startPos then
            parts[#parts + 1] = source:sub(pos)
            break
        end

        parts[#parts + 1] = source:sub(pos, startPos - 1)
        parts[#parts + 1] = spellToken

        local nextTokenStart = source:find("{", endPos + 1, true)
        local textEnd = nextTokenStart and (nextTokenStart - 1) or #source
        local trailingText = Trim(source:sub(endPos + 1, textEnd))
        if trailingText ~= "" then
            if trailingText:match("^<.*>$") then
                parts[#parts + 1] = trailingText
            else
                parts[#parts + 1] = "<" .. trailingText .. ">"
            end
            if nextTokenStart then
                parts[#parts + 1] = " "
            end
        end

        pos = textEnd + 1
    end

    return table.concat(parts)
end

local function StripUnsupportedTokens(line)
    local result = tostring(line or "")
    result = result:gsub("{spell:(%d+):%d+}", "{spell:%1}")
    result = result:gsub("%s*{self}%s*", " ")
    result = result:gsub("%s+", " ")
    return result
end

local function EnsureAudience(line)
    local timePart, rest = line:match("^(%s*{time:[^}]+})%s*(.*)$")
    if not timePart then
        return line
    end
    if StartsWithAudienceToken(rest) then
        return timePart .. " " .. rest
    end
    if rest == "" then
        return timePart .. " {所有人}"
    end
    return timePart .. " {所有人}" .. rest
end

local CLASS_TARGETS = {
    WARRIOR = "warrior",
    PALADIN = "paladin",
    HUNTER = "hunter",
    ROGUE = "rogue",
    PRIEST = "priest",
    DEATHKNIGHT = "deathknight",
    SHAMAN = "shaman",
    MAGE = "mage",
    WARLOCK = "warlock",
    MONK = "monk",
    DRUID = "druid",
    DEMONHUNTER = "demonhunter",
    EVOKER = "evoker",
}

local ROLE_TARGETS = {
    TANK = "tank",
    HEALER = "healer",
    DAMAGER = "dps",
    DPS = "dps",
}

local SPEC_TARGETS = {
    WARRIOR = { "arms", "fury", "protection+warrior" },
    PALADIN = { "holy+paladin", "protection+paladin", "retribution" },
    HUNTER = { "beast mastery", "marksmanship", "survival" },
    ROGUE = { "assassination", "outlaw", "subtlety" },
    PRIEST = { "discipline", "holy+priest", "shadow" },
    DEATHKNIGHT = { "blood", "frost+deathknight", "unholy" },
    SHAMAN = { "elemental", "enhancement", "restoration+shaman" },
    MAGE = { "arcane", "fire", "frost+mage" },
    WARLOCK = { "affliction", "demonology", "destruction" },
    MONK = { "brewmaster", "mistweaver", "windwalker" },
    DRUID = { "balance", "feral", "guardian", "restoration+druid" },
    DEMONHUNTER = { "havoc", "vengeance" },
    EVOKER = { "devastation", "preservation", "augmentation" },
}

local function NormalizeDashTarget(rawTarget)
    local target = Trim(rawTarget)
    if target == "" then
        return nil
    end

    local braceValue = target:match("^{([^}]+)}$")
    if braceValue then
        local lower = braceValue:lower()
        if lower == "everyone" or braceValue == "所有人" or braceValue == "全团" then
            return "所有人"
        end
        return braceValue
    end

    local lowerTarget = target:lower()
    if lowerTarget == "everyone" then
        return "所有人"
    end

    local role = target:match("^role:([%a_]+)$")
    if role then
        return ROLE_TARGETS[role:upper()]
    end

    local class = target:match("^class:([%a_]+)$")
    if class then
        return CLASS_TARGETS[class:upper()]
    end

    local specClass, specIndex = target:match("^spec:([%a_]+):(%d+)$")
    if specClass and specIndex then
        local specs = SPEC_TARGETS[specClass:upper()]
        return specs and specs[tonumber(specIndex)]
    end

    return target
end

local function ConsumeDashTarget(source, pos, allowPlain)
    local len = #source
    local i = pos
    while i <= len and source:sub(i, i):match("%s") do
        i = i + 1
    end
    if i > len then
        return nil
    end

    local braceEnd = source:find("}", i, true)
    if source:sub(i, i) == "{" and braceEnd then
        local raw = source:sub(i, braceEnd)
        if raw:match("^{everyone}$") or raw:match("^{所有人}$") or raw:match("^{全团}$") then
            return raw, braceEnd + 1
        end
        return nil
    end

    local token, tokenEnd = source:match("^([^%s]+)()", i)
    if not token or token == "" then
        return nil
    end
    if token:match("^role:[%a_]+$") or token:match("^class:[%a_]+$") or token:match("^spec:[%a_]+:%d+$") then
        return token, tokenEnd
    end
    if allowPlain and not token:find(":", 1, true) and not token:match("^%b{}$") then
        return token, tokenEnd
    end
    return nil
end

local function StartsPayloadAt(source, pos)
    local i = pos
    while i <= #source and source:sub(i, i):match("%s") do
        i = i + 1
    end
    return source:sub(i, i + 6) == "{spell:"
        or source:sub(i, i + 5) == "{text}"
end

local function FindNextDashTarget(source, pos)
    local searchPos = pos
    while searchPos <= #source do
        local spaceStart = source:find("%s", searchPos)
        if not spaceStart then
            return nil
        end
        local rawTarget, afterTarget = ConsumeDashTarget(source, spaceStart + 1, true)
        if rawTarget and StartsPayloadAt(source, afterTarget) then
            return spaceStart + 1
        end
        searchPos = spaceStart + 1
    end
    return nil
end

local function ConvertTextTags(line)
    local result = tostring(line or "")
    result = result:gsub("{text}(.-){/text}", "%1")
    return result
end

local function TransformDashAssignmentBody(rawBody)
    local source = ConvertColoredAudienceTokens(StripUnsupportedTokens(rawBody or ""))
    source = ConvertTextTags(source)

    local parts = {}
    local pos = 1
    while pos <= #source do
        local rawTarget, afterTarget = ConsumeDashTarget(source, pos, true)
        if not rawTarget then
            local rest = Trim(source:sub(pos))
            if rest ~= "" then
                parts[#parts + 1] = "{所有人}" .. rest
            end
            break
        end

        local nextTarget = FindNextDashTarget(source, afterTarget)
        local payloadEnd = nextTarget and (nextTarget - 1) or #source
        local payload = Trim(source:sub(afterTarget, payloadEnd))
        local target = NormalizeDashTarget(rawTarget)
        if target and payload ~= "" then
            parts[#parts + 1] = "{" .. target .. "} " .. payload
        elseif payload ~= "" then
            parts[#parts + 1] = "{所有人}" .. payload
        end

        if not nextTarget then
            break
        end
        pos = nextTarget
    end

    local body = table.concat(parts, " ")
    body = ConvertSpellTrailingTextToNotes(body)
    body = body:gsub("}({[^}]+})", "} %1")
    body = body:gsub("%s+", " ")
    return body
end

local function TransformDashAssignmentLine(timeBody, body, expansion)
    local assignment = body:match("^%s*%-%s*(.*)$")
    if assignment == nil then
        return nil
    end
    local line = "{time:" .. TransformTimeBlock(timeBody, expansion) .. "}"
    local newBody = TransformDashAssignmentBody(assignment)
    if newBody == "" then
        return EnsureAudience(line)
    end
    return line .. " " .. newBody
end

local function TransformLine(rawLine, expansion)
    local trimmed = Trim(rawLine)
    if trimmed == "" or not trimmed:match("^{time:") then
        return nil
    end

    local timeBody, body = trimmed:match("^{time:([^}]+)}(.*)$")
    if not timeBody then
        return nil
    end

    if body:match("^%s*%-") then
        return TransformDashAssignmentLine(timeBody, body, expansion)
    end

    body = StripUnsupportedTokens(body)
    body = ConvertColoredAudienceTokens(body)
    body = ConvertSpellTrailingTextToNotes(body)

    local line = "{time:" .. TransformTimeBlock(timeBody, expansion) .. "}"
    return EnsureAudience(line .. body)
end

local function Parse(text)
    local result = {
        lines = {},
        totalLines = 0,
        skipped = 0,
        phaseCount = 0,
        encounterID = tonumber(C and C.DB and C.DB.tacticTranslatorMRTBoss) or 0,
    }
    if type(text) ~= "string" or text == "" then
        return result
    end

    local expansion = GetBossPhaseExpansion(result.encounterID)
    local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local phaseSet = {}
    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        local transformed = TransformLine(line, expansion)
        if transformed then
            result.lines[#result.lines + 1] = transformed
            result.totalLines = result.totalLines + 1
            local payload = transformed:match("{time:([^}]+)}")
            for seg in tostring(payload or ""):gmatch("[^,]+") do
                local phaseTag = Trim(seg)
                if IsNativePhaseSegment(phaseTag) then
                    phaseSet[phaseTag] = true
                end
            end
        elseif Trim(line) ~= "" then
            result.skipped = result.skipped + 1
        end
    end
    for _ in pairs(phaseSet) do
        result.phaseCount = result.phaseCount + 1
    end
    return result
end

local function Format(parsed)
    if type(parsed) ~= "table" then
        return { stn = "", eventCount = 0, phaseCount = 0, skipped = 0, totalLines = 0 }
    end

    local lines = {
        "[方案]",
        "名称 = MRT 导入",
        "作者 = MRT 导入",
        "",
        "[时间轴]",
    }
    local encounterID = tonumber(parsed.encounterID) or 0
    if encounterID > 0 then
        lines[#lines + 1] = "-- EncounterID: " .. tostring(encounterID)
    end
    for _, line in ipairs(parsed.lines or {}) do
        lines[#lines + 1] = line
    end

    return {
        stn = table.concat(lines, "\n"),
        eventCount = #(parsed.lines or {}),
        phaseCount = parsed.phaseCount or 0,
        skipped = parsed.skipped or 0,
        totalLines = parsed.totalLines or 0,
        encounterID = encounterID,
    }
end

T.TacticTranslator:Register({
    id        = "mrt",
    name      = "MRT (Method Raid Tools)",
    nameKey   = "TACTIC_TRANSLATOR_MRT_NAME",
    sampleKey = "TACTIC_TRANSLATOR_MRT_SAMPLE",
    sample    = "{time:0:14} 集合 |cff33937f玩家|r {spell:370553}",
    detect    = IsMRTFormat,
    parse     = Parse,
    format    = Format,
})

end)
