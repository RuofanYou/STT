return {
  meta = {
    id = "stt_unit_parse_line_audience_state",
    plugin = "stt",
    type = "unit",
    title = "ParseTimelineLine 区分可展示与可执行受众状态",
  },
  init = {},
  events = {
    { type = "parse_line", line = "{time:00:04} {spell:1249251}" },
  },
  expect = {
    equals = {
      time = 4,
      content = "{spell:1249251}",
      displayText = "Spell1249251",
      hasAudience = false,
      segments = {
        {
          text = "Spell1249251",
          condition = "",
          cellText = "Spell1249251",
          rawText = "{spell:1249251}",
          primarySpellID = 1249251,
          spellTokens = {
            {
              raw = "{spell:1249251}",
              spellID = 1249251,
              spellName = "Spell1249251",
              spellIcon = 1349251,
              isPrimarySpell = true,
            },
          },
        },
      },
    },
  },
}
