return {
  meta = { id = "stt_unit_voice_filters_boss_all_timeline", plugin = "stt", type = "unit", title = "BOSS 前缀加所有人条件在所有人过滤关闭时不进入运行时间线" },
  init = {
    db = {
      filterAll = false,
    },
  },
  events = {
    {
      type = "parse_and_build_timeline_events_screen",
      text = "{time:00:21} {BOSS}飞羽1:{所有人}注意羽毛",
    },
  },
  expect = {
    equals = {},
  },
}
