local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

-- 条件过滤模块（团队笔记占位符）
-- 职业/职责/距离判断仅用于本地过滤，不做任何自动化战斗决策（12.0 合规）

-- 英文职业token到小写映射（便于比较）
local CLASS_TOKENS = {
    WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue",
    PRIEST = "priest", DEATHKNIGHT = "deathknight", SHAMAN = "shaman", MAGE = "mage",
    WARLOCK = "warlock", MONK = "monk", DRUID = "druid", DEMONHUNTER = "demonhunter",
    EVOKER = "evoker",
}

-- 条件类型映射
local CONDITION_TYPES = {
    -- 职业（英文/中文）
    warrior = 1, paladin = 1, hunter = 1, rogue = 1, priest = 1, deathknight = 1,
    shaman = 1, mage = 1, warlock = 1, monk = 1, druid = 1, demonhunter = 1, evoker = 1,

    ["战士"] = 1, ["圣骑士"] = 1, ["猎人"] = 1, ["潜行者"] = 1, ["牧师"] = 1,
    ["死亡骑士"] = 1, ["萨满祭司"] = 1, ["法师"] = 1, ["术士"] = 1, ["武僧"] = 1,
    ["德鲁伊"] = 1, ["恶魔猎手"] = 1, ["唤魔师"] = 1,

    -- 职责
    healer = 2, heal = 2, ["治疗"] = 2,
    tank = 2, ["坦克"] = 2,
    dd = 2, dps = 2, damager = 2, ["输出"] = 2,

    -- 战斗距离
    melee = 3, ["近战"] = 3,
    ranged = 3, ["远程"] = 3,

    -- 全团
    all = 4, everyone = 4, ["所有人"] = 4, ["全团"] = 4,

    -- Boss（显示但永不播报）
    boss = 5, BOSS = 5,

    -- 专精（type=6）
    -- 战士
    ["武器"] = 6, arms = 6,
    ["狂怒"] = 6, fury = 6,
    -- 圣骑士
    ["惩戒"] = 6, retribution = 6,
    -- 猎人
    ["野兽控制"] = 6, ["beast mastery"] = 6,
    ["射击"] = 6, marksmanship = 6,
    ["生存"] = 6, survival = 6,
    -- 潜行者
    ["奇袭"] = 6, assassination = 6,
    ["狂徒"] = 6, outlaw = 6,
    ["敏锐"] = 6, subtlety = 6,
    -- 牧师
    ["戒律"] = 6, discipline = 6,
    ["暗影"] = 6, shadow = 6,
    -- 死亡骑士
    ["鲜血"] = 6, blood = 6,
    ["邪恶"] = 6, unholy = 6,
    -- 萨满
    ["元素"] = 6, elemental = 6,
    ["增强"] = 6, enhancement = 6,
    -- 法师
    ["奥术"] = 6, arcane = 6,
    ["火焰"] = 6, fire = 6,
    -- 术士
    ["痛苦"] = 6, affliction = 6,
    ["恶魔学识"] = 6, demonology = 6,
    -- 武僧
    ["酒仙"] = 6, brewmaster = 6,
    ["踏风"] = 6, windwalker = 6,
    ["织雾"] = 6, mistweaver = 6,
    -- 德鲁伊
    ["平衡"] = 6, balance = 6,
    ["野性"] = 6, feral = 6,
    ["守护"] = 6, guardian = 6,
    -- 恶魔猎手
    ["浩劫"] = 6, havoc = 6,
    ["复仇"] = 6, vengeance = 6,
    ["食灵者"] = 6,
    -- 唤魔师
    ["湮灭"] = 6, devastation = 6,
    ["恩护"] = 6, preservation = 6,
    ["增辉"] = 6, augmentation = 6,
    -- 重名专精（同样 type=6）
    ["神圣"] = 6, holy = 6,
    ["防护"] = 6, protection = 6,
    ["冰霜"] = 6, frost = 6,
    ["恢复"] = 6, restoration = 6,
    ["毁灭"] = 6, destruction = 6,
}

-- 近战专精ID集合（GetSpecializationInfo 返回的 specID）
-- 依据 12.0 职业专精：仅用于"近战/远程"分组语义
local MELEE_SPEC_IDS = {
    -- 战士 Arms71/Fury72/Prot73
    [71] = true, [72] = true, [73] = true,
    -- 圣骑 Prot66、惩戒70（神圣65 视为非近战）
    [66] = true, [70] = true,
    -- 猎人 生存255 近战（其余远程）
    [255] = true,
    -- 潜行者 全近战 259/260/261
    [259] = true, [260] = true, [261] = true,
    -- 死亡骑士 全近战 250/251/252
    [250] = true, [251] = true, [252] = true,
    -- 武僧 踏风269、酒仙268 近战（织雾270 非近战）
    [268] = true, [269] = true,
    -- 德鲁伊 野性103、守护104 近战（平衡102/恢复105 非近战）
    [103] = true, [104] = true,
    -- 萨满 增强263 近战（元素262/恢复264 非近战）
    [263] = true,
    -- 恶魔猎手 全近战 577/581
    [577] = true, [581] = true,
}

-- 全近战职业（当无法获取专精时作为保底判断，不涉及语义别名）
local ALWAYS_MELEE_CLASS = {
    WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, DEMONHUNTER = true,
}

-- 专精ID → 职责（tank/healer 白名单，其余默认 damager）
-- 玩家的职责由专精决定，和有无组队/队伍分配无关
local SPEC_TO_ROLE = {
    -- Tank
    [66]  = "tank",   -- 防护骑
    [73]  = "tank",   -- 防护战
    [250] = "tank",   -- 鲜血DK
    [104] = "tank",   -- 守护德
    [268] = "tank",   -- 酒仙僧
    [581] = "tank",   -- 复仇DH
    -- Healer
    [65]   = "healer",  -- 神圣骑
    [105]  = "healer",  -- 恢复德
    [256]  = "healer",  -- 戒律牧
    [257]  = "healer",  -- 神圣牧
    [264]  = "healer",  -- 恢复萨
    [270]  = "healer",  -- 织雾僧
    [1468] = "healer",  -- 恩护龙
}

-- 专精名称（中英文）→ specID 列表
-- 重名专精映射到多个 ID，通过 AND 职业条件消歧
local SPEC_NAME_TO_IDS = {
    -- 战士
    ["武器"] = {71}, ["arms"] = {71},
    ["狂怒"] = {72}, ["fury"] = {72},
    -- 圣骑士
    ["惩戒"] = {70}, ["retribution"] = {70},
    -- 猎人
    ["野兽控制"] = {253}, ["beast mastery"] = {253},
    ["射击"] = {254}, ["marksmanship"] = {254},
    ["生存"] = {255}, ["survival"] = {255},
    -- 潜行者
    ["奇袭"] = {259}, ["assassination"] = {259},
    ["狂徒"] = {260}, ["outlaw"] = {260},
    ["敏锐"] = {261}, ["subtlety"] = {261},
    -- 牧师
    ["戒律"] = {256}, ["discipline"] = {256},
    ["暗影"] = {258}, ["shadow"] = {258},
    -- 死亡骑士
    ["鲜血"] = {250}, ["blood"] = {250},
    ["邪恶"] = {252}, ["unholy"] = {252},
    -- 萨满
    ["元素"] = {262}, ["elemental"] = {262},
    ["增强"] = {263}, ["enhancement"] = {263},
    -- 法师
    ["奥术"] = {62}, ["arcane"] = {62},
    ["火焰"] = {63}, ["fire"] = {63},
    -- 术士
    ["痛苦"] = {265}, ["affliction"] = {265},
    ["恶魔学识"] = {266}, ["demonology"] = {266},
    -- 武僧
    ["酒仙"] = {268}, ["brewmaster"] = {268},
    ["踏风"] = {269}, ["windwalker"] = {269},
    ["织雾"] = {270}, ["mistweaver"] = {270},
    -- 德鲁伊
    ["平衡"] = {102}, ["balance"] = {102},
    ["野性"] = {103}, ["feral"] = {103},
    ["守护"] = {104}, ["guardian"] = {104},
    -- 恶魔猎手
    ["浩劫"] = {577}, ["havoc"] = {577},
    ["复仇"] = {581}, ["vengeance"] = {581},
    ["食灵者"] = {1480},
    -- 唤魔师
    ["湮灭"] = {1467}, ["devastation"] = {1467},
    ["恩护"] = {1468}, ["preservation"] = {1468},
    ["增辉"] = {1473}, ["augmentation"] = {1473},
    -- 重名专精（匹配多个 specID）
    ["神圣"] = {65, 257}, ["holy"] = {65, 257},
    ["防护"] = {73, 66},  ["protection"] = {73, 66},
    ["冰霜"] = {64, 252}, ["frost"] = {64, 252},
    ["恢复"] = {264, 105}, ["restoration"] = {264, 105},
    ["毁灭"] = {267, 1467}, ["destruction"] = {267},
}

local function TrimText(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function SpecHint(classFile, specID)
    return {
        classFile = classFile,
        specID = specID,
    }
end

-- [人员] 槽位名的显示推断：仅用于离线时间轴行头补职业色/专精图标。
-- 规则保守：去掉末尾数字后精确匹配，不做包含/模糊猜测，避免自定义代号误染色。
local SLOT_SPEC_VISUAL_HINTS = {
    -- 战士
    zst = SpecHint("WARRIOR", 73), fz = SpecHint("WARRIOR", 73),
    ["防战"] = SpecHint("WARRIOR", 73), ["防戰"] = SpecHint("WARRIOR", 73),
    wqz = SpecHint("WARRIOR", 71), ["武器战"] = SpecHint("WARRIOR", 71), ["武器戰"] = SpecHint("WARRIOR", 71),
    kbz = SpecHint("WARRIOR", 72), ["狂暴战"] = SpecHint("WARRIOR", 72), ["狂暴戰"] = SpecHint("WARRIOR", 72),

    -- 圣骑士
    nq = SpecHint("PALADIN", 65), ["奶骑"] = SpecHint("PALADIN", 65), ["奶騎"] = SpecHint("PALADIN", 65),
    ["神圣骑"] = SpecHint("PALADIN", 65), ["神聖騎"] = SpecHint("PALADIN", 65),
    fq = SpecHint("PALADIN", 66), ["防骑"] = SpecHint("PALADIN", 66), ["防騎"] = SpecHint("PALADIN", 66),
    cjq = SpecHint("PALADIN", 70), ["惩戒骑"] = SpecHint("PALADIN", 70), ["懲戒騎"] = SpecHint("PALADIN", 70),

    -- 牧师
    jlm = SpecHint("PRIEST", 256), ["戒律牧"] = SpecHint("PRIEST", 256),
    ["神牧"] = SpecHint("PRIEST", 257), ["神圣牧"] = SpecHint("PRIEST", 257), ["神聖牧"] = SpecHint("PRIEST", 257),
    am = SpecHint("PRIEST", 258), ["暗牧"] = SpecHint("PRIEST", 258),

    -- 死亡骑士
    dkt = SpecHint("DEATHKNIGHT", 250), ["血dk"] = SpecHint("DEATHKNIGHT", 250), ["血DK"] = SpecHint("DEATHKNIGHT", 250),
    ["冰dk"] = SpecHint("DEATHKNIGHT", 251), ["冰DK"] = SpecHint("DEATHKNIGHT", 251),
    ["邪dk"] = SpecHint("DEATHKNIGHT", 252), ["邪DK"] = SpecHint("DEATHKNIGHT", 252),

    -- 萨满
    ns = SpecHint("SHAMAN", 264), ["奶萨"] = SpecHint("SHAMAN", 264), ["奶薩"] = SpecHint("SHAMAN", 264),
    ["恢复萨"] = SpecHint("SHAMAN", 264), ["恢復薩"] = SpecHint("SHAMAN", 264),
    ["元素萨"] = SpecHint("SHAMAN", 262), ["元素薩"] = SpecHint("SHAMAN", 262),
    zqs = SpecHint("SHAMAN", 263), ["增强萨"] = SpecHint("SHAMAN", 263), ["增強薩"] = SpecHint("SHAMAN", 263),

    -- 武僧
    wst = SpecHint("MONK", 268), ["酒仙"] = SpecHint("MONK", 268),
    ["奶僧"] = SpecHint("MONK", 270), ["织雾"] = SpecHint("MONK", 270), ["織霧"] = SpecHint("MONK", 270),
    ["踏风"] = SpecHint("MONK", 269), ["踏風"] = SpecHint("MONK", 269),

    -- 德鲁伊
    nd = SpecHint("DRUID", 105), ["奶德"] = SpecHint("DRUID", 105),
    ["恢复德"] = SpecHint("DRUID", 105), ["恢復德"] = SpecHint("DRUID", 105),
    ["鸟德"] = SpecHint("DRUID", 102), ["鳥德"] = SpecHint("DRUID", 102), ["鹌鹑"] = SpecHint("DRUID", 102), ["鵪鶉"] = SpecHint("DRUID", 102),
    ["平衡德"] = SpecHint("DRUID", 102), ["猫德"] = SpecHint("DRUID", 103), ["貓德"] = SpecHint("DRUID", 103),
    ["熊德"] = SpecHint("DRUID", 104), ["熊t"] = SpecHint("DRUID", 104), ["熊T"] = SpecHint("DRUID", 104), ["熊d"] = SpecHint("DRUID", 104), ["熊D"] = SpecHint("DRUID", 104),

    -- 恶魔猎手
    ["浩劫dh"] = SpecHint("DEMONHUNTER", 577), ["浩劫DH"] = SpecHint("DEMONHUNTER", 577),
    dht = SpecHint("DEMONHUNTER", 581), ["复仇dh"] = SpecHint("DEMONHUNTER", 581), ["复仇DH"] = SpecHint("DEMONHUNTER", 581),

    -- 唤魔师
    ["奶龙"] = SpecHint("EVOKER", 1468), ["奶龍"] = SpecHint("EVOKER", 1468), ["恩护"] = SpecHint("EVOKER", 1468),
    ["增辉"] = SpecHint("EVOKER", 1473), ["湮灭"] = SpecHint("EVOKER", 1467),

    -- 其他常见输出简称
    ["奥法"] = SpecHint("MAGE", 62), ["奧法"] = SpecHint("MAGE", 62),
    ["火法"] = SpecHint("MAGE", 63), ["冰法"] = SpecHint("MAGE", 64),
    ["兽王猎"] = SpecHint("HUNTER", 253), ["獸王獵"] = SpecHint("HUNTER", 253),
    ["射击猎"] = SpecHint("HUNTER", 254), ["射擊獵"] = SpecHint("HUNTER", 254),
    ["生存猎"] = SpecHint("HUNTER", 255), ["生存獵"] = SpecHint("HUNTER", 255),
}

local SLOT_CLASS_VISUAL_HINTS = {
    zs = "WARRIOR", ["战士"] = "WARRIOR", ["戰士"] = "WARRIOR",
    qs = "PALADIN", ["骑士"] = "PALADIN", ["騎士"] = "PALADIN", ["圣骑"] = "PALADIN", ["聖騎"] = "PALADIN",
    lr = "HUNTER", ["猎人"] = "HUNTER", ["獵人"] = "HUNTER",
    dz = "ROGUE", ["盗贼"] = "ROGUE", ["盜賊"] = "ROGUE", ["潜行者"] = "ROGUE",
    ms = "PRIEST", ["牧师"] = "PRIEST", ["牧師"] = "PRIEST",
    dk = "DEATHKNIGHT", ["死亡骑士"] = "DEATHKNIGHT", ["死亡騎士"] = "DEATHKNIGHT",
    sm = "SHAMAN", ["萨满"] = "SHAMAN", ["薩滿"] = "SHAMAN", ["萨满祭司"] = "SHAMAN",
    fs = "MAGE", ["法师"] = "MAGE", ["法師"] = "MAGE",
    ss = "WARLOCK", ["术士"] = "WARLOCK", ["術士"] = "WARLOCK",
    ws = "MONK", ["武僧"] = "MONK",
    d = "DRUID", xd = "DRUID", ["小德"] = "DRUID", ["德鲁伊"] = "DRUID", ["德魯伊"] = "DRUID",
    dh = "DEMONHUNTER", ["恶魔猎手"] = "DEMONHUNTER", ["惡魔獵手"] = "DEMONHUNTER",
    ["龙"] = "EVOKER", ["龍"] = "EVOKER", ["唤魔师"] = "EVOKER", ["喚魔師"] = "EVOKER",
}

local slotVisualConflictLogSeen = {}

local function NormalizeSlotVisualAlias(rawName)
    local text = TrimText(rawName)
    if text == "" then
        return "", ""
    end
    text = text:gsub("%d+$", "")
    text = TrimText(text)
    return text, text:lower()
end

local function CopyVisualHint(hint)
    if type(hint) ~= "table" then
        return nil
    end
    return {
        classFile = hint.classFile,
        specID = tonumber(hint.specID),
    }
end

function T.ResolveSlotVisualHint(slotName)
    local exact, lower = NormalizeSlotVisualAlias(slotName)
    if exact == "" then
        return nil
    end

    local specHint = SLOT_SPEC_VISUAL_HINTS[lower] or SLOT_SPEC_VISUAL_HINTS[exact]
    if specHint then
        return CopyVisualHint(specHint)
    end

    local classFile = SLOT_CLASS_VISUAL_HINTS[lower] or SLOT_CLASS_VISUAL_HINTS[exact]
    if classFile then
        return { classFile = classFile }
    end
    return nil
end

function T.ResolveCustomSlotVisualHint(specID)
    local id = tonumber(specID)
    if not id or id <= 0 then
        return nil
    end
    local classFile
    if GetSpecializationInfoByID then
        local ok, _, _, _, _, _, specClass = pcall(GetSpecializationInfoByID, id)
        if ok then
            classFile = specClass
        end
    end
    return {
        classFile = classFile,
        specID = math.floor(id + 0.5),
    }
end

local function NormalizeSlotVisualPlayerName(rawName)
    local text = TrimText(rawName)
    if text == "" then
        return ""
    end
    if T.STNTemplate and T.STNTemplate.StripColorCodes then
        text = T.STNTemplate.StripColorCodes(text)
        text = TrimText(text)
    end
    return text
end

local function BuildPlayerNameKeys(playerName)
    local text = NormalizeSlotVisualPlayerName(playerName)
    if text == "" then
        return nil
    end

    local keys = { text }
    local short = text:match("^([^-]+)%-.+$")
    if short and short ~= "" and short ~= text then
        keys[#keys + 1] = TrimText(short)
    end
    return keys
end

local function LogSlotVisualConflict(playerName, left, right, reason)
    if not (C and C.DB and C.DB.debugMode and T and T.debug) then
        return
    end
    local key = table.concat({
        tostring(playerName or ""),
        tostring(left and left.classFile or ""),
        tostring(left and left.specID or ""),
        tostring(right and right.classFile or ""),
        tostring(right and right.specID or ""),
        tostring(reason or ""),
    }, "|")
    if slotVisualConflictLogSeen[key] then
        return
    end
    slotVisualConflictLogSeen[key] = true
    T.debug("[SlotVisualHint] conflict player=%s reason=%s left=%s/%s right=%s/%s",
        tostring(playerName or ""),
        tostring(reason or ""),
        tostring(left and left.classFile or ""),
        tostring(left and left.specID or ""),
        tostring(right and right.classFile or ""),
        tostring(right and right.specID or ""))
end

local function MergeSlotVisualHint(playerName, existing, incoming)
    if type(existing) ~= "table" then
        return CopyVisualHint(incoming)
    end
    if type(incoming) ~= "table" then
        return existing
    end

    local existingClass = existing.classFile
    local incomingClass = incoming.classFile
    if existingClass and incomingClass and existingClass ~= incomingClass then
        LogSlotVisualConflict(playerName, existing, incoming, "class_mismatch")
        return {}
    end

    existing.classFile = existingClass or incomingClass
    local existingSpec = tonumber(existing.specID)
    local incomingSpec = tonumber(incoming.specID)
    if existingSpec and incomingSpec and existingSpec ~= incomingSpec then
        LogSlotVisualConflict(playerName, existing, incoming, "spec_mismatch")
        existing.specID = nil
        return existing
    end

    existing.specID = existingSpec or incomingSpec
    return existing
end

local function HasAnyKey(values)
    for _ in pairs(values or {}) do
        return true
    end
    return false
end

function T.BuildSlotVisualHints(slots, usedSlots, slotVisualSpecs)
    if type(slots) ~= "table" then
        return nil
    end

    local out = {}
    local hasAny = false
    local filterUsedSlots = HasAnyKey(usedSlots)
    for slotName, slotValue in pairs(slots) do
        local isUsed = (not filterUsedSlots) or (type(usedSlots) == "table" and usedSlots[slotName] == true)
        local hint = isUsed and T.ResolveSlotVisualHint(slotName) or nil
        if isUsed and not (hint and hint.specID) and type(slotVisualSpecs) == "table" then
            local customHint = T.ResolveCustomSlotVisualHint(slotVisualSpecs[slotName])
            if customHint then
                hint = MergeSlotVisualHint(slotName, hint, customHint)
            end
        end
        if hint and hint.classFile then
            for playerName in tostring(slotValue or ""):gmatch("[^,]+") do
                local keys = BuildPlayerNameKeys(playerName)
                for _, key in ipairs(keys or {}) do
                    out[key] = MergeSlotVisualHint(key, out[key], hint)
                    hasAny = true
                end
            end
        end
    end

    return hasAny and out or nil
end

function T.MergeSlotVisualHintMaps(left, right)
    if type(left) ~= "table" then
        left = nil
    end
    if type(right) ~= "table" then
        return left
    end

    local out = {}
    local hasAny = false
    for playerName, hint in pairs(left or {}) do
        out[tostring(playerName or "")] = CopyVisualHint(hint)
        hasAny = true
    end
    for playerName, hint in pairs(right) do
        local key = tostring(playerName or "")
        out[key] = MergeSlotVisualHint(key, out[key], hint)
        hasAny = true
    end
    return hasAny and out or nil
end

-- 获取玩家英文职业token（全大写）与本地化职业名
local function GetPlayerClass()
    local localized, token = UnitClass("player")
    return (token or ""), (localized or "")
end

-- 获取玩家职责（tank/healer/damager/none 小写）
-- 优先按专精判定，非组队场景也能工作；专精未就绪时兜底用组队分配。
local function GetPlayerRole()
    local specIndex = GetSpecialization()
    if specIndex then
        local specID = GetSpecializationInfo(specIndex)
        if specID then
            return SPEC_TO_ROLE[specID] or "damager"
        end
    end
    local role = UnitGroupRolesAssigned("player")
    if type(role) == "string" then
        role = role:lower()
        if role == "tank" or role == "healer" or role == "damager" then
            return role
        end
    end
    return "none"
end

-- 获取玩家所在小队（1-8），非团队返回0
local function GetPlayerGroup()
    if not IsInRaid() then return 0 end
    local me = UnitName("player")
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name == me then
            return subgroup or 0
        end
    end
    return 0
end

-- 获取玩家当前专精ID
local function GetPlayerSpecID()
    local specIndex = GetSpecialization()
    if specIndex then
        return GetSpecializationInfo(specIndex)
    end
    return nil
end

-- 判断玩家是否为"近战"
local function IsPlayerMelee()
    local token = select(2, UnitClass("player"))
    local specID = GetPlayerSpecID()
    if specID then
        return MELEE_SPEC_IDS[specID] == true
    end
    -- 未获取到专精：用全近战职业作兜底判断
    if token and ALWAYS_MELEE_CLASS[token] then
        return true
    end
    return false
end

function T.ResolveConditionSpecIDs(condition)
    local cond = type(condition) == "string" and condition:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if cond == "" then
        return nil
    end

    local condLower = cond:lower()
    local key = SPEC_NAME_TO_IDS[condLower] and condLower or cond
    local ids = SPEC_NAME_TO_IDS[key]
    if not ids then
        return nil
    end

    local out = {}
    for index, id in ipairs(ids) do
        out[index] = id
    end
    return out
end

function T.ResolveSpecRole(specID)
    return SPEC_TO_ROLE[tonumber(specID) or 0] or "damager"
end

-- 匹配单个条件
local function MatchSingleCondition(condition)
    if not condition or condition == "" then return false end
    local cond = condition:gsub("^%s+", ""):gsub("%s+$", "")
    local condLower = cond:lower()

    -- 全团
    if CONDITION_TYPES[condLower] == 4 or CONDITION_TYPES[cond] == 4 then
        return C.DB.filterAll ~= false
    end

    -- Boss：仅用于显示单元格，永不匹配玩家播报
    if CONDITION_TYPES[condLower] == 5 or CONDITION_TYPES[cond] == 5 then
        return false
    end

    -- 小队 g1..g8
    local gnum = condLower:match("^g([1-8])$")
    if gnum then
        if C.DB.filterParty == false then return false end
        return tonumber(gnum) == GetPlayerGroup()
    end

    -- 职责
    if CONDITION_TYPES[condLower] == 2 or CONDITION_TYPES[cond] == 2 then
        if C.DB.filterRole == false then return false end
        local role = GetPlayerRole()
        if condLower == "healer" or condLower == "heal" or cond == "治疗" then
            return role == "healer"
        elseif condLower == "tank" or cond == "坦克" then
            return role == "tank"
        elseif condLower == "dd" or condLower == "dps" or condLower == "damager" or cond == "输出" then
            return role == "damager"
        end
        return false
    end

    -- 近战/远程
    if CONDITION_TYPES[condLower] == 3 or CONDITION_TYPES[cond] == 3 then
        if C.DB.filterPos == false then return false end
        local melee = IsPlayerMelee()
        if condLower == "melee" or cond == "近战" then
            return melee
        elseif condLower == "ranged" or cond == "远程" then
            return not melee
        end
        return false
    end

    -- 专精
    if CONDITION_TYPES[condLower] == 6 or CONDITION_TYPES[cond] == 6 then
        if C.DB.filterClass == false then return false end
        local specID = GetPlayerSpecID()
        if not specID then return false end
        local key = SPEC_NAME_TO_IDS[condLower] and condLower or cond
        local ids = SPEC_NAME_TO_IDS[key]
        if not ids then return false end
        for _, id in ipairs(ids) do
            if id == specID then return true end
        end
        return false
    end

    -- 职业
    if CONDITION_TYPES[condLower] == 1 or CONDITION_TYPES[cond] == 1 then
        if C.DB.filterClass == false then return false end
        local token, localized = GetPlayerClass()
        local lowerToken = token and CLASS_TOKENS[token] or ""
        if condLower ~= "" and lowerToken == condLower then
            return true
        end
        if localized ~= "" and localized == cond then
            return true
        end
        return false
    end

    return false
end

local function NormalizeBroadcastName(name)
    local value = (type(name) == "string") and name or ""
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if T.STNTemplate and T.STNTemplate.StripColorCodes then
        value = T.STNTemplate.StripColorCodes(value)
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function SplitBroadcastName(name)
    local value = NormalizeBroadcastName(name)
    if value == "" then
        return "", ""
    end
    local short, realm = value:match("^([^-]+)%-(.+)$")
    if short and realm then
        return NormalizeBroadcastName(short), NormalizeBroadcastName(realm)
    end
    return value, ""
end

local function ReadCurrentPlayerName()
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    end
    if not name or name == "" then
        name, realm = UnitName("player")
    end

    local shortName, nameRealm = SplitBroadcastName(name)
    realm = NormalizeBroadcastName(realm)
    if realm == "" then
        realm = nameRealm
    end
    return shortName, realm
end

local function IsBroadcastNameMatch(targetName, playerName, playerRealm)
    local targetShort, targetRealm = SplitBroadcastName(targetName)
    if targetShort == "" or playerName == "" then
        return false
    end
    if targetRealm ~= "" and playerRealm ~= "" then
        return targetShort == playerName and targetRealm == playerRealm
    end
    return targetShort == playerName
end

-- 主函数：是否对玩家播报
-- conditionText 形如 "近战"/"healer,tank"/"g1"/"所有人"
-- 支持 AND（+）与 OR（,）：+ 优先级高于 ,
-- 示例："坦克+g1,治疗" = (坦克 AND 1队) OR 治疗
function T.ShouldBroadcastToPlayer(conditionText)
    if not conditionText or conditionText == "" then
        return true -- 无条件则对所有人播报
    end

    for orGroup in string.gmatch(conditionText, "[^,]+") do
        local allMatch = true
        for andTerm in string.gmatch(orGroup, "[^+]+") do
            if not MatchSingleCondition(andTerm) then
                allMatch = false
                break
            end
        end
        if allMatch then return true end
    end
    return false
end

-- 判断一个 {token} 是否为"组条件"标记（而非玩家ID/昵称）
-- 规则：
-- 1) token 在 CONDITION_TYPES 中，或
-- 2) 形如 g1..g8，或
-- 3) 逗号分隔的多个均满足 1/2
function T.IsGroupConditionToken(token)
    if not token or token == "" then return false end
    local t = token:gsub("^%s+", ""):gsub("%s+$", "")
    local function singleOk(x)
        local xl = x:lower()
        if CONDITION_TYPES[xl] or CONDITION_TYPES[x] then return true end
        if xl:match("^g[1-8]$") then return true end
        return false
    end
    -- 外层按逗号（OR）拆分，内层按加号（AND）拆分
    for orPart in string.gmatch(t, "[^,]+") do
        if orPart:find("+", 1, true) then
            for andPart in string.gmatch(orPart, "[^+]+") do
                if not singleOk(andPart) then return false end
            end
        else
            if not singleOk(orPart) then return false end
        end
    end
    return true
end

-- 名单匹配：若 names 为空视为不过滤；否则命中"我的昵称"或"当前角色ID"任一即通过
function T.ShouldBroadcastForNames(names)
    if type(names) ~= "table" or #names == 0 then return true end
    return T.DoesAudienceNameTargetPlayer(names)
end

-- 严格名单命中：仅明确写了当前角色名或我的昵称时返回 true。
function T.DoesAudienceNameTargetPlayer(names)
    if type(names) ~= "table" or #names == 0 then return false end
    local myName, myRealm = ReadCurrentPlayerName()
    local myNick = NormalizeBroadcastName(C and C.DB and C.DB.mynickname or "")
    for _, n in ipairs(names) do
        if myNick ~= "" and NormalizeBroadcastName(n) == myNick then
            return true
        end
        if IsBroadcastNameMatch(n, myName, myRealm) then
            return true
        end
    end
    return false
end

end)
