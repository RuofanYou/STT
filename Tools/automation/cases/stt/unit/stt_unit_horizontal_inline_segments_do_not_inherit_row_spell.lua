return {
  meta = {
    id = "stt_unit_horizontal_inline_segments_do_not_inherit_row_spell",
    plugin = "stt",
    type = "unit",
    title = "水平时间轴同一行多段不继承整行技能图标",
  },
  init = {
    spellNameMap = {
      [114052] = "升腾",
    },
  },
  events = {
    {
      type = "build_horizontal_items",
      text = [[
[时间轴]
{time:00:09} {JLM1}双拉水晶到脚下{增辉2}营救水晶到JLM脚下{奶萨1}{spell:114052}
      ]],
    },
  },
  expect = {
    equals = {
      {
        key = "player:JLM1",
        kind = "player",
        displayText = "JLM1",
        items = {
          { time = 9, duration = nil, collisionCount = 0 },
        },
      },
      {
        key = "player:增辉2",
        kind = "player",
        displayText = "增辉2",
        items = {
          { time = 9, duration = nil, collisionCount = 0 },
        },
      },
      {
        key = "player:奶萨1",
        kind = "player",
        displayText = "奶萨1",
        items = {
          { time = 9, spellID = 114052, duration = nil, collisionCount = 0 },
        },
      },
    },
  },
}
