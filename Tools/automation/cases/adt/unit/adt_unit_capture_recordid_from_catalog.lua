return {
  meta = { id = "adt_unit_capture_recordid_from_catalog", plugin = "adt", type = "unit", title = "StartPlacingNewDecor 数值参数反查 recordID" },
  init = {
    db = {},
    catalogByEntryID = {
      [42] = { recordID = 5002 },
    },
  },
  events = {
    { type = "start_new", entryID = 42 },
  },
  expect = {
    equals = {
      lastPlacedRecordID = 5002,
      restartRecordIDs = {},
      startPlacedEntryIDs = { 42 },
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = {},
    },
  },
}
