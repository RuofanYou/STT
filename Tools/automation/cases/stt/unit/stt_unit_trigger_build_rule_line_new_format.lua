return {
  meta = {
    id = "stt_unit_trigger_build_rule_line_new_format",
    plugin = "stt",
    type = "unit",
    title = "BuildRuleLine 输出新格式并自动补 {所有人}",
  },
  init = {},
  events = {
    { type = "build_trigger_rule_line", spellID = 466064, occurrence = nil, mode = "text", payload = "快躲" },
  },
  expect = {
    equals = "{on:spell:466064} {所有人}快躲",
  },
}
