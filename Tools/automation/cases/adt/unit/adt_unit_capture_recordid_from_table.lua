return {
  meta = { id = "adt_unit_capture_recordid_from_table", plugin = "adt", type = "unit", title = "StartPlacingNewDecor 表参数提取 recordID" },
  init = { db = {} },
  events = {
    { type = "start_new", entryID = { recordID = 9001 } },
  },
  expect = {
    equals = {
      lastPlacedRecordID = 9001,
      restartRecordIDs = {},
      startPlacedEntryIDs = { { recordID = 9001 } },
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = {},
    },
  },
}
