local T = unpack(select(2, ...))

local HookManager = T.HookManager or {
    hooks = {},
    ownerHooks = {},
}
T.HookManager = HookManager

local function Debug(fmt, ...)
    if T.debug then
        T.debug(string.format("[HookManager] " .. fmt, ...))
    end
end

local function ResolveTarget(target)
    if type(target) == "string" then
        return _G[target], target
    end
    return target, tostring(target)
end

local function EnsureOwnerList(self, owner)
    local list = self.ownerHooks[owner]
    if not list then
        list = {}
        self.ownerHooks[owner] = list
    end
    return list
end

function HookManager:Register(owner, target, fnName, handlerName)
    if type(owner) ~= "table" or type(fnName) ~= "string" or type(handlerName) ~= "string" then
        return false
    end
    local resolvedTarget, targetLabel = ResolveTarget(target)
    if type(resolvedTarget) ~= "table" and type(resolvedTarget) ~= "userdata" then
        return false
    end

    local targetHooks = self.hooks[resolvedTarget]
    if not targetHooks then
        targetHooks = {}
        self.hooks[resolvedTarget] = targetHooks
    end
    local bucket = targetHooks[fnName]
    if not bucket then
        bucket = { handlers = {} }
        targetHooks[fnName] = bucket
        hooksecurefunc(resolvedTarget, fnName, function(...)
            for hookOwner, hookHandlerName in pairs(bucket.handlers) do
                local handler = hookOwner and hookOwner[hookHandlerName]
                if type(handler) == "function" then
                    local ok, err = pcall(handler, hookOwner, ...)
                    if not ok then
                        Debug("HandlerError target=%s fn=%s owner=%s error=%s", targetLabel, fnName, tostring(hookOwner.name or hookOwner), tostring(err))
                    end
                end
            end
        end)
    end

    bucket.handlers[owner] = handlerName
    local ownerList = EnsureOwnerList(self, owner)
    ownerList[#ownerList + 1] = { target = resolvedTarget, fnName = fnName }
    return true
end

function HookManager:Unregister(owner, target, fnName)
    local resolvedTarget = ResolveTarget(target)
    local bucket = self.hooks[resolvedTarget] and self.hooks[resolvedTarget][fnName]
    if bucket then
        bucket.handlers[owner] = nil
    end
end

function HookManager:UnregisterAll(owner)
    local list = self.ownerHooks[owner]
    if not list then
        return
    end
    for _, entry in ipairs(list) do
        local bucket = self.hooks[entry.target] and self.hooks[entry.target][entry.fnName]
        if bucket then
            bucket.handlers[owner] = nil
        end
    end
    self.ownerHooks[owner] = nil
end
