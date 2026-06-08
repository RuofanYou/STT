local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local Logic = {}
T.SkillPickerLogic = Logic

local bossAliasIndex
local searchIndex
local lastSearchLogKey
local SEARCH_LOG_RENDER_LIMIT = 160
local CLASS_LABEL = {
    DEATHKNIGHT = "死亡骑士", DEMONHUNTER = "恶魔猎手", DRUID = "德鲁伊", EVOKER = "唤魔师",
    HUNTER = "猎人", MAGE = "法师", MONK = "武僧", PALADIN = "圣骑士", PRIEST = "牧师",
    ROGUE = "潜行者", SHAMAN = "萨满祭司", WARLOCK = "术士", WARRIOR = "战士",
}
local SPEC_LABEL = {
    GENERAL = "通用", BLOOD = "鲜血", FROST = "冰霜", UNHOLY = "邪恶", HAVOC = "浩劫",
    VENGEANCE = "复仇", BALANCE = "平衡", FERAL = "野性", GUARDIAN = "守护",
    RESTORATION = "恢复", DEVASTATION = "湮灭", PRESERVATION = "恩护", AUGMENTATION = "增辉",
    BEAST_MASTERY = "野兽控制", MARKSMANSHIP = "射击", SURVIVAL = "生存", ARCANE = "奥术",
    FIRE = "火焰", BREWMASTER = "酒仙", MISTWEAVER = "织雾", WINDWALKER = "踏风",
    HOLY = "神圣", PROTECTION = "防护", RETRIBUTION = "惩戒", DISCIPLINE = "戒律",
    SHADOW = "暗影", ASSASSINATION = "奇袭", OUTLAW = "狂徒", SUBTLETY = "敏锐",
    ELEMENTAL = "元素", ENHANCEMENT = "增强", AFFLICTION = "痛苦", DEMONOLOGY = "恶魔学识",
    DESTRUCTION = "毁灭", ARMS = "武器", FURY = "狂怒",
}

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeLookup(value)
    local text = Trim(value):lower()
    text = text:gsub("[%s%p]+", ""):gsub("·", ""):gsub("’", "")
    return text
end

local function HasChinese(text)
    return type(text) == "string" and text:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end

local function IsChineseChar(char)
    return type(char) == "string" and char:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end

local function IsLatinLookup(text)
    return type(text) == "string" and text:match("^[%w]+$") ~= nil
end

local function IsTimelineSpell(spellID)
    local id = tonumber(spellID)
    local blocked = T.Data and T.Data.NonTimelineSpellIDs
    return id and not (blocked and blocked[id])
end

local function IterUTF8(text)
    text = tostring(text or "")
    return text:gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

local function FormatTime(seconds)
    local value = math.max(0, tonumber(seconds) or 0)
    if math.abs(value - math.floor(value + 0.5)) < 0.0001 then
        local rounded = math.floor(value + 0.5)
        return string.format("%02d:%02d", math.floor(rounded / 60), rounded % 60)
    end
    local min = math.floor(value / 60)
    local sec = value - (min * 60)
    return string.format("%02d:%04.1f", min, sec)
end

local function BuildTimePayload(ctx)
    if type(ctx) ~= "table" then
        return FormatTime(0)
    end
    local phase = Trim(ctx.phase)
    if phase ~= "" then
        local sourceTime = tonumber(ctx.sourceTime)
        if not sourceTime then
            sourceTime = (tonumber(ctx.time) or 0) - (tonumber(ctx.phaseDisplayOffset) or 0)
        end
        return FormatTime(math.max(0, sourceTime or 0)) .. "," .. phase
    end
    return FormatTime(ctx.time)
end

local function FormatNumber(value)
    local number = tonumber(value)
    if not number then
        return nil
    end
    if math.abs(number - math.floor(number + 0.5)) < 0.0001 then
        return tostring(math.floor(number + 0.5))
    end
    return string.format("%.1f", number):gsub("0+$", ""):gsub("%.$", "")
end

local function BuildBossAliasIndex()
    if bossAliasIndex then
        return bossAliasIndex
    end
    bossAliasIndex = {}
    for bossID, boss in pairs(T.Data and T.Data.BossSpells or {}) do
        local function addAlias(alias)
            local key = NormalizeLookup(alias)
            if key ~= "" then
                bossAliasIndex[key] = tonumber(bossID)
            end
        end
        addAlias(boss.name)
        addAlias(boss.nameZh)
        for _, alias in ipairs(boss.aliases or {}) do
            addAlias(alias)
        end
    end
    return bossAliasIndex
end

local function ResolveRosterClass(rowName)
    local target = Trim(rowName)
    if target == "" then
        return nil
    end
    local shortName = target:match("^([^-]+)") or target
    if GetNumGroupMembers and GetRaidRosterInfo then
        for index = 1, GetNumGroupMembers() do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(index)
            local rosterShort = type(name) == "string" and (name:match("^([^-]+)") or name) or ""
            if rosterShort == shortName and type(classFile) == "string" and classFile ~= "" then
                return classFile
            end
        end
    end
    if UnitClass then
        local _, classFile = UnitClass(target)
        if type(classFile) == "string" and classFile ~= "" then
            return classFile
        end
    end
    return nil
end

function Logic.DetectRowKind(rowName, opts)
    local meta = type(opts) == "table" and opts.meta or nil
    local hintedClass = type(opts) == "table" and opts.class or nil
    local text = Trim(rowName)
    local metaKind = meta and meta.kind or nil
    if (metaKind == "boss" or metaKind == "npc") and tonumber(meta.encounterID) then
        return { kind = "boss", bossID = tonumber(meta.encounterID) }
    end
    if metaKind == "player" then
        local classFile = hintedClass or meta.classFile or (meta.playerInfo and meta.playerInfo.classFile) or ResolveRosterClass(text)
        if classFile then
            return { kind = "player", class = classFile }
        end
    end

    local bossID = BuildBossAliasIndex()[NormalizeLookup(text)]
    if bossID then
        return { kind = "boss", bossID = bossID }
    end

    local classFile = ResolveRosterClass(text)
    if classFile then
        return { kind = "player", class = classFile }
    end
    return { kind = "generic" }
end

function Logic.GetClassLabel(classFile)
    return CLASS_LABEL[tostring(classFile or "")] or tostring(classFile or "")
end

function Logic.GetSpecLabel(specKey)
    return SPEC_LABEL[tostring(specKey or "")] or tostring(specKey or "")
end

function Logic.FormatClassBreadcrumb(classFile, specKey)
    local classText = Logic.GetClassLabel(classFile)
    local specText = Logic.GetSpecLabel(specKey)
    if classText == "" then
        return specText
    end
    if specText == "" then
        return classText
    end
    return classText .. "/" .. specText
end

local function LookupSpellEntry(spellID)
    local id = tonumber(spellID)
    if not id then
        return nil
    end
    for _, classData in pairs(T.Data and T.Data.ClassSpells or {}) do
        for _, bucket in pairs(classData) do
            if type(bucket) == "table" and bucket[id] then
                return bucket[id]
            end
        end
    end
    for _, boss in pairs(T.Data and T.Data.BossSpells or {}) do
        if boss.spells and boss.spells[id] then
            return boss.spells[id]
        end
    end
    return nil
end

function Logic.GetSpellEntry(spellID)
    return LookupSpellEntry(spellID)
end

function Logic.GetSpellName(spellID, fallback)
    local id = tonumber(spellID)
    if id and C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    if id and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    local entry = LookupSpellEntry(id)
    if entry and type(entry.name) == "string" and entry.name ~= "" then
        return entry.name
    end
    return Trim(fallback) ~= "" and Trim(fallback) or "unknown"
end

function Logic.GetSpellIcon(spellID)
    local id = tonumber(spellID)
    if id and C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, id)
        if ok and icon then
            return icon
        end
    end
    if id and T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        return T.TimelineSyntax.ResolveSpellIcon(id)
    end
    return 134400
end

function Logic.GetSpellDuration(spellID, fallback)
    local number = tonumber(fallback)
    if number and number > 0 then
        return number
    end
    local entry = LookupSpellEntry(spellID)
    number = tonumber(entry and entry.dur)
    if number and number > 0 then
        return number
    end
    return nil
end

function Logic.BuildLine(ctx, spellID, dur)
    local id = tonumber(spellID)
    if not id or id <= 0 then
        return nil, "invalid_spell"
    end
    local timeText = BuildTimePayload(ctx)
    local name = Logic.GetSpellName(id)
    local duration = Logic.GetSpellDuration(id, dur)
    local spellToken = duration and string.format("{spell:%d,dur:%s}", id, FormatNumber(duration)) or string.format("{spell:%d}", id)
    local who = Trim(ctx and ctx.who or "")
    local targetToken = who ~= "" and (" {" .. who .. "}") or " "
    return string.format("{time:%s}%s%s<%s>", timeText, targetToken, spellToken, name)
end

function Logic.InsertSkillToken(ctx, spellID, dur)
    if type(ctx) ~= "table" then
        return false, "missing_context"
    end
    local line, reason = Logic.BuildLine(ctx, spellID, dur)
    if not line then
        return false, reason
    end
    if not (T.SemanticTimelineGUI and T.SemanticTimelineGUI.InsertTimelineLineByTime) then
        return false, "missing_editor"
    end
    local ok, err = T.SemanticTimelineGUI.InsertTimelineLineByTime(ctx, line, ctx.time, {
        source = "skill_picker",
    })
    if ok then
        if T.RecentSkills then
            T.RecentSkills.Push(ctx.class, spellID)
        end
        if T.debug then
            T.debug(string.format("[STT_SKILL_PICKER_INSERT] spellID=%s time=%.1f who=%s class=%s", tostring(spellID), tonumber(ctx.time) or 0, tostring(ctx.who or ""), tostring(ctx.class or "")))
        end
        return true
    end
    if T.debug then
        T.debug(string.format("[STT_SKILL_PICKER_INSERT_FAIL] spellID=%s reason=%s", tostring(spellID), tostring(err or "unknown")))
    end
    if T.msg then
        T.msg(string.format("添加技能失败：%s", tostring(err or "unknown")))
    end
    return false, err
end

local function AddSpell(out, seen, spellID, entry, breadcrumb)
    local id = tonumber(spellID)
    if not id or seen[id] or not IsTimelineSpell(id) then
        return
    end
    seen[id] = true
    out[#out + 1] = {
        spellID = id,
        name = Logic.GetSpellName(id, entry and entry.name),
        dur = Logic.GetSpellDuration(id, entry and entry.dur),
        icon = Logic.GetSpellIcon(id),
        category = entry and entry.category or nil,
        breadcrumb = breadcrumb,
        pinyin = T.Data and T.Data.SpellPinyin and T.Data.SpellPinyin[id] or nil,
    }
end

function Logic.GetClassSpells(classFile, bucketKey)
    local classData = T.Data and T.Data.ClassSpells and T.Data.ClassSpells[classFile]
    local out, seen = {}, {}
    if type(classData) ~= "table" then
        return out
    end
    local bucket = classData[bucketKey or "GENERAL"]
    if type(bucket) ~= "table" then
        return out
    end
    for spellID, entry in pairs(bucket) do
        AddSpell(out, seen, spellID, entry, Logic.FormatClassBreadcrumb(classFile, bucketKey or "GENERAL"))
    end
    table.sort(out, function(a, b)
        return tostring(a.name or a.spellID) < tostring(b.name or b.spellID)
    end)
    return out
end

function Logic.GetBossSpells(bossID)
    local boss = T.Data and T.Data.BossSpells and T.Data.BossSpells[tonumber(bossID)]
    local out, seen = {}, {}
    if not (boss and boss.spells) then
        return out
    end
    for spellID, entry in pairs(boss.spells) do
        AddSpell(out, seen, spellID, entry, boss.nameZh or boss.name or tostring(bossID))
    end
    table.sort(out, function(a, b)
        return tostring(a.name or a.spellID) < tostring(b.name or b.spellID)
    end)
    return out
end

local function AddSearchField(fields, text, weight, reason)
    local normalized = NormalizeLookup(text)
    if normalized ~= "" then
        fields[#fields + 1] = {
            text = normalized,
            weight = weight,
            reason = reason,
        }
    end
end

local function BuildPinyinFields(text)
    local hanziPinyin = T.Data and T.Data.HanziPinyin or nil
    if type(hanziPinyin) ~= "table" then
        return nil, nil
    end
    local syllables, initials = {}, {}
    for char in IterUTF8(text) do
        local py = hanziPinyin[char]
        if type(py) == "string" and py ~= "" then
            py = NormalizeLookup(py)
            if py ~= "" then
                syllables[#syllables + 1] = py
                initials[#initials + 1] = py:sub(1, 1)
            end
        elseif IsChineseChar(char) then
            return nil, nil
        end
    end
    if #syllables == 0 then
        return nil, nil
    end
    return table.concat(syllables, ""), table.concat(initials, "")
end

local function AddPinyinFields(fields, text, baseWeight)
    local full, initials = BuildPinyinFields(text)
    AddSearchField(fields, full, baseWeight, "pinyin")
    AddSearchField(fields, initials, baseWeight + 8, "initials")
end

local function AddAliasFields(fields, aliases)
    if type(aliases) == "table" then
        for _, alias in ipairs(aliases) do
            AddSearchField(fields, alias, 24, "alias")
            AddPinyinFields(fields, alias, 24)
        end
        return
    end
    if type(aliases) ~= "string" then
        return
    end
    for alias in aliases:gmatch("%S+") do
        AddSearchField(fields, alias, 24, "alias")
    end
end

local function BuildSearchIndex()
    if searchIndex then
        return searchIndex
    end
    local items, seen = {}, {}
    local function indexSpell(spellID, entry, breadcrumb)
        local before = #items
        AddSpell(items, seen, spellID, entry, breadcrumb)
        if #items == before then
            return
        end
        local item = items[#items]
        local staticName = entry and entry.name or nil
        local fields = {}
        AddSearchField(fields, item.name, 10, "name")
        AddSearchField(fields, staticName, 18, "staticName")
        AddAliasFields(fields, item.pinyin)
        AddPinyinFields(fields, item.name, 30)
        if staticName ~= item.name then
            AddPinyinFields(fields, staticName, 32)
        end
        AddSearchField(fields, item.category, 58, "category")
        AddSearchField(fields, item.breadcrumb, 62, "breadcrumb")
        item.searchFields = fields
        item.searchSortName = tostring(item.name or staticName or item.spellID)
    end

    for classFile, classData in pairs(T.Data and T.Data.ClassSpells or {}) do
        for bucketKey, bucket in pairs(classData) do
            if type(bucket) == "table" then
                for spellID, entry in pairs(bucket) do
                    indexSpell(spellID, entry, Logic.FormatClassBreadcrumb(classFile, bucketKey))
                end
            end
        end
    end
    for bossID, boss in pairs(T.Data and T.Data.BossSpells or {}) do
        for spellID, entry in pairs(boss.spells or {}) do
            indexSpell(spellID, entry, boss.nameZh or boss.name or tostring(bossID))
        end
    end

    table.sort(items, function(a, b)
        local nameA = tostring(a.searchSortName or a.name or a.spellID)
        local nameB = tostring(b.searchSortName or b.name or b.spellID)
        if nameA == nameB then
            return (a.spellID or 0) < (b.spellID or 0)
        end
        return nameA < nameB
    end)
    searchIndex = items
    return searchIndex
end

local function ScoreField(field, key)
    if field.text == key then
        return field.weight, field.reason
    end
    if field.text:find(key, 1, true) == 1 then
        return field.weight + 3, field.reason
    end
    local start = field.text:find(key, 1, true)
    if start then
        return field.weight + 10 + (start / 100), field.reason
    end
    return nil, nil
end

local function ScoreItem(item, key)
    local spellText = tostring(item.spellID or "")
    if spellText == key then
        return 0, "spellID"
    end
    if key:match("^%d+$") and spellText:find(key, 1, true) == 1 then
        return 5, "spellIDPrefix"
    end

    local bestScore, bestReason
    for _, field in ipairs(item.searchFields or {}) do
        local score, reason = ScoreField(field, key)
        if score and (not bestScore or score < bestScore) then
            bestScore, bestReason = score, reason
        end
    end
    return bestScore, bestReason
end

local function QueryIsAllowed(rawText, key)
    if key == "" then
        return true
    end
    if not HasChinese(rawText) and IsLatinLookup(key) and #key < 2 then
        return false
    end
    return true
end

local function DebugSearch(rawText, total, top)
    local key = NormalizeLookup(rawText)
    if key == lastSearchLogKey then
        return
    end
    lastSearchLogKey = key
    if not (T.debug and key ~= "") then
        return
    end
    T.debug(string.format(
        "[STT_SKILL_SEARCH] query=%s total=%d shown=%d top=%s reason=%s",
        tostring(rawText or ""),
        tonumber(total) or 0,
        math.min(tonumber(total) or 0, SEARCH_LOG_RENDER_LIMIT),
        top and tostring(top.spellID or "") or "",
        top and tostring(top.searchReason or "") or "none"
    ))
end

function Logic.ResetSpellSearchIndex()
    searchIndex = nil
    lastSearchLogKey = nil
end

function Logic.SearchSpells(keyword)
    local rawText = Trim(keyword)
    local key = NormalizeLookup(rawText)
    local items = BuildSearchIndex()
    if key == "" then
        return items
    end
    if not QueryIsAllowed(rawText, key) then
        DebugSearch(rawText, 0, nil)
        return {}
    end

    local filtered = {}
    for _, item in ipairs(items) do
        local score, reason = ScoreItem(item, key)
        if score then
            filtered[#filtered + 1] = {
                item = item,
                score = score,
                reason = reason,
            }
        end
    end
    table.sort(filtered, function(a, b)
        if a.score ~= b.score then
            return a.score < b.score
        end
        if (a.item.spellID or 0) ~= (b.item.spellID or 0) then
            return (a.item.spellID or 0) < (b.item.spellID or 0)
        end
        local nameA = tostring(a.item.searchSortName or a.item.name or a.item.spellID)
        local nameB = tostring(b.item.searchSortName or b.item.name or b.item.spellID)
        return nameA < nameB
    end)

    local out = {}
    for index, hit in ipairs(filtered) do
        hit.item.searchReason = hit.reason
        out[index] = hit.item
    end
    DebugSearch(rawText, #out, out[1])
    return out
end

end)
