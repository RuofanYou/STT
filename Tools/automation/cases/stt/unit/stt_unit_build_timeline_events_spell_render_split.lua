return {
  meta = {
    id = "stt_unit_build_timeline_events_spell_render_split",
    plugin = "stt",
    type = "unit",
    title = "时间轴与屏幕提醒对 spell token 分轨渲染",
  },
  init = {
    spellInfoMap = {
      [1249265] = { name = "狂奔怒火", iconID = 555001 },
      [1251361] = { name = "熊形态", iconID = 555002 },
    },
    db = {
      advanceTime = 3,
    },
  },
  events = {
    {
      type = "build_timeline_events_screen",
      parsed = {
        {
          time = 9,
          content = "{所有人}{spell:1249265} 去左边 {spell:1251361}",
          hasAudience = true,
        },
      },
    },
  },
  expect = {
    equals = {
      {
        time = 9,
        showTime = 6,
        text = "狂奔怒火 去左边 熊形态",
        timelineText = "狂奔怒火 去左边 |T555002:0:0:0:0:64:64:5:59:5:59|t 熊形态",
        ttsText = "狂奔怒火 去左边 熊形态",
        spellID = 1249265,
        spellIcon = 555001,
        isSilent = false,
      },
    },
  },
}
