-- core/tactical_notice.lua
--
-- V2 后这里只保留 3 个对外入口，其余 V1 渲染主链（banner/text/icon/bar 全局开关 + 4 个 EditMode anchor frame）已删除。
--
-- 对外保留：
--   * TacticalNotice:ShowReminder(data) - 薄 wrapper，转发到 ScreenReminder:Show
--   * TacticalNotice:ShowBanner(data)   - 屏幕顶部大字横幅，独立 standalone frame（不进 EditMode）
--   * TacticalNotice:ShowPullBlame(text, color) - 早开怪点名（转发 ShowBanner）
--
-- ShowBanner / ShowPullBlame 是早开怪 / 团队笔记 `!!` 专用大字警告，不归屏幕提醒指示器模型管。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({ { "semanticTimeline.runtimeEnabled", true }, "semanticTimeline.editorLoaded", "screenReminder.enabled", "earlyPull.enabled", "dreadElegy.enabled", "interruptRotation.enabled" }, function()

local TacticalNotice = {}
T.TacticalNotice = TacticalNotice

local BANNER_DEFAULT_DURATION = 2.5
local BANNER_FADE_IN = 0.15
local BANNER_FADE_OUT = 0.5
local BANNER_COOLDOWN = 0.8
local BANNER_FONT_SIZE = 42
local BANNER_POSITION = { point = "CENTER", x = 0, y = 120 }
local BANNER_FRAME_STRATA = "FULLSCREEN_DIALOG"
local BANNER_FRAME_LEVEL = 1000

local BANNER_SEVERITY_COLORS = {
    critical = { 1.0, 0.25, 0.25, 1 },
    warning  = { 1.0, 0.82, 0.25, 1 },
    info     = { 0.95, 0.95, 0.95, 1 },
}
local PULL_BLAME_COLORS = {
    red    = { 1.0, 0.25, 0.25, 1 },
    yellow = { 1.0, 0.82, 0.25, 1 },
}

local function ResolveBannerColor(severity, override)
    if type(override) == "table" then
        return override
    end
    return BANNER_SEVERITY_COLORS[severity] or BANNER_SEVERITY_COLORS.critical
end

local function ExtractSeverityPrefix(text)
    if type(text) ~= "string" then return nil, text end
    local normalize = T.TimelineSyntax and T.TimelineSyntax.NormalizeASCIIWhitespace
    local normalized = normalize and normalize(text) or text
    if normalized:sub(1, 2) == "!!" then
        local stripped = normalized:sub(3):match("^%s*(.-)%s*$") or ""
        return "critical", stripped
    end
    return nil, text
end

-- ──────────────────────────────────────────────────────────────────────
-- Banner standalone frame（独立于 EditMode 与 V2 indicator 系统）
-- ──────────────────────────────────────────────────────────────────────
local bannerFrame
local bannerState = {}

local function EnsureBannerFrame()
    if bannerFrame then
        bannerFrame:SetFrameStrata(BANNER_FRAME_STRATA)
        bannerFrame:SetFrameLevel(BANNER_FRAME_LEVEL)
        if bannerFrame.SetToplevel then
            bannerFrame:SetToplevel(true)
        end
        return bannerFrame
    end
    bannerFrame = CreateFrame("Frame", "STT_TacticalBanner", UIParent)
    bannerFrame:SetSize(860, 80)
    bannerFrame:SetPoint(BANNER_POSITION.point, UIParent, BANNER_POSITION.point, BANNER_POSITION.x, BANNER_POSITION.y)
    bannerFrame:SetFrameStrata(BANNER_FRAME_STRATA)
    bannerFrame:SetFrameLevel(BANNER_FRAME_LEVEL)
    bannerFrame:SetToplevel(true)
    bannerFrame:Hide()

    local text = bannerFrame:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, BANNER_FONT_SIZE, "OUTLINE,THICKOUTLINE")
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    text:SetShadowOffset(2, -2)
    text:SetShadowColor(0, 0, 0, 1)
    bannerFrame.text = text

    bannerFrame:SetScript("OnHide", function(self)
        self:SetAlpha(1)
        self:SetScript("OnUpdate", nil)
        bannerState.active = false
    end)
    return bannerFrame
end

function TacticalNotice:ShowBanner(data)
    if type(data) ~= "table" then return false end
    local severity, text = ExtractSeverityPrefix(data.text)
    if type(text) ~= "string" or text == "" then return false end

    local now = GetTime()
    if data.bypassCooldown ~= true and (now - (bannerState.lastAt or 0)) < BANNER_COOLDOWN then
        return false
    end

    local frame = EnsureBannerFrame()
    local color = ResolveBannerColor(data.severity or severity, data.color)
    local total = math.max(BANNER_FADE_IN + BANNER_FADE_OUT + 0.1,
        tonumber(data.duration) or BANNER_DEFAULT_DURATION)
    local hold = math.max(0, total - BANNER_FADE_IN - BANNER_FADE_OUT)

    frame.text:SetText(text)
    frame.text:SetTextColor(color[1] or 1, color[2] or 0.25, color[3] or 0.25, color[4] or 1)
    frame:SetAlpha(0)
    frame:Show()

    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < BANNER_FADE_IN then
            self:SetAlpha(elapsed / BANNER_FADE_IN)
        elseif elapsed < BANNER_FADE_IN + hold then
            self:SetAlpha(1)
        elseif elapsed < total then
            self:SetAlpha(1 - (elapsed - BANNER_FADE_IN - hold) / BANNER_FADE_OUT)
        else
            self:Hide()
        end
    end)

    bannerState.lastAt = now
    bannerState.active = true
    return true
end

function TacticalNotice:ShowPullBlame(text, color)
    local rgba = type(color) == "table" and color or PULL_BLAME_COLORS[color or "red"] or PULL_BLAME_COLORS.red
    return self:ShowBanner({
        text = text,
        duration = 3.15,
        color = rgba,
        bypassCooldown = true,
    })
end

-- ──────────────────────────────────────────────────────────────────────
-- ShowReminder: 时间轴 / 外部模块（interrupt_alert / semantic_timeline 等）
-- 仍通过此入口投递屏幕提醒，统一转发到 V2 ScreenReminder。
-- ──────────────────────────────────────────────────────────────────────
function TacticalNotice:ShowReminder(data)
    if type(data) ~= "table" then return false end
    if T.ScreenReminder and T.ScreenReminder.Show then
        T.ScreenReminder:Show(data)
        return true
    end
    return false
end

-- 兼容 timeline_runner / core 内残留调用，转发到 V2 ClearAll
function TacticalNotice:ClearAll()
    if T.ScreenReminder and T.ScreenReminder.ClearAll then
        T.ScreenReminder:ClearAll()
    end
    if bannerFrame then bannerFrame:Hide() end
end

end)
