local T = unpack(select(2, ...))

local EventBus = T.EventBus or {
    eventMap = {},
    ownerMap = {},
    registeredEvents = {},
    blockedLogged = {},
}
T.EventBus = EventBus
EventBus.registeredEvents = EventBus.registeredEvents or {}
EventBus.blockedLogged = EventBus.blockedLogged or {}

local frame = EventBus.frame or CreateFrame("Frame", "STT_EventBusFrame")
EventBus.frame = frame

local PROTECTED_EVENTS = {
    COMBAT_LOG_EVENT_UNFILTERED = true,
}

local function Debug(fmt, ...)
    if T.debug then
        T.debug(string.format("[EventBus] " .. fmt, ...))
    end
end

local function IsProtectedEvent(eventName)
    return PROTECTED_EVENTS[eventName] == true
end

local function LogBlockedEvent(eventName, owner)
    if EventBus.blockedLogged[eventName] then
        return
    end
    EventBus.blockedLogged[eventName] = true
    Debug("FrameEventSkippedProtected event=%s owner=%s", tostring(eventName), tostring(owner and (owner.name or owner)))
end

local function RegisterFrameEvent(eventName)
    if EventBus.registeredEvents[eventName] then
        return true
    end
    local ok, err = pcall(frame.RegisterEvent, frame, eventName)
    if ok then
        EventBus.registeredEvents[eventName] = true
        return true
    end
    Debug("FrameEventRegisterFailed event=%s error=%s", eventName, tostring(err))
    return false
end

local function AddOwnerSubscription(self, owner, eventName)
    local events = self.ownerMap[owner]
    if not events then
        events = {}
        self.ownerMap[owner] = events
    end
    events[eventName] = true
end

function EventBus:Register(owner, eventName, handlerName)
    if type(owner) ~= "table" or type(eventName) ~= "string" or eventName == "" or type(handlerName) ~= "string" then
        return false
    end
    if IsProtectedEvent(eventName) then
        LogBlockedEvent(eventName, owner)
        return false
    end
    local subscribers = self.eventMap[eventName]
    if not subscribers then
        subscribers = {}
        self.eventMap[eventName] = subscribers
    end
    subscribers[owner] = handlerName
    AddOwnerSubscription(self, owner, eventName)
    if not self.registeredEvents[eventName] then
        RegisterFrameEvent(eventName)
    end
    return true
end

function EventBus:Unregister(owner, eventName)
    local subscribers = self.eventMap[eventName]
    if subscribers then
        subscribers[owner] = nil
        if not next(subscribers) then
            self.eventMap[eventName] = nil
            if self.registeredEvents[eventName] then
                local ok, err = pcall(frame.UnregisterEvent, frame, eventName)
                if ok then
                    self.registeredEvents[eventName] = nil
                else
                    Debug("FrameEventUnregisterFailed event=%s error=%s", eventName, tostring(err))
                end
            end
        end
    end
    local events = self.ownerMap[owner]
    if events then
        events[eventName] = nil
        if not next(events) then
            self.ownerMap[owner] = nil
        end
    end
end

function EventBus:UnregisterAll(owner)
    local events = self.ownerMap[owner]
    if not events then
        return
    end
    local copy = {}
    for eventName in pairs(events) do
        copy[#copy + 1] = eventName
    end
    for _, eventName in ipairs(copy) do
        self:Unregister(owner, eventName)
    end
end

function EventBus:GetSubscriberCount(target)
    local count = 0
    if type(target) == "string" then
        for _ in pairs(self.eventMap[target] or {}) do
            count = count + 1
        end
        return count
    end
    for _ in pairs(self.ownerMap[target] or {}) do
        count = count + 1
    end
    return count
end

frame:SetScript("OnEvent", function(_, eventName, ...)
    local subscribers = EventBus.eventMap[eventName]
    if type(subscribers) ~= "table" then
        return
    end
    for owner, handlerName in pairs(subscribers) do
        local handler = owner and owner[handlerName]
        if type(handler) == "function" then
            local ok, err = pcall(handler, owner, eventName, ...)
            if not ok then
                Debug("HandlerError event=%s owner=%s error=%s", tostring(eventName), tostring(owner.name or owner), tostring(err))
            end
        end
    end
end)
