return {
  meta = { id = "adt_unit_place_success_event_rid_priority", plugin = "adt", type = "unit", title = "PLACE_SUCCESS 优先使用事件反查 recordID" },
  init = {
    db = { EnableBatchPlace = true },
    ctrlDown = true,
    lastPlacedRecordID = 200,
    decorByGUID = {
      ["guid-A"] = { decorID = 101 },
    },
  },
  events = {
    { type = "place_success", decorGUID = "guid-A", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    equals = {
      lastPlacedRecordID = 200,
      restartRecordIDs = { 101 },
      startPlacedEntryIDs = {},
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = { EnableBatchPlace = true },
    },
  },
}
