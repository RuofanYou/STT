return {
  meta = {
    id = "stt_unit_horizontal_group_slot_direct_member_stays_player",
    plugin = "stt",
    type = "unit",
    title = "水平时间轴直接使用成员槽位仍显示真实人员",
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
DZ1=瑟维雅
DZ2=瑟维成
种子=DZ1 DZ2

[时间轴]
{time:00:02}{DZ1}{spell:317920}<反魔法领域>
      ]],
    },
  },
  expect = {
    equals = {
      {
        key = "player:瑟维雅",
        kind = "player",
        displayText = "瑟维雅",
        items = {
          { time = 2, spellID = 317920, duration = nil, collisionCount = 0 },
        },
      },
    },
  },
}
