local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("CountdownEnabled", function()
local NEW_SINCE = "260511.6"

T.RegisterOptionModule({
    id = "countdown",
    category = "tactic",
    order = 12,
    titleKey = "GUI_NAV_COUNTDOWN",
    masterToggle = {
        dbPath = "CountdownEnabled",
        default = true,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_COUNTDOWN" },
        {
            key = "CountdownChannel",
            type = "dropdown",
            textKey = "GUI_COUNTDOWN_CHANNEL",
            width = 0.5,
            dbPath = "CountdownChannel",
            default = "Master",
            options = {
                { textKey = "GUI_COUNTDOWN_CHANNEL_MASTER", value = "Master" },
                { textKey = "GUI_COUNTDOWN_CHANNEL_SFX", value = "SFX" },
                { textKey = "GUI_COUNTDOWN_CHANNEL_DIALOG", value = "Dialog" },
            },
            tooltipKey = "STT_TT_COUNTDOWN_CHANNEL",
        },
        {
            type = "subtitle",
            textKey = "CT_PACK_SECTION",
            newSince = NEW_SINCE,
        },
        {
            key = "CountdownPack",
            type = "dropdown",
            textKey = "CT_PACK_ACTIVE",
            width = 0.7,
            labelWidth = 96,
            dbPath = "countdown.activePackId",
            default = "stt_default",
            options = function()
                return T.CountdownPacks and T.CountdownPacks.GetDropdownOptions and T.CountdownPacks.GetDropdownOptions() or {}
            end,
            newSince = NEW_SINCE,
            tooltipKey = "STT_TT_COUNTDOWN_PACK",
        },
        {
            key = "CountdownPreview",
            type = "button",
            textKey = "CT_PACK_PREVIEW",
            width = 0.3,
            onClick = function()
                if T.CountdownPacks and T.CountdownPacks.Preview then
                    T.CountdownPacks.Preview(5)
                end
            end,
            newSince = NEW_SINCE,
            tooltipKey = "STT_TT_COUNTDOWN_PREVIEW",
        },
        }
    end,
})

end)
