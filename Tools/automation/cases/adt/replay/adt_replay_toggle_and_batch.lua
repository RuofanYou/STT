return {
  meta = { id = "adt_replay_toggle_and_batch", plugin = "adt", type = "replay", title = "开关三件套与批量放置联动回放" },
  init = {
    db = { EnableBatchPlace = false, EnableCopy = false },
    ctrlDown = true,
    lastPlacedRecordID = 1000,
    decorByGUID = {
      ["g1"] = { decorID = 6001 },
    },
  },
  events = {
    { type = "toggle_triplet", key = "EnableBatchPlace", value = true },
    { type = "toggle_triplet", key = "EnableCopy", value = true },
    { type = "place_success", decorGUID = "g1", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    baseline = "adt_replay_toggle_and_batch.golden.lua",
  },
}
