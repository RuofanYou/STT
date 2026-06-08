local T = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local TimelineEdit = {}
T.TimelineEdit = TimelineEdit

local function Notify(text)
    if T.msg and text and text ~= "" then
        T.msg(text)
    end
end

local function Debug(eventName, fields)
    if not T.debug then
        return
    end
    local parts = {}
    for key, value in pairs(type(fields) == "table" and fields or {}) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
    end
    table.sort(parts)
    T.debug(string.format("[%s] %s", tostring(eventName), table.concat(parts, " ")))
end

local function GetPerfMs()
    if debugprofilestop then
        return debugprofilestop()
    end
    if GetTimePreciseSec then
        return GetTimePreciseSec() * 1000
    end
    if GetTime then
        return GetTime() * 1000
    end
    return 0
end

local function ElapsedMs(startedAt)
    return math.floor((GetPerfMs() - (tonumber(startedAt) or 0)) + 0.5)
end

local function NormalizeTokens(tokens)
    if type(tokens) ~= "table" then
        return {}
    end
    if tokens.spellID or tokens.sourceLineNum or tokens.rowID or tokens.item then
        return { tokens }
    end
    local out = {}
    for _, token in ipairs(tokens) do
        if type(token) == "table" then
            out[#out + 1] = token
        end
    end
    return out
end

local function PrepareUndo(source)
    if not (T.EditorUndo and T.EditorUndo.PushSnapshot) then
        return nil
    end
    T.EditorUndo:PushSnapshot(source or "timeline_edit_before")
    return T.EditorUndo.cursor
end

local function SquashUndo(startCursor, source)
    if startCursor and T.EditorUndo and T.EditorUndo.SquashFromCursor then
        T.EditorUndo:SquashFromCursor(startCursor, source or "timeline_edit")
    end
end

local function ResolvePasteContext(ctx, opts)
    local anchor = opts and opts.anchor
    if anchor == "cursor" then
        return ctx
    end
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead then
        return T.SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead(ctx) or ctx
    end
    return ctx
end

local function TokenTime(token)
    return tonumber(token and token.item and token.item.time)
        or tonumber(token and token.time)
        or 0
end

local function TokenLine(token)
    return tonumber(token and token.item and token.item.lineNum)
        or tonumber(token and token.sourceLineNum)
end

local function FormatEditTime(seconds)
    local value = math.max(0, tonumber(seconds) or 0)
    local min = math.floor(value / 60)
    local sec = value - min * 60
    return string.format("%d:%04.1f", min, sec)
end

local function Feedback(text, key)
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.SetEditFeedback then
        T.SemanticTimelineGUI.SetEditFeedback(text, key)
    else
        Notify(text)
    end
end

local function BuildRewriteOptsForToken(baseOpts, token)
    local opts = {}
    for key, value in pairs(type(baseOpts) == "table" and baseOpts or {}) do
        if key ~= "targetAudienceByRowKey" then
            opts[key] = value
        end
    end
    local audienceByRowKey = type(baseOpts) == "table" and baseOpts.targetAudienceByRowKey or nil
    if type(audienceByRowKey) == "table" then
        local item = token and (token.item or token)
        local rowKey = tostring(item and item.rowKey or token and token.rowKey or "")
        opts.targetAudience = audienceByRowKey[rowKey]
    end
    return opts
end

local function GetTokenItem(token)
    return type(token) == "table" and (token.item or token) or nil
end

local function TokenSegmentIndex(token)
    local item = GetTokenItem(token)
    return tonumber(item and item.sourceSegmentIndex)
end

local function TokenRowKey(token)
    local item = GetTokenItem(token)
    return tostring(item and item.rowKey or token and token.rowKey or "")
end

local function TokenTab(token)
    local item = GetTokenItem(token)
    return tostring(item and item.editorTab or token and token.editorTab or "")
end

local function CopyContextToken(token)
    if not (T.SemanticTimelineGUI and T.SemanticTimelineGUI.CopyTimelineLineForContext) then
        return nil, "missing_editor"
    end
    local ok, payload = T.SemanticTimelineGUI.CopyTimelineLineForContext(token)
    if not ok then
        return nil, payload
    end
    payload.time = TokenTime(token)
    payload.who = token.who
    payload.rowKey = token.rowKey
    payload.editorTab = token.editorTab
    payload.class = token.class
    payload.kind = token.kind
    return payload
end

function TimelineEdit.Copy(tokens, opts)
    local targets = NormalizeTokens(tokens)
    local payloads = {}
    for _, token in ipairs(targets) do
        local payload, reason = CopyContextToken(token)
        if payload then
            payloads[#payloads + 1] = payload
        else
            Feedback(string.format("复制失败：%s", tostring(reason or "unknown")), "timeline_copy_failed")
            return false, reason
        end
    end
    if #payloads == 0 then
        return false, "empty_selection"
    end
    if not (T.TimelineClipboard and T.TimelineClipboard.Set) then
        return false, "missing_clipboard"
    end
    T.TimelineClipboard.Set(payloads, opts and opts.cut == true)
    if not (opts and opts.silentFeedback == true) then
        Feedback(string.format("已复制 %d 个技能点", #payloads), "timeline_copy")
    end
    Debug("STT_TIMELINE_EDIT_COPY", { count = #payloads, cut = opts and opts.cut == true })
    return true, #payloads
end

function TimelineEdit.DeleteTokens(tokens, source)
    local targets = NormalizeTokens(tokens)
    if #targets == 0 then
        return false, "empty_selection"
    end
    if not (T.SemanticTimelineGUI and T.SemanticTimelineGUI.DeleteTimelineLineForContext) then
        return false, "missing_editor"
    end

    table.sort(targets, function(a, b)
        local lineA = tonumber(a and a.sourceLineNum) or 0
        local lineB = tonumber(b and b.sourceLineNum) or 0
        if lineA == lineB then
            return TokenTime(a) > TokenTime(b)
        end
        return lineA > lineB
    end)

    local undoStart = PrepareUndo(source or "timeline_delete_before")
    for _, token in ipairs(targets) do
        local ok, reason = T.SemanticTimelineGUI.DeleteTimelineLineForContext(token, source or "timeline_delete")
        if not ok then
            Feedback(string.format("删除失败：%s", tostring(reason or "unknown")), "timeline_delete_failed")
            return false, reason
        end
    end
    SquashUndo(undoStart, source or "timeline_delete")
    if T.TimelineSelectionBox then
        T.TimelineSelectionBox.Clear("delete")
    end
    if source == "timeline_cut" then
        Feedback(string.format("已剪切 %d 个技能点 · Ctrl/Command+Z 可撤销", #targets), "timeline_cut")
    else
        Feedback(string.format("已删除 %d 个技能点 · Ctrl/Command+Z 可撤销", #targets), "timeline_delete")
    end
    Debug("STT_TIMELINE_EDIT_DELETE", { count = #targets })
    return true
end

function TimelineEdit.Cut(tokens)
    local copied, reason = TimelineEdit.Copy(tokens, { cut = true, silentFeedback = true })
    if not copied then
        return false, reason
    end
    return TimelineEdit.DeleteTokens(tokens, "timeline_cut")
end

function TimelineEdit.Paste(ctx, opts)
    if not (T.TimelineClipboard and T.TimelineClipboard.Get) then
        return false, "missing_clipboard"
    end
    local tokens = T.TimelineClipboard.Get()
    if not tokens or #tokens == 0 then
        Feedback("剪贴板为空", "timeline_clipboard_empty")
        return false, "clipboard_empty"
    end
    if not (T.SemanticTimelineGUI and T.SemanticTimelineGUI.PasteTimelineLineForContext) then
        Feedback("粘贴失败：编辑器未就绪", "timeline_paste_failed")
        return false, "missing_editor"
    end

    local pasteCtx = ResolvePasteContext(ctx, opts)
    if type(pasteCtx) ~= "table" then
        Feedback("没有可用对象行，不能粘贴", "timeline_missing_context")
        return false, "missing_context"
    end

    local baseTime
    for _, token in ipairs(tokens) do
        local timeValue = TokenTime(token)
        if not baseTime or timeValue < baseTime then
            baseTime = timeValue
        end
    end
    baseTime = baseTime or 0
    local targetTime = tonumber(pasteCtx.time) or 0
    local undoStart = PrepareUndo("timeline_paste_before")

    for _, token in ipairs(tokens) do
        local relTime = TokenTime(token) - baseTime
        local itemCtx = {}
        for key, value in pairs(pasteCtx) do
            itemCtx[key] = value
        end
        itemCtx.time = math.max(0, targetTime + relTime)
        itemCtx.rawTime = itemCtx.time
        local ok, reason = T.SemanticTimelineGUI.PasteTimelineLineForContext(itemCtx, token)
        if not ok then
            Feedback(string.format("粘贴失败：%s", tostring(reason or "unknown")), "timeline_paste_failed")
            return false, reason
        end
    end

    SquashUndo(undoStart, "timeline_paste")
    Feedback(string.format("已粘贴 %d 个技能点到 %s · Ctrl/Command+Z 可撤销", #tokens, FormatEditTime(targetTime)), "timeline_paste")
    Debug("STT_TIMELINE_EDIT_PASTE", { count = #tokens, time = targetTime })
    return true, #tokens
end

function TimelineEdit.MoveTokens(tokens, primaryItem, targetTime, opts)
    local targets = NormalizeTokens(tokens)
    if #targets == 0 then
        return false, "empty_selection"
    end
    if not (T.SemanticTimelineGUI and T.SemanticTimelineGUI.RewriteTimelineItemsBatch) then
        return false, "missing_editor"
    end

    local primaryTime = tonumber(primaryItem and primaryItem.time) or TokenTime(targets[1])
    local delta = (tonumber(targetTime) or primaryTime or 0) - (primaryTime or 0)
    Debug("STT_TIMELINE_EDIT_BATCH_DRAG_BEGIN", {
        count = #targets,
        primaryLine = tonumber(primaryItem and primaryItem.lineNum),
        primaryTime = primaryTime,
        targetTime = tonumber(targetTime),
        delta = delta,
    })
    table.sort(targets, function(a, b)
        local lineA = tonumber(a and a.sourceLineNum) or tonumber(a and a.item and a.item.lineNum) or 0
        local lineB = tonumber(b and b.sourceLineNum) or tonumber(b and b.item and b.item.lineNum) or 0
        if lineA == lineB then
            return TokenTime(a) > TokenTime(b)
        end
        return lineA > lineB
    end)

    local totalStartedAt = GetPerfMs()
    local rewriteStartedAt = totalStartedAt
    local undoStart = PrepareUndo("timeline_batch_drag_before")
    local rewriteOpts = {}
    for key, value in pairs(type(opts) == "table" and opts or {}) do
        rewriteOpts[key] = value
    end
    rewriteOpts.deferApply = true

    for index, token in ipairs(targets) do
        local oldTime = TokenTime(token)
        local nextTime = math.max(0, oldTime + delta)
        local tokenRewriteOpts = BuildRewriteOptsForToken(rewriteOpts, token)
        Debug("STT_TIMELINE_EDIT_BATCH_TOKEN_PLAN", {
            index = index,
            oldTime = oldTime,
            targetTime = nextTime,
            delta = nextTime - oldTime,
            line = TokenLine(token),
            segment = TokenSegmentIndex(token),
            rowKey = TokenRowKey(token),
            tab = TokenTab(token),
            targetWho = tokenRewriteOpts.targetAudience and tokenRewriteOpts.targetAudience.who or "",
        })
    end

    local ok, reason, batchResult = T.SemanticTimelineGUI.RewriteTimelineItemsBatch(targets, primaryItem, targetTime, rewriteOpts)
    if not ok then
        Debug("STT_TIMELINE_EDIT_BATCH_FLUSH", {
            ok = false,
            count = #targets,
            delta = delta,
            reason = reason,
        })
        Feedback(string.format("批量移动失败：%s", tostring(reason or "unknown")), "timeline_move_failed")
        return false, reason
    end

    local appliedCount = 0
    for _, op in ipairs(type(batchResult) == "table" and batchResult.applied or {}) do
        appliedCount = appliedCount + 1
        Debug("STT_TIMELINE_EDIT_BATCH_TOKEN_DONE", {
            index = op.index,
            oldTime = op.oldTime,
            targetTime = op.targetTime,
            oldLine = op.lineNum,
            insertedLine = op.insertedLine or "",
            rowKey = op.rowKey,
            tab = op.tab,
        })
    end
    for _, op in ipairs(type(batchResult) == "table" and batchResult.planned or {}) do
        if op.skippedDuplicate then
            Debug("STT_TIMELINE_EDIT_BATCH_TOKEN_DEDUP", {
                index = op.index,
                duplicateOf = op.duplicateOf,
                line = op.lineNum,
                segment = op.sourceSegmentIndex or 1,
                rowKey = op.rowKey,
                tab = op.tab,
            })
        elseif op.skippedReason or op.failedReason then
            Debug("STT_TIMELINE_EDIT_BATCH_TOKEN_FAIL", {
                index = op.index,
                reason = op.skippedReason or op.failedReason,
                line = op.lineNum,
                segment = op.sourceSegmentIndex or 1,
                rowKey = op.rowKey,
                tab = op.tab,
            })
        end
    end

    local rewriteMs = ElapsedMs(rewriteStartedAt)
    local flushStartedAt = GetPerfMs()
    local flushOk = T.SemanticTimelineGUI.FlushEditorBatchEdit and T.SemanticTimelineGUI.FlushEditorBatchEdit("timeline_batch_drag")
    Debug("STT_TIMELINE_EDIT_BATCH_FLUSH", {
        ok = flushOk == true,
        count = #targets,
        applied = appliedCount,
        delta = delta,
    })
    if not flushOk then
        return false, "flush_failed"
    end
    local flushMs = ElapsedMs(flushStartedAt)
    if T.EditorUndo and T.EditorUndo.PushSnapshot then
        T.EditorUndo:PushSnapshot("timeline_batch_drag")
    end
    SquashUndo(undoStart, "timeline_batch_drag")
    if T.TimelineSelectionBox then
        T.TimelineSelectionBox.Clear("batch_drag")
    end
    Feedback(string.format("已批量移动 %d 个技能点到 %s · Ctrl/Command+Z 可撤销", #targets, FormatEditTime(targetTime)), "timeline_batch_drag")
    Debug("STT_TIMELINE_EDIT_BATCH_DRAG_PERF", { count = #targets, applied = appliedCount, rewriteMs = rewriteMs, flushMs = flushMs, totalMs = ElapsedMs(totalStartedAt) })
    Debug("STT_TIMELINE_EDIT_BATCH_DRAG", { count = #targets, applied = appliedCount, delta = delta })
    return true, #targets
end

function TimelineEdit.GetSelectionTargets(ctx)
    if T.TimelineSelectionBox and T.TimelineSelectionBox.GetTargets then
        return T.TimelineSelectionBox.GetTargets(ctx)
    end
    if type(ctx) == "table" and ctx.hitToken == true then
        return { ctx }
    end
    return {}
end

end)
