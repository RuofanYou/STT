local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("rosterPlanner.enabled", function()

local RP = T.ModuleLoader:NewModule({
    name = "RosterPlanner",
    dbKey = "rosterPlanner.enabled",
    defaultEnabled = false,
})

T.RosterPlanner = RP

local DEFAULT_SAMPLE = table.concat({
    "# STT 阵容文本 v2.0",
    "豆豆DKT = 挨打的豆豆-白银之手, 豆豆战士-白银之手",
    "吉田猫德 = 吉田-戈杜尼",
    "千山FS = 千山-白银之手",
    "我就LR = 我就-白银之手",
    "",
    "[M梦裂]",
    "豆豆DKT    吉田猫德    千山FS    | 我就LR",
}, "\n")

local LEGACY_HEADER = {
    ["人员"] = "roster",
    ["Roster"] = "roster",
    ["roster"] = "roster",
    ["本周说明"] = "notes",
    ["Notes"] = "notes",
    ["notes"] = "notes",
}

local runtime = {
    invite = nil,
    lastParseErrorCount = nil,
    receivedSnapshot = nil,
}

RP.parsed = nil
RP.runtime = runtime

local function Text(key, fallback)
    return (L and L[key]) or fallback or key
end

local function Debug(fmt, ...)
    if not T.debug then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[RP] " .. tostring(fmt), ...))
    else
        T.debug("[RP] " .. tostring(fmt))
    end
end

function RP:IsFeatureAllowed()
    return C and C.DB and C.DB.debugMode == true
end

function RP:BlockIfNotDebug()
    if self:IsFeatureAllowed() then
        return false
    end
    if T.msg then
        T.msg(Text("RP_MSG_DEBUG_REQUIRED", "阵容设置助手仍在 Beta：需先开启 /st debug 并 /reload。"))
    end
    return true
end

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function StripComment(line)
    line = tostring(line or "")
    local pos = line:find("#", 1, true)
    if pos then
        line = line:sub(1, pos - 1)
    end
    return Trim(line)
end

local function NormalizeLegacySourceText(sourceText)
    local out = {}
    local section = nil
    local changed = false
    for rawLine in (tostring(sourceText or "") .. "\n"):gmatch("([^\n]*)\n") do
        local stripped = StripComment(rawLine)
        local block = stripped:match("^%[(.-)%]$")
        if block and LEGACY_HEADER[Trim(block)] then
            section = LEGACY_HEADER[Trim(block)]
            changed = true
        elseif block then
            section = "boss"
            out[#out + 1] = rawLine
        elseif section == "notes" then
            if stripped:match("^([^=]+)%s*=%s*(.+)$") then
                out[#out + 1] = rawLine
            elseif stripped ~= "" then
                changed = true
            else
                out[#out + 1] = rawLine
            end
        else
            out[#out + 1] = rawLine
        end
    end
    if not changed then
        return sourceText
    end
    while #out > 0 and out[#out] == "" do
        out[#out] = nil
    end
    return table.concat(out, "\n")
end

local function NormalizeName(name)
    local text = Trim(name)
    text = text:gsub("%s+", "")
    local short = text:match("^([^%-]+)")
    return string.lower(short or text)
end

function RP:NormalizeRosterName(name)
    return NormalizeName(name)
end

local function AppendUnique(list, seen, value)
    local text = Trim(value)
    if text == "" then
        return
    end
    local key = NormalizeName(text)
    if seen[key] then
        return
    end
    seen[key] = true
    list[#list + 1] = text
end

local function SplitNames(part)
    local values = {}
    local seen = {}
    local text = Trim(part)
    text = text:gsub("，", ",")
    text = text:gsub("\t", " ")
    text = text:gsub(",", " ")
    for token in text:gmatch("%S+") do
        AppendUnique(values, seen, token)
    end
    return values
end

local function BuildAliasIndex(parsed)
    parsed.aliasToKey = {}
    parsed.keyLookup = {}
    for key, aliases in pairs(parsed.roster or {}) do
        local normalizedKey = NormalizeName(key)
        parsed.keyLookup[normalizedKey] = key
        parsed.aliasToKey[normalizedKey] = key
        for _, alias in ipairs(aliases or {}) do
            parsed.aliasToKey[NormalizeName(alias)] = key
        end
    end
end

local function AddBossLine(parsed, boss, line)
    local mainPart, subPart = line:match("^(.-)%s*|%s*(.*)$")
    if not mainPart then
        mainPart = line
        subPart = ""
    end
    local row = {
        main = SplitNames(mainPart),
        subs = SplitNames(subPart),
    }
    boss.lines[#boss.lines + 1] = row
    for _, token in ipairs(row.main) do
        boss.mainAll[#boss.mainAll + 1] = token
    end
    for _, token in ipairs(row.subs) do
        boss.subsAll[#boss.subsAll + 1] = token
    end
end

function RP.GetDefaultSourceText()
    return DEFAULT_SAMPLE
end

function RP.Parse(sourceText)
    local parsed = {
        roster = {},
        bosses = {},
        errors = {},
        warnings = {},
    }
    local currentBoss = nil
    local rosterOrder = {}

    sourceText = tostring(sourceText or "")
    local lineNo = 0
    for rawLine in (sourceText .. "\n"):gmatch("([^\n]*)\n") do
        lineNo = lineNo + 1
        local stripped = StripComment(rawLine)
        if stripped ~= "" then
            local key, value = stripped:match("^([^=]+)%s*=%s*(.+)$")
            if key and value then
                key = Trim(key)
                if key == "" then
                    parsed.errors[#parsed.errors + 1] = { line = lineNo, msg = Text("RP_ERR_ROSTER_KV", "格式：昵称 = 角色名1, 角色名2") }
                else
                    local aliases = SplitNames(value)
                    if #aliases == 0 then
                        parsed.errors[#parsed.errors + 1] = { line = lineNo, msg = Text("RP_ERR_ROSTER_EMPTY", "角色名列表不能为空") }
                    else
                        if not parsed.roster[key] then
                            rosterOrder[#rosterOrder + 1] = key
                        end
                        parsed.roster[key] = aliases
                    end
                end
            elseif stripped:find("=", 1, true) then
                parsed.errors[#parsed.errors + 1] = { line = lineNo, msg = Text("RP_ERR_ROSTER_KV", "格式：昵称 = 角色名1, 角色名2") }
            else
                local block = stripped:match("^%[(.-)%]$")
                if block then
                    block = Trim(block)
                    if block == "" then
                        parsed.errors[#parsed.errors + 1] = { line = lineNo, msg = Text("RP_ERR_EMPTY_BLOCK", "块名不能为空") }
                        currentBoss = nil
                    else
                        currentBoss = {
                            name = block,
                            lines = {},
                            mainAll = {},
                            subsAll = {},
                        }
                        parsed.bosses[#parsed.bosses + 1] = currentBoss
                    end
                elseif stripped:match("^%[") or stripped:match("%]$") then
                    parsed.errors[#parsed.errors + 1] = { line = lineNo, msg = Text("RP_ERR_BLOCK_SYNTAX", "块标题语法错误") }
                elseif currentBoss then
                    AddBossLine(parsed, currentBoss, stripped)
                else
                    parsed.warnings[#parsed.warnings + 1] = { line = lineNo, msg = Text("RP_WARN_LINE_OUTSIDE_BLOCK", "该行不在任何 BOSS 块内，已忽略") }
                end
            end
        end
    end

    parsed.rosterOrder = rosterOrder
    BuildAliasIndex(parsed)

    for _, boss in ipairs(parsed.bosses) do
        for _, token in ipairs(boss.mainAll) do
            if not parsed.aliasToKey[NormalizeName(token)] then
                parsed.warnings[#parsed.warnings + 1] = { boss = boss.name, token = token, msg = Text("RP_WARN_UNKNOWN_TOKEN", "未在别名表中定义，按字面量处理") }
            end
        end
        for _, token in ipairs(boss.subsAll) do
            if not parsed.aliasToKey[NormalizeName(token)] then
                parsed.warnings[#parsed.warnings + 1] = { boss = boss.name, token = token, msg = Text("RP_WARN_UNKNOWN_TOKEN", "未在别名表中定义，按字面量处理") }
            end
        end
    end

    return parsed
end

local function EnsureDB()
    if type(C.DB.rosterPlanner) ~= "table" then
        C.DB.rosterPlanner = {}
    end
    local db = C.DB.rosterPlanner
    local defaults = C.defaults and C.defaults.rosterPlanner or {}
    for key, value in pairs(defaults) do
        if type(value) ~= "table" and db[key] == nil then
            db[key] = value
        end
    end
    if type(db.subPanel) ~= "table" then
        db.subPanel = {}
    end
    for key, value in pairs(defaults.subPanel or {}) do
        if type(value) ~= "table" and db.subPanel[key] == nil then
            db.subPanel[key] = value
        end
    end
    if type(db.subPanel.position) ~= "table" then
        db.subPanel.position = {}
    end
    for key, value in pairs((defaults.subPanel and defaults.subPanel.position) or {}) do
        if db.subPanel.position[key] == nil then
            db.subPanel.position[key] = value
        end
    end
    if type(db.sourceText) ~= "string" or db.sourceText == "" then
        db.sourceText = DEFAULT_SAMPLE
    else
        db.sourceText = NormalizeLegacySourceText(db.sourceText)
    end
    db.groupLayout = nil
    if type(db.aliasGuidCache) ~= "table" then
        db.aliasGuidCache = {}
    end
    if db.difficultyMode ~= "auto" and db.difficultyMode ~= "mythic20" and db.difficultyMode ~= "flex" then
        db.difficultyMode = "auto"
    end
    if type(STT_DB) == "table" then
        STT_DB.rosterPlanner = db
    end
    return db
end

function RP:EnsureDB()
    return EnsureDB()
end

function RP:GetParsed()
    if not self.parsed then
        self:RecomputeParsed("lazy")
    end
    return self.parsed
end

function RP:RecomputeParsed(reason)
    local db = EnsureDB()
    self.parsed = RP.Parse(db.sourceText or "")
    local errorCount = #(self.parsed.errors or {})
    if runtime.lastParseErrorCount ~= errorCount then
        runtime.lastParseErrorCount = errorCount
        Debug("ParseComplete reason=%s bosses=%d errors=%d warnings=%d", tostring(reason or ""), #(self.parsed.bosses or {}), errorCount, #(self.parsed.warnings or {}))
    end
    if T.RosterPlannerGUI and T.RosterPlannerGUI.Refresh then
        T.RosterPlannerGUI:Refresh()
    end
    if T.RosterPlannerSubPanel and T.RosterPlannerSubPanel.Refresh then
        T.RosterPlannerSubPanel:Refresh()
    end
    return self.parsed
end

local function ReadUnitName(unit)
    if not UnitName then
        return nil
    end
    local name, realm = UnitName(unit)
    if not name or name == "" then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function CollectCurrentGroup()
    local map = {}
    local list = {}
    local function add(unit)
        local fullName = ReadUnitName(unit)
        if fullName then
            local key = NormalizeName(fullName)
            map[key] = fullName
            list[#list + 1] = {
                unit = unit,
                name = fullName,
                short = fullName:match("^([^%-]+)") or fullName,
                online = UnitIsConnected and UnitIsConnected(unit) ~= false or true,
            }
        end
    end

    add("player")
    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, count do
            add("raid" .. i)
        end
    elseif IsInGroup and IsInGroup() then
        local count = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
        for i = 1, count do
            add("party" .. i)
        end
    end
    return map, list
end

function RP:ReadCurrentRaidLayout()
    local layout = {}
    if not IsInRaid or not IsInRaid() then
        return layout, false
    end

    local groupSize = {}
    for i = 1, 8 do
        groupSize[i] = 0
    end
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name and subgroup and subgroup >= 1 and subgroup <= 8 then
            groupSize[subgroup] = groupSize[subgroup] + 1
            if groupSize[subgroup] <= 5 then
                layout[(subgroup - 1) * 5 + groupSize[subgroup]] = name
            end
        end
    end
    return layout, true
end

function RP:GetCurrentRaidMembers()
    local list = {}
    if not IsInRaid or not IsInRaid() then
        return list
    end
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do
        local name, _, subgroup, _, _, classFileName = GetRaidRosterInfo(i)
        if name then
            list[#list + 1] = {
                name = name,
                subgroup = subgroup,
                classFileName = classFileName,
                role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(name) or nil,
            }
        end
    end
    table.sort(list, function(a, b)
        if (a.subgroup or 0) == (b.subgroup or 0) then
            return tostring(a.name) < tostring(b.name)
        end
        return (a.subgroup or 0) < (b.subgroup or 0)
    end)
    return list
end

function RP:GetCurrentRaidMembersWithSpec()
    if T.RaidSpecReader and T.RaidSpecReader.GetLastMembers then
        return T.RaidSpecReader:GetLastMembers()
    end
    return {}
end

function RP:ResolveCharacter(token, parsed)
    parsed = parsed or self:GetParsed()
    local normalized = NormalizeName(token)
    local key = parsed.aliasToKey and parsed.aliasToKey[normalized] or nil
    key = key or token
    local aliases = {}
    local seen = {}
    if parsed.roster and parsed.roster[key] then
        for _, alias in ipairs(parsed.roster[key]) do
            AppendUnique(aliases, seen, alias)
        end
    else
        AppendUnique(aliases, seen, token)
    end

    local groupMap = CollectCurrentGroup()
    local primary = aliases[1] or token
    local isOnline = false
    for _, alias in ipairs(aliases) do
        if groupMap[NormalizeName(alias)] then
            primary = groupMap[NormalizeName(alias)]
            isOnline = true
            break
        end
        if UnitExists and UnitExists(alias) then
            primary = alias
            isOnline = true
            break
        end
    end

    return {
        token = token,
        key = key,
        primaryName = primary,
        aliases = aliases,
        isOnline = isOnline,
    }
end

function RP:GetBossLayout(bossIndex, resolveNames, parsed)
    parsed = parsed or self:GetParsed()
    local boss = parsed.bosses and parsed.bosses[tonumber(bossIndex) or 1] or nil
    local layout = {}
    if not boss then
        return layout
    end
    for rowIndex, row in ipairs(boss.lines or {}) do
        if rowIndex <= 8 then
            for pos = 1, 5 do
                local token = row.main and row.main[pos] or nil
                if token and token ~= "" then
                    layout[(rowIndex - 1) * 5 + pos] = resolveNames and self:ResolveCharacter(token, parsed).primaryName or token
                end
            end
        end
    end
    return layout
end

local function JoinTokens(tokens)
    local values = {}
    for _, token in ipairs(tokens or {}) do
        local text = Trim(token)
        if text ~= "" then
            values[#values + 1] = text
        end
    end
    return table.concat(values, "    ")
end

local function BuildBossLinesFromLayout(layout, oldBoss)
    local lines = {}
    for group = 1, 8 do
        local main = {}
        for pos = 1, 5 do
            main[#main + 1] = Trim(layout and layout[(group - 1) * 5 + pos] or "")
        end
        local subs = oldBoss and oldBoss.lines and oldBoss.lines[group] and oldBoss.lines[group].subs or nil
        local mainText = JoinTokens(main)
        local subText = JoinTokens(subs)
        if mainText ~= "" or subText ~= "" then
            if subText ~= "" then
                lines[#lines + 1] = mainText .. " | " .. subText
            else
                lines[#lines + 1] = mainText
            end
        end
    end
    return lines
end

local function IsAliasLine(line)
    local stripped = StripComment(line)
    return stripped:match("^([^=]+)%s*=%s*(.+)$") ~= nil
end

local function ReplaceBossBlock(sourceText, bossIndex, bossName, newLines)
    local out = {}
    local currentBossIndex = 0
    local inTarget = false
    local inserted = false

    local function insertNewLines()
        if inserted then
            return
        end
        for _, line in ipairs(newLines or {}) do
            out[#out + 1] = line
        end
        inserted = true
    end

    for rawLine in (tostring(sourceText or "") .. "\n"):gmatch("([^\n]*)\n") do
        local stripped = StripComment(rawLine)
        local block = stripped:match("^%[(.-)%]$")
        if block then
            if inTarget then
                insertNewLines()
                inTarget = false
            end
            currentBossIndex = currentBossIndex + 1
            out[#out + 1] = rawLine
            if currentBossIndex == bossIndex then
                inTarget = true
                inserted = false
            end
        elseif inTarget then
            if stripped == "" or IsAliasLine(rawLine) then
                out[#out + 1] = rawLine
            end
        else
            out[#out + 1] = rawLine
        end
    end

    if inTarget then
        insertNewLines()
    elseif currentBossIndex < bossIndex then
        if #out > 0 and Trim(out[#out]) ~= "" then
            out[#out + 1] = ""
        end
        out[#out + 1] = "[" .. (Trim(bossName) ~= "" and Trim(bossName) or ("BOSS" .. tostring(bossIndex))) .. "]"
        insertNewLines()
    end

    while #out > 0 and out[#out] == "" do
        out[#out] = nil
    end
    return table.concat(out, "\n")
end

function RP:SaveBossLayout(bossIndex, layout)
    local db = EnsureDB()
    local parsed = self:GetParsed()
    bossIndex = tonumber(bossIndex or db.activeBossIndex) or 1
    local boss = parsed.bosses and parsed.bosses[bossIndex] or nil
    local bossName = boss and boss.name or ("BOSS" .. tostring(bossIndex))
    local lines = BuildBossLinesFromLayout(layout, boss)
    db.sourceText = ReplaceBossBlock(db.sourceText or "", bossIndex, bossName, lines)
    if type(STT_DB) == "table" and STT_DB.rosterPlanner then
        STT_DB.rosterPlanner.sourceText = db.sourceText
        STT_DB.rosterPlanner.groupLayout = nil
    end
    self:RecomputeParsed("boss_layout")
    return true
end

function RP:GetPlayerRosterKey(parsed)
    parsed = parsed or self:GetParsed()
    local playerName = ReadUnitName("player")
    if not playerName then
        return nil
    end
    return parsed.aliasToKey and parsed.aliasToKey[NormalizeName(playerName)] or playerName
end

function RP:GetBossStatusForPlayer(parsed, boss, playerKey)
    if not boss or not playerKey then
        return "none"
    end
    local playerNorm = NormalizeName(playerKey)
    local aliases = {}
    local function addAlias(value)
        aliases[NormalizeName(value)] = true
    end
    addAlias(playerKey)
    if parsed.roster and parsed.roster[playerKey] then
        for _, alias in ipairs(parsed.roster[playerKey]) do
            addAlias(alias)
        end
    end
    for _, token in ipairs(boss.mainAll or {}) do
        local key = parsed.aliasToKey and parsed.aliasToKey[NormalizeName(token)] or token
        if NormalizeName(key) == playerNorm or aliases[NormalizeName(token)] then
            return "main"
        end
    end
    for _, token in ipairs(boss.subsAll or {}) do
        local key = parsed.aliasToKey and parsed.aliasToKey[NormalizeName(token)] or token
        if NormalizeName(key) == playerNorm or aliases[NormalizeName(token)] then
            return "sub"
        end
    end
    return "none"
end

local function BuildWantedSet(self, boss, parsed)
    local wanted = {}
    local wantedNames = {}
    for _, token in ipairs(boss.mainAll or {}) do
        local resolved = self:ResolveCharacter(token, parsed)
        local name = resolved.primaryName
        local key = NormalizeName(name)
        if not wanted[key] then
            wanted[key] = true
            wantedNames[#wantedNames + 1] = name
        end
    end
    return wanted, wantedNames
end

local function CanLeadGroup()
    if not IsInGroup or not IsInGroup() then
        return true
    end
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then
        return true
    end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then
        return true
    end
    return false
end

local function GetRaidCombatUnits()
    local units = {}
    for i = 1, 40 do
        local unit = "raid" .. i
        if UnitAffectingCombat and UnitAffectingCombat(unit) then
            units[#units + 1] = UnitName(unit) or unit
        end
    end
    return units
end

local function BuildCurrentRaidState()
    local currentGroup = {}
    local currentPos = {}
    local nameToID = {}
    local groupSize = {}
    for i = 1, 8 do
        groupSize[i] = 0
    end

    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name and subgroup then
            local key = NormalizeName(name)
            groupSize[subgroup] = (groupSize[subgroup] or 0) + 1
            currentGroup[key] = subgroup
            currentPos[key] = groupSize[subgroup]
            nameToID[key] = i
        end
    end
    return currentGroup, currentPos, nameToID, groupSize
end

local function BuildDesiredLayout(list)
    local needGroup = {}
    local needPos = {}
    local duplicates = {}
    local count = 0
    for i = 1, 40 do
        local name = Trim(list and list[i] or "")
        if name ~= "" then
            local key = NormalizeName(name)
            if needGroup[key] then
                duplicates[#duplicates + 1] = name
            else
                needGroup[key] = math.floor((i - 1) / 5) + 1
                needPos[key] = ((i - 1) % 5) + 1
                count = count + 1
            end
        end
    end
    return needGroup, needPos, count, duplicates
end

function RP:ProcessRaidLayoutApply()
    local state = runtime.groupApply
    if not state then
        return
    end
    local combatUnits = GetRaidCombatUnits()
    if #combatUnits > 0 then
        runtime.groupApply = nil
        T.msg(string.format(Text("RP_MSG_GROUP_APPLY_COMBAT", "有人正在战斗，已停止调整小队：%s"), table.concat(combatUnits, "、")))
        Debug("GroupApplyStopCombat units=%s", table.concat(combatUnits, ","))
        return
    end

    local currentGroup, currentPos, nameToID, groupSize = BuildCurrentRaidState()

    if not state.groupsReady then
        local waitForMove = false
        for unit, group in pairs(state.needGroup or {}) do
            if currentGroup[unit] and currentGroup[unit] ~= group and (groupSize[group] or 0) < 5 then
                SetRaidSubgroup(nameToID[unit], group)
                groupSize[currentGroup[unit]] = (groupSize[currentGroup[unit]] or 1) - 1
                groupSize[group] = (groupSize[group] or 0) + 1
                waitForMove = true
            end
        end
        if waitForMove then
            return
        end

        local swapped = {}
        local waitForSwap = false
        for unit, group in pairs(state.needGroup or {}) do
            if not swapped[unit] and currentGroup[unit] and currentGroup[unit] ~= group then
                local target
                for other, otherGroup in pairs(currentGroup) do
                    if not swapped[other] and otherGroup == group and state.needGroup[other] ~= otherGroup then
                        target = other
                        break
                    end
                end
                if target then
                    SwapRaidSubgroup(nameToID[unit], nameToID[target])
                    swapped[unit] = true
                    swapped[target] = true
                    waitForSwap = true
                end
            end
        end
        if waitForSwap then
            return
        end

        state.groupsReady = true
    end

    local swapped = {}
    local waitForPosition = false
    for unit, pos in pairs(state.needPos or {}) do
        if currentPos[unit] and currentPos[unit] ~= pos and nameToID[unit] ~= 1 and not swapped[unit] then
            local bridge
            for other, group in pairs(currentGroup) do
                if group ~= currentGroup[unit] and nameToID[other] ~= 1 and not swapped[other] then
                    bridge = other
                    break
                end
            end

            local target
            for other, otherPos in pairs(currentPos) do
                if currentGroup[other] == currentGroup[unit] and otherPos == pos and nameToID[other] ~= 1 and not swapped[other] then
                    target = other
                    break
                end
            end

            if target and bridge then
                state.lockedUnit[unit] = true
                SwapRaidSubgroup(nameToID[unit], nameToID[bridge])
                SwapRaidSubgroup(nameToID[bridge], nameToID[target])
                SwapRaidSubgroup(nameToID[unit], nameToID[bridge])
                swapped[unit] = true
                swapped[target] = true
                swapped[bridge] = true
                waitForPosition = true
            end
        end
    end
    if waitForPosition then
        return
    end

    runtime.groupApply = nil
    T.msg(Text("RP_MSG_GROUP_APPLY_DONE", "小队阵型调整完成。"))
    Debug("GroupApplyDone slots=%d", tonumber(state.count) or 0)
end

function RP:ApplyRaidLayout(list)
    if self:BlockIfNotDebug() then
        return false
    end
    if not IsInRaid or not IsInRaid() then
        T.msg(Text("RP_MSG_GROUP_APPLY_NOT_RAID", "当前不在团队中，不能调整小队。"))
        return false
    end
    if not SetRaidSubgroup or not SwapRaidSubgroup then
        T.msg(Text("RP_MSG_GROUP_APPLY_API_MISSING", "当前客户端不可用小队调整 API。"))
        return false
    end
    if not CanLeadGroup() then
        T.msg(Text("RP_MSG_NOT_LEADER", "只有团长或助理可以执行阵容邀请。"))
        return false
    end
    local combatUnits = GetRaidCombatUnits()
    if #combatUnits > 0 then
        T.msg(string.format(Text("RP_MSG_GROUP_APPLY_COMBAT", "有人正在战斗，已停止调整小队：%s"), table.concat(combatUnits, "、")))
        return false
    end
    local needGroup, needPos, count, duplicates = BuildDesiredLayout(list)
    if count == 0 then
        T.msg(Text("RP_MSG_GROUP_APPLY_EMPTY", "阵型为空，先读取或填写团队名单。"))
        return false
    end
    if #duplicates > 0 then
        T.msg(string.format(Text("RP_MSG_GROUP_APPLY_DUPLICATE", "阵型里有重复名字，已按第一次出现处理：%s"), table.concat(duplicates, "、")))
    end
    runtime.groupApply = {
        needGroup = needGroup,
        needPos = needPos,
        lockedUnit = {},
        groupsReady = false,
        count = count,
    }
    Debug("GroupApplyStart slots=%d duplicates=%d", count, #duplicates)
    self:ProcessRaidLayoutApply()
    return true
end

local function InviteName(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        return pcall(C_PartyInfo.InviteUnit, name)
    end
    if InviteUnit then
        return pcall(InviteUnit, name)
    end
    return false, "InviteUnitMissing"
end

local function KickName(name)
    if UninviteUnit then
        return pcall(UninviteUnit, name)
    end
    return false, "UninviteUnitMissing"
end

function RP:_InviteNextBatch()
    local state = runtime.invite
    if not state then
        return
    end
    local nowIndex = state.index or 1
    local total = #(state.queue or {})
    if nowIndex > total then
        runtime.invite = nil
        T.msg(string.format(Text("RP_MSG_INVITE_DONE", "阵容邀请完成：已处理 %d 人。"), total))
        Debug("InviteQueueComplete boss=%s total=%d", tostring(state.bossName), total)
        return
    end

    local batchEnd = math.min(total, nowIndex + 3)
    for i = nowIndex, batchEnd do
        local name = state.queue[i]
        local ok, result = InviteName(name)
        Debug("InviteSent boss=%s index=%d name=%s ok=%s result=%s", tostring(state.bossName), i, tostring(name), tostring(ok), tostring(result))
    end
    state.index = batchEnd + 1

    if state.index <= total then
        state.waiting = true
        local runID = state.runID
        C_Timer.After(8, function()
            if runtime.invite and runtime.invite.runID == runID and runtime.invite.waiting == true then
                runtime.invite.waiting = false
                Debug("InviteBatchTimeout boss=%s nextIndex=%d", tostring(runtime.invite.bossName), tonumber(runtime.invite.index) or 0)
                RP:_InviteNextBatch()
            end
        end)
    else
        self:_InviteNextBatch()
    end
end

function RP:GROUP_ROSTER_UPDATE()
    if runtime.groupApply then
        if runtime.groupTimer and runtime.groupTimer.Cancel then
            runtime.groupTimer:Cancel()
        end
        runtime.groupTimer = C_Timer.NewTimer(0.5, function()
            runtime.groupTimer = nil
            if RP and RP.ProcessRaidLayoutApply then
                RP:ProcessRaidLayoutApply()
            end
        end)
    end

    local state = runtime.invite
    if not (state and state.waiting) then
        return
    end
    state.waiting = false
    Debug("InviteBatchRosterUpdate boss=%s nextIndex=%d", tostring(state.bossName), tonumber(state.index) or 0)
    self:_InviteNextBatch()
end

local function BuildDiff(self, boss, parsed)
    local wanted, wantedNames = BuildWantedSet(self, boss, parsed)
    local currentMap, currentList = CollectCurrentGroup()
    local toInvite = {}
    for _, name in ipairs(wantedNames) do
        if not currentMap[NormalizeName(name)] then
            toInvite[#toInvite + 1] = name
        end
    end

    local toKick = {}
    local playerNorm = NormalizeName(ReadUnitName("player") or "")
    for _, entry in ipairs(currentList) do
        local key = NormalizeName(entry.name)
        if key ~= playerNorm and not wanted[key] then
            toKick[#toKick + 1] = entry.name
        end
    end
    return toInvite, toKick
end

local function EnsureKickPopup()
    if StaticPopupDialogs["STT_RP_CONFIRM_KICK"] then
        return
    end
    StaticPopupDialogs["STT_RP_CONFIRM_KICK"] = {
        text = "%s",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            if T.RosterPlanner and T.RosterPlanner._pendingKickConfirm then
                T.RosterPlanner:_RunConfirmedInviteAndKick()
            end
        end,
        OnCancel = function()
            if T.RosterPlanner then
                T.RosterPlanner._pendingKickConfirm = nil
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

function RP:_RunConfirmedInviteAndKick()
    local pending = self._pendingKickConfirm
    self._pendingKickConfirm = nil
    if not pending then
        return
    end
    for _, name in ipairs(pending.toKick or {}) do
        local ok, result = KickName(name)
        Debug("KickSent boss=%s name=%s ok=%s result=%s", tostring(pending.bossName), tostring(name), tostring(ok), tostring(result))
    end
    self:StartInviteQueue(pending.bossName, pending.toInvite)
end

function RP:StartInviteQueue(bossName, toInvite)
    runtime.invite = {
        runID = tostring((GetTime and GetTime()) or time() or 0) .. ":" .. tostring(math.random(1000, 9999)),
        bossName = bossName,
        queue = toInvite or {},
        index = 1,
        waiting = false,
    }
    Debug("InviteQueueStart boss=%s total=%d", tostring(bossName), #(toInvite or {}))
    self:_InviteNextBatch()
end

function RP:InviteForBoss(bossIndex, mode)
    if self:BlockIfNotDebug() then
        return false
    end
    local db = EnsureDB()
    local parsed = self:RecomputeParsed("invite")
    bossIndex = tonumber(bossIndex or db.activeBossIndex) or 1
    local boss = parsed.bosses and parsed.bosses[bossIndex] or nil
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        T.msg(Text("RP_MSG_IN_COMBAT", "战斗中不能执行阵容邀请。"))
        return false
    end
    if not boss then
        T.msg(Text("RP_MSG_NO_BOSS", "没有可邀请的 BOSS 阵容块。"))
        return false
    end
    if not CanLeadGroup() then
        T.msg(Text("RP_MSG_NOT_LEADER", "只有团长或助理可以执行阵容邀请。"))
        return false
    end

    mode = mode or db.inviteMode or "inviteOnly"
    local toInvite, toKick = BuildDiff(self, boss, parsed)
    Debug("InviteDiff boss=%s mode=%s invite=%d kick=%d", tostring(boss.name), tostring(mode), #toInvite, #toKick)

    if mode == "inviteAndKick" and #toKick > 0 and db.confirmKick ~= false then
        EnsureKickPopup()
        self._pendingKickConfirm = {
            bossName = boss.name,
            toInvite = toInvite,
            toKick = toKick,
        }
        local list = table.concat(toKick, "、")
        StaticPopup_Show("STT_RP_CONFIRM_KICK", string.format(Text("RP_MSG_CONFIRM_KICK", "将移出不在当前 BOSS 主力名单内的玩家：\n%s\n\n确认后会先移出这些玩家，再继续邀请缺席主力。"), list))
        return true
    end
    if mode == "inviteAndKick" and #toKick > 0 then
        self._pendingKickConfirm = {
            bossName = boss.name,
            toInvite = toInvite,
            toKick = toKick,
        }
        self:_RunConfirmedInviteAndKick()
        return true
    end

    self:StartInviteQueue(boss.name, toInvite)
    return true
end

function RP:OnFirstLoad()
    EnsureDB()
    self:RecomputeParsed("first_load")
end

function RP:OnEnable()
    if not self:IsFeatureAllowed() then
        local db = EnsureDB()
        db.enabled = false
        if STT_DB and STT_DB.rosterPlanner then
            STT_DB.rosterPlanner.enabled = false
        end
        Debug("BlockedByDebugGate")
        return
    end
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE")
    if T.events and not runtime.bossSelectionRegistered then
        runtime.bossSelectionRegistered = true
        T.events:Register("STT_BOSS_SELECTION_CHANGED", self, function(owner)
            if T.RosterPlannerGUI and T.RosterPlannerGUI.Refresh then
                T.RosterPlannerGUI:Refresh()
            end
            if T.RosterPlannerSubPanel and T.RosterPlannerSubPanel.Refresh then
                T.RosterPlannerSubPanel:Refresh()
            end
            Debug("BossSelectionChanged")
        end)
    end
    Debug("Enabled")
end

function RP:OnDisable()
    runtime.invite = nil
    runtime.groupApply = nil
    if runtime.groupTimer and runtime.groupTimer.Cancel then
        runtime.groupTimer:Cancel()
        runtime.groupTimer = nil
    end
    self._commReady = false
    Debug("Disabled")
end

function RP:RefreshConfig(reason)
    EnsureDB()
    self:RecomputeParsed(reason or "config")
end

end)
