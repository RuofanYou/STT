return {
  meta = { id = "adt_unit_event_dispatch_path", plugin = "adt", type = "unit", title = "通过 OnEvent 路径处理 PLACE_SUCCESS" },
  init = {
    db = { EnableBatchPlace = true },
    ctrlDown = true,
    lastPlacedRecordID = 90,
  },
  events = {
    { type = "event_dispatch", decorGUID = "guid-none", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    equals = {
      lastPlacedRecordID = 90,
      restartRecordIDs = { 90 },
      startPlacedEntryIDs = {},
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = { EnableBatchPlace = true },
    },
  },
}
