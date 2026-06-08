local T = unpack(select(2, ...))

local function RefreshTimelineAutoEvents()
    if T.TimelineRunner and T.TimelineRunner.RefreshAutoEvents then
        T.TimelineRunner:RefreshAutoEvents()
    end
end

local function RegisterShellModule(name, dbKey, handlers)
    local module = T.ModuleLoader:NewModule({
        name = name,
        dbKey = dbKey,
        defaultEnabled = false,
    })
    if type(handlers) == "table" then
        for key, value in pairs(handlers) do
            module[key] = value
        end
    end
    return module
end

local function RegisterShellWhenCold(name, dbKey, handlers)
    if T.ShouldLoadFeature and T.ShouldLoadFeature(dbKey, false) then
        return nil
    end
    handlers = handlers or {}
    handlers._isColdShell = true
    return RegisterShellModule(name, dbKey, handlers)
end

RegisterShellModule("TacticRuntime", "semanticTimeline.runtimeEnabled", {
    IsRuntimeLoaded = function()
        return T.SemanticTimeline ~= nil
    end,
    OnEnable = function()
        if T.SemanticTimeline and T.SemanticTimeline.OnEnable then
            T.SemanticTimeline:OnEnable()
        end
    end,
    OnDisable = function()
        if T.SemanticTimeline and T.SemanticTimeline.OnDisable then
            T.SemanticTimeline:OnDisable()
        end
    end,
})

RegisterShellModule("Voice", "ttsEnabled", {
    dependencies = { "TacticRuntime" },
    OnEnable = RefreshTimelineAutoEvents,
    OnDisable = function()
        if T.ClearTTSQueue then
            T.ClearTTSQueue()
        end
        RefreshTimelineAutoEvents()
    end,
})

RegisterShellModule("Countdown", "CountdownEnabled", {
    dependencies = { "TacticRuntime" },
    OnEnable = RefreshTimelineAutoEvents,
    OnDisable = RefreshTimelineAutoEvents,
})

RegisterShellModule("SegmentedBar", "Bar.Enabled", {
    dependencies = { "TacticRuntime" },
    OnEnable = RefreshTimelineAutoEvents,
    OnDisable = function()
        if T.ClearAllBars then
            T.ClearAllBars()
        end
        RefreshTimelineAutoEvents()
    end,
})

RegisterShellModule("BlizzardTimeline", "blizzardTimeline.enabled", {
    dependencies = { "TacticRuntime" },
    OnEnable = function()
        if T.BlizzardTimeline and T.BlizzardTimeline.ApplyViewSettings then
            T.BlizzardTimeline:ApplyViewSettings()
        end
        RefreshTimelineAutoEvents()
    end,
    OnDisable = function()
        if T.BlizzardTimeline and T.BlizzardTimeline.ClearInjected then
            T.BlizzardTimeline:ClearInjected()
        end
        RefreshTimelineAutoEvents()
    end,
})

RegisterShellModule("ScreenReminder", "screenReminder.enabled", {
    dependencies = { "TacticRuntime" },
    OnEnable = RefreshTimelineAutoEvents,
    OnDisable = function()
        if T.ScreenReminder and T.ScreenReminder.ClearAll then
            T.ScreenReminder:ClearAll()
        end
        RefreshTimelineAutoEvents()
    end,
})

RegisterShellModule("FriendlyNameplate", "friendlyNameplate.enabled", {
    OnEnable = function()
        if T.FriendlyNameplate and T.FriendlyNameplate.OnEnable then
            T.FriendlyNameplate:OnEnable()
        end
    end,
    OnDisable = function()
        if T.FriendlyNameplate and T.FriendlyNameplate.OnDisable then
            T.FriendlyNameplate:OnDisable()
        end
    end,
})

RegisterShellModule("SemanticTimeline", "semanticTimeline.enabled", {
    dependencies = { "TacticRuntime" },
})

RegisterShellModule("TacticalUI", "semanticTimeline.ui.enabled", {
    dependencies = { "SemanticTimeline" },
})
RegisterShellModule("VersionCheck", "versionCheck.enabled")
RegisterShellModule("TacticTranslator", "tacticTranslator.enabled")
RegisterShellModule("DurabilityCheck", "buffCheck.repairReminder.enabled", {
    OnEnable = function()
        if T.BuffCheck and T.BuffCheck.ApplyEnabledState then
            T.BuffCheck:ApplyEnabledState()
        end
    end,
    OnDisable = function()
        if T.BuffCheck and T.BuffCheck.ApplyEnabledState then
            T.BuffCheck:ApplyEnabledState()
        end
    end,
})

RegisterShellWhenCold("AutoLogging", "autoLogging.enabled")
RegisterShellWhenCold("EarlyPull", "earlyPull.enabled")
RegisterShellWhenCold("BuffCheck", "buffCheck.enabled")
RegisterShellWhenCold("RaidCommandPanel", "raidCommandPanel.enabled")
RegisterShellWhenCold("RosterPlanner", "rosterPlanner.enabled")
RegisterShellWhenCold("RealtimeBoard", "realtimeBoard.enabled")
RegisterShellWhenCold("DreadElegy", "dreadElegy.enabled")
RegisterShellWhenCold("AuraColorAlert", "auraColorAlert.enabled")
RegisterShellWhenCold("PersonalAuraAlert", "personalAuraAlert.enabled")
RegisterShellWhenCold("InterruptRotation", "interruptRotation.enabled")
RegisterShellWhenCold("SuperZoom", "superZoom.enabled")
RegisterShellWhenCold("PrivateAuraList", "privateAuraList.enabled")
RegisterShellWhenCold("PrivateAuraHijack", "privateAuraHijack.enabled")
RegisterShellWhenCold("LuraCrystalAlert", "luraCrystal.enabled")
RegisterShellWhenCold("CastRecorder", "castRecorder.backendEnabled")
RegisterShellWhenCold("SelfMarker", "selfMarker.enabled")
