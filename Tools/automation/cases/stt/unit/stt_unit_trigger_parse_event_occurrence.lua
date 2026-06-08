return {
  meta = {
    id = "stt_unit_trigger_parse_event_occurrence",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine {event:xx}#N 带次数",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{event:16}#2 {所有人}第二次吸取灵魂" },
  },
  expect = {
    equals = {
      eventID = 16,
      triggerKind = "event",
      occurrence = 2,
      mode = "text",
      payload = "{所有人}第二次吸取灵魂",
      requireAudience = true,
      segmentCount = 1,
    },
  },
}
