return {
  meta = {
    id = "stt_replay_tactical_notice_stop_clears",
    plugin = "stt",
    type = "replay",
    title = "停止时间轴后清空屏幕提醒",
  },
  init = {
    spellInfoMap = {
      [589] = { iconID = 135898 },
    },
    db = {
      dataSource = "MRT",
      useRaidNote = true,
      useSelfNote = false,
      advanceTime = 3,
      ttsEnabled = false,
      blizzardTimeline = { injectInTest = false },
    },
  },
  events = {
    {
      type = "set_source_text",
      source = "MRT",
      text = [[
{time:00:03}<静默>{所有人}集合 {spell:589}
{time:00:08}{所有人}第二条
      ]],
    },
    { type = "start_from_current_screen", isTest = false },
    { type = "stop_timeline_screen" },
    { type = "collect" },
  },
  expect = {
    baseline = "stt_replay_tactical_notice_stop_clears.golden.lua",
  },
}
