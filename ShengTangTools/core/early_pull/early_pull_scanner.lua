local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("earlyPull.enabled", function()

T.EarlyPull = T.EarlyPull or {}
local Scanner = {}
T.EarlyPull.Scanner = Scanner

local GROUP_CHANNEL = {
    RAID = true,
    PARTY = true,
    INSTANCE_CHAT = true,
}

local function DebugOnce(runtime, key, message)
    runtime.debugOnce = runtime.debugOnce or {}
    if runtime.debugOnce[key] then
        return
    end
    runtime.debugOnce[key] = true
    if T.debug then
        T.debug("[EarlyPull] " .. message)
    end
end

local function IsCombatLogRestricted(runtime)
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
        local ok, restricted = pcall(C_CombatLog.IsCombatLogRestricted)
        if ok and restricted == true then
            DebugOnce(runtime, "combatLogRestricted", "combat_log_restricted=true")
            return true
        end
    end
    return false
end

local function IsPlayerControlledSource(flags)
    if not (flags and bit and COMBATLOG_OBJECT_CONTROL_MASK and COMBATLOG_OBJECT_CONTROL_PLAYER) then
        return false
    end
    return bit.band(flags, COMBATLOG_OBJECT_CONTROL_MASK) == COMBATLOG_OBJECT_CONTROL_PLAYER
end

local function IsHostileNpc(flags)
    if not (flags and bit and COMBATLOG_OBJECT_CONTROL_MASK and COMBATLOG_OBJECT_CONTROL_NPC and COMBATLOG_OBJECT_REACTION_MASK) then
        return false
    end
    local control = bit.band(flags, COMBATLOG_OBJECT_CONTROL_MASK)
    local reaction = bit.band(flags, COMBATLOG_OBJECT_REACTION_MASK)
    return control == COMBATLOG_OBJECT_CONTROL_NPC
        and (reaction == COMBATLOG_OBJECT_REACTION_HOSTILE or reaction == COMBATLOG_OBJECT_REACTION_NEUTRAL)
end

-- 12.0 secret 系统总结：
-- 1) UnitGUID("bossN") / UnitName("bossN") 一律 secret——boss 集合不可维护。
-- 2) UnitThreatSituation(unit, "bossN") 返回 secret 数字——threat 路径已删（参见上方注释）。
-- 3) "boss1target" 这类复合 token 沿目标链传染 secret——target 路径同样拔除。
-- blame 退化为 CLEU 单路；CLEU 中 isBossTarget 一律按 false（所有候选人同等惩罚，相对排序仍成立）。

local function UnitFullName(unit)
    local name, realm = UnitName(unit)
    if not name then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name .. "-" .. (GetRealmName() or "")
end

local function SenderUnit(sender)
    if not sender then
        return nil
    end
    if UnitFullName("player") == sender or UnitName("player") == sender then
        return "player"
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitFullName(unit) == sender or UnitName(unit) == sender then
                return unit
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitFullName(unit) == sender or UnitName(unit) == sender then
                return unit
            end
        end
    end
    return nil
end

local function MayAcceptPullTimer(sender)
    local unit = SenderUnit(sender)
    if not unit then
        return false
    end
    return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
end

-- 12.0 secret 系统下三路信号的现状：
-- - threat：UnitThreatSituation 返回 secret 数字，比较即崩，拔除。
-- - boss target：boss1target 沿目标链传染 secret，UnitGUID/UnitName 不可信，拔除。
-- - CLEU：事件 payload 仍可读，retain。blame 退化为 CLEU 单路 + STTEP 战后兜底。

function Scanner.COMBAT_LOG_EVENT_UNFILTERED(runtime, ...)
    if not (runtime and runtime.logs) then
        return
    end

    runtime.cachedCombatLogRestricted = IsCombatLogRestricted(runtime)

    local timestamp, event, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellID, spellName, _, auraType
    if CombatLogGetCurrentEventInfo then
        timestamp, event, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellID, spellName, _, auraType = CombatLogGetCurrentEventInfo()
    else
        timestamp, event, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellID, spellName, _, auraType = ...
    end

    if event == "SPELL_SUMMON" and sourceGUID and destGUID and IsPlayerControlledSource(sourceFlags) then
        runtime.petOwners[destGUID] = {
            ownerGUID = sourceGUID,
            ownerName = sourceName,
            petName = destName,
            time = GetTime(),
        }
        return
    end

    if event == "SPELL_AURA_APPLIED" and auraType ~= "DEBUFF" then
        return
    end
    if not (sourceGUID and destGUID and IsPlayerControlledSource(sourceFlags) and IsHostileNpc(destFlags)) then
        return
    end

    local entry = runtime.logs.combatLog:Advance()
    entry.time = GetTime()
    entry.rawTimestamp = tonumber(timestamp)
    entry.event = event
    entry.sourceGUID = sourceGUID
    entry.name = sourceName
    entry.destGUID = destGUID
    entry.destName = destName
    entry.spellID = tonumber(spellID)
    entry.spellName = spellName
    entry.isBossTarget = false  -- 12.0 secret 限制下不可识别 boss 身份
end

function Scanner.CHAT_MSG_ADDON(runtime, prefix, message, channel, sender)
    if not (runtime and prefix and message and GROUP_CHANNEL[channel] and prefix:sub(1, 2) == "D5") then
        return
    end
    if IsEncounterInProgress and IsEncounterInProgress() then
        return
    end
    if IsInGroup() and not MayAcceptPullTimer(sender) then
        return
    end

    local _, _, ty, duration, instanceID = strsplit("\t", message)
    if ty ~= "PT" then
        return
    end
    duration = tonumber(duration or 0)
    instanceID = tonumber(instanceID)
    local currentInstanceID = select(8, GetInstanceInfo())

    if not duration or duration > 60 or duration < 0 or (duration > 0 and duration < 3) then
        return
    end
    if instanceID and currentInstanceID and instanceID ~= currentInstanceID then
        return
    end

    if duration == 0 then
        if runtime.ClearExpectedPull then
            runtime:ClearExpectedPull()
        else
            runtime.expectedPullTimeDBM = nil
            runtime.countdownActive = false
        end
        T.debug("[EarlyPull] dbm_pt_cancel sender=" .. tostring(sender))
    else
        if runtime.ClearExpectedPull then
            runtime:ClearExpectedPull()
        end
        runtime.expectedPullTimeDBM = GetTime() + duration
        runtime.countdownActive = true
        if runtime.ScheduleCountdownExpiry then
            runtime:ScheduleCountdownExpiry(duration, "dbm")
        end
        T.debug("[EarlyPull] dbm_pt_start duration=" .. tostring(duration) .. " sender=" .. tostring(sender))
    end
end

function Scanner.START_PLAYER_COUNTDOWN(runtime, initiatedBy, timeRemaining, totalTime)
    if not runtime then
        return
    end
    local remain = tonumber(timeRemaining) or tonumber(totalTime)
    if not remain or remain <= 0 then
        return
    end
    if runtime.ClearExpectedPull then
        runtime:ClearExpectedPull()
    end
    runtime.expectedPullTimeBlizz = GetTime() + remain
    runtime.countdownActive = true
    if runtime.ScheduleCountdownExpiry then
        runtime:ScheduleCountdownExpiry(remain, "blizzard")
    end
    T.debug("[EarlyPull] blizzard_countdown_start remain=" .. tostring(remain) .. " initiatedBy=" .. tostring(initiatedBy))
end

function Scanner.CANCEL_PLAYER_COUNTDOWN(runtime, initiatedBy)
    if not runtime then
        return
    end
    runtime.expectedPullTimeBlizz = nil
    runtime.expectedPullTimeSTT = nil
    runtime.expectedPullTimeDBM = nil
    runtime.countdownActive = false
    T.debug("[EarlyPull] blizzard_countdown_cancel initiatedBy=" .. tostring(initiatedBy))
end

end)
