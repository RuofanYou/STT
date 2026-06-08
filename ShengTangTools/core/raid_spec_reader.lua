local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({ "semanticTimeline.editorLoaded", "rosterPlanner.enabled" }, function()

local RaidSpecReader = {}
T.RaidSpecReader = RaidSpecReader

local TICK_INTERVAL = 0.25
local REQUEST_INTERVAL = 2
local INSPECT_TIMEOUT = 3
local RETRY_INTERVAL = 10
local MAX_ATTEMPTS = 3
local READ_WINDOW = 60

local frame

local state = {
    active = false,
    members = nil,
    queueOrder = nil,
    queueByGUID = nil,
    currentGUID = nil,
    callback = nil,
    deadline = 0,
    elapsed = 0,
    nextRequestAt = 0,
    lastMembers = nil,
}

local cacheByGUID = {}

local function Now()
    return GetTime and GetTime() or 0
end

local function Debug(fmt, ...)
    if T.debug then
        T.debug(string.format("[RaidSpecReader] " .. tostring(fmt), ...))
    end
end

local function IsCombatBlocked()
    return InCombatLockdown and InCombatLockdown()
end

local function FullUnitName(unit, fallback)
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName(unit)
    end
    if name and name ~= "" then
        if realm and realm ~= "" then
            return name .. "-" .. realm
        end
        return name
    end
    return fallback
end

local function UnitDisplayName(unit)
    if GetUnitName then
        return GetUnitName(unit, true)
    end
    return UnitName and UnitName(unit) or nil
end

local function UnitOnline(unit)
    if UnitIsConnected then
        return UnitIsConnected(unit) == true
    end
    return true
end

local function UnitClassFile(unit, fallback)
    local classFile
    if UnitClass then
        _, classFile = UnitClass(unit)
    end
    return classFile or fallback
end

local function UnitIsRealPlayer(unit)
    if UnitExists and UnitExists(unit) and UnitIsPlayer then
        return UnitIsPlayer(unit) == true
    end
    return true
end

local function ReadPlayerSpec()
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
        or (GetSpecialization and GetSpecialization())
    if not specIndex then
        return nil
    end

    local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
    if not getInfo then
        return nil
    end

    local ok, specID = pcall(getInfo, specIndex, false)
    if not ok then
        return nil
    end
    if type(specID) == "table" then
        specID = specID.specID or specID.id
    end
    specID = tonumber(specID)
    return specID and specID > 0 and specID or nil
end

local function IsPlayerMember(unit, guid)
    if unit == "player" then
        return true
    end
    local playerGUID = UnitGUID and UnitGUID("player") or nil
    return guid and playerGUID and guid == playerGUID
end

local function HasSecretIdentity(unit)
    if not (C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret) then
        return false
    end
    local ok, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
    return ok and secret == true
end

local function StopReading()
    if frame then
        frame:UnregisterEvent("INSPECT_READY")
        frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        frame:UnregisterEvent("ENCOUNTER_START")
        frame:Hide()
    end
    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
end

local function StoreSpec(member, specID, source)
    specID = tonumber(specID)
    if not member or not member.guid or not specID or specID <= 0 then
        return
    end
    cacheByGUID[member.guid] = {
        specID = specID,
        classFileName = member.classFileName,
        source = source or "inspect_fresh",
        updatedAt = Now(),
    }
end

local function BeginInspectWindow()
    for _, record in pairs(cacheByGUID) do
        if record.source == "inspect_fresh" then
            record.source = "inspect_cache"
        end
    end
end

local function ApplyCachedSpec(member)
    local record = member and member.guid and cacheByGUID[member.guid] or nil
    if not record or not tonumber(record.specID) then
        return false
    end
    member.specID = tonumber(record.specID)
    member.classFileName = member.classFileName or record.classFileName
    member.specSource = record.source or "inspect_cache"
    member.failReason = nil
    return true
end

local function CountMissing(members)
    local missing = 0
    for _, member in ipairs(members or {}) do
        if member and member.isOnline == true and not tonumber(member.specID) then
            missing = missing + 1
        end
    end
    return missing
end

local function RefreshFromCache()
    for _, member in ipairs(state.members or {}) do
        if member and member.isOnline == true and not tonumber(member.specID) then
            ApplyCachedSpec(member)
        end
    end
end

local function QueueCount()
    local count = 0
    for _, guid in ipairs(state.queueOrder or {}) do
        if state.queueByGUID and state.queueByGUID[guid] then
            count = count + 1
        end
    end
    return count
end

local function Finish(ok, reason)
    local callback = state.callback
    local members = state.members
    local missing = CountMissing(members)

    StopReading()

    state.active = false
    state.members = nil
    state.queueOrder = nil
    state.queueByGUID = nil
    state.currentGUID = nil
    state.callback = nil
    state.deadline = 0
    state.elapsed = 0
    state.nextRequestAt = 0

    if ok then
        state.lastMembers = members or {}
    end

    Debug("finish ok=%s reason=%s missing=%d", tostring(ok == true), tostring(reason or ""), missing)
    if callback then
        callback({
            ok = ok == true,
            reason = reason,
            members = members or {},
            missing = missing,
        })
    end
end

local function MarkFailure(entry, reason)
    local member = entry and entry.member
    if member then
        member.failReason = reason
        Debug("fail name=%s unit=%s reason=%s attempts=%d", tostring(member.fullName or member.name), tostring(entry.unit), tostring(reason), tonumber(entry.attempts) or 0)
    end
end

local function DropEntry(guid)
    if state.queueByGUID then
        state.queueByGUID[guid] = nil
    end
    if state.currentGUID == guid then
        state.currentGUID = nil
        if ClearInspectPlayer then
            ClearInspectPlayer()
        end
    end
end

local function RetryOrDrop(entry, reason)
    MarkFailure(entry, reason)
    if (tonumber(entry.attempts) or 0) >= MAX_ATTEMPTS then
        DropEntry(entry.guid)
        return
    end
    entry.status = "waiting"
    entry.nextAt = Now() + RETRY_INTERVAL
    state.currentGUID = nil
    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
end

local function NextReadyEntry(now)
    for _, guid in ipairs(state.queueOrder or {}) do
        local entry = state.queueByGUID and state.queueByGUID[guid] or nil
        if entry and entry.status == "waiting" and (entry.nextAt or 0) <= now then
            return entry
        end
    end
end

local function ValidateEntry(entry)
    local unit = entry and entry.unit
    if not (unit and UnitExists and UnitExists(unit) and UnitOnline(unit)) then
        return false, "unit_missing"
    end
    if not UnitIsRealPlayer(unit) then
        return false, "not_player"
    end
    if HasSecretIdentity(unit) then
        return false, "secret"
    end
    if not (CanInspect and CanInspect(unit, false)) then
        return false, "canInspect=false"
    end
    return true
end

local function RequestEntry(entry)
    entry.attempts = (entry.attempts or 0) + 1

    local ok, result = ValidateEntry(entry)
    if not ok then
        RetryOrDrop(entry, result)
        return
    end

    entry.status = "requesting"
    entry.lastRequest = Now()
    state.nextRequestAt = entry.lastRequest + REQUEST_INTERVAL
    state.currentGUID = entry.guid

    local sent = pcall(NotifyInspect, entry.unit)
    if not sent then
        RetryOrDrop(entry, "notify_failed")
        return
    end
    Debug("notify name=%s unit=%s attempt=%d", tostring(entry.member and (entry.member.fullName or entry.member.name)), tostring(entry.unit), entry.attempts)
end

local function ContinueScan()
    if not state.active then
        return
    end

    RefreshFromCache()
    if CountMissing(state.members) == 0 then
        Finish(true, "complete")
        return
    end
    if IsCombatBlocked() then
        Finish(false, "combat")
        return
    end

    local now = Now()
    if now >= state.deadline then
        Finish(true, "partial")
        return
    end
    if QueueCount() == 0 then
        Finish(true, "partial")
        return
    end
    if InspectFrame and InspectFrame:IsShown() then
        return
    end

    local current = state.currentGUID and state.queueByGUID and state.queueByGUID[state.currentGUID] or nil
    if current then
        if now - (current.lastRequest or 0) >= INSPECT_TIMEOUT then
            RetryOrDrop(current, "timeout")
        end
        return
    end

    if now < (state.nextRequestAt or 0) then
        return
    end

    local entry = NextReadyEntry(now)
    if entry then
        RequestEntry(entry)
    end
end

local function AddQueueEntry(queueOrder, queueByGUID, member)
    if not (member and member.guid) then
        return
    end
    if queueByGUID[member.guid] then
        return
    end
    queueByGUID[member.guid] = {
        guid = member.guid,
        unit = member.unit,
        member = member,
        attempts = 0,
        status = "waiting",
        nextAt = 0,
    }
    queueOrder[#queueOrder + 1] = member.guid
end

local function AddMember(members, queueOrder, queueByGUID, unit, rosterName, subgroup, classFileName)
    local name = rosterName or UnitDisplayName(unit)
    if not name or name == "" then
        return
    end
    if unit ~= "player" and UnitExists and UnitExists(unit) and not UnitIsRealPlayer(unit) then
        Debug("skip_non_player name=%s unit=%s", tostring(name), tostring(unit))
        return
    end

    local guid = UnitGUID and UnitGUID(unit) or nil
    local online = UnitOnline(unit)
    local member = {
        name = name,
        fullName = FullUnitName(unit, name),
        classFileName = UnitClassFile(unit, classFileName),
        subgroup = subgroup,
        role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil,
        guid = guid,
        unit = unit,
        isOnline = online,
    }

    if IsPlayerMember(unit, guid) then
        member.specID = ReadPlayerSpec()
        member.specSource = "player"
        StoreSpec(member, member.specID, "player")
    elseif online and guid then
        if not ApplyCachedSpec(member) then
            AddQueueEntry(queueOrder, queueByGUID, member)
        end
    end

    members[#members + 1] = member
end

local function BuildMembers()
    local members = {}
    local queueOrder = {}
    local queueByGUID = {}

    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for index = 1, count do
            local unit = "raid" .. index
            local name, _, subgroup, _, _, classFileName = GetRaidRosterInfo(index)
            AddMember(members, queueOrder, queueByGUID, unit, name, subgroup, classFileName)
        end
    else
        AddMember(members, queueOrder, queueByGUID, "player", nil, 1, nil)
        local count = GetNumGroupMembers and GetNumGroupMembers() or 1
        for index = 1, math.max(0, count - 1) do
            AddMember(members, queueOrder, queueByGUID, "party" .. index, nil, 1, nil)
        end
    end

    return members, queueOrder, queueByGUID
end

function RaidSpecReader:GetLastMembers()
    return state.lastMembers or {}
end

function RaidSpecReader:IsActive()
    return state.active == true
end

function RaidSpecReader:ReadCurrentGroup(callback)
    if state.active then
        return false, "busy"
    end
    if not IsInGroup or not IsInGroup() then
        return false, "not_group"
    end
    if IsCombatBlocked() then
        return false, "combat"
    end
    if not (NotifyInspect and GetInspectSpecialization and CanInspect and UnitGUID) then
        return false, "not_ready"
    end

    BeginInspectWindow()

    state.active = true
    state.currentGUID = nil
    state.callback = callback
    state.deadline = Now() + READ_WINDOW
    state.elapsed = 0
    state.nextRequestAt = 0
    state.members, state.queueOrder, state.queueByGUID = BuildMembers()

    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", RaidSpecReader.OnEvent)
        frame:SetScript("OnUpdate", RaidSpecReader.OnUpdate)
        frame:Hide()
    end
    frame:RegisterEvent("INSPECT_READY")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:Show()

    Debug("start total=%d queue=%d window=%d", #(state.members or {}), QueueCount(), READ_WINDOW)
    ContinueScan()
    return true
end

function RaidSpecReader.OnEvent(_, event, guid)
    if not state.active then
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
        Finish(false, "combat")
        return
    end
    if event ~= "INSPECT_READY" then
        return
    end

    local entry = guid and state.queueByGUID and state.queueByGUID[guid] or nil
    if not entry or state.currentGUID ~= guid then
        return
    end

    local ok, specID = pcall(GetInspectSpecialization, entry.unit)
    specID = ok and tonumber(specID) or nil
    if specID and specID > 0 then
        entry.member.specID = specID
        entry.member.specSource = "inspect_fresh"
        entry.member.failReason = nil
        StoreSpec(entry.member, specID, "inspect_fresh")
        Debug("ready name=%s specID=%d", tostring(entry.member.fullName or entry.member.name), specID)
        DropEntry(guid)
    else
        RetryOrDrop(entry, "spec_zero")
    end
    ContinueScan()
end

function RaidSpecReader.OnUpdate(_, elapsed)
    if not state.active then
        return
    end
    state.elapsed = (state.elapsed or 0) + (elapsed or 0)
    if state.elapsed < TICK_INTERVAL then
        return
    end
    state.elapsed = 0
    ContinueScan()
end

end)
