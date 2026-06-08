return {
  meta = { id = "stt_unit_build_segments_condition_and_player", plugin = "stt", type = "unit", title = "segments 正确拆分条件与玩家" },
  init = {
    spellNameMap = { [123] = "烈焰" },
  },
  events = {
    { type = "build_segments", text = "{tank}开怪 {Alice}走位 {spell:123}" },
  },
  expect = {
    equals = {
      {
        text = "开怪",
        condition = "tank",
        cellText = "开怪",
        rawText = "开怪",
        spellTokens = {},
      },
      {
        text = "走位 烈焰",
        condition = "",
        players = { "Alice" },
        cellText = "走位 烈焰",
        rawText = "走位 {spell:123}",
        primarySpellID = 123,
        spellTokens = {
          {
            raw = "{spell:123}",
            spellID = 123,
            spellName = "烈焰",
            spellIcon = 100123,
            isPrimarySpell = true,
          },
        },
      },
    },
  },
}
