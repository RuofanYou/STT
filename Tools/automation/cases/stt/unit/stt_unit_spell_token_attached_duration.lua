return {
  meta = {
    id = "stt_unit_spell_token_attached_duration",
    plugin = "stt",
    type = "unit",
    title = "spell token 支持逗号 dur 写法并保留旧写法",
  },
  init = {
    spellNameMap = {
      [363534] = "回溯",
    },
  },
  events = {
    { type = "parse_line", line = "{time:00:05}{DKT1}{spell:363534,dur:4}<回溯>" },
  },
  expect = {
    equals = {
      time = 5,
      content = "{DKT1}{spell:363534}<回溯>",
      displayText = "{DKT1}回溯",
      hasAudience = true,
      modifiers = {
        dur = { value = 4 },
      },
      segments = {
        {
          text = "回溯",
          cellText = "回溯",
          rawText = "{spell:363534}<回溯>",
          condition = "",
          players = { "DKT1" },
          spellTokens = {
            {
              raw = "{spell:363534}",
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
