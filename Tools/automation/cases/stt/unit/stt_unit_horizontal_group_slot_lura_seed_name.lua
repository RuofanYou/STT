return {
  meta = {
    id = "stt_unit_horizontal_group_slot_lura_seed_name",
    plugin = "stt",
    type = "unit",
    title = "鲁拉种子多人员写法保留种子组名",
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
咕咕2=咕咕玩家
SS1=术士玩家
增辉1=增辉玩家
LR1=猎人玩家
AM1=暗牧玩家
增辉2=增辉玩家2
DKT1=死亡骑士坦克玩家
种子=咕咕2 SS1 增辉1 LR1 AM1 增辉2 DKT1

[时间轴]
{time:00:43.5} {种子}{bar:5,spell:1253031,label:<扔下种子>}
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
          { time = 43.5, spellID = 1253031, duration = 5, collisionCount = 0 },
        },
      },
    },
  },
}
