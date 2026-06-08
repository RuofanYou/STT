return {
  meta = {
    id = "stt_unit_friendly_nameplate_apply_now",
    plugin = "stt",
    type = "unit",
    title = "立即应用会写入三类 CVar 并刷新当前场景",
  },
  init = {
    cvars = {
      nameplateshowfriendlyPlayers = "0",
      nameplateShowOnlyNameForFriendlyPlayerUnits = "0",
      nameplateUseClassColorForFriendlyPlayerUnitNames = "0",
      UnitNameFriendlyPlayerName = "1",
    },
    instanceType = "none",
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
      nameplates = {},
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
