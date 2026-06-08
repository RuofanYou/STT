local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local ExportImport = {}
T.ExportImport = ExportImport

local FORMAT_VERSION = 1
local MAX_IMPORT_BYTES = 500 * 1024

local TYPE_CODE_RAID = "R"
local TYPE_CODE_DUNGEON = "D"
local TYPE_CODE_SETTINGS = "S"
local TYPE_CODE_PLAN = "P"

local PLAN_FORMAT = "STT_PLANS"
local SETTINGS_FORMAT = "STT_SETTINGS"

local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)

local function D()
    return T.Profile and T.Profile:GetActiveData() or nil
end

local SETTINGS_EXCLUDE = {
    Profiles = true,
    CurrentProfileByChar = true,
    ActiveProfileID = true,
    ActiveProfileIDByChar = true,
    DefaultProfileID = true,
    _nextProfileID = true,
    _profileSchemaVersion = true,
    _schema = true,
    migrated_to_12 = true,
    _backup_v1 = true,
    mynickname = true,
    debugMode = true,
    devMode = true,
    safeMode = true,
    minimap = true,
    preferredLocale = true,
}

local SEMANTIC_TIMELINE_EXCLUDE = {
    notes = true,
    workbench = true,
    captured = true,
}

local function LogEvent(eventName, fields)
    if T and T.LogDebugEvent then
        T.LogDebugEvent(eventName, fields)
    end
end

local function Trim(text)
    local normalized = tostring(text or "")
    normalized = normalized:gsub("^%s+", "")
    normalized = normalized:gsub("%s+$", "")
    return normalized
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[DeepCopy(k)] = DeepCopy(v)
    end
    return out
end

local function CountEntries(value)
    local count = 0
    for _ in pairs(value or {}) do
        count = count + 1
    end
    return count
end

local function CountLeafNodes(value)
    if type(value) ~= "table" then
        return 1
    end

    local count = 0
    for _, child in pairs(value) do
        count = count + CountLeafNodes(child)
    end
    return count
end

local function GetSettingsDB()
    local db = STT_DB or C.DB or {}
    if C and C.DB ~= db then
        C.DB = db
    end
    return db
end

local function GetNote()
    return T and T.Note or nil
end

local function GetTypeName(typeCode)
    if typeCode == TYPE_CODE_RAID then
        return L["团本战术板"] or "团本战术板"
    end
    if typeCode == TYPE_CODE_DUNGEON then
        return L["大秘境战术板"] or "大秘境战术板"
    end
    if typeCode == TYPE_CODE_SETTINGS then
        return L["设置配置"] or "设置配置"
    end
    if typeCode == TYPE_CODE_PLAN then
        return L["单方案分享"] or "单方案分享"
    end
    return tostring(typeCode or "")
end

local function GetExpectedFormat(typeCode)
    if typeCode == TYPE_CODE_RAID or typeCode == TYPE_CODE_DUNGEON then
        return PLAN_FORMAT
    end
    if typeCode == TYPE_CODE_SETTINGS then
        return SETTINGS_FORMAT
    end
    return nil
end

local function NormalizeInstanceType(instanceType)
    local normalized = tostring(instanceType or ""):lower()
    if normalized == "raid" or normalized == "dungeon" then
        return normalized
    end
    return nil
end

local function MatchBossKey(instanceType, bossKey)
    local normalizedBossKey = T.NormalizeSemanticBossKeyText and T.NormalizeSemanticBossKeyText(bossKey) or nil
    if not normalizedBossKey then
        return nil
    end

    local prefix = tostring(instanceType or "") .. ":"
    if normalizedBossKey:sub(1, #prefix) ~= prefix then
        return nil
    end
    return normalizedBossKey
end

local function ShouldExcludeSetting(pathName, key)
    if not pathName then
        return SETTINGS_EXCLUDE[key] == true
    end
    if pathName == "semanticTimeline" then
        return SEMANTIC_TIMELINE_EXCLUDE[key] == true
    end
    return false
end

local function ResolvePath(path)
    local parts = {}
    if type(path) ~= "string" or path == "" then
        return parts
    end
    for segment in path:gmatch("[^%.]+") do
        parts[#parts + 1] = segment
    end
    return parts
end

local function WritePath(root, path, value)
    local parts = ResolvePath(path)
    if type(root) ~= "table" or #parts == 0 then
        return false
    end

    local current = root
    for index = 1, #parts - 1 do
        local key = parts[index]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    current[parts[#parts]] = value
    return true
end

local function ReadPath(root, path)
    local parts = ResolvePath(path)
    if type(root) ~= "table" or #parts == 0 then
        return nil, false
    end

    local current = root
    for index = 1, #parts do
        if type(current) ~= "table" then
            return nil, false
        end
        current = current[parts[index]]
        if current == nil then
            return nil, false
        end
    end
    return current, true
end

local function ClearPath(root, path)
    local parts = ResolvePath(path)
    if type(root) ~= "table" or #parts == 0 then
        return false
    end

    local current = root
    for index = 1, #parts - 1 do
        current = current[parts[index]]
        if type(current) ~= "table" then
            return false
        end
    end
    current[parts[#parts]] = nil
    return true
end

local function IsCustomOptionPushItem(itemDef)
    return type(itemDef) == "table"
        and itemDef.type == "custom"
        and itemDef.optionPush == true
        and type(itemDef.dbPath) == "string"
        and itemDef.dbPath ~= ""
end

local function GetOptionItems(moduleDef)
    if T.GetOptionModuleItems then
        return T.GetOptionModuleItems(moduleDef, T.OptionEngine)
    end
    if type(moduleDef) == "table" and type(moduleDef.itemsFactory) == "function" then
        local ok, items = pcall(moduleDef.itemsFactory, T.OptionEngine, moduleDef)
        if ok and type(items) == "table" then
            return items
        end
    end
    return moduleDef and moduleDef.items or {}
end

local function ForEachCustomOptionPushItem(callback)
    if type(callback) ~= "function" then
        return
    end
    for _, moduleDef in ipairs(T.OptionDefinitions or {}) do
        for _, itemDef in ipairs(GetOptionItems(moduleDef)) do
            if IsCustomOptionPushItem(itemDef) then
                callback(itemDef, moduleDef)
            end
        end
    end
end

local function CollectCustomOptionPushSettings(settings)
    if type(settings) ~= "table" then
        return 0
    end

    local changedCount = 0
    local engine = T.OptionEngine
    ForEachCustomOptionPushItem(function(itemDef)
        local value
        if engine and engine.GetItemValue then
            value = engine:GetItemValue(itemDef)
        elseif type(itemDef.getter) == "function" then
            value = itemDef.getter(engine, itemDef)
        end

        if value ~= nil then
            local leafCount = CountLeafNodes(value)
            if leafCount > 0 and WritePath(settings, itemDef.dbPath, DeepCopy(value)) then
                changedCount = changedCount + leafCount
            end
        end
    end)

    return changedCount
end

local function ApplyCustomOptionPushSettings(settings)
    if type(settings) ~= "table" then
        return 0, 0
    end

    local applied = 0
    local skipped = 0
    local engine = T.OptionEngine
    ForEachCustomOptionPushItem(function(itemDef, moduleDef)
        local value, found = ReadPath(settings, itemDef.dbPath)
        if not found then
            return
        end

        local leafCount = CountLeafNodes(value)
        if engine and engine.ApplyItem then
            engine:ApplyItem(itemDef, DeepCopy(value), moduleDef)
            applied = applied + leafCount
        elseif type(itemDef.setter) == "function" then
            itemDef.setter(DeepCopy(value), engine, itemDef)
            if type(itemDef.apply) == "function" then
                itemDef.apply(value, engine, itemDef, moduleDef)
            end
            applied = applied + leafCount
        else
            skipped = skipped + leafCount
        end
        ClearPath(settings, itemDef.dbPath)
    end)

    return applied, skipped
end

local function BuildSettingsDiff(currentValue, defaultValue, pathName)
    if type(defaultValue) ~= "table" then
        if currentValue == nil then
            return nil, 0
        end
        if type(currentValue) ~= type(defaultValue) then
            return nil, 0
        end
        if currentValue == defaultValue then
            return nil, 0
        end
        return DeepCopy(currentValue), 1
    end

    if type(currentValue) ~= "table" then
        currentValue = {}
    end

    local out = {}
    local changedCount = 0

    for key, childDefault in pairs(defaultValue) do
        if not ShouldExcludeSetting(pathName, key) then
            local childPath = pathName and (pathName .. "." .. tostring(key)) or tostring(key)
            local childValue, childCount = BuildSettingsDiff(currentValue[key], childDefault, childPath)
            if childValue ~= nil then
                out[key] = childValue
                changedCount = changedCount + childCount
            end
        end
    end

    if next(out) == nil then
        return nil, 0
    end

    return out, changedCount
end

local function ResetSettingsToDefaults(targetDB, defaultDB)
    for key in pairs(targetDB) do
        if not SETTINGS_EXCLUDE[key] and defaultDB[key] == nil then
            targetDB[key] = nil
        end
    end

    for key, value in pairs(defaultDB) do
        if not SETTINGS_EXCLUDE[key] then
            targetDB[key] = DeepCopy(value)
        end
    end
end

local function ApplySettingsDiff(targetDB, diffValue, defaultValue, pathName)
    if type(defaultValue) ~= "table" then
        if type(diffValue) ~= type(defaultValue) then
            return 0, 1
        end
        return 1, 0
    end

    if type(diffValue) ~= "table" then
        return 0, CountLeafNodes(diffValue)
    end

    if type(targetDB) ~= "table" then
        targetDB = {}
    end

    local applied = 0
    local skipped = 0

    for key, value in pairs(diffValue) do
        if ShouldExcludeSetting(pathName, key) then
            skipped = skipped + CountLeafNodes(value)
        else
            local defaultChild = defaultValue[key]
            if defaultChild == nil then
                skipped = skipped + CountLeafNodes(value)
            elseif type(defaultChild) == "table" then
                if type(value) ~= "table" then
                    skipped = skipped + CountLeafNodes(value)
                else
                    if type(targetDB[key]) ~= "table" then
                        targetDB[key] = DeepCopy(defaultChild)
                    end
                    local childApplied, childSkipped = ApplySettingsDiff(
                        targetDB[key],
                        value,
                        defaultChild,
                        pathName and (pathName .. "." .. tostring(key)) or tostring(key)
                    )
                    applied = applied + childApplied
                    skipped = skipped + childSkipped
                end
            else
                if type(value) ~= type(defaultChild) then
                    skipped = skipped + 1
                else
                    targetDB[key] = DeepCopy(value)
                    applied = applied + 1
                end
            end
        end
    end

    return applied, skipped
end

local function BuildPlanRecord(note, planID)
    local plan = note and note.GetPlan and note:GetPlan(planID) or nil
    if not plan then
        return nil
    end

    return {
        name = tostring(plan.name or ""),
        content = tostring(plan.content or ""),
        author = tostring(plan.author or ""),
        createdTime = tonumber(plan.created or 0) or 0,
        lastUpdateName = tostring(plan.lastUpdateName or ""),
        lastUpdateTime = tonumber(plan.lastUpdateTime or 0) or 0,
        kind = tostring(plan.kind or ""),
    }
end

local function CollectPlanMap(note, sourceMap, instanceType)
    local out = {}
    local count = 0

    for bossKey, planID in pairs(sourceMap or {}) do
        local normalizedBossKey = MatchBossKey(instanceType, bossKey)
        if normalizedBossKey then
            local record = BuildPlanRecord(note, planID)
            if record then
                out[normalizedBossKey] = record
                count = count + 1
            end
        end
    end

    return out, count
end

local function SortNumericList(values)
    table.sort(values, function(a, b)
        return tonumber(a) < tonumber(b)
    end)
    return values
end

local function DeletePlansByInstanceType(note, instanceType)
    local noteDB = STT_DB and D() or nil
    if not (note and note.DeletePlan and noteDB) then
        return 0
    end

    local ids = {}
    local seen = {}

    for bossKey, planID in pairs(noteDB.SemanticPlanIDByBossKey or {}) do
        if MatchBossKey(instanceType, bossKey) and not seen[planID] then
            ids[#ids + 1] = planID
            seen[planID] = true
        end
    end

    for bossKey, planID in pairs(noteDB.PersonalBossPlans or {}) do
        if MatchBossKey(instanceType, bossKey) and not seen[planID] then
            ids[#ids + 1] = planID
            seen[planID] = true
        end
    end

    SortNumericList(ids)

    local deleted = 0
    for _, planID in ipairs(ids) do
        if note:DeletePlan(planID) then
            deleted = deleted + 1
        end
    end

    return deleted
end

local function EnsureLibraries()
    if not LibSerialize or not LibDeflate then
        return false, L["通信库未加载"] or "通信库未加载"
    end
    return true, nil
end

function ExportImport:GetTypeName(typeCode)
    return GetTypeName(typeCode)
end

function ExportImport:Encode(typeCode, data)
    local ok, err = EnsureLibraries()
    if not ok then
        return nil, err
    end

    if typeCode == TYPE_CODE_PLAN then
        return nil, L["当前版本暂不支持单方案分享"] or "当前版本暂不支持单方案分享"
    end

    local expectedFormat = GetExpectedFormat(typeCode)
    if not expectedFormat then
        return nil, L["数据格式无效"] or "数据格式无效"
    end

    if type(data) ~= "table" or data._format ~= expectedFormat then
        return nil, L["数据格式无效"] or "数据格式无效"
    end

    local serialized = LibSerialize:Serialize(data)
    if not serialized then
        return nil, L["序列化失败"] or "序列化失败"
    end

    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then
        return nil, L["压缩失败"] or "压缩失败"
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, L["编码失败"] or "编码失败"
    end

    LogEvent("STT_EXPORT_IMPORT_ENCODE", {
        result = "ok",
        len = #encoded,
    })

    return string.format("STT:%d:%s:%s", FORMAT_VERSION, typeCode, encoded), nil
end

function ExportImport:Decode(rawText)
    local ok, err = EnsureLibraries()
    if not ok then
        return nil, err
    end

    local text = Trim(rawText)
    if text == "" then
        return nil, L["导入数据为空"] or "导入数据为空"
    end

    if #text > MAX_IMPORT_BYTES then
        return nil, L["导入数据过大"] or "导入数据过大"
    end

    local versionText, typeCode, encoded = text:match("^STT:(%d+):([RDSP]):(.+)$")
    if not versionText then
        return nil, L["无效的导入字符串"] or "无效的导入字符串"
    end

    local version = tonumber(versionText)
    if version ~= FORMAT_VERSION then
        return nil, string.format(
            L["不支持的格式版本 %d（当前: %d）"] or "不支持的格式版本 %d（当前: %d）",
            version or 0,
            FORMAT_VERSION
        )
    end

    if typeCode == TYPE_CODE_PLAN then
        return nil, L["当前版本暂不支持单方案分享"] or "当前版本暂不支持单方案分享"
    end

    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then
        return nil, L["数据损坏：解码失败"] or "数据损坏：解码失败"
    end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, L["数据损坏：解压失败"] or "数据损坏：解压失败"
    end

    local success, data = LibSerialize:Deserialize(decompressed)
    if success ~= true or type(data) ~= "table" then
        return nil, L["数据损坏：反序列化失败"] or "数据损坏：反序列化失败"
    end

    local expectedFormat = GetExpectedFormat(typeCode)
    if not expectedFormat or data._format ~= expectedFormat then
        return nil, L["数据格式无效"] or "数据格式无效"
    end

    LogEvent("STT_EXPORT_IMPORT_DECODE", {
        result = "ok",
        len = #text,
    })

    return {
        typeCode = typeCode,
        version = version,
        data = data,
    }, nil
end

function ExportImport:CollectPlans(instanceType)
    local normalizedType = NormalizeInstanceType(instanceType)
    if not normalizedType then
        return nil, 0
    end

    local note = GetNote()
    local noteDB = STT_DB and D() or nil
    if not (note and noteDB) then
        return nil, 0
    end

    local plans, planCount = CollectPlanMap(note, noteDB.SemanticPlanIDByBossKey, normalizedType)
    local personalPlans, personalCount = CollectPlanMap(note, noteDB.PersonalBossPlans, normalizedType)
    local totalCount = planCount + personalCount

    if totalCount <= 0 then
        return nil, 0
    end

    local payload = {
        _format = PLAN_FORMAT,
        _version = FORMAT_VERSION,
        _exportTime = time(),
        _exporterVersion = tostring(T and T.Version or ""),
        _exporterName = tostring(UnitName and (UnitName("player") or "") or ""),
        _instanceType = normalizedType,
        plans = plans,
        personalPlans = personalPlans,
    }

    LogEvent("STT_EXPORT_IMPORT_COLLECT_PLANS", {
        result = normalizedType,
        rowCount = totalCount,
    })

    return payload, totalCount
end

function ExportImport:CollectSettings()
    local currentDB = GetSettingsDB()
    local defaults = C and C.defaults or nil
    if type(defaults) ~= "table" then
        return nil, 0
    end

    local settings, changedCount = BuildSettingsDiff(currentDB, defaults, nil)
    settings = settings or {}
    changedCount = changedCount + CollectCustomOptionPushSettings(settings)
    if not settings or changedCount <= 0 then
        return nil, 0
    end

    local payload = {
        _format = SETTINGS_FORMAT,
        _version = FORMAT_VERSION,
        _exportTime = time(),
        _exporterVersion = tostring(T and T.Version or ""),
        _exporterName = tostring(UnitName and (UnitName("player") or "") or ""),
        settings = settings,
    }

    LogEvent("STT_EXPORT_IMPORT_COLLECT_SETTINGS", {
        result = "ok",
        rowCount = changedCount,
    })

    return payload, changedCount
end

function ExportImport:Preview(text)
    local decoded, err = self:Decode(text)
    if not decoded then
        return nil, err
    end

    local data = decoded.data
    local summary = {
        typeCode = decoded.typeCode,
        typeName = GetTypeName(decoded.typeCode),
        version = decoded.version,
        exportTime = tonumber(data._exportTime or 0) or 0,
        exporterName = tostring(data._exporterName or ""),
        exporterVersion = tostring(data._exporterVersion or ""),
        planCount = CountEntries(data.plans),
        personalPlanCount = CountEntries(data.personalPlans),
        settingsCount = CountLeafNodes(data.settings or {}),
    }

    return summary, nil
end

function ExportImport:ImportPlans(data, mode)
    local instanceType = NormalizeInstanceType(data and data._instanceType)
    local note = GetNote()
    local noteDB = STT_DB and D() or nil
    if not instanceType or not (note and note.UpsertSemanticBossPlan and note.UpsertPersonalBossPlan and noteDB) then
        return 0, 0
    end

    if mode == "replace" then
        DeletePlansByInstanceType(note, instanceType)
    end

    local imported = 0
    local skipped = 0

    for bossKey, plan in pairs(data.plans or {}) do
        local normalizedBossKey = MatchBossKey(instanceType, bossKey)
        if normalizedBossKey and type(plan) == "table" then
            local planID = note:UpsertSemanticBossPlan(
                normalizedBossKey,
                tostring(plan.name or ""),
                tostring(plan.content or ""),
                {
                    forceContent = true,
                    authorName = tostring(plan.lastUpdateName or ""),
                    timestamp = tonumber(plan.lastUpdateTime or 0) or nil,
                    planAuthor = tostring(plan.author or ""),
                }
            )
            if planID then
                noteDB.PlanCreatedTime[planID] = tonumber(plan.createdTime or 0) or noteDB.PlanCreatedTime[planID]
                imported = imported + 1
            else
                skipped = skipped + 1
            end
        else
            if type(plan) == "table" then
                LogEvent("STT_EXPORT_IMPORT_REJECT_BOSS_KEY", {
                    bossKey = tostring(bossKey or ""),
                    result = "skipped",
                    cause = "invalid_boss_key",
                })
            end
            skipped = skipped + 1
        end
    end

    for bossKey, plan in pairs(data.personalPlans or {}) do
        local normalizedBossKey = MatchBossKey(instanceType, bossKey)
        if normalizedBossKey and type(plan) == "table" then
            local planID = note:UpsertPersonalBossPlan(
                normalizedBossKey,
                tostring(plan.name or ""),
                tostring(plan.content or ""),
                {
                    forceContent = true,
                    authorName = tostring(plan.lastUpdateName or ""),
                    timestamp = tonumber(plan.lastUpdateTime or 0) or nil,
                    planAuthor = tostring(plan.author or ""),
                }
            )
            if planID then
                noteDB.PlanCreatedTime[planID] = tonumber(plan.createdTime or 0) or noteDB.PlanCreatedTime[planID]
                imported = imported + 1
            else
                skipped = skipped + 1
            end
        else
            if type(plan) == "table" then
                LogEvent("STT_EXPORT_IMPORT_REJECT_BOSS_KEY", {
                    bossKey = tostring(bossKey or ""),
                    result = "skipped",
                    cause = "invalid_boss_key",
                })
            end
            skipped = skipped + 1
        end
    end

    LogEvent("STT_EXPORT_IMPORT_IMPORT_PLANS", {
        result = mode,
        rowCount = imported,
        errorCount = skipped,
    })

    return imported, skipped
end

function ExportImport:ImportSettings(data, mode)
    local defaults = C and C.defaults or nil
    local settings = data and data.settings or nil
    if type(defaults) ~= "table" or type(settings) ~= "table" then
        return 0, CountLeafNodes(settings or {})
    end

    local currentDB = GetSettingsDB()
    if mode == "replace" then
        ResetSettingsToDefaults(currentDB, defaults)
    end

    local customApplied, customSkipped = ApplyCustomOptionPushSettings(settings)
    local applied, skipped = ApplySettingsDiff(currentDB, settings, defaults, nil)
    applied = applied + customApplied
    skipped = skipped + customSkipped

    LogEvent("STT_EXPORT_IMPORT_IMPORT_SETTINGS", {
        result = mode,
        rowCount = applied,
        errorCount = skipped,
    })

    return applied, skipped
end

function ExportImport:Import(text, mode)
    local importMode = tostring(mode or "merge")
    if importMode ~= "merge" and importMode ~= "replace" then
        importMode = "merge"
    end

    local decoded, err = self:Decode(text)
    if not decoded then
        return false, err
    end

    if decoded.typeCode == TYPE_CODE_SETTINGS then
        local applied, skipped = self:ImportSettings(decoded.data, importMode)
        return true, string.format(
            L["设置导入完成：已应用 %d 项，跳过 %d 项"] or "设置导入完成：已应用 %d 项，跳过 %d 项",
            applied,
            skipped
        )
    end

    local imported, skipped = self:ImportPlans(decoded.data, importMode)
    return true, string.format(
        L["导入完成：已写入 %d 项，跳过 %d 项"] or "导入完成：已写入 %d 项，跳过 %d 项",
        imported,
        skipped
    )
end

function ExportImport:ExportRaidPlans()
    local payload, count = self:CollectPlans("raid")
    if not payload or count <= 0 then
        return nil, L["没有可导出的数据"] or "没有可导出的数据"
    end
    return self:Encode(TYPE_CODE_RAID, payload)
end

function ExportImport:ExportDungeonPlans()
    local payload, count = self:CollectPlans("dungeon")
    if not payload or count <= 0 then
        return nil, L["没有可导出的数据"] or "没有可导出的数据"
    end
    return self:Encode(TYPE_CODE_DUNGEON, payload)
end

function ExportImport:ExportSettings()
    local payload, count = self:CollectSettings()
    if not payload or count <= 0 then
        return nil, L["没有可导出的数据"] or "没有可导出的数据"
    end
    return self:Encode(TYPE_CODE_SETTINGS, payload)
end

end)
