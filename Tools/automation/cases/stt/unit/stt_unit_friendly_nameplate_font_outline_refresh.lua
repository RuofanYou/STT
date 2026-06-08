return {
  meta = {
    id = "stt_unit_friendly_nameplate_font_outline_refresh",
    plugin = "stt",
    type = "unit",
    title = "描边配置变更会立即刷新当前可见友方玩家姓名板",
  },
  init = {
    nameplates = {
      { unit = "nameplate1", isFriend = true, isPlayer = true, font = { path = "Fonts/FRIZQT__.TTF", size = 9, flags = "" } },
    },
  },
  events = {
    { type = "friendly_nameplate_toggle" },
    { type = "friendly_nameplate_apply" },
    { type = "friendly_nameplate_set_option", key = "fontOutline", value = "OUTLINE" },
  },
  expect = {
    equals = {
      enabled = true,
      runtimeApplied = true,
      serverNameNeedsReload = true,
      fontConfig = {
        fontSize = 12,
        fontOutline = "OUTLINE",
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
            flags = "OUTLINE",
          },
        },
      },
      cvars = {
        nameplateshowfriendlyPlayers = "1",
        nameplateShowOnlyNameForFriendlyPlayerUnits = "1",
        nameplateUseClassColorForFriendlyPlayerUnitNames = "1",
      },
      setCVarCalls = {
        { name = "nameplateshowfriendlyPlayers", value = "1" },
        { name = "nameplateShowOnlyNameForFriendlyPlayerUnits", value = "1" },
        { name = "nameplateUseClassColorForFriendlyPlayerUnitNames", value = "1" },
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
