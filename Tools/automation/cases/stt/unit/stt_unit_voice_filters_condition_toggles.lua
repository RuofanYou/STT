return {
  meta = { id = "stt_unit_voice_filters_condition_toggles", plugin = "stt", type = "unit", title = "职业职责站位小队过滤开关生效" },
  init = {
    playerClassToken = "WARRIOR",
    playerClassLocalized = "战士",
    playerRole = "TANK",
    inRaid = true,
    raidRoster = {
      { name = "Tester", subgroup = 1 },
    },
    db = {
      filterClass = false,
      filterRole = false,
      filterPos = false,
      filterParty = false,
    },
  },
  events = {
    {
      type = "build_timeline_events",
      parsed = {
        {
          time = 1,
          hasAudience = true,
          segments = {
            { text = "职业", condition = "战士", players = nil },
          },
        },
        {
          time = 2,
          hasAudience = true,
          segments = {
            { text = "职责", condition = "坦克", players = nil },
          },
        },
        {
          time = 3,
          hasAudience = true,
          segments = {
            { text = "站位", condition = "近战", players = nil },
          },
        },
        {
          time = 4,
          hasAudience = true,
          segments = {
            { text = "小队", condition = "g1", players = nil },
          },
        },
      },
    },
  },
  expect = {
    equals = {},
  },
}
