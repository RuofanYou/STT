return {
  meta = { id = "stt_unit_parse_text_ignores_comments", plugin = "stt", type = "unit", title = "ParseTimelineText 忽略无时间注释行" },
  init = {},
  events = {
    { type = "parse_text", text = "时间轴\n{time:00:05} 标签:{所有人}准备战斗\n战斗结束\n{time:00:10} 全员躲旋风" },
  },
  expect = {
    equals = {
      {
        time = 5,
        line = 2,
        content = "标签:{所有人}准备战斗",
        displayText = "标签:{所有人}准备战斗",
        hasAudience = true,
        segments = {
          {
            text = "标签:",
            condition = "",
            cellText = "标签:",
            rawText = "标签:",
            spellTokens = {},
          },
          {
            text = "准备战斗",
            condition = "所有人",
            cellText = "准备战斗",
            rawText = "准备战斗",
            spellTokens = {},
          },
        },
      },
      {
        time = 10,
        line = 4,
        content = "全员躲旋风",
        displayText = "全员躲旋风",
        hasAudience = false,
        segments = {
          {
            text = "全员躲旋风",
            condition = "",
            cellText = "全员躲旋风",
            rawText = "全员躲旋风",
            spellTokens = {},
          },
        },
      },
    },
  },
}
