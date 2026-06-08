local T, C, L = unpack(select(2, ...))
do

local ParserHook = {}
T.VisualBoardParserHook = ParserHook

local function Trim(text)
    local value = tostring(text or "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function ParseBoardPayload(payload)
    local raw = Trim(payload)
    if raw == "" then
        return nil
    end
    local boardRef, offset = raw:match("^([^@]+)@([%d%.]+)$")
    boardRef = Trim(boardRef or raw)
    if boardRef == "" then
        return nil
    end
    return {
        boardRef = boardRef,
        offset = tonumber(offset) or 0,
    }
end

function ParserHook.ExtractInvokes(text)
    local invokes = {}
    local stripped = tostring(text or ""):gsub("{board:([^}]+)}", function(payload)
        local item = ParseBoardPayload(payload)
        if item then
            invokes[#invokes + 1] = item
        end
        return ""
    end)
    stripped = Trim(stripped:gsub("%s+", " "))
    return stripped, invokes
end

function ParserHook.HasInvokes(text)
    return tostring(text or ""):find("{board:[^}]+}") ~= nil
end

end
