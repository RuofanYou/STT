local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("raidCommandPanel.enabled", function()

local function ApplyRaidCommandPanel()
    if T.RaidCommandPanel and T.RaidCommandPanel.RefreshConfig then
        T.RaidCommandPanel:RefreshConfig("option")
    end
    if T.ModuleLoader then
        if C.DB and C.DB.raidCommandPanel and C.DB.raidCommandPanel.enabled == true then
            T.ModuleLoader:Enable("RaidCommandPanel", "option")
        else
            T.ModuleLoader:Disable("RaidCommandPanel", "option")
        end
    end
end

local function ToggleLock()
    if T.RaidCommandPanel then
        T.RaidCommandPanel:SetLocked(not T.RaidCommandPanel:IsLocked())
    end
end

local function FormatDeathTTSLimit(value)
    local format = L["RCP_OPT_DEATH_TTS_LIMIT_FMT"] or "%d"
    return string.format(format, math.floor((tonumber(value) or 2) + 0.5))
end

local function FormatStyleScale(value)
    return string.format("%.2fx", tonumber(value) or 1)
end

T.RegisterOptionModule({
    id = "raid_command_panel",
    category = "raidlead",
    order = 47,
    titleKey = "GUI_NAV_RAID_COMMAND_PANEL",
    masterToggle = {
        dbPath = "raidCommandPanel.enabled",
        default = false,
        apply = ApplyRaidCommandPanel,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_GENERAL" },
        { type = "check", textKey = "RCP_OPT_ONLY_INSTANCE", dbPath = "raidCommandPanel.onlyInInstance", default = true, width = 0.5, apply = ApplyRaidCommandPanel },
        {
            key = "toggleLock",
            type = "button",
            textKey = "RCP_OPT_LOCK",
            width = 0.5,
            ignoreModuleDisabled = true,
            onClick = ToggleLock,
        },
        {
            key = "styleScale",
            type = "slider",
            textKey = "RCP_OPT_STYLE_SCALE",
            dbPath = "raidCommandPanel.styleScale",
            default = 1,
            min = 0.8,
            max = 1.8,
            step = 0.05,
            width = 1,
            formatFunc = FormatStyleScale,
            newSince = "260511.19",
            apply = ApplyRaidCommandPanel,
        },

        { type = "subtitle", textKey = "RCP_OPT_SUBMODULES" },
        { type = "check", textKey = "RCP_OPT_REZ_GROUP", dbPath = "raidCommandPanel.rezTracker.enabled", default = true, width = 0.5, apply = ApplyRaidCommandPanel },
        {
            type = "check",
            textKey = "RCP_OPT_REZ_TTS",
            dbPath = "raidCommandPanel.rezTracker.ttsOnUse",
            default = false,
            width = 0.5,
            depend = { dbPath = "raidCommandPanel.rezTracker.enabled" },
            apply = ApplyRaidCommandPanel,
        },
        {
            key = "rezTTStext",
            type = "editbox",
            textKey = "RCP_OPT_REZ_TTS_TEXT",
            dbPath = "raidCommandPanel.rezTracker.ttsOnUseText",
            default = "",
            width = 1,
            maxLetters = 80,
            placeholderTextKey = "RCP_OPT_REZ_TTS_PLACEHOLDER",
            depend = { dbPath = "raidCommandPanel.rezTracker.ttsOnUse" },
            apply = ApplyRaidCommandPanel,
        },
        { type = "check", textKey = "RCP_OPT_LUST_GROUP", dbPath = "raidCommandPanel.lustMonitor.enabled", default = true, width = 0.5, apply = ApplyRaidCommandPanel },
        { type = "check", textKey = "RCP_OPT_TIMER_GROUP", dbPath = "raidCommandPanel.encounterTimer.enabled", default = true, width = 0.5, apply = ApplyRaidCommandPanel },
        {
            type = "check",
            textKey = "RCP_OPT_LUST_TTS",
            dbPath = "raidCommandPanel.lustMonitor.ttsEnding",
            default = false,
            width = 0.5,
            depend = { dbPath = "raidCommandPanel.lustMonitor.enabled" },
            apply = ApplyRaidCommandPanel,
        },
        {
            key = "lustTTStext",
            type = "editbox",
            textKey = "RCP_OPT_LUST_TTS_TEXT",
            dbPath = "raidCommandPanel.lustMonitor.ttsEndingText",
            default = "",
            width = 1,
            maxLetters = 80,
            placeholderTextKey = "RCP_OPT_LUST_TTS_PLACEHOLDER",
            depend = { dbPath = "raidCommandPanel.lustMonitor.ttsEnding" },
            apply = ApplyRaidCommandPanel,
        },
        { type = "check", textKey = "RCP_OPT_DEATH_GROUP", dbPath = "raidCommandPanel.deathLog.enabled", default = true, width = 0.5, apply = ApplyRaidCommandPanel },
        {
            type = "check",
            textKey = "RCP_RECAP_ENABLE",
            dbPath = "raidCommandPanel.deathLog.showRecap",
            default = true,
            width = 0.5,
            depend = { dbPath = "raidCommandPanel.deathLog.enabled" },
            apply = ApplyRaidCommandPanel,
        },
        {
            type = "check",
            textKey = "RCP_OPT_DEATH_TTS",
            dbPath = "raidCommandPanel.deathLog.ttsOnDeath",
            default = false,
            width = 0.5,
            depend = { dbPath = "raidCommandPanel.deathLog.enabled" },
            apply = ApplyRaidCommandPanel,
        },
        {
            key = "deathTTSLimit",
            type = "slider",
            textKey = "RCP_OPT_DEATH_TTS_LIMIT",
            dbPath = "raidCommandPanel.deathLog.ttsDeathLimit",
            default = 2,
            min = 1,
            max = 40,
            step = 1,
            width = 1,
            formatFunc = FormatDeathTTSLimit,
            depend = { dbPath = "raidCommandPanel.deathLog.ttsOnDeath" },
            newSince = "260506.23",
            apply = ApplyRaidCommandPanel,
        },
        {
            key = "deathTTStext",
            type = "editbox",
            textKey = "RCP_OPT_DEATH_TTS_TEXT",
            dbPath = "raidCommandPanel.deathLog.ttsOnDeathText",
            default = "",
            width = 1,
            maxLetters = 80,
            placeholderTextKey = "RCP_OPT_DEATH_TTS_PLACEHOLDER",
            depend = { dbPath = "raidCommandPanel.deathLog.ttsOnDeath" },
            apply = ApplyRaidCommandPanel,
        },

        { type = "subtitle", textKey = "RCP_OPT_ACTIONS" },
        {
            type = "button",
            textKey = "RCP_OPT_TEST",
            width = 0.5,
            ignoreModuleDisabled = true,
            onClick = function()
                if T.RaidCommandPanel and T.RaidCommandPanel.RunTest then
                    if C.DB and C.DB.raidCommandPanel and C.DB.raidCommandPanel.enabled ~= true then
                        C.DB.raidCommandPanel.enabled = true
                        if STT_DB then
                            STT_DB.raidCommandPanel = C.DB.raidCommandPanel
                        end
                        if T.ModuleLoader then
                            T.ModuleLoader:Enable("RaidCommandPanel", "option_test")
                        end
                    end
                    T.RaidCommandPanel:RunTest()
                end
            end,
        },
        {
            type = "button",
            textKey = "RCP_OPT_RESET_POS",
            width = 0.5,
            ignoreModuleDisabled = true,
            onClick = function()
                if T.RaidCommandPanel and T.RaidCommandPanel.ResetPosition then
                    T.RaidCommandPanel:ResetPosition()
                end
            end,
        },
        }
    end,
})

end)
