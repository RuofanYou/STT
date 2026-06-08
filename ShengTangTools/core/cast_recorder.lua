-- 施法记录器（Cast Recorder）
-- 记录玩家自己整场战斗的施法序列，用于战后对照回放。
--
-- 合规说明：
--   采集手段为 UNIT_SPELLCAST_SUCCEEDED 与蓄力施法 UNIT_SPELLCAST_EMPOWER_* ——
--   纯 UI 事件，仅取 unit=="player"，不触碰战斗日志。记录与回放都是纯数据呈现，
--   不在战斗中驱动任何决策或游戏内行为。后台记录默认启用，面板开关只控制显示。
--
-- 数据本地持久化到 STT_CDB.castRecords（PerCharacter）。
-- 团队收集由 cast_log_comm.lua 按手动请求读取最近记录。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("castRecorder.backendEnabled", function()

local DB_KEY = "castRecorder"
local DEFAULT_MAX_RECORDS = 1
local PHASE_POLL_INTERVAL = 0.5

local Recorder = T.ModuleLoader:NewModule({
    name = "CastRecorder",
    dbKey = "castRecorder.backendEnabled",
    defaultEnabled = false,
})

function Recorder:OnRegister()
    T.CastRecorder = self
end
T.CastRecorder = Recorder

-- 当前录制缓冲：仅在 ENCOUNTER_START~END 之间非 nil
local recording = nil
local phaseTicker = nil

local function GetDB()
    C.DB[DB_KEY] = C.DB[DB_KEY] or {}
    if type(STT_DB) == "table" then
        STT_DB[DB_KEY] = C.DB[DB_KEY]
    end
    return C.DB[DB_KEY]
end

local function GetMaxRecords()
    local n = tonumber(GetDB().maxRecords)
    if not n or n < 1 then
        return DEFAULT_MAX_RECORDS
    end
    return math.max(1, math.min(5, math.floor(n)))
end

-- 录像存储（PerCharacter）。TOC 声明的 STT_CDB 在该角色首次存档前为 nil，
-- STT 核心未统一初始化它；与 option_push.lua 一致，由使用方在此确保就绪。
local function GetStore()
    STT_CDB = type(STT_CDB) == "table" and STT_CDB or {}
    STT_CDB.castRecords = STT_CDB.castRecords or {}
    return STT_CDB.castRecords
end

local function TrimStore(store)
    local maxN = GetMaxRecords()
    while #store > maxN do
        table.remove(store, #store)
    end
end

-- 取录制时刻激活的 STN 方案 ID，用于回放对照
local function GetActivePlanId()
    if not T.Note or not T.Note.GetPlanList then
        return nil
    end
    for _, plan in ipairs(T.Note:GetPlanList()) do
        if plan.isActive then
            return plan.id
        end
    end
    return nil
end

local function GetCurrentBossKeyText()
    return T.Note and T.Note.GetCurrentBossKey and T.Note:GetCurrentBossKey() or nil
end

local function StopPhaseTicker()
    if phaseTicker then
        phaseTicker:Cancel()
        phaseTicker = nil
    end
end

-- 轮询阶段：不抢占 phase_detector 的 onPhaseChanged 单一回调，仅只读 GetCurrentPhase
local function StartPhaseTicker()
    StopPhaseTicker()
    phaseTicker = C_Timer.NewTicker(PHASE_POLL_INTERVAL, function()
        if not recording then
            return
        end
        local cur = T.PhaseDetector and T.PhaseDetector:GetCurrentPhase() or nil
        if cur and cur ~= recording.lastPhase then
            recording.lastPhase = cur
            recording.phases[#recording.phases + 1] = {
                t = GetTime() - recording.startTime,
                phase = cur,
            }
        end
    end)
end

function Recorder:ENCOUNTER_START(event, encounterID, encounterName, difficultyID, groupSize)
    local initialPhase = T.PhaseDetector and T.PhaseDetector:GetCurrentPhase() or nil
    recording = {
        encounterID = encounterID,
        encounterName = encounterName,
        difficulty = difficultyID,
        startTime = GetTime(),
        planId = GetActivePlanId(),
        bossKeyText = GetCurrentBossKeyText(),
        casts = {},
        castGUIDs = {},
        empower = {},
        phases = { { t = 0, phase = initialPhase or "p1" } },
        lastPhase = initialPhase,
    }
    -- 仅在战斗期间订阅施法事件，平时零订阅
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SUCCEEDED")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_START")
    self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_EMPOWER_STOP")
    StartPhaseTicker()
end

local function IsRecordableSpell(spellID)
    local id = tonumber(spellID)
    if not id then
        return false
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        local name = ok and type(info) == "table" and info.name or ok and type(info) == "string" and info or nil
        if type(name) == "string" and (name:match("^%[DNT%]") or name:match("^%(DNT%)")) then
            return false
        end
    end
    return true
end

local function RecordCast(castGUID, spellID, duration, failed)
    if not recording or not spellID then
        return
    end
    if not IsRecordableSpell(spellID) then
        return
    end
    if castGUID then
        if recording.castGUIDs[castGUID] then
            return
        end
        recording.castGUIDs[castGUID] = true
    end
    recording.casts[#recording.casts + 1] = {
        t = GetTime() - recording.startTime,
        s = spellID,
        d = duration and duration > 0 and duration or nil,
        f = failed == true and true or nil,
    }
end

function Recorder:UNIT_SPELLCAST_SUCCEEDED(event, unitTarget, castGUID, spellID)
    if unitTarget ~= "player" then
        return
    end
    if recording and castGUID and recording.empower[castGUID] then
        return
    end
    RecordCast(castGUID, spellID)
end

function Recorder:UNIT_SPELLCAST_EMPOWER_START(event, unitTarget, castGUID, spellID)
    if unitTarget ~= "player" or not recording or not castGUID or not spellID then
        return
    end
    if not IsRecordableSpell(spellID) then
        return
    end
    recording.empower[castGUID] = {
        t = GetTime() - recording.startTime,
        s = spellID,
    }
end

function Recorder:UNIT_SPELLCAST_EMPOWER_STOP(event, unitTarget, castGUID, spellID, complete, interruptedBy)
    if unitTarget ~= "player" then
        return
    end
    local start = recording and castGUID and recording.empower[castGUID] or nil
    if start then
        recording.empower[castGUID] = nil
        if recording.castGUIDs[castGUID] then
            return
        end
        recording.castGUIDs[castGUID] = true
        local startTime = tonumber(start.t) or (GetTime() - recording.startTime)
        local duration = math.max(0, GetTime() - recording.startTime - startTime)
        recording.casts[#recording.casts + 1] = {
            t = startTime,
            s = spellID or start.s,
            d = duration > 0 and duration or nil,
            f = ((complete == false) or interruptedBy ~= nil) and true or nil,
        }
        return
    end
    RecordCast(castGUID, spellID, nil, (complete == false) or interruptedBy ~= nil)
end

function Recorder:ENCOUNTER_END(event, encounterID, encounterName, difficultyID, groupSize, success)
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_START")
    self:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    StopPhaseTicker()
    local rec = recording
    recording = nil
    if not rec then return end
    -- 空录像（整场没记到自己任何施法）直接丢弃
    if #rec.casts == 0 then return end
    local store = GetStore()

    table.insert(store, 1, {
        encounterID = rec.encounterID,
        encounterName = rec.encounterName,
        difficulty = rec.difficulty,
        success = (success == 1) or (success == true),
        date = GetServerTime(),
        duration = GetTime() - rec.startTime,
        planId = rec.planId,
        bossKeyText = rec.bossKeyText,
        -- 录制者身份用于甘特图行标签与职业色。
        playerName = UnitName("player"),
        playerClass = select(2, UnitClass("player")),
        casts = rec.casts,
        phases = rec.phases,
    })

    -- 保留策略：仅留最近 N 场，裁剪超出部分
    TrimStore(store)

end

function Recorder:OnEnable()
    TrimStore(GetStore())
    self:RegisterEvent("ENCOUNTER_START", "ENCOUNTER_START")
    self:RegisterEvent("ENCOUNTER_END", "ENCOUNTER_END")
end

function Recorder:OnDisable()
    -- 事件由 ModuleLoader:_DoDisable 统一 UnregisterAllEvents，这里只清运行态
    StopPhaseTicker()
    recording = nil
end

--=== 供回放 GUI 使用的公开 API ===--

function Recorder:GetRecords()
    local store = GetStore()
    TrimStore(store)
    return store
end

function Recorder:TrimSavedRecords()
    local store = GetStore()
    local before = #store
    TrimStore(store)
    return math.max(0, before - #store), #store
end

function Recorder:DeleteRecord(index)
    local store = GetStore()
    if store and store[index] then
        table.remove(store, index)
        return true
    end
    return false
end

function Recorder:ClearAllRecords()
    GetStore()
    STT_CDB.castRecords = {}
end

end)
