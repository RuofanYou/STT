return {
  meta = { id = "stt_unit_should_trigger_true", plugin = "stt", type = "unit", title = "ShouldTriggerEvent 命中职责条件" },
  init = {
    playerRole = "TANK",
  },
  events = {
    {
      type = "should_trigger",
      event = {
        segments = {
          { text = "开怪", condition = "tank", players = nil },
        },
      },
    },
  },
  expect = {
    equals = true,
  },
}
