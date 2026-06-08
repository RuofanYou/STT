local T, C, L = unpack(select(2, ...))

local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local GetTime = GetTime

local DEFAULT_STEP_SIZE = 40
local DEFAULT_BLEND_SPEED = 0.15
local DEFAULT_SCROLLBAR_WIDTH = 8
local DEFAULT_ROW_BUFFER = 1
local SNAP_THRESHOLD = 0.5
local MIN_THUMB_SIZE = 24

local SCROLLBAR_FADE_IN_DURATION  = 0.15
local SCROLLBAR_FADE_OUT_DURATION = 0.4
local SCROLLBAR_FADE_OUT_DELAY    = 1.5
local DEFAULT_TEXT_INSET = 6
local AXIS_VERTICAL = "vertical"
local AXIS_HORIZONTAL = "horizontal"

local function Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function DeltaLerp(startValue, targetValue, blendSpeed, elapsed)
    local t = Clamp((tonumber(blendSpeed) or DEFAULT_BLEND_SPEED) * (tonumber(elapsed) or 0) * 60, 0, 1)
    return startValue + (targetValue - startValue) * t
end
T.DeltaLerp = T.DeltaLerp or DeltaLerp

local function ApplyMixin(frame, mixin)
    for key, value in pairs(mixin) do
        frame[key] = value
    end
end

local function GetViewportHeight(self)
    return math_max(0, math_floor((self.viewport and self.viewport:GetHeight()) or 0))
end

local function GetViewportWidth(self)
    return math_max(0, math_floor((self.viewport and self.viewport:GetWidth()) or 0))
end

local function CountLines(text)
    local _, lineCount = tostring(text or ""):gsub("\n", "\n")
    return lineCount + 1
end

local SmoothScrollMixin = {}

function SmoothScrollMixin:SetStepSize(size)
    self.stepSize = math_max(1, tonumber(size) or DEFAULT_STEP_SIZE)
end

function SmoothScrollMixin:SetScrollBarWidth(width)
    local nextWidth = math_max(0, tonumber(width) or DEFAULT_SCROLLBAR_WIDTH)
    self.scrollBarWidth = nextWidth
    if self.viewport then
        self.viewport:ClearAllPoints()
        self.viewport:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        self.viewport:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -(nextWidth > 0 and nextWidth or 0), 0)
    end
    if self.scrollBar then
        self.scrollBar:SetWidth(math_max(1, nextWidth))
    end
    if self.UpdateScrollChildRect then
        self:UpdateScrollChildRect()
    end
end

function SmoothScrollMixin:SetBlendSpeed(speed)
    self.blendSpeed = math_max(0.01, tonumber(speed) or DEFAULT_BLEND_SPEED)
end

function SmoothScrollMixin:GetOffset()
    return tonumber(self.offset) or 0
end

function SmoothScrollMixin:GetScrollRange()
    return tonumber(self.range) or 0
end

function SmoothScrollMixin:IsScrollable()
    return self:GetScrollRange() > 0
end

function SmoothScrollMixin:GetVerticalScroll()
    return self:GetOffset()
end

function SmoothScrollMixin:GetVerticalScrollRange()
    return self:GetScrollRange()
end

function SmoothScrollMixin:SetVerticalScroll(value)
    self:SnapTo(value)
end

function SmoothScrollMixin:SetScrollChangedCallback(callback)
    self.onScrollChangedCallback = callback
end

function SmoothScrollMixin:SetViewRefreshCallback(callback)
    self.beforeViewRefreshCallback = callback
end

function SmoothScrollMixin:SetViewRefreshThrottle(seconds)
    self.viewRefreshThrottle = math_max(0, tonumber(seconds) or 0)
end

function SmoothScrollMixin:UpdateScrollBar()
    local scrollBar = self.scrollBar
    if not (scrollBar and scrollBar.Refresh) then
        return
    end
    scrollBar:Refresh()
end

function SmoothScrollMixin:SetOffset(value)
    local offset = Clamp(tonumber(value) or 0, 0, self:GetScrollRange())
    self.offset = offset

    if self.scrollRef then
        self.scrollRef:ClearAllPoints()
        self.scrollRef:SetPoint("TOPLEFT", self.viewport, "TOPLEFT", 0, math_floor(offset + 0.5))
    end

    if self.OnScrollChanged then
        self:OnScrollChanged(offset)
    end
    self:UpdateScrollBar()
end

function SmoothScrollMixin:SetScrollRange(range)
    self.range = math_max(0, tonumber(range) or 0)
    self.scrollTarget = Clamp(tonumber(self.scrollTarget) or 0, 0, self.range)
    self:SetOffset(self:GetOffset())
end

function SmoothScrollMixin:StopScrolling()
    self.isScrolling = false
    self:SetScript("OnUpdate", nil)
    self:SetOffset(self.scrollTarget or self:GetOffset())
    if self.UpdateView then
        self:UpdateView(true)
    end
end

function SmoothScrollMixin:SnapTo(value)
    self.scrollTarget = Clamp(tonumber(value) or 0, 0, self:GetScrollRange())
    self:StopScrolling()
end

function SmoothScrollMixin:ScrollTo(value)
    local target = Clamp(tonumber(value) or 0, 0, self:GetScrollRange())
    self.scrollTarget = target

    if math_abs(target - self:GetOffset()) < SNAP_THRESHOLD then
        self:SnapTo(target)
        return
    end

    self.isScrolling = true
    self:SetScript("OnUpdate", function(frame, elapsed)
        frame:OnUpdate_Easing(elapsed)
    end)
end

function SmoothScrollMixin:ScrollBy(delta)
    self:ScrollTo((self.scrollTarget or self:GetOffset()) + (tonumber(delta) or 0))
end

function SmoothScrollMixin:ScrollToTop()
    self:ScrollTo(0)
end

function SmoothScrollMixin:ScrollToBottom()
    self:ScrollTo(self:GetScrollRange())
end

function SmoothScrollMixin:OnUpdate_Easing(elapsed)
    local current = self:GetOffset()
    local target = Clamp(tonumber(self.scrollTarget) or current, 0, self:GetScrollRange())
    local diff = target - current

    if math_abs(diff) < SNAP_THRESHOLD then
        self:SnapTo(target)
        return
    end

    self:SetOffset(DeltaLerp(current, target, self.blendSpeed, elapsed))
end

function SmoothScrollMixin:OnMouseWheel(delta)
    if not self:IsScrollable() then
        return
    end

    if self.scrollBar and self.scrollBar.RevealTemporarily then
        self.scrollBar:RevealTemporarily()
    end

    local multiplier = IsShiftKeyDown() and 2 or 1
    self:ScrollBy(-(tonumber(delta) or 0) * (self.stepSize or DEFAULT_STEP_SIZE) * multiplier)
end

function SmoothScrollMixin:OnScrollChanged(offset)
    if type(self.onScrollChangedCallback) == "function" then
        self.onScrollChangedCallback(self, offset)
    end
end

local function EndThumbDrag(thumb)
    thumb.dragging = nil
    thumb:SetScript("OnUpdate", nil)
end

local function ScrollBar_OnFadeUpdate(self, elapsed)
    local current = self:GetAlpha()
    local target = self.fadeTarget or 0
    if math_abs(current - target) < 0.01 then
        self:SetAlpha(target)
        self._fading = nil
        self:SetScript("OnUpdate", nil)
        return
    end
    local step = (self.fadeSpeed or 3) * elapsed
    if current < target then
        self:SetAlpha(math_min(current + step, target))
    else
        self:SetAlpha(math_max(current - step, target))
    end
end

local function ApplyScrollBarFadeBehavior(frame)
    function frame:FadeIn()
        if self._fadeOutTimer then
            self._fadeOutTimer:Cancel()
            self._fadeOutTimer = nil
        end
        self.fadeTarget = 1
        self.fadeSpeed = 1 / SCROLLBAR_FADE_IN_DURATION
        if not self._fading then
            self._fading = true
            self:SetScript("OnUpdate", ScrollBar_OnFadeUpdate)
        end
    end

    function frame:ScheduleFadeOut()
        if self._fadeOutTimer then
            self._fadeOutTimer:Cancel()
        end
        self._fadeOutTimer = C_Timer.NewTimer(SCROLLBAR_FADE_OUT_DELAY, function()
            self._fadeOutTimer = nil
            self.fadeTarget = 0
            self.fadeSpeed = 1 / SCROLLBAR_FADE_OUT_DURATION
            if not self._fading then
                self._fading = true
                self:SetScript("OnUpdate", ScrollBar_OnFadeUpdate)
            end
        end)
    end
end

local function IsHorizontal(axis)
    return axis == AXIS_HORIZONTAL
end

local function ApplyAtlasOrientation(texture, atlas, useAtlasSize, axis)
    if IsHorizontal(axis) then
        texture:SetRotation(0)
        local atlasInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        if atlasInfo then
            texture:SetTexture(atlasInfo.file or atlasInfo.filename)
            texture:SetTexCoord(
                atlasInfo.rightTexCoord, atlasInfo.topTexCoord,
                atlasInfo.leftTexCoord, atlasInfo.topTexCoord,
                atlasInfo.rightTexCoord, atlasInfo.bottomTexCoord,
                atlasInfo.leftTexCoord, atlasInfo.bottomTexCoord
            )
            if useAtlasSize then
                texture:SetSize(atlasInfo.height or 0, atlasInfo.width or 0)
            end
            return
        end
    end

    texture:SetAtlas(atlas, useAtlasSize == true)
    texture:SetRotation(0)
end

local function GetAxisSpan(frame, axis)
    if IsHorizontal(axis) then
        return math_max(0, math_floor(frame:GetWidth() or 0))
    end
    return math_max(0, math_floor(frame:GetHeight() or 0))
end

local function GetPointerPosition(axis)
    local scale = UIParent and UIParent:GetEffectiveScale() or 1
    local cursorX, cursorY = GetCursorPosition()
    if IsHorizontal(axis) then
        return cursorX / scale
    end
    return cursorY / scale
end

local function GetRailOffset(scrollBar, thumbSpan)
    local pointerPos = GetPointerPosition(scrollBar.axis)
    local rail = scrollBar.rail
    if IsHorizontal(scrollBar.axis) then
        local railLeft = rail:GetLeft() or 0
        local railRight = rail:GetRight() or 0
        local railSpan = math_max(0, railRight - railLeft)
        local travel = math_max(0, railSpan - thumbSpan)
        local leftOffset = Clamp(pointerPos - railLeft - (thumbSpan * 0.5), 0, travel)
        return leftOffset, travel
    end

    local railTop = rail:GetTop() or 0
    local railBottom = rail:GetBottom() or 0
    local railSpan = math_max(0, railTop - railBottom)
    local travel = math_max(0, railSpan - thumbSpan)
    local topOffset = Clamp(railTop - pointerPos - (thumbSpan * 0.5), 0, travel)
    return topOffset, travel
end

local function ComputeOffsetFromPointer(scrollBar)
    local thumbSpan = GetAxisSpan(scrollBar.thumb, scrollBar.axis)
    local axisOffset, travel = GetRailOffset(scrollBar, thumbSpan)
    if travel <= 0 then
        return 0
    end
    local ratio = travel > 0 and (axisOffset / travel) or 0
    return ratio * scrollBar:GetRange()
end

local function BeginThumbDrag(scrollBar, thumb)
    thumb.dragging = true
    if scrollBar.stopOffset then
        scrollBar:stopOffset()
    end
    thumb:SetScript("OnUpdate", function()
        scrollBar:SetOffset(ComputeOffsetFromPointer(scrollBar))
    end)
end

local function JumpByRail(scrollBar)
    if not scrollBar:IsScrollable() then
        return
    end

    local value = ComputeOffsetFromPointer(scrollBar)
    if scrollBar.ScrollToOffset then
        scrollBar:ScrollToOffset(value)
        return
    end
    scrollBar:SetOffset(value)
end

local function UpdateThumbTextures(thumb, state)
    local suffix = (state == "down") and "-down"
                or (state == "over") and "-over"
                or ""
    ApplyAtlasOrientation(thumb.topTex, "minimal-scrollbar-small-thumb-top" .. suffix, true, thumb.axis)
    ApplyAtlasOrientation(thumb.bottomTex, "minimal-scrollbar-small-thumb-bottom" .. suffix, true, thumb.axis)
    ApplyAtlasOrientation(thumb.middleTex, "minimal-scrollbar-small-thumb-middle" .. suffix, false, thumb.axis)
end

local function CreateScrollBarBase(parent, opts)
    opts = type(opts) == "table" and opts or {}
    local axis = opts.axis or AXIS_VERTICAL
    local thickness = math_max(1, tonumber(opts.thickness) or DEFAULT_SCROLLBAR_WIDTH)

    local scrollBar = CreateFrame("Frame", nil, parent)
    scrollBar.axis = axis
    scrollBar.getRange = opts.getRange
    scrollBar.getOffset = opts.getOffset
    scrollBar.getPageSize = opts.getPageSize
    scrollBar.setOffset = opts.setOffset
    scrollBar.scrollToOffset = opts.scrollToOffset
    scrollBar.stopOffset = opts.stopOffset
    scrollBar.revealOnRefresh = opts.revealOnRefresh ~= false

    if IsHorizontal(axis) then
        scrollBar:SetHeight(thickness)
    else
        scrollBar:SetWidth(thickness)
    end
    scrollBar:Hide()
    scrollBar:SetAlpha(0)

    local rail = CreateFrame("Button", nil, scrollBar)
    if IsHorizontal(axis) then
        rail:SetPoint("LEFT", scrollBar, "LEFT", 0, 0)
        rail:SetPoint("RIGHT", scrollBar, "RIGHT", 0, 0)
        rail:SetHeight(thickness)
    else
        rail:SetPoint("TOP", scrollBar, "TOP", 0, 0)
        rail:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
        rail:SetWidth(thickness)
    end

    local trackTop = rail:CreateTexture(nil, "BACKGROUND")
    local trackBottom = rail:CreateTexture(nil, "BACKGROUND")
    local trackMiddle = rail:CreateTexture(nil, "BACKGROUND")
    ApplyAtlasOrientation(trackTop, "minimal-scrollbar-track-top", true, axis)
    ApplyAtlasOrientation(trackBottom, "minimal-scrollbar-track-bottom", true, axis)
    ApplyAtlasOrientation(trackMiddle, "!minimal-scrollbar-track-middle", false, axis)

    if IsHorizontal(axis) then
        trackTop:SetPoint("LEFT", rail, "LEFT", 0, 0)
        trackBottom:SetPoint("RIGHT", rail, "RIGHT", 0, 0)
        trackMiddle:SetPoint("LEFT", trackTop, "RIGHT", 0, 0)
        trackMiddle:SetPoint("RIGHT", trackBottom, "LEFT", 0, 0)
        trackMiddle:SetPoint("TOP", rail, "TOP", 0, 0)
        trackMiddle:SetPoint("BOTTOM", rail, "BOTTOM", 0, 0)
    else
        trackTop:SetPoint("TOP", rail, "TOP", 0, 0)
        trackBottom:SetPoint("BOTTOM", rail, "BOTTOM", 0, 0)
        trackMiddle:SetPoint("TOP", trackTop, "BOTTOM", 0, 0)
        trackMiddle:SetPoint("BOTTOM", trackBottom, "TOP", 0, 0)
        trackMiddle:SetPoint("LEFT", rail, "LEFT", 0, 0)
        trackMiddle:SetPoint("RIGHT", rail, "RIGHT", 0, 0)
    end

    rail:SetScript("OnMouseDown", function()
        JumpByRail(scrollBar)
    end)
    rail:SetScript("OnEnter", function()
        scrollBar:FadeIn()
    end)
    rail:SetScript("OnLeave", function()
        scrollBar:ScheduleFadeOut()
    end)

    local thumb = CreateFrame("Button", nil, rail)
    thumb.axis = axis
    if IsHorizontal(axis) then
        thumb:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, 0)
        thumb:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", 0, 0)
        thumb:SetWidth(MIN_THUMB_SIZE)
    else
        thumb:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, 0)
        thumb:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
        thumb:SetHeight(MIN_THUMB_SIZE)
    end

    local topTex = thumb:CreateTexture(nil, "ARTWORK")
    local bottomTex = thumb:CreateTexture(nil, "ARTWORK")
    local middleTex = thumb:CreateTexture(nil, "ARTWORK")

    if IsHorizontal(axis) then
        topTex:SetPoint("LEFT", thumb, "LEFT", 0, 0)
        bottomTex:SetPoint("RIGHT", thumb, "RIGHT", 0, 0)
        middleTex:SetPoint("LEFT", topTex, "RIGHT", 0, 0)
        middleTex:SetPoint("RIGHT", bottomTex, "LEFT", 0, 0)
        middleTex:SetPoint("TOP", thumb, "TOP", 0, 0)
        middleTex:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    else
        topTex:SetPoint("TOP", thumb, "TOP", 0, 0)
        bottomTex:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
        middleTex:SetPoint("TOP", topTex, "BOTTOM", 0, 0)
        middleTex:SetPoint("BOTTOM", bottomTex, "TOP", 0, 0)
        middleTex:SetPoint("LEFT", thumb, "LEFT", 0, 0)
        middleTex:SetPoint("RIGHT", thumb, "RIGHT", 0, 0)
    end

    thumb.topTex = topTex
    thumb.bottomTex = bottomTex
    thumb.middleTex = middleTex
    UpdateThumbTextures(thumb, "normal")

    thumb:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    thumb:SetScript("OnMouseDown", function(self)
        UpdateThumbTextures(self, "down")
        BeginThumbDrag(scrollBar, self)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        UpdateThumbTextures(self, self._mouseOver and "over" or "normal")
        EndThumbDrag(self)
    end)
    thumb:SetScript("OnHide", function(self)
        EndThumbDrag(self)
    end)
    thumb:SetScript("OnEnter", function(self)
        self._mouseOver = true
        UpdateThumbTextures(self, "over")
        scrollBar:FadeIn()
    end)
    thumb:SetScript("OnLeave", function(self)
        self._mouseOver = false
        if not self.dragging then
            UpdateThumbTextures(self, "normal")
        end
        scrollBar:ScheduleFadeOut()
    end)

    scrollBar.rail = rail
    scrollBar.thumb = thumb
    scrollBar.trackTop = trackTop
    scrollBar.trackBottom = trackBottom
    scrollBar.trackMiddle = trackMiddle

    function scrollBar:GetRange()
        return math_max(0, tonumber(type(self.getRange) == "function" and self.getRange() or 0) or 0)
    end

    function scrollBar:GetOffset()
        return Clamp(tonumber(type(self.getOffset) == "function" and self.getOffset() or 0) or 0, 0, self:GetRange())
    end

    function scrollBar:GetPageSize()
        return math_max(0, tonumber(type(self.getPageSize) == "function" and self.getPageSize() or 0) or 0)
    end

    function scrollBar:IsScrollable()
        return self:GetRange() > 0
    end

    function scrollBar:SetOffset(value)
        if type(self.setOffset) == "function" then
            self.setOffset(Clamp(tonumber(value) or 0, 0, self:GetRange()))
        end
    end

    function scrollBar:ScrollToOffset(value)
        local target = Clamp(tonumber(value) or 0, 0, self:GetRange())
        if type(self.scrollToOffset) == "function" then
            self.scrollToOffset(target)
            return
        end
        self:SetOffset(target)
    end

    function scrollBar:Refresh()
        local range = self:GetRange()
        local pageSize = self:GetPageSize()
        local railSpan = GetAxisSpan(self.rail, self.axis)

        if range <= 0 or pageSize <= 0 or railSpan <= 0 then
            if self:IsShown() then
                self:SetAlpha(0)
                self:Hide()
            end
            return
        end

        if not self:IsShown() then
            self:Show()
            self:SetAlpha(0)
        end
        self.thumb:Show()
        if self.revealOnRefresh then
            self:FadeIn()
            self:ScheduleFadeOut()
        end

        local contentSpan = range + pageSize
        local thumbSpan = math_max(MIN_THUMB_SIZE, math_floor((pageSize / contentSpan) * railSpan + 0.5))
        thumbSpan = math_min(thumbSpan, railSpan)
        if IsHorizontal(self.axis) then
            self.thumb:SetWidth(thumbSpan)
        else
            self.thumb:SetHeight(thumbSpan)
        end

        local travel = math_max(0, railSpan - thumbSpan)
        local ratio = range > 0 and (self:GetOffset() / range) or 0
        local axisOffset = travel * ratio

        self.thumb:ClearAllPoints()
        if IsHorizontal(self.axis) then
            self.thumb:SetPoint("TOPLEFT", self.rail, "TOPLEFT", axisOffset, 0)
            self.thumb:SetPoint("BOTTOMLEFT", self.rail, "BOTTOMLEFT", axisOffset, 0)
        else
            self.thumb:SetPoint("TOPLEFT", self.rail, "TOPLEFT", 0, -axisOffset)
            self.thumb:SetPoint("TOPRIGHT", self.rail, "TOPRIGHT", 0, -axisOffset)
        end
    end

    function scrollBar:RevealTemporarily()
        self:Refresh()
        if not self:IsShown() then
            return
        end
        self:FadeIn()
        self:ScheduleFadeOut()
    end

    ApplyScrollBarFadeBehavior(scrollBar)
    scrollBar:SetScript("OnSizeChanged", function()
        scrollBar:Refresh()
    end)
    return scrollBar
end

local function CreateScrollBar(scrollView, width)
    if (tonumber(width) or 0) <= 0 then
        return nil
    end

    local scrollBar = CreateScrollBarBase(scrollView, {
        axis = AXIS_VERTICAL,
        thickness = width,
        getRange = function()
            return scrollView:GetScrollRange()
        end,
        getOffset = function()
            return scrollView:GetOffset()
        end,
        getPageSize = function()
            return GetViewportHeight(scrollView)
        end,
        setOffset = function(value)
            scrollView:SnapTo(value)
        end,
        scrollToOffset = function(value)
            scrollView:ScrollTo(value)
        end,
        stopOffset = function()
            scrollView:StopScrolling()
        end,
        revealOnRefresh = scrollView.scrollBarRevealOnRefresh,
    })
    scrollBar:SetPoint("TOPRIGHT", scrollView, "TOPRIGHT", 0, 0)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollView, "BOTTOMRIGHT", 0, 0)
    return scrollBar
end

local function CreateScrollBase(parent, opts)
    local scroll = CreateFrame("Frame", nil, parent)
    ApplyMixin(scroll, SmoothScrollMixin)

    opts = type(opts) == "table" and opts or {}
    scroll.offset = 0
    scroll.scrollTarget = 0
    scroll.range = 0
    scroll:SetStepSize(opts.stepSize or DEFAULT_STEP_SIZE)
    scroll:SetBlendSpeed(opts.blendSpeed or DEFAULT_BLEND_SPEED)
    scroll.scrollBarWidth = tonumber(opts.scrollBarWidth)
    if scroll.scrollBarWidth == nil then
        scroll.scrollBarWidth = T.Style and T.Style.Scaled and T.Style.Scaled("SCROLL_BAR_WIDTH") or DEFAULT_SCROLLBAR_WIDTH
    end
    scroll.scrollBarRevealOnRefresh = opts.scrollBarRevealOnRefresh ~= false

    scroll.viewport = CreateFrame("Frame", nil, scroll)
    scroll.viewport:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    scroll.viewport:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -(scroll.scrollBarWidth > 0 and scroll.scrollBarWidth or 0), 0)
    scroll.viewport:SetClipsChildren(true)
    scroll.viewport:EnableMouseWheel(true)
    scroll.viewport:SetScript("OnMouseWheel", function(_, delta)
        scroll:OnMouseWheel(delta)
    end)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        scroll:OnMouseWheel(delta)
    end)

    scroll.scrollBar = CreateScrollBar(scroll, scroll.scrollBarWidth)
    return scroll
end

function T.CreateSimpleScroll(parent, opts)
    local scroll = CreateScrollBase(parent, opts)

    local container = CreateFrame("Frame", nil, scroll.viewport)
    container:SetPoint("TOPLEFT", scroll.viewport, "TOPLEFT", 0, 0)
    container:SetSize(1, 1)

    scroll.scrollRef = container
    scroll.container = container
    scroll.content = container
    scroll.contentHeight = 0

    function scroll:SetContentHeight(height)
        self.contentHeight = math_max(0, tonumber(height) or 0)
        self.container:SetWidth(math_max(1, GetViewportWidth(self)))
        self.container:SetHeight(math_max(self.contentHeight, GetViewportHeight(self)))
        self:SetScrollRange(math_max(0, self.contentHeight - GetViewportHeight(self)))
    end

    function scroll:UpdateScrollChildRect()
        self:SetContentHeight(self.contentHeight)
    end

    scroll:HookScript("OnSizeChanged", function(self)
        self:SetContentHeight(self.contentHeight)
    end)

    return scroll
end

local VirtualScrollMixin = {}

function VirtualScrollMixin:SetRowFactory(factory)
    self.rowFactory = factory
    self.rowFrames = {}
    self:Refresh(true)
end

function VirtualScrollMixin:SetRenderCallback(callback)
    self.renderCallback = callback
    self:Refresh(true)
end

function VirtualScrollMixin:SetDataCount(totalCount)
    self.dataCount = math_max(0, tonumber(totalCount) or 0)
    self.rowOffsets = nil
    self.totalRowsHeight = nil
    self:Refresh(true)
end

function VirtualScrollMixin:SetRowHeight(height)
    self.rowHeight = math_max(1, tonumber(height) or 1)
    self.rowOffsets = nil
    self.totalRowsHeight = nil
    if not self._customStepSize then
        self:SetStepSize(self.rowHeight * 3)
    end
    self:Refresh(true)
end

function VirtualScrollMixin:SetRowHeightProvider(provider)
    self.rowHeightProvider = type(provider) == "function" and provider or nil
    self.rowOffsets = nil
    self.totalRowsHeight = nil
    self:Refresh(true)
end

function VirtualScrollMixin:GetDataRowHeight(dataIndex)
    if type(self.rowHeightProvider) == "function" then
        return math_max(0, tonumber(self.rowHeightProvider(dataIndex, self)) or 0)
    end
    return math_max(1, tonumber(self.rowHeight) or 1)
end

function VirtualScrollMixin:RebuildRowMetrics()
    if type(self.rowHeightProvider) ~= "function" then
        self.rowOffsets = nil
        self.totalRowsHeight = nil
        return
    end
    local offsets = {}
    local total = 0
    for index = 1, math_max(0, tonumber(self.dataCount) or 0) do
        offsets[index] = total
        total = total + self:GetDataRowHeight(index)
    end
    offsets[(tonumber(self.dataCount) or 0) + 1] = total
    self.rowOffsets = offsets
    self.totalRowsHeight = total
end

function VirtualScrollMixin:GetVisibleRowCount()
    if type(self.rowHeightProvider) == "function" then
        self:RebuildRowMetrics()
        local total = math_max(0, tonumber(self.dataCount) or 0)
        if total <= 0 then
            return 1
        end
        local firstVisible = self:GetFirstVisibleDataIndex()
        local bottom = self:GetOffset() + GetViewportHeight(self)
        local count = 0
        for index = firstVisible, total do
            count = count + 1
            local rowTop = (self.rowOffsets and self.rowOffsets[index]) or 0
            if rowTop > bottom then
                break
            end
        end
        return math_max(1, count)
    end
    return math_max(1, math.ceil(GetViewportHeight(self) / math_max(1, self.rowHeight or 1)))
end

function VirtualScrollMixin:GetFirstVisibleDataIndex()
    if self.dataCount <= 0 then
        return 1
    end
    if type(self.rowHeightProvider) == "function" then
        self:RebuildRowMetrics()
        local offset = self:GetOffset()
        for index = 1, self.dataCount do
            local rowEnd = self.rowOffsets and self.rowOffsets[index + 1] or 0
            if rowEnd > offset then
                return index
            end
        end
        return self.dataCount
    end
    return Clamp(math_floor(self:GetOffset() / math_max(1, self.rowHeight or 1)) + 1, 1, self.dataCount)
end

function VirtualScrollMixin:GetRowFrame(displayIndex)
    return self.rowFrames and self.rowFrames[displayIndex] or nil
end

function VirtualScrollMixin:EnsureRowFrames()
    local poolSize = math_max(1, self:GetVisibleRowCount() + (self.rowBuffer or DEFAULT_ROW_BUFFER) * 2)
    self.poolSize = poolSize
    self.rowFrames = self.rowFrames or {}

    if type(self.rowFactory) ~= "function" then
        return
    end

    while #self.rowFrames < poolSize do
        local row = self.rowFactory(self.scrollRef)
        row:Hide()
        self.rowFrames[#self.rowFrames + 1] = row
    end
end

function VirtualScrollMixin:UpdateMetrics()
    local viewportWidth = math_max(1, GetViewportWidth(self))
    local viewportHeight = GetViewportHeight(self)
    self:RebuildRowMetrics()
    local totalHeight = self.totalRowsHeight or (self.dataCount * self.rowHeight)

    self.scrollRef:SetWidth(viewportWidth)
    self.scrollRef:SetHeight(math_max(totalHeight, viewportHeight))
    self:SetScrollRange(math_max(0, totalHeight - viewportHeight))
end

function VirtualScrollMixin:UpdateView(force)
    self:EnsureRowFrames()
    self:UpdateMetrics()

    local total = self.dataCount
    local firstVisible = self:GetFirstVisibleDataIndex()
    local startIndex = math_max(1, firstVisible - (self.rowBuffer or DEFAULT_ROW_BUFFER))

    if not force and self.lastRenderStart == startIndex and self.lastRenderCount == total then
        return
    end

    self.lastRenderStart = startIndex
    self.lastRenderCount = total
    self.lastVisibleIndex = firstVisible
    self.lastViewRefreshAt = GetTime and GetTime() or self.lastViewRefreshAt

    if type(self.beforeViewRefreshCallback) == "function" then
        self.beforeViewRefreshCallback(self, startIndex)
    end

    for displayIndex, row in ipairs(self.rowFrames or {}) do
        local dataIndex = startIndex + displayIndex - 1
        if dataIndex <= total and type(self.renderCallback) == "function" then
            local rowTop = self.rowOffsets and self.rowOffsets[dataIndex] or ((dataIndex - 1) * self.rowHeight)
            local rowHeight = self:GetDataRowHeight(dataIndex)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.scrollRef, "TOPLEFT", 0, -rowTop)
            row:SetWidth(math_max(1, GetViewportWidth(self)))
            row:SetHeight(math_max(0, rowHeight))
            row:Show()
            self.renderCallback(row, dataIndex, displayIndex)
        else
            row:Hide()
        end
    end
end

function VirtualScrollMixin:Refresh(force)
    self:UpdateView(force == true)
end

function VirtualScrollMixin:ScrollToDataIndex(index)
    local dataIndex = math_max(1, tonumber(index) or 1)
    local target
    if type(self.rowHeightProvider) == "function" then
        self:RebuildRowMetrics()
        target = (self.rowOffsets and self.rowOffsets[dataIndex]) or 0
    else
        target = (dataIndex - 1) * self.rowHeight
    end
    self:ScrollTo(target)
end

function VirtualScrollMixin:OnScrollChanged(offset)
    local currentFirst = self:GetFirstVisibleDataIndex()
    if currentFirst ~= self.lastVisibleIndex then
        local throttle = tonumber(self.viewRefreshThrottle) or 0
        if throttle > 0 and self.isScrolling then
            local now = GetTime and GetTime() or 0
            local lastRefreshAt = tonumber(self.lastViewRefreshAt) or 0
            if lastRefreshAt <= 0 or (now - lastRefreshAt) >= throttle then
                self.lastVisibleIndex = currentFirst
                self:UpdateView(false)
            end
        else
            self.lastVisibleIndex = currentFirst
            self:UpdateView(false)
        end
    end
    SmoothScrollMixin.OnScrollChanged(self, offset)
end

function T.CreateVirtualScroll(parent, opts)
    opts = type(opts) == "table" and opts or {}

    local scroll = CreateScrollBase(parent, opts)
    ApplyMixin(scroll, VirtualScrollMixin)

    scroll.scrollRef = CreateFrame("Frame", nil, scroll.viewport)
    scroll.scrollRef:SetPoint("TOPLEFT", scroll.viewport, "TOPLEFT", 0, 0)
    scroll.scrollRef:SetSize(1, 1)
    scroll.rowFrames = {}
    scroll.rowFactory = nil
    scroll.renderCallback = nil
    scroll.dataCount = 0
    scroll.rowHeight = math_max(1, tonumber(opts.rowHeight) or 1)
    scroll.rowBuffer = math_max(0, math_floor(tonumber(opts.rowBuffer) or DEFAULT_ROW_BUFFER))
    scroll._customStepSize = opts.stepSize ~= nil
    scroll:SetViewRefreshThrottle(opts.viewRefreshThrottle or 0)

    if not scroll._customStepSize then
        scroll:SetStepSize(scroll.rowHeight * 3)
    end

    scroll:HookScript("OnSizeChanged", function(self)
        self:Refresh(true)
    end)

    return scroll
end

function T.CreateSmoothValueDriver(opts)
    opts = type(opts) == "table" and opts or {}

    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetSize(1, 1)
    driver:SetAlpha(0)
    driver:EnableMouse(false)
    ApplyMixin(driver, SmoothScrollMixin)

    driver.offset = math_max(0, tonumber(opts.offset) or 0)
    driver.scrollTarget = driver.offset
    driver.range = math_max(0, tonumber(opts.range) or 0)
    driver:SetStepSize(opts.stepSize or DEFAULT_STEP_SIZE)
    driver:SetBlendSpeed(opts.blendSpeed or DEFAULT_BLEND_SPEED)
    driver:SetScrollChangedCallback(opts.onValueChanged)

    function driver:UpdateScrollBar()
    end

    function driver:SetOffset(value)
        self.offset = Clamp(tonumber(value) or 0, 0, self:GetScrollRange())
        if self.OnScrollChanged then
            self:OnScrollChanged(self.offset)
        end
    end

    return driver
end

function T.CreateHorizontalScrollBar(parent, opts)
    opts = type(opts) == "table" and opts or {}
    return CreateScrollBarBase(parent, {
        axis = AXIS_HORIZONTAL,
        thickness = opts.height or opts.thickness or DEFAULT_SCROLLBAR_WIDTH,
        getRange = opts.getRange,
        getOffset = opts.getOffset,
        getPageSize = opts.getPageSize,
        setOffset = opts.setOffset,
        scrollToOffset = opts.scrollToOffset,
        stopOffset = opts.stopOffset,
    })
end

function T.CreateScrollEditBox(parent, opts)
    opts = type(opts) == "table" and opts or {}

    local frame = CreateFrame("Frame", nil, parent)
    ApplyMixin(frame, SmoothScrollMixin)
    if opts.width and opts.height then
        frame:SetSize(opts.width, opts.height)
    end

    frame.offset = 0
    frame.scrollTarget = 0
    frame.range = 0
    frame:SetStepSize(opts.stepSize or DEFAULT_STEP_SIZE)
    frame:SetBlendSpeed(opts.blendSpeed or DEFAULT_BLEND_SPEED)
    frame.scrollBarWidth = tonumber(opts.scrollBarWidth)
    if frame.scrollBarWidth == nil then
        frame.scrollBarWidth = DEFAULT_SCROLLBAR_WIDTH
    end

    local textInsets = opts.textInsets
    local leftInset = DEFAULT_TEXT_INSET
    local rightInset = DEFAULT_TEXT_INSET
    local topInset = DEFAULT_TEXT_INSET
    local bottomInset = DEFAULT_TEXT_INSET
    if type(textInsets) == "table" then
        leftInset = tonumber(textInsets[1]) or leftInset
        rightInset = tonumber(textInsets[2]) or rightInset
        topInset = tonumber(textInsets[3]) or topInset
        bottomInset = tonumber(textInsets[4]) or bottomInset
    end

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(frame.scrollBarWidth > 0 and frame.scrollBarWidth or 0), 0)
    scrollFrame:EnableMouseWheel(true)
    frame.viewport = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetSize(1, 1)
    content:EnableMouse(true)
    scrollFrame:SetScrollChild(content)

    local editBox = CreateFrame("EditBox", nil, content)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(opts.autoFocus == true)
    if opts.fontObject then
        editBox:SetFontObject(opts.fontObject)
    elseif opts.font then
        editBox:SetFont(opts.font, opts.fontSize or 12, opts.fontFlags or "")
    else
        editBox:SetFontObject(ChatFontNormal)
    end
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    editBox:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    editBox:SetHeight(1)
    editBox:SetTextInsets(leftInset, rightInset, topInset, bottomInset)
    editBox:EnableMouse(true)
    editBox:EnableMouseWheel(true)
    frame.scrollBar = CreateScrollBar(frame, frame.scrollBarWidth)

    local function RefreshMetrics()
        local viewportWidth = math_max(1, GetViewportWidth(frame))
        local viewportHeight = math_max(1, GetViewportHeight(frame))

        -- viewport 尺寸还没就绪时（锚定链未传播），延迟到下一帧重试
        if (viewportWidth <= 1 or viewportHeight <= 1) and frame:IsVisible() and not frame._pendingRefresh then
            frame._pendingRefresh = true
            C_Timer.After(0, function()
                frame._pendingRefresh = nil
                RefreshMetrics()
            end)
            return
        end

        content:SetWidth(viewportWidth)

        local textHeight = 0
        if editBox.GetTextHeight then
            textHeight = tonumber(editBox:GetTextHeight()) or 0
        end
        if textHeight <= 0 then
            local _, fontHeight = editBox:GetFont()
            textHeight = CountLines(editBox:GetText()) * math_max(1, (fontHeight or 12) + 2)
        end

        local contentHeight = math_max(viewportHeight, math_floor(textHeight + topInset + bottomInset + 0.5))
        editBox:SetHeight(contentHeight)
        content:SetHeight(contentHeight)
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
        frame:SetScrollRange(math_max(0, contentHeight - viewportHeight))
    end

    function frame:SetOffset(value)
        local offset = Clamp(tonumber(value) or 0, 0, self:GetScrollRange())
        self.offset = offset
        self._settingOffset = true
        scrollFrame:SetVerticalScroll(offset)
        self._settingOffset = nil
        SmoothScrollMixin.OnScrollChanged(self, offset)
        self:UpdateScrollBar()
    end

    function frame:SetCursorAutoScrollSuppressed(suppressed)
        local depth = tonumber(self._cursorAutoScrollSuppressDepth) or 0
        if suppressed then
            depth = depth + 1
        else
            depth = math_max(0, depth - 1)
        end
        self._cursorAutoScrollSuppressDepth = depth
    end

    function frame:IsCursorAutoScrollSuppressed()
        return (tonumber(self._cursorAutoScrollSuppressDepth) or 0) > 0
    end

    content:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)
    scrollFrame:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        frame:OnMouseWheel(delta)
    end)
    scrollFrame:SetScript("OnVerticalScroll", function(_, offset)
        if frame._settingOffset then
            return
        end
        frame.offset = Clamp(tonumber(offset) or 0, 0, frame:GetScrollRange())
        frame.scrollTarget = frame.offset
        SmoothScrollMixin.OnScrollChanged(frame, frame.offset)
        frame:UpdateScrollBar()
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(_, _, yrange)
        frame.range = math_max(0, tonumber(yrange) or 0)
        if frame.offset > frame.range then
            frame:SnapTo(frame.range)
        else
            frame:UpdateScrollBar()
        end
    end)
    content:SetScript("OnMouseWheel", function(_, delta)
        frame:OnMouseWheel(delta)
    end)
    editBox:SetScript("OnMouseWheel", function(_, delta)
        frame:OnMouseWheel(delta)
    end)
    if opts.disableCursorAutoScroll ~= true then
        editBox:HookScript("OnCursorChanged", function(_, _, y, _, cursorHeight)
            if frame:IsCursorAutoScrollSuppressed() then
                return
            end
            local cursorTop = math_abs(tonumber(y) or 0)
            local cursorBottom = cursorTop + (tonumber(cursorHeight) or 0)
            local scrollOffset = frame:GetOffset()
            local viewportHeight = math_max(1, GetViewportHeight(frame))

            if cursorTop < scrollOffset then
                frame:SnapTo(cursorTop)
            elseif cursorBottom > (scrollOffset + viewportHeight) then
                frame:SnapTo(cursorBottom - viewportHeight)
            end
        end)
    end
    editBox:HookScript("OnTextChanged", function()
        RefreshMetrics()
    end)
    frame:HookScript("OnSizeChanged", function()
        RefreshMetrics()
    end)
    scrollFrame:HookScript("OnSizeChanged", function()
        RefreshMetrics()
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        frame:OnMouseWheel(delta)
    end)

    frame.scrollView = frame
    frame.nativeScrollFrame = scrollFrame
    frame.content = content
    frame.editBox = editBox
    frame.RefreshMetrics = RefreshMetrics

    function frame:SetText(text)
        editBox:SetText(text or "")
        RefreshMetrics()
    end

    function frame:GetText()
        return editBox:GetText()
    end

    function frame:SetFocus()
        editBox:SetFocus()
    end

    function frame:ClearFocus()
        editBox:ClearFocus()
    end

    RefreshMetrics()
    return frame
end
