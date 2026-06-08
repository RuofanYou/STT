local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("interruptRotation.enabled", function()

local V = T.InterruptRotationView or {}
T.InterruptRotationView = V

local CARD_W, CARD_H, CARD_GAP = 220, 38, 5
local SELECTOR_W, SELECTOR_H = CARD_W + 28, CARD_H + 14
local BAR_H = 6
local BLEND_SPEED = 0.18
local CATCHUP_EPSILON = 0.001
local DEFAULT_TOP_RIGHT_X = -260
local DEFAULT_TOP_RIGHT_Y = -190

local function GetDB()
    if type(C.DB.interruptRotation) ~= "table" then
        C.DB.interruptRotation = {}
    end
    return C.DB.interruptRotation
end

local function WriteDBValue(key, value)
    local db = GetDB()
    db[key] = value
    if type(STT_DB) == "table" then
        STT_DB.interruptRotation = STT_DB.interruptRotation or {}
        STT_DB.interruptRotation[key] = value
    end
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function GetFallbackDurationSec(durationSec)
    if durationSec then
        return Clamp(durationSec, 0.2, 12)
    end
    local db = GetDB()
    return Clamp(tonumber(db.bannerDurationSec) or 2, 1, 12)
end

local function ShortName(name)
    local text = tostring(name or "")
    if Ambiguate then
        text = Ambiguate(text, "short") or text
    end
    return text:gsub("%-.+$", "")
end

local function SetBackdropColor(frame, r, g, b, a)
    if frame and frame.SetBackdropColor then
        frame:SetBackdropColor(r, g, b, a)
    end
end

local function SetBackdropBorderColor(frame, r, g, b, a)
    if frame and frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(r, g, b, a)
    end
end

local function CreateCard(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(CARD_W, CARD_H)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    SetBackdropColor(frame, 0.04, 0.04, 0.05, 0.86)

    frame.indexText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.indexText:SetPoint("LEFT", frame, "LEFT", 12, 0)
    frame.indexText:SetJustifyH("LEFT")
    frame.indexText:SetTextColor(0.82, 0.82, 0.82, 1)

    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.nameText:SetPoint("LEFT", frame.indexText, "RIGHT", 10, 0)
    frame.nameText:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    frame.nameText:SetJustifyH("LEFT")
    if frame.nameText.SetWordWrap then
        frame.nameText:SetWordWrap(false)
    end

    frame:Hide()
    return frame
end

local function SavePosition(container)
    if not container or not UIParent then
        return
    end
    local x, y = container:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (x and y and px and py) then
        return
    end
    WriteDBValue("cardX", math.floor((x - px) + 0.5))
    WriteDBValue("cardY", math.floor((y - py) + 0.5))
end

local function ApplyPosition(container)
    local db = GetDB()
    container:ClearAllPoints()
    if db.cardX ~= nil or db.cardY ~= nil then
        container:SetPoint("CENTER", UIParent, "CENTER", tonumber(db.cardX) or 0, tonumber(db.cardY) or 0)
    else
        container:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", DEFAULT_TOP_RIGHT_X, DEFAULT_TOP_RIGHT_Y)
    end
end

local function AdjustTargetForWrap(target, current, max)
    if not max or max <= 1 then
        return target
    end
    local adjusted = target
    local half = max / 2
    while adjusted - current > half do
        adjusted = adjusted - max
    end
    while current - adjusted > half do
        adjusted = adjusted + max
    end
    return adjusted
end

local function WrappedDistance(index, center, max)
    local distance = index - center
    if not max or max <= 1 then
        return distance
    end
    local half = max / 2
    while distance > half do
        distance = distance - max
    end
    while distance < -half do
        distance = distance + max
    end
    return distance
end

local function NormalizeIndex(value, max)
    if not max or max <= 0 then
        return 1
    end
    while value > max do
        value = value - max
    end
    while value < 1 do
        value = value + max
    end
    return value
end

local function UpdateCastBar(self)
    local progress = 0
    if self._fallbackStartMS and self._fallbackEndMS and self._fallbackEndMS > self._fallbackStartMS then
        progress = (GetTime() * 1000 - self._fallbackStartMS) / (self._fallbackEndMS - self._fallbackStartMS)
    end

    progress = Clamp(progress, 0, 1)
    self._selectorBar:SetValue(progress)
    if self._selectorFill then
        self._selectorFill:SetWidth(math.max(1, (SELECTOR_W - 10) * progress))
    end
end

local function OnUpdate(_, elapsed)
    local self = T.InterruptRotationView
    if not self or not self._container or not self._max or self._max <= 0 then
        return
    end

    local target = AdjustTargetForWrap(self._focusIndex or 1, self._smoothIndex or 1, self._max)
    self._smoothIndex = T.DeltaLerp(self._smoothIndex or target, target, BLEND_SPEED, elapsed)
    if math.abs((self._smoothIndex or target) - target) <= CATCHUP_EPSILON then
        self._smoothIndex = NormalizeIndex(target, self._max)
        self._focusIndex = NormalizeIndex(self._focusIndex or self._smoothIndex, self._max)
    end

    for index, card in ipairs(self._cards or {}) do
        if index > self._max then
            card:Hide()
        else
            local distance = WrappedDistance(index, self._smoothIndex or self._focusIndex or 1, self._max)
            local absDist = math.abs(distance)
            local y = -distance * (CARD_H + CARD_GAP)
            local scale = absDist < 0.5 and 1.08 or (absDist < 1.5 and 0.94 or 0.84)
            local alpha = absDist < 0.5 and 1.0 or (absDist < 1.5 and 0.72 or 0.34)

            card:ClearAllPoints()
            card:SetPoint("CENTER", self._container, "CENTER", 0, y)
            card:SetScale(scale)
            card:SetAlpha(alpha)
            card:Show()
        end
    end

    UpdateCastBar(self)
end

function V:EnsureContainer()
    if self._container then
        return self._container
    end

    local container = CreateFrame("Frame", nil, UIParent)
    container:SetSize(SELECTOR_W + 16, (CARD_H + CARD_GAP) * 6 + 48)
    container:SetFrameStrata("HIGH")
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:EnableMouse(false)
    container:SetScript("OnUpdate", OnUpdate)
    ApplyPosition(container)

    container.selector = CreateFrame("Frame", nil, container, "BackdropTemplate")
    container.selector:SetSize(SELECTOR_W, SELECTOR_H)
    container.selector:SetPoint("CENTER", container, "CENTER", 0, 0)
    container.selector:SetFrameLevel(container:GetFrameLevel() + 12)
    container.selector:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    SetBackdropColor(container.selector, 0.08, 0.07, 0.03, 0.18)
    SetBackdropBorderColor(container.selector, 1, 0.82, 0, 0.72)
    container.selector:EnableMouse(false)

    container.selector.fill = container.selector:CreateTexture(nil, "ARTWORK")
    container.selector.fill:SetPoint("LEFT", container.selector, "LEFT", 5, 0)
    container.selector.fill:SetHeight(SELECTOR_H - 10)
    container.selector.fill:SetWidth(1)
    container.selector.fill:SetColorTexture(1, 0.82, 0, 0.22)

    container.castBar = CreateFrame("StatusBar", nil, container)
    container.castBar:SetSize(SELECTOR_W - 16, BAR_H)
    container.castBar:SetPoint("TOP", container.selector, "BOTTOM", 0, -3)
    container.castBar:SetMinMaxValues(0, 1)
    container.castBar:SetValue(0)
    container.castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    container.castBar:SetStatusBarColor(1, 0.82, 0, 0.95)
    container.castBar:SetFrameLevel(container:GetFrameLevel() + 13)

    container.castBar.bg = container.castBar:CreateTexture(nil, "BACKGROUND")
    container.castBar.bg:SetAllPoints()
    container.castBar.bg:SetColorTexture(0, 0, 0, 0.55)

    self._container = container
    self._selectorFrame = container.selector
    self._selectorBar = container.castBar
    self._selectorFill = container.selector.fill
    self._cards = self._cards or {}
    if T.EditMode and T.EditMode.Register then
        T.EditMode:Register({
            frame = container,
            displayName = L["GUI_NAV_INTERRUPT_ROTATION"] or "打断轮替",
            saveFunc = function() SavePosition(container) end,
            group = "solo",
            onExit = function()
                if not V._visible then container:Hide() end
            end,
        })
    end
    container:Hide()
    return container
end

function V:Rebuild(players, myKick, max)
    max = math.max(0, tonumber(max) or 0)
    self._max = max
    self._myKick = tonumber(myKick) or 0
    self._focusIndex = NormalizeIndex(tonumber(self._focusIndex) or 1, math.max(max, 1))
    self._smoothIndex = NormalizeIndex(tonumber(self._smoothIndex) or self._focusIndex, math.max(max, 1))

    local container = self:EnsureContainer()
    if max <= 0 then
        self:Hide()
        return
    end

    for index = 1, max do
        local card = self._cards[index] or CreateCard(container)
        self._cards[index] = card
        card.indexText:SetText(string.format("[%d/%d]", index, max))
        card.nameText:SetText(ShortName(players and players[index] or "?"))
        if index == self._myKick then
            SetBackdropBorderColor(card, 1, 0.82, 0, 0.95)
            card.nameText:SetTextColor(1, 0.9, 0.28, 1)
        else
            SetBackdropBorderColor(card, 0, 0, 0, 0.55)
            card.nameText:SetTextColor(0.86, 0.86, 0.86, 1)
        end
        card:Show()
    end

    for index = max + 1, #self._cards do
        self._cards[index]:Hide()
    end

end

function V:Show(trackedUnit, durationSec)
    if (tonumber(self._max) or 0) <= 0 then
        return
    end
    self._trackedUnit = trackedUnit
    self._fallbackStartMS = GetTime() * 1000
    self._fallbackEndMS = self._fallbackStartMS + GetFallbackDurationSec(durationSec) * 1000
    self._visible = true
    self:EnsureContainer():Show()
end

function V:Hide()
    self._visible = false
    if self._container then
        if not (T.EditMode and T.EditMode.IsEditing and T.EditMode:IsEditing(self._container)) then
            self._container:Hide()
        end
    end
    if self._selectorBar then
        self._selectorBar:SetValue(0)
    end
    if self._selectorFill then
        self._selectorFill:SetWidth(1)
    end
    self._trackedUnit = nil
    self._fallbackStartMS = nil
    self._fallbackEndMS = nil
end

function V:IsLocked()
    local container = self._container
    return not (container and T.EditMode and T.EditMode.IsEditing and T.EditMode:IsEditing(container))
end

function V:SetLocked(locked, silent)
    local container = self:EnsureContainer()
    if locked then
        if T.EditMode and T.EditMode.Exit then
            T.EditMode:Exit(container)
        end
        if not self._visible then
            container:Hide()
        end
        if not silent then
            T.msg(L["OPT_IR_POSITION_LOCKED"] or "打断显示位置已锁定")
        end
        return
    end

    if T.EditMode and T.EditMode.Enter then
        T.EditMode:Enter(container)
    end
    if not silent then
        T.msg(L["OPT_IR_POSITION_UNLOCKED"] or "打断显示位置已解锁")
    end
end

function V:ResetPosition()
    WriteDBValue("cardX", nil)
    WriteDBValue("cardY", nil)
    if self._container then
        ApplyPosition(self._container)
    end
    T.msg(L["OPT_IR_POSITION_RESET_DONE"] or "打断显示位置已重置")
end

function V:OnCastChanged(castCount, durationSec)
    if (tonumber(self._max) or 0) <= 0 then
        return
    end
    self._focusIndex = NormalizeIndex(tonumber(castCount) or 1, self._max)
    self._fallbackStartMS = GetTime() * 1000
    self._fallbackEndMS = self._fallbackStartMS + GetFallbackDurationSec(durationSec) * 1000
end

end)
