local T = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded", "raidCommandPanel.enabled", "rosterPlanner.enabled", "earlyPull.enabled", "dreadElegy.enabled", "buffCheck.enabled", "castRecorder.backendEnabled", "raidLead.optionPushAccept", "versionCheck.enabled", "tacticTranslator.enabled"}, function()

local Comm = {}
T.Comm = Comm

local PROTOCOL_VERSION = 1
local CMD_ACK = "_ack"
local CMD_RELAY = "_relay"

local CHANNEL_PREFIX = {
    note = "STTNOTE",
    optionpush = "STTOPT1",
    roster = "STTRP1",
    dreadElegy = "STTRUNE",
    buffDurability = "STTBCD",
    version = "STTVER",
    earlyPull = "STTEP",
    castLog = "STTCAST",
}

local COMMAND_POLICY = {
    note = {
        sync = { target = "group", prio = "BULK", reliable = true, ackMode = "business", terminalAckStatuses = { applied = true, reject = true }, timeout = 15, maxRetries = 1, minInterval = 2, coalesce = true },
        ack = { prio = "ALERT", timeout = 5 },
    },
    optionpush = {
        offer = { target = "group", prio = "BULK", reliable = true, ackMode = "business", terminalAckStatuses = { accept = true, merge = true, replace = true, reject = true, noop = true }, timeout = 12, maxRetries = 1, minInterval = 1, coalesce = true },
        ack = { prio = "ALERT", timeout = 5 },
    },
    version = {
        query = { prio = "NORMAL", reliable = false, timeout = 2.5, minInterval = 0.5, coalesce = true },
        reply = { prio = "NORMAL", timeout = 2, minInterval = 0.1 },
        summary = { prio = "NORMAL", timeout = 2 },
    },
    roster = {
        snapshot = { prio = "BULK", timeout = 8, minInterval = 1, coalesce = true },
    },
    dreadElegy = {
        legacy = { prio = "ALERT", timeout = 3, minInterval = 0.1 },
    },
    earlyPull = {
        claim = { prio = "ALERT", timeout = 3, minInterval = 0.1 },
    },
    buffDurability = {
        durability = { prio = "NORMAL", timeout = 3, minInterval = 0.5, coalesce = true },
    },
    castLog = {
        broadcast = { target = "group", prio = "BULK", reliable = false, timeout = 8, minInterval = 5, coalesce = true },
        request = { target = "group", prio = "BULK", reliable = false, timeout = 8, minInterval = 3, coalesce = true },
    },
}

local callbacks = {}
local decodeFailureHandlers = {}
local registered = {}
local pending = {}
local queuedReliable = {}
local throttleState = {}
local selfTests = {}
local receivedMessages = {}
local receivedMessageOrder = {}
local selfTestHandlersReady = false
local sequence = 0
local restrictionBits = 0
local restrictionsEnabled = false
local restrictionFrame = nil
local EnsureRestrictionFrame

local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
local AceComm = LibStub and LibStub:GetLibrary("AceComm-3.0", true)
local transport = AceComm and AceComm:Embed({}) or nil

local SendAddonMessageResult = Enum and Enum.SendAddonMessageResult or {
    Success = 0,
    AddonMessageThrottle = 3,
    ChannelThrottle = 8,
    GeneralError = 9,
}

local function Debug(fmt, ...)
    if not T.debug then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[Comm] " .. tostring(fmt), ...))
    else
        T.debug("[Comm] " .. tostring(fmt))
    end
end

local function CountTableEntries(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do
            count = count + 1
        end
    end
    return count
end

local function ValueSummary(value)
    local valueType = type(value)
    if valueType == "table" then
        return "table:" .. tostring(CountTableEntries(value))
    end
    return tostring(value)
end

local PAYLOAD_SUMMARY_KEYS = {
    "proto",
    "label",
    "mode",
    "moduleId",
    "scanID",
    "requester",
    "target",
    "version",
    "status",
    "reason",
    "planID",
}

local function PayloadSummary(payload)
    if type(payload) ~= "table" then
        return tostring(payload)
    end
    local parts = {}
    for _, key in ipairs(PAYLOAD_SUMMARY_KEYS) do
        if payload[key] ~= nil then
            parts[#parts + 1] = key .. "=" .. ValueSummary(payload[key])
        end
    end
    if type(payload.expected) == "table" then
        parts[#parts + 1] = "expected=" .. tostring(#payload.expected)
    end
    if type(payload.entries) == "table" then
        parts[#parts + 1] = "entries=" .. tostring(CountTableEntries(payload.entries))
    end
    if type(payload.detail) == "table" then
        parts[#parts + 1] = "detail=" .. ValueSummary(payload.detail)
    elseif payload.detail ~= nil then
        parts[#parts + 1] = "detail=" .. tostring(payload.detail)
    end
    if type(payload.data) == "table" then
        local data = payload.data
        if data.name ~= nil then
            parts[#parts + 1] = "dataName=" .. tostring(data.name)
        end
        if data.encounterID ~= nil then
            parts[#parts + 1] = "encounterID=" .. tostring(data.encounterID)
        end
        if type(data.content) == "string" then
            parts[#parts + 1] = "contentLen=" .. tostring(#data.content)
        end
        if type(data.visualBoardPackage) == "table" and type(data.visualBoardPackage.boards) == "table" then
            parts[#parts + 1] = "boardPackageBoards=" .. tostring(#data.visualBoardPackage.boards)
        end
    end
    if #parts == 0 then
        return "keys=" .. tostring(CountTableEntries(payload))
    end
    return table.concat(parts, ",")
end

local function FormatNameList(list, limit)
    if type(list) ~= "table" or #list <= 0 then
        return "-"
    end
    limit = tonumber(limit) or 5
    local parts = {}
    for i = 1, math.min(#list, limit) do
        parts[#parts + 1] = tostring(list[i])
    end
    if #list > limit then
        parts[#parts + 1] = "+" .. tostring(#list - limit)
    end
    return table.concat(parts, ",")
end

local function GetPolicy(channel, cmd)
    local channelPolicy = COMMAND_POLICY[channel]
    return channelPolicy and channelPolicy[cmd] or nil
end

local function IsTerminalBusinessAck(entry, payload)
    local terminalAckStatuses = entry and entry.terminalAckStatuses
    if not terminalAckStatuses then
        return true
    end
    local status = type(payload) == "table" and payload.status or nil
    return status ~= nil and terminalAckStatuses[tostring(status)] == true
end

local function GetPrefix(channel)
    return CHANNEL_PREFIX[channel]
end

local function ShallowCopy(src)
    local dst = {}
    for k, v in pairs(src or {}) do
        dst[k] = v
    end
    return dst
end

local function Now()
    return (GetTime and GetTime()) or 0
end

local function NewMessageID()
    sequence = (sequence % 99999) + 1
    local stamp = (time and time()) or math.floor(Now() * 1000)
    return string.format("%s-%05d-%04d", tostring(stamp), sequence, math.random(0, 9999))
end

local function Encode(envelope)
    if type(envelope) ~= "table" then
        return nil, "envelope_not_table"
    end
    if not (LibSerialize and LibDeflate) then
        return nil, "missing_codec"
    end
    local serialized = LibSerialize:Serialize(envelope)
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then
        return nil, "compress_failed"
    end
    local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
    if not encoded then
        return nil, "encode_failed"
    end
    return encoded
end

local function Decode(text)
    if type(text) ~= "string" then
        return nil, "message_not_string"
    end
    if not (LibSerialize and LibDeflate) then
        return nil, "missing_codec"
    end
    local decoded = LibDeflate:DecodeForWoWAddonChannel(text)
    if not decoded then
        return nil, "decode_failed"
    end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, "decompress_failed"
    end
    local ok, envelope = LibSerialize:Deserialize(decompressed)
    if not ok then
        return nil, "deserialize_failed"
    end
    if type(envelope) ~= "table" then
        return nil, "envelope_not_table"
    end
    return envelope
end

local function RealmFromName(fullName)
    local realm = tostring(fullName or ""):match("%-(.+)$")
    return realm and realm:gsub("%s+", "") or nil
end

local function BuildFullName(name, realm)
    if not name or name == "" then
        return nil
    end
    if tostring(name):find("-", 1, true) then
        return tostring(name)
    end
    realm = realm and realm ~= "" and realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or nil
    if realm and realm ~= "" then
        return tostring(name) .. "-" .. tostring(realm):gsub("%s+", "")
    end
    return tostring(name)
end

local function GetUnitFullName(unit)
    if not unit or not UnitExists or not UnitExists(unit) then
        return nil
    end
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName(unit)
    end
    if not name or name == "" then
        name, realm = UnitName(unit)
    end
    return BuildFullName(name, realm)
end

local function GetPlayerFullName()
    return GetUnitFullName("player") or BuildFullName(UnitName and UnitName("player"))
end

local function ShortName(name)
    if Ambiguate then
        local short = Ambiguate(tostring(name or ""), "short")
        if short and short ~= "" then
            return short
        end
    end
    return tostring(name or ""):match("^([^-]+)") or tostring(name or "")
end

local function NormalizeNameKey(name)
    return tostring(name or ""):gsub("%s+", ""):lower()
end

local function SameName(left, right)
    if NormalizeNameKey(left) == NormalizeNameKey(right) then
        return true
    end
    local leftShort = NormalizeNameKey(ShortName(left))
    local rightShort = NormalizeNameKey(ShortName(right))
    if leftShort ~= "" and leftShort == rightShort then
        local leftRealm = RealmFromName(left)
        local rightRealm = RealmFromName(right)
        if not leftRealm or not rightRealm then
            return true
        end
        return NormalizeNameKey(leftRealm) == NormalizeNameKey(rightRealm)
    end
    return false
end

local function IsSelfTarget(name)
    return SameName(name, GetPlayerFullName()) or SameName(name, UnitName and UnitName("player"))
end

local function IsDuplicateInbound(sender, id)
    if not id then
        return false
    end
    local key = NormalizeNameKey(sender) .. ":" .. tostring(id)
    if receivedMessages[key] then
        return true
    end
    receivedMessages[key] = Now()
    receivedMessageOrder[#receivedMessageOrder + 1] = key
    if #receivedMessageOrder > 500 then
        for i = 1, 100 do
            local oldKey = table.remove(receivedMessageOrder, 1)
            if oldKey then
                receivedMessages[oldKey] = nil
            end
        end
    end
    return false
end

function Comm:NormalizeName(name, realm)
    return BuildFullName(name, realm)
end

function Comm:GetPlayerFullName()
    return GetPlayerFullName()
end

function Comm:IsSelfTarget(name)
    return IsSelfTarget(name)
end

local function IterateGroupUnits(callback)
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            if callback("raid" .. i) then
                return true
            end
        end
        return false
    end
    if IsInGroup and IsInGroup() then
        if callback("player") then
            return true
        end
        for i = 1, (MAX_PARTY_MEMBERS or 4) do
            if callback("party" .. i) then
                return true
            end
        end
    end
    return false
end

local function FindGroupMemberTarget(name)
    local foundName, foundGUID
    IterateGroupUnits(function(unit)
        local unitName = GetUnitFullName(unit)
        if unitName and SameName(unitName, name) then
            foundName = unitName
            foundGUID = UnitGUID(unit)
            return true
        end
        return false
    end)
    return foundName, foundGUID
end

function Comm:ResolvePlayerName(name)
    local memberName = FindGroupMemberTarget(name)
    return memberName or BuildFullName(name)
end

local function IsSameServerGUID(guid)
    if not (guid and C_PlayerInfo and C_PlayerInfo.UnitIsSameServer and PlayerLocation and PlayerLocation.CreateFromGUID) then
        return false
    end
    local ok, same = pcall(function()
        return C_PlayerInfo.UnitIsSameServer(PlayerLocation:CreateFromGUID(guid))
    end)
    return ok and same == true
end

local function ShouldRelayPlayerTarget(name)
    local memberName, memberGUID = FindGroupMemberTarget(name)
    if not memberName then
        return false, BuildFullName(name)
    end
    if IsSameServerGUID(memberGUID) then
        return false, memberName
    end
    local playerRealm = RealmFromName(GetPlayerFullName())
    local memberRealm = RealmFromName(memberName)
    if playerRealm and memberRealm and NormalizeNameKey(playerRealm) == NormalizeNameKey(memberRealm) then
        return false, memberName
    end
    return true, memberName
end

local function TargetKey(target)
    if type(target) == "table" then
        return tostring(target.type or "?") .. ":" .. tostring(target.name or target.target or "")
    end
    return tostring(target or "group")
end

local function AddExpectedTarget(map, list, name)
    if not name or name == "" or IsSelfTarget(name) then
        return
    end
    local key = NormalizeNameKey(name)
    if key == "" or map[key] then
        return
    end
    map[key] = name
    list[#list + 1] = name
end

local function BuildGroupExpectedTargets()
    local map, list = {}, {}
    IterateGroupUnits(function(unit)
        AddExpectedTarget(map, list, GetUnitFullName(unit))
        return false
    end)
    return map, list
end

function Comm:GetGroupTargets()
    local _, list = BuildGroupExpectedTargets()
    return list
end

local function BuildExpectedTargets(opts, route)
    local map, list = {}, {}
    if type(opts.expectedAcks) == "table" then
        for _, name in ipairs(opts.expectedAcks) do
            AddExpectedTarget(map, list, name)
        end
    elseif opts.target == nil or opts.target == "group" or (route and route.semantic == "group") then
        map, list = BuildGroupExpectedTargets()
    elseif type(opts.target) == "table" and opts.target.type == "player" then
        AddExpectedTarget(map, list, route and route.target or opts.target.name or opts.target.target)
    elseif opts.target == "self" then
        AddExpectedTarget(map, list, GetPlayerFullName())
    end
    return map, list, #list
end

local function FindExpectedKey(entry, sender)
    if not entry or not sender or sender == "" then
        return nil
    end
    local key = NormalizeNameKey(sender)
    if entry.expected and entry.expected[key] then
        return key
    end
    if entry.expected then
        for expectedKey, expectedName in pairs(entry.expected) do
            if SameName(expectedName, sender) then
                return expectedKey
            end
        end
    end
    return key
end

local function GetMissingTargets(entry)
    local missing = {}
    if not (entry and entry.expectedList and entry.acks) then
        return missing
    end
    for _, name in ipairs(entry.expectedList) do
        local key = FindExpectedKey(entry, name)
        if key and not entry.acks[key] then
            missing[#missing + 1] = name
        end
    end
    return missing
end

function Comm:ResolveGroupScope()
    local home = LE_PARTY_CATEGORY_HOME or 1
    local instance = LE_PARTY_CATEGORY_INSTANCE or 2
    if IsInRaid and IsInRaid(instance) then
        return "INSTANCE_CHAT"
    end
    if IsInGroup and IsInGroup(instance) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid(home) then
        return "RAID"
    end
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup(home) then
        return "PARTY"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function ResolveTarget(target, opts)
    opts = opts or {}
    if target == nil or target == "group" then
        local scope = Comm:ResolveGroupScope()
        if scope then
            return { distribution = scope, semantic = "group" }
        end
        return nil, "missing_group_scope"
    end
    if target == "guild" then
        return { distribution = "GUILD", semantic = "guild" }
    end
    if target == "self" then
        local playerName = GetPlayerFullName()
        if playerName then
            return { distribution = "WHISPER", target = playerName, semantic = "self" }
        end
        return nil, "missing_self_target"
    end
    if type(target) == "table" and target.type == "player" then
        local name = target.name or target.target
        if not name then
            return nil, "missing_player_target"
        end
        local shouldRelay, resolvedName = ShouldRelayPlayerTarget(name)
        if not resolvedName then
            return nil, "missing_player_target"
        end
        if opts.preferWhisper then
            local route = { distribution = "WHISPER", target = resolvedName, semantic = "player" }
            if opts.backupRelay and shouldRelay then
                local scope = Comm:ResolveGroupScope()
                if scope then
                    route.backupRelayTarget = resolvedName
                    route.backupDistribution = scope
                end
            end
            return route
        end
        if opts.allowRelay ~= false and shouldRelay then
            local scope = Comm:ResolveGroupScope()
            if scope then
                return { distribution = scope, semantic = "relay", relayTarget = resolvedName }
            end
        end
        return { distribution = "WHISPER", target = resolvedName, semantic = "player" }
    end
    return nil, "unknown_target"
end

local function IsRetryableSendResult(result)
    local normalized = tonumber(result)
    return normalized == (SendAddonMessageResult.AddonMessageThrottle or 3)
        or normalized == (SendAddonMessageResult.ChannelThrottle or 8)
        or normalized == (SendAddonMessageResult.GeneralError or 9)
end

local function CancelTimer(timer)
    if timer and timer.Cancel then
        timer:Cancel()
    end
end

local function BuildMeta(envelope, distribution, sender, relayed)
    return {
        id = envelope.id,
        replyTo = envelope.replyTo,
        channel = distribution,
        distribution = distribution,
        sender = sender,
        sentAt = envelope.sentAt,
        target = envelope.target,
        relayed = relayed == true,
        envelope = envelope,
    }
end

local SendEnvelope

local function SendAck(channel, sourceEnvelope, sender, status, extra)
    if not (sourceEnvelope and sourceEnvelope.id and sender and sender ~= "") then
        return
    end
    SendEnvelope(channel, {
        v = PROTOCOL_VERSION,
        channel = channel,
        cmd = CMD_ACK,
        id = NewMessageID(),
        replyTo = sourceEnvelope.id,
        payload = {
            status = status or "received",
            cmd = sourceEnvelope.cmd,
            channel = channel,
            extra = extra,
        },
        sentAt = Now(),
    }, {
        target = { type = "player", name = sender },
        prio = "ALERT",
        allowRelay = true,
        preferWhisper = true,
        backupRelay = true,
        ensureID = true,
    })
end

local function CompletePending(replyTo, payload, sender, ackKind)
    local entry = replyTo and pending[replyTo]
    if not entry then
        return
    end
    ackKind = ackKind or "transport"
    if entry.ackMode == "business" and ackKind ~= "business" then
        return
    end
    if entry.ackMode ~= "business" and ackKind == "business" then
        return
    end
    local status = payload and payload.status or "received"
    local terminalAck = ackKind ~= "business" or IsTerminalBusinessAck(entry, payload)
    local ackKey = FindExpectedKey(entry, sender)
    if entry.expectedCount and entry.expectedCount > 0 then
        if not (ackKey and entry.expected and entry.expected[ackKey]) then
            Debug("CommAckIgnored id=%s channel=%s cmd=%s sender=%s reason=unexpected_sender", tostring(replyTo), tostring(entry.channel), tostring(entry.cmd), tostring(sender))
            return
        end
        if terminalAck and entry.acks[ackKey] then
            Debug("CommAckIgnored id=%s channel=%s cmd=%s sender=%s status=%s reason=duplicate_terminal", tostring(replyTo), tostring(entry.channel), tostring(entry.cmd), tostring(sender), tostring(status))
            return
        end
    elseif terminalAck and entry.ackCount > 0 then
        Debug("CommAckIgnored id=%s channel=%s cmd=%s sender=%s status=%s reason=duplicate_terminal", tostring(replyTo), tostring(entry.channel), tostring(entry.cmd), tostring(sender), tostring(status))
        return
    end
    if terminalAck and ackKey then
        entry.acks[ackKey] = payload or true
    end
    if terminalAck then
        entry.ackCount = (entry.ackCount or 0) + 1
    end
    Debug(
        "CommAck id=%s channel=%s cmd=%s ackKind=%s sender=%s status=%s terminal=%s ack=%d/%d elapsed=%.2f request={%s} response={%s}",
        tostring(replyTo),
        tostring(entry.channel),
        tostring(entry.cmd),
        tostring(ackKind),
        tostring(sender),
        tostring(status),
        tostring(terminalAck),
        entry.ackCount or 0,
        entry.expectedCount or 0,
        entry.createdAt and (Now() - entry.createdAt) or 0,
        PayloadSummary(entry.envelope and entry.envelope.payload),
        PayloadSummary(payload)
    )
    if type(entry.opts.onAck) == "function" then
        pcall(entry.opts.onAck, payload, sender, entry, terminalAck)
    end
    if terminalAck and ((entry.expectedCount or 0) <= 0 or (entry.ackCount or 0) >= entry.expectedCount) then
        pending[replyTo] = nil
        CancelTimer(entry.timer)
        Debug("CommComplete id=%s channel=%s cmd=%s ack=%d/%d elapsed=%.2f", tostring(replyTo), tostring(entry.channel), tostring(entry.cmd), entry.ackCount or 0, entry.expectedCount or 0, entry.createdAt and (Now() - entry.createdAt) or 0)
        if type(entry.opts.onComplete) == "function" then
            pcall(entry.opts.onComplete, entry)
        end
    end
end

local function RetryPending(id, reason)
    local entry = pending[id]
    if not entry then
        return
    end
    local maxRetries = tonumber(entry.opts.maxRetries)
    if maxRetries == nil then
        maxRetries = 1
    end
    if entry.attempt >= maxRetries then
        pending[id] = nil
        CancelTimer(entry.timer)
        entry.missingAcks = GetMissingTargets(entry)
        Debug("CommTimeout id=%s channel=%s cmd=%s target=%s reason=%s ack=%d/%d missing=%d missingList=%s request={%s}", tostring(id), tostring(entry.channel), tostring(entry.cmd), TargetKey(entry.opts.target), tostring(reason), entry.ackCount or 0, entry.expectedCount or 0, #(entry.missingAcks or {}), FormatNameList(entry.missingAcks), PayloadSummary(entry.envelope and entry.envelope.payload))
        if type(entry.opts.onTimeout) == "function" then
            pcall(entry.opts.onTimeout, entry)
        end
        return
    end
    entry.attempt = entry.attempt + 1
    Debug("CommRetry id=%s channel=%s cmd=%s attempt=%d/%d reason=%s", tostring(id), tostring(entry.channel), tostring(entry.cmd), entry.attempt, maxRetries, tostring(reason))
    SendEnvelope(entry.channel, entry.envelope, entry.opts, true)
end

local function StartPendingTimeout(id)
    local entry = pending[id]
    if not entry then
        return
    end
    CancelTimer(entry.timer)
    local timeout = tonumber(entry.opts.timeout) or 5
    if C_Timer and C_Timer.NewTimer then
        entry.timer = C_Timer.NewTimer(timeout, function()
            RetryPending(id, "timeout")
        end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(timeout, function()
            if pending[id] == entry then
                RetryPending(id, "timeout")
            end
        end)
    end
end

local function DispatchEnvelope(channel, envelope, distribution, sender, relayed)
    if envelope.v ~= PROTOCOL_VERSION or envelope.channel ~= channel or type(envelope.cmd) ~= "string" then
        Debug("EnvelopeRejected channel=%s sender=%s reason=bad_envelope", tostring(channel), tostring(sender))
        return
    end

    if envelope.cmd == CMD_RELAY then
        local relay = envelope.payload
        if type(relay) ~= "table" or type(relay.envelope) ~= "table" then
            Debug("RelayRejected sender=%s reason=bad_payload", tostring(sender))
            return
        end
        if not IsSelfTarget(relay.target) then return end
        DispatchEnvelope(channel, relay.envelope, distribution, sender, true)
        return
    end

    if envelope.cmd == CMD_ACK then
        CompletePending(envelope.replyTo or (envelope.payload and envelope.payload.replyTo), envelope.payload, sender, "transport")
        return
    end

    if IsSelfTarget(sender) and not (envelope.target and envelope.target.type == "self") then return end

    if IsDuplicateInbound(sender, envelope.id) then return end

    local businessReplyTo = type(envelope.payload) == "table" and envelope.payload.replyTo or nil
    local businessAckConsumed = false
    if businessReplyTo and pending[businessReplyTo] and pending[businessReplyTo].ackMode == "business" then
        CompletePending(businessReplyTo, envelope.payload, sender, "business")
        businessAckConsumed = true
    end

    local channelCallbacks = callbacks[channel]
    local list = channelCallbacks and channelCallbacks[envelope.cmd] or nil
    if not list then
        if businessAckConsumed then
            return
        end
        Debug("NoHandler channel=%s cmd=%s sender=%s", tostring(channel), tostring(envelope.cmd), tostring(sender))
        if envelope.requireAck then
            SendAck(channel, envelope, sender, "no_handler")
        end
        return
    end

    local meta = BuildMeta(envelope, distribution, sender, relayed)
    for _, callback in ipairs(list) do
        local ok, err = pcall(callback, envelope.payload, sender, meta)
        if not ok then
            Debug("CallbackFailed channel=%s cmd=%s sender=%s err=%s", tostring(channel), tostring(envelope.cmd), tostring(sender), tostring(err))
        end
    end

    if envelope.requireAck then
        SendAck(channel, envelope, sender, "received")
    end
end

local function RawSend(channel, envelope, route, opts)
    local prefix = GetPrefix(channel)
    if not prefix then
        return false, "unknown_channel"
    end
    if not transport then
        return false, "missing_acecomm"
    end
    local encoded, err = Encode(envelope)
    if not encoded then
        Debug("EncodeFailed channel=%s cmd=%s err=%s", tostring(channel), tostring(envelope and envelope.cmd), tostring(err))
        return false, err
    end

    local prio = opts.prio or "NORMAL"
    local ok, result = pcall(transport.SendCommMessage, transport, prefix, encoded, route.distribution, route.target, prio, function(_, sent, total, sendResult)
        local didSend = sent == true or (type(sent) == "number" and type(total) == "number" and sent >= total)
        if type(opts.onProgress) == "function" then
            pcall(opts.onProgress, sent, total, sendResult)
        end
        if didSend == false and opts.reliable and IsRetryableSendResult(sendResult) then
            RetryPending(envelope.id, "send_result_" .. tostring(sendResult))
        end
    end)
    if not ok then
        Debug("SendFailed channel=%s cmd=%s route=%s target=%s err=%s", tostring(channel), tostring(envelope and envelope.cmd), tostring(route.distribution), tostring(route.target), tostring(result))
        return false, result
    end
    return true
end

local function QueueReliable(channel, cmd, payload, opts, reason)
    local key = opts.queueKey or (channel .. ":" .. cmd .. ":" .. TargetKey(opts.target))
    queuedReliable[key] = {
        channel = channel,
        cmd = cmd,
        payload = payload,
        opts = ShallowCopy(opts),
        reason = reason,
    }
    return true, "queued_" .. tostring(reason)
end

local function ShouldDefer(opts)
    if opts._skipDefer or opts.reliable ~= true then
        return false
    end
    if restrictionsEnabled then
        return true, "restricted"
    end
    if opts.deferInCombat and InCombatLockdown and InCombatLockdown() then
        return true, "combat"
    end
    return false
end

local function FlushQueued(reason)
    if restrictionsEnabled then
        return
    end
    for key, item in pairs(queuedReliable) do
        local opts = item.opts or {}
        if not (opts.deferInCombat and InCombatLockdown and InCombatLockdown()) then
            queuedReliable[key] = nil
            opts._skipDefer = true
            Comm:Send(item.channel, item.cmd, item.payload, opts)
        end
    end
end

local function ApplyThrottle(channel, cmd, payload, opts)
    if opts._skipThrottle then
        return false
    end
    local minInterval = tonumber(opts.minInterval)
    if not minInterval or minInterval <= 0 then
        return false
    end
    local key = opts.throttleKey or (channel .. ":" .. cmd .. ":" .. TargetKey(opts.target))
    local now = Now()
    local state = throttleState[key] or { last = 0 }
    throttleState[key] = state
    local remaining = minInterval - (now - state.last)
    if remaining <= 0 then
        state.last = now
        return false
    end
    if opts.coalesce then
        state.pending = {
            channel = channel,
            cmd = cmd,
            payload = payload,
            opts = ShallowCopy(opts),
        }
        if not state.timer then
            state.timer = C_Timer and C_Timer.NewTimer and C_Timer.NewTimer(remaining, function()
                state.timer = nil
                local pendingSend = state.pending
                state.pending = nil
                if pendingSend then
                    pendingSend.opts._skipThrottle = true
                    state.last = Now()
                    Comm:Send(pendingSend.channel, pendingSend.cmd, pendingSend.payload, pendingSend.opts)
                end
            end)
        end
        return true, "coalesced"
    end
    return true, "throttled"
end

SendEnvelope = function(channel, envelope, opts, isRetry)
    opts = opts or {}
    local route, err = ResolveTarget(opts.target or "group", opts)
    if not route then
        return false, err
    end

    local sendEnvelope = envelope
    if route.semantic == "relay" then
        sendEnvelope = {
            v = PROTOCOL_VERSION,
            channel = channel,
            cmd = CMD_RELAY,
            id = NewMessageID(),
            payload = {
                target = route.relayTarget,
                envelope = envelope,
            },
            sentAt = Now(),
        }
        envelope.target = { type = "player", name = route.relayTarget, route = "relay" }
    else
        envelope.target = { type = route.semantic, name = route.target, route = route.distribution }
    end
    if route.backupRelayTarget then
        envelope.target.route = "WHISPER+RELAY"
    end

    if opts.reliable and envelope.id and not pending[envelope.id] then
        local expected, expectedList, expectedCount = BuildExpectedTargets(opts, route)
        pending[envelope.id] = {
            channel = channel,
            cmd = envelope.cmd,
            envelope = envelope,
            opts = opts,
            attempt = isRetry and 1 or 0,
            ackMode = opts.ackMode or "transport",
            terminalAckStatuses = opts.terminalAckStatuses,
            expected = expected,
            expectedList = expectedList,
            expectedCount = expectedCount,
            acks = {},
            ackCount = 0,
            createdAt = Now(),
        }
        StartPendingTimeout(envelope.id)
    elseif opts.reliable and envelope.id and pending[envelope.id] then
        StartPendingTimeout(envelope.id)
    end

    local ok, err = RawSend(channel, sendEnvelope, route, opts)
    if route.backupRelayTarget then
        local relayEnvelope = {
            v = PROTOCOL_VERSION,
            channel = channel,
            cmd = CMD_RELAY,
            id = NewMessageID(),
            payload = {
                target = route.backupRelayTarget,
                envelope = envelope,
            },
            sentAt = Now(),
        }
        local relayRoute = { distribution = route.backupDistribution, semantic = "relay_backup" }
        local relayOk, relayErr = RawSend(channel, relayEnvelope, relayRoute, opts)
        if not ok and relayOk then
            return true
        end
        if not ok then
            return false, err
        end
        if not relayOk then
            Debug("BackupRelayFailed id=%s channel=%s cmd=%s err=%s", tostring(envelope.id), tostring(channel), tostring(envelope.cmd), tostring(relayErr))
        end
    end
    return ok, err
end

function Comm:Register(channel, cmd, onReceive)
    if type(cmd) ~= "string" or cmd == "" then
        return false, "cmd_required"
    end
    if type(onReceive) ~= "function" then
        return false, "callback_not_function"
    end
    local prefix = GetPrefix(channel)
    if not prefix then
        return false, "unknown_channel"
    end
    if not transport then
        return false, "missing_acecomm"
    end

    callbacks[channel] = callbacks[channel] or {}
    callbacks[channel][cmd] = callbacks[channel][cmd] or {}
    callbacks[channel][cmd][#callbacks[channel][cmd] + 1] = onReceive

    if not registered[channel] then
        transport:RegisterComm(prefix, function(_, text, distribution, sender)
            local envelope, err = Decode(text)
            if not envelope then
                Debug("CommDecodeFailed channel=%s sender=%s bytes=%d err=%s", tostring(channel), tostring(sender), #(text or ""), tostring(err))
                local handlers = decodeFailureHandlers[channel]
                if handlers then
                    local meta = {
                        channel = channel,
                        distribution = distribution,
                        sender = sender,
                        bytes = #(text or ""),
                        err = err,
                    }
                    for _, handler in ipairs(handlers) do
                        pcall(handler, meta)
                    end
                end
                return
            end
            DispatchEnvelope(channel, envelope, distribution, sender)
        end)
        registered[channel] = true
    end
    return true
end

function Comm:RegisterDecodeFailureHandler(channel, handler)
    if type(channel) ~= "string" or channel == "" then
        return false, "channel_required"
    end
    if type(handler) ~= "function" then
        return false, "handler_required"
    end
    decodeFailureHandlers[channel] = decodeFailureHandlers[channel] or {}
    decodeFailureHandlers[channel][#decodeFailureHandlers[channel] + 1] = handler
    return true
end

function Comm:Send(channel, cmd, payload, opts)
    if type(cmd) ~= "string" or cmd == "" then
        return false, "cmd_required"
    end
    if not GetPrefix(channel) then
        return false, "unknown_channel"
    end
    if type(payload) ~= "table" then
        return false, "payload_not_table"
    end
    opts = ShallowCopy(opts)
    local policy = GetPolicy(channel, cmd) or {}
    opts.prio = opts.prio or policy.prio or "NORMAL"
    opts.target = opts.target or policy.target or "group"
    opts.reliable = opts.reliable == true or (opts.reliable == nil and policy.reliable == true)
    opts.ackMode = opts.ackMode or policy.ackMode or "transport"
    opts.terminalAckStatuses = opts.terminalAckStatuses or policy.terminalAckStatuses
    opts.timeout = opts.timeout or policy.timeout or 5
    opts.maxRetries = opts.maxRetries or policy.maxRetries
    opts.minInterval = opts.minInterval or policy.minInterval
    opts.coalesce = opts.coalesce == true or (opts.coalesce == nil and policy.coalesce == true)

    if opts.reliable == true or opts.deferInCombat == true then
        EnsureRestrictionFrame()
    end

    local shouldThrottle, throttleResult = ApplyThrottle(channel, cmd, payload, opts)
    if shouldThrottle then
        return throttleResult == "coalesced", throttleResult
    end

    local shouldDefer, deferReason = ShouldDefer(opts)
    if shouldDefer then
        return QueueReliable(channel, cmd, payload, opts, deferReason)
    end

    local envelope = {
        v = PROTOCOL_VERSION,
        channel = channel,
        cmd = cmd,
        id = (opts.reliable or opts.backupRelay or opts.ensureID) and NewMessageID() or opts.id,
        replyTo = opts.replyTo,
        payload = payload,
        requireAck = opts.reliable == true and opts.ackMode ~= "business",
        sentAt = Now(),
    }
    return SendEnvelope(channel, envelope, opts)
end

local function EnsureSelfTestHandlers()
    if selfTestHandlersReady then
        return true
    end
    local ok, err = Comm:Register("version", "_selftest_ping", function(payload, sender, meta)
        local nonce = type(payload) == "table" and payload.nonce or nil
        local replyTarget = sender or GetPlayerFullName()
        local replyRoute = IsSelfTarget(replyTarget) and "self" or { type = "player", name = replyTarget }
        Debug("SelfTestPingReceived nonce=%s sender=%s dist=%s relayed=%s", tostring(nonce), tostring(sender), tostring(meta and meta.distribution), tostring(meta and meta.relayed))
        Comm:Send("version", "_selftest_pong", {
            nonce = nonce,
            from = GetPlayerFullName(),
            route = meta and meta.distribution,
            relayed = meta and meta.relayed == true,
        }, {
            target = replyRoute,
            prio = "NORMAL",
            reliable = false,
            allowRelay = true,
            preferWhisper = true,
            backupRelay = true,
            ensureID = true,
            minInterval = 0,
        })
    end)
    if not ok then
        return false, err
    end
    ok, err = Comm:Register("version", "_selftest_pong", function(payload, sender, meta)
        local nonce = type(payload) == "table" and payload.nonce or nil
        local entry = nonce and selfTests[nonce] or nil
        if not entry then
            Debug("SelfTestPongIgnored nonce=%s sender=%s reason=unknown_nonce", tostring(nonce), tostring(sender))
            return
        end
        CancelTimer(entry.timer)
        selfTests[nonce] = nil
        Debug("SelfTestOK nonce=%s sender=%s dist=%s relayed=%s", tostring(nonce), tostring(sender), tostring(meta and meta.distribution), tostring(meta and meta.relayed))
        if T.msg then
            T.msg(string.format("通信自检成功：target=%s sender=%s route=%s", tostring(entry.label), tostring(sender), tostring(meta and meta.distribution)))
        end
    end)
    if not ok then
        return false, err
    end
    selfTestHandlersReady = true
    return true
end

function Comm:RunSelfTest(targetArg)
    local ok, err = EnsureSelfTestHandlers()
    if not ok then
        if T.msg then
            T.msg("通信自检失败：注册失败 " .. tostring(err))
        end
        return false, err
    end

    targetArg = tostring(targetArg or "")
    local target, label
    if targetArg == "" or targetArg == "self" then
        target = "self"
        label = "self"
    elseif targetArg == "group" then
        target = "group"
        label = "group"
    else
        target = { type = "player", name = targetArg }
        label = targetArg
    end

    local nonce = NewMessageID()
    selfTests[nonce] = { label = label }
    if C_Timer and C_Timer.NewTimer then
        selfTests[nonce].timer = C_Timer.NewTimer(3, function()
            if selfTests[nonce] then
                selfTests[nonce] = nil
                Debug("SelfTestTimeout nonce=%s target=%s", tostring(nonce), tostring(label))
                if T.msg then
                    T.msg("通信自检超时：target=" .. tostring(label))
                end
            end
        end)
    end

    ok, err = Comm:Send("version", "_selftest_ping", {
        nonce = nonce,
        from = GetPlayerFullName(),
    }, {
        target = target,
        prio = "NORMAL",
        reliable = false,
        allowRelay = true,
        preferWhisper = true,
        backupRelay = true,
        ensureID = true,
        minInterval = 0,
    })
    if not ok then
        local entry = selfTests[nonce]
        if entry then
            CancelTimer(entry.timer)
            selfTests[nonce] = nil
        end
        Debug("SelfTestSendFailed nonce=%s target=%s err=%s", tostring(nonce), tostring(label), tostring(err))
        if T.msg then
            T.msg("通信自检发送失败：target=" .. tostring(label) .. " err=" .. tostring(err))
        end
        return false, err
    end
    if T.msg then
        T.msg("通信自检已发送：target=" .. tostring(label))
    end
    return true
end

function Comm:GetPrefix(channel)
    return GetPrefix(channel)
end

function Comm:IsRestricted()
    return restrictionsEnabled == true
end

local function OnRestrictionChanged(_, restrictionType, state)
    if not (Enum and Enum.AddOnRestrictionState and bit and restrictionType ~= nil) then
        return
    end
    local active = state == Enum.AddOnRestrictionState.Active or state == Enum.AddOnRestrictionState.Activating
    local bitValue = bit and restrictionType and bit.lshift(1, restrictionType) or 0
    if active then
        restrictionBits = bit.bor(restrictionBits, bitValue)
    else
        restrictionBits = bit.band(restrictionBits, bit.bnot(bitValue))
    end
    local nextRestricted = bit.band(restrictionBits, 0x6) ~= 0
    if nextRestricted ~= restrictionsEnabled then
        restrictionsEnabled = nextRestricted
        Debug("RestrictionChanged active=%s bits=0x%x", tostring(restrictionsEnabled), restrictionBits)
        if not restrictionsEnabled then
            FlushQueued("restriction_lifted")
        end
    end
end

function EnsureRestrictionFrame()
    if restrictionFrame or type(CreateFrame) ~= "function" then
        return
    end
    restrictionFrame = CreateFrame("Frame")
    if restrictionFrame.RegisterEvent then
        pcall(restrictionFrame.RegisterEvent, restrictionFrame, "ADDON_RESTRICTION_STATE_CHANGED")
        pcall(restrictionFrame.RegisterEvent, restrictionFrame, "PLAYER_REGEN_ENABLED")
    end
    restrictionFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_RESTRICTION_STATE_CHANGED" then
            OnRestrictionChanged(nil, ...)
        elseif event == "PLAYER_REGEN_ENABLED" then
            FlushQueued("combat_lifted")
        end
    end)
end

function Comm:EnsureRestrictionFrame()
    EnsureRestrictionFrame()
end

end)
