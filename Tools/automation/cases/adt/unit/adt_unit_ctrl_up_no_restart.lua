return {
  meta = { id = "adt_unit_ctrl_up_no_restart", plugin = "adt", type = "unit", title = "Ctrl 松开时不续放" },
  init = {
    db = { EnableBatchPlace = true },
    ctrlDown = false,
    lastPlacedRecordID = 333,
    decorByGUID = {
      ["guid-C"] = { decorID = 444 },
    },
  },
  events = {
    { type = "place_success", decorGUID = "guid-C", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    equals = {
      lastPlacedRecordID = 333,
      restartRecordIDs = {},
      startPlacedEntryIDs = {},
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = { EnableBatchPlace = true },
    },
  },
}
