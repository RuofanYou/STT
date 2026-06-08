return {
  meta = {
    id = "stt_unit_visual_board_editor_cold_load",
    plugin = "stt",
    type = "unit",
    title = "视觉画板编辑器冷加载但运行时画板接收播放小核可用",
  },
  events = {
    {
      type = "visual_board_cold_load_contract",
    },
  },
  expect = {
    equals = {
      before = {
        editorGUI = false,
        componentDrawer = false,
        layerPanel = false,
        slideBar = false,
        iconPicker = false,
        createBoard = "nil",
        applyTemplate = "nil",
        parser = "function",
        overlay = "function",
        mergeTotal = 1,
        resolvedBoard = "P2分散",
        strippedText = "{time:00:01} {所有人}分散",
        invokeRef = "P2分散",
        invokeOffset = 3,
      },
      after = {
        editorGUI = true,
        componentDrawer = true,
        layerPanel = true,
        slideBar = true,
        iconPicker = true,
        createBoard = "function",
        applyTemplate = "function",
      },
    },
  },
}
