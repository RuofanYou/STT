return {
  meta = { id = "stt_replay_clear_tts_queue", plugin = "stt", type = "replay", title = "清队后状态回放" },
  init = {
    db = { ttsEnabled = true, ttsVoiceID = 0, ttsVolume = 100 },
    manualTimers = true,
  },
  events = {
    { type = "play_tts", texts = { "测试A", "测试B" } },
    { type = "run_timers", maxDelay = 0.1 },
    { type = "clear_tts" },
  },
  expect = {
    baseline = "stt_replay_clear_tts_queue.golden.lua",
  },
}
