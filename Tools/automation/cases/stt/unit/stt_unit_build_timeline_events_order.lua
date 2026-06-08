return {
  meta = { id = "stt_unit_build_timeline_events_order", plugin = "stt", type = "unit", title = "BuildTimelineEvents 生成 showTime 并排序" },
  init = {
    playerRole = "TANK",
    db = {
      advanceTime = 3,
    },
  },
  events = {
    {
      type = "build_timeline_events",
      parsed = {
        { time = 12, segments = { { text = "第二条", condition = "所有人", players = nil } }, content = "{所有人}第二条" },
        { time = 5, segments = { { text = "第一条", condition = "tank", players = nil } }, content = "{tank}第一条" },
      },
    },
  },
  expect = {
    equals = {
      { time = 5, showTime = 2, text = "第一条" },
      { time = 12, showTime = 9, text = "第二条" },
    },
  },
}
