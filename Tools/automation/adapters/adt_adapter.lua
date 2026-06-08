local Common = require("mocks.wow_api_common")

local source = debug.getinfo(1, "S").source
local this_path = source:sub(1, 1) == "@" and source:sub(2) or source
local function dirname(path)
    local d = path and path:match("^(.*)/[^/]+$")
    return (d and d ~= "") and d or "."
end
local automation_dir = dirname(dirname(this_path))
local tools_dir = dirname(automation_dir)
local repo_root = dirname(tools_dir)
if repo_root == "." then
    repo_root = os.getenv("PWD") or "."
end

local MODULE_PATH = repo_root .. "/AdvancedDecorationTools/src/features/housing/Housing_BatchPlace.lua"

local M = {}

local function create_context(fixture)
    local db = Common.deep_copy((fixture.init and fixture.init.db) or {})
    local context = {
        db = db,
        restartRecordIDs = {},
        startPlacedEntryIDs = {},
        debugLines = {},
        timers = {},
        uiRefreshCount = 0,
        loadSettingsCount = 0,
        ctrlDown = not not ((fixture.init and fixture.init.ctrlDown) or false),
        catalogByEntryID = Common.deep_copy((fixture.init and fixture.init.catalogByEntryID) or {}),
        decorByGUID = Common.deep_copy((fixture.init and fixture.init.decorByGUID) or {}),
    }

    local ADT = {
        L = {},
        Housing = {},
        PaintMode = nil,
        TestAPI = {},
    }

    function ADT.GetDBValue(key)
        return context.db[key]
    end

    function ADT.SetDBValue(key, value)
        context.db[key] = value
    end

    function ADT.DebugPrint(msg)
        context.debugLines[#context.debugLines + 1] = tostring(msg)
    end

    function ADT.Housing:StartPlacingByRecordID(recordID)
        context.restartRecordIDs[#context.restartRecordIDs + 1] = recordID
        return true
    end

    local C_HousingBasicMode = {
        StartPlacingNewDecor = function(entryID)
            context.startPlacedEntryIDs[#context.startPlacedEntryIDs + 1] = entryID
        end,
        StartPlacingPreviewDecor = function() end,
    }

    local C_HousingCatalog = {
        GetCatalogEntryInfo = function(entryID)
            return context.catalogByEntryID[entryID]
        end,
    }

    local C_HousingDecor = {
        GetDecorInstanceInfoForGUID = function(guid)
            return context.decorByGUID[guid]
        end,
    }

    local hooks = {}
    local function hooksecurefunc(tbl, func_name, hook_fn)
        local key = tostring(tbl) .. ":" .. tostring(func_name)
        hooks[key] = hooks[key] or tbl[func_name]
        local original = hooks[key] or function() end
        tbl[func_name] = function(...)
            local ret = { original(...) }
            hook_fn(...)
            return table.unpack(ret)
        end
    end

    local env = Common.new_base_env({
        ADT = ADT,
        C_HousingBasicMode = C_HousingBasicMode,
        C_HousingCatalog = C_HousingCatalog,
        C_HousingDecor = C_HousingDecor,
        CreateFrame = function()
            return Common.make_frame()
        end,
        hooksecurefunc = hooksecurefunc,
        IsControlKeyDown = function()
            return context.ctrlDown
        end,
        C_Timer = {
            After = function(delay, fn)
                context.timers[#context.timers + 1] = delay
                if type(fn) == "function" then
                    fn()
                end
            end,
        },
    })

    local chunk, load_err = loadfile(MODULE_PATH, "t", env)
    if not chunk then
        error("加载 Housing_BatchPlace.lua 失败: " .. tostring(load_err))
    end

    local ok, runtime_err = pcall(chunk, "AdvancedDecorationTools", ADT)
    if not ok then
        error("执行 Housing_BatchPlace.lua 失败: " .. tostring(runtime_err))
    end

    context.ADT = ADT
    context.env = env

    if fixture.init and fixture.init.lastPlacedRecordID ~= nil then
        ADT.PaintMode.lastPlacedRecordID = fixture.init.lastPlacedRecordID
    end

    return context
end

local function process_events(context, events)
    for _, event in ipairs(events or {}) do
        if event.type == "set_ctrl" then
            context.ctrlDown = not not event.value
        elseif event.type == "set_db" then
            context.db[event.key] = event.value
        elseif event.type == "start_new" then
            context.env.C_HousingBasicMode.StartPlacingNewDecor(event.entryID)
        elseif event.type == "start_preview" then
            context.env.C_HousingBasicMode.StartPlacingPreviewDecor(event.recordID)
        elseif event.type == "place_success" then
            context.ADT.PaintMode:OnDecorPlaced(event.decorGUID, event.size, event.isNew, event.isPreview)
        elseif event.type == "toggle_triplet" then
            context.db[event.key] = event.value
            context.uiRefreshCount = context.uiRefreshCount + 1
            context.loadSettingsCount = context.loadSettingsCount + 1
        elseif event.type == "event_dispatch" then
            context.ADT.PaintMode:TriggerEvent("HOUSING_DECOR_PLACE_SUCCESS", event.decorGUID, event.size, event.isNew, event.isPreview)
        else
            error("未知 ADT 事件类型: " .. tostring(event.type))
        end
    end
end

local function snapshot(context)
    return {
        lastPlacedRecordID = context.ADT.PaintMode and context.ADT.PaintMode.lastPlacedRecordID or nil,
        restartRecordIDs = Common.deep_copy(context.restartRecordIDs),
        startPlacedEntryIDs = Common.deep_copy(context.startPlacedEntryIDs),
        uiRefreshCount = context.uiRefreshCount,
        loadSettingsCount = context.loadSettingsCount,
        db = Common.deep_copy(context.db),
    }
end

function M.RunCase(caseName, fixture)
    local context = create_context(fixture)
    function context.ADT.TestAPI.RunCase(_, _caseName, _fixture)
        process_events(context, _fixture.events)
        return {
            ok = true,
            output = snapshot(context),
            case = _caseName,
        }
    end

    return context.ADT.TestAPI.RunCase(context.ADT.TestAPI, caseName, fixture)
end

return M
