-- 当前 S1 团本/大秘境 EncounterWarnings/EncounterEvents 补充映射
-- 玩家侧仍以 spellID 作为唯一编辑入口；eventID / triggerSpellID 仅用于内部触发归一化。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

T.SemanticEncounterEventMapVersionS14 = "encounter_events_s14_v4"

T.Assets:Define("SemanticEncounterEventMapS14", {
    targetTable = T,
    targetKey = "SemanticEncounterEventMapS14",
    factory = function()
        return {
    -- 虚灵尖塔 / 威厄高尔与艾佐拉克
    [3178] = {
        [1244221] = {
            encounterEventIDs = { 104 }, -- 亡者吐息 / Dread Breath
            triggerSpellIDs = { 1244221 },
        },
    },

    -- 梦境裂隙 / 奇美鲁斯，未梦之神
    [3306] = {
        [1245396] = {
            encounterEventIDs = { 307 }, -- 吞噬 / Consume
            triggerSpellIDs = { 1245396 },
        },
        [1245404] = {
            encounterEventIDs = { 48 }, -- 贪食俯冲 / Ravenous Dive
            triggerSpellIDs = { 1245404 },
        },
    },

    -- 迈萨拉洞窟 / 沃达扎
    -- 说明：
    -- 1. encounterEventIDs 仅用于来源记录与核验，不直接暴露给玩家。
    -- 2. triggerSpellIDs 是运行时可能从暴雪事件结构里观察到的 spellID，
    --    最终都会归一到左侧技能目录使用的 canonical spellID。
    [3213] = {
        [1251554] = {
            encounterEventIDs = { 16 }, -- 吸取灵魂
            triggerSpellIDs = { 1251554 },
        },
        [1252054] = {
            encounterEventIDs = { 17 }, -- 寂灭
            triggerSpellIDs = { 1252054 },
        },
        [1252130] = {
            encounterEventIDs = { 19 }, -- 束缚幻影
            triggerSpellIDs = { 1251204, 1252130 },
        },
        [1250708] = {
            encounterEventIDs = { 20 }, -- 死疽融合
            triggerSpellIDs = { 1250708 },
        },
    },
        }
    end,
})

return true

end)
