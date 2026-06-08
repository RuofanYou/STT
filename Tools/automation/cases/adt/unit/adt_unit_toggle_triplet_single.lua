return {
  meta = { id = "adt_unit_toggle_triplet_single", plugin = "adt", type = "unit", title = "三件套单次切换" },
  init = {
    db = { EnableBatchPlace = false },
  },
  events = {
    { type = "toggle_triplet", key = "EnableBatchPlace", value = true },
  },
  expect = {
    equals = {
      lastPlacedRecordID = nil,
      restartRecordIDs = {},
      startPlacedEntryIDs = {},
      uiRefreshCount = 1,
      loadSettingsCount = 1,
      db = { EnableBatchPlace = true },
    },
  },
}
