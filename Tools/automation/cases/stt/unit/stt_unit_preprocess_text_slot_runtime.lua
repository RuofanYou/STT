return {
  meta = {
    id = "stt_unit_preprocess_text_slot_runtime",
    plugin = "stt",
    type = "unit",
    title = "PreprocessText 解析单括号槽位并按团队命中多值",
  },
  init = {
    playerName = "豆豆2",
    inRaid = true,
    raidRoster = {
      { name = "豆豆2", subgroup = 1 },
    },
  },
  events = {
    {
      type = "preprocess_text",
      text = [[
[人员]
奶德1 = 豆豆1,豆豆2

{time:00:03}{奶德1}繁荣
      ]],
    },
  },
  expect = {
    equals = {
      isValid = true,
      hasBlocks = true,
      bodyKind = "timeline",
      processedText = "{time:00:03}{豆豆2}繁荣\n      ",
      slotCount = 1,
      placeholderCount = 0,
      errorCount = 0,
    },
  },
}
