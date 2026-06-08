return {
  meta = {
    id = "stt_replay_tactical_notice_lock_hides_anchors",
    plugin = "stt",
    type = "replay",
    title = "屏幕提醒锁定后应隐藏编辑壳",
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
    { type = "tactical_notice_command", args = "lock" },
    { type = "collect_screen" },
  },
  expect = {
    baseline = "stt_replay_tactical_notice_lock_hides_anchors.golden.lua",
  },
}
