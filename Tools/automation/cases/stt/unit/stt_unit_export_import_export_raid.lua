return {
  meta = {
    id = "stt_unit_export_import_export_raid",
    plugin = "stt",
    type = "unit",
    title = "导出团本方案摘要",
  },
  init = {
    now = 1711180200,
    playerName = "Tester",
    exportImport = {
      semanticPlans = {
        ["raid:1:101"] = {
          name = "团队方案A",
          content = "[时间轴]\n{time:00:10} {所有人}集合",
          author = "Alice",
          createdTime = 1711100000,
          lastUpdateName = "Bob",
          lastUpdateTime = 1711180000,
        },
        ["dungeon:2:201"] = {
          name = "不会被导出的地下城",
          content = "STN_TRIGGER_V1\n{spell:1} | text | skip",
        },
      },
      personalPlans = {
        ["raid:1:101"] = {
          name = "个人方案A",
          content = "[时间轴]\n{time:00:12} {所有人}自保",
          author = "Alice",
          createdTime = 1711100100,
          lastUpdateName = "Alice",
          lastUpdateTime = 1711180100,
        },
      },
    },
  },
  events = {
    { type = "export_import_export", channel = "raid" },
  },
  expect = {
    equals = {
      ok = true,
      prefix = "STT:1:R:",
      hasText = true,
      summary = {
        typeCode = "R",
        typeName = "团本战术板",
        version = 1,
        exportTime = 1711180200,
        exporterName = "Tester",
        exporterVersion = "260323.25",
        planCount = 1,
        personalPlanCount = 1,
        settingsCount = 0,
      },
    },
  },
}
