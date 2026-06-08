return {
  meta = { id = "stt_replay_start_from_current_mrt", plugin = "stt", type = "replay", title = "正式模式从 MRT 启动回放" },
  init = {
    db = {
      dataSource = "MRT",
      useRaidNote = true,
      useSelfNote = false,
      advanceTime = 3,
      blizzardTimeline = { injectInTest = false },
    },
  },
  events = {
    {
      type = "set_source_text",
      source = "MRT",
      text = [[
{time:00:03}{所有人}集合
{time:00:08}{所有人}分散
      ]],
    },
    { type = "start_from_current", isTest = false },
  },
  expect = {
    baseline = "stt_replay_start_from_current_mrt.golden.lua",
  },
}
