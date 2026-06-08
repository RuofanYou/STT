local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("realtimeBoard.enabled", function()

-- 实时战术板模块：负责把时间轴以结构化行列表方式呈现在屏幕侧边。
-- 数据源引用 TimelineRunner 维护的运行时时间轴；显示层再通过 displayList 做二次映射。
local existingShell = T.ModuleLoader:Get("RealtimeBoard")
if existingShell and existingShell._isColdShell and not T.RealtimeBoard then
    T.ModuleLoader.modules["RealtimeBoard"] = nil
    for index, name in ipairs(T.ModuleLoader.order or {}) do
        if name == "RealtimeBoard" then
            table.remove(T.ModuleLoader.order, index)
            break
        end
    end
end
local RealtimeBoard = T.ModuleLoader:NewModule({
    name = "RealtimeBoard",
    dbKey = "realtimeBoard.enabled",
    defaultEnabled = false,
    initialized = false,
})
T.RealtimeBoard = RealtimeBoard

-- 颜色常量：集中管理不同状态下的视觉反馈，避免散落硬编码。
local COLORS = {
    indicatorActive = { 0.30, 0.85, 0.55, 1.0 },
    indicatorUpcoming = { 0.60, 0.60, 0.60, 0.3 },
    rowBgActive = { 0.20, 0.50, 0.35, 0.25 },
    rowActiveGlow = { 1.00, 0.95, 0.10, 0.9 },
    rowBgUpcoming = { 0.12, 0.12, 0.16, 0.10 },
    rowBgExpired = { 0.08, 0.08, 0.10, 0.15 },
    timeActive = { 0.30, 1.00, 0.55, 1.0 },
    timeNear = { 1.00, 0.85, 0.30, 1.0 },
    timeUrgent = { 1.00, 0.40, 0.35, 1.0 },
    timeFuture = { 0.75, 0.75, 0.80, 1.0 },
    timeExpired = { 0.45, 0.45, 0.48, 0.6 },
    descActive = { 1.00, 1.00, 1.00, 1.0 },
    descUpcoming = { 0.82, 0.82, 0.85, 1.0 },
    descExpired = { 0.50, 0.50, 0.52, 0.6 },
    frameBg = { 0.06, 0.06, 0.08, 1.0 },
    headerBg = { 0.10, 0.10, 0.13, 1.0 },
    headerText = { 0.90, 0.90, 0.93, 1.0 },
    timerText = { 0.30, 0.85, 0.55, 1.0 },
}

local BOARD_MIN_WIDTH = 180
local BOARD_MIN_HEIGHT = 160
local BOARD_FALLBACK_MAX_WIDTH = 1200
local BOARD_FALLBACK_MAX_HEIGHT = 900

local function NormalizeSpellDisplayMode(value)
    if value == "iconText" or value == "icon" or value == "text" then
        return value
    end
    return "iconText"
end

local FALLBACK_BAR_TEXTURES = {
    default = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    smooth = "Interface\\TargetingFrame\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}

local function ClampNumber(value, minValue, maxValue, fallback)
    local number = tonumber(value)
    if number == nil then
        number = fallback
    end
    return math.max(minValue, math.min(maxValue, number))
end

local function NormalizeColor3(value, fallback)
    local src = type(value) == "table" and value or fallback
    return {
        ClampNumber(src and src[1], 0, 1, fallback[1] or 1),
        ClampNumber(src and src[2], 0, 1, fallback[2] or 1),
        ClampNumber(src and src[3], 0, 1, fallback[3] or 1),
    }
end

local function ResolveBarTexture(textureName)
    textureName = type(textureName) == "string" and textureName ~= "" and textureName or "flat"
    if T.GetBarTexture then
        return T.GetBarTexture(textureName)
    end
    return FALLBACK_BAR_TEXTURES[textureName] or FALLBACK_BAR_TEXTURES.flat
end

local function ApplyTextureWithColor(texture, textureName, color, alpha)
    if not texture then
        return
    end
    local path = ResolveBarTexture(textureName)
    if textureName == "flat" or path == FALLBACK_BAR_TEXTURES.flat then
        texture:SetColorTexture(color[1], color[2], color[3], alpha)
        return
    end
    texture:SetTexture(path)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(color[1], color[2], color[3], alpha)
end

local function BuildClassicGlowKey(active)
    local color = NormalizeColor3(active and active.glowColor, COLORS.rowActiveGlow)
    return string.format(
        "%.3f:%.3f:%.3f:%.3f:%d:%.2f:%d:%d:%d:%d",
        color[1],
        color[2],
        color[3],
        ClampNumber(active and active.glowAlpha, 0, 1, COLORS.rowActiveGlow[4]),
        ClampNumber(active and active.glowLines, 1, 30, 4),
        ClampNumber(active and active.glowFrequency, -2, 2, 0.12),
        ClampNumber(active and active.glowLength, 1, 60, 8),
        ClampNumber(active and active.glowThickness, 1, 12, 1),
        ClampNumber(active and active.glowXOffset, -50, 50, 0),
        ClampNumber(active and active.glowYOffset, -50, 50, 0)
    )
end

-- 运行态：记录当前绑定的时间轴、滚动位置和自动跟踪状态。
local viewState = {
    timeline = nil,
    startTime = 0,
    transportTime = 0,
    transportPlaying = false,
    hasTransportState = false,
    currentIndex = 1,
    currentDisplayIndex = 1,
    activeTimelineIndex = nil,
    activeDisplayIndex = nil,
    combatElapsed = 0,
    isAutoScroll = true,
    manualScrollTime = 0,
    isRunning = false,
    isTest = false,
    isStaticPreview = false,
}

-- 显示层索引表：统一承接过期过滤、远期过滤与方向反转。
local displayList = {}
local displaySortBuffer = {}
local missingPhaseStartLogged = {}

-- UI 与对象池：只创建可视区所需行数，避免长时间轴全量建行。
local ui = nil
local accumulator = 0
local visibilityState = "hidden"
local focusRendererMissingLogged = false
local ACTIVE_GLOW_KEY = "stt_realtime_board_active"

local function HasFocusRenderer(cause)
    local ready = RealtimeBoard.RefreshFocusFrame and RealtimeBoard.RefreshFocusRows and RealtimeBoard.EnsureFocusContainer
    if ready then
        return true
    end
    if T.debug and not focusRendererMissingLogged then
        focusRendererMissingLogged = true
        T.debug("[RealtimeBoard] focus_renderer_missing cause=" .. tostring(cause))
    end
    return false
end

local function ResetFocusState(reason)
    if RealtimeBoard.ResetFocusState then
        RealtimeBoard:ResetFocusState(reason)
    end
end

local function ApplyBoardResizeBounds(frame)
    if not frame or not frame.SetResizeBounds then
        if frame and frame.SetMinResize then
            frame:SetMinResize(BOARD_MIN_WIDTH, BOARD_MIN_HEIGHT)
        end
        return
    end

    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or BOARD_FALLBACK_MAX_WIDTH
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or BOARD_FALLBACK_MAX_HEIGHT
    local maxWidth = math.max(BOARD_FALLBACK_MAX_WIDTH, math.floor(screenWidth * 0.95))
    local maxHeight = math.max(BOARD_FALLBACK_MAX_HEIGHT, math.floor(screenHeight * 0.95))
    frame:SetResizeBounds(BOARD_MIN_WIDTH, BOARD_MIN_HEIGHT, maxWidth, maxHeight)
end

local function EnsureDB()
    C.DB.realtimeBoard = C.DB.realtimeBoard or {}
    C.DB.realtimeBoard.position = C.DB.realtimeBoard.position or {}
    if C.DB.realtimeBoard.spellDisplayMode == nil then
        C.DB.realtimeBoard.spellDisplayMode = (C.DB.realtimeBoard.showSpellIcon == false) and "text" or "iconText"
    else
        C.DB.realtimeBoard.spellDisplayMode = NormalizeSpellDisplayMode(C.DB.realtimeBoard.spellDisplayMode)
    end
    C.DB.realtimeBoard.showSpellIcon = nil
    local style = C.DB.realtimeBoard.displayStyle
    if style ~= "classic" and style ~= "focus" and style ~= "concise" then
        style = "classic"
    end
    C.DB.realtimeBoard.displayStyle = style
    C.DB.realtimeBoard.activeHighlightStyle = nil
    if type(C.DB.realtimeBoard.activeHighlight) ~= "table" then
        C.DB.realtimeBoard.activeHighlight = {}
    end
    local active = C.DB.realtimeBoard.activeHighlight
    active.color = NormalizeColor3(active.color, COLORS.rowBgActive)
    active.alpha = ClampNumber(active.alpha, 0, 1, COLORS.rowBgActive[4])
    active.texture = type(active.texture) == "string" and active.texture ~= "" and active.texture or "flat"
    active.indicatorWidth = ClampNumber(active.indicatorWidth, 1, 10, C.DB.realtimeBoard.indicatorWidth or 3)
    active.glowEnabled = active.glowEnabled == true
    active.glowColor = NormalizeColor3(active.glowColor, COLORS.rowActiveGlow)
    active.glowAlpha = ClampNumber(active.glowAlpha, 0, 1, COLORS.rowActiveGlow[4])
    active.glowLines = ClampNumber(active.glowLines, 1, 30, 4)
    active.glowFrequency = ClampNumber(active.glowFrequency, -2, 2, 0.12)
    active.glowLength = ClampNumber(active.glowLength, 1, 60, 8)
    active.glowThickness = ClampNumber(active.glowThickness, 1, 12, 1)
    active.glowXOffset = ClampNumber(active.glowXOffset, -50, 50, 0)
    active.glowYOffset = ClampNumber(active.glowYOffset, -50, 50, 0)
    C.DB.realtimeBoard.focus = C.DB.realtimeBoard.focus or {}
    local focus = C.DB.realtimeBoard.focus
    if C.DB.realtimeBoard.timePosition == nil then
        C.DB.realtimeBoard.timePosition = (focus.timePosition == "left" or focus.timePosition == "right") and focus.timePosition or "right"
    elseif C.DB.realtimeBoard.timePosition ~= "left" and C.DB.realtimeBoard.timePosition ~= "right" then
        C.DB.realtimeBoard.timePosition = "right"
    end
    focus.timePosition = nil
    focus.upNeighbors = focus.upNeighbors or 2
    focus.downNeighbors = focus.downNeighbors or 2
    if focus.emphasisVersion == nil then
        focus.emphasis = 0.55
        focus.emphasisVersion = 1
    end
    focus.emphasis = math.max(0, math.min(1, tonumber(focus.emphasis) or 0.55))
    focus.spacingPx = math.max(0, math.min(24, tonumber(focus.spacingPx) or tonumber(focus.gapPx) or 4))
    focus.gapPx = nil
    focus.holdSeconds = math.max(0, math.min(3, tonumber(focus.holdSeconds) or 0.7))
    if focus.departureEnabled == nil then
        if focus.settleEnabled ~= nil then
            focus.departureEnabled = focus.settleEnabled ~= false
        else
            focus.departureEnabled = focus.pulseEnabled ~= false
        end
    end
    focus.settleEnabled = nil
    focus.pulseEnabled = nil
    focus.blendSpeed = focus.blendSpeed or 0.18
    focus.align = focus.align or "left"
    if focus.widthRatioVersion == nil and focus.widthRatio == 0.82 then
        focus.widthRatio = 1.00
        focus.widthRatioVersion = 1
    end
    focus.widthRatio = focus.widthRatio or 1.00
    focus.widthRatio = math.max(0.50, math.min(1.00, tonumber(focus.widthRatio) or 1.00))
    if STT_DB then
        STT_DB.realtimeBoard = C.DB.realtimeBoard
    end
    return C.DB.realtimeBoard
end

local function EnsurePosition()
    local db = EnsureDB()
    local fallback = C.defaults.realtimeBoard.position
    local pos = db.position
    if pos.point == nil then pos.point = fallback.point end
    if pos.relPoint == nil then pos.relPoint = fallback.relPoint end
    if pos.x == nil then pos.x = fallback.x end
    if pos.y == nil then pos.y = fallback.y end
    if pos.width == nil then pos.width = fallback.width end
    if pos.height == nil then pos.height = fallback.height end
    return pos
end

local function SetVisibilityState(nextState, cause)
    if visibilityState == nextState then
        return
    end
    visibilityState = nextState
end

local function GetEventAbsoluteTime(event)
    if type(event) ~= "table" then
        return nil
    end

    local eventTime = tonumber(event.time) or 0
    if viewState.isTest then
        return tonumber(event.previewTime) or eventTime
    end
    if not event.phase then
        return eventTime
    end

    local phaseStart = T.PhaseDetector and T.PhaseDetector.GetPhaseStartTime and T.PhaseDetector:GetPhaseStartTime(event.phase) or nil
    if not phaseStart then
        if T.debug and event.phase and not missingPhaseStartLogged[event.phase] then
            missingPhaseStartLogged[event.phase] = true
            T.debug(string.format(
                "[RealtimeBoard] missing_phase_start phase=%s timelineCount=%d",
                tostring(event.phase),
                type(viewState.timeline) == "table" and #viewState.timeline or 0
            ))
        end
        return nil
    end

    return math.max(0, phaseStart - (viewState.startTime or phaseStart)) + eventTime
end

local function GetEventRemaining(event, combatElapsed)
    local absoluteTime = GetEventAbsoluteTime(event)
    if absoluteTime == nil then
        return nil
    end
    return absoluteTime - (tonumber(combatElapsed) or 0)
end

local function FindDisplayIndexByTimelineIndex(timelineIndex)
    if not timelineIndex then
        return nil
    end
    for index = 1, #displayList do
        if displayList[index] == timelineIndex then
            return index
        end
    end
    return nil
end

local function FindNextEventAbsoluteTime(timeline, startIndex)
    if type(timeline) ~= "table" then
        return nil
    end
    if timeline == viewState.timeline then
        local displayIndex = FindDisplayIndexByTimelineIndex(startIndex)
        if displayIndex then
            for index = displayIndex + 1, #displayList do
                local timelineIndex = displayList[index]
                local absoluteTime = GetEventAbsoluteTime(timeline[timelineIndex])
                if absoluteTime ~= nil then
                    return absoluteTime
                end
            end
            return nil
        end
    end
    for index = (tonumber(startIndex) or 0) + 1, #timeline do
        local absoluteTime = GetEventAbsoluteTime(timeline[index])
        if absoluteTime ~= nil then
            return absoluteTime
        end
    end
    return nil
end

local function FormatCombatTimer(seconds)
    local total = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

local function FormatCountdown(remaining, event)
    local formatMode = EnsureDB().countdownFormat or "precise"
    if formatMode == "elapsed" then
        local absoluteTime = GetEventAbsoluteTime(event)
        if absoluteTime == nil then
            return ""
        end
        return FormatCombatTimer(absoluteTime)
    end

    local value = tonumber(remaining) or 0
    if value <= 0 then
        return ""
    end
    local total = math.max(0, math.floor(value))
    if formatMode == "full" then
        return string.format("%d:%02d", math.floor(total / 60), total % 60)
    end
    if formatMode == "seconds" then
        return string.format("%ds", total)
    end
    return string.format("%.1fs", value)
end

local function GetCachedCountdown(timelineIndex, remaining, event, combatElapsed)
    local cache = viewState.countdownTextByIndex
    if cache and viewState.countdownCacheElapsed == combatElapsed then
        local countdown = cache[timelineIndex]
        if countdown ~= nil then
            return countdown
        end
    end
    return FormatCountdown(remaining, event)
end

local function GetRowState(dataIndex, remaining)
    if remaining <= 0 then
        return "expired"
    end
    if dataIndex == viewState.activeTimelineIndex then
        return "active"
    end
    return "upcoming"
end

local function GetTimeColor(state, remaining)
    if state == "expired" then
        return COLORS.timeExpired
    end
    if state == "active" then
        if remaining <= 3 then
            return COLORS.timeUrgent
        end
        if remaining <= 10 then
            return COLORS.timeNear
        end
        return COLORS.timeActive
    end
    if remaining <= 3 then
        return COLORS.timeUrgent
    end
    if remaining <= 10 then
        return COLORS.timeNear
    end
    return COLORS.timeFuture
end

local function GetRowStep()
    local db = EnsureDB()
    local rowHeight = tonumber(db.rowHeight) or 32
    if db.displayStyle == "concise" then
        rowHeight = math.min(rowHeight, 22)
    end
    return math.max(1, rowHeight + (db.rowSpacing or 0))
end

local UpdateLeftTimeSlotWidth

local function UpdateCurrentSelectionFromDisplayList(combatElapsed)
    local timeline = viewState.timeline
    local total = #displayList
    if type(timeline) ~= "table" or total == 0 then
        viewState.currentIndex = 1
        viewState.currentDisplayIndex = 1
        viewState.activeTimelineIndex = nil
        viewState.activeDisplayIndex = nil
        return
    end

    local db = EnsureDB()
    local isFocus = db.displayStyle == "focus"
    local holdSeconds = isFocus and (tonumber(db.focus and db.focus.holdSeconds) or 0.7) or 0
    local elapsed = tonumber(combatElapsed) or 0
    local selectedDisplayIndex = total
    local selectedTimelineIndex = displayList[total]
    local activeDisplayIndex = nil
    local activeTimelineIndex = nil
    local activeRemaining = nil

    for displayIndex = 1, total do
        local timelineIndex = displayList[displayIndex]
        local event = timeline[timelineIndex]
        local absoluteTime = GetEventAbsoluteTime(event)
        if absoluteTime ~= nil then
            local remaining = absoluteTime - elapsed
            if remaining > 0 and (not activeRemaining or remaining < activeRemaining) then
                activeRemaining = remaining
                activeDisplayIndex = displayIndex
                activeTimelineIndex = timelineIndex
            end

            local switchTime = absoluteTime + holdSeconds
            if isFocus and holdSeconds > 0 then
                local nextTime = FindNextEventAbsoluteTime(timeline, timelineIndex)
                if nextTime ~= nil then
                    switchTime = math.min(switchTime, nextTime)
                end
            end
            if switchTime > elapsed then
                selectedDisplayIndex = displayIndex
                selectedTimelineIndex = timelineIndex
                break
            end
        end
    end

    viewState.currentDisplayIndex = selectedDisplayIndex
    viewState.currentIndex = selectedTimelineIndex or 1
    viewState.activeDisplayIndex = activeDisplayIndex
    viewState.activeTimelineIndex = activeTimelineIndex
end

-- 重建显示列表：这里只处理“看什么、按什么顺序看”，不改底层时间轴顺序。
function RealtimeBoard:RebuildDisplayList(combatElapsed)
    wipe(displayList)
    wipe(displaySortBuffer)
    viewState.currentDisplayIndex = 1
    viewState.activeTimelineIndex = nil
    viewState.activeDisplayIndex = nil

    local timeline = viewState.timeline
    if type(timeline) ~= "table" or #timeline == 0 then
        if UpdateLeftTimeSlotWidth then
            UpdateLeftTimeSlotWidth(combatElapsed)
        end
        return
    end

    local db = EnsureDB()
    local isFocus = db.displayStyle == "focus"
    local expiredMode = db.expiredMode or "gray"
    local maxLookahead = tonumber(db.maxLookahead) or 0

    for index = 1, #timeline do
        local event = timeline[index]
        local absoluteTime = GetEventAbsoluteTime(event)
        local remaining = absoluteTime and (absoluteTime - (tonumber(combatElapsed) or 0)) or nil
        local include = true

        if remaining == nil then
            include = false
        elseif isFocus then
            include = true
        elseif remaining < 0 then
            if expiredMode == "hide" then
                include = false
            elseif expiredMode == "fade" and remaining < -2 then
                include = false
            end
        elseif maxLookahead > 0 and remaining > maxLookahead then
            include = false
        end

        if include then
            displaySortBuffer[#displaySortBuffer + 1] = {
                timelineIndex = index,
                absoluteTime = absoluteTime,
                seq = tonumber(event and event.seq) or index,
            }
        end
    end

    table.sort(displaySortBuffer, function(a, b)
        if a.absoluteTime ~= b.absoluteTime then
            return a.absoluteTime < b.absoluteTime
        end
        if a.seq ~= b.seq then
            return a.seq < b.seq
        end
        return a.timelineIndex < b.timelineIndex
    end)

    for index, entry in ipairs(displaySortBuffer) do
        displayList[index] = entry.timelineIndex
    end
    wipe(displaySortBuffer)

    if db.timeDirection == "up" and not isFocus then
        local total = #displayList
        for index = 1, math.floor(total / 2) do
            local reverseIndex = total - index + 1
            displayList[index], displayList[reverseIndex] = displayList[reverseIndex], displayList[index]
        end
    end

    UpdateCurrentSelectionFromDisplayList(combatElapsed)

    if UpdateLeftTimeSlotWidth then
        UpdateLeftTimeSlotWidth(combatElapsed)
    end
end

local function GetDisplayCount()
    return #displayList
end

local function GetScrollView()
    return ui and ui.scrollView or nil
end

function RealtimeBoard:GetCombatElapsed()
    if T.TimelineRunner and T.TimelineRunner.GetState then
        local state = T.TimelineRunner:GetState()
        if type(state) == "table" then
            return math.max(0, tonumber(state.currentTime) or 0)
        end
    end
    if viewState.hasTransportState then
        return math.max(0, tonumber(viewState.transportTime) or 0)
    end
    return math.max(0, GetTime() - (viewState.startTime or GetTime()))
end

local function UpdateHeaderTitle()
    if not (ui and ui.headerTitle) then
        return
    end

    local title = L["实时战术板"]
    local source = C.DB and C.DB.dataSource or "STN"
    if source == "STN" then
        local semantic = T.SemanticTimeline
        if semantic and semantic.GetCurrentPlanBundle then
            local bundle = semantic:GetCurrentPlanBundle({ allowActiveFallback = false })
            local planTitle = bundle and bundle.title
            if type(planTitle) == "string" and planTitle ~= "" then
                title = planTitle
            end
        end
    elseif source == "MRT" then
        title = "MRT"
    end

    ui.headerTitle:SetText(title)
end

local boardCellRenderer = nil

local function EnsureBoardCellRenderer()
    if not boardCellRenderer then
        boardCellRenderer = T.CreateCellRenderer()
    end
    return boardCellRenderer
end

local function ApplyRowFonts(row)
    local db = EnsureDB()
    row.descText:SetFont(STANDARD_TEXT_FONT, db.fontSize or 13, "OUTLINE")
    row.timeText:SetFont(STANDARD_TEXT_FONT, db.timeFontSize or 12, "OUTLINE")
end

local function GetLeftTimeSlotWidth()
    return viewState.leftTimeSlotWidth or 0
end

local function MeasureCountdownTextWidth(text)
    if not ui or text == "" then
        return 0
    end
    if not ui.timeMeasureText then
        ui.timeMeasureText = ui:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        ui.timeMeasureText:SetPoint("TOPLEFT", ui, "TOPLEFT", -1000, 1000)
        ui.timeMeasureText:SetAlpha(0)
    end
    local db = EnsureDB()
    local fontSize = db.timeFontSize or 12
    if ui.timeMeasureTextFontSize ~= fontSize then
        ui.timeMeasureText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        ui.timeMeasureTextFontSize = fontSize
    end
    ui.timeMeasureText:SetText(text or "")
    return ui.timeMeasureText:GetStringWidth() or 0
end

UpdateLeftTimeSlotWidth = function(combatElapsed)
    local db = EnsureDB()
    if db.timePosition ~= "left" then
        if viewState.leftTimeSlotWidth ~= nil then
            viewState.leftTimeSlotWidth = nil
        end
        viewState.countdownCacheElapsed = nil
        if viewState.countdownTextByIndex then
            wipe(viewState.countdownTextByIndex)
        end
        return
    end

    local countdownCache = viewState.countdownTextByIndex
    if not countdownCache then
        countdownCache = {}
        viewState.countdownTextByIndex = countdownCache
    else
        wipe(countdownCache)
    end
    viewState.countdownCacheElapsed = combatElapsed

    local maxWidth = 0
    for _, timelineIndex in ipairs(displayList) do
        local event = viewState.timeline and viewState.timeline[timelineIndex] or nil
        if event then
            local remaining = GetEventRemaining(event, combatElapsed) or 0
            local countdown = FormatCountdown(remaining, event)
            countdownCache[timelineIndex] = countdown
            maxWidth = math.max(maxWidth, MeasureCountdownTextWidth(countdown))
        end
    end
    local nextWidth = math.min(120, math.max(0, math.ceil(maxWidth + 2)))
    if viewState.leftTimeSlotWidth ~= nextWidth then
        viewState.leftTimeSlotWidth = nextWidth
    end
end

local function ApplyRowLayout(row)
    if not (ui and row) then
        return
    end

    local db = EnsureDB()
    if db.displayStyle == "concise" and T.RealtimeBoardConcise and T.RealtimeBoardConcise.ApplyRowLayout then
        T.RealtimeBoardConcise.ApplyRowLayout(row, db)
        return
    end

    local width = math.max(40, ui.scrollArea:GetWidth())
    local activeHighlight = type(db.activeHighlight) == "table" and db.activeHighlight or {}
    local indicatorWidth = db.displayStyle == "classic"
        and math.max(tonumber(db.indicatorWidth) or 3, tonumber(activeHighlight.indicatorWidth) or 3)
        or (db.indicatorWidth or 3)
    local iconGap = 6
    local iconSize = db.iconSize or 22
    local showIcon = db.spellDisplayMode ~= "text"
    local isFocus = db.displayStyle == "focus"
    local leftInset = isFocus and 8 or (indicatorWidth + 8)
    local iconLeft = isFocus and 8 or (indicatorWidth + iconGap)
    local textLeft = leftInset
    local timeWidth = 64
    local timeOnLeft = db.timePosition == "left"
    local rightInset = timeOnLeft and 8 or 72

    row:SetSize(width, db.rowHeight or 32)

    row.indicator:SetSize(indicatorWidth, db.rowHeight or 32)
    row.indicator:ClearAllPoints()
    row.indicator:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    row.rowBg:ClearAllPoints()
    row.rowBg:SetAllPoints(row)
    local content = row.contentFrame or row
    if row.contentFrame then
        row.contentFrame:SetScale(1)
        row.contentFrame:ClearAllPoints()
        row.contentFrame:SetAllPoints(row)
    end

    ApplyRowFonts(row)

    row.iconFrame:SetSize(iconSize, iconSize)
    row.iconFrame:ClearAllPoints()
    if timeOnLeft then
        timeWidth = GetLeftTimeSlotWidth()
        row.timeText:ClearAllPoints()
        row.timeText:SetPoint("LEFT", content, "LEFT", leftInset, 0)
        row.timeText:SetWidth(timeWidth)
        row.timeText:SetJustifyH("RIGHT")
        textLeft = leftInset + timeWidth + iconGap
        row.iconFrame:SetPoint("LEFT", content, "LEFT", textLeft, 0)
    else
        row.iconFrame:SetPoint("LEFT", content, "LEFT", iconLeft, 0)
    end
    row.iconBorder:ClearAllPoints()
    row.iconBorder:SetAllPoints(row.iconFrame)

    row._cellsLeftOffset = textLeft
    if showIcon then
        if timeOnLeft then
            textLeft = textLeft + iconSize + iconGap
        else
            textLeft = iconLeft + iconSize + iconGap
        end
    end

    -- cellClipFrame 用于单元格渲染（显示全部模式）
    if row.cellClipFrame then
        row.cellClipFrame:ClearAllPoints()
        row.cellClipFrame:SetPoint("LEFT", content, "LEFT", textLeft, 0)
        row.cellClipFrame:SetPoint("RIGHT", content, "RIGHT", -rightInset, 0)
        row.cellClipFrame:SetPoint("TOP", content, "TOP", 0, -1)
        row.cellClipFrame:SetPoint("BOTTOM", content, "BOTTOM", 0, 1)
    end

    row.descText:ClearAllPoints()
    row.descText:SetPoint("LEFT", content, "LEFT", textLeft, 0)
    row.descText:SetPoint("RIGHT", content, "RIGHT", -rightInset, 0)

    if not timeOnLeft then
        row.timeText:ClearAllPoints()
        row.timeText:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        row.timeText:SetWidth(timeWidth)
        row.timeText:SetJustifyH("RIGHT")
    end

    row.iconFrame:SetShown(showIcon)
end

local function StopClassicActiveGlow(row)
    if not (row and row.__sttActiveGlowKey) then
        return
    end
    local glow = LibStub and LibStub("LibCustomGlow-1.0", true) or nil
    local target = row.activeGlowFrame or row
    if glow then
        glow.PixelGlow_Stop(target, ACTIVE_GLOW_KEY)
    end
    row.__sttActiveGlowKey = nil
    if row.activeGlowFrame then
        row.activeGlowFrame:Hide()
    end
end

local function StartClassicActiveGlow(row, active)
    local glow = LibStub and LibStub("LibCustomGlow-1.0", true) or nil
    if not (glow and row and active and active.glowEnabled == true) then
        return
    end
    local alpha = ClampNumber(active.glowAlpha, 0, 1, COLORS.rowActiveGlow[4])
    if alpha <= 0 then
        StopClassicActiveGlow(row)
        return
    end
    local glowKey = BuildClassicGlowKey(active)
    if row.__sttActiveGlowKey == glowKey then
        return
    end
    StopClassicActiveGlow(row)
    local color = NormalizeColor3(active.glowColor, COLORS.rowActiveGlow)
    color[4] = alpha
    local target = row.activeGlowFrame or row
    if target.SetAllPoints then
        target:ClearAllPoints()
        target:SetAllPoints(row)
        target:Show()
    end
    row.__sttActiveGlowKey = glowKey
    glow.PixelGlow_Start(
        target,
        color,
        active.glowLines,
        active.glowFrequency,
        active.glowLength,
        active.glowThickness,
        active.glowXOffset,
        active.glowYOffset,
        false,
        ACTIVE_GLOW_KEY
    )
end

local function ApplyFocusRowChrome(row)
    row.indicator:Hide()
    StopClassicActiveGlow(row)
    row.rowBg:SetColorTexture(0, 0, 0, 0)
    row.iconBorder:SetColorTexture(0, 0, 0, 0.35)
end

local function ResetClassicActiveDecor(row, db)
    row.indicator:SetWidth(tonumber(db.indicatorWidth) or 3)
end

local function ApplyClassicActiveHighlight(row, state, db)
    ResetClassicActiveDecor(row, db)
    if state ~= "active" then
        return
    end

    local active = type(db.activeHighlight) == "table" and db.activeHighlight or {}
    local color = NormalizeColor3(active.color, COLORS.rowBgActive)
    local alpha = ClampNumber(active.alpha, 0, 1, COLORS.rowBgActive[4])
    row.indicator:SetWidth(ClampNumber(active.indicatorWidth, 1, 10, tonumber(db.indicatorWidth) or 3))
    row.indicator:SetColorTexture(color[1], color[2], color[3], 1)
    ApplyTextureWithColor(row.rowBg, active.texture, color, alpha)

    StartClassicActiveGlow(row, active)
end

function RealtimeBoard:ApplyRowStyle(row, state, remaining)
    local db = EnsureDB()
    ResetClassicActiveDecor(row, db)
    if db.displayStyle ~= "classic" or state ~= "active" then
        StopClassicActiveGlow(row)
    end
    if state == "active" then
        row.indicator:SetColorTexture(unpack(COLORS.indicatorActive))
        row.indicator:Show()
        row.rowBg:SetColorTexture(unpack(COLORS.rowBgActive))
        row.descText:SetTextColor(unpack(COLORS.descActive))
    elseif state == "upcoming" then
        row.indicator:SetColorTexture(unpack(COLORS.indicatorUpcoming))
        row.indicator:Show()
        row.rowBg:SetColorTexture(unpack(COLORS.rowBgUpcoming))
        row.descText:SetTextColor(unpack(COLORS.descUpcoming))
    else
        row.indicator:Hide()
        row.rowBg:SetColorTexture(unpack(COLORS.rowBgExpired))
        row.descText:SetTextColor(unpack(COLORS.descExpired))
    end

    -- 过期淡出只影响视觉层，底层事件数据仍由时间轴保持单一权威。
    if db.displayStyle == "focus" then
        ApplyFocusRowChrome(row)
    elseif db.displayStyle == "concise" then
        if T.RealtimeBoardConcise and T.RealtimeBoardConcise.ApplyRowChrome then
            T.RealtimeBoardConcise.ApplyRowChrome(row, state, remaining)
        end
    elseif state == "expired" and db.expiredMode == "fade" then
        row:SetAlpha(math.max(0, 1 + (tonumber(remaining) or 0) / 2))
    else
        row.iconBorder:SetColorTexture(0, 0, 0, 0.35)
        row:SetAlpha(1)
        ApplyClassicActiveHighlight(row, state, db)
    end

    row.timeText:SetTextColor(unpack(GetTimeColor(state, remaining)))
end

-- 创建单行 UI：行对象会被重复绑定到不同时间轴索引，属于对象池复用点。
function RealtimeBoard:CreateRowFrame(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetFrameStrata("HIGH")
    row:HookScript("OnHide", StopClassicActiveGlow)

    row.rowBg = row:CreateTexture(nil, "BACKGROUND")
    row.rowBg:SetAllPoints(row)

    row.indicator = row:CreateTexture(nil, "ARTWORK")
    row.indicator:SetColorTexture(1, 1, 1, 1)

    row.contentFrame = CreateFrame("Frame", nil, row)
    row.contentFrame:SetFrameLevel(row:GetFrameLevel() + 1)
    row.contentFrame:SetAllPoints(row)

    row.activeGlowFrame = CreateFrame("Frame", nil, row)
    row.activeGlowFrame:SetFrameLevel(row.contentFrame:GetFrameLevel() + 10)
    row.activeGlowFrame:SetAllPoints(row)
    row.activeGlowFrame:EnableMouse(false)
    row.activeGlowFrame:Hide()

    row.iconFrame = CreateFrame("Frame", nil, row.contentFrame, "BackdropTemplate")
    row.iconFrame:SetFrameLevel(row.contentFrame:GetFrameLevel() + 1)

    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints(row.iconFrame)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconBorder = row.iconFrame:CreateTexture(nil, "BORDER")
    row.iconBorder:SetAllPoints(row.iconFrame)
    row.iconBorder:SetColorTexture(0, 0, 0, 0.35)

    -- 单元格容器（显示全部模式用 CellRenderer 渲染）
    local cellClipFrame = CreateFrame("Frame", nil, row.contentFrame)
    cellClipFrame:SetClipsChildren(true)
    local cellContainer = CreateFrame("Frame", nil, cellClipFrame)
    cellContainer:SetPoint("LEFT", cellClipFrame, "LEFT", 0, 0)
    cellContainer:SetPoint("TOP", cellClipFrame, "TOP", 0, 0)
    cellContainer:SetPoint("BOTTOM", cellClipFrame, "BOTTOM", 0, 0)
    row.cellClipFrame = cellClipFrame
    row.cellContainer = cellContainer

    -- 回退文本（仅与我相关模式，无 cells 时使用）
    row.descText = T.CreateFontString(row.contentFrame, {
        template = "GameFontNormal",
        justifyH = "LEFT",
        justifyV = "MIDDLE",
        wordWrap = false,
    })

    row.timeText = T.CreateFontString(row.contentFrame, {
        template = "GameFontNormal",
        justifyH = "RIGHT",
        justifyV = "MIDDLE",
    })

    ApplyRowLayout(row)
    row:Hide()
    return row
end

function RealtimeBoard:UpdateCurrentIndex(combatElapsed)
    UpdateCurrentSelectionFromDisplayList(combatElapsed)
end

-- 以“当前事件在 displayList 中的位置”为锚点，兼容过滤与反向时间轴。
local function FindCurrentDisplayIndex()
    local total = #displayList
    if total == 0 then
        return 1
    end

    local db = EnsureDB()
    local displayIndex = db.displayStyle == "focus"
        and viewState.currentDisplayIndex
        or (viewState.activeDisplayIndex or viewState.currentDisplayIndex)
    displayIndex = tonumber(displayIndex) or 1
    if displayIndex < 1 then
        return 1
    end
    if displayIndex > total then
        return total
    end
    return displayIndex
end

function RealtimeBoard:ComputeAutoScrollTarget()
    local scrollView = GetScrollView()
    if not scrollView then
        return
    end

    local db = EnsureDB()
    local total = GetDisplayCount()
    if total == 0 then
        scrollView:ScrollToTop()
        return
    end

    local visibleRows = math.max(1, math.floor(ui.scrollArea:GetHeight() / GetRowStep()))
    local maxStart = math.max(1, total - visibleRows + 1)

    local displayIndex = FindCurrentDisplayIndex()
    local targetRow
    if db.anchorPosition == "top" then
        targetRow = displayIndex
    elseif db.anchorPosition == "bottom" then
        targetRow = displayIndex - visibleRows + 1
    else
        targetRow = displayIndex - math.floor(visibleRows * 0.33)
    end

    if targetRow < 1 then
        targetRow = 1
    elseif targetRow > maxStart then
        targetRow = maxStart
    end

    scrollView:SetRowHeight(GetRowStep())
    scrollView:ScrollTo((targetRow - 1) * GetRowStep())
end

function RealtimeBoard:BindRow(row, dataIndex, displayIndex, combatElapsed)
    local event = viewState.timeline and viewState.timeline[dataIndex] or nil
    if not event then
        row:Hide()
        return
    end

    local db = EnsureDB()
    local remaining = GetEventRemaining(event, combatElapsed) or 0
    local state = GetRowState(dataIndex, remaining)
    local countdown = GetCachedCountdown(dataIndex, remaining, event, combatElapsed)
    if row._lastCountdown ~= countdown then
        row.timeText:SetText(countdown)
        row._lastCountdown = countdown
    end

    if db.displayStyle == "concise" and T.RealtimeBoardConcise then
        ApplyRowLayout(row)
        T.RealtimeBoardConcise:BindRow(row, event, dataIndex, displayIndex, combatElapsed)
        row.icon:SetTexture(nil)
        row.icon:SetDesaturated(state == "expired")
        self:ApplyRowStyle(row, state, remaining)
        row:Show()
        return
    end

    ApplyRowLayout(row)

    local cells = event.cells
    if cells and #cells > 0 then
        -- 显示全部模式：用 CellRenderer 渲染所有单元格（与解析区共享渲染逻辑）
        row.descText:Hide()
        row.iconFrame:Hide()
        -- cellClipFrame 与行内文本共享左侧留白；聚焦模式不再继承经典指示条宽度。
        local db = EnsureDB()
        local indicatorWidth = db.indicatorWidth or 3
        local leftOffset = indicatorWidth + 4
        local rightOffset = -72
        if db.displayStyle == "focus" then
            leftOffset = 8
        end
        if db.timePosition == "left" then
            leftOffset = row._cellsLeftOffset or leftOffset
            rightOffset = -8
        end
        local content = row.contentFrame or row
        row.cellClipFrame:ClearAllPoints()
        row.cellClipFrame:SetPoint("LEFT", content, "LEFT", leftOffset, 0)
        row.cellClipFrame:SetPoint("RIGHT", content, "RIGHT", rightOffset, 0)
        row.cellClipFrame:SetPoint("TOP", content, "TOP", 0, -1)
        row.cellClipFrame:SetPoint("BOTTOM", content, "BOTTOM", 0, 1)
        row.cellClipFrame:Show()
        local renderer = EnsureBoardCellRenderer()
        -- 单元格 UI 配置读取 semanticTimeline.ui（SSOT 配置源，与解析区共享）
        local stDB = C.DB and C.DB.semanticTimeline
        local stUI = stDB and type(stDB.ui) == "table" and stDB.ui or {}
        local uiConfig = {
            cellWidth = stUI.cellWidth or 120,
            rowHeight = db.rowHeight or 32,
            iconSize = stUI.iconSize or 16,
            spellDisplayMode = db.spellDisplayMode or "iconText",
            showWho = db.showAudienceName ~= false,
            cellGap = db.cellStyle == "clean" and 6 or (stUI.cellGap or 2),
            cellStyle = db.cellStyle or "clean",
        }
        local xOffset = 0
        for _, cellData in ipairs(cells) do
            local cell = renderer:AcquireCell(row.cellContainer)
            local actualWidth = renderer:PopulateCell(cell, cellData, uiConfig, xOffset) or uiConfig.cellWidth
            xOffset = xOffset + actualWidth + uiConfig.cellGap
        end
        local totalWidth = math.max(0, xOffset - uiConfig.cellGap)
        row.cellContainer:SetWidth(math.max(totalWidth, row.cellClipFrame:GetWidth()))
    else
        -- 仅与我相关模式：无 cells，回退到 descText
        row.cellClipFrame:Hide()
        row.descText:Show()
        local spellDisplayMode = EnsureDB().spellDisplayMode or "iconText"
        local fallbackText = event.screenText or event.text or ""
        if spellDisplayMode == "icon" and type(event.spellHiddenScreenText) == "string" then
            fallbackText = event.spellHiddenScreenText
        end
        row.descText:SetText(fallbackText)
        if spellDisplayMode ~= "text" and event.spellIcon then
            row.icon:SetTexture(event.spellIcon)
            row.iconFrame:Show()
        else
            row.icon:SetTexture(nil)
            row.iconFrame:Hide()
        end
    end

    row.icon:SetDesaturated(state == "expired")
    self:ApplyRowStyle(row, state, remaining)
    row:Show()
end

function RealtimeBoard:RefreshVisibleRows(combatElapsed)
    local scrollView = GetScrollView()
    if not scrollView then
        return
    end

    -- 释放所有 board cells 回 pool，BindRow 会重新获取
    if boardCellRenderer then
        boardCellRenderer:ReleaseAll()
    end

    viewState.combatElapsed = combatElapsed
    scrollView:SetRowHeight(GetRowStep())
    scrollView:SetStepSize(GetRowStep() * 3)
    scrollView:SetDataCount(GetDisplayCount())
    scrollView:Refresh(true)
end

function RealtimeBoard:RefreshAtTime(combatElapsed, opts)
    if not viewState.isRunning then
        return
    end

    opts = type(opts) == "table" and opts or {}
    local db = EnsureDB()
    local nextElapsed = math.max(0, tonumber(combatElapsed) or 0)
    viewState.combatElapsed = nextElapsed
    self:UpdateCurrentIndex(nextElapsed)
    self:RebuildDisplayList(nextElapsed)

    if db.displayStyle == "focus" then
        self:UpdateHeaderTimer(nextElapsed)
        if HasFocusRenderer("refresh") then
            self:RefreshFocusRows(nextElapsed, opts.elapsed or 0, { updateContent = true })
        end
        return
    end

    local now = GetTime()
    if not viewState.isAutoScroll and (now - (viewState.manualScrollTime or 0)) >= (db.autoScrollDelay or 3) then
        viewState.isAutoScroll = true
    end
    if viewState.isAutoScroll then
        self:ComputeAutoScrollTarget()
    end
    self:RefreshVisibleRows(nextElapsed)
    self:UpdateHeaderTimer(nextElapsed)
end

function RealtimeBoard:ApplyTransportState(state, opts)
    if type(state) ~= "table" then
        return
    end

    opts = type(opts) == "table" and opts or {}
    local nextTime = math.max(0, tonumber(state.currentTime) or 0)
    local nextPlaying = state.playing == true
    local oldTime = tonumber(viewState.transportTime) or 0
    local oldPlaying = viewState.transportPlaying == true
    local timeDelta = math.abs(nextTime - oldTime)
    local playingChanged = oldPlaying ~= nextPlaying

    viewState.transportTime = nextTime
    viewState.transportPlaying = nextPlaying
    viewState.hasTransportState = true

    if timeDelta >= 0.50 then
        ResetFocusState("transport_jump")
    end

    if viewState.isRunning and (opts.force == true or playingChanged or not nextPlaying or timeDelta >= 0.50) then
        self:RefreshAtTime(nextTime, { elapsed = opts.elapsed or 0 })
    end

end

function RealtimeBoard:EnsureTransportSubscription()
    if self._runnerTransportSubscribed then
        return
    end
    local runner = T.TimelineRunner
    if not (runner and runner.Subscribe) then
        return
    end
    self._runnerTransportSubscribed = true
    self._runnerTransportUnsubscribe = runner:Subscribe(function(state)
        RealtimeBoard:ApplyTransportState(state)
    end)
end

RealtimeBoard._FocusDeps = {
    viewState = viewState,
    displayList = displayList,
    EnsureDB = EnsureDB,
    GetUI = function()
        return ui
    end,
    GetEventAbsoluteTime = GetEventAbsoluteTime,
    GetEventRemaining = GetEventRemaining,
    FindNextEventAbsoluteTime = FindNextEventAbsoluteTime,
    FindCurrentDisplayIndex = FindCurrentDisplayIndex,
    ReleaseBoardCells = function()
        if boardCellRenderer then
            boardCellRenderer:ReleaseAll()
        end
    end,
}

RealtimeBoard._ConciseDeps = {
    EnsureDB = EnsureDB,
    GetLeftTimeSlotWidth = GetLeftTimeSlotWidth,
}

function RealtimeBoard:SetDisplayStyle(style)
    local nextStyle = "classic"
    if style == "focus" or style == "concise" then
        nextStyle = style
    end
    local db = EnsureDB()
    local oldStyle = db.displayStyle or "classic"
    db.displayStyle = nextStyle
    if STT_DB then
        STT_DB.realtimeBoard = C.DB.realtimeBoard
    end

    if ui then
        if nextStyle == "focus" then
            if ui.scrollView then
                ui.scrollView:Hide()
            end
            if HasFocusRenderer("style") then
                local container = self:EnsureFocusContainer()
                if container then
                    container:Show()
                end
            end
        else
            if ui.focusContainer then
                ui.focusContainer:Hide()
            end
            if ui.scrollView then
                ui.scrollView:Show()
            end
        end
        self:RefreshLayout()
    end

end

function RealtimeBoard:UpdateHeaderTimer(combatElapsed)
    if not (ui and ui.headerTimer) then
        return
    end

    ui.headerTimer:SetText(FormatCombatTimer(combatElapsed))
    ui.header:SetShown(EnsureDB().showHeader ~= false)
end

function RealtimeBoard:RefreshLayout()
    if not ui then
        return
    end

    local db = EnsureDB()
    local pos = EnsurePosition()
    local combatElapsed = 0
    if viewState.isRunning then
        combatElapsed = self:GetCombatElapsed()
        self:UpdateCurrentIndex(combatElapsed)
        self:RebuildDisplayList(combatElapsed)
    end

    ui:SetScale(db.scale or 1)
    ui:SetSize(pos.width or 280, pos.height or 400)
    ui.bg:SetColorTexture(COLORS.frameBg[1], COLORS.frameBg[2], COLORS.frameBg[3], db.bgAlpha or 0.65)

    ui.header:SetHeight(db.headerHeight or 28)
    ui.headerBg:SetColorTexture(unpack(COLORS.headerBg))
    ui.header:SetShown(db.showHeader ~= false)

    ui.scrollArea:ClearAllPoints()
    ui.scrollArea:SetPoint("TOPLEFT", ui, "TOPLEFT", 0, -((db.showHeader ~= false) and (db.headerHeight or 28) or 0))
    ui.scrollArea:SetPoint("BOTTOMRIGHT", ui, "BOTTOMRIGHT", 0, 0)

    ui.headerTitle:SetFont(STANDARD_TEXT_FONT, math.max(11, (db.fontSize or 13) + 1), "OUTLINE")
    ui.headerTitle:SetTextColor(unpack(COLORS.headerText))
    ui.headerTimer:SetFont(STANDARD_TEXT_FONT, db.timeFontSize or 12, "OUTLINE")
    ui.headerTimer:SetTextColor(unpack(COLORS.timerText))

    if ui.scrollView then
        ui.scrollView:SetRowHeight(GetRowStep())
        ui.scrollView:SetStepSize(GetRowStep() * 3)
        ui.scrollView:SetDataCount(GetDisplayCount())
        if db.displayStyle == "focus" then
            ui.scrollView:Hide()
        else
            ui.scrollView:Show()
            ui.scrollView:Refresh(true)
        end
    end
    if db.displayStyle == "focus" and HasFocusRenderer("layout") then
        self:EnsureFocusContainer()
    end
    if ui.focusContainer then
        ui.focusContainer:SetAllPoints(ui.scrollArea)
        ui.focusContainer:SetShown(db.displayStyle == "focus")
    end

    if db.locked ~= false then
        ui.lockBtn:Hide()
        ui.resizer:Hide()
    else
        ui.lockBtn:Show()
        ui.resizer:Show()
    end

    UpdateHeaderTitle()

    if viewState.isRunning then
        if db.displayStyle == "focus" then
            if HasFocusRenderer("layout_refresh") then
                self:RefreshFocusRows(combatElapsed, 1 / math.max(1, db.maxFPS or 30))
            end
        else
            self:RefreshVisibleRows(combatElapsed)
        end
        self:UpdateHeaderTimer(combatElapsed)
    end
end

function RealtimeBoard:SavePosition()
    if not ui then
        return
    end

    local pos = EnsurePosition()
    local point, _, relPoint, x, y = ui:GetPoint()
    pos.point = point or pos.point or "TOPLEFT"
    pos.relPoint = relPoint or pos.relPoint or "TOPLEFT"
    pos.x = x or 0
    pos.y = y or 0
    pos.width = ui:GetWidth()
    pos.height = ui:GetHeight()
    if STT_DB then
        STT_DB.realtimeBoard = C.DB.realtimeBoard
    end
end

function RealtimeBoard:EnsureUI()
    if ui then
        return ui
    end
    return self:CreateUI()
end

function RealtimeBoard:RefreshVisibility(cause)
    local db = EnsureDB()
    if db.enabled == false then
        if ui then
            ui:Hide()
        end
        SetVisibilityState("hidden", cause or "disable")
        return
    end

    local hasRuntime = viewState.isRunning and type(viewState.timeline) == "table" and #viewState.timeline > 0
    local shouldShowShell = hasRuntime or db.locked == false
    if not shouldShowShell then
        if ui then
            ui:Hide()
        end
        SetVisibilityState("hidden", cause or "lock")
        return
    end

    local frame = self:EnsureUI()
    self:LoadPosition()
    self:RefreshLayout()
    frame:Show()
    if hasRuntime then
        visibilityState = "runtime"
        return
    end
    SetVisibilityState("shell", cause or "unlock")
end

function RealtimeBoard:LoadPosition()
    if not ui then
        return
    end

    local pos = EnsurePosition()
    ui:ClearAllPoints()
    ui:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    ui:SetSize(pos.width or 280, pos.height or 400)
end

function RealtimeBoard:IsLocked()
    return EnsureDB().locked ~= false
end

function RealtimeBoard:SetLocked(locked, opts)
    local db = EnsureDB()
    db.locked = locked and true or false
    if STT_DB then
        STT_DB.realtimeBoard = C.DB.realtimeBoard
    end

    if db.locked == false and db.enabled ~= false then
        self:EnsureUI()
    end

    if ui then
        ui:SetMovable(true)
        ui:EnableMouse(db.locked == false)
        if db.locked ~= false then
            ui:RegisterForDrag()
            ui.lockBtn:Hide()
            ui.resizer:Hide()
        else
            ui:RegisterForDrag("LeftButton")
            ui.lockBtn:Show()
            ui.resizer:Show()
        end
    end

    self:RefreshVisibility(db.locked ~= false and "lock" or "unlock")

    if not opts or opts.announce ~= false then
        if db.locked ~= false then
            T.msg(L["位置已锁定"])
        else
            T.msg(L["位置已解锁"])
        end
    end
end

function RealtimeBoard:ResetPosition(opts)
    local db = EnsureDB()
    local fallback = C.defaults.realtimeBoard.position
    db.position = {
        point = fallback.point,
        relPoint = fallback.relPoint,
        x = fallback.x,
        y = fallback.y,
        width = fallback.width,
        height = fallback.height,
    }
    if STT_DB then
        STT_DB.realtimeBoard = C.DB.realtimeBoard
    end

    if ui or (db.enabled ~= false and db.locked == false) then
        self:EnsureUI()
        self:LoadPosition()
        self:RefreshVisibility("reset")
    end

    if not opts or opts.announce ~= false then
        T.msg(L["位置已重置"])
    end
end

function RealtimeBoard:RefreshEnabledState()
    self:EnsureTransportSubscription()
    local db = EnsureDB()
    if db.enabled == false then
        self:Stop("disable")
        return
    end

    local state = T.TimelineRunner and T.TimelineRunner.GetRuntimeState and T.TimelineRunner:GetRuntimeState() or nil
    if state and (state.isActive or state.isRunning) then
        local activeTimeline = (db.showAllEvents and state.boardTimeline and #state.boardTimeline > 0) and state.boardTimeline or state.timeline
        if type(activeTimeline) == "table" and #activeTimeline > 0 then
            if viewState.isRunning
                and viewState.timeline == activeTimeline
                and viewState.startTime == state.startTime
                and viewState.isTest == (state.isTest and true or false)
            then
                self:ApplyTransportState(state, { force = true })
                return
            end
            self:Start(activeTimeline, state.startTime, state.isTest, { preserve = true })
            self:ApplyTransportState(state, { force = true })
            return
        end
    end
    self:Stop("stop")
end

function RealtimeBoard:RefreshConfig()
    self:RefreshEnabledState()
    if ui then
        self:RefreshLayout()
    end
    self:RefreshVisibility("config")
end

-- 测试入口：显式拦截 trigger 方案，避免误以为战术板失效。
function RealtimeBoard:RunTest()
    local text, source, bundle = nil, nil, nil
    if T.GetTimelineSourceText then
        text, source, bundle = T.GetTimelineSourceText({ silent = true })
    end

    if source == "STN" and bundle and bundle.bodyKind == "trigger" then
        T.msg(L["事件驱动模式无法使用实时战术板"])
        return false
    end

    if text and T.STNTemplate and T.STNTemplate.PreprocessText then
        local template = T.STNTemplate.PreprocessText(text)
        if template and template.bodyKind == "trigger" then
            T.msg(L["事件驱动模式无法使用实时战术板"])
            return false
        end
    end

    if T.TimelineRunner and T.TimelineRunner.StartTest then
        return T.TimelineRunner:StartTest()
    end
    return false
end

function RealtimeBoard:Start(timeline, startTime, isTest, opts)
    self:EnsureTransportSubscription()
    local db = EnsureDB()
    if db.enabled == false or type(timeline) ~= "table" or #timeline == 0 then
        self:Stop("stop")
        return false
    end

    self:EnsureUI()

    if not opts or opts.preserve ~= true then
        if ui and ui.scrollView then
            ui.scrollView:SnapTo(0)
        end
        if ui and ui.focusContainer then
            for _, row in ipairs(ui.focusContainer.rows or {}) do
                row._currentScale, row._targetScale = 1, 1
                row._currentAlpha, row._targetAlpha = 0, 0
                row._currentY, row._targetY = 0, 0
            end
        end
        viewState.isAutoScroll = true
        viewState.manualScrollTime = 0
    end

    local isStaticPreview = type(opts) == "table" and opts.staticPreview == true
    viewState.timeline = timeline
    viewState.startTime = tonumber(startTime) or GetTime()
    if isStaticPreview then
        viewState.transportTime = 0
        viewState.transportPlaying = false
        viewState.hasTransportState = true
    else
        viewState.transportTime = math.max(0, GetTime() - viewState.startTime)
        viewState.transportPlaying = false
        viewState.hasTransportState = false
    end
    viewState.isRunning = true
    viewState.isTest = isTest and true or false
    viewState.isStaticPreview = isStaticPreview
    ResetFocusState("start")
    wipe(missingPhaseStartLogged)

    local combatElapsed = self:GetCombatElapsed()
    self:UpdateCurrentIndex(combatElapsed)
    self:RebuildDisplayList(combatElapsed)
    self:ComputeAutoScrollTarget()

    accumulator = 0
    self:RefreshVisibility("runtime")
    return true
end

function RealtimeBoard:Stop(cause)
    viewState.timeline = nil
    viewState.isRunning = false
    viewState.isTest = false
    viewState.isStaticPreview = false
    viewState.startTime = 0
    viewState.transportTime = 0
    viewState.transportPlaying = false
    viewState.hasTransportState = false
    viewState.currentIndex = 1
    viewState.currentDisplayIndex = 1
    viewState.activeTimelineIndex = nil
    viewState.activeDisplayIndex = nil
    viewState.combatElapsed = 0
    viewState.isAutoScroll = true
    viewState.manualScrollTime = 0
    ResetFocusState("stop")
    accumulator = 0
    wipe(displayList)
    wipe(missingPhaseStartLogged)

    if ui then
        ui.headerTimer:SetText("0:00")
        if ui.scrollView then
            ui.scrollView:SetDataCount(0)
            ui.scrollView:SnapTo(0)
            for _, row in ipairs(ui.scrollView.rowFrames or {}) do
                row._lastCountdown = nil
                row:Hide()
            end
        end
        if boardCellRenderer then
            boardCellRenderer:ReleaseAll()
        end
        if ui.focusContainer then
            for _, row in ipairs(ui.focusContainer.rows or {}) do
                row._lastCountdown = nil
                row:Hide()
            end
        end
    end
    self:RefreshVisibility(cause or "stop")
end

function RealtimeBoard:OnRegister()
    T.RealtimeBoard = self
end

function RealtimeBoard:OnEnable()
    self:RefreshEnabledState()
    if T.RealtimeBoardConcise and T.RealtimeBoardConcise.SetColorWatcherEnabled then
        T.RealtimeBoardConcise.SetColorWatcherEnabled(true)
    end
end

function RealtimeBoard:OnDisable()
    self:Stop("module_disable")
    if self._runnerTransportUnsubscribe then
        pcall(self._runnerTransportUnsubscribe)
        self._runnerTransportUnsubscribe = nil
        self._runnerTransportSubscribed = nil
    end
    if T.RealtimeBoardConcise and T.RealtimeBoardConcise.SetColorWatcherEnabled then
        T.RealtimeBoardConcise.SetColorWatcherEnabled(false)
    end
end

function RealtimeBoard:IsRunning()
    return viewState.isRunning
end

function RealtimeBoard:CreateUI()
    if ui then
        return ui
    end

    local db = EnsureDB()
    local pos = EnsurePosition()

    local frame = CreateFrame("Frame", "STT_RealtimeBoard", UIParent, "BackdropTemplate")
    frame:SetSize(pos.width or 280, pos.height or 400)
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    ApplyBoardResizeBounds(frame)
    frame:EnableMouse(false)
    frame:RegisterForDrag()
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetColorTexture(COLORS.frameBg[1], COLORS.frameBg[2], COLORS.frameBg[3], db.bgAlpha or 0.65)

    frame.border = frame:CreateTexture(nil, "BORDER")
    frame.border:SetAllPoints(frame)
    frame.border:SetColorTexture(0, 0, 0, 0)

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.header:SetHeight(db.headerHeight or 28)

    frame.headerBg = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.headerBg:SetAllPoints(frame.header)
    frame.headerBg:SetColorTexture(unpack(COLORS.headerBg))

    frame.headerTitle = T.CreateFontString(frame.header, {
        template = "GameFontNormal",
        point = {"LEFT", frame.header, "LEFT", 10, 0},
        justifyH = "LEFT",
    })

    frame.headerTimer = T.CreateFontString(frame.header, {
        template = "GameFontNormal",
        point = {"RIGHT", frame.header, "RIGHT", -10, 0},
        justifyH = "RIGHT",
        text = "0:00",
    })

    frame.scrollView = T.CreateVirtualScroll(frame, {
        rowHeight = GetRowStep(),
        stepSize = GetRowStep() * 3,
        rowBuffer = 1,
        scrollBarRevealOnRefresh = false,
    })
    frame.scrollView:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(db.showHeader ~= false and (db.headerHeight or 28) or 0))
    frame.scrollView:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.scrollView:SetRowFactory(function(parent)
        return RealtimeBoard:CreateRowFrame(parent)
    end)
    frame.scrollView:SetRenderCallback(function(row, dataIndex)
        local timelineIndex = displayList[dataIndex]
        if not timelineIndex then
            row._lastCountdown = nil
            row:Hide()
            return
        end
        RealtimeBoard:BindRow(row, timelineIndex, dataIndex, viewState.combatElapsed or 0)
    end)

    local baseOnMouseWheel = frame.scrollView.OnMouseWheel
    function frame.scrollView:OnMouseWheel(delta)
        viewState.isAutoScroll = false
        viewState.manualScrollTime = GetTime()
        self:SetRowHeight(GetRowStep())
        self:SetStepSize(GetRowStep() * 3)
        baseOnMouseWheel(self, delta)
        RealtimeBoard:RefreshVisibleRows(RealtimeBoard:GetCombatElapsed())
    end

    frame.scrollArea = frame.scrollView.viewport
    frame.content = frame.scrollView.scrollRef

    frame:SetScript("OnDragStart", function(self)
        if RealtimeBoard:IsLocked() then
            return
        end
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        RealtimeBoard:SavePosition()
    end)

    frame:SetScript("OnSizeChanged", function(self)
        if not ui or self ~= ui then
            return
        end
        local posData = EnsurePosition()
        posData.width = self:GetWidth()
        posData.height = self:GetHeight()
        if STT_DB then
            STT_DB.realtimeBoard = C.DB.realtimeBoard
        end
        RealtimeBoard:RefreshLayout()
    end)

    -- 主循环计时器：经典列表限频重绑；聚焦模式每帧动画、限频刷新内容。
    frame:SetScript("OnUpdate", function(_, elapsed)
        if not viewState.isRunning then
            return
        end

        local db = EnsureDB()
        local now = GetTime()
        local combatElapsed = RealtimeBoard:GetCombatElapsed()
        viewState.combatElapsed = combatElapsed
        local interval = 1 / math.max(1, db.maxFPS or 30)
        if viewState.hasTransportState and not viewState.transportPlaying then
            return
        end

        if db.displayStyle == "focus" then
            if HasFocusRenderer("tick") then
                RealtimeBoard:RefreshFocusFrame(combatElapsed, elapsed, interval)
            end
            return
        end

        accumulator = accumulator + elapsed
        if accumulator < interval then
            return
        end
        accumulator = 0

        RealtimeBoard:UpdateCurrentIndex(combatElapsed)
        RealtimeBoard:RebuildDisplayList(combatElapsed)
        if not viewState.isAutoScroll and (now - (viewState.manualScrollTime or 0)) >= (EnsureDB().autoScrollDelay or 3) then
            viewState.isAutoScroll = true
        end
        if viewState.isAutoScroll then
            RealtimeBoard:ComputeAutoScrollTarget()
        end

        RealtimeBoard:RefreshVisibleRows(combatElapsed)
        RealtimeBoard:UpdateHeaderTimer(combatElapsed)
    end)

    local lockBtn = T.CreateButton(frame, {
        text = L["锁定位置"],
        width = 72,
        height = 20,
        point = { "TOPRIGHT", frame, "TOPRIGHT", -8, -4 },
    })
    lockBtn:SetScript("OnClick", function()
        RealtimeBoard:SetLocked(true)
        if T.RealtimeBoardGUI and T.RealtimeBoardGUI.RefreshTexts then
            T.RealtimeBoardGUI.RefreshTexts()
        end
    end)
    frame.lockBtn = lockBtn

    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(18, 18)
    resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function()
        if RealtimeBoard:IsLocked() then
            return
        end
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        RealtimeBoard:SavePosition()
    end)
    frame.resizer = resizer
    resizer:SetFrameLevel(frame.scrollArea:GetFrameLevel() + 10)

    ui = frame
    if T.EditMode and T.EditMode.Register and not frame._editModeRegistered then
        T.EditMode:Register({
            frame = frame,
            displayName = L["实时战术板"],
            saveFunc = function() RealtimeBoard:SavePosition() end,
            group = "blizz",
            onExit = function() RealtimeBoard:RefreshVisibility("editmode") end,
        })
        frame._editModeRegistered = true
    end
    UpdateHeaderTitle()
    self:SetLocked(db.locked ~= false, { announce = false })
    self:SetDisplayStyle(db.displayStyle or "classic")
    self:RefreshVisibility("create")
    return ui
end

T.RealtimeBoardCommands = {
    board = function(args)
        local sub = (args or ""):lower()
        if sub == "" or sub == "help" then
            T.msg("=== 实时战术板命令 ===")
            T.msg("  /st board - 切换实时战术板")
            T.msg("  /st board on - 开启实时战术板")
            T.msg("  /st board off - 关闭实时战术板")
            T.msg("  /st board test - 用当前方案测试实时战术板")
            T.msg("  /st board lock - 锁定位置")
            T.msg("  /st board unlock - 解锁位置")
            T.msg("  /st board reset - 重置位置")
            return
        end

        local db = EnsureDB()
        if sub == "test" then
            RealtimeBoard:RunTest()
            return
        end
        if sub == "lock" then
            RealtimeBoard:SetLocked(true)
            return
        end
        if sub == "unlock" then
            RealtimeBoard:SetLocked(false)
            return
        end
        if sub == "reset" then
            RealtimeBoard:ResetPosition()
            return
        end
        if sub == "on" then
            db.enabled = true
            if STT_DB then
                STT_DB.realtimeBoard = C.DB.realtimeBoard
            end
            if T.ModuleLoader then
                T.ModuleLoader:SetDesired("RealtimeBoard", true, "command")
            end
            T.msg(L["实时战术板已启用"])
            return
        end
        if sub == "off" then
            db.enabled = false
            if STT_DB then
                STT_DB.realtimeBoard = C.DB.realtimeBoard
            end
            if T.ModuleLoader then
                T.ModuleLoader:SetDesired("RealtimeBoard", false, "command")
            else
                RealtimeBoard:Stop()
            end
            T.msg(L["实时战术板已禁用"])
            return
        end

        db.enabled = not (db.enabled ~= false)
        if STT_DB then
            STT_DB.realtimeBoard = C.DB.realtimeBoard
        end
        if T.ModuleLoader then
            T.ModuleLoader:SetDesired("RealtimeBoard", db.enabled, "command")
        end
        if db.enabled then
            T.msg(L["实时战术板已启用"])
        else
            if not T.ModuleLoader then
                RealtimeBoard:Stop()
            end
            T.msg(L["实时战术板已禁用"])
        end
    end,
}

T.HandleRealtimeBoardCommand = function(cmd, args)
    if T.RealtimeBoardCommands and T.RealtimeBoardCommands[cmd] then
        T.RealtimeBoardCommands[cmd](args)
        return true
    end
    return false
end

end)
