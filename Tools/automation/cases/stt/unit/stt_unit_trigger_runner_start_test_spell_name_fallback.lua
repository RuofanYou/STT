return {
  meta = {
    id = "stt_unit_trigger_runner_start_test_spell_name_fallback",
    plugin = "stt",
    type = "unit",
    title = "TriggerRunner 测试模式在纯 spell 规则下回退技能名播报",
  },
  init = {
    spellNameMap = {
      [1249265] = "狂奔怒火",
    },
  },
  events = {
    {
      type = "set_source_text",
      source = "MRT",
      text = table.concat({
        "[方案]",
        "名称=测试",
        "作者=STT",
        "",
        "[触发轴]",
        "{on:spell:1249265}",
      }, "\n"),
    },
    { type = "trigger_runner_start_test" },
  },
  expect = {
    equals = {
      started = true,
      speakCalls = {
        {
          voiceID = 0,
          text = "狂奔怒火",
          rate = 0,
          volume = 100,
          overlap = false,
        },
      },
    },
  },
}
