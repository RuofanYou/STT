local T = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local Clipboard = {}
T.TimelineClipboard = Clipboard

local storedTokens
local storedIsCut = false

local function CopyToken(token)
    if type(token) ~= "table" then
        return nil
    end
    local copy = {}
    for key, value in pairs(token) do
        if type(value) ~= "table" and type(value) ~= "function" and type(value) ~= "userdata" then
            copy[key] = value
        end
    end
    if type(token.item) == "table" then
        copy.item = token.item
    end
    return copy
end

local function CopyTokens(tokens)
    local out = {}
    for _, token in ipairs(type(tokens) == "table" and tokens or {}) do
        local copy = CopyToken(token)
        if copy then
            out[#out + 1] = copy
        end
    end
    return out
end

function Clipboard.Set(tokens, isCut)
    local copied = CopyTokens(tokens)
    if #copied == 0 then
        return false
    end
    storedTokens = copied
    storedIsCut = isCut == true
    if T.debug then
        T.debug(string.format("[STT_TIMELINE_CLIPBOARD_SET] count=%d cut=%s", #copied, tostring(storedIsCut)))
    end
    return true
end

function Clipboard.Get()
    if not storedTokens or #storedTokens == 0 then
        return nil, false
    end
    return CopyTokens(storedTokens), storedIsCut
end

function Clipboard.HasContent()
    return storedTokens ~= nil and #storedTokens > 0
end

function Clipboard.Clear()
    storedTokens = nil
    storedIsCut = false
end

end)
