local M = {}

local function is_table(v)
    return type(v) == "table"
end

function M.deep_equal(a, b)
    if type(a) ~= type(b) then
        return false
    end

    if not is_table(a) then
        return a == b
    end

    for k, v in pairs(a) do
        if not M.deep_equal(v, b[k]) then
            return false
        end
    end

    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end

    return true
end

local function dump(v)
    if type(v) ~= "table" then
        return tostring(v)
    end

    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)

    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = tostring(k) .. "=" .. dump(v[k])
    end
    return "{" .. table.concat(out, ", ") .. "}"
end

function M.diff_message(actual, expected)
    return "实际值: " .. dump(actual) .. "\n期望值: " .. dump(expected)
end

return M
