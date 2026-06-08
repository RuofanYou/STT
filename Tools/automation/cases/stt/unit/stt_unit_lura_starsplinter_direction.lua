return {
  meta = {
    id = "stt_unit_lura_starsplinter_direction",
    plugin = "stt",
    type = "unit",
    title = "鲁拉 P4 星辰裂片方向窗口（实验）只在命中时间叠加箭头",
  },
  events = {
    {
      type = "lura_starsplinter_direction_cases",
      cases = {
        { label = "p4_13_2", encounterID = 3183, difficultyID = 16, phase = "p4", severity = 1, elapsedSec = 13.2 },
        { label = "p4_14_2", encounterID = 3183, difficultyID = 16, phase = "p4", severity = 1, elapsedSec = 14.2 },
        { label = "p4_15_2", encounterID = 3183, difficultyID = 16, phase = "p4", severity = 1, elapsedSec = 15.2 },
        { label = "p4_33_2", encounterID = 3183, difficultyID = 16, phase = "p4", severity = 1, elapsedSec = 33.2 },
        { label = "p4_34_2", encounterID = 3183, difficultyID = 16, phase = "p4", severity = 1, elapsedSec = 34.2 },
        { label = "p4_35_2", encounterID = 3183, difficultyID = 16, phase = "p4", severity = 1, elapsedSec = 35.2 },
        { label = "other_boss", encounterID = 9999, difficultyID = 16, phase = "p4", severity = 1, elapsedSec = 13.2 },
        { label = "non_mythic", encounterID = 3183, difficultyID = 15, phase = "p4", severity = 1, elapsedSec = 13.2 },
        { label = "non_p4", encounterID = 3183, difficultyID = 16, phase = "p3", severity = 1, elapsedSec = 13.2 },
        { label = "other_severity", encounterID = 3183, difficultyID = 16, phase = "p4", severity = 2, elapsedSec = 13.2 },
        { label = "outside_window", encounterID = 3183, difficultyID = 16, phase = "p4", severity = 1, elapsedSec = 16.2 },
      },
    },
  },
  expect = {
    equals = {
      { label = "p4_13_2", arrow = "←" },
      { label = "p4_14_2", arrow = "→" },
      { label = "p4_15_2", arrow = "←" },
      { label = "p4_33_2", arrow = "←" },
      { label = "p4_34_2", arrow = "→" },
      { label = "p4_35_2", arrow = "←" },
      { label = "other_boss", arrow = nil },
      { label = "non_mythic", arrow = nil },
      { label = "non_p4", arrow = nil },
      { label = "other_severity", arrow = nil },
      { label = "outside_window", arrow = nil },
    },
  },
}
