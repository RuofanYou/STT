return {
  meta = {
    id = "stt_unit_interrupt_macro_warlock_non_demo",
    plugin = "stt",
    type = "unit",
    title = "非恶魔术鲁拉打断宏保持法术封锁",
  },
  init = {
    playerClassLocalized = "术士",
    playerClassToken = "WARLOCK",
    specIndex = 1,
    specID = 265,
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
      spellID = 19647,
      spellName = "法术封锁",
      icon = 119647,
      preview = "#showtooltip 法术封锁\n/cast [@boss2,harm,nodead] 法术封锁",
    },
  },
}
