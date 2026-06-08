local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

local SEMANTIC_BOSS_KEY_SCHEMA_VERSION = 3
local PLAN_SCOPE_TEAM = "team"
local PLAN_SCOPE_PERSONAL = "personal"

-- 战术方案核心模块（v2 存储结构与 API）
local Note = {}
T.Note = Note
T.SemanticPlanStore = Note

local function D()
    return T.Profile:GetActiveData()
end

local DEFAULT_PLAN_CONTENT = table.concat({
    "[方案]",
    "名称 = 新方案",
    "作者 = STT",
    "",
    "[人员]",
    "坦克1 = 团长",
    "治疗1 = 团长",
    "",
    "[时间轴]",
    "{time:00:10} {{坦克1}}开怪",
    "{time:00:20} {{治疗1}}准备抬血",
}, "\n")
local LEGACY_DEFAULT_PLAN_CONTENT = "时间轴\n{time:00:05} 准备战斗\n{time:00:10} {所有人}注意站位\n{time:00:15} {p:坦克} 开怪\n战斗结束"

local function NormalizeSemanticBossInstanceType(instanceType)
    local normalized = tostring(instanceType or ""):lower()
    if normalized == "raid" or normalized == "dungeon" then
        return normalized
    end
    return nil
end

local function BuildSemanticBossKeyText(instanceType, instanceID, encounterID)
    local normalizedType = NormalizeSemanticBossInstanceType(instanceType)
    local normalizedInstanceID = tonumber(instanceID)
    local normalizedEncounterID = tonumber(encounterID)
    if not normalizedType or not normalizedInstanceID or not normalizedEncounterID then
        return nil
    end
    return string.format("%s:%d:%d", normalizedType, normalizedInstanceID, normalizedEncounterID)
end

local function ParseSemanticBossKeyText(text)
    if type(text) ~= "string" then
        return nil
    end
    local instanceType, instanceID, encounterID = text:match("^(%a+):(%-?%d+):(%-?%d+)$")
    if not instanceType then
        return nil
    end
    local normalizedType = NormalizeSemanticBossInstanceType(instanceType)
    if not normalizedType then
        return nil
    end
    return {
        instanceType = normalizedType,
        instanceID = tonumber(instanceID) or 0,
        encounterID = tonumber(encounterID) or 0,
    }
end

local function ParseLegacySemanticBossKeyText(text)
    local parsed = ParseSemanticBossKeyText(text)
    if parsed then
        return parsed
    end
    if type(text) ~= "string" then
        return nil
    end
    local instanceType, instanceID, encounterID = text:match("^(%a+):(%-?%d+):(%-?%d+):(%-?%d+)$")
    if not instanceType then
        return nil
    end
    local normalizedType = NormalizeSemanticBossInstanceType(instanceType)
    if not normalizedType then
        return nil
    end
    return {
        instanceType = normalizedType,
        instanceID = tonumber(instanceID) or 0,
        encounterID = tonumber(encounterID) or 0,
    }
end

local function NormalizeSemanticBossKeyText(text)
    local parsed = ParseSemanticBossKeyText(text)
    if not parsed then
        return nil
    end
    return BuildSemanticBossKeyText(parsed.instanceType, parsed.instanceID, parsed.encounterID)
end

local function NormalizeAnySemanticBossKeyText(value)
    if type(value) == "table" then
        return BuildSemanticBossKeyText(value.instanceType, value.instanceID, value.encounterID)
    end
    return NormalizeSemanticBossKeyText(value)
end

local function NormalizeLegacySemanticBossKeyText(text)
    local parsed = ParseLegacySemanticBossKeyText(text)
    if not parsed then
        return nil
    end
    return BuildSemanticBossKeyText(parsed.instanceType, parsed.instanceID, parsed.encounterID)
end

T.BuildSemanticBossKeyText = BuildSemanticBossKeyText
T.ParseSemanticBossKeyText = ParseSemanticBossKeyText
T.NormalizeSemanticBossKeyText = NormalizeSemanticBossKeyText

local function GetDefaultPlanContent()
    return (T.STNTemplate and T.STNTemplate.BuildDefaultTemplate and T.STNTemplate.BuildDefaultTemplate()) or DEFAULT_PLAN_CONTENT
end

local function GetTemplateInfo(content, opts)
    return T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(content or "", opts) or nil
end

local function BuildTemplateRejectReason(info)
    if not info or info.hasBlocks ~= true then
        return L["仅支持结构化模板"] or "仅支持结构化模板"
    end
    if info and info.errors and #info.errors > 0 then
        return string.format("%s %d", L["模板解析错误"] or "模板解析错误", #info.errors)
    end
    return L["仅支持结构化模板"] or "仅支持结构化模板"
end

local function IsPlayableStructuredContent(content, expectedBodyKind, opts)
    local info = GetTemplateInfo(content, opts)
    local ok = T.STNTemplate and T.STNTemplate.IsBodyUsable and T.STNTemplate.IsBodyUsable(info, expectedBodyKind) or false
    return ok == true, info
end

Note.SyncDeps = {
    GetDB = D,
    NormalizeSemanticBossKeyText = NormalizeSemanticBossKeyText,
    BuildTemplateRejectReason = BuildTemplateRejectReason,
    IsPlayableStructuredContent = IsPlayableStructuredContent,
    PlanScopeTeam = PLAN_SCOPE_TEAM,
}

local function GetNoteSync()
    return T.NoteSync
end

local function NormalizePlanScope(scope)
    if scope == PLAN_SCOPE_PERSONAL or scope == "personal_boss" then
        return PLAN_SCOPE_PERSONAL
    end
    return PLAN_SCOPE_TEAM
end

--=== v2 数据结构与迁移 ===--
-- 统一权威：D().*

-- 生成下一个可用 ID（数组型 ID，递增不复用）
local function NextId()
    D().nextID = (D().nextID or 1) + 1
    return D().nextID - 1
end

local function EnsureNoteTables(noteDB)
    noteDB.Plans = noteDB.Plans or {}
    noteDB.PlanNames = noteDB.PlanNames or {}
    noteDB.AutoLoad = noteDB.AutoLoad or {}
    noteDB.EncounterAutoLoad = noteDB.EncounterAutoLoad or {}
    noteDB.PlanLastUpdateName = noteDB.PlanLastUpdateName or {}
    noteDB.PlanLastUpdateTime = noteDB.PlanLastUpdateTime or {}
    noteDB.PlanAuthor = noteDB.PlanAuthor or {}
    noteDB.PlanCreatedTime = noteDB.PlanCreatedTime or {}
    noteDB.PlanEncounterIDs = noteDB.PlanEncounterIDs or {}
    noteDB.SelfNote = noteDB.SelfNote or ""
    noteDB.nextID = noteDB.nextID or 1
    noteDB.PlanKinds = noteDB.PlanKinds or {}
    noteDB.SemanticBossKeyByPlanID = noteDB.SemanticBossKeyByPlanID or {}
    noteDB.SemanticPlanIDByBossKey = noteDB.SemanticPlanIDByBossKey or {}
    noteDB.PersonalBossPlans = noteDB.PersonalBossPlans or {}
    noteDB.PersonalBossPlansByID = noteDB.PersonalBossPlansByID or {}
    noteDB.PlanHiddenFromLegacy = noteDB.PlanHiddenFromLegacy or {}
    noteDB.SemanticBossKeySchemaVersion = tonumber(noteDB.SemanticBossKeySchemaVersion) or 0
end

local function ClearBossBindingForPlan(noteDB, planID, bossKeyByPlanID, planIDByBossKey, kindName, clearHiddenFlag)
    local bossKey = bossKeyByPlanID[planID]
    if bossKey and planIDByBossKey[bossKey] == planID then
        planIDByBossKey[bossKey] = nil
    end
    bossKeyByPlanID[planID] = nil
    if kindName and noteDB.PlanKinds[planID] == kindName then
        noteDB.PlanKinds[planID] = nil
    end
    if clearHiddenFlag == true then
        noteDB.PlanHiddenFromLegacy[planID] = nil
    end
end

local function LogBossKeyMigration(fields)
    if T and T.LogDebugEvent then
        T.LogDebugEvent("STT_BOSS_KEY_MIGRATE", fields)
    end
end

local function GetPlanRecencyScore(noteDB, planID)
    local normalizedPlanID = tonumber(planID) or 0
    return tonumber(noteDB.PlanLastUpdateTime and noteDB.PlanLastUpdateTime[normalizedPlanID]) or 0
end

local function BuildBossKeyMigrationCandidates(noteDB, bossKeyToPlanID, planIDToBossKey, kindName)
    local candidates = {}
    local seen = {}

    local function push(planID, bossKey)
        local normalizedPlanID = tonumber(planID)
        local rawBossKey = tostring(bossKey or "")
        if not normalizedPlanID or rawBossKey == "" or not noteDB.Plans[normalizedPlanID] then
            return
        end

        local canonicalBossKey = NormalizeLegacySemanticBossKeyText(rawBossKey)
        if not canonicalBossKey then
            LogBossKeyMigration({
                kind = kindName,
                sourceBossKey = rawBossKey,
                planID = normalizedPlanID,
                result = "drop_invalid_key",
            })
            return
        end

        local dedupeKey = table.concat({
            tostring(normalizedPlanID),
            rawBossKey,
            canonicalBossKey,
        }, "\031")
        if seen[dedupeKey] then
            return
        end
        seen[dedupeKey] = true

        candidates[#candidates + 1] = {
            planID = normalizedPlanID,
            sourceBossKey = rawBossKey,
            canonicalBossKey = canonicalBossKey,
            updatedAt = GetPlanRecencyScore(noteDB, normalizedPlanID),
        }
    end

    for bossKey, planID in pairs(bossKeyToPlanID or {}) do
        push(planID, bossKey)
    end
    for planID, bossKey in pairs(planIDToBossKey or {}) do
        push(planID, bossKey)
    end

    return candidates
end

local function SelectBossKeyMigrationWinners(candidates)
    local winners = {}
    for _, candidate in ipairs(candidates or {}) do
        local current = winners[candidate.canonicalBossKey]
        if not current
            or candidate.updatedAt > current.updatedAt
            or (
                candidate.updatedAt == current.updatedAt
                and candidate.planID == current.planID
                and candidate.sourceBossKey == candidate.canonicalBossKey
                and current.sourceBossKey ~= current.canonicalBossKey
            )
            or (candidate.updatedAt == current.updatedAt and candidate.planID > current.planID) then
            winners[candidate.canonicalBossKey] = candidate
        end
    end
    return winners
end

local function RebuildBossBindingMap(noteDB, config)
    local candidates = BuildBossKeyMigrationCandidates(
        noteDB,
        config.bossKeyToPlanID,
        config.planIDToBossKey,
        config.kindName
    )
    local winners = SelectBossKeyMigrationWinners(candidates)
    local nextBossKeyToPlanID = {}
    local nextPlanIDToBossKey = {}

    for _, candidate in ipairs(candidates) do
        local winner = winners[candidate.canonicalBossKey]
        if winner and winner.planID == candidate.planID and winner.sourceBossKey == candidate.sourceBossKey then
            nextBossKeyToPlanID[candidate.canonicalBossKey] = candidate.planID
            nextPlanIDToBossKey[candidate.planID] = candidate.canonicalBossKey
            noteDB.PlanKinds[candidate.planID] = config.kindName
            noteDB.PlanHiddenFromLegacy[candidate.planID] = nil
            if candidate.sourceBossKey ~= candidate.canonicalBossKey then
                LogBossKeyMigration({
                    kind = config.kindName,
                    sourceBossKey = candidate.sourceBossKey,
                    canonicalBossKey = candidate.canonicalBossKey,
                    planID = candidate.planID,
                result = "canonicalized",
            })
            end
        elseif winner and winner.planID == candidate.planID then
            LogBossKeyMigration({
                kind = config.kindName,
                sourceBossKey = candidate.sourceBossKey,
                canonicalBossKey = candidate.canonicalBossKey,
                planID = candidate.planID,
                keptPlanID = winner.planID,
                result = "drop_alias",
            })
        else
            if noteDB.PlanKinds[candidate.planID] == config.kindName then
                noteDB.PlanKinds[candidate.planID] = nil
            end
            noteDB.PlanHiddenFromLegacy[candidate.planID] = true
            LogBossKeyMigration({
                kind = config.kindName,
                sourceBossKey = candidate.sourceBossKey,
                canonicalBossKey = candidate.canonicalBossKey,
                planID = candidate.planID,
                keptPlanID = winner and winner.planID or nil,
                result = "hidden_conflict",
                cause = "last_update",
            })
        end
    end

    for planID, kindName in pairs(noteDB.PlanKinds or {}) do
        if kindName == config.kindName and not nextPlanIDToBossKey[tonumber(planID) or 0] then
            noteDB.PlanKinds[planID] = nil
            noteDB.PlanHiddenFromLegacy[planID] = true
        end
    end

    return nextBossKeyToPlanID, nextPlanIDToBossKey, winners
end

local function MigrateBossScopedMetadataMap(noteDB, sourceMap, winnerByCanonicalKey)
    local migrated = {}
    for bossKey, value in pairs(sourceMap or {}) do
        local canonicalBossKey = NormalizeLegacySemanticBossKeyText(bossKey)
        if canonicalBossKey then
            local winner = winnerByCanonicalKey and winnerByCanonicalKey[canonicalBossKey] or nil
            if winner and bossKey == winner.sourceBossKey then
                migrated[canonicalBossKey] = value
            elseif migrated[canonicalBossKey] == nil and NormalizeSemanticBossKeyText(bossKey) == canonicalBossKey then
                migrated[canonicalBossKey] = value
            elseif migrated[canonicalBossKey] == nil and winner == nil then
                migrated[canonicalBossKey] = value
            end
        end
    end
    return migrated
end

local function BuildSemanticBossMigrationSource(noteDB, workbench)
    local source = {}
    for bossKey, planID in pairs(noteDB.SemanticPlanIDByBossKey or {}) do
        source[bossKey] = planID
    end

    local adopted = 0
    local legacyBossPlanMap = type(workbench) == "table" and workbench.bossPlanMap or nil
    for bossKey, planID in pairs(legacyBossPlanMap or {}) do
        local canonicalBossKey = NormalizeLegacySemanticBossKeyText(bossKey)
        local normalizedPlanID = tonumber(planID)
        if canonicalBossKey and normalizedPlanID and noteDB.Plans[normalizedPlanID] and source[canonicalBossKey] == nil then
            source[canonicalBossKey] = normalizedPlanID
            adopted = adopted + 1
        end
    end

    return source, adopted
end

local function GetWorkbenchSelectionBossKeyText(workbench)
    local selection = type(workbench) == "table" and type(workbench.selection) == "table" and workbench.selection or nil
    if not selection then
        return nil
    end
    return BuildSemanticBossKeyText(selection.instanceType, selection.instanceID, selection.encounterID)
end

-- 创建默认方案（v2）
function Note:CreateDefaultPlan()
    local id = 1
    EnsureNoteTables(D())
    D().Plans[id] = GetDefaultPlanContent()
    D().PlanNames[id] = L["默认方案"]
    local who = UnitName("player") or "Unknown"
    local now = time()
    D().PlanAuthor[id] = who
    D().PlanCreatedTime[id] = now
    D().PlanLastUpdateName[id] = who
    D().PlanLastUpdateTime[id] = now
    D().currentSTNNote = id
    D().nextID = 2
end

local function NormalizeLegacyDefaultPlan(noteDB)
    if type(noteDB) ~= "table" then
        return
    end

    if tostring(noteDB.Plans and noteDB.Plans[1] or "") ~= LEGACY_DEFAULT_PLAN_CONTENT then
        return
    end

    noteDB.Plans[1] = GetDefaultPlanContent()
end

-- 合并旧三分法数据为 v2（一次性）
function Note:MigrateOldData()
    if STT_DB._schema == 2 then return end

    local old = {
        notes = STT_DB.notes,
        personalNotes = STT_DB.personalNotes,
        drafts = STT_DB.drafts,
        currentNote = STT_DB.currentNote,
        currentSTNNote = STT_DB.currentSTNNote,
    }

    -- 备份以便回滚
    STT_DB._backup_v1 = old

    -- 初始化当前配置容器
    local N = D()
    EnsureNoteTables(N)

    -- 收集旧记录到列表
    local pool = {}
    local function push(tbl)
        if not tbl then return end
        for id, note in pairs(tbl) do
            table.insert(pool, {
                name = tostring(note.name or id or L["未命名方案"]),
                content = tostring(note.content or ""),
                created = tonumber(note.created or 0) or 0,
                modified = tonumber(note.modified or 0) or 0,
                author = tostring(note.author or UnitName("player") or ""),
                lastName = tostring(note.lastUpdateName or note.author or UnitName("player") or ""),
                lastTime = tonumber(note.lastUpdateTime or note.modified or note.created or 0) or 0,
                encounterID = note.encounterID,
            })
        end
    end
    push(STT_DB.notes)
    push(STT_DB.personalNotes)
    push(STT_DB.drafts)

    table.sort(pool, function(a,b)
        return (a.modified or 0) > (b.modified or 0)
    end)

    local nextId = 1
    for _, it in ipairs(pool) do
        N.Plans[nextId] = it.content
        N.PlanNames[nextId] = it.name
        N.PlanAuthor[nextId] = it.author
        N.PlanCreatedTime[nextId] = it.created ~= 0 and it.created or time()
        N.PlanLastUpdateName[nextId] = it.lastName
        N.PlanLastUpdateTime[nextId] = it.lastTime ~= 0 and it.lastTime or time()
        local encounterID = tonumber(it.encounterID)
        if encounterID and encounterID > 0 and not N.EncounterAutoLoad[encounterID] then
            N.EncounterAutoLoad[encounterID] = nextId
            N.PlanEncounterIDs[nextId] = encounterID
        end
        nextId = nextId + 1
    end
    N.nextID = nextId

    -- 激活项迁移：优先旧 currentSTNNote 其次 currentNote，否则第一个
    if STT_DB.currentSTNNote and N.Plans[1] then
        -- 旧仓库中 STN 用的是字符串/任意 ID；迁移后为顺序数组，无法一一映射
        -- 规则：迁移期不做内容匹配，仅把“激活”落在最新一条（第一个）
        N.currentSTNNote = 1
    elseif STT_DB.currentNote and N.Plans[1] then
        N.currentSTNNote = 1
    elseif N.Plans[1] then
        N.currentSTNNote = 1
    end

    -- 清除旧字段
    STT_DB.notes = nil
    STT_DB.personalNotes = nil
    STT_DB.drafts = nil
    STT_DB.currentNote = nil
    STT_DB.currentSTNNote = nil

    STT_DB._schema = 2
end

function Note:MigrateSemanticBossKeys()
    local N = STT_DB and D() or nil
    if type(N) ~= "table" then
        return
    end

    EnsureNoteTables(N)
    if N.SemanticBossKeySchemaVersion == SEMANTIC_BOSS_KEY_SCHEMA_VERSION then
        return
    end

    local semanticTimelineDB = STT_DB.semanticTimeline
    local workbench = semanticTimelineDB and semanticTimelineDB.workbench or nil
    local semanticBossSource, legacyBossMapAdopted = BuildSemanticBossMigrationSource(N, workbench)
    local semanticPlanMap, semanticPlanMapByID, semanticWinners = RebuildBossBindingMap(N, {
        bossKeyToPlanID = semanticBossSource,
        planIDToBossKey = N.SemanticBossKeyByPlanID,
        kindName = "semantic_boss",
    })
    local personalPlanMap, personalPlanMapByID = RebuildBossBindingMap(N, {
        bossKeyToPlanID = N.PersonalBossPlans,
        planIDToBossKey = N.PersonalBossPlansByID,
        kindName = "personal_boss",
    })

    N.SemanticPlanIDByBossKey = semanticPlanMap
    N.SemanticBossKeyByPlanID = semanticPlanMapByID
    N.PersonalBossPlans = personalPlanMap
    N.PersonalBossPlansByID = personalPlanMapByID

    if type(workbench) == "table" then
        workbench.bossTemplateVer = MigrateBossScopedMetadataMap(N, workbench.bossTemplateVer, semanticWinners)
        workbench.bossTemplateDigest = MigrateBossScopedMetadataMap(N, workbench.bossTemplateDigest, semanticWinners)
        if not NormalizeSemanticBossKeyText(N.CurrentSemanticBossKeyText) then
            N.CurrentSemanticBossKeyText = GetWorkbenchSelectionBossKeyText(workbench)
            N.CurrentSemanticBossKeyReason = N.CurrentSemanticBossKeyText and "migrate_workbench_selection" or nil
        end
        workbench.bossPlanMap = nil
    end
    if legacyBossMapAdopted > 0 and C and C.DB and C.DB.debugMode and T and T.debug then
        T.debug(string.format(
            "[STT_BOSS_KEY_MIGRATE_LEGACY_MAP] adopted=%d schema=%d",
            legacyBossMapAdopted,
            SEMANTIC_BOSS_KEY_SCHEMA_VERSION
        ))
    end

    N.SemanticBossKeySchemaVersion = SEMANTIC_BOSS_KEY_SCHEMA_VERSION
end

-- 初始化数据库（v2）
function Note:InitDB()
    STT_DB = STT_DB or {}
    EnsureNoteTables(D())
    NormalizeLegacyDefaultPlan(D())

    -- 如存在旧结构，先迁移
    if not STT_DB._schema or STT_DB._schema ~= 2 then
        self:MigrateOldData()
        NormalizeLegacyDefaultPlan(D())
    end
    self:MigrateSemanticBossKeys()

    -- 如果迁移后仍无任何方案，则创建默认方案
    if not next(D().Plans) then
        self:CreateDefaultPlan()
    end
end

function Note:InitComm()
    local sync = GetNoteSync()
    if sync and sync.InitComm then
        return sync:InitComm(self)
    end
end

--=== v2 核心 API ===--

-- 获取方案列表（供 GUI）
function Note:GetPlanList()
    local list = {}
    local N = D()
    local active = N.currentSTNNote
    -- 遍历稀疏数组：禁止 ipairs/#
    for id, content in pairs(N.Plans) do
        local name = N.PlanNames[id]
        local lastT = N.PlanLastUpdateTime[id]
        local author = N.PlanLastUpdateName[id] or N.PlanAuthor[id]
        table.insert(list, {
            id = id,
            name = name or (L["方案"] .. tostring(id)),
            lastUpdated = lastT or 0,
        author = author or "",
        isActive = (active == id),
        contentLen = content and #content or 0,
        encounterID = N.PlanEncounterIDs[id],
    })
    end
    table.sort(list, function(a,b) return (a.lastUpdated or 0) > (b.lastUpdated or 0) end)
    return list
end

-- 获取方案详情
function Note:GetPlan(id)
    local N = D()
    if not id or not N.Plans[id] then return nil end
    return {
        id = id,
        name = N.PlanNames[id],
        content = N.Plans[id],
        lastUpdateName = N.PlanLastUpdateName[id],
        lastUpdateTime = N.PlanLastUpdateTime[id],
        author = N.PlanAuthor[id],
        created = N.PlanCreatedTime[id],
        mapID = N.AutoLoad and N.AutoLoad.__reverse and N.AutoLoad.__reverse[id] or nil,
        encounterID = N.PlanEncounterIDs[id],
        kind = N.PlanKinds[id],
        bossKey = N.SemanticBossKeyByPlanID[id],
        personalBossKey = N.PersonalBossPlansByID[id],
        hiddenFromLegacy = N.PlanHiddenFromLegacy[id] == true,
    }
end

function Note:GetPlanKind(id)
    local N = D()
    if not id or not N.Plans[id] then
        return nil
    end
    return N.PlanKinds[id]
end

function Note:SetCurrentBossKey(bossKey, reason)
    local N = D()
    local normalizedBossKey = NormalizeAnySemanticBossKeyText(bossKey)
    if not normalizedBossKey then
        return false
    end

    N.CurrentSemanticBossKeyText = normalizedBossKey
    N.CurrentSemanticBossKeyReason = tostring(reason or "unknown")
    local parsed = ParseSemanticBossKeyText(normalizedBossKey)
    if parsed and tonumber(parsed.encounterID) and tonumber(parsed.encounterID) > 0 then
        local reasonText = tostring(reason or "")
        if reasonText == "encounter_start" or reasonText == "runtime_encounter" or reasonText == "option_encounter" then
            N.LastEncounterBossKeyText = normalizedBossKey
        end
    end
    if T.LogDebugEvent then
        T.LogDebugEvent("STT_RUNTIME_BOSS_CONTEXT", {
            bossKey = normalizedBossKey,
            cause = tostring(reason or "unknown"),
            result = "set",
        })
    end
    return true
end

function Note:SetCurrentSemanticBossKey(bossKey, reason)
    return self:SetCurrentBossKey(bossKey, reason)
end

function Note:GetCurrentBossKey()
    local N = D()
    local normalizedBossKey = NormalizeSemanticBossKeyText(N.CurrentSemanticBossKeyText)
    if not normalizedBossKey then
        N.CurrentSemanticBossKeyText = nil
        N.CurrentSemanticBossKeyReason = nil
        return nil
    end
    return normalizedBossKey
end

function Note:GetCurrentSemanticBossKey()
    return self:GetCurrentBossKey()
end

function Note:GetLastEncounterBossKey()
    local N = D()
    local normalizedBossKey = NormalizeSemanticBossKeyText(N.LastEncounterBossKeyText)
    if not normalizedBossKey then
        N.LastEncounterBossKeyText = nil
        return nil
    end
    return normalizedBossKey
end

function Note:GetSemanticBossPlanID(bossKey)
    local N = D()
    local normalizedBossKey = NormalizeAnySemanticBossKeyText(bossKey)
    if not normalizedBossKey then
        return nil
    end

    local planID = N.SemanticPlanIDByBossKey[normalizedBossKey]
    if planID and N.Plans[planID] then
        return planID
    end

    if planID then
        N.SemanticPlanIDByBossKey[normalizedBossKey] = nil
    end
    return nil
end

function Note:GetPersonalBossPlanID(bossKey)
    local N = D()
    local normalizedBossKey = NormalizeAnySemanticBossKeyText(bossKey)
    if not normalizedBossKey then
        return nil
    end

    local planID = N.PersonalBossPlans[normalizedBossKey]
    if planID and N.Plans[planID] then
        return planID
    end

    if planID then
        N.PersonalBossPlans[normalizedBossKey] = nil
    end
    return nil
end

function Note:GetBossPlanID(bossKey, scope)
    if NormalizePlanScope(scope) == PLAN_SCOPE_PERSONAL then
        return self:GetPersonalBossPlanID(bossKey)
    end
    return self:GetSemanticBossPlanID(bossKey)
end

function Note:GetBossPlan(bossKey, scope)
    local planID = self:GetBossPlanID(bossKey, scope)
    return planID and self:GetPlan(planID) or nil
end

function Note:GetCurrentPlanBundle(options)
    local opts = type(options) == "table" and options or {}
    local bossKeyText = NormalizeAnySemanticBossKeyText(opts.bossKeyText or opts.bossKey)
        or self:GetCurrentBossKey()

    local teamPlan = bossKeyText and self:GetBossPlan(bossKeyText, PLAN_SCOPE_TEAM) or nil
    local personalPlan = bossKeyText and self:GetBossPlan(bossKeyText, PLAN_SCOPE_PERSONAL) or nil
    local activePlan = nil
    local fallbackActive = false
    if (not bossKeyText or bossKeyText == "") and not teamPlan and not personalPlan and opts.allowActiveFallback ~= false then
        activePlan = self:GetActivePlan()
        teamPlan = activePlan
        fallbackActive = teamPlan ~= nil
    end

    return {
        bossKeyText = bossKeyText or "",
        sourceReason = tostring(D().CurrentSemanticBossKeyReason or ""),
        teamPlanID = teamPlan and teamPlan.id or nil,
        personalPlanID = personalPlan and personalPlan.id or nil,
        activePlanID = activePlan and activePlan.id or nil,
        fallbackActive = fallbackActive,
        teamName = teamPlan and tostring(teamPlan.name or "") or "",
        personalName = personalPlan and tostring(personalPlan.name or "") or "",
        teamText = teamPlan and tostring(teamPlan.content or "") or "",
        personalText = personalPlan and tostring(personalPlan.content or "") or "",
    }
end

function Note:MarkPlanAsSemanticBoss(planID, bossKey)
    local N = D()
    local normalizedPlanID = tonumber(planID)
    local normalizedBossKey = NormalizeAnySemanticBossKeyText(bossKey)
    if not normalizedPlanID or not normalizedBossKey or not N.Plans[normalizedPlanID] then
        return false
    end

    if N.PersonalBossPlansByID[normalizedPlanID] then
        ClearBossBindingForPlan(N, normalizedPlanID, N.PersonalBossPlansByID, N.PersonalBossPlans, "personal_boss", false)
    end

    local oldBossKey = N.SemanticBossKeyByPlanID[normalizedPlanID]
    if oldBossKey and oldBossKey ~= normalizedBossKey and N.SemanticPlanIDByBossKey[oldBossKey] == normalizedPlanID then
        N.SemanticPlanIDByBossKey[oldBossKey] = nil
    end

    local oldPlanID = N.SemanticPlanIDByBossKey[normalizedBossKey]
    if oldPlanID and oldPlanID ~= normalizedPlanID then
        ClearBossBindingForPlan(N, oldPlanID, N.SemanticBossKeyByPlanID, N.SemanticPlanIDByBossKey, "semantic_boss", true)
    end

    N.PlanKinds[normalizedPlanID] = "semantic_boss"
    N.SemanticBossKeyByPlanID[normalizedPlanID] = normalizedBossKey
    N.SemanticPlanIDByBossKey[normalizedBossKey] = normalizedPlanID
    N.PlanHiddenFromLegacy[normalizedPlanID] = nil
    return true
end

function Note:MarkPlanAsPersonalBoss(planID, bossKey)
    local N = D()
    local normalizedPlanID = tonumber(planID)
    local normalizedBossKey = NormalizeAnySemanticBossKeyText(bossKey)
    if not normalizedPlanID or not normalizedBossKey or not N.Plans[normalizedPlanID] then
        return false
    end

    if N.SemanticBossKeyByPlanID[normalizedPlanID] then
        ClearBossBindingForPlan(N, normalizedPlanID, N.SemanticBossKeyByPlanID, N.SemanticPlanIDByBossKey, "semantic_boss", true)
    end

    local oldBossKey = N.PersonalBossPlansByID[normalizedPlanID]
    if oldBossKey and oldBossKey ~= normalizedBossKey and N.PersonalBossPlans[oldBossKey] == normalizedPlanID then
        N.PersonalBossPlans[oldBossKey] = nil
    end

    local oldPlanID = N.PersonalBossPlans[normalizedBossKey]
    if oldPlanID and oldPlanID ~= normalizedPlanID then
        ClearBossBindingForPlan(N, oldPlanID, N.PersonalBossPlansByID, N.PersonalBossPlans, "personal_boss", false)
    end

    N.PlanKinds[normalizedPlanID] = "personal_boss"
    N.PersonalBossPlans[normalizedBossKey] = normalizedPlanID
    N.PersonalBossPlansByID[normalizedPlanID] = normalizedBossKey
    return true
end

function Note:UpsertSemanticBossPlan(bossKey, name, content, options)
    local N = D()
    local normalizedBossKey = NormalizeSemanticBossKeyText(bossKey)
    if not normalizedBossKey then
        return nil
    end

    local opts = options or {}
    local planID = self:GetSemanticBossPlanID(normalizedBossKey)
    if not planID and opts.planID and N.Plans[opts.planID] then
        planID = tonumber(opts.planID)
    end

    local normalizedName = tostring(name or "")
    local normalizedContent = tostring(content or "")
    if not planID then
        planID = self:CreatePlan(normalizedName, normalizedContent)
    end
    if not planID or not N.Plans[planID] then
        return nil
    end

    self:MarkPlanAsSemanticBoss(planID, normalizedBossKey)

    local update = {}
    if normalizedName ~= "" and normalizedName ~= N.PlanNames[planID] then
        update.name = normalizedName
    end

    local currentContent = tostring(N.Plans[planID] or "")
    local shouldSyncContent = opts.forceContent == true
        or (opts.onlyIfEmpty == true and currentContent == "")
        or (opts.forceContent ~= false and opts.onlyIfEmpty ~= true and content ~= nil)
    if shouldSyncContent and normalizedContent ~= currentContent then
        update.content = normalizedContent
    end

    if next(update) then
        self:UpdatePlan(planID, update)
    end

    if opts.authorName and opts.authorName ~= "" then
        N.PlanLastUpdateName[planID] = tostring(opts.authorName)
    end
    if opts.timestamp then
        N.PlanLastUpdateTime[planID] = tonumber(opts.timestamp) or N.PlanLastUpdateTime[planID]
    end
    if opts.planAuthor and opts.planAuthor ~= "" then
        N.PlanAuthor[planID] = tostring(opts.planAuthor)
    end

    return planID
end

function Note:UpsertPersonalBossPlan(bossKey, name, content, options)
    local N = D()
    local normalizedBossKey = NormalizeSemanticBossKeyText(bossKey)
    if not normalizedBossKey then
        return nil
    end

    local opts = options or {}
    local planID = self:GetPersonalBossPlanID(normalizedBossKey)
    if not planID and opts.planID and N.Plans[opts.planID] then
        planID = tonumber(opts.planID)
    end

    local normalizedName = tostring(name or "")
    local normalizedContent = tostring(content or "")
    if not planID then
        planID = self:CreatePlan(normalizedName, normalizedContent)
    end
    if not planID or not N.Plans[planID] then
        return nil
    end

    self:MarkPlanAsPersonalBoss(planID, normalizedBossKey)

    local update = {}
    if normalizedName ~= "" and normalizedName ~= N.PlanNames[planID] then
        update.name = normalizedName
    end

    local currentContent = tostring(N.Plans[planID] or "")
    local shouldSyncContent = opts.forceContent == true
        or (opts.onlyIfEmpty == true and currentContent == "")
        or (opts.forceContent ~= false and opts.onlyIfEmpty ~= true and content ~= nil)
    if shouldSyncContent and normalizedContent ~= currentContent then
        update.content = normalizedContent
    end

    if next(update) then
        self:UpdatePlan(planID, update)
    end

    if opts.authorName and opts.authorName ~= "" then
        N.PlanLastUpdateName[planID] = tostring(opts.authorName)
    end
    if opts.timestamp then
        N.PlanLastUpdateTime[planID] = tonumber(opts.timestamp) or N.PlanLastUpdateTime[planID]
    end
    if opts.planAuthor and opts.planAuthor ~= "" then
        N.PlanAuthor[planID] = tostring(opts.planAuthor)
    end

    return planID
end

function Note:UpsertBossPlan(bossKey, scope, content, meta)
    local opts = meta or {}
    local planName = tostring(opts.name or opts.planName or opts.title or "")
    if NormalizePlanScope(scope) == PLAN_SCOPE_PERSONAL then
        return self:UpsertPersonalBossPlan(bossKey, planName, content, opts)
    end
    return self:UpsertSemanticBossPlan(bossKey, planName, content, opts)
end

-- 创建方案
function Note:CreatePlan(name, content, mapID, encounterID)
    local N = D()
    EnsureNoteTables(N)
    local id = NextId()
    local who = UnitName("player") or ""
    local now = time()
    N.Plans[id] = tostring(content or "")
    N.PlanNames[id] = name and tostring(name) or (L["新方案"] .. " " .. tostring(id))
    N.PlanAuthor[id] = who
    N.PlanCreatedTime[id] = now
    N.PlanLastUpdateName[id] = who
    N.PlanLastUpdateTime[id] = now
    if mapID then
        N.AutoLoad = N.AutoLoad or {}
        N.AutoLoad[mapID] = id
        N.AutoLoad.__reverse = N.AutoLoad.__reverse or {}
        N.AutoLoad.__reverse[id] = mapID
    end
    if encounterID then
        local normalizedEncounterID = tonumber(encounterID)
        if normalizedEncounterID and normalizedEncounterID > 0 then
            N.EncounterAutoLoad = N.EncounterAutoLoad or {}
            N.EncounterAutoLoad[normalizedEncounterID] = id
            N.PlanEncounterIDs[id] = normalizedEncounterID
        end
    end
    return id
end

-- 更新方案
function Note:UpdatePlan(id, data)
    local N = D()
    if not id or not N.Plans[id] then return false end
    local changed = false
    local oldName = N.PlanNames[id]
    local oldLen = #(N.Plans[id] or "")
    if data.name and data.name ~= N.PlanNames[id] then
        N.PlanNames[id] = data.name; changed = true
    end
    if data.content ~= nil and data.content ~= N.Plans[id] then
        N.Plans[id] = data.content
        N.PlanLastUpdateName[id] = UnitName("player") or N.PlanLastUpdateName[id]
        N.PlanLastUpdateTime[id] = time()
        changed = true
    end
    if data.mapID ~= nil then
        N.AutoLoad = N.AutoLoad or {}
        -- 解除旧映射
        if N.AutoLoad.__reverse and N.AutoLoad.__reverse[id] then
            local old = N.AutoLoad.__reverse[id]
            N.AutoLoad[old] = nil
            N.AutoLoad.__reverse[id] = nil
        end
        if data.mapID then
            N.AutoLoad[data.mapID] = id
            N.AutoLoad.__reverse = N.AutoLoad.__reverse or {}
            N.AutoLoad.__reverse[id] = data.mapID
        end
        changed = true
    end
    if data.encounterID ~= nil then
        local oldEncounterID = tonumber(N.PlanEncounterIDs[id])
        if oldEncounterID and N.EncounterAutoLoad and N.EncounterAutoLoad[oldEncounterID] == id then
            N.EncounterAutoLoad[oldEncounterID] = nil
        end
        N.PlanEncounterIDs[id] = nil

        local normalizedEncounterID = tonumber(data.encounterID)
        if normalizedEncounterID and normalizedEncounterID > 0 then
            N.EncounterAutoLoad = N.EncounterAutoLoad or {}
            local oldPlanID = tonumber(N.EncounterAutoLoad[normalizedEncounterID])
            if oldPlanID and oldPlanID ~= id then
                N.PlanEncounterIDs[oldPlanID] = nil
            end
            N.EncounterAutoLoad[normalizedEncounterID] = id
            N.PlanEncounterIDs[id] = normalizedEncounterID
        end
        changed = true
    end
    return changed
end

-- 删除方案（不重排 ID）
function Note:DeletePlan(id)
    local N = D()
    if not id or not N.Plans[id] then return false end
    ClearBossBindingForPlan(N, id, N.SemanticBossKeyByPlanID, N.SemanticPlanIDByBossKey, "semantic_boss", true)
    ClearBossBindingForPlan(N, id, N.PersonalBossPlansByID, N.PersonalBossPlans, "personal_boss", false)
    N.Plans[id] = nil
    N.PlanNames[id] = nil
    N.PlanLastUpdateName[id] = nil
    N.PlanLastUpdateTime[id] = nil
    N.PlanAuthor[id] = nil
    N.PlanCreatedTime[id] = nil
    if N.AutoLoad and N.AutoLoad.__reverse and N.AutoLoad.__reverse[id] then
        local mapID = N.AutoLoad.__reverse[id]
        N.AutoLoad[mapID] = nil
        N.AutoLoad.__reverse[id] = nil
    end
    local encounterID = tonumber(N.PlanEncounterIDs[id])
    if encounterID and N.EncounterAutoLoad and N.EncounterAutoLoad[encounterID] == id then
        N.EncounterAutoLoad[encounterID] = nil
    end
    N.PlanEncounterIDs[id] = nil
    if N.currentSTNNote == id then
        N.currentSTNNote = nil
    end
    return true
end

-- 设置/获取激活方案
function Note:SetActivePlan(id, options)
    local N = D()
    if not id or not N.Plans[id] then return false end
    N.currentSTNNote = id
    local opts = options or {}
    if opts.manual == true then
        self:MarkManualPlanSelection(id, opts.contextKey)
    elseif opts.contextKey and opts.auto == true then
        self.autoState = self.autoState or {}
        self.autoState.lastContextKey = tostring(opts.contextKey)
        self.autoState.lastAutoPlanID = tonumber(id)
    end
    return true
end
function Note:GetActivePlan()
    local N = D()
    local id = N.currentSTNNote
    if id and N.Plans[id] then
        return self:GetPlan(id)
    end
    return nil
end

-- 复制方案
function Note:CopyPlan(id, newName)
    local p = self:GetPlan(id)
    if not p then return nil end
    local nid = self:CreatePlan(newName or (p.name .. " - 副本"), p.content, p.mapID, p.encounterID)
    return nid
end

-- 根据区域 ID 查找方案
function Note:GetPlanByMapID(mapID)
    local N = D()
    if not mapID or not N.AutoLoad then return nil end
    local id = N.AutoLoad[mapID]
    if id and N.Plans[id] then return self:GetPlan(id) end
    return nil
end

function Note:GetPlanByEncounterID(encounterID)
    local N = D()
    local normalizedEncounterID = tonumber(encounterID)
    if not normalizedEncounterID or normalizedEncounterID <= 0 or not N.EncounterAutoLoad then
        return nil
    end
    local id = N.EncounterAutoLoad[normalizedEncounterID]
    if id and N.Plans[id] then
        return self:GetPlan(id)
    end
    return nil
end

function Note:GetCurrentMapID()
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = tonumber(C_Map.GetBestMapForUnit("player"))
        if mapID and mapID > 0 then
            return mapID
        end
    end
    return nil
end

function Note:GetCurrentEncounterID()
    local state = self.autoState or {}
    local encounterID = tonumber(state.runtimeEncounterID)
    if encounterID and encounterID > 0 then
        return encounterID
    end
    if T.SemanticTimeline and T.SemanticTimeline.GetLastKnownEncounterID then
        encounterID = tonumber(T.SemanticTimeline:GetLastKnownEncounterID())
        if encounterID and encounterID > 0 then
            return encounterID
        end
    end
    return nil
end

function Note:ResolveAutoPlanTarget()
    local mapID = self:GetCurrentMapID()
    local mapPlan = mapID and self:GetPlanByMapID(mapID) or nil
    if mapPlan then
        return {
            plan = mapPlan,
            mapID = mapID,
            encounterID = tonumber(mapPlan.encounterID) or self:GetCurrentEncounterID(),
            source = "map",
            contextKey = string.format("map:%d", mapID),
        }
    end

    local encounterID = self:GetCurrentEncounterID()
    local encounterPlan = encounterID and self:GetPlanByEncounterID(encounterID) or nil
    if encounterPlan then
        return {
            plan = encounterPlan,
            mapID = mapID,
            encounterID = encounterID,
            source = "encounter",
            contextKey = string.format("encounter:%d", encounterID),
        }
    end

    return nil
end

function Note:MarkManualPlanSelection(id, contextKey)
    local normalizedPlanID = tonumber(id)
    if not normalizedPlanID then
        return
    end

    local targetContextKey = contextKey
    if targetContextKey == nil then
        local target = self:ResolveAutoPlanTarget()
        targetContextKey = target and target.contextKey or nil
    end

    self.autoState = self.autoState or {}
    self.autoState.manualPlanID = normalizedPlanID
    self.autoState.manualContextKey = targetContextKey and tostring(targetContextKey) or nil
end

function Note:ApplyAutoPlanSelection(reason)
    local target = self:ResolveAutoPlanTarget()
    if not target or not target.plan or not target.contextKey then
        return false, "no_target"
    end

    local state = self.autoState or {}
    self.autoState = state

    if state.manualContextKey and state.manualContextKey ~= target.contextKey then
        state.manualContextKey = nil
        state.manualPlanID = nil
    end

    local activePlanID = tonumber(D() and D().currentSTNNote)
    if state.manualContextKey == target.contextKey
        and tonumber(state.manualPlanID)
        and activePlanID == tonumber(state.manualPlanID) then
        return false, "manual_override"
    end

    local targetPlanID = tonumber(target.plan.id)
    state.lastResolvedSource = tostring(reason or target.source or "")
    state.lastResolvedContextKey = target.contextKey
    state.lastResolvedMapID = tonumber(target.mapID) or nil
    state.lastResolvedEncounterID = tonumber(target.encounterID) or nil

    if activePlanID == targetPlanID then
        state.lastContextKey = target.contextKey
        state.lastAutoPlanID = targetPlanID
        return false, "already_active"
    end

    self:SetActivePlan(targetPlanID, {
        auto = true,
        contextKey = target.contextKey,
    })

    if C and C.DB and C.DB.debugMode then
        T.debug(string.format(
            "AutoSelectPlan: reason=%s source=%s context=%s plan=%s",
            tostring(reason or ""),
            tostring(target.source or ""),
            tostring(target.contextKey),
            tostring(targetPlanID)
        ))
    end
    return true, target
end

function Note:ScheduleAutoPlanSelection(reason, delay)
    self.autoState = self.autoState or {}
    if self.autoState.refreshTimer and self.autoState.refreshTimer.Cancel then
        self.autoState.refreshTimer:Cancel()
    end
    self.autoState.refreshTimer = C_Timer.NewTimer(delay or 0.2, function()
        if self.autoState then
            self.autoState.refreshTimer = nil
        end
        self:ApplyAutoPlanSelection(reason)
    end)
end

function Note:OnAutoEvent(event, ...)
    self.autoState = self.autoState or {}
    if event == "ENCOUNTER_START" then
        self.autoState.runtimeEncounterID = tonumber((...))
        self:ScheduleAutoPlanSelection("encounter_start", 0.1)
    elseif event == "PLAYER_LOGIN" then
        self:ScheduleAutoPlanSelection("player_login", 0.5)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        if not IsInInstance or not select(1, IsInInstance()) then
            self.autoState.runtimeEncounterID = nil
        end
        self:ScheduleAutoPlanSelection(string.lower(event), 0.5)
    end
end

function Note:InitAutoSwitch()
    self.autoState = self.autoState or {}
    if self._autoFrame then
        return
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("ZONE_CHANGED_INDOORS")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:SetScript("OnEvent", function(_, event, ...)
        self:OnAutoEvent(event, ...)
    end)
    self._autoFrame = frame
    self:ScheduleAutoPlanSelection("init", 0.5)
end

--=== 兼容层（旧 API 名称，仅转发，不读旧字段）===--
function Note:GetNoteList()
    return self:GetPlanList()
end
function Note:GetNote(id)
    return self:GetPlan(id)
end
function Note:CreateNote(name, content, type)
    -- 兼容旧签名：忽略 type，统一创建为普通方案
    return self:CreatePlan(name, content)
end
function Note:UpdateNote(id, data)
    return self:UpdatePlan(id, data)
end
function Note:DeleteNote(id)
    return self:DeletePlan(id)
end
function Note:CopyNote(id, newName)
    return self:CopyPlan(id, newName)
end
function Note:SetCurrentNote(id)
    return self:SetActivePlan(id)
end

-- 导出方案
function Note:ExportNote(id)
    local note = self:GetPlan(id)
    if not note then return nil end
    
    -- 导出时补齐副本/首领ID与最近更新人/时间元数据，便于跨端同步
    -- 编码规则：使用管道分隔，内容做转义；前缀区分版本
    local prefix = "STT_NOTE2"
    local function esc(s)
        s = tostring(s or "")
        s = s:gsub("|", "##PIPE##")
        s = s:gsub("\n", "##NL##")
        return s
    end
    local parts = {
        prefix,
        esc(note.name),
        esc(note.author or UnitName("player") or ""),
        esc(T.Version or ""),
        tostring(time()),
        tostring(note.encounterID or ""),
        esc(note.lastUpdateName or note.author or UnitName("player") or ""),
        tostring(note.lastUpdateTime or note.modified or time()),
        esc(note.content or "")
    }
    return table.concat(parts, "|")
end

-- 导入方案
function Note:ImportNote(str)
    if not str or type(str) ~= "string" then
        return false, "无效的导入数据"
    end
    local function unesc(s)
        s = tostring(s or "")
        s = s:gsub("##PIPE##", "|")
        s = s:gsub("##NL##", "\n")
        return s
    end

    local name, author, ver, ts, encounterID, lastName, lastTime, content

    if str:match("^STT_NOTE2|") then
        local parts = {}
        for part in str:gmatch("[^|]+") do table.insert(parts, part) end
        -- parts: [1]=STT_NOTE2, 2=name,3=author,4=ver,5=ts,6=encounterID,7=lastName,8=lastTime,9=content
        if #parts < 9 then return false, "导入数据不完整" end
        name = unesc(parts[2])
        author = unesc(parts[3])
        ver = unesc(parts[4])
        ts = tonumber(parts[5])
        encounterID = tonumber(parts[6]) or nil
        lastName = unesc(parts[7])
        lastTime = tonumber(parts[8])
        content = unesc(table.concat(parts, "|", 9)) -- 允许内容内包含转义过的管道
    elseif str:match("^STT_NOTE:") then
        local raw = str:sub(10)
        local parts = {}
        for part in raw:gmatch("[^|]+") do table.insert(parts, part) end
        if #parts < 5 then return false, "导入数据不完整" end
        name = unesc(parts[1])
        author = unesc(parts[2])
        ver = unesc(parts[3])
        ts = tonumber(parts[4])
        content = unesc(table.concat(parts, "|", 5))
    else
        -- 无前缀导入也必须是新结构化模板
        name = L["导入方案"]
        author = UnitName("player") or ""
        ver = T.Version
        ts = time()
        content = str
    end

    local valid, info = IsPlayableStructuredContent(content)
    if not valid then
        return false, BuildTemplateRejectReason(info)
    end

    local id = self:CreateNote((name or L["新方案"]) .. " (导入)", content or "", "personal")
    if not id then return false, "创建方案失败" end
    if encounterID then
        self:UpdatePlan(id, { encounterID = encounterID })
    end
    local N = D()
    if N and N.Plans[id] then
        N.PlanAuthor[id] = author or N.PlanAuthor[id]
        N.PlanLastUpdateName[id] = lastName or author or N.PlanLastUpdateName[id]
        N.PlanLastUpdateTime[id] = lastTime or ts or N.PlanLastUpdateTime[id]
    end
    return true, id
end

-- 发送到团队（聊天文本，不带结构化数据）
function Note:SendToRaid(id)
    local note = self:GetPlan(id)
    if not note then return false end

    local valid, info = IsPlayableStructuredContent(note.content or "")
    if not valid then
        T.msg(BuildTemplateRejectReason(info))
        return false
    end
    
    -- 检查是否在团队中
    if not IsInRaid() and not IsInGroup() then
        T.msg("你不在团队或小队中")
        return false
    end

    -- 12.0 限制：副本/团队副本内不发送聊天（避免与系统限制冲突）
    local inInstance = IsInInstance()
    if inInstance then
        T.msg("12.0 限制：副本内禁用发送团队笔记")
        return false
    end
    
    local channel = IsInRaid() and "RAID" or "PARTY"
    
    -- 分割内容为多行
    local lines = {}
    for line in note.content:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    -- 发送标题
    SendChatMessage("===== " .. note.name .. " =====", channel)
    
    -- 逐行发送内容
    for i, line in ipairs(lines) do
        -- 移除颜色代码
        line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        SendChatMessage(line, channel)
    end
    
    -- 发送结束标记
    SendChatMessage("===== 结束 =====", channel)
    
    T.msg("方案已发送到" .. (IsInRaid() and "团队" or "小队"))
    return true
end

function Note:IsCommAllowed()
    local sync = GetNoteSync()
    if sync and sync.IsCommAllowed then
        return sync:IsCommAllowed(self)
    end
    return false, "通信模块未加载"
end

function Note:QueuePayloadToSTT(proto, payload, summaryLabel, callbacks)
    local sync = GetNoteSync()
    if sync and sync.QueuePayloadToSTT then
        return sync:QueuePayloadToSTT(self, proto, payload, summaryLabel, callbacks)
    end
    return false, "sync_module_missing"
end

function Note:SendToSTT(id)
    local sync = GetNoteSync()
    if sync and sync.SendToSTT then
        return sync:SendToSTT(self, id)
    end
    return false, "sync_module_missing"
end

function Note:SendSemanticBossToSTT(bossKey, content, callbacks)
    local sync = GetNoteSync()
    if sync and sync.SendSemanticBossToSTT then
        return sync:SendSemanticBossToSTT(self, bossKey, content, callbacks)
    end
    return false, "sync_module_missing"
end

function Note:ReceiveSemanticBossFromSTT(payload, sender)
    local sync = GetNoteSync()
    if sync and sync.ReceiveSemanticBossFromSTT then
        return sync:ReceiveSemanticBossFromSTT(self, payload, sender)
    end
    return nil
end

function Note:OnCommPayload(payload, channel, sender, meta)
    local sync = GetNoteSync()
    if sync and sync.OnCommPayload then
        return sync:OnCommPayload(self, payload, channel, sender, meta)
    end
end

function Note:OnCommDecodeFailed(meta)
    local sync = GetNoteSync()
    if sync and sync.OnCommDecodeFailed then
        return sync:OnCommDecodeFailed(self, meta)
    end
end

-- 搜索方案
function Note:SearchNotes(keyword)
    local results = {}
    keyword = keyword:lower()
    
    local function checkNote(note)
        local name = note.name:lower()
        local content = note.content:lower()
        if name:find(keyword, 1, true) or content:find(keyword, 1, true) then
            return true
        end
        return false
    end
    
    -- 搜索所有方案
    local N = D()
    for id, content in pairs(N.Plans) do
        local note = { name = N.PlanNames[id] or (L["方案"] .. id), content = content }
        if checkNote(note) then
            table.insert(results, {id = id, note = note, type = "plan"})
        end
    end
    
    return results
end

-- 获取方案统计
function Note:GetStatistics()
    local stats = {
        total = 0,
        main = 0,
        personal = 0,
        drafts = 0,
        totalLines = 0,
        totalChars = 0
    }
    
    local N = D()
    for _, content in pairs(N.Plans) do
        stats.main = stats.main + 1
        stats.totalChars = stats.totalChars + #content
        for _ in content:gmatch("\n") do
            stats.totalLines = stats.totalLines + 1
        end
    end
    stats.total = stats.main
    return stats
end

-- 自动保存草稿（保留但走 v2 方案，不再单独 drafts 容器）
function Note:AutoSaveDraft(content)
    if not self.autoSaveDraftId then
        self.autoSaveDraftId = self:CreatePlan("自动保存", content)
    else
        self:UpdatePlan(self.autoSaveDraftId, {content = content})
    end
    return self.autoSaveDraftId
end

function Note:OnProfileChanged()
    self.autoState = nil
    self.autoSaveDraftId = nil
end

if T.events then
    T.events:Register("STT_PROFILE_CHANGED", Note, Note.OnProfileChanged)
end

T.RegisterInitCallback(function()
    Note:InitDB()
    Note:InitComm()
end)

end)
