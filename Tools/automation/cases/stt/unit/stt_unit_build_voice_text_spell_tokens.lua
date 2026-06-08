return {
  meta = {
    id = "stt_unit_build_voice_text_spell_tokens",
    plugin = "stt",
    type = "unit",
    title = "语音文本对 spell token 只读法术名",
  },
  init = {
    spellInfoMap = {
      [1249265] = { name = "狂奔怒火", iconID = 555001 },
      [1251361] = { name = "熊形态", iconID = 555002 },
    },
  },
  events = {
    {
      type = "build_voice_text",
      event = {
        content = "{所有人}{spell:1249265} 去左边 {spell:1251361}",
      },
    },
  },
  expect = {
    equals = "狂奔怒火 去左边 熊形态",
  },
}
