return {
  meta = {
    id = "stt_unit_runtime_group_slot_targets_tts",
    plugin = "stt",
    type = "unit",
    title = "运行时多人员槽位仍按真实成员进入语音与屏幕提醒队列",
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
      type = "personal_stt_runtime_counts",
      text = table.concat({
        "[人员]",
        "DZ1=瑟维雅",
        "DZ2=瑟维贼",
        "种子=DZ1 DZ2",
        "",
        "[时间轴]",
        "{time:00:05}{种子}{to:种子环形提醒#1}丢下种子",
        "{time:0:08} {DZ2}{spell:122470,dur:10}<业报之触>",
      }, "\n"),
    },
  },
  expect = {
    equals = {
      isValid = true,
      externalDetected = false,
      processedHasAll = false,
      eventCount = 2,
      timelineCount = 1,
      boardCount = 2,
      hits = 1,
      translatorEventCount = 0,
      translatorHasAll = false,
    },
  },
}
