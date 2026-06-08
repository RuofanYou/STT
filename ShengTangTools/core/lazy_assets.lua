local T = unpack(select(2, ...))

local Assets = T.Assets or {
    defs = {},
}
T.Assets = Assets

local function InstallLazyField(tbl, fieldName, assetKey)
    if type(tbl) ~= "table" or type(fieldName) ~= "string" or fieldName == "" then
        return
    end

    local mt = getmetatable(tbl) or {}
    local previousIndex = mt.__index
    local lazyFields = mt.__sttLazyFields or {}
    lazyFields[fieldName] = assetKey
    mt.__sttLazyFields = lazyFields

    if mt.__sttLazyIndexInstalled ~= true then
        mt.__index = function(target, key)
            local lazyKey = lazyFields[key]
            if lazyKey then
                return Assets:Get(lazyKey)
            end
            if type(previousIndex) == "function" then
                return previousIndex(target, key)
            end
            if type(previousIndex) == "table" then
                return previousIndex[key]
            end
            return nil
        end
        mt.__sttLazyIndexInstalled = true
    end

    setmetatable(tbl, mt)
end

function Assets:Define(key, def)
    if type(key) ~= "string" or key == "" or type(def) ~= "table" or type(def.factory) ~= "function" then
        return false
    end
    self.defs[key] = def
    if def.targetTable and def.targetKey then
        InstallLazyField(def.targetTable, def.targetKey, key)
    end
    return true
end

function Assets:Get(key, owner)
    local def = self.defs and self.defs[key]
    if not def then
        return nil
    end
    if def.value == nil then
        def.value = def.factory()
        if def.targetTable and def.targetKey then
            rawset(def.targetTable, def.targetKey, def.value)
        end
    end
    if owner then
        def.owners = def.owners or {}
        def.owners[owner] = true
    end
    return def.value
end

function Assets:ReleaseOwner(owner)
    if not owner then
        return
    end
    for _, def in pairs(self.defs or {}) do
        if def.owners then
            def.owners[owner] = nil
            if not next(def.owners) then
                def.owners = nil
                def.value = nil
                if def.targetTable and def.targetKey then
                    rawset(def.targetTable, def.targetKey, nil)
                end
            end
        end
    end
    pcall(collectgarbage, "collect")
end

function Assets:IsLoaded(key)
    local def = self.defs and self.defs[key]
    return def and def.value ~= nil or false
end

function Assets:GetStats()
    local stats = {
        total = 0,
        loaded = 0,
        cold = 0,
        loadedKeys = {},
    }
    for key, def in pairs(self.defs or {}) do
        stats.total = stats.total + 1
        if def.value ~= nil then
            stats.loaded = stats.loaded + 1
            stats.loadedKeys[#stats.loadedKeys + 1] = key
        else
            stats.cold = stats.cold + 1
        end
    end
    table.sort(stats.loadedKeys)
    return stats
end
