return {
  meta = {
    id = "stt_unit_trigger_parse_event_empty",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine {event:xx} 纯触发标记无播报",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{event:16}" },
  },
  expect = {
    equals = {
      eventID = 16,
      triggerKind = "event",
      mode = "text",
      payload = "",
      requireAudience = true,
      segmentCount = 0,
    },
  },
}
