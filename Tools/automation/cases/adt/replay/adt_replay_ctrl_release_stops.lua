return {
  meta = { id = "adt_replay_ctrl_release_stops", plugin = "adt", type = "replay", title = "按住-松开 Ctrl 停止续放" },
  init = {
    db = { EnableBatchPlace = true },
    ctrlDown = true,
    lastPlacedRecordID = 99,
    decorByGUID = {
      ["g1"] = { decorID = 100 },
      ["g2"] = { decorID = 200 },
    },
  },
  events = {
    { type = "place_success", decorGUID = "g1", size = 1, isNew = true, isPreview = false },
    { type = "set_ctrl", value = false },
    { type = "place_success", decorGUID = "g2", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    baseline = "adt_replay_ctrl_release_stops.golden.lua",
  },
}
