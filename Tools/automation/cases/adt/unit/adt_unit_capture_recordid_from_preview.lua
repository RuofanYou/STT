return {
  meta = { id = "adt_unit_capture_recordid_from_preview", plugin = "adt", type = "unit", title = "StartPlacingPreviewDecor 直接使用 recordID" },
  init = { db = {} },
  events = {
    { type = "start_preview", recordID = 777 },
  },
  expect = {
    equals = {
      lastPlacedRecordID = 777,
      restartRecordIDs = {},
      startPlacedEntryIDs = {},
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = {},
    },
  },
}
