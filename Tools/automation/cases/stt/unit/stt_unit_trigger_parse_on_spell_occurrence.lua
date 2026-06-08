return {
  meta = {
    id = "stt_unit_trigger_parse_on_spell_occurrence",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine 新格式 {on:spell:xxx}#N 第N次触发",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{on:spell:466064}#2 {所有人}第二次集合" },
  },
  expect = {
    equals = {
      spellID = 466064,
      triggerKind = "spell",
      occurrence = 2,
      mode = "text",
      payload = "{所有人}第二次集合",
      requireAudience = true,
      segmentCount = 1,
    },
  },
}
