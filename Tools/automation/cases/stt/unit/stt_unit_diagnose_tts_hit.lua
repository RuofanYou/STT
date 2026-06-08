return {
  meta = {
    id = "stt_unit_diagnose_tts_hit",
    plugin = "stt",
    type = "unit",
    title = "一键诊断把命中自己的正文行统计为语音播报",
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
        "{time:00:43.5} {种子} 扔下种子",
      }, "\n"),
    },
    { type = "collect_diagnose_hits" },
  },
  expect = {
    equals = {
      ttsHits = 1,
      displayHits = 0,
      reason = "ok",
      source = "MRT",
    },
  },
}
