return {
  meta = {
    id = "stt_unit_visual_board_boss_icon",
    plugin = "stt",
    type = "unit",
    title = "视觉画板 Boss 纯图标使用主干鲁拉图标",
  },
  events = {
    {
      type = "visual_board_clock_boss_icon",
      render = true,
    },
  },
  expect = {
    equals = {
      encounterID = 3183,
      iconCount = 2,
      bossIconCount = 2,
      textureIconCount = 0,
      circleIconCount = 2,
      redCircleCount = 0,
      renderTexture = 7448204,
      renderMaskCount = 2,
    },
  },
}
