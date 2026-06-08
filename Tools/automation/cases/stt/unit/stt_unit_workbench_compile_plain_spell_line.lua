return {
  meta = {
    id = "stt_unit_workbench_compile_plain_spell_line",
    plugin = "stt",
    type = "unit",
    title = "工作台编译不再把纯时间+技能行误报为时间格式无效",
  },
  init = {},
  events = {
    {
      type = "compile_workbench_rows_minimal",
      text = [[
{time:00:04} {spell:1249251}
{time:00:10}{所有人}集合
      ]],
    },
  },
  expect = {
    equals = {
      rowCount = 2,
      errorCount = 0,
      rows = {
        {
          rowType = "spell",
          line = 1,
          label = "Spell1249251",
          hasAudience = false,
          spellID = 1249251,
        },
        {
          rowType = "text",
          line = 2,
          label = "{所有人}集合",
          hasAudience = true,
          spellID = nil,
        },
      },
      errors = {},
    },
  },
}
