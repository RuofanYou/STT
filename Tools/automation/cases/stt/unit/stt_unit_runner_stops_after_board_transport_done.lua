return {
  meta = {
    id = "stt_unit_runner_stops_after_board_transport_done",
    plugin = "stt",
    type = "unit",
    title = "显示全部事件的展示轴结束后正式传输时钟正常停止",
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
    { type = "advance_time", elapsed = 120 },
    { type = "collect_runner_state" },
  },
  expect = {
    equals = {
      playing = false,
      currentTimePositive = true,
      totalTimePositive = true,
      isTest = false,
    },
  },
}
