return {
  meta = {
    id = "stt_unit_inline_sound_only_event",
    plugin = "stt",
    type = "unit",
    title = "BuildTimelineEvents 保留纯音效事件",
  },
  init = {},
  events = {
    {
      type = "parse_and_build_timeline_events_screen",
      text = "{time:00:10}{所有人}{@ding.ogg}",
    },
  },
  expect = {
    equals = {
      {
        time = 10,
        showTime = 7,
        text = "",
        timelineText = "",
        ttsText = "",
        isSilent = true,
        inlineSound = {
          path = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\ding.ogg",
          label = "ding.ogg",
        },
      },
    },
  },
}
