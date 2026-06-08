return {
  meta = {
    id = "stt_unit_horizontal_skill_drop_items",
    plugin = "stt",
    type = "unit",
    title = "水平时间轴识别技能抽屉写入的 dur 并优先使用人员行",
  },
  init = {
    spellNameMap = {
      [363534] = "回溯",
      [372048] = "压迫怒吼",
    },
  },
  events = {
    {
      type = "build_horizontal_items",
      text = [[
[人员]
增辉=

[时间轴]
{time:00:05}{DKT1}{spell:363534,dur:4}<回溯>
{time:00:07}{增辉}{spell:372048}<压迫怒吼>
      ]],
    },
  },
  expect = {
    equals = {
      {
        key = "player:DKT1",
        kind = "player",
        displayText = "DKT1",
        items = {
          { time = 5, spellID = 363534, duration = 4, collisionCount = 0 },
        },
      },
      {
        key = "player:增辉",
        kind = "player",
        displayText = "增辉",
        items = {
          { time = 7, spellID = 372048, duration = nil, collisionCount = 0 },
        },
      },
    },
  },
}
