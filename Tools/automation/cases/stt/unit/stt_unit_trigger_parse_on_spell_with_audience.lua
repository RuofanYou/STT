return {
  meta = {
    id = "stt_unit_trigger_parse_on_spell_with_audience",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine 新格式 {on:spell:xxx} 带受众",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{on:spell:466064} {所有人}躲正面" },
  },
  expect = {
    equals = {
      spellID = 466064,
      triggerKind = "spell",
      mode = "text",
      payload = "{所有人}躲正面",
      requireAudience = true,
      segmentCount = 1,
    },
  },
}
