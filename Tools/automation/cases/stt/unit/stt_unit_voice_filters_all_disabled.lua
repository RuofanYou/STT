return {
  meta = { id = "stt_unit_voice_filters_all_disabled", plugin = "stt", type = "unit", title = "filterAll 关闭后不播报所有人条件" },
  init = {
    db = {
      filterAll = false,
    },
  },
  events = {
    {
      type = "should_trigger",
      event = {
        segments = {
          { text = "集合", condition = "所有人", players = nil },
        },
      },
    },
  },
  expect = {
    equals = false,
  },
}
