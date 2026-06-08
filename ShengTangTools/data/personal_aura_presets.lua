local T = unpack(select(2, ...))
T.RegisterColdFile("personalAuraAlert.enabled", function()

T.Data = T.Data or {}

T.Data.PersonalAuraPresetBossOrder = {
    3183,
    3181,
}

T.Data.PersonalAuraPresetBosses = {
    [3183] = {
        nameKey = "PERSONAL_AURA_PRESET_BOSS_3183",
        fallbackName = "至暗之夜降临",
        presets = {
            {
                key = "lura_dark_rune",
                nameKey = "PERSONAL_AURA_PRESET_LURA_DARK_RUNE",
                fallbackName = "黑暗符文",
                severity = 2,
                -- 占位参考=14（符文 debuff 窗口）；真值待实机用观测记录的 info.duration 校准
                durationSec = 14,
                -- 阶段 1/3 触发；与同为 sev2 的「充能」靠不重叠时间窗口区分（鲁拉 M 阶段边界参考，待实机校准）
                timeWindows = {
                    { startSec = 0, endSec = 180 },   -- P1
                    { startSec = 225, endSec = 330 }, -- P3
                },
                calibrated = false,
                enabledDefault = false,
            },
            {
                key = "lura_starsplinter",
                nameKey = "PERSONAL_AURA_PRESET_LURA_STARSPLINTER",
                fallbackName = "星辰裂片",
                severity = 1,
                durationSec = 2.9,
                calibrated = true,
                enabledDefault = true,
            },
            {
                key = "lura_galvanize",
                nameKey = "PERSONAL_AURA_PRESET_LURA_GALVANIZE",
                fallbackName = "充能",
                severity = 2,
                -- 占位参考=7；真值待实机用观测记录的 info.duration 校准
                durationSec = 7,
                -- 阶段 2/4 触发；与同为 sev2 的「黑暗符文」靠不重叠时间窗口区分（鲁拉 M 阶段边界参考，待实机校准）
                timeWindows = {
                    { startSec = 180, endSec = 225 }, -- P2
                    { startSec = 330, endSec = 522 }, -- P4
                },
                calibrated = false,
                enabledDefault = false,
            },
        },
    },
    [3181] = {
        nameKey = "PERSONAL_AURA_PRESET_BOSS_3181",
        fallbackName = "宇宙之冕",
        presets = {
            {
                key = "crown_silver_strike",
                nameKey = "PERSONAL_AURA_PRESET_CROWN_SILVER_STRIKE",
                fallbackName = "银锋箭",
                severity = 1,
                durationSec = 5,
                calibrated = false,
                enabledDefault = false,
            },
            {
                key = "crown_void_tremor",
                nameKey = "PERSONAL_AURA_PRESET_CROWN_VOID_TREMOR",
                fallbackName = "虚空斥力",
                severity = 1,
                durationSec = 5,
                calibrated = false,
                enabledDefault = false,
            },
        },
    },
}

end)
