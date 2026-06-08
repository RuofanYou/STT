local T, C, L = unpack(select(2, ...))

local addon_name = T.addon_name

local GUI
local currentTab
local guiTabGroup
local planPanel
local settingsPanel
local visualBoardPanel
local resizeHandle
local runtimeTestStartButton
local runtimeTestStopButton
local pendingInitialTab
local isResizing = false
local lastSettingsModuleId
local settingsLayoutRefreshSerial = 0
local fontScaleApplySerial = 0
local EnsureSettingsLayout

local DEFAULT_GUI_WIDTH = 900
local DEFAULT_GUI_HEIGHT = 680
local RESIZE_HANDLE_SIZE = 28
local CHANGELOG_MODULE_ID = "changelog"

local TAB_TITLE_KEYS = {
    "GUI_TAB_SETTINGS",
    "GUI_TAB_PLAN",
    "GUI_TAB_VISUAL_BOARD",
}

local function ResolveText(textKey, fallback)
    local value = textKey and rawget(L, textKey)
    if value ~= nil then
        return value
    end
    return fallback or textKey or ""
end

local function GetTabTitle(index)
    if index == 2 then
        return ResolveText(TAB_TITLE_KEYS[index], "战术方案")
    end
    if index == 3 then
        return ResolveText(TAB_TITLE_KEYS[index], "视觉画板")
    end
    return ResolveText(TAB_TITLE_KEYS[index], "设置")
end

local function NormalizeTabIndex(index)
    if tonumber(index) == 3 then
        return 3
    end
    if tonumber(index) == 2 then
        return 2
    end
    return 1
end

local function GetSemanticUILayout()
    local semantic = C and C.DB and C.DB.semanticTimeline
    return semantic and semantic.ui or nil
end

local function NormalizeAvailableTab(index)
    return NormalizeTabIndex(index)
end

local function ClampNumber(value, minValue, maxValue, fallback)
    local numberValue = tonumber(value)
    if not numberValue then
        return fallback
    end
    if numberValue < minValue then
        return minValue
    end
    if numberValue > maxValue then
        return maxValue
    end
    return numberValue
end

local function GetUIParentCenter()
    local width = (UIParent and UIParent:GetWidth()) or DEFAULT_GUI_WIDTH
    local height = (UIParent and UIParent:GetHeight()) or DEFAULT_GUI_HEIGHT
    return width / 2, height / 2
end

local function GetMaxWindowSize()
    local maxWidth = (UIParent and UIParent:GetWidth()) or DEFAULT_GUI_WIDTH
    local maxHeight = (UIParent and UIParent:GetHeight()) or DEFAULT_GUI_HEIGHT
    return math.max(DEFAULT_GUI_WIDTH, maxWidth), math.max(DEFAULT_GUI_HEIGHT, maxHeight)
end

local function ClampPlanSize(width, height)
    local maxWidth, maxHeight = GetMaxWindowSize()
    return ClampNumber(width, DEFAULT_GUI_WIDTH, maxWidth, DEFAULT_GUI_WIDTH),
        ClampNumber(height, DEFAULT_GUI_HEIGHT, maxHeight, DEFAULT_GUI_HEIGHT)
end

local function GetSavedPlanSize()
    local ui = GetSemanticUILayout()
    return ClampPlanSize(
        ui and ui.planWidth or DEFAULT_GUI_WIDTH,
        ui and ui.planHeight or DEFAULT_GUI_HEIGHT
    )
end

local function IsResizableTab(index)
    local normalized = NormalizeTabIndex(index)
    return normalized == 2 or normalized == 3
end

local function GetGUIBounds()
    if not GUI then
        return nil
    end

    local left = GUI:GetLeft()
    local bottom = GUI:GetBottom()
    local width = GUI:GetWidth()
    local height = GUI:GetHeight()
    if not (left and bottom and width and height) then
        return nil
    end

    return left, bottom, width, height
end

local function GetCurrentGUICenter()
    local left, bottom, width, height = GetGUIBounds()
    if not left then
        return nil, nil
    end

    return left + width / 2, bottom + height / 2
end

local function ApplyGUIRect(width, height, centerX, centerY)
    if not GUI then
        return
    end

    local targetWidth, targetHeight = ClampPlanSize(width, height)
    local targetCenterX = tonumber(centerX)
    local targetCenterY = tonumber(centerY)
    if not (targetCenterX and targetCenterY) then
        targetCenterX, targetCenterY = GetUIParentCenter()
    end

    GUI:ClearAllPoints()
    GUI:SetPoint("CENTER", UIParent, "BOTTOMLEFT", targetCenterX, targetCenterY)
    GUI:SetSize(math.floor(targetWidth + 0.5), math.floor(targetHeight + 0.5))
end

local function AnchorGUIToTopLeft()
    local left, bottom, width, height = GetGUIBounds()
    if not left then
        return false
    end

    local top = bottom + height
    GUI:ClearAllPoints()
    GUI:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    GUI:SetSize(math.floor(width + 0.5), math.floor(height + 0.5))
    return true
end

local function NormalizeGUIAnchorToCenter()
    local left, bottom, width, height = GetGUIBounds()
    if not left then
        return
    end

    local centerX = left + width / 2
    local centerY = bottom + height / 2
    ApplyGUIRect(width, height, centerX, centerY)
end

local function SavePlanWindowLayout(cause)
    local ui = GetSemanticUILayout()
    if not ui or not GUI or not IsResizableTab(currentTab) then
        return
    end

    local width, height = ClampPlanSize(GUI:GetWidth(), GUI:GetHeight())
    local left = GUI:GetLeft()
    local bottom = GUI:GetBottom()
    if not (left and bottom) then
        return
    end

    ui.planWidth = width
    ui.planHeight = height
    ui.planPosX = left + width / 2
    ui.planPosY = bottom + height / 2
end

local function SavePlanWindowPosition(cause)
    local ui = GetSemanticUILayout()
    if not ui or not GUI then
        return
    end

    local centerX, centerY = GetCurrentGUICenter()
    if not (centerX and centerY) then
        return
    end

    ui.planPosX = centerX
    ui.planPosY = centerY
    T.debug("[GUI] PlanPositionSaved cause=%s center=(%.1f, %.1f)",
        tostring(cause or "unknown"), centerX, centerY)
end

local function UpdateResizeHandleVisibility()
    if not resizeHandle then
        return
    end

    if GUI and GUI:IsShown()
        and ((currentTab == 2 and planPanel and planPanel:IsShown())
            or (currentTab == 3 and visualBoardPanel and visualBoardPanel:IsShown())) then
        resizeHandle:Show()
    else
        resizeHandle:Hide()
    end
end

local function UpdateRuntimeTestButtonsVisibility()
    local shown = GUI and GUI:IsShown() and currentTab == 1
    if runtimeTestStartButton then
        runtimeTestStartButton:SetShown(shown == true)
    end
    if runtimeTestStopButton then
        runtimeTestStopButton:SetShown(shown == true)
    end
end

local function FinishResize(cause)
    if not GUI then
        return
    end

    if isResizing then
        GUI:StopMovingOrSizing()
        isResizing = false
        NormalizeGUIAnchorToCenter()
        if IsResizableTab(currentTab) then
            SavePlanWindowLayout(cause or "resize_stop")
        end
    end

    UpdateResizeHandleVisibility()
    UpdateRuntimeTestButtonsVisibility()
end

local function ApplyTabFrameRect(index, preserveCenterX, preserveCenterY)
    local normalized = NormalizeTabIndex(index)
    local targetCenterX = tonumber(preserveCenterX)
    local targetCenterY = tonumber(preserveCenterY)

    if IsResizableTab(normalized) then
        local ui = GetSemanticUILayout()
        local width, height = GetSavedPlanSize()
        if targetCenterX and targetCenterY then
            ApplyGUIRect(width, height, targetCenterX, targetCenterY)
        elseif ui and ui.planPosX and ui.planPosY then
            ApplyGUIRect(width, height, ui.planPosX, ui.planPosY)
        else
            local centerX, centerY = GetUIParentCenter()
            ApplyGUIRect(width, height, centerX, centerY)
        end
        return
    end

    if targetCenterX and targetCenterY then
        ApplyGUIRect(DEFAULT_GUI_WIDTH, DEFAULT_GUI_HEIGHT, targetCenterX, targetCenterY)
        return
    end

    local centerX, centerY = GetUIParentCenter()
    ApplyGUIRect(DEFAULT_GUI_WIDTH, DEFAULT_GUI_HEIGHT, centerX, centerY)
end

local function ApplyTabVisibility(index)
    local tabIndex = NormalizeTabIndex(index)

    if settingsPanel then
        if tabIndex == 1 then
            settingsPanel:Show()
        else
            settingsPanel:Hide()
        end
    end

    if planPanel then
        if tabIndex == 2 then
            planPanel:Show()
        else
            planPanel:Hide()
        end
    end

    if visualBoardPanel then
        if tabIndex == 3 then
            visualBoardPanel:Show()
        else
            visualBoardPanel:Hide()
        end
    end

    if guiTabGroup then
        guiTabGroup:SetActiveTab(tabIndex, true)
    end

    currentTab = tabIndex
    UpdateRuntimeTestButtonsVisibility()

    local ui = GetSemanticUILayout()
    if ui then
        ui.lastTab = tabIndex
    end

    UpdateResizeHandleVisibility()
end

local function ShowRequestedTab(index)
    local normalized = NormalizeAvailableTab(index)
    if not GUI or not GUI:IsShown() then
        ApplyTabVisibility(normalized)
        return
    end

    if currentTab == normalized then
        ApplyTabVisibility(normalized)
        return
    end

    local centerX, centerY = GetCurrentGUICenter()

    if IsResizableTab(currentTab) and currentTab ~= normalized then
        SavePlanWindowLayout("tab_switch")
    end

    FinishResize("tab_switch")
    ApplyTabFrameRect(normalized, centerX, centerY)
    ApplyTabVisibility(normalized)
    if normalized == 1 then
        EnsureSettingsLayout()
    end
    if IsResizableTab(normalized) then
        SavePlanWindowPosition("tab_switch")
    end
end

T.IsSettingsPanelDescendant = function(frame)
    if not (frame and settingsPanel) then
        return false
    end
    local current = frame
    while current do
        if current == settingsPanel then
            return true
        end
        current = current.GetParent and current:GetParent() or nil
    end
    return false
end

local function GetSettingsSidebarWidth()
    return T.Style and T.Style.Scaled and T.Style.Scaled("SIDEBAR_WIDTH") or T.Style.Nav.SIDEBAR_WIDTH
end

local function GetSettingsSidebarInnerWidth()
    local pad = T.Style and T.Style.Scaled and T.Style.Scaled("SIDEBAR_INNER_PAD") or 20
    return math.max(120, GetSettingsSidebarWidth() - pad)
end

local function GetSettingsContentWidth()
    local frameWidth = (GUI and GUI:GetWidth()) or DEFAULT_GUI_WIDTH
    local sidebarWidth = GetSettingsSidebarWidth()
    local gap = T.Style and T.Style.Scale and T.Style.Scale(12) or 12
    return math.max(420, math.floor(frameWidth - 48 - sidebarWidth - gap - 32))
end

local function ApplyScrollBarScale(scroll)
    if scroll and scroll.SetScrollBarWidth and T.Style and T.Style.Scaled then
        scroll:SetScrollBarWidth(T.Style.Scaled("SCROLL_BAR_WIDTH"))
    end
end

local function GetScrollOffset(scroll)
    if not scroll then
        return nil
    end
    if scroll.GetOffset then
        return scroll:GetOffset()
    end
    if scroll.GetVerticalScroll then
        return scroll:GetVerticalScroll()
    end
    return nil
end

local function RestoreScrollOffset(scroll, offset)
    if not (scroll and offset) then
        return
    end
    if scroll.SetOffset then
        scroll:SetOffset(offset)
    elseif scroll.SnapTo then
        scroll:SnapTo(offset)
    elseif scroll.SetVerticalScroll then
        scroll:SetVerticalScroll(offset)
    end
end

local function NavigateSettingsModule(moduleId)
    if not (settingsPanel and settingsPanel.initialized and settingsPanel.scroll and T.OptionEngine and T.OptionEngine.moduleAnchors) then
        return false
    end
    local anchor = T.OptionEngine.moduleAnchors[moduleId]
    if anchor == nil then
        return false
    end

    settingsPanel.pendingNavModuleId = moduleId
    settingsPanel.pendingNavAnchor = anchor
    if settingsPanel.navTree and settingsPanel.navTree.SetActiveModule then
        settingsPanel.navTree:SetActiveModule(moduleId)
    end
    settingsPanel.scroll:ScrollTo(anchor)
    lastSettingsModuleId = moduleId
    return true
end

local function RestoreSettingsModule()
    if not (settingsPanel and settingsPanel:IsShown()) then
        return
    end
    local changelogDef = T.OptionEngine and T.OptionEngine.GetModuleById and T.OptionEngine:GetModuleById(CHANGELOG_MODULE_ID)
    if changelogDef and T.NewBadge and T.NewBadge:IsModuleNew(changelogDef) and NavigateSettingsModule(CHANGELOG_MODULE_ID) then
        return
    end
    if lastSettingsModuleId then
        NavigateSettingsModule(lastSettingsModuleId)
    end
end

local function SetGUIResizeBoundsRelaxed(relaxed)
    if not GUI then
        return
    end
    if GUI.SetResizeBounds then
        if relaxed then
            GUI:SetResizeBounds(1, 1)
        else
            GUI:SetResizeBounds(DEFAULT_GUI_WIDTH, DEFAULT_GUI_HEIGHT)
        end
    elseif GUI.SetMinResize then
        if relaxed then
            GUI:SetMinResize(1, 1)
        else
            GUI:SetMinResize(DEFAULT_GUI_WIDTH, DEFAULT_GUI_HEIGHT)
        end
    end
end

local function SetFrameAlpha(frame, alpha)
    if frame and frame.SetAlpha then
        frame:SetAlpha(alpha)
    end
end

local GUI_SKIN_PIECES = {
    "TopLeftCorner",
    "TopRightCorner",
    "BottomLeftCorner",
    "BottomRightCorner",
    "TopEdge",
    "BottomEdge",
    "LeftEdge",
    "RightEdge",
    "Center",
}

local function SetFrameShownPreservingState(frame, shown)
    if not frame then
        return
    end
    if shown then
        if frame.__sttSRShownBeforeMorph ~= nil then
            local restoreShown = frame.__sttSRShownBeforeMorph == true
            if frame.SetShown then
                frame:SetShown(restoreShown)
            elseif restoreShown and frame.Show then
                frame:Show()
            elseif not restoreShown and frame.Hide then
                frame:Hide()
            end
            frame.__sttSRShownBeforeMorph = nil
        end
        return
    end
    if frame.__sttSRShownBeforeMorph == nil and frame.IsShown then
        frame.__sttSRShownBeforeMorph = frame:IsShown() == true
    end
    if frame.SetShown then
        frame:SetShown(false)
    elseif frame.Hide then
        frame:Hide()
    end
end

local function SetTabGroupShown(shown)
    if not guiTabGroup then
        return
    end
    for _, button in ipairs(guiTabGroup.buttons or {}) do
        SetFrameShownPreservingState(button, shown == true)
    end
end

local function SetGUISkinShown(shown)
    if not GUI then
        return
    end
    for _, name in ipairs(GUI_SKIN_PIECES) do
        SetFrameShownPreservingState(GUI[name], shown == true)
    end
    SetFrameShownPreservingState(GUI._frameSkinBackground, shown == true)
    SetFrameShownPreservingState(GUI._frameSkinTitleBar, shown == true)
    SetFrameShownPreservingState(GUI._frameSkinBaseBackdrop, shown == true)
    if type(GUI._frameSkinLegacyKyrian) == "table" then
        for _, texture in pairs(GUI._frameSkinLegacyKyrian) do
            SetFrameShownPreservingState(texture, shown == true)
        end
    end
end

local function SetFrameTreeMouseEnabled(frame, enabled)
    if not frame then
        return
    end
    if frame.EnableMouse and frame.IsMouseEnabled then
        if enabled then
            if frame.__sttSRMouseEnabled ~= nil then
                frame:EnableMouse(frame.__sttSRMouseEnabled == true)
                frame.__sttSRMouseEnabled = nil
            end
        else
            if frame.__sttSRMouseEnabled == nil then
                frame.__sttSRMouseEnabled = frame:IsMouseEnabled() == true
            end
            frame:EnableMouse(false)
        end
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            SetFrameTreeMouseEnabled(child, enabled)
        end
    end
end

local function SetContentMouseEnabled(enabled)
    local state = enabled == true
    SetFrameTreeMouseEnabled(GUI and GUI.CloseButton, state)
    SetFrameTreeMouseEnabled(guiTabGroup, state)
    SetFrameTreeMouseEnabled(settingsPanel, state)
    SetFrameTreeMouseEnabled(planPanel, state)
    SetFrameTreeMouseEnabled(visualBoardPanel, state)
    SetFrameTreeMouseEnabled(resizeHandle, state)
    SetFrameTreeMouseEnabled(runtimeTestStartButton, state)
    SetFrameTreeMouseEnabled(runtimeTestStopButton, state)
end

function T.GUI_GetFrame()
    return GUI
end

function T.GUI_GetSnapshot()
    if not GUI then
        return nil
    end
    local centerX, centerY = GetCurrentGUICenter()
    return {
        tab = NormalizeAvailableTab(currentTab or 1),
        width = GUI:GetWidth() or DEFAULT_GUI_WIDTH,
        height = GUI:GetHeight() or DEFAULT_GUI_HEIGHT,
        centerX = centerX,
        centerY = centerY,
        scrollOffset = GetScrollOffset(settingsPanel and settingsPanel.scroll),
    }
end

function T.GUI_RestoreSnapshot(snapshot)
    if not (GUI and type(snapshot) == "table") then
        return
    end
    local tab = NormalizeAvailableTab(snapshot.tab or currentTab or 1)
    ApplyGUIRect(snapshot.width or DEFAULT_GUI_WIDTH, snapshot.height or DEFAULT_GUI_HEIGHT, snapshot.centerX, snapshot.centerY)
    ApplyTabVisibility(tab)
    if tab == 1 then
        EnsureSettingsLayout()
        RestoreScrollOffset(settingsPanel and settingsPanel.scroll, snapshot.scrollOffset)
    end
end

function T.GUI_SetContentAlpha(alpha)
    if not GUI then
        return
    end
    local value = math.max(0, math.min(1, tonumber(alpha) or 0))
    SetFrameAlpha(GUI.TitleText, value)
    SetFrameAlpha(GUI.CloseButton, value)
    if guiTabGroup then
        for _, button in ipairs(guiTabGroup.buttons or {}) do
            SetFrameAlpha(button, value)
        end
    end
    SetFrameAlpha(settingsPanel, value)
    SetFrameAlpha(planPanel, value)
    SetFrameAlpha(visualBoardPanel, value)
    SetFrameAlpha(resizeHandle, value)
    SetFrameAlpha(runtimeTestStartButton, value)
    SetFrameAlpha(runtimeTestStopButton, value)
end

function T.GUI_SetMorphSurfaceAlpha(alpha)
    if not GUI then
        return
    end
    local value = math.max(0, math.min(1, tonumber(alpha) or 0))
    GUI:SetAlpha(value)
end

function T.GUI_SetMorphChromeHidden(hidden)
    local shown = hidden ~= true
    SetGUISkinShown(shown)
    SetTabGroupShown(shown)
end

function T.GUI_SetContentMouseEnabled(enabled)
    SetContentMouseEnabled(enabled == true)
end

function T.GUI_SetFrameTreeMouseEnabled(frame, enabled)
    SetFrameTreeMouseEnabled(frame, enabled == true)
end

function T.GUI_SetResizeBoundsRelaxed(relaxed)
    SetGUIResizeBoundsRelaxed(relaxed == true)
end

function T.RefreshSettingsFontScaleLayout(reason)
    local fontAlreadyApplied = reason == "font_scale_slider" or reason == "font_scale_preset" or reason == "font_scale"
    if not fontAlreadyApplied and T.Style and T.Style.ApplyRegisteredFonts then
        T.Style.ApplyRegisteredFonts()
    end
    if not (settingsPanel and settingsPanel.initialized) then
        return
    end

    local shouldDelayRebuild = reason == "font_scale_slider"
    local sidebarWidth = GetSettingsSidebarWidth()
    local innerWidth = GetSettingsSidebarInnerWidth()
    settingsPanel.leftPanel:SetWidth(sidebarWidth)
    if settingsPanel.searchFrame and settingsPanel.searchFrame.SetSearchWidth then
        settingsPanel.searchFrame:SetSearchWidth(innerWidth)
    end
    if settingsPanel.navTree then
        if shouldDelayRebuild then
            settingsPanel.navTree.width = innerWidth
            settingsPanel.navTree:SetWidth(innerWidth)
        elseif settingsPanel.navTree.SetTreeWidth then
            settingsPanel.navTree:SetTreeWidth(innerWidth)
        end
    end
    ApplyScrollBarScale(settingsPanel.navScroll)
    ApplyScrollBarScale(settingsPanel.scroll)

    local function rebuild()
        if T.OptionEngine and T.OptionEngine.RenderAll and settingsPanel.scroll then
            local scroll = settingsPanel.scroll
            local offset = GetScrollOffset(scroll)
            T.OptionEngine:RenderAll(scroll.content, GetSettingsContentWidth())
            RestoreScrollOffset(scroll, offset)
        end
    end

    if shouldDelayRebuild then
        settingsLayoutRefreshSerial = settingsLayoutRefreshSerial + 1
        local serial = settingsLayoutRefreshSerial
        C_Timer.After(0.08, function()
            if serial ~= settingsLayoutRefreshSerial then
                return
            end
            rebuild()
        end)
    else
        settingsLayoutRefreshSerial = settingsLayoutRefreshSerial + 1
        rebuild()
    end
end

function T.ApplySettingsFontScale(newScale, oldScale, source)
    local reason = source == "slider" and "font_scale_slider" or "font_scale_preset"
    local function applyNow()
        if T.Style and T.Style.ApplyFontScale then
            T.Style.ApplyFontScale(reason)
        end
    end

    if source ~= "slider" then
        fontScaleApplySerial = fontScaleApplySerial + 1
        applyNow()
        return
    end

    fontScaleApplySerial = fontScaleApplySerial + 1
    local serial = fontScaleApplySerial
    C_Timer.After(0.06, function()
        if serial ~= fontScaleApplySerial then
            return
        end
        applyNow()
    end)
end

EnsureSettingsLayout = function()
    if not settingsPanel or settingsPanel.initialized then
        return
    end

    local leftPanel = CreateFrame("Frame", nil, settingsPanel)
    leftPanel:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 8, -10)
    leftPanel:SetPoint("BOTTOMLEFT", settingsPanel, "BOTTOMLEFT", 8, 6)
    leftPanel:SetWidth(GetSettingsSidebarWidth())

    local navInnerWidth = GetSettingsSidebarInnerWidth()

    local searchFrame = T.OptionSearch.Create(leftPanel, navInnerWidth)
    searchFrame:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 10, -12)

    runtimeTestStartButton = T.CreateActionButton(leftPanel, {
        width = 92,
        height = 24,
        point = { "BOTTOMLEFT", searchFrame, "TOPLEFT", 0, 30 },
        textFn = function()
            return ResolveText("RUNTIME_TEST_START_BUTTON", "运行测试")
        end,
        onClick = function()
            if T.RuntimeTestControls and T.RuntimeTestControls.Start then
                T.RuntimeTestControls:Start()
            end
        end,
    })
    runtimeTestStopButton = T.CreateActionButton(leftPanel, {
        width = 92,
        height = 24,
        point = { "LEFT", runtimeTestStartButton, "RIGHT", 8, 0 },
        textFn = function()
            return ResolveText("RUNTIME_TEST_STOP_BUTTON", "停止测试")
        end,
        onClick = function()
            if T.RuntimeTestControls and T.RuntimeTestControls.Stop then
                T.RuntimeTestControls:Stop()
            end
        end,
    })
    runtimeTestStartButton:Hide()
    runtimeTestStopButton:Hide()

    local navScroll = T.CreateSimpleScroll(leftPanel, {
        stepSize = 26,
    })
    navScroll:SetPoint("TOPLEFT", searchFrame, "BOTTOMLEFT", 0, -12)
    navScroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -10, 6)

    local navTree = T.NavTree.Create(navScroll.content, navInnerWidth)
    navTree:SetPoint("TOPLEFT", navScroll.content, "TOPLEFT", 0, 0)
    navTree:HookScript("OnSizeChanged", function(self)
        navScroll:SetContentHeight(self:GetHeight())
    end)

    local scroll = T.CreateSimpleScroll(settingsPanel, { stepSize = 48 })
    scroll:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 12, 0)
    scroll:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMRIGHT", 0, 6)

    -- GUI=900, 面板inset=24*2, 左面板=SIDEBAR_WIDTH, 间距=12, 右余量=20
    local contentWidth = GetSettingsContentWidth()

    T.OptionEngine:Initialize(scroll.content, GUI, scroll)
    T.OptionEngine:SetRenderCallback(function(categories)
        navTree:SetModules(categories)
        local activeModuleId = T.OptionEngine:GetActiveModuleForOffset(scroll:GetOffset() or 0)
        navTree:SetActiveModule(activeModuleId)
        navScroll:SetContentHeight(navTree:GetHeight())
    end)

    navTree:SetOnNavigate(function(moduleId)
        NavigateSettingsModule(moduleId)
        if moduleId == "tacticTranslator" and T.FocusTacticTranslatorInput then
            C_Timer.After(0.05, function()
                if settingsPanel and settingsPanel:IsShown() then
                    T.FocusTacticTranslatorInput()
                end
            end)
        end
    end)

    scroll:SetScrollChangedCallback(function(_, offset)
        local pendingModuleId = settingsPanel.pendingNavModuleId
        if pendingModuleId then
            local target = tonumber(settingsPanel.pendingNavAnchor) or 0
            if math.abs((tonumber(offset) or 0) - target) <= 1 then
                settingsPanel.pendingNavModuleId = nil
                settingsPanel.pendingNavAnchor = nil
            end
            navTree:SetActiveModule(pendingModuleId)
            lastSettingsModuleId = pendingModuleId
            return
        end
        local activeModuleId = T.OptionEngine:GetActiveModuleForOffset(offset or 0)
        navTree:SetActiveModule(activeModuleId)
        if activeModuleId and settingsPanel:IsShown() and not settingsPanel.suppressLastModuleUpdate then
            lastSettingsModuleId = activeModuleId
        end
    end)

    searchFrame:SetOnQueryChanged(function(query)
        T.OptionEngine:SetSearchQuery(query)
    end)

    settingsPanel.leftPanel = leftPanel
    settingsPanel.searchFrame = searchFrame
    settingsPanel.navScroll = navScroll
    settingsPanel.navTree = navTree
    settingsPanel.scroll = scroll
    settingsPanel.initialized = true
    UpdateRuntimeTestButtonsVisibility()

    settingsPanel.suppressLastModuleUpdate = true
    T.OptionEngine:RenderAll(scroll.content, contentWidth)
    settingsPanel.suppressLastModuleUpdate = nil
    RestoreSettingsModule()
end

local function ReleaseSettingsRenderTree(reason)
    if settingsPanel and not settingsPanel.initialized then
        return
    end
    if T.OptionEngine and T.OptionEngine.ReleaseRenderTree then
        if settingsPanel then
            settingsPanel.suppressLastModuleUpdate = true
        end
        T.OptionEngine:ReleaseRenderTree(reason)
        if settingsPanel then
            settingsPanel.suppressLastModuleUpdate = nil
        end
    end
end

local function RefreshTabs()
    if not guiTabGroup then
        return
    end
    for index, button in ipairs(guiTabGroup.buttons or {}) do
        if button and button.SetText then
            button:SetText(GetTabTitle(index))
        end
    end
end

local function SwitchTab(index)
    local normalized = NormalizeAvailableTab(index)
    if guiTabGroup then
        guiTabGroup:SetActiveTab(normalized)
    else
        ApplyTabVisibility(normalized)
    end
end

local function EnsureGUICreated()
    if GUI then
        return true
    end
    if not T.CreateGUI then
        return false
    end

    if C and C.DB and C.DB.safeMode then
        T.msg("检测到安全模式，按需创建GUI（本次会话）")
    end

    local ok, err = xpcall(T.CreateGUI, geterrorhandler())
    if not ok and err then
        T.msg("GUI创建失败（已拦截）: " .. tostring(err))
        return false
    end
    return GUI ~= nil
end

function T.GetGUIMemoryState()
    return {
        root = GUI ~= nil,
        settings = settingsPanel ~= nil,
        settingsInitialized = settingsPanel and settingsPanel.initialized == true,
        settingsRenderTree = T.OptionEngine and T.OptionEngine.renderRoot ~= nil,
        plan = planPanel ~= nil,
        visualBoard = visualBoardPanel ~= nil,
    }
end

T.IsGUIInteractionLocked = function()
    return isResizing
end

T.SwitchToTab = function(index)
    if not EnsureGUICreated() then
        T.msg("GUI模块未加载")
        return
    end
    local normalized = NormalizeAvailableTab(index)
    if GUI and not GUI:IsShown() then
        pendingInitialTab = normalized
        GUI:Show()
        return
    end
    SwitchTab(normalized)
end

T.SwitchToSemanticTab = function()
    T.SwitchToTab(2)
end

T.SwitchToVisualBoardTab = function()
    T.SwitchToTab(3)
end

T.OpenSettingsModule = function(moduleId)
    if not EnsureGUICreated() then
        T.msg("GUI模块未加载")
        return
    end

    local function navigate()
        SwitchTab(1)
        if not (settingsPanel and settingsPanel.initialized) then
            return
        end
        if NavigateSettingsModule(moduleId) then
            return
        end
        if moduleId and settingsPanel.navTree and settingsPanel.navTree.SetActiveModule then
            settingsPanel.navTree:SetActiveModule(moduleId)
        end
    end

    if GUI and not GUI:IsShown() then
        GUI:Show()
        C_Timer.After(0.05, navigate)
        return
    end

    navigate()
end

T.ToggleGUI = function()
    if not EnsureGUICreated() then
        T.msg("GUI模块未加载")
        return
    end

    local session = T.ScreenReminderEditSession
    if session and session.IsActive and session:IsActive() then
        session:Exit()
        return
    end

    if GUI:IsShown() then
        GUI:Hide()
    else
        GUI:Show()
    end
end

local function EnsureSemanticEditorLoaded()
    if T.ActivateColdFeature then
        T.ActivateColdFeature("semanticTimeline.editorLoaded")
    end
    if T.SemanticTimeline and T.SemanticTimeline.OnEnable then
        T.SemanticTimeline:OnEnable("plan_panel_show")
    end
    return T.SemanticTimelineGUI and T.SemanticTimelineGUI.CreateInterface
end

local function EnsureVisualBoardEditorLoaded()
    if T.ActivateColdFeature then
        T.ActivateColdFeature("visualBoard.editorLoaded")
    end
    return T.VisualBoardEditorGUI and T.VisualBoardEditorGUI.CreateInterface
end

local function BuildMainPanels()
    local panelInsetTop = -60
    local panelInsetBottom = 52

    planPanel = CreateFrame("Frame", nil, GUI)
    planPanel:SetPoint("TOPLEFT", GUI, "TOPLEFT", 24, panelInsetTop)
    planPanel:SetPoint("BOTTOMRIGHT", GUI, "BOTTOMRIGHT", -24, panelInsetBottom)
    planPanel:Hide()
    T.SemanticTimelinePanel = planPanel

    planPanel:SetScript("OnShow", function(self)
        EnsureSemanticEditorLoaded()
        if not self.initialized then
            if T.SemanticTimelineGUI and T.SemanticTimelineGUI.CreateInterface then
                T.SemanticTimelineGUI.CreateInterface(self)
                self.initialized = true
            else
                T.msg("语义时间轴模块尚未加载")
            end
        end
        if T.SemanticTimeline and T.SemanticTimeline.EnsureEditorWorkbenchReady then
            T.SemanticTimeline:EnsureEditorWorkbenchReady("plan_panel_show")
        end
        if T.SemanticTimeline and T.SemanticTimeline.ApplyAutoBossSelection then
            T.SemanticTimeline:ApplyAutoBossSelection("semantic_panel_show")
        end
        if T.SemanticTimelineGUI and T.SemanticTimelineGUI.ApplySavedLayout then
            T.SemanticTimelineGUI.ApplySavedLayout()
        end
        if T.SemanticTimelineGUI and T.SemanticTimelineGUI.RefreshData then
            T.SemanticTimelineGUI.RefreshData("panel_show")
        end
        UpdateResizeHandleVisibility()
    end)

    planPanel:SetScript("OnHide", function()
        UpdateResizeHandleVisibility()
    end)

    settingsPanel = CreateFrame("Frame", nil, GUI)
    settingsPanel:SetPoint("TOPLEFT", GUI, "TOPLEFT", 24, panelInsetTop)
    settingsPanel:SetPoint("BOTTOMRIGHT", GUI, "BOTTOMRIGHT", -24, panelInsetBottom)
    settingsPanel:Hide()
    T.SettingsPanel = settingsPanel

    settingsPanel:SetScript("OnShow", function()
        if not settingsPanel.initialized then
            return
        end
        if T.OptionEngine and T.OptionEngine.CancelRenderRelease then
            T.OptionEngine:CancelRenderRelease()
        end
        if T.OptionEngine and not T.OptionEngine.renderRoot and T.OptionEngine.Rebuild then
            settingsPanel.suppressLastModuleUpdate = true
            T.OptionEngine:Rebuild()
            settingsPanel.suppressLastModuleUpdate = nil
        end
        T.OptionEngine:RefreshDependStates()
        RestoreSettingsModule()
        local function FocusActiveSettingsModule()
            if not (T.FocusTacticTranslatorInput and settingsPanel.scroll and T.OptionEngine and T.OptionEngine.GetActiveModuleForOffset) then
                return
            end
            local activeModuleId = T.OptionEngine:GetActiveModuleForOffset(settingsPanel.scroll:GetOffset() or 0)
            if activeModuleId == "tacticTranslator" then
                T.FocusTacticTranslatorInput()
            end
        end
        if not settingsPanel.firstShowDone then
            settingsPanel.firstShowDone = true
            C_Timer.After(0.05, function()
                if settingsPanel:IsShown() then
                    FocusActiveSettingsModule()
                end
            end)
            return
        end
        C_Timer.After(0.05, function()
            if settingsPanel:IsShown() then
                FocusActiveSettingsModule()
            end
        end)
    end)

    settingsPanel:SetScript("OnHide", function()
        ReleaseSettingsRenderTree("settings_hide")
    end)

    visualBoardPanel = CreateFrame("Frame", nil, GUI)
    visualBoardPanel:SetPoint("TOPLEFT", GUI, "TOPLEFT", 24, panelInsetTop)
    visualBoardPanel:SetPoint("BOTTOMRIGHT", GUI, "BOTTOMRIGHT", -24, panelInsetBottom)
    visualBoardPanel:Hide()
    T.VisualBoardPanel = visualBoardPanel

    visualBoardPanel:SetScript("OnShow", function(self)
        EnsureVisualBoardEditorLoaded()
        if not self.initialized then
            if T.VisualBoardEditorGUI and T.VisualBoardEditorGUI.CreateInterface then
                T.VisualBoardEditorGUI.CreateInterface(self)
                self.initialized = true
            else
                T.msg("视觉画板编辑器尚未加载")
            end
        elseif T.VisualBoardEditorGUI and T.VisualBoardEditorGUI.RefreshAll then
            T.VisualBoardEditorGUI:RefreshAll()
        end
    end)
end

local function CreateReloadPopup()
    StaticPopupDialogs["STT_RELOAD_UI"] = {
        text = (L["语言切换成功"] or "语言切换成功") .. "\n\n" .. (L["需要重载界面"] or "需要重载界面") .. "?",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local function CreateLayoutResetPopup()
    StaticPopupDialogs["STT_RESET_PLAN_LAYOUT"] = {
        text = L["RESET_PLAN_LAYOUT_CONFIRM"] or "确定要重置战术方案的窗口大小、位置和分隔线比例吗？",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            local ui = GetSemanticUILayout()
            if not ui then
                return
            end

            ui.planWidth = DEFAULT_GUI_WIDTH
            ui.planHeight = DEFAULT_GUI_HEIGHT
            ui.planPosX = nil
            ui.planPosY = nil
            ui.dividerRatio = 0.5
            if type(ui.perViewMode) == "table" then
                if type(ui.perViewMode.vertical) == "table" then
                    ui.perViewMode.vertical.dividerRatio = 0.5
                end
                if type(ui.perViewMode.horizontal) == "table" then
                    ui.perViewMode.horizontal.dividerRatio = 0.8
                end
            end
            ui.lastTab = 1
            T.msg(L["RESET_PLAN_LAYOUT_DONE"] or "战术方案布局已重置，下次打开战术方案时生效")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local function CreateNicknamePopup()
    StaticPopupDialogs[addon_name .. "_NicknameInput"] = {
        text = L["昵称说明"],
        button1 = L["确认"],
        button2 = L["取消"],
        hasEditBox = true,
        editBoxWidth = 200,
        OnShow = function(self)
            local editBox = _G[self:GetName() .. "EditBox"]
            if editBox then
                editBox:SetText(C.DB.mynickname or "")
                editBox:SetFocus()
                editBox:HighlightText()
            end
        end,
        OnAccept = function(self)
            local editBox = _G[self:GetName() .. "EditBox"]
            if not editBox then
                return
            end
            local nickname = strtrim(editBox:GetText() or "")
            C.DB.mynickname = nickname
            STT_DB.mynickname = nickname
            if nickname ~= "" then
                T.msg(string.format(L["昵称已设置"], nickname))
            else
                T.msg(L["昵称已清空"])
            end
            if T.RefreshUI then
                T.RefreshUI()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

T.CreateGUI = function()
    if GUI then
        return
    end

    GUI = CreateFrame("Frame", addon_name .. "_GUI", UIParent)
    T.GUI = GUI
    GUI:SetSize(DEFAULT_GUI_WIDTH, DEFAULT_GUI_HEIGHT)
    GUI:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    GUI:SetFrameStrata("HIGH")
    GUI:SetFrameLevel(2)
    GUI:Hide()
    GUI:SetMovable(true)
    GUI:SetResizable(true)
    if GUI.SetResizeBounds then
        GUI:SetResizeBounds(DEFAULT_GUI_WIDTH, DEFAULT_GUI_HEIGHT)
    elseif GUI.SetMinResize then
        GUI:SetMinResize(DEFAULT_GUI_WIDTH, DEFAULT_GUI_HEIGHT)
    end
    GUI:EnableMouse(true)
    GUI:SetHitRectInsets(0, 0, -45, 0)
    GUI:EnableMouseWheel(true)
    GUI:SetScript("OnMouseWheel", function()
    end)
    if T.MarkPingBlocker then
        T.MarkPingBlocker(GUI, true)
    end

    local titleText = GUI:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", GUI, "TOP", 0, 6)
    titleText:SetText(T.addon_cname or L["STT"] or "STT")
    GUI.TitleText = titleText
    if T.FrameSkin then
        T.FrameSkin:Register(GUI, "main")
        T.FrameSkin:Apply(GUI, "main")
    end

    local closeButton = CreateFrame("Button", nil, GUI, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 5, 5)
    closeButton:SetScript("OnClick", function()
        GUI:Hide()
    end)
    GUI.CloseButton = closeButton

    GUI:RegisterForDrag("LeftButton")
    GUI:SetScript("OnDragStart", function(self)
        if isResizing then
            return
        end
        self:StartMoving()
    end)
    GUI:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local session = T.ScreenReminderEditSession
        if session and session.IsActive and session:IsActive() then
            if session.SaveCapsuleDock then
                session:SaveCapsuleDock()
            end
            return
        end
        if IsResizableTab(currentTab) then
            SavePlanWindowLayout("drag_stop")
        else
            SavePlanWindowPosition("drag_stop")
        end
    end)
    GUI:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            FinishResize("resize_mouseup")
        end
    end)
    tinsert(UISpecialFrames, GUI:GetName())

    BuildMainPanels()

    resizeHandle = CreateFrame("Frame", nil, GUI)
    resizeHandle:SetSize(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE)
    resizeHandle:SetPoint("BOTTOMRIGHT", GUI, "BOTTOMRIGHT", 0, 0)
    resizeHandle:EnableMouse(true)
    resizeHandle:SetHitRectInsets(-6, 0, 0, -6)
    resizeHandle:SetFrameLevel(GUI:GetFrameLevel() + 10)
    resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not IsResizableTab(currentTab) then
            return
        end
        isResizing = true
        GUI:Raise()
        AnchorGUIToTopLeft()
        GUI:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            FinishResize("resize_mouseup")
        end
    end)
    resizeHandle:Hide()

    local tabs = {
        { key = 1, text = GetTabTitle(1), name = addon_name .. "MainTab1" },
        { key = 2, text = GetTabTitle(2), name = addon_name .. "MainTab2" },
        { key = 3, text = GetTabTitle(3), name = addon_name .. "MainTab3" },
    }

    guiTabGroup = T.CreateTabGroup(GUI, {
        style = "panel",
        point = { "TOPLEFT", GUI, "BOTTOMLEFT", 10, -8 },
        spacing = 4,
        tabs = tabs,
        onChange = function(index)
            local normalized = NormalizeTabIndex(index)
            if currentTab == normalized then
                return
            end
            ShowRequestedTab(normalized)
        end,
    })

    CreateReloadPopup()
    CreateLayoutResetPopup()
    CreateNicknamePopup()
    RefreshTabs()

    T.RefreshUI = function()
        if not GUI then
            return
        end

        if GUI.TitleText then
            GUI.TitleText:SetText(T.addon_cname or L["STT"] or "STT")
        end
        if runtimeTestStartButton and runtimeTestStartButton.Refresh then
            runtimeTestStartButton:Refresh()
        end
        if runtimeTestStopButton and runtimeTestStopButton.Refresh then
            runtimeTestStopButton:Refresh()
        end
        UpdateRuntimeTestButtonsVisibility()
        RefreshTabs()

        if settingsPanel and settingsPanel.initialized then
            settingsPanel.searchFrame:RefreshTexts()
            T.OptionEngine:RefreshAllTexts()
        end

        if T.SemanticTimelineGUI and T.SemanticTimelineGUI.RefreshLocalization then
            T.SemanticTimelineGUI.RefreshLocalization()
        end

        if T.VisualBoardEditorGUI and T.VisualBoardEditorGUI.RefreshLocalization then
            T.VisualBoardEditorGUI.RefreshLocalization()
        end

        if StaticPopupDialogs["STT_RELOAD_UI"] then
            StaticPopupDialogs["STT_RELOAD_UI"].text = (L["语言切换成功"] or "语言切换成功") .. "\n\n" .. (L["需要重载界面"] or "需要重载界面") .. "?"
        end
        if StaticPopupDialogs["STT_RESET_PLAN_LAYOUT"] then
            StaticPopupDialogs["STT_RESET_PLAN_LAYOUT"].text = L["RESET_PLAN_LAYOUT_CONFIRM"] or "确定要重置战术方案的窗口大小、位置和分隔线比例吗？"
        end
        if StaticPopupDialogs[addon_name .. "_NicknameInput"] then
            StaticPopupDialogs[addon_name .. "_NicknameInput"].text = L["昵称说明"]
            StaticPopupDialogs[addon_name .. "_NicknameInput"].button1 = L["确认"]
            StaticPopupDialogs[addon_name .. "_NicknameInput"].button2 = L["取消"]
        end
    end

    GUI:SetScript("OnShow", function()
        local ui = GetSemanticUILayout()
        local tab = NormalizeAvailableTab(pendingInitialTab or (ui and ui.lastTab) or 1)
        pendingInitialTab = nil

        ApplyTabFrameRect(tab)
        ApplyTabVisibility(tab)
        if tab == 1 then
            EnsureSettingsLayout()
            T.OptionEngine:RefreshDependStates()
        end
        if T.SemanticTimeline and T.SemanticTimeline.ApplyAutoBossSelection then
            T.SemanticTimeline:ApplyAutoBossSelection("gui_show")
        end
    end)

    GUI:SetScript("OnHide", function()
        local session = T.ScreenReminderEditSession
        if session and session.IsActive and session:IsActive() then
            session:Abort()
        end
        ReleaseSettingsRenderTree("gui_hide")
        FinishResize("gui_hide")
        GUI:StopMovingOrSizing()
        local ui = GetSemanticUILayout()
        if ui then
            ui.lastTab = NormalizeTabIndex(currentTab or ui.lastTab or 1)
        end
        if IsResizableTab(currentTab) then
            SavePlanWindowLayout("gui_hide")
        end
        if T.SemanticTimelineGUI and T.SemanticTimelineGUI.OnPanelHide then
            T.SemanticTimelineGUI.OnPanelHide()
        end
        if T.SemanticTimeline and T.SemanticTimeline.WipeCompiledPlanCache then
            T.SemanticTimeline:WipeCompiledPlanCache()
        end
        -- 收口：主面板关闭 → 锁回所有 solo 解锁锚点（自我位置标记/分段进度条/屏幕提醒/鲁拉符文面板/打断轮替/贝洛朗光环）
        if T.EditMode and T.EditMode.ExitAllSolo then
            T.EditMode:ExitAllSolo()
        end
        -- 屏幕提醒走自己的 SetLocked 业务通道（除了 EditMode 还要写 Schema.locked + 触发 onAnchorChanged）
        if T.ScreenReminder and T.ScreenReminder.SetLocked and not T.ScreenReminder:IsLocked() then
            T.ScreenReminder:SetLocked(true)
        end
        -- 鲁拉符文面板同理（它的 SetLocked 还要 Hide 面板 + StopChatMirrorTimers）
        if T.DreadElegy and T.DreadElegy.SetLocked and not T.DreadElegy:IsLocked() then
            T.DreadElegy:SetLocked(true)
        end
    end)
end
