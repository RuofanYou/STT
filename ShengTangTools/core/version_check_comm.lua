local T, C = unpack(select(2, ...))
T.RegisterColdFile("versionCheck.enabled", function()

local JITTER_MAX = 0.2

local function Debug(fmt, ...)
    if not T.debug then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[VersionCheck] " .. tostring(fmt), ...))
    else
        T.debug("[VersionCheck] " .. tostring(fmt))
    end
end

local function OnQuery(payload, sender)
    if type(payload) ~= "table" then
        return
    end
    local target = T.Comm and T.Comm.ResolvePlayerName and T.Comm:ResolvePlayerName(sender) or sender
    if not target then
        Debug("QueryIgnored sender=%s reason=no_target", tostring(sender))
        return
    end
    local delay = math.random() * JITTER_MAX
    C_Timer.After(delay, function()
        local reply = {
            version = T.Version or "dev",
            scanID = payload.scanID,
            target = target,
        }
        local nickname = C and C.DB and strtrim(C.DB.mynickname or "") or ""
        if nickname ~= "" then
            reply.nickname = nickname
        end
        local ok, err = T.Comm:Send("version", "reply", reply, {
            target = { type = "player", name = target },
            prio = "NORMAL",
            minInterval = 0,
            reliable = false,
            allowRelay = true,
            preferWhisper = true,
            backupRelay = true,
        })
        Debug("QueryReply sender=%s target=%s scanID=%s route=player ok=%s err=%s", tostring(sender), tostring(target), tostring(payload.scanID), tostring(ok), tostring(err))
    end)
end

if T.Comm then
    local ok, err = T.Comm:Register("version", "query", OnQuery)
    if not ok then
        Debug("CommRegisterFailed cmd=query err=%s", tostring(err))
    end
end

end)
