-- 鲁拉符文设置同步：团长战斗外切换频道或分配模式后，同步到团员本地设置。
local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("dreadElegy.enabled", function()

local M = {}
T.DreadElegyChannelSync = M

M.PREFIX = "STTRUNE"

local VALID_CHAT_TYPES = {
    raid = true,
    yell = true,
    emote = true,
    say = true,
}

local VALID_ROUTE_MODES = {
    event = true,
    sequential = true,
}

local FALLBACK_CHAT_TYPE_NAMES = {
    raid = "团队",
    yell = "大喊",
    emote = "表情",
    say = "说",
}

local FALLBACK_ROUTE_MODE_NAMES = {
    event = "按团长事件分流 1/4",
    sequential = "按收到顺序 1-5",
}

local function GetDB()
    C.DB.dreadElegy = C.DB.dreadElegy or {}
    return C.DB.dreadElegy
end

function M.IsValidChatType(chatType)
    return VALID_CHAT_TYPES[chatType] == true
end

function M.IsValidRouteMode(routeMode)
    return VALID_ROUTE_MODES[routeMode] == true
end

function M.GetDisplayName(chatType)
    local localeKey = "DREAD_ELEGY_CHANNEL_" .. string.upper(tostring(chatType or ""))
    return (L and L[localeKey]) or FALLBACK_CHAT_TYPE_NAMES[chatType] or tostring(chatType)
end

function M.GetRouteModeDisplayName(routeMode)
    local localeKey = "DREAD_ELEGY_ROUTE_MODE_" .. string.upper(tostring(routeMode or ""))
    return (L and L[localeKey]) or FALLBACK_ROUTE_MODE_NAMES[routeMode] or tostring(routeMode)
end

local function IsPlayerGroupLeader()
    return UnitIsGroupLeader and UnitIsGroupLeader("player") == true
end

local function IsSenderGroupLeader(sender)
    local shortSender = Ambiguate(sender or "", "short")
    if shortSender == "" then return false end

    if IsInRaid() then
        for i = 1, MAX_RAID_MEMBERS do
            local name, rank = GetRaidRosterInfo(i)
            if name and Ambiguate(name, "short") == shortSender then
                return rank == 2
            end
        end
        return false
    end

    if IsInGroup() then
        if UnitIsGroupLeader("player") and Ambiguate(UnitName("player") or "", "short") == shortSender then
            return true
        end
        for i = 1, 4 do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name and Ambiguate(name, "short") == shortSender then
                return UnitIsGroupLeader(unit) == true
            end
        end
    end

    return false
end

function M.Send(chatType, inEncounter, routeMode)
    if not M.IsValidChatType(chatType) then
        T.debug("[DreadElegy] RuneChannelSyncIgnored reason=invalid_type chatType=" .. tostring(chatType))
        return false
    end
    if not M.IsValidRouteMode(routeMode) then
        T.debug("[DreadElegy] RuneChannelSyncIgnored reason=invalid_route routeMode=" .. tostring(routeMode))
        return false
    end
    if InCombatLockdown() or inEncounter or (IsEncounterInProgress and IsEncounterInProgress()) then
        T.debug("[DreadElegy] RuneChannelSyncIgnored reason=combat_or_encounter chatType=" .. tostring(chatType))
        return false
    end
    if not IsInRaid() and not IsInGroup() then
        T.debug("[DreadElegy] RuneChannelSyncIgnored reason=not_in_group chatType=" .. tostring(chatType))
        return false
    end
    if not IsPlayerGroupLeader() then
        T.debug("[DreadElegy] RuneChannelSyncIgnored reason=not_leader chatType=" .. tostring(chatType))
        return false
    end
    if not T.Comm then
        T.debug("[DreadElegy] RuneChannelSyncIgnored reason=comm_missing chatType=" .. tostring(chatType))
        return false
    end

    local channel = IsInRaid() and "RAID" or "PARTY"
    local msg = "S:" .. chatType .. ":" .. routeMode .. ":" .. math.floor(GetTime and GetTime() or 0)
    local ok, err = T.Comm:Send("dreadElegy", "legacy", { type = "legacy", message = msg }, { target = "group", prio = "ALERT" })
    if ok then
        T.debug(string.format(
            "[DreadElegy] RuneChannelSyncSent chatType=%s routeMode=%s channel=%s",
            tostring(chatType),
            tostring(routeMode),
            channel
        ))
        return true
    end

    T.debug(string.format(
        "[DreadElegy] RuneChannelSyncIgnored reason=send_failed chatType=%s routeMode=%s channel=%s ok=%s err=%s",
        tostring(chatType),
        tostring(routeMode),
        channel,
        tostring(ok),
        tostring(err)
    ))
    return false
end

function M.HandleAddonMessage(message, channel, sender)
    local proto, chatType, routeMode = strsplit(":", tostring(message or ""))
    if proto ~= "S" then
        return false
    end

    if not IsSenderGroupLeader(sender) then
        T.debug("[DreadElegy] RuneChannelSyncIgnored reason=sender_not_leader sender=" .. tostring(sender))
        return true
    end
    if not M.IsValidChatType(chatType) then
        T.debug("[DreadElegy] RuneChannelSyncIgnored reason=invalid_type chatType=" .. tostring(chatType))
        return true
    end
    if routeMode ~= nil and not M.IsValidRouteMode(routeMode) then
        routeMode = nil
    end

    local db = GetDB()
    local chatChanged = db.chatType ~= chatType
    local routeChanged = routeMode and db.runeRouteMode ~= routeMode
    if not chatChanged and not routeChanged then
        T.debug(string.format(
            "[DreadElegy] RuneChannelSyncIgnored reason=already_current chatType=%s routeMode=%s",
            tostring(chatType),
            tostring(routeMode)
        ))
        return true
    end

    if chatChanged then
        db.chatType = chatType
    end
    if routeChanged then
        db.runeRouteMode = routeMode
    end
    if chatChanged and T.DreadElegy and T.DreadElegy.RefreshRuneButtons then
        T.DreadElegy:RefreshRuneButtons()
    end
    if routeChanged and T.DreadElegy and T.DreadElegy.ResetChatMirror then
        T.DreadElegy:ResetChatMirror()
    end

    if routeMode then
        T.msg(string.format(
            L["DREAD_ELEGY_CONFIG_SYNC_APPLIED"] or "符文设置已跟随团长：频道 %s，分配 %s",
            M.GetDisplayName(chatType),
            M.GetRouteModeDisplayName(routeMode)
        ))
    else
        T.msg(string.format(L["DREAD_ELEGY_CHANNEL_SYNC_APPLIED"] or "符文频道已跟随团长切换为：%s", M.GetDisplayName(chatType)))
    end
    T.debug(string.format(
        "[DreadElegy] RuneChannelSyncApplied chatType=%s routeMode=%s sender=%s channel=%s",
        tostring(chatType),
        tostring(routeMode),
        tostring(sender),
        tostring(channel)
    ))
    return true
end

end)
