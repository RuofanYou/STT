return {
  meta = { id = "stt_unit_voice_filters_personal_plain", plugin = "stt", type = "unit", title = "个人方案无受众标记仍对自己生效" },
  init = {
    db = {
      filterAll = false,
    },
  },
  events = {
    {
      type = "should_trigger",
      event = {
        isPersonal = true,
        hasAudience = false,
        segments = {
          { text = "个人提醒", condition = "", players = nil },
        },
      },
    },
  },
  expect = {
    equals = true,
  },
}
