return {
  meta = {
    id = "stt_unit_trigger_runner_event_rule_not_duplicated_on_finished",
    plugin = "stt",
    type = "unit",
    title = "TriggerRunner 的 event 规则在 FINISHED 阶段不会重复播报",
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
    { type = "trigger_runner_timeline_event_state_changed", eventID = 1601 },
  },
  expect = {
    equals = {
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
