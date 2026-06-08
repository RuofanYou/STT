local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("earlyPull.enabled", function()

T.EarlyPull = T.EarlyPull or {}
local Claim = {
    pendingSelfClaim = nil,
    currentEncounter = nil,
    lastSentSessionKey = nil,
    receivedBySession = {},
    receivedLru = {},
}
T.EarlyPull.Claim = Claim

local function Const()
    return T.EarlyPull.Constants or {}
end

local function Debug(message)
    if T.debug then
        T.debug("[EarlyPull] " .. tostring(message))
    end
end

local function StripRealm(name)
    if type(name) ~= "string" or name == "" then
        return name
    end
    local short = name:match("^([^%-]+)")
    return short or name
end

local function PlayerFullName()
    local name = UnitName("player") or ""
    local realm = GetRealmName() or ""
    if realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function InChatMessagingLockdown()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, restricted, reason = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok then
            return restricted == true, reason
        end
    end
    return false, nil
end

local function PickSendChannel()
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function MakeSessionKey(encounterID, difficultyID)
    return tostring(encounterID or 0) .. ":" .. tostring(difficultyID or 0)
end

local function PushLru(sessionKey)
    local lru = Claim.receivedLru
    for i = #lru, 1, -1 do
        if lru[i] == sessionKey then
            table.remove(lru, i)
        end
    end
    table.insert(lru, sessionKey)
    local maxSize = tonumber(Const().receivedSessionLruSize) or 8
    while #lru > maxSize do
        local oldKey = table.remove(lru, 1)
        if oldKey then
            Claim.receivedBySession[oldKey] = nil
        end
    end
end

-- ============================================================
-- self-claim 记录链路
-- ============================================================

function Claim.RecordRegenEarly(now, expectedPullTime)
    local window = tonumber(Const().pullOnTimeWindow) or 1
    local diff = now - expectedPullTime  -- 负=提前
    if diff > -window then
        return false
    end
    local encounter = Claim.currentEncounter
    Claim.pendingSelfClaim = {
        diffMs = math.floor(diff * 1000 + 0.5),
        playerGUID = UnitGUID("player") or "",
        playerName = PlayerFullName(),
        reason = "regen",
        encounterID = encounter and encounter.encounterID or nil,
        difficultyID = encounter and encounter.difficultyID or nil,
        sessionKey = encounter and encounter.sessionKey or nil,
        createdAt = now,
    }
    Debug("self_claim_recorded reason=regen diff=" .. tostring(diff)
        .. " session=" .. tostring(Claim.pendingSelfClaim.sessionKey))
    return true
end

function Claim.UpgradeReason(reason, spellID)
    local pending = Claim.pendingSelfClaim
    if not pending then
        return
    end
    if pending.reason == reason then
        return
    end
    pending.reason = reason
    pending.spellID = spellID
    Debug("self_claim_upgrade reason=" .. tostring(reason) .. " spell=" .. tostring(spellID))
end

function Claim.FinalizeEncounter(encounterID, difficultyID)
    local sessionKey = MakeSessionKey(encounterID, difficultyID)
    Claim.currentEncounter = {
        encounterID = encounterID,
        difficultyID = difficultyID,
        sessionKey = sessionKey,
    }
    local pending = Claim.pendingSelfClaim
    if pending then
        pending.encounterID = encounterID
        pending.difficultyID = difficultyID
        pending.sessionKey = sessionKey
        Debug("self_claim_finalized encounterID=" .. tostring(encounterID)
            .. " difficultyID=" .. tostring(difficultyID))
    end
end

-- 战中 blame 已展示后由 early_pull.lua 调，用于战后去重
function Claim.MarkBlameDisplayed(sessionKey, playerName)
    if not sessionKey then
        return
    end
    Claim.receivedBySession[sessionKey] = Claim.receivedBySession[sessionKey] or {
        firstAt = GetTime(),
        claims = {},
        displayed = true,
    }
    local entry = Claim.receivedBySession[sessionKey]
    entry.displayed = true
    entry.displayedSource = "blame_local"
    entry.displayedPlayerShort = StripRealm(playerName or "")
    PushLru(sessionKey)
end

-- ============================================================
-- 战后发送（脱战后 1s 触发；遇 lockdown 重试 N 次）
-- ============================================================

local function TrySendOnce(payload, attempt)
    local locked, lockReason = InChatMessagingLockdown()
    if locked then
        Debug("post_sync_send_blocked attempt=" .. attempt .. " lockdown=" .. tostring(lockReason))
        return false
    end
    local channel = PickSendChannel()
    if not channel then
        Debug("post_sync_send_skip reason=no_channel")
        return true  -- 单人无频道：不再重试，本地展示由 self-loopback 缺失，由 ShowPostSync 直发兜底
    end
    if not T.Comm then
        Debug("post_sync_send_skip reason=comm_missing")
        return true
    end
    local ok, result = T.Comm:Send("earlyPull", "claim", { type = "claim", message = payload }, { target = "group", prio = "ALERT" })
    if ok ~= true then
        Debug("post_sync_send_failed attempt=" .. attempt .. " channel=" .. channel
            .. " result=" .. tostring(result))
    end
    return ok == true
end

local function ScheduleRetry(payload, attempt)
    local maxRetry = tonumber(Const().postCombatSendMaxRetry) or 5
    if attempt >= maxRetry then
        Debug("post_sync_send_giveup attempt=" .. attempt)
        return
    end
    local gap = tonumber(Const().postCombatSendRetryGap) or 1
    local nextAttempt = attempt + 1
    C_Timer.After(gap, function()
        local sent = TrySendOnce(payload, nextAttempt)
        if not sent then
            ScheduleRetry(payload, nextAttempt)
        end
    end)
end

local function BuildPayload(claim)
    local version = tonumber(Const().syncProtocolVersion) or 1
    return table.concat({
        "C",
        tostring(version),
        tostring(claim.sessionKey or MakeSessionKey(claim.encounterID, claim.difficultyID)),
        tostring(claim.encounterID or 0),
        tostring(claim.difficultyID or 0),
        tostring(claim.diffMs or 0),
        tostring(claim.playerGUID or ""),
        tostring(claim.playerName or ""),
        tostring(claim.reason or "regen"),
    }, "\t")
end

function Claim.SendIfPending(triggerReason)
    local pending = Claim.pendingSelfClaim
    if not pending then
        return
    end
    if not pending.sessionKey then
        return
    end
    if Claim.lastSentSessionKey == pending.sessionKey then
        return
    end
    Claim.lastSentSessionKey = pending.sessionKey
    local payload = BuildPayload(pending)
    local delay = tonumber(Const().postCombatSendDelay) or 1

    -- 单人/无频道场景：本地直显（自己提前开怪也要看到结果）
    local channel = PickSendChannel()
    local localFallbackClaim
    if not channel then
        localFallbackClaim = {
            playerName = pending.playerName,
            playerGUID = pending.playerGUID,
            diffMs = pending.diffMs,
            reason = pending.reason,
            sessionKey = pending.sessionKey,
        }
    end

    C_Timer.After(delay, function()
        if localFallbackClaim then
            Debug("post_sync_local_fallback reason=no_channel")
            Claim.DisplayClaim(localFallbackClaim)
            return
        end
        local sent = TrySendOnce(payload, 1)
        if not sent then
            ScheduleRetry(payload, 1)
        end
    end)
end

-- ============================================================
-- 接收 + 去重 + 展示
-- ============================================================

local function ParseMessage(message)
    if type(message) ~= "string" or message == "" then
        return nil
    end
    local parts = { strsplit("\t", message) }
    if #parts < 9 then
        return nil
    end
    local command, version = parts[1], tonumber(parts[2])
    if command ~= "C" then
        return nil
    end
    local expectedVersion = tonumber(Const().syncProtocolVersion) or 1
    if version ~= expectedVersion then
        return nil, "version_mismatch"
    end
    local claim = {
        command = command,
        version = version,
        sessionKey = parts[3],
        encounterID = tonumber(parts[4]),
        difficultyID = tonumber(parts[5]),
        diffMs = tonumber(parts[6]),
        playerGUID = parts[7],
        playerName = parts[8],
        reason = parts[9],
    }
    if not (claim.sessionKey and claim.diffMs and claim.playerName and claim.playerName ~= "") then
        return nil, "field_invalid"
    end
    return claim
end

local function PickWinner(claims)
    local winner
    for _, c in ipairs(claims) do
        if not winner or (tonumber(c.diffMs) or 0) < (tonumber(winner.diffMs) or 0) then
            winner = c
        end
    end
    return winner
end

local function FlushSession(sessionKey)
    local entry = Claim.receivedBySession[sessionKey]
    if not entry then
        return
    end
    entry.displayTimer = nil
    local winner = PickWinner(entry.claims)
    if not winner then
        return
    end
    local winnerShort = StripRealm(winner.playerName)
    -- 同名 → 战中（推测）已正确，忽略 STTEP；异名 → 走纠正模式（「实际开怪：…」）。
    if entry.displayedSource == "blame_local" then
        if entry.displayedPlayerShort == winnerShort then
            Debug("post_sync_ignored reason=blame_local_already_shown session=" .. sessionKey
                .. " player=" .. tostring(winnerShort))
            entry.displayed = true
            return
        end
        Debug("post_sync_correct session=" .. sessionKey
            .. " blame_player=" .. tostring(entry.displayedPlayerShort)
            .. " actual_player=" .. tostring(winnerShort))
        Claim.DisplayClaim(winner, true)
        entry.displayed = true
        entry.displayedSource = "post_sync_correct"
        entry.displayedPlayerShort = winnerShort
        return
    end
    if entry.displayed then
        Debug("post_sync_ignored reason=already_displayed session=" .. sessionKey)
        return
    end
    Claim.DisplayClaim(winner, false)
    entry.displayed = true
    entry.displayedSource = "post_sync_shown"
    entry.displayedPlayerShort = winnerShort
end

function Claim.OnReceive(prefix, message, channel, sender)
    if prefix ~= (Const().syncPrefix or "STTEP") then
        return
    end
    local claim, parseErr = ParseMessage(message)
    if not claim then
        Debug("post_sync_received_drop reason=" .. tostring(parseErr or "parse_fail")
            .. " sender=" .. tostring(sender))
        return
    end
    Debug("post_sync_received player=" .. tostring(claim.playerName)
        .. " diff=" .. tostring((claim.diffMs or 0) / 1000)
        .. " session=" .. tostring(claim.sessionKey)
        .. " sender=" .. tostring(sender))

    local sessionKey = claim.sessionKey
    local entry = Claim.receivedBySession[sessionKey]
    if not entry then
        entry = {
            firstAt = GetTime(),
            claims = {},
            displayed = false,
        }
        Claim.receivedBySession[sessionKey] = entry
        PushLru(sessionKey)
    end
    -- 同一 sender 只保留首条
    for _, existing in ipairs(entry.claims) do
        if existing.playerGUID == claim.playerGUID then
            Debug("post_sync_ignored reason=duplicate_sender player=" .. tostring(claim.playerName))
            return
        end
    end
    table.insert(entry.claims, claim)

    if entry.displayed then
        Debug("post_sync_ignored reason=already_displayed_late_arrival player=" .. tostring(claim.playerName))
        return
    end
    if entry.displayTimer then
        return
    end
    local windowDelay = tonumber(Const().postSyncDisplayDelay) or 0.5
    entry.displayTimer = true
    C_Timer.After(windowDelay, function()
        FlushSession(sessionKey)
    end)
end

function Claim.DisplayClaim(claim, isCorrection)
    if T.EarlyPull.Announce and T.EarlyPull.Announce.ShowPostSync then
        T.EarlyPull.Announce:ShowPostSync(claim, isCorrection)
    end
end

-- ============================================================
-- 生命周期
-- ============================================================

function Claim.ResetSession()
    Claim.pendingSelfClaim = nil
    Claim.currentEncounter = nil
    -- receivedBySession 不立即清，让晚到的 STTEP 仍能命中已展示标记被忽略；
    -- 由 LRU 控制上限避免无限增长。
end

-- 给本地测试用：构造一条 fake claim 直接展示，绕过 addon 通信
function Claim.LocalTest(diffSeconds)
    local diff = tonumber(diffSeconds) or -3.2
    local claim = {
        playerName = PlayerFullName(),
        playerGUID = UnitGUID("player") or "",
        diffMs = math.floor(diff * 1000 + 0.5),
        reason = "test",
        sessionKey = MakeSessionKey(0, 0),
    }
    Claim.DisplayClaim(claim)
end

end)
