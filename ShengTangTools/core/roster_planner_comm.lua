local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("rosterPlanner.enabled", function()

local RP = T.RosterPlanner
if not RP then
    return
end

local function Text(key, fallback)
    return (L and L[key]) or fallback or key
end

local function Debug(fmt, ...)
    if not T.debug then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[RP] " .. tostring(fmt), ...))
    else
        T.debug("[RP] " .. tostring(fmt))
    end
end

local function ReadUnitName(unit)
    local name, realm = UnitName(unit)
    if not name or name == "" then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

function RP:EnsureCommReady()
    if self._commReady then
        return true
    end
    if not T.Comm then
        Debug("CommMissing")
        return false
    end
    local ok, err = T.Comm:Register("roster", "snapshot", function(payload, sender, meta)
        self:HandleCommPayload(payload, meta and meta.channel, sender)
    end)
    if not ok then
        Debug("CommRegisterFailed err=%s", tostring(err))
        return false
    end
    self._commReady = true
    return true
end

function RP:GetWhisperTargets(parsed)
    parsed = parsed or self:GetParsed()
    local targets = {}
    local seen = {}
    local function add(name)
        if not name or name == "" then
            return
        end
        local key = string.lower(name)
        if seen[key] then
            return
        end
        seen[key] = true
        targets[#targets + 1] = name
    end
    for _, boss in ipairs(parsed.bosses or {}) do
        for _, token in ipairs(boss.subsAll or {}) do
            local resolved = self:ResolveCharacter(token, parsed)
            add(resolved.primaryName)
        end
    end
    return targets
end

function RP:Broadcast()
    if self.BlockIfNotDebug and self:BlockIfNotDebug() then
        return false
    end
    local db = self:EnsureDB()
    local mode = db.subPanel and db.subPanel.broadcastChannel or "GUILD_AND_WHISPER"
    if mode == "OFF" then
        T.msg(Text("RP_MSG_BROADCAST_OFF", "替补推送已关闭。"))
        return false
    end
    local parsed = self:RecomputeParsed("broadcast")
    if #(parsed.errors or {}) > 0 then
        T.msg(string.format(Text("RP_MSG_PARSE_ERRORS", "阵容文本还有 %d 个解析错误，先修正后再推送。"), #(parsed.errors or {})))
        return false
    end
    local payload = {
        ver = 1,
        type = "ROSTER_SNAPSHOT",
        senderName = ReadUnitName("player") or UnitName("player"),
        sourceText = db.sourceText or "",
        timestamp = (time and time()) or 0,
    }

    if (mode == "GUILD" or mode == "GUILD_AND_WHISPER") and IsInGuild and IsInGuild() then
        local ok, err = T.Comm:Send("roster", "snapshot", payload, { target = "guild", prio = "BULK" })
        Debug("CommSent channel=GUILD ok=%s err=%s", tostring(ok), tostring(err))
    end
    if mode == "WHISPER" or mode == "GUILD_AND_WHISPER" then
        for _, target in ipairs(self:GetWhisperTargets(parsed)) do
            local ok, err = T.Comm:Send("roster", "snapshot", payload, { target = { type = "player", name = target }, prio = "BULK", allowRelay = true })
            Debug("CommSent channel=WHISPER target=%s ok=%s err=%s", tostring(target), tostring(ok), tostring(err))
        end
    end
    T.msg(Text("RP_MSG_BROADCAST_DONE", "阵容已推送给装有 STT 的替补。"))
    return true
end

function RP:HandleCommPayload(payload, channel, sender)
    if not payload or payload.type ~= "ROSTER_SNAPSHOT" or type(payload.sourceText) ~= "string" then
        Debug("CommPayloadIgnored sender=%s", tostring(sender))
        return
    end
    self.runtime.receivedSnapshot = {
        senderName = payload.senderName or sender,
        sourceText = payload.sourceText,
        timestamp = payload.timestamp,
        parsed = RP.Parse(payload.sourceText),
    }
    Debug("CommSnapshotReceived sender=%s channel=%s bosses=%d errors=%d", tostring(sender), tostring(channel), #(self.runtime.receivedSnapshot.parsed.bosses or {}), #(self.runtime.receivedSnapshot.parsed.errors or {}))
    if #(self.runtime.receivedSnapshot.parsed.errors or {}) == 0 and T.RosterPlannerSubPanel and T.RosterPlannerSubPanel.Show then
        T.RosterPlannerSubPanel:Show()
    end
end

end)
