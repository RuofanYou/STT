return {
  meta = {
    id = "stt_unit_inline_modifier_sound",
    plugin = "stt",
    type = "unit",
    title = "ParseTimelineLine 剥离 {@...} 并解析音效路径",
  },
  init = {},
  events = {
    { type = "parse_line", line = "{time:00:10}{@ding.m4a} {所有人}分散" },
  },
  expect = {
    equals = {
      time = 10,
      content = "{所有人}分散",
      displayText = "{所有人}分散",
      hasAudience = true,
      modifiers = {
        sound = {
          path = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\ding.m4a",
          label = "ding.m4a",
        },
      },
      segments = {
        { text = "分散", cellText = "分散", rawText = "分散", condition = "所有人", spellTokens = {} },
      },
    },
  },
}
