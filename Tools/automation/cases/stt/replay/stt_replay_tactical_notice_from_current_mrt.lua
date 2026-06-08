return {
  meta = {
    id = "stt_replay_tactical_notice_from_current_mrt",
    plugin = "stt",
    type = "replay",
    title = "从 MRT 启动后触发屏幕提醒",
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
    { type = "advance_time", elapsed = 0 },
    { type = "advance_time", elapsed = 5 },
    { type = "collect" },
  },
  expect = {
    baseline = "stt_replay_tactical_notice_from_current_mrt.golden.lua",
  },
}
