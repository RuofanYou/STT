local T, C, L = unpack(select(2, ...))

-- STT 更新日志（单一权威）—— 按天写日记
--
-- 内容规矩（务必遵守）：
--   1) 游戏更新公告口吻、平实，对着玩家说话：「现在你可以……了」「开发了X，现在你可以……了」；
--      明显修复直接点名，内部/小修复含糊带过。
--   2) 只写玩家能感知的功能；纯开发改动（重构/性能/解耦/日志/通信）一律不写。
--   3) 禁止脑补：每条都要先读对应模块代码、或当天写进 locale 的玩家文案确认真实行为，拿不准就问作者，绝不编。
--   4) 禁止此地无银的括号（如「不依赖ElvUI」「安全宏条」这类竞品/技术框架）。
--
-- 结构：每个块 = 一天（date = "YYYY-MM-DD"，不带版本号；插件标题栏本来就有版本号）。
--   当天内容按 new / improved / fixed 分类（任一为空即省略）；从上到下日期从新到旧。
--   条目只写 CHANGELOG_* locale key，正文必须放到 zhCN/zhTW/enUS 主语言包。
--   纯内部改动的日子直接跳过不写；只从更新日志上线那天起逐日记，更久远的看 release 包（release/STT/*.zip）。

T.Assets:Define("Changelog", {
    targetTable = T,
    targetKey = "Changelog",
    factory = function()
        return {
            {
                date = "2026-06-08",
                fixed = {
                    "CHANGELOG_20260608_FIXED_PHASE_RELATIVE_TIMELINE",
                    "CHANGELOG_20260608_FIXED_CROWN_MYTHIC_P2_TEMPLATE",
                    "CHANGELOG_20260608_FIXED_VISUAL_BOARD_INSPECTOR_WIDTH",
                    "CHANGELOG_20260608_FIXED_VISUAL_BOARD_SYNC_PACKAGE",
                },
            },
            {
                date = "2026-06-07",
                fixed = {
                    "CHANGELOG_20260607_FIXED_VISUAL_BOARD_FRAME_GEOMETRY",
                },
            },
            {
                date = "2026-06-06",
                fixed = {
                    "CHANGELOG_20260606_FIXED_LURA_HORIZONTAL_RUNE_ROUTE",
                },
            },
            {
                date = "2026-06-05",
                new = {
                    "CHANGELOG_20260605_NEW_VISUAL_BOARD_OVERVIEW",
                    "CHANGELOG_20260605_NEW_VISUAL_BOARD_BOSS_PACKAGE",
                    "CHANGELOG_20260605_NEW_VISUAL_BOARD_TIMELINE_TOKEN",
                    "CHANGELOG_20260605_NEW_VISUAL_BOARD_SLIDES",
                    "CHANGELOG_20260605_NEW_VISUAL_BOARD_EDITOR_TOOLS",
                    "CHANGELOG_20260605_NEW_VISUAL_BOARD_SHORTCUTS",
                    "CHANGELOG_20260605_NEW_VISUAL_BOARD_ICON_TEXT",
                    "CHANGELOG_20260605_IMPROVED_VISUAL_BOARD_LAYOUT",
                    "CHANGELOG_20260605_NEW_VISUAL_BOARD_FEEDBACK",
                },
            },
            {
                date = "2026-06-04",
                improved = {
                    "CHANGELOG_20260604_IMPROVED_PERSONAL_AURA_PRESETS",
                },
                fixed = {
                    "CHANGELOG_20260604_FIXED_EMPTY_TEAM_TEMPLATE",
                },
            },
            {
                date = "2026-06-03",
                improved = {
                    "CHANGELOG_20260603_IMPROVED_REALTIME_BOARD_ACTIVE_HIGHLIGHT",
                    "CHANGELOG_20260603_IMPROVED_LURA_CRYSTAL_PROGRESS_HINT",
                },
                fixed = {
                    "CHANGELOG_20260603_FIXED_DIAGNOSE_DISPLAY_ONLY",
                },
            },
            {
                date = "2026-06-02",
                new = {
                    "CHANGELOG_20260602_NEW_LURA_STARSPLINTER_DIRECTION",
                    "CHANGELOG_20260602_NEW_SELF_MARKER_SOLID_BLOCK",
                },
                improved = {
                    "CHANGELOG_20260602_IMPROVED_LURA_BUTTON_BAR_LAYOUT",
                },
                fixed = {
                    "CHANGELOG_20260602_FIXED_BOSS_PLAN_SWITCH",
                    "CHANGELOG_20260602_FIXED_TEMPLATE_ACTOR_ICONS",
                    "CHANGELOG_20260602_FIXED_SEEK_SCREEN_REMINDER",
                    "CHANGELOG_20260602_FIXED_TTS_QUEUE_DELAY",
                },
            },
            {
                date = "2026-06-01",
                improved = {
                    "CHANGELOG_20260601_IMPROVED_ENTRY_TOGGLES",
                    "CHANGELOG_20260601_IMPROVED_REMEMBER_PANEL",
                    "CHANGELOG_20260601_IMPROVED_VERSION_NICKNAME",
                    "CHANGELOG_20260601_IMPROVED_UNLOCK_POS",
                    "CHANGELOG_20260601_IMPROVED_SCREEN_REMINDER_COUNTDOWN_SIZE",
                },
                fixed = {
                    "CHANGELOG_20260601_FIXED_DREAD_ELEGY_PANEL",
                    "CHANGELOG_20260601_FIXED_DREAD_ELEGY_ZHTW_BUTTONS",
                    "CHANGELOG_20260601_FIXED_TIMELINE_MULTI_NAMES",
                    "CHANGELOG_20260601_FIXED_BELORAN_TEMPLATE",
                },
            },
            {
                date = "2026-05-31",
                new = {
                    "CHANGELOG_20260531_NEW_CHANGELOG_PANEL",
                },
                improved = {
                    "CHANGELOG_20260531_IMPROVED_SCREEN_REMINDER_ANIM",
                },
                fixed = {
                    "CHANGELOG_20260531_FIXED_TIMELINE_RESET",
                    "CHANGELOG_20260531_FIXED_FRIENDLY_NAMEPLATE_OUTLINE",
                    "CHANGELOG_20260531_FIXED_INTERRUPT_OLD_RAID",
                },
            },
            {
                date = "2026-05-30",
                new = {
                    "CHANGELOG_20260530_NEW_GLOBAL_TEST_BUTTONS",
                    "CHANGELOG_20260530_NEW_TIMELINE_STOP_BUTTON",
                },
                improved = {
                    "CHANGELOG_20260530_IMPROVED_PERFORMANCE",
                    "CHANGELOG_20260530_IMPROVED_SEND_PROGRESS",
                },
                fixed = {
                    "CHANGELOG_20260530_FIXED_SYNC_VERSION_MISMATCH",
                },
            },
        }
    end,
})
