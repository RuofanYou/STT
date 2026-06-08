return {
  meta = {
    id = "stt_unit_realtime_board_bar_only_cells",
    plugin = "stt",
    type = "unit",
    title = "实时战术板为仅含 bar 的行生成可读单元格",
  },
  init = {
    spellInfoMap = {
      [1253031] = { name = "厄运种子", iconID = 6253031 },
      [222222] = { name = "无标签技能", iconID = 6222222 },
      [333333] = { name = "正文技能", iconID = 6333333 },
    },
  },
  events = {
    {
      type = "parse_and_build_board_timeline_events",
      text = table.concat({
        "{time:00:43.5} {所有人}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:00:50.0} {所有人}{bar:5,spell:222222}",
        "{time:00:55.0} {所有人}已有正文{bar:5,spell:333333,label:<不要覆盖>}",
        "{time:01:00.0} {所有人}{bar:5,spell:999999}",
      }, "\n"),
    },
  },
  expect = {
    equals = {
      {
        time = 43.5,
        text = "所有人 扔下种子",
        cells = {
          {
            who = "所有人",
            whoType = "condition",
            actionText = "扔下种子",
            spellHiddenActionText = "扔下种子",
            spellID = 1253031,
            spellIcon = 6253031,
          },
        },
      },
      {
        time = 50,
        text = "所有人 无标签技能",
        cells = {
          {
            who = "所有人",
            whoType = "condition",
            actionText = "无标签技能",
            spellHiddenActionText = "无标签技能",
            spellID = 222222,
            spellIcon = 6222222,
          },
        },
      },
      {
        time = 55,
        text = "所有人 已有正文",
        cells = {
          {
            who = "所有人",
            whoType = "condition",
            actionText = "已有正文",
            spellHiddenActionText = "已有正文",
            spellID = nil,
            spellIcon = nil,
          },
        },
      },
      {
        time = 60,
        text = "所有人 Spell999999",
        cells = {
          {
            who = "所有人",
            whoType = "condition",
            actionText = "Spell999999",
            spellHiddenActionText = "Spell999999",
            spellID = 999999,
            spellIcon = 1099999,
          },
        },
      },
    },
  },
}
