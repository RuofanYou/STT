-- screen_reminder/indicator_icon.lua
-- icon 类 indicator：方形图标 + 倒数 + 可选标签
-- 独立 pool。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

T.ScreenReminderIndicators = T.ScreenReminderIndicators or {}
local Module = {}
T.ScreenReminderIndicators.icon = Module

local pool = {}

local function HexToRGB(hex)
    if type(hex) ~= "string" or #hex < 6 then
        return 1, 1, 1
    end
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r / 255, g / 255, b / 255
end

local DEFAULT_ICON = 134400 -- 问号图标

local Instance = {}
Instance.__index = Instance

local function CreateNewFrame()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(36, 36)
    frame:Hide()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon:SetAllPoints(frame)

    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, frame, "CooldownFrameTemplate")
    if ok and cooldown then
        cooldown:SetAllPoints(frame)
        if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
        if cooldown.SetReverse then cooldown:SetReverse(true) end
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
        frame.cooldown = cooldown
    end

    if frame.SetBackdrop then
        frame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    frame.countdown = frame:CreateFontString(nil, "OVERLAY")
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    frame.label:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    return frame
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
    instance.frame.icon:SetTexture(nil)
    instance.frame.countdown:SetText("")
    instance.frame.label:SetText("")
    instance.ctx = nil
    pool[#pool + 1] = instance
end

function Instance:ApplyStyle()
    local def = self.def
    if not def then return end
    local style = def.style or {}
    local size = math.max(8, tonumber(style.size) or 36)
    self.frame:SetSize(size, size)

    if style.desaturated then
        self.frame.icon:SetDesaturated(true)
    else
        self.frame.icon:SetDesaturated(false)
    end

    if self.frame.SetBackdrop then
        if style.borderEnabled ~= false then
            local r, g, b = HexToRGB(style.borderColor or "000000")
            self.frame:SetBackdropBorderColor(r, g, b, 1)
        else
            self.frame:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end

    self.frame.label:SetShown(style.showLabel == true)
    if self.frame.cooldown then
        self.frame.cooldown:SetShown(style.cooldownSwipeEnabled ~= false)
    end

    -- 倒数布局
    local pos = (def.countdown and def.countdown.position) or "overlay"
    local cdFontSize = T.ScreenReminderCountdown and T.ScreenReminderCountdown.ResolveFontSize
        and T.ScreenReminderCountdown.ResolveFontSize(def.countdown, math.max(10, math.floor(size * 0.45)))
        or math.max(10, math.floor(size * 0.45))
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
    else -- overlay
        self.frame.countdown:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    end
end

function Instance:SetData(def)
    self.def = def
    self:ApplyStyle()
end

function Instance:SetText(text)
    self.frame.label:SetText(text or "")
end

function Instance:ResolveIconTexture()
    local style = (self.def and self.def.style) or {}
    local ctx = self.ctx or {}
    if style.source == "spellID" then
        local sid = tonumber(style.spellID) or 0
        if sid > 0 then
            return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                or (GetSpellTexture and GetSpellTexture(sid))
                or DEFAULT_ICON
        end
    elseif style.source == "texture" then
        if type(style.texture) == "string" and style.texture ~= "" then
            return style.texture
        end
    end
    -- context: 优先用 ctx.spellIcon，再 ctx.spellID 查
    if ctx.spellIcon then return ctx.spellIcon end
    if ctx.spellID and ctx.spellID > 0 then
        return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ctx.spellID)
            or (GetSpellTexture and GetSpellTexture(ctx.spellID))
            or DEFAULT_ICON
    end
    return DEFAULT_ICON
end

function Instance:Refresh()
    self:ApplyStyle()
    if self.running then
        self.frame.icon:SetTexture(self:ResolveIconTexture())
        if self.frame.cooldown then
            if self.def and self.def.style and self.def.style.cooldownSwipeEnabled == false then
                self.frame.cooldown:SetCooldown(0, 0)
                self.frame.cooldown:Hide()
            else
                self.frame.cooldown:Show()
                self.frame.cooldown:SetCooldown(self.startTime or GetTime(), self.duration or 0)
            end
        end
    end
end

function Instance:Start(ctx, duration)
    self.ctx = ctx or {}
    self:ApplyStyle()
    self.duration = math.max(0.05, tonumber(duration) or 0)
    self.startTime = GetTime()
    self.endTime = self.startTime + self.duration
    self.lingerActive = false
    self.lingerEndTime = nil
    self.frame:SetAlpha(1)
    self.frame.countdown:Show()
    self.frame.icon:SetTexture(self:ResolveIconTexture())
    if self.frame.cooldown then
        if self.def and self.def.style and self.def.style.cooldownSwipeEnabled == false then
            self.frame.cooldown:SetCooldown(0, 0)
            self.frame.cooldown:Hide()
        else
            self.frame.cooldown:Show()
            self.frame.cooldown:SetCooldown(self.startTime, self.duration)
        end
    end
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
    self.startTime = nil
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        if T.ScreenReminderEffects then
            T.ScreenReminderEffects.StopPixelGlow(self.frame)
        end
        if self.frame.cooldown then
            if self.frame.cooldown.Clear then
                self.frame.cooldown:Clear()
            else
                self.frame.cooldown:SetCooldown(0, 0)
            end
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
