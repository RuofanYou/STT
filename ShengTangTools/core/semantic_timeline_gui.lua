local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local SemanticTimelineGUI = {}
T.SemanticTimelineGUI = SemanticTimelineGUI
SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET = 44
SemanticTimelineGUI.TRANSPORT_DOCK_BOTTOM = 10
SemanticTimelineGUI.TRANSPORT_DOCK_WIDTH = 118
SemanticTimelineGUI.TRANSPORT_DOCK_HEIGHT = 28

local TOP_PANEL_HEIGHT = 68
local CONTENT_TOP_OFFSET = -(TOP_PANEL_HEIGHT + 4)
local TIME_COLUMN_WIDTH = 52
local DIVIDER_WIDTH = 12
local DIVIDER_THROTTLE = 1 / 30
local DIVIDER_RESET_DURATION = 0.25
local DIVIDER_DOUBLE_CLICK_THRESHOLD = 0.3
local DIVIDER_HIT_PADDING = 6
local ROW_SIDE_PADDING = 4
local ROW_TOP_OFFSET = -6
local ROW_BOTTOM_PADDING = 6
local DEFAULT_CELL_WIDTH = 120
local DEFAULT_ROW_HEIGHT = 26
local DEFAULT_ICON_SIZE = 16
local DEFAULT_CELL_GAP = 2
local MIN_CELL_WIDTH = 80
local MAX_CELL_WIDTH = 200
local MIN_ROW_HEIGHT = 20
local MAX_ROW_HEIGHT = 40
local MIN_ICON_SIZE = 12
local MAX_ICON_SIZE = 24
local MIN_CELL_GAP = 0
local MAX_CELL_GAP = 10

local rootFrame
local statusLabel
local errorSummaryLabel
local rowsScroll
local rowFrames = {}
local leftPanelFrame
local verticalViewFrame
local rightPanelFrame
local hScrollBar
local horizontalScrollModel
local horizontalTimeline
local hScrollDeferredTimer
local hScrollReadySeen = false

local viewModeSelector
local instanceTypeSelector
local instanceSelector
local bossSelector

local reloadTemplateBtn
local syncBtn
local teamTabBtn
local personalTabBtn
local editorTabGroup
local resolveSourceSelector
local activeEditorTab = "team"
local currentResolveSource = "team_plus_personal"

local editorBox
local editorScrollView
local rawModeBtn
local formModeBtn
local editorMode = "raw"
local rawEditorContainer
local formContainer
local formSpellNameText
local formHintText
local formPayloadEditorBox
local formSpellLabel
local formPayloadLabel
local isFormHydrating = false
local formSaveTimer

local currentRows = {}
local currentErrors = {}
local currentDisplayRows = {}
local cellRenderer = nil -- 延迟初始化，等 T.CreateCellRenderer 加载
local globalHorizontalOffset = 0
local globalMaxContentWidth = 0
local selectedRowID
local currentPlanFormat = "timeline"
local currentTemplateInfo = nil
local viewportStateByBossTab = {}
local currentEditorDocument = nil
local isEditorDocumentHydrated = false
local flushSkipLogSeen = {}
local dividerState = {
    ratio = 0.5,
    dragActive = false,
    dragElapsed = 0,
    dragMoved = false,
    dragStartCursorX = 0,
    lastClickAt = 0,
    animTicker = nil,
}
local dividerLayoutMode = "split"
local currentLeftMode = "horizontal"
local inputConsumeLogSeen = {}
SemanticTimelineGUI._lastRefreshCompileMs = 0
SemanticTimelineGUI._lastRefreshHtgMs = 0

function SemanticTimelineGUI.GetPerfMs()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end
    return nil
end

function SemanticTimelineGUI.ElapsedMs(startedAt)
    if not startedAt then
        return nil
    end
    local now = SemanticTimelineGUI.GetPerfMs()
    if not now then
        return nil
    end
    return math.floor((now - startedAt) + 0.5)
end

local statusToken = 0
SemanticTimelineGUI.statusToast = {
    key = nil,
    keyExpire = 0,
    keyCount = 1,
    keyBaseText = nil,
    fadeTicker = nil,
    mergeWindow = 2.0,
    fadeInTime = 0.20,
    holdTime = 1.80,
    fadeOutTime = 0.25,
    fadeSteps = 10,
}
local saveTimer
local editorHighlightToken = 0
local isEditorHydrating = false
local RefreshRows
local RefreshTriggerForm
local ResetLoadedState
local ApplyFormRuleNow
local ApplyEditorTextNow
local ScheduleFormSave
local ScheduleEditorSave
local SetEditorMode
local SwitchEditorTab
local SwitchEditorDocument
local SelectRow
local GetActiveEditorTab
local SetActiveEditorTab
local HandleReloadTemplate
local HandleSyncMembers
local RefreshActionButtonState
local CreateRows
local LogPlanEvent
local HideSelectorMenu = T.HideSelectorMenu

function SemanticTimelineGUI.HideTransientMenus()
    HideSelectorMenu()
    if T.TimelineContextMenu and T.TimelineContextMenu.Hide then
        T.TimelineContextMenu.Hide()
    end
end

local function ST()
    return T.SemanticTimeline
end

local function LogInputConsumeOnce(action)
    local key = tostring(action or "")
    if key == "" or inputConsumeLogSeen[key] then
        return
    end
    inputConsumeLogSeen[key] = true
    if LogPlanEvent then
        LogPlanEvent("STT_PLAN_INPUT_CONSUME", {
            action = key,
        })
    end
end

local function LogEditorKeyboardGuardOnce(state)
    local key = "keyboard_guard_" .. tostring(state or "")
    if inputConsumeLogSeen[key] then
        return
    end
    inputConsumeLogSeen[key] = true
end

function SemanticTimelineGUI.GetEditorScrollOffset()
    if editorScrollView and editorScrollView.GetOffset then
        return tonumber(editorScrollView:GetOffset()) or 0
    end
    if editorScrollView and editorScrollView.GetVerticalScroll then
        return tonumber(editorScrollView:GetVerticalScroll()) or 0
    end
    return 0
end

function SemanticTimelineGUI.RestoreEditorScrollOffset(offset)
    if not editorScrollView then
        return
    end
    local target = math.max(0, tonumber(offset) or 0)
    if editorScrollView.SnapTo then
        editorScrollView:SnapTo(target)
    elseif editorScrollView.SetVerticalScroll then
        editorScrollView:SetVerticalScroll(target)
    end
end

function SemanticTimelineGUI.SetEditorCursor(cursor)
    if not (editorBox and editorBox.SetCursorPosition) then
        return
    end
    local maxCursor = #(editorBox:GetText() or "")
    editorBox:SetCursorPosition(math.max(0, math.min(tonumber(cursor) or 0, maxCursor)))
end

function SemanticTimelineGUI.PreserveEditorViewportDuringTextReplace(text, cursor, cause, opts)
    if not editorBox then
        return false
    end

    opts = type(opts) == "table" and opts or {}
    local scrollView = editorScrollView
    local targetOffset = tonumber(opts.offset)
    if targetOffset == nil then
        targetOffset = SemanticTimelineGUI.GetEditorScrollOffset()
    end
    local targetCursor = tonumber(cursor)
    if targetCursor == nil then
        targetCursor = editorBox.GetCursorPosition and (tonumber(editorBox:GetCursorPosition()) or 0) or 0
    end
    local revealCursor = opts.revealCursor == true

    if scrollView and scrollView.SetCursorAutoScrollSuppressed then
        scrollView:SetCursorAutoScrollSuppressed(true)
    end
    editorBox:SetText(text or "")
    if not revealCursor then
        SemanticTimelineGUI.SetEditorCursor(targetCursor)
        SemanticTimelineGUI.RestoreEditorScrollOffset(targetOffset)
    end
    if scrollView and scrollView.SetCursorAutoScrollSuppressed then
        scrollView:SetCursorAutoScrollSuppressed(false)
    end

    if revealCursor then
        SemanticTimelineGUI.SetEditorCursor(targetCursor)
    elseif C_Timer and C_Timer.After then
        local expectedScrollView = scrollView
        C_Timer.After(0, function()
            if editorScrollView ~= expectedScrollView then
                return
            end
            SemanticTimelineGUI.RestoreEditorScrollOffset(targetOffset)
        end)
    end

    if LogPlanEvent then
        LogPlanEvent("STT_EDITOR_VIEWPORT_PRESERVE", {
            cause = cause,
            offset = math.floor((tonumber(targetOffset) or 0) + 0.5),
            cursor = math.floor((tonumber(targetCursor) or 0) + 0.5),
            mode = revealCursor and "reveal_cursor" or "preserve_offset",
        })
    end
    return true
end

local function GetTimelineUILayout()
    local semantic = C and C.DB and C.DB.semanticTimeline
    return semantic and semantic.ui or nil
end

function SemanticTimelineGUI.EnsureTimelineUIPreferences()
    local db = C and C.DB and C.DB.semanticTimeline
    if not db then
        return nil
    end

    db.ui = type(db.ui) == "table" and db.ui or {}
    local ui = db.ui
    if ui.viewMode ~= "vertical" and ui.viewMode ~= "horizontal" then
        ui.viewMode = "horizontal"
    end
    ui.perViewMode = type(ui.perViewMode) == "table" and ui.perViewMode or {}
    ui.perViewMode.vertical = type(ui.perViewMode.vertical) == "table" and ui.perViewMode.vertical or {}
    ui.perViewMode.horizontal = type(ui.perViewMode.horizontal) == "table" and ui.perViewMode.horizontal or {}

    local vertical = ui.perViewMode.vertical
    if type(vertical.dividerRatio) ~= "number" then
        vertical.dividerRatio = type(ui.dividerRatio) == "number" and ui.dividerRatio or 0.5
    end
    if type(vertical.cellWidth) ~= "number" then vertical.cellWidth = type(ui.cellWidth) == "number" and ui.cellWidth or DEFAULT_CELL_WIDTH end
    if type(vertical.rowHeight) ~= "number" then vertical.rowHeight = type(ui.rowHeight) == "number" and ui.rowHeight or DEFAULT_ROW_HEIGHT end
    if type(vertical.iconSize) ~= "number" then vertical.iconSize = type(ui.iconSize) == "number" and ui.iconSize or DEFAULT_ICON_SIZE end
    if type(vertical.cellGap) ~= "number" then vertical.cellGap = type(ui.cellGap) == "number" and ui.cellGap or DEFAULT_CELL_GAP end
    if type(vertical.scrollY) ~= "number" then vertical.scrollY = 0 end

    local horizontal = ui.perViewMode.horizontal
    if type(horizontal.dividerRatio) ~= "number" then horizontal.dividerRatio = 0.8 end
    if type(horizontal.pxPerSecond) ~= "number" then horizontal.pxPerSecond = 50 end
    if type(horizontal.scrollX) ~= "number" then horizontal.scrollX = 0 end
    if type(horizontal.scrollY) ~= "number" then horizontal.scrollY = 0 end
    if type(horizontal.firstColMinW) ~= "number" then horizontal.firstColMinW = 80 end
    if type(horizontal.firstColMaxW) ~= "number" then horizontal.firstColMaxW = 200 end
    if type(horizontal.rowHeight) ~= "number" then horizontal.rowHeight = 28 end
    if type(horizontal.iconSize) ~= "number" then horizontal.iconSize = 24 end
    if type(ui.playerCacheById) ~= "table" then ui.playerCacheById = {} end
    if type(ui.bossPortraitCache) ~= "table" then ui.bossPortraitCache = {} end
    if type(ui.bossIconCache) ~= "table" then ui.bossIconCache = {} end
    if type(ui.bossJournalEncounterCache) ~= "table" then ui.bossJournalEncounterCache = {} end
    return ui
end

function SemanticTimelineGUI.NormalizeLeftMode(mode)
    return mode == "vertical" and "vertical" or "horizontal"
end

function SemanticTimelineGUI.GetActiveLeftMode()
    local ui = SemanticTimelineGUI.EnsureTimelineUIPreferences()
    return SemanticTimelineGUI.NormalizeLeftMode(ui and ui.viewMode or currentLeftMode)
end

function SemanticTimelineGUI.GetViewModePrefs(mode)
    local ui = SemanticTimelineGUI.EnsureTimelineUIPreferences()
    if not ui then
        return nil
    end
    return ui.perViewMode[SemanticTimelineGUI.NormalizeLeftMode(mode or ui.viewMode)]
end

function SemanticTimelineGUI.GetActiveDividerRatio()
    local prefs = SemanticTimelineGUI.GetViewModePrefs(SemanticTimelineGUI.GetActiveLeftMode())
    local ratio = tonumber(prefs and prefs.dividerRatio) or 0.5
    if ratio < 0 then
        return 0
    end
    if ratio > 1 then
        return 1
    end
    return ratio
end

local function ClampDividerRatio(ratio)
    local numeric = tonumber(ratio)
    if not numeric or numeric ~= numeric then
        return 0.5
    end
    if numeric < 0 then
        return 0
    end
    if numeric > 1 then
        return 1
    end
    return numeric
end

local function GetCursorPositionScaled()
    local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
    local cursorX, cursorY = GetCursorPosition()
    return cursorX / scale, cursorY / scale
end

local RefreshDividerVisualState
do
    local STATES = {
        idle  = { lineW = 1, color = { 0.55, 0.55, 0.55, 0.35 } },
        hover = { lineW = 2, color = { 0.95, 0.85, 0.55, 0.90 } },
        drag  = { lineW = 2, color = { 1.00, 0.92, 0.60, 1.00 } },
    }
    RefreshDividerVisualState = function()
        local visuals = rootFrame and rootFrame.dividerVisuals
        if not visuals or not visuals.centerLine then
            return
        end
        local dividerFrame = rootFrame.dividerFrame
        local stateName
        if dividerState.dragActive then
            stateName = "drag"
        elseif dividerFrame and dividerFrame:IsMouseOver() then
            stateName = "hover"
        else
            stateName = "idle"
        end
        local palette = STATES[stateName]
        local c = palette.color
        visuals.centerLine:SetWidth(palette.lineW)
        visuals.centerLine:SetColorTexture(c[1], c[2], c[3], c[4])
    end
end

local function SaveDividerRatio(ratio, cause)
    local ui = GetTimelineUILayout()
    if not ui then
        return
    end
    local normalizedRatio = ClampDividerRatio(ratio)
    local mode = SemanticTimelineGUI.GetActiveLeftMode()
    local prefs = SemanticTimelineGUI.GetViewModePrefs(mode)
    if prefs then
        prefs.dividerRatio = normalizedRatio
    end
    if mode == "vertical" then
        ui.dividerRatio = normalizedRatio
    end
    T.debug("[SemanticTimelineGUI] DividerRatioSaved cause=%s ratio=%.3f",
        tostring(cause or "unknown"), normalizedRatio)
end

function SemanticTimelineGUI.ApplySelectorWidth(button, width)
    if not button then
        return
    end
    if button.SetSelectorWidth then
        button:SetSelectorWidth(width)
    else
        button:SetWidth(width)
    end
end

function SemanticTimelineGUI.ResolveTopRowWidths(columns, availableWidth)
    local widths = {}
    local minTotal = 0
    local weightTotal = 0
    for index, column in ipairs(columns or {}) do
        local minWidth = tonumber(column.minWidth) or tonumber(column.width) or 80
        widths[index] = minWidth
        minTotal = minTotal + minWidth
        if minWidth < (tonumber(column.maxWidth) or minWidth) then
            weightTotal = weightTotal + (tonumber(column.weight) or 1)
        end
    end

    if minTotal <= 0 or availableWidth <= minTotal then
        if minTotal > availableWidth and availableWidth > 0 then
            local scale = availableWidth / minTotal
            for index, width in ipairs(widths) do
                widths[index] = math.max(64, math.floor(width * scale))
            end
        end
        return widths
    end

    local extra = availableWidth - minTotal
    while extra > 0 and weightTotal > 0 do
        local used = 0
        local nextWeightTotal = 0
        for index, column in ipairs(columns) do
            local maxWidth = tonumber(column.maxWidth) or widths[index]
            if widths[index] < maxWidth then
                local weight = tonumber(column.weight) or 1
                local add = math.min(maxWidth - widths[index], math.floor(extra * weight / weightTotal))
                if add <= 0 then
                    add = 1
                end
                widths[index] = widths[index] + add
                used = used + add
            end
        end
        if used <= 0 then
            break
        end
        extra = extra - used
        for index, column in ipairs(columns) do
            local maxWidth = tonumber(column.maxWidth) or widths[index]
            if widths[index] < maxWidth then
                nextWeightTotal = nextWeightTotal + (tonumber(column.weight) or 1)
            end
        end
        weightTotal = nextWeightTotal
    end

    return widths
end

function SemanticTimelineGUI.LayoutTopButtonColumns(topPanel, columns, anchorY)
    if not topPanel or not columns or #columns == 0 then
        return nil
    end

    local panelWidth = tonumber(topPanel:GetWidth()) or 0
    if panelWidth <= 0 then
        return nil
    end

    local leftPad, rightPad = 12, 12
    local gaps = math.max(0, #columns - 1)
    local gap = gaps > 0 and 10 or 0
    local availableWidth = math.max(0, panelWidth - leftPad - rightPad - gap * gaps)
    local widths = SemanticTimelineGUI.ResolveTopRowWidths(columns, availableWidth)

    for index, column in ipairs(columns) do
        SemanticTimelineGUI.ApplySelectorWidth(column.button, widths[index])
        column.button:ClearAllPoints()
        if index == 1 then
            column.button:SetPoint("TOPLEFT", topPanel, "TOPLEFT", leftPad, anchorY)
        else
            column.button:SetPoint("LEFT", columns[index - 1].button, "RIGHT", gap, 0)
        end
    end
    return widths
end

function SemanticTimelineGUI.LayoutFirstTopRow(topPanel)
    local columns = topPanel and topPanel.firstRowColumns or nil
    if not topPanel or not columns or #columns == 0 then
        return nil
    end

    local panelWidth = tonumber(topPanel:GetWidth()) or 0
    if panelWidth <= 0 then
        return nil
    end

    local gap = topPanel.topRowGap or 10
    local leftPad = topPanel.topLeftPad or 12
    local rightPad = topPanel.topRightPad or 12
    local buttonWidth = topPanel.topActionButtonWidth or 100
    local anchorY = topPanel.firstRowAnchorY or -12
    local availableWidth = math.max(0, panelWidth - leftPad - rightPad - buttonWidth - (gap * #columns))
    local widths = SemanticTimelineGUI.ResolveTopRowWidths(columns, availableWidth)

    for index, column in ipairs(columns) do
        SemanticTimelineGUI.ApplySelectorWidth(column.button, widths[index])
        column.button:ClearAllPoints()
        if index == 1 then
            column.button:SetPoint("TOPLEFT", topPanel, "TOPLEFT", leftPad, anchorY)
        else
            column.button:SetPoint("LEFT", columns[index - 1].button, "RIGHT", gap, 0)
        end
    end

    reloadTemplateBtn:SetWidth(buttonWidth)
    reloadTemplateBtn:ClearAllPoints()
    reloadTemplateBtn:SetPoint("TOPRIGHT", topPanel, "TOPRIGHT", -rightPad, anchorY)
    return widths
end

function SemanticTimelineGUI.LayoutSecondTopRow(topPanel, firstRowWidths)
    if not topPanel or not firstRowWidths then
        return
    end

    local panelWidth = tonumber(topPanel:GetWidth()) or 0
    if panelWidth <= 0 then
        return
    end

    local gap = topPanel.topRowGap or 10
    local leftPad = topPanel.topLeftPad or 12
    local rightPad = topPanel.topRightPad or 12
    local buttonWidth = topPanel.topActionButtonWidth or 100
    local anchorY = topPanel.secondRowAnchorY or -44
    local viewWidth = firstRowWidths[1] or 104
    local resolveWidth = firstRowWidths[2] or 170
    local profileWidth = firstRowWidths[3] or 220
    local rightEdge = panelWidth - rightPad
    local rightButtonsWidth = (buttonWidth * 2) + gap
    local leftAreaWidth = math.max(0, rightEdge - leftPad - rightButtonsWidth - gap)
    local maxProfileWidth = leftAreaWidth - viewWidth - resolveWidth - (gap * 2)
    if maxProfileWidth < profileWidth then
        profileWidth = math.max(64, maxProfileWidth)
    end

    SemanticTimelineGUI.ApplySelectorWidth(viewModeSelector, viewWidth)
    SemanticTimelineGUI.ApplySelectorWidth(resolveSourceSelector, resolveWidth)
    SemanticTimelineGUI.ApplySelectorWidth(topPanel.profileSelector, profileWidth)
    syncBtn:SetWidth(buttonWidth)
    SemanticTimelineGUI.syncRaidBtn:SetWidth(buttonWidth)

    viewModeSelector:ClearAllPoints()
    viewModeSelector:SetPoint("TOPLEFT", topPanel, "TOPLEFT", leftPad, anchorY)

    resolveSourceSelector:ClearAllPoints()
    resolveSourceSelector:SetPoint("LEFT", viewModeSelector, "RIGHT", gap, 0)

    if topPanel.profileSelector then
        topPanel.profileSelector:ClearAllPoints()
        topPanel.profileSelector:SetPoint("LEFT", resolveSourceSelector, "RIGHT", gap, 0)
    end

    SemanticTimelineGUI.syncRaidBtn:ClearAllPoints()
    SemanticTimelineGUI.syncRaidBtn:SetPoint("TOPRIGHT", topPanel, "TOPRIGHT", -rightPad, anchorY)

    syncBtn:ClearAllPoints()
    syncBtn:SetPoint("RIGHT", SemanticTimelineGUI.syncRaidBtn, "LEFT", -gap, 0)
end

local function RelayoutTopButtons()
    local topPanel = instanceTypeSelector and instanceTypeSelector:GetParent()
    local firstRowColumns = topPanel and topPanel.firstRowColumns or nil
    if not firstRowColumns then
        return
    end

    local firstRowWidths = SemanticTimelineGUI.LayoutFirstTopRow(topPanel)
    SemanticTimelineGUI.LayoutSecondTopRow(topPanel, firstRowWidths)
end

local function ApplyDividerRatio(ratio)
    if not (rootFrame and leftPanelFrame and rightPanelFrame) then
        return
    end

    local dividerFrame = rootFrame.dividerFrame
    if not dividerFrame then
        return
    end

    local totalWidth = math.max(0, (tonumber(rootFrame:GetWidth()) or 0) - 24 - DIVIDER_WIDTH)
    local normalizedRatio = ClampDividerRatio(ratio)
    local threshold = 0
    local layoutMode = "split"
    if totalWidth > 0 then
        threshold = math.min(0.08, math.max(0.02, 24 / totalWidth))
    end

    if normalizedRatio <= threshold then
        normalizedRatio = 0
        layoutMode = "left_collapsed"
    elseif normalizedRatio >= (1 - threshold) then
        normalizedRatio = 1
        layoutMode = "right_collapsed"
    end

    dividerState.ratio = normalizedRatio
    dividerLayoutMode = layoutMode

    if layoutMode == "left_collapsed" then
        leftPanelFrame:Hide()
        leftPanelFrame:ClearAllPoints()
        leftPanelFrame:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 12, CONTENT_TOP_OFFSET)
        leftPanelFrame:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", 12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)
        leftPanelFrame:SetWidth(0)

        dividerFrame:ClearAllPoints()
        dividerFrame:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 12, CONTENT_TOP_OFFSET)
        dividerFrame:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", 12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)

        rightPanelFrame:Show()
        rightPanelFrame:ClearAllPoints()
        rightPanelFrame:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 12, CONTENT_TOP_OFFSET)
        rightPanelFrame:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", -12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)
        dividerFrame:SetHitRectInsets(0, -18, 0, 0)
        return
    end

    if layoutMode == "right_collapsed" then
        rightPanelFrame:Hide()
        rightPanelFrame:ClearAllPoints()
        rightPanelFrame:SetPoint("TOPLEFT", dividerFrame, "TOPRIGHT", 0, 0)
        rightPanelFrame:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", -12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)

        leftPanelFrame:Show()
        leftPanelFrame:ClearAllPoints()
        leftPanelFrame:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 12, CONTENT_TOP_OFFSET)
        leftPanelFrame:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", 12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)
        leftPanelFrame:SetPoint("TOPRIGHT", rootFrame, "TOPRIGHT", -12, CONTENT_TOP_OFFSET)
        leftPanelFrame:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", -12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)

        dividerFrame:ClearAllPoints()
        dividerFrame:SetPoint("TOPRIGHT", rootFrame, "TOPRIGHT", -12, CONTENT_TOP_OFFSET)
        dividerFrame:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", -12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)
        dividerFrame:SetHitRectInsets(-18, 0, 0, 0)
        return
    end

    leftPanelFrame:Show()
    leftPanelFrame:ClearAllPoints()
    leftPanelFrame:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 12, CONTENT_TOP_OFFSET)
    leftPanelFrame:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", 12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)
    leftPanelFrame:SetWidth(totalWidth * normalizedRatio)

    dividerFrame:ClearAllPoints()
    dividerFrame:SetPoint("TOPLEFT", leftPanelFrame, "TOPRIGHT", 0, 0)
    dividerFrame:SetPoint("BOTTOMLEFT", leftPanelFrame, "BOTTOMRIGHT", 0, 0)

    rightPanelFrame:Show()
    rightPanelFrame:ClearAllPoints()
    rightPanelFrame:SetPoint("TOPLEFT", dividerFrame, "TOPRIGHT", 0, 0)
    rightPanelFrame:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", -12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)
    dividerFrame:SetHitRectInsets(-DIVIDER_HIT_PADDING, -DIVIDER_HIT_PADDING, 0, 0)
end

local function CancelDividerAnimation()
    if dividerState.animTicker then
        dividerState.animTicker:Cancel()
        dividerState.animTicker = nil
    end
end

local function AnimateDividerRatio(fromRatio, toRatio, duration)
    CancelDividerAnimation()

    local elapsed = 0
    dividerState.animTicker = C_Timer.NewTicker(0.016, function()
        if not rootFrame then
            CancelDividerAnimation()
            return
        end

        elapsed = elapsed + 0.016
        local progress = math.min(elapsed / duration, 1)
        local eased = progress * progress * (3 - 2 * progress)
        local ratio = fromRatio + (toRatio - fromRatio) * eased
        ApplyDividerRatio(ratio)

        if progress >= 1 then
            CancelDividerAnimation()
            SaveDividerRatio(toRatio, "divider_reset")
            RefreshRows({
                force = true,
                cause = "divider_reset",
            })
        end
    end)
end

local function StopDividerDrag(cause, forceRefresh)
    if not dividerState.dragActive then
        return false
    end

    dividerState.dragActive = false
    dividerState.dragElapsed = 0
    dividerState.dragMoved = false
    SaveDividerRatio(dividerState.ratio, cause or "divider_drag")
    RefreshDividerVisualState()

    local dividerFrame = rootFrame and rootFrame.dividerFrame
    if SetCursor and dividerFrame and not dividerFrame:IsMouseOver() then
        SetCursor(nil)
    end

    if forceRefresh then
        RefreshRows({
            force = true,
            cause = cause or "divider_drag",
        })
    end
    return true
end

function SemanticTimelineGUI._CreateSemanticRootFrame(parent)
    rootFrame = CreateFrame("Frame", nil, parent)
    rootFrame:SetAllPoints(parent)
    rootFrame:EnableMouse(true)
    if T.MarkPingBlocker then
        T.MarkPingBlocker(rootFrame)
    end
    rootFrame:HookScript("OnShow", function()
        wipe(inputConsumeLogSeen)
    end)
    rootFrame:HookScript("OnHide", SemanticTimelineGUI.HideTransientMenus)
    rootFrame:HookScript("OnSizeChanged", function()
        ApplyDividerRatio(dividerState.ratio)
        RelayoutTopButtons()
    end)
end

function SemanticTimelineGUI._CreateTopPanel()
    local topPanel = CreateFrame("Frame", nil, rootFrame, "BackdropTemplate")
    topPanel:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 0, 0)
    topPanel:SetPoint("TOPRIGHT", rootFrame, "TOPRIGHT", 0, 0)
    topPanel:SetHeight(TOP_PANEL_HEIGHT)
    topPanel:EnableMouse(true)
    topPanel:SetFrameStrata(rootFrame:GetFrameStrata())
    topPanel:SetFrameLevel(rootFrame:GetFrameLevel() + 20)

    if T.FrameSkin then
        topPanel._frameSkinAlpha = 0.35
        T.FrameSkin:Register(topPanel, "panel")
        T.FrameSkin:Apply(topPanel, "panel")
    else
        T.ApplyBackdrop(topPanel, { alpha = 0.35 })
    end

    local firstRowY = -8
    local secondRowY = -38
    topPanel.topRowGap = 10
    topPanel.topLeftPad = 12
    topPanel.topRightPad = 12
    topPanel.firstRowAnchorY = firstRowY
    topPanel.secondRowAnchorY = secondRowY
    topPanel.topActionButtonWidth = 100

    local topSelectorLabelWidthCol1 = 36
    local topSelectorLabelWidthCol2 = 72
    local topSelectorLabelWidthCol3 = 42

    instanceTypeSelector = T.CreateSelectorButton(topPanel, {
        width = 114,
        height = 26,
        labelWidth = topSelectorLabelWidthCol1,
        ownerFrame = rootFrame,
    })
    instanceTypeSelector:SetFrameLevel(topPanel:GetFrameLevel() + 5)

    instanceSelector = T.CreateSelectorButton(topPanel, {
        width = 260,
        height = 26,
        labelWidth = topSelectorLabelWidthCol2,
        ownerFrame = rootFrame,
    })
    instanceSelector:SetFrameLevel(topPanel:GetFrameLevel() + 5)

    bossSelector = T.CreateSelectorButton(topPanel, {
        width = 280,
        height = 26,
        labelWidth = topSelectorLabelWidthCol3,
        ownerFrame = rootFrame,
    })
    bossSelector:SetFrameLevel(topPanel:GetFrameLevel() + 5)

    if T.CreateProfileSelector then
        topPanel.profileSelector = T.CreateProfileSelector(topPanel, rootFrame)
        topPanel.profileSelector:SetFrameLevel(topPanel:GetFrameLevel() + 5)
    end

    viewModeSelector = T.CreateSelectorButton(topPanel, {
        width = 112,
        height = 26,
        labelWidth = topSelectorLabelWidthCol1,
        ownerFrame = rootFrame,
    })
    viewModeSelector:SetFrameLevel(topPanel:GetFrameLevel() + 5)

    resolveSourceSelector = T.CreateSelectorButton(topPanel, {
        width = 240,
        height = 26,
        labelWidth = topSelectorLabelWidthCol2,
        ownerFrame = rootFrame,
    })
    resolveSourceSelector:SetFrameLevel(topPanel:GetFrameLevel() + 5)

    reloadTemplateBtn = T.CreateButton(topPanel, { width = 100, height = 26 })
    reloadTemplateBtn:SetScript("OnClick", function()
        HideSelectorMenu()
        HandleReloadTemplate()
    end)

    syncBtn = T.CreateButton(topPanel, { width = 100, height = 26 })
    syncBtn:SetScript("OnClick", function()
        HideSelectorMenu()
        HandleSyncMembers()
    end)
    if T.SemanticTimelineSyncButton then
        T.SemanticTimelineSyncButton:Bind(syncBtn, {
            refresh = function()
                RefreshActionButtonState()
            end,
            setTooltip = SetTooltipHandler,
            getDefaultText = function()
                return L["同步方案"] or "同步方案"
            end,
            getPersonalTooltip = function()
                return L["个人方案不支持同步"] or "个人方案不支持同步"
            end,
            getBusyTooltip = function()
                return "当前方案正在同步"
            end,
        })
    end

    SemanticTimelineGUI.syncRaidBtn = T.CreateButton(topPanel, { width = 100, height = 26 })
    SemanticTimelineGUI.syncRaidBtn:SetScript("OnClick", function()
        HideSelectorMenu()
        SemanticTimelineGUI.HandleSyncRaidMembers()
    end)

    local firstRowColumns = {
        { button = instanceTypeSelector, minWidth = 104, maxWidth = 126, weight = 0.5 },
        { button = instanceSelector, minWidth = 170, maxWidth = 230, weight = 0.8 },
        { button = bossSelector, minWidth = 220, maxWidth = 330, weight = 1.2 },
    }
    topPanel.firstRowColumns = firstRowColumns
    topPanel:HookScript("OnSizeChanged", RelayoutTopButtons)
    topPanel:SetScript("OnMouseDown", HideSelectorMenu)
end

function SemanticTimelineGUI._CreateTransportDock()
    local dock = CreateFrame("Frame", nil, rootFrame)
    dock:SetSize(SemanticTimelineGUI.TRANSPORT_DOCK_WIDTH, SemanticTimelineGUI.TRANSPORT_DOCK_HEIGHT)
    dock:SetPoint("BOTTOM", rootFrame, "BOTTOM", 0, SemanticTimelineGUI.TRANSPORT_DOCK_BOTTOM)
    dock:SetFrameStrata(rootFrame:GetFrameStrata())
    dock:SetFrameLevel(rootFrame:GetFrameLevel() + 18)
    dock:EnableMouse(false)
    dock:Hide()
    SemanticTimelineGUI.transportDock = dock
    return dock
end

function SemanticTimelineGUI._CreateTimelinePanel()
    local leftPanel = CreateFrame("Frame", nil, rootFrame, "BackdropTemplate")
    leftPanel:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 12, CONTENT_TOP_OFFSET)
    leftPanel:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", 12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)
    leftPanel:SetWidth(0)
    leftPanel:SetFrameStrata(rootFrame:GetFrameStrata())
    leftPanel:SetFrameLevel(rootFrame:GetFrameLevel() + 5)
    leftPanelFrame = leftPanel
    leftPanel:HookScript("OnSizeChanged", function()
        RefreshRows({
            cause = "left_panel_resize",
        })
    end)

    if T.FrameSkin then
        leftPanel._frameSkinAlpha = 0.25
        T.FrameSkin:Register(leftPanel, "panel")
        T.FrameSkin:Apply(leftPanel, "panel")
    else
        T.ApplyBackdrop(leftPanel, { alpha = 0.25 })
    end

    verticalViewFrame = CreateFrame("Frame", nil, leftPanel)
    verticalViewFrame:SetAllPoints(leftPanel)
    CreateRows(verticalViewFrame, 6, ROW_TOP_OFFSET)

    if T.HorizontalTimelineGUI and T.HorizontalTimelineGUI.Create then
        horizontalTimeline = T.HorizontalTimelineGUI.Create(leftPanel, {
            transportParent = SemanticTimelineGUI.transportDock,
            focusItem = function(item)
                SemanticTimelineGUI.FocusTimelineItem(item)
            end,
            focusLine = function(lineNumber)
                SemanticTimelineGUI.FocusEditorLine(lineNumber)
            end,
            onContextMenu = function(_, ctx)
                SemanticTimelineGUI.HandleHorizontalContextMenu(ctx)
            end,
        })
        if horizontalTimeline and horizontalTimeline.root then
            horizontalTimeline.root:Hide()
        end
    end
    return leftPanel
end

function SemanticTimelineGUI._CreateDividerFrame(leftPanel)
    local dividerFrame = CreateFrame("Frame", nil, rootFrame)
    dividerFrame:SetWidth(DIVIDER_WIDTH)
    dividerFrame:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
    dividerFrame:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 0, 0)
    dividerFrame:EnableMouse(true)
    dividerFrame:SetHitRectInsets(-DIVIDER_HIT_PADDING, -DIVIDER_HIT_PADDING, 0, 0)
    dividerFrame:SetFrameStrata(rootFrame:GetFrameStrata())
    dividerFrame:SetFrameLevel(rootFrame:GetFrameLevel() + 15)
    rootFrame.dividerFrame = dividerFrame

    local centerLine = dividerFrame:CreateTexture(nil, "ARTWORK")
    centerLine:SetSize(1, 1)
    centerLine:SetPoint("TOP", dividerFrame, "TOP", 0, 0)
    centerLine:SetPoint("BOTTOM", dividerFrame, "BOTTOM", 0, 0)

    rootFrame.dividerVisuals = { centerLine = centerLine }
    RefreshDividerVisualState()

    local function ShowResizeCursor()
        if SetCursor then
            SetCursor("Interface/CURSOR/UI-Cursor-Move.blp")
        end
    end
    local function ClearResizeCursor()
        if SetCursor then
            SetCursor(nil)
        end
    end

    dividerFrame:SetScript("OnEnter", function()
        if T.IsGUIInteractionLocked and T.IsGUIInteractionLocked() then
            return
        end
        ShowResizeCursor()
        RefreshDividerVisualState()
    end)
    dividerFrame:SetScript("OnLeave", function()
        if not dividerState.dragActive then
            ClearResizeCursor()
        end
        RefreshDividerVisualState()
    end)
    dividerFrame:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        if T.IsGUIInteractionLocked and T.IsGUIInteractionLocked() then
            return
        end
        CancelDividerAnimation()
        dividerState.dragActive = true
        dividerState.dragElapsed = DIVIDER_THROTTLE
        dividerState.dragMoved = false
        dividerState.dragStartCursorX = GetCursorPositionScaled()
        RefreshDividerVisualState()
    end)
    dividerFrame:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then
            return
        end

        if dividerState.dragActive and dividerState.dragMoved and StopDividerDrag("divider_drag", true) then
            return
        end

        dividerState.dragActive = false
        dividerState.dragElapsed = 0
        dividerState.dragMoved = false

        local now = GetTime()
        if now - dividerState.lastClickAt <= DIVIDER_DOUBLE_CLICK_THRESHOLD then
            dividerState.lastClickAt = 0
            AnimateDividerRatio(dividerState.ratio, 0.5, DIVIDER_RESET_DURATION)
        else
            dividerState.lastClickAt = now
        end

        RefreshDividerVisualState()
    end)
    dividerFrame:SetScript("OnUpdate", function(_, elapsed)
        if not dividerState.dragActive or not rootFrame then
            return
        end

        dividerState.dragElapsed = dividerState.dragElapsed + (elapsed or 0)
        if dividerState.dragElapsed < DIVIDER_THROTTLE then
            return
        end
        dividerState.dragElapsed = 0

        if not IsMouseButtonDown("LeftButton") then
            if dividerState.dragMoved then
                StopDividerDrag("divider_release", true)
            else
                dividerState.dragActive = false
                dividerState.dragElapsed = 0
                dividerState.dragMoved = false
            end
            return
        end

        local cursorX = GetCursorPositionScaled()
        if math.abs(cursorX - dividerState.dragStartCursorX) >= 2 then
            dividerState.dragMoved = true
        end
        local rootLeft = rootFrame:GetLeft() or 0
        local totalWidth = math.max(1, (tonumber(rootFrame:GetWidth()) or 0) - 24 - DIVIDER_WIDTH)
        local ratio = (cursorX - rootLeft - 12 - DIVIDER_WIDTH * 0.5) / totalWidth
        ApplyDividerRatio(ratio)
    end)

    return dividerFrame
end

function SemanticTimelineGUI._CreateRightPanel(dividerFrame)
    local rightPanel = CreateFrame("Frame", nil, rootFrame)
    rightPanel:SetPoint("TOPLEFT", dividerFrame, "TOPRIGHT", 0, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", -12, SemanticTimelineGUI.CONTENT_BOTTOM_OFFSET)
    rightPanel:SetFrameStrata(rootFrame:GetFrameStrata())
    rightPanel:SetFrameLevel(rootFrame:GetFrameLevel() + 5)
    rightPanel:SetClipsChildren(true)

    rightPanelFrame = rightPanel
    return rightPanel
end

function SemanticTimelineGUI._CreateEditorWorkspace(rightPanel)
    local savedTab = C and C.DB and C.DB.semanticTimeline and C.DB.semanticTimeline.ui and C.DB.semanticTimeline.ui.activeEditorTab or "team"
    SetActiveEditorTab(savedTab, true)

    editorTabGroup = T.CreateTabGroup(rightPanel, {
        point = {"TOPLEFT", rightPanel, "TOPLEFT", 10, 0},
        spacing = 6,
        defaultTab = GetActiveEditorTab(),
        tabs = {
            { key = "team", text = L["团队方案"] or "团队方案", width = 84, height = 22 },
            { key = "personal", text = L["个人方案"] or "个人方案", width = 84, height = 22 },
        },
        onChange = function(tab)
            HideSelectorMenu()
            SwitchEditorTab(tab)
        end,
    })
    teamTabBtn = editorTabGroup.buttonByKey.team
    personalTabBtn = editorTabGroup.buttonByKey.personal

    rawModeBtn = T.CreateButton(rightPanel, { width = 88, height = 22 })
    rawModeBtn:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -10, -32)
    rawModeBtn:SetScript("OnClick", function()
        SetEditorMode("raw")
    end)

    formModeBtn = T.CreateButton(rightPanel, { width = 88, height = 22 })
    formModeBtn:SetPoint("RIGHT", rawModeBtn, "LEFT", -6, 0)
    formModeBtn:SetScript("OnClick", function()
        SetEditorMode("form")
    end)

    SemanticTimelineGUI.errorSummaryFrame = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
    SemanticTimelineGUI.errorSummaryFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -34)
    SemanticTimelineGUI.errorSummaryFrame:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -8, -34)
    SemanticTimelineGUI.errorSummaryFrame:SetHeight(46)
    SemanticTimelineGUI.errorSummaryFrame:SetClipsChildren(true)
    SemanticTimelineGUI.errorSummaryFrame:Hide()
    T.ApplyBackdrop(SemanticTimelineGUI.errorSummaryFrame, { alpha = 0.28 })

    errorSummaryLabel = SemanticTimelineGUI.errorSummaryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    errorSummaryLabel:SetPoint("TOPLEFT", SemanticTimelineGUI.errorSummaryFrame, "TOPLEFT", 8, -6)
    errorSummaryLabel:SetPoint("BOTTOMRIGHT", SemanticTimelineGUI.errorSummaryFrame, "BOTTOMRIGHT", -8, 6)
    errorSummaryLabel:SetJustifyH("LEFT")
    errorSummaryLabel:SetJustifyV("TOP")
    errorSummaryLabel:SetWordWrap(true)
    errorSummaryLabel:SetTextColor(1, 0.35, 0.35, 1)

    rawEditorContainer = CreateFrame("Frame", nil, rightPanel)
    rawEditorContainer:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -34)
    rawEditorContainer:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -8, 0)
    T.ApplyBackdrop(rawEditorContainer, { alpha = 0.15 })

    local editor = T.NoteEditor and T.NoteEditor.CreateSimpleEditor and T.NoteEditor:CreateSimpleEditor(rawEditorContainer)
    if editor then
        editor:SetPoint("TOPLEFT", rawEditorContainer, "TOPLEFT", 4, -4)
        editor:SetPoint("BOTTOMRIGHT", rawEditorContainer, "BOTTOMRIGHT", -4, 4)
        editorBox = editor.editBox
        editorScrollView = editor.scrollView
    end

    formContainer = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
    formContainer:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -34)
    formContainer:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -8, 0)
    if T.FrameSkin then
        formContainer._frameSkinAlpha = 0.15
        T.FrameSkin:Register(formContainer, "subPanel")
        T.FrameSkin:Apply(formContainer, "subPanel")
    else
        T.ApplyBackdrop(formContainer, { alpha = 0.15 })
    end

    formSpellLabel = formContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    formSpellLabel:SetPoint("TOPLEFT", formContainer, "TOPLEFT", 10, -10)
    formSpellLabel:SetWidth(72)
    formSpellLabel:SetJustifyH("LEFT")

    formSpellNameText = formContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formSpellNameText:SetPoint("LEFT", formSpellLabel, "RIGHT", 8, 0)
    formSpellNameText:SetPoint("RIGHT", formContainer, "RIGHT", -10, 0)
    formSpellNameText:SetJustifyH("LEFT")

    formPayloadLabel = formContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    formPayloadLabel:SetPoint("TOPLEFT", formContainer, "TOPLEFT", 10, -40)
    formPayloadLabel:SetWidth(88)
    formPayloadLabel:SetJustifyH("LEFT")

    local payloadContainer = CreateFrame("Frame", nil, formContainer)
    payloadContainer:SetPoint("TOPLEFT", formContainer, "TOPLEFT", 10, -60)
    payloadContainer:SetPoint("BOTTOMRIGHT", formContainer, "BOTTOMRIGHT", -10, 30)
    T.ApplyBackdrop(payloadContainer, { alpha = 0.12 })

    local payloadEditor = T.NoteEditor and T.NoteEditor.CreateSimpleEditor and T.NoteEditor:CreateSimpleEditor(payloadContainer)
    if payloadEditor then
        payloadEditor:SetPoint("TOPLEFT", payloadContainer, "TOPLEFT", 4, -4)
        payloadEditor:SetPoint("BOTTOMRIGHT", payloadContainer, "BOTTOMRIGHT", -4, 4)
        formPayloadEditorBox = payloadEditor.editBox
    end

    formHintText = formContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    formHintText:SetPoint("BOTTOMLEFT", formContainer, "BOTTOMLEFT", 10, 8)
    formHintText:SetPoint("BOTTOMRIGHT", formContainer, "BOTTOMRIGHT", -10, 8)
    formHintText:SetJustifyH("LEFT")
    formHintText:SetTextColor(0.85, 0.82, 0.62, 1)

end

function SemanticTimelineGUI._BindEditorHandlers()
    if editorBox then
        editorBox:SetScript("OnTextChanged", function(_, userInput)
            if not userInput or isEditorHydrating then
                return
            end
            ScheduleEditorSave()
            if T.EditorUndo then
                T.EditorUndo:ScheduleEditSnapshot()
            end
        end)

        editorBox:SetScript("OnEditFocusLost", function()
            if saveTimer then
                saveTimer:Cancel()
                saveTimer = nil
            end
            ApplyEditorTextNow()
            if T.EditorUndo then
                T.EditorUndo:PushSnapshot("edit")
            end
        end)
    end

    if formPayloadEditorBox then
        formPayloadEditorBox:SetScript("OnTextChanged", function(_, userInput)
            if not userInput or isFormHydrating then
                return
            end
            ScheduleFormSave()
        end)
        formPayloadEditorBox:SetScript("OnEditFocusLost", function()
            if formSaveTimer then
                formSaveTimer:Cancel()
                formSaveTimer = nil
            end
            ApplyFormRuleNow()
        end)
    end
end

LogPlanEvent = function(eventName, fields)
    local sem = ST()
    if sem and sem.LogPlanEvent then
        sem.LogPlanEvent(eventName, fields)
    end
end

local function LogFlushSkipOnce(reason, document, text)
    if not (C and C.DB and C.DB.debugMode and T and T.debug) then
        return
    end

    local normalizedTab = document and document.tab == "personal" and "personal" or "team"
    local key = table.concat({
        tostring(reason or ""),
        tostring(document and document.bossKeyText or ""),
        tostring(normalizedTab or ""),
        tostring(document and document.planID or 0),
    }, "|")
    if flushSkipLogSeen[key] then
        return
    end
    flushSkipLogSeen[key] = true

    T.debug(string.format(
        "[SemanticTimelineGUI] %s boss=%s tab=%s planID=%s len=%d",
        tostring(reason or ""),
        tostring(document and document.bossKeyText or ""),
        tostring(normalizedTab or ""),
        tostring(document and document.planID or ""),
        #(tostring(text or ""))
    ))
end

local function GetCurrentBossKeyText()
    if currentEditorDocument and currentEditorDocument.bossKeyText then
        return currentEditorDocument.bossKeyText
    end
    local sem = ST()
    if not (sem and sem.GetCurrentBossSelectorKey and sem.SerializeBossSelectorKey) then
        return ""
    end
    return sem:SerializeBossSelectorKey(sem:GetCurrentBossSelectorKey()) or ""
end

local function BuildViewportKey(bossKeyText, tab)
    return string.format("%s|%s", tostring(bossKeyText or ""), tostring(tab or "team"))
end

local function ClearViewportState()
    wipe(viewportStateByBossTab)
end

local function NormalizeEditorTab(tab)
    if tab == "personal" then
        return "personal"
    end
    return "team"
end

function SemanticTimelineGUI.NormalizeEditorTab(tab)
    return NormalizeEditorTab(tab)
end

local function GetDocumentBossKeyText(document)
    if type(document) == "table" and type(document.bossKeyText) == "string" then
        return document.bossKeyText
    end
    return GetCurrentBossKeyText()
end

local function SaveViewportState(tab, cause, bossKeyTextOverride)
    if not (editorBox and editorScrollView) then
        return
    end

    local bossKeyText = tostring(bossKeyTextOverride or GetCurrentBossKeyText() or "")
    if bossKeyText == "" then
        return
    end

    local normalizedTab = NormalizeEditorTab(tab)
    local state = {
        offset = math.floor((editorScrollView:GetVerticalScroll() or 0) + 0.5),
        cursor = tonumber(editorBox:GetCursorPosition()) or 0,
    }
    viewportStateByBossTab[BuildViewportKey(bossKeyText, normalizedTab)] = state
    LogPlanEvent("STT_EDITOR_VIEWPORT_SAVE", {
        bossKey = bossKeyText,
        tab = normalizedTab,
        offset = state.offset,
        cursor = state.cursor,
        cause = cause,
    })
end

local function RestoreViewportState(tab, cause, bossKeyTextOverride)
    if not (editorBox and editorScrollView) then
        return
    end

    local bossKeyText = tostring(bossKeyTextOverride or GetCurrentBossKeyText() or "")
    local normalizedTab = NormalizeEditorTab(tab)
    local state = bossKeyText ~= "" and viewportStateByBossTab[BuildViewportKey(bossKeyText, normalizedTab)] or nil
    local targetOffset = 0
    local targetCursor = 0
    if state then
        local maxOffset = math.max(0, editorScrollView:GetVerticalScrollRange() or 0)
        local maxCursor = #(editorBox:GetText() or "")
        targetOffset = math.max(0, math.min(tonumber(state.offset) or 0, maxOffset))
        targetCursor = math.max(0, math.min(tonumber(state.cursor) or 0, maxCursor))
    end

    editorBox:SetCursorPosition(targetCursor)
    editorScrollView:SnapTo(targetOffset)
end

local function ShouldRestoreViewport(cause)
    return cause == "initial_open"
        or cause == "panel_show"
        or cause == "boss_change"
        or cause == "tab_switch"
        or cause == "sync_apply"
end

local function ShouldForceDocumentHydrate(cause)
    return cause == "initial_open"
        or cause == "panel_show"
        or cause == "profile_changed"
        or cause == "sync_apply"
end

function SemanticTimelineGUI.GetActiveProfileName()
    if T.Profile and T.Profile.GetActive then
        local profile = T.Profile:GetActive()
        local meta = profile and profile._meta
        if meta and meta.name and meta.name ~= "" then
            return tostring(meta.name)
        end
    end

    local db = STT_DB
    local id = T.Profile and T.Profile:GetActiveProfileID() or nil
    local profile = id and db.Profiles and db.Profiles[id]
    local meta = profile and profile._meta
    if meta and meta.name and meta.name ~= "" then
        return tostring(meta.name)
    end
    return nil
end

function SemanticTimelineGUI.GetSaveStatusText()
    local profileName = SemanticTimelineGUI.GetActiveProfileName()
    if profileName then
        return string.format(L["已保存：%s"] or "已保存：%s", profileName)
    end
    return L["已保存"] or "已保存"
end

function SemanticTimelineGUI.CancelStatusTicker()
    local toast = SemanticTimelineGUI.statusToast
    if toast.fadeTicker then
        toast.fadeTicker:Cancel()
        toast.fadeTicker = nil
    end
end

function SemanticTimelineGUI.ScheduleStatusFadeOut(token)
    local toast = SemanticTimelineGUI.statusToast
    C_Timer.After(toast.holdTime, function()
        if token ~= statusToken or not statusLabel then
            return
        end

        local step = 0
        SemanticTimelineGUI.CancelStatusTicker()
        toast.fadeTicker = C_Timer.NewTicker(
            toast.fadeOutTime / toast.fadeSteps,
            function(self)
                if token ~= statusToken or not statusLabel then
                    self:Cancel()
                    return
                end

                step = step + 1
                statusLabel:SetAlpha(math.max(0, 1 - step / toast.fadeSteps))
                if step >= toast.fadeSteps then
                    statusLabel:SetText("")
                    statusLabel:SetAlpha(1)
                    self:Cancel()
                    toast.fadeTicker = nil
                end
            end,
            toast.fadeSteps
        )
    end)
end

function SemanticTimelineGUI.SetStatus(text, key)
    if not statusLabel or not text or text == "" then
        return
    end

    local toast = SemanticTimelineGUI.statusToast
    local now = GetTime and GetTime() or 0
    if key and key == toast.key and now < toast.keyExpire then
        toast.keyCount = toast.keyCount + 1
        toast.keyExpire = now + toast.mergeWindow
        statusToken = statusToken + 1
        SemanticTimelineGUI.CancelStatusTicker()
        statusLabel:SetAlpha(1)
        statusLabel:SetText(string.format("%s ×%d", toast.keyBaseText or text, toast.keyCount))
        SemanticTimelineGUI.ScheduleStatusFadeOut(statusToken)
        return
    end

    toast.key = key
    toast.keyBaseText = text
    toast.keyCount = 1
    toast.keyExpire = key and (now + toast.mergeWindow) or 0
    statusToken = statusToken + 1
    local token = statusToken
    SemanticTimelineGUI.CancelStatusTicker()
    statusLabel:SetText(text)
    statusLabel:SetAlpha(0)

    local step = 0
    toast.fadeTicker = C_Timer.NewTicker(
        toast.fadeInTime / toast.fadeSteps,
        function(self)
            if token ~= statusToken or not statusLabel then
                self:Cancel()
                return
            end

            step = step + 1
            statusLabel:SetAlpha(math.min(1, step / toast.fadeSteps))
            if step >= toast.fadeSteps then
                self:Cancel()
                toast.fadeTicker = nil
                SemanticTimelineGUI.ScheduleStatusFadeOut(token)
            end
        end,
        toast.fadeSteps
    )
end

function SemanticTimelineGUI.ShowSaveStatus()
    SemanticTimelineGUI.SetStatus(SemanticTimelineGUI.GetSaveStatusText(), "save")
end

function SemanticTimelineGUI.ShowReloadTemplateStatus()
    SemanticTimelineGUI.SetStatus(L["已重载：模板"] or "已重载：模板", "reload")
end

local function GetSelectedSpellRow()
    if not selectedRowID or selectedRowID == "" then
        return nil
    end
    for _, row in ipairs(currentRows or {}) do
        if row.rowID == selectedRowID and row.rowType == "spell" then
            return row
        end
    end
    return nil
end

local function SetSelectorButtonValue(button, label, valueText, value)
    if not button then
        return
    end
    button:SetLabel(label or "")
    button:SetSelectedValue(value, valueText or "-")
end

local function SetSelectorButtonEnabled(button, enabled)
    if not button then
        return
    end
    button:SetSelectorEnabled(enabled ~= false)
end

local function SetTooltipHandler(button, tooltipText)
    if not button then
        return
    end

    button.tooltipText = tooltipText
    button.tooltipWhenDisabledOnly = tooltipText ~= nil
end

local function SetTabButtonState(button, isActive)
    if not button then
        return
    end

    if button.SetTabActive then
        button:SetTabActive(isActive)
        return
    end

    button:SetEnabled(not isActive)
    if button.GetFontString then
        local fontString = button:GetFontString()
        if fontString then
            if isActive then
                fontString:SetTextColor(1, 0.92, 0.6, 1)
            else
                fontString:SetTextColor(1, 1, 1, 1)
            end
        end
    end
end

function SemanticTimelineGUI._SyncEditorTabGroupState(tab)
    local normalizedTab = tab == "personal" and "personal" or "team"
    if editorTabGroup then
        if editorTabGroup.SetActiveTab then
            editorTabGroup:SetActiveTab(normalizedTab, true)
            return
        end
        editorTabGroup.activeKey = normalizedTab
    end
    SetTabButtonState(teamTabBtn, normalizedTab == "team")
    SetTabButtonState(personalTabBtn, normalizedTab == "personal")
end

GetActiveEditorTab = function()
    if activeEditorTab ~= "personal" then
        return "team"
    end
    return "personal"
end

function SemanticTimelineGUI.GetActiveEditorTab()
    return GetActiveEditorTab()
end

function SemanticTimelineGUI.SwitchEditorDocument(targetBossKey, targetTab, cause)
    return SwitchEditorDocument(targetBossKey, targetTab, cause)
end

function SemanticTimelineGUI.GetEditorText()
    return editorBox and (editorBox:GetText() or "") or nil
end

function SemanticTimelineGUI.ReplaceEditorText(newText, caretPos, source, opts)
    if not (editorBox and SemanticTimelineGUI._segmentMove and SemanticTimelineGUI._segmentMove.ReplaceText) then
        return false
    end
    SemanticTimelineGUI._segmentMove.ReplaceText(newText, caretPos, source, opts)
    return true
end

local function GetResolveSourceItems()
    return {
        { value = "team", text = L["仅团队方案"] or "仅团队方案" },
        { value = "personal", text = L["仅个人方案"] or "仅个人方案" },
        { value = "team_plus_personal", text = L["团队+个人"] or "团队+个人" },
    }
end

function SemanticTimelineGUI.GetViewModeItems()
    return {
        { value = "vertical", text = L["TIMELINE_VIEW_VERTICAL"] or "垂直" },
        { value = "horizontal", text = L["TIMELINE_VIEW_HORIZONTAL"] or "水平" },
    }
end

function SemanticTimelineGUI.RefreshViewModeSelector()
    if not viewModeSelector then
        return
    end
    local mode = SemanticTimelineGUI.GetActiveLeftMode()
    viewModeSelector:SetItems(SemanticTimelineGUI.GetViewModeItems())
    viewModeSelector.onSelect = function(value)
        SemanticTimelineGUI.SetLeftMode(value)
    end
    local valueText = mode == "horizontal" and (L["TIMELINE_VIEW_HORIZONTAL"] or "水平") or (L["TIMELINE_VIEW_VERTICAL"] or "垂直")
    SetSelectorButtonValue(viewModeSelector, L["TIMELINE_VIEW_LABEL"] or "视角", valueText, mode)
    SetSelectorButtonEnabled(viewModeSelector, true)
end

SetActiveEditorTab = function(tab, persist)
    if tab ~= "team" and tab ~= "personal" then
        tab = "team"
    end

    activeEditorTab = tab
    SemanticTimelineGUI._SyncEditorTabGroupState(tab)
    if persist then
        local db = C and C.DB and C.DB.semanticTimeline
        if db then
            db.ui = db.ui or {}
            db.ui.activeEditorTab = tab
        end
    end
end

RefreshActionButtonState = function()
    local isPersonalTab = GetActiveEditorTab() == "personal"

    if syncBtn then
        local syncButton = T.SemanticTimelineSyncButton
        if syncButton and syncButton.RefreshEnabled then
            syncButton:RefreshEnabled(isPersonalTab)
        else
            syncBtn:SetEnabled(not isPersonalTab)
            SetTooltipHandler(syncBtn, isPersonalTab and (L["个人方案不支持同步"] or "个人方案不支持同步") or nil)
        end
    end
    if SemanticTimelineGUI.syncRaidBtn then
        SemanticTimelineGUI.syncRaidBtn:SetEnabled(not isPersonalTab)
        SetTooltipHandler(SemanticTimelineGUI.syncRaidBtn, isPersonalTab and (L["个人方案不支持同步"] or "个人方案不支持同步") or nil)
    end

    if reloadTemplateBtn then
        reloadTemplateBtn:SetEnabled(not isPersonalTab)
        SetTooltipHandler(reloadTemplateBtn, isPersonalTab and (L["个人方案无内置模板"] or "个人方案无内置模板") or nil)
    end
end

local function RefreshResolveSourceSelector()
    local db = C and C.DB and C.DB.semanticTimeline
    if not db then
        return
    end

    currentResolveSource = db.resolveSource or currentResolveSource or "team_plus_personal"
    db.resolveSource = currentResolveSource
    if resolveSourceSelector then
        resolveSourceSelector:SetItems(GetResolveSourceItems())
        resolveSourceSelector.onSelect = function(value)
            local sem = ST()
            currentResolveSource = sem and sem.SetResolveSource and sem:SetResolveSource(value) or (value or "team_plus_personal")
            db.resolveSource = currentResolveSource
            SemanticTimelineGUI.RefreshData("resolve_source_change")
        end

        local valueText = L["团队+个人"] or "团队+个人"
        for _, item in ipairs(resolveSourceSelector.items) do
            if item.value == currentResolveSource then
                valueText = item.text
                break
            end
        end
        SetSelectorButtonValue(resolveSourceSelector, L["解析方案"] or "解析方案", valueText, currentResolveSource)
        SetSelectorButtonEnabled(resolveSourceSelector, #resolveSourceSelector.items > 1)
    end
    if T.RefreshProfileSelector then
        T.RefreshProfileSelector()
    end
end

local function GetCurrentPlanForEditor(sem, tab)
    if not sem then
        return nil
    end

    if tab == "personal" then
        if sem.EnsureCurrentPersonalPlanPrepared then
            local ok, plan = pcall(sem.EnsureCurrentPersonalPlanPrepared, sem)
            if ok and plan ~= nil then
                return plan
            end
        end
        if sem.GetCurrentPersonalPlan then
            local ok, plan = pcall(sem.GetCurrentPersonalPlan, sem)
            if ok and plan ~= nil then
                return plan
            end
        end
        return nil
    end

    if sem.GetCurrentPlan then
        return sem:GetCurrentPlan()
    end

    return nil
end

local function CopyBossKey(key)
    if type(key) ~= "table" then
        return nil
    end
    return {
        instanceType = key.instanceType,
        instanceID = tonumber(key.instanceID) or 0,
        encounterID = tonumber(key.encounterID) or 0,
    }
end

local function CopyEditorDocument(document)
    if type(document) ~= "table" then
        return nil
    end
    return {
        bossKeyText = tostring(document.bossKeyText or ""),
        tab = NormalizeEditorTab(document.tab),
        planID = tonumber(document.planID),
        name = tostring(document.name or ""),
        loadedDigest = tonumber(document.loadedDigest) or 0,
    }
end

function SemanticTimelineGUI.GetCurrentEditorDocumentSnapshot()
    return CopyEditorDocument(currentEditorDocument)
end

local function BuildEditorDocumentState(document, sem)
    if type(document) ~= "table" then
        return nil
    end
    local content = tostring(document.content or "")
    local digest = sem and sem.ComputeContentDigest and sem.ComputeContentDigest(content) or 0
    return {
        bossKeyText = tostring(document.bossKeyText or ""),
        tab = NormalizeEditorTab(document.tab),
        planID = tonumber(document.planID),
        name = tostring(document.name or ""),
        loadedDigest = digest,
    }
end

local function CancelEditorSaveTimer()
    if saveTimer then
        saveTimer:Cancel()
        saveTimer = nil
    end
end

local function CancelFormSaveTimer()
    if formSaveTimer then
        formSaveTimer:Cancel()
        formSaveTimer = nil
    end
end

local function FlushCurrentEditorDocument(cause)
    if not currentEditorDocument then
        return true, "noop"
    end

    local sem = ST()
    if not (sem and sem.SavePlanDocument) then
        return false, "failed"
    end

    local text = editorBox and (editorBox:GetText() or "") or ""
    if isEditorDocumentHydrated ~= true then
        LogFlushSkipOnce("flush_skipped_unhydrated", currentEditorDocument, text)
        return true, "skipped_unhydrated"
    end

    local liveDocument = sem.GetPlanDocumentForBossTab
        and sem:GetPlanDocumentForBossTab(currentEditorDocument.bossKeyText, currentEditorDocument.tab)
        or nil
    if not liveDocument or tonumber(liveDocument.planID) ~= tonumber(currentEditorDocument.planID) then
        LogFlushSkipOnce("flush_skipped_stale_document", currentEditorDocument, text)
        return true, "skipped_stale_document"
    end

    local digest = sem.ComputeContentDigest and sem.ComputeContentDigest(text) or 0
    if digest == currentEditorDocument.loadedDigest then
        return true, "noop"
    end

    local ok = sem:SavePlanDocument(currentEditorDocument, text, cause)
    if ok then
        currentEditorDocument.loadedDigest = digest
    end
    return ok, ok and "saved" or "failed"
end

function SemanticTimelineGUI.FlushEditorNow(cause)
    CancelEditorSaveTimer()
    CancelFormSaveTimer()
    if cause ~= "panel_hide" then
        ApplyFormRuleNow()
    end
    local ok, result = FlushCurrentEditorDocument(cause or "manual_flush")
    if ok and result == "saved" then
        SemanticTimelineGUI.ShowSaveStatus()
    end
    return ok, result
end

local function ResolveDocumentTarget(sem, targetBossKey, targetTab)
    local normalizedTab = NormalizeEditorTab(targetTab or GetActiveEditorTab())
    local bossKey
    if type(targetBossKey) == "string" and sem.ParseBossSelectorKey then
        bossKey = sem:ParseBossSelectorKey(targetBossKey)
    elseif type(targetBossKey) == "table" then
        bossKey = CopyBossKey(targetBossKey)
    end
    bossKey = bossKey or sem:GetCurrentBossSelectorKey()
    local bossKeyText = sem:SerializeBossSelectorKey(bossKey)
    return bossKey, bossKeyText, normalizedTab
end

local function FormatSeconds(seconds)
    local value = tonumber(seconds)
    if not value then
        return "--:--"
    end
    if value < 0 then
        value = 0
    end
    local rounded = math.floor(value + 0.5)
    local minutes = math.floor(rounded / 60)
    local sec = rounded % 60
    return string.format("%02d:%02d", minutes, sec)
end

local function ClampNumber(value, minValue, maxValue, fallback)
    local number = tonumber(value)
    if not number then
        return fallback
    end
    if number < minValue then
        return minValue
    end
    if number > maxValue then
        return maxValue
    end
    return number
end

local function GetTimelineUIConfig()
    local db = C and C.DB and C.DB.semanticTimeline
    db = db or {}
    db.ui = type(db.ui) == "table" and db.ui or {}

    db.ui.cellWidth = ClampNumber(db.ui.cellWidth, MIN_CELL_WIDTH, MAX_CELL_WIDTH, DEFAULT_CELL_WIDTH)
    db.ui.rowHeight = ClampNumber(db.ui.rowHeight, MIN_ROW_HEIGHT, MAX_ROW_HEIGHT, DEFAULT_ROW_HEIGHT)
    db.ui.iconSize = ClampNumber(db.ui.iconSize, MIN_ICON_SIZE, MAX_ICON_SIZE, DEFAULT_ICON_SIZE)
    db.ui.cellGap = ClampNumber(db.ui.cellGap, MIN_CELL_GAP, MAX_CELL_GAP, DEFAULT_CELL_GAP)

    return db.ui
end

local function GetVisibleRowCount()
    local ui = GetTimelineUIConfig()
    local availableHeight = 0
    if leftPanelFrame and leftPanelFrame.GetHeight then
        availableHeight = math.max(0, (leftPanelFrame:GetHeight() or 0) + ROW_TOP_OFFSET - ROW_BOTTOM_PADDING)
    end
    if availableHeight <= 0 then
        return 1
    end
    return math.max(1, math.floor(availableHeight / ui.rowHeight))
end

local function EnsureCellRenderer()
    if not cellRenderer then
        cellRenderer = T.CreateCellRenderer()
    end
    return cellRenderer
end

local function ReleaseAllCells()
    EnsureCellRenderer():ReleaseAll()
end

local function AcquireCell(parent)
    local cell = EnsureCellRenderer():AcquireCell(parent)
    -- 解析区专用：点击选中行
    cell:SetScript("OnClick", function(self)
        SelectRow(self.rowData)
    end)
    return cell
end

local function RefreshEditorModeButtons()
    local structuredRawOnly = currentPlanFormat == "trigger" and currentTemplateInfo and currentTemplateInfo.hasBlocks == true
    local isTrigger = currentPlanFormat == "trigger" and not structuredRawOnly
    local baseTop = isTrigger and -60 or -34
    local errorTop = isTrigger and -60 or -34
    local hasErrors = #(currentErrors or {}) > 0
    local editorTop = hasErrors and (errorTop - 54) or baseTop
    if rawModeBtn then
        rawModeBtn:SetEnabled(isTrigger and editorMode ~= "raw")
        rawModeBtn:SetShown(isTrigger)
    end
    if formModeBtn then
        formModeBtn:SetEnabled(isTrigger and editorMode ~= "form")
        formModeBtn:SetShown(isTrigger)
    end
    if SemanticTimelineGUI.errorSummaryFrame then
        SemanticTimelineGUI.errorSummaryFrame:ClearAllPoints()
        SemanticTimelineGUI.errorSummaryFrame:SetPoint("TOPLEFT", rightPanelFrame, "TOPLEFT", 8, errorTop)
        SemanticTimelineGUI.errorSummaryFrame:SetPoint("TOPRIGHT", rightPanelFrame, "TOPRIGHT", -8, errorTop)
        SemanticTimelineGUI.errorSummaryFrame:SetShown(hasErrors)
    end
    if rawEditorContainer then
        rawEditorContainer:ClearAllPoints()
        rawEditorContainer:SetPoint("TOPLEFT", rightPanelFrame, "TOPLEFT", 8, editorTop)
        rawEditorContainer:SetPoint("BOTTOMRIGHT", rightPanelFrame, "BOTTOMRIGHT", -8, 0)
        rawEditorContainer:SetShown((not isTrigger) or editorMode == "raw" or structuredRawOnly)
    end
    if formContainer then
        formContainer:ClearAllPoints()
        formContainer:SetPoint("TOPLEFT", rightPanelFrame, "TOPLEFT", 8, editorTop)
        formContainer:SetPoint("BOTTOMRIGHT", rightPanelFrame, "BOTTOMRIGHT", -8, 0)
        formContainer:SetShown(isTrigger and editorMode == "form")
    end
end

-- BuildCellWho / BuildDisplayCell 已提取至 TimelineSyntax（单一权威）
local function BuildDisplayCell(segment, row)
    return T.TimelineSyntax.BuildDisplayCell(segment, {
        personalUntargeted = row and row.editorTab == "personal",
    })
end

local function BuildDisplayRow(row, cells)
    if #cells == 0 then
        return nil
    end

    return {
        rowID = row.rowID,
        timeSec = row.timeSec,
        phase = row.phase,
        rowType = row.rowType,
        enabled = row.enabled ~= false,
        editorTab = row.editorTab,
        sourcePlanID = row.sourcePlanID,
        isError = false,
        errorLine = nil,
        cells = cells,
    }
end

local function BuildErrorDisplayRow(err)
    return {
        rowID = string.format("error:%d", tonumber(err.line) or 0),
        rowType = "error",
        timeSec = nil,
        enabled = true,
        isError = true,
        errorLine = tonumber(err.line),
        cells = {
            {
                who = L["错误"] or "错误",
                whoType = "error",
                actionText = string.format("%s%d: %s", L["第"] or "第", tonumber(err.line) or 0, tostring(err.reason or "")),
                spellID = nil,
                spellIcon = nil,
                fullText = tostring(err.reason or ""),
                isError = true,
            },
        },
    }
end

-- 阶段分隔行：标签解析（优先 phaseLabels 配置，次选自动生成）
local function ResolvePhaseLabel(phaseKey, encounterID)
    local config = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[tonumber(encounterID) or 0]
    if config and type(config.phaseLabels) == "table" then
        local baseKey = tostring(phaseKey or ""):match("^([pi]%d+)") or phaseKey
        if config.phaseLabels[baseKey] then
            return config.phaseLabels[baseKey]
        end
    end
    local pType, pIndex = tostring(phaseKey or ""):match("^([pi])(%d+)")
    if pType == "p" then return "P" .. (pIndex or "?") end
    if pType == "i" then return "过渡 " .. (pIndex or "?") end
    return tostring(phaseKey or "")
end

-- 阶段分隔行：构建 displayRow（模式参考 BuildErrorDisplayRow）
local function BuildPhaseHeaderRow(phaseKey, encounterID)
    local baseKey = tostring(phaseKey or ""):match("^([pi]%d+)") or tostring(phaseKey or "")
    return {
        rowID = "phase:" .. baseKey,
        timeSec = nil,
        rowType = "phase_header",
        phase = phaseKey,
        phaseLabel = ResolvePhaseLabel(phaseKey, encounterID),
        enabled = true,
        isError = false,
        cells = {},
    }
end

local function BuildCellDisplayRows()
    currentDisplayRows = {}
    local lastPhase = nil

    -- 获取当前 encounterID（从第一行的 bossKey 中取）
    local encounterID = 0
    if currentRows and currentRows[1] and type(currentRows[1].key) == "table" then
        encounterID = tonumber(currentRows[1].key.encounterID) or 0
    end

    for _, row in ipairs(currentRows or {}) do
        -- 阶段变化时插入分隔行（仅当存在 phase 标记时）
        local rowPhase = row.phase
        if rowPhase ~= lastPhase and (rowPhase or lastPhase) then
            currentDisplayRows[#currentDisplayRows + 1] = BuildPhaseHeaderRow(
                rowPhase or "p1", encounterID)
        end
        lastPhase = rowPhase

        if type(row.segments) == "table" then
            local cells = {}
            for _, segment in ipairs(row.segments) do
                local cell = BuildDisplayCell(segment, row)
                if cell then
                    cells[#cells + 1] = cell
                end
            end

            local displayRow = BuildDisplayRow(row, cells)
            if displayRow then
                currentDisplayRows[#currentDisplayRows + 1] = displayRow
            end
        end
    end

    for _, err in ipairs(currentErrors or {}) do
        currentDisplayRows[#currentDisplayRows + 1] = BuildErrorDisplayRow(err)
    end

end

local function FocusEditorLine(lineNumber)
    if not editorBox or type(lineNumber) ~= "number" or lineNumber <= 0 then
        return
    end

    local text = editorBox:GetText() or ""
    local line = 1
    local startPos = 0

    for segment in (text .. "\n"):gmatch("([^\n]*)\n") do
        local endPos = startPos + #segment
        if line == lineNumber then
            editorBox:SetFocus()
            editorBox:SetCursorPosition(endPos)
            if editorBox.HighlightText then
                editorBox:HighlightText(startPos, endPos)
                editorHighlightToken = editorHighlightToken + 1
                local token = editorHighlightToken
                C_Timer.After(2, function()
                    if token ~= editorHighlightToken or not editorBox then
                        return
                    end
                    editorBox:HighlightText(0, 0)
                end)
            end
            return
        end
        startPos = endPos + 1
        line = line + 1
    end
end

local function RefreshErrorSummary()
    if not errorSummaryLabel then
        return
    end

    if #currentErrors == 0 then
        errorSummaryLabel:SetText("")
        if SemanticTimelineGUI.errorSummaryFrame then
            SemanticTimelineGUI.errorSummaryFrame:Hide()
        end
        return
    end

    local first = currentErrors[1]
    local line = tonumber(first.line) or 0
    local where = line > 0 and string.format("第 %d 行", line) or "方案"
    local message = tostring(first.message or "")
    if message == "" then
        message = tostring(first.reason or "")
    end
    if message == "" then
        message = "这一行无法解析"
    end

    local text = string.format("发现 %d 个问题。%s：%s", #currentErrors, where, message)
    local fix = tostring(first.fix or "")
    if fix ~= "" then
        text = text .. "\n" .. fix
    end
    errorSummaryLabel:SetText(text)
    if SemanticTimelineGUI.errorSummaryFrame then
        SemanticTimelineGUI.errorSummaryFrame:Show()
    end
end

local function EnsureCurrentRowsLoaded()
    local sem = ST()
    if not sem then
        ResetLoadedState(true)
        return
    end

    if currentEditorDocument and sem.PreparePlanForTab then
        sem:PreparePlanForTab(currentEditorDocument.tab)
    elseif sem.PreparePlanForTab then
        sem:PreparePlanForTab(GetActiveEditorTab())
    elseif sem.EnsureCurrentPlanPrepared then
        sem:EnsureCurrentPlanPrepared()
    end

    local plan = currentEditorDocument and sem.GetCurrentPlanDocument and sem:GetCurrentPlanDocument(currentEditorDocument.tab)
        or GetCurrentPlanForEditor(sem, GetActiveEditorTab())
    if not plan then
        ResetLoadedState(true)
        RefreshErrorSummary()
        RefreshEditorModeButtons()
        RefreshActionButtonState()
        return
    end

    local compileStartedAt = SemanticTimelineGUI.GetPerfMs()
    local compiled = sem.CompileResolvedPlanContent and sem:CompileResolvedPlanContent() or sem:CompileCurrentPlanText()
    currentRows = compiled and compiled.rows or {}
    currentErrors = compiled and compiled.errors or {}
    currentPlanFormat = compiled and compiled.format or "timeline"
    currentTemplateInfo = compiled and compiled.templateInfo or nil

    BuildCellDisplayRows()
    SemanticTimelineGUI._lastRefreshCompileMs = SemanticTimelineGUI.ElapsedMs(compileStartedAt) or 0
    RefreshErrorSummary()
    RefreshEditorModeButtons()
    RefreshActionButtonState()
    RefreshResolveSourceSelector()
end

local function ApplyRowCellOffset(row, offset)
    if not row or not row.cellContainer or not row.cellClipFrame then
        return
    end
    row.cellContainer:ClearAllPoints()
    row.cellContainer:SetPoint("TOP", row.cellClipFrame, "TOP", 0, 0)
    row.cellContainer:SetPoint("BOTTOM", row.cellClipFrame, "BOTTOM", 0, 0)
    row.cellContainer:SetPoint("LEFT", row.cellClipFrame, "LEFT", -(tonumber(offset) or 0), 0)
end

local HSCROLL_BAR_HEIGHT = 8
local HSCROLL_BAR_BOTTOM_OFFSET = -10
local HSCROLL_BAR_TOP_GAP = 0
local HSCROLL_BLEND_SPEED = 0.15
local ROWS_LEFT_INSET = 6
local ROWS_RIGHT_INSET = 2
local HSCROLL_CAUSE_POLICY = {
    initial_open = { defer = true, reveal = true },
    panel_show = { defer = true, reveal = true },
    left_panel_resize = { defer = true, reveal = false },
    boss_change = { defer = true, reveal = true },
    tab_switch = { defer = true, reveal = true },
    document_switch = { defer = true, reveal = true },
    sync_apply = { defer = true, reveal = true },
}

local function IsLayoutRefreshCause(cause)
    if type(cause) ~= "string" or cause == "" then
        return false
    end

    return cause == "divider_drag"
        or cause == "divider_release"
        or cause == "divider_reset"
        or cause == "left_panel_resize"
        or cause == "left_panel_resize_deferred"
end

local function CancelDeferredHorizontalRefresh()
    if hScrollDeferredTimer then
        hScrollDeferredTimer:Cancel()
        hScrollDeferredTimer = nil
    end
end

local function GetVisibleCellClipWidth()
    for _, row in ipairs(rowFrames or {}) do
        if row and row:IsShown() and row.cellClipFrame and row.cellClipFrame:IsShown() then
            local width = tonumber(row.cellClipFrame:GetWidth()) or 0
            if width > 0 then
                return math.max(0, width)
            end
        end
    end
    return 0
end

local function GetFallbackCellClipWidth()
    if dividerLayoutMode == "left_collapsed" then
        return 0
    end

    local baseWidth = 0
    if rowsScroll and rowsScroll.GetWidth then
        baseWidth = math.max(baseWidth, tonumber(rowsScroll:GetWidth()) or 0)
    end
    if leftPanelFrame and leftPanelFrame.GetWidth then
        baseWidth = math.max(baseWidth, (tonumber(leftPanelFrame:GetWidth()) or 0) - ROWS_LEFT_INSET - ROWS_RIGHT_INSET)
    end
    if baseWidth <= 0 then
        return 0
    end
    return math.max(0, baseWidth - TIME_COLUMN_WIDTH - ROW_SIDE_PADDING * 2 - 4)
end

local function GetCellClipWidth(preferGeometry)
    if dividerLayoutMode == "left_collapsed" then
        return 0
    end

    if preferGeometry then
        local fallbackWidth = GetFallbackCellClipWidth()
        if fallbackWidth > 0 then
            return fallbackWidth
        end
    end

    local visibleWidth = GetVisibleCellClipWidth()
    if visibleWidth > 0 then
        return visibleWidth
    end
    return GetFallbackCellClipWidth()
end

local function CalcDisplayRowContentWidth(data, ui)
    if not data or data.rowType == "phase_header" then
        return 0
    end

    local count = #(data.cells or {})
    if count <= 0 then
        return 0
    end

    return count * ui.cellWidth + math.max(0, count - 1) * ui.cellGap
end

local function RecalcGlobalContentWidth()
    local ui = GetTimelineUIConfig()
    local maxWidth = 0
    for _, data in ipairs(currentDisplayRows or {}) do
        local rowWidth = CalcDisplayRowContentWidth(data, ui)
        if rowWidth > maxWidth then
            maxWidth = rowWidth
        end
    end
    globalMaxContentWidth = maxWidth
end

local function GetHorizontalScrollRange(clipWidth)
    return math.max(0, globalMaxContentWidth - math.max(0, tonumber(clipWidth) or GetCellClipWidth()))
end

local function ClampHorizontalOffset(maxOffset)
    maxOffset = math.max(0, tonumber(maxOffset) or GetHorizontalScrollRange())
    if maxOffset <= 0 then
        globalHorizontalOffset = 0
        return
    end
    if globalHorizontalOffset < 0 then
        globalHorizontalOffset = 0
    elseif globalHorizontalOffset > maxOffset then
        globalHorizontalOffset = maxOffset
    end
    if horizontalScrollModel then
        horizontalScrollModel.scrollTarget = math.max(0, math.min(horizontalScrollModel.scrollTarget or globalHorizontalOffset, maxOffset))
    end
end

local function ApplyGlobalHorizontalOffset()
    for _, row in ipairs(rowFrames or {}) do
        if row and row:IsShown() and row.cellContainer then
            ApplyRowCellOffset(row, globalHorizontalOffset)
        end
    end
end

local function UpdateHorizontalScrollBar()
    if hScrollBar and hScrollBar.Refresh then
        hScrollBar:Refresh()
    end
end

local function GetHorizontalRefreshPolicy(cause)
    local policy = cause and HSCROLL_CAUSE_POLICY[cause] or nil
    return policy or false
end

local function DebugLogHorizontalMetrics(cause, clipWidth, range)
    if not (cause and cause ~= "" and C and C.DB and C.DB.debugMode and T and T.debug) then
        return
    end

    local scrollTarget = horizontalScrollModel and horizontalScrollModel.scrollTarget or globalHorizontalOffset
    T.debug(string.format(
        "[STT_HSCROLL_METRICS] cause=%s maxContent=%.0f clip=%.0f range=%.0f offset=%.0f target=%.0f",
        tostring(cause),
        tonumber(globalMaxContentWidth) or 0,
        tonumber(clipWidth) or 0,
        tonumber(range) or 0,
        tonumber(globalHorizontalOffset) or 0,
        tonumber(scrollTarget) or 0
    ))
end

local function DebugLogHorizontalReady(cause, clipWidth, range)
    if range <= 0 then
        hScrollReadySeen = false
        return
    end
    if hScrollReadySeen then
        return
    end
    hScrollReadySeen = true
    if not (C and C.DB and C.DB.debugMode and T and T.debug) then
        return
    end
    T.debug(string.format(
        "[STT_HSCROLL_READY] cause=%s maxContent=%.0f clip=%.0f range=%.0f",
        tostring(cause or ""),
        tonumber(globalMaxContentWidth) or 0,
        tonumber(clipWidth) or 0,
        tonumber(range) or 0
    ))
end

local function EnsureHorizontalScrollModel()
    if horizontalScrollModel then
        return horizontalScrollModel
    end
    horizontalScrollModel = T.CreateSmoothValueDriver({
        blendSpeed = HSCROLL_BLEND_SPEED,
        onValueChanged = function(_, offset)
            globalHorizontalOffset = offset
            ApplyGlobalHorizontalOffset()
            UpdateHorizontalScrollBar()
        end,
    })
    return horizontalScrollModel
end

local function StopHorizontalScroll()
    if horizontalScrollModel then
        horizontalScrollModel:StopScrolling()
    end
end

local function ResetHorizontalScrollState()
    CancelDeferredHorizontalRefresh()
    StopHorizontalScroll()
    globalHorizontalOffset = 0
    globalMaxContentWidth = 0
    hScrollReadySeen = false
    if horizontalScrollModel then
        horizontalScrollModel.offset = 0
        horizontalScrollModel.scrollTarget = 0
    end
end

local function RefreshHorizontalMetrics(opts)
    opts = type(opts) == "table" and opts or {}

    if dividerLayoutMode == "left_collapsed" then
        ResetHorizontalScrollState()
        UpdateHorizontalScrollBar()
        return 0
    end

    local ui = GetTimelineUIConfig()
    local horizontalModel = EnsureHorizontalScrollModel()
    local range = 0
    local clipWidth
    local preferGeometry = opts.preferGeometry == true or IsLayoutRefreshCause(opts.cause)

    RecalcGlobalContentWidth()
    rowFrames = rowsScroll and rowsScroll.rowFrames or rowFrames
    clipWidth = GetCellClipWidth(preferGeometry)
    range = GetHorizontalScrollRange(clipWidth)

    horizontalModel:SetBlendSpeed(HSCROLL_BLEND_SPEED)
    horizontalModel:SetStepSize(math.max(24, math.floor(ui.cellWidth * 0.75)))
    horizontalModel:SetScrollRange(range)
    globalHorizontalOffset = horizontalModel:GetOffset()
    ClampHorizontalOffset(range)
    ApplyGlobalHorizontalOffset()
    UpdateHorizontalScrollBar()
    DebugLogHorizontalMetrics(opts.cause, clipWidth, range)
    DebugLogHorizontalReady(opts.cause, clipWidth, range)

    if opts.revealBar and range > 0 and hScrollBar and hScrollBar.RevealTemporarily then
        hScrollBar:RevealTemporarily()
    end

    return range
end

local function ScheduleDeferredHorizontalRefresh(cause, revealBar)
    local policy = GetHorizontalRefreshPolicy(cause)
    if not policy or not policy.defer then
        return
    end
    CancelDeferredHorizontalRefresh()
    hScrollDeferredTimer = C_Timer.NewTimer(0, function()
        hScrollDeferredTimer = nil
        if not rowsScroll then
            return
        end
        rowFrames = rowsScroll.rowFrames or rowFrames
        RefreshHorizontalMetrics({
            cause = tostring(cause or "refresh") .. "_deferred",
            revealBar = revealBar == true or policy.reveal == true,
        })
    end)
end

local function SetHorizontalOffset(value)
    globalHorizontalOffset = tonumber(value) or 0
    ClampHorizontalOffset()
    local model = EnsureHorizontalScrollModel()
    model:SetBlendSpeed(HSCROLL_BLEND_SPEED)
    model:SnapTo(globalHorizontalOffset)
end

local function ScrollHorizontalTo(value)
    local model = EnsureHorizontalScrollModel()
    model:SetBlendSpeed(HSCROLL_BLEND_SPEED)
    model:ScrollTo(value)
end

local function ScrollHorizontalBy(delta)
    local ui = GetTimelineUIConfig()
    local step = math.max(24, math.floor(ui.cellWidth * 0.75))
    local model = EnsureHorizontalScrollModel()
    model:SetBlendSpeed(HSCROLL_BLEND_SPEED)
    model:SetStepSize(step)
    model:ScrollBy(-((tonumber(delta) or 0) * step))
end

local function ResetHorizontalScroll()
    SetHorizontalOffset(0)
end

local function RouteTimelineMouseWheel(delta, verticalFallback)
    if IsShiftKeyDown() then
        ScrollHorizontalBy(delta)
        return
    end
    if type(verticalFallback) == "function" then
        verticalFallback(delta)
    end
end

local function CreateTimelineRowFrame(parent)
    local row = CreateFrame("Button", nil, parent)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)

    local selectTex = row:CreateTexture(nil, "OVERLAY")
    selectTex:SetAllPoints(row)
    selectTex:SetColorTexture(0.2, 0.55, 0.9, 0.25)
    selectTex:Hide()

    local timeText = T.CreateFontString(row, {
        template = "GameFontHighlightSmall",
        point = {"LEFT", row, "LEFT", ROW_SIDE_PADDING, 0},
        width = TIME_COLUMN_WIDTH,
        justifyH = "LEFT",
        wordWrap = false,
    })

    local cellClipFrame = CreateFrame("Frame", nil, row)
    cellClipFrame:SetPoint("LEFT", timeText, "RIGHT", 4, 0)
    cellClipFrame:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_SIDE_PADDING, -1)
    cellClipFrame:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_SIDE_PADDING, 1)
    cellClipFrame:SetClipsChildren(true)
    cellClipFrame:EnableMouseWheel(true)

    local cellContainer = CreateFrame("Frame", nil, cellClipFrame)
    cellContainer:SetPoint("LEFT", cellClipFrame, "LEFT", 0, 0)
    cellContainer:SetPoint("TOP", cellClipFrame, "TOP", 0, 0)
    cellContainer:SetPoint("BOTTOM", cellClipFrame, "BOTTOM", 0, 0)

    -- 阶段分隔行标签（居中覆盖整行，默认隐藏）
    local phaseLabel = T.CreateFontString(row, {
        template = "GameFontNormal",
        point = {"CENTER", row, "CENTER", 0, 0},
        justifyH = "CENTER",
        wordWrap = false,
    })
    phaseLabel:SetAllPoints(row)
    phaseLabel:Hide()

    row:SetScript("OnClick", function(self)
        -- 阶段分隔行不可选中
        if self.data and self.data.rowType == "phase_header" then
            return
        end
        SelectRow(self.data)
    end)
    cellClipFrame:SetScript("OnMouseWheel", function(_, delta)
        RouteTimelineMouseWheel(delta, function(nextDelta)
            if rowsScroll and rowsScroll.OnMouseWheel then
                rowsScroll:OnMouseWheel(nextDelta)
            end
        end)
    end)

    row.bg = bg
    row.timeText = timeText
    row.selectTex = selectTex
    row.phaseLabel = phaseLabel
    row.cellClipFrame = cellClipFrame
    row.cellContainer = cellContainer
    return row
end

local function PopulateCellFrame(cell, rowData, cellData, ui, xOffset)
    cell.rowData = rowData
    EnsureCellRenderer():PopulateCell(cell, cellData, ui, xOffset)
end

local function RefreshRowCells(row, data, ui)
    local xOffset = 0

    for _, cellData in ipairs(data.cells or {}) do
        local cell = AcquireCell(row.cellContainer)
        PopulateCellFrame(cell, data, cellData, ui, xOffset)
        xOffset = xOffset + ui.cellWidth + ui.cellGap
    end

    local totalWidth = math.max(0, xOffset - ui.cellGap)
    row.cellContainer.contentWidth = totalWidth
    row.cellContainer:SetWidth(math.max(totalWidth, row.cellClipFrame:GetWidth()))
    ApplyRowCellOffset(row, globalHorizontalOffset)
end

local function RenderTimelineRow(row, dataIndex)
    local data = currentDisplayRows[dataIndex]
    local ui = GetTimelineUIConfig()

    row:SetHeight(ui.rowHeight)
    row.timeText:SetWidth(TIME_COLUMN_WIDTH)

    if not data then
        row.data = nil
        row:Hide()
        return
    end

    row:Show()
    row.data = data

    -- 阶段分隔行：金色文字 + 暗金背景，不显示时间和 cell
    if data.rowType == "phase_header" then
        row.timeText:SetText("")
        row.phaseLabel:SetText("|cFFFFD100\226\148\128\226\148\128 " .. (data.phaseLabel or "") .. " \226\148\128\226\148\128|r")
        row.phaseLabel:Show()
        row.bg:SetColorTexture(0.15, 0.12, 0.05, 0.6)
        row.selectTex:Hide()
        row.cellClipFrame:Hide()
        return
    end

    -- 普通行：隐藏阶段标签，恢复 cellClipFrame
    row.phaseLabel:Hide()
    row.cellClipFrame:Show()

    if (dataIndex % 2) == 1 then
        row.bg:SetColorTexture(0.10, 0.10, 0.16, 0.55)
    else
        row.bg:SetColorTexture(0.06, 0.06, 0.10, 0.25)
    end

    if currentPlanFormat == "trigger" and not data.isError then
        row.timeText:SetText(L["动态"] or "动态")
    else
        row.timeText:SetText(data.timeSec and FormatSeconds(data.timeSec) or "--:--")
    end

    if selectedRowID and selectedRowID == data.rowID then
        row.selectTex:Show()
    else
        row.selectTex:Hide()
    end

    RefreshRowCells(row, data, ui)
end

function SemanticTimelineGUI.RefreshHorizontalTimeline(opts)
    if not horizontalTimeline then
        return false
    end
    opts = type(opts) == "table" and opts or {}
    horizontalTimeline:Refresh(currentRows, {
        cause = opts.cause,
        restoreScrollY = opts.cause == "initial_open" or opts.cause == "panel_show",
        fullText = editorBox and (editorBox:GetText() or "") or "",
    })
    return true
end

RefreshRows = function(opts)
    if not rowsScroll then
        return
    end

    opts = opts or {}
    if SemanticTimelineGUI.GetActiveLeftMode() == "horizontal" and horizontalTimeline then
        if verticalViewFrame then
            verticalViewFrame:Hide()
        end
        if horizontalTimeline.Show then
            horizontalTimeline:Show()
        end
        SemanticTimelineGUI.RefreshHorizontalTimeline(opts)
        return
    end

    if horizontalTimeline and horizontalTimeline.Hide then
        horizontalTimeline:Hide()
    end
    if verticalViewFrame then
        verticalViewFrame:Show()
    end

    local ui = GetTimelineUIConfig()
    local rowHeight = math.max(1, tonumber(ui.rowHeight) or DEFAULT_ROW_HEIGHT)
    local dataCount = #currentDisplayRows

    if rowsScroll.rowHeight ~= rowHeight then
        rowsScroll.rowHeight = rowHeight
        if not rowsScroll._customStepSize then
            rowsScroll:SetStepSize(rowHeight * 3)
        end
    elseif not rowsScroll._customStepSize then
        rowsScroll:SetStepSize(rowHeight * 3)
    end

    if rowsScroll.dataCount ~= dataCount then
        rowsScroll.dataCount = dataCount
    end

    if IsLayoutRefreshCause(opts.cause) then
        ResetHorizontalScroll()
    end

    if dividerLayoutMode == "left_collapsed" then
        ResetHorizontalScrollState()
        UpdateHorizontalScrollBar()
        if opts.cause then
            LogPlanEvent("STT_ROWS_REFRESH", {
                bossKey = GetCurrentBossKeyText(),
                tab = GetActiveEditorTab(),
                rowCount = #currentDisplayRows,
                errorCount = #(currentErrors or {}),
                cause = opts.cause,
            })
        end
        return
    end

    if opts.force ~= false then
        rowsScroll:Refresh(true)
    end
    rowFrames = rowsScroll.rowFrames or rowFrames
    local hScrollPolicy = GetHorizontalRefreshPolicy(opts.cause)
    RefreshHorizontalMetrics({
        cause = opts.cause,
        revealBar = hScrollPolicy and hScrollPolicy.reveal == true,
    })
    ScheduleDeferredHorizontalRefresh(opts.cause, hScrollPolicy and hScrollPolicy.reveal == true)
    if opts.cause then
        LogPlanEvent("STT_ROWS_REFRESH", {
            bossKey = GetCurrentBossKeyText(),
            tab = GetActiveEditorTab(),
            rowCount = #currentDisplayRows,
            errorCount = #(currentErrors or {}),
            cause = opts.cause,
        })
    end
end

SelectRow = function(data)
    if not data then
        return
    end
    -- 阶段分隔行不可选中
    if data.rowType == "phase_header" then
        return
    end

    if data.isError and data.errorLine then
        selectedRowID = data.rowID
        RefreshRows()
        FocusEditorLine(data.errorLine)
        return
    end

    local sem = ST()
    if not sem then
        return
    end

    local targetTab = NormalizeEditorTab(data.editorTab or GetActiveEditorTab())
    selectedRowID = data.rowID
    if targetTab ~= GetActiveEditorTab() then
        SwitchEditorDocument(nil, targetTab, "timeline_row_jump")
    else
        RefreshRows()
    end

    local line = sem.GetPlanLineByRowIDForTab and sem:GetPlanLineByRowIDForTab(targetTab, data.rowID)
        or sem:GetCurrentPlanLineByRowID(data.rowID)
    if line then
        FocusEditorLine(line)
    end

    RefreshTriggerForm()
end

ResetLoadedState = function(clearEditor)
    currentRows = {}
    currentErrors = {}
    currentDisplayRows = {}
    ResetHorizontalScrollState()
    if horizontalTimeline then
        horizontalTimeline:Refresh({}, { cause = "reset" })
    end
    ReleaseAllCells()
    currentPlanFormat = "timeline"
    currentTemplateInfo = nil
    selectedRowID = nil

    if clearEditor and editorBox then
        isEditorHydrating = true
        editorBox:SetText("")
        isEditorHydrating = false
        isEditorDocumentHydrated = false
    end

    if clearEditor and formPayloadEditorBox then
        isFormHydrating = true
        formPayloadEditorBox:SetText("")
        isFormHydrating = false
    end

    UpdateHorizontalScrollBar()
end

function SemanticTimelineGUI.BuildValueTextOptions(items, valueKey, textKey)
    local out = {}
    for _, item in ipairs(items or {}) do
        out[#out + 1] = {
            value = item[valueKey],
            text = item[textKey],
        }
    end
    return out
end

function SemanticTimelineGUI.FindFirstInstanceWithEncounters(sem, instanceType, instanceOptions)
    for _, option in ipairs(instanceOptions or {}) do
        if option and option.instanceID and #sem:GetWorkbenchEncounterList(instanceType, option.instanceID) > 0 then
            return option
        end
    end
    return instanceOptions and instanceOptions[1] or nil
end

function SemanticTimelineGUI.ResolveSwitchTargetBoss(sem, instanceType, instanceID, encounterID)
    if not (sem and sem.BuildBossSelectorKey) then
        return nil
    end

    local resolvedInstanceType = instanceType
    local resolvedInstanceID = tonumber(instanceID) or 0
    local resolvedEncounterID = tonumber(encounterID) or 0

    if resolvedInstanceID == 0 then
        local instanceOptions = sem:GetWorkbenchInstanceList(resolvedInstanceType)
        local preferredInstance = SemanticTimelineGUI.FindFirstInstanceWithEncounters(sem, resolvedInstanceType, instanceOptions)
        resolvedInstanceID = preferredInstance and tonumber(preferredInstance.instanceID) or 0
    end
    if resolvedInstanceID == 0 then
        return nil
    end

    if resolvedEncounterID == 0 then
        local encounterOptions = sem:GetWorkbenchEncounterList(resolvedInstanceType, resolvedInstanceID)
        resolvedEncounterID = encounterOptions[1] and tonumber(encounterOptions[1].encounterID) or 0
    end
    if resolvedEncounterID == 0 then
        return nil
    end

    return sem:BuildBossSelectorKey(
        resolvedInstanceType,
        resolvedInstanceID,
        resolvedEncounterID
    )
end

local function RefreshDropdowns()
    if not instanceTypeSelector then
        return false
    end
    local sem = ST()
    if not sem then
        return false
    end

    local selectionChanged = false
    local selection = sem:GetWorkbenchSelection()
    local typeOptions = sem:GetWorkbenchInstanceTypeOptions()
    local instanceOptions = sem:GetWorkbenchInstanceList(selection.instanceType)
    if #instanceOptions == 0 then
        sem:RebuildTemplateIndexes(true)
        selection = sem:GetWorkbenchSelection()
        typeOptions = sem:GetWorkbenchInstanceTypeOptions()
        instanceOptions = sem:GetWorkbenchInstanceList(selection.instanceType)
    end
    if #instanceOptions == 0 and #typeOptions > 0 then
        for _, typeOption in ipairs(typeOptions) do
            local candidateInstances = sem:GetWorkbenchInstanceList(typeOption.value)
            local preferredInstance = SemanticTimelineGUI.FindFirstInstanceWithEncounters(sem, typeOption.value, candidateInstances)
            if preferredInstance then
                sem:SetWorkbenchSelection(typeOption.value, preferredInstance.instanceID, nil)
                selectionChanged = true
                break
            end
        end
        if selectionChanged then
            selection = sem:GetWorkbenchSelection()
            instanceOptions = sem:GetWorkbenchInstanceList(selection.instanceType)
        end
    end

    local encounterOptions = sem:GetWorkbenchEncounterList(selection.instanceType, selection.instanceID)
    if #encounterOptions == 0 and #instanceOptions > 0 then
        local preferredInstance = SemanticTimelineGUI.FindFirstInstanceWithEncounters(sem, selection.instanceType, instanceOptions)
        if preferredInstance and preferredInstance.instanceID ~= selection.instanceID then
            sem:SetWorkbenchSelection(selection.instanceType, preferredInstance.instanceID, nil)
            selectionChanged = true
            selection = sem:GetWorkbenchSelection()
            encounterOptions = sem:GetWorkbenchEncounterList(selection.instanceType, selection.instanceID)
        end
    end

    local instanceTypeValueText = L["无可用选项"] or "-"
    for _, option in ipairs(typeOptions) do
        if option.value == selection.instanceType then
            instanceTypeValueText = option.text
            break
        end
    end
    if instanceTypeValueText == (L["无可用选项"] or "-") and typeOptions[1] then
        instanceTypeValueText = typeOptions[1].text
    end

    instanceTypeSelector:SetItems(typeOptions)
    instanceTypeSelector.onSelect = function(value)
        local targetBossKey = SemanticTimelineGUI.ResolveSwitchTargetBoss(sem, value, nil, nil)
        if not targetBossKey then
            return
        end
        sem:RecordManualBossSelection(targetBossKey)
        SwitchEditorDocument(targetBossKey, GetActiveEditorTab(), "boss_change")
    end
    SetSelectorButtonValue(instanceTypeSelector, L["类型"] or "类型", instanceTypeValueText, selection.instanceType)
    SetSelectorButtonEnabled(instanceTypeSelector, #typeOptions > 1)

    local normalizedInstanceOptions = SemanticTimelineGUI.BuildValueTextOptions(instanceOptions, "instanceID", "name")
    local instanceValueText = L["无可用选项"] or "-"
    for _, option in ipairs(normalizedInstanceOptions) do
        if option.value == selection.instanceID then
            instanceValueText = option.text
            break
        end
    end
    if instanceValueText == (L["无可用选项"] or "-") and normalizedInstanceOptions[1] then
        instanceValueText = normalizedInstanceOptions[1].text
    end

    instanceSelector:SetItems(normalizedInstanceOptions)
    instanceSelector.onSelect = function(value)
        local targetBossKey = SemanticTimelineGUI.ResolveSwitchTargetBoss(sem, selection.instanceType, value, nil)
        if not targetBossKey then
            return
        end
        sem:RecordManualBossSelection(targetBossKey)
        SwitchEditorDocument(targetBossKey, GetActiveEditorTab(), "boss_change")
    end
    SetSelectorButtonValue(instanceSelector, L["副本"] or "副本", instanceValueText, selection.instanceID)
    SetSelectorButtonEnabled(instanceSelector, #normalizedInstanceOptions > 0)

    local normalizedEncounterOptions = SemanticTimelineGUI.BuildValueTextOptions(encounterOptions, "encounterID", "name")
    local bossValueText = L["无可用选项"] or "-"
    for _, option in ipairs(normalizedEncounterOptions) do
        if option.value == selection.encounterID then
            bossValueText = option.text
            break
        end
    end
    if bossValueText == (L["无可用选项"] or "-") and normalizedEncounterOptions[1] then
        bossValueText = normalizedEncounterOptions[1].text
    end

    bossSelector:SetItems(normalizedEncounterOptions)
    bossSelector.onSelect = function(value)
        local targetBossKey = SemanticTimelineGUI.ResolveSwitchTargetBoss(sem, selection.instanceType, selection.instanceID, value)
        if not targetBossKey then
            return
        end
        sem:RecordManualBossSelection(targetBossKey)
        SwitchEditorDocument(targetBossKey, GetActiveEditorTab(), "boss_change")
    end
    SetSelectorButtonValue(bossSelector, L["Boss"] or "Boss", bossValueText, selection.encounterID)
    SetSelectorButtonEnabled(bossSelector, #normalizedEncounterOptions > 0)

    return selectionChanged
end

RefreshTriggerForm = function()
    if not formContainer then
        return
    end

    local sem = ST()
    local selectedRow = GetSelectedSpellRow()
    local isTrigger = currentPlanFormat == "trigger"
    local structuredRawOnly = isTrigger and currentTemplateInfo and currentTemplateInfo.hasBlocks == true
    local hasSelection = isTrigger and selectedRow ~= nil

    if formSpellNameText then
        formSpellNameText:SetText(hasSelection and (selectedRow.label or "") or (L["请选择左侧技能"] or "请选择左侧技能"))
    end
    if formHintText then
        if structuredRawOnly then
            formHintText:SetText(L["结构化模板仅支持原始文本编辑"] or "结构化模板仅支持原始文本编辑")
        elseif hasSelection then
            formHintText:SetText(L["第N次覆写请在原始文本手写"] or "第N次覆写请在原始文本手写")
        else
            formHintText:SetText(L["触发式方案仅支持逐技能编辑默认规则"] or "触发式方案仅支持逐技能编辑默认规则")
        end
    end

    if formPayloadEditorBox then
        isFormHydrating = true
        local activeRule = sem and sem.GetTriggerDefaultRuleForDocument and currentEditorDocument and selectedRow
            and sem:GetTriggerDefaultRuleForDocument(currentEditorDocument, selectedRow.spellID)
            or nil
        formPayloadEditorBox:SetText(hasSelection and ((activeRule and activeRule.payload) or selectedRow.textPayload or "") or "")
        isFormHydrating = false
        formPayloadEditorBox:SetEnabled(hasSelection and not structuredRawOnly)
    end
end

function SemanticTimelineGUI.RequestRuntimeReloadAfterSave(cause)
    local runner = T.TimelineRunner
    if runner and runner.RequestRuntimeReloadFromCurrent then
        runner:RequestRuntimeReloadFromCurrent(cause or "editor_save")
    end
end

ApplyFormRuleNow = function()
    if isFormHydrating or currentPlanFormat ~= "trigger" or (currentTemplateInfo and currentTemplateInfo.hasBlocks == true) then
        return
    end
    local selectedRow = GetSelectedSpellRow()
    if not selectedRow then
        return
    end

    local sem = ST()
    if not sem then
        return
    end

    if not currentEditorDocument then
        return
    end

    local payload = formPayloadEditorBox and formPayloadEditorBox:GetText() or ""
    local compiled = sem.UpsertTriggerDefaultRuleForDocument
        and sem:UpsertTriggerDefaultRuleForDocument(currentEditorDocument, selectedRow.spellID, "text", payload)
        or nil
    if not compiled then
        return
    end

    local document = sem.GetPlanDocumentForBossTab
        and sem:GetPlanDocumentForBossTab(currentEditorDocument.bossKeyText, currentEditorDocument.tab)
        or nil
    if editorBox then
        isEditorHydrating = true
        editorBox:SetText(document and document.content or "")
        isEditorHydrating = false
        isEditorDocumentHydrated = true
    end
    if currentEditorDocument and sem.ComputeContentDigest then
        currentEditorDocument.loadedDigest = sem.ComputeContentDigest(document and document.content or "")
        if document and document.name ~= nil then
            currentEditorDocument.name = tostring(document.name or "")
        end
    end

    currentRows = compiled.rows or {}
    currentErrors = compiled.errors or {}
    currentPlanFormat = compiled.format or "trigger"
    currentTemplateInfo = compiled.templateInfo or nil
    BuildCellDisplayRows()
    RefreshRows()
    RefreshErrorSummary()
    RefreshEditorModeButtons()
    RefreshTriggerForm()
    SemanticTimelineGUI.ShowSaveStatus()
    SemanticTimelineGUI.RequestRuntimeReloadAfterSave("form_save")
end

ScheduleFormSave = function()
    if formSaveTimer then
        formSaveTimer:Cancel()
        formSaveTimer = nil
    end

    formSaveTimer = C_Timer.NewTimer(0.2, function()
        ApplyFormRuleNow()
        formSaveTimer = nil
    end)
end

SetEditorMode = function(mode)
    if currentPlanFormat ~= "trigger" or (currentTemplateInfo and currentTemplateInfo.hasBlocks == true) then
        editorMode = "raw"
    elseif mode == "form" or mode == "raw" then
        editorMode = mode
    end
    RefreshEditorModeButtons()
    RefreshTriggerForm()
end

SwitchEditorDocument = function(targetBossKey, targetTab, cause, options)
    local sem = ST()
    if not sem then
        return false
    end

    local refreshCause = type(cause) == "string" and cause or "document_switch"
    local switchOptions = type(options) == "table" and options or {}
    local previousDocument = CopyEditorDocument(currentEditorDocument)
    local previousSelection = sem:GetCurrentBossSelectorKey()
    local previousTab = GetActiveEditorTab()
    local previousDocumentBoss = previousDocument and sem.ParseBossSelectorKey and sem:ParseBossSelectorKey(previousDocument.bossKeyText) or nil
    local targetBoss, targetBossKeyText, normalizedTab = ResolveDocumentTarget(sem, targetBossKey, targetTab)
    if not targetBoss or targetBossKeyText == "" then
        return false
    end

    local shouldForceHydrate = ShouldForceDocumentHydrate(refreshCause)
    local isSameDocument = previousDocument
        and previousDocument.bossKeyText == targetBossKeyText
        and previousDocument.tab == normalizedTab

    local flushOK = SemanticTimelineGUI.FlushEditorNow(refreshCause)
    if not flushOK then
        LogPlanEvent("STT_PLAN_SWITCH", {
            prevBossKey = previousDocument and previousDocument.bossKeyText or nil,
            prevTab = previousDocument and previousDocument.tab or nil,
            prevPlanID = previousDocument and previousDocument.planID or nil,
            nextBossKey = targetBossKeyText,
            nextTab = normalizedTab,
            cause = refreshCause,
            result = "blocked",
        })
        return false
    end

    if not isSameDocument and previousDocument then
        SaveViewportState(previousDocument.tab, refreshCause, previousDocument.bossKeyText)
    end

    sem:SetWorkbenchSelection(
        targetBoss.instanceType,
        targetBoss.instanceID,
        targetBoss.encounterID,
        switchOptions
    )
    SetActiveEditorTab(normalizedTab, true)

    local document = sem.GetPlanDocumentForBossTab and sem:GetPlanDocumentForBossTab(targetBoss, normalizedTab) or nil
    if not document and sem.EnsurePlanDocumentForBossTab then
        document = sem:EnsurePlanDocumentForBossTab(targetBoss, normalizedTab)
    end
    if not document then
        local revertSelection = previousDocumentBoss or previousSelection
        if revertSelection then
            sem:SetWorkbenchSelection(
                revertSelection.instanceType,
                revertSelection.instanceID,
                revertSelection.encounterID,
                switchOptions
            )
        end
        SetActiveEditorTab(previousTab, true)
        LogPlanEvent("STT_PLAN_SWITCH", {
            prevBossKey = previousDocument and previousDocument.bossKeyText or nil,
            prevTab = previousDocument and previousDocument.tab or nil,
            prevPlanID = previousDocument and previousDocument.planID or nil,
            nextBossKey = targetBossKeyText,
            nextTab = normalizedTab,
            cause = refreshCause,
            result = "missing_document",
        })
        return false
    end

    if not isSameDocument or shouldForceHydrate then
        if editorBox then
            isEditorHydrating = true
            editorBox:SetText(tostring(document.content or ""))
            isEditorHydrating = false
            isEditorDocumentHydrated = true
            if T.EditorUndo then
                T.EditorUndo:ResetForDocument("init")
            end
        end
        currentEditorDocument = BuildEditorDocumentState(document, sem)
        RestoreViewportState(normalizedTab, refreshCause, document.bossKeyText)
    elseif currentEditorDocument then
        currentEditorDocument.planID = tonumber(document.planID)
        currentEditorDocument.name = tostring(document.name or currentEditorDocument.name or "")
    end

    RefreshDropdowns()
    if not isSameDocument or shouldForceHydrate then
        ResetHorizontalScroll()
    end
    EnsureCurrentRowsLoaded()
    if currentPlanFormat == "trigger" and not GetSelectedSpellRow() then
        for _, row in ipairs(currentRows or {}) do
            if row.rowType == "spell" then
                selectedRowID = row.rowID
                break
            end
        end
    end
    RefreshRows({
        cause = refreshCause,
    })
    RefreshTriggerForm()
    RefreshActionButtonState()
    RefreshEditorModeButtons()
    RefreshResolveSourceSelector()

    return true
end

SwitchEditorTab = function(tab)
    SwitchEditorDocument(nil, tab, "tab_switch")
end

ApplyEditorTextNow = function(source)
    if isEditorHydrating or not editorBox then
        return false
    end

    local sem = ST()
    if not (sem and currentEditorDocument) then
        return false
    end

    local ok, flushResult = FlushCurrentEditorDocument("editor_auto")
    if not ok then
        return false
    end

    if flushResult ~= "saved" then
        return false
    end

    SemanticTimelineGUI.RefreshData("editor_save_refresh", {
        source = source,
    })
    SemanticTimelineGUI.ShowSaveStatus()
    SemanticTimelineGUI.RequestRuntimeReloadAfterSave("editor_save")
    return true
end

ScheduleEditorSave = function()
    if saveTimer then
        saveTimer:Cancel()
        saveTimer = nil
    end

    saveTimer = C_Timer.NewTimer(0.2, function()
        ApplyEditorTextNow()
        saveTimer = nil
    end)
end

function SemanticTimelineGUI.FlushEditorBatchEdit(source)
    if saveTimer then
        saveTimer:Cancel()
        saveTimer = nil
    end
    local cause = source or "batch_edit"
    local refreshed = false
    if ApplyEditorTextNow then
        refreshed = ApplyEditorTextNow(cause)
    end
    if not refreshed then
        RefreshRows({
            force = true,
            cause = cause,
        })
    end
    return true
end

function SemanticTimelineGUI._SplitLinesKeepTrailing(text)
    local lines = {}
    local start = 1
    local len = #text
    while start <= len + 1 do
        local pos = text:find("\n", start, true)
        if not pos then
            lines[#lines + 1] = text:sub(start)
            break
        end
        lines[#lines + 1] = text:sub(start, pos - 1)
        start = pos + 1
    end
    return lines
end

function SemanticTimelineGUI._ReportAliasApplyFail(reason, extra)
    if T and T.debug then
        T.debug("[SpellAlias:Apply] fail reason=" .. tostring(reason) .. (extra and (" " .. extra) or ""))
    end
    if T and T.msg then
        T.msg("技能名改写失败（" .. tostring(reason) .. "），请手动在编辑器里改写源文本")
    end
end

function SemanticTimelineGUI._ApplyHitsToSourceLine(rowData, wantedHits)
    if not (rowData and editorBox and T.SpellAliasScanner) then
        SemanticTimelineGUI._ReportAliasApplyFail("no_prereq")
        return false
    end
    local sem = ST()
    if not (sem and sem.GetCurrentPlanLineByRowID) then
        SemanticTimelineGUI._ReportAliasApplyFail("no_sem_api")
        return false
    end
    local lineIdx = sem:GetCurrentPlanLineByRowID(rowData.rowID)
    if not lineIdx then
        SemanticTimelineGUI._ReportAliasApplyFail("no_line_for_row", "rowID=" .. tostring(rowData.rowID))
        return false
    end
    local fullText = editorBox:GetText() or ""
    local lines = SemanticTimelineGUI._SplitLinesKeepTrailing(fullText)
    if lineIdx < 1 or lineIdx > #lines then
        SemanticTimelineGUI._ReportAliasApplyFail("line_out_of_range", "lineIdx=" .. tostring(lineIdx) .. " total=" .. tostring(#lines))
        return false
    end
    local lineText = lines[lineIdx]
    local hitsInLine = T.SpellAliasScanner.Scan(lineText)
    if type(hitsInLine) ~= "table" or #hitsInLine == 0 then
        SemanticTimelineGUI._ReportAliasApplyFail("scan_empty", "lineText=" .. tostring(lineText))
        return false
    end
    -- 只保留 wantedHits 里列出的（word+spellID 双匹配）
    local picked = {}
    local wantedSet = {}
    local wantedDesc = {}
    for i = 1, #wantedHits do
        local w = wantedHits[i]
        wantedSet[w.word .. "|" .. tostring(w.spellID)] = true
        wantedDesc[#wantedDesc + 1] = w.word .. ":" .. tostring(w.spellID)
    end
    local hitsDesc = {}
    for i = 1, #hitsInLine do
        local h = hitsInLine[i]
        hitsDesc[#hitsDesc + 1] = h.word .. ":" .. tostring(h.spellID)
        if wantedSet[h.word .. "|" .. tostring(h.spellID)] then
            picked[#picked + 1] = h
        end
    end
    if #picked == 0 then
        SemanticTimelineGUI._ReportAliasApplyFail("picked_empty",
            "wanted=[" .. table.concat(wantedDesc, ",") .. "] hitsInLine=[" .. table.concat(hitsDesc, ",") .. "] lineText=" .. tostring(lineText))
        return false
    end
    local newLine = T.SpellAliasScanner.ApplyReplacements(lineText, picked)
    if newLine == lineText then
        SemanticTimelineGUI._ReportAliasApplyFail("no_change", "lineText=" .. tostring(lineText))
        return false
    end
    lines[lineIdx] = newLine
    SemanticTimelineGUI.PreserveEditorViewportDuringTextReplace(table.concat(lines, "\n"), editorBox:GetCursorPosition(), "spell_alias_apply")
    -- 接受是主动动作，不走 200ms 防抖——立即 flush + refresh，玩家能马上看到 icon 消失
    if ApplyEditorTextNow then
        ApplyEditorTextNow()
    else
        ScheduleEditorSave()
    end
    if T and T.debug then
        T.debug("[SpellAlias:Apply] ok lineIdx=" .. tostring(lineIdx) .. " replaced=" .. tostring(#picked))
    end
    return true
end

function SemanticTimelineGUI.ApplyAliasReplacement(rowData, hit)
    if not hit then
        return
    end
    SemanticTimelineGUI._ApplyHitsToSourceLine(rowData, { hit })
end

function SemanticTimelineGUI.ApplyAliasReplacementBatch(rowData, hits)
    if type(hits) ~= "table" or #hits == 0 then
        return
    end
    SemanticTimelineGUI._ApplyHitsToSourceLine(rowData, hits)
end

HandleReloadTemplate = function()
    local sem = ST()
    if not sem then
        return
    end

    if GetActiveEditorTab() == "personal" then
        return
    end

    local bossKey = sem:GetCurrentBossSelectorKey()
    local reloader = T.SemanticTemplateReload
    local result = reloader and reloader.ReloadTeamPlan and reloader.ReloadTeamPlan(sem, bossKey) or nil
    if not (result and result.ok) then
        return
    end

    if currentEditorDocument then
        currentEditorDocument.loadedDigest = result.digest
    end
    if editorBox then
        isEditorHydrating = true
        editorBox:SetText(result.text or "")
        isEditorHydrating = false
        isEditorDocumentHydrated = true
    end
    SemanticTimelineGUI.RefreshData("reload_template")
    SemanticTimelineGUI.ShowReloadTemplateStatus()
end

function SemanticTimelineGUI.HandleSyncRaidMembers()
    if T.SyncRaid and T.SyncRaid.HandleSemanticEditor then
        T.SyncRaid.HandleSemanticEditor({
            editorBox = editorBox,
            activeTab = GetActiveEditorTab(),
            preserveText = function(text, cursor, cause)
                return SemanticTimelineGUI.PreserveEditorViewportDuringTextReplace(text, cursor, cause)
            end,
            applyEditorText = ApplyEditorTextNow,
        })
        return
    end

    if T.msg then
        T.msg(L["MSG_SYNC_RAID_NOT_READY"] or "专精数据未就绪，请稍候再试")
    end
    if T.debug then
        T.debug("[SyncRaid] module_missing_on_click")
    end
end

HandleSyncMembers = function()
    local sem = ST()
    if not sem then
        return
    end

    if GetActiveEditorTab() == "personal" then
        return
    end

    local note = T.Note
    local bossKey = sem:GetCurrentBossSelectorKey()
    local bossKeyText = bossKey and sem:SerializeBossSelectorKey(bossKey) or nil
    local content = sem:GetCurrentPlanContent()
    if not (note and note.SendSemanticBossToSTT and bossKeyText) then
        return
    end
    local syncButton = T.SemanticTimelineSyncButton
    if syncButton and syncButton.SetStatus then
        syncButton:SetStatus("sending")
    end
    note:SendSemanticBossToSTT(bossKeyText, content, {
        onProgress = function(sent, total)
            if syncButton and syncButton.SetStatus then
                syncButton:SetStatus("sending", sent, total)
            end
        end,
        onComplete = function()
            if syncButton and syncButton.SetStatus then
                syncButton:SetStatus("complete")
            end
        end,
        onTimeout = function()
            if syncButton and syncButton.SetStatus then
                syncButton:SetStatus("timeout")
            end
        end,
        onDuplicate = function()
            if syncButton and syncButton.SetStatus then
                syncButton:SetStatus("in_progress")
            end
        end,
        onSendFailed = function()
            if syncButton and syncButton.SetStatus then
                syncButton:SetStatus("failed")
            end
        end,
    })
end

function SemanticTimelineGUI.CreateVerticalHorizontalScrollBar(parent, left)
    hScrollBar = T.CreateHorizontalScrollBar(parent, {
        height = HSCROLL_BAR_HEIGHT,
        getRange = function()
            return GetHorizontalScrollRange()
        end,
        getOffset = function()
            return globalHorizontalOffset
        end,
        getPageSize = function()
            return GetCellClipWidth()
        end,
        setOffset = function(value)
            SetHorizontalOffset(value)
        end,
        scrollToOffset = function(value)
            ScrollHorizontalTo(value)
        end,
        stopOffset = function()
            StopHorizontalScroll()
        end,
    })
    hScrollBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT",
        left + TIME_COLUMN_WIDTH + ROW_SIDE_PADDING + 4, HSCROLL_BAR_BOTTOM_OFFSET)
    hScrollBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, HSCROLL_BAR_BOTTOM_OFFSET)
    hScrollBar:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
end

CreateRows = function(parent, left, top)
    local ui = GetTimelineUIConfig()
    rowsScroll = T.CreateVirtualScroll(parent, {
        rowHeight = ui.rowHeight,
        stepSize = ui.rowHeight * 3,
        rowBuffer = 1,
    })
    rowsScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    rowsScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2,
        -(HSCROLL_BAR_BOTTOM_OFFSET + HSCROLL_BAR_HEIGHT + HSCROLL_BAR_TOP_GAP))
    local rowsScroll_OnMouseWheel_Original = rowsScroll.OnMouseWheel
    rowsScroll.OnMouseWheel = function(self, delta)
        RouteTimelineMouseWheel(delta, function(nextDelta)
            if rowsScroll_OnMouseWheel_Original then
                rowsScroll_OnMouseWheel_Original(self, nextDelta)
            end
        end)
    end
    rowsScroll:SetRowFactory(function(scrollParent)
        return CreateTimelineRowFrame(scrollParent)
    end)
    rowsScroll:SetViewRefreshCallback(function()
        ReleaseAllCells()
    end)
    rowsScroll:SetRenderCallback(function(row, dataIndex)
        RenderTimelineRow(row, dataIndex)
    end)
    SemanticTimelineGUI.CreateVerticalHorizontalScrollBar(parent, left)
end

function SemanticTimelineGUI.FadeFrameIn(frame)
    if not frame then
        return
    end
    frame:Show()
    if UIFrameFadeIn then
        frame:SetAlpha(0)
        UIFrameFadeIn(frame, 0.3, 0, 1)
    else
        frame:SetAlpha(1)
    end
end

function SemanticTimelineGUI.FadeFrameOut(frame)
    if not frame then
        return
    end
    if UIFrameFadeOut then
        UIFrameFadeOut(frame, 0.3, frame:GetAlpha() or 1, 0)
        C_Timer.After(0.3, function()
            if frame and frame:GetAlpha() <= 0.05 then
                frame:Hide()
                frame:SetAlpha(1)
            end
        end)
    else
        frame:Hide()
        frame:SetAlpha(1)
    end
end

function SemanticTimelineGUI.GetModeFrame(mode)
    mode = SemanticTimelineGUI.NormalizeLeftMode(mode)
    if mode == "horizontal" then
        return horizontalTimeline and horizontalTimeline.root or nil
    end
    return verticalViewFrame
end

function SemanticTimelineGUI.SetLeftMode(mode)
    local normalized = SemanticTimelineGUI.NormalizeLeftMode(mode)
    local ui = SemanticTimelineGUI.EnsureTimelineUIPreferences()
    if not ui then
        return
    end

    local previous = SemanticTimelineGUI.GetActiveLeftMode()
    ui.viewMode = normalized
    currentLeftMode = normalized
    ApplyDividerRatio(SemanticTimelineGUI.GetActiveDividerRatio())
    SemanticTimelineGUI.RefreshViewModeSelector()
    if SemanticTimelineGUI.transportDock then
        SemanticTimelineGUI.transportDock:SetShown(normalized == "horizontal")
    end

    local previousFrame = SemanticTimelineGUI.GetModeFrame(previous)
    local nextFrame = SemanticTimelineGUI.GetModeFrame(normalized)
    if previous ~= normalized then
        SemanticTimelineGUI.FadeFrameOut(previousFrame)
        SemanticTimelineGUI.FadeFrameIn(nextFrame)
        LogPlanEvent("STT_TIMELINE_VIEW_SWITCH", {
            bossKey = GetCurrentBossKeyText(),
            tab = GetActiveEditorTab(),
            prevMode = previous,
            nextMode = normalized,
        })
    elseif nextFrame then
        nextFrame:Show()
    end

    RefreshRows({
        force = true,
        cause = "view_mode_switch",
    })
end

function SemanticTimelineGUI.GetLeftPanel()
    return leftPanelFrame
end

function SemanticTimelineGUI.GetTextEditor()
    return editorBox
end

local function PrepareHorizontalSkillContext(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    if ctx.kind == "header" then
        ctx.editorTab = NormalizeEditorTab(ctx.editorTab or GetActiveEditorTab())
        return ctx
    end
    local detect = T.SkillPickerLogic and T.SkillPickerLogic.DetectRowKind(ctx.who, {
        meta = ctx.meta,
        class = ctx.class,
    }) or { kind = "generic" }
    ctx.kind = detect.kind or "generic"
    ctx.class = detect.class or ctx.class
    ctx.bossID = detect.bossID or ctx.bossID
    ctx.editorTab = NormalizeEditorTab(ctx.editorTab or GetActiveEditorTab())
    return ctx
end

function SemanticTimelineGUI.ResolveHorizontalContextAtCursor()
    if not (horizontalTimeline and horizontalTimeline.ResolveContextAtCursor) then
        return nil
    end
    return PrepareHorizontalSkillContext(horizontalTimeline:ResolveContextAtCursor())
end

function SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead(ctx)
    if not (horizontalTimeline and horizontalTimeline.ResolveContextAtPlayhead) then
        return nil
    end
    return PrepareHorizontalSkillContext(horizontalTimeline:ResolveContextAtPlayhead(ctx))
end

function SemanticTimelineGUI.SetEditFeedback(text, key, seconds)
    if horizontalTimeline and horizontalTimeline.SetEditFeedback then
        horizontalTimeline:SetEditFeedback(text, key, seconds)
        return
    end
    if SemanticTimelineGUI.SetStatus then
        SemanticTimelineGUI.SetStatus(text, key)
    end
end

function SemanticTimelineGUI.PreviewHorizontalExternalSkillDrag(payload)
    if not (horizontalTimeline and horizontalTimeline.PreviewExternalSkillDrag) then
        return nil
    end
    return PrepareHorizontalSkillContext(horizontalTimeline:PreviewExternalSkillDrag(payload))
end

function SemanticTimelineGUI.ClearHorizontalExternalSkillDragPreview(reason)
    if horizontalTimeline and horizontalTimeline.ClearExternalSkillDragPreview then
        horizontalTimeline:ClearExternalSkillDragPreview(reason)
    end
end

function SemanticTimelineGUI.HandleHorizontalContextMenu(ctx)
    ctx = PrepareHorizontalSkillContext(ctx)
    if not ctx then
        return
    end

    local x, y = GetCursorPosition()
    if T.TimelineContextMenu then
        T.TimelineContextMenu.Show({ x = x, y = y }, ctx)
    end
    if LogPlanEvent then
        LogPlanEvent("STT_SKILL_CONTEXT_MENU", {
            bossKey = GetCurrentBossKeyText(),
            tab = ctx.editorTab,
            row = ctx.who,
            kind = ctx.kind,
            time = string.format("%.1f", tonumber(ctx.time) or 0),
        })
    end
end

SemanticTimelineGUI._segmentMove = SemanticTimelineGUI._segmentMove or {}

function SemanticTimelineGUI._segmentMove.Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

function SemanticTimelineGUI._segmentMove.HasSource(item)
    return type(item) == "table" and SemanticTimelineGUI._segmentMove.Trim(item.sourceSegmentText) ~= ""
end

function SemanticTimelineGUI._segmentMove.SplitPlayers(text)
    local players = {}
    for name in tostring(text or ""):gmatch("[^\n]+") do
        local normalized = SemanticTimelineGUI._segmentMove.Trim(name)
        if normalized ~= "" then
            players[#players + 1] = normalized
        end
    end
    return players
end

function SemanticTimelineGUI._segmentMove.SerializeSegment(segment)
    if type(segment) ~= "table" then
        return ""
    end
    local parts = {}
    local condition = SemanticTimelineGUI._segmentMove.Trim(segment.condition)
    if condition ~= "" then
        parts[#parts + 1] = "{" .. condition .. "}"
    end
    for _, name in ipairs(type(segment.players) == "table" and segment.players or {}) do
        local normalized = SemanticTimelineGUI._segmentMove.Trim(name)
        if normalized ~= "" then
            parts[#parts + 1] = "{" .. normalized .. "}"
        end
    end
    parts[#parts + 1] = SemanticTimelineGUI._segmentMove.Trim(segment.rawText or segment.cellText or segment.text)
    return table.concat(parts)
end

function SemanticTimelineGUI._segmentMove.IsSourceAudienceToken(token)
    local value = SemanticTimelineGUI._segmentMove.Trim(token)
    if value == "" then
        return false
    end
    local name = value:match("^([%w_]+)%s*:")
    if value:match("^spell:%d+") then
        return false
    end
    if value:sub(1, 1) == "@" then
        return false
    end
    if name and T.InlineModifier and type(T.InlineModifier.KNOWN) == "table" and T.InlineModifier.KNOWN[name] then
        return false
    end
    return true
end

function SemanticTimelineGUI._segmentMove.SplitSourceSegments(line)
    local content = tostring(line or ""):gsub("{time:[^}]+}", "", 1)
    local segments = {}
    local currentStart = nil
    local currentHasBody = false
    local pendingAudienceStart = nil
    local pos = 1

    local function Push(endPos)
        if currentStart and currentHasBody then
            local text = SemanticTimelineGUI._segmentMove.Trim(content:sub(currentStart, endPos))
            if text ~= "" then
                segments[#segments + 1] = text
            end
        end
        currentStart = nil
        currentHasBody = false
        pendingAudienceStart = nil
    end

    while true do
        local b, e = content:find("%b{}", pos)
        if not b then
            if currentStart then
                if SemanticTimelineGUI._segmentMove.Trim(content:sub(pos)) ~= "" then
                    currentHasBody = true
                end
                Push(#content)
            end
            break
        end

        if currentStart and SemanticTimelineGUI._segmentMove.Trim(content:sub(pos, b - 1)) ~= "" then
            currentHasBody = true
        elseif pendingAudienceStart and SemanticTimelineGUI._segmentMove.Trim(content:sub(pos, b - 1)) ~= "" then
            currentStart = pendingAudienceStart
            currentHasBody = true
            pendingAudienceStart = nil
        end

        local token = content:sub(b + 1, e - 1)
        if SemanticTimelineGUI._segmentMove.IsSourceAudienceToken(token) then
            if currentStart and currentHasBody then
                Push(b - 1)
            end
            if not pendingAudienceStart then
                pendingAudienceStart = b
            end
        else
            if not currentStart then
                currentStart = pendingAudienceStart or b
                pendingAudienceStart = nil
            end
            currentHasBody = true
        end
        pos = e + 1
    end

    return segments
end

function SemanticTimelineGUI._segmentMove.BuildAudienceSource(audience)
    local parts = {}
    if SemanticTimelineGUI._segmentMove.AppendAudienceParts(parts, audience) then
        return table.concat(parts)
    end
    return ""
end

function SemanticTimelineGUI._segmentMove.ReplaceSourceAudience(segmentText, audience)
    local body = tostring(segmentText or "")
    local audienceText = SemanticTimelineGUI._segmentMove.BuildAudienceSource(audience)
    if audienceText == "" then
        return SemanticTimelineGUI._segmentMove.Trim(body)
    end

    local pos = 1
    while true do
        local prefixEnd = body:find("%S", pos)
        if not prefixEnd then
            return audienceText
        end
        local b, e = body:find("%b{}", prefixEnd)
        if b ~= prefixEnd then
            return audienceText .. SemanticTimelineGUI._segmentMove.Trim(body:sub(prefixEnd))
        end
        local token = body:sub(b + 1, e - 1)
        if not SemanticTimelineGUI._segmentMove.IsSourceAudienceToken(token) then
            return audienceText .. SemanticTimelineGUI._segmentMove.Trim(body:sub(b))
        end
        pos = e + 1
    end
end

function SemanticTimelineGUI._segmentMove.AppendAudienceParts(parts, audience)
    if type(parts) ~= "table" or type(audience) ~= "table" then
        return false
    end
    local condition = SemanticTimelineGUI._segmentMove.Trim(audience.condition)
    if condition ~= "" then
        parts[#parts + 1] = "{" .. condition .. "}"
    end
    for _, name in ipairs(type(audience.players) == "table" and audience.players or {}) do
        local normalized = SemanticTimelineGUI._segmentMove.Trim(name)
        if normalized ~= "" then
            parts[#parts + 1] = "{" .. normalized .. "}"
        end
    end
    if condition == "" and #parts == 0 then
        local who = SemanticTimelineGUI._segmentMove.Trim(audience.who)
        if who ~= "" then
            parts[#parts + 1] = "{" .. who .. "}"
        end
    end
    return #parts > 0
end

function SemanticTimelineGUI._segmentMove.SerializeItem(item, opts)
    local parts = {}
    local targetAudience = type(opts) == "table" and opts.targetAudience or nil
    if not SemanticTimelineGUI._segmentMove.AppendAudienceParts(parts, targetAudience) then
        local condition = SemanticTimelineGUI._segmentMove.Trim(item and item.sourceCondition)
        if condition ~= "" then
            parts[#parts + 1] = "{" .. condition .. "}"
        end
        for _, name in ipairs(SemanticTimelineGUI._segmentMove.SplitPlayers(item and item.sourcePlayersText)) do
            parts[#parts + 1] = "{" .. name .. "}"
        end
        if #parts == 0 and item and item.targetKind == "player" then
            local who = SemanticTimelineGUI._segmentMove.Trim(item.who)
            if who ~= "" then
                parts[#parts + 1] = "{" .. who .. "}"
            end
        end
    end

    local body = SemanticTimelineGUI._segmentMove.Trim(item and item.sourceSegmentText)
    if body == "" then
        body = SemanticTimelineGUI._segmentMove.Trim(item and item.fullText)
    end
    if body ~= "" then
        parts[#parts + 1] = body
    end
    return table.concat(parts)
end

function SemanticTimelineGUI._segmentMove.BuildLine(timePayload, content)
    local body = SemanticTimelineGUI._segmentMove.Trim(content)
    if body == "" then
        return nil
    end
    return "{time:" .. tostring(timePayload or "00:00") .. "} " .. body
end

function SemanticTimelineGUI._segmentMove.SplitLines(text)
    local lines = {}
    for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    if #lines > 0 and lines[#lines] == "" then
        lines[#lines] = nil
    end
    return lines
end

function SemanticTimelineGUI._segmentMove.GetLineTime(line)
    local syntax = T.TimelineSyntax
    if not (syntax and syntax.ParseTimelineLine) then
        return nil
    end
    local parsed = syntax.ParseTimelineLine(line or "")
    return parsed and tonumber(parsed.time) or nil
end

function SemanticTimelineGUI._segmentMove.FindTimeBlock(lines, lineNum)
    local index = tonumber(lineNum)
    if not (type(lines) == "table" and index and index > 0 and lines[index]) then
        return index or 1, index or 1
    end
    if not SemanticTimelineGUI._segmentMove.GetLineTime(lines[index]) then
        return index, index
    end

    local first = index
    while first > 1 and SemanticTimelineGUI._segmentMove.GetLineTime(lines[first - 1]) do
        first = first - 1
    end

    local last = index
    while last < #lines and SemanticTimelineGUI._segmentMove.GetLineTime(lines[last + 1]) do
        last = last + 1
    end

    return first, last
end

function SemanticTimelineGUI._segmentMove.SortTimeBlock(lines, blockStart, blockEnd)
    local startIndex = tonumber(blockStart) or 1
    local endIndex = tonumber(blockEnd) or (startIndex - 1)
    if not (type(lines) == "table" and startIndex > 0 and endIndex > startIndex) then
        return
    end

    local entries = {}
    for index = startIndex, endIndex do
        entries[#entries + 1] = {
            line = lines[index],
            seconds = SemanticTimelineGUI._segmentMove.GetLineTime(lines[index]) or 0,
        }
    end

    for index = 2, #entries do
        local current = entries[index]
        local cursor = index - 1
        while cursor >= 1 and entries[cursor].seconds > current.seconds do
            entries[cursor + 1] = entries[cursor]
            cursor = cursor - 1
        end
        entries[cursor + 1] = current
    end

    for offset, entry in ipairs(entries) do
        lines[startIndex + offset - 1] = entry.line
    end
end

function SemanticTimelineGUI._segmentMove.InsertLineByTime(lines, blockStart, blockEnd, line, seconds)
    local targetSeconds = tonumber(seconds) or 0
    local startIndex = math.max(1, tonumber(blockStart) or 1)
    local endIndex = tonumber(blockEnd) or (startIndex - 1)
    local insertAt = math.max(startIndex, endIndex + 1)

    for index = startIndex, endIndex do
        local lineSeconds = SemanticTimelineGUI._segmentMove.GetLineTime(lines[index])
        if lineSeconds and lineSeconds > targetSeconds then
            insertAt = index
            break
        end
    end

    table.insert(lines, insertAt, line)
    return insertAt
end

function SemanticTimelineGUI._segmentMove.GetLineStartOffset(lines, lineNum)
    local target = tonumber(lineNum) or 1
    local offset = 0
    for index = 1, math.max(1, target) - 1 do
        offset = offset + #(lines[index] or "") + 1
    end
    return offset
end

function SemanticTimelineGUI._segmentMove.GetLineTimeCaret(lines, lineNum)
    local offset = SemanticTimelineGUI._segmentMove.GetLineStartOffset(lines, lineNum)
    local line = lines[tonumber(lineNum) or 1] or ""
    local tokenStart, tokenEnd = line:find("{time:[^}]+}")
    if tokenStart and tokenEnd then
        return offset + tokenEnd
    end
    return offset
end

function SemanticTimelineGUI._segmentMove.FindSegmentIndex(segments, item)
    local preferred = tonumber(item and item.sourceSegmentIndex)
    if preferred and type(segments[preferred]) == "table" then
        local segment = segments[preferred]
        local preferredRaw = SemanticTimelineGUI._segmentMove.Trim(segment.rawText or segment.cellText or segment.text)
        local targetRaw = SemanticTimelineGUI._segmentMove.Trim(item and item.sourceSegmentText)
        local preferredSpellID = tonumber(segment.primarySpellID)
        local targetSpellID = tonumber(item and item.spellID)
        if (targetRaw ~= "" and preferredRaw == targetRaw) or (targetSpellID and preferredSpellID == targetSpellID) then
            return preferred
        end
    end
    local targetSpellID = tonumber(item and item.spellID)
    local targetRaw = SemanticTimelineGUI._segmentMove.Trim(item and item.sourceSegmentText)
    for index, segment in ipairs(segments or {}) do
        local raw = SemanticTimelineGUI._segmentMove.Trim(segment.rawText or segment.cellText or segment.text)
        local spellID = tonumber(segment.primarySpellID)
        if (targetSpellID and spellID == targetSpellID) or (targetRaw ~= "" and raw == targetRaw) then
            return index
        end
    end
    return nil
end

function SemanticTimelineGUI._segmentMove.ReplaceText(newText, caretPos, source, opts)
    if T.EditorUndo and T.EditorUndo.ReplaceText then
        T.EditorUndo:ReplaceText(newText, caretPos, source, opts)
        return
    end
    editorBox:SetText(newText)
    editorBox:SetCursorPosition(tonumber(caretPos) or 0)
    opts = type(opts) == "table" and opts or {}
    if opts.deferApply == true then
        return
    end
    local refreshed = false
    if ApplyEditorTextNow then
        refreshed = ApplyEditorTextNow(source)
    end
    if not refreshed then
        RefreshRows({
            force = true,
            cause = source,
        })
    end
end

function SemanticTimelineGUI.InsertTimelineLineByTime(ctx, line, seconds, opts)
    local source = type(opts) == "table" and opts.source or "skill_picker"
    local textLine = SemanticTimelineGUI._segmentMove.Trim(line)
    if textLine == "" then
        return false, "empty_line"
    end
    if not editorBox then
        return false, "editor_not_ready"
    end

    local targetTab = NormalizeEditorTab(ctx and ctx.editorTab or GetActiveEditorTab())
    if targetTab ~= GetActiveEditorTab() then
        SwitchEditorDocument(nil, targetTab, source .. "_tab")
    end

    local lines = SemanticTimelineGUI._segmentMove.SplitLines(editorBox:GetText() or "")
    local insertLine
    if #lines == 0 then
        lines[1] = textLine
        insertLine = 1
    else
        local sourceLineNum = tonumber(ctx and ctx.sourceLineNum)
        local blockStart, blockEnd
        if sourceLineNum and sourceLineNum > 0 and lines[sourceLineNum] then
            blockStart, blockEnd = SemanticTimelineGUI._segmentMove.FindTimeBlock(lines, sourceLineNum)
            if not SemanticTimelineGUI._segmentMove.GetLineTime(lines[blockStart]) then
                blockStart, blockEnd = nil, nil
            end
        end
        if not (blockStart and blockEnd and blockStart <= blockEnd) then
            local index = 1
            while index <= #lines do
                if SemanticTimelineGUI._segmentMove.GetLineTime(lines[index]) then
                    blockStart = index
                    blockEnd = index
                    while blockEnd < #lines and SemanticTimelineGUI._segmentMove.GetLineTime(lines[blockEnd + 1]) do
                        blockEnd = blockEnd + 1
                    end
                    break
                end
                index = index + 1
            end
        end
        if blockStart and blockEnd then
            SemanticTimelineGUI._segmentMove.SortTimeBlock(lines, blockStart, blockEnd)
            insertLine = SemanticTimelineGUI._segmentMove.InsertLineByTime(lines, blockStart, blockEnd, textLine, seconds)
        else
            lines[#lines + 1] = textLine
            insertLine = #lines
        end
    end

    local caretPos = SemanticTimelineGUI._segmentMove.GetLineTimeCaret(lines, insertLine)
    SemanticTimelineGUI._segmentMove.ReplaceText(table.concat(lines, "\n"), caretPos, source)
    if T.debug then
        T.debug(string.format("[STT_SKILL_PICKER_TEXT_INSERT] line=%s time=%.1f sourceLine=%s", tostring(insertLine), tonumber(seconds) or 0, tostring(ctx and ctx.sourceLineNum or "")))
    end
    return true
end

SemanticTimelineGUI._personnelRow = SemanticTimelineGUI._personnelRow or {}

function SemanticTimelineGUI._personnelRow.BuildLine(rowName, mappingName)
    local name = SemanticTimelineGUI._segmentMove.Trim(rowName)
    local value = SemanticTimelineGUI._segmentMove.Trim(mappingName)
    if value == "" then
        return name
    end
    return name .. "=" .. value
end

function SemanticTimelineGUI._personnelRow.HasRealSectionHeader(info, sectionName)
    local section = info and info.sections and info.sections[sectionName] or nil
    local rawLine = section and info.rawLines and info.rawLines[section.headerLine] or nil
    return SemanticTimelineGUI._segmentMove.Trim(rawLine) == "[" .. sectionName .. "]"
end

function SemanticTimelineGUI._personnelRow.FindBodySection(info)
    if not (info and info.sections) then
        return nil
    end
    return info.sections["触发轴"] or info.sections["时间轴"]
end

function SemanticTimelineGUI._personnelRow.InsertSection(lines, info, rowLine)
    local bodySection = SemanticTimelineGUI._personnelRow.FindBodySection(info)
    local insertAt = bodySection and tonumber(bodySection.headerLine) or (#lines + 1)
    table.insert(lines, insertAt, "")
    table.insert(lines, insertAt, rowLine)
    table.insert(lines, insertAt, "[人员]")
    return insertAt + 1
end

function SemanticTimelineGUI._personnelRow.NormalizeSectionSpacing(lines, sectionName)
    local headerLine
    local expectedHeader = "[" .. tostring(sectionName or "") .. "]"
    for index, line in ipairs(lines or {}) do
        if SemanticTimelineGUI._segmentMove.Trim(line) == expectedHeader then
            headerLine = index
            break
        end
    end
    if not headerLine then
        return
    end

    local nextHeaderLine
    for index = headerLine + 1, #lines do
        if SemanticTimelineGUI._segmentMove.Trim(lines[index]):match("^%[[^%]]+%]$") then
            nextHeaderLine = index
            break
        end
    end

    local sectionEnd = (nextHeaderLine or (#lines + 1)) - 1
    local firstContentLine
    local lastContentLine
    for index = headerLine + 1, sectionEnd do
        if SemanticTimelineGUI._segmentMove.Trim(lines[index]) ~= "" then
            firstContentLine = firstContentLine or index
            lastContentLine = index
        end
    end
    if not firstContentLine then
        return
    end

    while firstContentLine > headerLine + 1 do
        table.remove(lines, headerLine + 1)
        firstContentLine = firstContentLine - 1
        lastContentLine = lastContentLine - 1
        if nextHeaderLine then
            nextHeaderLine = nextHeaderLine - 1
        end
    end

    if nextHeaderLine then
        local cursor = lastContentLine + 1
        while cursor < nextHeaderLine do
            table.remove(lines, cursor)
            nextHeaderLine = nextHeaderLine - 1
        end
        table.insert(lines, cursor, "")
    end
end

function SemanticTimelineGUI._personnelRow.UpsertIconLine(lines, info, rowName, specID)
    local section = info and info.sections and info.sections["人员图标"] or nil
    local targetName = SemanticTimelineGUI._segmentMove.Trim(rowName)
    local id = tonumber(specID)
    local shouldWrite = id and id > 0
    local startLine = section and ((tonumber(section.headerLine) or 0) + 1) or nil
    local endLine = section and (tonumber(section.lastLine) or (startLine - 1)) or nil

    if section then
        for lineNumber = endLine, startLine, -1 do
            local key = SemanticTimelineGUI._segmentMove.Trim(tostring(lines[lineNumber] or ""):match("^%s*([^=]+)%s*="))
            if key == targetName then
                if shouldWrite then
                    lines[lineNumber] = targetName .. "=" .. tostring(math.floor(id + 0.5))
                else
                    table.remove(lines, lineNumber)
                end
                return
            end
        end
        if shouldWrite then
            table.insert(lines, endLine + 1, targetName .. "=" .. tostring(math.floor(id + 0.5)))
        end
        return
    end

    if not shouldWrite then
        return
    end

    local personnelSection = info and info.sections and info.sections["人员"] or nil
    local insertAt = personnelSection and ((tonumber(personnelSection.lastLine) or tonumber(personnelSection.headerLine) or 0) + 1) or (#lines + 1)
    table.insert(lines, insertAt, "")
    table.insert(lines, insertAt + 1, "[人员图标]")
    table.insert(lines, insertAt + 2, targetName .. "=" .. tostring(math.floor(id + 0.5)))
end

function SemanticTimelineGUI._personnelRow.FindKeyLine(info, lines, sectionName, keyName)
    local section = info and info.sections and info.sections[sectionName] or nil
    if not section then
        return nil
    end
    local targetName = SemanticTimelineGUI._segmentMove.Trim(keyName)
    local startLine = (tonumber(section.headerLine) or 0) + 1
    local endLine = tonumber(section.lastLine) or startLine - 1
    for lineNumber = startLine, endLine do
        local line = tostring(lines[lineNumber] or "")
        local rawKey = line:match("^%s*([^=]+)%s*=") or line
        local key = SemanticTimelineGUI._segmentMove.Trim(rawKey)
        if key == targetName then
            return lineNumber
        end
    end
    return nil
end

function SemanticTimelineGUI._personnelRow.RenameBodyTargets(lines, info, oldRowName, newRowName)
    local oldName = SemanticTimelineGUI._segmentMove.Trim(oldRowName)
    local newName = SemanticTimelineGUI._segmentMove.Trim(newRowName)
    if oldName == "" or newName == "" or oldName == newName then
        return
    end
    local bodySection = SemanticTimelineGUI._personnelRow.FindBodySection(info)
    if not bodySection then
        return
    end
    local lineNumbers = bodySection.lineNumbers
    if type(lineNumbers) ~= "table" or #lineNumbers == 0 then
        local startLine = (tonumber(bodySection.headerLine) or 0) + 1
        local endLine = tonumber(bodySection.lastLine) or startLine - 1
        lineNumbers = {}
        for lineNumber = startLine, endLine do
            lineNumbers[#lineNumbers + 1] = lineNumber
        end
    end
    for _, lineNumber in ipairs(lineNumbers) do
        local line = tostring(lines[lineNumber] or "")
        line = line:gsub("{{(.-)}}", function(raw)
            if SemanticTimelineGUI._segmentMove.Trim(raw) == oldName then
                return "{{" .. newName .. "}}"
            end
            return "{{" .. raw .. "}}"
        end)
        line = line:gsub("{([^{}]+)}", function(raw)
            if SemanticTimelineGUI._segmentMove.Trim(raw) == oldName then
                return "{" .. newName .. "}"
            end
            return "{" .. raw .. "}"
        end)
        lines[lineNumber] = line
    end
end

function SemanticTimelineGUI.GetPersonnelRow(rowName)
    if not editorBox then
        return nil
    end
    local name = SemanticTimelineGUI._segmentMove.Trim(rowName)
    if name == "" then
        return nil
    end
    local preprocess = T.STNTemplate and T.STNTemplate.PreprocessText
    local info = preprocess and preprocess(editorBox:GetText() or "", { relaxed = true }) or nil
    if not (info and info.slots and info.slots[name] ~= nil) then
        return nil
    end
    return {
        rowName = name,
        mappingName = tostring(info.slots[name] or ""),
        specID = info.slotVisualSpecs and tonumber(info.slotVisualSpecs[name]) or nil,
    }
end

function SemanticTimelineGUI.UpsertPersonnelRow(opts)
    opts = type(opts) == "table" and opts or {}
    local rowName = SemanticTimelineGUI._segmentMove.Trim(opts.rowName)
    local oldRowName = SemanticTimelineGUI._segmentMove.Trim(opts.oldRowName)
    local isEdit = oldRowName ~= ""
    if rowName == "" then
        return false, "empty_row_name"
    end
    if rowName:find("[=\r\n%[%]{}]") then
        return false, "invalid_row_name"
    end
    local mappingName = SemanticTimelineGUI._segmentMove.Trim(opts.mappingName)
    if mappingName:find("[=\r\n%[%]{}]") then
        return false, "invalid_mapping_name"
    end
    if not editorBox then
        return false, "editor_not_ready"
    end

    local text = editorBox:GetText() or ""
    local preprocess = T.STNTemplate and T.STNTemplate.PreprocessText
    local info = preprocess and preprocess(text, { relaxed = true }) or nil
    local oldRowExists = info and info.slots and oldRowName ~= "" and info.slots[oldRowName] ~= nil
    local editMissingRow = isEdit and not oldRowExists and opts.allowCreateIfMissing == true
    if info and info.slots and info.slots[rowName] ~= nil and rowName ~= oldRowName then
        return false, "duplicate_row_name"
    end

    local newText
    local caretLine = 1
    local rowLine = SemanticTimelineGUI._personnelRow.BuildLine(rowName, mappingName)
    if not (info and info.hasBlocks == true) then
        if isEdit and not editMissingRow then
            return false, "personnel_row_not_found"
        end
        local output = { "[人员]", rowLine }
        local defaultHint = T.ResolveSlotVisualHint and T.ResolveSlotVisualHint(rowName) or nil
        local customSpecID = defaultHint and defaultHint.specID and nil or tonumber(opts.specID)
        if customSpecID and customSpecID > 0 then
            output[#output + 1] = ""
            output[#output + 1] = "[人员图标]"
            output[#output + 1] = rowName .. "=" .. tostring(math.floor(customSpecID + 0.5))
        end
        output[#output + 1] = ""
        output[#output + 1] = "[时间轴]"
        local normalized = tostring(text or ""):gsub("\r\n", "\n")
        if SemanticTimelineGUI._segmentMove.Trim(normalized) ~= "" then
            for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
                if editMissingRow and oldRowName ~= rowName then
                    line = line:gsub("{{(.-)}}", function(raw)
                        if SemanticTimelineGUI._segmentMove.Trim(raw) == oldRowName then
                            return "{{" .. rowName .. "}}"
                        end
                        return "{{" .. raw .. "}}"
                    end)
                    line = line:gsub("{([^{}]+)}", function(raw)
                        if SemanticTimelineGUI._segmentMove.Trim(raw) == oldRowName then
                            return "{" .. rowName .. "}"
                        end
                        return "{" .. raw .. "}"
                    end)
                end
                output[#output + 1] = line
            end
        end
        newText = table.concat(output, "\n")
        caretLine = 2
    else
        local lines = SemanticTimelineGUI._segmentMove.SplitLines(text)
        local personnelSection = info.sections and info.sections["人员"] or nil
        if isEdit and oldRowExists then
            caretLine = SemanticTimelineGUI._personnelRow.FindKeyLine(info, lines, "人员", oldRowName)
            if not caretLine then
                return false, "personnel_row_not_found"
            end
            lines[caretLine] = rowLine
        elseif editMissingRow then
            if not personnelSection or not SemanticTimelineGUI._personnelRow.HasRealSectionHeader(info, "人员") then
                caretLine = SemanticTimelineGUI._personnelRow.InsertSection(lines, info, rowLine)
            else
                caretLine = (tonumber(personnelSection.lastLine) or tonumber(personnelSection.headerLine) or 0) + 1
                table.insert(lines, caretLine, rowLine)
            end
        elseif not personnelSection or not SemanticTimelineGUI._personnelRow.HasRealSectionHeader(info, "人员") then
            caretLine = SemanticTimelineGUI._personnelRow.InsertSection(lines, info, rowLine)
        else
            caretLine = (tonumber(personnelSection.lastLine) or tonumber(personnelSection.headerLine) or 0) + 1
            table.insert(lines, caretLine, rowLine)
        end

        local defaultHint = T.ResolveSlotVisualHint and T.ResolveSlotVisualHint(rowName) or nil
        local customSpecID = defaultHint and defaultHint.specID and nil or tonumber(opts.specID)
        local nextInfo = preprocess and preprocess(table.concat(lines, "\n"), { relaxed = true }) or nil
        if isEdit and oldRowName ~= rowName then
            SemanticTimelineGUI._personnelRow.RenameBodyTargets(lines, nextInfo, oldRowName, rowName)
            nextInfo = preprocess and preprocess(table.concat(lines, "\n"), { relaxed = true }) or nil
            SemanticTimelineGUI._personnelRow.UpsertIconLine(lines, nextInfo, oldRowName, nil)
            nextInfo = preprocess and preprocess(table.concat(lines, "\n"), { relaxed = true }) or nil
        end
        SemanticTimelineGUI._personnelRow.UpsertIconLine(lines, nextInfo, rowName, customSpecID)
        SemanticTimelineGUI._personnelRow.NormalizeSectionSpacing(lines, "人员")
        SemanticTimelineGUI._personnelRow.NormalizeSectionSpacing(lines, "人员图标")
        newText = table.concat(lines, "\n")
    end

    local linesForCaret = SemanticTimelineGUI._segmentMove.SplitLines(newText)
    local caretPos = SemanticTimelineGUI._segmentMove.GetLineStartOffset(linesForCaret, caretLine)
    if T.EditorUndo and T.EditorUndo.ReplaceText then
        T.EditorUndo:ReplaceText(newText, caretPos, "personnel_row_editor")
    else
        editorBox:SetText(newText)
        editorBox:SetCursorPosition(caretPos)
        if ApplyEditorTextNow then
            ApplyEditorTextNow("personnel_row_editor")
        else
            RefreshRows({
                force = true,
                cause = "personnel_row_editor",
            })
        end
    end
    local feedback = isEdit and (L["PERSONNEL_ROW_EDITOR_UPDATED"] or "已更新人员行：%s") or (L["PERSONNEL_ROW_EDITOR_ADDED"] or "已新增人员行：%s")
    SemanticTimelineGUI.SetEditFeedback(string.format(feedback, rowName), isEdit and "personnel_row_updated" or "personnel_row_added")
    return true
end

function SemanticTimelineGUI._segmentMove.FormatTimelineTime(seconds)
    local value = math.max(0, tonumber(seconds) or 0)
    local rounded = math.floor(value + 0.5)
    return string.format("%d:%02d", math.floor(rounded / 60), rounded % 60)
end

function SemanticTimelineGUI._segmentMove.ResolveEditorLineForContext(ctx, source)
    if type(ctx) ~= "table" then
        return nil, "missing_context"
    end
    if not editorBox then
        return nil, "editor_not_ready"
    end

    local targetTab = NormalizeEditorTab(ctx.editorTab or GetActiveEditorTab())
    if targetTab ~= GetActiveEditorTab() then
        SwitchEditorDocument(nil, targetTab, (source or "context_menu") .. "_tab")
    end

    local lineNum = tonumber(ctx.sourceLineNum)
    local sem = ST()
    if (not lineNum or lineNum <= 0) and sem and ctx.rowID and sem.GetPlanLineByRowIDForTab then
        lineNum = tonumber(sem:GetPlanLineByRowIDForTab(targetTab, ctx.rowID))
    end
    if not lineNum or lineNum <= 0 then
        return nil, "missing_line"
    end

    local lines = SemanticTimelineGUI._segmentMove.SplitLines(editorBox:GetText() or "")
    local line = lines[lineNum]
    if not line then
        return nil, "missing_line"
    end
    return {
        lines = lines,
        lineNum = lineNum,
        line = line,
        targetTab = targetTab,
    }
end

function SemanticTimelineGUI.CopyTimelineLineForContext(ctx)
    local resolved, reason = SemanticTimelineGUI._segmentMove.ResolveEditorLineForContext(ctx, "context_menu_copy")
    if not resolved then
        return false, reason
    end

    local parsed = T.TimelineSyntax and T.TimelineSyntax.ParseTimelineLine and T.TimelineSyntax.ParseTimelineLine(resolved.line) or nil
    local modifierDur = parsed and parsed.modifiers and parsed.modifiers.dur and parsed.modifiers.dur.value or nil
    local spellID = tonumber(ctx and ctx.spellID) or tonumber(parsed and parsed.primarySpellID)
    local dur = tonumber(ctx and ctx.dur) or tonumber(modifierDur) or tonumber(tostring(resolved.line):match("dur:([%d%.]+)"))
    local name = spellID and T.SkillPickerLogic and T.SkillPickerLogic.GetSpellName and T.SkillPickerLogic.GetSpellName(spellID) or nil
    local line = resolved.line
    local item = ctx and ctx.item
    if parsed and item and SemanticTimelineGUI._segmentMove.HasSource(item) then
        local payload = SemanticTimelineGUI._segmentMove.Trim((resolved.line or ""):match("{time:([^}]+)}"))
        if payload == "" then
            payload = SemanticTimelineGUI._segmentMove.FormatTimelineTime(item.time or ctx.time)
        end
        local content = SemanticTimelineGUI._segmentMove.SerializeItem(item)
        line = SemanticTimelineGUI._segmentMove.BuildLine(payload, content) or line
    end

    return true, {
        line = line,
        lineNum = resolved.lineNum,
        spellID = spellID,
        dur = dur,
        name = name,
        time = tonumber(item and item.time) or tonumber(ctx and ctx.time) or tonumber(parsed and parsed.time) or 0,
    }
end

function SemanticTimelineGUI.DeleteTimelineLineForContext(ctx, source)
    local resolved, reason = SemanticTimelineGUI._segmentMove.ResolveEditorLineForContext(ctx, source or "context_menu_delete")
    if not resolved then
        return false, reason
    end

    local parsed = T.TimelineSyntax and T.TimelineSyntax.ParseTimelineLine and T.TimelineSyntax.ParseTimelineLine(resolved.line) or nil
    local item = ctx and ctx.item
    if parsed and item and SemanticTimelineGUI._segmentMove.HasSource(item) and type(parsed.segments) == "table" and #parsed.segments > 1 then
        local removeIndex
        local targetRaw = SemanticTimelineGUI._segmentMove.Trim(item.sourceSegmentText)
        local targetSpellID = tonumber(item.spellID)
        for index, segment in ipairs(parsed.segments) do
            local raw = SemanticTimelineGUI._segmentMove.Trim(segment.rawText or segment.cellText or segment.text)
            local spellID = tonumber(segment.primarySpellID)
            if (targetRaw ~= "" and raw == targetRaw) or (targetSpellID and spellID == targetSpellID) then
                removeIndex = index
                break
            end
        end
        if not removeIndex then
            removeIndex = SemanticTimelineGUI._segmentMove.FindSegmentIndex(parsed.segments, item)
        end
        if not removeIndex then
            return false, "segment_not_found"
        end
        local remaining = {}
        for index, segment in ipairs(parsed.segments) do
            if index ~= removeIndex then
                remaining[#remaining + 1] = segment
            end
        end
        local payload = SemanticTimelineGUI._segmentMove.Trim((resolved.line or ""):match("{time:([^}]+)}"))
        if payload == "" then
            payload = SemanticTimelineGUI._segmentMove.FormatTimelineTime(item.time or ctx.time)
        end
        local parts = {}
        for _, segment in ipairs(remaining) do
            parts[#parts + 1] = SemanticTimelineGUI._segmentMove.SerializeSegment(segment)
        end
        resolved.lines[resolved.lineNum] = SemanticTimelineGUI._segmentMove.BuildLine(payload, table.concat(parts)) or resolved.line
    else
        table.remove(resolved.lines, resolved.lineNum)
    end
    local caretLine = math.min(resolved.lineNum, #resolved.lines)
    local caretPos = caretLine > 0 and SemanticTimelineGUI._segmentMove.GetLineStartOffset(resolved.lines, caretLine) or 0
    SemanticTimelineGUI._segmentMove.ReplaceText(table.concat(resolved.lines, "\n"), caretPos, source or "context_menu_delete")
    if T.debug then
        T.debug(string.format("[STT_TIMELINE_CONTEXT_DELETE] line=%s source=%s", tostring(resolved.lineNum), tostring(source or "context_menu_delete")))
    end
    return true
end

function SemanticTimelineGUI.PasteTimelineLineForContext(ctx, payload)
    if type(payload) ~= "table" then
        return false, "clipboard_empty"
    end
    if tonumber(payload.spellID) and T.SkillPickerLogic and T.SkillPickerLogic.InsertSkillToken then
        return T.SkillPickerLogic.InsertSkillToken(ctx, payload.spellID, payload.dur)
    end

    local body = SemanticTimelineGUI._segmentMove.Trim(tostring(payload.line or ""):gsub("{time:[^}]+}", "", 1))
    if body == "" then
        return false, "clipboard_empty"
    end
    local line = string.format("{time:%s} %s", SemanticTimelineGUI._segmentMove.FormatTimelineTime(ctx and ctx.time), body)
    return SemanticTimelineGUI.InsertTimelineLineByTime(ctx, line, ctx and ctx.time, {
        source = "context_menu_paste",
    })
end

function SemanticTimelineGUI._segmentMove.Rewrite(item, newSeconds, opts)
    local syntax = T.TimelineSyntax
    if not (syntax and syntax.RewriteTimeInText and syntax.ParseTimelineLine and syntax.FormatTimeLike) then
        return false, "syntax_missing"
    end

    local lineNum = tonumber(item and item.lineNum)
    local text = editorBox:GetText() or ""
    local lines = SemanticTimelineGUI._segmentMove.SplitLines(text)
    local line = lines[lineNum]
    local parsed = syntax.ParseTimelineLine(line or "")
    if not (parsed and type(parsed.segments) == "table" and #parsed.segments > 1) then
        local tokenStart, tokenEnd, payload = (line or ""):find("{time:([^}]+)}")
        if not tokenStart then
            return false, "no_time_token"
        end

        local blockStart, blockEnd = SemanticTimelineGUI._segmentMove.FindTimeBlock(lines, lineNum)
        local movedPayload = syntax.FormatTimeLike(payload, newSeconds, opts)
        local movedLine
        if type(opts) == "table" and type(opts.targetAudience) == "table" then
            local sourceSegments = SemanticTimelineGUI._segmentMove.SplitSourceSegments(line)
            local movedContent = sourceSegments[1] or SemanticTimelineGUI._segmentMove.Trim((line or ""):gsub("{time:[^}]+}", "", 1))
            movedContent = SemanticTimelineGUI._segmentMove.ReplaceSourceAudience(movedContent, opts.targetAudience)
            movedLine = SemanticTimelineGUI._segmentMove.BuildLine(movedPayload, movedContent)
            if not movedLine then
                return false, "move_line_empty"
            end
        else
            local replacement = "{time:" .. movedPayload .. "}"
            movedLine = (line or ""):sub(1, tokenStart - 1) .. replacement .. (line or ""):sub(tokenEnd + 1)
        end
        table.remove(lines, lineNum)
        if lineNum <= blockEnd then
            blockEnd = blockEnd - 1
        end

        SemanticTimelineGUI._segmentMove.SortTimeBlock(lines, blockStart, blockEnd)
        local insertedLine = SemanticTimelineGUI._segmentMove.InsertLineByTime(lines, blockStart, blockEnd, movedLine, newSeconds)
        local caretPos = SemanticTimelineGUI._segmentMove.GetLineTimeCaret(lines, insertedLine)
        local newText = table.concat(lines, "\n")
        SemanticTimelineGUI._segmentMove.ReplaceText(newText, caretPos, "drag", opts)
        return true, "source_rewrite", insertedLine, {
            oldLine = lineNum,
            insertedLine = insertedLine,
            lineRemoved = true,
        }
    end

    local moveIndex = SemanticTimelineGUI._segmentMove.FindSegmentIndex(parsed.segments, item)
    if not moveIndex then
        return false, "segment_not_found"
    end
    local sourceSegments = SemanticTimelineGUI._segmentMove.SplitSourceSegments(line)

    local remaining = {}
    for index, segment in ipairs(parsed.segments) do
        if index ~= moveIndex then
            remaining[#remaining + 1] = segment
        end
    end

    local oldPayload = SemanticTimelineGUI._segmentMove.Trim((line or ""):match("{time:([^}]+)}"))
    if oldPayload == "" then
        oldPayload = SemanticTimelineGUI._segmentMove.Trim(item and item.timePayload)
    end
    if oldPayload == "" then
        oldPayload = "00:00"
    end

    local movedPayload = syntax.FormatTimeLike(oldPayload, newSeconds, opts)
    local movedContent = sourceSegments[moveIndex]
    if type(opts) == "table" and type(opts.targetAudience) == "table" then
        movedContent = SemanticTimelineGUI._segmentMove.ReplaceSourceAudience(movedContent, opts.targetAudience)
    end
    if SemanticTimelineGUI._segmentMove.Trim(movedContent) == "" then
        movedContent = SemanticTimelineGUI._segmentMove.SerializeItem(item, opts)
    end
    if SemanticTimelineGUI._segmentMove.Trim(movedContent) == "" then
        movedContent = SemanticTimelineGUI._segmentMove.SerializeSegment(parsed.segments[moveIndex])
    end
    local movedLine = SemanticTimelineGUI._segmentMove.BuildLine(movedPayload, movedContent)
    if not movedLine then
        return false, "move_line_empty"
    end

    local blockStart, blockEnd = SemanticTimelineGUI._segmentMove.FindTimeBlock(lines, lineNum)
    local insertedLine
    if #remaining > 0 then
        local parts = {}
        for index, segment in ipairs(parsed.segments) do
            if index ~= moveIndex then
                parts[#parts + 1] = sourceSegments[index] or SemanticTimelineGUI._segmentMove.SerializeSegment(segment)
            end
        end
        lines[lineNum] = SemanticTimelineGUI._segmentMove.BuildLine(oldPayload, table.concat(parts)) or ""
        SemanticTimelineGUI._segmentMove.SortTimeBlock(lines, blockStart, blockEnd)
        insertedLine = SemanticTimelineGUI._segmentMove.InsertLineByTime(lines, blockStart, blockEnd, movedLine, newSeconds)
    else
        table.remove(lines, lineNum)
        if lineNum <= blockEnd then
            blockEnd = blockEnd - 1
        end
        SemanticTimelineGUI._segmentMove.SortTimeBlock(lines, blockStart, blockEnd)
        insertedLine = SemanticTimelineGUI._segmentMove.InsertLineByTime(lines, blockStart, blockEnd, movedLine, newSeconds)
    end

    local caretPos = SemanticTimelineGUI._segmentMove.GetLineTimeCaret(lines, insertedLine)
    local newText = table.concat(lines, "\n")
    SemanticTimelineGUI._segmentMove.ReplaceText(newText, caretPos, "drag", opts)
    LogPlanEvent("STT_HTG_SEGMENT_MOVE", {
        line = lineNum,
        insertedLine = insertedLine,
        who = item.who,
        targetWho = type(opts) == "table" and opts.targetAudience and opts.targetAudience.who or nil,
        spellID = tonumber(item.spellID),
        newTime = tonumber(newSeconds),
        targetTab = NormalizeEditorTab(item and item.editorTab or GetActiveEditorTab()),
    })
    return true, "segment_move", insertedLine, {
        oldLine = lineNum,
        insertedLine = insertedLine,
        lineRemoved = #remaining == 0,
        removedSegmentIndex = moveIndex,
    }
end

function SemanticTimelineGUI.RewriteTimelineItemTime(item, newSeconds, opts)
    local lineNum = tonumber(item and item.lineNum)
    if not (editorBox and lineNum and lineNum > 0) then
        return false, "line_not_found"
    end
    local sem = ST()
    local sourceSeconds = math.max(0, (tonumber(newSeconds) or 0) - (tonumber(item and item.phaseDisplayOffset) or 0))

    local targetTab = NormalizeEditorTab(item and item.editorTab or GetActiveEditorTab())
    local originalTab = GetActiveEditorTab()
    local originalDocument = CopyEditorDocument(currentEditorDocument)
    local switchedForRewrite = false

    local function RestoreRewriteDocument()
        if not switchedForRewrite then
            return
        end
        local restoreBossKey = originalDocument and originalDocument.bossKeyText or nil
        local restoreTab = originalDocument and originalDocument.tab or originalTab
        SwitchEditorDocument(restoreBossKey, restoreTab, "horizontal_drag_restore")
    end

    local function ReturnWithRestore(ok, reason, movedLine, moveMeta)
        RestoreRewriteDocument()
        return ok, reason, movedLine, moveMeta
    end

    if targetTab ~= GetActiveEditorTab() then
        local switched = SwitchEditorDocument(nil, targetTab, "horizontal_drag_rewrite")
        if not switched then
            return false, "switch_failed"
        end
        switchedForRewrite = true
    end
    if not (type(opts) == "table" and opts.deferApply == true) and sem and item and item.rowID ~= "" and sem.GetPlanLineByRowIDForTab then
        lineNum = tonumber(sem:GetPlanLineByRowIDForTab(targetTab, item.rowID)) or lineNum
    end
    item.lineNum = lineNum
    local hasTargetAudience = type(opts) == "table" and type(opts.targetAudience) == "table"
    if SemanticTimelineGUI._segmentMove.HasSource(item) or hasTargetAudience then
        local ok, mode, movedLine, moveMeta = SemanticTimelineGUI._segmentMove.Rewrite(item, sourceSeconds, opts)
        if ok then
            LogPlanEvent("STT_HTG_DRAG_REWRITE", {
                line = movedLine or lineNum,
                newTime = tonumber(sourceSeconds),
                targetTab = targetTab,
                mode = mode or "source_rewrite",
                targetWho = hasTargetAudience and opts.targetAudience.who or nil,
            })
        end
        if ok and movedLine then
            item.lineNum = movedLine
        end
        return ReturnWithRestore(ok, mode, movedLine, moveMeta)
    end
    local syntax = T.TimelineSyntax
    if not (syntax and syntax.RewriteTimeInText) then
        return ReturnWithRestore(false, "syntax_missing")
    end

    local result = syntax.RewriteTimeInText(editorBox:GetText() or "", lineNum, sourceSeconds, opts)
    if not (result and result.changed) then
        return ReturnWithRestore(false, result and result.reason or "not_changed")
    end

    if T.EditorUndo and T.EditorUndo.ReplaceText then
        T.EditorUndo:ReplaceText(result.newText, result.newCaretPos, "drag", opts)
    else
        editorBox:SetText(result.newText)
        editorBox:SetCursorPosition(tonumber(result.newCaretPos) or 0)
        if not (type(opts) == "table" and opts.deferApply == true) then
            if ApplyEditorTextNow then
                ApplyEditorTextNow()
            end
            RefreshRows({
                force = true,
                cause = "drag",
            })
        end
    end

    LogPlanEvent("STT_HTG_DRAG_REWRITE", {
        line = lineNum,
        newTime = tonumber(sourceSeconds),
        targetTab = targetTab,
        mode = "source_rewrite",
    })
    return ReturnWithRestore(true, "source_rewrite", lineNum, {
        oldLine = lineNum,
        insertedLine = lineNum,
        lineRemoved = false,
    })
end

function SemanticTimelineGUI.GetTimelineItemLine(item, source)
    local lineNum = tonumber(item and item.lineNum)
    if not (editorBox and lineNum and lineNum > 0) then
        return nil, "line_not_found"
    end

    local targetTab = NormalizeEditorTab(item and item.editorTab or GetActiveEditorTab())
    if targetTab ~= GetActiveEditorTab() then
        local switched = SwitchEditorDocument(nil, targetTab, (source or "timeline_item") .. "_tab")
        if not switched then
            return nil, "switch_failed"
        end
    end

    local sem = ST()
    if sem and item and item.rowID ~= "" and sem.GetPlanLineByRowIDForTab then
        lineNum = tonumber(sem:GetPlanLineByRowIDForTab(targetTab, item.rowID)) or lineNum
    end
    if not lineNum or lineNum <= 0 then
        return nil, "line_not_found"
    end

    local lines = SemanticTimelineGUI._segmentMove.SplitLines(editorBox:GetText() or "")
    local line = lines[lineNum]
    if type(line) ~= "string" then
        return nil, "line_not_found"
    end

    return {
        line = line,
        lineNum = lineNum,
        targetTab = targetTab,
    }
end

function SemanticTimelineGUI.RewriteTimelineItemLine(item, newLineString)
    local resolved, reason = SemanticTimelineGUI.GetTimelineItemLine(item, "event_editor_rewrite")
    if not resolved then
        return false, reason
    end

    local syntax = T.TimelineSyntax
    if not (syntax and syntax.RewriteEventLineInText) then
        return false, "syntax_missing"
    end

    local result = syntax.RewriteEventLineInText(editorBox:GetText() or "", resolved.lineNum, newLineString)
    if not (result and result.changed) then
        return false, result and result.reason or "not_changed"
    end

    if T.EditorUndo and T.EditorUndo.ReplaceText then
        T.EditorUndo:ReplaceText(result.newText, result.newCaretPos, "event_editor")
    else
        editorBox:SetText(result.newText)
        editorBox:SetCursorPosition(tonumber(result.newCaretPos) or 0)
        if ApplyEditorTextNow then
            ApplyEditorTextNow("event_editor")
        end
        RefreshRows({
            force = true,
            cause = "event_editor",
        })
    end

    LogPlanEvent("editor.event.edited", {
        lineNum = resolved.lineNum,
        rowID = item and item.rowID or nil,
        before = resolved.line,
        after = newLineString,
    })
    return true, "line_rewrite"
end

function SemanticTimelineGUI.FocusEditorLine(lineNumber)
    FocusEditorLine(lineNumber)
end

function SemanticTimelineGUI.FocusTimelineItem(item)
    if type(item) ~= "table" then
        return
    end

    local sem = ST()
    local rowID = tostring(item.rowID or "")
    local targetTab = NormalizeEditorTab(item.editorTab or GetActiveEditorTab())

    if rowID ~= "" then
        selectedRowID = rowID
    end

    if targetTab ~= GetActiveEditorTab() then
        SwitchEditorDocument(nil, targetTab, "horizontal_item_jump")
    else
        RefreshRows()
    end

    local lineNum = nil
    if sem and rowID ~= "" then
        if sem.GetPlanLineByRowIDForTab then
            lineNum = sem:GetPlanLineByRowIDForTab(targetTab, rowID)
        end
        if not lineNum and sem.GetCurrentPlanLineByRowID then
            lineNum = sem:GetCurrentPlanLineByRowID(rowID)
        end
    end
    lineNum = tonumber(lineNum) or tonumber(item.lineNum)

    if lineNum and lineNum > 0 then
        FocusEditorLine(lineNum)
    end
end

function SemanticTimelineGUI.CreateInterface(parent)
    if rootFrame then
        return
    end

    if not parent then
        return
    end

    local sem = ST()
    if not sem then
        return
    end

    SemanticTimelineGUI._CreateSemanticRootFrame(parent)
    SemanticTimelineGUI._CreateTopPanel()
    SemanticTimelineGUI._CreateTransportDock()
    local leftPanel = SemanticTimelineGUI._CreateTimelinePanel()
    local dividerFrame = SemanticTimelineGUI._CreateDividerFrame(leftPanel)
    local rightPanel = SemanticTimelineGUI._CreateRightPanel(dividerFrame)
    SemanticTimelineGUI._CreateEditorWorkspace(rightPanel)
    SemanticTimelineGUI._BindEditorHandlers()
    if T.EditorUndo then
        T.EditorUndo:Init(editorBox, rawEditorContainer or rightPanelFrame or rootFrame, rootFrame)
    end
    currentLeftMode = SemanticTimelineGUI.GetActiveLeftMode()

    statusLabel = rootFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLabel:SetPoint("TOPLEFT", leftPanelFrame or rootFrame, "BOTTOMLEFT", 6, -4)
    if T.SkillDrawer and T.SkillDrawer.Init then
        T.SkillDrawer.Init(rootFrame)
    end

    SemanticTimelineGUI.ApplySavedLayout()
    SemanticTimelineGUI.RefreshViewModeSelector()
    SemanticTimelineGUI.SetLeftMode(currentLeftMode)
    RelayoutTopButtons()
    SetEditorMode("raw")
    SemanticTimelineGUI.RefreshLocalization()
    if sem.EnsureEditorWorkbenchReady then
        sem:EnsureEditorWorkbenchReady("gui_first_open")
    else
        sem:EnsureSemanticBossPlansInitialized({ cause = "gui_first_open" })
    end
    SemanticTimelineGUI.RefreshData("initial_open")
end

function SemanticTimelineGUI.ApplySavedLayout()
    SemanticTimelineGUI.EnsureTimelineUIPreferences()
    currentLeftMode = SemanticTimelineGUI.GetActiveLeftMode()
    ApplyDividerRatio(SemanticTimelineGUI.GetActiveDividerRatio())
    RelayoutTopButtons()
end

function SemanticTimelineGUI.RefreshLocalization()
    if not rootFrame then
        return
    end

    if editorTabGroup then
        editorTabGroup.tabs[1].text = L["团队方案"] or "团队方案"
        editorTabGroup.tabs[2].text = L["个人方案"] or "个人方案"
        editorTabGroup:Refresh()
    end
    if teamTabBtn then
        teamTabBtn:SetText(L["团队方案"] or "团队方案")
    end
    if personalTabBtn then
        personalTabBtn:SetText(L["个人方案"] or "个人方案")
    end
    SemanticTimelineGUI.RefreshViewModeSelector()
    reloadTemplateBtn:SetText(L["从模板重载"] or "从模板重载")
    if T.SemanticTimelineSyncButton and T.SemanticTimelineSyncButton.IsBusy and not T.SemanticTimelineSyncButton:IsBusy() then
        T.SemanticTimelineSyncButton:ResetText()
    end
    SemanticTimelineGUI.syncRaidBtn:SetText(L["同步团员"] or "导入团员")
    if rawModeBtn then rawModeBtn:SetText(L["原始文本"] or "原始文本") end
    if formModeBtn then formModeBtn:SetText(L["逐技能"] or "逐技能") end
    if resolveSourceSelector then
        resolveSourceSelector:SetItems(GetResolveSourceItems())
        local valueText = L["团队+个人"] or "团队+个人"
        for _, item in ipairs(resolveSourceSelector.items or {}) do
            if item.value == currentResolveSource then
                valueText = item.text
                break
            end
        end
        SetSelectorButtonValue(resolveSourceSelector, L["解析方案"] or "解析方案", valueText, currentResolveSource)
        SetSelectorButtonEnabled(resolveSourceSelector, #resolveSourceSelector.items > 1)
    end
    if formSpellLabel then formSpellLabel:SetText(L["当前技能"] or "当前技能") end
    if formPayloadLabel then formPayloadLabel:SetText(L["战术文本"] or "战术文本") end

    RefreshDropdowns()
    RefreshRows()
    RefreshErrorSummary()
    RefreshActionButtonState()
    RefreshEditorModeButtons()
    RefreshTriggerForm()
end

function SemanticTimelineGUI.SwitchEditorDocumentToBossKey(bossKeyText, tab, cause, options)
    local sem = ST()
    if not (sem and sem.ParseBossSelectorKey) then
        return false
    end

    local parsedBossKey = sem:ParseBossSelectorKey(bossKeyText)
    if not parsedBossKey then
        return false
    end
    return SwitchEditorDocument(parsedBossKey, tab or GetActiveEditorTab(), cause or "boss_change", options)
end

function SemanticTimelineGUI.OnPanelHide()
    SemanticTimelineGUI.HideTransientMenus()
    CancelDividerAnimation()
    StopDividerDrag("panel_hide", false)
    CancelEditorSaveTimer()
    CancelFormSaveTimer()
    statusToken = statusToken + 1
    SemanticTimelineGUI.CancelStatusTicker()
    if statusLabel then
        statusLabel:SetText("")
        statusLabel:SetAlpha(1)
    end
    if T.EditorUndo then
        T.EditorUndo:Clear()
    end
    ApplyFormRuleNow()
    FlushCurrentEditorDocument("panel_hide")
    currentEditorDocument = nil
    isEditorDocumentHydrated = false
    local sem = ST()
    if sem and sem.ClearManualBossSelection then
        sem:ClearManualBossSelection()
    end

    -- 释放 Lua 侧数据引用（Frame 对象无法释放，只清数据）
    wipe(currentRows)
    wipe(currentErrors)
    wipe(currentDisplayRows)
    ResetHorizontalScrollState()
    if horizontalTimeline then
        horizontalTimeline:Hide()
        if horizontalTimeline.Deactivate then
            horizontalTimeline:Deactivate()
        end
        if horizontalTimeline.ReleaseData then
            horizontalTimeline:ReleaseData()
        else
            horizontalTimeline:Refresh({}, { cause = "panel_hide" })
        end
    end
    ClearViewportState()
    ReleaseAllCells()
    selectedRowID = nil
    currentTemplateInfo = nil
    -- 清空 EditBox 文本释放字符串内存
    if editorBox then
        isEditorHydrating = true
        editorBox:SetText("")
        isEditorHydrating = false
        isEditorDocumentHydrated = false
    end
    -- 清空表单编辑器文本
    if formPayloadEditorBox then
        formPayloadEditorBox:SetText("")
    end
    -- 隐藏所有行（释放 row.data 引用）
    for _, row in ipairs(rowFrames) do
        row.data = nil
        row:Hide()
    end
    UpdateHorizontalScrollBar()
end

function SemanticTimelineGUI.GetMemoryState()
    local hState = horizontalTimeline and horizontalTimeline.GetMemoryState and horizontalTimeline:GetMemoryState() or {}
    return {
        root = rootFrame ~= nil,
        visible = SemanticTimelineGUI.IsVisible(),
        rows = #(currentRows or {}),
        errors = #(currentErrors or {}),
        displayRows = #(currentDisplayRows or {}),
        rowFrames = #(rowFrames or {}),
        cellActive = cellRenderer and #(cellRenderer.active or {}) or 0,
        cellPool = cellRenderer and #(cellRenderer.pool or {}) or 0,
        saveTimer = saveTimer ~= nil,
        formSaveTimer = formSaveTimer ~= nil,
        statusTicker = SemanticTimelineGUI.statusToast and SemanticTimelineGUI.statusToast.fadeTicker ~= nil,
        horizontal = hState,
    }
end

function SemanticTimelineGUI.RefreshTimelineStyle()
    if not rootFrame or not rowsScroll then
        return
    end

    RefreshRows({
        force = true,
        cause = "timeline_style_change",
    })
end

SemanticTimelineGUI._EditorDeps = {
    LogPlanEvent = function(eventName, fields)
        if LogPlanEvent then
            LogPlanEvent(eventName, fields)
        end
    end,
    ApplyEditorTextNow = function(source)
        if ApplyEditorTextNow then
            return ApplyEditorTextNow(source)
        end
        return false
    end,
    RefreshRows = function(opts)
        if RefreshRows then
            RefreshRows(opts)
        end
    end,
    LogInputConsumeOnce = LogInputConsumeOnce,
    LogEditorKeyboardGuardOnce = LogEditorKeyboardGuardOnce,
}

function SemanticTimelineGUI.IsVisible()
    if not rootFrame then
        return false
    end

    if rootFrame.IsVisible then
        return rootFrame:IsVisible()
    end
    if rootFrame.IsShown then
        return rootFrame:IsShown()
    end
    return true
end

function SemanticTimelineGUI.RefreshData(cause, opts)
    if not SemanticTimelineGUI.IsVisible() then
        return
    end

    opts = type(opts) == "table" and opts or {}
    local refreshCause = type(cause) == "string" and cause or "refresh"
    local refreshStartedAt = SemanticTimelineGUI.GetPerfMs()
    if T.TimelineSelectionBox and (refreshCause == "boss_change" or refreshCause == "profile_changed" or refreshCause == "sync_apply" or refreshCause == "panel_show" or refreshCause == "initial_open") then
        T.TimelineSelectionBox.Clear(refreshCause)
    end
    if refreshCause == "initial_open" or refreshCause == "panel_show" or refreshCause == "profile_changed" then
        local sem = ST()
        if sem then
            local targetBossKey = currentEditorDocument and currentEditorDocument.bossKeyText or sem:GetCurrentBossSelectorKey()
            local targetTab = currentEditorDocument and currentEditorDocument.tab or GetActiveEditorTab()
            if targetBossKey then
                SwitchEditorDocument(targetBossKey, targetTab, refreshCause)
                return
            end
        end
    end

    local selectionChanged = RefreshDropdowns()
    if selectionChanged or refreshCause == "boss_change" or refreshCause == "sync_apply" then
        local targetTab = currentEditorDocument and currentEditorDocument.tab or GetActiveEditorTab()
        SwitchEditorDocument(nil, targetTab, refreshCause)
        return
    end

    EnsureCurrentRowsLoaded()
    if ShouldRestoreViewport(refreshCause) then
        local viewportTab = currentEditorDocument and currentEditorDocument.tab or GetActiveEditorTab()
        local bossKeyText = GetDocumentBossKeyText(currentEditorDocument)
        RestoreViewportState(viewportTab, refreshCause, bossKeyText)
    end
    if currentPlanFormat == "trigger" and not GetSelectedSpellRow() then
        for _, row in ipairs(currentRows or {}) do
            if row.rowType == "spell" then
                selectedRowID = row.rowID
                break
            end
        end
    end
    local htgStartedAt = SemanticTimelineGUI.GetPerfMs()
    RefreshRows({
        cause = refreshCause,
    })
    SemanticTimelineGUI._lastRefreshHtgMs = SemanticTimelineGUI.ElapsedMs(htgStartedAt) or 0
    RefreshTriggerForm()
    RefreshActionButtonState()
    RefreshEditorModeButtons()
    RefreshResolveSourceSelector()
    if opts.source == "skill_picker" and T.debug then
        T.debug(string.format(
            "[STT_SKILL_PICKER_PERF] totalMs=%s compileMs=%s htgMs=%s",
            tostring(SemanticTimelineGUI.ElapsedMs(refreshStartedAt) or 0),
            tostring(SemanticTimelineGUI._lastRefreshCompileMs or 0),
            tostring(SemanticTimelineGUI._lastRefreshHtgMs or 0)
        ))
    end
    return {
        totalMs = SemanticTimelineGUI.ElapsedMs(refreshStartedAt) or 0,
        compileMs = SemanticTimelineGUI._lastRefreshCompileMs or 0,
        htgMs = SemanticTimelineGUI._lastRefreshHtgMs or 0,
    }
end

if T.events then
    T.events:Register("STT_PROFILE_CHANGED", SemanticTimelineGUI, function(self)
        if T.RefreshProfileSelector then
            T.RefreshProfileSelector()
        end
        self.RefreshData("profile_changed")
    end)
end

end)
