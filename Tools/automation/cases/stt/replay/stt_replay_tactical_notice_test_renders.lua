return {
  meta = {
    id = "stt_replay_tactical_notice_test_renders",
    plugin = "stt",
    type = "replay",
    title = "屏幕提醒测试按钮应真实渲染样例",
  },
  init = {
    spellInfoMap = {
      [589] = { iconID = 135898 },
      [17] = { iconID = 135940 },
    },
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
      text = [[
{time:00:03}{所有人}{star}集合 {spell:589}
{time:00:08}<静默>{所有人}坦克换嘲讽 {spell:17}
      ]],
    },
    { type = "tactical_notice_command", args = "test" },
    { type = "collect_screen" },
  },
  expect = {
    baseline = "stt_replay_tactical_notice_test_renders.golden.lua",
  },
}
