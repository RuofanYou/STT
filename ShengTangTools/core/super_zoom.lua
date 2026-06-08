local T, C = unpack(select(2, ...))
T.RegisterColdFile("superZoom.enabled", function()

local DB_KEY = "superZoom"

local CVAR_MAX_ZOOM = "cameraDistanceMaxZoomFactor"

-- 之前版本写过的俯仰相关 CVar，本版本不再管理，但需要一次性还原回游戏默认值，避免残留影响。
local LEGACY_PITCH_CVARS = {
    "test_cameraDynamicPitch",
    "test_cameraDynamicPitchBaseFovPad",
    "test_cameraDynamicPitchBaseFovPadFlying",
    "test_cameraDynamicPitchBaseFovPadDownScale",
    "test_cameraDynamicPitchSmartPivotCutoffDist",
}

local MAX_ZOOM_SCALE = 15
local SCHEMA_VERSION = 3

local SuperZoom = T.ModuleLoader:NewModule({
    name = "SuperZoom",
    dbKey = DB_KEY .. ".enabled",
    defaultEnabled = false,
})
T.SuperZoom = SuperZoom

local function GetDB()
    if type(C.DB) ~= "table" then
        return nil
    end
    if type(C.DB[DB_KEY]) ~= "table" then
        C.DB[DB_KEY] = {}
    end
    return C.DB[DB_KEY]
end

local function WriteSavedVar(key, value)
    if type(STT_DB) ~= "table" then
        return
    end
    STT_DB[DB_KEY] = STT_DB[DB_KEY] or {}
    STT_DB[DB_KEY][key] = value
end

local function GetCVarDefaultNumber(cvar)
    local raw = GetCVarDefault and GetCVarDefault(cvar)
    return tonumber(raw)
end

local function SafeSetCVar(cvar, value)
    if type(SetCVar) ~= "function" or not cvar or value == nil then
        return false
    end
    local ok = pcall(SetCVar, cvar, value)
    if not ok then
        T.debug(string.format("[SuperZoom] SetCVar failed cvar=%s value=%s", tostring(cvar), tostring(value)))
        return false
    end
    return true
end

-- 触发引擎重新应用 cameraDistanceMaxZoomFactor，否则单纯 SetCVar 不立刻生效。
local function RefreshCamera()
    if MoveViewOutStart then pcall(MoveViewOutStart, 0) end
    if MoveViewInStart then pcall(MoveViewInStart, 0) end
    if MoveViewInStop then pcall(MoveViewInStop) end
    if MoveViewOutStop then pcall(MoveViewOutStop) end
end

function SuperZoom:GetMaxZoomDefaultPanel()
    local raw = GetCVarDefaultNumber(CVAR_MAX_ZOOM) or 2.6
    return raw * MAX_ZOOM_SCALE
end

function SuperZoom:IsEnabled()
    local db = GetDB()
    return db ~= nil and db.enabled == true
end

function SuperZoom:GetMaxZoomPanel()
    local db = GetDB()
    local value = db and tonumber(db.maxZoom)
    if value ~= nil then
        return value
    end
    return self:GetMaxZoomDefaultPanel()
end

function SuperZoom:ApplyMaxZoom(panelValue)
    panelValue = tonumber(panelValue)
    if panelValue == nil then
        return
    end
    local cvarValue = panelValue / MAX_ZOOM_SCALE
    SafeSetCVar(CVAR_MAX_ZOOM, cvarValue)
    RefreshCamera()
    T.debug(string.format("[SuperZoom] ApplyMaxZoom panel=%.2f cvar=%.3f", panelValue, cvarValue))
end

function SuperZoom:ApplyAll()
    if not self:IsEnabled() then
        return
    end
    self:ApplyMaxZoom(self:GetMaxZoomPanel())
end

function SuperZoom:ResetMaxZoom()
    local def = self:GetMaxZoomDefaultPanel()
    local db = GetDB()
    if db then
        db.maxZoom = def
        WriteSavedVar("maxZoom", def)
    end
    SafeSetCVar(CVAR_MAX_ZOOM, def / MAX_ZOOM_SCALE)
    RefreshCamera()
    T.debug(string.format("[SuperZoom] ResetMaxZoom panel=%.2f", def))
    return def
end

-- 迁移：清理旧版本残留（俯仰 CVar 还原为游戏默认；删除 db.groundPitch 字段）
local function MigrateIfNeeded()
    local db = GetDB()
    if not db then
        return
    end
    if tonumber(db._schema) == SCHEMA_VERSION then
        return
    end
    for _, cvar in ipairs(LEGACY_PITCH_CVARS) do
        local def = GetCVarDefaultNumber(cvar)
        if def ~= nil then
            SafeSetCVar(cvar, def)
        end
    end
    db.groundPitch = nil
    if type(STT_DB) == "table" and type(STT_DB[DB_KEY]) == "table" then
        STT_DB[DB_KEY].groundPitch = nil
    end
    db.maxZoom = SuperZoom:GetMaxZoomDefaultPanel()
    db._schema = SCHEMA_VERSION
    WriteSavedVar("maxZoom", db.maxZoom)
    WriteSavedVar("_schema", SCHEMA_VERSION)
    T.debug(string.format("[SuperZoom] Migrate v%d maxZoom=%.2f (pitch cvars restored)",
        SCHEMA_VERSION, db.maxZoom))
end

function SuperZoom:OnRegister()
    T.SuperZoom = self
end

function SuperZoom:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN", "OnEvent")
    if IsLoggedIn and IsLoggedIn() then
        MigrateIfNeeded()
        self:ApplyAll()
    end
end

function SuperZoom:OnDisable()
end

function SuperZoom:OnEvent(event)
    if event == "PLAYER_LOGIN" then
        MigrateIfNeeded()
        self:ApplyAll()
    end
end

end)
