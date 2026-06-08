return {
  meta = { id = "adt_unit_place_success_fallback_last_rid", plugin = "adt", type = "unit", title = "PLACE_SUCCESS 无事件 rid 时回退 lastPlacedRecordID" },
  init = {
    db = { EnableBatchPlace = true },
    ctrlDown = true,
    lastPlacedRecordID = 333,
    decorByGUID = {},
  },
  events = {
    { type = "place_success", decorGUID = "guid-miss", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    equals = {
      lastPlacedRecordID = 333,
      restartRecordIDs = { 333 },
      startPlacedEntryIDs = {},
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = { EnableBatchPlace = true },
    },
  },
}
