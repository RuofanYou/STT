return {
  meta = {
    id = "stt_unit_diagnose_bar_only_display_hit",
    plugin = "stt",
    type = "unit",
    title = "一键诊断把命中自己的 bar-only 行统计为显示内容",
  },
  init = {
    playerName = "瑟维雅",
    inRaid = true,
    raidRoster = {
      { name = "瑟维雅", subgroup = 1 },
      { name = "瑟维贼", subgroup = 1 },
    },
  },
  events = {
    {
      type = "set_source_text",
      source = "MRT",
      text = table.concat({
        "[人员]",
        "DZ1=瑟维雅",
        "DZ2=瑟维贼",
        "种子=DZ1 DZ2",
        "",
        "[时间轴]",
        "{time:00:43.5} {种子}{bar:5,spell:1253031,label:<扔下种子>}",
      }, "\n"),
    },
    { type = "collect_diagnose_hits" },
  },
  expect = {
    equals = {
      ttsHits = 0,
      displayHits = 1,
      reason = "display_only",
      source = "MRT",
    },
  },
}
