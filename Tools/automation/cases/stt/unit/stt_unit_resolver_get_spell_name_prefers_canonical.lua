return {
  meta = {
    id = "stt_unit_resolver_get_spell_name_prefers_canonical",
    plugin = "stt",
    type = "unit",
    title = "事件解析器优先使用 canonical spellName",
  },
  init = {
    spellNameMap = {
      [1249265] = "狂奔怒火",
    },
  },
  events = {
    {
      type = "resolver_get_spell_name",
      spellID = 1249265,
      fallbackName = "狂奔怒□",
    },
  },
  expect = {
    equals = "狂奔怒火",
  },
}
