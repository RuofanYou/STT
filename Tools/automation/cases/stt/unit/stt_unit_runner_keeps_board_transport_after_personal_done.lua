return {
  meta = {
    id = "stt_unit_runner_keeps_board_transport_after_personal_done",
    plugin = "stt",
    type = "unit",
    title = "显示全部事件时个人轴播完后继续维持实时板传输时钟",
  },
  init = {
    playerName = "奶龙",
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
{time:00:07}{奶龙}螺旋
{time:00:09}{DKT}罩子
{time:00:11}{神牧}落地后化身
{time:01:54}{奶僧}还魂
      ]],
    },
    { type = "start_from_current", isTest = false },
    { type = "advance_time", elapsed = 8 },
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
