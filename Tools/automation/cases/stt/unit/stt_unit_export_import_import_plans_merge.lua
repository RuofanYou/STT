return {
  meta = {
    id = "stt_unit_export_import_import_plans_merge",
    plugin = "stt",
    type = "unit",
    title = "团本方案合并导入",
  },
  init = {
    now = 1711180200,
    playerName = "Tester",
    exportImport = {
      semanticPlans = {
        ["raid:1:101"] = {
          name = "新团队方案",
          content = "[时间轴]\n{time:00:10} {所有人}集合",
          author = "Alice",
          createdTime = 1711100000,
          lastUpdateName = "Bob",
          lastUpdateTime = 1711180000,
        },
      },
      personalPlans = {
        ["raid:1:101"] = {
          name = "新个人方案",
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
    {
      type = "export_import_reseed",
      state = {
        semanticPlans = {
          ["raid:1:101"] = {
            name = "旧团队方案",
            content = "[时间轴]\n{time:00:05} {所有人}旧内容",
          },
          ["raid:1:102"] = {
            name = "保留团队方案",
            content = "[时间轴]\n{time:00:20} {所有人}保留",
          },
        },
        personalPlans = {
          ["raid:1:101"] = {
            name = "旧个人方案",
            content = "[时间轴]\n{time:00:08} {所有人}旧个人",
          },
        },
      },
    },
    {
      type = "export_import_import",
      mode = "merge",
      source = "last",
      collectState = {
        instanceType = "raid",
      },
    },
  },
  expect = {
    equals = {
      ok = true,
      message = "导入完成：已写入 2 项，跳过 0 项",
      reloadUICount = 0,
      snapshot = {
        semantic = {
          ["raid:1:101"] = {
            name = "新团队方案",
            content = "[时间轴]\n{time:00:10} {所有人}集合",
            author = "Alice",
            createdTime = 1711100000,
            lastUpdateName = "Bob",
            lastUpdateTime = 1711180000,
            kind = "semantic_boss",
          },
          ["raid:1:102"] = {
            name = "保留团队方案",
            content = "[时间轴]\n{time:00:20} {所有人}保留",
            author = "Tester",
            createdTime = 0,
            lastUpdateName = "Tester",
            lastUpdateTime = 0,
            kind = "semantic_boss",
          },
        },
        personal = {
          ["raid:1:101"] = {
            name = "新个人方案",
            content = "[时间轴]\n{time:00:12} {所有人}自保",
            author = "Alice",
            createdTime = 1711100100,
            lastUpdateName = "Alice",
            lastUpdateTime = 1711180100,
            kind = "personal_boss",
          },
        },
        settings = {},
      },
    },
  },
}
