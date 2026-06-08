return {
  meta = {
    id = "stt_unit_resolver_resolve_timeline_spell_meta_canonical",
    plugin = "stt",
    type = "unit",
    title = "Timeline spell meta 使用 canonical spellName",
  },
  init = {
    spellNameMap = {
      [1249265] = "狂奔怒火",
    },
  },
  events = {
    {
      type = "resolver_resolve_timeline_spell_meta",
      encounterID = 999001,
      eventInfoOrID = {
        id = 101,
        spellID = 1249265,
        spellName = "狂奔怒□",
      },
    },
  },
  expect = {
    equals = {
      eventID = 101,
      observedSpellID = 1249265,
      spellID = 1249265,
      spellName = "狂奔怒火",
    },
  },
}
