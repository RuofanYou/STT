local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("rosterPlanner.enabled", function()

local function ApplyRosterPlanner()
    local debugOn = C and C.DB and C.DB.debugMode == true
    if not debugOn and C.DB and C.DB.rosterPlanner then
        C.DB.rosterPlanner.enabled = false
        if STT_DB and STT_DB.rosterPlanner then
            STT_DB.rosterPlanner.enabled = false
        end
    end
    if T.RosterPlanner and T.RosterPlanner.RefreshConfig then
        T.RosterPlanner:RefreshConfig("option")
    end
    if T.ModuleLoader then
        if C.DB and C.DB.rosterPlanner and C.DB.rosterPlanner.enabled == true then
            T.ModuleLoader:Enable("RosterPlanner", "option")
        else
            T.ModuleLoader:Disable("RosterPlanner", "option")
        end
    end
end

local function RenderRosterPlanner(slot, context)
    if T.RosterPlannerGUI and T.RosterPlannerGUI.RenderSettingsPanel then
        return T.RosterPlannerGUI:RenderSettingsPanel(slot, context)
    end
    T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -4 },
        text = L["RP_MSG_GUI_NOT_READY"] or "阵容设置助手界面尚未加载，请 /reload 后重试。",
        color = { 1, 0.55, 0.45, 1 },
    })
    return { height = 56 }
end

T.RegisterOptionModule({
    id = "roster_planner",
    category = "raidlead",
    order = 48,
    titleKey = "GUI_NAV_ROSTER_PLANNER",
    beta = true,
    masterToggle = {
        dbPath = "rosterPlanner.enabled",
        default = false,
        apply = ApplyRosterPlanner,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "RP_OPT_ACTIONS" },
        {
            type = "custom",
            height = 840,
            ignoreModuleDisabled = true,
            render = RenderRosterPlanner,
        },
        }
    end,
})

end)
