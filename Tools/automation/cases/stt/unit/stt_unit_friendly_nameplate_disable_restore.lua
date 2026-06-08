return {
  meta = {
    id = "stt_unit_friendly_nameplate_disable_restore",
    plugin = "stt",
    type = "unit",
    title = "关闭姓名版优化会恢复原始 CVar",
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
      nameplates = {},
      cvars = {
        nameplateshowfriendlyPlayers = "0",
        nameplateShowOnlyNameForFriendlyPlayerUnits = "0",
        nameplateUseClassColorForFriendlyPlayerUnitNames = "0",
        UnitNameFriendlyPlayerName = "1",
      },
      setCVarCalls = {
        { name = "nameplateshowfriendlyPlayers", value = "1" },
        { name = "nameplateShowOnlyNameForFriendlyPlayerUnits", value = "1" },
        { name = "nameplateUseClassColorForFriendlyPlayerUnitNames", value = "1" },
        { name = "UnitNameFriendlyPlayerName", value = "1" },
        { name = "nameplateshowfriendlyPlayers", value = "0" },
        { name = "nameplateShowOnlyNameForFriendlyPlayerUnits", value = "0" },
        { name = "nameplateUseClassColorForFriendlyPlayerUnitNames", value = "0" },
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
        "友方姓名版优化配置已禁用",
        "友方姓名版设置已恢复",
        "姓名版恢复说明_需重载",
      },
    },
  },
}
