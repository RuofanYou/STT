local bossKey = "raid:999:111"
local builtinBody = "{time:00:05} {所有人}{spell:12345}<开场>"
local reloadedBuiltinText = table.concat({
  "[方案]",
  "名称 = 测试Boss",
  "作者 = STT",
  "",
  "[人员]",
  "",
  "[时间轴]",
  builtinBody,
}, "\n")
local legacyText = table.concat({
  "[方案]",
  "名称=旧方案",
  "作者=玩家",
  "",
  "[时间轴]",
  "{time:00:10} {玩家甲}<旧内容>",
}, "\n")
local playerText = table.concat({
  "[方案]",
  "名称=已有方案",
  "作者=玩家",
  "",
  "[时间轴]",
  "{time:00:15} {玩家乙}<自定义>",
}, "\n")

return {
  meta = {
    id = "stt_unit_semantic_template_initializes_empty",
    plugin = "stt",
    type = "unit",
    title = "语义团队方案首次初始化为空，只有主动重载才写入内置模板",
  },
  events = {
    {
      type = "semantic_template_initialization_cases",
      version = "automation_builtin_v2",
      builtinPlans = {
        [bossKey] = builtinBody,
      },
      builtinMeta = {
        [bossKey] = {
          instanceID = 999,
          instanceName = "测试副本",
          instanceNameZh = "测试副本",
          encounterName = "Test Boss",
          encounterNameZh = "测试Boss",
          journalOrder = 1,
        },
      },
      cases = {
        {
          id = "fresh_install_empty",
        },
        {
          id = "manual_reload_writes_builtin",
          reloadBossKey = bossKey,
        },
        {
          id = "existing_player_content_preserved",
          seed = {
            semanticPlans = {
              [bossKey] = {
                name = "已有方案",
                content = playerText,
              },
            },
          },
        },
        {
          id = "legacy_plan_content_preserved",
          seed = {
            legacyPlanMap = {
              [bossKey] = {
                name = "旧方案",
                content = legacyText,
              },
            },
          },
        },
      },
    },
  },
  expect = {
    equals = {
      {
        id = "fresh_install_empty",
        semantic = {
          [bossKey] = "",
        },
        personal = {
          [bossKey] = "",
        },
        bossTemplateVer = {
          [bossKey] = "automation_builtin_v2",
        },
        bossTemplateDigestSet = {},
      },
      {
        id = "manual_reload_writes_builtin",
        semantic = {
          [bossKey] = reloadedBuiltinText,
        },
        personal = {
          [bossKey] = "",
        },
        bossTemplateVer = {
          [bossKey] = "automation_builtin_v2",
        },
        bossTemplateDigestSet = {
          [bossKey] = true,
        },
        reloadOk = true,
        reloadText = reloadedBuiltinText,
      },
      {
        id = "existing_player_content_preserved",
        semantic = {
          [bossKey] = playerText,
        },
        personal = {
          [bossKey] = "",
        },
        bossTemplateVer = {
          [bossKey] = "automation_builtin_v2",
        },
        bossTemplateDigestSet = {
          [bossKey] = true,
        },
      },
      {
        id = "legacy_plan_content_preserved",
        semantic = {
          [bossKey] = legacyText,
        },
        personal = {
          [bossKey] = "",
        },
        bossTemplateVer = {
          [bossKey] = "automation_builtin_v2",
        },
        bossTemplateDigestSet = {
          [bossKey] = true,
        },
      },
    },
  },
}
