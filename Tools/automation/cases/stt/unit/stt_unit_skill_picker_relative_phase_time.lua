return {
  meta = {
    id = "stt_unit_skill_picker_relative_phase_time",
    plugin = "stt",
    type = "unit",
    title = "水平时间轴插入技能优先写入阶段相对时间",
  },
  init = {
    spellNameMap = {
      [1242515] = "虚光汇流",
    },
  },
  events = {
    {
      type = "build_skill_picker_lines",
      encounterID = 3182,
      cases = {
        {
          time = 162.2,
          spellID = 1242515,
          phaseDisplayStats = {
            markers = {
              { key = "p1r1", displayKey = "p1", time = 0 },
              { key = "p2r1", displayKey = "p2", time = 109 },
            },
          },
          items = {
            { time = 162.2, sourceTime = 53.2, phaseDisplayOffset = 109, timePayload = "00:53.2,p2r1" },
          },
        },
        {
          time = 162.2,
          spellID = 1242515,
          items = {
            { time = 162.2, sourceTime = 53.2, phaseDisplayOffset = 109, timePayload = "00:53.2,p2r1" },
          },
        },
        {
          time = 90,
          spellID = 1242515,
          items = {
            { time = 90, timePayload = "01:30" },
          },
        },
      },
    },
  },
  expect = {
    equals = {
      {
        line = "{time:00:53.2,p2r1} {BOSS}{spell:1242515}<虚光汇流>",
        reason = nil,
        ctx = {
          time = 162.2,
          sourceTime = 53.2,
          phase = "p2r1",
          phaseDisplayOffset = 109,
          timePayload = "00:53.2,p2r1",
        },
      },
      {
        line = "{time:00:53.2,p2r1} {BOSS}{spell:1242515}<虚光汇流>",
        reason = nil,
        ctx = {
          time = 162.2,
          sourceTime = 53.2,
          phase = "p2r1",
          phaseDisplayOffset = 109,
          timePayload = "00:53.2,p2r1",
        },
      },
      {
        line = "{time:01:30} {BOSS}{spell:1242515}<虚光汇流>",
        reason = nil,
        ctx = {
          time = 90,
          sourceTime = nil,
          phase = nil,
          phaseDisplayOffset = nil,
          timePayload = "01:30",
        },
      },
    },
  },
}
