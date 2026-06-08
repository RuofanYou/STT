return {
  meta = {
    id = "stt_unit_spell_token_legacy_colon",
    plugin = "stt",
    type = "unit",
    title = "spell token 保留冒号旧写法",
  },
  init = {
    spellNameMap = {
      [363534] = "回溯",
    },
  },
  events = {
    { type = "parse_line", line = "{time:00:05}{DKT1}{spell:363534:4}<回溯>" },
  },
  expect = {
    equals = {
      time = 5,
      content = "{DKT1}{spell:363534:4}<回溯>",
      displayText = "{DKT1}回溯",
      hasAudience = true,
      segments = {
        {
          text = "回溯",
          cellText = "回溯",
          rawText = "{spell:363534:4}<回溯>",
          condition = "",
          players = { "DKT1" },
          spellTokens = {
            {
              raw = "{spell:363534:4}",
              spellID = 363534,
              spellName = "回溯",
              spellIcon = 463534,
              isPrimarySpell = true,
            },
          },
          primarySpellID = 363534,
        },
      },
    },
  },
}
