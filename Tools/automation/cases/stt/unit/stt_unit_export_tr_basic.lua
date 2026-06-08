return {
  meta = {
    id = "stt_unit_export_tr_basic",
    plugin = "stt",
    type = "unit",
    title = "debug 模式下导出基础 STT 时间轴为 TR 字符串",
  },
  init = {
    db = {
      debugMode = true,
    },
  },
  events = {
    {
      type = "export_tr",
      text = "[时间轴]\n{time:00:10} {瑟瑟}{ct:5}{@ding.ogg}{spell:12345}",
      options = { encounterID = 3182 },
    },
  },
  expect = {
    equals = {
      ok = true,
      prefix = "!TR:",
      decoded = {
        eventCount = 1,
        encounterID = 3182,
        triggerTime = 10,
        loadType = "NAME",
        loadName = "瑟瑟",
        displayType = "SPELL",
        spellID = 12345,
        countdownEnabled = true,
        countdownStart = 5,
        soundEnabled = true,
        soundFile = "ding.ogg",
      },
    },
  },
}
