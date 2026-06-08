return {
  meta = {
    id = "stt_unit_friendly_nameplate_font_restore",
    plugin = "stt",
    type = "unit",
    title = "关闭姓名版优化会恢复友方玩家姓名板原始字体",
  },
  init = {
    nameplates = {
      { unit = "nameplate1", isFriend = true, isPlayer = true, font = { path = "Fonts/FRIZQT__.TTF", size = 9, flags = "OUTLINE" } },
      { unit = "nameplate2", isFriend = false, isPlayer = true, font = { path = "Fonts/FRIZQT__.TTF", size = 10, flags = "" } },
    },
  },
  events = {
    { type = "friendly_nameplate_toggle" },
    { type = "friendly_nameplate_apply" },
    { type = "friendly_nameplate_toggle" },
  },
  expect = {
    equals = {
      enabled = false,
      runtimeApplied = false,
      serverNameNeedsReload = true,
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
      nameplates = {
        {
          unit = "nameplate1",
          isFriend = true,
          isPlayer = true,
          font = {
            path = "Fonts/FRIZQT__.TTF",
            size = 9,
            flags = "OUTLINE",
          },
        },
        {
          unit = "nameplate2",
          isFriend = false,
          isPlayer = true,
          font = {
            path = "Fonts/FRIZQT__.TTF",
            size = 10,
            flags = "",
          },
        },
      },
      cvars = {
        nameplateshowfriendlyPlayers = nil,
        nameplateShowOnlyNameForFriendlyPlayerUnits = nil,
        nameplateUseClassColorForFriendlyPlayerUnitNames = nil,
      },
      setCVarCalls = {
        { name = "nameplateshowfriendlyPlayers", value = "1" },
        { name = "nameplateShowOnlyNameForFriendlyPlayerUnits", value = "1" },
        { name = "nameplateUseClassColorForFriendlyPlayerUnitNames", value = "1" },
        { name = "nameplateshowfriendlyPlayers", value = nil },
        { name = "nameplateShowOnlyNameForFriendlyPlayerUnits", value = nil },
        { name = "nameplateUseClassColorForFriendlyPlayerUnitNames", value = nil },
      },
      namePlateOptionValue = nil,
      ui = {
        enableText = "",
        applyText = "",
        fontSizeText = "",
        fontSizeValue = nil,
        fontOutlineLabel = "",
        fontOutlineText = "",
        toggles = {},
        descriptions = {},
      },
      messages = {
        "友方姓名版优化配置已启用",
        "友方姓名版优化已应用",
        "友方姓名版优化配置已禁用",
        "友方姓名版设置已恢复",
        "姓名版恢复说明_需重载",
      },
    },
  },
}
