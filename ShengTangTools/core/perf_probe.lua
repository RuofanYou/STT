local T, C = unpack(select(2, ...))

local PerfProbe = T.PerfProbe or {}
T.PerfProbe = PerfProbe
local ModuleStatus
local SHELL_MEMORY_TARGET_KB = 8192
local GC_CYCLE_TARGET_KB = 5120

local function Now()
    return debugprofilestop and debugprofilestop() or 0
end

local function RefreshMemory()
    if UpdateAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
    end
end

local function GetSTTMemoryKB()
    RefreshMemory()
    if C_AddOns and C_AddOns.GetAddOnMemoryUsage then
        local ok, value = pcall(C_AddOns.GetAddOnMemoryUsage, T.addon_name or "ShengTangTools")
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    if GetAddOnMemoryUsage then
        local ok, value = pcall(GetAddOnMemoryUsage, T.addon_name or "ShengTangTools")
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return nil
end

local function GetLuaMemoryKB()
    local ok, value = pcall(collectgarbage, "count")
    if ok and tonumber(value) then
        return tonumber(value)
    end
    return nil
end

local function FormatNumber(value, suffix)
    if value == nil then
        return "-"
    end
    if math.abs(value) >= 10 then
        return string.format("%.0f%s", value, suffix or "")
    end
    return string.format("%.1f%s", value, suffix or "")
end

local function FormatState(value)
    return value and "YES" or "NO"
end

local function Print(line)
    if T.RecordDebugLog then
        T.RecordDebugLog(line, "MEM")
    end
    if T.msg then
        T.msg(line)
    end
end

local function EnsurePerfDB()
    STT_DB.perf = STT_DB.perf or {}
    return STT_DB.perf
end

local function ReadBoolPath(root, path)
    local current = root
    for key in tostring(path or ""):gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return false
        end
        current = current[key]
    end
    return current == true
end

local function SetBoolPath(root, path, value)
    if type(root) ~= "table" then
        return
    end
    local current = root
    local parts = {}
    for key in tostring(path or ""):gmatch("[^%.]+") do
        parts[#parts + 1] = key
    end
    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    if #parts > 0 then
        current[parts[#parts]] = value == true
    end
end

local function SetColdFlag(path, value)
    SetBoolPath(C and C.DB, path, value)
    SetBoolPath(STT_DB, path, value)
end

local function SnapshotModuleDesired()
    local snapshot = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or tostring(time and time() or ""),
        debugMode = C and C.DB and C.DB.debugMode == true or false,
        suppressForbiddenPopup = C and C.DB and C.DB.suppressForbiddenPopup == true or false,
        optionPushAccept = ReadBoolPath(C and C.DB, "raidLead.optionPushAccept"),
        modules = {},
    }
    if T.ModuleLoader then
        for _, module in ipairs(T.ModuleLoader:List()) do
            snapshot.modules[module.name] = T.ModuleLoader:IsDbEnabled(module) == true
        end
    end
    EnsurePerfDB().moduleDesiredSnapshot = snapshot
    return snapshot
end

local function SnapshotModuleDesiredNoPersist()
    local snapshot = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or tostring(time and time() or ""),
        debugMode = C and C.DB and C.DB.debugMode == true or false,
        suppressForbiddenPopup = C and C.DB and C.DB.suppressForbiddenPopup == true or false,
        optionPushAccept = ReadBoolPath(C and C.DB, "raidLead.optionPushAccept"),
        modules = {},
    }
    if T.ModuleLoader then
        for _, module in ipairs(T.ModuleLoader:List()) do
            snapshot.modules[module.name] = T.ModuleLoader:IsDbEnabled(module) == true
        end
    end
    return snapshot
end

local function SetRootFlag(key, value)
    if C and C.DB then
        C.DB[key] = value == true
    end
    if type(STT_DB) == "table" then
        STT_DB[key] = value == true
    end
end

local function SetAllModuleDesired(enabled)
    if not T.ModuleLoader then
        return 0
    end
    local count = 0
    for _, module in ipairs(T.ModuleLoader:List()) do
        if T.ModuleLoader:SetDbEnabled(module, enabled == true) then
            module.desired = enabled == true
            module.pendingReload = module.firstLoaded == true and module.enabled ~= enabled
            count = count + 1
        end
    end
    return count
end

local function RestoreModuleDesired(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.modules) ~= "table" or not T.ModuleLoader then
        return false
    end
    for _, module in ipairs(T.ModuleLoader:List()) do
        local enabled = snapshot.modules[module.name] == true
        T.ModuleLoader:SetDbEnabled(module, enabled)
        module.desired = enabled
        module.pendingReload = module.firstLoaded == true and module.enabled ~= enabled
    end
    SetRootFlag("debugMode", snapshot.debugMode == true)
    SetRootFlag("suppressForbiddenPopup", snapshot.suppressForbiddenPopup == true)
    SetColdFlag("raidLead.optionPushAccept", snapshot.optionPushAccept == true)
    return true
end

local function PersistMemorySnapshot(snap, counts, assetStats)
    if type(STT_DB) ~= "table" then
        return
    end
    local modules = {}
    if T.ModuleLoader then
        for _, module in ipairs(T.ModuleLoader:List()) do
            modules[#modules + 1] = {
                name = module.name,
                desired = T.ModuleLoader:IsDbEnabled(module) == true,
                active = module.enabled == true,
                loaded = module.firstLoaded == true,
                pending = module.pendingReload == true,
                status = ModuleStatus(module),
                lastDeltaKB = module._perfStats and module._perfStats.lastDeltaKB or nil,
                loadDeltaKB = module._perfStats and module._perfStats.loadDeltaKB or nil,
                softDisableDeltaKB = module._perfStats and module._perfStats.softDisableDeltaKB or nil,
                events = T.EventBus and T.EventBus:GetSubscriberCount(module) or 0,
            }
        end
    end
    local loadedKeys = {}
    if assetStats and type(assetStats.loadedKeys) == "table" then
        for index, key in ipairs(assetStats.loadedKeys) do
            loadedKeys[index] = key
        end
    end
    EnsurePerfDB().lastMemorySnapshot = {
        capturedAt = snap.capturedAt,
        version = snap.version,
        sttKB = snap.sttKB,
        luaKB = snap.luaKB,
        gcReclaimedKB = snap.gcReclaimedKB,
        sttWithinTarget = snap.sttKB and snap.sttKB <= SHELL_MEMORY_TARGET_KB or nil,
        gcWithinTarget = snap.gcReclaimedKB and snap.gcReclaimedKB <= GC_CYCLE_TARGET_KB or nil,
        reconcileMs = snap.reconcileMs,
        counts = {
            total = counts.total,
            loaded = counts.loaded,
            cold = counts.cold,
            pending = counts.pending,
        },
        assets = {
            total = assetStats and assetStats.total or 0,
            loaded = assetStats and assetStats.loaded or 0,
            cold = assetStats and assetStats.cold or 0,
            loadedKeys = loadedKeys,
        },
        modules = modules,
    }
end

local function BuildModuleAuditSummary(audit)
    if type(audit) ~= "table" then
        return nil
    end
    local results = type(audit.results) == "table" and audit.results or nil
    if not results and audit.moduleName then
        results = {
            {
                moduleName = audit.moduleName,
                baselineKB = audit.baselineKB,
                loadedKB = audit.loadedKB,
                loadDeltaKB = audit.loadDeltaKB,
                returnedKB = audit.returnedKB,
                returnDeltaKB = audit.returnDeltaKB,
                baselineGCKB = audit.baselineGCKB,
                loadedGCKB = audit.loadedGCKB,
                returnedGCKB = audit.returnedGCKB,
                maxGCKB = audit.maxGCKB,
                pass = audit.pass == true,
            },
        }
    end

    local summary = {
        mode = audit.mode or "single",
        startedAt = audit.startedAt,
        finishedAt = date and date("%Y-%m-%d %H:%M:%S") or tostring(time and time() or ""),
        total = 0,
        passed = 0,
        warned = 0,
        maxReturnDeltaKB = nil,
        maxGCKB = nil,
        results = {},
    }
    for _, result in ipairs(results or {}) do
        summary.total = summary.total + 1
        if result.pass == true then
            summary.passed = summary.passed + 1
        else
            summary.warned = summary.warned + 1
        end
        local returnDelta = tonumber(result.returnDeltaKB)
        if returnDelta and (not summary.maxReturnDeltaKB or returnDelta > summary.maxReturnDeltaKB) then
            summary.maxReturnDeltaKB = returnDelta
        end
        local maxGC = tonumber(result.maxGCKB)
        if maxGC and (not summary.maxGCKB or maxGC > summary.maxGCKB) then
            summary.maxGCKB = maxGC
        end
        summary.results[#summary.results + 1] = {
            moduleName = result.moduleName,
            baselineKB = result.baselineKB,
            loadedKB = result.loadedKB,
            loadDeltaKB = result.loadDeltaKB,
            returnedKB = result.returnedKB,
            returnDeltaKB = result.returnDeltaKB,
            baselineGCKB = result.baselineGCKB,
            loadedGCKB = result.loadedGCKB,
            returnedGCKB = result.returnedGCKB,
            maxGCKB = result.maxGCKB,
            pass = result.pass == true,
        }
    end
    return summary
end

local function PersistModuleAuditSummary(audit)
    local summary = BuildModuleAuditSummary(audit)
    if summary then
        EnsurePerfDB().lastModuleAudit = summary
    end
    return summary
end

function PerfProbe:Before()
    return {
        t = Now(),
        sttKB = GetSTTMemoryKB(),
    }
end

function PerfProbe:After(module, op, before)
    if not (module and before) then
        return
    end
    local afterKB = GetSTTMemoryKB()
    local elapsed = Now() - (before.t or Now())
    local delta = nil
    if afterKB and before.sttKB then
        delta = afterKB - before.sttKB
    end

    module._perfStats = module._perfStats or {}
    module._perfStats.lastDeltaKB = delta
    module._perfStats.lastOp = op
    if op == "enable" then
        module._perfStats.loadDeltaKB = delta
        module._perfStats.totalEnableMs = (module._perfStats.totalEnableMs or 0) + elapsed
    elseif op == "disable" then
        module._perfStats.softDisableDeltaKB = delta
        module._perfStats.totalDisableMs = (module._perfStats.totalDisableMs or 0) + elapsed
    end
end

function PerfProbe:Snapshot()
    pcall(collectgarbage, "collect")
    local beforeLuaKB = GetLuaMemoryKB()
    pcall(collectgarbage, "collect")
    local afterLuaKB = GetLuaMemoryKB()
    return {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or tostring(time and time() or ""),
        version = T.Version,
        luaKB = afterLuaKB,
        gcReclaimedKB = beforeLuaKB and afterLuaKB and math.max(0, beforeLuaKB - afterLuaKB) or nil,
        sttKB = GetSTTMemoryKB(),
        reconcileMs = T.ModuleLoader and T.ModuleLoader.lastReconcileMs or 0,
    }
end

function PerfProbe:GetModuleCounts()
    local counts = {
        total = 0,
        loaded = 0,
        cold = 0,
        pending = 0,
    }
    if not T.ModuleLoader then
        return counts
    end
    for _, module in ipairs(T.ModuleLoader:List()) do
        counts.total = counts.total + 1
        if module.firstLoaded == true then
            counts.loaded = counts.loaded + 1
        else
            counts.cold = counts.cold + 1
        end
        if module.pendingReload == true then
            counts.pending = counts.pending + 1
        end
    end
    return counts
end

function ModuleStatus(module)
    if module.pendingReload == true and module.desired == true then
        return "待加载"
    end
    if module.pendingReload == true and module.desired ~= true then
        return "待卸载"
    end
    if module.enabled == true then
        return "运行中"
    end
    if module.firstLoaded == true then
        return "已软停"
    end
    return "冷态"
end

function PerfProbe:PrintMemorySnapshot()
    local snap = self:Snapshot()
    local counts = self:GetModuleCounts()
    local assetStats = T.Assets and T.Assets:GetStats() or nil
    PersistMemorySnapshot(snap, counts, assetStats)
    Print("==== STT 内存快照 ====")
    Print("Addon: " .. tostring(T.addon_name or "ShengTangTools"))
    Print(string.format(
        "STT 自占: %s KB | Lua VM: %s KB | GC 回收: %s KB",
        FormatNumber(snap.sttKB),
        FormatNumber(snap.luaKB),
        FormatNumber(snap.gcReclaimedKB)
    ))
    Print(string.format(
        "验收线: 冷壳≤%dKB=%s | 单次GC≤%dKB=%s",
        SHELL_MEMORY_TARGET_KB,
        snap.sttKB and (snap.sttKB <= SHELL_MEMORY_TARGET_KB and "PASS" or "WARN") or "-",
        GC_CYCLE_TARGET_KB,
        snap.gcReclaimedKB and (snap.gcReclaimedKB <= GC_CYCLE_TARGET_KB and "PASS" or "WARN") or "-"
    ))
    Print("---- Shell ----")
    Print(string.format(
        "Core Shell: loaded | Modules: total=%d loaded=%d cold=%d pending=%d | Assets: total=%d loaded=%d cold=%d | Reconcile=%sms",
        counts.total,
        counts.loaded,
        counts.cold,
        counts.pending,
        assetStats and assetStats.total or 0,
        assetStats and assetStats.loaded or 0,
        assetStats and assetStats.cold or 0,
        FormatNumber(snap.reconcileMs)
    ))
    local guiState = T.GetGUIMemoryState and T.GetGUIMemoryState() or {}
    Print(string.format(
        "GUI Shell: root=%s settingsFrame=%s settingsBuilt=%s settingsTree=%s planFrame=%s visualBoardFrame=%s",
        FormatState(guiState.root),
        FormatState(guiState.settings),
        FormatState(guiState.settingsInitialized),
        FormatState(guiState.settingsRenderTree),
        FormatState(guiState.plan),
        FormatState(guiState.visualBoard)
    ))
    local sem = T.SemanticTimeline
    Print(string.format(
        "Plan Editor: coldFeature=%s workbenchInitialized=%s",
        FormatState(T.RuntimeColdFeatures and T.RuntimeColdFeatures["semanticTimeline.editorLoaded"] == true),
        FormatState(sem and sem.IsSemanticBossPlansInitialized and sem:IsSemanticBossPlansInitialized())
    ))
    if assetStats and #assetStats.loadedKeys > 0 then
        Print("Loaded assets: " .. table.concat(assetStats.loadedKeys, ", "))
    end
    Print("---- Modules ----")
    if T.ModuleLoader then
        for _, module in ipairs(T.ModuleLoader:List()) do
            local stats = module._perfStats or {}
            local eventCount = T.EventBus and T.EventBus:GetSubscriberCount(module) or 0
            Print(string.format(
                "[%s] desired=%s active=%s loaded=%s pending=%s status=%s loadDelta=%sKB softDisableDelta=%sKB events=%d",
                tostring(module.name),
                T.ModuleLoader:IsDbEnabled(module) and "ON" or "OFF",
                module.enabled and "YES" or "NO",
                module.firstLoaded and "YES" or "NO",
                module.pendingReload and "YES" or "NO",
                ModuleStatus(module),
                stats.loadDeltaKB and FormatNumber(stats.loadDeltaKB) or "-",
                stats.softDisableDeltaKB and FormatNumber(stats.softDisableDeltaKB) or "-",
                eventCount
            ))
        end
    end
    Print("提示：运行时启用/禁用只写配置并标记待重载；彻底加载/卸载以 /reload 后快照为准。")
end

function PerfProbe:PrintSnapshot(mode)
    local snap = self:Snapshot()
    Print("────────────────────────────────────────────────")
    Print(string.format(
        "STT 性能探针 | Lua: %s KB | STT: %s KB",
        FormatNumber(snap.luaKB),
        FormatNumber(snap.sttKB)
    ))
    Print("模块名               启用  最近δKB  累计ms  事件数  首加载  启用次数")

    if T.ModuleLoader then
        for _, module in ipairs(T.ModuleLoader:List()) do
            local stats = module._perfStats or {}
            local eventCount = T.EventBus and T.EventBus:GetSubscriberCount(module) or 0
            local totalMs = (stats.totalEnableMs or 0) + (stats.totalDisableMs or 0)
            Print(string.format(
                "%-20s %-4s %-8s %-7s %-7d %-7s %d",
                tostring(module.name),
                module.enabled and "是" or "否",
                stats.lastDeltaKB and FormatNumber(stats.lastDeltaKB, "") or "-",
                totalMs > 0 and FormatNumber(totalMs, "") or "-",
                eventCount,
                module.firstLoaded and "是" or "否",
                stats.enabledTimes or 0
            ))
        end
    end

    local baseline = STT_DB and STT_DB.perf and STT_DB.perf.baseline
    if mode == "diff" and type(baseline) == "table" and snap.sttKB and baseline.sttKB then
        Print(string.format("基线: %s | 当前差值: %s KB", tostring(baseline.capturedAt or "-"), FormatNumber(snap.sttKB - baseline.sttKB)))
    elseif type(baseline) == "table" then
        Print("基线: " .. tostring(baseline.capturedAt or "-"))
    end
    Print("提示：/st mod enable <模块名> 或 /st mod disable <模块名>")
    Print("────────────────────────────────────────────────")
end

function PerfProbe:SetBaseline()
    STT_DB.perf = STT_DB.perf or {}
    STT_DB.perf.baseline = self:Snapshot()
    Print("STT 性能基线已记录: " .. tostring(STT_DB.perf.baseline.capturedAt or "-"))
end

function PerfProbe:ResetBaseline()
    if STT_DB and STT_DB.perf then
        STT_DB.perf.baseline = nil
    end
    Print("STT 性能基线已清空")
end

local function ReloadForAudit()
    if T.PerfProbe and T.PerfProbe._startupAuditContinue == true then
        Print("模块验收已写入下一阶段；请执行 /reload 继续。")
        return false
    end
    if ReloadUI then
        ReloadUI()
        return true
    end
    Print("当前环境不能自动 /reload，请手动 /reload 继续验收。")
    return false
end

local function GetAuditModuleNames()
    local names = {}
    if not T.ModuleLoader then
        return names
    end
    for _, module in ipairs(T.ModuleLoader:List()) do
        if module and module.name then
            names[#names + 1] = module.name
        end
    end
    table.sort(names)
    return names
end

function PerfProbe:BeginModuleAudit(moduleName)
    if not T.ModuleLoader then
        Print("模块管理器未加载")
        return
    end
    local module = T.ModuleLoader:Get(moduleName)
    if not module then
        Print("未知模块: " .. tostring(moduleName))
        return
    end

    local perf = EnsurePerfDB()
    perf.moduleAudit = {
        moduleName = module.name,
        stage = "baseline",
        startedAt = date and date("%Y-%m-%d %H:%M:%S") or tostring(time and time() or ""),
        original = SnapshotModuleDesiredNoPersist(),
        snapshots = {},
    }
    SetAllModuleDesired(false)
    SetRootFlag("debugMode", false)
    SetRootFlag("suppressForbiddenPopup", false)
    Print("模块验收开始: " .. tostring(module.name) .. "；阶段 1/4 写入全冷 baseline，正在重载。")
    ReloadForAudit()
end

function PerfProbe:BeginAllModuleAudit()
    if not T.ModuleLoader then
        Print("模块管理器未加载")
        return
    end
    local names = GetAuditModuleNames()
    if #names == 0 then
        Print("没有可验收模块。")
        return
    end

    local perf = EnsurePerfDB()
    perf.moduleAudit = {
        mode = "all",
        moduleName = names[1],
        queue = names,
        index = 1,
        stage = "baseline",
        startedAt = date and date("%Y-%m-%d %H:%M:%S") or tostring(time and time() or ""),
        original = SnapshotModuleDesiredNoPersist(),
        snapshots = {},
        results = {},
    }
    SetAllModuleDesired(false)
    SetRootFlag("debugMode", false)
    SetRootFlag("suppressForbiddenPopup", false)
    Print(string.format(
        "全模块验收开始: 共 %d 个模块；阶段 1/%d 写入全冷 baseline，正在重载。",
        #names,
        (#names * 3) + 1
    ))
    ReloadForAudit()
end

function PerfProbe:CancelModuleAudit()
    local perf = EnsurePerfDB()
    perf.moduleAudit = nil
    Print("模块验收已取消。")
end

function PerfProbe:PrintModuleAuditStatus()
    local audit = STT_DB and STT_DB.perf and STT_DB.perf.moduleAudit
    if type(audit) ~= "table" then
        Print("当前没有正在进行的模块验收。")
        return
    end
    Print(string.format(
        "模块验收: mode=%s module=%s index=%s/%s stage=%s baseline=%sKB loaded=%sKB returned=%sKB pass=%s",
        tostring(audit.mode or "single"),
        tostring(audit.moduleName or "-"),
        tostring(audit.index or 1),
        tostring(audit.queue and #audit.queue or 1),
        tostring(audit.stage or "-"),
        FormatNumber(audit.baselineKB),
        FormatNumber(audit.loadedKB),
        FormatNumber(audit.returnedKB),
        tostring(audit.pass)
    ))
end

function PerfProbe:PrintModuleAuditReport()
    local summary = STT_DB and STT_DB.perf and STT_DB.perf.lastModuleAudit
    if type(summary) ~= "table" then
        Print("还没有模块验收报告；先执行 /st mod audit <模块名|all>。")
        return
    end
    Print(string.format(
        "最近模块验收报告: mode=%s PASS=%d/%d WARN=%d maxReturnDelta=%sKB maxGC=%sKB finished=%s",
        tostring(summary.mode or "-"),
        tonumber(summary.passed) or 0,
        tonumber(summary.total) or 0,
        tonumber(summary.warned) or 0,
        FormatNumber(summary.maxReturnDeltaKB),
        FormatNumber(summary.maxGCKB),
        tostring(summary.finishedAt or "-")
    ))
    for _, result in ipairs(summary.results or {}) do
        Print(string.format(
            "模块验收报告: %s baseline=%sKB loaded=%sKB loadDelta=%sKB returned=%sKB returnDelta=%sKB maxGC=%sKB result=%s",
            tostring(result.moduleName),
            FormatNumber(result.baselineKB),
            FormatNumber(result.loadedKB),
            FormatNumber(result.loadDeltaKB),
            FormatNumber(result.returnedKB),
            FormatNumber(result.returnDeltaKB),
            FormatNumber(result.maxGCKB),
            result.pass == true and "PASS" or "WARN"
        ))
    end
end

function PerfProbe:ContinueModuleAudit()
    local audit = STT_DB and STT_DB.perf and STT_DB.perf.moduleAudit
    if type(audit) ~= "table" then
        return
    end
    if audit.stage == "done" then
        EnsurePerfDB().moduleAudit = nil
        return
    end
    if not T.ModuleLoader then
        return
    end

    local module = T.ModuleLoader:Get(audit.moduleName)
    if not module then
        Print("模块验收中止：未知模块 " .. tostring(audit.moduleName))
        EnsurePerfDB().moduleAudit = nil
        return
    end

    local snap = self:Snapshot()
    audit.snapshots = audit.snapshots or {}
    audit.snapshots[#audit.snapshots + 1] = {
        stage = audit.stage,
        capturedAt = snap.capturedAt,
        sttKB = snap.sttKB,
        luaKB = snap.luaKB,
        gcReclaimedKB = snap.gcReclaimedKB,
    }

    if audit.stage == "baseline" then
        audit.baselineKB = snap.sttKB
        audit.baselineGCKB = snap.gcReclaimedKB
        audit.maxGCKB = snap.gcReclaimedKB
        SetAllModuleDesired(false)
        T.ModuleLoader:SetDbEnabled(module, true)
        audit.stage = "loaded"
        Print("模块验收阶段 2/4: 已记录全冷 baseline，启用 " .. tostring(module.name) .. " 并重载。")
        ReloadForAudit()
        return
    end

    if audit.stage == "loaded" then
        audit.loadedKB = snap.sttKB
        audit.loadedGCKB = snap.gcReclaimedKB
        if snap.gcReclaimedKB and (not audit.maxGCKB or snap.gcReclaimedKB > audit.maxGCKB) then
            audit.maxGCKB = snap.gcReclaimedKB
        end
        if snap.sttKB and audit.baselineKB then
            audit.loadDeltaKB = snap.sttKB - audit.baselineKB
        end
        SetAllModuleDesired(false)
        audit.stage = "returned"
        Print("模块验收阶段 3/4: 已记录单模块 loaded，禁用并重载检查回 baseline。")
        ReloadForAudit()
        return
    end

    if audit.stage == "returned" then
        audit.returnedKB = snap.sttKB
        audit.returnedGCKB = snap.gcReclaimedKB
        if snap.gcReclaimedKB and (not audit.maxGCKB or snap.gcReclaimedKB > audit.maxGCKB) then
            audit.maxGCKB = snap.gcReclaimedKB
        end
        if snap.sttKB and audit.baselineKB then
            audit.returnDeltaKB = snap.sttKB - audit.baselineKB
            audit.returnPct = audit.baselineKB > 0 and (audit.returnDeltaKB / audit.baselineKB) or 0
            audit.pass = snap.sttKB <= audit.baselineKB * 1.10
                and (not audit.maxGCKB or audit.maxGCKB <= GC_CYCLE_TARGET_KB)
        end

        if audit.mode == "all" then
            audit.results = audit.results or {}
            audit.results[#audit.results + 1] = {
                moduleName = audit.moduleName,
                baselineKB = audit.baselineKB,
                loadedKB = audit.loadedKB,
                loadDeltaKB = audit.loadDeltaKB,
                returnedKB = audit.returnedKB,
                returnDeltaKB = audit.returnDeltaKB,
                baselineGCKB = audit.baselineGCKB,
                loadedGCKB = audit.loadedGCKB,
                returnedGCKB = audit.returnedGCKB,
                maxGCKB = audit.maxGCKB,
                pass = audit.pass == true,
            }
            local nextIndex = (audit.index or 1) + 1
            if audit.queue and audit.queue[nextIndex] then
                audit.index = nextIndex
                audit.moduleName = audit.queue[nextIndex]
                audit.stage = "baseline"
                audit.baselineKB = nil
                audit.loadedKB = nil
                audit.loadDeltaKB = nil
                audit.returnedKB = nil
                audit.returnDeltaKB = nil
                audit.returnPct = nil
                audit.baselineGCKB = nil
                audit.loadedGCKB = nil
                audit.returnedGCKB = nil
                audit.maxGCKB = nil
                audit.pass = nil
                SetAllModuleDesired(false)
                Print(string.format(
                    "全模块验收继续: %d/%d %s，写入全冷 baseline 并重载。",
                    nextIndex,
                    #audit.queue,
                    tostring(audit.moduleName)
                ))
                ReloadForAudit()
                return
            end

            RestoreModuleDesired(audit.original)
            audit.stage = "restore"
            Print("全模块验收模块队列完成；恢复原配置并重载。")
            ReloadForAudit()
            return
        end

        RestoreModuleDesired(audit.original)
        audit.stage = "restore"
        Print(string.format(
            "模块验收阶段 4/4: 回退差值=%sKB，结果=%s；恢复原配置并重载。",
            FormatNumber(audit.returnDeltaKB),
            audit.pass == true and "PASS" or "WARN"
        ))
        ReloadForAudit()
        return
    end

    if audit.stage == "restore" then
        audit.stage = "done"
        if audit.mode == "all" then
            local summary = PersistModuleAuditSummary(audit)
            EnsurePerfDB().moduleAudit = nil
            local passed = 0
            local total = 0
            for _, result in ipairs(audit.results or {}) do
                total = total + 1
                if result.pass == true then
                    passed = passed + 1
                end
                Print(string.format(
                    "模块验收结果: %s baseline=%sKB loaded=%sKB loadDelta=%sKB returned=%sKB returnDelta=%sKB maxGC=%sKB result=%s",
                    tostring(result.moduleName),
                    FormatNumber(result.baselineKB),
                    FormatNumber(result.loadedKB),
                    FormatNumber(result.loadDeltaKB),
                    FormatNumber(result.returnedKB),
                    FormatNumber(result.returnDeltaKB),
                    FormatNumber(result.maxGCKB),
                    result.pass == true and "PASS" or "WARN"
                ))
            end
            Print(string.format(
                "全模块验收完成: PASS=%d/%d maxReturnDelta=%sKB maxGC=%sKB",
                passed,
                total,
                FormatNumber(summary and summary.maxReturnDeltaKB),
                FormatNumber(summary and summary.maxGCKB)
            ))
            return
        end
        PersistModuleAuditSummary(audit)
        EnsurePerfDB().moduleAudit = nil
        Print(string.format(
            "模块验收完成: %s baseline=%sKB loaded=%sKB loadDelta=%sKB returned=%sKB returnDelta=%sKB maxGC=%sKB result=%s",
            tostring(audit.moduleName),
            FormatNumber(audit.baselineKB),
            FormatNumber(audit.loadedKB),
            FormatNumber(audit.loadDeltaKB),
            FormatNumber(audit.returnedKB),
            FormatNumber(audit.returnDeltaKB),
            FormatNumber(audit.maxGCKB),
            audit.pass == true and "PASS" or "WARN"
        ))
    end
end

function PerfProbe:PrepareAllColdBaseline(saveSnapshot)
    if not T.ModuleLoader then
        Print("模块管理器未加载")
        return
    end
    local snapshot = saveSnapshot and SnapshotModuleDesired() or nil
    local count = SetAllModuleDesired(false)
    SetRootFlag("debugMode", false)
    SetRootFlag("suppressForbiddenPopup", false)
    SetColdFlag("raidLead.optionPushAccept", false)
    if snapshot then
        Print(string.format("已保存当前模块配置（%s），并写入全模块禁用 baseline；请 /reload 后执行 /st mem。", tostring(snapshot.capturedAt or "-")))
    else
        Print("已写入全模块禁用配置；请 /reload 后执行 /st mem。")
    end
    Print(string.format("已禁用模块数: %d；调试模式与弹窗过滤已临时关闭。", count))
end

function PerfProbe:PrepareSoloModule(moduleName)
    local module = T.ModuleLoader and T.ModuleLoader:Get(moduleName)
    if not module then
        Print("未知模块: " .. tostring(moduleName))
        return
    end
    SetAllModuleDesired(false)
    T.ModuleLoader:SetDbEnabled(module, true)
    module.desired = true
    module.pendingReload = module.enabled ~= true
    Print("已写入单模块启用配置: " .. tostring(moduleName) .. "；请 /reload 后执行 /st mem。")
end

function PerfProbe:RestoreModuleSnapshot()
    local snapshot = STT_DB and STT_DB.perf and STT_DB.perf.moduleDesiredSnapshot
    if not RestoreModuleDesired(snapshot) then
        Print("没有可恢复的模块配置快照")
        return
    end
    Print(string.format("已恢复模块配置快照（%s）；请 /reload 后生效。", tostring(snapshot.capturedAt or "-")))
end

function PerfProbe:HandlePerfCommand(args)
    args = tostring(args or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if args == "baseline" then
        self:SetBaseline()
    elseif args == "diff" then
        self:PrintSnapshot("diff")
    elseif args == "reset" then
        self:ResetBaseline()
    else
        self:PrintSnapshot()
    end
end

function PerfProbe:HandleModCommand(args)
    args = tostring(args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args == "audit status" then
        self:PrintModuleAuditStatus()
        return
    end
    if args == "audit report" then
        self:PrintModuleAuditReport()
        return
    end
    if args == "audit cancel" then
        self:CancelModuleAudit()
        return
    end
    local auditName = args:match("^audit%s+(.+)$")
    if auditName then
        auditName = auditName:gsub("^%s+", ""):gsub("%s+$", "")
        if auditName:lower() == "all" then
            self:BeginAllModuleAudit()
        else
            self:BeginModuleAudit(auditName)
        end
        return
    end
    if args == "baseline" then
        self:PrepareAllColdBaseline(true)
        return
    end
    if args == "alloff" or args == "all-off" then
        self:PrepareAllColdBaseline(false)
        return
    end
    if args == "restore" then
        self:RestoreModuleSnapshot()
        return
    end
    local soloName = args:match("^solo%s+(.+)$")
    if soloName then
        soloName = soloName:gsub("^%s+", ""):gsub("%s+$", "")
        self:PrepareSoloModule(soloName)
        return
    end

    local action, name = args:match("^(%S+)%s+(.+)$")
    if not action then
        Print("STT 模块状态:")
        if T.ModuleLoader then
            for _, module in ipairs(T.ModuleLoader:List()) do
                Print(string.format(
                    "  %s: desired=%s active=%s loaded=%s pending=%s status=%s",
                    module.name,
                    T.ModuleLoader:IsDbEnabled(module) and "ON" or "OFF",
                    module.enabled and "YES" or "NO",
                    module.firstLoaded and "YES" or "NO",
                    module.pendingReload and "YES" or "NO",
                    ModuleStatus(module)
                ))
            end
        end
        return
    end

    action = action:lower()
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not (T.ModuleLoader and T.ModuleLoader:Get(name)) then
        Print("未知模块: " .. tostring(name))
        return
    end

    if action == "enable" or action == "on" then
        local ok, err = T.ModuleLoader:SetDesired(name, true, "slash")
        Print(ok and ("模块启用配置已写入: " .. name .. "；请 /reload 后加载") or ("模块启用失败: " .. tostring(err)))
    elseif action == "disable" or action == "off" then
        local ok, err = T.ModuleLoader:SetDesired(name, false, "slash")
        Print(ok and ("模块禁用配置已写入: " .. name .. "；请 /reload 后彻底卸载") or ("模块禁用失败: " .. tostring(err)))
    elseif action == "devload" then
        T.ModuleLoader:SetDbEnabled(name, true)
        local ok, err = T.ModuleLoader:Enable(name, "devload")
        Print(ok and ("开发热加载完成: " .. name) or ("开发热加载失败: " .. tostring(err)))
    else
        Print("用法: /st mod enable <模块名>、/st mod disable <模块名>、/st mod baseline、/st mod alloff、/st mod solo <模块名>、/st mod audit <模块名|all>、/st mod audit report、/st mod restore")
    end
end

function PerfProbe:HandlePlogCommand(args)
    args = tostring(args or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if not T.PerfLog then
        Print("性能日志模块未加载")
        return
    end

    if args == "" then
        if not T.PerfLog:IsEnabled() then
            T.PerfLog:Start()
        end
        if T.ShowPerfLogWindow then
            T.ShowPerfLogWindow()
        else
            Print("性能日志窗口模块未加载")
        end
    elseif args == "on" then
        T.PerfLog:Start()
        Print("性能日志采样已开启；复现卡顿后执行 /st plog 复制日志")
    elseif args == "off" then
        T.PerfLog:Stop()
        Print("性能日志采样已关闭")
    elseif args == "clear" then
        T.PerfLog:Clear()
        Print("性能日志已清空")
    elseif args == "status" then
        Print(string.format(
            "性能日志: %s | cvar=%s | 条数=%d | 自身估算开销=%s%%",
            T.PerfLog:IsEnabled() and "开启" or "关闭",
            T.PerfLog:IsCVarReady() and "1" or "0",
            T.PerfLog:GetCount(),
            FormatNumber(T.PerfLog:GetSelfOverheadEstimate())
        ))
    else
        Print("用法: /st plog [on|off|clear|status]")
    end
end

if T.RegisterInitCallback then
    T.RegisterInitCallback(function()
        if not (T.PerfProbe and T.PerfProbe.ContinueModuleAudit) then
            return
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                T.PerfProbe._startupAuditContinue = true
                T.PerfProbe:ContinueModuleAudit()
                T.PerfProbe._startupAuditContinue = nil
            end)
        else
            T.PerfProbe._startupAuditContinue = true
            T.PerfProbe:ContinueModuleAudit()
            T.PerfProbe._startupAuditContinue = nil
        end
    end)
end
