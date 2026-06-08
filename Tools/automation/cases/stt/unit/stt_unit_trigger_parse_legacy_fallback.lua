return {
  meta = {
    id = "stt_unit_trigger_parse_legacy_fallback",
    plugin = "stt",
    type = "unit",
    title = "ParseRuleLine 旧格式 {spell:xxx}|mode|payload 不再支持",
  },
  init = {},
  events = {
    { type = "parse_trigger_rule_line", line = "{spell:466064}|text|{所有人}快躲" },
  },
  expect = {
    equals = { error = "no_match" },
  },
}
