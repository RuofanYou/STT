local T, C, L = unpack(select(2, ...))

local PerfLog = T.PerfLog or {}
T.PerfLog = PerfLog

local LOG_LIMIT = 1000
local LOG_HEADER = "序号;时间;运行秒;类别;消息"
local DEFAULT_SAMPLE_INTERVAL = 1
local DEFAULT_SLOW_THRESHOLD = 5
local MAX_UPDATE_ERRORS = 5

local log = {
    start = 1,
    count = 0,
    nextSeq = 1,
    entries = {},
}

local enabled = false
local sampleFrame = nil
local eventFrame = nil
local elapsedSinceSample = 0
local updateErrorCount = 0
local sampleCount = 0
local slowCount = 0
local overheadMs = 0
local startAtMs = 0
local baseline = nil
local lastLuaKB = nil

local TokenMethods = {}

local function Now()
    return debugprofilestop and debugprofilestop() or 0
end

local function GetRuntimeSec()
    return string.format("%.3f", Now() / 1000)
end

local function GetConfig()
    STT_DB = STT_DB or {}
    if type(STT_DB.perfLog) ~= "table" then
        STT_DB.perfLog = {}
    end
    local cfg = STT_DB.perfLog
    if cfg.enabled == nil then cfg.enabled = false end
    if tonumber(cfg.slowThresholdMs) == nil then cfg.slowThresholdMs = DEFAULT_SLOW_THRESHOLD end
    if tonumber(cfg.sampleIntervalSec) == nil then cfg.sampleIntervalSec = DEFAULT_SAMPLE_INTERVAL end
    return cfg
end

local function EscapeCSVField(value)
    local text = tostring(value or "")
    if text:find("[;\"\r\n]") then
        text = text:gsub("\"", "\"\"")
        return "\"" .. text .. "\""
    end
    return text
end

local function EntryAt(relativeIndex)
    if relativeIndex < 1 or relativeIndex > log.count then
        return nil
    end
    local index = ((log.start + relativeIndex - 2) % LOG_LIMIT) + 1
    return log.entries[index]
end

local function Append(category, message)
    local index
    if log.count < LOG_LIMIT then
        index = ((log.start + log.count - 1) % LOG_LIMIT) + 1
        log.count = log.count + 1
    else
        index = log.start
        log.start = (log.start % LOG_LIMIT) + 1
    end

    log.entries[index] = {
        seq = log.nextSeq,
        timeText = date and date("%Y-%m-%d %H:%M:%S") or "",
        runtime = GetRuntimeSec(),
        category = category or "note",
        message = message or "",
    }
    log.nextSeq = log.nextSeq + 1
end

local function FormatNumber(value, suffix)
    local n = tonumber(value)
    if not n then
        return "-"
    end
    if math.abs(n) >= 10 then
        return string.format("%.0f%s", n, suffix or "")
    end
    return string.format("%.1f%s", n, suffix or "")
end

local function FormatSignedKB(value)
    local n = tonumber(value)
    if not n then
        return "-"
    end
    return string.format("%+.1fKB", n)
end

local function FormatExtra(extra)
    if type(extra) ~= "table" then
        return ""
    end
    local keys = {}
    for key in pairs(extra) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        local value = extra[key]
        if value ~= nil then
            parts[#parts + 1] = key .. "=" .. tostring(value)
        end
    end
    return table.concat(parts, " ")
end

local function GetLuaMemoryKB()
    local ok, value = pcall(collectgarbage, "count")
    if ok and tonumber(value) then
        return tonumber(value)
    end
    return nil
end

local function RefreshAddOnMemory()
    if UpdateAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
    end
end

local function GetSTTMemoryKB()
    RefreshAddOnMemory()
    if GetAddOnMemoryUsage then
        local ok, value = pcall(GetAddOnMemoryUsage, T.addon_name or "ShengTangTools")
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return nil
end

local function GetCVarBool(name)
    if C_CVar and C_CVar.GetCVarBool then
        local ok, value = pcall(C_CVar.GetCVarBool, name)
        if ok then
            return value == true
        end
    end
    if GetCVar then
        local ok, value = pcall(GetCVar, name)
        if ok then
            return tostring(value) == "1"
        end
    end
    return false
end

local function IsProfilerReady()
    if C_AddOnProfiler and C_AddOnProfiler.IsEnabled then
        local ok, value = pcall(C_AddOnProfiler.IsEnabled)
        if ok then
            return value == true
        end
    end
    return GetCVarBool("addonProfilerEnabled")
end

local function GetProfilerMetric(metricName)
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric) then
        return nil
    end
    if not IsProfilerReady() then
        return nil
    end
    local metric = Enum.AddOnProfilerMetric[metricName]
    if metric == nil then
        return nil
    end
    local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, T.addon_name or "ShengTangTools", metric)
    if ok and tonumber(value) then
        return tonumber(value)
    end
    return nil
end

local function BuildTickMessage()
    local luaKB = GetLuaMemoryKB()
    local sttKB = GetSTTMemoryKB()
    local gcDelta = nil
    if luaKB and lastLuaKB then
        gcDelta = luaKB - lastLuaKB
    end
    lastLuaKB = luaKB

    return string.format(
        "stt=%sKB lua=%sKB last=%sms recent=%sms encounter=%sms peak=%sms gc_delta=%s reconcile=%sms",
        FormatNumber(sttKB),
        FormatNumber(luaKB),
        FormatNumber(GetProfilerMetric("LastTime")),
        FormatNumber(GetProfilerMetric("RecentAverageTime")),
        FormatNumber(GetProfilerMetric("EncounterAverageTime")),
        FormatNumber(GetProfilerMetric("PeakTime")),
        FormatSignedKB(gcDelta),
        FormatNumber(T.ModuleLoader and T.ModuleLoader.lastReconcileMs or nil)
    )
end

local function Snapshot()
    return {
        luaKB = GetLuaMemoryKB(),
        sttKB = GetSTTMemoryKB(),
        recentMs = GetProfilerMetric("RecentAverageTime"),
        capturedAtMs = Now(),
    }
end

local function EnsureSampleFrame()
    if not sampleFrame then
        sampleFrame = CreateFrame("Frame")
    end
    return sampleFrame
end

local function EnsureEventFrame()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "ENCOUNTER_START" then
                local encounterID, name, difficultyID = ...
                PerfLog:RecordEvent("ENCOUNTER_START", {
                    id = tonumber(encounterID) or 0,
                    name = name,
                    diff = tonumber(difficultyID) or 0,
                })
            elseif event == "ENCOUNTER_END" then
                local encounterID, name, difficultyID, groupSize, success = ...
                PerfLog:RecordEvent("ENCOUNTER_END", {
                    id = tonumber(encounterID) or 0,
                    name = name,
                    diff = tonumber(difficultyID) or 0,
                    size = tonumber(groupSize) or 0,
                    success = tonumber(success) or 0,
                })
            elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
                PerfLog:RecordEvent(event)
            end
        end)
    end
    return eventFrame
end

local function SetEventsRegistered(state)
    local frame = EnsureEventFrame()
    if state then
        frame:RegisterEvent("ENCOUNTER_START")
        frame:RegisterEvent("ENCOUNTER_END")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        frame:UnregisterAllEvents()
    end
end

local function OnUpdate(_, elapsed)
    if not enabled then
        return
    end
    elapsedSinceSample = elapsedSinceSample + (tonumber(elapsed) or 0)
    local interval = math.max(0.2, tonumber(GetConfig().sampleIntervalSec) or DEFAULT_SAMPLE_INTERVAL)
    if elapsedSinceSample < interval then
        return
    end
    elapsedSinceSample = 0

    local before = Now()
    local ok, err = pcall(function()
        PerfLog:RecordTick(BuildTickMessage())
    end)
    overheadMs = overheadMs + math.max(0, Now() - before)

    if ok then
        updateErrorCount = 0
    else
        updateErrorCount = updateErrorCount + 1
        PerfLog:RecordNote("采样失败 err=" .. tostring(err) .. " count=" .. tostring(updateErrorCount))
        if updateErrorCount >= MAX_UPDATE_ERRORS then
            PerfLog:Stop("采样连续失败")
        end
    end
end

function PerfLog:IsEnabled()
    return enabled == true
end

function PerfLog:GetCount()
    return log.count
end

function PerfLog:IsCVarReady()
    return IsProfilerReady()
end

function PerfLog:GetSelfOverheadEstimate()
    local durationMs = math.max(1, Now() - (startAtMs > 0 and startAtMs or Now()))
    return math.max(0, overheadMs / durationMs * 100)
end

function PerfLog:RecordTick(message)
    if not enabled then
        return
    end
    sampleCount = sampleCount + 1
    Append("tick", message)
end

function PerfLog:RecordSlow(label, ms, extra)
    if not enabled then
        return
    end
    slowCount = slowCount + 1
    local details = FormatExtra(extra)
    local message = string.format("%s %sms", tostring(label or "slow"), FormatNumber(ms))
    if details ~= "" then
        message = message .. " " .. details
    end
    Append("slow", message)
end

function PerfLog:RecordEvent(label, extra)
    if not enabled then
        return
    end
    local details = FormatExtra(extra)
    local message = tostring(label or "event")
    if details ~= "" then
        message = message .. " " .. details
    end
    Append("event", message)
end

function PerfLog:RecordNote(message)
    if not enabled and message ~= "clear" then
        return
    end
    Append("note", message)
end

function TokenMethods:Finish(extra)
    if self.finished or not enabled then
        return
    end
    self.finished = true
    local before = Now()
    local ms = math.max(0, before - (self.startedAt or before))
    local threshold = tonumber(GetConfig().slowThresholdMs) or DEFAULT_SLOW_THRESHOLD
    if ms >= threshold then
        PerfLog:RecordSlow(self.label, ms, extra)
    end
    overheadMs = overheadMs + math.max(0, Now() - before)
end

function PerfLog:Begin(label)
    if not enabled then
        return nil
    end
    return setmetatable({
        label = tostring(label or "operation"),
        startedAt = Now(),
        finished = false,
    }, { __index = TokenMethods })
end

function PerfLog:Clear()
    log.start = 1
    log.count = 0
    log.nextSeq = 1
    wipe(log.entries)
end

function PerfLog:BuildCSV()
    local lines = { LOG_HEADER }
    if log.count == 0 then
        lines[#lines + 1] = ";;;;" .. EscapeCSVField("暂无性能日志；执行 /st plog on 后复现卡顿，再用 /st plog 打开复制")
        return table.concat(lines, "\n")
    end
    for i = 1, log.count do
        local entry = EntryAt(i)
        if entry then
            lines[#lines + 1] = table.concat({
                EscapeCSVField(entry.seq),
                EscapeCSVField(entry.timeText),
                EscapeCSVField(entry.runtime),
                EscapeCSVField(entry.category),
                EscapeCSVField(entry.message),
            }, ";")
        end
    end
    return table.concat(lines, "\n")
end

function PerfLog:Start()
    if enabled then
        self:RecordNote("plog 已在运行")
        return
    end

    local cfg = GetConfig()
    enabled = true
    cfg.enabled = true
    elapsedSinceSample = 0
    updateErrorCount = 0
    sampleCount = 0
    slowCount = 0
    overheadMs = 0
    startAtMs = Now()
    baseline = Snapshot()
    lastLuaKB = baseline and baseline.luaKB or nil

    EnsureSampleFrame():SetScript("OnUpdate", OnUpdate)
    SetEventsRegistered(true)

    self:RecordNote(string.format(
        "plog 启动 cvar=%s sample=%.1fs slow=%sms buffer_limit=%d",
        self:IsCVarReady() and "1" or "0",
        tonumber(cfg.sampleIntervalSec) or DEFAULT_SAMPLE_INTERVAL,
        FormatNumber(tonumber(cfg.slowThresholdMs) or DEFAULT_SLOW_THRESHOLD),
        LOG_LIMIT
    ))
    if not self:IsCVarReady() then
        self:RecordNote("addOnProfilerEnabled 未开启；CPU 字段会显示 -，STT 不会擅自开启该 cvar")
    end
end

function PerfLog:Stop(reason)
    if not enabled then
        return
    end

    local finish = Snapshot()
    local durationSec = math.max(0, (Now() - startAtMs) / 1000)
    local luaDelta = finish and baseline and finish.luaKB and baseline.luaKB and (finish.luaKB - baseline.luaKB) or nil
    local recentDelta = finish and baseline and finish.recentMs and baseline.recentMs and (finish.recentMs - baseline.recentMs) or nil

    self:RecordNote(string.format(
        "plog 停止%s 持续=%s秒 采样=%d条 慢操作=%d条 lua_delta=%s recent_delta=%sms 自身估算开销=%s%%",
        reason and (" reason=" .. tostring(reason)) or "",
        FormatNumber(durationSec),
        sampleCount,
        slowCount,
        FormatSignedKB(luaDelta),
        FormatNumber(recentDelta),
        FormatNumber(self:GetSelfOverheadEstimate())
    ))

    enabled = false
    GetConfig().enabled = false
    if sampleFrame then
        sampleFrame:SetScript("OnUpdate", nil)
    end
    SetEventsRegistered(false)
end

function T.BuildPerfLogCSV()
    return PerfLog:BuildCSV()
end

function T.GetPerfLogCount()
    return PerfLog:GetCount()
end
