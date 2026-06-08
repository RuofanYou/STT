return {
  meta = {
    id = "stt_unit_diagnose_stn_personal_default_self",
    plugin = "stt",
    type = "unit",
    title = "一键诊断沿用 STN 运行时 bundle 并保留个人方案无受众默认自己",
  },
  init = {
    playerName = "瑟维雅",
    db = {
      dataSource = "STN",
      semanticTimeline = {
        runtimeEnabled = true,
        enabled = false,
        resolveSource = "team_plus_personal",
        personalOverridesTeam = true,
      },
    },
  },
  events = {
    {
      type = "set_current_plan_bundle",
      teamText = table.concat({
        "[时间轴]",
        "{time:00:05} {旁观者} 团队无关提醒",
      }, "\n"),
      personalText = table.concat({
        "[时间轴]",
        "{time:00:08} 个人默认提醒",
      }, "\n"),
    },
    { type = "collect_diagnose_hits" },
  },
  expect = {
    equals = {
      ttsHits = 1,
      displayHits = 0,
      reason = "ok",
      source = "STN",
    },
  },
}
