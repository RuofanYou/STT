return {
  meta = {
    id = "stt_unit_visual_board_midnightfall_template",
    plugin = "stt",
    type = "unit",
    title = "视觉画板能生成至暗之夜 v2 示意图并保持黄色圈低于人员层",
  },
  events = {
    {
      type = "visual_board_midnightfall_template",
      encounterID = 3183,
      render = true,
    },
  },
  expect = {
    equals = {
      encounterID = 3183,
      background = "至暗之夜降临",
      elementCount = 72,
      counts = {
        marker = 5,
        person = 20,
        shape = 26,
        text = 21,
      },
      textureIcons = 0,
      spellIcons = 0,
      markerIcons = 5,
      shapeCircles = 12,
      shapeArrows = 12,
      lowYellowCircles = 12,
      titleText = "P2第四轮分散示意图",
      doorText = "门口",
      render = {
        textures = 45,
        fontStrings = 22,
        lines = 0,
        firstTexture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
      },
    },
  },
}
