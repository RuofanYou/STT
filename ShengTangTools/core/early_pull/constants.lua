local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("earlyPull.enabled", function()

T.EarlyPull = T.EarlyPull or {}
C.Const = C.Const or {}

local Constants = {
    afterPullDelay = 0.3,
    regenAnchorMaxAge = 5,
    maxPullTimeDiff = 60,
    pullOnTimeWindow = 1.0,
    pullTimeDiffDecimals = 2,
    autoPrintDetails = false,
    criticalWindowBegin = -2.0,
    criticalWindowEnd = 0.3,
    timelinessOffset = -1.0,
    timelinessDecayRate = 0.5,
    combatLogBaseScore = 1.0,
    combatLogNonDamagePenalty = 0.3,
    combatLogSpellCastPenalty = 0.5,
    combatLogNonBossTargetPenalty = 0.1,
    combatLogRestrictedPenalty = 0.3,
    -- 12.0 secret 系统下 threat（UnitThreatSituation）与 boss target（boss1target 链）两路皆已拔除，
    -- blame 退化为 CLEU 单路 + STTEP 战后兜底（详见 early_pull_blame.lua / early_pull_claim.lua）。
    spellBlameCutoff = 0.5,
    lowCertaintyCutoff = 0.3,
    logSize = {
        combat = 1000,
    },
    -- 战后同步（仅在战中"识别不出"时由 self-claim 兜底）
    syncPrefix = "STTEP",
    syncProtocolVersion = 1,
    postCombatSendDelay = 1.0,        -- 脱战后多久才广播 self-claim
    postCombatSendMaxRetry = 5,       -- lockdown 等异常下的最大重试次数
    postCombatSendRetryGap = 1.0,     -- 每次重试间隔秒
    postSyncDisplayDelay = 0.5,       -- 收到首条 claim 后等待去重的窗口
    receivedSessionLruSize = 8,       -- 已显示 session 缓存上限
}

T.EarlyPull.Constants = Constants
C.Const.EarlyPull = Constants

end)
