local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("Bar.Enabled", function()

local BarWidget = {}
BarWidget.__index = BarWidget
T.BarWidget = BarWidget

local framePool = {}

local DEFAULT_STYLE = {
    width = 240,
    height = 22,
    bgColor = { 0, 0, 0, 0.55 },
    barColor = { 0.55, 0.25, 0.85, 1 },
    tickColor = { 1, 1, 1, 0.85 },
    tickWidth = 2,
    borderSize = 1,
    borderColor = { 0, 0, 0, 1 },
    tickFontSize = 13,
    tickFontColor = { 1, 1, 1, 1 },
    tickWarnColor = { 1, 0.3, 0.3, 1 },
    tickWarnThreshold = 0.5,
    tickFontOutline = "OUTLINE",
    tickMinSegWidth = 1.2,
    iconSize = 22,
    iconGap = 2,
    labelFont = STANDARD_TEXT_FONT,
    labelFontSize = 13,
    labelFontColor = { 1, 1, 1, 1 },
    labelOffset = 4,
    labelRemainFmt = " (%.1f)",
    barTexture = nil,           -- 进度条填充纹理路径；nil 时回退为 SetColorTexture（纯色）
}

local function CopyColor(value, fallback)
    if type(value) ~= "table" then
        value = fallback
    end
    return {
        tonumber(value and value[1]) or (fallback and fallback[1]) or 1,
        tonumber(value and value[2]) or (fallback and fallback[2]) or 1,
        tonumber(value and value[3]) or (fallback and fallback[3]) or 1,
        tonumber(value and value[4]) or (fallback and fallback[4]) or 1,
    }
end

local function NormalizeStyle(style)
    style = type(style) == "table" and style or {}
    local out = {}
    for key, value in pairs(DEFAULT_STYLE) do
        out[key] = value
    end
    for key, value in pairs(style) do
        out[key] = value
    end

    out.width = math.max(80, tonumber(out.width) or DEFAULT_STYLE.width)
    out.height = math.max(8, tonumber(out.height) or DEFAULT_STYLE.height)
    out.tickWidth = math.max(1, tonumber(out.tickWidth) or DEFAULT_STYLE.tickWidth)
    out.borderSize = math.max(0, tonumber(out.borderSize) or DEFAULT_STYLE.borderSize)
    out.tickFontSize = math.max(8, tonumber(out.tickFontSize) or DEFAULT_STYLE.tickFontSize)
    out.tickWarnThreshold = math.max(0, tonumber(out.tickWarnThreshold) or DEFAULT_STYLE.tickWarnThreshold)
    out.tickMinSegWidth = math.max(0, tonumber(out.tickMinSegWidth) or DEFAULT_STYLE.tickMinSegWidth)
    out.iconSize = math.max(0, tonumber(out.iconSize) or out.height)
    out.iconGap = math.max(0, tonumber(out.iconGap) or DEFAULT_STYLE.iconGap)
    out.labelFontSize = math.max(8, tonumber(out.labelFontSize) or DEFAULT_STYLE.labelFontSize)
    out.labelOffset = math.max(0, tonumber(out.labelOffset) or DEFAULT_STYLE.labelOffset)
    out.bgColor = CopyColor(out.bgColor, DEFAULT_STYLE.bgColor)
    out.barColor = CopyColor(out.barColor, DEFAULT_STYLE.barColor)
    out.tickColor = CopyColor(out.tickColor, DEFAULT_STYLE.tickColor)
    out.borderColor = CopyColor(out.borderColor, DEFAULT_STYLE.borderColor)
    out.tickFontColor = CopyColor(out.tickFontColor, DEFAULT_STYLE.tickFontColor)
    out.tickWarnColor = CopyColor(out.tickWarnColor, DEFAULT_STYLE.tickWarnColor)
    out.labelFontColor = CopyColor(out.labelFontColor, DEFAULT_STYLE.labelFontColor)
    out.labelRemainFmt = type(out.labelRemainFmt) == "string" and out.labelRemainFmt or DEFAULT_STYLE.labelRemainFmt
    out.tickFontOutline = type(out.tickFontOutline) == "string" and out.tickFontOutline or DEFAULT_STYLE.tickFontOutline
    out.labelFont = type(out.labelFont) == "string" and out.labelFont or DEFAULT_STYLE.labelFont
    return out
end

local function SetColor(texture, color)
    if texture and texture.SetColorTexture then
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

-- 用 preset 纹理（path 或 atlas）+ vertex color 染色；空时回退到 SetColorTexture
-- path 支持 "atlas:<atlasName>" 前缀 → SetAtlas；否则按文件路径 SetTexture
local function SetTextureWithColor(texture, path, color)
    if not texture then return end
    if type(path) == "string" and path ~= "" then
        local atlasName = path:match("^atlas:(.+)$")
        if atlasName and texture.SetAtlas then
            texture:SetAtlas(atlasName)
        else
            texture:SetTexture(path)
        end
        if texture.SetVertexColor then
            texture:SetVertexColor(color[1], color[2], color[3], color[4])
        end
    else
        SetColor(texture, color)
    end
end

local function AcquireFrame(parent)
    local frame = table.remove(framePool)
    if not frame then
        frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        frame.bg:SetPoint("TOPLEFT")

        frame.fill = frame:CreateTexture(nil, "ARTWORK")
        frame.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        frame.fill:SetPoint("LEFT", frame.bg, "LEFT")

        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")

        frame.labelFS = frame:CreateFontString(nil, "OVERLAY")
        frame.tickLines = {}
        frame.tickTexts = {}
    else
        frame:SetParent(parent)
    end
    frame:Show()
    return frame
end

local function ReleaseFrame(frame)
    if not frame then
        return
    end
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    frame.icon:SetTexture(nil)
    frame.labelFS:SetText("")
    frame.labelFS._lastText = nil
    for _, texture in ipairs(frame.tickLines) do
        texture:Hide()
    end
    for _, fontString in ipairs(frame.tickTexts) do
        fontString:SetText("")
        fontString._lastText = nil
        fontString:Hide()
    end
    framePool[#framePool + 1] = frame
end

function BarWidget:Create(parent, opts)
    opts = type(opts) == "table" and opts or {}
    local duration = tonumber(opts.duration)
    if not duration or duration <= 0 then
        return nil
    end

    local frame = AcquireFrame(parent or UIParent)
    local widget = setmetatable({
        frame = frame,
        duration = duration,
        tickInterval = tonumber(opts.tickInterval),
        iconTexture = opts.iconTexture,
        label = opts.label or "",
        style = NormalizeStyle(opts.style),
        onTickReached = opts.onTickReached,
        onFinish = opts.onFinish,
        running = false,
        elapsed = 0,
        updateAccum = 0,
        lastSegIdx = nil,
        finished = false,
    }, BarWidget)
    widget:ApplyStyle()
    return widget
end

function BarWidget:GetSize()
    local style = self.style or DEFAULT_STYLE
    local iconWidth = self.iconTexture and (style.iconSize + style.iconGap) or 0
    local height = style.height + style.labelOffset + style.labelFontSize + 2
    return style.width + iconWidth, height
end

function BarWidget:ApplyStyle()
    local frame = self.frame
    local style = self.style
    local iconSize = self.iconTexture and style.iconSize or 0
    local iconWidth = self.iconTexture and (iconSize + style.iconGap) or 0
    local totalWidth, totalHeight = self:GetSize()

    frame:SetSize(totalWidth, totalHeight)
    frame.bg:ClearAllPoints()
    frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", iconWidth, 0)
    frame.bg:SetSize(style.width, style.height)
    SetColor(frame.bg, style.bgColor)

    frame.fill:ClearAllPoints()
    frame.fill:SetPoint("LEFT", frame.bg, "LEFT")
    frame.fill:SetSize(1, style.height)
    SetTextureWithColor(frame.fill, style.barTexture, style.barColor)

    frame.border:ClearAllPoints()
    frame.border:SetPoint("TOPLEFT", frame.bg, "TOPLEFT", -style.borderSize, style.borderSize)
    frame.border:SetPoint("BOTTOMRIGHT", frame.bg, "BOTTOMRIGHT", style.borderSize, -style.borderSize)
    frame.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = math.max(1, style.borderSize),
    })
    frame.border:SetBackdropBorderColor(style.borderColor[1], style.borderColor[2], style.borderColor[3], style.borderColor[4])
    frame.border:SetShown(style.borderSize > 0)

    frame.icon:ClearAllPoints()
    if self.iconTexture then
        frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.icon:SetSize(iconSize, iconSize)
        frame.icon:SetTexture(self.iconTexture)
        frame.icon:Show()
    else
        frame.icon:Hide()
    end

    frame.labelFS:ClearAllPoints()
    frame.labelFS:SetPoint("TOP", frame.bg, "BOTTOM", 0, -style.labelOffset)
    frame.labelFS:SetFont(style.labelFont, style.labelFontSize, "OUTLINE")
    frame.labelFS:SetTextColor(style.labelFontColor[1], style.labelFontColor[2], style.labelFontColor[3], style.labelFontColor[4])
    frame.labelFS:SetWidth(style.width + iconWidth)
    frame.labelFS:SetJustifyH("CENTER")

    self:LayoutTicks()
    self:UpdateVisual(0)
end

function BarWidget:LayoutTicks()
    local frame = self.frame
    local style = self.style
    local tickInterval = tonumber(self.tickInterval)
    local tickCount = 0
    if tickInterval and tickInterval > 0 and tickInterval <= self.duration then
        tickCount = math.ceil(self.duration / tickInterval)
    end

    for _, texture in ipairs(frame.tickLines) do
        texture:Hide()
    end
    for _, fontString in ipairs(frame.tickTexts) do
        fontString:SetText("")
        fontString._lastText = nil
        fontString:Hide()
    end

    if tickCount <= 1 then
        return
    end

    for index = 1, tickCount - 1 do
        local texture = frame.tickLines[index]
        if not texture then
            texture = frame:CreateTexture(nil, "OVERLAY")
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            frame.tickLines[index] = texture
        end
        local x = math.min(style.width, (index * tickInterval / self.duration) * style.width)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", frame.bg, "TOPLEFT", x - style.tickWidth * 0.5, 0)
        texture:SetSize(style.tickWidth, style.height)
        SetColor(texture, style.tickColor)
        texture:Show()
    end

    for index = 1, tickCount do
        local segStart = (index - 1) * tickInterval
        local segLen = math.min(tickInterval, self.duration - segStart)
        local segWidth = (segLen / self.duration) * style.width
        if segWidth >= style.tickFontSize * style.tickMinSegWidth then
            local fontString = frame.tickTexts[index]
            if not fontString then
                fontString = frame:CreateFontString(nil, "OVERLAY")
                frame.tickTexts[index] = fontString
            end
            local x = ((segStart + segLen * 0.5) / self.duration) * style.width
            fontString:ClearAllPoints()
            fontString:SetPoint("CENTER", frame.bg, "LEFT", x, 0)
            fontString:SetFont(STANDARD_TEXT_FONT, style.tickFontSize, style.tickFontOutline)
            fontString:SetTextColor(style.tickFontColor[1], style.tickFontColor[2], style.tickFontColor[3], style.tickFontColor[4])
            fontString:Show()
        end
    end
end

function BarWidget:UpdateVisual(elapsed)
    local style = self.style
    local remaining = math.max(0, self.duration - elapsed)
    local progress = math.max(0, math.min(1, elapsed / self.duration))
    self.frame.fill:SetWidth(math.max(1, progress * style.width))

    local tickInterval = tonumber(self.tickInterval)
    if tickInterval and tickInterval > 0 and tickInterval <= self.duration then
        local segIdx = math.min(math.ceil(self.duration / tickInterval), math.floor(elapsed / tickInterval) + 1)
        if segIdx ~= self.lastSegIdx then
            if self.lastSegIdx and self.frame.tickTexts[self.lastSegIdx] then
                self.frame.tickTexts[self.lastSegIdx]:SetText("")
                self.frame.tickTexts[self.lastSegIdx]._lastText = nil
            end
            if self.lastSegIdx and segIdx > self.lastSegIdx and self.onTickReached then
                self.onTickReached(self, segIdx - 1, math.ceil(self.duration / tickInterval))
            end
            self.lastSegIdx = segIdx
        end

        local fontString = self.frame.tickTexts[segIdx]
        if fontString then
            local segStart = (segIdx - 1) * tickInterval
            local segLen = math.min(tickInterval, self.duration - segStart)
            local segLeft = math.max(0, segLen - (elapsed - segStart))
            local text = string.format("%.1f", segLeft)
            if text ~= fontString._lastText then
                fontString:SetText(text)
                fontString._lastText = text
                local color = segLeft <= style.tickWarnThreshold and style.tickWarnColor or style.tickFontColor
                fontString:SetTextColor(color[1], color[2], color[3], color[4])
            end
        end
    end

    local fmt = style.labelRemainFmt or ""
    local labelText = tostring(self.label or "")
    if fmt ~= "" then
        labelText = labelText .. string.format(fmt, remaining)
    end
    if labelText ~= self.frame.labelFS._lastText then
        self.frame.labelFS:SetText(labelText)
        self.frame.labelFS._lastText = labelText
    end
end

function BarWidget:Start(startTime)
    self.startTime = tonumber(startTime) or GetTime()
    self.running = true
    self.finished = false
    self.frame:SetScript("OnUpdate", function(_, dt)
        if not self.running then
            return
        end
        self.updateAccum = (self.updateAccum or 0) + (tonumber(dt) or 0)
        if self.updateAccum < 0.05 then
            return
        end
        self.updateAccum = 0
        self.elapsed = math.max(0, GetTime() - self.startTime)
        self:UpdateVisual(self.elapsed)
        if self.elapsed >= self.duration then
            self:Finish()
        end
    end)
    self.elapsed = math.max(0, GetTime() - self.startTime)
    self:UpdateVisual(self.elapsed)
end

function BarWidget:Stop()
    self.running = false
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
    end
end

function BarWidget:Finish()
    if self.finished then
        return
    end
    self.finished = true
    self:Stop()
    if self.onFinish then
        self.onFinish(self)
    end
end

function BarWidget:Reset()
    self.elapsed = 0
    self.lastSegIdx = nil
    self.finished = false
    self:UpdateVisual(0)
end

function BarWidget:SetStyle(style)
    self.style = NormalizeStyle(style)
    self:ApplyStyle()
end

function BarWidget:SetLabel(text)
    self.label = text or ""
    self.frame.labelFS._lastText = nil
    self:UpdateVisual(self.elapsed or 0)
end

function BarWidget:SetIcon(texture)
    self.iconTexture = texture
    self:ApplyStyle()
end

function BarWidget:Destroy()
    self:Stop()
    ReleaseFrame(self.frame)
    self.frame = nil
end

end)
