-- 鲁拉水晶：本机释放黎明水晶后的本地屏幕倒计时提醒。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("luraCrystal.enabled", function()

local M = T.ModuleLoader:NewModule({
    name = "LuraCrystalAlert",
    dbKey = "luraCrystal.enabled",
    defaultEnabled = false,
})
T.LuraCrystalAlert = M

local LURA_ENCOUNTER_ID = 3183
local LURA_CRYSTAL_SPELL_ID = 1253050
local DEFAULT_DURATION_SEC = 3
local DEFAULT_INDICATOR = "计时条#1"
local DEFAULT_TEXT = "黎明水晶：%.1f秒内捡起"

local frame

local luraEncounterActive = false
local lastCastGUID = nil
local countdownTimers = {}

local function NormalizeDuration(value)
    local duration = tonumber(value) or DEFAULT_DURATION_SEC
    if duration < 1 then
        duration = 1
    elseif duration > 5 then
        duration = 5
    end
    return duration
end

local function GetDB()
    if not C.DB.luraCrystal then
        C.DB.luraCrystal = {}
    end
    local db = C.DB.luraCrystal
    if db.enabled == nil then db.enabled = false end
    if tostring(db.indicatorName or "") == "" then
        db.indicatorName = DEFAULT_INDICATOR
    end
    if db.countdownAudioEnabled == nil then
        db.countdownAudioEnabled = true
    end
    db.durationSec = NormalizeDuration(db.durationSec)
    return db
end

local function CancelCountdownAudio()
    for _, timer in ipairs(countdownTimers) do
        if timer and timer.Cancel then
            timer:Cancel()
        end
    end
    wipe(countdownTimers)
end

local function ScheduleCountdownAudio(duration)
    CancelCountdownAudio()
    if not T.PlayCountdownMp3 then
        return 0
    end
    local countdownValue = math.floor((tonumber(duration) or 0) + 0.0001)
    if countdownValue < 1 then
        return 0
    elseif countdownValue > 10 then
        countdownValue = 10
    end

    local scheduled = 0
    for offset = 0, countdownValue - 1 do
        local number = countdownValue - offset
        local timer = C_Timer.NewTimer(offset, function()
            T.PlayCountdownMp3(number)
        end)
        countdownTimers[#countdownTimers + 1] = timer
        scheduled = scheduled + 1
    end
    return scheduled
end

function M:IsEnabled()
    return GetDB().enabled == true
end

function M:ApplySettings()
    local db = GetDB()
    T.debug("[LuraCrystalAlert] ApplySettings enabled=" .. tostring(db.enabled))
end

function M:Show(source, ignoreEnabled)
    if not ignoreEnabled and not self:IsEnabled() then
        T.debug("[LuraCrystalAlert] skipped disabled source=" .. tostring(source or "unknown"))
        return false
    end
    if not (T.ScreenReminderAlert and T.ScreenReminderAlert.ShowImmediateCountdown) then
        T.debug("[LuraCrystalAlert] skipped screen_reminder_alert_missing")
        return false
    end

    local db = GetDB()
    local indicatorName = tostring(db.indicatorName or DEFAULT_INDICATOR)

    local duration = NormalizeDuration(db.durationSec)
    local shown = T.ScreenReminderAlert:ShowImmediateCountdown({
        text = string.format(L["LURA_CRYSTAL_ALERT_TEXT"] or DEFAULT_TEXT, duration),
        durationSec = duration,
        indicatorName = indicatorName,
        spellID = LURA_CRYSTAL_SPELL_ID,
    })
    T.debug(string.format(
        "[LuraCrystalAlert] source=%s shown=%s indicator=%s duration=%.1f",
        tostring(source or "unknown"),
        tostring(shown),
        indicatorName,
        duration
    ))
    if shown == true and db.countdownAudioEnabled ~= false then
        local audioCount = ScheduleCountdownAudio(duration)
        T.debug(string.format("[LuraCrystalAlert] countdown_audio timers=%d duration=%.1f", audioCount, duration))
    end
    return shown == true
end

function M:Test()
    local shown = self:Show("test", true)
    if T.msg then
        if shown then
            T.msg(string.format("鲁拉水晶提醒：已模拟 %.1f 秒倒计时", NormalizeDuration(GetDB().durationSec)))
        else
            T.msg("鲁拉水晶提醒：未显示。请确认屏幕提醒已启用且样式存在。")
        end
    end
    return shown
end

local function HandleSpellcast(unitTarget, castGUID, spellID)
    if unitTarget ~= "player" then
        return
    end
    if tonumber(spellID) ~= LURA_CRYSTAL_SPELL_ID then
        return
    end
    if not luraEncounterActive then
        T.debug("[LuraCrystalAlert] skipped outside_lura")
        return
    end

    local guid = tostring(castGUID or "")
    if guid ~= "" and guid == lastCastGUID then
        T.debug("[LuraCrystalAlert] skipped duplicate castGUID=" .. guid)
        return
    end
    lastCastGUID = guid
    M:Show("unit_spellcast_succeeded", false)
end

function M:OnRegister()
    T.LuraCrystalAlert = self
end

function M:OnEnable()
    if not frame then
        frame = CreateFrame("Frame")
        M.frame = frame
        frame:SetScript("OnEvent", function(_, event, ...)
            M:OnEvent(event, ...)
        end)
    end
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

function M:OnDisable()
    if frame then
        frame:UnregisterAllEvents()
    end
    luraEncounterActive = false
    lastCastGUID = nil
    CancelCountdownAudio()
end

function M:OnEvent(event, ...)
    if event == "ENCOUNTER_START" then
        local encounterIDArg = ...
        local encounterID = tonumber(encounterIDArg)
        if encounterID == LURA_ENCOUNTER_ID then
            luraEncounterActive = true
            lastCastGUID = nil
            T.debug("[LuraCrystalAlert] LuraEncounter begin")
        else
            luraEncounterActive = false
            lastCastGUID = nil
        end
    elseif event == "ENCOUNTER_END" then
        if luraEncounterActive then
            T.debug("[LuraCrystalAlert] LuraEncounter end")
        end
        luraEncounterActive = false
        lastCastGUID = nil
        CancelCountdownAudio()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        HandleSpellcast(...)
    end
end

end)
