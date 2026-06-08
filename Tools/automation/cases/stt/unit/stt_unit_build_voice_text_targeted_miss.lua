return {
  meta = {
    id = "stt_unit_build_voice_text_targeted_miss",
    plugin = "stt",
    type = "unit",
    title = "BuildVoiceText 未命中当前玩家时直接静默",
  },
  init = {
    playerName = "测试者",
    spellInfoMap = {
      [1249265] = { name = "狂奔怒火", iconID = 555001 },
    },
  },
  events = {
    {
      type = "build_voice_text",
      event = {
        content = "{张三}{spell:1249265} 去左边",
      },
    },
  },
  expect = {
    equals = "",
  },
}
