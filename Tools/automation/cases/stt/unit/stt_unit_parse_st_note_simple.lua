return {
  meta = { id = "stt_unit_parse_st_note_simple", plugin = "stt", type = "unit", title = "ParseSTNote 解析默认方案" },
  init = {
    playerName = "测试坦克",
    note = {
      default = {
        id = "default",
        content = [[
[人员]
坦克 = 测试坦克

{time:00:03}{坦克}集合
{time:00:08}{所有人}分散
        ]],
      },
    },
  },
  events = {
    { type = "parse_st_note" },
  },
  expect = {
    equals = {
      { time = 3, text = "集合" },
      { time = 8, text = "分散" },
    },
  },
}
