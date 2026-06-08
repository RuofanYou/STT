return {
  meta = {
    id = "stt_unit_build_segments_attached_spell_duration",
    plugin = "stt",
    type = "unit",
    title = "BuildSegments 直接识别 spell token 的 dur 参数",
  },
  init = {
    spellNameMap = {
      [363534] = "回溯",
    },
  },
  events = {
    { type = "build_segments", text = "{DKT1}{spell:363534,dur:4}<回溯>" },
  },
  expect = {
    equals = {
      {
        text = "回溯",
        condition = "",
        players = { "DKT1" },
        cellText = "回溯",
        primarySpellID = 363534,
        rawText = "{spell:363534,dur:4}<回溯>",
        spellTokens = {
          {
            raw = "{spell:363534,dur:4}",
            spellID = 363534,
            spellName = "回溯",
            spellIcon = 463534,
            isPrimarySpell = true,
            duration = 4,
          },
        },
      },
    },
  },
}
