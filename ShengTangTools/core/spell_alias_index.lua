local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

-- 反向技能别名索引：中文名 → spellID
-- 数据源：内置方案 `T.SemanticBuiltinPlansS14` 中出现过的 `{spell:ID}`，
-- 外加 GUI 层运行中增量喂入的玩家方案文本。所有 ID 通过 C_Spell API 正向
-- 查询得到官方名字，再反向入库。无需手动维护字典。

local Index = {}
T.SpellAliasIndex = Index

local nameToEntries = {}
local knownIDs = {}
local pendingIDs = {}
local built = false

local SPELL_ID_SCAN_PATTERN = "{spell:(%d+)"

local function D()
    return T.Profile and T.Profile:GetActiveData() or nil
end

local function LookupSpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        local name = info and info.name or nil
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

local function SortEntries(entries)
    table.sort(entries, function(a, b)
        if a.freq ~= b.freq then
            return a.freq > b.freq
        end
        return a.id < b.id
    end)
end

local function RecordName(name, id, freq)
    local entries = nameToEntries[name]
    if not entries then
        entries = {}
        nameToEntries[name] = entries
    end
    for _, entry in ipairs(entries) do
        if entry.id == id then
            entry.freq = entry.freq + freq
            SortEntries(entries)
            return
        end
    end
    entries[#entries + 1] = { id = id, freq = freq }
    SortEntries(entries)
end

local function TryResolveID(id, freq)
    id = tonumber(id)
    if not id or id <= 0 then
        return false
    end
    freq = freq or 1
    knownIDs[id] = (knownIDs[id] or 0) + freq
    local name = LookupSpellName(id)
    if name then
        RecordName(name, id, freq)
        pendingIDs[id] = nil
        return true
    end
    pendingIDs[id] = true
    if C_Spell and C_Spell.RequestLoadSpellData then
        C_Spell.RequestLoadSpellData(id)
    end
    return false
end

function Index.IngestText(text)
    if type(text) ~= "string" or text == "" then
        return
    end
    for idStr in text:gmatch(SPELL_ID_SCAN_PATTERN) do
        TryResolveID(idStr, 1)
    end
end

function Index.RetryPending()
    local resolved = 0
    local remaining = {}
    for id in pairs(pendingIDs) do
        local name = LookupSpellName(id)
        if name then
            local freq = knownIDs[id] or 1
            RecordName(name, id, freq)
            resolved = resolved + 1
        else
            remaining[id] = true
        end
    end
    pendingIDs = remaining
    return resolved
end

-- 递归扫描任意 nested table：所有 number key 作为 spellID 候选入库；
-- 所有 string value 走 IngestText 扫 {spell:ID}；嵌套 table 继续递归。
-- 查不到 API 名字的 ID 进 pending，不污染字典（例如 BuffCheck.RuneItems 里的 itemID）。
local function IngestTable(tbl, depth)
    if type(tbl) ~= "table" or (depth or 0) > 6 then
        return
    end
    for k, v in pairs(tbl) do
        if type(k) == "number" and k > 0 then
            TryResolveID(k, 1)
        end
        if type(v) == "string" then
            Index.IngestText(v)
        elseif type(v) == "table" then
            IngestTable(v, (depth or 0) + 1)
        end
    end
end

function Index.Build()
    if built then
        return
    end
    -- 只扫"玩家战术文本里真会写到的"spellID 来源，避免引入大量无关的
    -- 光环监控/团队增益 ID 导致字典污染（那些表里某些 spell 的中文名恰好
    -- 是"空射""单射"这类通用战术术语，会把玩家的自定义短语误识别为技能名）
    IngestTable(T.SemanticBuiltinPlansS14, 0)
    if STT_DB and D() and type(D().Plans) == "table" then
        for _, text in pairs(D().Plans) do
            if type(text) == "string" then
                Index.IngestText(text)
            end
        end
    end
    built = true
end

function Index.Reset()
    nameToEntries = {}
    knownIDs = {}
    pendingIDs = {}
    built = false
end

function Index.GetNames()
    local out = {}
    for name, entries in pairs(nameToEntries) do
        local primary = entries[1]
        if primary then
            out[#out + 1] = { name = name, id = primary.id }
        end
    end
    return out
end

function Index.GetIDByName(name)
    local entries = nameToEntries[name]
    if entries and entries[1] then
        return entries[1].id
    end
    return nil
end

function Index.IsReady()
    return built and next(nameToEntries) ~= nil
end

function Index.HasPending()
    return next(pendingIDs) ~= nil
end

if T.events then
    T.events:Register("STT_PROFILE_CHANGED", Index, function(self)
        self.Reset()
        self.Build()
    end)
end

end)
