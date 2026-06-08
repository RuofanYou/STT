return {
  meta = {
    id = "stt_unit_interrupt_macro_hunter_non_survival",
    plugin = "stt",
    type = "unit",
    title = "非生存猎鲁拉打断宏保持反制射击",
  },
  init = {
    playerClassLocalized = "猎人",
    playerClassToken = "HUNTER",
    specIndex = 1,
    specID = 253,
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
      spellID = 147362,
      spellName = "反制射击",
      icon = 247362,
      preview = "#showtooltip 反制射击\n/cast [@boss2,harm,nodead] 反制射击",
    },
  },
}
