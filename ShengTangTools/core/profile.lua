local T, C, L = unpack(select(2, ...))

-- 内部模块名 T.Profile；玩家可见层统一称为"配置"。
-- 视觉与心智模型对齐暴雪 PlayerSpellsFrame.LoadSystem。
local Profile = {}
T.Profile = Profile

local PROFILE_SCHEMA_VERSION = 1

local function Now()
    return time and time() or 0
end

function Profile:GetCharKey()
    local name = UnitName and UnitName("player") or T.PlayerName or "Unknown"
    local realm = GetRealmName and GetRealmName() or ""
    if realm == "" then
        return tostring(name or "Unknown")
    end
    return tostring(name or "Unknown") .. "-" .. tostring(realm):gsub("%s+", "")
end

local function GetCurrentCharInfo()
    local name = UnitName and UnitName("player") or T.PlayerName or "Unknown"
    local classFile = ""
    if UnitClass then
        local _
        _, classFile = UnitClass("player")
    end
    local charKey = Profile:GetCharKey()
    return tostring(name or "Unknown"), tostring(classFile or ""), charKey
end

local function GetDefaultProfileName()
    local _, _, charKey = GetCurrentCharInfo()
    return charKey ~= "" and charKey or (L["CONFIG_PROFILE_DEFAULT_NAME"] or "默认配置")
end

local function EnsureRoot()
    STT_DB = STT_DB or {}
    STT_DB.Profiles = type(STT_DB.Profiles) == "table" and STT_DB.Profiles or {}
    STT_DB.ActiveProfileIDByChar = type(STT_DB.ActiveProfileIDByChar) == "table" and STT_DB.ActiveProfileIDByChar or {}
    STT_DB["CurrentProfileBy" .. "Char"] = nil
    STT_DB._nextProfileID = tonumber(STT_DB._nextProfileID) or 1
    return STT_DB
end

local function EnsureProfileTables(profile)
    profile.Plans = type(profile.Plans) == "table" and profile.Plans or {}
    profile.PlanNames = type(profile.PlanNames) == "table" and profile.PlanNames or {}
    profile.AutoLoad = type(profile.AutoLoad) == "table" and profile.AutoLoad or {}
    profile.EncounterAutoLoad = type(profile.EncounterAutoLoad) == "table" and profile.EncounterAutoLoad or {}
    profile.PlanLastUpdateName = type(profile.PlanLastUpdateName) == "table" and profile.PlanLastUpdateName or {}
    profile.PlanLastUpdateTime = type(profile.PlanLastUpdateTime) == "table" and profile.PlanLastUpdateTime or {}
    profile.PlanAuthor = type(profile.PlanAuthor) == "table" and profile.PlanAuthor or {}
    profile.PlanCreatedTime = type(profile.PlanCreatedTime) == "table" and profile.PlanCreatedTime or {}
    profile.PlanEncounterIDs = type(profile.PlanEncounterIDs) == "table" and profile.PlanEncounterIDs or {}
    profile.SelfNote = profile.SelfNote or ""
    profile.nextID = tonumber(profile.nextID) or 1
    profile.PlanKinds = type(profile.PlanKinds) == "table" and profile.PlanKinds or {}
    profile.SemanticBossKeyByPlanID = type(profile.SemanticBossKeyByPlanID) == "table" and profile.SemanticBossKeyByPlanID or {}
    profile.SemanticPlanIDByBossKey = type(profile.SemanticPlanIDByBossKey) == "table" and profile.SemanticPlanIDByBossKey or {}
    profile.PersonalBossPlans = type(profile.PersonalBossPlans) == "table" and profile.PersonalBossPlans or {}
    profile.PersonalBossPlansByID = type(profile.PersonalBossPlansByID) == "table" and profile.PersonalBossPlansByID or {}
    profile.PlanHiddenFromLegacy = type(profile.PlanHiddenFromLegacy) == "table" and profile.PlanHiddenFromLegacy or {}
    profile.SemanticBossKeySchemaVersion = tonumber(profile.SemanticBossKeySchemaVersion) or 0
    profile._meta = type(profile._meta) == "table" and profile._meta or {}
    profile._meta.name = tostring(profile._meta.name or GetDefaultProfileName())
    profile._meta["sc" .. "ope"] = nil
    if not profile._meta.ownerKey or profile._meta.ownerKey == "" then
        profile._meta.ownerKey = Profile:GetCharKey()
    end
    if not profile._meta.ownerName or profile._meta.ownerName == "" or not profile._meta.ownerClass then
        local ownerName, ownerClass = GetCurrentCharInfo()
        profile._meta.ownerName = profile._meta.ownerName or ownerName
        profile._meta.ownerClass = profile._meta.ownerClass or ownerClass
    end
    profile._meta.createdAt = tonumber(profile._meta.createdAt) or Now()
    profile._meta.updatedAt = tonumber(profile._meta.updatedAt) or profile._meta.createdAt
    return profile
end

function Profile:GetActiveProfileID()
    local db = EnsureRoot()
    return tonumber(db.ActiveProfileIDByChar[self:GetCharKey()])
end

function Profile:Get(id)
    local db = EnsureRoot()
    local profile = db.Profiles[tonumber(id)]
    if type(profile) == "table" then
        return EnsureProfileTables(profile)
    end
    return nil
end

function Profile:GetActive()
    return self:Get(self:GetActiveProfileID())
end

function Profile:GetActiveData()
    local active = self:GetActive()
    if active then
        return active
    end
    self:EnsureBindingForChar()
    active = self:GetActive()
    if active then
        return active
    end
    error("[STT][Profile] active profile missing")
end

function Profile:GetList()
    local db = EnsureRoot()
    local list = {}
    local charKey = self:GetCharKey()
    local activeID = self:GetActiveProfileID()
    for id, profile in pairs(db.Profiles) do
        local numericID = tonumber(id)
        if numericID then
            local meta = EnsureProfileTables(profile)._meta
            list[#list + 1] = {
                id = numericID,
                name = meta.name or GetDefaultProfileName(),
                ownerKey = meta.ownerKey,
                ownerName = meta.ownerName,
                ownerClass = meta.ownerClass,
                isMine = meta.ownerKey == charKey,
                isActive = numericID == activeID,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.isMine ~= b.isMine then
            return a.isMine
        end
        return (a.id or 0) < (b.id or 0)
    end)
    return list
end

function Profile:GetMyOwnedProfileID()
    local db = EnsureRoot()
    local charKey = self:GetCharKey()
    local ownedID
    for id, profile in pairs(db.Profiles) do
        local numericID = tonumber(id)
        local meta = type(profile) == "table" and EnsureProfileTables(profile)._meta or nil
        if numericID and meta and meta.ownerKey == charKey and (not ownedID or numericID < ownedID) then
            ownedID = numericID
        end
    end
    return ownedID
end

function Profile:Create(name)
    local db = EnsureRoot()
    local normalized = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" then
        error(L["CONFIG_PROFILE_NAME_REQUIRED"] or "请输入配置名字", 0)
    end

    local id = tonumber(db._nextProfileID) or 1
    db._nextProfileID = id + 1
    local ownerName, ownerClass, ownerKey = GetCurrentCharInfo()

    local profile = EnsureProfileTables({
        _meta = {
            name = normalized,
            ownerKey = ownerKey,
            ownerName = ownerName,
            ownerClass = ownerClass,
            createdAt = Now(),
            updatedAt = Now(),
        },
    })
    db.Profiles[id] = profile

    if T.events then
        T.events:Fire("STT_PROFILE_CREATED", id)
    end
    return id
end

function Profile:Rename(id, newName)
    local profile = self:Get(id)
    if not profile then
        return false
    end
    local meta = profile._meta
    local normalized = tostring(newName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" then
        normalized = GetDefaultProfileName()
    end
    local oldName = meta.name
    if oldName == normalized then
        return true
    end
    meta.name = normalized
    meta.updatedAt = Now()
    if T.events then
        T.events:Fire("STT_PROFILE_RENAMED", tonumber(id), oldName, normalized)
    end
    return true
end

function Profile:SetActive(id)
    local numericID = tonumber(id)
    if not numericID or not self:Get(numericID) then
        error("[STT][Profile] profile not found", 0)
    end
    local db = EnsureRoot()
    local charKey = self:GetCharKey()
    local prev = tonumber(db.ActiveProfileIDByChar[charKey])
    if prev == numericID then
        return true
    end

    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.FlushEditorNow then
        local ok, result = T.SemanticTimelineGUI.FlushEditorNow("profile_will_change")
        if not ok then
            if T.debug then
                T.debug(string.format("[STT][Profile] switch blocked: flushResult=%s", tostring(result)))
            end
            return false
        end
    end

    db.ActiveProfileIDByChar[charKey] = numericID
    self:Get(numericID)._meta.updatedAt = Now()

    if T.events then
        T.events:Fire("STT_PROFILE_CHANGED", numericID, prev, charKey)
    end
    if T.Note and T.Note.ApplyAutoPlanSelection then
        T.Note:ApplyAutoPlanSelection("profile_switch")
    end

    local meta = db.Profiles[numericID] and db.Profiles[numericID]._meta or {}
    if T.msg then
        T.msg((L["CONFIG_PROFILE_SWITCHED"] or "已切换到配置「%s」"):format(meta.name or GetDefaultProfileName()))
    end
    return true
end

function Profile:GetDefaultProfileID()
    local db = EnsureRoot()
    local id = tonumber(db.DefaultProfileID)
    if id and self:Get(id) then
        return id
    end
    if db.DefaultProfileID ~= nil then
        db.DefaultProfileID = nil
    end
    return nil
end

function Profile:SetDefaultProfileID(id)
    local db = EnsureRoot()
    local prev = tonumber(db.DefaultProfileID)
    local numericID = tonumber(id)
    if numericID and not self:Get(numericID) then
        error("[STT][Profile] default profile not found", 0)
    end
    if prev == numericID then
        return true
    end

    db.DefaultProfileID = numericID
    if T.events then
        T.events:Fire("STT_PROFILE_DEFAULT_CHANGED", numericID, prev)
    end
    if T.msg then
        if numericID then
            local meta = db.Profiles[numericID] and db.Profiles[numericID]._meta or {}
            T.msg((L["CONFIG_PROFILE_DEFAULT_SET"] or "已设为新角色默认配置：%s"):format(meta.name or ""))
        else
            T.msg(L["CONFIG_PROFILE_DEFAULT_UNSET"] or "已取消新角色默认配置")
        end
    end
    return true
end

function Profile:Delete(id)
    local numericID = tonumber(id)
    local db = EnsureRoot()
    local profile = self:Get(numericID)
    if not profile then
        return false
    end

    if self:GetActiveProfileID() == numericID then
        local fallbackID
        for profileID in pairs(db.Profiles) do
            local candidateID = tonumber(profileID)
            if candidateID and candidateID ~= numericID and (not fallbackID or candidateID < fallbackID) then
                fallbackID = candidateID
            end
        end
        if fallbackID then
            self:SetActive(fallbackID)
        else
            db.ActiveProfileIDByChar[self:GetCharKey()] = nil
        end
    end

    for charKey, activeID in pairs(db.ActiveProfileIDByChar) do
        if tonumber(activeID) == numericID then
            db.ActiveProfileIDByChar[charKey] = nil
        end
    end
    local clearedDefaultID = tonumber(db.DefaultProfileID) == numericID and numericID or nil
    if clearedDefaultID then
        db.DefaultProfileID = nil
    end

    db.Profiles[numericID] = nil
    if T.events then
        T.events:Fire("STT_PROFILE_DELETED", numericID)
        if clearedDefaultID then
            T.events:Fire("STT_PROFILE_DEFAULT_CHANGED", nil, clearedDefaultID)
        end
    end
    if not next(db.Profiles) then
        local newID = self:Create(GetDefaultProfileName())
        self:SetActive(newID)
    end
    return true
end

local function CopyTable(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[CopyTable(k)] = CopyTable(v)
    end
    return copy
end

function Profile:CopyContentTo(srcID, dstID)
    local src = self:Get(srcID)
    local dst = self:Get(dstID)
    if not src or not dst then
        error("[STT][Profile] copy source or target missing", 0)
    end
    if tonumber(srcID) == tonumber(dstID) then
        error("[STT][Profile] copy source and target are same", 0)
    end

    local meta = dst._meta
    for key in pairs(dst) do
        if key ~= "_meta" then
            dst[key] = nil
        end
    end
    for key, value in pairs(src) do
        if key ~= "_meta" then
            dst[key] = CopyTable(value)
        end
    end
    dst._meta = meta
    dst._meta.updatedAt = Now()
    EnsureProfileTables(dst)

    if T.events then
        T.events:Fire("STT_PROFILE_CONTENT_COPIED", tonumber(srcID), tonumber(dstID))
        if tonumber(dstID) == self:GetActiveProfileID() then
            T.events:Fire("STT_PROFILE_CHANGED", tonumber(dstID), tonumber(dstID), self:GetCharKey())
        end
    end
    return true
end

function Profile:EnsureBindingForChar()
    local db = EnsureRoot()
    local charKey = self:GetCharKey()

    local activeID = tonumber(db.ActiveProfileIDByChar[charKey])
    if activeID and self:Get(activeID) then
        return activeID
    end

    local ownedID = self:GetMyOwnedProfileID()
    if not ownedID then
        local name = GetDefaultProfileName()
        ownedID = self:Create(name)
        if T.msg then
            T.msg((L["CONFIG_PROFILE_AUTO_CREATED"] or "已为「%s」自动创建配置"):format(name))
        end
    end

    local defaultID = self:GetDefaultProfileID()
    db.ActiveProfileIDByChar[charKey] = defaultID or ownedID
    return db.ActiveProfileIDByChar[charKey]
end

function Profile:MigrateActiveProfileToByChar()
    local db = EnsureRoot()
    local legacy = tonumber(db.ActiveProfileID)
    if not legacy then
        db.ActiveProfileID = nil
        return
    end
    local charKey = self:GetCharKey()
    if not db.ActiveProfileIDByChar[charKey] then
        db.ActiveProfileIDByChar[charKey] = legacy
    end
    db.ActiveProfileID = nil
end

function Profile:MigrateLegacyNote()
    local db = EnsureRoot()
    if (tonumber(db._profileSchemaVersion) or 0) >= PROFILE_SCHEMA_VERSION then
        return
    end

    if type(db.Note) ~= "table" then
        db._profileSchemaVersion = PROFILE_SCHEMA_VERSION
        return
    end

    local legacy = db.Note
    local ownerName, ownerClass, ownerKey = GetCurrentCharInfo()
    local profileName = ownerKey ~= "" and ownerKey or GetDefaultProfileName()
    local newID = tonumber(db._nextProfileID) or 1
    local newProfiles = {}
    legacy._meta = {
        name = profileName,
        ownerKey = ownerKey,
        ownerName = ownerName,
        ownerClass = ownerClass,
        createdAt = Now(),
        updatedAt = Now(),
    }
    newProfiles[newID] = EnsureProfileTables(legacy)

    if type(newProfiles[newID].Plans) ~= "table" then
        error("[STT][Profile] legacy Plans table missing")
    end

    db.Profiles = newProfiles
    db["CurrentProfileBy" .. "Char"] = nil
    db.ActiveProfileIDByChar = type(db.ActiveProfileIDByChar) == "table" and db.ActiveProfileIDByChar or {}
    db.ActiveProfileIDByChar[ownerKey] = newID
    db.ActiveProfileID = nil
    db._nextProfileID = newID + 1
    db.Note = nil
    db._profileSchemaVersion = PROFILE_SCHEMA_VERSION

    if T.msg then
        T.msg((L["CONFIG_PROFILE_MIGRATION_DONE"] or "已为您迁移到新版配置体系。原方案保留在「%s」"):format(newProfiles[newID]._meta.name))
    end
end
