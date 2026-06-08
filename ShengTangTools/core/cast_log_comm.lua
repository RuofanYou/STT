-- 施法记录团队通信（Cast Log Comm）
-- 只负责按手动请求把本地录制结果广播给团队，并缓存团队成员最近一场记录。

local T, C = unpack(select(2, ...))
T.RegisterColdFile("castRecorder.backendEnabled", function()

local CastLogComm = {}
T.CastLogComm = CastLogComm

local teamRecords = {}
local pendingBroadcastTimer = nil
local pendingBroadcastPayload = nil
local pendingBroadcastScope = nil
local requestSeq = 0

local function Debug(fmt, ...)
    if not T.debug then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[CastLogComm] " .. tostring(fmt), ...))
    else
        T.debug("[CastLogComm] " .. tostring(fmt))
    end
end

local function GetCurrentBossKeyText()
    return T.Note and T.Note.GetCurrentBossKey and T.Note:GetCurrentBossKey() or ""
end

local function CopyCasts(casts)
    local out = {}
    if type(casts) ~= "table" then
        return out
    end
    for _, cast in ipairs(casts) do
        local spellID = tonumber(cast and cast.s)
        local t = tonumber(cast and cast.t)
        if spellID and t then
            local item = {
                t = math.floor(t * 1000 + 0.5),
                s = spellID,
            }
            local duration = tonumber(cast and cast.d)
            if duration and duration > 0 then
                item.d = math.floor(duration * 1000 + 0.5)
            end
            if cast and cast.f == true then
                item.f = true
            end
            out[#out + 1] = item
        end
    end
    return out
end

local function RestoreCasts(casts)
    local out = {}
    if type(casts) ~= "table" then
        return out
    end
    for _, cast in ipairs(casts) do
        local spellID = tonumber(cast and cast.s)
        local t = tonumber(cast and cast.t)
        if spellID and t then
            local item = {
                t = t / 1000,
                s = spellID,
            }
            local duration = tonumber(cast and cast.d)
            if duration and duration > 0 then
                item.d = duration / 1000
            end
            if cast and cast.f == true then
                item.f = true
            end
            out[#out + 1] = item
        end
    end
    return out
end

local function CopyPhases(phases)
    local out = {}
    if type(phases) ~= "table" then
        return out
    end
    for _, phase in ipairs(phases) do
        local t = tonumber(phase and phase.t)
        local name = phase and phase.phase
        if t and name ~= nil then
            out[#out + 1] = {
                t = t,
                phase = tostring(name),
            }
        end
    end
    return out
end

local function BuildCastLogID(record, casts)
    local playerName = tostring(record.playerName or UnitName("player") or "?")
    local bossKeyText = tostring(record.bossKeyText or record.encounterID or "unknown")
    local stamp = tostring(record.date or (GetServerTime and GetServerTime()) or (time and time()) or 0)
    return table.concat({ playerName, bossKeyText, stamp, tostring(#casts or 0) }, "#")
end

local function BuildPayload(record)
    if type(record) ~= "table" then
        return nil
    end
    local casts = CopyCasts(record.casts)
    if #casts == 0 then
        return nil
    end
    return {
        castLogID = BuildCastLogID(record, casts),
        encounterID = tonumber(record.encounterID),
        bossKeyText = tostring(record.bossKeyText or ""),
        difficulty = tonumber(record.difficulty),
        duration = tonumber(record.duration) or 0,
        playerName = tostring(record.playerName or UnitName("player") or "?"),
        playerClass = tostring(record.playerClass or select(2, UnitClass("player")) or ""),
        casts = casts,
        phases = CopyPhases(record.phases),
    }
end

local function FindLocalRecordForRequest(payload)
    if not (T.CastRecorder and T.CastRecorder.GetRecords) then
        return nil
    end
    local records = T.CastRecorder:GetRecords()
    local bossKeyText = tostring(payload and payload.bossKeyText or "")
    if bossKeyText ~= "" then
        for _, record in ipairs(records or {}) do
            if tostring(record and record.bossKeyText or "") == bossKeyText then
                return record
            end
        end
    end
    local encounterID = tonumber(payload and payload.encounterID)
    if encounterID then
        for _, record in ipairs(records or {}) do
            if tonumber(record and record.encounterID) == encounterID then
                return record
            end
        end
    end
    return nil
end

local function BuildRequestPayload()
    local bossKeyText = GetCurrentBossKeyText()
    local localRecord = FindLocalRecordForRequest({ bossKeyText = bossKeyText })
    requestSeq = requestSeq + 1
    return {
        requestID = table.concat({
            tostring(UnitName("player") or "?"),
            tostring((GetServerTime and GetServerTime()) or (time and time()) or 0),
            tostring(requestSeq),
        }, "#"),
        bossKeyText = bossKeyText,
        encounterID = tonumber(localRecord and localRecord.encounterID),
    }
end

local function NormalizePayload(payload, sender)
    if type(payload) ~= "table" then
        return nil
    end
    local casts = RestoreCasts(payload.casts)
    if #casts == 0 then
        return nil
    end
    return {
        castLogID = tostring(payload.castLogID or ""),
        encounterID = tonumber(payload.encounterID),
        bossKeyText = tostring(payload.bossKeyText or ""),
        difficulty = tonumber(payload.difficulty),
        duration = tonumber(payload.duration) or 0,
        playerName = tostring(payload.playerName or sender or "?"),
        playerClass = tostring(payload.playerClass or ""),
        casts = casts,
        phases = CopyPhases(payload.phases),
    }
end

local function ClearTeamRecords()
    teamRecords = {}
    if T.CastLogRow and T.CastLogRow.Refresh then
        T.CastLogRow.Refresh()
    end
end

local function OnReceive(payload, sender)
    if T.Comm and T.Comm.IsSelfTarget and T.Comm:IsSelfTarget(sender) then
        Debug("ReceiveIgnored id=%s sender=%s reason=self", tostring(payload and payload.castLogID), tostring(sender))
        return
    end
    local record = NormalizePayload(payload, sender)
    if not record then
        Debug("ReceiveIgnored id=%s sender=%s reason=bad_payload", tostring(payload and payload.castLogID), tostring(sender))
        return
    end
    local key = tostring(sender or record.playerName)
    teamRecords[key] = record
    Debug("Receive id=%s sender=%s player=%s bossKey=%s encounter=%s casts=%d", tostring(record.castLogID), tostring(sender), tostring(record.playerName), tostring(record.bossKeyText), tostring(record.encounterID), #record.casts)
    if T.CastLogRow and T.CastLogRow.Refresh then
        T.CastLogRow.Refresh()
    end
end

local function OnReceiveRequest(payload, sender)
    if T.Comm and T.Comm.IsSelfTarget and T.Comm:IsSelfTarget(sender) then
        Debug("RequestIgnored id=%s sender=%s reason=self", tostring(payload and payload.requestID), tostring(sender))
        return
    end
    local record = FindLocalRecordForRequest(payload)
    if not record then
        Debug("RequestIgnored id=%s sender=%s reason=no_record bossKey=%s encounter=%s", tostring(payload and payload.requestID), tostring(sender), tostring(payload and payload.bossKeyText), tostring(payload and payload.encounterID))
        return
    end
    local delay = 0.5 + (math.random and math.random() or 0) * 3
    Debug("RequestAccepted id=%s sender=%s player=%s bossKey=%s encounter=%s casts=%d delay=%.1f", tostring(payload and payload.requestID), tostring(sender), tostring(record.playerName), tostring(record.bossKeyText), tostring(record.encounterID), #(record.casts or {}), delay)
    CastLogComm.BroadcastRecord(record, delay)
end

local function Register()
    if not (T.Comm and T.Comm.Register) then
        Debug("RegisterSkipped reason=missing_comm")
        return
    end
    local ok, err = T.Comm:Register("castLog", "broadcast", OnReceive)
    if not ok then
        Debug("RegisterFailed err=%s", tostring(err))
    end
    ok, err = T.Comm:Register("castLog", "request", OnReceiveRequest)
    if not ok then
        Debug("RegisterRequestFailed err=%s", tostring(err))
    end
end

function CastLogComm.BroadcastRecord(record, delaySec)
    local scope = T.Comm and T.Comm.ResolveGroupScope and T.Comm:ResolveGroupScope() or nil
    if not (T.Comm and T.Comm.Send and scope) then
        Debug("BroadcastSkipped reason=missing_group")
        return
    end
    local payload = BuildPayload(record)
    if not payload then
        Debug("BroadcastSkipped reason=empty_payload")
        return
    end
    local delay = tonumber(delaySec) or 0
    if pendingBroadcastTimer and pendingBroadcastTimer.Cancel then
        pendingBroadcastTimer:Cancel()
    end
    pendingBroadcastPayload = payload
    pendingBroadcastScope = scope
    Debug("BroadcastSchedule id=%s scope=%s player=%s bossKey=%s encounter=%s casts=%d delay=%.1f", tostring(payload.castLogID), tostring(scope), tostring(payload.playerName), tostring(payload.bossKeyText), tostring(payload.encounterID), #payload.casts, delay)
    pendingBroadcastTimer = C_Timer.NewTimer(delay, function()
        local sendPayload = pendingBroadcastPayload
        local sendScope = pendingBroadcastScope
        pendingBroadcastTimer = nil
        pendingBroadcastPayload = nil
        pendingBroadcastScope = nil
        if not sendPayload then
            Debug("BroadcastSkipped reason=payload_cleared")
            return
        end
        local ok, err = T.Comm:Send("castLog", "broadcast", sendPayload)
        Debug("BroadcastSendResult id=%s ok=%s result=%s scope=%s bossKey=%s encounter=%s casts=%d reliable=false", tostring(sendPayload.castLogID), tostring(ok), tostring(err), tostring(sendScope), tostring(sendPayload.bossKeyText), tostring(sendPayload.encounterID), #(sendPayload.casts or {}))
    end)
end

function CastLogComm.RequestTeamRecords()
    local scope = T.Comm and T.Comm.ResolveGroupScope and T.Comm:ResolveGroupScope() or nil
    if not (T.Comm and T.Comm.Send and scope) then
        Debug("RequestSkipped reason=missing_group")
        return false
    end
    ClearTeamRecords()
    local payload = BuildRequestPayload()
    local ok, err = T.Comm:Send("castLog", "request", payload)
    Debug("RequestSendResult id=%s ok=%s result=%s scope=%s bossKey=%s encounter=%s", tostring(payload.requestID), tostring(ok), tostring(err), tostring(scope), tostring(payload.bossKeyText), tostring(payload.encounterID))
    return ok
end

function CastLogComm.ClearTeamRecords()
    ClearTeamRecords()
end

function CastLogComm.GetTeamRecords()
    return teamRecords
end

Register()

local eventFrame = CreateFrame and CreateFrame("Frame") or nil
if eventFrame then
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            pendingBroadcastPayload = nil
            pendingBroadcastScope = nil
            if pendingBroadcastTimer and pendingBroadcastTimer.Cancel then
                pendingBroadcastTimer:Cancel()
                pendingBroadcastTimer = nil
            end
        end
        ClearTeamRecords()
    end)
end

end)
