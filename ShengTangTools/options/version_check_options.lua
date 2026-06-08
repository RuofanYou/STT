local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("versionCheck.enabled", function()

-- ════════════════════════════════════════════════════════════════
--  STT 团员版本检测模块
--  通信频道 version，请求/响应通过 T.Comm 发送 table payload
-- ════════════════════════════════════════════════════════════════

local QUERY_TIMEOUT    = 2.0      -- 超时秒数
local COOLDOWN_SECONDS = 5.0      -- 冷却时间
local Version = T.VersionUtil

-- UI 常量
local ROW_HEIGHT       = 26
local HEADER_HEIGHT    = 24
local TABLE_HEIGHT     = 340
local COL_NAME_W       = 180
local COL_VERSION_W    = 160
local COL_STATUS_W     = 130
-- COL_CLASS_W = 剩余

-- 状态枚举与排序权重
local STATUS_LATEST      = "latest"
local STATUS_OUTDATED    = "outdated"
local STATUS_MISSING     = "missing"
local STATUS_OFFLINE     = "offline"

local STATUS_WEIGHT = {
    [STATUS_LATEST]  = 1,
    [STATUS_OUTDATED] = 2,
    [STATUS_MISSING]  = 3,
    [STATUS_OFFLINE]  = 4,
}

local STATUS_COLORS = {
    [STATUS_LATEST]   = { 0.3,  0.9,  0.3,  1 },
    [STATUS_OUTDATED] = { 0.95, 0.76, 0.2,  1 },
    [STATUS_MISSING]  = { 0.85, 0.3,  0.3,  1 },
    [STATUS_OFFLINE]  = { 0.5,  0.5,  0.5,  1 },
}

local HEADER_COLOR     = { 1, 0.86, 0.32, 1 }
local ROW_BG_EVEN      = { 0.15, 0.15, 0.15, 0.25 }
local ROW_BG_HOVER     = { 0.3, 0.28, 0.15, 0.35 }
local NAME_ID_COLOR    = { 0.55, 0.55, 0.55 }

-- ── 运行时状态 ──
local commFrame        = nil
local resultMap        = {}    -- fullName → entry
local entryByFullName  = {}
local entryByShortName = {}
local versionCache     = {}    -- fullName → version
local sortedResults    = {}    -- 排序后数组
local highestVersion   = nil
local isScanning       = false
local scanTimer        = nil
local targetedQueryTimer = nil
local lastScanTime     = 0
local currentScanID    = nil
local uiRefreshCb      = nil   -- 绑定 UI 刷新回调

-- ── 工具函数 ──
local function IsInAnyGroup()
    local home = LE_PARTY_CATEGORY_HOME or 1
    local instance = LE_PARTY_CATEGORY_INSTANCE or 2
    return (IsInRaid and (IsInRaid(home) or IsInRaid(instance) or IsInRaid()))
        or (IsInGroup and (IsInGroup(home) or IsInGroup(instance) or IsInGroup()))
end

local function IsInAnyRaid()
    local home = LE_PARTY_CATEGORY_HOME or 1
    local instance = LE_PARTY_CATEGORY_INSTANCE or 2
    return IsInRaid and (IsInRaid(home) or IsInRaid(instance) or IsInRaid())
end

local function ShortName(fullName)
    return Ambiguate(fullName or "", "short")
end

local function BuildFullName(name, realm)
    if T.Comm and T.Comm.NormalizeName then
        return T.Comm:NormalizeName(name, realm)
    end
    if not name or name == "" then
        return nil
    end
    if name:find("-", 1, true) then
        return name
    end
    realm = realm and realm ~= "" and realm or GetRealmName()
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end

local function FullNameFromUnit(unit)
    if not unit then
        return nil
    end
    return BuildFullName(UnitFullName(unit))
end

local function NormalizeSender(sender)
    if not sender or sender == "" then
        return nil
    end
    return BuildFullName(sender)
end

local function IsTargetSelf(target)
    if not target or target == "" then
        return true
    end
    return T.Comm and T.Comm.IsSelfTarget and T.Comm:IsSelfTarget(target) == true
end

local function GetClassColor(classFile)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 0.7, 0.7, 0.7
end

local function NormalizeNickname(value)
    if type(value) ~= "string" then
        return nil
    end
    local nickname = strtrim(value)
    return nickname ~= "" and nickname or nil
end

local function EscapeInlineText(value)
    local escaped = tostring(value or ""):gsub("|", "||")
    return escaped
end

local function ColorText(text, r, g, b)
    local red = math.floor(math.max(0, math.min(1, r or 1)) * 255 + 0.5)
    local green = math.floor(math.max(0, math.min(1, g or 1)) * 255 + 0.5)
    local blue = math.floor(math.max(0, math.min(1, b or 1)) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x%s|r", red, green, blue, EscapeInlineText(text))
end

local function FormatDisplayName(entry)
    local name = entry and entry.name or ""
    local nickname = entry and not entry.fromCache and NormalizeNickname(entry.nickname)
    if not nickname then
        return EscapeInlineText(name)
    end
    local cr, cg, cb = GetClassColor(entry.classFile)
    local nr = NAME_ID_COLOR[1]
    local ng = NAME_ID_COLOR[2]
    local nb = NAME_ID_COLOR[3]
    return string.format("%s%s", ColorText(nickname, cr, cg, cb), ColorText("（" .. name .. "）", nr, ng, nb))
end

local function StatusText(status)
    if status == STATUS_LATEST then
        return L["VERSION_CHECK_STATUS_LATEST"] or "最新"
    elseif status == STATUS_OUTDATED then
        return L["VERSION_CHECK_STATUS_OUTDATED"] or "过时"
    elseif status == STATUS_MISSING then
        return L["VERSION_CHECK_STATUS_NOT_INSTALLED"] or "未安装"
    elseif status == STATUS_OFFLINE then
        return L["VERSION_CHECK_STATUS_OFFLINE"] or "离线"
    end
    return ""
end

-- ── 数据层 ──

local function CollectRoster()
    local roster = {}
    if IsInAnyRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local name, _, _, _, _, classFile, _, online = GetRaidRosterInfo(i)
            local fullName = FullNameFromUnit(unit) or BuildFullName(name)
            if fullName then
                roster[#roster + 1] = {
                    name     = ShortName(fullName),
                    fullName = fullName,
                    classFile = classFile,
                    online   = online,
                    unitId   = unit,
                    guid     = UnitGUID(unit),
                }
            end
        end
    elseif IsInAnyGroup() then
        -- 自己
        local _, myClass = UnitClass("player")
        local myFullName = FullNameFromUnit("player") or BuildFullName(UnitName("player"), GetRealmName())
        roster[#roster + 1] = {
            name      = ShortName(myFullName),
            fullName  = myFullName,
            classFile = myClass,
            online    = true,
            unitId    = "player",
            guid      = UnitGUID("player"),
        }
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local fullName = FullNameFromUnit(unit)
            if fullName then
                local _, classFile = UnitClass(unit)
                roster[#roster + 1] = {
                    name      = ShortName(fullName),
                    fullName  = fullName,
                    classFile = classFile,
                    online    = UnitIsConnected(unit),
                    unitId    = unit,
                    guid      = UnitGUID(unit),
                }
            end
        end
    end
    return roster
end

local function DetermineStatus(ver)
    if not ver then return STATUS_MISSING end
    if Version.GreaterOrEqual(ver, highestVersion) then return STATUS_LATEST end
    return STATUS_OUTDATED
end

local function SortResults()
    sortedResults = {}
    for _, entry in pairs(resultMap) do
        sortedResults[#sortedResults + 1] = entry
    end
    table.sort(sortedResults, function(a, b)
        local wa = STATUS_WEIGHT[a.status] or 9
        local wb = STATUS_WEIGHT[b.status] or 9
        if wa ~= wb then return wa < wb end
        return (a.name or "") < (b.name or "")
    end)
end

local function GetSummary()
    local total, installed, latest, outdated, missing = 0, 0, 0, 0, 0
    for _, entry in pairs(resultMap) do
        if entry.status ~= STATUS_OFFLINE then
            total = total + 1
        else
            total = total + 1
        end
        if entry.status == STATUS_LATEST then
            installed = installed + 1
            latest = latest + 1
        elseif entry.status == STATUS_OUTDATED then
            installed = installed + 1
            outdated = outdated + 1
        elseif entry.status == STATUS_MISSING then
            missing = missing + 1
        end
    end
    return total, installed, latest, outdated, missing
end

local function RefreshUI()
    if type(uiRefreshCb) == "function" then
        uiRefreshCb()
    end
end

local function RebuildLookup()
    entryByFullName = {}
    entryByShortName = {}
    for fullName, entry in pairs(resultMap) do
        entryByFullName[fullName] = entry
        local shortName = entry.name
        if shortName and shortName ~= "" then
            if entryByShortName[shortName] then
                entryByShortName[shortName] = false
            else
                entryByShortName[shortName] = entry
            end
        end
    end
end

local function FindEntryBySender(sender)
    local fullName = NormalizeSender(sender)
    if fullName and entryByFullName[fullName] then
        return entryByFullName[fullName]
    end

    local entry = entryByShortName[ShortName(sender)]
    if entry then
        return entry
    end
    return nil
end

local function UpdateHighest(version)
    highestVersion = Version.Max(highestVersion, version)
end

local function ApplyVersion(entry, version, fromCache)
    if not (entry and version and version ~= "") then
        return
    end
    entry.version = version
    entry.fromCache = fromCache == true
    if entry.fullName then
        versionCache[entry.fullName] = version
    end
    UpdateHighest(version)
end

local function ApplyNickname(entry, nickname)
    nickname = NormalizeNickname(nickname)
    if entry and nickname and not entry.fromCache then
        entry.nickname = nickname
    end
end

local function RefreshStatuses()
    highestVersion = T.Version
    for _, entry in pairs(resultMap) do
        if entry.version then
            UpdateHighest(entry.version)
        end
    end
    for _, entry in pairs(resultMap) do
        if entry.version then
            entry.status = DetermineStatus(entry.version)
        end
    end
end

-- ── 通信层 ──
local function TargetLabel(target)
    if type(target) == "table" then
        return target.name or target.target or target.type
    end
    return target
end

local function FormatNameList(list, limit)
    if type(list) ~= "table" or #list <= 0 then
        return "-"
    end
    limit = tonumber(limit) or 6
    local parts = {}
    for i = 1, math.min(#list, limit) do
        parts[#parts + 1] = tostring(list[i])
    end
    if #list > limit then
        parts[#parts + 1] = "+" .. tostring(#list - limit)
    end
    return table.concat(parts, ",")
end

local function CollectMissingVersionTargets()
    local missing = {}
    for fullName, entry in pairs(resultMap) do
        if entry and entry.status == STATUS_MISSING then
            missing[#missing + 1] = fullName
        end
    end
    table.sort(missing)
    return missing
end

local function SendCommand(cmd, payload, target, opts)
    if not (T.Comm and cmd) then
        return false
    end
    opts = opts or {}
    opts.target = target
    opts.prio = opts.prio or "NORMAL"
    local ok, err = T.Comm:Send("version", cmd, payload, opts)
    if not ok and T.debug then
        T.debug(string.format("[VersionCheck] Send failed cmd=%s target=%s err=%s", tostring(cmd), tostring(TargetLabel(target)), tostring(err)))
    end
    return ok == true
end

local function CancelTimer(timer)
    if timer and timer.Cancel then
        timer:Cancel()
    end
end

local function SendTargetedQueryFallback(scanID, myFullName, roster)
    if currentScanID ~= scanID then
        return
    end
    for _, info in ipairs(roster or {}) do
        if info.online and info.fullName ~= myFullName then
            local entry = resultMap[info.fullName]
            if entry and not entry.version and entry.status ~= STATUS_OFFLINE then
                SendCommand("query", {
                    scanID = scanID,
                    requester = myFullName,
                    expected = { info.fullName },
                }, { type = "player", name = info.fullName }, {
                    reliable = false,
                    timeout = QUERY_TIMEOUT,
                    minInterval = 0,
                    coalesce = false,
                    allowRelay = true,
                    preferWhisper = true,
                    backupRelay = true,
                    ensureID = true,
                })
                if T.debug then
                    T.debug(string.format("[VersionCheck] QueryFallback target=%s scanID=%s", tostring(info.fullName), tostring(scanID)))
                end
            end
        end
    end
end

local function OnReply(payload, sender)
    if type(payload) ~= "table" then return end
    if payload.target and not IsTargetSelf(payload.target) then
        if T.debug then
            T.debug(string.format("[VersionCheck] ReplyIgnored sender=%s target=%s reason=not_for_me", tostring(sender), tostring(payload.target)))
        end
        return
    end
    if currentScanID and payload.scanID and tostring(payload.scanID) ~= tostring(currentScanID) then
        if T.debug then
            T.debug(string.format("[VersionCheck] ReplyIgnored sender=%s scanID=%s current=%s reason=stale", tostring(sender), tostring(payload.scanID), tostring(currentScanID)))
        end
        return
    end
    local ver = payload.version
    local entry = ver and FindEntryBySender(sender)
    if entry then
        ApplyVersion(entry, ver, false)
        ApplyNickname(entry, payload.nickname)
        RefreshStatuses()
        SortResults()
        RefreshUI()
        if T.debug then
            T.debug(string.format("[VersionCheck] ReplyApplied sender=%s version=%s scanID=%s", tostring(sender), tostring(ver), tostring(payload.scanID)))
        end
    elseif T.debug then
        T.debug(string.format("[VersionCheck] ReplyUnmatched sender=%s target=%s version=%s scanID=%s", tostring(sender), tostring(payload.target), tostring(ver), tostring(payload.scanID)))
    end
end

local function OnSummary(payload, sender)
    if T.debug then
        T.debug(string.format("[VersionCheck] SummaryReceived sender=%s total=%s installed=%s", tostring(sender), tostring(payload and payload.total), tostring(payload and payload.installed)))
    end
end

local function EnsureCommReady()
    if commFrame then return end

    if not T.Comm then return end
    local ok, err = T.Comm:Register("version", "reply", OnReply)
    if ok then
        ok, err = T.Comm:Register("version", "summary", OnSummary)
    end
    if not ok then
        if T.debug then
            T.debug("[VersionCheck] CommRegisterFailed err=" .. tostring(err))
        end
        return
    end
    commFrame = true
end

EnsureCommReady()

-- ── 扫描逻辑 ──

local VersionCheck = {}
T.VersionCheck = VersionCheck

function VersionCheck:StartScan()
    -- 前置检查
    if not IsInAnyGroup() then
        T.msg(L["VERSION_CHECK_NOT_IN_GROUP"] or "需要在队伍或团队中使用")
        return false
    end
    if InCombatLockdown() then
        T.msg("战斗中无法使用")
        return false
    end
    local now = GetTime()
    if now - lastScanTime < COOLDOWN_SECONDS then
        return false
    end

    EnsureCommReady()

    -- 重置状态
    lastScanTime = now
    isScanning = true
    resultMap = {}
    sortedResults = {}
    highestVersion = T.Version

    -- 收集名单
    local roster = CollectRoster()
    local myFullName = FullNameFromUnit("player") or BuildFullName(UnitName("player"), GetRealmName())
    local scanID = tostring(math.floor((GetTime and GetTime() or 0) * 1000))
    currentScanID = scanID

    for _, info in ipairs(roster) do
        local entry = {
            name      = info.name,
            fullName  = info.fullName,
            guid      = info.guid,
            classFile = info.classFile,
            version   = nil,
            status    = info.online and STATUS_MISSING or STATUS_OFFLINE,
            unitId    = info.unitId,
        }
        -- 自己直接填入版本
        if info.fullName == myFullName then
            ApplyVersion(entry, T.Version, false)
            ApplyNickname(entry, C and C.DB and C.DB.mynickname)
            entry.status = STATUS_LATEST
        elseif info.online and versionCache[info.fullName] then
            ApplyVersion(entry, versionCache[info.fullName], true)
        end
        resultMap[info.fullName] = entry
    end

    RebuildLookup()
    RefreshStatuses()
    SortResults()
    RefreshUI()

    -- 发现类通信走团队广播，避免跨服点名和聊天权限造成误判。
    local expected = {}
    for _, info in ipairs(roster) do
        if info.online and info.fullName ~= myFullName then
            expected[#expected + 1] = info.fullName
        end
    end
    if #expected > 0 then
        if T.debug then
            T.debug(string.format("[VersionCheck] QueryStart scanID=%s expected=%d targets=%s", tostring(scanID), #expected, FormatNameList(expected)))
        end
        SendCommand("query", {
            scanID = scanID,
            requester = myFullName,
            expected = expected,
        }, "group", {
            reliable = false,
            timeout = QUERY_TIMEOUT,
            minInterval = 0.5,
            coalesce = true,
        })
    end

    -- 超时后刷新最终结果
    CancelTimer(scanTimer)
    CancelTimer(targetedQueryTimer)
    targetedQueryTimer = C_Timer.NewTimer(0.6, function()
        targetedQueryTimer = nil
        SendTargetedQueryFallback(scanID, myFullName, roster)
    end)
    scanTimer = C_Timer.NewTimer(QUERY_TIMEOUT, function()
        isScanning = false
        targetedQueryTimer = nil
        RefreshStatuses()
        SortResults()
        RefreshUI()
        local total, installed, latest, outdated, missing = GetSummary()
        if T.debug then
            local missingTargets = CollectMissingVersionTargets()
            T.debug(string.format("[VersionCheck] Summary scanID=%s total=%d installed=%d latest=%d outdated=%d missing=%d missingList=%s", tostring(scanID), total, installed, latest, outdated, missing, FormatNameList(missingTargets)))
        end
    end)

    return true
end

-- ── UI 渲染 ──

local function RenderVersionCheck(parent, context)
    local width = context.width
    local totalHeight = 0

    -- ─ 操作区 ─
    local actionBar = CreateFrame("Frame", nil, parent)
    actionBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    actionBar:SetSize(width, 36)
    totalHeight = totalHeight + 36

    local scanBtn = T.CreateButton(actionBar, {
        width = 160,
        height = 28,
        point = { "LEFT", actionBar, "LEFT", 0, 0 },
        text = L["VERSION_CHECK_BUTTON"] or "检测版本",
    })

    local summaryText = T.CreateFontString(actionBar, {
        layer = "OVERLAY",
        template = "GameFontNormal",
        point = { "RIGHT", actionBar, "RIGHT", 0, 0 },
        size = 11,
        color = { 0.72, 0.72, 0.72, 1 },
        justifyH = "RIGHT",
        text = "",
    })

    -- 提示文字（无数据时居中显示）
    local hintText = T.CreateFontString(parent, {
        layer = "OVERLAY",
        template = "GameFontNormal",
        size = 12,
        color = { 0.6, 0.6, 0.6, 1 },
        justifyH = "CENTER",
        text = L["VERSION_CHECK_HINT"] or "点击检测按钮查询团队成员的 STT 安装情况",
    })
    hintText:SetPoint("TOP", actionBar, "BOTTOM", 0, -80)
    hintText:SetWidth(width)

    -- ─ 表头 ─
    local colClassW = math.max(80, width - COL_NAME_W - COL_VERSION_W - COL_STATUS_W)

    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", actionBar, "BOTTOMLEFT", 0, -8)
    header:SetSize(width, HEADER_HEIGHT)
    header:Hide()
    totalHeight = totalHeight + 8 + HEADER_HEIGHT

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.12, 0.12, 0.12, 0.4)

    local function MakeHeaderLabel(parentFrame, text, xOffset, colWidth)
        local fs = T.CreateFontString(parentFrame, {
            layer = "OVERLAY",
            template = "GameFontNormal",
            size = 11,
            color = HEADER_COLOR,
            justifyH = "LEFT",
            text = text,
        })
        fs:SetPoint("LEFT", parentFrame, "LEFT", xOffset + 8, 0)
        fs:SetWidth(colWidth - 8)
        return fs
    end

    local xOff = 0
    MakeHeaderLabel(header, L["VERSION_CHECK_COL_NAME"] or "角色名", xOff, COL_NAME_W)
    xOff = xOff + COL_NAME_W
    MakeHeaderLabel(header, L["VERSION_CHECK_COL_VERSION"] or "版本号", xOff, COL_VERSION_W)
    xOff = xOff + COL_VERSION_W
    MakeHeaderLabel(header, L["VERSION_CHECK_COL_STATUS"] or "状态", xOff, COL_STATUS_W)
    xOff = xOff + COL_STATUS_W
    MakeHeaderLabel(header, L["VERSION_CHECK_COL_CLASS"] or "职业", xOff, colClassW)

    -- 表头底部分割线
    local headerLine = header:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3], 0.3)

    -- ─ VirtualScroll 表体 ─
    local scrollHeight = math.min(TABLE_HEIGHT, ROW_HEIGHT * 40)

    local scroll = T.CreateVirtualScroll(parent, {
        rowHeight = ROW_HEIGHT,
    })
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    scroll:SetSize(width, scrollHeight)
    scroll:Hide()
    totalHeight = totalHeight + scrollHeight

    -- 行工厂
    scroll:SetRowFactory(function(scrollContent)
        local row = CreateFrame("Frame", nil, scrollContent)
        row:SetHeight(ROW_HEIGHT)

        -- 背景
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0, 0, 0, 0)

        -- 悬停高亮
        row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(ROW_BG_HOVER[1], ROW_BG_HOVER[2], ROW_BG_HOVER[3], ROW_BG_HOVER[4])
        row.highlight:Hide()

        -- 列：角色名
        row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameFs:SetFont(row.nameFs:GetFont(), 11, "")
        row.nameFs:SetJustifyH("LEFT")
        row.nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.nameFs:SetWidth(COL_NAME_W - 8)
        row.nameFs:SetWordWrap(false)

        -- 列：版本号
        row.versionFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.versionFs:SetFont(row.versionFs:GetFont(), 11, "")
        row.versionFs:SetJustifyH("LEFT")
        row.versionFs:SetPoint("LEFT", row, "LEFT", COL_NAME_W + 8, 0)
        row.versionFs:SetWidth(COL_VERSION_W - 8)
        row.versionFs:SetWordWrap(false)

        -- 列：状态
        row.statusFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.statusFs:SetFont(row.statusFs:GetFont(), 11, "")
        row.statusFs:SetJustifyH("LEFT")
        row.statusFs:SetPoint("LEFT", row, "LEFT", COL_NAME_W + COL_VERSION_W + 8, 0)
        row.statusFs:SetWidth(COL_STATUS_W - 8)
        row.statusFs:SetWordWrap(false)

        -- 列：职业
        row.classFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.classFs:SetFont(row.classFs:GetFont(), 11, "")
        row.classFs:SetJustifyH("LEFT")
        row.classFs:SetPoint("LEFT", row, "LEFT", COL_NAME_W + COL_VERSION_W + COL_STATUS_W + 8, 0)
        row.classFs:SetWidth(colClassW - 8)
        row.classFs:SetWordWrap(false)

        -- 交互层（悬停 + tooltip）
        row.hitArea = CreateFrame("Frame", nil, row)
        row.hitArea:SetAllPoints()
        row.hitArea:EnableMouse(true)
        row.hitArea:SetScript("OnEnter", function()
            row.highlight:Show()
            -- Tooltip
            local entry = row.dataEntry
            if entry then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT", -20, 10)
                local nickname = not entry.fromCache and NormalizeNickname(entry.nickname)
                GameTooltip:AddLine(nickname or entry.fullName or entry.name, 1, 0.92, 0.75)
                if nickname then
                    GameTooltip:AddLine(string.format(L["VERSION_CHECK_TOOLTIP_NICKNAME"] or "昵称：%s", nickname), 1, 0.92, 0.75)
                    GameTooltip:AddLine(string.format(L["VERSION_CHECK_TOOLTIP_CHARACTER"] or "角色：%s", entry.fullName or entry.name or ""), 0.72, 0.72, 0.72)
                end
                if entry.version then
                    GameTooltip:AddLine("v" .. entry.version, 1, 1, 1)
                    if Version.Greater(highestVersion, entry.version) then
                        local days, builds = Version.Diff(highestVersion, entry.version)
                        local hint
                        if days > 0 then
                            hint = string.format(L["VERSION_CHECK_TOOLTIP_BEHIND_DAYS"] or "落后 %d 天", days)
                        elseif builds > 0 then
                            hint = string.format(L["VERSION_CHECK_TOOLTIP_BEHIND_BUILDS"] or "落后 %d 个版本", builds)
                        end
                        if hint then
                            GameTooltip:AddLine(hint, 0.95, 0.76, 0.2)
                        end
                    end
                    if entry.fromCache then
                        GameTooltip:AddLine(L["VERSION_CHECK_TOOLTIP_CACHED"] or "本轮未响应，显示上次检测结果", 0.72, 0.72, 0.72)
                    end
                else
                    GameTooltip:AddLine(StatusText(entry.status), unpack(STATUS_COLORS[entry.status] or { 1, 1, 1, 1 }))
                end
                GameTooltip:Show()
            end
        end)
        row.hitArea:SetScript("OnLeave", function()
            row.highlight:Hide()
            GameTooltip:Hide()
        end)

        return row
    end)

    -- 渲染回调
    scroll:SetRenderCallback(function(row, dataIndex)
        local entry = sortedResults[dataIndex]
        if not entry then
            row:Hide()
            return
        end
        row.dataEntry = entry

        -- 交替行背景
        if dataIndex % 2 == 0 then
            row.bg:SetColorTexture(ROW_BG_EVEN[1], ROW_BG_EVEN[2], ROW_BG_EVEN[3], ROW_BG_EVEN[4])
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        -- 角色名（职业颜色）
        local cr, cg, cb = GetClassColor(entry.classFile)
        row.nameFs:SetText(FormatDisplayName(entry))
        row.nameFs:SetTextColor(cr, cg, cb, 1)

        -- 版本号
        if entry.version then
            row.versionFs:SetText("v" .. entry.version)
            local sc = STATUS_COLORS[entry.status] or { 1, 1, 1, 1 }
            row.versionFs:SetTextColor(sc[1], sc[2], sc[3], 1)
        else
            row.versionFs:SetText("--")
            row.versionFs:SetTextColor(0.5, 0.5, 0.5, 1)
        end

        -- 状态
        local sc = STATUS_COLORS[entry.status] or { 1, 1, 1, 1 }
        local dot = (entry.status == STATUS_OFFLINE) and "○ " or "● "
        row.statusFs:SetText(dot .. StatusText(entry.status))
        row.statusFs:SetTextColor(sc[1], sc[2], sc[3], 1)

        -- 职业名
        if entry.classFile then
            local localizedClass = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[entry.classFile]
            row.classFs:SetText(localizedClass or entry.classFile)
            row.classFs:SetTextColor(cr, cg, cb, 1)
        else
            row.classFs:SetText("--")
            row.classFs:SetTextColor(0.5, 0.5, 0.5, 1)
        end
    end)

    -- ─ UI 刷新逻辑 ─
    local function UpdateUI()
        local hasData = #sortedResults > 0

        hintText:SetShown(not hasData)
        header:SetShown(hasData)
        scroll:SetShown(hasData)

        if hasData then
            -- 动态调整滚动区高度
            local neededHeight = math.min(TABLE_HEIGHT, #sortedResults * ROW_HEIGHT)
            scroll:SetHeight(neededHeight)
            scroll:SetDataCount(#sortedResults)
            scroll:Refresh(true)
        end

        -- 摘要文本
        if hasData then
            local total, installed, latest, outdated, missing = GetSummary()
            summaryText:SetText(string.format(
                L["VERSION_CHECK_SUMMARY"] or "已安装 %d/%d | 最新 %d | 过时 %d | 未安装 %d",
                installed, total, latest, outdated, missing
            ))
        else
            summaryText:SetText("")
        end

        -- 按钮状态
        local inGroup = IsInAnyGroup()
        local inCombat = InCombatLockdown()
        local onCooldown = (GetTime() - lastScanTime) < COOLDOWN_SECONDS

        if not inGroup then
            scanBtn:Disable()
            scanBtn.tooltipText = L["VERSION_CHECK_NOT_IN_GROUP"] or "需要在队伍或团队中使用"
            scanBtn.tooltipWhenDisabledOnly = true
        elseif inCombat then
            scanBtn:Disable()
            scanBtn.tooltipText = "战斗中无法使用"
            scanBtn.tooltipWhenDisabledOnly = true
        elseif isScanning or onCooldown then
            scanBtn:Disable()
            scanBtn:SetText(L["VERSION_CHECK_SCANNING"] or "检测中...")
            scanBtn.tooltipText = nil
        else
            scanBtn:Enable()
            scanBtn:SetText(L["VERSION_CHECK_BUTTON"] or "检测团队版本")
            scanBtn.tooltipText = nil
        end
    end

    uiRefreshCb = UpdateUI

    -- 按钮点击
    scanBtn:SetScript("OnClick", function()
        if VersionCheck:StartScan() then
            UpdateUI()
            -- 冷却结束后恢复按钮
            C_Timer.After(COOLDOWN_SECONDS, UpdateUI)
        end
    end)

    -- 初始状态
    UpdateUI()

    -- 面板每次显示时重新评估按钮状态
    parent:HookScript("OnShow", UpdateUI)

    -- 注册通信（确保即使没有点击按钮也能响应别人的查询）
    EnsureCommReady()

    return { height = totalHeight + 12 }
end

-- ── 注册选项模块 ──

T.RegisterOptionModule({
    id = "versionCheck",
    category = "raidlead",
    order = 5,
    titleKey = "GUI_NAV_VERSION_CHECK",
    itemsFactory = function()
        return {
        {
            key = "versionCheckPanel",
            type = "custom",
            textKey = "GUI_NAV_VERSION_CHECK",
            width = 1,
            height = 420,
            render = RenderVersionCheck,
        },
        }
    end,
})

end)
