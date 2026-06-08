return {
  meta = { id = "stt_unit_should_trigger_false_names", plugin = "stt", type = "unit", title = "ShouldTriggerEvent 名单不匹配" },
  init = {
    playerName = "Alice",
  },
  events = {
    {
      type = "should_trigger",
      event = {
        segments = {
          { text = "转火", condition = "", players = { "Bob" } },
        },
      },
    },
  },
  expect = {
    equals = false,
  },
}
