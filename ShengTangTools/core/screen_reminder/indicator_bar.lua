-- screen_reminder/indicator_bar.lua
-- bar 类 indicator：水平进度条 + 文本 + 倒数 + 可选图标
-- 复用 T.BarWidget 作为底层渲染（不另造）。
-- 因 BarWidget:Create 要求 duration > 0，本 instance 在每次 Start 时新建 widget，Stop 时 Destroy。
-- 上层 indicator instance 仍走 Acquire/Release pool 以减少 frame 创建。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

T.ScreenReminderIndicators = T.ScreenReminderIndicators or {}
local Module = {}
T.ScreenReminderIndicators.bar = Module

local pool = {}

local function HexToRGB(hex, fallback)
    if type(hex) ~= "string" or #hex < 6 then
        return fallback and fallback[1] or 1, fallback and fallback[2] or 1, fallback and fallback[3] or 1, 1
    end
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r / 255, g / 255, b / 255, 1
end

local function StyleFromDef(def)
    local style = (def and def.style) or {}
    local br, bg, bb, ba = HexToRGB(style.barColor, { 0.55, 0.85, 0.4 })
    local kr, kg, kb, ka = HexToRGB(style.bgColor, { 0.1, 0.1, 0.1 })
    local barTexturePath
    if T.ScreenReminderMediaPresets and T.ScreenReminderMediaPresets.GetTexture then
        barTexturePath = T.ScreenReminderMediaPresets.GetTexture("statusbar", style.barTexture or "blizzard")
    end
    return {
        width = math.max(40, tonumber(style.width) or 240),
        height = math.max(8, tonumber(style.height) or 20),
        barColor = { br, bg, bb, ba },
        bgColor = { kr, kg, kb, 0.55 },
        borderSize = style.border ~= false and 1 or 0,
        borderColor = { 0, 0, 0, 1 },
        iconSize = math.max(8, tonumber(style.iconSize) or 20),
        iconGap = 2,
        tickFontSize = 11,
        labelFontSize = math.max(10, math.floor((tonumber(style.height) or 20) * 0.6)),
        labelRemainFmt = "",   -- 我们自己管理倒数文本，不让 BarWidget 自带
        barTexture = barTexturePath,
    }
end

local Instance = {}
Instance.__index = Instance

local function CreateNewContainer()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(240, 32)
    frame:Hide()
    -- 顶层挂一个倒数 fs（覆盖在 bar 之上或左右两侧）
    frame.countdown = frame:CreateFontString(nil, "OVERLAY")
    frame.countdown:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    return frame
end

function Module.Acquire(parent)
    local instance = table.remove(pool)
    if not instance then
        instance = setmetatable({ frame = CreateNewContainer() }, Instance)
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
    if instance.widget then
        instance.widget:Destroy()
        instance.widget = nil
    end
    instance.frame:Hide()
    instance.frame:ClearAllPoints()
    instance.frame:SetParent(UIParent)
    instance.frame.countdown:SetText("")
    pool[#pool + 1] = instance
end

function Instance:SetData(def)
    self.def = def
    -- style 变化在 Start 重建 widget 时生效；这里只处理倒数布局
    self:LayoutCountdown()
end

function Instance:LayoutCountdown()
    local def = self.def
    if not def then return end
    local pos = (def.countdown and def.countdown.position) or "right"
    local cd = self.frame.countdown
    local cdFontSize = T.ScreenReminderCountdown and T.ScreenReminderCountdown.ResolveFontSize
        and T.ScreenReminderCountdown.ResolveFontSize(def.countdown, 13)
        or 13
    cd:SetFont(STANDARD_TEXT_FONT, cdFontSize, "OUTLINE")
    cd:ClearAllPoints()
    local barFrame = self.widget and self.widget.frame
    local anchor = barFrame or self.frame
    if pos == "left" then
        cd:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    elseif pos == "above" then
        cd:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    elseif pos == "below" then
        cd:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    elseif pos == "overlay" then
        cd:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else -- right
        cd:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    end
end

function Instance:Refresh()
    -- 若 widget 存在（运行中），用新 style 重做布局
    if self.widget then
        self.widget:SetStyle(StyleFromDef(self.def))
    end
    self:LayoutCountdown()
end

function Instance:ResolveIcon()
    local def = self.def
    local style = (def and def.style) or {}
    if style.iconOnLeft == false then return nil end
    local ctx = self.ctx or {}
    if ctx.spellIcon then return ctx.spellIcon end
    if ctx.spellID and ctx.spellID > 0 then
        return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ctx.spellID)
            or (GetSpellTexture and GetSpellTexture(ctx.spellID))
    end
    return nil
end

function Instance:Start(ctx, duration)
    self.ctx = ctx or {}
    self.duration = math.max(0.05, tonumber(duration) or 0)
    self.endTime = GetTime() + self.duration
    self.lingerActive = false
    self.lingerEndTime = nil
    self.frame:SetAlpha(1)
    self.frame.countdown:Show()

    -- 销毁旧 widget
    if self.widget then
        self.widget:Destroy()
        self.widget = nil
    end

    local widget = T.BarWidget:Create(self.frame, {
        duration = self.duration,
        iconTexture = self:ResolveIcon(),
        label = (self.def.style and self.def.style.textOnBar ~= false) and (self.ctx.text or "") or "",
        style = StyleFromDef(self.def),
    })
    if not widget then return end
    widget.frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    widget.frame:SetAlpha(1)
    self.widget = widget
    widget.onFinish = function()
        self:OnDurationEnd()
    end
    self:LayoutCountdown()
    widget:Start(GetTime())
    self.running = true

    self._accum = 0
    self.frame:SetScript("OnUpdate", function(_, dt)
        self:OnUpdate(dt)
    end)
    self:UpdateCountdown()
end

function Instance:OnDurationEnd()
    if not self.running or self.lingerActive then return end
    local glowTarget = self.widget and self.widget.frame or self.frame
    self.pixelGlowFrame = glowTarget
    local glowSec = T.ScreenReminderEffects and T.ScreenReminderEffects.StartPixelGlow(glowTarget, self.def) or 0
    local lingerSec = math.max(0, tonumber(self.lingerSec) or 0)
    local waitSec = math.max(lingerSec, glowSec)
    if waitSec > 0 then
        self.lingerActive = true
        self.lingerEndTime = GetTime() + waitSec
        self.frame.countdown:Hide()
        if lingerSec > 0 and self.lingerFadeEnabled ~= false then
            UIFrameFadeOut(self.frame, lingerSec, self.frame:GetAlpha() or 1, 0)
            if self.widget and self.widget.frame then
                UIFrameFadeOut(self.widget.frame, lingerSec, self.widget.frame:GetAlpha() or 1, 0)
            end
        end
        return
    end
    self:Stop()
    if self.onFinish then self.onFinish(self) end
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
        self:OnDurationEnd()
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
            T.ScreenReminderEffects.StopPixelGlow(self.pixelGlowFrame or self.frame)
            if self.widget and self.widget.frame ~= self.pixelGlowFrame then
                T.ScreenReminderEffects.StopPixelGlow(self.widget.frame)
            end
        end
        self.pixelGlowFrame = nil
        if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(self.frame) end
        self.frame:SetAlpha(1)
        if self.frame.countdown then self.frame.countdown:Show() end
    end
    if self.widget then
        if self.widget.frame then
            if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(self.widget.frame) end
            self.widget.frame:SetAlpha(1)
        end
        self.widget:Stop()
    end
end

function Instance:SetOnFinish(callback)
    self.onFinish = callback
end

function Instance:SetText(text)
    self.ctx = self.ctx or {}
    self.ctx.text = text or ""
    if self.widget then
        self.widget:SetLabel(text or "")
    end
end

end)
