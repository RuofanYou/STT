return {
  meta = { id = "adt_replay_four_entry_flow", plugin = "adt", type = "replay", title = "四入口连续放置回放" },
  init = {
    db = { EnableBatchPlace = true },
    ctrlDown = true,
    catalogByEntryID = {
      [11] = { recordID = 1111 },
    },
    decorByGUID = {
      ["g1"] = { decorID = 1111 },
      ["g2"] = { decorID = 2222 },
      ["g3"] = { decorID = 3333 },
      ["g4"] = { decorID = 4444 },
    },
  },
  events = {
    { type = "start_new", entryID = 11 },
    { type = "place_success", decorGUID = "g1", size = 1, isNew = true, isPreview = false },
    { type = "start_preview", recordID = 2222 },
    { type = "place_success", decorGUID = "g2", size = 1, isNew = true, isPreview = true },
    { type = "start_new", entryID = { recordID = 3333 } },
    { type = "place_success", decorGUID = "g3", size = 1, isNew = true, isPreview = false },
    { type = "place_success", decorGUID = "g4", size = 1, isNew = true, isPreview = false },
  },
  expect = {
    baseline = "adt_replay_four_entry_flow.golden.lua",
  },
}
