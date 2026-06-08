local T = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local BatchRewrite = {}
T.TimelineBatchRewrite = BatchRewrite

local function GUI()
    return T.SemanticTimelineGUI
end

local function Move()
    local gui = GUI()
    return gui and gui._segmentMove or nil
end

local function NormalizeTab(tab)
    local gui = GUI()
    if gui and gui.NormalizeEditorTab then
        return gui.NormalizeEditorTab(tab)
    end
    return tab == "personal" and "personal" or "team"
end

local function GetActiveTab()
    local gui = GUI()
    if gui and gui.GetActiveEditorTab then
        return gui.GetActiveEditorTab()
    end
    return "team"
end

local function GetItem(token)
    if type(token) ~= "table" then
        return nil
    end
    return token.item or token
end

local function SourceKey(tab, lineNum, item, token)
    local segment = tonumber(item and item.sourceSegmentIndex)
    if segment then
        return string.format("%s:%s:seg:%s", tostring(tab), tostring(lineNum), tostring(segment))
    end

    local rowKey = tostring(item and item.rowKey or token and token.rowKey or "")
    local spellID = tostring(item and item.spellID or token and token.spellID or "")
    local sourceText = tostring(item and item.sourceSegmentText or "")
    return string.format("%s:%s:auto:%s:%s:%s", tostring(tab), tostring(lineNum), rowKey, spellID, sourceText)
end

local function ResolveAudience(item, opts)
    opts = type(opts) == "table" and opts or {}
    if type(opts.targetAudienceByRowKey) == "table" then
        local rowKey = tostring(item and item.rowKey or "")
        if rowKey ~= "" and opts.targetAudienceByRowKey[rowKey] then
            return opts.targetAudienceByRowKey[rowKey]
        end
    end
    if type(opts.targetAudience) == "table" then
        return opts.targetAudience
    end
    return nil
end

local function FindPrimaryTimeBlock(lines, preferredLine)
    local move = Move()
    if not (move and type(lines) == "table") then
        return nil, nil
    end

    local bestStart, bestEnd, bestDistance
    local index = 1
    local preferred = tonumber(preferredLine) or 1
    while index <= #lines do
        if move.GetLineTime(lines[index]) then
            local blockStart = index
            local blockEnd = index
            while blockEnd < #lines and move.GetLineTime(lines[blockEnd + 1]) do
                blockEnd = blockEnd + 1
            end

            local distance = 0
            if preferred < blockStart then
                distance = blockStart - preferred
            elseif preferred > blockEnd then
                distance = preferred - blockEnd
            end
            if not bestDistance or distance < bestDistance then
                bestStart, bestEnd, bestDistance = blockStart, blockEnd, distance
            end
            index = blockEnd + 1
        else
            index = index + 1
        end
    end
    return bestStart, bestEnd
end

local function BuildOperations(tokens, primaryItem, targetTime, opts)
    local firstItem = GetItem(type(tokens) == "table" and tokens[1] or nil)
    local primaryTime = tonumber(primaryItem and primaryItem.time) or tonumber(firstItem and firstItem.time) or 0
    local delta = (tonumber(targetTime) or primaryTime) - primaryTime
    local groups = {}
    local orderedTabs = {}
    local planned = {}
    local seen = {}

    for index, token in ipairs(type(tokens) == "table" and tokens or {}) do
        local item = GetItem(token)
        local lineNum = tonumber(item and item.lineNum) or tonumber(token and token.sourceLineNum)
        local tab = NormalizeTab(item and item.editorTab or token and token.editorTab or GetActiveTab())
        local oldTime = tonumber(item and item.time) or tonumber(token and token.time) or 0
        local op = {
            index = index,
            token = token,
            item = item,
            lineNum = lineNum,
            sourceSegmentIndex = tonumber(item and item.sourceSegmentIndex),
            tab = tab,
            oldTime = oldTime,
            targetTime = oldTime + delta,
            sourceSeconds = math.max(0, oldTime + delta - (tonumber(item and item.phaseDisplayOffset) or 0)),
            targetAudience = ResolveAudience(item, opts),
            rowKey = tostring(item and item.rowKey or token and token.rowKey or ""),
        }
        planned[#planned + 1] = op

        if item and lineNum and lineNum > 0 then
            local key = SourceKey(tab, lineNum, item, token)
            if not seen[key] then
                seen[key] = op
                if not groups[tab] then
                    groups[tab] = {}
                    orderedTabs[#orderedTabs + 1] = tab
                end
                groups[tab][#groups[tab] + 1] = op
            else
                op.skippedDuplicate = true
                op.duplicateOf = seen[key].index
            end
        else
            op.skippedReason = "missing_line"
        end
    end

    return groups, orderedTabs, planned, delta
end

local function ApplyToCurrentDocument(ops, opts)
    local gui = GUI()
    local move = Move()
    local syntax = T.TimelineSyntax
    if not (gui and move and syntax and syntax.ParseTimelineLine and syntax.FormatTimeLike) then
        return false, "syntax_missing"
    end
    if type(ops) ~= "table" or #ops == 0 then
        return true, nil, {}
    end

    local text = gui.GetEditorText and gui.GetEditorText() or nil
    if text == nil then
        return false, "editor_not_ready"
    end

    local lines = move.SplitLines(text)
    local opsByLine = {}
    local applied = {}
    local movedEntries = {}
    local preferredLine

    for _, op in ipairs(ops) do
        local line = lines[op.lineNum]
        if line then
            local parsed = syntax.ParseTimelineLine(line)
            local moveIndex = 1
            if parsed and type(parsed.segments) == "table" and #parsed.segments > 1 then
                moveIndex = move.FindSegmentIndex(parsed.segments, op.item)
            end
            if moveIndex then
                op.moveIndex = moveIndex
                opsByLine[op.lineNum] = opsByLine[op.lineNum] or {}
                opsByLine[op.lineNum][moveIndex] = op
                if not preferredLine or op.lineNum < preferredLine then
                    preferredLine = op.lineNum
                end
            else
                op.failedReason = "segment_not_found"
            end
        else
            op.failedReason = "missing_line"
        end
    end

    local newLines = {}
    for lineNum, line in ipairs(lines) do
        local lineOps = opsByLine[lineNum]
        if not lineOps then
            newLines[#newLines + 1] = line
        else
            local parsed = syntax.ParseTimelineLine(line)
            local oldPayload = move.Trim((line or ""):match("{time:([^}]+)}"))
            if oldPayload == "" then
                oldPayload = "00:00"
            end

            local sourceSegments = move.SplitSourceSegments(line)
            local segmentCount = parsed and type(parsed.segments) == "table" and #parsed.segments or 0
            if segmentCount <= 1 then
                local op = lineOps[1]
                if op then
                    local content = sourceSegments[1] or move.Trim((line or ""):gsub("{time:[^}]+}", "", 1))
                    if type(op.targetAudience) == "table" then
                        content = move.ReplaceSourceAudience(content, op.targetAudience)
                    end
                    movedEntries[#movedEntries + 1] = {
                        op = op,
                        line = move.BuildLine(syntax.FormatTimeLike(oldPayload, op.sourceSeconds, opts), content),
                        seconds = op.sourceSeconds,
                    }
                end
            else
                local remaining = {}
                for index, segment in ipairs(parsed.segments) do
                    local op = lineOps[index]
                    if op then
                        local content = sourceSegments[index] or move.SerializeSegment(segment)
                        if type(op.targetAudience) == "table" then
                            content = move.ReplaceSourceAudience(content, op.targetAudience)
                        end
                        movedEntries[#movedEntries + 1] = {
                            op = op,
                            line = move.BuildLine(syntax.FormatTimeLike(oldPayload, op.sourceSeconds, opts), content),
                            seconds = op.sourceSeconds,
                        }
                    else
                        remaining[#remaining + 1] = sourceSegments[index] or move.SerializeSegment(segment)
                    end
                end
                if #remaining > 0 then
                    newLines[#newLines + 1] = move.BuildLine(oldPayload, table.concat(remaining)) or line
                end
            end
        end
    end

    if #movedEntries == 0 then
        return false, "no_batch_entries"
    end

    table.sort(movedEntries, function(a, b)
        if a.seconds == b.seconds then
            return (a.op.index or 0) < (b.op.index or 0)
        end
        return (a.seconds or 0) < (b.seconds or 0)
    end)

    local blockStart, blockEnd = FindPrimaryTimeBlock(newLines, preferredLine)
    if not blockStart then
        blockStart = #newLines + 1
        blockEnd = #newLines
    else
        move.SortTimeBlock(newLines, blockStart, blockEnd)
    end

    for _, entry in ipairs(movedEntries) do
        if entry.line then
            local insertedLine = move.InsertLineByTime(newLines, blockStart, blockEnd, entry.line, entry.seconds)
            blockEnd = blockEnd + 1
            entry.op.insertedLine = insertedLine
            applied[#applied + 1] = entry.op
        else
            entry.op.failedReason = "move_line_empty"
        end
    end

    local caretLine = applied[#applied] and applied[#applied].insertedLine or preferredLine or 1
    local caretPos = move.GetLineTimeCaret(newLines, caretLine)
    local replaceOpts = {}
    for key, value in pairs(type(opts) == "table" and opts or {}) do
        replaceOpts[key] = value
    end
    local replaced = gui.ReplaceEditorText and gui.ReplaceEditorText(table.concat(newLines, "\n"), caretPos, "timeline_batch_drag_atomic", replaceOpts)
    if not replaced then
        return false, "replace_failed"
    end
    return true, nil, applied
end

function BatchRewrite.Rewrite(tokens, primaryItem, targetTime, opts)
    local gui = GUI()
    if not gui then
        return false, "missing_editor"
    end

    local groups, orderedTabs, planned, delta = BuildOperations(tokens, primaryItem, targetTime, opts)
    if #orderedTabs == 0 then
        return false, "missing_line", { planned = planned, applied = {}, delta = delta }
    end

    local originalTab = GetActiveTab()
    local originalDocument = gui.GetCurrentEditorDocumentSnapshot and gui.GetCurrentEditorDocumentSnapshot() or nil
    local applied = {}

    for _, tab in ipairs(orderedTabs) do
        if tab ~= GetActiveTab() then
            local switched = gui.SwitchEditorDocument and gui.SwitchEditorDocument(nil, tab, "timeline_batch_drag_atomic")
            if not switched then
                return false, "switch_failed", { planned = planned, applied = applied, delta = delta }
            end
        end

        local ok, reason, tabApplied = ApplyToCurrentDocument(groups[tab], opts)
        if not ok then
            return false, reason, { planned = planned, applied = applied, delta = delta }
        end
        for _, op in ipairs(tabApplied or {}) do
            applied[#applied + 1] = op
        end
    end

    local restoreBossKey = originalDocument and originalDocument.bossKeyText or nil
    local restoreTab = originalDocument and originalDocument.tab or originalTab
    if restoreTab ~= GetActiveTab() and gui.SwitchEditorDocument then
        gui.SwitchEditorDocument(restoreBossKey, restoreTab, "timeline_batch_drag_atomic_restore")
    end

    return true, "batch_source_rewrite", {
        planned = planned,
        applied = applied,
        delta = delta,
    }
end

if T.SemanticTimelineGUI then
    T.SemanticTimelineGUI.RewriteTimelineItemsBatch = function(tokens, primaryItem, targetTime, opts)
        return BatchRewrite.Rewrite(tokens, primaryItem, targetTime, opts)
    end
end

end)
