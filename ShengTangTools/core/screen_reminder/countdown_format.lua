-- screen_reminder/countdown_format.lua
-- 倒数 token → 字符串 + 颜色十六进制。纯函数，4 类 indicator 共用。
--
-- 输入字段（来自 indicator.countdown）：
--   enabled       bool
--   fontSize      number?  手动倒数字号；nil 时由各指示器沿用原自动字号
--   decimals      0|1|2
--   unit          "s"|"秒"|""
--   wrap          "none"|"()"|"[]"|"{}"|"<>"
--   colorByTime   bool
--   critical      { threshold, color }
--   warning       { threshold, color }
--   normal        { color }
--
-- 输出：(text, hexColor)
--   text = wrap_open .. number .. unit .. wrap_close
--   text 在 enabled=false 或 remaining<0 时返回空串

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

T.ScreenReminderCountdown = T.ScreenReminderCountdown or {}
local Countdown = T.ScreenReminderCountdown

local WRAP_PAIRS = {
    ["none"] = { "", "" },
    ["()"]   = { "(", ")" },
    ["[]"]   = { "[", "]" },
    ["{}"]   = { "{", "}" },
    ["<>"]   = { "<", ">" },
}

local DECIMALS_FMT = {
    [0] = "%.0f",
    [1] = "%.1f",
    [2] = "%.2f",
}

local function ResolveDecimals(value)
    local n = tonumber(value)
    if n == 0 or n == 1 or n == 2 then return n end
    return 1
end

function Countdown.ResolveFontSize(def, fallback)
    if type(def) ~= "table" or def.fontSize == nil then
        return tonumber(fallback) or 13
    end
    local size = math.floor((tonumber(def.fontSize) or fallback or 13) + 0.5)
    if size < 8 then return 8 end
    if size > 100 then return 100 end
    return size
end

local function ResolveColor(def, remaining)
    if not def or def.colorByTime ~= true then
        return (def and def.normal and def.normal.color) or "FFFFFF"
    end
    local critical = def.critical
    local warning = def.warning
    if critical and remaining <= (tonumber(critical.threshold) or 1.0) then
        return critical.color or "FF3333"
    end
    if warning and remaining <= (tonumber(warning.threshold) or 3.0) then
        return warning.color or "FFCC33"
    end
    return (def.normal and def.normal.color) or "FFFFFF"
end

function Countdown.Format(remaining, def)
    if type(def) ~= "table" or def.enabled == false then
        return "", "FFFFFF"
    end
    remaining = tonumber(remaining) or 0
    if remaining < 0 then remaining = 0 end

    local decimals = ResolveDecimals(def.decimals)
    local fmt = DECIMALS_FMT[decimals] or DECIMALS_FMT[1]
    local numText = string.format(fmt, remaining)

    local unit = def.unit
    if unit == nil then unit = "s" end
    if unit ~= "s" and unit ~= "秒" and unit ~= "" then
        unit = "s"
    end

    local wrap = WRAP_PAIRS[def.wrap or "none"] or WRAP_PAIRS["none"]
    local text = wrap[1] .. numText .. unit .. wrap[2]
    local color = ResolveColor(def, remaining)
    return text, color
end

-- 给 FontString 直接设置（带颜色）
-- 用 FontString 上的 __lastText/__lastColor 字段做无变化跳过，避免 OnUpdate 每帧无意义重设
function Countdown.ApplyToFontString(fontString, remaining, def)
    if not fontString then return "", "FFFFFF" end
    local text, color = Countdown.Format(remaining, def)
    if fontString.__lastText ~= text then
        fontString:SetText(text)
        fontString.__lastText = text
    end
    if color and fontString.__lastColor ~= color then
        local r = (tonumber(color:sub(1, 2), 16) or 255) / 255
        local g = (tonumber(color:sub(3, 4), 16) or 255) / 255
        local b = (tonumber(color:sub(5, 6), 16) or 255) / 255
        fontString:SetTextColor(r, g, b, 1)
        fontString.__lastColor = color
    end
    return text, color
end

end)
