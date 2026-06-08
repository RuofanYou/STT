return {
  meta = { id = "stt_replay_tts_queue_start_timeout", plugin = "stt", type = "replay", title = "TTS 未收到开始事件时继续队列" },
  init = {
    db = { ttsEnabled = true, ttsVoiceID = 0, ttsVolume = 100 },
    manualTimers = true,
  },
  events = {
    { type = "play_tts", texts = { "一号", "二号" } },
    { type = "run_timers", maxDelay = 0.1 },
    { type = "run_timers", minDelay = 3 },
    { type = "run_timers", maxDelay = 0.1 },
    { type = "collect_tts_trace" },
  },
  expect = {
    baseline = "stt_replay_tts_queue_start_timeout.golden.lua",
  },
}
