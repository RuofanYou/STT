-- 自动战斗日志
-- 按当前区域类型与难度自动开启 /combatlog，离开目标区域时关闭。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("autoLogging.enabled", function()

local AL = T.ModuleLoader:NewModule({
    name = "AutoLogging",
    dbKey = "autoLogging.enabled",
    defaultEnabled = false,
})

function AL:OnRegister()
    T.AutoLogging = self
end
T.AutoLogging = AL

local eventFrame = nil
local pendingTimer = nil

local DIFFICULTY_LFR = 7
local DIFFICULTY_LFR_NEW = 17
local DIFFICULTY_RAID_NORMAL = 14
local DIFFICULTY_RAID_HEROIC = 15
local DIFFICULTY_RAID_MYTHIC = 16
local DIFFICULTY_MYTHIC_KEYSTONE = 8

local function Dbg(...)
    T.debug("[AutoLog]", ...)
end

local function IsEnabled()
    return C.DB and C.DB.autoLogging and C.DB.autoLogging.enabled
end

local function IsCombatLogging()
    if C_ChatInfo and C_ChatInfo.IsLoggingCombat then
        local ok, enabled = pcall(C_ChatInfo.IsLoggingCombat)
        if ok then
            return enabled == true
        end
    end
    return LoggingCombat() == true
end

local function ShouldEnableAdvancedLog(db)
    return db and db.checkAdvanced ~= false
end

local function StartLogging(db)
    if IsCombatLogging() then
        Dbg("StartLogging: already logging, skip")
        return false
    end
    if ShouldEnableAdvancedLog(db) and GetCVar and SetCVar and GetCVar("advancedCombatLogging") ~= "1" then
        SetCVar("advancedCombatLogging", "1")
        Dbg("StartLogging: advancedCombatLogging enabled")
    end
    LoggingCombat(true)
    Dbg("StartLogging: LoggingCombat(true) called")
    T.msg(L["AUTO_LOG_STARTED"])
    return true
end

local function StopLogging()
    if not IsCombatLogging() then
        Dbg("StopLogging: not logging, skip")
        return false
    end
    LoggingCombat(false)
    Dbg("StopLogging: LoggingCombat(false) called")
    T.msg(L["AUTO_LOG_STOPPED"])
    return true
end

local function ShouldLogCurrentInstance(db)
    if type(db) ~= "table" or db.enabled ~= true then
        return false
    end

    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return false
    end

    local _, _, difficultyID = GetInstanceInfo()
    if instanceType == "raid" then
        if difficultyID == DIFFICULTY_RAID_MYTHIC then
            return db.raidMythic ~= false
        elseif difficultyID == DIFFICULTY_RAID_HEROIC then
            return db.raidHeroic ~= false
        elseif difficultyID == DIFFICULTY_RAID_NORMAL then
            return db.raidNormal == true
        elseif difficultyID == DIFFICULTY_LFR or difficultyID == DIFFICULTY_LFR_NEW then
            return db.raidLFR == true
        end
        return false
    end

    if instanceType == "party" then
        if difficultyID == DIFFICULTY_MYTHIC_KEYSTONE then
            return db.mythicPlus ~= false
        end
        return db.dungeon == true
    end

    return false
end
AL.ShouldLogCurrentInstance = ShouldLogCurrentInstance

function AL:ApplyState(verbose)
    local db = C.DB and C.DB.autoLogging
    local target = ShouldLogCurrentInstance(db)
    local current = IsCombatLogging()
    local _, instanceType, difficultyID = GetInstanceInfo()

    Dbg(("ApplyState: enabled=%s type=%s difficulty=%s target=%s current=%s"):format(
        tostring(db and db.enabled), tostring(instanceType), tostring(difficultyID),
        tostring(target), tostring(current)))

    if target == current then
        return
    end

    if target then
        StartLogging(db)
    else
        StopLogging()
    end
end

function AL:ScheduleApplyState()
    if pendingTimer and pendingTimer.Cancel then
        pendingTimer:Cancel()
    end
    pendingTimer = C_Timer.NewTimer(1.5, function()
        pendingTimer = nil
        AL:ApplyState(true)
    end)
end

local function OnEvent(_, event)
    Dbg("Event:", event)
    AL:ScheduleApplyState()
end

local function EnsureFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    return eventFrame
end

local function RegisterEvents()
    EnsureFrame()
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    Dbg("Events registered")
end

local function UnregisterEvents()
    if pendingTimer and pendingTimer.Cancel then
        pendingTimer:Cancel()
        pendingTimer = nil
    end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    Dbg("Events unregistered")
    StopLogging()
end

function AL:OnEnable()
    Dbg("OnEnable")
    RegisterEvents()
    self:ScheduleApplyState()
end

function AL:OnDisable()
    Dbg("OnDisable")
    UnregisterEvents()
end

function AL:Init()
    local enabled = IsEnabled()
    Dbg(("Init: enabled=%s"):format(tostring(enabled)))
    if T.ModuleLoader then
        if enabled then
            T.ModuleLoader:Enable("AutoLogging", "legacy_init")
        else
            T.ModuleLoader:Disable("AutoLogging", "legacy_init")
        end
        return
    end
    if enabled then
        RegisterEvents()
        self:ScheduleApplyState()
    else
        UnregisterEvents()
    end
end

end)
