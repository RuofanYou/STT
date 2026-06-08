return {
  meta = {
    id = "stt_unit_trigger_runner_display_text_uses_canonical_spell_name",
    plugin = "stt",
    type = "unit",
    title = "TriggerRunner 已移除旧的时间轴展示文本接口",
  },
  init = {
    selectedEncounterID = 999001,
    encounterSpellCatalog = {
      { spellID = 1249265, occurrenceCount = 1, firstOccurrence = 1 },
    },
    spellNameMap = {
      [1249265] = "狂奔怒火",
    },
  },
  events = {
    {
      type = "trigger_runner_start",
      text = table.concat({
        "[方案]",
        "名称=测试",
        "作者=STT",
        "",
        "[触发轴]",
        "{on:spell:1249265}",
      }, "\n"),
    },
    {
      type = "trigger_runner_has_display_text_api",
    },
  },
  expect = {
    equals = {
      present = false,
    },
  },
}
