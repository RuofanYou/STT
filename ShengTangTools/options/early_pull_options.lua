local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("earlyPull.enabled", function()

T.RegisterOptionModule({
    id = "earlyPull",
    category = "raidlead",
    order = 45,
    titleKey = "GUI_NAV_EARLY_PULL",
    beta = true,
    masterToggle = {
        dbPath = "earlyPull.enabled",
        default = false,
    },
    itemsFactory = function()
        return {
        {
            type = "check",
            textKey = "EARLY_PULL_RAID_ONLY",
            dbPath = "earlyPull.raidOnly",
            default = true,
        },
        {
            type = "check",
            textKey = "EARLY_PULL_BIG_TEXT",
            dbPath = "earlyPull.bigText",
            default = true,
        },
        {
            type = "check",
            textKey = "EARLY_PULL_TTS",
            dbPath = "earlyPull.tts",
            default = false,
        },
        }
    end,
})

end)
