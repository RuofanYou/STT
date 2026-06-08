-- 施法记录甘特图临时行（Cast Log Row）
-- 作为只读行插入到战术方案「水平视角甘特图」的最上方，
-- 显示玩家自己与团队成员本场战斗的实际施法，与下方方案技能点做「计划 vs 实际」对照。
--
-- 这里只做数据适配：把录像转换成 horizontal_timeline_data 的标准 entry/items，
-- 展开按钮、分技能子行、横向滚动和 tooltip 都继续复用水平时间轴的单一渲染链路。
-- 行被标记 readOnly=true：甘特图据此屏蔽交互、给 chip 加青色边框、给整行加 accent
-- rail 与青色 tint —— 视觉上区分「实际记录层」与「方案计划层」。
-- 行标签用录制者角色名 + 职业色。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local CastLogRow = {}
T.CastLogRow = CastLogRow

local DB_KEY = "castRecorder"
local ROW_KEY_PREFIX = "__castlog__:"
local ROW_ICON = "Interface\\COMMON\\Indicator-Gray"   -- 行首 status dot，渲染时按职业色染色

local lastGui = nil

local function Debug(fmt, ...)
    if not T.debug then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[CastLogRow] " .. tostring(fmt), ...))
    else
        T.debug("[CastLogRow] " .. tostring(fmt))
    end
end

local function GetDB()
    if C and C.DB then
        C.DB[DB_KEY] = C.DB[DB_KEY] or {}
        return C.DB[DB_KEY]
    end
    return {}
end

-- 显示条件：是否在甘特图里显示施法记录行。
-- 后台记录始终启用；团队记录只在团长手动刷新后通信，这里只控制本机是否显示记录行。
local function ShouldShow()
    local db = GetDB()
    return db.showInGantt ~= false
end

local function GetCurrentEncounterID()
    local bossKeyText = T.Note and T.Note.GetCurrentBossKey and T.Note:GetCurrentBossKey() or nil
    local bossKey = bossKeyText and T.ParseSemanticBossKeyText and T.ParseSemanticBossKeyText(bossKeyText) or nil
    if type(bossKey) == "table" then
        return tonumber(bossKey.encounterID)
    end
    return nil
end

local function GetCurrentBossKeyText()
    return T.Note and T.Note.GetCurrentBossKey and T.Note:GetCurrentBossKey() or ""
end

-- 找匹配当前甘特图 Boss 的最近一场本地录像（GetRecords 最新在前）。
local function FindRecord(teamEncounterIDs)
    if not T.CastRecorder or not T.CastRecorder.GetRecords then
        return nil
    end
    local records = T.CastRecorder:GetRecords()
    local currentBossKeyText = GetCurrentBossKeyText()
    if currentBossKeyText ~= "" then
        for _, rec in ipairs(records) do
            if tostring(rec and rec.bossKeyText or "") == currentBossKeyText then
                return rec
            end
        end
    end
    local encounterID = GetCurrentEncounterID()
    if encounterID then
        for _, rec in ipairs(records) do
            if tonumber(rec.encounterID) == encounterID then
                return rec
            end
        end
    end
    if type(teamEncounterIDs) == "table" then
        for _, rec in ipairs(records) do
            local id = tonumber(rec and rec.encounterID)
            if id and teamEncounterIDs[id] == true then
                return rec
            end
        end
    end
    return nil
end

local function SpellIcon(spellID)
    if T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        local icon = T.TimelineSyntax.ResolveSpellIcon(spellID)
        if icon then
            return icon
        end
    end
    return 134400
end

local function SpellName(spellID)
    local id = tonumber(spellID)
    if not id then
        return nil
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok then
            if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
                return info.name
            elseif type(info) == "string" and info ~= "" then
                return info
            end
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tostring(id)
end

-- 录制者身份：优先用录像字段，回退当前角色。
local function PlayerNameOf(record)
    return (record and record.playerName) or UnitName("player") or "?"
end

local function PlayerClassOf(record)
    return (record and record.playerClass) or select(2, UnitClass("player"))
end

local function MakeRowKey(record)
    return ROW_KEY_PREFIX .. PlayerNameOf(record)
end

local function IsCastLogKey(key)
    return key == "__castlog__" or (type(key) == "string" and key:sub(1, #ROW_KEY_PREFIX) == ROW_KEY_PREFIX)
end

local function RemoveCastLogKeys(gui)
    if type(gui) ~= "table" then
        return
    end
    if type(gui.perRow) == "table" then
        for key in pairs(gui.perRow) do
            if IsCastLogKey(key) then
                gui.perRow[key] = nil
            end
        end
    end
    local keys = gui.orderedKeys
    if type(keys) ~= "table" then
        return
    end
    for index = #keys, 1, -1 do
        if IsCastLogKey(keys[index]) then
            table.remove(keys, index)
        end
    end
end

local function BuildEntry(record, rowKey)
    local displayName = PlayerNameOf(record)
    local entry = {
        key = rowKey,
        meta = {
            kind = "castLog",
            displayText = displayName,
            classFile = PlayerClassOf(record),
            iconTexture = ROW_ICON,
        },
        items = {},
        firstTime = 0,
        firstSortIndex = -1000000,
        sortOrder = -1000000,
        readOnly = true,
    }
    local maxTime = tonumber(record and record.duration) or 0
    for index, cast in ipairs(record and record.casts or {}) do
        local time = math.max(0, tonumber(cast.t) or 0)
        local spellID = tonumber(cast.s) or 0
        local name = SpellName(spellID)
        local icon = SpellIcon(spellID)
        local duration = tonumber(cast.d)
        local failed = cast.f == true
        entry.items[#entry.items + 1] = {
            time = time,
            sourceTime = time,
            phaseDisplayOffset = 0,
            spellID = spellID,
            spellIcon = icon,
            fullText = name,
            who = displayName,
            targetKind = "castLog",
            sourceWho = displayName,
            sourceWhoType = "castLog",
            sourceCondition = "",
            sourcePlayersText = "",
            sourceSegmentText = name,
            sourceSegmentIndex = index,
            timePayload = "",
            lineNum = -index,
            rowID = rowKey .. ":" .. tostring(index),
            editorTab = "castLog",
            sourcePlanID = nil,
            rowKey = rowKey,
            duration = duration and duration > 0 and duration or nil,
            castFailed = failed,
            collisions = {},
            readOnly = true,
        }
        if failed then
            entry.items[#entry.items].sourceCondition = "failed"
        end
        local endTime = time + (duration and duration > 0 and duration or 0)
        if endTime > maxTime then
            maxTime = endTime
        end
    end
    return entry, maxTime
end

local function RecordMatchesCurrentBoss(record, ownRecord)
    local currentBossKeyText = GetCurrentBossKeyText()
    local recordBossKeyText = tostring(record and record.bossKeyText or "")
    if currentBossKeyText ~= "" and recordBossKeyText ~= "" then
        if recordBossKeyText == currentBossKeyText then
            return true
        end
        if ownRecord and tonumber(record and record.encounterID) == tonumber(ownRecord.encounterID) then
            return true
        end
        return false, "boss_key_mismatch"
    end
    if ownRecord and tonumber(record and record.encounterID) == tonumber(ownRecord.encounterID) then
        return true
    end
    local encounterID = GetCurrentEncounterID()
    if encounterID ~= nil and tonumber(record and record.encounterID) == encounterID then
        return true
    end
    return false, "encounter_mismatch"
end

local function CollectRecords()
    local records = {}
    local seen = {}
    local teamRecords = T.CastLogComm and T.CastLogComm.GetTeamRecords and T.CastLogComm.GetTeamRecords() or nil
    local teamEncounterIDs = {}
    if type(teamRecords) == "table" then
        for _, record in pairs(teamRecords) do
            local matched = RecordMatchesCurrentBoss(record, nil)
            local encounterID = tonumber(record and record.encounterID)
            if matched and encounterID then
                teamEncounterIDs[encounterID] = true
            end
        end
    end
    local ownRecord = FindRecord(teamEncounterIDs)
    if ownRecord then
        local key = MakeRowKey(ownRecord)
        records[#records + 1] = ownRecord
        seen[key] = true
    end
    if type(teamRecords) == "table" then
        local sorted = {}
        for _, record in pairs(teamRecords) do
            local matched, reason = RecordMatchesCurrentBoss(record, ownRecord)
            if matched then
                sorted[#sorted + 1] = record
            else
                Debug("RecordFiltered id=%s player=%s reason=%s recordBossKey=%s currentBossKey=%s recordEncounter=%s currentEncounter=%s", tostring(record and record.castLogID), tostring(PlayerNameOf(record)), tostring(reason), tostring(record and record.bossKeyText), tostring(GetCurrentBossKeyText()), tostring(record and record.encounterID), tostring(GetCurrentEncounterID()))
            end
        end
        table.sort(sorted, function(a, b)
            return PlayerNameOf(a) < PlayerNameOf(b)
        end)
        for _, record in ipairs(sorted) do
            local key = MakeRowKey(record)
            if not seen[key] then
                records[#records + 1] = record
                seen[key] = true
            end
        end
    end
    return records
end

-- 往水平时间轴 perRow/orderedKeys 头部插入临时行（由 Refresh 在 displayRows 构建前调用）
function CastLogRow.Inject(gui)
    if not gui or type(gui.perRow) ~= "table" or type(gui.orderedKeys) ~= "table" then
        return
    end
    lastGui = gui
    RemoveCastLogKeys(gui)
    if not ShouldShow() then
        return
    end
    local records = CollectRecords()
    if #records == 0 then
        Debug("InjectSkipped reason=no_records currentBossKey=%s currentEncounter=%s", tostring(GetCurrentBossKeyText()), tostring(GetCurrentEncounterID()))
        return
    end
    local insertIndex = 1
    for _, record in ipairs(records) do
        local rowKey = MakeRowKey(record)
        local entry, maxTime = BuildEntry(record, rowKey)
        if #entry.items > 0 then
            gui.perRow[rowKey] = entry
            table.insert(gui.orderedKeys, insertIndex, rowKey)
            insertIndex = insertIndex + 1
            if tonumber(maxTime) and maxTime > (tonumber(gui.maxTime) or 0) then
                gui.maxTime = maxTime
            end
            Debug("InjectRow id=%s rowKey=%s player=%s bossKey=%s encounter=%s items=%d", tostring(record.castLogID), tostring(rowKey), tostring(PlayerNameOf(record)), tostring(record.bossKeyText), tostring(record.encounterID), #entry.items)
        end
    end
end

-- 选项变更（开关 / 模块启停）后强制甘特图重画一次
function CastLogRow.Refresh()
    if lastGui and lastGui.Refresh then
        lastGui:Refresh(lastGui.sourceRows, { cause = "cast_log_toggle" })
    end
end

end)
