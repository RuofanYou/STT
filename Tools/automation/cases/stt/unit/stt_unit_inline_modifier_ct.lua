return {
  meta = {
    id = "stt_unit_inline_modifier_ct",
    plugin = "stt",
    type = "unit",
    title = "ParseTimelineLine 剥离 {ct:N} 并保留受众",
  },
  init = {},
  events = {
    { type = "parse_line", line = "{time:00:10}{ct:5} {所有人}分散" },
  },
  expect = {
    equals = {
      time = 10,
      content = "{所有人}分散",
      displayText = "{所有人}分散",
      hasAudience = true,
      modifiers = {
        ct = { value = 5 },
      },
      segments = {
        { text = "分散", cellText = "分散", rawText = "分散", condition = "所有人", spellTokens = {} },
      },
    },
  },
}
