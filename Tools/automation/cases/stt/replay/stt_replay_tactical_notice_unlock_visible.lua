return {
  meta = {
    id = "stt_replay_tactical_notice_unlock_visible",
    plugin = "stt",
    type = "replay",
    title = "屏幕提醒解锁后应显示可见框体",
  },
  init = {
    db = {
      dataSource = "MRT",
      useRaidNote = false,
      useSelfNote = false,
      ttsEnabled = false,
      blizzardTimeline = { injectInTest = false },
    },
  },
  events = {
    { type = "tactical_notice_command", args = "unlock" },
    { type = "collect_screen" },
  },
  expect = {
    baseline = "stt_replay_tactical_notice_unlock_visible.golden.lua",
  },
}
