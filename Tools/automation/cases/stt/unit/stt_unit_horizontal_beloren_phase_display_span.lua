return {
  meta = {
    id = "stt_unit_horizontal_beloren_phase_display_span",
    plugin = "stt",
    type = "unit",
    title = "贝洛朗 M 模板按内置阶段展示跨度换算 P2 时间",
  },
  init = {
    spellNameMap = {
      [1242515] = "虚光汇流",
    },
  },
  events = {
    {
      type = "build_horizontal_items",
      encounterID = 3182,
      phaseDisplaySpans = {
        p1r1 = 109,
      },
      text = [[
[时间轴]
{time:01:40,p1r1} {贝洛朗}{spell:1242515,dur:6}
{time:00:53.2,p2r1} {贝洛朗}{spell:1242515,dur:6}
      ]],
    },
  },
  expect = {
    equals = {
      {
        key = "player:贝洛朗",
        kind = "player",
        displayText = "贝洛朗",
        items = {
          { time = 100, spellID = 1242515, duration = 6, collisionCount = 0 },
          { time = 162.2, spellID = 1242515, duration = 6, collisionCount = 0 },
        },
      },
    },
  },
}
