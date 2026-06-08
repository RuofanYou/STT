return {
  meta = { id = "adt_unit_toggle_triplet_multi", plugin = "adt", type = "unit", title = "三件套多次切换" },
  init = {
    db = { EnableBatchPlace = true, EnableDupe = true, EnableCopy = false },
  },
  events = {
    { type = "toggle_triplet", key = "EnableDupe", value = false },
    { type = "toggle_triplet", key = "EnableCopy", value = true },
  },
  expect = {
    equals = {
      lastPlacedRecordID = nil,
      restartRecordIDs = {},
      startPlacedEntryIDs = {},
      uiRefreshCount = 2,
      loadSettingsCount = 2,
      db = { EnableBatchPlace = true, EnableDupe = false, EnableCopy = true },
    },
  },
}
