local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("buffCheck.repairReminder.enabled", function()

local DB_KEY = "buffCheck.repairReminder"
local NEW_SINCE = "260519.53"

local function ApplyAutoRepair()
    if T.BuffCheck and T.BuffCheck.ApplyEnabledState then
        T.BuffCheck:ApplyEnabledState()
    end
end

local function RefreshReminder()
    if T.BuffCheck and T.BuffCheck.EvaluateRepairReminder then
        T.BuffCheck:EvaluateRepairReminder("options", true)
    end
end

local function FormatSeconds(value)
    return string.format(L["GUI_DURABILITY_CHECK_SECONDS_FMT"] or "%d秒", math.floor((tonumber(value) or 0) + 0.5))
end

local function FormatMinutes(value)
    return string.format(L["GUI_DURABILITY_CHECK_MINUTES_FMT"] or "%d分钟", math.floor((tonumber(value) or 0) + 0.5))
end

T.RegisterOptionModule({
    id = "durability_check",
    category = "interface",
    order = 35,
    titleKey = "GUI_NAV_DURABILITY_CHECK",
    newSince = NEW_SINCE,
    masterToggle = {
        dbPath = DB_KEY .. ".enabled",
        default = false,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_DURABILITY_CHECK_DISPLAY", newSince = NEW_SINCE },
        { type = "check", textKey = "GUI_DURABILITY_CHECK_COMBAT_END", dbPath = DB_KEY .. ".combatEndReminder", default = true, width = 0.5, apply = RefreshReminder, newSince = NEW_SINCE },
        { type = "slider", textKey = "GUI_DURABILITY_CHECK_THRESHOLD", dbPath = DB_KEY .. ".thresholdPct", min = 1, max = 100, step = 1, default = 25, width = 0.5, apply = RefreshReminder, newSince = NEW_SINCE },
        { type = "slider", textKey = "GUI_DURABILITY_CHECK_CRITICAL", dbPath = DB_KEY .. ".criticalPct", min = 1, max = 100, step = 1, default = 10, width = 0.5, apply = RefreshReminder, newSince = NEW_SINCE },
        { type = "slider", textKey = "GUI_DURABILITY_CHECK_DURATION", dbPath = DB_KEY .. ".durationSec", min = 2, max = 30, step = 1, default = 5, width = 0.5, formatFunc = FormatSeconds, apply = RefreshReminder, newSince = NEW_SINCE },
        { type = "slider", textKey = "GUI_DURABILITY_CHECK_REPEAT", dbPath = DB_KEY .. ".repeatMinutes", min = 1, max = 60, step = 1, default = 10, width = 0.5, formatFunc = FormatMinutes, apply = RefreshReminder, newSince = NEW_SINCE },
        { type = "check", textKey = "GUI_DURABILITY_CHECK_TTS", dbPath = DB_KEY .. ".tts", default = false, width = 0.5, apply = RefreshReminder, newSince = NEW_SINCE },
        { type = "subtitle", textKey = "GUI_SUBTITLE_DURABILITY_AUTO_REPAIR", newSince = NEW_SINCE },
        { type = "check", textKey = "GUI_DURABILITY_AUTO_REPAIR", tooltipKey = "GUI_DURABILITY_AUTO_REPAIR_TIP", dbPath = DB_KEY .. ".autoRepair", default = true, width = 0.5, apply = ApplyAutoRepair, newSince = NEW_SINCE },
        { type = "check", textKey = "GUI_DURABILITY_AUTO_REPAIR_GUILD", dbPath = DB_KEY .. ".autoRepairGuildFunds", default = true, width = 0.5, depend = { dbPath = DB_KEY .. ".autoRepair" }, newSince = NEW_SINCE },
        { type = "check", textKey = "GUI_DURABILITY_AUTO_REPAIR_SUMMARY", dbPath = DB_KEY .. ".autoRepairShowSummary", default = true, width = 0.5, depend = { dbPath = DB_KEY .. ".autoRepair" }, newSince = NEW_SINCE },
        }
    end,
})

end)
