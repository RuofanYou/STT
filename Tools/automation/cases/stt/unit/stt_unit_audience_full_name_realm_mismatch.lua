return {
  meta = {
    id = "stt_unit_audience_full_name_realm_mismatch",
    plugin = "stt",
    type = "unit",
    title = "人员全名服务器不同时不误命中",
  },
  init = {
    playerName = "棒不头吴彦祖-死亡之翼",
    inRaid = true,
    raidRoster = {
      { name = "棒不头吴彦祖-死亡之翼", subgroup = 1 },
    },
  },
  events = {
    {
      type = "personal_stt_runtime_counts",
      text = table.concat({
        "[人员]",
        "咕咕1=棒不头吴彦祖-奥特兰克",
        "种子=咕咕1",
        "",
        "[时间轴]",
        "{time:00:05}{种子}{bar:5,spell:1253031,label:<扔下种子>}",
      }, "\n"),
    },
  },
  expect = {
    equals = {
      isValid = true,
      externalDetected = false,
      processedHasAll = false,
      eventCount = 1,
      timelineCount = 0,
      boardCount = 1,
      hits = 0,
      translatorEventCount = 0,
      translatorHasAll = false,
    },
  },
}
