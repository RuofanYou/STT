local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("raidCommandPanel.enabled", function()

local RCP = T.ModuleLoader:NewModule({
    name = "RaidCommandPanel",
    dbKey = "raidCommandPanel.enabled",
    defaultEnabled = false,
})

T.RaidCommandPanel = RCP

local REBIRTH_SPELL_ID = 20484
local SOULSTONE_BUFF_ID = 20707
local IDLE_TIMEOUT_SECONDS = 300
local DEATH_EVENT_WINDOW_SECONDS = 15
local DEATH_EVENT_BUFFER_MAX = 40

local STATIC_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "GROUP_ROSTER_UPDATE",
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "UNIT_AURA",
    "UNIT_FLAGS",
    "UNIT_HEALTH",
    "SPELL_UPDATE_CHARGES",
}
-- COMBAT_LOG_EVENT_UNFILTERED 在 12.0.x 污染栈下会触发 ADDON_ACTION_FORBIDDEN；
-- RCP 先停用这条增强监听，保留其他事件链路避免刷错。

local METHOD_BY_SPELLID = {
    [20484] = "rebirth",
    [61999] = "raise_ally",
    [95750] = "soulstone",
    [391054] = "intercession",
}

local LUST_BUFFS = {
    2825,
    32182,
    80353,
    264667,
    390386,
    178207,
    230935,
    309658,
}

local SATED_DEBUFFS = {
    57723,
    57724,
    80354,
    95809,
    390435,
}

local runtime = {
    session = nil,
    topRow = {
        charges = nil,
        maxCharges = nil,
        nextChargeETA = nil,
        lustState = "none",
        lustExpiration = nil,
    },
    pendingRefresh = false,
    refreshTimer = nil,
    idleTicker = nil,
    tickerFrame = nil,
    tickerElapsed = 0,
    lastActivityTime = 0,
    lustEndingKey = nil,
    soulstoneName = nil,
    soulstoneUnits = {},
    unitDeadState = {},
    recapCache = {},
    recapCacheOrder = {},
    recentEventsByGUID = {},
    recentEventsByName = {},
    recentEventProbeCount = 0,
    healthSnapshotsByGUID = {},
    healthSnapshotsByName = {},
    healthSecretSkippedLogged = false,
    damageMeterUnavailableLogged = false,
    secretUnitSkippedLogged = false,
    combatLogProbeLogged = false,
    testMode = false,
    configActive = false,
}

local bitBand = bit and bit.band
local GROUP_AFFILIATION_FLAGS = (COMBATLOG_OBJECT_AFFILIATION_MINE or 0)
    + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0)
    + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0)

local function Debug(fmt, ...)
    if not T.debug then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[RCP] " .. tostring(fmt), ...))
    else
        T.debug("[RCP] " .. tostring(fmt))
    end
end

local function IsSecretValue(value)
    if value == nil then
        return false
    end
    if T.EncounterEventResolver and T.EncounterEventResolver.IsSecretValue then
        return T.EncounterEventResolver.IsSecretValue(value)
    end
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        if ok and result == true then
            return true
        end
    end
    if type(issecrettable) == "function" then
        local ok, result = pcall(issecrettable, value)
        if ok and result == true then
            return true
        end
    end
    return false
end

local function GetNow()
    return (GetTime and tonumber(GetTime())) or 0
end

local function EnsureDB()
    if type(C.DB.raidCommandPanel) ~= "table" then
        C.DB.raidCommandPanel = {}
    end
    local db = C.DB.raidCommandPanel
    local defaults = C.defaults and C.defaults.raidCommandPanel or {}
    if type(db.position) ~= "table" then
        db.position = {}
    end
    if type(db.rezTracker) ~= "table" then
        db.rezTracker = {}
    end
    if type(db.lustMonitor) ~= "table" then
        db.lustMonitor = {}
    end
    if type(db.encounterTimer) ~= "table" then
        db.encounterTimer = {}
    end
    if type(db.deathLog) ~= "table" then
        db.deathLog = {}
    end

    for key, value in pairs(defaults) do
        if type(value) ~= "table" and db[key] == nil then
            db[key] = value
        end
    end
    for key, value in pairs(defaults.position or {}) do
        if db.position[key] == nil then
            db.position[key] = value
        end
    end
    for key, value in pairs(defaults.rezTracker or {}) do
        if db.rezTracker[key] == nil then
            db.rezTracker[key] = value
        end
    end
    for key, value in pairs(defaults.lustMonitor or {}) do
        if db.lustMonitor[key] == nil then
            db.lustMonitor[key] = value
        end
    end
    for key, value in pairs(defaults.encounterTimer or {}) do
        if db.encounterTimer[key] == nil then
            db.encounterTimer[key] = value
        end
    end
    for key, value in pairs(defaults.deathLog or {}) do
        if db.deathLog[key] == nil then
            db.deathLog[key] = value
        end
    end
    if STT_DB then
        STT_DB.raidCommandPanel = db
    end
    return db
end

local function IsSubModuleEnabled(key)
    local db = EnsureDB()
    return db[key] and db[key].enabled == true
end

local function ClearRecapCache()
    wipe(runtime.recapCache)
    wipe(runtime.recapCacheOrder)
end

local function AnySubModuleEnabled()
    return IsSubModuleEnabled("rezTracker") or IsSubModuleEnabled("lustMonitor") or IsSubModuleEnabled("encounterTimer") or IsSubModuleEnabled("deathLog")
end

local function IsRuntimeActive()
    return runtime.testMode == true or runtime.configActive == true
end

local function RefreshRuntimeActive()
    local db = EnsureDB()
    runtime.configActive = db.enabled == true and AnySubModuleEnabled()
    return IsRuntimeActive()
end

local function IsAllowedByInstance()
    local db = EnsureDB()
    if db.onlyInInstance ~= true then
        return true
    end
    local inInstance = IsInInstance and IsInInstance()
    return inInstance == true
end

local function GetUnitName(unit)
    local name, realm = UnitName(unit)
    if not name then
        return nil
    end
    if IsSecretValue(name) then
        return name
    end
    if name == "" then
        return nil
    end
    local fullName = realm and not IsSecretValue(realm) and realm ~= "" and (name .. "-" .. realm) or name
    if Ambiguate then
        return Ambiguate(fullName, "short")
    end
    return fullName
end

local function CacheUnit(session, unit)
    if not UnitExists or not UnitExists(unit) then
        return
    end
    local guid = UnitGUID(unit)
    if not guid or IsSecretValue(guid) then
        return
    end
    local _, classFile = UnitClass(unit)
    session.rosterCache[guid] = {
        name = GetUnitName(unit) or guid,
        class = classFile,
        unit = unit,
    }
end

local function CacheRoster(session)
    if not session then
        return
    end
    session.rosterCache = {}
    CacheUnit(session, "player")
    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for index = 1, count do
            CacheUnit(session, "raid" .. index)
        end
    elseif IsInGroup and IsInGroup() then
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for index = 1, count do
            CacheUnit(session, "party" .. index)
        end
    end
    Debug("RosterCached count=%d", (function()
        local count = 0
        for _ in pairs(session.rosterCache) do
            count = count + 1
        end
        return count
    end)())
end

local function GetSoulstoneName()
    if runtime.soulstoneName then
        return runtime.soulstoneName
    end
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(SOULSTONE_BUFF_ID)
    elseif GetSpellInfo then
        name = GetSpellInfo(SOULSTONE_BUFF_ID)
    end
    runtime.soulstoneName = name or "Soulstone"
    return runtime.soulstoneName
end

local function UnitHasSoulstone(unit)
    if unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(SOULSTONE_BUFF_ID) ~= nil
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        return C_UnitAuras.GetAuraDataBySpellName(unit, GetSoulstoneName(), "HELPFUL") ~= nil
    end
    return false
end

local function FindDeathByGUID(guid, requireUnresolved)
    local session = runtime.session
    if not session or not guid or IsSecretValue(guid) then
        return nil
    end
    for index = #session.deaths, 1, -1 do
        local death = session.deaths[index]
        if death.guid == guid and (not requireUnresolved or not death.resurrected) then
            return death
        end
    end
    return nil
end

local function FindDeathByUnitKey(unitKey, requireUnresolved)
    local session = runtime.session
    if not session or not unitKey then
        return nil
    end
    for index = #session.deaths, 1, -1 do
        local death = session.deaths[index]
        if death.unitKey == unitKey and (not requireUnresolved or not death.resurrected) then
            return death
        end
    end
    return nil
end

local function ResolveName(guid, eventName)
    local session = runtime.session
    local meta = (guid and not IsSecretValue(guid) and session and session.rosterCache) and session.rosterCache[guid] or nil
    if meta and meta.name then
        return meta.name
    end
    if eventName and IsSecretValue(eventName) then
        return eventName
    end
    if eventName and eventName ~= "" then
        return Ambiguate and Ambiguate(eventName, "short") or eventName
    end
    return UNKNOWN or "Unknown"
end

local function IsGroupPlayerDeath(flags)
    if not flags or IsSecretValue(flags) or not bitBand then
        return false
    end
    return bitBand(flags, COMBATLOG_OBJECT_TYPE_PLAYER or 0) ~= 0
        and bitBand(flags, GROUP_AFFILIATION_FLAGS) ~= 0
end

local AnnounceDeathCaptured

local function ClearRecentEvents()
    wipe(runtime.recentEventsByGUID)
    wipe(runtime.recentEventsByName)
    runtime.recentEventProbeCount = 0
    wipe(runtime.healthSnapshotsByGUID)
    wipe(runtime.healthSnapshotsByName)
    runtime.healthSecretSkippedLogged = false
end

local function NormalizeEventName(value)
    if not value or IsSecretValue(value) then
        return nil
    end
    local name = tostring(value)
    if name == "" then
        return nil
    end
    return Ambiguate and Ambiguate(name, "short") or name
end

local function IsRosterMemberEvent(destGUID, destName)
    local session = runtime.session
    if not session then
        return false
    end
    if destGUID and not IsSecretValue(destGUID) and session.rosterCache[destGUID] then
        return true
    end
    local shortName = NormalizeEventName(destName)
    if not shortName then
        return false
    end
    for _, meta in pairs(session.rosterCache or {}) do
        if NormalizeEventName(meta.name) == shortName then
            return true
        end
    end
    return false
end

local function IsGroupPlayerEvent(destGUID, destName, destFlags)
    return IsGroupPlayerDeath(destFlags) or IsRosterMemberEvent(destGUID, destName)
end

local function GetUnitHealthSnapshot(unitGUID)
    if not unitGUID or IsSecretValue(unitGUID) or not UnitGUID or not UnitHealth or not UnitHealthMax then
        return nil, nil
    end
    local function read(unit)
        if UnitExists and not UnitExists(unit) then
            return nil, nil
        end
        if UnitGUID(unit) ~= unitGUID then
            return nil, nil
        end
        local current = tonumber(UnitHealth(unit))
        local maxHealth = tonumber(UnitHealthMax(unit))
        if not current or not maxHealth or maxHealth <= 0 then
            return nil, nil
        end
        return current, current / maxHealth
    end

    local current, pct = read("player")
    if current then
        return current, pct
    end
    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for index = 1, count do
            current, pct = read("raid" .. index)
            if current then
                return current, pct
            end
        end
    elseif IsInGroup and IsInGroup() then
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for index = 1, count do
            current, pct = read("party" .. index)
            if current then
                return current, pct
            end
        end
    end
    return nil, nil
end

local function TrimRecentEventList(list, minTime)
    while #list > 0 and ((tonumber(list[1].capturedAt) or 0) < minTime or #list > DEATH_EVENT_BUFFER_MAX) do
        table.remove(list, 1)
    end
end

local function StoreRecentEvent(index, key, payload, minTime)
    if not key or IsSecretValue(key) then
        return
    end
    local list = index[key]
    if not list then
        list = {}
        index[key] = list
    end
    list[#list + 1] = payload
    TrimRecentEventList(list, minTime)
end

local function StoreRecentEventPayload(destGUID, destName, payload)
    if type(payload) ~= "table" then
        return
    end
    local now = GetNow()
    local publicGUID = destGUID and not IsSecretValue(destGUID) and destGUID or nil
    local shortName = NormalizeEventName(destName)
    if not publicGUID and not shortName then
        return
    end
    local currentHP, healthPercent = nil, nil
    if publicGUID then
        currentHP, healthPercent = GetUnitHealthSnapshot(publicGUID)
    end
    payload.capturedAt = now
    payload.eventTime = payload.eventTime or now
    payload.sessionTime = runtime.session and (now - runtime.session.startTime) or nil
    payload.currentHP = payload.currentHP or currentHP
    payload.healthPercent = payload.healthPercent or healthPercent
    local minTime = now - DEATH_EVENT_WINDOW_SECONDS
    StoreRecentEvent(runtime.recentEventsByGUID, publicGUID, payload, minTime)
    StoreRecentEvent(runtime.recentEventsByName, shortName, payload, minTime)
    if runtime.recentEventProbeCount < 8 then
        runtime.recentEventProbeCount = runtime.recentEventProbeCount + 1
        Debug("RecentEventCaptured event=%s dest=%s guid=%s amount=%s overheal=%s effective=%s source=%s", tostring(payload.event), tostring(shortName or destName), tostring(publicGUID or "-"), tostring(payload.amount), tostring(payload.overhealing or "-"), tostring(payload.effectiveAmount or "-"), tostring(payload.sourceName or "-"))
    end
end

local function RecordRecentCombatEvent(destGUID, destName, destFlags, payload)
    if not IsGroupPlayerEvent(destGUID, destName, destFlags) then
        return
    end
    StoreRecentEventPayload(destGUID, destName, payload)
end

local function RecordCombatLogRecapEvent(subevent, sourceName, destGUID, destName, destFlags, spellID, amount, absorbed, critical, overhealing, effectiveAmount)
    if subevent ~= "SPELL_HEAL" and subevent ~= "SPELL_PERIODIC_HEAL" and subevent ~= "SPELL_HEAL_ABSORBED" and subevent ~= "SPELL_ABSORBED" then
        return
    end
    local numericAmount = tonumber(amount)
    if not numericAmount or numericAmount <= 0 then
        return
    end
    local displayAmount = numericAmount
    if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        displayAmount = tonumber(effectiveAmount) or numericAmount
        if displayAmount <= 0 then
            return
        end
    end
    RecordRecentCombatEvent(destGUID, destName, destFlags, {
        event = subevent,
        spellID = spellID,
        amount = displayAmount,
        rawAmount = numericAmount,
        absorbed = absorbed,
        critical = critical,
        overhealing = overhealing,
        effectiveAmount = effectiveAmount,
        sourceName = sourceName,
        destName = NormalizeEventName(destName) or destName,
    })
end

local function ToPublicNumber(value)
    if value == nil then
        return nil, false
    end
    if IsSecretValue(value) then
        return nil, true
    end
    local ok, numberValue = pcall(tonumber, value)
    if not ok or type(numberValue) ~= "number" then
        return nil, false
    end
    local mathOK = pcall(function()
        return numberValue + 0
    end)
    if not mathOK then
        return nil, true
    end
    return numberValue, false
end

local function LogHealthSnapshotSkipped(unit, field)
    if runtime.healthSecretSkippedLogged then
        return
    end
    runtime.healthSecretSkippedLogged = true
    Debug("HealthSnapshotSkipped reason=secret unit=%s field=%s", tostring(unit), tostring(field or "unknown"))
end

local function ReadUnitHealth(unit)
    if not unit or IsSecretValue(unit) or not UnitExists or not UnitExists(unit) then
        return nil
    end
    local guid = UnitGUID and UnitGUID(unit)
    if not guid or IsSecretValue(guid) then
        return nil
    end
    local current, currentSecret = ToPublicNumber(UnitHealth and UnitHealth(unit) or nil)
    local maxHealth, maxSecret = ToPublicNumber(UnitHealthMax and UnitHealthMax(unit) or nil)
    if currentSecret then
        LogHealthSnapshotSkipped(unit, "current")
    elseif maxSecret then
        LogHealthSnapshotSkipped(unit, "max")
    end
    if not current or not maxHealth or maxHealth <= 0 then
        return nil
    end
    local name = GetUnitName(unit)
    return {
        guid = guid,
        name = name,
        current = current,
        maxHealth = maxHealth,
        healthPercent = current / maxHealth,
    }
end

local function StoreHealthSnapshot(snapshot)
    if type(snapshot) ~= "table" or not snapshot.guid then
        return
    end
    snapshot.updatedAt = GetNow()
    runtime.healthSnapshotsByGUID[snapshot.guid] = snapshot
    local shortName = NormalizeEventName(snapshot.name)
    if shortName then
        runtime.healthSnapshotsByName[shortName] = snapshot
    end
end

local function UpdateHealthSnapshot(unit, recordGain)
    local session = runtime.session
    if not session or session.endTime then
        return
    end
    local snapshot = ReadUnitHealth(unit)
    if not snapshot then
        return
    end
    local previous = runtime.healthSnapshotsByGUID[snapshot.guid]
    local previousCurrent = nil
    if previous then
        previousCurrent = ToPublicNumber(previous.current)
    end
    local gain = previousCurrent and (snapshot.current - previousCurrent) or 0
    StoreHealthSnapshot(snapshot)
    if recordGain ~= true or gain <= 0 then
        return
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        return
    end
    StoreRecentEventPayload(snapshot.guid, snapshot.name, {
        event = "STT_HEALTH_GAIN",
        amount = gain,
        currentHP = snapshot.current,
        healthPercent = snapshot.healthPercent,
        sourceName = L["RCP_RECAP_SOURCE_HEALTH_CHANGE"] or "Health Change",
        destName = NormalizeEventName(snapshot.name) or snapshot.name,
    })
end

local function UpdateAllHealthSnapshots(recordGain)
    if not runtime.session or runtime.session.endTime then
        return
    end
    UpdateHealthSnapshot("player", recordGain)
    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for index = 1, count do
            UpdateHealthSnapshot("raid" .. index, recordGain)
        end
    elseif IsInGroup and IsInGroup() then
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for index = 1, count do
            UpdateHealthSnapshot("party" .. index, recordGain)
        end
    end
end

local function MethodFromSpellID(spellID)
    return METHOD_BY_SPELLID[tonumber(spellID)] or "other"
end

local function FormatSessionTime(seconds)
    local total = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

local function AllPlayersOutOfCombat()
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return false
    end
    local session = runtime.session
    if not session then
        return true
    end
    for _, meta in pairs(session.rosterCache or {}) do
        if meta.unit and UnitExists and UnitExists(meta.unit) and UnitAffectingCombat and UnitAffectingCombat(meta.unit) then
            return false
        end
    end
    return true
end

local function StopIdleWatchdog()
    if runtime.idleTicker and runtime.idleTicker.Cancel then
        runtime.idleTicker:Cancel()
    end
    runtime.idleTicker = nil
end

local function MarkActivity()
    runtime.lastActivityTime = GetNow()
end

local function AddDeath(unitGUID)
    local session = runtime.session
    if not session or not unitGUID or IsSecretValue(unitGUID) then
        return
    end
    local meta = session.rosterCache[unitGUID]
    if not meta then
        return
    end
    local latest = FindDeathByGUID(unitGUID, true)
    if latest then
        return
    end
    local death = {
        time = GetNow() - session.startTime,
        capturedAt = GetNow(),
        guid = unitGUID,
        name = meta.name,
        class = meta.class,
        resurrected = false,
        recapID = nil,
        recapResolved = false,
    }
    session.deaths[#session.deaths + 1] = death
    if AnnounceDeathCaptured then
        AnnounceDeathCaptured(death, "guid")
    end
    Debug("DeathCaptured name=%s guid=%s count=%d", tostring(meta.name), tostring(unitGUID), #session.deaths)
    RCP:RefreshUI("death")
end

local function AddDeathByUnit(unit)
    local session = runtime.session
    if not session or not unit or IsSecretValue(unit) or not UnitExists or not UnitExists(unit) then
        return
    end
    local unitKey = tostring(unit)
    local guid = UnitGUID(unit)
    local publicGUID = guid and not IsSecretValue(guid) and guid or nil
    if FindDeathByUnitKey(unitKey, true) or (publicGUID and FindDeathByGUID(publicGUID, true)) then
        return
    end

    local meta = publicGUID and session.rosterCache[publicGUID] or nil
    local _, classFile = UnitClass(unit)
    local name = meta and meta.name or GetUnitName(unit)
    if not name or IsSecretValue(name) then
        return
    end
    local death = {
        time = GetNow() - session.startTime,
        capturedAt = GetNow(),
        guid = publicGUID,
        unitKey = unitKey,
        name = name,
        class = meta and meta.class or classFile,
        resurrected = false,
        recapID = nil,
        recapResolved = false,
    }
    session.deaths[#session.deaths + 1] = death
    if AnnounceDeathCaptured then
        AnnounceDeathCaptured(death, "unit")
    end
    Debug("DeathCapturedByUnit unit=%s name=%s count=%d", unitKey, tostring(name), #session.deaths)
    RCP:RefreshUI("death_unit")
end

local function EnsureSessionFromCombatLog()
    if runtime.session then
        return runtime.session
    end
    runtime.testMode = false
    ClearRecapCache()
    runtime.session = {
        encounterID = nil,
        encounterName = L["RCP_TITLE"] or "团本指挥",
        difficultyID = nil,
        groupSize = GetNumGroupMembers and GetNumGroupMembers() or nil,
        startTime = GetNow(),
        endTime = nil,
        success = nil,
        rosterCache = {},
        deaths = {},
    }
    CacheRoster(runtime.session)
    UpdateAllHealthSnapshots(false)
    wipe(runtime.soulstoneUnits)
    wipe(runtime.unitDeadState)
    runtime.secretUnitSkippedLogged = false
    runtime.combatLogProbeLogged = false
    Debug("SessionStartedFromCombatLog groupSize=%s", tostring(runtime.session.groupSize))
    RCP:RefreshUI("combat_log_session")
    return runtime.session
end

local function AddDeathFromCombatLog(unitGUID, unitName, unitFlags)
    if not IsGroupPlayerDeath(unitFlags) then
        return
    end
    local session = EnsureSessionFromCombatLog()
    if not session or session.endTime then
        return
    end

    local publicGUID = unitGUID and not IsSecretValue(unitGUID) and unitGUID or nil
    if publicGUID and FindDeathByGUID(publicGUID, true) then
        return
    end

    local meta = publicGUID and session.rosterCache[publicGUID] or nil
    local name = meta and meta.name or unitName or (UNKNOWN or "Unknown")
    if not IsSecretValue(name) and name == "" then
        name = UNKNOWN or "Unknown"
    end

    local death = {
        time = GetNow() - session.startTime,
        capturedAt = GetNow(),
        guid = publicGUID,
        name = name,
        class = meta and meta.class or nil,
        resurrected = false,
        recapID = nil,
        recapResolved = false,
    }
    session.deaths[#session.deaths + 1] = death
    if AnnounceDeathCaptured then
        AnnounceDeathCaptured(death, "combat_log")
    end
    Debug("DeathCapturedFromCombatLog publicGUID=%s nameSecret=%s count=%d", publicGUID and "true" or "false", IsSecretValue(name) and "true" or "false", #session.deaths)
    RCP:RefreshUI("death_combat_log")
end

local function AddPlayerDeathFromEvent()
    local session = EnsureSessionFromCombatLog()
    if not session or session.endTime then
        return
    end
    AddDeathByUnit("player")
    runtime.unitDeadState.player = true
    Debug("PlayerDeathEventCaptured deaths=%d", #(session.deaths or {}))
end

local function PairResurrection(spellID, sourceGUID, sourceName, destGUID)
    if not runtime.session or not sourceGUID or not destGUID then
        return false
    end
    local death = FindDeathByGUID(destGUID, true)
    if not death then
        return false
    end
    local sourceMeta = (not IsSecretValue(sourceGUID)) and runtime.session.rosterCache[sourceGUID] or nil
    death.resurrected = true
    death.resurrectedBy = ResolveName(sourceGUID, sourceName)
    death.resurrectedByClass = sourceMeta and sourceMeta.class
    death.method = MethodFromSpellID(spellID)
    death.resurrectTime = GetNow() - runtime.session.startTime
    Debug("ResurrectionPaired target=%s source=%s method=%s", tostring(death.name), tostring(death.resurrectedBy), tostring(death.method))
    RCP:RefreshUI("resurrection")
    return true, death
end

local function MarkSoulstoneResurrection(guid)
    local death = FindDeathByGUID(guid, true)
    if not death then
        return
    end
    death.resurrected = true
    death.method = "soulstone"
    death.resurrectTime = GetNow() - runtime.session.startTime
    Debug("SoulstonePaired target=%s", tostring(death.name))
    RCP:RefreshUI("soulstone")
end

local function MarkSoulstoneResurrectionByUnit(unitKey)
    local death = FindDeathByUnitKey(unitKey, true)
    if not death then
        return
    end
    death.resurrected = true
    death.method = "soulstone"
    death.resurrectTime = GetNow() - runtime.session.startTime
    Debug("SoulstonePairedByUnit target=%s unit=%s", tostring(death.name), tostring(unitKey))
    RCP:RefreshUI("soulstone_unit")
end

local function ReadCustomText(value, fallback)
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return fallback
    end
    return value
end

local function RenderTTSTemplate(template, fields)
    local text = tostring(template or "")
    fields = fields or {}
    text = text:gsub("{source}", tostring(fields.source or UNKNOWN or "Unknown"))
    text = text:gsub("{target}", tostring(fields.target or UNKNOWN or "Unknown"))
    text = text:gsub("{sourceName}", tostring(fields.sourceName or UNKNOWN or "Unknown"))
    return text
end

local function GetPublicEventName(name)
    if not name or IsSecretValue(name) then
        return nil
    end
    if name == "" then
        return nil
    end
    return Ambiguate and Ambiguate(name, "short") or name
end

local function EnqueueText(text)
    if T.Speaker and T.Speaker.Enqueue then
        return T.Speaker:Enqueue(text)
    end
    return false
end

AnnounceDeathCaptured = function(death, reason)
    local db = EnsureDB()
    if not (db.deathLog.enabled and db.deathLog.ttsOnDeath) then
        return
    end
    local limit = math.max(1, math.floor((tonumber(db.deathLog.ttsDeathLimit) or 2) + 0.5))
    local deathCount = runtime.session and #(runtime.session.deaths or {}) or 1
    if deathCount > limit then
        if deathCount == limit + 1 then
            Debug("TTSDeathLimitReached limit=%d count=%d reason=%s", limit, deathCount, tostring(reason or "death"))
        end
        return
    end
    local sourceName = death and death.name
    if not sourceName or IsSecretValue(sourceName) or sourceName == "" then
        return
    end
    local fallback = L["TTS_DEATH_DEFAULT"] or "{sourceName}死了"
    local text = RenderTTSTemplate(ReadCustomText(db.deathLog.ttsOnDeathText, fallback), {
        sourceName = sourceName,
    })
    if EnqueueText(text) then
        Debug("TTSDeathCaptured name=%s reason=%s", tostring(sourceName), tostring(reason or "death"))
    end
end

local function GetEnumValue(groupName, key, fallback)
    local group = Enum and Enum[groupName]
    local value = group and group[key]
    if value ~= nil then
        return value
    end
    return fallback
end

local function GetDamageMeterSessionType()
    return GetEnumValue("DamageMeterSessionType", "Current", 1)
end

local function GetDamageMeterType(key, fallback)
    return GetEnumValue("DamageMeterType", key, fallback)
end

local function GetDamageMeterCombatSession(metricType)
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        if not runtime.damageMeterUnavailableLogged then
            runtime.damageMeterUnavailableLogged = true
            Debug("DamageMeterUnavailable api=GetCombatSessionFromType")
        end
        return nil
    end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, GetDamageMeterSessionType(), metricType)
    if not ok or type(session) ~= "table" or IsSecretValue(session) then
        Debug("DamageMeterSessionReadFailed metric=%s ok=%s secret=%s", tostring(metricType), tostring(ok), IsSecretValue(session) and "true" or "false")
        return nil
    end
    return session
end

local function NormalizeName(value)
    if not value or IsSecretValue(value) then
        return nil
    end
    local name = tostring(value)
    if name == "" then
        return nil
    end
    return Ambiguate and Ambiguate(name, "short") or name
end

local function FindDeathForCombatSource(combatSource)
    local session = runtime.session
    if not session or type(combatSource) ~= "table" then
        return nil
    end

    local guid = combatSource.sourceGUID
    if guid and not IsSecretValue(guid) then
        for index = #session.deaths, 1, -1 do
            local death = session.deaths[index]
            if death.guid == guid then
                return death
            end
        end
    end

    local name = NormalizeName(combatSource.name)
    local deathTime = tonumber(combatSource.deathTimeSeconds)
    if not name or not deathTime then
        return nil
    end
    for index = #session.deaths, 1, -1 do
        local death = session.deaths[index]
        if NormalizeName(death.name) == name and math.abs((tonumber(death.time) or 0) - deathTime) <= 2 then
            return death
        end
    end
    return nil
end

local function ResolveDeathRecaps(reason)
    local session = runtime.session
    if not session or not IsSubModuleEnabled("deathLog") then
        return 0
    end
    local meterSession = GetDamageMeterCombatSession(GetDamageMeterType("Deaths", 9))
    local sources = meterSession and meterSession.combatSources
    if type(sources) ~= "table" then
        return 0
    end

    local resolved = 0
    local usedDeaths = {}
    for _, combatSource in ipairs(sources) do
        local recapID = tonumber(combatSource and combatSource.deathRecapID)
        local death = recapID and FindDeathForCombatSource(combatSource) or nil
        if death and not usedDeaths[death] then
            usedDeaths[death] = true
            local changed = death.recapID ~= recapID or death.recapResolved ~= true
            death.recapID = recapID
            death.recapResolved = true
            death.recapDeathTimeSeconds = tonumber(combatSource.deathTimeSeconds) or death.time
            death.sourceCreatureID = combatSource.sourceCreatureID
            if changed then
                resolved = resolved + 1
                Debug("RecapResolved name=%s recapID=%s reason=%s", tostring(death.name), tostring(recapID), tostring(reason or "event"))
            end
        end
    end
    if resolved > 0 then
        RCP:RefreshUI("recap")
    end
    return resolved
end

local function StoreRecapCache(recapID, payload)
    local key = tonumber(recapID)
    if not key then
        return payload
    end
    if runtime.recapCache[key] == nil then
        runtime.recapCacheOrder[#runtime.recapCacheOrder + 1] = key
    end
    runtime.recapCache[key] = payload
    while #runtime.recapCacheOrder > 50 do
        local oldKey = table.remove(runtime.recapCacheOrder, 1)
        runtime.recapCache[oldKey] = nil
    end
    return payload
end

local function FetchDeathRecapData(recapID)
    local key = tonumber(recapID)
    if not key or key < 0 then
        return { hasEvents = false, events = {}, maxHealth = nil, reason = "no_recap" }
    end
    local cached = runtime.recapCache[key]
    if cached and (runtime.testMode or GetNow() - (tonumber(cached.fetchedAt) or 0) <= 10) then
        Debug("RecapFetch state=hit recapID=%s", tostring(key))
        return cached
    end
    if not (C_DeathRecap and C_DeathRecap.HasRecapEvents and C_DeathRecap.GetRecapEvents) then
        Debug("RecapFetch state=unavailable recapID=%s", tostring(key))
        return StoreRecapCache(key, { hasEvents = false, events = {}, maxHealth = nil, fetchedAt = GetNow(), reason = "api_unavailable" })
    end

    local okHas, hasEvents = pcall(C_DeathRecap.HasRecapEvents, key)
    if not okHas or hasEvents ~= true then
        Debug("RecapFetch state=no_events recapID=%s ok=%s", tostring(key), tostring(okHas))
        return StoreRecapCache(key, { hasEvents = false, events = {}, maxHealth = nil, fetchedAt = GetNow(), reason = "no_events" })
    end

    local okEvents, events = pcall(C_DeathRecap.GetRecapEvents, key)
    local maxHealth = nil
    if C_DeathRecap.GetRecapMaxHealth then
        local okMax, result = pcall(C_DeathRecap.GetRecapMaxHealth, key)
        if okMax and not IsSecretValue(result) then
            maxHealth = tonumber(result)
        end
    end
    if not okEvents or type(events) ~= "table" or IsSecretValue(events) then
        Debug("RecapFetch state=error recapID=%s ok=%s", tostring(key), tostring(okEvents))
        return StoreRecapCache(key, { hasEvents = false, events = {}, maxHealth = maxHealth, fetchedAt = GetNow(), reason = "read_failed" })
    end

    Debug("RecapFetch state=miss recapID=%s events=%d", tostring(key), #events)
    return StoreRecapCache(key, {
        hasEvents = true,
        events = events,
        maxHealth = maxHealth,
        fetchedAt = GetNow(),
    })
end

local function GetDamageTakenSpells(deathEntry)
    if type(deathEntry) ~= "table" or not deathEntry.guid or IsSecretValue(deathEntry.guid) then
        return {}
    end
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then
        return {}
    end
    local ok, source = pcall(
        C_DamageMeter.GetCombatSessionSourceFromType,
        GetDamageMeterSessionType(),
        GetDamageMeterType("DamageTaken", 7),
        deathEntry.guid,
        deathEntry.sourceCreatureID
    )
    if not ok or type(source) ~= "table" or IsSecretValue(source) or type(source.combatSpells) ~= "table" then
        return {}
    end
    local list = {}
    for _, spell in ipairs(source.combatSpells) do
        if type(spell) == "table" and not IsSecretValue(spell) then
            list[#list + 1] = spell
        end
    end
    table.sort(list, function(a, b)
        return (tonumber(a.totalAmount) or 0) > (tonumber(b.totalAmount) or 0)
    end)
    return list
end

local function AnnounceRezUsed(spellID, sourceName, destName, death)
    local db = EnsureDB()
    if not (db.rezTracker.enabled and db.rezTracker.ttsOnUse) then
        return
    end
    if MethodFromSpellID(spellID) == "soulstone" then
        return
    end

    local source = (death and death.resurrectedBy and not IsSecretValue(death.resurrectedBy)) and death.resurrectedBy or GetPublicEventName(sourceName)
    local target = (death and death.name and not IsSecretValue(death.name)) and death.name or GetPublicEventName(destName)
    local fallback = (source and target)
        and string.format(L["TTS_REZ_USED_WITH_NAMES"] or "%s战复了%s", source, target)
        or (L["TTS_REZ_USED_GENERIC"] or "有人被战复")
    local customText = tostring(db.rezTracker.ttsOnUseText or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local customNeedsNames = customText:find("{source}", 1, true) or customText:find("{target}", 1, true)
    local template = (customNeedsNames and not (source and target)) and fallback or ReadCustomText(customText, fallback)
    EnqueueText(RenderTTSTemplate(template, {
        source = source,
        target = target,
    }))
    Debug("TTSRezUsed source=%s target=%s method=%s", tostring(source), tostring(target), tostring(MethodFromSpellID(spellID)))
end

local function UpdateSoulstoneUnit(unit)
    if not IsSubModuleEnabled("deathLog") or not unit then
        return
    end
    if IsSecretValue(unit) then
        if not runtime.secretUnitSkippedLogged then
            runtime.secretUnitSkippedLogged = true
            Debug("SecretUnitSkipped source=unit_update")
        end
        return
    end
    if not UnitExists or not UnitExists(unit) then
        return
    end
    local unitKey = tostring(unit)
    local guid = UnitGUID(unit)
    local publicGUID = guid and not IsSecretValue(guid) and guid or nil
    local hasSoulstone = UnitHasSoulstone(unit)
    runtime.soulstoneUnits[unitKey] = hasSoulstone or nil

    local isDead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) == true
    local wasDead = runtime.unitDeadState[unitKey] == true
    runtime.unitDeadState[unitKey] = isDead or nil
    if isDead and not wasDead then
        AddDeathByUnit(unit)
    end
    if wasDead and not isDead and runtime.soulstoneUnits[unitKey] then
        runtime.soulstoneUnits[unitKey] = nil
        if publicGUID then
            MarkSoulstoneResurrection(publicGUID)
        else
            MarkSoulstoneResurrectionByUnit(unitKey)
        end
    end
end

local function UpdateAllSoulstoneUnits()
    UpdateSoulstoneUnit("player")
    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for index = 1, count do
            UpdateSoulstoneUnit("raid" .. index)
        end
    elseif IsInGroup and IsInGroup() then
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for index = 1, count do
            UpdateSoulstoneUnit("party" .. index)
        end
    end
end

local function UpdateRezCharges()
    local info = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(REBIRTH_SPELL_ID) or nil
    local topRow = runtime.topRow
    if type(info) == "table" then
        topRow.charges = tonumber(info.currentCharges) or 0
        topRow.maxCharges = tonumber(info.maxCharges) or 0
        local startTime = tonumber(info.cooldownStartTime) or 0
        local duration = tonumber(info.cooldownDuration) or 0
        if startTime > 0 and duration > 0 and topRow.charges < topRow.maxCharges then
            topRow.nextChargeETA = math.max(0, startTime + duration - GetNow())
        else
            topRow.nextChargeETA = nil
        end
    else
        topRow.charges = nil
        topRow.maxCharges = nil
        topRow.nextChargeETA = nil
    end
end

local function ReadPlayerAura(spellID)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end
    return nil
end

local function UpdateLustState()
    local topRow = runtime.topRow
    for _, spellID in ipairs(LUST_BUFFS) do
        local aura = ReadPlayerAura(spellID)
        if aura then
            topRow.lustState = "active"
            topRow.lustExpiration = aura.expirationTime
            return
        end
    end
    for _, spellID in ipairs(SATED_DEBUFFS) do
        local aura = ReadPlayerAura(spellID)
        if aura then
            topRow.lustState = "sated"
            topRow.lustExpiration = aura.expirationTime
            return
        end
    end
    topRow.lustState = "none"
    topRow.lustExpiration = nil
    runtime.lustEndingKey = nil
end

local function EvaluateTTS()
    local db = EnsureDB()
    local now = GetNow()
    if db.lustMonitor.enabled and db.lustMonitor.ttsEnding and runtime.topRow.lustState == "active" and runtime.topRow.lustExpiration then
        local remain = runtime.topRow.lustExpiration - now
        local key = tostring(runtime.topRow.lustExpiration)
        if remain <= 5 and remain > 0 and runtime.lustEndingKey ~= key then
            runtime.lustEndingKey = key
            EnqueueText(ReadCustomText(db.lustMonitor.ttsEndingText, L["TTS_LUST_ENDING"] or "嗜血即将结束"))
            Debug("TTSLustEnding remain=%.1f", remain)
        end
    end
end

local function UpdateTopRow()
    if IsSubModuleEnabled("rezTracker") then
        UpdateRezCharges()
    else
        runtime.topRow.charges = nil
        runtime.topRow.maxCharges = nil
        runtime.topRow.nextChargeETA = nil
    end
    if IsSubModuleEnabled("lustMonitor") then
        UpdateLustState()
    else
        runtime.topRow.lustState = "none"
        runtime.topRow.lustExpiration = nil
    end
    EvaluateTTS()
end

local function StartTicker()
    if runtime.tickerFrame then
        runtime.tickerFrame:Show()
        return
    end
    runtime.tickerFrame = CreateFrame("Frame")
    runtime.tickerFrame:SetScript("OnUpdate", function(_, elapsed)
        runtime.tickerElapsed = (runtime.tickerElapsed or 0) + (elapsed or 0)
        if runtime.tickerElapsed < 0.1 then
            return
        end
        runtime.tickerElapsed = 0
        UpdateTopRow()
        if T.RaidCommandPanelGUI and T.RaidCommandPanelGUI.RefreshCountdowns then
            T.RaidCommandPanelGUI:RefreshCountdowns(RCP)
        end
    end)
end

local function StopTicker()
    if runtime.tickerFrame then
        runtime.tickerFrame:Hide()
    end
end

local function StartIdleWatchdog()
    StopIdleWatchdog()
    MarkActivity()
    if not C_Timer or not C_Timer.NewTicker then
        return
    end
    runtime.idleTicker = C_Timer.NewTicker(30, function()
        local session = runtime.session
        if not session or session.endTime then
            return
        end
        if GetNow() - (runtime.lastActivityTime or session.startTime) <= IDLE_TIMEOUT_SECONDS then
            return
        end
        if not AllPlayersOutOfCombat() then
            return
        end
        session.endTime = GetNow()
        session.success = "timeout"
        StopIdleWatchdog()
        Debug("SessionTimeout encounterID=%s", tostring(session.encounterID))
        RCP:RefreshUI("timeout")
    end)
end

local function ClearRuntimeSession(reason)
    runtime.session = nil
    runtime.testMode = false
    wipe(runtime.soulstoneUnits)
    wipe(runtime.unitDeadState)
    ClearRecapCache()
    ClearRecentEvents()
    runtime.secretUnitSkippedLogged = false
    runtime.combatLogProbeLogged = false
    Debug("SessionCleared reason=%s", tostring(reason))
    RCP:RefreshUI(reason or "clear")
end

local function NewSession(encounterID, encounterName, difficultyID, groupSize)
    runtime.testMode = false
    ClearRecapCache()
    ClearRecentEvents()
    runtime.session = {
        encounterID = encounterID,
        encounterName = encounterName,
        difficultyID = difficultyID,
        groupSize = groupSize,
        startTime = GetNow(),
        endTime = nil,
        success = nil,
        rosterCache = {},
        deaths = {},
    }
    CacheRoster(runtime.session)
    UpdateAllHealthSnapshots(false)
    wipe(runtime.soulstoneUnits)
    wipe(runtime.unitDeadState)
    runtime.secretUnitSkippedLogged = false
    runtime.combatLogProbeLogged = false
    UpdateAllSoulstoneUnits()
    StartIdleWatchdog()
    Debug("SessionStarted encounterID=%s name=%s groupSize=%s", tostring(encounterID), tostring(encounterName), tostring(groupSize))
    RCP:RefreshUI("encounter_start")
end

function RCP:OnRegister()
    T.RaidCommandPanel = self
end

function RCP:OnFirstLoad()
    RefreshRuntimeActive()
end

function RCP:OnEnable()
    for _, eventName in ipairs(STATIC_EVENTS) do
        self:RegisterEvent(eventName, "OnEvent")
    end
    self:RefreshConfig("enable")
    StartTicker()
    UpdateTopRow()
    self:RefreshUI("enable")
end

function RCP:OnDisable()
    runtime.configActive = false
    StopIdleWatchdog()
    StopTicker()
    ClearRuntimeSession("disable")
    if T.RaidCommandPanelGUI and T.RaidCommandPanelGUI.Hide then
        T.RaidCommandPanelGUI:Hide()
    end
end

function RCP:RefreshConfig(reason)
    RefreshRuntimeActive()
    if not IsRuntimeActive() and runtime.session then
        ClearRuntimeSession("config_disabled")
    end
    UpdateTopRow()
    self:RefreshUI(reason or "config")
end

function RCP:OnEvent(eventName, ...)
    if eventName == "PLAYER_ENTERING_WORLD" then
        if not IsRuntimeActive() then
            if runtime.session then
                ClearRuntimeSession("disabled")
            end
            UpdateTopRow()
            self:RefreshUI("entering_world")
            return
        end
        if not IsAllowedByInstance() then
            ClearRuntimeSession("leaving_instance")
        end
        UpdateTopRow()
        self:RefreshUI("entering_world")
        return
    end

    if not IsRuntimeActive() then
        if runtime.session then
            ClearRuntimeSession("disabled")
        end
        return
    end
    if not IsAllowedByInstance() then
        return
    end

    if eventName == "ENCOUNTER_START" then
        NewSession(...)
    elseif eventName == "ENCOUNTER_END" then
        local encounterID, _, _, _, success = ...
        local session = runtime.session
        if session and (not encounterID or session.encounterID == encounterID) then
            ResolveDeathRecaps("encounter_end")
            session.endTime = GetNow()
            session.success = (success == 1)
            ClearRecapCache()
            StopIdleWatchdog()
            Debug("SessionEnded encounterID=%s success=%s", tostring(encounterID), tostring(session.success))
            self:RefreshUI("encounter_end")
        end
    elseif eventName == "GROUP_ROSTER_UPDATE" then
        if runtime.session and not runtime.session.endTime then
            CacheRoster(runtime.session)
            UpdateAllHealthSnapshots(false)
            UpdateAllSoulstoneUnits()
        end
    elseif eventName == "COMBAT_LOG_EVENT_UNFILTERED" then
        MarkActivity()
        local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellID = CombatLogGetCurrentEventInfo()
        if IsSubModuleEnabled("deathLog") then
            if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
                local timestamp, eventType, hideCaster, eventSourceGUID, eventSourceName, eventSourceFlags, eventSourceRaidFlags, eventDestGUID, eventDestName, eventDestFlags, eventDestRaidFlags, eventSpellID, _, _, amount, overhealing, absorbed, critical = CombatLogGetCurrentEventInfo()
                local rawAmount = tonumber(amount) or 0
                local effective = math.max(rawAmount - (tonumber(overhealing) or 0), 0)
                RecordCombatLogRecapEvent(eventType, eventSourceName, eventDestGUID, eventDestName, eventDestFlags, eventSpellID, rawAmount, absorbed, critical, overhealing, effective)
            elseif subevent == "SPELL_HEAL_ABSORBED" then
                local timestamp, eventType, hideCaster, absorbSourceGUID, absorbSourceName, absorbSourceFlags, absorbSourceRaidFlags, eventDestGUID, eventDestName, eventDestFlags, eventDestRaidFlags, absorbSpellID, absorbSpellName, absorbSpellSchool, healerGUID, healerName, healerFlags, healerRaidFlags, healSpellID, healSpellName, healSpellSchool, amountDenied = CombatLogGetCurrentEventInfo()
                RecordCombatLogRecapEvent(eventType, healerName, eventDestGUID, eventDestName, eventDestFlags, healSpellID or absorbSpellID, amountDenied, amountDenied, false, nil, 0)
            elseif subevent == "SPELL_ABSORBED" then
                local timestamp, eventType, hideCaster, eventSourceGUID, eventSourceName, eventSourceFlags, eventSourceRaidFlags, eventDestGUID, eventDestName, eventDestFlags, eventDestRaidFlags, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20, arg21, arg22 = CombatLogGetCurrentEventInfo()
                local shieldOwnerName = arg16
                local shieldSpellID = tonumber(arg19)
                local absorbedAmount = tonumber(arg22)
                if not absorbedAmount then
                    shieldOwnerName = arg13
                    shieldSpellID = tonumber(arg16)
                    absorbedAmount = tonumber(arg19)
                end
                RecordCombatLogRecapEvent(eventType, shieldOwnerName, eventDestGUID, eventDestName, eventDestFlags, shieldSpellID, absorbedAmount, nil, false)
            end
        end
        if subevent == "UNIT_DIED" then
            if not runtime.combatLogProbeLogged then
                runtime.combatLogProbeLogged = true
                Debug("CombatLogDeathToken targetSecret=%s flagsSecret=%s hasSession=%s", IsSecretValue(destName) and "true" or "false", IsSecretValue(destFlags) and "true" or "false", runtime.session and "true" or "false")
            end
            AddDeathFromCombatLog(destGUID, destName, destFlags)
        elseif subevent == "SPELL_RESURRECT" then
            local _, death = PairResurrection(spellID, sourceGUID, sourceName, destGUID)
            AnnounceRezUsed(spellID, sourceName, destName, death)
        end
    elseif eventName == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        ResolveDeathRecaps("damage_meter_event")
    elseif eventName == "PLAYER_DEAD" then
        MarkActivity()
        AddPlayerDeathFromEvent()
    elseif eventName == "PLAYER_ALIVE" or eventName == "PLAYER_UNGHOST" then
        UpdateSoulstoneUnit("player")
    elseif eventName == "UNIT_AURA" then
        local unit = ...
        if IsSecretValue(unit) then
            if IsSubModuleEnabled("deathLog") then
                UpdateSoulstoneUnit(unit)
            end
            return
        end
        if unit == "player" and IsSubModuleEnabled("lustMonitor") then
            UpdateLustState()
            self:RefreshUI("lust")
        end
        if IsSubModuleEnabled("deathLog") then
            UpdateSoulstoneUnit(unit)
        end
    elseif eventName == "UNIT_FLAGS" then
        UpdateSoulstoneUnit(...)
    elseif eventName == "UNIT_HEALTH" then
        if IsSubModuleEnabled("deathLog") then
            UpdateHealthSnapshot(..., true)
        end
        UpdateSoulstoneUnit(...)
    elseif eventName == "SPELL_UPDATE_CHARGES" then
        UpdateRezCharges()
        self:RefreshUI("rez")
    end
end

function RCP:RefreshUI(cause)
    runtime.pendingRefresh = true
    if runtime.refreshTimer then
        return
    end
    runtime.refreshTimer = true
    C_Timer.After(0.1, function()
        runtime.refreshTimer = nil
        if not runtime.pendingRefresh then
            return
        end
        runtime.pendingRefresh = false
        if T.RaidCommandPanelGUI and T.RaidCommandPanelGUI.Refresh then
            T.RaidCommandPanelGUI:Refresh(self, cause)
        end
    end)
end

function RCP:GetSnapshot()
    return {
        db = EnsureDB(),
        session = runtime.session,
        topRow = runtime.topRow,
        allowed = runtime.testMode or IsAllowedByInstance(),
        mainEnabled = EnsureDB().enabled == true,
        hasAnySubModule = AnySubModuleEnabled(),
    }
end

function RCP:EnsureDB()
    return EnsureDB()
end

function RCP:IsSecretValue(value)
    return IsSecretValue(value)
end

function RCP:ResolveDeathRecap(deathEntry, reason)
    if type(deathEntry) ~= "table" then
        return nil
    end
    if deathEntry.recapID == nil or deathEntry.recapResolved ~= true then
        ResolveDeathRecaps(reason or "open")
    end
    return deathEntry.recapID
end

function RCP:GetDeathRecapData(recapID)
    return FetchDeathRecapData(recapID)
end

function RCP:GetDeathDamageTakenSpells(deathEntry)
    return GetDamageTakenSpells(deathEntry)
end

function RCP:GetDeathRecentEvents(deathEntry)
    if type(deathEntry) ~= "table" then
        return {}
    end
    local sources = {}
    if deathEntry.guid and not IsSecretValue(deathEntry.guid) and type(runtime.recentEventsByGUID[deathEntry.guid]) == "table" then
        sources[#sources + 1] = runtime.recentEventsByGUID[deathEntry.guid]
    end
    local shortName = NormalizeEventName(deathEntry.name)
    if shortName and type(runtime.recentEventsByName[shortName]) == "table" then
        sources[#sources + 1] = runtime.recentEventsByName[shortName]
    end
    if #sources == 0 then
        Debug("RecentEventsForDeath name=%s guid=%s heal=0 absorb=0 reason=empty keys=%s", tostring(deathEntry.name), tostring(deathEntry.guid), shortName or "-")
        return {}
    end
    local deathAt = tonumber(deathEntry.capturedAt)
    if not deathAt and runtime.session and deathEntry.time then
        deathAt = (tonumber(runtime.session.startTime) or 0) + (tonumber(deathEntry.time) or 0)
    end
    local list = {}
    local seen = {}
    local healCount = 0
    local absorbCount = 0
    for _, source in ipairs(sources) do
        for _, item in ipairs(source) do
            local capturedAt = tonumber(item.capturedAt)
            if not seen[item] and capturedAt and deathAt and capturedAt >= deathAt - DEATH_EVENT_WINDOW_SECONDS and capturedAt <= deathAt + 0.5 then
                seen[item] = true
                list[#list + 1] = item
                if item.event == "SPELL_HEAL" or item.event == "SPELL_PERIODIC_HEAL" or item.event == "SPELL_HEAL_ABSORBED" then
                    healCount = healCount + 1
                elseif item.event == "SPELL_ABSORBED" then
                    absorbCount = absorbCount + 1
                end
            end
        end
    end
    Debug("RecentEventsForDeath name=%s guid=%s heal=%d absorb=%d total=%d keys=%s", tostring(deathEntry.name), tostring(deathEntry.guid), healCount, absorbCount, #list, shortName or "-")
    return list
end

function RCP:FormatSessionTime(seconds)
    return FormatSessionTime(seconds)
end

function RCP:SetLocked(locked)
    local db = EnsureDB()
    db.locked = locked and true or false
    if STT_DB then
        STT_DB.raidCommandPanel = db
    end
    if T.RaidCommandPanelGUI and T.RaidCommandPanelGUI.ApplyLockState then
        T.RaidCommandPanelGUI:ApplyLockState(self)
    end
    self:RefreshUI("lock")
end

function RCP:IsLocked()
    return EnsureDB().locked ~= false
end

function RCP:ResetPosition()
    local db = EnsureDB()
    local fallback = C.defaults.raidCommandPanel.position
    db.position = {
        point = fallback.point,
        relPoint = fallback.relPoint,
        x = fallback.x,
        y = fallback.y,
        width = fallback.width,
    }
    if STT_DB then
        STT_DB.raidCommandPanel = db
    end
    if T.RaidCommandPanelGUI and T.RaidCommandPanelGUI.LoadPosition then
        T.RaidCommandPanelGUI:LoadPosition(self)
    end
    self:RefreshUI("reset")
end

function RCP:RunTest()
    runtime.testMode = true
    ClearRecapCache()
    local session = {
        encounterID = 999001,
        encounterName = L["RCP_TITLE"] or "团本指挥",
        difficultyID = 16,
        groupSize = 20,
        startTime = GetNow() - 230,
        endTime = nil,
        success = nil,
        rosterCache = {},
        deaths = {
            { time = 134, guid = "test-1", name = "张三", class = "DRUID", resurrected = false, recapID = 1001, recapResolved = true, recapDeathTimeSeconds = 134 },
            { time = 202, guid = "test-2", name = "李四", class = "PALADIN", resurrected = true, resurrectedBy = "王五", resurrectedByClass = "DEATHKNIGHT", method = "rebirth", resurrectTime = 215, recapID = -1, recapResolved = true },
            { time = 228, guid = "test-3", name = "孙七", class = "WARLOCK", resurrected = true, method = "soulstone", resurrectTime = 232, recapID = -1, recapResolved = true },
        },
    }
    runtime.session = session
    StoreRecapCache(1001, {
        hasEvents = true,
        maxHealth = 1200000,
        fetchedAt = GetNow(),
        events = {
            { "SPELL_DAMAGE", 1239045, 210000, 126.2, 76, "首领", 0, 4, false, 0, false, false },
            { "SPELL_DAMAGE", 1239046, 380000, 130.4, 44, "首领", 45000, 32, false, 0, true, false },
            { "SPELL_DAMAGE", 1239047, 680000, 134.0, 0, "首领", 0, 1, false, 145000, false, false },
        },
    })
    runtime.topRow.charges = 3
    runtime.topRow.maxCharges = 4
    runtime.topRow.nextChargeETA = 84
    runtime.topRow.lustState = "active"
    runtime.topRow.lustExpiration = GetNow() + 38
    Debug("TestDataInjected deaths=%d", #session.deaths)
    self:RefreshUI("test")
end

function RCP:HandleCommand(arg)
    arg = tostring(arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "test" then
        if not EnsureDB().enabled then
            EnsureDB().enabled = true
            if STT_DB then
                STT_DB.raidCommandPanel = C.DB.raidCommandPanel
            end
            if T.ModuleLoader then
                T.ModuleLoader:Enable("RaidCommandPanel", "command_test")
            end
        end
        self:RunTest()
        T.msg(L["RCP_TEST_DONE"] or "团本指挥面板测试数据已显示")
    elseif arg == "reset" then
        self:ResetPosition()
        T.msg(L["位置已重置"] or "位置已重置")
    else
        local db = EnsureDB()
        db.enabled = not (db.enabled == true)
        if STT_DB then
            STT_DB.raidCommandPanel = db
        end
        if T.ModuleLoader then
            if db.enabled then
                T.ModuleLoader:Enable("RaidCommandPanel", "command")
            else
                T.ModuleLoader:Disable("RaidCommandPanel", "command")
            end
        end
        T.msg((L["RCP_TITLE"] or "团本指挥") .. ": " .. (db.enabled and "ON" or "OFF"))
    end
end

end)
