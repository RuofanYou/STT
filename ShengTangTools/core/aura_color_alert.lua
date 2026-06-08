-- ═══════════════════════════════════════════════════════════════
-- 贝洛朗光环提醒 (Beloren Aura Alert)
-- Boss: 贝洛朗 (Belo'ren) — 进军奎尔丹纳斯 1 号 Boss — encounterID 3182
--
-- 机制：亡者吐息施放前，玩家身上会出现蓝/黄私有光环，按颜色分组站位。
--
-- 检测：私有光环的 spellID 是 secret value，无法反查；但光环本身出现在
--       C_UnitAuras.GetUnitAuras("player","HARMFUL") 枚举里，且 aura.icon
--       字段可读。靠 icon 让玩家看图识别颜色。
--
-- 生命周期：只在 ENCOUNTER_START(3182) 到 ENCOUNTER_END 之间订阅 UNIT_AURA，
--          避免其他战斗误报，也省性能。
--
-- 位置/大小：设置页解锁后通过 STT 编辑模式拖动；缩放通过设置界面滑块调整。
--           DB.pos / DB.scale 持久化。
--
-- 测试：/st auracolor — 循环切换蓝/黄/关闭（仅 UI 预览）
-- ═══════════════════════════════════════════════════════════════
local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("auraColorAlert.enabled", function()

local DB_KEY = "auraColorAlert"
local BELOREN_ENCOUNTER_ID = 3182
local STTAUDIO_DIR = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\"

local DISPLAY_DURATION = 300
local FADE_OUT_DURATION = 1.5
local FRAME_WIDTH = 260
local FRAME_HEIGHT = 220

local TEST_BLUE_ICON = 135847   -- spell_frost_frostbolt02
local TEST_YELLOW_ICON = 135927 -- spell_holy_surgeoflight

local AURA_COLOR_EVENT_SOUND_MAP = {
    [482] = { triggerType = 0, soundFileName = STTAUDIO_DIR .. "beloren_yellow.ogg" }, -- 圣光羽毛（黄色分组）
    [483] = { triggerType = 0, soundFileName = STTAUDIO_DIR .. "beloren_blue.ogg" }, -- 虚空羽毛（蓝色分组）
}

local DEFAULT_POS = { point = "TOP", relPoint = "TOP", x = 0, y = -100 }
local DEFAULT_SCALE = 1.0
local MIN_SCALE = 0.1
local MAX_SCALE = 2.5

-- ── 模块状态 ─────────────────────────────────────────────────
local AuraColorAlert = T.ModuleLoader:NewModule({
    name = "AuraColorAlert",
    dbKey = DB_KEY .. ".enabled",
    defaultEnabled = false,
})
T.AuraColorAlert = AuraColorAlert

local hideTimer
local mover           -- 可拖动、可缩放的主框体
local content         -- 内部容器（承载 pulseAG，不影响 mover scale）
local icon
local label
local pulseAG
local fadeOutAG
local eventFrame
local inEncounter = false
local unitAuraRegistered = false
local alertActive = false
local editPreviewActive = false
local currentAuraInstanceID = nil
local auraColorEventSoundsRegistered = false

-- ── DB ───────────────────────────────────────────────────────
local function GetDB()
    if not C.DB[DB_KEY] then
        C.DB[DB_KEY] = {}
    end
    local db = C.DB[DB_KEY]
    if db.enabled == nil then db.enabled = false end
    if type(db.pos) ~= "table" then
        db.pos = { point = DEFAULT_POS.point, relPoint = DEFAULT_POS.relPoint, x = DEFAULT_POS.x, y = DEFAULT_POS.y }
    end
    if tonumber(db.scale) == nil then
        db.scale = DEFAULT_SCALE
    end
    if db.pulse == nil then
        db.pulse = true
    end
    if tonumber(db.alpha) == nil then
        db.alpha = 1.0
    end
    if db.showName == nil then
        db.showName = true
    end
    if db.audioEnabled == nil then
        db.audioEnabled = false
    end
    return db
end

local function IsFeatureEnabled()
    return C and C.DB and GetDB().enabled == true
end

local function ClampScale(value)
    local v = tonumber(value) or DEFAULT_SCALE
    if v < MIN_SCALE then v = MIN_SCALE end
    if v > MAX_SCALE then v = MAX_SCALE end
    return v
end

local function ClampAlpha(value)
    local v = tonumber(value) or 1
    if v < 0.2 then v = 0.2 end
    if v > 1 then v = 1 end
    return v
end

-- ── UI ───────────────────────────────────────────────────────
local function ApplyPosition()
    if not mover then return end
    local pos = GetDB().pos
    mover:ClearAllPoints()
    mover:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or -100)
end

local function ApplyScale()
    if not mover then return end
    mover:SetScale(ClampScale(GetDB().scale))
end

local function ApplyAlpha()
    if not content then return end
    content:SetAlpha(ClampAlpha(GetDB().alpha))
end

local function SavePosition()
    if not mover then return end
    local point, _, relPoint, x, y = mover:GetPoint(1)
    local db = GetDB()
    db.pos.point = point or "TOP"
    db.pos.relPoint = relPoint or "TOP"
    db.pos.x = x or 0
    db.pos.y = y or 0
end

local function EnsureAlertUI()
    if mover then
        return mover
    end

    mover = CreateFrame("Frame", "STT_AuraColorAlert", UIParent)
    mover:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    mover:SetFrameStrata("HIGH")
    mover:SetFrameLevel(200)
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    ApplyPosition()
    ApplyScale()
    mover:Hide()

    content = CreateFrame("Frame", nil, mover)
    content:SetAllPoints(mover)

    icon = content:CreateTexture(nil, "ARTWORK")
    icon:SetSize(140, 140)
    icon:SetPoint("CENTER", content, "CENTER", 0, 30)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    label = content:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 32, "OUTLINE,THICKOUTLINE")
    label:SetPoint("TOP", icon, "BOTTOM", 0, -10)
    label:SetShadowOffset(2, -2)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetTextColor(1, 0.92, 0.6, 1)

    ApplyAlpha()

    pulseAG = content:CreateAnimationGroup()
    pulseAG:SetLooping("REPEAT")
    do
        local up = pulseAG:CreateAnimation("Scale")
        up:SetScale(1.1, 1.1)
        up:SetDuration(0.4)
        up:SetOrder(1)
        up:SetSmoothing("IN_OUT")
        local down = pulseAG:CreateAnimation("Scale")
        down:SetScale(1 / 1.1, 1 / 1.1)
        down:SetDuration(0.4)
        down:SetOrder(2)
        down:SetSmoothing("IN_OUT")
    end

    fadeOutAG = mover:CreateAnimationGroup()
    do
        local fade = fadeOutAG:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(FADE_OUT_DURATION)
    end
    fadeOutAG:SetScript("OnFinished", function()
        mover:Hide()
        mover:SetAlpha(1)
        alertActive = false
        currentAuraInstanceID = nil
    end)

    if T.EditMode and T.EditMode.Register then
        T.EditMode:Register({
            frame = mover,
            displayName = L["GUI_NAV_AURA_COLOR"] or "贝洛朗光环提醒",
            saveFunc = function() SavePosition() end,
            group = "solo",
            onExit = function()
                editPreviewActive = false
                if not alertActive then
                    mover:Hide()
                end
            end,
        })
    end

    return mover
end

local function HideAlert()
    if hideTimer then
        hideTimer:Cancel()
        hideTimer = nil
    end
    if pulseAG then pulseAG:Stop() end
    if fadeOutAG and fadeOutAG:IsPlaying() then fadeOutAG:Stop() end
    alertActive = false
    currentAuraInstanceID = nil
    if mover then
        mover:SetAlpha(1)
        if not editPreviewActive then
            mover:Hide()
        end
    end
end

local function ShowAlert(iconFileID, auraName, source)
    if not iconFileID then return end
    EnsureAlertUI()

    if hideTimer then hideTimer:Cancel() end
    if fadeOutAG:IsPlaying() then
        fadeOutAG:Stop()
        mover:SetAlpha(1)
    end

    icon:SetTexture(iconFileID)
    if GetDB().showName ~= false then
        label:SetText(auraName or "")
    else
        label:SetText("")
    end

    alertActive = true
    mover:Show()
    if GetDB().pulse ~= false then
        pulseAG:Play()
    end

    hideTimer = C_Timer.NewTimer(DISPLAY_DURATION, function()
        hideTimer = nil
        pulseAG:Stop()
        fadeOutAG:Play()
    end)
end

-- ── 检测：私有光环只读取可公开枚举到的图标和名称 ───────────────
local function ScanPlayerAuras(reason)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs) then
        return
    end

    local excludeSet = {}
    local ok, selfCastIDs = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, "player", "HARMFUL|PLAYER")
    if ok and type(selfCastIDs) == "table" then
        for _, id in ipairs(selfCastIDs) do
            excludeSet[id] = true
        end
    end

    local ok2, auras = pcall(
        C_UnitAuras.GetUnitAuras,
        "player", "HARMFUL", 10,
        Enum.UnitAuraSortRule.ExpirationOnly,
        Enum.UnitAuraSortDirection.Reverse
    )
    if not ok2 or type(auras) ~= "table" then
        return
    end

    for _, aura in ipairs(auras) do
        local instanceID = aura and aura.auraInstanceID
        if instanceID and not excludeSet[instanceID] and aura.icon then
            if alertActive and currentAuraInstanceID == instanceID then
                return
            end
            currentAuraInstanceID = instanceID
            ShowAlert(aura.icon, aura.name, reason or "unit_aura")
            return
        end
    end
end

-- ── 事件管理 ─────────────────────────────────────────────────
local function RegisterUnitAura()
    if unitAuraRegistered or not eventFrame then return end
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    unitAuraRegistered = true
end

local function UnregisterUnitAura()
    if not unitAuraRegistered or not eventFrame then return end
    eventFrame:UnregisterEvent("UNIT_AURA")
    unitAuraRegistered = false
end

local function UnregisterAuraColorEventSounds()
    if not auraColorEventSoundsRegistered then
        return
    end
    if not (C_EncounterEvents and C_EncounterEvents.SetEventSound) then
        T.debug("[AuraColor] SetEventSound 不可用，无法移除羽毛颜色事件音频")
        return
    end

    for eventID, config in pairs(AURA_COLOR_EVENT_SOUND_MAP) do
        C_EncounterEvents.SetEventSound(eventID, config.triggerType, nil)
        T.debug("[AuraColor] 羽毛颜色事件音频已移除 eventID=" .. tostring(eventID) .. " triggerType=" .. tostring(config.triggerType))
    end
    auraColorEventSoundsRegistered = false
end

local function RegisterAuraColorEventSounds()
    if not (C_EncounterEvents and C_EncounterEvents.SetEventSound) then
        T.debug("[AuraColor] SetEventSound 不可用")
        return
    end

    UnregisterAuraColorEventSounds()

    local count = 0
    for eventID, config in pairs(AURA_COLOR_EVENT_SOUND_MAP) do
        C_EncounterEvents.SetEventSound(eventID, config.triggerType, {
            file = config.soundFileName,
            channel = "Master",
            volume = 1,
        })
        count = count + 1
        T.debug("[AuraColor] 羽毛颜色事件音频已注册 eventID=" .. tostring(eventID) .. " triggerType=" .. tostring(config.triggerType) .. " file=" .. config.soundFileName)
    end
    auraColorEventSoundsRegistered = count > 0
end

local function OnEvent(_, event, ...)
    if event == "ENCOUNTER_START" then
        local encounterID = tonumber((...))
        if encounterID == BELOREN_ENCOUNTER_ID and IsFeatureEnabled() then
            inEncounter = true
            RegisterUnitAura()
            if GetDB().audioEnabled then
                RegisterAuraColorEventSounds()
            end
            T.debug("[AuraColor] ENCOUNTER_START id=" .. tostring(encounterID))
        end
    elseif event == "ENCOUNTER_END" then
        if inEncounter then
            T.debug("[AuraColor] ENCOUNTER_END")
        end
        inEncounter = false
        UnregisterAuraColorEventSounds()
        UnregisterUnitAura()
        HideAlert()
    elseif event == "UNIT_AURA" then
        if not (inEncounter and IsFeatureEnabled()) then
            return
        end
        local unit, updateInfo = ...
        if unit ~= "player" or type(updateInfo) ~= "table" or not updateInfo.addedAuras then
            return
        end
        ScanPlayerAuras("unit_aura_added")
    end
end

local function RecreateEventFrame()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
        unitAuraRegistered = false
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:SetScript("OnEvent", OnEvent)
    return eventFrame
end

-- ── 编辑模式预览 ─────────────────────────────────────────────
local function EnterEditPreview()
    if not IsFeatureEnabled() then return end
    EnsureAlertUI()
    editPreviewActive = true
    if not alertActive then
        icon:SetTexture(TEST_YELLOW_ICON)
        label:SetText(L["AURA_COLOR_PREVIEW_LABEL"] or "预览")
        mover:Show()
    end
end

local function ExitEditPreview()
    editPreviewActive = false
    if mover and not alertActive then
        mover:Hide()
    end
end

-- ── 对外接口 ─────────────────────────────────────────────
function AuraColorAlert:GetMemoryState()
    return {
        overlay = mover ~= nil,
        eventFrame = eventFrame ~= nil,
        inEncounter = inEncounter,
        unitAuraRegistered = unitAuraRegistered,
    }
end

function AuraColorAlert:SetEnabled(enabled)
    GetDB().enabled = enabled == true
    if IsFeatureEnabled() then
        RecreateEventFrame()
        EnsureAlertUI()
    else
        inEncounter = false
        UnregisterUnitAura()
        if mover and T.EditMode and T.EditMode.Exit then
            T.EditMode:Exit(mover)
        end
        ExitEditPreview()
        HideAlert()
    end
    self:RefreshAudio()
end

function AuraColorAlert:RefreshScale()
    ApplyScale()
end

function AuraColorAlert:RefreshAlpha()
    ApplyAlpha()
end

function AuraColorAlert:RefreshAudio()
    if IsFeatureEnabled() and GetDB().audioEnabled then
        if inEncounter then
            RegisterAuraColorEventSounds()
        end
    else
        UnregisterAuraColorEventSounds()
    end
end

function AuraColorAlert:IsLocked()
    return not (mover and T.EditMode and T.EditMode.IsEditing and T.EditMode:IsEditing(mover))
end

function AuraColorAlert:SetLocked(locked)
    if locked then
        if mover and T.EditMode and T.EditMode.Exit then
            T.EditMode:Exit(mover)
        end
        ExitEditPreview()
        T.msg(L["AURA_COLOR_LOCKED"] or "贝洛朗光环提醒位置已锁定")
        return
    end

    EnsureAlertUI()
    EnterEditPreview()
    if T.EditMode and T.EditMode.Enter then
        T.EditMode:Enter(mover)
    end
    T.msg(L["AURA_COLOR_UNLOCKED"] or "贝洛朗光环提醒位置已解锁")
end

function AuraColorAlert:ResetPosition()
    local db = GetDB()
    db.pos.point = DEFAULT_POS.point
    db.pos.relPoint = DEFAULT_POS.relPoint
    db.pos.x = DEFAULT_POS.x
    db.pos.y = DEFAULT_POS.y
    if mover then
        ApplyPosition()
    end
    T.msg(L["AURA_COLOR_RESET_DONE"] or "贝洛朗光环提醒位置已重置")
end

-- /st auracolor 测试：循环蓝→黄→关
local testIndex = 0
T.TestAuraColorAlert = function()
    testIndex = testIndex + 1
    local cycle = testIndex % 3
    if cycle == 1 then
        ShowAlert(TEST_BLUE_ICON, "蓝色光环", "test_blue")
        T.msg("光环颜色测试：|cff3399ff蓝色|r 图标")
    elseif cycle == 2 then
        ShowAlert(TEST_YELLOW_ICON, "黄色光环", "test_yellow")
        T.msg("光环颜色测试：|cffffd91a黄色|r 图标")
    else
        HideAlert()
        T.msg("光环颜色测试：已关闭")
    end
end

function AuraColorAlert:OnRegister()
    T.AuraColorAlert = self
end

function AuraColorAlert:OnEnable()
    RecreateEventFrame()
    AuraColorAlert:RefreshAudio()
end

function AuraColorAlert:OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
    end
    unitAuraRegistered = false
    inEncounter = false
    UnregisterAuraColorEventSounds()
    HideAlert()
end

end)
