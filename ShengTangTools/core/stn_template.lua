local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

-- STN 结构化模板预处理（单一权威）
-- 目标：
-- 1) 识别 [方案] / [人员] / [设置] / [时间轴]/[触发轴] 中文分段；
-- 2) 校验基础格式错误；
-- 3) 将 {{槽位}} 转换为现有解析链可识别的 {玩家名} token；
-- 4) 保留原模板文本，运行时只消费预处理后的正文。
local Template = {}
T.STNTemplate = Template

local SECTION_PLAN = "方案"
local SECTION_SLOTS = "人员"
local SECTION_SETTINGS = "设置"
local SECTION_TIMELINE = "时间轴"
local SECTION_TRIGGER = "触发轴"
local SECTION_INTERRUPT = "打断"
local SECTION_SLOT_ICONS = "人员图标"

local KNOWN_SECTIONS = {
    [SECTION_PLAN] = true,
    [SECTION_SLOTS] = true,
    [SECTION_SETTINGS] = true,
    [SECTION_TIMELINE] = true,
    [SECTION_TRIGGER] = true,
    [SECTION_INTERRUPT] = true,
    [SECTION_SLOT_ICONS] = true,
}

local BODY_SECTION_KIND = {
    [SECTION_TIMELINE] = "timeline",
    [SECTION_TRIGGER] = "trigger",
}

local function Trim(text)
    if type(text) ~= "string" then
        return ""
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

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

local function StripColorCodes(text)
    if type(text) ~= "string" then
        return ""
    end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function UnquoteValue(text)
    local value = Trim(text)
    if value:match('^".*"$') or value:match("^'.*'$") then
        value = value:sub(2, -2)
    end
    return value
end

local function NormalizePlayerName(text)
    local value = Trim(UnquoteValue(text))
    value = StripColorCodes(value)
    return Trim(value)
end

local function NormalizeSlotValue(text)
    local value = Trim(UnquoteValue(text))
    value = StripColorCodes(value)
    value = value:gsub("，", ",")

    local names = {}
    for part in value:gmatch("[^,]+") do
        local name = Trim(part)
        if name ~= "" then
            names[#names + 1] = name
        end
    end
    return table.concat(names, ",")
end

Template.Trim = Trim
Template.StripColorCodes = StripColorCodes
Template.NormalizePlayerName = NormalizePlayerName

local function BuildUserDiagnostic(reason, content)
    local rawReason = tostring(reason or "")
    local rawContent = tostring(content or "")
    local sectionName = rawContent:match("^%s*(%[[^%]]+%])%s*$")
    local key = rawContent:match("^%s*([^=]+)%s*=")
    key = key and Trim(key) or ""

    if rawReason:find("技能 token 未闭合", 1, true) then
        local token = rawContent:match("({spell:%d+[^}%s]*)")
        return "缺少 }", token and ("把 " .. token .. " 改成 " .. token .. "}") or "把技能标记写成 {spell:740}。"
    end
    if rawReason:find("时间 token 未闭合", 1, true) then
        local token = rawContent:match("({time:[^}%s]*)")
        return "缺少 }", token and ("把 " .. token .. " 改成 " .. token .. "}") or "把时间标记写成 {time:00:12}。"
    end
    if rawReason:find("token 未闭合", 1, true) then
        return "缺少 }", "检查这一行的 {...}，把缺少的 } 补上。"
    end
    if rawReason:find("多余的右花括号", 1, true) then
        return "多了 }", "删除多余的 }，或补上对应的 {。"
    end
    if rawReason:find("技能 token 格式无效", 1, true) then
        return "技能标记格式不对", "写成 {spell:740} 这样的格式。"
    end
    if rawReason == (L["模板块重复"] or "模板块重复") then
        local label = sectionName or "这个段落"
        return label .. " 重复了", "一个方案只保留一个 " .. label .. "，把内容合并到同一段。"
    end
    if rawReason == (L["模板块无效"] or "模板块无效") then
        return (sectionName or "这个段落") .. " 不能识别", "使用 [人员]、[时间轴] 或 [触发轴] 这类支持的段落名。"
    end
    if rawReason == (L["模板块外存在内容"] or "模板块外存在内容") then
        return "这行不在任何段落里", "放到 [时间轴] 下面，或删除这行。"
    end
    if rawReason == (L["模板键值格式无效"] or "模板键值格式无效") then
        return "这一行格式不对", "在这个段落里写成 名字 = 内容。"
    end
    if rawReason == (L["模板键重复"] or "模板键重复") then
        local label = key ~= "" and key or "这个名字"
        return label .. " 重复了", "只保留一个 " .. label .. "，或合并内容。"
    end
    if rawReason == (L["人员槽位重复"] or "人员槽位重复") then
        local label = key ~= "" and key or "这个人员槽位"
        return label .. " 重复了", "只保留一个 " .. label .. "，或合并内容。"
    end
    if rawReason == (L["人员槽位不能为空"] or "人员槽位不能为空") then
        return "人员槽位没有填写名字", "在 = 后面填玩家名，例如 DK1 = 玩家名。"
    end
    if rawReason == (L["正文块冲突"] or "正文块冲突") then
        return "[时间轴] 和 [触发轴] 不能同时使用", "保留其中一种正文段落。"
    end
    if rawReason == (L["缺少正文块"] or "缺少正文块") then
        return "缺少 [时间轴]", "添加 [时间轴]，把要播报的行放在下面。"
    end
    if rawReason == (L["仅支持结构化模板"] or "仅支持结构化模板") then
        return "没有找到时间轴内容", "每行以 {time:00:12} 开头，或使用 [时间轴] 段落。"
    end

    return rawReason ~= "" and rawReason or "这一行无法解析", "检查这一行的格式，按战术方案语法改写。"
end

local function PushError(info, line, reason, content, fatal)
    local message, fix = BuildUserDiagnostic(reason, content)
    info.errors[#info.errors + 1] = {
        line = tonumber(line) or 0,
        reason = tostring(reason or ""),
        content = tostring(content or ""),
        fatal = fatal == true,
        message = message,
        fix = fix,
        severity = "error",
    }
end

local function PushSettingsError(info, line, reason, content)
    local message, fix = BuildUserDiagnostic(reason, content)
    info.settingsErrors[#info.settingsErrors + 1] = {
        line = tonumber(line) or 0,
        reason = tostring(reason or ""),
        content = tostring(content or ""),
        message = message,
        fix = fix,
        severity = "error",
    }
end

local function CountMapKeys(map)
    local count = 0
    for _ in pairs(map or {}) do
        count = count + 1
    end
    return count
end

local function HasFatalErrors(info)
    for _, err in ipairs(info and info.errors or {}) do
        if err and err.fatal == true then
            return true
        end
    end
    return false
end

Template.HasFatalErrors = HasFatalErrors

local function PushTokenError(info, lineNumber, reason, content)
    PushError(info, lineNumber, reason, content, true)
end

local function ValidateTokenIntegrity(info, lineNumber, line)
    local text = tostring(line or ""):gsub("｛", "{"):gsub("｝", "}")
    if Trim(text) == "" then
        return
    end

    local pos = 1
    while pos <= #text do
        local openPos = text:find("{", pos, true)
        local closePos = text:find("}", pos, true)
        if closePos and (not openPos or closePos < openPos) then
            PushTokenError(info, lineNumber, "多余的右花括号，请检查 {...} 是否成对", line)
            return
        end
        if not openPos then
            return
        end

        closePos = text:find("}", openPos + 1, true)
        local nextOpenPos = text:find("{", openPos + 1, true)
        if not closePos or (nextOpenPos and nextOpenPos < closePos) then
            local fragment = text:sub(openPos, math.min(#text, openPos + 40))
            if fragment:match("^%{spell:%d+") then
                PushTokenError(info, lineNumber, "技能 token 未闭合，请写成 {spell:技能ID}", line)
            elseif fragment:match("^%{time:") then
                PushTokenError(info, lineNumber, "时间 token 未闭合，请写成 {time:分:秒}", line)
            else
                PushTokenError(info, lineNumber, "token 未闭合，请检查 {...} 是否成对", line)
            end
            return
        end

        local token = text:sub(openPos, closePos)
        if token:match("^%{spell:") and not token:match("^%{spell:%d+[^}]*%}$") then
            PushTokenError(info, lineNumber, "技能 token 格式无效，请写成 {spell:技能ID}", line)
            return
        end
        pos = closePos + 1
    end
end

local function ValidateBodyTokenIntegrity(info, bodyLines, lineNumbers)
    for index, line in ipairs(bodyLines or {}) do
        ValidateTokenIntegrity(info, tonumber(lineNumbers and lineNumbers[index]) or index, line)
    end
end

local function SplitLines(raw)
    local lines = {}
    local normalized = tostring(raw or ""):gsub("\r\n", "\n")
    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    return normalized, lines
end

local function DetectStructuredBlocks(lines)
    for _, line in ipairs(lines or {}) do
        local section = Trim(line):match("^%[([^%]]+)%]$")
        if section then
            return true
        end
    end
    return false
end

local function EnsureSection(info, name, headerLine)
    local section = info.sections[name]
    if not section then
        section = {
            name = name,
            headerLine = tonumber(headerLine) or 0,
            lines = {},
            lineNumbers = {},
            lastLine = tonumber(headerLine) or 0,
        }
        info.sections[name] = section
    end
    return section
end

local function FinalizeSectionRanges(info)
    local rawLineCount = #info.rawLines
    local ordered = {}
    for _, name in ipairs({ SECTION_PLAN, SECTION_SLOTS, SECTION_SLOT_ICONS, SECTION_SETTINGS, SECTION_TIMELINE, SECTION_TRIGGER, SECTION_INTERRUPT }) do
        local section = info.sections[name]
        if section then
            ordered[#ordered + 1] = section
        end
    end

    table.sort(ordered, function(a, b)
        return (tonumber(a.headerLine) or 0) < (tonumber(b.headerLine) or 0)
    end)

    for index, section in ipairs(ordered) do
        local nextSection = ordered[index + 1]
        local nextHeaderLine = nextSection and nextSection.headerLine or (rawLineCount + 1)
        if #section.lineNumbers > 0 then
            section.lastLine = section.lineNumbers[#section.lineNumbers]
        else
            section.lastLine = nextHeaderLine - 1
        end
    end
end

local function NormalizeRelaxedBodyText(text)
    local lines = {}
    local normalized = tostring(text or ""):gsub("\r\n", "\n")
    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        local processed = tostring(line or ""):gsub("{{(.-)}}", function(rawSlot)
            local slotName = Trim(rawSlot)
            return "{" .. slotName .. "}"
        end)
        lines[#lines + 1] = processed
    end
    return table.concat(lines, "\n")
end

local function HasTimelineBodyText(text)
    local normalized = tostring(text or ""):gsub("\r\n", "\n")
    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        if Trim(line):find("{time:", 1, true) then
            return true
        end
    end
    return false
end

local function NormalizeRosterName(text)
    local value = NormalizePlayerName(text)
    if value ~= "" and Ambiguate then
        local short = Ambiguate(value, "short")
        if short and short ~= "" then
            value = short
        end
    end
    return value
end

local function IsPlayerInCurrentGroup(name)
    local target = NormalizeRosterName(name)
    if target == "" then
        return false
    end

    local myName = NormalizeRosterName(UnitName and UnitName("player") or "")
    if myName ~= "" and myName == target then
        return true
    end

    if not GetNumGroupMembers or not GetRaidRosterInfo then
        return false
    end

    local groupCount = tonumber(GetNumGroupMembers()) or 0
    for index = 1, groupCount do
        local rosterName = NormalizeRosterName(GetRaidRosterInfo(index))
        if rosterName ~= "" and rosterName == target then
            return true
        end
    end
    return false
end

Template.IsPlayerInCurrentGroup = IsPlayerInCurrentGroup

local function ResolveSlotAtRuntime(slotValue)
    local normalized = NormalizeSlotValue(slotValue)

    -- 含内部空格 = 全员匹配语义:列出的所有玩家都听到事件,返回名字数组
    -- 与逗号 fallback(顺序找在场第一个)对偶,跟 [打断] 段空格分隔写法保持一致
    if normalized:find("%s") then
        local names = {}
        for part in normalized:gmatch("%S+") do
            local name = Trim(part)
            if name ~= "" then
                names[#names + 1] = name
            end
        end
        if #names > 1 then
            return names
        end
        if #names == 1 then
            return names[1]
        end
    end

    local names = {}
    for part in normalized:gmatch("[^,]+") do
        local name = Trim(part)
        if name ~= "" then
            names[#names + 1] = name
        end
    end

    for _, name in ipairs(names) do
        if IsPlayerInCurrentGroup(name) then
            return name
        end
    end

    return names[1] or normalized
end

Template.ResolveSlotAtRuntime = ResolveSlotAtRuntime

local function ResolveSlotToken(info, originalLine, rawToken, lineText, strictSlot)
    local slotName = Trim(rawToken)
    if slotName == "" then
        if strictSlot then
            PushError(info, originalLine, L["槽位名不能为空"] or "槽位名不能为空", lineText)
            return "{__STN_EMPTY_SLOT__}"
        end
        return "{}"
    end

    local slotValue = info.slots[slotName]
    if slotValue and slotValue ~= "" then
        info.usedSlots[slotName] = true
        local resolved = ResolveSlotAtRuntime(slotValue)
        if type(resolved) == "table" then
            if #resolved > 0 then
                local parts = {}
                for _, name in ipairs(resolved) do
                    parts[#parts + 1] = "{" .. name .. "}"
                end
                return table.concat(parts)
            end
        elseif type(resolved) == "string" and resolved ~= "" then
            return "{" .. resolved .. "}"
        end
    end

    if strictSlot then
        info.missingSlots[slotName] = true
        PushError(
            info,
            originalLine,
            string.format("%s: %s", L["未定义人员槽位"] or "未定义人员槽位", slotName),
            lineText
        )
        return "{__STN_MISSING_SLOT_" .. slotName .. "__}"
    end

    return "{" .. rawToken .. "}"
end

local function ReplaceSlotPlaceholders(info, bodyLines, bodyLineNumbers)
    local processedLines = {}

    for index, line in ipairs(bodyLines or {}) do
        local originalLine = tonumber(bodyLineNumbers and bodyLineNumbers[index]) or index
        local processed = tostring(line or ""):gsub("{{(.-)}}", function(rawSlot)
            local slotName = Trim(rawSlot)
            info.placeholderCount = (info.placeholderCount or 0) + 1
            return ResolveSlotToken(info, originalLine, slotName, line, true)
        end)

        -- 单花括号 slot 展开:循环到稳定,支持 [人员] 段嵌套引用(左边=DKT1 DKT2,DKT1=豆豆)
        -- 上限 5 层既覆盖任何实际嵌套场景,又给出兜底防御;循环引用(左边=左边)第二轮即稳定退出
        for _ = 1, 5 do
            local prev = processed
            processed = processed:gsub("{([^}]+)}", function(rawToken)
                return ResolveSlotToken(info, originalLine, rawToken, line, false)
            end)
            if processed == prev then break end
        end

        processedLines[#processedLines + 1] = processed
    end

    return processedLines
end

function Template.PreprocessText(text, opts)
    local normalized, lines = SplitLines(text)
    local relaxed = type(opts) == "table" and opts.relaxed == true

    -- 空/纯空白内容不是格式错误，直接返回空结果
    if normalized == "" or normalized:match("^%s*$") then
        return {
            sourceText = normalized,
            rawLines = lines,
            hasBlocks = false,
            sections = {},
            meta = {},
            slots = {},
            slotVisualSpecs = {},
            usedSlots = {},
            phaseRules = {},
            errors = {},
            settingsErrors = {},
            missingSlots = {},
            bodyText = "",
            processedText = "",
            bodyLineMap = {},
            bodyKind = nil,
            bodyHeaderLine = 0,
            bodySectionName = nil,
            slotCount = 0,
            placeholderCount = 0,
            isValid = false,
        }
    end

    local info = {
        sourceText = normalized,
        rawLines = lines,
        hasBlocks = DetectStructuredBlocks(lines),
        sections = {},
        meta = {},
        slots = {},
        slotVisualSpecs = {},
        usedSlots = {},
        phaseRules = {},
        errors = {},
        settingsErrors = {},
        missingSlots = {},
        bodyText = "",
        processedText = "",
        bodyLineMap = {},
        bodyKind = nil,
        bodyHeaderLine = 0,
        bodySectionName = nil,
        slotCount = 0,
        placeholderCount = 0,
        isValid = false,
    }

    if relaxed and not info.hasBlocks then
        info.bodyText = normalized
        info.processedText = NormalizeRelaxedBodyText(normalized)
        info.bodyKind = "timeline"
        local _, processedLines = SplitLines(info.processedText)
        ValidateBodyTokenIntegrity(info, processedLines)
        info.isValid = not HasFatalErrors(info)
        return info
    end

    if not info.hasBlocks then
        if normalized:find("{time:", 1, true) then
            info.bodyText = normalized
            info.processedText = NormalizeRelaxedBodyText(normalized)
            info.bodyKind = "timeline"
            local _, processedLines = SplitLines(info.processedText)
            ValidateBodyTokenIntegrity(info, processedLines)
            info.isValid = not HasFatalErrors(info)
            return info
        end
        PushError(info, 0, L["仅支持结构化模板"] or "仅支持结构化模板", "")
        return info
    end

    local currentSection = nil
    local seenSection = {}
    local planKeys = {}
    local slotKeys = {}
    local phaseKeys = {}
    local usingImplicitTimeline = false

    for lineNumber, line in ipairs(lines) do
        local trimmed = Trim(line)
        local sectionName = trimmed:match("^%[([^%]]+)%]$")
        if sectionName then
            if not KNOWN_SECTIONS[sectionName] then
                PushError(info, lineNumber, L["模板块无效"] or "模板块无效", trimmed)
                currentSection = nil
            else
                if seenSection[sectionName] then
                    PushError(info, lineNumber, L["模板块重复"] or "模板块重复", trimmed)
                else
                    seenSection[sectionName] = true
                end
                usingImplicitTimeline = false
                currentSection = sectionName
                EnsureSection(info, sectionName, lineNumber)
            end
        elseif currentSection == SECTION_TIMELINE or currentSection == SECTION_TRIGGER then
            local section = EnsureSection(info, currentSection)
            section.lines[#section.lines + 1] = line
            section.lineNumbers[#section.lineNumbers + 1] = lineNumber
        elseif currentSection == SECTION_INTERRUPT then
            -- [打断] 由打断轮替模块消费；模板预处理只把它识别为合法块，避免污染时间轴正文。
        elseif currentSection == SECTION_PLAN or currentSection == SECTION_SLOTS or currentSection == SECTION_SETTINGS or currentSection == SECTION_SLOT_ICONS then
            if currentSection == SECTION_SLOTS and usingImplicitTimeline then
                local section = EnsureSection(info, SECTION_TIMELINE, lineNumber)
                section.lines[#section.lines + 1] = line
                section.lineNumbers[#section.lineNumbers + 1] = lineNumber
            elseif trimmed ~= "" then
                local rawKey, rawValue = line:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
                if currentSection == SECTION_SLOTS and not rawKey and not seenSection[SECTION_TIMELINE] and not seenSection[SECTION_TRIGGER] and line:find("{time:", 1, true) then
                    seenSection[SECTION_TIMELINE] = true
                    usingImplicitTimeline = true
                    currentSection = SECTION_TIMELINE

                    local section = EnsureSection(info, SECTION_TIMELINE, lineNumber)
                    section.lines[#section.lines + 1] = line
                    section.lineNumbers[#section.lineNumbers + 1] = lineNumber
                elseif not rawKey then
                    if currentSection == SECTION_SLOTS then
                        local key = Trim(line)
                        if slotKeys[key] then
                            PushError(info, lineNumber, L["人员槽位重复"] or "人员槽位重复", line)
                        elseif key == "" then
                            PushError(info, lineNumber, L["槽位名不能为空"] or "槽位名不能为空", line)
                        else
                            slotKeys[key] = true
                            info.slots[key] = ""
                        end
                    elseif currentSection == SECTION_SETTINGS then
                        PushSettingsError(info, lineNumber, L["模板键值格式无效"] or "模板键值格式无效", line)
                    else
                        PushError(info, lineNumber, L["模板键值格式无效"] or "模板键值格式无效", line)
                    end
                else
                    local key = Trim(rawKey)
                    local value = UnquoteValue(rawValue)
                    if currentSection == SECTION_PLAN then
                        if planKeys[key] then
                            PushError(info, lineNumber, L["模板键重复"] or "模板键重复", line)
                        else
                            planKeys[key] = true
                            info.meta[key] = value
                        end
                    elseif currentSection == SECTION_SLOTS then
                        if slotKeys[key] then
                            PushError(info, lineNumber, L["人员槽位重复"] or "人员槽位重复", line)
                        else
                            slotKeys[key] = true
                            local playerName = NormalizeSlotValue(value)
                            if playerName == "" then
                                PushError(info, lineNumber, L["人员槽位不能为空"] or "人员槽位不能为空", line)
                            else
                                info.slots[key] = playerName
                            end
                        end
                    elseif currentSection == SECTION_SETTINGS then
                        local phaseKey = NormalizePhaseKey(key)
                        local spellID = value:match("^%s*{on:spell:(%d+)}%s*$")
                        if phaseKeys[phaseKey or key] then
                            PushSettingsError(info, lineNumber, L["模板键重复"] or "模板键重复", line)
                        elseif not phaseKey or not spellID then
                            PushSettingsError(info, lineNumber, L["模板键值格式无效"] or "模板键值格式无效", line)
                        else
                            phaseKeys[phaseKey] = true
                            info.phaseRules[phaseKey] = {
                                type = "spell",
                                spellID = tonumber(spellID),
                            }
                        end
                    elseif currentSection == SECTION_SLOT_ICONS then
                        local specID = tonumber(value)
                        if not specID or specID <= 0 then
                            PushError(info, lineNumber, L["模板键值格式无效"] or "模板键值格式无效", line)
                        else
                            info.slotVisualSpecs[key] = math.floor(specID + 0.5)
                        end
                    end
                end
            end
        elseif trimmed ~= "" then
            PushError(info, lineNumber, L["模板块外存在内容"] or "模板块外存在内容", line)
        end
    end

    FinalizeSectionRanges(info)

    if not info.sections[SECTION_SLOTS] then
        info.slotCount = 0
    end

    local hasTimeline = info.sections[SECTION_TIMELINE] ~= nil
    local hasTrigger = info.sections[SECTION_TRIGGER] ~= nil
    if hasTimeline and hasTrigger then
        PushError(info, 0, L["正文块冲突"] or "正文块冲突", "[" .. SECTION_TIMELINE .. "]/[" .. SECTION_TRIGGER .. "]")
    elseif not hasTimeline and not hasTrigger then
        PushError(info, 0, L["缺少正文块"] or "缺少正文块", "[" .. SECTION_TIMELINE .. "]/[" .. SECTION_TRIGGER .. "]")
    end

    local bodySection = nil
    if hasTimeline and not hasTrigger then
        bodySection = info.sections[SECTION_TIMELINE]
    elseif hasTrigger and not hasTimeline then
        bodySection = info.sections[SECTION_TRIGGER]
    end

    info.slotCount = CountMapKeys(info.slots)
    if bodySection then
        info.bodySectionName = bodySection.name
        info.bodyKind = BODY_SECTION_KIND[bodySection.name]
        info.bodyHeaderLine = tonumber(bodySection.headerLine) or 0
        info.bodyText = table.concat(bodySection.lines, "\n")
        info.bodyLineMap = bodySection.lineNumbers
        local processedLines = ReplaceSlotPlaceholders(info, bodySection.lines, bodySection.lineNumbers)
        ValidateBodyTokenIntegrity(info, processedLines, bodySection.lineNumbers)
        info.processedText = table.concat(processedLines, "\n")
    end
    info.isValid = info.bodyKind ~= nil and #(info.errors or {}) == 0

    return info
end

function Template.IsBodyUsable(info, expectedBodyKind)
    if type(info) ~= "table" then
        return false
    end

    local bodyKind = tostring(info.bodyKind or "")
    if expectedBodyKind and bodyKind ~= expectedBodyKind then
        return false
    end
    if bodyKind == "" then
        return false
    end
    if HasFatalErrors(info) then
        return false
    end
    if info.isValid == true then
        return true
    end
    if bodyKind ~= "timeline" then
        return false
    end

    return HasTimelineBodyText(info.processedText or info.bodyText or "")
end

function Template.HasStructuredBlocks(text)
    local info = Template.PreprocessText(text)
    return info.hasBlocks == true
end

function Template.ReplaceBodyText(text, newBodyText)
    local info = Template.PreprocessText(text)
    if not info.hasBlocks then
        return tostring(text or "")
    end

    local bodySection = info.bodySectionName and info.sections[info.bodySectionName] or nil
    if not bodySection then
        return tostring(text or "")
    end

    local output = {}
    local startLine = tonumber(bodySection.headerLine) or 0
    local endLine = tonumber(bodySection.lastLine) or startLine
    local rawLines = info.rawLines or {}

    for index = 1, startLine do
        output[#output + 1] = rawLines[index] or ""
    end

    local normalizedBody = tostring(newBodyText or ""):gsub("\r\n", "\n")
    if normalizedBody ~= "" then
        for line in (normalizedBody .. "\n"):gmatch("([^\n]*)\n") do
            output[#output + 1] = line
        end
    end

    for index = endLine + 1, #rawLines do
        output[#output + 1] = rawLines[index]
    end

    return table.concat(output, "\n")
end

function Template.ReplaceTimelineBody(text, newBodyText)
    return Template.ReplaceBodyText(text, newBodyText)
end

local function SortedSlotKeys(slots)
    local keys = {}
    for key in pairs(slots or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

function Template.BuildTemplate(options)
    local opts = type(options) == "table" and options or {}
    local author = Trim(tostring(opts.author or ""))
    if author == "" then
        author = UnitName and UnitName("player") or "Player"
    end

    local name = Trim(tostring(opts.name or ""))
    if name == "" then
        name = "新方案"
    end

    local bodyKind = opts.bodyKind == "trigger" and "trigger" or "timeline"
    local bodyHeader = bodyKind == "trigger" and SECTION_TRIGGER or SECTION_TIMELINE
    local slots = type(opts.slots) == "table" and opts.slots or {}
    local settingsText = tostring(opts.settingsText or ""):gsub("\r\n", "\n")
    local bodyText = tostring(opts.bodyText or ""):gsub("\r\n", "\n")

    local lines = {
        "[方案]",
        "名称 = " .. name,
        "作者 = " .. author,
        "",
        "[人员]",
    }

    for _, key in ipairs(SortedSlotKeys(slots)) do
        lines[#lines + 1] = string.format("%s = %s", tostring(key), tostring(slots[key] or ""))
    end

    lines[#lines + 1] = ""
    if settingsText ~= "" then
        lines[#lines + 1] = "[" .. SECTION_SETTINGS .. "]"
        for line in (settingsText .. "\n"):gmatch("([^\n]*)\n") do
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "[" .. bodyHeader .. "]"
    if bodyText ~= "" then
        for line in (bodyText .. "\n"):gmatch("([^\n]*)\n") do
            lines[#lines + 1] = line
        end
    end

    return table.concat(lines, "\n")
end

function Template.BuildDefaultTemplate()
    local author = UnitName and UnitName("player") or "Player"
    return Template.BuildTemplate({
        name = "新方案",
        author = tostring(author or "Player"),
        bodyKind = "timeline",
        slots = {
            ["坦克1"] = tostring(author or "Player"),
            ["治疗1"] = tostring(author or "Player"),
        },
        bodyText = "{time:00:10} {{坦克1}}开怪\n{time:00:20} {{治疗1}}准备抬血",
    })
end

end)
