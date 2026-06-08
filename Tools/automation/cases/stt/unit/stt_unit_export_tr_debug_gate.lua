return {
  meta = {
    id = "stt_unit_export_tr_debug_gate",
    plugin = "stt",
    type = "unit",
    title = "STT 到 TR 导出仅在 debug 模式启用",
  },
  init = {},
  events = {
    {
      type = "export_tr",
      text = "[时间轴]\n{time:00:10} {瑟瑟}{ct:5}{@ding.ogg}{spell:12345}",
      options = { encounterID = 3182 },
    },
  },
  expect = {
    equals = {
      ok = false,
      err = "debug_only",
    },
  },
}
