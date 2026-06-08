local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local ContextMenu = {}
T.TimelineContextMenu = ContextMenu

local MENU_WIDTH = 328
local MENU_SHORTCUT_WIDTH = 112
local ROW_HEIGHT = 24
local HEADER_HEIGHT = 42
local SEPARATOR_HEIGHT = 8
local MENU_PAD_X = 8
local MENU_PAD_Y = 8
local BUTTON_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local COLORS = {
    bg = { 0.075, 0.075, 0.085, 0.94 },
    border = { 0.38, 0.38, 0.40, 0.58 },
    hover = { 0.72, 0.72, 0.76, 0.13 },
    text = { 0.92, 0.92, 0.93, 1 },
    muted = { 0.56, 0.56, 0.58, 1 },
    dim = { 0.35, 0.35, 0.37, 1 },
    separator = { 1, 1, 1, 0.11 },
    chip = { 1, 1, 1, 0.09 },
}

local menuFrame
local dismissFrame

local function ApplyBackdrop(frame, alpha)
    if frame and frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = BUTTON_TEXTURE,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], alpha or COLORS.bg[4])
        frame:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], COLORS.border[4])
    end
end

local function EnsureDismiss()
    if dismissFrame then
        return
    end
    dismissFrame = CreateFrame("Frame")
    dismissFrame:SetScript("OnEvent", function()
        if menuFrame and menuFrame:IsShown() and not menuFrame:IsMouseOver() then
            ContextMenu.Hide()
        end
    end)
end

local function SetDismissActive(active)
    EnsureDismiss()
    if active then
        dismissFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    else
        dismissFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    end
end

local function EnsureMenu()
    if menuFrame then
        return menuFrame
    end
    local frame = CreateFrame("Frame", "STT_TimelineContextMenu", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(80)
    frame:SetWidth(MENU_WIDTH)
    frame.rows = {}
    frame:SetClampedToScreen(true)
    frame:Hide()
    ApplyBackdrop(frame)
    menuFrame = frame
    EnsureDismiss()
    return frame
end

local function AcquireRow(parent, index)
    local row = parent.rows[index]
    if row then
        row:Show()
        return row
    end
    row = CreateFrame("Button", nil, parent)
    row:SetSize(MENU_WIDTH - (MENU_PAD_X * 2), ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -1)
    row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 1)
    row.bg:SetColorTexture(1, 1, 1, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -(MENU_SHORTCUT_WIDTH + 18), 0)
    row.text:SetJustifyH("LEFT")
    row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rightText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.rightText:SetWidth(MENU_SHORTCUT_WIDTH)
    row.rightText:SetJustifyH("RIGHT")
    row.sep = row:CreateTexture(nil, "ARTWORK")
    row.sep:SetColorTexture(unpack(COLORS.separator))
    row.sep:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.sep:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.sep:SetHeight(1)
    row.sep:Hide()
    row.metaTitle = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.metaTitle:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -3)
    row.metaTitle:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -3)
    row.metaTitle:SetJustifyH("LEFT")
    row.timeA = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.timeA:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 5)
    row.timeB = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.timeB:SetPoint("LEFT", row.timeA, "RIGHT", 16, 0)
    row:SetScript("OnEnter", function(self)
        if self._menuKind == "item" and self._enabled ~= false then
            self.bg:SetColorTexture(unpack(COLORS.hover))
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0)
    end)
    parent.rows[index] = row
    return row
end

local Notify

local function ResetRow(row)
    row._menuKind = nil
    row._enabled = false
    row:SetScript("OnClick", nil)
    row:SetEnabled(false)
    row.bg:SetColorTexture(1, 1, 1, 0)
    row.text:Hide()
    row.rightText:Hide()
    row.sep:Hide()
    row.metaTitle:Hide()
    row.timeA:Hide()
    row.timeB:Hide()
end

local function ConfigureMenuItem(row, text, rightText, enabled, onClick, disabledReason)
    ResetRow(row)
    row._menuKind = "item"
    row._enabled = enabled ~= false
    row:SetHeight(ROW_HEIGHT)
    row.text:Show()
    row.rightText:Show()
    row.text:SetText(text or "")
    row.rightText:SetText(rightText or "")
    local textColor = row._enabled and COLORS.text or COLORS.dim
    local rightColor = row._enabled and COLORS.muted or COLORS.dim
    row.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4])
    row.rightText:SetTextColor(rightColor[1], rightColor[2], rightColor[3], rightColor[4])
    row:SetEnabled(row._enabled or disabledReason ~= nil)
    if row._enabled then
        row:SetScript("OnClick", onClick)
    elseif disabledReason then
        row:SetScript("OnClick", function()
            if T.SemanticTimelineGUI and T.SemanticTimelineGUI.SetEditFeedback then
                T.SemanticTimelineGUI.SetEditFeedback(disabledReason, "timeline_context_disabled")
            else
                Notify(disabledReason)
            end
        end)
    else
        row:SetScript("OnClick", nil)
    end
end

local function ConfigureSeparator(row)
    ResetRow(row)
    row._menuKind = "separator"
    row:SetHeight(SEPARATOR_HEIGHT)
    row.sep:Show()
end

local function ConfigureMetaHeader(row, title, cursorTime, playheadTime)
    ResetRow(row)
    row._menuKind = "meta"
    row:SetHeight(HEADER_HEIGHT)
    row.metaTitle:Show()
    row.timeA:Show()
    row.timeB:Show()
    row.metaTitle:SetText(title or "")
    row.metaTitle:SetTextColor(0.94, 0.94, 0.95, 1)
    row.timeA:SetText("当前位置  " .. tostring(cursorTime or "0:00.0"))
    row.timeB:SetText("播放头  " .. tostring(playheadTime or "0:00.0"))
    row.timeA:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3], COLORS.muted[4])
    row.timeB:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3], COLORS.muted[4])
end

Notify = function(text)
    if T.msg and text and text ~= "" then
        T.msg(text)
    end
end

local function Feedback(text, key)
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.SetEditFeedback then
        T.SemanticTimelineGUI.SetEditFeedback(text, key)
    else
        Notify(text)
    end
end

local function FormatMenuTime(seconds)
    local value = math.max(0, tonumber(seconds) or 0)
    local min = math.floor(value / 60)
    local sec = value - min * 60
    return string.format("%d:%04.1f", min, sec)
end

local function Shortcut(key)
    if IsMacClient and IsMacClient() then
        return "Command+" .. tostring(key or "")
    end
    return "Ctrl+" .. tostring(key or "")
end

local function HasClipboard()
    return T.TimelineClipboard and T.TimelineClipboard.HasContent and T.TimelineClipboard.HasContent()
end

local function HasContextRow(ctx)
    return type(ctx) == "table" and tostring(ctx.rowKey or "") ~= ""
end

local function GetContextTargets(ctx)
    if type(ctx) == "table" and ctx.hitToken == true then
        if T.TimelineSelectionBox
            and T.TimelineSelectionBox.Count
            and T.TimelineSelectionBox.Count() > 0
            and T.TimelineSelectionBox.IsChipSelected
            and T.TimelineSelectionBox.IsChipSelected(ctx.chip)
            and T.TimelineSelectionBox.GetTargets then
            return T.TimelineSelectionBox.GetTargets(ctx)
        end
        return { ctx }
    end
    if T.TimelineSelectionBox and T.TimelineSelectionBox.GetTargets then
        return T.TimelineSelectionBox.GetTargets(ctx)
    end
    return {}
end

local function GetPlayheadContext(ctx)
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead then
        return T.SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead(ctx)
    end
    return nil
end

local function PositionMenu(frame, anchor)
    local scale = UIParent:GetEffectiveScale() or 1
    local x = tonumber(anchor and anchor.x) or 0
    local y = tonumber(anchor and anchor.y) or 0
    local uiWidth = UIParent:GetWidth() or 0
    local uiHeight = UIParent:GetHeight() or 0
    local width = frame:GetWidth() or MENU_WIDTH
    local height = frame:GetHeight() or 1
    local left = (x / scale) + 8
    local top = (y / scale) - 8
    if uiWidth > 0 and left + width > uiWidth - 8 then
        left = math.max(8, uiWidth - width - 8)
    end
    if top - height < 8 then
        top = math.min(uiHeight - 8, height + 8)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function ContextMenu.Hide()
    if menuFrame then
        menuFrame:Hide()
    end
    if dismissFrame then
        SetDismissActive(false)
    end
end

function ContextMenu.Show(anchor, ctx)
    local frame = EnsureMenu()
    local rowIndex = 0
    local y = -MENU_PAD_Y

    for _, row in ipairs(frame.rows) do
        row:Hide()
    end

    local function AcquireMenuRow(height)
        rowIndex = rowIndex + 1
        local row = AcquireRow(frame, rowIndex)
        row:SetSize(MENU_WIDTH - (MENU_PAD_X * 2), height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", MENU_PAD_X, y)
        y = y - height
        return row
    end

    local function AddMetaHeader(title, cursorTime, playheadTime)
        ConfigureMetaHeader(AcquireMenuRow(HEADER_HEIGHT), title, cursorTime, playheadTime)
    end

    local function AddSeparator()
        ConfigureSeparator(AcquireMenuRow(SEPARATOR_HEIGHT))
    end

    local function AddMenuItem(text, rightText, enabled, onClick, disabledReason)
        ConfigureMenuItem(AcquireMenuRow(ROW_HEIGHT), text, rightText, enabled, onClick, disabledReason)
    end

    if type(ctx) == "table" and ctx.kind == "header" then
        AddMetaHeader(ctx.title or "轨道管理", "列头区域", "")
        AddSeparator()
        if ctx.canEditPersonnelRow and ctx.rowName then
            AddMenuItem(L["PERSONNEL_ROW_MENU_EDIT"] or "编辑人员行", tostring(ctx.rowName or ""), true, function()
                ContextMenu.Hide()
                if T.TimelinePersonnelRowEditor and T.TimelinePersonnelRowEditor.Open then
                    T.TimelinePersonnelRowEditor.Open({
                        mode = "edit",
                        rowName = ctx.rowName,
                        specID = ctx.specID,
                        allowCreateFromTarget = ctx.allowCreateFromTarget == true,
                    })
                end
            end)
        end
        AddMenuItem(L["PERSONNEL_ROW_MENU_ADD"] or "新增人员行", "", true, function()
            ContextMenu.Hide()
            if T.TimelinePersonnelRowEditor and T.TimelinePersonnelRowEditor.Open then
                T.TimelinePersonnelRowEditor.Open({
                    mode = "add",
                })
            end
        end)
        frame:SetHeight(math.abs(y) + MENU_PAD_Y)
        PositionMenu(frame, anchor)
        SetDismissActive(true)
        frame:Show()
        return
    end

    local targets = GetContextTargets(ctx)
    local canEditLine = #targets > 0
    local hasContext = HasContextRow(ctx)
    local hasClipboard = HasClipboard()
    local playheadCtx = GetPlayheadContext(ctx)
    local hasPlayheadContext = HasContextRow(playheadCtx)
    local targetForMove = targets[1] and (targets[1].item or targets[1]) or nil
    local whoText = tostring((ctx and (ctx.who or ctx.rowLabel)) or L["TIMELINE_VIEW_UNSPECIFIED"] or "未指定")
    if #targets > 0 then
        whoText = string.format("已选 %d 个技能点 / %s", #targets, whoText)
    end
    local ctxTime = FormatMenuTime(ctx and ctx.time)
    local playheadTime = FormatMenuTime(playheadCtx and playheadCtx.time)
    local pasteDisabledReason = hasContext and "剪贴板为空" or "没有可用对象行，不能粘贴"
    local moveDisabledReason = canEditLine and "没有可用对象行，不能移动" or "没有选中技能点"

    AddMetaHeader(whoText, ctxTime, playheadTime)
    AddSeparator()
    AddMenuItem(L["TIMELINE_EVENT_EDITOR_MENU_EDIT"] or "编辑", "", type(targetForMove) == "table", function()
        ContextMenu.Hide()
        if T.TimelineEventEditor and T.TimelineEventEditor.Open then
            T.TimelineEventEditor.Open(targetForMove)
        end
    end, "没有选中技能点")
    AddMenuItem("在此插入技能", "", hasContext, function()
        ContextMenu.Hide()
        if T.SkillDrawer then
            if T.SkillDrawer.IsOpen and T.SkillDrawer.IsOpen() then
                if T.SkillDrawer.SetContext then
                    T.SkillDrawer.SetContext(ctx)
                end
            else
                T.SkillDrawer.OpenWithContext(ctx)
            end
        end
    end, "没有可用对象行，不能插入")
    AddMenuItem("粘贴到此处", "", hasContext and hasClipboard, function()
        if T.TimelineEdit and T.TimelineEdit.Paste and T.TimelineEdit.Paste(ctx, { anchor = "cursor" }) then
            ContextMenu.Hide()
        end
    end, pasteDisabledReason)
    AddMenuItem("粘贴到播放头", Shortcut("V"), hasPlayheadContext and hasClipboard, function()
        if T.TimelineEdit and T.TimelineEdit.Paste and T.TimelineEdit.Paste(ctx, { anchor = "playhead" }) then
            ContextMenu.Hide()
        end
    end, hasClipboard and "没有可用对象行，不能粘贴" or "剪贴板为空")
    AddSeparator()
    AddMenuItem("移动选中到此处", "", hasContext and canEditLine, function()
        if T.TimelineEdit and T.TimelineEdit.MoveTokens and T.TimelineEdit.MoveTokens(targets, targetForMove, ctx.time, { precision = 1 }) then
            ContextMenu.Hide()
        end
    end, moveDisabledReason)
    AddMenuItem("移动选中到播放头", "", hasPlayheadContext and canEditLine, function()
        if T.TimelineEdit and T.TimelineEdit.MoveTokens and T.TimelineEdit.MoveTokens(targets, targetForMove, playheadCtx.time, { precision = 1 }) then
            ContextMenu.Hide()
        end
    end, canEditLine and "没有可用对象行，不能移动" or "没有选中技能点")
    AddMenuItem("预览此时间点", "Space", type(ctx) == "table", function()
        ContextMenu.Hide()
        if T.TimelineRunner and T.TimelineRunner.Play then
            T.TimelineRunner:Play(ctx.time or 0)
        end
        Feedback(string.format("已从 %s 开始预览", ctxTime), "timeline_preview")
    end, "没有可预览的时间点")
    AddSeparator()
    AddMenuItem("剪切", Shortcut("X"), canEditLine, function()
        if T.TimelineEdit and T.TimelineEdit.Cut and T.TimelineEdit.Cut(targets) then
            ContextMenu.Hide()
        end
    end, "没有选中技能点")
    AddMenuItem("复制", Shortcut("C"), canEditLine, function()
        if T.TimelineEdit and T.TimelineEdit.Copy and T.TimelineEdit.Copy(targets) then
            ContextMenu.Hide()
        end
    end, "没有选中技能点")
    AddMenuItem("删除", "Delete", canEditLine, function()
        if T.TimelineEdit and T.TimelineEdit.DeleteTokens and T.TimelineEdit.DeleteTokens(targets, "context_menu_delete") then
            ContextMenu.Hide()
        end
    end, "没有选中技能点")

    frame:SetHeight(math.abs(y) + MENU_PAD_Y)
    PositionMenu(frame, anchor)
    SetDismissActive(true)
    frame:Show()
end

end)
