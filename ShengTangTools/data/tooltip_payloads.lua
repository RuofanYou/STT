local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

T.TooltipPayloads = T.TooltipPayloads or {}

local Payloads = T.TooltipPayloads
Payloads.registry = Payloads.registry or {}

T.Assets:Define("TooltipPayloadRegistry", {
    factory = function()
        return {
    STT_TT_COUNTDOWN_CHANNEL = {
        titleKey = "TT_COUNTDOWN_CHANNEL_TITLE",
        summaryKey = "TT_COUNTDOWN_CHANNEL_SUMMARY",
        concepts = { "ct", "countdown-audio", "time" },
    },
    STT_TT_COUNTDOWN_PACK = {
        titleKey = "TT_COUNTDOWN_PACK_TITLE",
        summaryKey = "TT_COUNTDOWN_PACK_SUMMARY",
        concepts = { "ct", "countdown-audio", "voice-pack" },
    },
    STT_TT_COUNTDOWN_PREVIEW = {
        titleKey = "TT_COUNTDOWN_PREVIEW_TITLE",
        summaryKey = "TT_COUNTDOWN_PREVIEW_SUMMARY",
        concepts = { "ct" },
    },
    STT_TT_TTS_VOICE = {
        titleKey = "TT_TTS_VOICE_TITLE",
        summaryKey = "TT_TTS_VOICE_SUMMARY",
        concepts = { "time", "spell" },
    },
    STT_TT_TTS_VOLUME = {
        titleKey = "TT_TTS_VOLUME_TITLE",
        summaryKey = "TT_TTS_VOLUME_SUMMARY",
        concepts = { "ct" },
    },
    STT_TT_TTS_RATE = {
        titleKey = "TT_TTS_RATE_TITLE",
        summaryKey = "TT_TTS_RATE_SUMMARY",
        concepts = { "time" },
    },
    STT_TT_TTS_PRINT_CHAT = {
        titleKey = "TT_TTS_PRINT_CHAT_TITLE",
        summaryKey = "TT_TTS_PRINT_CHAT_SUMMARY",
        concepts = { "audience", "spell", "time" },
    },
    STT_TT_CUSTOM_AUDIO_ENABLED = {
        titleKey = "TT_CUSTOM_AUDIO_ENABLED_TITLE",
        summaryKey = "TT_CUSTOM_AUDIO_ENABLED_SUMMARY",
        concepts = { "time", "format-comparison", "voice-pack", "inline-sfx" },
    },
    STT_TT_BAR_WIDTH = {
        titleKey = "TT_BAR_WIDTH_TITLE",
        summaryKey = "TT_BAR_WIDTH_SUMMARY",
        concepts = { "duration-bar", "bar-advanced", "time" },
    },
    ["战斗外常驻显示_TOOLTIP"] = {
        title = "战斗外常驻显示",
        summary = "战斗外预览当前方案。",
        concepts = { "realtime-board", "realtime-preview-ooc", "timeline-panel", "time" },
    },
    DREAD_ELEGY_ROUTE_MODE_TIP = {
        title = "符文分配模式",
        summary = "选择符文路径分配方式。",
        concepts = { "lura-rune", "lura-rune-channel", "scheme-team", "leader-only" },
    },
    DREAD_ELEGY_ANNOUNCE_ONSHOW_TIP = {
        title = "符文编号播报",
        summary = "显示符文时提示编号。",
        concepts = { "lura-rune", "screen-alert" },
    },
    OPT_IR_BANNER_OTHERS_TIP = {
        title = "其他人横幅",
        summary = "显示非自己的打断提示。",
        concepts = { "interrupt-rotation", "interrupt-block", "interrupt-style", "personnel-mapping", "scheme-team" },
    },
    OPT_IR_BOSS_OVERLAY_TIP = {
        title = "Boss 读条覆盖",
        summary = "显示打断读条辅助层。",
        concepts = { "interrupt-rotation", "screen-alert", "spell" },
    },
    STT_TT_TTS_ADVANCE = {
        title = "提前播报时间",
        summary = "设置语音提前秒数。",
        concepts = { "time", "time-no-advance", "trigger-advance", "trigger-precise-zero" },
    },
        }
    end,
})

local function EnsureDefaults()
    if Payloads.defaultsLoaded == true then
        return
    end
    Payloads.defaultsLoaded = true
    local registry = T.Assets:Get("TooltipPayloadRegistry", "TooltipPayloads") or {}

    for key, payload in pairs(registry) do
        Payloads.registry[key] = payload
    end
end

function Payloads.Register(key, payload)
    if type(key) ~= "string" or key == "" or type(payload) ~= "table" then
        return
    end
    Payloads.registry[key] = payload
end

function Payloads.Get(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    EnsureDefaults()
    return Payloads.registry[key]
end

function Payloads.Resolve(key)
    local payload = Payloads.Get(key)
    if type(payload) == "function" then
        return payload()
    end
    return payload
end

end)
