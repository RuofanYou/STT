return {
  meta = {
    id = "stt_unit_interrupt_macro_warlock_spec",
    plugin = "stt",
    type = "unit",
    title = "鲁拉打断宏按术士专精选择技能",
  },
  init = {
    playerClassLocalized = "术士",
    playerClassToken = "WARLOCK",
    specIndex = 2,
    specID = 266,
    spellNameMap = {
      [19647] = "法术封锁",
      [119914] = "巨斧投掷",
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
      spellID = 119914,
      spellName = "巨斧投掷",
      icon = 219914,
      preview = "#showtooltip 巨斧投掷\n/cast [@boss2,harm,nodead] 巨斧投掷",
    },
  },
}
