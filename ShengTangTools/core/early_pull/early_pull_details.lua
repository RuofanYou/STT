local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("earlyPull.enabled", function()

T.EarlyPull = T.EarlyPull or {}
local Details = {}
T.EarlyPull.Details = Details

local function FormatCandidate(label, cand)
    if not cand then
        return string.format("%s: -", label)
    end
    return string.format(
        "%s: %s score=%.3f cleu=%.3f spell=%s",
        label,
        cand.name or cand.guid or "-",
        cand.score or 0,
        cand.combatLogScore or 0,
        tostring(cand.spellID or "-")
    )
end

function Details.Print(runtime)
    local result = runtime and runtime.lastResult
    if not result then
        T.msg(L["EARLY_PULL_NO_DETAILS"] or "暂无提前开怪明细")
        return
    end

    local header = string.format(
        "EarlyPull encounter=%s diff=%s restricted(lockdown=%s, cleu=%s)",
        tostring(result.ctx.encounterName or result.ctx.encounterID or "-"),
        tostring(result.ctx.pullTimeDiff),
        tostring(result.ctx.restricted and result.ctx.restricted.lockdown),
        tostring(result.ctx.restricted and result.ctx.restricted.combatLog)
    )
    T.msg(header)
    T.msg(FormatCandidate("best", result.best))
    T.msg(FormatCandidate("second", result.second))
    T.debug("[EarlyPull] details " .. header)
    T.debug("[EarlyPull] " .. FormatCandidate("best", result.best))
    T.debug("[EarlyPull] " .. FormatCandidate("second", result.second))
end

end)
