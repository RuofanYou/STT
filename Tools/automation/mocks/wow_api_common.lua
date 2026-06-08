local M = {}

local function shallow_copy(src)
    local out = {}
    for k, v in pairs(src or {}) do
        out[k] = v
    end
    return out
end

function M.deep_copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, val in pairs(v) do
        out[M.deep_copy(k)] = M.deep_copy(val)
    end
    return out
end

function M.new_base_env(extra)
    local env = {
        assert = assert,
        error = error,
        ipairs = ipairs,
        math = math,
        next = next,
        pairs = pairs,
        pcall = pcall,
        rawget = rawget,
        rawset = rawset,
        select = select,
        setmetatable = setmetatable,
        string = string,
        table = table,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = table.unpack,
        xpcall = xpcall,
        utf8 = utf8,
        getmetatable = getmetatable,
        print = function() end,
        _G = nil,
    }

    env._G = env

    for k, v in pairs(extra or {}) do
        env[k] = v
    end

    return env
end

function M.make_frame()
    local frame = {
        __events = {},
        __scripts = {},
        __shown = false,
    }

    function frame:RegisterEvent(event)
        self.__events[event] = true
    end

    function frame:UnregisterEvent(event)
        self.__events[event] = nil
    end

    function frame:SetScript(name, fn)
        self.__scripts[name] = fn
    end

    function frame:Show()
        self.__shown = true
    end

    function frame:Hide()
        self.__shown = false
    end

    function frame:IsShown()
        return self.__shown
    end

    function frame:TriggerEvent(event, ...)
        local cb = self.__scripts.OnEvent
        if cb and self.__events[event] then
            cb(self, event, ...)
        end
    end

    function frame:RunOnUpdate(elapsed)
        local cb = self.__scripts.OnUpdate
        if cb then
            cb(self, elapsed)
        end
    end

    return frame
end

function M.merge(dst, src)
    local out = shallow_copy(dst)
    for k, v in pairs(src or {}) do
        out[k] = v
    end
    return out
end

return M
