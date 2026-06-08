return {
  meta = { id = "stt_replay_start_from_current_test_no_inject", plugin = "stt", type = "replay", title = "测试模式默认不注入暴雪时间轴" },
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
{time:00:05}{所有人}测试注入
      ]],
    },
    { type = "start_from_current", isTest = true },
  },
  expect = {
    baseline = "stt_replay_start_from_current_test_no_inject.golden.lua",
  },
}
