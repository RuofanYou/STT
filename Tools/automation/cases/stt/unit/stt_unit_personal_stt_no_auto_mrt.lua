return {
  meta = {
    id = "stt_unit_personal_stt_no_auto_mrt",
    plugin = "stt",
    type = "unit",
    title = "个人 STT 简化格式不自动识别为 MRT",
  },
  init = {
    db = {
      filterAll = false,
      filterClass = false,
      filterRole = false,
      filterPos = false,
      filterParty = false,
    },
  },
  events = {
    {
      type = "personal_stt_runtime_counts",
      text = [[
{time:00:02.0} -  {spell:355936}
{time:00:08.2} -  {spell:359816}
{time:00:17.2} -  {spell:355936}
{time:00:32.8} -  {spell:355936}
{time:00:43.2} -  {spell:355936}
{time:01:13.2} -  {spell:355936}
{time:01:14.3} -  {spell:363534}
{time:01:27.8} -  {spell:355936}
{time:01:39.3} -  {spell:355936}
{time:01:53.8} -  {spell:355936}
{time:02:06.0} -  {spell:355936}
{time:02:21.3} -  {spell:359816}
{time:02:27.1} -  {spell:355936}
{time:02:47.1} -  {spell:355936}
{time:03:00.0} -  {spell:355936}
{time:03:11.5} -  {spell:355936}
{time:03:23.0} -  {spell:355936}
{time:03:33.7} -  {spell:355936}
{time:03:46.6} -  {spell:355936}
{time:04:01.4} -  {spell:355936}
{time:04:14.0} -  {spell:355936}
{time:04:22.7} -  {spell:359816}
{time:04:31.6} -  {spell:355936}
{time:04:49.9} -  {spell:355936}
{time:05:07.2} -  {spell:355936}
{time:05:27.8} -  {spell:363534}
{time:05:29.2} -  {spell:355936}
{time:05:45.9} -  {spell:355936}
{time:05:58.3} -  {spell:355936}
{time:06:11.2} -  {spell:355936}
      ]],
      translateFormat = "mrt",
      translateText = "{time:00:02.0} -  {spell:355936}",
    },
  },
  expect = {
    equals = {
      isValid = true,
      externalDetected = false,
      processedHasAll = false,
      eventCount = 30,
      timelineCount = 30,
      boardCount = 30,
      hits = 30,
      translatorEventCount = 1,
      translatorHasAll = true,
    },
  },
}
