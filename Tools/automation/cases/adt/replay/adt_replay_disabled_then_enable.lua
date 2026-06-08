return {
  meta = { id = "adt_replay_disabled_then_enable", plugin = "adt", type = "replay", title = "开关关闭后开启再续放" },
  init = {
    db = { EnableBatchPlace = false },
    ctrlDown = true,
    lastPlacedRecordID = 5,
    decorByGUID = {
      ["g1"] = { decorID = 101 },
      ["g2"] = { decorID = 102 },
    },
  },
  events = {
    { type = "place_success", decorGUID = "g1", size = 1, isNew = true, isPreview = false },
    { type = "set_db", key = "EnableBatchPlace", value = true },
    { type = "place_success", decorGUID = "g2", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    baseline = "adt_replay_disabled_then_enable.golden.lua",
  },
}
