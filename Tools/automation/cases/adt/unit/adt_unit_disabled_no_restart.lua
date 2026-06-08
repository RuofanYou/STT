return {
  meta = { id = "adt_unit_disabled_no_restart", plugin = "adt", type = "unit", title = "开关关闭时不续放" },
  init = {
    db = { EnableBatchPlace = false },
    ctrlDown = true,
    lastPlacedRecordID = 333,
    decorByGUID = {
      ["guid-B"] = { decorID = 222 },
    },
  },
  events = {
    { type = "place_success", decorGUID = "guid-B", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    equals = {
      lastPlacedRecordID = 333,
      restartRecordIDs = {},
      startPlacedEntryIDs = {},
      uiRefreshCount = 0,
      loadSettingsCount = 0,
      db = { EnableBatchPlace = false },
    },
  },
}
