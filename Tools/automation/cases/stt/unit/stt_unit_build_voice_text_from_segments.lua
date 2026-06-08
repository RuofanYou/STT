return {
  meta = { id = "stt_unit_build_voice_text_from_segments", plugin = "stt", type = "unit", title = "BuildVoiceText 合并 segments" },
  init = {},
  events = {
    {
      type = "build_voice_text",
      event = {
        segments = {
          { text = "第一句" },
          { text = "第二句" },
        },
      },
    },
  },
  expect = {
    equals = "第一句 第二句",
  },
}
