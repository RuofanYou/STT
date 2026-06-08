local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("interruptRotation.enabled", function()

local Banner = {}
T.InterruptRotationBanner = Banner

local AUDIO_BASE_PATH = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\"
local DEFAULT_SOUND_FILE = "interrupt.ogg"
local DEFAULT_DURATION = 2
local MIN_DURATION = 1
local MAX_DURATION = 12
local DEFAULT_BANNER_SCALE = 3.0
local MIN_BANNER_SCALE = 1.0
local MAX_BANNER_SCALE = 5.0
local TEXT_BANNER_FONT_SIZE = 32
local TEXT_BANNER_WIDTH = 520
local TEXT_BANNER_POSITION = { point = "CENTER", relPoint = "CENTER", x = 0, y = 80 }
local TEXT_BANNER_COLOR = { 0xFA / 255, 0xDE / 255, 0x85 / 255, 1 }
local TEXT_BANNER_COUNTDOWN = {
    enabled = true,
    decimals = 1,
    unit = "s",
    wrap = "none",
    colorByTime = true,
    critical = { threshold = 3.0, color = "FF5555" },
    warning = { threshold = 5.0, color = "FFCC55" },
    normal = { color = "50FF50" },
}

local textBannerFrame
local textBannerToken = 0
local textBannerActive = false
local textBannerEditPreview = false

local function Debug(fmt, ...)
    if C and C.DB and C.DB.debugMode == true and T.debug then
        T.debug(string.format("[IR] " .. fmt, ...))
    end
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

local function ShortName(name)
    local text = tostring(name or "")
    if Ambiguate then
        text = Ambiguate(text, "short") or text
    end
    return text:gsub("%-.+$", "")
end

local function GetBannerDuration(db)
    local duration = tonumber(db and db.bannerDurationSec) or DEFAULT_DURATION
    return math.min(MAX_DURATION, math.max(MIN_DURATION, duration))
end

local function GetBannerScale(db)
    local scale = tonumber(db and db.bannerScale) or DEFAULT_BANNER_SCALE
    return math.min(MAX_BANNER_SCALE, math.max(MIN_BANNER_SCALE, scale))
end

local function ApplyTextBannerPosition(frame)
    if not frame then return end
    local pos = GetDB().bannerPos
    if type(pos) ~= "table" then
        pos = TEXT_BANNER_POSITION
    end
    frame:ClearAllPoints()
    frame:SetPoint(
        pos.point or TEXT_BANNER_POSITION.point,
        UIParent,
        pos.relPoint or TEXT_BANNER_POSITION.relPoint,
        tonumber(pos.x) or TEXT_BANNER_POSITION.x,
        tonumber(pos.y) or TEXT_BANNER_POSITION.y
    )
end

local function SaveTextBannerPosition(frame)
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    WriteDBValue("bannerPos", {
        point = point or TEXT_BANNER_POSITION.point,
        relPoint = relPoint or TEXT_BANNER_POSITION.relPoint,
        x = x or TEXT_BANNER_POSITION.x,
        y = y or TEXT_BANNER_POSITION.y,
    })
end

local function GetSoundFile(db)
    local text = strtrim(tostring(db and db.soundFile or ""))
    if text == "" then
        text = DEFAULT_SOUND_FILE
    end
    text = text:gsub("/", "\\")

    local lower = text:lower()
    local baseLower = AUDIO_BASE_PATH:lower()
    if lower:sub(1, #baseLower) == baseLower then
        text = text:sub(#AUDIO_BASE_PATH + 1)
        lower = text:lower()
    end

    local relativePrefix = "media\\sttaudio\\"
    if lower:sub(1, #relativePrefix) == relativePrefix then
        text = text:sub(#relativePrefix + 1)
    end

    if text:find(":", 1, true) or text:find("..", 1, true) or text:sub(1, 1) == "\\" then
        text = DEFAULT_SOUND_FILE
    end
    return AUDIO_BASE_PATH .. text
end

local function EnsureTextBannerFrame()
    if textBannerFrame then
        return textBannerFrame
    end

    local frame = CreateFrame("Frame", "STT_InterruptRotationTextBanner", UIParent)
    frame:SetSize(TEXT_BANNER_WIDTH, TEXT_BANNER_FONT_SIZE + 12)
    ApplyTextBannerPosition(frame)
    frame:SetFrameStrata("HIGH")
    frame:SetScale(GetBannerScale(GetDB()))
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER")
    text:SetWordWrap(false)
    text:SetJustifyH("CENTER")
    text:SetFont(STANDARD_TEXT_FONT, TEXT_BANNER_FONT_SIZE, "OUTLINE")
    text:SetTextColor(TEXT_BANNER_COLOR[1], TEXT_BANNER_COLOR[2], TEXT_BANNER_COLOR[3], TEXT_BANNER_COLOR[4])
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.8)
    frame.text = text

    local countdown = frame:CreateFontString(nil, "OVERLAY")
    countdown:SetPoint("RIGHT", text, "LEFT", -6, 0)
    countdown:SetFont(STANDARD_TEXT_FONT, TEXT_BANNER_FONT_SIZE, "OUTLINE")
    countdown:SetShadowOffset(1, -1)
    countdown:SetShadowColor(0, 0, 0, 0.8)
    frame.countdown = countdown

    frame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        textBannerActive = false
        if self.countdown then
            self.countdown:SetText("")
            self.countdown.__lastText = nil
            self.countdown.__lastColor = nil
        end
    end)

    textBannerFrame = frame
    if T.EditMode and T.EditMode.Register then
        T.EditMode:Register({
            frame = frame,
            displayName = L["OPT_IR_BANNER_POSITION_TITLE"] or "打断横幅",
            saveFunc = function() SaveTextBannerPosition(frame) end,
            group = "solo",
            onExit = function()
                textBannerEditPreview = false
                if not textBannerActive then
                    frame:Hide()
                end
            end,
        })
    end
    return frame
end

local function ShowTextBannerPreview(frame)
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    frame:SetAlpha(1)
    frame:SetScale(GetBannerScale(GetDB()))
    frame.text:SetText(L["OPT_IR_POSITION_PREVIEW"] or "打断位置预览")
    frame.countdown:SetText("")
    frame:Show()
end

local function UpdateTextBannerCountdown(frame, remaining)
    if T.ScreenReminderCountdown and T.ScreenReminderCountdown.ApplyToFontString then
        T.ScreenReminderCountdown.ApplyToFontString(frame.countdown, remaining, TEXT_BANNER_COUNTDOWN)
        return
    end
    frame.countdown:SetText(string.format("%.1fs", math.max(0, remaining or 0)))
    frame.countdown:SetTextColor(1, 0.8, 0.33, 1)
end

local function ShowTextBanner(text, duration)
    if type(text) ~= "string" or text == "" then
        return false
    end

    local frame = EnsureTextBannerFrame()
    textBannerToken = textBannerToken + 1
    local token = textBannerToken

    local total = math.max(0.05, tonumber(duration) or DEFAULT_DURATION)
    local endTime = GetTime() + total

    frame:SetAlpha(1)
    frame:SetScale(GetBannerScale(GetDB()))
    ApplyTextBannerPosition(frame)
    frame._countdownAccum = 0
    frame.text:SetText(text)
    UpdateTextBannerCountdown(frame, total)
    textBannerActive = true
    frame:Show()

    frame:SetScript("OnUpdate", function(self, dt)
        if token ~= textBannerToken then
            return
        end
        self._countdownAccum = (self._countdownAccum or 0) + (dt or 0)
        if self._countdownAccum < 0.05 then
            return
        end
        self._countdownAccum = 0

        local remaining = endTime - GetTime()
        if remaining <= 0 then
            textBannerActive = false
            if textBannerEditPreview then
                ShowTextBannerPreview(self)
            else
                self:Hide()
            end
            return
        end
        UpdateTextBannerCountdown(self, remaining)
    end)
    return true
end

local function BuildPayload(interrupts, isCastStart)
    local db = GetDB()
    local duration = GetBannerDuration(db)
    local castCount = tonumber(interrupts and interrupts.castCount) or 1
    local max = tonumber(interrupts and interrupts.max) or 0
    local myKick = tonumber(interrupts and interrupts.myKick) or 0
    local myTable = interrupts and interrupts.myTable or {}
    local name = ShortName(myTable[castCount] or "")
    local isSelf = castCount == myKick
    local isNext = (castCount + 1 == myKick) or (myKick == 1 and max > 0 and castCount == max)

    if isSelf and isCastStart then
        if db.bannerSelf == false then
            return nil
        end
        return {
            prefix = L["OPT_IR_BANNER_SELF"] or "你打断：",
            severity = "critical",
            duration = duration,
            selfCue = true,
            name = name,
            castCount = castCount,
            max = max,
        }
    elseif isSelf or isNext then
        if db.bannerNext == false then
            return nil
        end
        return {
            prefix = L["OPT_IR_BANNER_NEXT"] or "准备打断：",
            severity = "warning",
            duration = duration,
            prepareCue = isNext,
            name = name,
            castCount = castCount,
            max = max,
        }
    end

    if db.bannerOthers ~= true then
        return nil
    end
    return {
        prefix = L["OPT_IR_BANNER_OTHERS_PREFIX"] or "他人打断：",
        severity = "info",
        duration = duration,
        name = name,
        castCount = castCount,
        max = max,
    }
end

function Banner:Show(interrupts, isCastStart, options)
    if T.GetInterruptRotationUIStyle and T.GetInterruptRotationUIStyle() ~= "banner" then
        return false
    end
    local payload = BuildPayload(interrupts, isCastStart == true)
    if not payload then
        return false
    end

    local text = string.format("%s [%d/%d] %s", payload.prefix, payload.castCount, payload.max, payload.name)
    local ok, shown = pcall(ShowTextBanner, text, payload.duration)
    if not ok then
        Debug("banner failed err=%s", tostring(shown))
    end

    if payload.selfCue then
        self:PlaySelfSound()
    elseif payload.prepareCue and not (options and options.suppressPrepareCue) then
        self:PlayPrepareTTS()
    end
    return true
end

function Banner:RefreshScale()
    if textBannerFrame then
        textBannerFrame:SetScale(GetBannerScale(GetDB()))
    end
end

function Banner:IsLocked()
    return not (textBannerFrame and T.EditMode and T.EditMode.IsEditing and T.EditMode:IsEditing(textBannerFrame))
end

function Banner:SetLocked(locked, silent)
    local frame = EnsureTextBannerFrame()
    if locked then
        if T.EditMode and T.EditMode.Exit then
            T.EditMode:Exit(frame)
        end
        textBannerEditPreview = false
        if not textBannerActive then
            frame:Hide()
        end
        if not silent then
            T.msg(L["OPT_IR_POSITION_LOCKED"] or "打断显示位置已锁定")
        end
        return
    end

    textBannerEditPreview = true
    if not textBannerActive then
        ShowTextBannerPreview(frame)
    end
    if T.EditMode and T.EditMode.Enter then
        T.EditMode:Enter(frame)
    end
    if not silent then
        T.msg(L["OPT_IR_POSITION_UNLOCKED"] or "打断显示位置已解锁")
    end
end

function Banner:ResetPosition()
    WriteDBValue("bannerPos", nil)
    if textBannerFrame then
        ApplyTextBannerPosition(textBannerFrame)
    end
    T.msg(L["OPT_IR_POSITION_RESET_DONE"] or "打断显示位置已重置")
end

function Banner:PlayPrepareTTS()
    local db = GetDB()
    if db.ttsOnPrepare ~= false and T.PlayTTS then
        local ok, err = pcall(T.PlayTTS, L["OPT_IR_TTS_TEXT"] or "准备")
        if not ok then
            Debug("tts failed err=%s", tostring(err))
        end
    end
end

function Banner:PlaySelfSound()
    local db = GetDB()
    if db.soundOnSelf == true and PlaySoundFile then
        local soundFile = GetSoundFile(db)
        local ok, willPlay = pcall(PlaySoundFile, soundFile, "Master")
        if not ok then
            Debug("sound failed err=%s", tostring(willPlay))
        elseif willPlay == false then
            Debug("sound skipped file=%s", soundFile)
        end
    end
end

end)
