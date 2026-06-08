return {
  meta = {
    id = "stt_unit_horizontal_slot_visual_hint",
    plugin = "stt",
    type = "unit",
    title = "水平时间轴用人员槽位代号补离线职业色与专精图标",
  },
  events = {
    {
      type = "build_horizontal_per_row",
      text = [[
[人员]
奶德1=Animagus
小德1=吉田步美
åÅZST1=误导者
奶龙1=大龙秋秋
增辉2=大龙秋秋
LR1=带刀蝴蝶
DK2=凭本事装逼
DH2=纳闷住
FS2=法术回响
SS1=暗影线

[时间轴]
{time:00:03} {奶德1}繁荣
{time:00:04} {小德1}战复
{time:00:05} {åÅZST1}不识别
{time:00:06} {ZST1}直接槽位名
{time:00:07} {DH1}直接职业槽位
{time:00:08} {DK1}直接职业槽位
{time:00:09} {增辉2}同名未使用槽位不冲突
      ]],
    },
  },
  expect = {
    equals = {
      {
        key = "player:Animagus",
        kind = "player",
        displayText = "Animagus",
        classFile = "DRUID",
        specID = 105,
        specIcon = 200105,
        playerInfo = {
          name = "Animagus",
          classFile = "DRUID",
          specID = 105,
          specIcon = 200105,
        },
      },
      {
        key = "player:吉田步美",
        kind = "player",
        displayText = "吉田步美",
        classFile = "DRUID",
        playerInfo = {
          name = "吉田步美",
          classFile = "DRUID",
        },
      },
      {
        key = "player:误导者",
        kind = "player",
        displayText = "误导者",
        playerInfo = {
          name = "误导者",
        },
      },
      {
        key = "player:ZST1",
        kind = "player",
        displayText = "ZST1",
        classFile = "WARRIOR",
        specID = 73,
        specIcon = 200073,
        playerInfo = {
          name = "ZST1",
          classFile = "WARRIOR",
          specID = 73,
          specIcon = 200073,
        },
      },
      {
        key = "player:DH1",
        kind = "player",
        displayText = "DH1",
        classFile = "DEMONHUNTER",
        playerInfo = {
          name = "DH1",
          classFile = "DEMONHUNTER",
        },
      },
      {
        key = "player:DK1",
        kind = "player",
        displayText = "DK1",
        classFile = "DEATHKNIGHT",
        playerInfo = {
          name = "DK1",
          classFile = "DEATHKNIGHT",
        },
      },
      {
        key = "player:大龙秋秋",
        kind = "player",
        displayText = "大龙秋秋",
        classFile = "EVOKER",
        specID = 1473,
        specIcon = 201473,
        playerInfo = {
          name = "大龙秋秋",
          classFile = "EVOKER",
          specID = 1473,
          specIcon = 201473,
        },
      },
      {
        key = "player:带刀蝴蝶",
        kind = "player",
        displayText = "带刀蝴蝶",
        classFile = "HUNTER",
        playerInfo = {
          name = "带刀蝴蝶",
          classFile = "HUNTER",
        },
      },
      {
        key = "player:凭本事装逼",
        kind = "player",
        displayText = "凭本事装逼",
        classFile = "DEATHKNIGHT",
        playerInfo = {
          name = "凭本事装逼",
          classFile = "DEATHKNIGHT",
        },
      },
      {
        key = "player:纳闷住",
        kind = "player",
        displayText = "纳闷住",
        classFile = "DEMONHUNTER",
        playerInfo = {
          name = "纳闷住",
          classFile = "DEMONHUNTER",
        },
      },
      {
        key = "player:法术回响",
        kind = "player",
        displayText = "法术回响",
        classFile = "MAGE",
        playerInfo = {
          name = "法术回响",
          classFile = "MAGE",
        },
      },
      {
        key = "player:暗影线",
        kind = "player",
        displayText = "暗影线",
        classFile = "WARLOCK",
        playerInfo = {
          name = "暗影线",
          classFile = "WARLOCK",
        },
      },
    },
  },
}
