local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("earlyPull.enabled", function()

T.EarlyPull = T.EarlyPull or {}
local Blame = {}
T.EarlyPull.Blame = Blame

local DAMAGE_EVENTS = {
    SWING_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    RANGE_DAMAGE = true,
}

local SWING_EVENTS = {
    SWING_DAMAGE = true,
}

local function GetConstants(ctx)
    return (ctx and ctx.constants) or (T.EarlyPull and T.EarlyPull.Constants) or {}
end

local function GetCandidate(candidates, guid)
    if not guid then
        return nil
    end
    local cand = candidates[guid]
    if not cand then
        cand = {
            guid = guid,
            score = 0,
            combatLogScore = 0,
        }
        candidates[guid] = cand
    end
    return cand
end

local function Timeliness(ctx, entry)
    if not (ctx and entry and entry.time) then
        return 0
    end
    local constants = GetConstants(ctx)
    local center = (ctx.pullTime or 0) + (constants.timelinessOffset or -1)
    return 1 - (constants.timelinessDecayRate or 0.5) * math.abs(entry.time - center)
end

local function Window(ctx)
    local constants = GetConstants(ctx)
    local pullTime = ctx.pullTime or 0
    return pullTime + (constants.criticalWindowBegin or -2), pullTime + (constants.criticalWindowEnd or -0.1)
end

local function ScoreCombat(ctx, candidates)
    local logs = ctx.logs or {}
    if not logs.combatLog then
        return
    end

    local constants = GetConstants(ctx)
    local beginTime, endTime = Window(ctx)
    for entry in logs.combatLog:IterateWindow(beginTime, endTime) do
        local cand = GetCandidate(candidates, entry.sourceGUID)
        if cand then
            local score = (constants.combatLogBaseScore or 1) * Timeliness(ctx, entry)
            if ctx.restricted and ctx.restricted.combatLog then
                score = score * (constants.combatLogRestrictedPenalty or 0.3)
            end
            if not DAMAGE_EVENTS[entry.event] then
                score = score * (constants.combatLogNonDamagePenalty or 0.3)
            end
            if entry.event == "SPELL_CAST_SUCCESS" then
                score = score * (constants.combatLogSpellCastPenalty or 0.5)
            end
            if not entry.isBossTarget then
                score = score * (constants.combatLogNonBossTargetPenalty or 0.1)
            end
            if score > (cand.combatLogScore or 0) then
                cand.combatLogScore = score
                cand.combatLogEntry = entry
            end
        end
    end
end

-- 12.0 secret 系统下 threat 与 boss target 两路信号皆已拔除（参见 scanner.lua / constants.lua）。
-- blame 退化为 CLEU 单路：cand.score 即 cand.combatLogScore，cand.name 来自 combatEntry.name。

local function FinalizeCandidate(ctx, cand)
    if not cand then
        return nil
    end

    local constants = GetConstants(ctx)
    cand.score = cand.combatLogScore or 0

    local combatEntry = cand.combatLogEntry
    if combatEntry and (cand.combatLogScore or 0) >= (constants.spellBlameCutoff or 0.5) then
        cand.spellID = SWING_EVENTS[combatEntry.event] and 6603 or combatEntry.spellID
    end

    cand.name = (combatEntry and combatEntry.name) or cand.name

    if cand.guid and not cand.guid:find("^Player") then
        local owner = ctx.petOwners and ctx.petOwners[cand.guid]
        if owner then
            cand.petOwner = owner.ownerName
            cand.name = cand.name or owner.petName
        end
    end

    return cand
end

function Blame:Run(ctx)
    if type(ctx) ~= "table" then
        return nil, nil
    end

    local candidates = {}
    ScoreCombat(ctx, candidates)

    local best, second
    for _, cand in pairs(candidates) do
        FinalizeCandidate(ctx, cand)
        if not best or cand.score > best.score then
            second = best
            best = cand
        elseif not second or cand.score > second.score then
            second = cand
        end
    end

    return best, second
end

function Blame:Describe(best, second, lowCertaintyCutoff)
    if not best then
        return L["EARLY_PULL_UNKNOWN_BLAMED"] or "未知"
    end

    local name = best.name or L["EARLY_PULL_UNKNOWN_BLAMED"] or "未知"
    if best.petOwner then
        name = string.format(L["EARLY_PULL_PET_OWNER_FMT"] or "%s 的宠物 %s", best.petOwner, name)
    end

    if second and (best.score - (second.score or 0)) < (lowCertaintyCutoff or 0.3) then
        name = name .. " (?)"
    end
    return name
end

end)
