return {
  meta = { id = "stt_unit_parse_text_unsupported_opts", plugin = "stt", type = "unit", title = "ParseTimelineText 识别不支持参数" },
  init = {},
  events = {
    { type = "parse_text", text = "{time:10,optX,optY}点名" },
  },
  expect = {
    equals = {},
  },
}
