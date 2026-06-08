return {
  meta = {
    id = "stt_unit_friendly_nameplate_font_driver_refresh",
    plugin = "stt",
    type = "unit",
    title = "姓名板驱动刷新后仍会重新套用友方玩家字体",
  },
  init = {
    nameplates = {
      { unit = "nameplate1", isFriend = true, isPlayer = true, font = { path = "Fonts/FRIZQT__.TTF", size = 9, flags = "" } },
    },
  },
  events = {
    { type = "friendly_nameplate_toggle" },
    { type = "friendly_nameplate_apply" },
    { type = "friendly_nameplate_mutate_nameplate_font", index = 1, size = 9, flags = "" },
    { type = "friendly_nameplate_driver_event", name = "UpdateNamePlateSize" },
    { type = "friendly_nameplate_mutate_nameplate_font", index = 1, size = 9, flags = "" },
    { type = "friendly_nameplate_driver_event", name = "OnNamePlateAdded" },
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
