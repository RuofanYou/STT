-- 鲁拉 P4 星辰裂片方向增强（实验）：只在个人光环提醒命中后额外叠加方向箭头。

local T, C = unpack(select(2, ...))
T.RegisterColdFile("personalAuraAlert.enabled", function()

local M = {}
T.LuraStarsplinterDirection = M

local LURA_ENCOUNTER_ID = 3183
local MYTHIC_RAID_DIFFICULTY_ID = 16
local STAR_SPLINTER_SEVERITY = 1
local DEFAULT_INDICATOR_NAME = "文本#1"
local DIRECTION_DURATION_SEC = 1
local WINDOW_TOLERANCE_SEC = 0.10
local ROUND_STARTS = { 13, 33, 53, 73, 93 }

local function Debug(fmt, ...)
    if not (T.debug and C and C.DB and C.DB.debugMode == true) then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[LuraStarsplinterDirection] " .. tostring(fmt), ...))
    else
        T.debug("[LuraStarsplinterDirection] " .. tostring(fmt))
    end
end

local function IsP4(phase)
    local normalized = tostring(phase or ""):lower()
    return normalized == "p4" or normalized:match("^p4r%d+$") ~= nil
end

local function GetCurrentPhase()
    local detector = T.PhaseDetector
    if detector and detector.GetCurrentPhase then
        return detector:GetCurrentPhase()
    end
    return nil
end

local function ResolvePhaseElapsedSec(phase, fallbackElapsed)
    local detector = T.PhaseDetector
    if detector and detector.GetPhaseStartTime and type(GetTime) == "function" then
        local phaseStart = detector:GetPhaseStartTime(phase) or detector:GetPhaseStartTime("p4")
        if phaseStart then
            return math.max(0, GetTime() - phaseStart)
        end
    end
    return tonumber(fallbackElapsed)
end

function M.ResolveArrow(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    if tonumber(ctx.encounterID) ~= LURA_ENCOUNTER_ID then
        return nil
    end
    if tonumber(ctx.difficultyID) ~= MYTHIC_RAID_DIFFICULTY_ID then
        return nil
    end
    if tonumber(ctx.severity) ~= STAR_SPLINTER_SEVERITY then
        return nil
    end
    if not IsP4(ctx.phase) then
        return nil
    end

    local elapsed = tonumber(ctx.elapsedSec)
    if not elapsed then
        return nil
    end

    for _, base in ipairs(ROUND_STARTS) do
        local offset = elapsed - base
        if offset >= -WINDOW_TOLERANCE_SEC and offset < 1 then
            return "←"
        elseif offset >= 1 and offset < 2 then
            return "→"
        elseif offset >= 2 and offset < 3 + WINDOW_TOLERANCE_SEC then
            return "←"
        end
    end
    return nil
end

function M:OnPersonalAuraAlertShown(ctx)
    if type(ctx) ~= "table" then
        return false
    end

    local phase = GetCurrentPhase()
    local elapsed = ResolvePhaseElapsedSec(phase, ctx.elapsedSec)
    local arrow = M.ResolveArrow({
        encounterID = ctx.encounterID,
        difficultyID = ctx.difficultyID,
        severity = ctx.severity,
        phase = phase,
        elapsedSec = elapsed,
    })
    if not arrow then
        Debug("skip encounter=%s difficulty=%s severity=%s phase=%s elapsed=%s",
            tostring(ctx.encounterID),
            tostring(ctx.difficultyID),
            tostring(ctx.severity),
            tostring(phase),
            elapsed ~= nil and string.format("%.2f", elapsed) or "nil")
        return false
    end
    if not (T.ScreenReminderAlert and T.ScreenReminderAlert.ShowImmediateCountdown) then
        Debug("skip reason=screen_reminder_alert_missing arrow=%s", tostring(arrow))
        return false
    end

    local shown = T.ScreenReminderAlert:ShowImmediateCountdown({
        text = arrow,
        durationSec = DIRECTION_DURATION_SEC,
        indicatorName = DEFAULT_INDICATOR_NAME,
        severity = "critical",
    })
    Debug("show arrow=%s shown=%s phase=%s elapsed=%s",
        tostring(arrow),
        tostring(shown),
        tostring(phase),
        elapsed ~= nil and string.format("%.2f", elapsed) or "nil")
    return shown == true
end

end)
