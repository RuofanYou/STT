local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("earlyPull.enabled", function()

T.EarlyPull = T.EarlyPull or {}
local Announce = {}
T.EarlyPull.Announce = Announce

local function GetSpellName(spellID)
    if not spellID then
        return nil
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name or nil
    end
    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end
    return nil
end

local function FormatDiff(diff)
    local constants = T.EarlyPull.Constants or {}
    local decimals = tonumber(constants.pullTimeDiffDecimals) or 2
    return string.format("%." .. decimals .. "f", math.abs(tonumber(diff) or 0))
end

local function StripRealm(name)
    if type(name) ~= "string" or name == "" then
        return name
    end
    local short = name:match("^([^%-]+)")
    return short or name
end

function Announce:BuildText(ctx, best, second)
    local constants = T.EarlyPull.Constants or {}
    local blameName = T.EarlyPull.Blame:Describe(best, second, constants.lowCertaintyCutoff)
    local spellName = best and best.spellID and GetSpellName(best.spellID) or nil
    local mainText

    if ctx.pullTimeDiff == nil then
        mainText = string.format(L["EARLY_PULL_UNTIMED_FMT"] or "%s 开怪", blameName)
    elseif ctx.pullTimeDiff < 0 then
        mainText = string.format(L["EARLY_PULL_EARLY_FMT"] or "%s 提前 %s秒 开怪", blameName, FormatDiff(ctx.pullTimeDiff))
    else
        mainText = string.format(L["EARLY_PULL_LATE_FMT"] or "%s 延后 %s秒 开怪", blameName, FormatDiff(ctx.pullTimeDiff))
    end

    if spellName and spellName ~= "" then
        return mainText .. "\n" .. string.format(L["EARLY_PULL_BY_SPELL_FMT"] or "by %s", spellName)
    end
    return mainText
end

function Announce:ShouldShow(ctx)
    if not (C.DB and C.DB.earlyPull and C.DB.earlyPull.enabled ~= false) then
        return false
    end
    local diff = ctx and ctx.pullTimeDiff
    if diff == nil then
        return true
    end
    return diff < -(T.EarlyPull.Constants.pullOnTimeWindow or 1)
end

-- 本机 blame 是否给出了"真实玩家名"（而非空/未知）
function Announce:HasReliableBlame(best)
    if not best then
        return false
    end
    if type(best.name) ~= "string" or best.name == "" then
        return false
    end
    local unknownText = L["EARLY_PULL_UNKNOWN_BLAMED"] or "未知"
    if best.name == unknownText then
        return false
    end
    return true
end

function Announce:Show(ctx, best, second)
    if not self:ShouldShow(ctx) then
        T.debug("[EarlyPull] announce_skip diff=" .. tostring(ctx and ctx.pullTimeDiff))
        return false
    end

    -- 识别不出真实玩家 → 战中静默，留给战后 self-claim 兜底
    if not self:HasReliableBlame(best) then
        T.debug("[EarlyPull] announce_skip reason=unknown_blame diff=" .. tostring(ctx and ctx.pullTimeDiff))
        return false, "unknown_blame"
    end

    -- 12.0 secret 后只剩 CLEU 单路 → 末尾追加「（推测）」让玩家知道这是猜测，
    -- 战后 STTEP 收到不同名 claim 时由 Announce:ShowPostSync(isCorrection=true) 覆盖。
    local text = self:BuildText(ctx, best, second)
    local guessSuffix = L["EARLY_PULL_GUESS_SUFFIX"] or "（推测）"
    local textWithSuffix = text .. guessSuffix
    local color = (ctx.pullTimeDiff == nil or ctx.pullTimeDiff < 0) and "red" or "yellow"
    if C.DB.earlyPull.bigText ~= false and T.TacticalNotice and T.TacticalNotice.ShowPullBlame then
        T.TacticalNotice:ShowPullBlame(textWithSuffix, color)
    end
    if C.DB.earlyPull.tts == true and T.PlayTTS then
        T.PlayTTS(textWithSuffix)
    end
    T.msg(textWithSuffix:gsub("\n", " "))
    T.debug("[EarlyPull] announce_show diff=" .. tostring(ctx.pullTimeDiff) .. " text=" .. textWithSuffix:gsub("\n", " / "))
    return true, best and best.name or nil
end

-- 战后同步展示：来自 self-claim（含自己 self-loopback）。
-- isCorrection=true 时表示「战中已播报某人（推测），但 STTEP 收到不同名玩家自证」，
-- 文案改用「实际开怪：」前缀，告诉玩家这是对战中推测的纠正。
function Announce:ShowPostSync(claim, isCorrection)
    if not (claim and type(claim) == "table") then
        return false
    end
    if not (C.DB and C.DB.earlyPull and C.DB.earlyPull.enabled ~= false) then
        return false
    end
    local playerName = StripRealm(claim.playerName or "")
    if playerName == "" then
        T.debug("[EarlyPull] post_sync_skip reason=no_player_name")
        return false
    end
    local diffSec = (tonumber(claim.diffMs) or 0) / 1000
    local diffStr = FormatDiff(diffSec)
    local mainText
    if isCorrection then
        mainText = string.format(
            L["EARLY_PULL_POST_SYNC_CORRECT_FMT"] or "实际开怪：%s 提前 %s秒",
            playerName, diffStr)
    elseif diffSec < 0 then
        mainText = string.format(
            L["EARLY_PULL_POST_SYNC_EARLY_FMT"] or "%s 提前 %s秒 开怪",
            playerName, diffStr)
    else
        mainText = string.format(
            L["EARLY_PULL_POST_SYNC_LATE_FMT"] or "%s 延后 %s秒 开怪",
            playerName, diffStr)
    end

    local color = diffSec < 0 and "red" or "yellow"
    if C.DB.earlyPull.bigText ~= false and T.TacticalNotice and T.TacticalNotice.ShowPullBlame then
        T.TacticalNotice:ShowPullBlame(mainText, color)
    end
    if C.DB.earlyPull.tts == true and T.PlayTTS then
        T.PlayTTS(mainText)
    end
    T.msg(mainText)
    T.debug("[EarlyPull] post_sync_show player=" .. playerName
        .. " diff=" .. tostring(diffSec)
        .. " reason=" .. tostring(claim.reason)
        .. " correction=" .. tostring(isCorrection or false))
    return true
end

end)
