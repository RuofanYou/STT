return {
  meta = {
    id = "stt_unit_trigger_runner_event_rule_speaks_on_added",
    plugin = "stt",
    type = "unit",
    title = "TriggerRunner 的 event 规则在 ADDED 阶段立即播报且 FINISHED 不重复",
  },
  init = {
    selectedEncounterID = 3071,
    encounterTimelineEventStateMap = {
      [1601] = 2,
    },
  },
  events = {
    {
      type = "trigger_runner_start",
      text = table.concat({
        "[方案]",
        "名称=测试",
        "作者=STT",
        "",
        "[触发轴]",
        "{event:1601} {所有人}准备散开",
      }, "\n"),
    },
    {
      type = "trigger_runner_timeline_event_added",
      eventInfo = {
        id = 1601,
        source = 0,
      },
    },
    { type = "trigger_runner_collect_speak_calls" },
  },
  expect = {
    equals = {
      debugLines = {
        "TTS播放: 准备散开 (音量: 100)",
      },
      speakCalls = {
        {
          voiceID = 0,
          text = "准备散开",
          rate = 0,
          volume = 100,
          overlap = false,
        },
      },
    },
  },
}
