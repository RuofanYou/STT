return {
  meta = {
    id = "stt_unit_friendly_nameplate_toggle_config_only",
    plugin = "stt",
    type = "unit",
    title = "姓名版总开关只改配置，不在野外立即生效",
  },
  init = {
    cvars = {
      nameplateshowfriendlyPlayers = "0",
      nameplateShowOnlyNameForFriendlyPlayerUnits = "0",
      nameplateUseClassColorForFriendlyPlayerUnitNames = "0",
    },
    instanceType = "none",
  },
  events = {
    { type = "friendly_nameplate_toggle" },
    { type = "friendly_nameplate_collect" },
  },
  expect = {
    equals = {
      enabled = true,
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
      cvars = {
        nameplateshowfriendlyPlayers = "0",
        nameplateShowOnlyNameForFriendlyPlayerUnits = "0",
        nameplateUseClassColorForFriendlyPlayerUnitNames = "0",
      },
      setCVarCalls = {},
      namePlateOptionValue = true,
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
      },
    },
  },
}
