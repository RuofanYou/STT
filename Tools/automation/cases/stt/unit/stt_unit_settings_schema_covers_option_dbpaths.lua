return {
  meta = {
    id = "stt_unit_settings_schema_covers_option_dbpaths",
    plugin = "stt",
    type = "unit",
    title = "设置导出 schema 覆盖普通设置路径",
  },
  events = {
    { type = "settings_schema_audit" },
  },
  expect = {
    equals = {
      ok = true,
      missing = {},
    },
  },
}
