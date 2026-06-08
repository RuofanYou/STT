return {
  meta = {
    id = "stt_unit_member_runtime_only_parse_st_note",
    plugin = "stt",
    type = "unit",
    title = "团员默认 runtime 不加载完整编辑器仍可解析语音播报",
  },
  init = {
    playerName = "测试团员",
    db = {
      dataSource = "STN",
      ttsEnabled = true,
      semanticTimeline = {
        runtimeEnabled = true,
        enabled = false,
        resolveSource = "team_plus_personal",
      },
    },
    note = {
      default = {
        id = "default",
        name = "团长同步方案",
        content = table.concat({
          "[方案]",
          "名称=团长同步方案",
          "",
          "[人员]",
          "成员=测试团员",
          "",
          "[时间轴]",
          "{time:00:03}{{成员}}{spell:111}团队集合",
          "{time:00:08}{所有人}分散",
        }, "\n"),
      },
      personal = {
        id = "personal",
        name = "个人方案",
        content = table.concat({
          "[时间轴]",
          "{time:00:05}{测试团员}{spell:111}个人集合",
        }, "\n"),
      },
    },
  },
  events = {
    {
      type = "runtime_only_parse_st_note",
      teamText = table.concat({
        "[方案]",
        "名称=团长同步方案",
        "",
        "[人员]",
        "成员=测试团员",
        "",
        "[时间轴]",
        "{time:00:03}{{成员}}{spell:111}团队集合",
        "{time:00:08}{所有人}分散",
      }, "\n"),
      personalText = table.concat({
        "[时间轴]",
        "{time:00:05}{测试团员}{spell:111}个人集合",
      }, "\n"),
    },
  },
  expect = {
    equals = {
      hasRuntime = true,
      fullEditorLoaded = false,
      parsed = {
        { time = 5, text = "Spell111个人集合" },
        { time = 8, text = "分散" },
      },
    },
  },
}
