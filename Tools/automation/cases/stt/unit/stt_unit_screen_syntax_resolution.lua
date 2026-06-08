return {
  meta = {
    id = "stt_unit_screen_syntax_resolution",
    plugin = "stt",
    type = "unit",
    title = "屏幕提醒语法解析",
  },
  init = {
    spellInfoMap = {
      [589] = { iconID = 135898 },
    },
  },
  events = {
    {
      type = "resolve_screen_syntax",
      text = "<静默>{所有人}集合 {rt1} ~~只朗读~~",
      spellID = 589,
    },
  },
  expect = {
    equals = {
      text = "集合 |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t 只朗读",
      spellIcon = 135898,
    },
  },
}
