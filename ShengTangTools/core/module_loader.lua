local T, C = unpack(select(2, ...))

local ModuleLoader = T.ModuleLoader or {
    modules = {},
    order = {},
    pendingCombat = {},
    strictReloadGated = true,
}
T.ModuleLoader = ModuleLoader

local function SplitPath(path)
    local parts = {}
    if type(path) ~= "string" or path == "" then
        return parts
    end
    for segment in path:gmatch("[^%.]+") do
        parts[#parts + 1] = segment
    end
    return parts
end

local function ReadPath(root, path)
    local current = root
    for _, key in ipairs(SplitPath(path)) do
        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
    end
    return current
end

local function WritePath(root, path, value)
    local parts = SplitPath(path)
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

local function SafeCall(module, methodName, ...)
    local method = module and module[methodName]
    if type(method) ~= "function" then
        return true
    end
    local ok, err = pcall(method, module, ...)
    if not ok then
        module._broken = tostring(err or "unknown")
        if T.debug then
            T.debug(string.format(
                "[ModuleLoader] ModuleError module=%s method=%s error=%s",
                tostring(module.name),
                tostring(methodName),
                tostring(err)
            ))
        end
    end
    return ok, err
end

local function ShowReloadPrompt(module, action)
    if T.msg then
        local moduleName = tostring(module and module.name or "?")
        if action == "enable" then
            T.msg(string.format("模块 %s 已写入启用配置；/reload 后加载完整功能。", moduleName))
        elseif action == "disable" then
            T.msg(string.format("模块 %s 已写入禁用配置；当前会话已软停用，/reload 后彻底卸载。", moduleName))
        else
            T.msg(string.format("模块 %s 状态已变更；请 /reload 完成加载状态切换。", moduleName))
        end
    end
end

local ModuleMethods = {}

function ModuleMethods:RegisterEvent(eventName, handlerName)
    if T.EventBus then
        return T.EventBus:Register(self, eventName, handlerName)
    end
    return false
end

function ModuleMethods:UnregisterEvent(eventName)
    if T.EventBus then
        T.EventBus:Unregister(self, eventName)
    end
end

function ModuleMethods:UnregisterAllEvents()
    if T.EventBus then
        T.EventBus:UnregisterAll(self)
    end
end

function ModuleMethods:RegisterMessage(messageName, handlerName)
    if T.MessageBus then
        return T.MessageBus:Register(self, messageName, handlerName)
    end
    return false
end

function ModuleMethods:UnregisterMessage(messageName)
    if T.MessageBus then
        T.MessageBus:Unregister(self, messageName)
    end
end

function ModuleMethods:SendMessage(messageName, ...)
    if T.MessageBus then
        T.MessageBus:SendMessage(messageName, ...)
    end
end

function ModuleMethods:RegisterHook(target, fnName, handlerName)
    if T.HookManager then
        return T.HookManager:Register(self, target, fnName, handlerName)
    end
    return false
end

function ModuleMethods:IsUserEnabled()
    return ModuleLoader:IsDbEnabled(self)
end

function ModuleLoader:NewModule(desc)
    if type(desc) ~= "table" or type(desc.name) ~= "string" or desc.name == "" then
        error("ModuleLoader:NewModule requires desc.name", 2)
    end
    if type(desc.dbKey) ~= "string" or desc.dbKey == "" then
        error("ModuleLoader:NewModule requires desc.dbKey", 2)
    end
    if desc.defaultEnabled == true then
        error("ModuleLoader:NewModule requires defaultEnabled=false", 2)
    end
    local existing = self.modules[desc.name]
    if existing and existing._isColdShell == true then
        self.modules[desc.name] = nil
        for index, name in ipairs(self.order or {}) do
            if name == desc.name then
                table.remove(self.order, index)
                break
            end
        end
    elseif existing then
        if existing.dbKey == desc.dbKey then
            if T.debug then
                T.debug(string.format(
                    "[ModuleLoader] DuplicateSameModuleIgnored module=%s dbKey=%s",
                    tostring(desc.name),
                    tostring(desc.dbKey)
                ))
            end
            return existing
        end
        error("ModuleLoader duplicate module: " .. desc.name, 2)
    end

    local module = {}
    for k, v in pairs(desc) do
        module[k] = v
    end
    for k, v in pairs(ModuleMethods) do
        module[k] = v
    end
    module.state = "Registered"
    module.enabled = false
    module.desired = false
    module.pendingReload = false
    module.refCount = 0
    module._perfStats = {
        enabledTimes = 0,
        disabledTimes = 0,
        totalEnableMs = 0,
        totalDisableMs = 0,
        lastDeltaKB = nil,
    }
    setmetatable(module, {
        __newindex = function(tbl, key, value)
            rawset(tbl, key, value)
            if key == "OnRegister" and type(value) == "function" and not rawget(tbl, "_onRegistered") then
                tbl._onRegistered = true
                SafeCall(tbl, "OnRegister")
            end
        end,
    })

    self.modules[module.name] = module
    self.order[#self.order + 1] = module.name
    if type(module.OnRegister) == "function" and not module._onRegistered then
        module._onRegistered = true
        SafeCall(module, "OnRegister")
    end
    return module
end

function ModuleLoader:Get(name)
    return self.modules and self.modules[name] or nil
end

function ModuleLoader:GetByDbKey(dbKey)
    if type(dbKey) ~= "string" or dbKey == "" then
        return nil
    end
    for _, module in ipairs(self:List()) do
        if module.dbKey == dbKey then
            return module
        end
    end
    return nil
end

function ModuleLoader:List()
    local list = {}
    for _, name in ipairs(self.order or {}) do
        list[#list + 1] = self.modules[name]
    end
    return list
end

function ModuleLoader:IsEnabled(name)
    local module = self:Get(name)
    return module and module.enabled == true or false
end

function ModuleLoader:IsDbEnabled(module)
    if type(module) == "string" then
        module = self:Get(module)
    end
    if not module then
        return false
    end
    local value = ReadPath(C and C.DB, module.dbKey)
    if value == nil then
        return module.defaultEnabled == true
    end
    return value == true
end

function ModuleLoader:IsDesired(module)
    return self:IsDbEnabled(module)
end

function ModuleLoader:SetDbEnabled(module, enabled)
    if type(module) == "string" then
        module = self:Get(module)
    end
    if not module or type(module.dbKey) ~= "string" or module.dbKey == "" then
        return false
    end
    WritePath(C.DB, module.dbKey, enabled == true)
    if type(STT_DB) == "table" then
        WritePath(STT_DB, module.dbKey, enabled == true)
    end
    return true
end

function ModuleLoader:_ShouldGateRuntimeChange(reason, internal)
    if self.strictReloadGated == false or internal == true or self._reconciling == true then
        return false
    end
    return reason ~= "devload" and reason ~= "option_hotload"
end

function ModuleLoader:SetDesired(name, enabled, reason)
    local module = self:Get(name)
    if not module then
        return false, "unknown_module"
    end
    self:SetDbEnabled(module, enabled == true)
    if enabled then
        if T.LoadColdFilesForDesired then
            T.LoadColdFilesForDesired()
        end
        module = self:Get(name)
        if not module then
            return false, "unknown_module"
        end
        if reason == "option" and module._isColdShell ~= true then
            return self:Enable(name, "option_hotload")
        end
        return self:Enable(name, reason or "desired")
    end
    return self:Disable(name, reason or "desired")
end

function ModuleLoader:_EnsureCombatFrame()
    if self.combatFrame then
        return
    end
    self.combatFrame = CreateFrame("Frame")
    self.combatFrame:SetScript("OnEvent", function()
        self.combatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self:_FlushCombatQueue()
    end)
end

function ModuleLoader:_QueueCombat(name, enabled, reason)
    self.pendingCombat[name] = { enabled = enabled == true, reason = reason }
    self:_EnsureCombatFrame()
    self.combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if T.msg then
        T.msg(string.format("战斗中切换 %s 已排队，脱战后自动应用。", tostring(name)))
    end
end

function ModuleLoader:_FlushCombatQueue()
    local pending = self.pendingCombat
    self.pendingCombat = {}
    for name, op in pairs(pending or {}) do
        if op.enabled then
            self:Enable(name, op.reason or "combat_queue")
        else
            self:Disable(name, op.reason or "combat_queue")
        end
    end
end

function ModuleLoader:_DoEnable(module, reason)
    if module.enabled then
        return true
    end
    if module._broken then
        return false, module._broken
    end

    module.state = "Enabling"
    local before = T.PerfProbe and T.PerfProbe:Before()
    if not module.firstLoaded then
        local ok, err = SafeCall(module, "OnFirstLoad", reason)
        if not ok then
            module.state = "Error"
            module.desired = false
            module.pendingReload = true
            self:SetDbEnabled(module, false)
            ShowReloadPrompt(module, "disable")
            return false, err
        end
        module.firstLoaded = true
    end

    local ok, err = SafeCall(module, "OnEnable", reason)
    if not ok then
        module.state = "Error"
        module.desired = false
        module.pendingReload = true
        self:SetDbEnabled(module, false)
        ShowReloadPrompt(module, "disable")
        return false, err
    end
    module.enabled = true
    module.desired = true
    module.pendingReload = false
    module.state = "Enabled"
    module._perfStats.enabledTimes = (module._perfStats.enabledTimes or 0) + 1
    if T.PerfProbe then
        T.PerfProbe:After(module, "enable", before)
    end
    return true
end

function ModuleLoader:_EnableDependency(name, ownerName, reason)
    local module = self:Get(name)
    if not module then
        return false, "missing_dependency:" .. tostring(name)
    end
    module.refCount = (module.refCount or 0) + 1
    local ok, err = self:Enable(name, reason or ("dependency:" .. tostring(ownerName)), true)
    if not ok then
        module.refCount = math.max(0, (module.refCount or 1) - 1)
    end
    return ok, err
end

function ModuleLoader:Enable(name, reason, internal)
    local module = self:Get(name)
    if not module then
        return false, "unknown_module"
    end
    if module.combatUnsafe == true and InCombatLockdown and InCombatLockdown() and not internal then
        self:_QueueCombat(name, true, reason)
        return true, "queued"
    end
    module.desired = self:IsDbEnabled(module)
    if self:_ShouldGateRuntimeChange(reason, internal) and not module.enabled then
        module.pendingReload = module.desired == true
        if module.pendingReload then
            module.state = "PendingLoad"
            ShowReloadPrompt(module, "enable")
            return true, "reload_required"
        end
        return true, "disabled"
    end
    if type(module.IsRuntimeLoaded) == "function" and not module:IsRuntimeLoaded() then
        module.pendingReload = module.desired == true
        if module.pendingReload then
            module.state = "PendingLoad"
            ShowReloadPrompt(module, "enable")
            return true, "reload_required"
        end
        return true, "disabled"
    end

    if not module.enabled then
        module._enabledDeps = {}
        for _, depName in ipairs(module.dependencies or {}) do
            local ok, err = self:_EnableDependency(depName, module.name, reason)
            if not ok then
                for _, enabledDepName in ipairs(module._enabledDeps) do
                    self:Disable(enabledDepName, "dependency_rollback:" .. tostring(module.name), true)
                end
                module._enabledDeps = {}
                return false, err
            end
            module._enabledDeps[#module._enabledDeps + 1] = depName
        end
    end
    return self:_DoEnable(module, reason)
end

function ModuleLoader:_DoDisable(module, reason)
    if not module.enabled then
        return true
    end

    module.state = "Disabling"
    local before = T.PerfProbe and T.PerfProbe:Before()
    local errors = {}
    local okSoft, errSoft = SafeCall(module, "OnSoftDisable", reason)
    if not okSoft then
        errors[#errors + 1] = tostring(errSoft or "OnSoftDisable failed")
    end

    local okDisable, errDisable = SafeCall(module, "OnDisable", reason)
    if not okDisable then
        errors[#errors + 1] = tostring(errDisable or "OnDisable failed")
    end

    module:UnregisterAllEvents()
    if T.MessageBus then
        T.MessageBus:UnregisterAll(module)
    end
    if T.HookManager then
        T.HookManager:UnregisterAll(module)
    end

    local okRelease, errRelease = SafeCall(module, "OnRelease", reason)
    if not okRelease then
        errors[#errors + 1] = tostring(errRelease or "OnRelease failed")
    end
    if T.Assets and T.Assets.ReleaseOwner then
        T.Assets:ReleaseOwner(module.name)
    end

    module.enabled = false
    module.desired = false
    module.pendingReload = false
    module.state = #errors > 0 and "Error" or "Disabled"
    module._perfStats.disabledTimes = (module._perfStats.disabledTimes or 0) + 1
    if T.PerfProbe then
        T.PerfProbe:After(module, "disable", before)
    end
    if #errors > 0 then
        return false, table.concat(errors, "; ")
    end
    return true
end

function ModuleLoader:Disable(name, reason, internal)
    local module = self:Get(name)
    if not module then
        return false, "unknown_module"
    end
    if module.combatUnsafe == true and InCombatLockdown and InCombatLockdown() and not internal then
        self:_QueueCombat(name, false, reason)
        return true, "queued"
    end
    module.desired = self:IsDbEnabled(module)

    if internal and (module.refCount or 0) > 0 then
        module.refCount = module.refCount - 1
    end
    if self:IsDbEnabled(module) or (module.refCount or 0) > 0 then
        return true, "protected"
    end

    local deps = module._enabledDeps or {}
    local ok, err = self:_DoDisable(module, reason)
    if not ok then
        if self:_ShouldGateRuntimeChange(reason, internal) and module.firstLoaded == true then
            module.pendingReload = true
            ShowReloadPrompt(module, "disable")
        end
        return false, err
    end
    if self:_ShouldGateRuntimeChange(reason, internal) and module.firstLoaded == true then
        module.pendingReload = true
        module.state = "PendingUnload"
        ShowReloadPrompt(module, "disable")
    end
    module._enabledDeps = {}
    for _, depName in ipairs(deps) do
        self:Disable(depName, "dependency_release:" .. tostring(module.name), true)
    end
    return true
end

function ModuleLoader:Reconcile(reason)
    local started = debugprofilestop and debugprofilestop() or 0
    self._reconciling = true
    for _, module in ipairs(self:List()) do
        module.desired = self:IsDbEnabled(module)
        local ok, err
        if module.desired then
            ok, err = self:Enable(module.name, reason or "reconcile")
        else
            ok, err = self:Disable(module.name, reason or "reconcile")
        end
        if not ok and T.debug then
            T.debug(string.format(
                "[ModuleLoader] ReconcileFailed module=%s error=%s",
                tostring(module.name),
                tostring(err)
            ))
        end
        if ok then
            module.pendingReload = false
        end
    end
    self._reconciling = false
    local elapsed = (debugprofilestop and debugprofilestop() or started) - started
    self.lastReconcileMs = elapsed
end
