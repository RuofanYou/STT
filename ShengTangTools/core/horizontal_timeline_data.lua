local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local HorizontalData = {}
T.HorizontalTimelineData = HorizontalData

local DEFAULT_ICON = 134400
local TIME_GRID_STEPS = { 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300 }
local TARGET_LABEL_GAP = 90
local MIN_MINOR_GAP = 14

local function CountDecimals(value)
    local number = tonumber(value) or 0
    if math.abs(number - math.floor(number + 0.5)) < 0.0001 then
        return 0
    end
    return 1
end

local function RoundToStep(value, step)
    local number = math.max(0, tonumber(value) or 0)
    local stepValue = math.max(0.1, tonumber(step) or 1)
    return math.floor((number / stepValue) + 0.5) * stepValue
end

local function PickStepForGap(pxPerSecond, targetGap)
    local px = math.max(0.0001, tonumber(pxPerSecond) or 1)
    local gap = math.max(1, tonumber(targetGap) or TARGET_LABEL_GAP)
    for _, step in ipairs(TIME_GRID_STEPS) do
        if step * px >= gap then
            return step
        end
    end
    return TIME_GRID_STEPS[#TIME_GRID_STEPS]
end

local function PickMinorStep(pxPerSecond, majorStep)
    local px = math.max(0.0001, tonumber(pxPerSecond) or 1)
    local major = tonumber(majorStep) or 1
    local candidate = major
    for _, step in ipairs(TIME_GRID_STEPS) do
        if step >= major then
            break
        end
        local ratio = major / step
        if step * px >= MIN_MINOR_GAP and math.abs(ratio - math.floor(ratio + 0.5)) < 0.0001 then
            candidate = step
        end
    end
    return candidate
end

local function PickSnapStep(pxPerSecond)
    local px = math.max(0.0001, tonumber(pxPerSecond) or 1)
    if px >= 260 then
        return 0.1
    end
    if px >= 160 then
        return 0.2
    end
    if px >= 90 then
        return 0.5
    end
    return 1
end

local CLASS_TOKEN_BY_CONDITION = {
    warrior = "WARRIOR", ["战士"] = "WARRIOR",
    paladin = "PALADIN", ["圣骑士"] = "PALADIN",
    hunter = "HUNTER", ["猎人"] = "HUNTER",
    rogue = "ROGUE", ["潜行者"] = "ROGUE",
    priest = "PRIEST", ["牧师"] = "PRIEST",
    deathknight = "DEATHKNIGHT", ["死亡骑士"] = "DEATHKNIGHT",
    shaman = "SHAMAN", ["萨满祭司"] = "SHAMAN",
    mage = "MAGE", ["法师"] = "MAGE",
    warlock = "WARLOCK", ["术士"] = "WARLOCK",
    monk = "MONK", ["武僧"] = "MONK",
    druid = "DRUID", ["德鲁伊"] = "DRUID",
    demonhunter = "DEMONHUNTER", ["恶魔猎手"] = "DEMONHUNTER",
    evoker = "EVOKER", ["唤魔师"] = "EVOKER",
}

local ROLE_COLORS = {
    healer = { 0.30, 1.00, 0.45, 1 },
    tank = { 0.35, 0.65, 1.00, 1 },
    dps = { 1.00, 0.62, 0.30, 1 },
    all = { 0.92, 0.92, 0.92, 1 },
    boss = { 1.00, 0.82, 0.20, 1 },
    condition = { 0.86, 0.86, 0.92, 1 },
    player = { 1.00, 1.00, 1.00, 1 },
}

local NPC_COLOR = ROLE_COLORS.boss

local ROLE_TOKEN_BY_KEY = {
    healer = "HEALER",
    tank = "TANK",
    dps = "DAMAGER",
    damager = "DAMAGER",
}

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizePersonnelEntry(raw)
    if type(raw) == "table" then
        local displayName = Trim(raw.displayName or raw.name or raw[1])
        local slotName = Trim(raw.slotName or raw.key or raw.slot or "")
        if displayName == "" then
            displayName = slotName
        end
        return displayName, slotName, tonumber(raw.specID)
    end

    local displayName = Trim(raw)
    return displayName, displayName
end

local function IsGroupSlotValue(slotValue)
    local text = Trim(slotValue)
    local count = 0
    for _ in text:gmatch("%S+") do
        count = count + 1
        if count > 1 then
            return true
        end
    end
    return false
end

local function AddUniqueName(out, seen, name)
    local text = Trim(name)
    if text ~= "" and not seen[text] then
        seen[text] = true
        out[#out + 1] = text
    end
end

local function ResolveSlotDisplayNames(slots, slotName, depth, stack)
    local name = Trim(slotName)
    if name == "" then
        return {}
    end
    if type(slots) ~= "table" or depth > 5 or (stack and stack[name]) then
        return { name }
    end

    local slotValue = slots[name]
    if not slotValue or Trim(slotValue) == "" then
        return { name }
    end

    stack = stack or {}
    stack[name] = true
    local resolved = T.STNTemplate and T.STNTemplate.ResolveSlotAtRuntime and T.STNTemplate.ResolveSlotAtRuntime(slotValue) or slotValue
    local out, seen = {}, {}

    local function AddResolved(value)
        local text = Trim(value)
        if text == "" then
            return
        end
        if slots[text] and not stack[text] then
            for _, nested in ipairs(ResolveSlotDisplayNames(slots, text, depth + 1, stack)) do
                AddUniqueName(out, seen, nested)
            end
        else
            AddUniqueName(out, seen, text)
        end
    end

    if type(resolved) == "table" then
        for _, value in ipairs(resolved) do
            AddResolved(value)
        end
    else
        AddResolved(resolved)
    end
    stack[name] = nil
    return #out > 0 and out or { name }
end

local function BuildAudienceDisplayKey(names)
    local out = {}
    for _, name in ipairs(names or {}) do
        local text = Trim(name)
        if text ~= "" then
            out[#out + 1] = text
        end
    end
    return table.concat(out, "/")
end

function HorizontalData.ExtractPersonnelContext(text)
    if type(text) ~= "string" or text == "" then
        return nil, nil
    end
    local preprocess = T.STNTemplate and T.STNTemplate.PreprocessText
    if not preprocess then
        return nil, nil
    end

    local info = preprocess(text, { relaxed = true })
    local slots = info and info.slots or nil
    local section = info and info.sections and info.sections["人员"] or nil
    if not section then
        return nil, nil
    end

    local groupMemberSlots = {}
    if type(slots) == "table" then
        for _, slotValue in pairs(slots) do
            if IsGroupSlotValue(slotValue) then
                for member in tostring(slotValue or ""):gmatch("%S+") do
                    local memberName = Trim(member)
                    if slots[memberName] ~= nil then
                        groupMemberSlots[memberName] = true
                    end
                end
            end
        end
    end

    local personnelKeys = {}
    local seenPersonnel = {}
    local function AddPersonnelKey(slotName, raw, specID)
        local displayName = Trim(raw)
        if displayName ~= "" and not seenPersonnel[displayName] then
            seenPersonnel[displayName] = true
            personnelKeys[#personnelKeys + 1] = {
                slotName = Trim(slotName),
                displayName = displayName,
                specID = tonumber(specID),
            }
        end
    end

    local rawLines = info.rawLines or {}
    local startLine = (tonumber(section.headerLine) or 0) + 1
    local endLine = tonumber(section.lastLine) or startLine - 1
    for lineNumber = startLine, endLine do
        local rawLine = tostring(rawLines[lineNumber] or "")
        local rawKey = rawLine:match("^%s*([^=]+)%s*=")
        if not rawKey then
            rawKey = Trim(rawLine)
        end
        local key = Trim(rawKey)
        local slotValue = key ~= "" and slots and slots[key] or nil
        if key ~= "" then
            if slotValue and groupMemberSlots[key] then
                -- 作为多人员组右侧引用的中间槽位，只有正文直接使用时才建显示行。
            elseif slotValue and IsGroupSlotValue(slotValue) then
                -- 多人员组只作为显示别名使用，不把右侧成员补成空人员行。
            elseif slotValue and T.STNTemplate and T.STNTemplate.ResolveSlotAtRuntime then
                local resolved = T.STNTemplate.ResolveSlotAtRuntime(slotValue)
                if type(resolved) == "string" and Trim(resolved) ~= "" then
                    AddPersonnelKey(key, resolved, info.slotVisualSpecs and info.slotVisualSpecs[key])
                else
                    AddPersonnelKey(key, key, info.slotVisualSpecs and info.slotVisualSpecs[key])
                end
            else
                AddPersonnelKey(key, key, info.slotVisualSpecs and info.slotVisualSpecs[key])
            end
        end
    end

    local audienceDisplayByLine = {}
    local bodySection = info.sections and info.bodySectionName and info.sections[info.bodySectionName] or nil
    if bodySection and type(slots) == "table" then
        for index, line in ipairs(bodySection.lines or {}) do
            local actualLine = tonumber(bodySection.lineNumbers and bodySection.lineNumbers[index]) or index
            for rawToken in tostring(line or ""):gmatch("{([^}]+)}") do
                local slotName = Trim(rawToken)
                local slotValue = slots[slotName]
                if slotValue and IsGroupSlotValue(slotValue) then
                    local names = ResolveSlotDisplayNames(slots, slotName, 1, {})
                    if #names > 1 then
                        local expandedKey = BuildAudienceDisplayKey(names)
                        if expandedKey ~= "" then
                            audienceDisplayByLine[actualLine] = audienceDisplayByLine[actualLine] or {}
                            audienceDisplayByLine[actualLine][expandedKey] = {
                                displayName = slotName,
                            }
                        end
                    end
                end
            end
        end
    end

    return #personnelKeys > 0 and personnelKeys or nil, next(audienceDisplayByLine) and audienceDisplayByLine or nil
end

local function CopyColor(color)
    return {
        tonumber(color and color[1]) or 1,
        tonumber(color and color[2]) or 1,
        tonumber(color and color[3]) or 1,
        tonumber(color and color[4]) or 1,
    }
end

local function ResolveClassColor(classFile)
    local token = type(classFile) == "string" and classFile:upper() or nil
    if token and C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(token)
        if color then
            return {
                tonumber(color.r) or 1,
                tonumber(color.g) or 1,
                tonumber(color.b) or 1,
                1,
            }
        end
    end
    if token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
        local color = RAID_CLASS_COLORS[token]
        return {
            tonumber(color.r) or 1,
            tonumber(color.g) or 1,
            tonumber(color.b) or 1,
            1,
        }
    end
    return nil
end

local function NormalizeRoleToken(role)
    local key = type(role) == "string" and role:lower() or ""
    return ROLE_TOKEN_BY_KEY[key]
end

local function ResolveSpecInfo(specID)
    local idValue = tonumber(specID)
    if not idValue then
        return nil
    end

    local icon, role, classFile = nil, nil, nil
    if GetSpecializationInfoByID then
        local ok, id, name, description, specIcon, specRole, specClass = pcall(GetSpecializationInfoByID, idValue)
        if ok then
            icon = specIcon
            role = specRole
            classFile = specClass
        end
    end

    if (not role or role == "") and T.ResolveSpecRole then
        role = T.ResolveSpecRole(idValue)
    end

    return {
        specID = idValue,
        specIcon = icon,
        role = NormalizeRoleToken(role),
        classFile = classFile,
    }
end

local function ResolveSingleSpecCondition(text)
    if not T.ResolveConditionSpecIDs then
        return nil
    end
    local ids = T.ResolveConditionSpecIDs(text)
    if type(ids) ~= "table" or #ids ~= 1 then
        return nil
    end
    return ResolveSpecInfo(ids[1])
end

local function ParseNameRealm(who)
    local text = Trim(who)
    if text == "" then
        return "", nil
    end
    local name, realm = text:match("^([^-]+)%-(.+)$")
    if name and realm then
        return Trim(name), Trim(realm)
    end
    return text, nil
end

local function RecordWhoStats(stats, who, whoType)
    if whoType ~= "player" then
        return
    end
    local text = Trim(who)
    if text == "" or text:find("/", 1, true) then
        return
    end
    local name, realm = ParseNameRealm(text)
    if name == "" then
        return
    end
    local bucket = stats[name]
    if not bucket then
        bucket = { total = 0, realms = {} }
        stats[name] = bucket
    end
    bucket.total = bucket.total + 1
    if realm and realm ~= "" then
        bucket.realms[realm] = true
    else
        bucket.realms[""] = true
    end
end

local function CountKeys(values)
    local count = 0
    for _ in pairs(values or {}) do
        count = count + 1
    end
    return count
end

local function ResolveKind(who, whoType)
    local text = Trim(who)
    local lower = text:lower()
    if whoType == "condition" then
        if lower == "boss" then
            return "boss"
        end
        return "condition"
    end
    return "player"
end

local function NormalizeWhoInfo(who, whoType, allWhoStats)
    local kind = ResolveKind(who, whoType)
    local displayText = Trim(who)
    local playerInfo = nil

    if kind == "player" then
        local name, realm = ParseNameRealm(displayText)
        local stats = allWhoStats and allWhoStats[name] or nil
        local shouldShowRealm = realm and realm ~= "" and stats and CountKeys(stats.realms) > 1
        displayText = shouldShowRealm and (name .. "-" .. realm) or name
        playerInfo = {
            name = name,
            realm = realm,
        }
    else
        displayText = displayText:gsub("%s+%d+$", "")
    end

    if displayText == "" then
        displayText = L["TIMELINE_VIEW_UNSPECIFIED"] or "未指定"
    end

    return {
        kind = kind,
        key = kind .. ":" .. displayText,
        displayText = displayText,
        playerInfo = playerInfo,
    }
end

local function CopyPlayerInfo(playerInfo)
    if type(playerInfo) ~= "table" then
        return nil
    end
    return {
        name = playerInfo.name,
        realm = playerInfo.realm,
        classFile = playerInfo.classFile,
        specID = tonumber(playerInfo.specID),
        specIcon = playerInfo.specIcon,
    }
end

local function ResolveSlotVisualHint(slotVisualHints, playerInfo, displayText)
    if type(slotVisualHints) ~= "table" then
        return nil
    end

    local name = playerInfo and playerInfo.name or displayText
    local realm = playerInfo and playerInfo.realm or nil
    if realm and realm ~= "" then
        local fullKey = tostring(name or "") .. "-" .. tostring(realm)
        if slotVisualHints[fullKey] then
            return slotVisualHints[fullKey]
        end
    end
    return slotVisualHints[tostring(name or displayText or "")]
end

local function BuildResolvedSlotVisualHint(rawHint)
    if type(rawHint) ~= "table" then
        return nil
    end

    local specID = tonumber(rawHint.specID)
    local specInfo = specID and ResolveSpecInfo(specID) or nil
    return {
        classFile = rawHint.classFile or (specInfo and specInfo.classFile) or nil,
        specID = specID,
        specIcon = specInfo and specInfo.specIcon or nil,
        role = specInfo and specInfo.role or nil,
    }
end

function HorizontalData.NormalizeWho(who, whoType, allWhoStats)
    return NormalizeWhoInfo(who, whoType, allWhoStats).displayText
end

local function SplitConditionOrTerms(condition)
    local text = Trim(condition)
    if text == "" or not text:find(",", 1, true) then
        return nil
    end

    local out = {}
    for part in text:gmatch("[^,]+") do
        local item = Trim(part)
        if item ~= "" then
            out[#out + 1] = item
        end
    end
    return #out > 1 and out or nil
end

local function CloneCellForWho(cell, who)
    local out = {}
    for key, value in pairs(cell or {}) do
        out[key] = value
    end
    out.who = who
    out.whoType = "condition"
    return out
end

local function BuildDisplayCells(segment, opts)
    local cell = T.TimelineSyntax and T.TimelineSyntax.BuildDisplayCell and T.TimelineSyntax.BuildDisplayCell(segment, opts) or nil
    if not cell then
        return nil
    end

    local conditionTerms = cell.whoType == "condition" and SplitConditionOrTerms(segment and segment.condition) or nil
    if not conditionTerms then
        return { cell }
    end

    local players = type(segment and segment.players) == "table" and segment.players or nil
    local playerText = players and #players > 0 and table.concat(players, "/") or ""
    local cells = {}
    for _, condition in ipairs(conditionTerms) do
        local who = playerText ~= "" and (condition .. "/" .. playerText) or condition
        cells[#cells + 1] = CloneCellForWho(cell, who)
    end
    return cells
end

local BOSS_ALIAS_BY_ENCOUNTER = {
    [3183] = {
        ["鲁拉"] = true,
        ["L'ura"] = true,
    },
    [53159] = {
        ["腐沼"] = true,
        ["Rotmire"] = true,
    },
}

local function IsBossAliasForEncounter(text, encounterID)
    local aliases = BOSS_ALIAS_BY_ENCOUNTER[tonumber(encounterID) or 0]
    return aliases and aliases[Trim(text)] == true
end

local function ResolveConditionMeta(who, kind, encounterID)
    local text = Trim(who)
    local lower = text:lower()
    local classFile = CLASS_TOKEN_BY_CONDITION[lower] or CLASS_TOKEN_BY_CONDITION[text]
    local color = classFile and ResolveClassColor(classFile) or nil

    if kind == "boss" or IsBossAliasForEncounter(text, encounterID) then
        return {
            kind = "boss",
            displayText = text ~= "" and text or "BOSS",
            color = CopyColor(ROLE_COLORS.boss),
            iconTexture = DEFAULT_ICON,
            encounterID = tonumber(encounterID) or 0,
        }
    end

    local specInfo = ResolveSingleSpecCondition(text)
    if lower == "healer" or lower == "heal" or text == "治疗" then
        color = ROLE_COLORS.healer
        specInfo = specInfo or { role = "HEALER" }
    elseif lower == "tank" or text == "坦克" then
        color = ROLE_COLORS.tank
        specInfo = specInfo or { role = "TANK" }
    elseif lower == "dps" or lower == "dd" or lower == "damager" or text == "输出" then
        color = ROLE_COLORS.dps
        specInfo = specInfo or { role = "DAMAGER" }
    elseif lower == "all" or lower == "everyone" or text == "所有人" or text == "全团" then
        color = ROLE_COLORS.all
        specInfo = specInfo or { role = "ALL" }
    end

    if specInfo and specInfo.classFile then
        color = ResolveClassColor(specInfo.classFile) or color
    end

    local isPlayerCondition = specInfo or classFile or color ~= nil
    return {
        kind = isPlayerCondition and "condition" or "npc",
        displayText = text,
        color = CopyColor(color or NPC_COLOR),
        iconTexture = nil,
        encounterID = tonumber(encounterID) or 0,
        role = specInfo and specInfo.role or nil,
        specID = specInfo and specInfo.specID or nil,
        specIcon = specInfo and specInfo.specIcon or nil,
        classFile = specInfo and specInfo.classFile or nil,
        playerInfo = classFile and { classFile = classFile } or nil,
    }
end

function HorizontalData.ResolveConditionColor(who)
    local condition = type(who) == "string" and (who:match("^([^/]+)") or who) or who
    local meta = ResolveConditionMeta(condition, "condition", 0)
    return meta and meta.color or nil
end

local function ResolveEncounterIcon(encounterID)
    local sem = T and T.SemanticTimeline or nil
    local encounter = sem and sem.encountersByID and sem.encountersByID[tonumber(encounterID) or 0] or nil
    return encounter and tonumber(encounter.encounterIcon) or nil
end

local function BuildMeta(info, encounterID, slotVisualHint, instanceID)
    local resolvedEncounterID = tonumber(encounterID) or 0
    local encounterIcon = ResolveEncounterIcon(resolvedEncounterID)
    if info.kind == "player" then
        local playerInfo = CopyPlayerInfo(info.playerInfo) or {}
        local visualHint = BuildResolvedSlotVisualHint(slotVisualHint)
        if visualHint then
            playerInfo.classFile = visualHint.classFile
            playerInfo.specID = visualHint.specID
            playerInfo.specIcon = visualHint.specIcon
        end
        return {
            kind = "player",
            displayText = info.displayText,
            color = CopyColor(ROLE_COLORS.player),
            iconTexture = nil,
            classFile = visualHint and visualHint.classFile or nil,
            specID = visualHint and visualHint.specID or nil,
            specIcon = visualHint and visualHint.specIcon or nil,
            role = visualHint and visualHint.role or nil,
            playerInfo = playerInfo,
            encounterID = resolvedEncounterID,
            instanceID = tonumber(instanceID) or 0,
            encounterIcon = encounterIcon,
        }
    end
    local meta = ResolveConditionMeta(info.displayText, info.kind, resolvedEncounterID)
    meta.displayText = info.displayText
    meta.instanceID = tonumber(instanceID) or 0
    meta.encounterIcon = encounterIcon
    return meta
end

local function ResolveSpellIcon(spellID, existingIcon)
    if existingIcon then
        return existingIcon
    end
    if T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        return T.TimelineSyntax.ResolveSpellIcon(spellID)
    end
    return nil
end

local function ResolveSpellName(spellID)
    local id = tonumber(spellID)
    if not id or id <= 0 then
        return nil
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
        if type(info) == "string" and info ~= "" then
            return info
        end
    end
    if GetSpellInfo then
        local name = GetSpellInfo(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

local function AddItemToEntry(entry, item)
    local bucketKey = tostring(tonumber(item.time) or 0)
    entry._timeBuckets = entry._timeBuckets or {}

    local primary = entry._timeBuckets[bucketKey]
    if primary then
        primary.collisions[#primary.collisions + 1] = item
        return
    end

    item.collisions = {}
    entry._timeBuckets[bucketKey] = item
    entry.items[#entry.items + 1] = item
end

local function GetBarValues(row)
    return T.InlineModifier and T.InlineModifier.GetBarValues and T.InlineModifier.GetBarValues(row) or nil
end

local function ResolveBarDuration(row)
    local maxDuration = nil
    for _, bar in ipairs(GetBarValues(row) or {}) do
        local duration = tonumber(bar and bar.duration)
        if duration and duration > 0 then
            maxDuration = math.max(maxDuration or 0, duration)
        end
    end
    return maxDuration
end

local function ResolveDuration(row, segment)
    local modifiers = type(row and row.modifiers) == "table" and row.modifiers or nil
    local duration = modifiers and modifiers.dur and tonumber(modifiers.dur.value) or nil
    if duration and duration > 0 then
        return duration
    end
    for _, token in ipairs(segment and segment.spellTokens or {}) do
        local tokenDuration = tonumber(token and token.duration)
        if tokenDuration and tokenDuration > 0 then
            return tokenDuration
        end
    end
    return ResolveBarDuration(row)
end

local function BuildBarDisplayCells(segment)
    if not (T.TimelineSyntax and T.TimelineSyntax.BuildCellWho) then
        return nil
    end
    local who, whoType = T.TimelineSyntax.BuildCellWho(segment)
    if Trim(who) == "" then
        return nil
    end

    local baseCell = {
        who = who,
        whoType = whoType,
        actionText = "",
        fullText = "",
        spellID = nil,
        spellIcon = nil,
    }
    local conditionTerms = whoType == "condition" and SplitConditionOrTerms(segment and segment.condition) or nil
    if not conditionTerms then
        return { baseCell }
    end

    local players = type(segment and segment.players) == "table" and segment.players or nil
    local playerText = players and #players > 0 and table.concat(players, "/") or ""
    local cells = {}
    for _, condition in ipairs(conditionTerms) do
        local cellWho = playerText ~= "" and (condition .. "/" .. playerText) or condition
        cells[#cells + 1] = CloneCellForWho(baseCell, cellWho)
    end
    return #cells > 0 and cells or nil
end

local function ResolveBarText(bar, cell, spellID)
    local label = Trim(bar and (bar.labelOverride or bar.label) or "")
    if label ~= "" then
        return label
    end

    local cellText = Trim(cell and (cell.fullText or cell.actionText) or "")
    if cellText ~= "" then
        return cellText
    end

    local spellName = ResolveSpellName(spellID)
    if spellName then
        return spellName
    end
    if tonumber(spellID) then
        return tostring(math.floor(tonumber(spellID) + 0.5))
    end
    return ""
end

local function ParsePhaseKey(phase)
    local raw = tostring(phase or "")
    if raw == "" then
        return nil
    end
    local phaseType, phaseIndex, roundIndex = raw:match("^([pi])(%d+)r(%d+)$")
    if not phaseType then
        phaseType, phaseIndex = raw:match("^([pi])(%d+)$")
        roundIndex = "1"
    end
    local normalizedPhaseIndex = tonumber(phaseIndex)
    local normalizedRoundIndex = tonumber(roundIndex)
    if not phaseType or not normalizedPhaseIndex or normalizedPhaseIndex < 1
        or not normalizedRoundIndex or normalizedRoundIndex < 1 then
        return nil
    end
    local baseKey = phaseType .. tostring(normalizedPhaseIndex)
    return {
        baseKey = baseKey,
        key = string.format("%sr%d", baseKey, normalizedRoundIndex),
        sourceKey = raw,
        phaseType = phaseType,
        phaseIndex = normalizedPhaseIndex,
        roundIndex = normalizedRoundIndex,
    }
end

HorizontalData.ParsePhaseKey = ParsePhaseKey

local function ExtractPhaseFromTimePayload(payload)
    local rawPhase = tostring(payload or ""):match(",%s*([piPI]%d+r?%d*)%s*$")
    local parsed = rawPhase and ParsePhaseKey(rawPhase:lower()) or nil
    if not parsed then
        return nil, nil, nil
    end
    return parsed.key, rawPhase:lower(), parsed
end

HorizontalData.ExtractPhaseFromTimePayload = ExtractPhaseFromTimePayload

local function ResolvePhaseLabel(encounterID, baseKey)
    local config = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[tonumber(encounterID) or 0] or nil
    if config and type(config.phaseLabels) == "table" and config.phaseLabels[baseKey] then
        return config.phaseLabels[baseKey]
    end
    if tostring(baseKey or ""):match("^p%d+$") then
        return "P" .. tostring(baseKey):match("%d+")
    end
    if tostring(baseKey or ""):match("^i%d+$") then
        return "过渡 " .. tostring(baseKey):match("%d+")
    end
    return tostring(baseKey or "")
end

local function ResolveRowPhaseDisplayKey(row, parsed)
    local _, rawPhase, parsedRaw = ExtractPhaseFromTimePayload(row and row.timePayload)
    if parsedRaw and parsed and parsedRaw.key == parsed.key then
        return rawPhase
    end
    return parsed and parsed.sourceKey or nil
end

local function BuildPhaseOrderMap(encounterID)
    local config = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[tonumber(encounterID) or 0] or nil
    local order = config and type(config.phaseOrder) == "table" and config.phaseOrder or nil
    if not order then
        return nil
    end
    local map = {}
    for index, phaseKey in ipairs(order) do
        local parsed = ParsePhaseKey(phaseKey)
        if parsed then
            map[parsed.baseKey] = index
        end
    end
    return next(map) and map or nil
end

local function ResolvePhaseSpanFromAnchors(encounterID, baseKey)
    local config = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[tonumber(encounterID) or 0] or nil
    local rules = config and type(config.anchors) == "table" and config.anchors[baseKey] or nil
    if type(rules) ~= "table" then
        return 0
    end
    local maxDuration = tonumber(rules.duration) or 0
    for _, rule in ipairs(rules) do
        if type(rule) == "table" then
            maxDuration = math.max(maxDuration, tonumber(rule.duration) or 0)
        end
    end
    return math.max(0, maxDuration)
end

local function ResolvePhaseDisplaySpan(row, parsed)
    local spans = type(row) == "table" and row.phaseDisplaySpans or nil
    if type(spans) ~= "table" or type(parsed) ~= "table" then
        return nil
    end
    return tonumber(spans[parsed.key])
        or tonumber(spans[parsed.sourceKey])
        or tonumber(spans[parsed.baseKey])
end

local function GetDefaultPhaseOrder(parsed)
    if parsed.phaseType == "i" then
        return parsed.phaseIndex * 2
    end
    return (parsed.phaseIndex - 1) * 2 + 1
end

local function AddMissingConfiguredPhaseGroups(encounterID, groupsByKey, orderedGroups)
    local config = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[tonumber(encounterID) or 0] or nil
    local order = config and type(config.phaseOrder) == "table" and config.phaseOrder or nil
    if not order or #orderedGroups == 0 then
        return
    end

    local orderByBaseKey = {}
    for index, phaseKey in ipairs(order) do
        local parsed = ParsePhaseKey(phaseKey)
        if parsed then
            orderByBaseKey[parsed.baseKey] = index
        end
    end

    local rounds = {}
    for _, group in ipairs(orderedGroups) do
        local orderIndex = orderByBaseKey[group.baseKey]
        if orderIndex then
            local round = group.roundIndex
            local info = rounds[round] or { minOrder = orderIndex, maxOrder = orderIndex }
            info.minOrder = math.min(info.minOrder, orderIndex)
            info.maxOrder = math.max(info.maxOrder, orderIndex)
            rounds[round] = info
        end
    end

    for roundIndex, info in pairs(rounds) do
        for orderIndex = info.minOrder, info.maxOrder do
            local parsed = ParsePhaseKey(order[orderIndex])
            if parsed then
                local key = string.format("%sr%d", parsed.baseKey, roundIndex)
                if not groupsByKey[key] then
                    local group = {
                        key = key,
                        sourceKey = roundIndex == 1 and parsed.sourceKey or key,
                        baseKey = parsed.baseKey,
                        phaseType = parsed.phaseType,
                        phaseIndex = parsed.phaseIndex,
                        roundIndex = roundIndex,
                        maxTime = ResolvePhaseSpanFromAnchors(encounterID, parsed.baseKey),
                        firstSortIndex = 0,
                    }
                    groupsByKey[key] = group
                    orderedGroups[#orderedGroups + 1] = group
                end
            end
        end
    end
end

local function BuildPhaseDisplayOffsets(rows)
    local groupsByKey = {}
    local orderedGroups = {}
    local encounterID

    for _, row in ipairs(rows or {}) do
        local rowTime = tonumber(row and row.timeSec)
        local parsed = ParsePhaseKey(row and row.phase)
        if rowTime and rowTime >= 0 and parsed then
            encounterID = encounterID or (row.key and tonumber(row.key.encounterID))
            local group = groupsByKey[parsed.key]
            if not group then
                group = {
                    key = parsed.key,
                    sourceKey = ResolveRowPhaseDisplayKey(row, parsed),
                    baseKey = parsed.baseKey,
                    phaseType = parsed.phaseType,
                    phaseIndex = parsed.phaseIndex,
                    roundIndex = parsed.roundIndex,
                    maxTime = 0,
                    firstSortIndex = tonumber(row.sortIndex) or #orderedGroups + 1,
                }
                groupsByKey[parsed.key] = group
                orderedGroups[#orderedGroups + 1] = group
            end
            local duration = ResolveDuration(row) or 0
            group.maxTime = math.max(group.maxTime, rowTime + duration)
            group.maxTime = math.max(group.maxTime, ResolvePhaseDisplaySpan(row, parsed) or 0)
            group.firstSortIndex = math.min(group.firstSortIndex, tonumber(row.sortIndex) or group.firstSortIndex)
        end
    end

    if #orderedGroups <= 1 then
        return {}, { phaseGroupCount = #orderedGroups, maxDisplayTime = 0 }
    end

    for _, group in ipairs(orderedGroups) do
        group.maxTime = math.max(group.maxTime, ResolvePhaseSpanFromAnchors(encounterID, group.baseKey))
    end

    AddMissingConfiguredPhaseGroups(encounterID, groupsByKey, orderedGroups)

    local phaseOrderMap = BuildPhaseOrderMap(encounterID)
    table.sort(orderedGroups, function(left, right)
        if left.roundIndex ~= right.roundIndex then
            return left.roundIndex < right.roundIndex
        end
        local leftOrder = phaseOrderMap and phaseOrderMap[left.baseKey] or GetDefaultPhaseOrder(left)
        local rightOrder = phaseOrderMap and phaseOrderMap[right.baseKey] or GetDefaultPhaseOrder(right)
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        if left.phaseIndex ~= right.phaseIndex then
            return left.phaseIndex < right.phaseIndex
        end
        if left.phaseType ~= right.phaseType then
            return left.phaseType < right.phaseType
        end
        return left.firstSortIndex < right.firstSortIndex
    end)

    local offsets = {}
    local markers = {}
    local cursor = 0
    local hasMultipleRounds = false
    for _, group in ipairs(orderedGroups) do
        if (tonumber(group.roundIndex) or 1) > 1 then
            hasMultipleRounds = true
            break
        end
    end

    for _, group in ipairs(orderedGroups) do
        offsets[group.key] = cursor
        markers[#markers + 1] = {
            key = group.key,
            displayKey = hasMultipleRounds and (group.sourceKey or group.key) or group.baseKey,
            baseKey = group.baseKey,
            label = ResolvePhaseLabel(encounterID, group.baseKey),
            time = cursor,
        }
        cursor = cursor + math.max(0, tonumber(group.maxTime) or 0)
    end

    return offsets, {
        phaseGroupCount = #orderedGroups,
        maxDisplayTime = cursor,
        markers = markers,
    }
end

HorizontalData.BuildPhaseDisplayOffsets = BuildPhaseDisplayOffsets

local function GetEntrySortOrder(entry)
    local meta = entry and entry.meta or nil
    if meta and meta.kind == "boss" then
        return 1
    end
    if meta and meta.kind == "npc" then
        return 1
    end
    if meta and meta.kind == "condition" and meta.role == "ALL" then
        return 2
    end
    if meta and meta.kind == "condition" then
        return 3
    end
    return 4
end

local function SortOrderedKeys(perRow, orderedKeys)
    table.sort(orderedKeys, function(leftKey, rightKey)
        local left = perRow[leftKey]
        local right = perRow[rightKey]
        local leftIndex = tonumber(left and left.firstSortIndex) or 0
        local rightIndex = tonumber(right and right.firstSortIndex) or 0
        if leftIndex ~= rightIndex then
            return leftIndex < rightIndex
        end
        return tostring(left and left.meta and left.meta.displayText or leftKey) < tostring(right and right.meta and right.meta.displayText or rightKey)
    end)
end

local function ResolveAudienceDisplayOverride(audienceDisplayByLine, row, cell)
    local lineNumber = tonumber(row and row.sourceLine) or tonumber(row and row.sortIndex) or 0
    local lineMap = type(audienceDisplayByLine) == "table" and audienceDisplayByLine[lineNumber] or nil
    if type(lineMap) ~= "table" then
        return nil
    end

    return lineMap[Trim(cell and cell.who)]
end

function HorizontalData.BuildPerRow(rows, opts)
    local sourceRows = type(rows) == "table" and rows or {}
    opts = type(opts) == "table" and opts or {}
    local whoStats = {}
    local prepared = {}
    local phaseOffsets, phaseStats = BuildPhaseDisplayOffsets(sourceRows)
    local personnelSet = {}
    local personnelInfoByDisplay = {}
    for _, rawPersonnel in ipairs(opts.personnelKeys or {}) do
        local text, slotName, specID = NormalizePersonnelEntry(rawPersonnel)
        if text ~= "" then
            personnelSet[text] = true
            personnelInfoByDisplay[text] = {
                slotName = slotName ~= "" and slotName or text,
                specID = specID,
            }
        end
    end

    for _, row in ipairs(sourceRows) do
        local rowTime = tonumber(row and row.timeSec)
        if rowTime and rowTime >= 0 and type(row.segments) == "table" then
            for segmentIndex, segment in ipairs(row.segments) do
                local cells = BuildDisplayCells(segment, {
                    personalUntargeted = row.editorTab == "personal",
                })
                if (not cells or #cells == 0) and GetBarValues(row) then
                    cells = BuildBarDisplayCells(segment)
                end
                for _, cell in ipairs(cells or {}) do
                    cell.segmentIndex = segmentIndex
                    local displayOverride = ResolveAudienceDisplayOverride(opts.audienceDisplayByLine, row, cell)
                    if displayOverride and Trim(displayOverride.displayName) ~= "" then
                        cell.who = Trim(displayOverride.displayName)
                        cell.whoType = "player"
                    end
                    if cell.whoType == "condition" and personnelSet[Trim(cell.who)] then
                        cell.whoType = "player"
                    end
                    RecordWhoStats(whoStats, cell.who, cell.whoType)
                    prepared[#prepared + 1] = {
                        row = row,
                        segment = segment,
                        cell = cell,
                    }
                end
            end
        end
    end

    local perRow = {}
    local orderedKeys = {}
    local maxTime = 0

    for _, preparedItem in ipairs(prepared) do
        local row = preparedItem.row
        local segment = preparedItem.segment
        local cell = preparedItem.cell
        local info = NormalizeWhoInfo(cell.who, cell.whoType, whoStats)
        local key = info.key
        local entry = perRow[key]
        local parsedDuration = ResolveDuration(row, segment)
        local sourceTime = math.max(0, tonumber(row.timeSec) or 0)
        local parsedPhase = ParsePhaseKey(row.phase)
        local phaseOffset = (parsedPhase and phaseOffsets[parsedPhase.key]) or 0
        local displayTime = sourceTime + phaseOffset
            if not entry then
                local slotVisualHint = info.kind == "player"
                    and ResolveSlotVisualHint(row.slotVisualHints, info.playerInfo, info.displayText)
                    or nil
                if not slotVisualHint and info.kind == "player" and T.ResolveSlotVisualHint then
                    slotVisualHint = T.ResolveSlotVisualHint(info.displayText)
                end
                local personnelInfo = info.kind == "player" and personnelInfoByDisplay[info.displayText] or nil
                entry = {
                    key = key,
                    meta = BuildMeta(info, row.key and row.key.encounterID or nil, slotVisualHint, row.key and row.key.instanceID or nil),
                    items = {},
                    firstTime = displayTime,
                    firstSortIndex = tonumber(row.sortIndex) or #orderedKeys + 1,
                }
                if personnelInfo and entry.meta then
                    entry.meta.personnelSlotName = personnelInfo.slotName
                    entry.meta.personnelSpecID = personnelInfo.specID
                end
                entry.sortOrder = GetEntrySortOrder(entry)
                perRow[key] = entry
                orderedKeys[#orderedKeys + 1] = key
        end
        entry.firstSortIndex = math.min(tonumber(entry.firstSortIndex) or math.huge, tonumber(row.sortIndex) or math.huge)

        local spellID = tonumber(cell.spellID)
        local sourceSegmentText = tostring(segment and segment.rawText or "")
        local bars = GetBarValues(row)
        local addedItem = false

        local function AddHorizontalItem(itemSpellID, itemSpellIcon, itemText, itemDuration)
            local item = {
                time = displayTime,
                sourceTime = sourceTime,
                phaseDisplayOffset = phaseOffset,
                spellID = itemSpellID,
                spellIcon = itemSpellIcon,
                fullText = tostring(itemText or ""),
                who = info.displayText,
                targetKind = info.kind,
                sourceWho = tostring(cell.who or ""),
                sourceWhoType = tostring(cell.whoType or ""),
                sourceCondition = tostring(segment and segment.condition or ""),
                sourcePlayersText = type(segment and segment.players) == "table" and table.concat(segment.players, "\n") or "",
                sourceSegmentText = sourceSegmentText,
                sourceSegmentIndex = tonumber(cell.segmentIndex),
                timePayload = tostring(row.timePayload or ""),
                lineNum = tonumber(row.sortIndex) or 0,
                rowID = tostring(row.rowID or ""),
                editorTab = row.editorTab ~= nil and tostring(row.editorTab) or nil,
                sourcePlanID = tonumber(row.sourcePlanID),
                rowKey = key,
                duration = itemDuration,
                collisions = {},
            }

            if item.time < entry.firstTime then
                entry.firstTime = item.time
            end
            local itemEndTime = item.time + (tonumber(item.duration) or 0)
            if itemEndTime > maxTime then
                maxTime = itemEndTime
            end
            AddItemToEntry(entry, item)
            addedItem = true
        end

        for _, bar in ipairs(bars or {}) do
            local barDuration = tonumber(bar and bar.duration)
            if barDuration and barDuration > 0 then
                local barSpellID = tonumber(bar.spellID) or spellID
                local barIcon = ResolveSpellIcon(barSpellID, bar.iconOverride or cell.spellIcon)
                AddHorizontalItem(barSpellID, barIcon, ResolveBarText(bar, cell, barSpellID), barDuration)
            end
        end

        if not addedItem then
            AddHorizontalItem(
                spellID,
                ResolveSpellIcon(spellID, cell.spellIcon),
                tostring(cell.fullText or cell.actionText or row.label or ""),
                parsedDuration
            )
        end
    end

    for _, rawPersonnel in ipairs(opts.personnelKeys or {}) do
        local text, slotName, customSpecID = NormalizePersonnelEntry(rawPersonnel)
        local rowKey = "player:" .. text
        if text ~= "" then
            local slotVisualHint = T.ResolveSlotVisualHint and T.ResolveSlotVisualHint(slotName ~= "" and slotName or text) or nil
            if not (slotVisualHint and slotVisualHint.specID) and T.ResolveCustomSlotVisualHint then
                local customHint = T.ResolveCustomSlotVisualHint(customSpecID)
                if customHint then
                    slotVisualHint = customHint
                end
            end
            local existing = perRow[rowKey]
            if existing and existing.meta and existing.meta.kind == "player" and slotVisualHint then
                local visualHint = BuildResolvedSlotVisualHint(slotVisualHint)
                if visualHint then
                    existing.meta.classFile = existing.meta.classFile or visualHint.classFile
                    existing.meta.specID = existing.meta.specID or visualHint.specID
                    existing.meta.specIcon = existing.meta.specIcon or visualHint.specIcon
                    existing.meta.role = existing.meta.role or visualHint.role
                    existing.meta.playerInfo = existing.meta.playerInfo or { name = text }
                    existing.meta.playerInfo.classFile = existing.meta.playerInfo.classFile or visualHint.classFile
                    existing.meta.playerInfo.specID = existing.meta.playerInfo.specID or visualHint.specID
                    existing.meta.playerInfo.specIcon = existing.meta.playerInfo.specIcon or visualHint.specIcon
                end
            elseif not existing then
                perRow[rowKey] = {
                    key = rowKey,
                    meta = BuildMeta({
                        key = rowKey,
                        kind = "player",
                        displayText = text,
                        playerInfo = { name = text },
                    }, nil, slotVisualHint, nil),
                    items = {},
                    firstTime = 0,
                    firstSortIndex = #orderedKeys + 1,
                }
                perRow[rowKey].meta.personnelSlotName = slotName ~= "" and slotName or text
                perRow[rowKey].meta.personnelSpecID = customSpecID
                perRow[rowKey].sortOrder = GetEntrySortOrder(perRow[rowKey])
                orderedKeys[#orderedKeys + 1] = rowKey
            end
        end
    end

    SortOrderedKeys(perRow, orderedKeys)

    for _, entry in pairs(perRow) do
        table.sort(entry.items, function(a, b)
            if a.time ~= b.time then
                return a.time < b.time
            end
            return (a.lineNum or 0) < (b.lineNum or 0)
        end)
        entry._timeBuckets = nil
    end

    return perRow, orderedKeys, maxTime, phaseStats
end

local function ResolveBucketKey(item)
    local sid = tonumber(item.spellID) or 0
    if sid > 0 then
        return "s:" .. sid, sid
    end
    return "t:" .. tostring(item.fullText or ""), 0
end

local function AddToSpellBucket(buckets, bucketOrder, item)
    local key, sid = ResolveBucketKey(item)
    local bucket = buckets[key]
    local bucketIndex = #bucketOrder + 1
    if not bucket then
        bucket = {
            bucketKey = key,
            spellID = sid,
            label = tostring(item.fullText or ""),
            spellIcon = item.spellIcon,
            items = {},
            firstTime = tonumber(item.time) or 0,
            bucketIndex = bucketIndex,
        }
        buckets[key] = bucket
        bucketOrder[#bucketOrder + 1] = key
    end
    bucket.items[#bucket.items + 1] = item
    local itemTime = tonumber(item.time) or 0
    if itemTime < bucket.firstTime then
        bucket.firstTime = itemTime
    end
end

local function CompareBucketItems(a, b)
    local ta = tonumber(a.time) or 0
    local tb = tonumber(b.time) or 0
    if ta ~= tb then return ta < tb end
    return (tonumber(a.lineNum) or 0) < (tonumber(b.lineNum) or 0)
end

function HorizontalData.BuildHorizontalDisplayRows(perRow, orderedKeys, expandedMap)
    local result = {}
    if type(perRow) ~= "table" or type(orderedKeys) ~= "table" then
        return result
    end
    expandedMap = type(expandedMap) == "table" and expandedMap or {}

    for _, ownerKey in ipairs(orderedKeys) do
        local entry = perRow[ownerKey]
        if entry then
            local buckets = {}
            local bucketOrder = {}
            for _, item in ipairs(entry.items or {}) do
                AddToSpellBucket(buckets, bucketOrder, item)
                for _, col in ipairs(item.collisions or {}) do
                    AddToSpellBucket(buckets, bucketOrder, col)
                end
            end
            for _, key in ipairs(bucketOrder) do
                table.sort(buckets[key].items, CompareBucketItems)
            end

            local spellCount = #bucketOrder
            local isExpanded = expandedMap[ownerKey] and spellCount >= 2 or false

            result[#result + 1] = {
                kind = "ownerHeader",
                ownerKey = ownerKey,
                meta = entry.meta,
                items = entry.items,
                hasSpells = spellCount >= 2,
                expanded = isExpanded,
                spellCount = spellCount,
                firstTime = entry.firstTime,
                entry = entry,
            }

            if isExpanded then
                table.sort(bucketOrder, function(a, b)
                    local left = buckets[a]
                    local right = buckets[b]
                    local leftKey = tostring(left and left.bucketKey or a)
                    local rightKey = tostring(right and right.bucketKey or b)
                    if leftKey ~= rightKey then
                        return leftKey < rightKey
                    end
                    local leftIndex = tonumber(left and left.bucketIndex) or math.huge
                    local rightIndex = tonumber(right and right.bucketIndex) or math.huge
                    if leftIndex ~= rightIndex then
                        return leftIndex < rightIndex
                    end
                    return a < b
                end)
                for _, key in ipairs(bucketOrder) do
                    local bucket = buckets[key]
                    result[#result + 1] = {
                        kind = "spellRow",
                        ownerKey = ownerKey,
                        ownerMeta = entry.meta,
                        spellID = bucket.spellID,
                        label = bucket.label,
                        spellIcon = bucket.spellIcon,
                        items = bucket.items,
                        firstTime = bucket.firstTime,
                        entry = entry,
                    }
                end
            end
        end
    end

    return result
end

function HorizontalData.PruneStaleExpanded(expandedMap, perRow)
    if type(expandedMap) ~= "table" or type(perRow) ~= "table" then
        return
    end
    for ownerKey in pairs(expandedMap) do
        if not perRow[ownerKey] then
            expandedMap[ownerKey] = nil
        end
    end
end

function HorizontalData.GetDragTargetTime(rawTime, freeDrag, grid)
    local timeValue = math.max(0, tonumber(rawTime) or 0)
    grid = type(grid) == "table" and grid or HorizontalData.BuildTimeGrid()
    if freeDrag then
        local precision = 1
        local factor = 10 ^ precision
        return math.floor(timeValue * factor + 0.5) / factor, "raw", precision
    end
    local snapStep = tonumber(grid.snapStep) or 1
    local snapped = RoundToStep(timeValue, snapStep)
    local precision = CountDecimals(snapStep)
    return snapped, precision > 0 and "snap" or "integer", precision
end

function HorizontalData.BuildTimeGrid(pxPerSecond, visibleWidth)
    local px = math.max(0.0001, tonumber(pxPerSecond) or 1)
    local width = math.max(1, tonumber(visibleWidth) or 1)
    local targetGap = TARGET_LABEL_GAP
    if width < 360 then
        targetGap = 110
    end

    local labelStep = PickStepForGap(px, targetGap)
    local minorStep = PickMinorStep(px, labelStep)
    local snapStep = PickSnapStep(px)

    return {
        minorStep = minorStep,
        majorStep = labelStep,
        labelStep = labelStep,
        snapStep = snapStep,
        precision = math.max(CountDecimals(labelStep), CountDecimals(snapStep)),
        minorVisible = minorStep < labelStep and (minorStep * px) >= MIN_MINOR_GAP,
    }
end

end)
