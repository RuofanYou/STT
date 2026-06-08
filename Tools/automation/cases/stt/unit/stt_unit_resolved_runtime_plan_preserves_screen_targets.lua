return {
  meta = {
    id = "stt_unit_resolved_runtime_plan_preserves_screen_targets",
    plugin = "stt",
    type = "unit",
    title = "团队+个人合并保留屏幕提醒点名路由",
  },
  events = {
    {
      type = "resolved_runtime_plan_targets",
      teamText = table.concat({
        "[方案]",
        "名称=测试",
        "",
        "[时间轴]",
        "{time:00:08.5}{所有人}{to:种子环形提醒#1}丢下种子",
        "{time:00:12}{所有人}{to:环形#1,计时条#1}多目标",
        "{time:00:16}{所有人}普通文本",
      }, "\n"),
      personalText = table.concat({
        "[时间轴]",
        "{time:00:30}{所有人}{spell:12345}个人覆盖",
      }, "\n"),
    },
  },
  expect = {
    equals = {
      events = {
        {
          time = 8.5,
          content = "{所有人}丢下种子",
          targets = { "种子环形提醒#1" },
        },
        {
          time = 12,
          content = "{所有人}多目标",
          targets = { "环形#1", "计时条#1" },
        },
        {
          time = 16,
          content = "{所有人}普通文本",
          targets = {},
        },
        {
          time = 30,
          content = "{所有人}{spell:12345}个人覆盖",
          targets = {},
        },
      },
    },
  },
}
