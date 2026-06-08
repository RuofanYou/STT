return {
  meta = {
    id = "stt_replay_tactical_notice_test_empty_placeholder",
    plugin = "stt",
    type = "replay",
    title = "屏幕提醒测试在空数据源时显示占位提醒",
  },
  init = {
    db = {
      dataSource = "MRT",
      useRaidNote = true,
      useSelfNote = false,
      ttsEnabled = false,
      blizzardTimeline = { injectInTest = false },
    },
  },
  events = {
    {
      type = "set_source_text",
      source = "MRT",
      text = "",
    },
    { type = "tactical_notice_command", args = "test" },
    { type = "collect_screen" },
  },
  expect = {
    baseline = "stt_replay_tactical_notice_test_empty_placeholder.golden.lua",
  },
}
