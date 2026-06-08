return {
  meta = { id = "stt_replay_tts_queue_sequence", plugin = "stt", type = "replay", title = "TTS 队列顺序回放" },
  init = {
    db = { ttsEnabled = true, ttsVoiceID = 0, ttsVolume = 100 },
    manualTimers = true,
  },
  events = {
    { type = "play_tts", texts = { "一号", "二号", "三号" } },
    { type = "run_timers", maxDelay = 0.1 },
    { type = "tts_event", eventName = "VOICE_CHAT_TTS_PLAYBACK_STARTED", args = { 0, 101, 500 } },
    { type = "tts_event", eventName = "VOICE_CHAT_TTS_PLAYBACK_FINISHED", args = { 1, 101 } },
    { type = "run_timers", maxDelay = 0.1 },
    { type = "tts_event", eventName = "VOICE_CHAT_TTS_PLAYBACK_STARTED", args = { 0, 102, 500 } },
    { type = "tts_event", eventName = "VOICE_CHAT_TTS_PLAYBACK_FINISHED", args = { 1, 102 } },
    { type = "run_timers", maxDelay = 0.1 },
    { type = "tts_event", eventName = "VOICE_CHAT_TTS_PLAYBACK_STARTED", args = { 0, 103, 500 } },
    { type = "tts_event", eventName = "VOICE_CHAT_TTS_PLAYBACK_FINISHED", args = { 1, 103 } },
    { type = "collect_tts_trace" },
  },
  expect = {
    baseline = "stt_replay_tts_queue_sequence.golden.lua",
  },
}
