local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({ "semanticTimeline.editorLoaded", "rosterPlanner.enabled" }, function()

T.SpecAliases = T.SpecAliases or {}
local SpecAliases = T.SpecAliases

-- WoW 全局 specID → 黑话（用户确认逐项填入；详细规范见 docs/spec/STT战术方案同步团员spec.md）
local SPEC_ALIAS = {
    -- 死亡骑士 (Death Knight)
    [250]  = "DKT",   -- 鲜血（坦克）
    [251]  = "冰DK",  -- 冰霜
    [252]  = "邪DK",  -- 邪恶

    -- 恶魔猎手 (Demon Hunter)
    [581]  = "DHT",   -- 复仇（坦克）
    [577]  = "浩劫",  -- 浩劫
    [1480] = "噬灭",  -- 噬灭（Devourer / DDH，12.0 Midnight 新增）

    -- 德鲁伊 (Druid)
    [102]  = "咕咕",  -- 平衡
    [103]  = "猫德",  -- 野性
    [104]  = "熊T",   -- 守护（坦克）
    [105]  = "奶德",  -- 恢复（治疗）

    -- 唤魔师 (Evoker)
    [1473] = "增辉",  -- 增辉（Augmentation）
    [1467] = "湮灭",  -- 湮灭（Devastation）
    [1468] = "奶龙",  -- 丰饶（Preservation, 治疗）

    -- 猎人 (Hunter)
    [253]  = "兽王猎",   -- 兽王
    [254]  = "射击猎",   -- 射击
    [255]  = "生存猎",   -- 生存

    -- 法师 (Mage)
    [62]   = "奥法",     -- 奥术
    [63]   = "火法",     -- 火焰
    [64]   = "冰法",     -- 冰霜

    -- 武僧 (Monk)
    [268]  = "WST",      -- 酒仙（坦克）
    [269]  = "踏风",     -- 踏风
    [270]  = "奶僧",     -- 织雾（治疗）

    -- 圣骑士 (Paladin)
    [65]   = "奶骑",     -- 神圣（治疗）
    [66]   = "防骑",     -- 防护（坦克）
    [70]   = "惩戒骑",   -- 惩戒（备选黑话: cjq）

    -- 牧师 (Priest)
    [256]  = "戒律牧",   -- 戒律（治疗，备选黑话: JLM）
    [257]  = "神牧",     -- 神圣（治疗）
    [258]  = "暗牧",     -- 暗影

    -- 潜行者 (Rogue)
    [259]  = "刺杀贼",   -- 刺杀
    [260]  = "狂徒贼",   -- 狂徒
    [261]  = "敏锐贼",   -- 敏锐

    -- 萨满 (Shaman)
    [262]  = "元素萨",   -- 元素
    [263]  = "增强萨",   -- 增强
    [264]  = "奶萨",     -- 恢复（治疗）

    -- 术士 (Warlock)
    [265]  = "痛苦术",   -- 痛苦
    [266]  = "恶魔术",   -- 恶魔
    [267]  = "毁灭术",   -- 毁灭

    -- 战士 (Warrior)
    [71]   = "武器战",   -- 武器
    [72]   = "狂暴战",   -- 狂怒（社区习惯叫法 狂暴）
    [73]   = "防战",     -- 防护（坦克）
}

local function StripSameRealm(fullName)
    local text = tostring(fullName or "")
    local name, realm = text:match("^([^-]+)-(.+)$")
    if not name then
        return text
    end

    local playerRealm
    if UnitFullName then
        _, playerRealm = UnitFullName("player")
    end
    local normalizedRealm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    if realm == playerRealm or realm == normalizedRealm then
        return name
    end
    return text
end

local function MissingName(member)
    local name = member and (member.fullName or member.name) or nil
    local text = StripSameRealm(name or "")
    if text == "" then
        return L["未知"] or "未知"
    end
    return text
end

function SpecAliases.Resolve(globalSpecID)
    return SPEC_ALIAS[tonumber(globalSpecID)]
end

function SpecAliases.GenerateRosterLines(members)
    local source = type(members) == "table" and members or {}
    local counter = {}
    local lines = {}
    local stats = {
        total = #source,
        included = 0,
        skippedOffline = 0,
        skippedNoSpec = 0,
        missing = {},
        sources = {},
    }

    for _, member in ipairs(source) do
        local isOnline = member and member.isOnline == true
        local alias = member and SpecAliases.Resolve(member.specID) or nil
        if not isOnline then
            stats.skippedOffline = stats.skippedOffline + 1
        elseif not alias then
            stats.skippedNoSpec = stats.skippedNoSpec + 1
            stats.missing[#stats.missing + 1] = {
                name = MissingName(member),
                fullName = member and (member.fullName or member.name) or nil,
                classFileName = member and member.classFileName or nil,
                source = member and member.specSource or nil,
                reason = member and (member.failReason or member.specFailReason) or "no_spec",
            }
        else
            counter[alias] = (counter[alias] or 0) + 1
            lines[#lines + 1] = string.format("%s%d=%s", alias, counter[alias], StripSameRealm(member.fullName or member.name))
            stats.included = stats.included + 1
            local sourceName = member and member.specSource or "unknown"
            stats.sources[sourceName] = (stats.sources[sourceName] or 0) + 1
        end
    end

    return lines, stats
end

end)
