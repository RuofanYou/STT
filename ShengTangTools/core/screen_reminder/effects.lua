-- screen_reminder/effects.lua
-- 屏幕提醒通用视觉效果：当前仅提供发光像素。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

T.ScreenReminderEffects = T.ScreenReminderEffects or {}
local Effects = T.ScreenReminderEffects

local PIXEL_GLOW_KEY = "stt_screen_pixel_glow"
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true) or nil

local function HexToColor(hex)
    if type(hex) ~= "string" or #hex < 6 then
        return nil
    end
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return { r / 255, g / 255, b / 255, 1 }
end

function Effects.StartPixelGlow(frame, def)
    if not frame or not LCG then
        return 0
    end
    local effects = def and def.effects
    local glow = effects and effects.pixelGlow
    if type(glow) ~= "table" or glow.enabled ~= true then
        return 0
    end

    local color = glow.useColor and HexToColor(glow.color) or nil
    local lines = math.max(1, tonumber(glow.lines) or 8)
    local frequency = tonumber(glow.frequency) or 0.25
    local length = math.max(1, tonumber(glow.length) or 10)
    local thickness = math.max(1, tonumber(glow.thickness) or 1)
    local xOffset = tonumber(glow.xOffset) or 0
    local yOffset = tonumber(glow.yOffset) or 0
    local duration
    if glow.durationMode == "linger" then
        duration = math.max(0, tonumber(def and def.lingerSec) or 0)
    else
        duration = math.max(0.1, tonumber(glow.duration) or 0.4)
    end
    if duration <= 0 then
        return 0
    end
    frame.__sttScreenPixelGlowToken = (frame.__sttScreenPixelGlowToken or 0) + 1
    local token = frame.__sttScreenPixelGlowToken

    LCG.PixelGlow_Stop(frame, PIXEL_GLOW_KEY)
    LCG.PixelGlow_Start(frame, color, lines, frequency, length, thickness, xOffset, yOffset, false, PIXEL_GLOW_KEY)
    if C_Timer and C_Timer.After then
        C_Timer.After(duration, function()
            if frame and frame.__sttScreenPixelGlowToken == token then
                LCG.PixelGlow_Stop(frame, PIXEL_GLOW_KEY)
            end
        end)
    end
    return duration
end

function Effects.StopPixelGlow(frame)
    if not frame then return end
    frame.__sttScreenPixelGlowToken = (frame.__sttScreenPixelGlowToken or 0) + 1
    if LCG then
        LCG.PixelGlow_Stop(frame, PIXEL_GLOW_KEY)
    end
end

end)
