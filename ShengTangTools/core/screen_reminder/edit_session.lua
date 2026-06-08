-- 屏幕提醒解锁锚点会话：GUI morph、胶囊、锚点子面板与空白点击关闭。
local T, C, L = unpack(select(2, ...))
local Schema
local ScreenReminder
local PanelConfig

T.RegisterColdFile("screenReminder.enabled", function()

Schema = T.ScreenReminderSchema
ScreenReminder = T.ScreenReminder
PanelConfig = T.ScreenReminderPanelConfig
local MORPH = {
    RANGE = 1000,
    BLEND_SPEED = 0.18,
    CAPSULE_W = 166,
    CAPSULE_H = 32,
    CAPSULE_RADIUS = 16,
    DOCK_X = 0,
    DOCK_Y = 0,
    GUI_FADE_END_T = 0.18,
    CAPSULE_FADE_START_T = 0.66,
    ANCHOR_FADE_IN = 0.16,
    ANCHOR_FADE_OUT = 0.14,
    SUBPANEL_W = 360,
    SUBPANEL_H = 420,
    SUBPANEL_PADDING = 14,
    SUBPANEL_RADIUS = 14,
    SUBPANEL_GAP = 16,
    SCREEN_PAD = 14,
}
T.SR_MORPH = MORPH

local Session = {
    state = "LOCKED",
    active = false,
    morphing = false,
    driver = nil,
    saved = nil,
    settledAt = nil,
    capsule = nil,
    morphSurface = nil,
    catcher = nil,
    floatHost = nil,
    eventFrame = nil,
    panelHome = nil,
}
T.ScreenReminderEditSession = Session

local function Debug(fmt, ...)
    if not T.debug then return end
    if select("#", ...) > 0 then
        T.debug(string.format("[ScreenReminderEditSession] " .. tostring(fmt), ...))
    else
        T.debug("[ScreenReminderEditSession] " .. tostring(fmt))
    end
end

local function Clamp(value, minValue, maxValue)
    local v = tonumber(value) or minValue
    if v < minValue then return minValue end
    if v > maxValue then return maxValue end
    return v
end

local function Lerp(fromValue, toValue, t)
    return (tonumber(fromValue) or 0) + ((tonumber(toValue) or 0) - (tonumber(fromValue) or 0)) * t
end

local function GetRoot()
    return Schema and Schema.GetRoot and Schema.GetRoot() or nil
end

local function GetDockStore()
    local root = GetRoot()
    if not root then return nil end
    root.editSession = type(root.editSession) == "table" and root.editSession or {}
    return root.editSession
end

local function ResolveDock()
    local store = GetDockStore()
    local parentW = (UIParent and UIParent:GetWidth()) or 1920
    local parentH = (UIParent and UIParent:GetHeight()) or 1080
    local defaultX = MORPH.SCREEN_PAD + MORPH.CAPSULE_W / 2 + MORPH.DOCK_X
    local defaultY = parentH - MORPH.SCREEN_PAD - MORPH.CAPSULE_H / 2 + MORPH.DOCK_Y
    local hasSavedDock = store and store.dockVersion == 4
    local x = hasSavedDock and tonumber(store.capsuleCenterX) or defaultX
    local y = hasSavedDock and tonumber(store.capsuleCenterY) or defaultY
    x = Clamp(x, MORPH.SCREEN_PAD + MORPH.CAPSULE_W / 2, parentW - MORPH.SCREEN_PAD - MORPH.CAPSULE_W / 2)
    y = Clamp(y, MORPH.SCREEN_PAD + MORPH.CAPSULE_H / 2, parentH - MORPH.SCREEN_PAD - MORPH.CAPSULE_H / 2)
    return x, y
end

local function SetFrameAlpha(frame, alpha)
    if frame and frame.SetAlpha then
        frame:SetAlpha(alpha)
    end
end

local function SetFrameShown(frame, shown)
    if frame and frame.SetShown then
        frame:SetShown(shown == true)
    elseif frame then
        if shown then frame:Show() else frame:Hide() end
    end
end

local function MakeTexture(parent, layer, texture)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetTexture(texture or "Interface\\Buttons\\WHITE8X8")
    return tex
end

local function SetTextureColor(texture, color)
    if texture and texture.SetVertexColor then
        texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

local function BuildPillSurface(frame, radius, color, borderColor)
    local r = tonumber(radius) or 12
    local parts = frame._sttPillParts
    if not parts then
        parts = {
            bg = MakeTexture(frame, "BACKGROUND"),
            lineTop = MakeTexture(frame, "BORDER"),
            lineBottom = MakeTexture(frame, "BORDER"),
            lineLeft = MakeTexture(frame, "BORDER"),
            lineRight = MakeTexture(frame, "BORDER"),
            shine = MakeTexture(frame, "ARTWORK"),
        }
        frame._sttPillParts = parts
    end

    parts.bg:SetAllPoints(frame)

    parts.lineTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
    parts.lineTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -1)
    parts.lineTop:SetHeight(1)
    parts.lineBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
    parts.lineBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)
    parts.lineBottom:SetHeight(1)
    parts.lineLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -r * 0.35)
    parts.lineLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, r * 0.35)
    parts.lineLeft:SetWidth(1)
    parts.lineRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -r * 0.35)
    parts.lineRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, r * 0.35)
    parts.lineRight:SetWidth(1)

    parts.shine:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -3)
    parts.shine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -3)
    parts.shine:SetHeight(math.max(4, math.floor(r * 0.42)))

    SetTextureColor(parts.bg, color)
    SetTextureColor(parts.lineTop, borderColor)
    SetTextureColor(parts.lineBottom, borderColor)
    SetTextureColor(parts.lineLeft, borderColor)
    SetTextureColor(parts.lineRight, borderColor)
    SetTextureColor(parts.shine, { 1, 1, 1, 0.055 })
end

local function CreateToolbarButton(parent, text, width, onClick, onDragStart, onDragStop)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, MORPH.CAPSULE_H - 8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button.bg = MakeTexture(button, "BACKGROUND")
    button.bg:SetAllPoints(button)
    SetTextureColor(button.bg, { 1, 1, 1, 0 })
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("CENTER")
    button.text:SetText(text or "")
    button.text:SetTextColor(1, 0.88, 0.48, 1)
    button:SetScript("OnEnter", function()
        SetTextureColor(button.bg, { 1, 1, 1, 0.08 })
    end)
    button:SetScript("OnLeave", function()
        SetTextureColor(button.bg, { 1, 1, 1, 0 })
    end)
    button:SetScript("OnMouseDown", function()
        SetTextureColor(button.bg, { 1, 0.82, 0.28, 0.10 })
    end)
    button:SetScript("OnMouseUp", function()
        SetTextureColor(button.bg, { 1, 1, 1, button:IsMouseOver() and 0.08 or 0 })
    end)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnDragStart", onDragStart)
    button:SetScript("OnDragStop", onDragStop)
    return button
end

local function BuildRoundedPanelSurface(frame, radius, color, borderColor)
    local r = tonumber(radius) or 12
    local parts = frame._sttRoundedParts
    if not parts then
        parts = {
            bgCenter = MakeTexture(frame, "BACKGROUND"),
            bgTop = MakeTexture(frame, "BACKGROUND"),
            bgBottom = MakeTexture(frame, "BACKGROUND"),
            bgLeft = MakeTexture(frame, "BACKGROUND"),
            bgRight = MakeTexture(frame, "BACKGROUND"),
            tl = MakeTexture(frame, "BACKGROUND", "Interface\\AddOns\\ShengTangTools\\media\\textures\\circle_white.png"),
            tr = MakeTexture(frame, "BACKGROUND", "Interface\\AddOns\\ShengTangTools\\media\\textures\\circle_white.png"),
            bl = MakeTexture(frame, "BACKGROUND", "Interface\\AddOns\\ShengTangTools\\media\\textures\\circle_white.png"),
            br = MakeTexture(frame, "BACKGROUND", "Interface\\AddOns\\ShengTangTools\\media\\textures\\circle_white.png"),
            lineTop = MakeTexture(frame, "BORDER"),
            lineBottom = MakeTexture(frame, "BORDER"),
            lineLeft = MakeTexture(frame, "BORDER"),
            lineRight = MakeTexture(frame, "BORDER"),
            glow = MakeTexture(frame, "ARTWORK"),
        }
        parts.tl:SetTexCoord(0, 0.5, 0, 0.5)
        parts.tr:SetTexCoord(0.5, 1, 0, 0.5)
        parts.bl:SetTexCoord(0, 0.5, 0.5, 1)
        parts.br:SetTexCoord(0.5, 1, 0.5, 1)
        frame._sttRoundedParts = parts
    end

    parts.bgCenter:SetPoint("TOPLEFT", frame, "TOPLEFT", r, -r)
    parts.bgCenter:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, r)
    parts.bgTop:SetPoint("TOPLEFT", frame, "TOPLEFT", r, 0)
    parts.bgTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -r, 0)
    parts.bgTop:SetHeight(r)
    parts.bgBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", r, 0)
    parts.bgBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, 0)
    parts.bgBottom:SetHeight(r)
    parts.bgLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -r)
    parts.bgLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, r)
    parts.bgLeft:SetWidth(r)
    parts.bgRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -r)
    parts.bgRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, r)
    parts.bgRight:SetWidth(r)
    parts.tl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    parts.tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    parts.bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    parts.br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    parts.tl:SetSize(r, r)
    parts.tr:SetSize(r, r)
    parts.bl:SetSize(r, r)
    parts.br:SetSize(r, r)

    parts.lineTop:SetPoint("TOPLEFT", frame, "TOPLEFT", r, -1)
    parts.lineTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -r, -1)
    parts.lineTop:SetHeight(1)
    parts.lineBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", r, 1)
    parts.lineBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, 1)
    parts.lineBottom:SetHeight(1)
    parts.lineLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -r)
    parts.lineLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, r)
    parts.lineLeft:SetWidth(1)
    parts.lineRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -r)
    parts.lineRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, r)
    parts.lineRight:SetWidth(1)
    parts.glow:SetPoint("TOPLEFT", frame, "TOPLEFT", r, -2)
    parts.glow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -r, -2)
    parts.glow:SetHeight(18)

    for _, key in ipairs({ "bgCenter", "bgTop", "bgBottom", "bgLeft", "bgRight", "tl", "tr", "bl", "br" }) do
        SetTextureColor(parts[key], color)
    end
    for _, key in ipairs({ "lineTop", "lineBottom", "lineLeft", "lineRight" }) do
        SetTextureColor(parts[key], borderColor)
    end
    SetTextureColor(parts.glow, { 1, 1, 1, 0.045 })
end

local function EaseOutCubic(t)
    t = Clamp(t, 0, 1)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

local function EaseInOutCubic(t)
    t = Clamp(t, 0, 1)
    if t < 0.5 then
        return 4 * t * t * t
    end
    local p = -2 * t + 2
    return 1 - (p * p * p) / 2
end

function Session:IsActive()
    return self.active == true
end

function Session:IsMorphing()
    return self.morphing == true
end

function Session:EnsureDriver()
    if self.driver then
        return self.driver
    end
    if not T.CreateSmoothValueDriver then
        return nil
    end
    self.driver = T.CreateSmoothValueDriver({
        range = MORPH.RANGE,
        blendSpeed = MORPH.BLEND_SPEED,
        onValueChanged = function(_, value)
            self:ApplyMorph((tonumber(value) or 0) / MORPH.RANGE)
        end,
    })
    return self.driver
end

function Session:EnsureCapsuleLayer()
    if self.capsule then
        return self.capsule
    end
    local gui = T.GUI_GetFrame and T.GUI_GetFrame()
    if not gui then
        return nil
    end
    local capsule = CreateFrame("Frame", nil, UIParent)
    capsule:SetSize(MORPH.CAPSULE_W, MORPH.CAPSULE_H)
    capsule:SetFrameStrata("DIALOG")
    capsule:SetFrameLevel(30)
    capsule:SetMovable(true)
    if capsule.SetClampedToScreen then
        capsule:SetClampedToScreen(true)
    end
    capsule:EnableMouse(true)
    capsule:SetAlpha(0)
    capsule:Hide()
    BuildPillSurface(capsule, MORPH.CAPSULE_RADIUS, { 0.015, 0.018, 0.022, 0.74 }, { 0.98, 0.78, 0.30, 0.24 })

    local function startDrag()
        self._capsuleDragging = true
        capsule:StartMoving()
    end
    local function stopDrag()
        capsule:StopMovingOrSizing()
        self:SaveCapsuleDock()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                self._capsuleDragging = false
            end)
        else
            self._capsuleDragging = false
        end
    end

    capsule:RegisterForDrag("LeftButton")
    capsule:SetScript("OnDragStart", startDrag)
    capsule:SetScript("OnDragStop", stopDrag)

    capsule.lockButton = CreateToolbarButton(capsule, L["SR_EDIT_TOOL_LOCK"] or "锁定", 78,
        function()
            if self._capsuleDragging then return end
            self:Exit()
        end,
        startDrag,
        stopDrag)
    capsule.lockButton:SetPoint("LEFT", capsule, "LEFT", 5, 0)

    capsule.divider = MakeTexture(capsule, "BORDER")
    capsule.divider:SetPoint("LEFT", capsule.lockButton, "RIGHT", 3, 0)
    capsule.divider:SetSize(1, MORPH.CAPSULE_H - 12)
    SetTextureColor(capsule.divider, { 1, 0.82, 0.28, 0.20 })

    capsule.testButton = CreateToolbarButton(capsule, L["SR_EDIT_TOOL_TEST"] or "测试", 72,
        function()
            if self._capsuleDragging then return end
            if ScreenReminder and ScreenReminder.RunTest then
                ScreenReminder:RunTest()
            end
        end,
        startDrag,
        stopDrag)
    capsule.testButton:SetPoint("LEFT", capsule.divider, "RIGHT", 3, 0)

    self.capsule = capsule
    return capsule
end

function Session:EnsureMorphSurface()
    if self.morphSurface then
        return self.morphSurface
    end
    local surface = CreateFrame("Frame", nil, UIParent)
    surface:SetFrameStrata("DIALOG")
    surface:SetFrameLevel(20)
    surface:EnableMouse(false)
    surface:SetAlpha(0)
    surface:Hide()
    BuildRoundedPanelSurface(surface, MORPH.SUBPANEL_RADIUS, { 0.015, 0.018, 0.022, 0.58 }, { 0.92, 0.72, 0.25, 0.22 })
    self.morphSurface = surface
    return surface
end

function Session:EnsureEventFrame()
    if self.eventFrame then
        return self.eventFrame
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function()
        if self.active then
            self:Abort()
        end
    end)
    self.eventFrame = frame
    return frame
end

function Session:EnsureFloatHost()
    if self.floatHost and self.catcher then
        return self.floatHost
    end
    local catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetFrameStrata("MEDIUM")
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseDown", function()
        self:CloseSubPanel()
    end)
    catcher:Hide()

    local host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("DIALOG")
    host:SetSize(MORPH.SUBPANEL_W + MORPH.SUBPANEL_PADDING * 2, MORPH.SUBPANEL_H + MORPH.SUBPANEL_PADDING * 2)
    host:EnableMouse(true)
    host:Hide()
    BuildRoundedPanelSurface(host, MORPH.SUBPANEL_RADIUS, { 0.014, 0.016, 0.02, 0.90 }, { 0.96, 0.76, 0.28, 0.34 })

    self.catcher = catcher
    self.floatHost = host
    return host
end

function Session:SaveSnapshot()
    self.saved = T.GUI_GetSnapshot and T.GUI_GetSnapshot() or nil
    return self.saved
end

function Session:RestoreSnapshot()
    if self.saved and T.GUI_RestoreSnapshot then
        T.GUI_RestoreSnapshot(self.saved)
    end
end

function Session:SaveCapsuleDock()
    local gui = T.GUI_GetFrame and T.GUI_GetFrame()
    local store = GetDockStore()
    local frame = self.capsule and self.capsule:IsShown() and self.capsule or gui
    if not (frame and store) then
        return
    end
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    local width = frame:GetWidth()
    local height = frame:GetHeight()
    if not (left and bottom and width and height) then
        return
    end
    store.capsuleCenterX = math.floor(left + width / 2 + 0.5)
    store.capsuleCenterY = math.floor(bottom + height / 2 + 0.5)
    store.dockVersion = 4
end

function Session:ApplyMorph(t)
    local gui = T.GUI_GetFrame and T.GUI_GetFrame()
    local snapshot = self.saved
    if not (gui and snapshot) then
        return
    end
    t = Clamp(t, 0, 1)

    local dockX, dockY = ResolveDock()
    local motionT = EaseInOutCubic(t)
    local width = Lerp(snapshot.width, MORPH.CAPSULE_W, motionT)
    local height = Lerp(snapshot.height, MORPH.CAPSULE_H, motionT)
    local centerX = Lerp(snapshot.centerX, dockX, motionT)
    local centerY = Lerp(snapshot.centerY, dockY, motionT)

    gui:ClearAllPoints()
    gui:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX, centerY)
    gui:SetSize(math.floor(width + 0.5), math.floor(height + 0.5))

    local contentAlpha
    if self.state == "LOCKING" then
        contentAlpha = 0
    elseif t <= MORPH.GUI_FADE_END_T then
        contentAlpha = 1 - (t / MORPH.GUI_FADE_END_T)
    else
        contentAlpha = 0
    end
    if T.GUI_SetContentAlpha then
        T.GUI_SetContentAlpha(contentAlpha)
    end
    if T.GUI_SetMorphSurfaceAlpha then
        T.GUI_SetMorphSurfaceAlpha(contentAlpha)
    end
    if T.GUI_SetMorphChromeHidden then
        T.GUI_SetMorphChromeHidden(t > 0.02)
    end
    if T.GUI_SetContentMouseEnabled then
        T.GUI_SetContentMouseEnabled(contentAlpha > 0.01)
    end

    local surface = self:EnsureMorphSurface()
    if surface then
        surface:ClearAllPoints()
        surface:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX, centerY)
        surface:SetSize(math.floor(width + 0.5), math.floor(height + 0.5))
        if t > 0.01 and t < 0.99 then
            surface:Show()
            local surfaceAlpha = self.state == "LOCKING" and (0.18 + 0.30 * (1 - t)) or (0.42 * EaseOutCubic(math.min(1, t / 0.22)))
            surface:SetAlpha(Clamp(surfaceAlpha, 0, 0.50))
        else
            surface:SetAlpha(0)
            surface:Hide()
        end
    end

    local capsule = self:EnsureCapsuleLayer()
    if capsule then
        capsule:ClearAllPoints()
        capsule:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX, centerY)
        capsule:SetSize(MORPH.CAPSULE_W, MORPH.CAPSULE_H)
        capsule:SetShown(t > 0.02)
        local capsuleAlpha = 0
        if t > MORPH.CAPSULE_FADE_START_T then
            capsuleAlpha = (t - MORPH.CAPSULE_FADE_START_T) / (1 - MORPH.CAPSULE_FADE_START_T)
        end
        capsule:SetAlpha(Clamp(capsuleAlpha, 0, 1))
    end

    if t >= 0.999 then
        self:OnMorphSettled(1)
    elseif t <= 0.001 then
        self:OnMorphSettled(0)
    else
        self.settledAt = nil
        self.morphing = true
    end
end

function Session:FadeAnchorsOut()
    if not (ScreenReminder and ScreenReminder.anchorFrames and T.EditMode and T.EditMode.GetOverlay) then
        return
    end
    for _, frame in pairs(ScreenReminder.anchorFrames) do
        local overlay = T.EditMode:GetOverlay(frame)
        if overlay and overlay:IsShown() then
            if UIFrameFadeOut then
                UIFrameFadeOut(overlay, MORPH.ANCHOR_FADE_OUT, overlay:GetAlpha() or 1, 0)
            else
                overlay:SetAlpha(0)
            end
        end
    end
end

function Session:OnMorphSettled(t)
    if self.settledAt == t then
        return
    end
    self.settledAt = t
    self.morphing = false

    if t == 1 then
        self.state = "UNLOCKED"
        if T.GUI_SetContentAlpha then
            T.GUI_SetContentAlpha(0)
        end
        if T.GUI_SetMorphSurfaceAlpha then
            T.GUI_SetMorphSurfaceAlpha(0)
        end
        if T.GUI_SetMorphChromeHidden then
            T.GUI_SetMorphChromeHidden(true)
        end
        if T.GUI_SetContentMouseEnabled then
            T.GUI_SetContentMouseEnabled(false)
        end
        local capsule = self:EnsureCapsuleLayer()
        if capsule then
            capsule:SetAlpha(1)
            capsule:Show()
        end
        return
    end

    self.state = "LOCKED"
    self.active = false
    self:CloseSubPanel()
    if ScreenReminder and ScreenReminder.SetLocked then
        ScreenReminder:SetLocked(true)
    end
    self:RestoreSnapshot()
    if T.GUI_SetContentAlpha then
        T.GUI_SetContentAlpha(1)
    end
    if T.GUI_SetMorphSurfaceAlpha then
        T.GUI_SetMorphSurfaceAlpha(1)
    end
    if T.GUI_SetMorphChromeHidden then
        T.GUI_SetMorphChromeHidden(false)
    end
    if T.GUI_SetContentMouseEnabled then
        T.GUI_SetContentMouseEnabled(true)
    end
    if T.GUI_SetResizeBoundsRelaxed then
        T.GUI_SetResizeBoundsRelaxed(false)
    end
    SetFrameShown(self.capsule, false)
    SetFrameShown(self.morphSurface, false)
end

function Session:Enter()
    local gui = T.GUI_GetFrame and T.GUI_GetFrame()
    if not (gui and ScreenReminder and ScreenReminder.SetLocked) then
        if ScreenReminder and ScreenReminder.SetLocked then
            ScreenReminder:SetLocked(false)
        end
        return
    end
    if self.active then
        if self.state == "LOCKING" and self.driver then
            self.state = "UNLOCKING"
            self.morphing = true
            self.settledAt = nil
            self.driver:ScrollTo(MORPH.RANGE)
        end
        return
    end

    local driver = self:EnsureDriver()
    if not driver then
        ScreenReminder:SetLocked(false)
        return
    end

    local indicators = Schema and Schema.ListIndicators and Schema.ListIndicators() or {}
    if #indicators == 0 then
        T.msg(L["SR_EDIT_NO_INDICATOR"] or "当前没有屏幕提醒指示器，请先新建一条。")
    end

    self:SaveSnapshot()
    if not self.saved then
        ScreenReminder:SetLocked(false)
        return
    end

    self.active = true
    self.morphing = true
    self.state = "UNLOCKING"
    self.settledAt = nil
    if T.GUI_SetResizeBoundsRelaxed then
        T.GUI_SetResizeBoundsRelaxed(true)
    end
    if T.GUI_SetContentAlpha then
        T.GUI_SetContentAlpha(1)
    end
    if T.GUI_SetMorphSurfaceAlpha then
        T.GUI_SetMorphSurfaceAlpha(1)
    end
    if T.GUI_SetMorphChromeHidden then
        T.GUI_SetMorphChromeHidden(false)
    end
    if T.GUI_SetContentMouseEnabled then
        T.GUI_SetContentMouseEnabled(true)
    end
    self:EnsureCapsuleLayer()
    self:EnsureEventFrame()
    ScreenReminder:SetLocked(false)
    driver:ScrollTo(MORPH.RANGE)
end

function Session:Exit()
    if not self.active then
        if ScreenReminder and ScreenReminder.SetLocked then
            ScreenReminder:SetLocked(true)
        end
        return
    end
    if self.state == "LOCKING" then
        return
    end
    local driver = self:EnsureDriver()
    if not driver then
        self:Abort()
        return
    end
    self:SaveCapsuleDock()
    self:CloseSubPanel()
    self:FadeAnchorsOut()
    self.state = "LOCKING"
    self.morphing = true
    self.settledAt = nil
    if self.capsule then
        self.capsule:SetAlpha(0)
    end
    driver:ScrollTo(0)
end

function Session:Abort()
    if not self.active then
        return
    end
    Debug("abort state=%s", tostring(self.state))
    local driver = self.driver
    if driver and driver.SnapTo then
        driver:SnapTo(0)
    end
    self.active = false
    self.morphing = false
    self.state = "LOCKED"
    self.settledAt = nil
    self:CloseSubPanel()
    SetFrameShown(self.capsule, false)
    SetFrameShown(self.morphSurface, false)
    if ScreenReminder and ScreenReminder.SetLocked then
        ScreenReminder:SetLocked(true)
    end
    self:RestoreSnapshot()
    if T.GUI_SetContentAlpha then
        T.GUI_SetContentAlpha(1)
    end
    if T.GUI_SetMorphSurfaceAlpha then
        T.GUI_SetMorphSurfaceAlpha(1)
    end
    if T.GUI_SetMorphChromeHidden then
        T.GUI_SetMorphChromeHidden(false)
    end
    if T.GUI_SetContentMouseEnabled then
        T.GUI_SetContentMouseEnabled(true)
    end
    if T.GUI_SetResizeBoundsRelaxed then
        T.GUI_SetResizeBoundsRelaxed(false)
    end
end

function Session:CapturePanelHome()
    if self.panelHome or not (PanelConfig and PanelConfig.frame) then
        return
    end
    local frame = PanelConfig.frame
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    self.panelHome = {
        parent = frame:GetParent(),
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x,
        y = y,
        width = PanelConfig.width,
        contentWidth = PanelConfig.contentWidth,
        height = frame:GetHeight(),
    }
end

function Session:RestorePanelHome()
    if not (self.panelHome and PanelConfig and PanelConfig.frame) then
        return
    end
    local frame = PanelConfig.frame
    local home = self.panelHome
    frame:Hide()
    frame:SetParent(home.parent)
    frame:ClearAllPoints()
    if home.point then
        frame:SetPoint(home.point, home.relativeTo, home.relativePoint, home.x or 0, home.y or 0)
    end
    if home.width and home.height then
        frame:SetSize(home.width, home.height)
    end
    PanelConfig.width = home.width
    PanelConfig.contentWidth = home.contentWidth
    frame:Show()
    self.panelHome = nil
end

function Session:PositionSubPanel(anchorFrame)
    local host = self.floatHost
    if not (host and anchorFrame and T.GetFrameRect) then
        return
    end
    local left, right, top, bottom = T.GetFrameRect(anchorFrame)
    if not (left and right and top and bottom) then
        return
    end
    local screenW = (UIParent and UIParent:GetWidth()) or 1920
    local screenH = (UIParent and UIParent:GetHeight()) or 1080
    local width = host:GetWidth() or MORPH.SUBPANEL_W
    local height = host:GetHeight() or (MORPH.SUBPANEL_H + MORPH.SUBPANEL_PADDING * 2)
    local x
    if right + MORPH.SUBPANEL_GAP + width <= screenW - MORPH.SCREEN_PAD then
        x = right + MORPH.SUBPANEL_GAP
    else
        x = left - MORPH.SUBPANEL_GAP - width
    end
    local y = top
    x = Clamp(x, MORPH.SCREEN_PAD, screenW - width - MORPH.SCREEN_PAD)
    y = Clamp(y, height + MORPH.SCREEN_PAD, screenH - MORPH.SCREEN_PAD)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

function Session:OnAnchorClicked(indicatorID, anchorFrame)
    if not self.active or self.state ~= "UNLOCKED" then
        return
    end
    if not (PanelConfig and PanelConfig.frame) then
        return
    end
    self:EnsureFloatHost()
    self:CapturePanelHome()

    local host = self.floatHost
    local panel = PanelConfig.frame
    PanelConfig.width = MORPH.SUBPANEL_W
    PanelConfig.contentWidth = MORPH.SUBPANEL_W - 18
    panel:SetParent(host)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", host, "TOPLEFT", MORPH.SUBPANEL_PADDING, -MORPH.SUBPANEL_PADDING)
    panel:SetSize(MORPH.SUBPANEL_W, MORPH.SUBPANEL_H)
    if PanelConfig.Refresh then
        PanelConfig:Refresh()
    end
    if T.GUI_SetFrameTreeMouseEnabled then
        T.GUI_SetFrameTreeMouseEnabled(panel, true)
    end
    panel:Show()
    host:Show()
    self.catcher:Show()
    self:PositionSubPanel(anchorFrame)
end

function Session:CloseSubPanel()
    SetFrameShown(self.catcher, false)
    SetFrameShown(self.floatHost, false)
    self:RestorePanelHome()
    if self.active and T.GUI_SetFrameTreeMouseEnabled and PanelConfig and PanelConfig.frame then
        T.GUI_SetFrameTreeMouseEnabled(PanelConfig.frame, false)
    end
end

if ScreenReminder and ScreenReminder.SetOnAnchorClicked then
    ScreenReminder:SetOnAnchorClicked(function(indicatorID, anchorFrame)
        Session:OnAnchorClicked(indicatorID, anchorFrame)
    end)
end

end)
