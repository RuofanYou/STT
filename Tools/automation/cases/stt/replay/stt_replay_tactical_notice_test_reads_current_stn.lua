return {
  meta = {
    id = "stt_replay_tactical_notice_test_reads_current_stn",
    plugin = "stt",
    type = "replay",
    title = "屏幕提醒测试读取当前 STN 方案",
  },
  init = {
    spellInfoMap = {
      [2061] = { iconID = 135913 },
    },
    db = {
      dataSource = "STN",
      ttsEnabled = false,
      blizzardTimeline = { injectInTest = false },
    },
  },
  events = {
    {
      type = "set_note",
      note = {
        default = {
          id = 3,
          name = "当前STN方案",
          content = [[
[方案]
名称 = STN屏幕提醒测试

[人员]
治疗 = 测试治疗

[时间轴]
{time:00:05}{所有人}治疗准备减伤 {spell:2061}
          ]],
        },
      },
    },
    { type = "tactical_notice_command", args = "test" },
    { type = "collect_screen" },
  },
  expect = {
    baseline = "stt_replay_tactical_notice_test_reads_current_stn.golden.lua",
  },
}
