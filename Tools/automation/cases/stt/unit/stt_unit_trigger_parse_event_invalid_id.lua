return {
  meta = {
    id = "stt_unit_trigger_parse_event_invalid_id",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine {event:0} 无效事件ID",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{event:0} {所有人}无效" },
  },
  expect = {
    equals = {
      error = "event_id_invalid",
    },
  },
}
