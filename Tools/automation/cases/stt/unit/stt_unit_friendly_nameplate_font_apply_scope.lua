return {
  meta = {
    id = "stt_unit_friendly_nameplate_font_apply_scope",
    plugin = "stt",
    type = "unit",
    title = "立即应用只放大友方玩家姓名板名字",
  },
  init = {
    cvars = {
      nameplateshowfriendlyPlayers = "0",
      nameplateShowOnlyNameForFriendlyPlayerUnits = "0",
      nameplateUseClassColorForFriendlyPlayerUnitNames = "0",
      UnitNameFriendlyPlayerName = "1",
    },
    nameplates = {
      { unit = "nameplate1", isFriend = true, isPlayer = true, font = { path = "Fonts/FRIZQT__.TTF", size = 9, flags = "" } },
      { unit = "nameplate2", isFriend = false, isPlayer = true, font = { path = "Fonts/FRIZQT__.TTF", size = 9, flags = "" } },
      { unit = "nameplate3", isFriend = true, isPlayer = false, font = { path = "Fonts/FRIZQT__.TTF", size = 9, flags = "" } },
    },
  },
  events = {
    { type = "friendly_nameplate_toggle" },
    { type = "friendly_nameplate_apply" },
  },
  expect = {
    equals = {
      enabled = true,
      runtimeApplied = true,
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
            size = 12,
            flags = "",
          },
        },
        {
          unit = "nameplate2",
          isFriend = false,
          isPlayer = true,
          font = {
            path = "Fonts/FRIZQT__.TTF",
            size = 9,
            flags = "",
          },
        },
        {
          unit = "nameplate3",
          isFriend = true,
          isPlayer = false,
          font = {
            path = "Fonts/FRIZQT__.TTF",
            size = 9,
            flags = "",
          },
        },
      },
      cvars = {
        nameplateshowfriendlyPlayers = "1",
        nameplateShowOnlyNameForFriendlyPlayerUnits = "1",
        nameplateUseClassColorForFriendlyPlayerUnitNames = "1",
        UnitNameFriendlyPlayerName = "1",
      },
      setCVarCalls = {
        { name = "nameplateshowfriendlyPlayers", value = "1" },
        { name = "nameplateShowOnlyNameForFriendlyPlayerUnits", value = "1" },
        { name = "nameplateUseClassColorForFriendlyPlayerUnitNames", value = "1" },
        { name = "UnitNameFriendlyPlayerName", value = "1" },
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
      },
    },
  },
}
