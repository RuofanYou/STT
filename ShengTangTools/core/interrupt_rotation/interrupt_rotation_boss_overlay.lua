local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("interruptRotation.enabled", function()

local BO = {}
T.InterruptRotationBossOverlay = BO

local BAR_H    = 36
local ICON_W   = 36
local TOTAL_W  = 560
local DEFAULT_Y = -200
local BAR_COLOR_R, BAR_COLOR_G, BAR_COLOR_B = 0.70, 0.22, 0.03

-- 至暗之夜（鲁拉）M 本：boss2/3/4 全部读同一个技能"终结"，时长固定 2 秒。
-- 12.0 把敌对 BOSS 的 UnitCastingInfo/UnitCastingDuration 全字段 secret 化，插件读不到，所以用预设。
-- 图标 fileID 在运行时经 C_Spell.GetSpellTexture(spellID) 反查（spell 元数据 API，非 unit-specific，公开）。
local FINISHER_NAME     = "终结"
local FINISHER_SPELL_ID = 1284934
local FINISHER_DURATION = 2

local function GetSpellIconSafe(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return nil
end

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

local function Clamp(v, lo, hi)
    v = tonumber(v) or 0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function ApplyPosition(frame)
    local db = GetDB()
    frame:ClearAllPoints()
    if db.bossOverlayX ~= nil or db.bossOverlayY ~= nil then
        frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(db.bossOverlayX) or 0, tonumber(db.bossOverlayY) or 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_Y)
    end
end

local function OnUpdate(frame)
    local self = T.InterruptRotationBossOverlay
    if not self or not self._unit then return end

    local startMS = self._fallbackStartMS
    local endMS   = self._fallbackEndMS
    if not startMS or not endMS or endMS <= startMS then return end

    local now = GetTime() * 1000
    -- 预设时长走完后自动隐藏（不依赖 UNIT_SPELLCAST_STOP，
    -- 应对 BOSS 死亡 / encounter end 时 STOP 事件可能不触发的情况）
    if now >= endMS then
        self:Hide()
        return
    end

    local progress  = Clamp((now - startMS) / (endMS - startMS), 0, 1)
    local remainSec = math.max(0, (endMS - now) / 1000)

    frame.castBar:SetValue(progress)
    frame.timerText:SetFormattedText("%.1f", remainSec)
end

local function EnsureFrame()
    if BO._frame then return BO._frame end

    local frame = CreateFrame("Frame", "STT_BossOverlayFrame", UIParent)
    frame:SetSize(TOTAL_W, BAR_H)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local x, y = f:GetCenter()
        local px, py = UIParent:GetCenter()
        if x and y and px and py then
            WriteDBValue("bossOverlayX", math.floor(x - px + 0.5))
            WriteDBValue("bossOverlayY", math.floor(y - py + 0.5))
        end
    end)
    frame:SetScript("OnUpdate", OnUpdate)

    -- 图标背景
    local iconBg = frame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    iconBg:SetVertexColor(0.05, 0.05, 0.05, 1)
    iconBg:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, 0)
    iconBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    iconBg:SetWidth(ICON_W)

    -- 图标纹理
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",    frame, "TOPLEFT",    1, -1)
    icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1,  1)
    icon:SetWidth(ICON_W - 2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon = icon

    -- 进度条背景
    local barBg = frame:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    barBg:SetVertexColor(0, 0, 0, 0.88)
    barBg:SetPoint("TOPLEFT",     frame, "TOPLEFT",     ICON_W + 2, 0)
    barBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,          0)

    -- 进度条
    local castBar = CreateFrame("StatusBar", nil, frame)
    castBar:SetPoint("TOPLEFT",     frame, "TOPLEFT",     ICON_W + 2, 0)
    castBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,          0)
    castBar:SetMinMaxValues(0, 1)
    castBar:SetValue(0)
    castBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    castBar:SetStatusBarColor(BAR_COLOR_R, BAR_COLOR_G, BAR_COLOR_B, 1)
    castBar:SetFrameLevel(frame:GetFrameLevel() + 1)
    frame.castBar = castBar

    -- 技能名（进度条内部，左侧）
    local spellText = castBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellText:SetPoint("LEFT",  castBar, "LEFT",  6,   0)
    spellText:SetPoint("RIGHT", castBar, "RIGHT", -52, 0)
    spellText:SetJustifyH("LEFT")
    spellText:SetTextColor(1, 1, 1, 0.9)
    if spellText.SetWordWrap then spellText:SetWordWrap(false) end
    frame.spellText = spellText

    -- 倒计时（进度条内部，右侧）
    local timerText = castBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerText:SetPoint("RIGHT", castBar, "RIGHT", -6, 0)
    timerText:SetJustifyH("RIGHT")
    timerText:SetTextColor(1, 1, 1, 1)
    frame.timerText = timerText

    ApplyPosition(frame)
    frame:Hide()

    BO._frame = frame
    return frame
end

function BO:Show(unit, durationSec, overrideIcon, overrideName)
    local frame = EnsureFrame()
    self._unit = unit

    -- 鲁拉 boss2/3/4 全部读"终结"，单一预设，不依赖任何 secret API
    local effDur      = tonumber(durationSec) or FINISHER_DURATION
    local displayName = overrideName          or FINISHER_NAME
    local displayIcon = overrideIcon          or GetSpellIconSafe(FINISHER_SPELL_ID)

    self._fallbackStartMS = GetTime() * 1000
    self._fallbackEndMS   = self._fallbackStartMS + math.max(0.5, effDur) * 1000

    frame.castBar:SetValue(0)
    frame.timerText:SetText("")
    frame.spellText:SetText(tostring(displayName))
    if displayIcon then
        frame.icon:SetTexture(displayIcon)
    else
        frame.icon:SetTexture(nil)
    end

    ApplyPosition(frame)
    frame:Show()
end

function BO:Hide()
    self._unit = nil
    if self._frame then
        self._frame:Hide()
        self._frame.castBar:SetValue(0)
    end
end

-- 候选 boss 计算（与 interrupt_rotation_macro.lua 的 BuildConditionText 一致）：
-- kick != 4：仅 boss<group+1>
-- kick == 4：boss<group+1> 倒序到 boss2 全部算候选（应对前序 boss 提前被断完死亡，unit ID 顺延）
local function IsCandidate(unit)
    if not unit then return false end
    local db = GetDB()
    local group = Clamp(db.midnightMacroGroup, 1, 3)
    local kick  = Clamp(db.midnightMacroKick,  1, 4)
    local bossID = group + 1
    if kick ~= 4 then
        return unit == ("boss" .. bossID)
    end
    for id = 2, bossID do
        if unit == ("boss" .. id) then return true end
    end
    return false
end

function BO:OnRawSpellEvent(eventName, unit)
    if not GetDB().bossOverlayEnabled then return end
    if not IsCandidate(unit) then return end

    if eventName == "UNIT_SPELLCAST_START" then
        if self._unit ~= unit then
            self:Show(unit)
        end
    elseif eventName == "UNIT_SPELLCAST_STOP" or eventName == "UNIT_SPELLCAST_INTERRUPTED" then
        if self._unit == unit then
            self:Hide()
        end
    end
end

T.RegisterUnlockCallback(function()
    EnsureFrame()
end)

end)
