local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("autoLogging.enabled", function()

local function ApplyAutoLogging()
    if T.ModuleLoader then
        if C.DB and C.DB.autoLogging and C.DB.autoLogging.enabled == true then
            T.ModuleLoader:Enable("AutoLogging", "option")
        else
            T.ModuleLoader:Disable("AutoLogging", "option")
        end
    elseif T.AutoLogging and T.AutoLogging.Init then
        T.AutoLogging:Init()
    end
end

local function ReapplyAutoLogging()
    if T.AutoLogging and T.AutoLogging.ApplyState then
        T.AutoLogging:ApplyState(true)
    end
end

T.RegisterOptionModule({
    id = "autoLogging",
    category = "utility",
    order = 46,
    titleKey = "GUI_NAV_AUTO_LOGGING",
    newSince = "260512.67",
    masterToggle = {
        dbPath = "autoLogging.enabled",
        default = false,
        apply = ApplyAutoLogging,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "AUTO_LOG_SECTION_RAID" },
        {
            key = "raidMythic",
            type = "check",
            textKey = "AUTO_LOG_RAID_MYTHIC",
            width = 0.5,
            dbPath = "autoLogging.raidMythic",
            default = true,
            apply = ReapplyAutoLogging,
            newSince = "260512.67",
        },
        {
            key = "raidHeroic",
            type = "check",
            textKey = "AUTO_LOG_RAID_HEROIC",
            width = 0.5,
            dbPath = "autoLogging.raidHeroic",
            default = true,
            apply = ReapplyAutoLogging,
            newSince = "260512.67",
        },
        {
            key = "raidNormal",
            type = "check",
            textKey = "AUTO_LOG_RAID_NORMAL",
            width = 0.5,
            dbPath = "autoLogging.raidNormal",
            default = false,
            apply = ReapplyAutoLogging,
            newSince = "260512.67",
        },
        {
            key = "raidLFR",
            type = "check",
            textKey = "AUTO_LOG_RAID_LFR",
            width = 0.5,
            dbPath = "autoLogging.raidLFR",
            default = false,
            apply = ReapplyAutoLogging,
            newSince = "260512.67",
        },

        { type = "subtitle", textKey = "AUTO_LOG_SECTION_DUNGEON" },
        {
            key = "mythicPlus",
            type = "check",
            textKey = "AUTO_LOG_MYTHIC_PLUS",
            width = 0.5,
            dbPath = "autoLogging.mythicPlus",
            default = true,
            apply = ReapplyAutoLogging,
            newSince = "260512.67",
        },
        {
            key = "dungeon",
            type = "check",
            textKey = "AUTO_LOG_DUNGEON",
            width = 0.5,
            dbPath = "autoLogging.dungeon",
            default = false,
            apply = ReapplyAutoLogging,
            newSince = "260512.67",
        },

        { type = "subtitle", textKey = "AUTO_LOG_SECTION_SYSTEM" },
        {
            key = "checkAdvanced",
            type = "check",
            textKey = "AUTO_LOG_CHECK_ADVANCED",
            width = 1,
            dbPath = "autoLogging.checkAdvanced",
            default = true,
            apply = ReapplyAutoLogging,
            newSince = "260512.67",
        },
        {
            key = "reapply",
            type = "button",
            textKey = "AUTO_LOG_REAPPLY",
            width = 1,
            onClick = ReapplyAutoLogging,
            newSince = "260512.67",
        },
        }
    end,
})

end)
