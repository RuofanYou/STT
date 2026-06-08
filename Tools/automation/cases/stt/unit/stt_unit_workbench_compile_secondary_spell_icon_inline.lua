return {
  meta = {
    id = "stt_unit_workbench_compile_secondary_spell_icon_inline",
    plugin = "stt",
    type = "unit",
    title = "工作台首个技能保留行头图标，后续技能内联图标",
  },
  init = {
    spellInfoMap = {
      [1249265] = { name = "狂奔怒火", iconID = 555001 },
      [1251361] = { name = "熊形态", iconID = 555002 },
    },
  },
  events = {
    {
      type = "compile_workbench_rows_minimal",
      text = [[
{time:00:28} -[瑟维莱] {spell:1249265} {spell:1251361}
      ]],
    },
  },
  expect = {
    equals = {
      rowCount = 1,
      errorCount = 0,
      rows = {
        {
          rowType = "spell",
          line = 1,
          label = "-[瑟维莱] 狂奔怒火 |T555002:0:0:0:0:64:64:5:59:5:59|t 熊形态",
          hasAudience = false,
          spellID = 1249265,
        },
      },
      errors = {},
    },
  },
}
