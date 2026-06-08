-- screen_reminder/indicator_circle.lua
-- circle 类 indicator：真正的中空圆环（四象限纹理 + 内圆 mask 控制厚度）
-- 算法参考时间轴提醒类参考插件的 CircleRegion；纹理为 STT 自有（media/textures/circle_*.png）。
-- 独立 pool。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

T.ScreenReminderIndicators = T.ScreenReminderIndicators or {}
local Module = {}
T.ScreenReminderIndicators.circle = Module

local pool = {}

-- 注意：WoW 12.0 加载 PNG 必须带 .png 后缀；不带后缀会按 BLP 查找而失败
local TEXTURE      = "Interface\\AddOns\\ShengTangTools\\media\\textures\\circle_white.png"
local MASK_TEXTURE = "Interface\\AddOns\\ShengTangTools\\media\\textures\\circle_inner_mask.png"

-- 顶点常量（WoW 全局）
local UL = UPPER_LEFT_VERTEX
local UR = UPPER_RIGHT_VERTEX
local LL = LOWER_LEFT_VERTEX
local LR = LOWER_RIGHT_VERTEX

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function HexToRGB(hex, fallback)
    if type(hex) ~= "string" or #hex < 6 then
        if fallback then return fallback[1], fallback[2], fallback[3] end
        return 1, 1, 1
    end
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r / 255, g / 255, b / 255
end

-- 镜像翻转纹理（用于让圆弧扫过方向变化时贴图也翻面）
local function HorizontallyMirror(texture)
    local width = texture:GetWidth()
    local ULx, ULy = texture:GetVertexOffset(UL)
    local URx, URy = texture:GetVertexOffset(UR)
    local LLx, LLy = texture:GetVertexOffset(LL)
    local LRx, LRy = texture:GetVertexOffset(LR)
    texture:SetVertexOffset(UL,  width - ULx, ULy)
    texture:SetVertexOffset(UR, -width - URx, URy)
    texture:SetVertexOffset(LL,  width - LLx, LLy)
    texture:SetVertexOffset(LR, -width - LRx, LRy)
end

local Instance = {}
Instance.__index = Instance

local function CreateNewFrame()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(64, 64)
    frame:Hide()

    -- 内圆遮罩：控制环厚度（mask size = region.size - 2 * thickness）
    frame.mask = frame:CreateMaskTexture()
    frame.mask:SetPoint("CENTER")
    frame.mask:SetTexture(MASK_TEXTURE, "CLAMPTOWHITE", "CLAMPTOWHITE", "NEAREST")
    frame.mask:SetSnapToPixelGrid(false)
    frame.mask:SetTexelSnappingBias(0)

    -- 4 象限的 background + foreground 纹理
    frame.bg = {}
    frame.fg = {}
    for i = 1, 4 do
        frame.bg[i] = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg[i]:SetTexture(TEXTURE)
        frame.bg[i]:SetVertexColor(0, 0, 0, 0.5)
        frame.bg[i]:AddMaskTexture(frame.mask)
        frame.bg[i]:SetSnapToPixelGrid(false)
        frame.bg[i]:SetTexelSnappingBias(0)

        frame.fg[i] = frame:CreateTexture(nil, "BACKGROUND")
        frame.fg[i]:SetTexture(TEXTURE)
        frame.fg[i]:AddMaskTexture(frame.mask)
        frame.fg[i]:SetSnapToPixelGrid(false)
        frame.fg[i]:SetTexelSnappingBias(0)
    end

    -- bg 锚点 + texCoord（4 象限各占 1/4 圆形纹理）
    -- 1: 右上 (0-90°)
    frame.bg[1]:SetPoint("BOTTOMLEFT", frame, "CENTER")
    frame.bg[1]:SetPoint("TOPRIGHT",  frame, "TOPRIGHT")
    frame.bg[1]:SetTexCoord(0.5, 0, 0.5, 0.5, 1, 0, 1, 0.5)
    frame.fg[1]:SetPoint("BOTTOMLEFT", frame, "CENTER")
    frame.fg[1]:SetPoint("TOPRIGHT",  frame, "TOPRIGHT")
    -- 2: 右下 (90-180°)
    frame.bg[2]:SetPoint("TOPLEFT",     frame, "CENTER")
    frame.bg[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    frame.bg[2]:SetTexCoord(0.5, 0.5, 0.5, 1, 1, 0.5, 1, 1)
    frame.fg[2]:SetPoint("TOPLEFT",     frame, "CENTER")
    frame.fg[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    -- 3: 左下 (180-270°)
    frame.bg[3]:SetPoint("TOPRIGHT",    frame, "CENTER")
    frame.bg[3]:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT")
    frame.bg[3]:SetTexCoord(0, 0.5, 0, 1, 0.5, 0.5, 0.5, 1)
    frame.fg[3]:SetPoint("TOPRIGHT",    frame, "CENTER")
    frame.fg[3]:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT")
    -- 4: 左上 (270-360°)
    frame.bg[4]:SetPoint("BOTTOMRIGHT", frame, "CENTER")
    frame.bg[4]:SetPoint("TOPLEFT",     frame, "TOPLEFT")
    frame.bg[4]:SetTexCoord(0, 0, 0, 0.5, 0.5, 0, 0.5, 0.5)
    frame.fg[4]:SetPoint("BOTTOMRIGHT", frame, "CENTER")
    frame.fg[4]:SetPoint("TOPLEFT",     frame, "TOPLEFT")

    -- 中央图标
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon:SetPoint("CENTER")
    frame.icon:Hide()

    -- 倒数 fs
    frame.countdown = frame:CreateFontString(nil, "OVERLAY")
    frame.countdown:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")

    -- chip 文本 fs（同播报文案；左右位置时按字符竖排）
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    frame.label:Hide()
    return frame
end

-- 将字符串按 utf-8 字符拆为单字数组（中文/英文/emoji 通用）
local function SplitUTF8Chars(s)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    local i = 1
    local len = #s
    while i <= len do
        local b = string.byte(s, i)
        local size = 1
        if b >= 0xF0 then size = 4
        elseif b >= 0xE0 then size = 3
        elseif b >= 0xC0 then size = 2
        end
        out[#out + 1] = string.sub(s, i, i + size - 1)
        i = i + size
    end
    return out
end

-- 把所有 fg 还原到满格（用于切换 indicator 或重置）
local function ResetFgFull(frame)
    frame.fg[1]:ClearVertexOffsets()
    frame.fg[1]:SetTexCoord(0.5, 0, 0.5, 0.5, 1, 0, 1, 0.5)
    frame.fg[2]:ClearVertexOffsets()
    frame.fg[2]:SetTexCoord(0.5, 0.5, 0.5, 1, 1, 0.5, 1, 1)
    frame.fg[3]:ClearVertexOffsets()
    frame.fg[3]:SetTexCoord(0, 0.5, 0, 1, 0.5, 0.5, 0.5, 1)
    frame.fg[4]:ClearVertexOffsets()
    frame.fg[4]:SetTexCoord(0, 0, 0, 0.5, 0.5, 0, 0.5, 0.5)
end

-- 按角度截断 4 象限 fg（degrees ∈ [0,360]）
local function SetDegrees(frame, degrees, radius)
    degrees = Clamp(degrees, 0, 360)
    ResetFgFull(frame)
    local rad = math.rad(90 - degrees)
    local u = math.cos(rad)
    local v = math.sin(rad)

    frame.fg[1]:SetShown(degrees < 90)
    if degrees == 0 or (degrees > 0 and degrees < 90) then
        frame.fg[1]:SetVertexOffset(UR, -u * radius, (v - 1) * radius)
        frame.fg[1]:SetTexCoord(0, 0, 0, 0.5, 0.5 * (1 - u), 0.5 * (1 - v), 0.5, 0.5)
        HorizontallyMirror(frame.fg[1])
    end

    frame.fg[2]:SetShown(degrees < 180)
    if degrees == 90 or (degrees > 90 and degrees < 180) then
        frame.fg[2]:SetVertexOffset(UR, (u - 1) * radius, v * radius)
        frame.fg[2]:SetTexCoord(0.5, 0.5, 0.5, 1, 0.5 * (1 + u), 0.5 * (1 - v), 1, 1)
    end

    frame.fg[3]:SetShown(degrees < 270)
    if degrees == 180 or (degrees > 180 and degrees < 270) then
        frame.fg[3]:SetVertexOffset(LL, -u * radius, (v + 1) * radius)
        frame.fg[3]:SetTexCoord(0.5, 0.5, 0.5 * (1 - u), 0.5 * (1 - v), 1, 0.5, 1, 1)
        HorizontallyMirror(frame.fg[3])
    end

    frame.fg[4]:SetShown(degrees < 360)
    if degrees == 270 or (degrees > 270 and degrees < 360) then
        frame.fg[4]:SetVertexOffset(LL, (u + 1) * radius, v * radius)
        frame.fg[4]:SetTexCoord(0, 0, 0.5 * (1 + u), 0.5 * (1 - v), 0.5, 0, 0.5, 0.5)
    end
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
    instance.ctx = nil
    return instance
end

function Module.Release(instance)
    if not instance then return end
    instance:Stop()
    instance.frame:Hide()
    instance.frame:ClearAllPoints()
    instance.frame:SetParent(UIParent)
    instance.frame.countdown:SetText("")
    instance.frame.icon:SetTexture(nil)
    instance.frame.icon:Hide()
    instance.frame.label:SetText("")
    instance.frame.label:Hide()
    instance.ctx = nil
    pool[#pool + 1] = instance
end

function Instance:ApplyStyle()
    local def = self.def
    if not def then return end
    local style = def.style or {}
    local radius = math.max(8, tonumber(style.radius) or 32)
    local size = radius * 2
    self.frame:SetSize(size, size)
    self.frame.bg[1]:SetSize(radius, radius)
    self.frame.bg[2]:SetSize(radius, radius)
    self.frame.bg[3]:SetSize(radius, radius)
    self.frame.bg[4]:SetSize(radius, radius)
    self.frame.fg[1]:SetSize(radius, radius)
    self.frame.fg[2]:SetSize(radius, radius)
    self.frame.fg[3]:SetSize(radius, radius)
    self.frame.fg[4]:SetSize(radius, radius)

    -- 厚度：mask size = size - 2 * thickness（thickness 越大，环越粗）
    local thickness = Clamp(tonumber(style.thickness) or 8, 1, math.floor(size / 2 - 1))
    self.frame.mask:SetSize(size - 2 * thickness, size - 2 * thickness)

    -- 材质 preset：bg/fg/glow 共用同一纹理
    local tex = TEXTURE
    if T.ScreenReminderMediaPresets and T.ScreenReminderMediaPresets.GetTexture then
        tex = T.ScreenReminderMediaPresets.GetTexture("circle", style.texturePreset or "flat") or TEXTURE
    end
    for i = 1, 4 do
        self.frame.bg[i]:SetTexture(tex)
        self.frame.fg[i]:SetTexture(tex)
    end

    -- 颜色
    local cr, cg, cb = HexToRGB(style.color, { 0.2, 0.8, 1.0 })
    for i = 1, 4 do
        self.frame.fg[i]:SetVertexColor(cr, cg, cb, 1)
    end
    -- bg 颜色（轮廓底色）
    local br, bbg, bb = HexToRGB(style.bgColor, { 0, 0, 0 })
    for i = 1, 4 do
        self.frame.bg[i]:SetVertexColor(br, bbg, bb, 0.5)
    end

    -- 中央图标
    if style.showIcon then
        local iconSize = math.max(8, tonumber(style.iconSize) or math.floor(radius * 0.8))
        self.frame.icon:SetSize(iconSize, iconSize)
        self.frame.icon:Show()
    else
        self.frame.icon:Hide()
    end

    -- countdown 字号 + 位置
    local pos = (def.countdown and def.countdown.position) or "overlay"
    local cdFontSize = T.ScreenReminderCountdown and T.ScreenReminderCountdown.ResolveFontSize
        and T.ScreenReminderCountdown.ResolveFontSize(def.countdown, math.max(10, math.floor(radius * 0.6)))
        or math.max(10, math.floor(radius * 0.6))
    self.frame.countdown:SetFont(STANDARD_TEXT_FONT, cdFontSize, "OUTLINE")
    self.frame.countdown:ClearAllPoints()
    if pos == "left" then
        self.frame.countdown:SetPoint("RIGHT", self.frame, "LEFT", -4, 0)
    elseif pos == "right" then
        self.frame.countdown:SetPoint("LEFT", self.frame, "RIGHT", 4, 0)
    elseif pos == "above" then
        self.frame.countdown:SetPoint("BOTTOM", self.frame, "TOP", 0, 2)
    elseif pos == "below" then
        self.frame.countdown:SetPoint("TOP", self.frame, "BOTTOM", 0, -2)
    else
        self.frame.countdown:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    end

    -- chip 文本字号 + 位置 + 横/竖排
    local showText = style.showText == true
    if showText then
        local tFontSize = math.max(8, tonumber(style.textFontSize) or 14)
        self.frame.label:SetFont(STANDARD_TEXT_FONT, tFontSize, "OUTLINE")
        self.frame.label:ClearAllPoints()
        local tpos = style.textPosition or "below"
        if tpos == "above" then
            self.frame.label:SetPoint("BOTTOM", self.frame, "TOP", 0, 4)
            self.frame.label:SetJustifyH("CENTER")
        elseif tpos == "left" then
            self.frame.label:SetPoint("RIGHT", self.frame, "LEFT", -6, 0)
            self.frame.label:SetJustifyH("CENTER")
        elseif tpos == "right" then
            self.frame.label:SetPoint("LEFT", self.frame, "RIGHT", 6, 0)
            self.frame.label:SetJustifyH("CENTER")
        else -- below
            self.frame.label:SetPoint("TOP", self.frame, "BOTTOM", 0, -4)
            self.frame.label:SetJustifyH("CENTER")
        end
        self.frame.label:SetSpacing(0)
        self.frame.label:Show()
    else
        self.frame.label:Hide()
    end

    -- 复位 fg 满格（运行时 OnUpdate 会重新算 degrees）
    ResetFgFull(self.frame)
end

-- 按 textPosition 把 ctx.text 应用到 label（left/right 自动竖排）
function Instance:ApplyLabelText()
    local style = (self.def and self.def.style) or {}
    if not (style.showText == true) then
        self.frame.label:SetText("")
        return
    end
    local text = (self.ctx and self.ctx.text) or ""
    local tpos = style.textPosition or "below"
    if tpos == "left" or tpos == "right" then
        local chars = SplitUTF8Chars(text)
        self.frame.label:SetText(table.concat(chars, "\n"))
    else
        self.frame.label:SetText(text)
    end
end

function Instance:SetData(def)
    self.def = def
    self:ApplyStyle()
end

function Instance:ResolveIcon()
    local ctx = self.ctx or {}
    if ctx.spellIcon then return ctx.spellIcon end
    if ctx.spellID and ctx.spellID > 0 then
        return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ctx.spellID)
            or (GetSpellTexture and GetSpellTexture(ctx.spellID))
            or 134400
    end
    return 134400
end

function Instance:Refresh()
    self:ApplyStyle()
    self:ApplyLabelText()
    if self.running and self.frame.icon:IsShown() then
        self.frame.icon:SetTexture(self:ResolveIcon())
    end
end

function Instance:Start(ctx, duration)
    self.ctx = ctx or {}
    self.duration = math.max(0.05, tonumber(duration) or 0)
    self.endTime = GetTime() + self.duration
    self.lingerActive = false
    self.lingerEndTime = nil
    self.frame:SetAlpha(1)
    if self.frame.countdown then self.frame.countdown:Show() end
    self.running = true

    if self.frame.icon:IsShown() then
        self.frame.icon:SetTexture(self:ResolveIcon())
    end

    self:ApplyLabelText()

    -- 初始角度
    self:UpdateProgress()
    self:UpdateCountdown()

    self._accum = 0
    self.frame:SetScript("OnUpdate", function(_, dt)
        self:OnUpdate(dt)
    end)
end

function Instance:UpdateProgress()
    local def = self.def
    if not def then return end
    local style = def.style or {}
    local elapsed = self.duration - math.max(0, (self.endTime or 0) - GetTime())
    local fillMode = style.fillMode or "drain"
    local direction = style.direction or "ccw"
    local progress = self.duration > 0 and (elapsed / self.duration) or 0
    -- drain: 满 → 空，最终 degrees 走向 0；fill: 空 → 满
    local degrees
    if fillMode == "drain" then
        degrees = (1 - progress) * 360
    else
        degrees = progress * 360
    end
    -- direction: ccw 默认顺时针 swipe 出去；按用户视觉 ccw 反向
    if direction == "ccw" then
        degrees = 360 - degrees
    end
    local radius = (self.frame:GetWidth() or 64) / 2
    SetDegrees(self.frame, degrees, radius)
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
        local lingerSec = math.max(0, tonumber(self.lingerSec) or 0)
        if lingerSec > 0 then
            self.lingerActive = true
            self.lingerEndTime = GetTime() + lingerSec
            if self.frame.countdown then self.frame.countdown:Hide() end
            if self.lingerFadeEnabled ~= false then
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
    self:UpdateProgress()
    self:UpdateCountdown()
end

function Instance:Stop()
    self.running = false
    self.lingerActive = false
    self.lingerEndTime = nil
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(self.frame) end
        self.frame:SetAlpha(1)
        if self.frame.countdown then self.frame.countdown:Show() end
    end
end

function Instance:SetOnFinish(callback)
    self.onFinish = callback
end

function Instance:SetText(text)
    self.ctx = self.ctx or {}
    self.ctx.text = text or ""
end

end)
