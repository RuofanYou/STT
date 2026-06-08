return {
  meta = { id = "stt_unit_parse_text_sort", plugin = "stt", type = "unit", title = "ParseTimelineText 按时间排序" },
  init = {},
  events = {
    { type = "parse_text", text = "{time:00:20}{所有人}B\n{time:00:05}{所有人}A" },
  },
  expect = {
    equals = {
      {
        time = 5,
        line = 2,
        content = "{所有人}A",
        displayText = "{所有人}A",
        hasAudience = true,
        segments = {
          {
            text = "A",
            condition = "所有人",
            cellText = "A",
            rawText = "A",
            spellTokens = {},
          },
        },
      },
      {
        time = 20,
        line = 1,
        content = "{所有人}B",
        displayText = "{所有人}B",
        hasAudience = true,
        segments = {
          {
            text = "B",
            condition = "所有人",
            cellText = "B",
            rawText = "B",
            spellTokens = {},
          },
        },
      },
    },
  },
}
