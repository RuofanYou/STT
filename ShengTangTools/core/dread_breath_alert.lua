-- ═══════════════════════════════════════════════════════════════
-- 亡者吐息 (Dread Breath) 点名超大屏幕警告
-- Boss: 威厄高尔 (Vaelgor) — 虚灵尖塔 · 双龙
--
-- 展示层仅保留测试/辅助用途；正式实战的稳定提示改以暴雪 private warning 为准。
-- 这里仍保留超大红色箭头 + "吐息点你！" 文字 + 红色屏幕闪烁，
-- 便于 /st breath 手测，或在其它模块已经明确解析到玩家中点时做辅助提示。
--
-- 测试: /st breath
-- ═══════════════════════════════════════════════════════════════
local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local overlay
local pulseAG
local flashAG
local rotateAG

local function EnsureAlertUI()
    if overlay then
        return overlay
    end

    overlay = CreateFrame("Frame", "STT_DreadBreathAlert", UIParent)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetFixedFrameStrata(true)
    overlay:SetFrameLevel(500)
    overlay:SetAllPoints()
    overlay:Hide()

    local screenFlash = overlay:CreateTexture(nil, "BACKGROUND")
    screenFlash:SetAllPoints()
    screenFlash:SetColorTexture(0.7, 0, 0, 0.18)

    local center = CreateFrame("Frame", nil, overlay)
    center:SetSize(500, 420)
    center:SetPoint("CENTER", 0, 40)

    local glowBg = center:CreateTexture(nil, "BACKGROUND")
    glowBg:SetSize(320, 320)
    glowBg:SetPoint("CENTER", center, "CENTER", 0, 30)
    glowBg:SetColorTexture(1, 0.05, 0.05, 0.25)
    glowBg:SetBlendMode("ADD")

    local arrow = center:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(220, 220)
    arrow:SetPoint("CENTER", center, "CENTER", 0, 40)
    arrow:SetAtlas("common-icon-forwardarrow")
    arrow:SetRotation(-math.pi / 2)
    arrow:SetVertexColor(1.0, 0.12, 0.08, 1.0)

    local label = center:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 72, "OUTLINE,THICKOUTLINE")
    label:SetPoint("TOP", arrow, "BOTTOM", 0, 30)
    label:SetTextColor(1, 0.15, 0.15, 1)
    label:SetText("吐息点你！")
    label:SetShadowOffset(3, -3)
    label:SetShadowColor(0, 0, 0, 1)

    pulseAG = center:CreateAnimationGroup()
    pulseAG:SetLooping("REPEAT")
    do
        local up = pulseAG:CreateAnimation("Scale")
        up:SetScale(1.14, 1.14)
        up:SetDuration(0.3)
        up:SetOrder(1)
        up:SetSmoothing("IN_OUT")
        local down = pulseAG:CreateAnimation("Scale")
        down:SetScale(1 / 1.14, 1 / 1.14)
        down:SetDuration(0.3)
        down:SetOrder(2)
        down:SetSmoothing("IN_OUT")
    end

    flashAG = screenFlash:CreateAnimationGroup()
    flashAG:SetLooping("REPEAT")
    do
        local a = flashAG:CreateAnimation("Alpha")
        a:SetFromAlpha(0.12)
        a:SetToAlpha(0.35)
        a:SetDuration(0.4)
        a:SetOrder(1)
        local b = flashAG:CreateAnimation("Alpha")
        b:SetFromAlpha(0.35)
        b:SetToAlpha(0.12)
        b:SetDuration(0.4)
        b:SetOrder(2)
    end

    rotateAG = arrow:CreateAnimationGroup()
    rotateAG:SetLooping("REPEAT")
    do
        local r1 = rotateAG:CreateAnimation("Rotation")
        r1:SetDegrees(6)
        r1:SetDuration(0.15)
        r1:SetOrder(1)
        r1:SetSmoothing("IN_OUT")
        local r2 = rotateAG:CreateAnimation("Rotation")
        r2:SetDegrees(-12)
        r2:SetDuration(0.3)
        r2:SetOrder(2)
        r2:SetSmoothing("IN_OUT")
        local r3 = rotateAG:CreateAnimation("Rotation")
        r3:SetDegrees(6)
        r3:SetDuration(0.15)
        r3:SetOrder(3)
        r3:SetSmoothing("IN_OUT")
    end

    return overlay
end

-- ── 显示 / 隐藏 ─────────────────────────────────────────
local trackedActive = false
local testActive = false
local overlayActive = false

local function StopAnimations()
    if pulseAG then
        pulseAG:Stop()
    end
    if flashAG then
        flashAG:Stop()
    end
    if rotateAG then
        rotateAG:Stop()
    end
end

local function HideAlert(reason)
    if not overlayActive then return end
    overlayActive = false
    StopAnimations()
    if overlay then
        overlay:Hide()
    end
    T.debug("[DreadBreath] DreadBreathAlertState active=false reason=" .. tostring(reason or "cleared"))
end

local function ShowAlert(source)
    if overlayActive then return end
    EnsureAlertUI()
    overlayActive = true
    overlay:Show()
    pulseAG:Play()
    flashAG:Play()
    rotateAG:Play()
    pcall(PlaySound, 8959, "Master")
    T.debug("[DreadBreath] DreadBreathAlertState active=true source=" .. tostring(source or "unknown"))
end

local function RefreshAlertVisibility(source, reason)
    if trackedActive or testActive then
        ShowAlert(source)
    else
        HideAlert(reason)
    end
end

local DreadBreathAlert = T.DreadBreathAlert or {}

function DreadBreathAlert:GetMemoryState()
    return {
        overlay = overlay ~= nil,
    }
end

function DreadBreathAlert.SetActive(active, source)
    trackedActive = active == true
    RefreshAlertVisibility(active and source or nil, active and nil or (source or "cleared"))
end

function DreadBreathAlert.IsActive()
    return overlayActive
end

T.DreadBreathAlert = DreadBreathAlert

-- ── 对外接口 ─────────────────────────────────────────────
-- /st breath 测试用
T.TestDreadBreathAlert = function()
    testActive = not testActive
    RefreshAlertVisibility(testActive and "test" or nil, testActive and nil or "test_off")
    if testActive then
        T.msg("亡者吐息警告：测试已开启，再次输入 /st breath 关闭")
    else
        T.msg("亡者吐息警告：已关闭测试")
    end
end

end)
