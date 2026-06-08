return {
  meta = {
    id = "stt_unit_friendly_nameplate_ui_texts",
    plugin = "stt",
    type = "unit",
    title = "姓名版页首次创建时按钮文本立即可见",
  },
  events = {
    { type = "friendly_nameplate_create_ui" },
  },
  expect = {
    equals = {
      enabled = false,
      runtimeApplied = false,
      serverNameNeedsReload = false,
      fontConfig = {
        fontSize = 12,
        fontOutline = "DEFAULT",
      },
      baseFonts = {
        normal = {
          path = "Fonts/FRIZQT__.TTF",
          size = 9,
          flags = "",
        },
        outlined = {
          path = "Fonts/FRIZQT__.TTF",
          size = 9,
          flags = "OUTLINE",
        },
      },
      nameplates = {},
      cvars = {},
      setCVarCalls = {},
      namePlateOptionValue = true,
      ui = {
        enableText = "友方姓名版优化: |cffff0000关|r",
        applyText = "立即应用",
        fontSizeText = "名字字号: 12",
        fontSizeValue = 12,
        fontOutlineLabel = "名字描边",
        fontOutlineText = "描边默认",
        toggles = {
          removeServerName = "去除服务器名: |cff00ff00开|r",
          nameOnly = "只显示名字: |cff00ff00开|r",
          useClassColor = "使用职业颜色: |cff00ff00开|r",
          autoInInstance = "仅副本内生效: |cff00ff00开|r",
        },
        descriptions = {
          "姓名版说明_去服务器名",
          "姓名版说明_只显示名字",
          "姓名版说明_仅副本内",
          "姓名版说明_字体",
        },
      },
      messages = {},
    },
  },
}
