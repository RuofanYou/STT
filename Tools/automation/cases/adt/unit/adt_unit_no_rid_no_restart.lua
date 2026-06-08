return {
  meta = { id = "adt_unit_no_rid_no_restart", plugin = "adt", type = "unit", title = "事件和 lastRID 都为空时不续放" },
  init = {
    db = { EnableBatchPlace = true },
    ctrlDown = true,
    decorByGUID = {},
  },
  events = {
    { type = "place_success", decorGUID = "guid-none", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    equals = {
      lastPlacedRecordID = nil,
      restartRecordIDs = {},
      startPlacedEntryIDs = {},
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = { EnableBatchPlace = true },
    },
  },
}
