local select, unpack = select, unpack
local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()
local C_Timer, C_VoiceChat = C_Timer, C_VoiceChat
local PlaySoundFile, StopSound = PlaySoundFile, StopSound
local ipairs, table, type = ipairs, table, type
local tostring = tostring

-- 统一播报队列：自定义配音与 TTS 共享同一条有序队列，杜绝同帧冲突。
-- 队列条目：
--   字符串        → TTS 播报
--   {audio=path, label=name} → 自定义配音（PlaySoundFile）

local Speaker = {}
T.Speaker = Speaker

local queue = {}
local isPlaying = false
local activeSoundHandle = nil -- 当前自定义配音的 sound handle
local currentTTSUtteranceID = nil
local waitingForTTSStart = false
local ttsGeneration = 0

local AUDIO_DELAY = 1.5 -- 配音播完后等待秒数，再播下一条
local TTS_START_TIMEOUT = 3 -- 没收到开始事件时释放队列，避免卡死
local ProcessQueue

local function NormalizeText(text)
    local cleaned = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return T.TimelineSyntax.NormalizeASCIIWhitespace(cleaned)
end

-- 停止当前正在播放的自定义配音
local function StopCustomAudio()
    if activeSoundHandle then
        StopSound(activeSoundHandle)
        activeSoundHandle = nil
    end
end

local function FinishCurrentTTS()
    waitingForTTSStart = false
    currentTTSUtteranceID = nil
    isPlaying = false
    ProcessQueue()
end

local ttsEventFrame = CreateFrame("Frame")
ttsEventFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED")
ttsEventFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED")
ttsEventFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED")
ttsEventFrame:SetScript("OnEvent", function(_, event, _, utteranceID)
    if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
        if waitingForTTSStart and currentTTSUtteranceID == nil and utteranceID ~= nil then
            waitingForTTSStart = false
            currentTTSUtteranceID = utteranceID
        end
        return
    end

    if currentTTSUtteranceID ~= nil and utteranceID == currentTTSUtteranceID then
        FinishCurrentTTS()
    elseif waitingForTTSStart then
        FinishCurrentTTS()
    end
end)

ProcessQueue = function()
    if #queue == 0 then
        isPlaying = false
        waitingForTTSStart = false
        currentTTSUtteranceID = nil
        return
    end

    local entry = table.remove(queue, 1)

    -- ━━━ 配音候选探测条目（由 T.PlayTTS 生成） ━━━
    if type(entry) == "table" and entry.audioCandidates then
        isPlaying = true
        waitingForTTSStart = false
        currentTTSUtteranceID = nil
        StopCustomAudio()
        if C_VoiceChat and C_VoiceChat.StopSpeakingText then
            C_VoiceChat.StopSpeakingText()
        end

        -- 逐个尝试候选路径，第一个成功的就用
        local matched = false
        for _, c in ipairs(entry.audioCandidates) do
            local willPlay, handle = PlaySoundFile(c.path, "Master")
            if willPlay then
                activeSoundHandle = handle
                T.debug("自定义配音: " .. c.label .. " (" .. (C.DB.customAudioPack or "ShengTangTools") .. ")")
                -- 有剩余文本则插回队列头部（也走配音解析，不直接当 TTS）
                if c.remainder and c.remainder ~= "" then
                    local subCandidates = T.CustomAudio and T.CustomAudio.Resolve(c.remainder)
                    if subCandidates then
                        table.insert(queue, 1, { audioCandidates = subCandidates, originalText = c.remainder })
                    else
                        table.insert(queue, 1, c.remainder)
                    end
                end
                C_Timer.After(AUDIO_DELAY, function()
                    isPlaying = false
                    ProcessQueue()
                end)
                matched = true
                break
            end
        end

        if not matched then
            -- 所有候选都没命中，原文走 TTS
            isPlaying = false
            table.insert(queue, 1, entry.originalText)
            ProcessQueue()
        end
        return
    end

    -- ━━━ TTS 条目（字符串） ━━━
    local text = NormalizeText(entry)
    if text == "" then
        C_Timer.After(0.05, ProcessQueue)
        return
    end

    isPlaying = true
    waitingForTTSStart = true
    currentTTSUtteranceID = nil
    ttsGeneration = ttsGeneration + 1
    local generation = ttsGeneration
    StopCustomAudio()

    if not (C_VoiceChat and C_VoiceChat.SpeakText) then
        T.debug("TTS API 不可用，降级打印：" .. text)
        waitingForTTSStart = false
        C_Timer.After(0.3, function()
            isPlaying = false
            ProcessQueue()
        end)
        return
    end

    if C_VoiceChat.StopSpeakingText then
        C_VoiceChat.StopSpeakingText()
    end

    C_Timer.After(0.1, function()
        if not isPlaying then
            return
        end
        local voiceID = C.DB.ttsVoiceID or 0
        local volume = C.DB.ttsVolume or 100
        local rate = C.DB.ttsRate or 0
        C_VoiceChat.SpeakText(voiceID, text, rate, volume, false)
        T.debug("TTS播放: " .. text .. " (音量: " .. tostring(volume) .. ")")
        C_Timer.After(TTS_START_TIMEOUT, function()
            if isPlaying and waitingForTTSStart and currentTTSUtteranceID == nil and generation == ttsGeneration then
                FinishCurrentTTS()
            end
        end)
    end)
end

-- 向队列追加一条 TTS 文本
function Speaker:Enqueue(text)
    if not C.DB.ttsEnabled then
        return false
    end
    local plog = T.PerfLog and T.PerfLog:Begin("tts:enqueue")
    local normalized = NormalizeText(text)
    if normalized == "" then
        if plog then plog:Finish({ qlen = #queue }) end
        return false
    end
    queue[#queue + 1] = normalized
    if not isPlaying then
        ProcessQueue()
    end
    if plog then plog:Finish({ qlen = #queue }) end
    return true
end

-- 向队列追加一条自定义配音
function Speaker:EnqueueAudio(path, label)
    if not C.DB.ttsEnabled then
        return false
    end
    queue[#queue + 1] = { audio = path, label = label }
    if not isPlaying then
        ProcessQueue()
    end
    return true
end

function Speaker:Clear()
    wipe(queue)
    isPlaying = false
    waitingForTTSStart = false
    currentTTSUtteranceID = nil
    ttsGeneration = ttsGeneration + 1
    StopCustomAudio()
    if C_VoiceChat and C_VoiceChat.StopSpeakingText then
        C_VoiceChat.StopSpeakingText()
    end
end

function Speaker:PlayList(texts)
    if type(texts) ~= "table" then
        return
    end
    for _, text in ipairs(texts) do
        self:Enqueue(text)
    end
end

-- 核心入口：解析文本 → 配音候选探测 → 入队
T.PlayTTS = function(text)
    if not C.DB.ttsEnabled then return false end

    local normalized = NormalizeText(text)
    if normalized == "" then return false end

    if C.DB.printEventsToChat then
        DEFAULT_CHAT_FRAME:AddMessage(normalized)
    end

    -- 尝试自定义配音解析
    if T.CustomAudio then
        local candidates = T.CustomAudio.Resolve(normalized)
        if candidates then
            -- 候选列表按优先级排列（完整匹配 > 前缀匹配）
            -- 入队一个"配音探测"条目：队列播放时逐个尝试 PlaySoundFile
            queue[#queue + 1] = { audioCandidates = candidates, originalText = normalized }
            if not isPlaying then
                ProcessQueue()
            end
            return true
        end
    end

    return Speaker:Enqueue(text)
end

T.ClearTTSQueue = function()
    Speaker:Clear()
end

end)
