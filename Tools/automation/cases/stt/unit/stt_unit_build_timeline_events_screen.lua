return {
  meta = {
    id = "stt_unit_build_timeline_events_screen",
    plugin = "stt",
    type = "unit",
    title = "BuildTimelineEvents 生成屏幕提醒字段",
  },
  init = {
    spellInfoMap = {
      [589] = { iconID = 135898 },
    },
    db = {
      advanceTime = 3,
    },
  },
  events = {
    {
      type = "build_timeline_events_screen",
      parsed = {
        {
          time = 3,
          content = "<静默>{所有人}集合 {spell:589}",
          displayText = "<静默>{所有人}集合 Spell589",
          spellID = 589,
        },
        {
          time = 8,
          content = "亡者吐息1:{所有人}去左边 {萨满1}风行",
          displayText = "亡者吐息1:{所有人}去左边 {萨满1}风行",
        },
      },
    },
  },
  expect = {
    equals = {
      {
        time = 3,
        showTime = 0,
        text = "集合 Spell589",
        timelineText = "集合 Spell589",
        ttsText = "集合 Spell589",
        spellID = 589,
        spellIcon = 135898,
        isSilent = false,
      },
      {
        time = 8,
        showTime = 5,
        text = "去左边",
        timelineText = "去左边",
        ttsText = "去左边",
        spellID = nil,
        spellIcon = nil,
        isSilent = false,
      },
    },
  },
}
