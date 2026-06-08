-- screen_reminder/indicator_text.lua
-- text 类 indicator：主文本 + 倒数（位置由 countdown.position 决定）
-- 独立 pool。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

T.ScreenReminderIndicators = T.ScreenReminderIndicators or {}
local Module = {}
T.ScreenReminderIndicators.text = Module

local pool = {}

local FONT_FACES = {
    default = STANDARD_TEXT_FONT,
    FRIZQT = "Fonts\\FRIZQT__.TTF",
}

local function ResolveFont(face)
    return FONT_FACES[face or "default"] or STANDARD_TEXT_FONT
end

local function HexToRGB(hex)
    if type(hex) ~= "string" or #hex < 6 then
        return 1, 1, 1
    end
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r / 255, g / 255, b / 255
end

local Instance = {}
Instance.__index = Instance

local OUTLINE_OFFSETS = {
    { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
    { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 },
}

local function EnsureTextOutline(frame)
    if frame.textOutline then return end
    frame.textOutline = {}
    for i, offset in ipairs(OUTLINE_OFFSETS) do
        local fs = frame:CreateFontString(nil, "BORDER")
        fs:SetPoint("CENTER", frame.text, "CENTER", offset[1], offset[2])
        fs:Hide()
        frame.textOutline[i] = fs
    end
end

local function CreateNewFrame()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(40, 24)
    frame:Hide()

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER", frame, "CENTER")

    frame.countdown = frame:CreateFontString(nil, "OVERLAY")
    EnsureTextOutline(frame)
    return frame
end

function Instance:RefreshFrameSize()
    local text = self.frame and self.frame.text
    if not text then return end
    local style = self.def and self.def.style or {}
    local fontSize = tonumber(style.fontSize) or 18
    local w = math.max(1, text:GetStringWidth() or 0)
    local h = math.max(fontSize, text:GetStringHeight() or 0)
    self.frame:SetSize(math.ceil(w + 16), math.ceil(h + 12))
end

function Module.Acquire(parent)
    local instance = table.remove(pool)
    if not instance then
        instance = setmetatable({ frame = CreateNewFrame() }, Instance)
    end
    instance.frame:SetParent(parent or UIParent)
    instance.frame:ClearAllPoints()
    instance.frame:Show()
    instance.running = false
    return instance
end

function Module.Release(instance)
    if not instance then return end
    instance:Stop()
    instance.frame:Hide()
    instance.frame:ClearAllPoints()
    instance.frame:SetParent(UIParent)
    instance.frame.text:SetText("")
    if instance.frame.textOutline then
        for _, fs in ipairs(instance.frame.textOutline) do
            fs:SetText("")
            fs:Hide()
        end
    end
    instance.frame.countdown:SetText("")
    pool[#pool + 1] = instance
end

-- ──────────────────────────────────────────────────────────────────────
-- 内部样式应用
-- ──────────────────────────────────────────────────────────────────────
function Instance:ApplyStyle()
    local def = self.def
    if not def then return end
    local style = def.style or {}
    local font = ResolveFont(style.fontFace)
    local fontSize = tonumber(style.fontSize) or 18
    local cdFontSize = T.ScreenReminderCountdown and T.ScreenReminderCountdown.ResolveFontSize
        and T.ScreenReminderCountdown.ResolveFontSize(def.countdown, fontSize)
        or fontSize
    local outline = style.bold and style.outline == false and "THICKOUTLINE" or ""

    self.frame.text:SetFont(font, fontSize, outline)
    self.frame.countdown:SetFont(font, cdFontSize, style.outline ~= false and "OUTLINE" or outline)

    if style.shadow then
        self.frame.text:SetShadowOffset(1, -1)
        self.frame.text:SetShadowColor(0, 0, 0, 0.8)
    else
        self.frame.text:SetShadowOffset(0, 0)
    end

    local r, g, b = HexToRGB(style.color)
    self.frame.text:SetTextColor(r, g, b, 1)

    EnsureTextOutline(self.frame)
    local or_, og, ob = HexToRGB(style.outlineColor or "000000")
    local outlineSize = style.bold and 2 or 1
    for i, fs in ipairs(self.frame.textOutline or {}) do
        local offset = OUTLINE_OFFSETS[i]
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", self.frame.text, "CENTER", offset[1] * outlineSize, offset[2] * outlineSize)
        fs:SetFont(font, fontSize, "")
        fs:SetTextColor(or_, og, ob, 1)
        fs:SetText(self.frame.text:GetText() or "")
        fs:SetShown(style.outline ~= false)
    end

    local scale = tonumber(style.scale) or 1.0
    self.frame:SetScale(math.max(0.5, math.min(3, scale)))

    -- 布局倒数相对位置
    local pos = (def.countdown and def.countdown.position) or "left"
    self.frame.countdown:ClearAllPoints()
    if pos == "left" then
        self.frame.countdown:SetPoint("RIGHT", self.frame.text, "LEFT", -6, 0)
    elseif pos == "right" then
        self.frame.countdown:SetPoint("LEFT", self.frame.text, "RIGHT", 6, 0)
    elseif pos == "above" then
        self.frame.countdown:SetPoint("BOTTOM", self.frame.text, "TOP", 0, 2)
    elseif pos == "below" then
        self.frame.countdown:SetPoint("TOP", self.frame.text, "BOTTOM", 0, -2)
    else -- overlay: 文本左侧叠加
        self.frame.countdown:SetPoint("RIGHT", self.frame.text, "LEFT", -6, 0)
    end

    self:RefreshFrameSize()
end

function Instance:SetData(def)
    self.def = def
    self:ApplyStyle()
end

function Instance:SetText(text)
    local value = text or ""
    self.frame.text:SetText(value)
    if self.frame.textOutline then
        for _, fs in ipairs(self.frame.textOutline) do
            fs:SetText(value)
        end
    end
    self:RefreshFrameSize()
end

function Instance:Refresh()
    self:ApplyStyle()
end

function Instance:Start(ctx, duration)
    self.ctx = ctx or {}
    self.duration = math.max(0.05, tonumber(duration) or 0)
    self.endTime = GetTime() + self.duration
    self.lingerActive = false
    self.lingerEndTime = nil
    self.frame:SetAlpha(1)
    self.frame.countdown:Show()
    self:SetText(self.ctx.text or "")
    self.running = true

    self:UpdateCountdown()
    self._accum = 0
    self.frame:SetScript("OnUpdate", function(_, dt)
        self:OnUpdate(dt)
    end)
end

function Instance:UpdateCountdown()
    local def = self.def
    if not def then return end
    local remaining = math.max(0, (self.endTime or 0) - GetTime())
    if T.ScreenReminderCountdown and T.ScreenReminderCountdown.ApplyToFontString then
        T.ScreenReminderCountdown.ApplyToFontString(self.frame.countdown, remaining, def.countdown)
    end
end

function Instance:OnUpdate(dt)
    if not self.running then return end
    if self.lingerActive then
        if GetTime() >= (self.lingerEndTime or 0) then
            self:Stop()
            if self.onFinish then self.onFinish(self) end
        end
        return
    end
    local remaining = (self.endTime or 0) - GetTime()
    if remaining <= 0 then
        local glowSec = T.ScreenReminderEffects and T.ScreenReminderEffects.StartPixelGlow(self.frame, self.def) or 0
        local lingerSec = math.max(0, tonumber(self.lingerSec) or 0)
        local waitSec = math.max(lingerSec, glowSec)
        if waitSec > 0 then
            self.lingerActive = true
            self.lingerEndTime = GetTime() + waitSec
            self.frame.countdown:Hide()
            if lingerSec > 0 and self.lingerFadeEnabled ~= false then
                UIFrameFadeOut(self.frame, lingerSec, self.frame:GetAlpha() or 1, 0)
            end
            return
        end
        self:Stop()
        if self.onFinish then self.onFinish(self) end
        return
    end
    self._accum = (self._accum or 0) + (dt or 0)
    if self._accum < 0.05 then return end
    self._accum = 0
    self:UpdateCountdown()
end

function Instance:Stop()
    self.running = false
    self.lingerActive = false
    self.lingerEndTime = nil
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        if T.ScreenReminderEffects then
            T.ScreenReminderEffects.StopPixelGlow(self.frame)
        end
        if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(self.frame) end
        self.frame:SetAlpha(1)
        if self.frame.countdown then self.frame.countdown:Show() end
    end
end

function Instance:SetOnFinish(callback)
    self.onFinish = callback
end

end)
