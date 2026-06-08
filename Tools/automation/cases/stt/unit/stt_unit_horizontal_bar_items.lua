return {
  meta = {
    id = "stt_unit_horizontal_bar_items",
    plugin = "stt",
    type = "unit",
    title = "水平时间轴把 bar 显示为持续条",
  },
  init = {
    spellNameMap = {
      [1246709] = "碎裂残片",
    },
  },
  events = {
    {
      type = "build_horizontal_items",
      text = [[
[时间轴]
{time:00:08.2,p2} {所有人}{bar:38.5,tick:3.5,spell:1246709}
{time:00:30} {所有人}{bar:30,tick:3,spell:1246709,label:<奶骑吃黄色！>}
{time:02:10} {tank}抗这一脚{bar:8}
{time:03:00} {bar:15,tick:4}
      ]],
    },
  },
  expect = {
    equals = {
      {
        key = "condition:所有人",
        kind = "condition",
        displayText = "所有人",
        items = {
          { time = 8.2, spellID = 1246709, duration = 38.5, collisionCount = 0 },
          { time = 30, spellID = 1246709, duration = 30, collisionCount = 0 },
        },
      },
      {
        key = "condition:tank",
        kind = "condition",
        displayText = "tank",
        items = {
          { time = 130, duration = 8, collisionCount = 0 },
        },
      },
    },
  },
}
