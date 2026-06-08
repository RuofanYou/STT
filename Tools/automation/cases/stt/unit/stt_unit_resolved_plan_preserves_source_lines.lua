return {
  meta = {
    id = "stt_unit_resolved_plan_preserves_source_lines",
    plugin = "stt",
    type = "unit",
    title = "团队+个人预览裁剪不改写原始编辑行号",
  },
  events = {
    {
      type = "compile_resolved_plan_content",
      teamText = table.concat({
        "[方案]",
        "名称=测试",
        "",
        "[人员]",
        "",
        "[时间轴]",
        "{time:00:10} {所有人}{spell:111}团队A",
        "{time:00:20} {所有人}{spell:222}团队B",
        "{time:00:25} {所有人}{spell:111}团队C{治疗}{spell:333}团队D",
      }, "\n"),
      personalText = table.concat({
        "[时间轴]",
        "{time:00:30} {所有人}{spell:111}个人A",
      }, "\n"),
    },
  },
  expect = {
    equals = {
      rowCount = 3,
      rows = {
        {
          editorTab = "team",
          spellID = 222,
          sortIndex = 8,
          line = 8,
        },
        {
          editorTab = "team",
          spellID = 333,
          sortIndex = 9,
          line = 9,
        },
        {
          editorTab = "personal",
          spellID = 111,
          sortIndex = 2,
          line = 2,
        },
      },
    },
  },
}
