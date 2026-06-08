local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("ttsEnabled", function()

local function FormatSeconds(value)
    local number = math.floor(((tonumber(value) or 0) * 10) + 0.5) / 10
    if T.GetActiveLocale and T.GetActiveLocale() == "enUS" then
        return string.format("%.1fs", number)
    end
    return string.format("%.1f秒", number)
end

local function BuildVoiceOptions()
    local voices = {}
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        for _, voice in ipairs(C_VoiceChat.GetTtsVoices() or {}) do
            voices[#voices + 1] = {
                text = voice.name,
                value = voice.voiceID,
            }
        end
    end
    if #voices == 0 then
        voices[1] = {
            textKey = "默认语音",
            value = 0,
        }
    end
    return voices
end

local function RequestVoiceRuntimeReload()
    local runner = T.TimelineRunner
    if not (runner and runner.RequestRuntimeReloadFromCurrent) then
        return
    end
    runner:RequestRuntimeReloadFromCurrent("voice_filter_change")
end

T.RegisterOptionModule({
    id = "voice",
    category = "tactic",
    order = 10,
    titleKey = "GUI_NAV_VOICE",
    masterToggle = {
        dbPath = "ttsEnabled",
        default = false,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_TTS" },
        {
            key = "ttsVoiceID",
            type = "dropdown",
            textKey = "TTS语音选择",
            width = 1,
            dbPath = "ttsVoiceID",
            default = 0,
            options = BuildVoiceOptions,
            tooltipKey = "STT_TT_TTS_VOICE",
        },
        {
            key = "ttsVolume",
            type = "slider",
            textKey = "音量",
            width = 0.5,
            dbPath = "ttsVolume",
            default = 100,
            min = 0,
            max = 100,
            step = 5,
            tooltipKey = "STT_TT_TTS_VOLUME",
        },
        {
            key = "ttsRate",
            type = "slider",
            textKey = "语速",
            width = 0.5,
            dbPath = "ttsRate",
            default = 0,
            min = -10,
            max = 10,
            step = 1,
            tooltipKey = "STT_TT_TTS_RATE",
        },
        {
            key = "printEventsToChat",
            type = "check",
            textKey = "聊天框打印播报文本",
            width = 1,
            dbPath = "printEventsToChat",
            default = false,
            tooltipKey = "STT_TT_TTS_PRINT_CHAT",
        },

        { type = "subtitle", textKey = "GUI_SUBTITLE_CUSTOM_AUDIO" },
        {
            key = "customAudioEnabled",
            type = "check",
            textKey = "GUI_CUSTOM_AUDIO_TOGGLE",
            width = 0.5,
            dbPath = "customAudioEnabled",
            default = true,
            tooltipKey = "STT_TT_CUSTOM_AUDIO_ENABLED",
        },
        {
            key = "customAudioPack",
            type = "dropdown",
            textKey = "GUI_CUSTOM_AUDIO_PACK",
            width = 0.5,
            dbPath = "customAudioPack",
            default = "ShengTangTools",
            options = function()
                if T.CustomAudio and T.CustomAudio.GetPacks then
                    return T.CustomAudio.GetPacks()
                end
                return { { text = "STT默认语音包", value = "ShengTangTools" } }
            end,
        },

        { type = "subtitle", textKey = "GUI_SUBTITLE_RANGE" },
        {
            key = "onlyInRaid",
            type = "check",
            textKey = "仅在团队副本播报",
            width = 0.5,
            dbPath = "onlyInRaid",
            default = true,
        },
        {
            key = "ttsAdvanceTime",
            type = "slider",
            textKey = "提前播报时间",
            width = 1,
            dbPath = "ttsAdvanceTime",
            default = 0,
            min = 0,
            max = 10,
            step = 0.1,
            formatFunc = FormatSeconds,
            tooltipKey = "STT_TT_TTS_ADVANCE",
        },

        { type = "subtitle", textKey = "GUI_SUBTITLE_FILTERS" },
        {
            key = "filterClass",
            type = "check",
            textKey = "播报职业",
            width = 0.5,
            dbPath = "filterClass",
            default = true,
            apply = RequestVoiceRuntimeReload,
        },
        {
            key = "filterRole",
            type = "check",
            textKey = "播报职责",
            width = 0.5,
            dbPath = "filterRole",
            default = true,
            apply = RequestVoiceRuntimeReload,
        },
        {
            key = "filterPos",
            type = "check",
            textKey = "播报站位",
            width = 0.5,
            dbPath = "filterPos",
            default = true,
            apply = RequestVoiceRuntimeReload,
        },
        {
            key = "filterAll",
            type = "check",
            textKey = "GUI_FILTER_ALL_TARGETS",
            width = 0.5,
            dbPath = "filterAll",
            default = true,
            clickLabel = true,
            apply = RequestVoiceRuntimeReload,
        },
        {
            key = "filterParty",
            type = "check",
            textKey = "播报小队",
            width = 0.5,
            dbPath = "filterParty",
            default = true,
            apply = RequestVoiceRuntimeReload,
        },

        { type = "subtitle", textKey = "GUI_SUBTITLE_PERSONAL" },
        {
            key = "mynickname",
            type = "button",
            textKey = "设置昵称",
            width = 0.5,
            dbPath = "mynickname",
            displayFunc = function(value)
                if value and value ~= "" then
                    return string.format("%s: %s", L["我的昵称"] or "我的昵称", value)
                end
                return string.format("%s: %s", L["我的昵称"] or "我的昵称", L["未设置"] or "未设置")
            end,
            onClick = function()
                StaticPopup_Show((T.addon_name or "STT") .. "_NicknameInput")
            end,
        },
        }
    end,
})

end)
