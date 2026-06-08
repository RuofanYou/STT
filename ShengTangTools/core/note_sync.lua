local T, C, L = unpack(select(2, ...))

-- STT 战术方案分发（Addon 通信）
-- 协议说明：
-- T.Comm channel: note
-- Payload: { proto = "N2" | "S2", data = <table> }

local PROTO_NOTE = "N2"
local PROTO_SEMANTIC_BOSS = "S2"
local PROTO_SEMANTIC_BOSS_BOARDS = "S2B"
local BOSS_BOARD_SYNC_TIMEOUT_SECONDS = 60

local NoteSync = {
    semanticBossPending = {},
}

T.NoteSync = NoteSync

local function GetDeps(note)
    return (note and note.SyncDeps) or (T.Note and T.Note.SyncDeps) or {}
end

local function D(note)
    local deps = GetDeps(note)
    if type(deps.GetDB) == "function" then
        return deps.GetDB()
    end
    return T.Profile and T.Profile:GetActiveData() or {}
end

local function NormalizeSemanticBossKeyText(note, text)
    local deps = GetDeps(note)
    if type(deps.NormalizeSemanticBossKeyText) == "function" then
        return deps.NormalizeSemanticBossKeyText(text)
    end
    return T.NormalizeSemanticBossKeyText and T.NormalizeSemanticBossKeyText(text) or nil
end

local function BuildTemplateRejectReason(note, info)
    local deps = GetDeps(note)
    if type(deps.BuildTemplateRejectReason) == "function" then
        return deps.BuildTemplateRejectReason(info)
    end
    if info and info.errors and #info.errors > 0 then
        return string.format("%s %d", L["模板解析错误"] or "模板解析错误", #info.errors)
    end
    return L["仅支持结构化模板"] or "仅支持结构化模板"
end

local function IsPlayableStructuredContent(note, content, expectedBodyKind, opts)
    local deps = GetDeps(note)
    if type(deps.IsPlayableStructuredContent) == "function" then
        return deps.IsPlayableStructuredContent(content, expectedBodyKind, opts)
    end
    local info = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(content or "", opts) or nil
    local ok = T.STNTemplate and T.STNTemplate.IsBodyUsable and T.STNTemplate.IsBodyUsable(info, expectedBodyKind) or false
    return ok == true, info
end

local function GetTeamScope(note)
    local deps = GetDeps(note)
    return deps.PlanScopeTeam or "team"
end

local function CommDebug(fmt, ...)
    if C and C.DB and C.DB.debugMode then
        T.debug("[同步] " .. string.format(fmt, ...))
    end
end

local function GetShortSender(sender)
    local raw = tostring(sender or "")
    if raw == "" then
        return "?"
    end
    if Ambiguate then
        local short = Ambiguate(raw, "short")
        if short and short ~= "" then
            return short
        end
    end
    return raw
end

local function CountBossBoardPackageBoards(package)
    local boards = type(package) == "table" and package.boards or nil
    if type(boards) ~= "table" then
        return 0
    end
    local count = 0
    for _, board in ipairs(boards) do
        if type(board) == "table" then
            count = count + 1
        end
    end
    return count
end

local function HasBossBoardPackage(payload)
    return CountBossBoardPackageBoards(type(payload) == "table" and payload.visualBoardPackage or nil) > 0
end

local function IsLargeBossBoardPackage(payload)
    local package = type(payload) == "table" and payload.visualBoardPackage or nil
    local mode = type(package) == "table" and tostring(package.mode or "") or ""
    return CountBossBoardPackageBoards(package) > 0 and (mode == "delta" or mode == "full")
end

local function IsRaidLeader(sender)
    local shortSender = GetShortSender(sender)
    if shortSender == "?" then
        return false
    end
    if IsInRaid() then
        for i = 1, MAX_RAID_MEMBERS do
            local name, rank = GetRaidRosterInfo(i)
            if name and GetShortSender(name) == shortSender then
                return rank and rank >= 2
            end
        end
        return false
    end
    if IsInGroup() then
        for i = 1, (MAX_PARTY_MEMBERS or 4) do
            local unit = "party" .. i
            if UnitExists(unit) and GetShortSender(UnitName(unit)) == shortSender then
                return UnitIsGroupLeader(unit) == true
            end
        end
    end
    return false
end

local function ShowPlanSyncWarning(message)
    if type(message) ~= "string" or message == "" then
        return
    end
    T.msg(message)
    if T.TacticalNotice and T.TacticalNotice.ShowBanner then
        T.TacticalNotice:ShowBanner({
            text = message,
            duration = 3.5,
            severity = "warning",
            force = true,
            bypassCooldown = true,
        })
    end
end

local planSyncWarnings = {}

local function ShouldShowPlanSyncWarning(key)
    local now = (GetTime and GetTime()) or time()
    key = tostring(key or "unknown")
    if planSyncWarnings[key] and now - planSyncWarnings[key] < 10 then
        return false
    end
    planSyncWarnings[key] = now
    return true
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
    return table.concat(parts, "、")
end

local function BuildShortNameList(list)
    local result = {}
    if type(list) ~= "table" then
        return result
    end
    for _, name in ipairs(list) do
        result[#result + 1] = GetShortSender(name)
    end
    table.sort(result)
    return result
end

local function GetPlanSyncAckReasonText(reason)
    reason = tostring(reason or "")
    if reason == "sender_not_leader" then
        return L["PLAN_SYNC_ACK_REASON_SENDER_NOT_LEADER"] or "对方仅接收团长推送"
    elseif reason == "payload_not_table" then
        return L["PLAN_SYNC_ACK_REASON_PAYLOAD_NOT_TABLE"] or "数据格式异常"
    elseif reason == "empty_content" then
        return L["PLAN_SYNC_ACK_REASON_EMPTY_CONTENT"] or "内容为空"
    elseif reason == "invalid_content" then
        return L["PLAN_SYNC_ACK_REASON_INVALID_CONTENT"] or "方案格式未通过"
    elseif reason == "apply_failed" then
        return L["PLAN_SYNC_ACK_REASON_APPLY_FAILED"] or "应用失败"
    elseif reason == "create_failed" then
        return L["PLAN_SYNC_ACK_REASON_CREATE_FAILED"] or "创建方案失败"
    end
    return reason ~= "" and reason or (L["PLAN_SYNC_ACK_REASON_UNKNOWN"] or "未知原因")
end

local function BuildAckRejectList(records)
    local result = {}
    if type(records) ~= "table" then
        return result
    end
    for _, record in pairs(records) do
        if record and record.status == "reject" then
            result[#result + 1] = string.format(L["PLAN_SYNC_ACK_REASON_FORMAT"] or "%s（%s）", record.name or "?", GetPlanSyncAckReasonText(record.reason))
        end
    end
    table.sort(result)
    return result
end

local function ComputeSyncDigest(content)
    local sem = T.SemanticTimeline
    if sem and sem.ComputeContentDigest then
        return sem.ComputeContentDigest(tostring(content or ""))
    end
    return nil
end

function NoteSync:OnCommDecodeFailed(note, meta)
    if type(meta) ~= "table" or meta.channel ~= "note" then
        return
    end
    local sender = meta.sender or "?"
    if not ShouldShowPlanSyncWarning("decode:" .. tostring(sender)) then
        return
    end
    CommDebug("接收端解码失败：sender=%s err=%s bytes=%s", GetShortSender(sender), tostring(meta.err), tostring(meta.bytes))
end

function NoteSync:InitComm(note)
    if note._commReady then
        return
    end
    if not T.Comm then
        return
    end
    local ok, err = T.Comm:Register("note", "sync", function(payload, sender, meta)
        note:OnCommPayload(payload, meta and meta.channel, sender, meta)
    end)
    if ok then
        ok, err = T.Comm:Register("note", "ack", function(payload, sender)
            CommDebug(
                "CommAck sender=%s replyTo=%s status=%s reason=%s planID=%s version=%s bossKey=%s digest=%s applyResult=%s",
                GetShortSender(sender),
                tostring(payload and payload.replyTo),
                tostring(payload and payload.status),
                tostring(payload and payload.reason),
                tostring(payload and payload.planID),
                tostring(payload and payload.version),
                tostring(payload and payload.bossKey),
                tostring(payload and payload.digest),
                tostring(payload and payload.applyResult)
            )
        end)
    end
    if ok and T.Comm.RegisterDecodeFailureHandler then
        T.Comm:RegisterDecodeFailureHandler("note", function(meta)
            note:OnCommDecodeFailed(meta)
        end)
    end
    if ok then
        note._commReady = true
    else
        CommDebug("通信注册失败：err=%s", tostring(err))
    end
end

function NoteSync:IsCommAllowed()
    local _, instType = IsInInstance()
    if instType == "pvp" or instType == "arena" then
        return false, "PVP环境不允许发送"
    end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return false, "大秘境进行中不允许发送"
    end
    return true
end

function NoteSync:QueuePayloadToSTT(note, proto, payload, summaryLabel, callbacks)
    callbacks = type(callbacks) == "table" and callbacks or {}
    if not T.Comm then
        T.msg("缺少通信库：T.Comm 未加载")
        if type(callbacks.onSendFailed) == "function" then
            pcall(callbacks.onSendFailed, "missing_comm")
        end
        return false
    end

    if not IsInRaid() and not IsInGroup() then
        T.msg(L["你不在团队或小队中"] or "Not in group")
        if type(callbacks.onSendFailed) == "function" then
            pcall(callbacks.onSendFailed, "not_in_group")
        end
        return false
    end

    local ok, why = self:IsCommAllowed()
    if not ok then
        T.msg("发送受限: " .. tostring(why))
        if type(callbacks.onSendFailed) == "function" then
            pcall(callbacks.onSendFailed, why)
        end
        return false
    end

    if proto == PROTO_NOTE or proto == PROTO_SEMANTIC_BOSS or proto == PROTO_SEMANTIC_BOSS_BOARDS then
        if UnitIsGroupLeader and UnitIsGroupLeader("player") ~= true then
            ShowPlanSyncWarning(L["PLAN_SYNC_SEND_NOT_LEADER_WARNING"] or "你还不是团长，可能有部分团员收不到同步")
        end
    end

    local normalizedSummary = tostring(summaryLabel or "同步数据")
    local channel = T.Comm.ResolveGroupScope and T.Comm:ResolveGroupScope() or (IsInRaid() and "RAID" or "PARTY")
    local ackRecords = {}
    local hasBossBoardPackage = (proto == PROTO_SEMANTIC_BOSS or proto == PROTO_SEMANTIC_BOSS_BOARDS) and HasBossBoardPackage(payload)
    local hasLargeBossBoardPackage = (proto == PROTO_SEMANTIC_BOSS or proto == PROTO_SEMANTIC_BOSS_BOARDS) and IsLargeBossBoardPackage(payload)

    local okSend, err = T.Comm:Send("note", "sync", {
        proto = proto,
        data = payload,
        label = normalizedSummary,
    }, {
        deferInCombat = true,
        prio = hasBossBoardPackage and "NORMAL" or nil,
        timeout = hasLargeBossBoardPackage and BOSS_BOARD_SYNC_TIMEOUT_SECONDS or nil,
        maxRetries = hasLargeBossBoardPackage and 0 or nil,
        queueKey = "note:" .. tostring(proto) .. ":" .. normalizedSummary,
        onProgress = function(sent, total, sendResult)
            if type(callbacks.onProgress) == "function" then
                pcall(callbacks.onProgress, sent, total, sendResult)
            end
        end,
        onAck = function(ackPayload, sender, _, terminal)
            if terminal and type(ackPayload) == "table" then
                local name = GetShortSender(sender)
                ackRecords[name] = {
                    name = name,
                    status = tostring(ackPayload.status or ""),
                    reason = ackPayload.reason,
                    planID = ackPayload.planID,
                }
            end
            CommDebug(
                "发送回执：label=%s proto=%s sender=%s status=%s terminal=%s reason=%s planID=%s version=%s bossKey=%s digest=%s applyResult=%s",
                normalizedSummary,
                tostring(proto),
                GetShortSender(sender),
                tostring(ackPayload and ackPayload.status),
                tostring(terminal),
                tostring(ackPayload and ackPayload.reason),
                tostring(ackPayload and ackPayload.planID),
                tostring(ackPayload and ackPayload.version),
                tostring(ackPayload and ackPayload.bossKey),
                tostring(ackPayload and ackPayload.digest),
                tostring(ackPayload and ackPayload.applyResult)
            )
            if type(callbacks.onAck) == "function" then
                pcall(callbacks.onAck, ackPayload, sender, terminal)
            end
        end,
        onComplete = function(entry)
            local rejects = BuildAckRejectList(ackRecords)
            if #rejects <= 0 then
                CommDebug("发送完成：label=%s proto=%s result=all_applied", normalizedSummary, tostring(proto))
                if type(callbacks.onComplete) == "function" then
                    pcall(callbacks.onComplete, entry)
                end
                return
            end
            if ShouldShowPlanSyncWarning("reject:" .. tostring(proto) .. ":" .. normalizedSummary) then
                ShowPlanSyncWarning(string.format(
                    L["PLAN_SYNC_SEND_PARTIAL_REJECT"] or "方案同步完成，但部分团员没有应用：%s",
                    FormatNameList(rejects, 5)
                ))
            end
            CommDebug("发送完成：label=%s proto=%s result=partial_reject rejects=%s", normalizedSummary, tostring(proto), FormatNameList(rejects, 8))
            if type(callbacks.onComplete) == "function" then
                pcall(callbacks.onComplete, entry)
            end
        end,
        onTimeout = function(entry)
            local missing = BuildShortNameList(entry and entry.missingAcks)
            local rejects = BuildAckRejectList(ackRecords)
            CommDebug("发送超时：label=%s proto=%s id=%s missing=%d rejects=%d", normalizedSummary, tostring(proto), tostring(entry and entry.envelope and entry.envelope.id), #missing, #rejects)
            if type(callbacks.onTimeout) == "function" then
                pcall(callbacks.onTimeout, entry)
            end
            if #missing <= 0 and #rejects <= 0 then
                return
            end
            if ShouldShowPlanSyncWarning("timeout:" .. tostring(proto) .. ":" .. normalizedSummary) then
                if #rejects > 0 and #missing > 0 then
                    ShowPlanSyncWarning(string.format(
                        L["PLAN_SYNC_SEND_PARTIAL_REJECT_AND_MISSING_ACK"] or "方案同步部分团员没有应用：%s；另有团员未返回同步确认，可能未收到或未应用：%s",
                        FormatNameList(rejects, 3),
                        FormatNameList(missing, 5)
                    ))
                elseif #rejects > 0 then
                    ShowPlanSyncWarning(string.format(
                        L["PLAN_SYNC_SEND_PARTIAL_REJECT"] or "方案同步完成，但部分团员没有应用：%s",
                        FormatNameList(rejects, 5)
                    ))
                else
                    ShowPlanSyncWarning(string.format(
                        L["PLAN_SYNC_SEND_MISSING_ACK"] or "方案已发送，但部分团员未返回同步确认，可能未收到或未应用：%s",
                        FormatNameList(missing, 5)
                    ))
                end
            end
        end,
    })
    if not okSend then
        T.msg(string.format("发送%s失败：%s", normalizedSummary, tostring(err)))
        CommDebug("发送失败：label=%s proto=%s channel=%s err=%s", normalizedSummary, proto, channel, tostring(err))
        if type(callbacks.onSendFailed) == "function" then
            pcall(callbacks.onSendFailed, err)
        end
        return false
    end
    local queued = type(err) == "string" and err:match("^queued_")
    T.msg(string.format("%s%s", queued and "已排队发送" or "已发送", normalizedSummary))
    return true
end

function NoteSync:SendToSTT(note, id)
    local plan = note:GetNote(id)
    if not plan then return false end

    local valid, info = IsPlayableStructuredContent(note, plan.content or "")
    if not valid then
        T.msg(BuildTemplateRejectReason(note, info))
        return false
    end

    local payload = {
        name = plan.name,
        content = plan.content or "",
        encounterID = tonumber(plan.encounterID) or nil,
        author = plan.author or UnitName("player") or "",
        ver = T.Version,
        ts = time(),
    }
    return self:QueuePayloadToSTT(note, PROTO_NOTE, payload, string.format("STT方案：%s", plan.name))
end

function NoteSync:SendSemanticBossToSTT(note, bossKey, content, callbacks)
    callbacks = type(callbacks) == "table" and callbacks or {}
    local normalizedBossKey = NormalizeSemanticBossKeyText(note, bossKey)
    if not normalizedBossKey then
        if type(callbacks.onSendFailed) == "function" then
            pcall(callbacks.onSendFailed, "invalid_boss_key")
        end
        return false
    end

    if self.semanticBossPending[normalizedBossKey] then
        if type(callbacks.onDuplicate) == "function" then
            pcall(callbacks.onDuplicate, normalizedBossKey)
        end
        CommDebug("跳过重复语义Boss同步：boss=%s reason=in_progress", normalizedBossKey)
        return false, "in_progress"
    end

    local noteID = note:GetSemanticBossPlanID(normalizedBossKey)
    local plan = noteID and note:GetPlan(noteID) or nil
    local normalizedContent = tostring(content or (plan and plan.content) or "")
    local payload = {
        kind = "semantic_boss",
        bossKey = normalizedBossKey,
        name = plan and plan.name or normalizedBossKey,
        content = normalizedContent,
        author = UnitName("player") or "",
        ver = T.Version,
        ts = time(),
    }
    local boardManifestPackage = nil
    if T.VisualBoardData and T.VisualBoardData.BuildBossBoardManifestPackage then
        local boardPackage = T.VisualBoardData:BuildBossBoardManifestPackage(normalizedBossKey)
        if type(boardPackage) == "table" then
            payload.visualBoardPackage = boardPackage
            boardManifestPackage = boardPackage
        end
    end

    local valid, info = IsPlayableStructuredContent(note, payload.content or "")
    if not valid then
        T.msg(BuildTemplateRejectReason(note, info))
        if type(callbacks.onSendFailed) == "function" then
            pcall(callbacks.onSendFailed, "invalid_content")
        end
        return false
    end

    local syncToken = {}
    self.semanticBossPending[normalizedBossKey] = syncToken

    local function clearPending()
        if self.semanticBossPending[normalizedBossKey] == syncToken then
            self.semanticBossPending[normalizedBossKey] = nil
        end
    end

    local requestedKeySet = {}
    local requestedKeys = {}
    local function addRequestedKeys(request)
        if type(request) ~= "table" or type(boardManifestPackage) ~= "table" then
            return
        end
        local requestBossKey = NormalizeSemanticBossKeyText(note, request.bossKey)
        if requestBossKey ~= normalizedBossKey then
            return
        end
        if tostring(request.manifestHash or "") ~= tostring(boardManifestPackage.manifestHash or "") then
            return
        end
        for _, key in ipairs(request.missingKeys or {}) do
            local syncKey = tostring(key or "")
            if syncKey ~= "" and not requestedKeySet[syncKey] then
                requestedKeySet[syncKey] = true
                requestedKeys[#requestedKeys + 1] = syncKey
            end
        end
    end

    local function sendRequestedBoards(entry)
        if #requestedKeys <= 0 then
            clearPending()
            if type(callbacks.onComplete) == "function" then
                pcall(callbacks.onComplete, entry)
            end
            return
        end
        table.sort(requestedKeys)
        local deltaPackage = T.VisualBoardData and T.VisualBoardData.BuildBossBoardDeltaPackage and T.VisualBoardData:BuildBossBoardDeltaPackage(normalizedBossKey, requestedKeys, boardManifestPackage and boardManifestPackage.manifestHash) or nil
        if type(deltaPackage) ~= "table" then
            clearPending()
            if type(callbacks.onComplete) == "function" then
                pcall(callbacks.onComplete, entry)
            end
            return
        end
        local deltaPayload = {
            kind = "semantic_boss_boards",
            bossKey = normalizedBossKey,
            author = UnitName("player") or "",
            ver = T.Version,
            ts = time(),
            visualBoardPackage = deltaPackage,
        }
        self:QueuePayloadToSTT(note, PROTO_SEMANTIC_BOSS_BOARDS, deltaPayload, string.format("语义Boss画板：%s", payload.name), {
            onProgress = callbacks.onProgress,
            onComplete = function(deltaEntry)
                clearPending()
                if type(callbacks.onComplete) == "function" then
                    pcall(callbacks.onComplete, deltaEntry)
                end
            end,
            onTimeout = function(deltaEntry)
                clearPending()
                if type(callbacks.onTimeout) == "function" then
                    pcall(callbacks.onTimeout, deltaEntry)
                end
            end,
            onSendFailed = function(reason)
                clearPending()
                if type(callbacks.onSendFailed) == "function" then
                    pcall(callbacks.onSendFailed, reason)
                end
            end,
        })
    end

    local ok, err = self:QueuePayloadToSTT(note, PROTO_SEMANTIC_BOSS, payload, string.format("语义Boss：%s", payload.name), {
        onProgress = callbacks.onProgress,
        onAck = function(ackPayload)
            if type(ackPayload) == "table" then
                addRequestedKeys(ackPayload.boardDeltaRequest)
            end
        end,
        onComplete = function(entry)
            sendRequestedBoards(entry)
        end,
        onTimeout = function(entry)
            clearPending()
            if type(callbacks.onTimeout) == "function" then
                pcall(callbacks.onTimeout, entry)
            end
        end,
        onSendFailed = function(reason)
            clearPending()
            if type(callbacks.onSendFailed) == "function" then
                pcall(callbacks.onSendFailed, reason)
            end
        end,
    })
    if not ok then
        clearPending()
    end
    return ok, err
end

function NoteSync:ReceiveSemanticBossFromSTT(note, payload, sender)
    if type(payload) ~= "table" then
        return nil
    end

    local bossKey = NormalizeSemanticBossKeyText(note, payload.bossKey)
    if not bossKey then
        if T.LogDebugEvent then
            T.LogDebugEvent("STT_PLAN_SYNC_RECEIVED", {
                bossKey = tostring(payload.bossKey or ""),
                sender = GetShortSender(sender or tostring(payload.author or "")),
                len = #(tostring(payload.content or "")),
                cause = "invalid_boss_key",
                result = "rejected",
            })
        end
        return nil
    end

    local name = tostring(payload.name or bossKey)
    local content = tostring(payload.content or "")
    local senderName = GetShortSender(sender or tostring(payload.author or ""))
    local valid, info = IsPlayableStructuredContent(note, content)
    if not valid then
        if T.LogDebugEvent then
            T.LogDebugEvent("STT_PLAN_SYNC_RECEIVED", {
                bossKey = bossKey,
                sender = senderName,
                len = #content,
                cause = "invalid_content",
                result = "rejected",
            })
        end
        T.msg(string.format("接收失败：%s", BuildTemplateRejectReason(note, info)))
        return nil
    end
    local boardMerge = nil
    local boardManifest = nil
    local boardPackageBoards = CountBossBoardPackageBoards(payload.visualBoardPackage)
    local boardPackageMode = type(payload.visualBoardPackage) == "table" and tostring(payload.visualBoardPackage.mode or "") or ""
    if boardPackageBoards > 0 and boardPackageMode == "manifest" and T.VisualBoardData and T.VisualBoardData.ApplyBossBoardManifest then
        local packageBossKey = NormalizeSemanticBossKeyText(note, payload.visualBoardPackage.bossKeyText)
        if packageBossKey == bossKey then
            boardManifest = T.VisualBoardData:ApplyBossBoardManifest(payload.visualBoardPackage, senderName)
        elseif T.debug then
            T.debug(string.format(
                "[同步] 跳过视觉画板清单：boss=%s packageBoss=%s sender=%s reason=boss_mismatch",
                tostring(bossKey),
                tostring(packageBossKey or payload.visualBoardPackage.bossKeyText),
                senderName
            ))
        end
    elseif boardPackageBoards > 0 and boardPackageMode == "full" and T.VisualBoardData and T.VisualBoardData.ReplaceBossBoards then
        local packageBossKey = NormalizeSemanticBossKeyText(note, payload.visualBoardPackage.bossKeyText)
        if packageBossKey == bossKey then
            boardMerge = T.VisualBoardData:ReplaceBossBoards(payload.visualBoardPackage, senderName)
        elseif T.debug then
            T.debug(string.format(
                "[同步] 跳过视觉画板包：boss=%s packageBoss=%s sender=%s reason=boss_mismatch",
                tostring(bossKey),
                tostring(packageBossKey or payload.visualBoardPackage.bossKeyText),
                senderName
            ))
        end
    end
    if T.LogDebugEvent then
        T.LogDebugEvent("STT_PLAN_SYNC_RECEIVED", {
            bossKey = bossKey,
            sender = senderName,
            len = #content,
            boardPackageBoards = boardPackageBoards,
            boardManifestMissing = boardManifest and boardManifest.missing or 0,
            boardMergeTotal = boardMerge and boardMerge.total or 0,
            cause = "addon_message",
            digest = ComputeSyncDigest(content),
            result = "accepted",
        })
    end

    local planID = note:UpsertBossPlan(bossKey, GetTeamScope(note), content, {
        name = name,
        forceContent = true,
        authorName = senderName ~= "" and senderName or (payload.author or ""),
        timestamp = tonumber(payload.ts) or time(),
        planAuthor = tostring(payload.author or ""),
    })
    if planID then
        note:SetActivePlan(planID, {
            manual = true,
            contextKey = "boss:" .. bossKey,
        })
        local digest = ComputeSyncDigest(content)
        CommDebug(
            "写入语义Boss：boss=%s planID=%s sender=%s len=%d digest=%s result=applied",
            bossKey,
            tostring(planID),
            senderName,
            #content,
            tostring(digest)
        )
        local function finishSemanticBossApply()
            local guiShown = T.GUI and T.GUI:IsShown() or false
            local didSwitchTab = false
            local semantic = T.SemanticTimeline
            if semantic and semantic.SwitchWorkbenchToBossKeyText then
                local ok, err, switchGuiShown, switchDidSwitchTab = semantic:SwitchWorkbenchToBossKeyText(bossKey, "sync_apply", {
                    suppressCurrentBossContext = true,
                })
                if ok then
                    guiShown = switchGuiShown
                    didSwitchTab = switchDidSwitchTab
                else
                    CommDebug(
                        "接收语义Boss后跳转失败：boss=%s planID=%s sender=%s err=%s",
                        bossKey,
                        tostring(planID),
                        senderName,
                        tostring(err)
                    )
                end
            end
            CommDebug(
                "完成语义Boss接收后处理：boss=%s planID=%s sender=%s guiShown=%s didSwitchTab=%s",
                bossKey,
                tostring(planID),
                senderName,
                tostring(guiShown),
                tostring(didSwitchTab)
            )
            if T.LogDebugEvent then
                T.LogDebugEvent("STT_PLAN_SYNC_APPLY", {
                    bossKey = bossKey,
                    planID = planID,
                    sender = senderName,
                    len = #content,
                    cause = didSwitchTab and "sync_switch_tab" or "addon_message",
                    digest = digest,
                    result = "applied",
                })
            end
            if boardMerge and boardMerge.total > 0 then
                ShowPlanSyncWarning(string.format(
                    L["PLAN_SYNC_RECEIVED_SEMANTIC_BOSS_BOARDS"] or "已接收团长同步Boss方案：%s（来自 %s，含视觉画板 导入%d 移除旧%d）",
                    name,
                    senderName ~= "" and senderName or "?",
                    boardMerge.added or 0,
                    boardMerge.removed or 0
                ))
            else
                ShowPlanSyncWarning(string.format(
                    L["PLAN_SYNC_RECEIVED_SEMANTIC_BOSS"] or "已接收团长同步Boss方案：%s（来自 %s）",
                    name,
                    senderName ~= "" and senderName or "?"
                ))
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, finishSemanticBossApply)
        else
            finishSemanticBossApply()
        end
    end
    return planID, boardManifest or boardMerge
end

function NoteSync:ReceiveSemanticBossBoardsFromSTT(note, payload, sender)
    if type(payload) ~= "table" then
        return nil
    end
    local bossKey = NormalizeSemanticBossKeyText(note, payload.bossKey)
    local package = payload.visualBoardPackage
    local packageBossKey = type(package) == "table" and NormalizeSemanticBossKeyText(note, package.bossKeyText) or nil
    if not bossKey or packageBossKey ~= bossKey or not (T.VisualBoardData and T.VisualBoardData.MergeBossBoardDelta) then
        return nil
    end
    local result = T.VisualBoardData:MergeBossBoardDelta(package, GetShortSender(sender or tostring(payload.author or "")))
    if T.LogDebugEvent then
        T.LogDebugEvent("STT_PLAN_SYNC_BOARDS_RECEIVED", {
            bossKey = bossKey,
            boardPackageBoards = CountBossBoardPackageBoards(package),
            boardMergeTotal = result and result.total or 0,
            manifestHash = type(package) == "table" and package.manifestHash or nil,
            sender = GetShortSender(sender or tostring(payload.author or "")),
            cause = "addon_message",
            result = result and result.total and result.total > 0 and "accepted" or "empty",
        })
    end
    return result
end

local function SendNoteAck(sender, meta, status, reason, extra)
    if not (T.Comm and sender and sender ~= "" and meta and meta.id) then
        return
    end
    status = status == "applied" and "applied" or "reject"
    if status == "applied" then
        reason = nil
    elseif not reason or reason == "" then
        reason = "apply_failed"
    end
    local ackPayload = {
        replyTo = meta.id,
        status = status,
        reason = reason,
        version = T.Version,
        applyResult = status == "applied" and "applied" or tostring(reason),
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            ackPayload[k] = v
        end
    end
    T.Comm:Send("note", "ack", ackPayload, {
        target = { type = "player", name = sender },
        prio = "ALERT",
        allowRelay = true,
        preferWhisper = true,
        backupRelay = true,
        ensureID = true,
    })
end

function NoteSync:OnCommPayload(note, payload, channel, sender, meta)
    if type(payload) ~= "table" then
        return
    end
    local myShort = GetShortSender(UnitName("player") or "")
    if GetShortSender(sender or "") == myShort then return end

    local proto = payload.proto
    if proto ~= PROTO_NOTE and proto ~= PROTO_SEMANTIC_BOSS and proto ~= PROTO_SEMANTIC_BOSS_BOARDS then return end

    if C.DB.syncOnlyFromLeader and not IsRaidLeader(sender) then
        ShowPlanSyncWarning(string.format(
            L["PLAN_SYNC_REJECTED_NON_LEADER_RECEIVER"] or "%s 尝试向你同步方案，但是由于你开启了“仅接收团长的方案推送”且 TA 不是团长，接收失败了",
            GetShortSender(sender)
        ))
        CommDebug("忽略非团长同步：proto=%s sender=%s", proto, GetShortSender(sender))
        SendNoteAck(sender, meta, "reject", "sender_not_leader", { proto = proto })
        return
    end

    local obj = payload.data
    if type(obj) ~= "table" then
        T.msg("接收失败：反序列化失败")
        CommDebug("接收失败：proto=%s sender=%s 原因=payload_not_table", proto, GetShortSender(sender))
        SendNoteAck(sender, meta, "reject", "payload_not_table", { proto = proto })
        return
    end

    if proto == PROTO_SEMANTIC_BOSS then
        local planID, boardResult = self:ReceiveSemanticBossFromSTT(note, obj, sender)
        local ackExtra = {
            proto = proto,
            planID = planID,
            bossKey = NormalizeSemanticBossKeyText(note, obj.bossKey) or tostring(obj.bossKey or ""),
            digest = ComputeSyncDigest(obj.content),
        }
        if type(boardResult) == "table" and type(boardResult.missingKeys) == "table" and #boardResult.missingKeys > 0 then
            ackExtra.boardDeltaRequest = {
                bossKey = boardResult.bossKeyText,
                manifestHash = boardResult.manifestHash,
                missingKeys = boardResult.missingKeys,
                removed = boardResult.removed,
            }
        end
        SendNoteAck(sender, meta, planID and "applied" or "reject", planID and nil or "apply_failed", ackExtra)
        collectgarbage("collect")
        return
    end

    if proto == PROTO_SEMANTIC_BOSS_BOARDS then
        local result = self:ReceiveSemanticBossBoardsFromSTT(note, obj, sender)
        local applied = type(result) == "table" and (result.total or 0) > 0
        SendNoteAck(sender, meta, applied and "applied" or "reject", applied and nil or "apply_failed", {
            proto = proto,
            bossKey = NormalizeSemanticBossKeyText(note, obj.bossKey) or tostring(obj.bossKey or ""),
            boardMergeTotal = result and result.total or 0,
        })
        collectgarbage("collect")
        return
    end

    local name = tostring(obj.name or "")
    local content = tostring(obj.content or "")
    if name == "" or content == "" then
        T.msg("接收失败：数据内容为空")
        CommDebug("接收失败：proto=%s sender=%s 原因=内容为空", proto, GetShortSender(sender))
        SendNoteAck(sender, meta, "reject", "empty_content", { proto = proto })
        return
    end

    local shortSender = GetShortSender(sender)
    local valid, info = IsPlayableStructuredContent(note, content)
    if not valid then
        T.msg(string.format("接收失败：%s", BuildTemplateRejectReason(note, info)))
        CommDebug("接收失败：proto=%s sender=%s 原因=%s", proto, shortSender, BuildTemplateRejectReason(note, info))
        SendNoteAck(sender, meta, "reject", "invalid_content", { proto = proto })
        return
    end
    local savedId = note:CreatePlan(name .. " (" .. shortSender .. ")", content, nil, tonumber(obj.encounterID) or nil)
    if savedId then
        local noteDB = D(note)
        local author = tostring(obj.author or "")
        if author == "" then
            author = shortSender
        end
        noteDB.PlanAuthor[savedId] = author
        noteDB.PlanLastUpdateName[savedId] = shortSender
        noteDB.PlanLastUpdateTime[savedId] = tonumber(obj.ts) or time()
        CommDebug(
            "写入普通方案：id=%s name=%s sender=%s author=%s ts=%s len=%d",
            tostring(savedId),
            name,
            shortSender,
            author,
            tostring(noteDB.PlanLastUpdateTime[savedId]),
            #content
        )
        ShowPlanSyncWarning(string.format(
            L["PLAN_SYNC_RECEIVED_NOTE"] or "已接收团长同步方案：%s（来自 %s）",
            name,
            shortSender
        ))
    end
    SendNoteAck(sender, meta, savedId and "applied" or "reject", savedId and nil or "create_failed", { proto = proto, planID = savedId })
    collectgarbage("collect")
end
