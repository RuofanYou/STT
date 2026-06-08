-- 轻量 luaunit 兼容层（仅保留本项目需要的断言能力）
local luaunit = {}

local function render(v)
    if type(v) ~= "table" then
        return tostring(v)
    end
    local out = {}
    for k, val in pairs(v) do
        out[#out + 1] = tostring(k) .. "=" .. render(val)
    end
    table.sort(out)
    return "{" .. table.concat(out, ",") .. "}"
end

local function deep_equal(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end

    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then
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

function luaunit.assertEquals(actual, expected, msg)
    if actual ~= expected then
        error(msg or ("assertEquals 失败: actual=" .. render(actual) .. ", expected=" .. render(expected)), 2)
    end
end

function luaunit.assertTrue(v, msg)
    if not v then
        error(msg or "assertTrue 失败", 2)
    end
end

function luaunit.assertFalse(v, msg)
    if v then
        error(msg or "assertFalse 失败", 2)
    end
end

function luaunit.assertNotNil(v, msg)
    if v == nil then
        error(msg or "assertNotNil 失败", 2)
    end
end

function luaunit.assertDeepEquals(actual, expected, msg)
    if not deep_equal(actual, expected) then
        error(msg or ("assertDeepEquals 失败: actual=" .. render(actual) .. ", expected=" .. render(expected)), 2)
    end
end

return luaunit
