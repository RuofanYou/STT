local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("earlyPull.enabled", function()

local PreloadedEarlyPull = T.EarlyPull or {}
local EarlyPull = T.ModuleLoader:NewModule({
    name = "EarlyPull",
    dbKey = "earlyPull.enabled",
    defaultEnabled = false,
})
for key, value in pairs(PreloadedEarlyPull) do
    if EarlyPull[key] == nil then
        EarlyPull[key] = value
    end
end
T.EarlyPull = EarlyPull

-- 12.0 secret / protected event 限制：boss GUID/Name/Threat/TargetChain 全部 secret 化，
-- threat、boss target 与 CLEU 主动监听都停用；blame 退化为倒计时事件 + STTEP 战后兜底。
EarlyPull.logs = {
    combatLog = T.RingTimeLog.new(EarlyPull.Constants.logSize.combat),
}
EarlyPull.petOwners = {}

local function Debug(message)
    if T.debug then
        T.debug("[EarlyPull] " .. tostring(message))
    end
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

local function ResetLogs()
    for _, log in pairs(EarlyPull.logs) do
        if log.Reset then
            log:Reset()
        end
    end
    wipe(EarlyPull.petOwners)
end

local function GetExpectedPullTime()
    return EarlyPull.expectedPullTimeDBM or EarlyPull.expectedPullTimeSTT or EarlyPull.expectedPullTimeBlizz
end

local function GetPullTimeDiff(pullTime)
    local expected = GetExpectedPullTime()
    if not expected then
        return nil
    end
    local diff = pullTime - expected
    if math.abs(diff) > (EarlyPull.Constants.maxPullTimeDiff or 60) then
        return nil
    end
    return diff
end

local function IsRaidOnly()
    return not (C.DB and C.DB.earlyPull and C.DB.earlyPull.raidOnly == false)
end

local function IsDebugMode()
    return C.DB and C.DB.debugMode == true
end

local function IsEarlyPullEnabled()
    return IsDebugMode() and C.DB and C.DB.earlyPull and C.DB.earlyPull.enabled == true
end

local function SendDbmPullTimer(duration)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        Debug("dbm_pt_send_skip api_missing")
        return false
    end
    local locked, reason = InChatMessagingLockdown()
    if locked then
        Debug("dbm_pt_send_skip lockdown=" .. tostring(reason))
        return false
    end

    local instanceID = select(8, GetInstanceInfo()) or 0
    local player = (UnitName("player") or "player") .. "-" .. (GetRealmName() or "")
    local message = string.format("%s\t1\tPT\t%d\t%d", player, tonumber(duration) or 0, instanceID)
    local channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or (IsInRaid() and "RAID" or "PARTY")
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, "D5", message, channel)
    if not ok or result == false then
        Debug("dbm_pt_send_failed duration=" .. tostring(duration) .. " channel=" .. tostring(channel) .. " result=" .. tostring(ok and result or "error"))
    end
    return ok and result ~= false
end

local function RunBlame(ctx)
    local ok, best, second = pcall(T.EarlyPull.Blame.Run, T.EarlyPull.Blame, ctx)
    if not ok then
        Debug("blame_error " .. tostring(best))
        return nil, nil
    end
    return best, second
end

local function FormatCandidateForDebug(cand)
    if not cand then
        return "-"
    end
    return tostring(cand.name or cand.guid or "-")
        .. "/score=" .. tostring(cand.score or 0)
        .. "/cleu=" .. tostring(cand.combatLogScore or 0)
end

local function LogBlameResult(ctx, best, second)
    local logs = ctx and ctx.logs or {}
    local combatCount = logs.combatLog and logs.combatLog.count or 0
    Debug("blame_result best=" .. FormatCandidateForDebug(best)
        .. " second=" .. FormatCandidateForDebug(second)
        .. " logs=combat:" .. tostring(combatCount))
end

function EarlyPull:ClearExpectedPull()
    self.expectedPullTimeDBM = nil
    self.expectedPullTimeSTT = nil
    self.expectedPullTimeBlizz = nil
    self.countdownActive = false
    self.countdownToken = (self.countdownToken or 0) + 1
end

function EarlyPull:ScheduleCountdownExpiry(duration, reason)
    local seconds = tonumber(duration)
    if not (seconds and seconds > 0) then
        return
    end
    local token = (self.countdownToken or 0) + 1
    self.countdownToken = token
    C_Timer.After(seconds + 1, function()
        if self.countdownToken ~= token then
            return
        end
        Debug("countdown_expired_clear reason=" .. tostring(reason))
        self:ClearExpectedPull()
    end)
end

function EarlyPull:RegisterCombatLogEvent(reason)
    if self.combatLogEventRegistered then
        return
    end
end

function EarlyPull:RegisterCountdownEvents(reason)
    if self.countdownEventsRegistered then
        return
    end
    local locked, lockdownReason = InChatMessagingLockdown()
    if locked then
        Debug("countdown_event_register_skip lockdown=" .. tostring(lockdownReason) .. " reason=" .. tostring(reason))
        return
    end
    local startOk, startErr = pcall(self.frame.RegisterEvent, self.frame, "START_PLAYER_COUNTDOWN")
    local cancelOk, cancelErr = pcall(self.frame.RegisterEvent, self.frame, "CANCEL_PLAYER_COUNTDOWN")
    if startOk and cancelOk then
        self.countdownEventsRegistered = true
    else
        Debug("countdown_event_register_failed reason=" .. tostring(reason)
            .. " start=" .. tostring(startErr)
            .. " cancel=" .. tostring(cancelErr))
    end
end

function EarlyPull:RegisterRestrictedEvents(reason)
    self:RegisterCombatLogEvent(reason)
    self:RegisterCountdownEvents(reason)
end

function EarlyPull:OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    if not IsEarlyPullEnabled() then
        return
    end
    if not (T.InstanceGate and T.InstanceGate.IsRaidActive and T.InstanceGate.IsRaidActive()) then
        return
    end

    local encounterTime = GetTime()
    local pullTime = encounterTime
    local anchor = "encounter"
    local regenAge = self.lastRegenDisabledTime and (encounterTime - self.lastRegenDisabledTime) or nil
    if self.lastRegenDisabledTime
        and self.lastRegenDisabledTime < encounterTime
        and regenAge <= (self.Constants.regenAnchorMaxAge or 5)
    then
        pullTime = self.lastRegenDisabledTime
        anchor = "regen"
    end

    local locked, lockdownReason = InChatMessagingLockdown()
    local combatLogRestricted = self.cachedCombatLogRestricted == true
    if not combatLogRestricted and C_CombatLog and C_CombatLog.IsCombatLogRestricted then
        local ok, restricted = pcall(C_CombatLog.IsCombatLogRestricted)
        combatLogRestricted = ok and restricted == true
    end

    local ctx = {
        pullTime = pullTime,
        pullTimeDiff = GetPullTimeDiff(pullTime),
        encounterID = encounterID,
        encounterName = encounterName,
        difficultyID = difficultyID,
        groupSize = groupSize,
        constants = self.Constants,
        logs = self.logs,
        petOwners = self.petOwners,
        restricted = {
            lockdown = locked,
            lockdownReason = lockdownReason,
            combatLog = combatLogRestricted,
        },
    }

    Debug("encounter_start id=" .. tostring(encounterID)
        .. " diff=" .. tostring(ctx.pullTimeDiff)
        .. " anchor=" .. anchor
        .. " regenAge=" .. tostring(regenAge)
        .. " expected=" .. tostring(GetExpectedPullTime()))
    if T.EarlyPull.Claim and T.EarlyPull.Claim.FinalizeEncounter then
        T.EarlyPull.Claim.FinalizeEncounter(encounterID, difficultyID)
    end
    local sessionKey = tostring(encounterID or 0) .. ":" .. tostring(difficultyID or 0)

    C_Timer.After(self.Constants.afterPullDelay or 0.3, function()
        local best, second = RunBlame(ctx)
        LogBlameResult(ctx, best, second)
        self.lastResult = {
            ctx = ctx,
            best = best,
            second = second,
        }
        local shown = T.EarlyPull.Announce:Show(ctx, best, second)
        if shown and T.EarlyPull.Claim and T.EarlyPull.Claim.MarkBlameDisplayed then
            T.EarlyPull.Claim.MarkBlameDisplayed(sessionKey, best and best.name)
        end
        if self.Constants.autoPrintDetails then
            T.EarlyPull.Details.Print(self)
        end
        self:ClearExpectedPull()
    end)
end

function EarlyPull:CancelCountdown()
    if C_PartyInfo and C_PartyInfo.DoCountdown then
        pcall(C_PartyInfo.DoCountdown, 0)
    end
    if T.InstanceGate and T.InstanceGate.IsRaidActive and T.InstanceGate.IsRaidActive() then
        SendDbmPullTimer(0)
    else
        Debug("dbm_pt_cancel_skip non_raid_test")
    end
    self:ClearExpectedPull()
    T.msg(L["EARLY_PULL_CANCELLED"] or "已取消当前倒数，如需重新开始请再次输入 /stt pull N")
end

function EarlyPull:CanStartPull()
    local isRaidActive = T.InstanceGate and T.InstanceGate.IsRaidActive and T.InstanceGate.IsRaidActive()
    if IsRaidOnly() then
        local reason = T.InstanceGate and T.InstanceGate.GetRaidRejectReason and T.InstanceGate.GetRaidRejectReason()
        if reason then
            return false, reason
        end
    end
    if isRaidActive and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return false, L["EARLY_PULL_NEED_ASSIST"] or "只有团长和助理可以发起拉怪倒数"
    end
    local locked = InChatMessagingLockdown()
    if locked then
        return false, L["EARLY_PULL_LOCKDOWN"] or "战斗中无法发起倒数"
    end
    return true
end

function EarlyPull:RunLocalTest(arg)
    local text = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local mode = "blame"
    local rest = text
    if text:match("^sync") then
        mode = "sync"
        rest = text:gsub("^sync%s*", "")
    end
    local duration = tonumber(rest) or 10
    if duration < 3 or duration > 60 then
        T.msg(L["EARLY_PULL_RANGE_3_60"] or "倒数时间必须在 3–60 秒之间")
        return
    end

    local diff = -math.min(3.2, math.max(1.1, duration / 3))

    if mode == "sync" then
        if T.EarlyPull.Claim and T.EarlyPull.Claim.LocalTest then
            T.EarlyPull.Claim.LocalTest(diff)
        end
        T.msg(string.format(L["EARLY_PULL_TEST_STARTED"] or "已模拟一次提前 %.2f秒 开怪提示", math.abs(diff)))
        return
    end

    local name = UnitName("player") or (L["EARLY_PULL_TEST_PLAYER"] or "测试玩家")
    local ctx = {
        pullTime = GetTime(),
        pullTimeDiff = diff,
        constants = self.Constants,
        restricted = {
            lockdown = false,
            combatLog = false,
        },
    }
    local best = {
        guid = UnitGUID("player"),
        name = name,
        spellID = 6603,
        score = 1,
        combatLogScore = 1,
    }
    self.lastResult = {
        ctx = ctx,
        best = best,
        second = nil,
    }
    T.EarlyPull.Announce:Show(ctx, best, nil)
    T.msg(string.format(L["EARLY_PULL_TEST_STARTED"] or "已模拟一次提前 %.2f秒 开怪提示", math.abs(diff)))
end

function EarlyPull:HandlePullCommand(arg)
    if not IsDebugMode() then
        T.msg(L["EARLY_PULL_BETA_DEBUG_REQUIRED"] or "提前开怪检测仍在 Beta：请先开启 /st debug 并 /reload。")
        return
    end
    if not IsEarlyPullEnabled() then
        T.msg(L["EARLY_PULL_DISABLED"] or "提前开怪检测未启用")
        return
    end

    local text = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "details" then
        T.EarlyPull.Details.Print(self)
        return
    end
    local testArg = text:match("^test%s*(.*)$")
    if text == "test" or testArg then
        self:RunLocalTest(testArg)
        return
    end

    local duration = tonumber(text)
    if text == "" then
        duration = 10
    end
    if duration == 0 then
        self:CancelCountdown()
        return
    end

    if self.countdownActive then
        self:CancelCountdown()
        return
    end

    if not duration or duration < 3 or duration > 60 then
        T.msg(L["EARLY_PULL_RANGE_3_60"] or "倒数时间必须在 3–60 秒之间")
        return
    end

    local ok, reason = self:CanStartPull()
    if not ok then
        T.msg(reason)
        return
    end

    if not (C_PartyInfo and C_PartyInfo.DoCountdown) then
        T.msg(L["EARLY_PULL_DOCOUNTDOWN_FAIL"] or "倒数启动失败（可能是权限或污染调用栈）")
        return
    end

    local callOk, success = pcall(C_PartyInfo.DoCountdown, duration)
    if not callOk or success == false then
        T.msg(L["EARLY_PULL_DOCOUNTDOWN_FAIL"] or "倒数启动失败（可能是权限或污染调用栈）")
        Debug("do_countdown_fail callOk=" .. tostring(callOk) .. " success=" .. tostring(success))
        return
    end

    self:ClearExpectedPull()
    self.expectedPullTimeSTT = GetTime() + duration
    self.countdownActive = true
    self:ScheduleCountdownExpiry(duration, "stt")
    if T.InstanceGate and T.InstanceGate.IsRaidActive and T.InstanceGate.IsRaidActive() then
        SendDbmPullTimer(duration)
    else
        Debug("dbm_pt_send_skip non_raid_test")
    end
    T.msg(string.format(L["EARLY_PULL_STARTED"] or "已发起 %d 秒拉怪倒数", duration))
end

function EarlyPull:OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ENCOUNTER_END" then
        if event == "ENCOUNTER_END" then
            Debug("encounter_end")
            -- 脱战可能晚于 ENCOUNTER_END（残血灭团等），尝试发送 self-claim
            if T.EarlyPull.Claim and T.EarlyPull.Claim.SendIfPending then
                T.EarlyPull.Claim.SendIfPending("encounter_end")
            end
        end
        ResetLogs()
        self:ClearExpectedPull()
        self.lastRegenDisabledTime = nil
        self.cachedCombatLogRestricted = false
        if T.EarlyPull.Claim and T.EarlyPull.Claim.ResetSession then
            T.EarlyPull.Claim.ResetSession()
        end
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0, function()
                self:RegisterRestrictedEvents("enter_world")
            end)
        end
        return
    end

    if not IsEarlyPullEnabled() then
        return
    end
    local isRaidActive = T.InstanceGate and T.InstanceGate.IsRaidActive and T.InstanceGate.IsRaidActive()
    if event ~= "CHAT_MSG_ADDON" and IsRaidOnly() and not isRaidActive then
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        local now = GetTime()
        self.lastRegenDisabledTime = now
        local expected = GetExpectedPullTime()
        if expected and T.EarlyPull.Claim and T.EarlyPull.Claim.RecordRegenEarly then
            T.EarlyPull.Claim.RecordRegenEarly(now, expected)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.lastRegenDisabledTime = nil
        if T.EarlyPull.Claim and T.EarlyPull.Claim.SendIfPending then
            T.EarlyPull.Claim.SendIfPending("regen_enabled")
        end
        C_Timer.After(0, function()
            self:RegisterRestrictedEvents("regen_enabled")
        end)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        T.EarlyPull.Scanner.COMBAT_LOG_EVENT_UNFILTERED(self, ...)
    elseif event == "CHAT_MSG_ADDON" then
        if isRaidActive or not IsRaidOnly() then
            T.EarlyPull.Scanner.CHAT_MSG_ADDON(self, ...)
        end
    elseif event == "START_PLAYER_COUNTDOWN" then
        T.EarlyPull.Scanner.START_PLAYER_COUNTDOWN(self, ...)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        T.EarlyPull.Scanner.CANCEL_PLAYER_COUNTDOWN(self, ...)
    elseif event == "ENCOUNTER_START" then
        self:OnEncounterStart(...)
    end
end

function EarlyPull:RegisterEvents()
    if not self.frame then
        return
    end
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.frame:RegisterEvent("CHAT_MSG_ADDON")
    self.frame:RegisterEvent("ENCOUNTER_START")
    self.frame:RegisterEvent("ENCOUNTER_END")
end

function EarlyPull:Initialize()
    if self.initialized then
        self:RegisterEvents()
        return
    end
    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnEvent", function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    self:RegisterEvents()

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, "D5")
    end
    if T.Comm then
        local ok, err = T.Comm:Register("earlyPull", "claim", function(payload, sender, meta)
            if type(payload) ~= "table" or payload.type ~= "claim" or type(payload.message) ~= "string" then
                return
            end
            if T.EarlyPull.Claim and T.EarlyPull.Claim.OnReceive then
                T.EarlyPull.Claim.OnReceive(self.Constants.syncPrefix or "STTEP", payload.message, meta and meta.channel, sender)
            end
        end)
        if not ok then
            Debug("sttep_comm_register_failed err=" .. tostring(err))
        end
    end
    self.initialized = true
end

function EarlyPull:OnRegister()
    T.EarlyPull = self
end

function EarlyPull:OnEnable()
    if IsDebugMode() then
        self:Initialize()
    end
end

function EarlyPull:OnDisable()
    if self.frame then
        self.frame:UnregisterAllEvents()
    end
    self.combatLogEventRegistered = false
    self.countdownEventsRegistered = false
    self:ClearExpectedPull()
    ResetLogs()
end

T.HandleEarlyPullCommand = function(args)
    EarlyPull:HandlePullCommand(args)
end

end)
