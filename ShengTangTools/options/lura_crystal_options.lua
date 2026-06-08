local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("luraCrystal.enabled", function()

local NEW_SINCE = "260521.24"
local DEFAULT_CRYSTAL_INDICATOR = "计时条#1"

local function ApplyCrystalAlert()
    if T.LuraCrystalAlert and T.LuraCrystalAlert.ApplySettings then
        T.LuraCrystalAlert:ApplySettings()
    end
end

local function TestCrystalAlert()
    if T.LuraCrystalAlert and T.LuraCrystalAlert.Test then
        T.LuraCrystalAlert:Test()
    end
end

local function FormatSeconds(value)
    return string.format("%.1f秒", tonumber(value) or 0)
end

local function BuildCrystalIndicatorItems()
    local selected = C.DB and C.DB.luraCrystal and C.DB.luraCrystal.indicatorName or DEFAULT_CRYSTAL_INDICATOR
    if T.ScreenReminderAlert and T.ScreenReminderAlert.BuildIndicatorItems then
        return T.ScreenReminderAlert:BuildIndicatorItems(
            selected,
            DEFAULT_CRYSTAL_INDICATOR,
            L["LURA_CRYSTAL_STYLE_MISSING"] or "当前选择：%s（未找到）"
        )
    end
    return {
        { text = DEFAULT_CRYSTAL_INDICATOR, value = DEFAULT_CRYSTAL_INDICATOR },
    }
end

local function RenderCrystalDescription(slot, context)
    local width = math.max(280, tonumber(context and context.width) or 280)
    T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -4 },
        width = width - 8,
        text = L["LURA_CRYSTAL_DURATION_DESC"]
            or "这是放下黎明水晶后的爆炸前窗口；倒计时结束后，水晶开始对全团造成 AOE 伤害，请在倒计时结束前捡起。",
        size = 11,
        color = { 0.75, 0.75, 0.75, 1 },
        wordWrap = true,
    })
    return { height = 44 }
end

T.RegisterOptionModule({
    id = "luraCrystal",
    category = "dungeon",
    order = 48.5,
    titleKey = "GUI_NAV_LURA_CRYSTAL",
    newSince = NEW_SINCE,
    masterToggle = {
        dbPath = "luraCrystal.enabled",
        default = false,
        apply = ApplyCrystalAlert,
    },
    itemsFactory = function()
        return {
        {
            type = "dropdown",
            textKey = "LURA_CRYSTAL_ALERT_STYLE",
            dbPath = "luraCrystal.indicatorName",
            default = DEFAULT_CRYSTAL_INDICATOR,
            options = BuildCrystalIndicatorItems,
            depend = { key = "enabled" },
            apply = ApplyCrystalAlert,
            newSince = NEW_SINCE,
        },
        {
            type = "slider",
            textKey = "LURA_CRYSTAL_ALERT_DURATION",
            tooltipKey = "LURA_CRYSTAL_ALERT_DURATION_TIP",
            dbPath = "luraCrystal.durationSec",
            default = 3,
            min = 1,
            max = 5,
            step = 0.1,
            formatFunc = FormatSeconds,
            depend = { key = "enabled" },
            apply = ApplyCrystalAlert,
            newSince = NEW_SINCE,
        },
        {
            type = "check",
            textKey = "LURA_CRYSTAL_COUNTDOWN_AUDIO",
            tooltipKey = "LURA_CRYSTAL_COUNTDOWN_AUDIO_TIP",
            dbPath = "luraCrystal.countdownAudioEnabled",
            default = true,
            depend = { key = "enabled" },
            apply = ApplyCrystalAlert,
            newSince = NEW_SINCE,
        },
        {
            key = "crystalDurationDesc",
            type = "custom",
            width = 1,
            height = 44,
            depend = { key = "enabled" },
            render = RenderCrystalDescription,
        },
        {
            type = "button",
            width = 1,
            textKey = "LURA_CRYSTAL_ALERT_TEST",
            depend = { key = "enabled" },
            onClick = TestCrystalAlert,
            newSince = NEW_SINCE,
        },
        }
    end,
})

end)
