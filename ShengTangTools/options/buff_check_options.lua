local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("buffCheck.enabled", function()

local function ApplyBuffCheckEnabled()
    if T.BuffCheck and T.BuffCheck.ApplyEnabledState then
        T.BuffCheck:ApplyEnabledState()
    end
end

local function RefreshBuffCheck()
    if T.BuffCheck and T.BuffCheck.Refresh then
        T.BuffCheck:Refresh()
    end
end

local function HandlePanelButtonClick(action, callback)
    if T.BuffCheck and T.BuffCheck.DebugEvent then
        T.BuffCheck:DebugEvent("OptionButtonClick", {
            action = action,
            enabled = T.BuffCheck:IsEnabled() and "true" or "false",
        })
    end
    if type(callback) == "function" then
        callback()
    end
end

T.RegisterOptionModule({
    id = "buff_check",
    category = "raidlead",
    order = 46,
    titleKey = "GUI_NAV_BUFF_CHECK",
    beta = true,
    masterToggle = {
        dbPath = "buffCheck.enabled",
        default = false,
        apply = ApplyBuffCheckEnabled,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_BUFF_TRIGGER" },
        {
            type = "check",
            textKey = "GUI_BUFF_AUTO_SHOW_ON_READY_CHECK",
            dbPath = "buffCheck.autoShowOnReadyCheck",
            default = true,
            width = 0.5,
        },
        {
            type = "slider",
            textKey = "GUI_BUFF_AUTO_HIDE_DELAY",
            dbPath = "buffCheck.autoHideDelaySec",
            min = 5,
            max = 60,
            step = 5,
            default = 15,
            width = 0.5,
        },
        {
            type = "dropdown",
            textKey = "GUI_BUFF_CHAT_CHANNEL",
            dbPath = "buffCheck.chatBroadcastChannel",
            default = "NONE",
            width = 0.5,
            options = {
                { textKey = "GUI_BUFF_CHANNEL_NONE", value = "NONE" },
                { textKey = "GUI_BUFF_CHANNEL_RAID", value = "RAID" },
                { textKey = "GUI_BUFF_CHANNEL_RAID_WARNING", value = "RAID_WARNING" },
                { textKey = "GUI_BUFF_CHANNEL_PARTY", value = "PARTY" },
            },
        },

        { type = "subtitle", textKey = "GUI_SUBTITLE_BUFF_DIMENSIONS" },
        { type = "check", textKey = "GUI_BUFF_CHECK_FOOD", dbPath = "buffCheck.checks.food", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_CHECK_FLASK", dbPath = "buffCheck.checks.flask", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_CHECK_RUNE", dbPath = "buffCheck.checks.rune", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_CHECK_VANTUS", dbPath = "buffCheck.checks.vantus", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_CHECK_WEAPON_ENCHANT", dbPath = "buffCheck.checks.weaponEnchantMain", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_CHECK_WEAPON_ENCHANT_OH", dbPath = "buffCheck.checks.weaponEnchantOff", default = false, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_CHECK_DURABILITY", dbPath = "buffCheck.checks.durability", default = true, width = 0.5, apply = RefreshBuffCheck },

        { type = "subtitle", textKey = "GUI_SUBTITLE_BUFF_RAID_BUFFS" },
        { type = "check", textKey = "GUI_BUFF_RAIDBUFF_AP", dbPath = "buffCheck.checks.raidBuffAP", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_RAIDBUFF_STAMINA", dbPath = "buffCheck.checks.raidBuffStamina", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_RAIDBUFF_INTELLECT", dbPath = "buffCheck.checks.raidBuffIntellect", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_RAIDBUFF_VERSATILITY", dbPath = "buffCheck.checks.raidBuffVersatility", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_RAIDBUFF_MASTERY", dbPath = "buffCheck.checks.raidBuffMastery", default = true, width = 0.5, apply = RefreshBuffCheck },
        { type = "check", textKey = "GUI_BUFF_RAIDBUFF_MOVEMENT", dbPath = "buffCheck.checks.raidBuffMovement", default = true, width = 0.5, apply = RefreshBuffCheck },

        { type = "subtitle", textKey = "GUI_SUBTITLE_BUFF_THRESHOLD" },
        { type = "slider", textKey = "GUI_BUFF_MIN_FOOD_TIER", dbPath = "buffCheck.minFoodTier", min = 0, max = 90, step = 10, default = 0, width = 0.5, apply = RefreshBuffCheck },
        { type = "slider", textKey = "GUI_BUFF_MIN_FLASK_TIER", dbPath = "buffCheck.minFlaskTier", min = 0, max = 165, step = 5, default = 0, width = 0.5, apply = RefreshBuffCheck },
        { type = "slider", textKey = "GUI_BUFF_MIN_DURABILITY", dbPath = "buffCheck.minDurabilityPct", min = 10, max = 100, step = 5, default = 50, width = 0.5, apply = RefreshBuffCheck },

        { type = "subtitle", textKey = "GUI_SUBTITLE_BUFF_PANEL" },
        { type = "button", textKey = "GUI_BUFF_OPEN_PANEL", width = 0.5, ignoreModuleDisabled = true, onClick = function()
            HandlePanelButtonClick("open_personal", T.BuffCheck and function()
                T.BuffCheck.testMode = false
                T.BuffCheck:ScanSelf()
                T.BuffCheck:BroadcastOwnDurability("options_personal", false)
                T.BuffCheck:ShowPersonal({ force = true, source = "options" })
            end)
        end },
        { type = "button", textKey = "GUI_BUFF_OPEN_RAID_PANEL", width = 0.5, ignoreModuleDisabled = true, onClick = function()
            HandlePanelButtonClick("open_raid", T.BuffCheck and function()
                T.BuffCheck.testMode = false
                T.BuffCheck:ScanRaidIfLead()
                T.BuffCheck:BroadcastOwnDurability("options_raid", true)
                T.BuffCheck:ShowRaid({ force = true, source = "options" })
            end)
        end },
        { type = "button", textKey = "GUI_BUFF_TEST", width = 0.5, ignoreModuleDisabled = true, onClick = function()
            HandlePanelButtonClick("test", T.BuffCheck and function() T.BuffCheck:RunTest({ source = "options" }) end)
        end },
        { type = "button", textKey = "GUI_BUFF_RESET_POSITION", width = 0.5, ignoreModuleDisabled = true, onClick = function()
            HandlePanelButtonClick("reset_position", nil)
            local defaultPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 100 }
            T.OptionEngine:SetValue("buffCheck.ui.panels.personal.position", defaultPos)
            T.OptionEngine:SetValue("buffCheck.ui.panels.raid.position", defaultPos)
            if T.BuffCheck then
                T.BuffCheck:Refresh()
            end
        end },
        }
    end,
})

end)
