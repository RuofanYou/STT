return {
  meta = {
    id = "stt_unit_preprocess_text_pure_mrt",
    plugin = "stt",
    type = "unit",
    title = "PreprocessText 放行纯 MRT 时间轴",
  },
  init = {},
  events = {
    {
      type = "preprocess_text",
      text = [[
{time:00:03}{所有人}集合
{time:00:08}{测试坦克}分散
      ]],
    },
  },
  expect = {
    equals = {
      isValid = true,
      hasBlocks = false,
      bodyKind = "timeline",
      processedText = "{time:00:03}{所有人}集合\n{time:00:08}{测试坦克}分散\n      ",
      slotCount = 0,
      placeholderCount = 0,
      errorCount = 0,
    },
  },
}
