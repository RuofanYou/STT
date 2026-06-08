local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local RecentSkills = {}
T.RecentSkills = RecentSkills

local MAX_RECENT = 5

local function NormalizeClass(classFile)
    local value = type(classFile) == "string" and classFile:upper() or ""
    value = value:gsub("[^A-Z]", "")
    if value == "" then
        return nil
    end
    return value
end

local function DB()
    if type(C.DB.semanticTimeline) ~= "table" then
        C.DB.semanticTimeline = {}
    end
    local db = C.DB.semanticTimeline
    if type(db.editor) ~= "table" then
        db.editor = {}
    end
    if type(db.editor.recentSkills) ~= "table" then
        db.editor.recentSkills = {}
    end
    return db.editor.recentSkills
end

function RecentSkills.Push(classFile, spellID)
    local classKey = NormalizeClass(classFile)
    local id = tonumber(spellID)
    if not classKey or not id or id <= 0 then
        return false
    end

    local store = DB()
    local bucket = type(store[classKey]) == "table" and store[classKey] or {}
    store[classKey] = bucket

    for index = #bucket, 1, -1 do
        if tonumber(bucket[index]) == id then
            table.remove(bucket, index)
        end
    end
    table.insert(bucket, 1, id)
    while #bucket > MAX_RECENT do
        table.remove(bucket)
    end
    return true
end

function RecentSkills.Get(classFile)
    local classKey = NormalizeClass(classFile)
    if not classKey then
        return {}
    end
    local bucket = DB()[classKey]
    if type(bucket) ~= "table" then
        return {}
    end
    local out = {}
    for _, spellID in ipairs(bucket) do
        local id = tonumber(spellID)
        if id and id > 0 then
            out[#out + 1] = id
        end
    end
    return out
end


end)
