local T, C, L = unpack(select(2, ...))

local NewBadge = {}
T.NewBadge = NewBadge

local NEW_ATLAS = "UI-Journeys-GreatVault-Tag-new"
local DEFAULT_ANCHOR = "TOPRIGHT"
local DEFAULT_WIDTH = 28
local DEFAULT_HEIGHT = 19

local Version = T.VersionUtil

local function ShouldInspectItems(moduleDef)
    if not moduleDef then
        return false
    end
    local masterToggle = moduleDef.masterToggle
    if not (masterToggle and masterToggle.dbPath and T.ModuleLoader) then
        return true
    end
    local runtimeModule = T.ModuleLoader:GetByDbKey(masterToggle.dbPath)
    if not runtimeModule then
        return true
    end
    return runtimeModule.enabled == true and runtimeModule.pendingReload ~= true
end

local function GetOptionItems(moduleDef)
    if not ShouldInspectItems(moduleDef) then
        return {}
    end
    if T.GetOptionModuleItems then
        return T.GetOptionModuleItems(moduleDef, T.OptionEngine)
    end
    if type(moduleDef) == "table" and type(moduleDef.itemsFactory) == "function" then
        local ok, items = pcall(moduleDef.itemsFactory, T.OptionEngine, moduleDef)
        if ok and type(items) == "table" then
            return items
        end
    end
    return moduleDef and moduleDef.items or {}
end

local function GetModuleLatestVersion(moduleDef)
    if not moduleDef then
        return nil
    end

    local latest = moduleDef.newSince
    for _, itemDef in ipairs(GetOptionItems(moduleDef)) do
        if itemDef and itemDef.newSince then
            latest = Version.Max(latest, itemDef.newSince)
        end
    end
    return latest
end

local function GetModuleById(moduleId)
    for _, moduleDef in ipairs(T.OptionDefinitions or {}) do
        if moduleDef and moduleDef.id == moduleId then
            return moduleDef
        end
    end
    return nil
end

local function GetCurrentVersion()
    if T and T.Version then
        return tostring(T.Version)
    end
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata("ShengTangTools", "Version") or "0.0.0"
    end
    return "0.0.0"
end

function NewBadge.Init(currentVersion)
    if type(STT_DB) ~= "table" then
        return false
    end

    if STT_DB.newBadgeSeen ~= nil and type(STT_DB.newBadgeSeen) ~= "table" then
        STT_DB.newBadgeSeen = {}
    end

    if STT_DB.newBadgeSeen == nil then
        local seen = {}
        local count = 0
        for _, moduleDef in ipairs(T.OptionDefinitions or {}) do
            if moduleDef and moduleDef.id then
                seen[moduleDef.id] = currentVersion
                count = count + 1
            end
        end
        STT_DB.newBadgeSeen = seen
        if T.debug then
            T.debug(string.format("[NewBadge] InitSeen count=%d version=%s", count, tostring(currentVersion)))
        end
    end

    return true
end

function NewBadge:GetSeen(moduleId)
    if type(STT_DB) ~= "table" or type(STT_DB.newBadgeSeen) ~= "table" then
        return nil
    end
    return STT_DB.newBadgeSeen[moduleId]
end

function NewBadge:IsItemNew(moduleDef, itemDef)
    if not moduleDef or not moduleDef.id or not itemDef or not itemDef.newSince then
        return false
    end
    return Version.Greater(itemDef.newSince, self:GetSeen(moduleDef.id))
end

function NewBadge:HasAnyNewItem(moduleDef)
    if not moduleDef then
        return false
    end
    for _, itemDef in ipairs(GetOptionItems(moduleDef)) do
        if self:IsItemNew(moduleDef, itemDef) then
            return true
        end
    end
    return false
end

function NewBadge:IsModuleNew(moduleDef)
    if not moduleDef or not moduleDef.id then
        return false
    end
    if moduleDef.newSince and Version.Greater(moduleDef.newSince, self:GetSeen(moduleDef.id)) then
        return true
    end
    return self:HasAnyNewItem(moduleDef)
end

function NewBadge:MarkSeen(moduleId)
    if not moduleId or type(STT_DB) ~= "table" then
        return false
    end

    local version = Version.Max(GetCurrentVersion(), GetModuleLatestVersion(GetModuleById(moduleId)))
    STT_DB.newBadgeSeen = type(STT_DB.newBadgeSeen) == "table" and STT_DB.newBadgeSeen or {}
    local previous = STT_DB.newBadgeSeen[moduleId]
    if previous == version then
        return false
    end

    STT_DB.newBadgeSeen[moduleId] = version
    if T.debug then
        T.debug(string.format("[NewBadge] MarkSeen module=%s version=%s previous=%s",
            tostring(moduleId),
            tostring(version),
            tostring(previous)
        ))
    end
    return true
end

function NewBadge:CreateBadge(parent, opts)
    if not parent or type(parent.CreateTexture) ~= "function" then
        return nil
    end

    opts = opts or {}
    local anchor = opts.anchor or DEFAULT_ANCHOR
    local width = opts.width or DEFAULT_WIDTH
    local height = opts.height or DEFAULT_HEIGHT
    local offsetX = opts.offsetX or 0
    local offsetY = opts.offsetY or 0

    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetAtlas(NEW_ATLAS)
    tex:SetSize(width, height)
    tex:SetPoint(anchor, parent, anchor, offsetX, offsetY)
    tex:Hide()
    return tex
end
