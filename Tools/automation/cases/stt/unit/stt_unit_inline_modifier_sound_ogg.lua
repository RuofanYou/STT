return {
  meta = {
    id = "stt_unit_inline_modifier_sound_ogg",
    plugin = "stt",
    type = "unit",
    title = "ParseTimelineLine 支持 ogg 行内音效",
  },
  init = {},
  events = {
    { type = "parse_line", line = "{time:00:10}{@alert.ogg} {所有人}分散" },
  },
  expect = {
    equals = {
      time = 10,
      content = "{所有人}分散",
      displayText = "{所有人}分散",
      hasAudience = true,
      modifiers = {
        sound = {
          path = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\alert.ogg",
          label = "alert.ogg",
        },
      },
      segments = {
        { text = "分散", cellText = "分散", rawText = "分散", condition = "所有人", spellTokens = {} },
      },
    },
  },
}
