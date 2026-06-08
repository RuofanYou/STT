return {
  meta = {
    id = "stt_unit_trigger_parse_event_with_audience",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine {event:xx} 带受众",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{event:16} {所有人}注意吸取灵魂" },
  },
  expect = {
    equals = {
      eventID = 16,
      triggerKind = "event",
      mode = "text",
      payload = "{所有人}注意吸取灵魂",
      requireAudience = true,
      segmentCount = 1,
    },
  },
}
