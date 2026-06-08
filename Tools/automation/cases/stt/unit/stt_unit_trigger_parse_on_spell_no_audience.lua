return {
  meta = {
    id = "stt_unit_trigger_parse_on_spell_no_audience",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine 新格式无受众 requireAudience 阻止播报",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{on:spell:466064} 这是备注" },
  },
  expect = {
    equals = {
      spellID = 466064,
      triggerKind = "spell",
      mode = "text",
      payload = "这是备注",
      requireAudience = true,
      segmentCount = 1,
    },
  },
}
