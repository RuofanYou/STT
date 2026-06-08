return {
  meta = {
    id = "stt_unit_horizontal_personnel_slot_resolves_row",
    plugin = "stt",
    type = "unit",
    title = "水平时间轴人员槽位解析为真实姓名行",
  },
  init = {
    spellNameMap = {
      [317920] = "反魔法领域",
    },
  },
  events = {
    {
      type = "build_horizontal_items",
      text = [[
[人员]
DKT1=队长冰豆

[时间轴]
{time:00:02}{DKT1}{spell:317920}<反魔法领域>
      ]],
    },
  },
  expect = {
    equals = {
      {
        key = "player:队长冰豆",
        kind = "player",
        displayText = "队长冰豆",
        items = {
          { time = 2, spellID = 317920, duration = nil, collisionCount = 0 },
        },
      },
    },
  },
}
