local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("tacticTranslator.enabled", function()

-- TR (TimelineReminders) 格式 adapter
-- 通过 T.TacticTranslator:Register 注册到通用翻译器注册表
-- 字符串结构：!TR:<base64(deflate(LibSerialize(table)))>

if not T.TacticTranslator then return end

local floor = math.floor

local function FormatTime(seconds)
    local s = tonumber(seconds) or 0
    if s < 0 then s = 0 end
    local m = floor(s / 60)
    local r = floor(s % 60)
    return string.format("%02d:%02d", m, r)
end

-- TR load.role / load.position / load.class → STT audience token
local ROLE_MAP = {
    TANK = "tank",
    HEALER = "healer",
    DAMAGER = "dps",
}

local POSITION_MAP = {
    MELEE = "melee",
    RANGED = "ranged",
}

-- TR display.region → STT 屏幕提醒指示器名称（默认命名约定 = "<类型>#1"）
-- TEXT 不映射，走默认文本广播；其他三种走 {to:...} 专属指示器路由
-- 用户如未在"设置 → 屏幕提醒"里建过对应名称的指示器，需要先建一个并启用"不参与通用文本提醒"
local REGION_TO_INDICATOR = {
    ICON   = "图标#1",
    BAR    = "计时条#1",
    CIRCLE = "环形#1",
}

-- TR 大写英文职业 → STT 内置职业 token（参考 condition_filter.lua 的中文/英文别名）
local CLASS_MAP = {
    WARRIOR = "warrior",
    PALADIN = "paladin",
    HUNTER = "hunter",
    ROGUE = "rogue",
    PRIEST = "priest",
    DEATHKNIGHT = "dk",
    SHAMAN = "shaman",
    MAGE = "mage",
    WARLOCK = "warlock",
    MONK = "monk",
    DRUID = "druid",
    DEMONHUNTER = "dh",
    EVOKER = "evoker",
}

local function GetLibs()
    local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    return LibSerialize, LibDeflate
end

local function IsTRFormat(content)
    return type(content) == "string" and content:match("^%s*!TR:") ~= nil
end

-- 从 trigger.relativeTo 推断 STT phase 后缀（p1 / p1r2 / i1 等）
-- 依据：T.PhaseAnchorsS14[encounterID].templateRules[phase] = { type="spell", spellID=N }
-- 反查命中则返回 phase 字符串 + 可选 round 后缀
local function ResolvePhaseTag(encounterID, relativeTo)
    if not (encounterID and relativeTo) then return nil end
    local anchors = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[encounterID]
    if not anchors or type(anchors.templateRules) ~= "table" then return nil end

    local triggerValue = tonumber(relativeTo.value)
    if not triggerValue then return nil end

    for phaseName, rule in pairs(anchors.templateRules) do
        if type(rule) == "table" and rule.type == "spell" and tonumber(rule.spellID) == triggerValue then
            local count = tonumber(relativeTo.count) or 1
            if count > 1 then
                return phaseName .. "r" .. tostring(count)
            end
            return phaseName
        end
    end
    return nil
end

-- 从 reminder.load 生成 STT 接收者 token（不带花括号）
local function BuildAudienceToken(load)
    if type(load) ~= "table" then return "所有人" end
    local t = load.type
    if t == "ALL" or not t then
        return "所有人"
    elseif t == "ROLE" then
        return ROLE_MAP[load.role or ""] or "所有人"
    elseif t == "POSITION" then
        return POSITION_MAP[load.position or ""] or "所有人"
    elseif t == "NAME" then
        local name = tostring(load.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return "所有人" end
        return name
    elseif t == "CLASS_SPEC" then
        return CLASS_MAP[load.class or ""] or "所有人"
    elseif t == "GROUP" then
        local g = tonumber(load.group)
        if g and g >= 1 and g <= 8 then
            return "g" .. tostring(g)
        end
        return "所有人"
    end
    return "所有人"
end

-- 把数字 clamp 到 [lo, hi]
local function Clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

-- 是否检测到 STT 当前不支持的字段（仅用于统计）
-- 注意：display.region 已映射到 {to:...}，display.ticks 仅在 BAR widget 集成后才能精准映射，暂列为未支持
local function CountUnsupported(reminder)
    local n = 0
    if reminder.glow and reminder.glow.enabled then n = n + 1 end
    if reminder.trigger and tonumber(reminder.trigger.linger) and tonumber(reminder.trigger.linger) > 0 then n = n + 1 end
    if reminder.trigger and reminder.trigger.hideOnUse then n = n + 1 end
    if reminder.display and reminder.display.ticks and #reminder.display.ticks > 0 then n = n + 1 end
    return n
end

-- 单条 reminder → STT 时间轴行
local function BuildTimelineLine(reminder, encounterID)
    local trigger = reminder.trigger or {}
    local display = reminder.display or {}
    local countdown = reminder.countdown or {}
    local sound = reminder.sound or {}
    local load = reminder.load or {}

    local timeStr = FormatTime(trigger.time)
    local phasePart = ""
    local phaseTag = ResolvePhaseTag(encounterID, trigger.relativeTo)
    if phaseTag then
        phasePart = "," .. phaseTag
    end

    local audience = "{" .. BuildAudienceToken(load) .. "}"

    -- 指示器路由：TR.display.region → STT {to:指示器名}
    local routePart = ""
    local indicatorName = REGION_TO_INDICATOR[display.region or ""]
    if indicatorName then
        routePart = "{to:" .. indicatorName .. "} "
    end

    local body = ""
    if display.type == "SPELL" then
        local spellID = tonumber(display.spellID)
        local override = tostring(display.spellText or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if override ~= "" then
            body = override
        end
        if spellID and spellID > 0 then
            body = body .. "{spell:" .. tostring(spellID) .. "}"
        end
    else
        local text = tostring(display.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then
            body = text
        end
    end

    -- 内联追加 sr / ct / sound
    local modifiers = ""
    local sr = tonumber(trigger.duration)
    if sr and sr > 0 then
        sr = Clamp(sr, 0, 10)
        local srStr = (sr == floor(sr)) and tostring(floor(sr)) or string.format("%.1f", sr)
        modifiers = modifiers .. "{sr:" .. srStr .. "}"
    end
    if countdown.enabled then
        local ct = tonumber(countdown.start)
        if ct and ct >= 1 then
            ct = Clamp(floor(ct + 0.5), 1, 10)
            modifiers = modifiers .. "{ct:" .. tostring(ct) .. "}"
        end
    end
    if sound.enabled and type(sound.file) == "string" and sound.file ~= "" then
        local file = sound.file:gsub("^%s+", ""):gsub("%s+$", "")
        -- 屏蔽含 { } \r \n 的非法路径
        if file ~= "" and not file:find("[{}\r\n]") then
            modifiers = modifiers .. "{@" .. file .. "}"
        end
    end

    -- STT 惯例（指南示例）：
    --   {time:01:00} {to:环形#1} {所有人}{sr:10}集合
    --   {to:} 在 {time:} 与 {audience} 之间；modifier 在 audience 与 body 之间
    return string.format("{time:%s%s} %s%s%s%s", timeStr, phasePart, routePart, audience, modifiers, body)
end

local function Parse(text)
    local result = {
        header     = nil,
        reminders  = {},
        skipped    = 0,
        totalLines = 0,
        unsupportedCount = 0,
    }

    if type(text) ~= "string" then
        return nil, "输入不是字符串"
    end

    local payload = text:match("^%s*!TR:(.+)$")
    if not payload then
        return nil, "缺少 !TR: 前缀"
    end
    payload = payload:gsub("%s+$", "")

    local LibSerialize, LibDeflate = GetLibs()
    if not (LibSerialize and LibDeflate) then
        return nil, "LibSerialize/LibDeflate 未加载"
    end

    local decoded = LibDeflate:DecodeForPrint(payload)
    if not decoded then
        return nil, "DecodeForPrint 失败（字符串可能损坏）"
    end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, "DecompressDeflate 失败（数据无法解压）"
    end

    local ok, data = LibSerialize:Deserialize(decompressed)
    if not ok or type(data) ~= "table" then
        return nil, "Deserialize 失败（数据格式不匹配）"
    end

    result.header = {
        encounterID = tonumber(data.id),
        difficulty  = tonumber(data.d),
        version     = tonumber(data.v),
    }

    local rmap = data.r
    if type(rmap) == "table" then
        local list = {}
        for _, reminder in pairs(rmap) do
            if type(reminder) == "table" then
                list[#list + 1] = reminder
            end
        end
        table.sort(list, function(a, b)
            local ta = tonumber(a.trigger and a.trigger.time) or 0
            local tb = tonumber(b.trigger and b.trigger.time) or 0
            return ta < tb
        end)

        for _, reminder in ipairs(list) do
            result.totalLines = result.totalLines + 1
            result.unsupportedCount = result.unsupportedCount + CountUnsupported(reminder)
            result.reminders[#result.reminders + 1] = reminder
        end
    end

    return result
end

local function Format(parsed)
    if type(parsed) ~= "table" then
        return { stn = "", eventCount = 0, phaseCount = 0, skipped = 0, totalLines = 0 }
    end

    local header = parsed.header or {}
    local reminders = parsed.reminders or {}
    local encounterID = header.encounterID

    local lines = {}

    lines[#lines + 1] = "[方案]"
    local planName = "TR 导入"
    if encounterID then
        planName = planName .. " (encounterID=" .. tostring(encounterID)
        if header.difficulty then
            planName = planName .. ", difficulty=" .. tostring(header.difficulty)
        end
        planName = planName .. ")"
    end
    lines[#lines + 1] = "名称 = " .. planName
    lines[#lines + 1] = "作者 = TR 导入"
    lines[#lines + 1] = ""

    lines[#lines + 1] = "[时间轴]"
    if encounterID then
        lines[#lines + 1] = "-- EncounterID: " .. tostring(encounterID)
    end
    if parsed.unsupportedCount and parsed.unsupportedCount > 0 then
        lines[#lines + 1] = string.format("-- 已跳过 %d 个 STT 不支持的字段 (glow / linger / hideOnUse / display.ticks)",
            parsed.unsupportedCount)
    end
    -- 提示：如方案中含 {to:图标#1}/{to:环形#1}/{to:计时条#1}，需在"设置 → 屏幕提醒"创建对应名字的指示器并启用"不参与通用文本提醒"
    local hasRoute = false
    for _, reminder in ipairs(reminders) do
        local region = reminder.display and reminder.display.region
        if REGION_TO_INDICATOR[region or ""] then hasRoute = true; break end
    end
    if hasRoute then
        lines[#lines + 1] = "-- 提示：本方案使用了 {to:...} 指示器路由，请确保设置 → 屏幕提醒里已建好对应名称的指示器"
    end

    local phaseSet = {}
    for _, reminder in ipairs(reminders) do
        local line = BuildTimelineLine(reminder, encounterID)
        lines[#lines + 1] = line
        local relativeTo = reminder.trigger and reminder.trigger.relativeTo
        local phaseTag = ResolvePhaseTag(encounterID, relativeTo)
        if phaseTag then
            phaseSet[phaseTag] = true
        end
    end

    local phaseCount = 0
    for _ in pairs(phaseSet) do
        phaseCount = phaseCount + 1
    end

    return {
        stn         = table.concat(lines, "\n"),
        eventCount  = #reminders,
        phaseCount  = phaseCount,
        skipped     = parsed.skipped or 0,
        totalLines  = parsed.totalLines or 0,
        header      = header,
    }
end

T.TacticTranslator:Register({
    id        = "tr",
    name      = "TR (TimelineReminders)",
    nameKey   = "TACTIC_TRANSLATOR_TR_NAME",
    sampleKey = "TACTIC_TRANSLATOR_TR_SAMPLE",
    sample    = "!TR:...(从 TimelineReminders 插件导出的字符串，复制完整内容到这里)",
    detect    = IsTRFormat,
    parse     = Parse,
    format    = Format,
})

end)
