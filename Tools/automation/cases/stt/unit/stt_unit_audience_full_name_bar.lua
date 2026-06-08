return {
  meta = {
    id = "stt_unit_audience_full_name_bar",
    plugin = "stt",
    type = "unit",
    title = "人员全名带服务器时当前玩家仍能收到进度条",
  },
  init = {
    playerName = "棒不头吴彦祖",
    inRaid = true,
    raidRoster = {
      { name = "棒不头吴彦祖", subgroup = 1 },
    },
    db = {
      dataSource = "MRT",
      useRaidNote = true,
      useSelfNote = false,
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
      timelineCount = 1,
      boardCount = 1,
      hits = 1,
      translatorEventCount = 0,
      translatorHasAll = false,
    },
  },
}
