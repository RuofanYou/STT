return {
  meta = {
    id = "stt_unit_horizontal_group_slot_keeps_group_row",
    plugin = "stt",
    type = "unit",
    title = "水平时间轴多人员槽位显示组名",
  },
  init = {
    spellNameMap = {
      [1253031] = "扔下种子",
    },
  },
  events = {
    {
      type = "build_horizontal_items",
      text = [[
[人员]
DZ1=瑟维雅
DZ2=瑟维成
种子=DZ1 DZ2

[时间轴]
{time:00:05}{种子}{bar:5,spell:1253031,label:<扔下种子>}
      ]],
    },
  },
  expect = {
    equals = {
      {
        key = "player:种子",
        kind = "player",
        displayText = "种子",
        items = {
          { time = 5, spellID = 1253031, duration = 5, collisionCount = 0 },
        },
      },
    },
  },
}
