return {
  meta = {
    id = "stt_unit_diagnose_audience_miss",
    plugin = "stt",
    type = "unit",
    title = "一键诊断不统计未命中当前玩家的人员组",
  },
  init = {
    playerName = "旁观者",
    inRaid = true,
    raidRoster = {
      { name = "旁观者", subgroup = 1 },
      { name = "瑟维雅", subgroup = 1 },
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
      displayHits = 0,
      reason = "no_hit",
      source = "MRT",
    },
  },
}
