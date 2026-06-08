local T, C = unpack(select(2, ...))
T.RegisterColdFile("realtimeBoard.enabled", function()

local RealtimeBoard = T.RealtimeBoard
if not RealtimeBoard then
    return
end

local deps = RealtimeBoard._FocusDeps or {}

local FOCUS_CHROME_ATLAS = {
    bg = "collections-slotheader",
}
local focusChromeAtlasState = {}
local focusChromeAtlasLogged = {}
local FOCUS_CATCHUP_ROWS_PER_SECOND = 12
local focusState = {
    centerDisplayIndex = nil,
    visualCenter = nil,
    logicAccumulator = 0,
}

local function EnsureDB()
    return deps.EnsureDB()
end

local function GetUI()
    return deps.GetUI and deps.GetUI() or nil
end

local function FocusAtlasExists(atlas)
    if not atlas or atlas == "" then
        return false
    end
    if focusChromeAtlasState[atlas] ~= nil then
        return focusChromeAtlasState[atlas]
    end

    local exists = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
    focusChromeAtlasState[atlas] = exists
    if not exists and T.debug and not focusChromeAtlasLogged[atlas] then
        focusChromeAtlasLogged[atlas] = true
        T.debug("[RealtimeBoard] focus_chrome_atlas missing atlas=" .. tostring(atlas))
    end
    return exists
end

local function ApplyFocusAtlas(texture, atlas, fallback)
    if texture and texture.SetAtlas and FocusAtlasExists(atlas) then
        texture:SetAtlas(atlas, false)
        texture:SetVertexColor(1, 1, 1, 1)
        return true
    end

    local color = fallback or { 0.06, 0.06, 0.08, 1.0 }
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return false
end

local function GetFocusRowScale(distance, focus)
    local d = math.abs(tonumber(distance) or 0)
    local emphasis = math.max(0, math.min(1, tonumber(focus.emphasis) or 0.55))
    if d == 0 then
        return 1.12 + emphasis * 0.28
    end
    if d == 1 then
        return 0.96 - emphasis * 0.08
    end
    if d == 2 then
        return 0.88 - emphasis * 0.10
    end
    return math.max(0.72, 0.82 - emphasis * 0.08 - (d - 3) * 0.04)
end

local function LerpNumber(fromValue, toValue, amount)
    local t = math.max(0, math.min(1, tonumber(amount) or 0))
    return (tonumber(fromValue) or 0) + ((tonumber(toValue) or 0) - (tonumber(fromValue) or 0)) * t
end

local function GetFocusVisualScale(distance, focus)
    local d = math.abs(tonumber(distance) or 0)
    local lower = math.floor(d)
    local upper = lower + 1
    return LerpNumber(GetFocusRowScale(lower, focus), GetFocusRowScale(upper, focus), d - lower)
end

local function GetFocusRowAlpha(distance, focus)
    local d = math.abs(tonumber(distance) or 0)
    local emphasis = math.max(0, math.min(1, tonumber(focus.emphasis) or 0.55))
    if d == 0 then
        return 1.00
    end
    if d == 1 then
        return math.max(0.58, 0.78 - emphasis * 0.18)
    end
    if d == 2 then
        return math.max(0.34, 0.58 - emphasis * 0.28)
    end
    return math.max(0.16, 0.38 - emphasis * 0.18 - (d - 3) * 0.08)
end

local function GetFocusVisualAlpha(distance, focus)
    local d = math.abs(tonumber(distance) or 0)
    local lower = math.floor(d)
    local upper = lower + 1
    return LerpNumber(GetFocusRowAlpha(lower, focus), GetFocusRowAlpha(upper, focus), d - lower)
end

local function ComputeFocusY(distance, focus, rowH)
    local d = tonumber(distance) or 0
    if d == 0 then
        return 0
    end

    local sign = d < 0 and 1 or -1
    local steps = math.abs(d)
    local wholeSteps = math.floor(steps)
    local partialStep = steps - wholeSteps
    local y = 0
    local gap = math.max(0, math.min(24, tonumber(focus.spacingPx) or 4))
    local previousScale = GetFocusRowScale(0, focus)

    for step = 1, wholeSteps do
        local scale = GetFocusRowScale(step, focus)
        y = y + rowH * (previousScale + scale) * 0.5 + gap
        previousScale = scale
    end

    if partialStep > 0 then
        local nextScale = GetFocusRowScale(wholeSteps + 1, focus)
        local partialScale = LerpNumber(previousScale, nextScale, partialStep)
        y = y + (rowH * (previousScale + partialScale) * 0.5 + gap) * partialStep
    end

    return sign * y
end

local function EaseInCubic(progress)
    local t = math.max(0, math.min(1, tonumber(progress) or 0))
    return t * t * t
end

local function GetFocusDepartureProgress(timelineIndex, combatElapsed, focus)
    if not focus or focus.departureEnabled == false then
        return 0
    end

    local viewState = deps.viewState
    local timeline = viewState and viewState.timeline or nil
    local event = timelineIndex and timeline and timeline[timelineIndex] or nil
    local absoluteTime = deps.GetEventAbsoluteTime(event)
    local holdSeconds = tonumber(focus.holdSeconds) or 0
    if not absoluteTime or holdSeconds <= 0 or combatElapsed < absoluteTime then
        return 0
    end

    local holdEnd = absoluteTime + holdSeconds
    local nextTime = deps.FindNextEventAbsoluteTime(timeline, timelineIndex)
    if nextTime ~= nil then
        holdEnd = math.min(holdEnd, nextTime)
    end
    local duration = holdEnd - absoluteTime
    if duration <= 0.05 then
        return 0
    end
    if combatElapsed >= holdEnd then
        return 1
    end

    local progress = math.max(0, math.min(1, (combatElapsed - absoluteTime) / duration))
    return EaseInCubic(progress)
end

local function UpdateFocusVisualCenter(targetCenter, elapsed)
    targetCenter = tonumber(targetCenter)
    if not targetCenter then
        focusState.visualCenter = nil
        return nil, false
    end

    local current = tonumber(focusState.visualCenter)
    if not current then
        focusState.visualCenter = targetCenter
        return targetCenter, false
    end

    local delta = targetCenter - current
    if math.abs(delta) <= 0.001 then
        focusState.visualCenter = targetCenter
        return targetCenter, false
    end

    local maxStep = math.max(0.02, (tonumber(elapsed) or 0) * FOCUS_CATCHUP_ROWS_PER_SECOND)
    if math.abs(delta) <= maxStep then
        current = targetCenter
    else
        current = current + (delta > 0 and maxStep or -maxStep)
    end

    focusState.visualCenter = current
    return current, math.abs(targetCenter - current) > 0.001
end

local function FindFocusRow(container, displayIndex)
    if not container or not displayIndex then
        return nil
    end
    for _, row in ipairs(container.rows or {}) do
        if not row._focusReserved and row._displayIndex == displayIndex then
            return row
        end
    end
    return nil
end

local function AcquireFocusRow(container, displayIndex, initialY, initialScale)
    local row = FindFocusRow(container, displayIndex)
    if row then
        return row, false
    end

    for _, candidate in ipairs(container.rows or {}) do
        if not candidate._focusReserved then
            candidate._displayIndex = displayIndex
            candidate._currentY = initialY or 0
            candidate._targetY = initialY or 0
            candidate._currentScale = initialScale or 1
            candidate._targetScale = initialScale or 1
            candidate._currentAlpha = 0
            candidate._targetAlpha = 0
            candidate._lastCountdown = nil
            return candidate, true
        end
    end
    return nil, false
end

function RealtimeBoard:EnsureFocusContainer()
    local ui = GetUI()
    if ui and ui.focusContainer then
        return ui.focusContainer
    end
    if not ui then
        return nil
    end

    local container = CreateFrame("Frame", nil, ui)
    container:SetAllPoints(ui.scrollArea)
    container.rows = {}
    container.focusChrome = container:CreateTexture(nil, "BACKGROUND", nil, 1)
    container.focusChrome:SetBlendMode("BLEND")
    container.focusChrome:Hide()
    for index = 1, 12 do
        local row = self:CreateRowFrame(container)
        row._currentScale, row._targetScale = 1, 1
        row._currentAlpha, row._targetAlpha = 0, 0
        row._currentY, row._targetY = 0, 0
        row._isFocusCenter = false
        container.rows[index] = row
    end
    ui.focusContainer = container
    return container
end

function RealtimeBoard:ResetFocusState()
    focusState.centerDisplayIndex = nil
    focusState.visualCenter = nil
    focusState.logicAccumulator = 0
end

function RealtimeBoard:RefreshFocusFrame(combatElapsed, elapsed, interval)
    focusState.logicAccumulator = focusState.logicAccumulator + (tonumber(elapsed) or 0)
    local updateContent = focusState.logicAccumulator >= (tonumber(interval) or 0)
    if updateContent then
        focusState.logicAccumulator = 0
        self:UpdateCurrentIndex(combatElapsed)
        self:RebuildDisplayList(combatElapsed)
        self:UpdateHeaderTimer(combatElapsed)
    end
    self:RefreshFocusRows(combatElapsed, elapsed, { updateContent = updateContent })
end

function RealtimeBoard:RefreshFocusRows(combatElapsed, elapsed, opts)
    local ui = GetUI()
    local container = self:EnsureFocusContainer()
    if not (ui and container) then
        return
    end

    local updateContent = not opts or opts.updateContent ~= false
    if updateContent and deps.ReleaseBoardCells then
        deps.ReleaseBoardCells()
    end

    local db = EnsureDB()
    local focus = db.focus or {}
    local upN = math.max(0, math.min(4, tonumber(focus.upNeighbors) or 2))
    local downN = math.max(0, math.min(4, tonumber(focus.downNeighbors) or 2))
    local rowH = db.rowHeight or 32
    local center = deps.FindCurrentDisplayIndex()
    local align = (focus.align == "center" or focus.align == "right") and focus.align or "left"
    local widthRatio = math.max(0.50, math.min(1.00, tonumber(focus.widthRatio) or 1.00))
    local rowWidth = math.max(160, (container:GetWidth() or 0) * widthRatio)
    local centerRowWidth = rowWidth / math.max(0.65, GetFocusRowScale(0, focus))
    local displayList = deps.displayList
    local centerTimelineIndex = center and displayList[center] or nil
    local departureProgress = GetFocusDepartureProgress(centerTimelineIndex, combatElapsed, focus)
    local visualCenter, isCatchingUp = UpdateFocusVisualCenter(center and (center + departureProgress) or nil, elapsed)
    local viewState = deps.viewState
    viewState.combatElapsed = combatElapsed
    container:Show()
    container:ClearAllPoints()
    container:SetAllPoints(ui.scrollArea)

    if container.focusChrome then
        local chromeHeight = math.max(18, rowH * GetFocusRowScale(0, focus) + 10)
        container.focusChrome:ClearAllPoints()
        container.focusChrome:SetSize(rowWidth + 16, chromeHeight)
        if align == "center" then
            container.focusChrome:SetPoint("CENTER", container, "CENTER", 0, 0)
        elseif align == "right" then
            container.focusChrome:SetPoint("RIGHT", container, "RIGHT", 8, 0)
        else
            container.focusChrome:SetPoint("LEFT", container, "LEFT", -8, 0)
        end
        ApplyFocusAtlas(container.focusChrome, FOCUS_CHROME_ATLAS.bg, { 0.08, 0.14, 0.20, 0.52 })
        container.focusChrome:SetAlpha(0.86)
        container.focusChrome:SetShown(centerTimelineIndex ~= nil)
    end

    if updateContent and center ~= focusState.centerDisplayIndex then
        focusState.centerDisplayIndex = center
    end

    if updateContent then
        for _, row in ipairs(container.rows or {}) do
            row._focusReserved = false
            row._focusActive = false
        end

        local rowCenter = visualCenter or center or 1
        local firstDisplayIndex = math.floor(rowCenter) - upN
        local lastDisplayIndex = math.ceil(rowCenter) + downN
        for displayIndex = firstDisplayIndex, lastDisplayIndex do
            local timelineIndex = displayIndex and displayList[displayIndex] or nil
            if timelineIndex then
                local initialDistance = displayIndex < rowCenter and -(upN + 2) or (downN + 2)
                local initialScale = GetFocusRowScale(math.abs(initialDistance), focus)
                local row = AcquireFocusRow(container, displayIndex, ComputeFocusY(initialDistance, focus, rowH), initialScale)
                row._isFocusCenter = false
                row._focusTimelineIndex = timelineIndex
                row._focusReserved = true
                row._focusActive = true
                self:BindRow(row, timelineIndex, displayIndex, combatElapsed)
            end
        end
    end

    for index = 1, #container.rows do
        local row = container.rows[index]
        if row._focusActive then
            local visualDistance = (tonumber(row._displayIndex) or center or 0) - (visualCenter or center or 0)
            row._targetScale = GetFocusVisualScale(visualDistance, focus)
            row._targetAlpha = GetFocusVisualAlpha(visualDistance, focus)
            row._targetY = ComputeFocusY(visualDistance, focus, rowH)
            row._isFocusCenter = math.abs(visualDistance) < 0.5
            if departureProgress > 0 or isCatchingUp then
                row._currentScale = row._targetScale
                row._currentAlpha = row._targetAlpha
                row._currentY = row._targetY
            else
                row._currentScale = T.DeltaLerp(row._currentScale or row._targetScale or 1, row._targetScale or 1, focus.blendSpeed, elapsed)
                row._currentAlpha = T.DeltaLerp(row._currentAlpha or 0, row._targetAlpha or 0, focus.blendSpeed, elapsed)
                row._currentY = T.DeltaLerp(row._currentY or 0, row._targetY or 0, focus.blendSpeed, elapsed)
            end
            row:SetAlpha(row._currentAlpha)
            row:SetScale(row._currentScale)
            if row.iconBorder then
                if row._isFocusCenter then
                    row.iconBorder:SetColorTexture(1, 0.82, 0, 0.9)
                else
                    row.iconBorder:SetColorTexture(0, 0, 0, 0.35)
                end
            end
            row:ClearAllPoints()
            if align == "center" then
                row:SetPoint("CENTER", container, "CENTER", 0, row._currentY)
            elseif align == "right" then
                row:SetPoint("RIGHT", container, "RIGHT", 0, row._currentY)
            else
                row:SetPoint("LEFT", container, "LEFT", 0, row._currentY)
            end
            local focusRowWidth = rowWidth / math.max(0.65, row._currentScale)
            if align ~= "left" then
                focusRowWidth = centerRowWidth
            end
            row:SetWidth(math.max(80, focusRowWidth))
            row:SetHeight(rowH)
            if row.contentFrame then
                row.contentFrame:SetScale(1)
                row.contentFrame:SetAlpha(1)
                row.contentFrame:ClearAllPoints()
                row.contentFrame:SetAllPoints(row)
            end
            row:Show()
        elseif updateContent then
            row._displayIndex = nil
            row._focusTimelineIndex = nil
            row._lastCountdown = nil
            if row.contentFrame then
                row.contentFrame:SetScale(1)
                row.contentFrame:SetAlpha(1)
                row.contentFrame:ClearAllPoints()
                row.contentFrame:SetAllPoints(row)
            end
            row:Hide()
        end
    end
end

end)
