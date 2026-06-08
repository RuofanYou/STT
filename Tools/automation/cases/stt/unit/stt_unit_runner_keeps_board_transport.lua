return {
  meta = {
    id = "stt_unit_runner_keeps_board_transport",
    plugin = "stt",
    type = "unit",
    title = "正式战斗中仅展示轴有内容时维持实时板传输时钟",
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
      text = [[
{time:00:05}{Bob}分散
      ]],
    },
    { type = "start_from_current", isTest = false },
    { type = "advance_time", elapsed = 0.05 },
    { type = "collect_runner_state" },
  },
  expect = {
    equals = {
      playing = true,
      currentTimePositive = true,
      totalTimePositive = true,
      isTest = false,
    },
  },
}
