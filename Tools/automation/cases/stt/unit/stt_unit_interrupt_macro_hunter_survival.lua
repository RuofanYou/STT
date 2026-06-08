return {
  meta = {
    id = "stt_unit_interrupt_macro_hunter_survival",
    plugin = "stt",
    type = "unit",
    title = "生存猎鲁拉打断宏使用压制",
  },
  init = {
    playerClassLocalized = "猎人",
    playerClassToken = "HUNTER",
    specIndex = 3,
    specID = 255,
    spellNameMap = {
      [147362] = "反制射击",
      [187707] = "压制",
    },
    db = {
      interruptRotation = {
        midnightMacroGroup = 1,
        midnightMacroKick = 1,
      },
    },
  },
  events = {
    { type = "interrupt_macro_preview" },
  },
  expect = {
    equals = {
      spellID = 187707,
      spellName = "压制",
      icon = 287707,
      preview = "#showtooltip 压制\n/cast [@boss2,harm,nodead] 压制",
    },
  },
}
