return {
  meta = {
    id = "stt_unit_member_default_runtime_outputs",
    plugin = "stt",
    type = "unit",
    title = "新团员默认 runtime 可播报倒数分段条并把完整展示轴交给实时战术板",
  },
  init = {
    playerName = "Alice",
    db = {
      dataSource = "MRT",
      useRaidNote = true,
      useSelfNote = false,
      realtimeBoard = {
        enabled = true,
        showAllEvents = true,
      },
    },
  },
  events = {
    {
      type = "set_source_text",
      source = "MRT",
      text = table.concat({
        "{time:00:05}{ct:3}{bar:4,tick:1,spell:111}{Alice}个人集合",
        "{time:00:08}{Bob}只给 Bob",
        "{time:00:10}{所有人}全团分散",
      }, "\n"),
    },
    { type = "start_from_current", isTest = false },
    { type = "advance_time", elapsed = 0.05 },
    { type = "advance_time", elapsed = 4.95 },
    { type = "collect_member_runtime_outputs" },
  },
  expect = {
    equals = {
      defaults = {
        ttsEnabled = true,
        countdownEnabled = true,
        barEnabled = true,
        semanticRuntimeEnabled = true,
        semanticEditorEnabled = false,
      },
      loaded = {
        hasRuntime = true,
        fullEditorLoaded = false,
      },
      speakCalls = {
        {
          voiceID = 0,
          text = "个人集合",
          rate = 0,
          volume = 100,
          overlap = false,
        },
      },
      soundCallCount = 3,
      barCalls = {
        {
          duration = 4,
          eventID = 1,
          fallbackLabel = "个人集合",
          labelOverride = nil,
          phase = nil,
          spellID = 111,
          startTime = 5,
          tickInterval = 1,
        },
      },
      realtimeBoardStarts = {
        {
          count = 3,
          hasStartTime = true,
          isTest = false,
          staticPreview = false,
          rows = {
            { time = 5, text = "Alice 个人集合" },
            { time = 8, text = "Bob 只给 Bob" },
            { time = 10, text = "所有人 全团分散" },
          },
        },
      },
    },
  },
}
