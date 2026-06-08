local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("tacticTranslator.enabled", function()

-- 通用战术板翻译器注册表（单一权威）
-- 每种外部格式（NSRT、MRT、其他）注册为一个 adapter：
--   { id, name, nameKey, sample, sampleKey, detect(text)->bool, parse(text)->parsed, format(parsed)->result }
-- parse/format 均为纯函数，无 UI 依赖；result 至少包含 stn 字段。

local TacticTranslator = {}
T.TacticTranslator = TacticTranslator

local registry = {}
local ordered = {}

function TacticTranslator:Register(def)
    if type(def) ~= "table" then return false end
    if type(def.id) ~= "string" or def.id == "" then return false end
    if type(def.parse) ~= "function" then return false end
    if type(def.format) ~= "function" then return false end
    if registry[def.id] then
        return false
    end
    registry[def.id] = def
    ordered[#ordered + 1] = def
    return true
end

function TacticTranslator:Unregister(id)
    if not id or not registry[id] then return false end
    registry[id] = nil
    for i, def in ipairs(ordered) do
        if def.id == id then
            table.remove(ordered, i)
            break
        end
    end
    return true
end

function TacticTranslator:GetAll()
    return ordered
end

function TacticTranslator:GetById(id)
    return registry[id]
end

function TacticTranslator:GetTranslator(id)
    return self:GetById(id)
end

function TacticTranslator:GetDefaultId()
    local first = ordered[1]
    return first and first.id or nil
end

function TacticTranslator:Translate(id, text)
    local def = registry[id]
    if not def then
        return nil, "unknown translator: " .. tostring(id)
    end
    if type(text) ~= "string" then
        return nil, "input text must be a string"
    end

    local okParse, parsed = pcall(def.parse, text)
    if not okParse then
        return nil, "parse error: " .. tostring(parsed)
    end
    if type(parsed) ~= "table" then
        return nil, "parser returned invalid result"
    end

    local okFormat, result = pcall(def.format, parsed)
    if not okFormat then
        return nil, "format error: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "formatter returned invalid result"
    end

    return result
end

local lastDetectLogSignature = nil

function TacticTranslator:DetectAndTranslate(text)
    if type(text) ~= "string" then
        return text, nil
    end

    for _, def in ipairs(ordered) do
        if type(def.detect) == "function" then
            local okDetect, matched = pcall(def.detect, text)
            if okDetect and matched then
                local result, err = self:Translate(def.id, text)
                if not result then
                    return text, nil, err
                end

                local stn = result.stn
                if type(stn) ~= "string" then
                    return text, nil, "formatter result missing stn"
                end

                local signature = string.format(
                    "%s:%d:%d:%d",
                    tostring(def.id),
                    #text,
                    tonumber(result.eventCount) or 0,
                    tonumber(result.skipped) or 0
                )
                if signature ~= lastDetectLogSignature and T.debug then
                    lastDetectLogSignature = signature
                    T.debug(string.format(
                        "[TACTIC_TRANSLATOR_DETECTED] format=%s events=%d skipped=%d",
                        tostring(def.id),
                        tonumber(result.eventCount) or 0,
                        tonumber(result.skipped) or 0
                    ))
                end

                return stn, def.id, result
            end
        end
    end

    return text, nil
end

end)
