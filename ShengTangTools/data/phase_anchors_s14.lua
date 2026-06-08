local T = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

T.PhaseAnchorsVersionS14 = "phase_anchors_s14_v11"

T.Assets:Define("PhaseAnchorsS14", {
    targetTable = T,
    targetKey = "PhaseAnchorsS14",
    factory = function()
        return {
    [3181] = {
        initialPhase = "p1",
        durationTolerance = 0.75,
        phaseOrder = { "p1", "i1", "p2", "i2", "p3" },
        templateRules = {
            i1 = { type = "spell", spellID = 1234569 },
            p2 = { type = "spell", spellID = 1238206 },
            i2 = { type = "spell", spellID = 1245874 },
            p3 = { type = "spell", spellID = 1238843 },
        },
        phaseLabels = {
            p1 = "第一阶段: 虚影尖塔",
            i1 = "阶段转换: 碾压奇点",
            p2 = "第二阶段: 破碎裂隙",
            i2 = "阶段转换: 碎裂奇点",
            p3 = "第三阶段: 终末之末",
        },
        anchors = {
            p1 = { duration = 1.5, toPhase = "i1" },
            i1 = { duration = 24.5, toPhase = "p2" },
            p2 = { duration = 1.5, toPhase = "i2" },
            i2 = { duration = 60, toPhase = "p3" },
        },
        difficultyOverrides = {
            [16] = {
                -- Mythic 的转阶段不是 Heroic 那套“单个 duration 直接切”。
                -- 这里改成 Mythic 专用：P1 先走短窗口组合信号；P2/P3 以阶段条真正结束为主锚点；
                -- 自动模板注入的 spell 规则只保留给 Heroic，避免在 Mythic 重新把阶段切早。
                ignoreBuiltinTemplateRules = true,
                anchors = {
                    p1 = {
                        {
                            durationOneOf = { 1.5, 25, 6 },
                            requiredCount = 2,
                            windowSeconds = 0.3,
                            toPhase = "i1",
                        },
                        {
                            spellID = 1234569,
                            minPhaseDuration = 100,
                            toPhase = "i1",
                        },
                    },
                    i1 = {
                        {
                            duration = 25,
                            matchEvent = "ended",
                            toPhase = "p2",
                        },
                        {
                            spellID = 1238206,
                            minPhaseDuration = 20,
                            toPhase = "p2",
                        },
                    },
                    p2 = {
                        {
                            requiredCount = 3,
                            windowSeconds = 0.3,
                            matchEvent = "canceled",
                            toPhase = "i2",
                        },
                        {
                            requiredCount = 8,
                            windowSeconds = 0.3,
                            matchEvent = "added",
                            toPhase = "p3",
                        },
                    },
                    i2 = {
                        {
                            requiredCount = 8,
                            windowSeconds = 0.3,
                            matchEvent = "added",
                            toPhase = "p3",
                        },
                    },
                },
            },
        },
    },
    [3306] = {
        initialPhase = "p1",
        durationTolerance = 0.75,
        phaseOrder = { "p1", "p2" },
        anchors = {
            p1 = {
                -- 奇美鲁斯的转 P2 不是稳定的 spell/event 锚点，正式服主流插件也都按阶段条 duration 判定。
                { duration = 164.5, durationTolerance = 6, toPhase = "p2" },
                { duration = 151.36, durationTolerance = 4, toPhase = "p2" },
                { duration = 148, durationTolerance = 2, toPhase = "p2" },
                { duration = 120, durationTolerance = 5, toPhase = "p2" },
                { duration = 10, durationTolerance = 1.5, toPhase = "p2" },
            },
            p2 = {
                -- 返场要等 Ravenous Dive 真正结束，不能在 p2 内部长条 Added 时提前切回 p1rN+1。
                { spellID = 1245404, matchEvent = "finished", toPhase = "p1", nextRound = true },
            },
        },
    },
    [3183] = {
        -- 鲁拉（至暗之夜降临）五阶段定义；切换时刻基于 ENCOUNTER_TIMELINE_EVENT 的 duration 字段（开战内的 45 / 97 / 180）。
        -- 命名约定：p1 序章 / i1 间歇 / p2 鲁拉本体（种子掉落） / p3 后续 / p4 收尾。
        initialPhase = "p1",
        durationTolerance = 0.5,
        phaseOrder = { "p1", "i1", "p2", "p3", "p4" },
        anchors = {
            p1 = { { duration = 45,  matchEvent = "added", toPhase = "i1" } },
            i1 = { { duration = 97,  matchEvent = "added", toPhase = "p2" } },
            p2 = { { duration = 180, matchEvent = "added", toPhase = "p3" } },
        },
        -- p3→p4：监听 INSTANCE_ENCOUNTER_ENGAGE_UNIT 事件；当 boss2 不存在且距上次切换 ≥ 20 秒时切换。
        engageUnitAnchors = {
            p3 = { { unitMissing = "boss2", minPhaseDuration = 20, toPhase = "p4" } },
        },
    },
    [3182] = {
        initialPhase = "p1",
        ignoreExternalPhase = true,
        durationTolerance = 0.75,
        phaseOrder = { "p1", "p2" },
        phaseLabels = {
            p1 = "P1: 浴火凤凰",
            p2 = "P2: 灰烬之壳",
        },
        delayRules = {
            {
                phase = "p2",
                duration = 40,
                durationTolerance = 0.2,
                baseline = 7.1,
                maxDiff = 20,
                minDelay = 0.3,
            },
        },
        anchors = {
            p1 = {
                {
                    duration = 6,
                    durationTolerance = 0,
                    minPhaseDuration = 5,
                    maxRecentAddedCount = 1,
                    windowSeconds = 0.1,
                    toPhase = "p2",
                },
            },
            p2 = {
                {
                    duration = 6,
                    durationTolerance = 0,
                    minPhaseDuration = 5,
                    toPhase = "p1",
                    nextRound = true,
                },
            },
        },
    },
        }
    end,
})

end)
