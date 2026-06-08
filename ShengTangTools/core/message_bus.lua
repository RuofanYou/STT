local T = unpack(select(2, ...))

local MessageBus = T.MessageBus or {
    callbackHandles = {},
    fallbackListeners = {},
}
T.MessageBus = MessageBus

local callbackHost = {}
local callbackLib = LibStub and LibStub("CallbackHandler-1.0", true)
if callbackLib and not MessageBus.callbacks then
    MessageBus.callbacks = callbackLib:New(callbackHost)
    MessageBus.callbackHost = callbackHost
elseif MessageBus.callbackHost then
    callbackHost = MessageBus.callbackHost
end

local function Debug(fmt, ...)
    if T.debug then
        T.debug(string.format("[MessageBus] " .. fmt, ...))
    end
end

function MessageBus:Register(owner, messageName, handlerName)
    if type(owner) ~= "table" or type(messageName) ~= "string" or type(handlerName) ~= "string" then
        return false
    end
    self.callbackHandles[owner] = self.callbackHandles[owner] or {}
    if self.callbacks then
        callbackHost.RegisterCallback(owner, messageName, handlerName)
        self.callbackHandles[owner][messageName] = true
    else
        local listeners = self.fallbackListeners[messageName] or {}
        listeners[owner] = handlerName
        self.fallbackListeners[messageName] = listeners
        self.callbackHandles[owner][messageName] = true
    end
    return true
end

function MessageBus:Unregister(owner, messageName)
    local handles = self.callbackHandles[owner]
    if not handles then
        return
    end
    if self.callbacks and handles[messageName] then
        callbackHost.UnregisterCallback(owner, messageName)
    elseif self.fallbackListeners[messageName] then
        self.fallbackListeners[messageName][owner] = nil
        if not next(self.fallbackListeners[messageName]) then
            self.fallbackListeners[messageName] = nil
        end
    end
    handles[messageName] = nil
    if not next(handles) then
        self.callbackHandles[owner] = nil
    end
end

function MessageBus:UnregisterAll(owner)
    local handles = self.callbackHandles[owner]
    if not handles then
        return
    end
    local names = {}
    for messageName in pairs(handles) do
        names[#names + 1] = messageName
    end
    for _, messageName in ipairs(names) do
        self:Unregister(owner, messageName)
    end
end

function MessageBus:SendMessage(messageName, ...)
    if self.callbacks then
        self.callbacks:Fire(messageName, ...)
        return
    end
    local listeners = self.fallbackListeners[messageName]
    if type(listeners) ~= "table" then
        return
    end
    for owner, handlerName in pairs(listeners) do
        local handler = owner and owner[handlerName]
        if type(handler) == "function" then
            local ok, err = pcall(handler, owner, messageName, ...)
            if not ok then
                Debug("HandlerError message=%s owner=%s error=%s", tostring(messageName), tostring(owner.name or owner), tostring(err))
            end
        end
    end
end
