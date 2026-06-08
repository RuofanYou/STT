local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local SemanticTimelineGUI = T.SemanticTimelineGUI
if not SemanticTimelineGUI then
    return
end

local function EditorDeps()
    return SemanticTimelineGUI._EditorDeps or {}
end

local function ApplyEditorTextNow(source)
    local deps = EditorDeps()
    if deps.ApplyEditorTextNow then
        return deps.ApplyEditorTextNow(source)
    end
    return false
end

local function RefreshRows(opts)
    local deps = EditorDeps()
    if deps.RefreshRows then
        deps.RefreshRows(opts)
    end
end

local function LogInputConsumeOnce(action)
    local deps = EditorDeps()
    if deps.LogInputConsumeOnce then
        deps.LogInputConsumeOnce(action)
    end
end

local function LogEditorKeyboardGuardOnce(state)
    local deps = EditorDeps()
    if deps.LogEditorKeyboardGuardOnce then
        deps.LogEditorKeyboardGuardOnce(state)
    end
end

T.EditorUndo = {
    entries = {},
    cursor = 0,
    maxDepth = 50,
    editBox = nil,
    panel = nil,
    debounceTimer = nil,
    suppressTextChanged = false,
    applyingSnapshot = false,
}

function T.EditorUndo:GetCursor()
    if not (self.editBox and self.editBox.GetCursorPosition) then
        return 0
    end
    return tonumber(self.editBox:GetCursorPosition()) or 0
end

function T.EditorUndo:SetCursor(cursor)
    if not (self.editBox and self.editBox.SetCursorPosition) then
        return
    end
    local maxCursor = #(self.editBox:GetText() or "")
    self.editBox:SetCursorPosition(math.max(0, math.min(tonumber(cursor) or 0, maxCursor)))
end

function T.EditorUndo:GetScrollOffset()
    return SemanticTimelineGUI.GetEditorScrollOffset()
end

function T.EditorUndo:RestoreScrollOffset(offset)
    SemanticTimelineGUI.RestoreEditorScrollOffset(offset)
end

function T.EditorUndo:CancelDebounce()
    if self.debounceTimer then
        self.debounceTimer:Cancel()
        self.debounceTimer = nil
    end
end

function T.EditorUndo:Clear()
    self:CancelDebounce()
    wipe(self.entries)
    self.cursor = 0
    self.suppressTextChanged = false
    self.applyingSnapshot = false
end

function T.EditorUndo:PushSnapshot(source)
    if not self.editBox or self.applyingSnapshot then
        return false
    end
    local text = self.editBox:GetText() or ""
    local last = self.entries[self.cursor]
    if last and last.text == text then
        last.caretPos = self:GetCursor()
        last.source = source or last.source
        return false
    end

    while #self.entries > self.cursor do
        table.remove(self.entries)
    end

    self.entries[#self.entries + 1] = {
        text = text,
        caretPos = self:GetCursor(),
        ts = time and time() or 0,
        source = source or "edit",
    }

    while #self.entries > self.maxDepth do
        table.remove(self.entries, 1)
    end
    self.cursor = #self.entries
    return true
end

function T.EditorUndo:ScheduleEditSnapshot()
    if self.suppressTextChanged or self.applyingSnapshot then
        return
    end
    self:CancelDebounce()
    self.debounceTimer = C_Timer.NewTimer(0.5, function()
        self.debounceTimer = nil
        self:PushSnapshot("edit")
    end)
end

function T.EditorUndo:ApplyEntry(entry, eventName)
    if not (entry and self.editBox) then
        return false
    end
    self:CancelDebounce()
    local scrollOffset = self:GetScrollOffset()
    self.applyingSnapshot = true
    self.suppressTextChanged = true
    SemanticTimelineGUI.PreserveEditorViewportDuringTextReplace(entry.text or "", entry.caretPos, eventName, {
        offset = scrollOffset,
        revealCursor = true,
    })
    self.suppressTextChanged = false
    self.applyingSnapshot = false
    local refreshed = ApplyEditorTextNow(eventName)
    if not refreshed then
        RefreshRows({
            force = true,
            cause = eventName,
        })
    end
    if SemanticTimelineGUI.SetEditFeedback or SemanticTimelineGUI.SetStatus then
        local actionText = eventName == "STT_EDITOR_REDO" and (L["已重做"] or "已重做") or (L["已撤销"] or "已撤销")
        local sourceText = tostring(entry.source or "")
        if sourceText == "timeline_batch_drag" then
            actionText = actionText .. "：批量移动"
        elseif sourceText == "timeline_paste" then
            actionText = actionText .. "：粘贴"
        elseif sourceText == "timeline_delete" or sourceText == "context_menu_delete" then
            actionText = actionText .. "：删除"
        elseif sourceText == "timeline_cut" then
            actionText = actionText .. "：剪切"
        elseif sourceText == "drag" then
            actionText = actionText .. "：改写时间"
        end
        actionText = actionText .. " · " .. (eventName == "STT_EDITOR_REDO" and "Ctrl/Command+Z 可撤销" or "Ctrl/Command+Shift+Z 可重做")
        if SemanticTimelineGUI.SetEditFeedback then
            SemanticTimelineGUI.SetEditFeedback(actionText, eventName == "STT_EDITOR_REDO" and "redo" or "undo")
        else
            SemanticTimelineGUI.SetStatus(actionText, eventName == "STT_EDITOR_REDO" and "redo" or "undo")
        end
    end
    return true
end

function T.EditorUndo:Undo()
    if self.cursor <= 1 then
        return false
    end
    self.cursor = self.cursor - 1
    return self:ApplyEntry(self.entries[self.cursor], "STT_EDITOR_UNDO")
end

function T.EditorUndo:Redo()
    if self.cursor >= #self.entries then
        return false
    end
    self.cursor = self.cursor + 1
    return self:ApplyEntry(self.entries[self.cursor], "STT_EDITOR_REDO")
end

function T.EditorUndo:SquashFromCursor(startCursor, source)
    local start = tonumber(startCursor)
    if not start or start < 1 or self.cursor <= start + 1 then
        return false
    end
    local final = self.entries[self.cursor]
    if not final then
        return false
    end
    final.source = source or final.source
    while #self.entries > start do
        table.remove(self.entries, start + 1)
    end
    self.entries[start + 1] = final
    self.cursor = start + 1
    return true
end

function T.EditorUndo:ReplaceText(newText, caretPos, source, opts)
    if not self.editBox then
        return false
    end
    opts = type(opts) == "table" and opts or {}
    self:CancelDebounce()
    local scrollOffset = self:GetScrollOffset()
    self.suppressTextChanged = true
    SemanticTimelineGUI.PreserveEditorViewportDuringTextReplace(newText or "", caretPos, source or "editor_replace", {
        offset = scrollOffset,
        revealCursor = true,
    })
    self.suppressTextChanged = false
    if opts.deferApply == true then
        return true
    end
    local refreshed = ApplyEditorTextNow(source or "editor_replace")
    self:PushSnapshot(source or "edit")
    if not refreshed then
        RefreshRows({
            force = true,
            cause = source or "editor_replace",
        })
    end
    return true
end

function T.EditorUndo:Init(editBox, panel, root)
    self.editBox = editBox
    self.panel = panel
    if T.KeyboardCapture then
        T.KeyboardCapture.Bind(root or panel, {
            {
                key = "Z",
                ctrl = true,
                handler = function()
                    self:Undo()
                    LogInputConsumeOnce("undo")
                    return true
                end,
            },
            {
                key = "Z",
                ctrl = true,
                shift = true,
                handler = function()
                    self:Redo()
                    LogInputConsumeOnce("redo")
                    return true
                end,
            },
            {
                key = "Y",
                ctrl = true,
                handler = function()
                    self:Redo()
                    LogInputConsumeOnce("redo")
                    return true
                end,
            },
        })
        T.KeyboardCapture.Bind(root or panel, {
            {
                key = "C",
                ctrl = true,
                handler = function()
                    if T.TimelineEdit and T.TimelineSelectionBox and T.TimelineSelectionBox.Count and T.TimelineSelectionBox.Count() > 0 then
                        T.TimelineEdit.Copy(T.TimelineSelectionBox.GetTargets())
                        LogInputConsumeOnce("timeline_copy")
                        return true
                    end
                    return false
                end,
            },
            {
                key = "X",
                ctrl = true,
                handler = function()
                    if T.TimelineEdit and T.TimelineSelectionBox and T.TimelineSelectionBox.Count and T.TimelineSelectionBox.Count() > 0 then
                        T.TimelineEdit.Cut(T.TimelineSelectionBox.GetTargets())
                        LogInputConsumeOnce("timeline_cut")
                        return true
                    end
                    return false
                end,
            },
            {
                key = "V",
                ctrl = true,
                handler = function()
                    if T.TimelineEdit and T.TimelineClipboard and T.TimelineClipboard.HasContent and T.TimelineClipboard.HasContent() then
                        local ctx = T.SemanticTimelineGUI and T.SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead and T.SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead()
                        if ctx then
                            T.TimelineEdit.Paste(ctx)
                            LogInputConsumeOnce("timeline_paste")
                            return true
                        end
                    end
                    return false
                end,
            },
        })
        T.KeyboardCapture.AttachEditBox(editBox, root or panel)
        LogEditorKeyboardGuardOnce("keyboard_capture")
    end
    self:Clear()
    self:PushSnapshot("init")
end

function T.EditorUndo:ResetForDocument(source)
    self:Clear()
    self:PushSnapshot(source or "init")
end

end)
