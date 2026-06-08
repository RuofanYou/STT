return {
  meta = {
    id = "stt_unit_trigger_parse_on_spell_empty",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine 新格式 {on:spell:xxx} 纯触发标记无播报",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{on:spell:466064}" },
  },
  expect = {
    equals = {
      spellID = 466064,
      triggerKind = "spell",
      mode = "text",
      payload = "",
      requireAudience = true,
      segmentCount = 0,
    },
  },
}
