local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("raidLead.optionPushAccept", function()

local Share = {}
T.OptionShare = Share

local POPUP_WIDTH = 520
local POPUP_BODY_WIDTH = 472
local POPUP_COLLAPSED_HEIGHT = 270
local POPUP_EXPANDED_HEIGHT = 390
local popupQueue = {}

local BLOCKED_PATHS_EXACT = {
    ttsVoiceID = true,
    debugMode = true,
    ["raidLead.optionPushAccept"] = true,
    ["raidLead.optionPushIgnoredSenders"] = true,
}

local BLOCKED_PREFIXES = {
    "visualBoard.",
    "version.",
    "internal.",
    "_",
}

local ALLOWED_TYPES = {
    check = true,
    slider = true,
    dropdown = true,
}

local function Text(key, fallback)
    if type(key) == "string" and L and L[key] then
        return L[key]
    end
    if fallback ~= nil then
        return fallback
    end
    return type(key) == "string" and key or ""
end

local function Debug(fmt, ...)
    if not T.debug then
        return
    end
    if select("#", ...) > 0 then
        T.debug(string.format("[OptionPush] " .. tostring(fmt), ...))
    else
        T.debug("[OptionPush] " .. tostring(fmt))
    end
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return copy
end

local function ReadPath(root, path, defaultValue)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return defaultValue
    end
    local current = root
    for segment in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return defaultValue
        end
        current = current[segment]
        if current == nil then
            return defaultValue
        end
    end
    return current
end

local function ValuesEqual(left, right, seen)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    seen = seen or {}
    if seen[left] == right then
        return true
    end
    seen[left] = right
    for key, value in pairs(left) do
        if not ValuesEqual(value, right[key], seen) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function CountMap(map)
    local count = 0
    for _ in pairs(map or {}) do
        count = count + 1
    end
    return count
end

local function CountList(list)
    local count = 0
    if type(list) ~= "table" then
        return count
    end
    for index in ipairs(list) do
        count = index
    end
    return count
end

local function FormatValue(value, depth)
    local valueType = type(value)
    if valueType == "boolean" then
        return value and Text("PUSH_VALUE_ON", "开") or Text("PUSH_VALUE_OFF", "关")
    end
    if valueType == "number" or valueType == "string" then
        return tostring(value)
    end
    if valueType ~= "table" then
        return tostring(value)
    end
    local fieldCount = CountMap(value)
    local listCount = CountList(value)
    if listCount > 0 and listCount == fieldCount then
        return string.format("列表（%d 项）", listCount)
    end
    return string.format("配置表（%d 项）", fieldCount)
end

local function GetPlayerFullName()
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    end
    if not name or name == "" then
        name = UnitName and UnitName("player")
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    if GetNormalizedRealmName then
        realm = GetNormalizedRealmName()
        if realm and realm ~= "" then
            return tostring(name) .. "-" .. realm
        end
    end
    return tostring(name or "")
end

local function SameShortName(a, b)
    if not a or not b then
        return false
    end
    local left = Ambiguate and Ambiguate(a, "short") or a
    local right = Ambiguate and Ambiguate(b, "short") or b
    return left ~= "" and left == right
end

local function IsSenderLeaderOrAssistant(sender)
    if not sender or sender == "" then
        return false
    end
    if SameShortName(sender, GetPlayerFullName()) then
        return (UnitIsGroupLeader and UnitIsGroupLeader("player") == true)
            or (UnitIsGroupAssistant and UnitIsGroupAssistant("player") == true)
    end
    if IsInRaid and IsInRaid() then
        for i = 1, MAX_RAID_MEMBERS do
            local name, rank = GetRaidRosterInfo(i)
            if name and SameShortName(sender, name) then
                return rank == 1 or rank == 2
            end
        end
        return false
    end
    if IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name and SameShortName(sender, name) then
                return (UnitIsGroupLeader and UnitIsGroupLeader(unit) == true)
                    or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit) == true)
            end
        end
    end
    return false
end

local function ResolveChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function SendOptionAck(sender, meta, status, detail)
    if not (T.Comm and sender and sender ~= "" and meta and meta.id) then
        return
    end
    T.Comm:Send("optionpush", "ack", {
        replyTo = meta.id,
        status = status,
        detail = detail,
    }, {
        target = { type = "player", name = sender },
        prio = "ALERT",
        allowRelay = true,
        preferWhisper = true,
        backupRelay = true,
        ensureID = true,
    })
end

function Share:EnsureCommReady()
    if self._commReady then
        return true
    end
    if not T.Comm then
        Debug("MissingComm")
        return false
    end
    local ok, err = T.Comm:Register("optionpush", "offer", function(payload, sender, meta)
        self:OnReceive(sender, payload, meta)
    end)
    if ok then
        ok, err = T.Comm:Register("optionpush", "ack", function() end)
    end
    if not ok then
        Debug("CommRegisterFailed err=%s", tostring(err))
        return false
    end
    self._commReady = true
    return true
end

local function EnsureCDB()
    STT_CDB = type(STT_CDB) == "table" and STT_CDB or {}
    STT_CDB.optionPushIgnoredSenders = type(STT_CDB.optionPushIgnoredSenders) == "table" and STT_CDB.optionPushIgnoredSenders or {}
    return STT_CDB
end

function Share:CanPush(silent)
    if not (IsInGroup and IsInGroup()) then
        if not silent then
            T.msg(Text("PUSH_NEED_GROUP", "不在队伍或团队中，无法下发设置。"))
        end
        return false
    end
    local isLead = (UnitIsGroupLeader and UnitIsGroupLeader("player") == true)
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player") == true)
    if not isLead then
        if not silent then
            T.msg(Text("PUSH_NEED_LEADER", "仅团长或团队助理可下发设置。"))
        end
        return false
    end
    return true
end

function Share:IsBlocked(dbPath, itemDef)
    if itemDef and itemDef.noPush == true then
        return true
    end
    if type(dbPath) ~= "string" or dbPath == "" then
        return true
    end
    if BLOCKED_PATHS_EXACT[dbPath] then
        return true
    end
    for _, prefix in ipairs(BLOCKED_PREFIXES) do
        if dbPath:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

function Share:IsPushable(itemDef)
    if type(itemDef) ~= "table" or self:IsBlocked(itemDef.dbPath, itemDef) then
        return false
    end
    if ALLOWED_TYPES[itemDef.type] == true then
        return true
    end
    return itemDef.type == "custom" and itemDef.optionPush == true
end

function Share:IsSenderIgnored(sender)
    local cdb = EnsureCDB()
    return sender and cdb.optionPushIgnoredSenders[sender] == true
end

function Share:AddIgnoredSender(sender)
    if not sender or sender == "" then
        return
    end
    local cdb = EnsureCDB()
    cdb.optionPushIgnoredSenders[sender] = true
end

function Share:ResetIgnored()
    local cdb = EnsureCDB()
    cdb.optionPushIgnoredSenders = {}
    T.msg(Text("PUSH_RESET_DONE", "已清空设置下发忽略名单。"))
end

local function GetModuleLabel(moduleDef)
    if not moduleDef then
        return ""
    end
    return Text(moduleDef.titleKey, moduleDef.id)
end

local function GetItemLabel(itemDef)
    if not itemDef then
        return ""
    end
    return Text(itemDef.textKey, itemDef.text or itemDef.key or itemDef.dbPath)
end

local function BuildItemPayload(itemDef, moduleDef)
    local engine = T.OptionEngine
    if not (engine and Share:IsPushable(itemDef)) then
        return nil
    end
    local value = engine:GetItemValue(itemDef)
    local moduleLabel = GetModuleLabel(moduleDef)
    local itemLabel = GetItemLabel(itemDef)
    return {
        v = T.Version or "0",
        sender = GetPlayerFullName(),
        mode = "item",
        moduleId = moduleDef and moduleDef.id or nil,
        label = moduleLabel .. " > " .. itemLabel,
        entries = {
            [itemDef.dbPath] = DeepCopy(value),
        },
        labels = {
            [itemDef.dbPath] = itemLabel,
        },
    }
end

local function AddEntry(payload, itemDef, moduleDef)
    if not Share:IsPushable(itemDef) then
        return
    end
    local engine = T.OptionEngine
    if not engine then
        return
    end
    payload.entries[itemDef.dbPath] = DeepCopy(engine:GetItemValue(itemDef))
    payload.labels[itemDef.dbPath] = GetItemLabel(itemDef)
end

local function BuildModulePayload(moduleDef)
    if not moduleDef then
        return nil
    end
    local moduleLabel = GetModuleLabel(moduleDef)
    local payload = {
        v = T.Version or "0",
        sender = GetPlayerFullName(),
        mode = "module",
        moduleId = moduleDef.id,
        label = moduleLabel,
        entries = {},
        labels = {},
    }
    if moduleDef.masterToggle and moduleDef.masterToggle.dbPath then
        AddEntry(payload, {
            key = "__master_toggle",
            type = "check",
            text = Text("GUI_LABEL_ENABLED", "启用"),
            dbPath = moduleDef.masterToggle.dbPath,
            default = moduleDef.masterToggle.default,
            apply = moduleDef.masterToggle.apply,
        }, moduleDef)
    end
    for _, itemDef in ipairs(T.GetOptionModuleItems and T.GetOptionModuleItems(moduleDef, T.OptionEngine) or moduleDef.items or {}) do
        AddEntry(payload, itemDef, moduleDef)
    end
    if CountMap(payload.entries) <= 0 then
        return nil
    end
    return payload
end

function Share:SendPayload(payload)
    if not self:CanPush(false) then
        return false
    end
    if not self:EnsureCommReady() then
        T.msg(Text("PUSH_SEND_FAILED", "设置下发失败：通信接口不可用。"))
        return false
    end
    local channel = ResolveChannel()
    if not channel then
        T.msg(Text("PUSH_NEED_GROUP", "不在队伍或团队中，无法下发设置。"))
        return false
    end
    local ok, err = T.Comm:Send("optionpush", "offer", payload, {
        deferInCombat = true,
        queueKey = "optionpush:" .. tostring(payload.moduleId or payload.label or payload.mode),
        onAck = function(ackPayload, sender, _, terminal)
            local detail = ackPayload and ackPayload.detail
            Debug(
                "OfferAck label=%s sender=%s status=%s terminal=%s detail=%s",
                tostring(payload.label),
                tostring(sender),
                tostring(ackPayload and ackPayload.status),
                tostring(terminal),
                type(detail) == "table" and ("table:" .. tostring(CountMap(detail))) or tostring(detail)
            )
        end,
        onTimeout = function(entry)
            Debug("OfferTimeout label=%s id=%s missing=%d", tostring(payload.label), tostring(entry and entry.envelope and entry.envelope.id), #(entry and entry.missingAcks or {}))
        end,
    })
    if not ok then
        T.msg(Text("PUSH_SEND_FAILED", "设置下发失败：通信接口不可用。"))
        Debug("SendFailed err=%s", tostring(err))
        return false
    end
    local count = CountMap(payload.entries)
    T.msg(string.format(Text("PUSH_SENT", "已下发设置：%s（%d 项）。"), tostring(payload.label or ""), count))
    Debug("STT_OPT_PUSH_SEND mode=%s label=%s entryCount=%d channel=%s", tostring(payload.mode), tostring(payload.label), count, tostring(channel))
    return true
end

function Share:OnShiftClick(itemDef, moduleDef)
    if not self:IsPushable(itemDef) then
        T.msg(Text("PUSH_NOT_PUSHABLE", "此设置不支持下发。"))
        return false
    end
    local payload = BuildItemPayload(itemDef, moduleDef)
    if not payload then
        T.msg(Text("PUSH_NO_ITEMS", "该模块无可下发设置。"))
        return false
    end
    return self:SendPayload(payload)
end

function Share:OnNavShiftClick(moduleId)
    local moduleDef = T.OptionEngine and T.OptionEngine:GetModuleById(moduleId)
    local payload = BuildModulePayload(moduleDef)
    if not payload then
        T.msg(Text("PUSH_NO_ITEMS", "该模块无可下发设置。"))
        return false
    end
    return self:SendPayload(payload)
end

function Share:FindItemByPath(dbPath)
    for _, moduleDef in ipairs(T.OptionDefinitions or {}) do
        if moduleDef.masterToggle and moduleDef.masterToggle.dbPath == dbPath then
            return {
                moduleDef = moduleDef,
                itemDef = {
                    key = "__master_toggle",
                    type = "check",
                    text = Text("GUI_LABEL_ENABLED", "启用"),
                    dbPath = moduleDef.masterToggle.dbPath,
                    default = moduleDef.masterToggle.default,
                    apply = moduleDef.masterToggle.apply,
                },
            }
        end
        for _, itemDef in ipairs(T.GetOptionModuleItems and T.GetOptionModuleItems(moduleDef, T.OptionEngine) or moduleDef.items or {}) do
            if itemDef.dbPath == dbPath then
                return { moduleDef = moduleDef, itemDef = itemDef }
            end
        end
    end
    return nil
end

function Share:BuildReceiveContext(sender, payload, meta)
    if type(payload) ~= "table" or type(payload.entries) ~= "table" then
        return nil, "bad_payload"
    end
    local entries = {}
    local unknown = {}
    local labels = type(payload.labels) == "table" and payload.labels or {}
    for dbPath, value in pairs(payload.entries) do
        local match = self:FindItemByPath(dbPath)
        if match and self:IsPushable(match.itemDef) then
            local oldValue = T.OptionEngine and T.OptionEngine:GetItemValue(match.itemDef) or ReadPath(C.DB, dbPath)
            if not ValuesEqual(oldValue, value) then
                entries[#entries + 1] = {
                    dbPath = dbPath,
                    value = value,
                    oldValue = oldValue,
                    label = labels[dbPath] or GetItemLabel(match.itemDef),
                    itemDef = match.itemDef,
                    moduleDef = match.moduleDef,
                }
            end
        else
            unknown[#unknown + 1] = {
                dbPath = dbPath,
                value = value,
                label = labels[dbPath] or dbPath,
            }
        end
    end
    table.sort(entries, function(a, b)
        return tostring(a.label) < tostring(b.label)
    end)
    table.sort(unknown, function(a, b)
        return tostring(a.label) < tostring(b.label)
    end)
    local screenImport
    local personalAuraImport
    for _, entry in ipairs(entries) do
        local builder = T.ScreenReminderOptionPush and T.ScreenReminderOptionPush.BuildImport
        local import = builder and builder(entry.value, entry.dbPath)
        if import then
            import.dbPath = entry.dbPath
            import.label = payload.label or entry.label
            screenImport = import
            if import.kind == "full" then
                break
            end
        end
        local personalBuilder = T.PersonalAuraAlertOptionPush and T.PersonalAuraAlertOptionPush.BuildImport
        local personalImport = personalBuilder and personalBuilder(entry.value, entry.dbPath)
        if personalImport then
            personalImport.dbPath = entry.dbPath
            personalImport.label = payload.label or entry.label
            personalAuraImport = personalImport
            if personalImport.kind == "full" then
                break
            end
        end
    end
    if screenImport then
        entries = {
            {
                dbPath = screenImport.dbPath,
                value = screenImport.value,
                oldValue = "本地屏幕提醒",
                label = screenImport.label,
                screenReminderImport = true,
            },
        }
        unknown = {}
    elseif personalAuraImport then
        entries = {
            {
                dbPath = personalAuraImport.dbPath,
                value = personalAuraImport.value,
                oldValue = "本地个人光环提醒",
                label = personalAuraImport.label,
                personalAuraImport = true,
            },
        }
        unknown = {}
    end
    return {
        sender = sender,
        payload = payload,
        commMeta = meta,
        entries = entries,
        unknown = unknown,
        screenReminderImport = screenImport,
        personalAuraImport = personalAuraImport,
        expanded = false,
    }
end

local function BuildDiffText(context, expanded)
    if context and context.screenReminderImport then
        local value = context.screenReminderImport.value
        local sourceList = type(value) == "table" and type(value.indicators) == "table" and value.indicators or { value }
        local sourceCount = 0
        local conflictCount = 0
        local lines = {}
        local localNames = {}
        local root = T.ScreenReminderSchema and T.ScreenReminderSchema.GetRoot and T.ScreenReminderSchema.GetRoot()
        for _, ind in ipairs(type(root and root.indicators) == "table" and root.indicators or {}) do
            localNames[tostring(ind.name or "")] = true
        end
        for _, ind in ipairs(sourceList) do
            if type(ind) == "table" then
                sourceCount = sourceCount + 1
                local name = tostring(ind.name or "未命名样式")
                local conflict = localNames[name] == true
                if conflict then
                    conflictCount = conflictCount + 1
                end
                if expanded and #lines < 8 then
                    lines[#lines + 1] = string.format("%s%s", name, conflict and "（本地同名）" or "")
                end
            end
        end
        local header = {
            string.format("导入样式：%d 条；本地同名：%d 条", sourceCount, conflictCount),
            "合并：同名生成副本；替换：同名直接覆盖。",
        }
        if type(value) == "table" and type(value.indicators) == "table" then
            header[#header + 1] = string.format("全局提前量：%s -> %s",
                tostring(root and root.globalLeadTimeSec),
                tostring(value.globalLeadTimeSec))
        end
        if expanded then
            if #lines > 0 then
                header[#header + 1] = "样式列表："
                for _, line in ipairs(lines) do
                    header[#header + 1] = " - " .. line
                end
            end
            if sourceCount > #lines then
                header[#header + 1] = string.format("还有 %d 条未显示", sourceCount - #lines)
            end
        end
        return table.concat(header, "\n")
    end
    if context and context.personalAuraImport then
        local import = context.personalAuraImport
        if type(import.buildDiffText) == "function" then
            return import.buildDiffText(import.value, expanded)
        end
        return "个人光环提醒规则导入"
    end

    local lines = {}
    local entries = context.entries or {}
    local unknown = context.unknown or {}
    local limit = expanded and 18 or 4
    for i = 1, math.min(#entries, limit) do
        local entry = entries[i]
        lines[#lines + 1] = string.format("%s: %s -> %s", tostring(entry.label), FormatValue(entry.oldValue), FormatValue(entry.value))
    end
    for i = 1, math.min(#unknown, math.max(0, limit - #lines)) do
        local entry = unknown[i]
        lines[#lines + 1] = string.format("%s: %s", tostring(entry.label), Text("PUSH_UNKNOWN_PATH", "未识别项，不会应用"))
    end
    local remaining = #entries + #unknown - #lines
    if remaining > 0 then
        lines[#lines + 1] = string.format(Text("PUSH_MORE_CHANGES", "还有 %d 项未展开显示"), remaining)
    end
    return table.concat(lines, "\n")
end

local function ShortLabel(label)
    local value = tostring(label or "")
    value = value:gsub("^屏幕提醒%s*>%s*", "")
    value = value:gsub("^个人光环提醒%s*>%s*", "")
    return value
end

local function ApplyTextColor(fontString, color)
    if not (fontString and fontString.SetTextColor) then
        return
    end
    local source = type(color) == "table" and color or {}
    fontString:SetTextColor(source[1] or 1, source[2] or 1, source[3] or 1, source[4] == nil and 1 or source[4])
end

local function StyleColor(name, fallback)
    return T.Style and T.Style.Color and T.Style.Color[name] or fallback
end

local function CreatePopupFont(parent, template, size, color, flags)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    if size and text.SetFont then
        text:SetFont(STANDARD_TEXT_FONT, size, flags)
    end
    ApplyTextColor(text, color)
    return text
end

local function BuildPopupViewModel(context)
    local payload = context.payload or {}
    local sender = context.sender or payload.sender or ""
    local count = #(context.entries or {}) + #(context.unknown or {})
    local view = {
        sender = sender,
        scope = ShortLabel(payload.label),
        actionHint = Text("PUSH_POPUP_ACTION_HINT", "请确认是否应用这次下发。"),
        diff = BuildDiffText(context, context.expanded == true),
    }
    if context.screenReminderImport then
        view.title = "屏幕提醒设置下发"
        view.summary = string.format("共 %d 项，选择合并或替换后应用。", count)
        view.actionHint = "请选择合并、替换或拒绝。"
    elseif context.personalAuraImport then
        view.title = "个人光环提醒下发"
        view.summary = string.format("共 %d 项，选择合并或替换后应用。", count)
        view.actionHint = "请选择合并、替换或拒绝。"
    elseif payload.mode == "module" then
        view.title = "整组设置下发"
        view.summary = string.format("共 %d 项变更，接受后写入本机设置。", count)
    else
        local first = context.entries and context.entries[1]
        local valueText = first and FormatValue(first.value) or ""
        view.title = "单项设置下发"
        view.summary = string.format("变更为：%s", valueText)
    end
    return view
end

local function ContextEntryCount(context)
    return #(context and context.entries or {})
end

local function ContextUnknownCount(context)
    return #(context and context.unknown or {})
end

local function IsOptionPushPopupVisible()
    local frame = Share.popupFrame
    return frame and frame.IsShown and frame:IsShown()
end

function Share:ApplyContext(context, mode)
    if not context then
        return 0, 0
    end
    if context.screenReminderImport then
        mode = mode == "replace" and "replace" or "merge"
        local applyImport = T.ScreenReminderOptionPush and T.ScreenReminderOptionPush.ApplyImport
        local stats = applyImport and applyImport(context.screenReminderImport.value, mode, context.screenReminderImport.kind)
        local applied = stats and (tonumber(stats.sourceCount) or 0) or 0
        local skipped = stats and #(context.unknown or {}) or (#(context.entries or {}) + #(context.unknown or {}))
        local payload = context.payload or {}
        if stats then
            T.msg(string.format("已%s团长下发的【%s】：%d 条，跳过 %d 项。",
                mode == "replace" and "替换" or "合并",
                tostring(payload.label or ""),
                applied,
                skipped))
        else
            T.msg("屏幕提醒导入失败：数据无效。")
            Debug("ScreenReminderImportApplyFailed sender=%s label=%s applyMode=%s", tostring(context.sender), tostring(payload.label), tostring(mode))
        end
        Debug("STT_OPT_PUSH_APPLIED sender=%s mode=%s label=%s applyMode=%s appliedCount=%d skippedCount=%d", tostring(context.sender), tostring(payload.mode), tostring(payload.label), tostring(mode), applied, skipped)
        return applied, skipped
    end
    if context.personalAuraImport then
        mode = mode == "replace" and "replace" or "merge"
        local applyImport = T.PersonalAuraAlertOptionPush and T.PersonalAuraAlertOptionPush.ApplyImport
        local stats = applyImport and applyImport(context.personalAuraImport.value, mode, context.personalAuraImport.kind)
        local applied = stats and (tonumber(stats.sourceCount) or 0) or 0
        local skipped = stats and #(context.unknown or {}) or (#(context.entries or {}) + #(context.unknown or {}))
        local payload = context.payload or {}
        if stats then
            T.msg(string.format("已%s团长下发的【%s】：%d 条，跳过 %d 项。",
                mode == "replace" and "替换" or "合并",
                tostring(payload.label or ""),
                applied,
                skipped))
        else
            T.msg(tostring(context.personalAuraImport.failedText or "个人光环提醒导入失败：数据无效。"))
            Debug("PersonalAuraImportApplyFailed sender=%s label=%s applyMode=%s", tostring(context.sender), tostring(payload.label), tostring(mode))
        end
        Debug("STT_OPT_PUSH_APPLIED sender=%s mode=%s label=%s applyMode=%s appliedCount=%d skippedCount=%d", tostring(context.sender), tostring(payload.mode), tostring(payload.label), tostring(mode), applied, skipped)
        return applied, skipped
    end
    local applied = 0
    for _, entry in ipairs(context.entries or {}) do
        if T.OptionEngine and entry.itemDef then
            T.OptionEngine:ApplyItem(entry.itemDef, DeepCopy(entry.value), entry.moduleDef)
            applied = applied + 1
        end
    end
    if T.OptionEngine then
        T.OptionEngine:RefreshWidgetValues()
        T.OptionEngine:RefreshDependStates()
    end
    local skipped = #(context.unknown or {})
    local payload = context.payload or {}
    if payload.mode == "module" then
        T.msg(string.format(Text("PUSH_APPLIED_MODULE", "已应用团长下发的【%s】设置：%d 项，跳过 %d 项。"), tostring(payload.label or ""), applied, skipped))
    else
        T.msg(string.format(Text("PUSH_APPLIED_ITEM", "已应用团长下发设置【%s】：%d 项，跳过 %d 项。"), tostring(payload.label or ""), applied, skipped))
    end
    Debug("STT_OPT_PUSH_APPLIED sender=%s mode=%s label=%s appliedCount=%d skippedCount=%d", tostring(context.sender), tostring(payload.mode), tostring(payload.label), applied, skipped)
    return applied, skipped
end

local RefreshPopupFrame

local function SetButton(button, text, action, shown)
    if not button then
        return
    end
    button:SetText(text)
    button.__sttAction = action
    if shown == false then
        button:Hide()
    else
        button:Show()
    end
end

local function ApplyContextSafely(context, mode)
    local ok, applied, skipped = pcall(function()
        return Share:ApplyContext(context, mode)
    end)
    if ok then
        return tonumber(applied) or 0, tonumber(skipped) or 0
    end
    T.msg("设置下发应用失败：请查看调试日志。")
    Debug("PopupApplyError mode=%s sender=%s label=%s err=%s", tostring(mode), tostring(context and context.sender), tostring(context and context.payload and context.payload.label), tostring(applied))
    return 0, ContextEntryCount(context) + ContextUnknownCount(context)
end

local function FinishPopup(frame, action)
    local context = frame and frame.__sttOptionPushContext
    if context and frame.__sttIgnoreCheck and frame.__sttIgnoreCheck:GetChecked() then
        Share:AddIgnoredSender(context.sender)
    end
    local payload = context and context.payload or {}
    local applied, skipped = 0, 0
    if not context then
        Debug("Popup%s missing_context", tostring(action or "Close"))
    elseif action == "merge" then
        applied, skipped = ApplyContextSafely(context, "merge")
        Debug("PopupMerge sender=%s label=%s entries=%d unknown=%d applied=%d skipped=%d", tostring(context.sender), tostring(payload.label), ContextEntryCount(context), ContextUnknownCount(context), tonumber(applied) or 0, tonumber(skipped) or 0)
        SendOptionAck(context.sender, context.commMeta, "merge", { applied = applied, skipped = skipped })
    elseif action == "replace" then
        applied, skipped = ApplyContextSafely(context, "replace")
        Debug("PopupReplace sender=%s label=%s entries=%d unknown=%d applied=%d skipped=%d", tostring(context.sender), tostring(payload.label), ContextEntryCount(context), ContextUnknownCount(context), tonumber(applied) or 0, tonumber(skipped) or 0)
        SendOptionAck(context.sender, context.commMeta, "replace", { applied = applied, skipped = skipped })
    elseif action == "accept" then
        applied, skipped = ApplyContextSafely(context)
        Debug("PopupAccept sender=%s label=%s entries=%d unknown=%d applied=%d skipped=%d", tostring(context.sender), tostring(payload.label), ContextEntryCount(context), ContextUnknownCount(context), tonumber(applied) or 0, tonumber(skipped) or 0)
        SendOptionAck(context.sender, context.commMeta, "accept", { applied = applied, skipped = skipped })
    else
        Debug("PopupReject hasContext=%s sender=%s label=%s entries=%d", tostring(context ~= nil), tostring(context and context.sender), tostring(payload.label), ContextEntryCount(context))
        if context then
            SendOptionAck(context.sender, context.commMeta, "reject", "user_rejected")
        end
    end
    if frame and frame.Hide then
        frame:Hide()
    end
end

local function EnsurePopup()
    if Share.popupFrame then
        return Share.popupFrame
    end
    local frame = CreateFrame("Frame", "STTOptionPushConfirmFrame", UIParent, "BackdropTemplate")
    frame:SetSize(POPUP_WIDTH, POPUP_COLLAPSED_HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.02, 0.02, 0.02, 0.92)
    frame:SetBackdropBorderColor(0.75, 0.62, 0.28, 0.95)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(owner, key)
        if key == "ESCAPE" then
            local context = owner and owner.__sttOptionPushContext
            Debug("PopupKeyReject key=%s sender=%s label=%s", tostring(key), tostring(context and context.sender), tostring(context and context.payload and context.payload.label))
            FinishPopup(owner, "reject")
        end
    end)

    frame.title = CreatePopupFont(frame, "GameFontNormal", 15, StyleColor("KYRIAN_GOLD", { 0.98, 0.86, 0.52, 1 }), "OUTLINE")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -16)
    frame.title:SetText("STT 设置下发")

    frame.actionHint = CreatePopupFont(frame, "GameFontDisableSmall", 11, { 0.7, 0.7, 0.7, 1 })
    frame.actionHint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -18)
    frame.actionHint:SetWidth(250)
    frame.actionHint:SetJustifyH("RIGHT")
    frame.actionHint:SetWordWrap(false)

    frame.divider = frame:CreateTexture(nil, "OVERLAY")
    frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -42)
    frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -42)
    frame.divider:SetHeight(1)
    frame.divider:SetColorTexture(unpack(StyleColor("SECTION_LINE", { 0.65, 0.55, 0.32, 0.5 })))

    frame.sourceLabel = CreatePopupFont(frame, "GameFontDisableSmall", 11, { 0.62, 0.62, 0.62, 1 })
    frame.sourceLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -58)
    frame.sourceLabel:SetText("来源")
    frame.sourceValue = CreatePopupFont(frame, "GameFontHighlightSmall", 12, { 1, 1, 1, 1 })
    frame.sourceValue:SetPoint("LEFT", frame.sourceLabel, "RIGHT", 18, 0)
    frame.sourceValue:SetWidth(390)
    frame.sourceValue:SetJustifyH("LEFT")
    frame.sourceValue:SetWordWrap(false)

    frame.scopeLabel = CreatePopupFont(frame, "GameFontDisableSmall", 11, { 0.62, 0.62, 0.62, 1 })
    frame.scopeLabel:SetPoint("TOPLEFT", frame.sourceLabel, "BOTTOMLEFT", 0, -10)
    frame.scopeLabel:SetText("范围")
    frame.scopeValue = CreatePopupFont(frame, "GameFontHighlightSmall", 12, StyleColor("KYRIAN_GOLD", { 0.98, 0.86, 0.52, 1 }))
    frame.scopeValue:SetPoint("LEFT", frame.scopeLabel, "RIGHT", 18, 0)
    frame.scopeValue:SetWidth(390)
    frame.scopeValue:SetJustifyH("LEFT")
    frame.scopeValue:SetWordWrap(true)

    frame.summaryLabel = CreatePopupFont(frame, "GameFontDisableSmall", 11, { 0.62, 0.62, 0.62, 1 })
    frame.summaryLabel:SetPoint("TOPLEFT", frame.scopeLabel, "BOTTOMLEFT", 0, -12)
    frame.summaryLabel:SetText("摘要")
    frame.summaryValue = CreatePopupFont(frame, "GameFontHighlightSmall", 12, { 0.9, 0.9, 0.9, 1 })
    frame.summaryValue:SetPoint("TOPLEFT", frame.summaryLabel, "TOPRIGHT", 18, 0)
    frame.summaryValue:SetWidth(390)
    frame.summaryValue:SetJustifyH("LEFT")
    frame.summaryValue:SetWordWrap(true)

    frame.diffPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.diffPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -126)
    frame.diffPanel:SetSize(POPUP_BODY_WIDTH, 74)
    frame.diffPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.diffPanel:SetBackdropColor(0.015, 0.015, 0.018, 0.82)
    frame.diffPanel:SetBackdropBorderColor(0.26, 0.22, 0.12, 0.75)

    frame.diffTitle = CreatePopupFont(frame.diffPanel, "GameFontNormalSmall", 11, StyleColor("KYRIAN_GOLD", { 0.98, 0.86, 0.52, 1 }))
    frame.diffTitle:SetPoint("TOPLEFT", frame.diffPanel, "TOPLEFT", 10, -7)
    frame.diffTitle:SetText("变更明细")

    frame.__sttDiffButton = T.CreateButton(frame, { width = 110, height = 22 })
    frame.__sttDiffButton:SetPoint("TOPRIGHT", frame.diffPanel, "TOPRIGHT", -8, -5)
    frame.__sttDiffButton:SetFrameLevel(frame.diffPanel:GetFrameLevel() + 2)
    frame.__sttDiffButton:SetScript("OnClick", function(button)
        local owner = button:GetParent()
        local data = owner and owner.__sttOptionPushContext
        if not data then
            return
        end
        data.expanded = not data.expanded
        RefreshPopupFrame(owner)
    end)

    frame.diffText = CreatePopupFont(frame.diffPanel, "GameFontHighlightSmall", 11, { 0.86, 0.86, 0.86, 1 })
    frame.diffText:SetPoint("TOPLEFT", frame.diffPanel, "TOPLEFT", 10, -32)
    frame.diffText:SetPoint("BOTTOMRIGHT", frame.diffPanel, "BOTTOMRIGHT", -10, 8)
    frame.diffText:SetJustifyH("LEFT")
    frame.diffText:SetJustifyV("TOP")
    frame.diffText:SetWordWrap(true)

    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 48)
    check.text = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check.text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.text:SetWidth(430)
    check.text:SetJustifyH("LEFT")
    check.text:SetWordWrap(true)
    frame.__sttIgnoreCheck = check

    frame.buttonBar = CreateFrame("Frame", nil, frame)
    frame.buttonBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
    frame.buttonBar:SetSize(312, 24)

    frame.button1 = T.CreateButton(frame, { width = 92, height = 24 })
    frame.button2 = T.CreateButton(frame, { width = 92, height = 24 })
    frame.button3 = T.CreateButton(frame, { width = 92, height = 24 })
    for _, button in ipairs({ frame.button1, frame.button2, frame.button3 }) do
        button:SetScript("OnClick", function(btn)
            local owner = btn:GetParent()
            FinishPopup(owner, btn.__sttAction)
        end)
    end

    frame:SetScript("OnHide", function(owner)
        local context = owner and owner.__sttOptionPushContext
        if owner and owner.__sttSuppressNextHideLog then
            owner.__sttSuppressNextHideLog = nil
            return
        end
        owner.__sttOptionPushContext = nil
        Share.pendingPopup = nil
        Share.popupActive = false
        if #popupQueue > 0 then
            local nextContext = table.remove(popupQueue, 1)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    Share:ShowPopup(nextContext)
                end)
            else
                Share:ShowPopup(nextContext)
            end
        end
    end)
    frame.__sttSuppressNextHideLog = true
    frame:Hide()
    Share.popupFrame = frame
    return frame
end

RefreshPopupFrame = function(frame)
    local context = frame and frame.__sttOptionPushContext
    if not context then
        return
    end
    local view = BuildPopupViewModel(context)
    frame:SetHeight(context.expanded and POPUP_EXPANDED_HEIGHT or POPUP_COLLAPSED_HEIGHT)
    frame.title:SetText(view.title or "STT 设置下发")
    frame.actionHint:SetText(tostring(view.actionHint or ""))
    frame.sourceValue:SetText(tostring(view.sender or ""))
    frame.scopeValue:SetText(tostring(view.scope or ""))
    frame.summaryValue:SetText(tostring(view.summary or ""))
    frame.diffPanel:SetHeight(context.expanded and 194 or 74)
    frame.diffText:SetText(tostring(view.diff or ""))
    frame.__sttDiffButton:SetText(context.expanded and Text("PUSH_POPUP_HIDE_DIFF", "收起变更") or Text("PUSH_POPUP_VIEW_DIFF", "查看变更"))
    frame.__sttIgnoreCheck.text:SetText(string.format(Text("PUSH_POPUP_IGNORE_LABEL", "以后不再接受 %s 的下发"), tostring(context.sender or "")))

    frame.button1:ClearAllPoints()
    frame.button2:ClearAllPoints()
    frame.button3:ClearAllPoints()
    frame.buttonBar:ClearAllPoints()
    frame.buttonBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
    if context.screenReminderImport or context.personalAuraImport then
        SetButton(frame.button1, "合并", "merge", true)
        SetButton(frame.button2, "替换", "replace", true)
        SetButton(frame.button3, Text("PUSH_POPUP_REJECT", "拒绝"), "reject", true)
        frame.buttonBar:SetSize(312, 24)
        frame.button1:SetPoint("LEFT", frame.buttonBar, "LEFT", 0, 0)
        frame.button2:SetPoint("CENTER", frame.buttonBar, "CENTER", 0, 0)
        frame.button3:SetPoint("RIGHT", frame.buttonBar, "RIGHT", 0, 0)
    else
        SetButton(frame.button1, Text("PUSH_POPUP_ACCEPT", "接受"), "accept", true)
        SetButton(frame.button2, Text("PUSH_POPUP_REJECT", "拒绝"), "reject", true)
        SetButton(frame.button3, "", "reject", false)
        frame.buttonBar:SetSize(212, 24)
        frame.button1:SetPoint("LEFT", frame.buttonBar, "LEFT", 0, 0)
        frame.button2:SetPoint("RIGHT", frame.buttonBar, "RIGHT", 0, 0)
    end
end

function Share:ShowPopup(context)
    local frame = EnsurePopup()
    if self.popupActive or IsOptionPushPopupVisible() then
        popupQueue[#popupQueue + 1] = context
        return
    end
    self.pendingPopup = context
    self.popupActive = true
    if not frame then
        Debug("PopupShowFailed sender=%s label=%s", tostring(context and context.sender), tostring(context and context.payload and context.payload.label))
        self.pendingPopup = nil
        self.popupActive = false
    else
        frame.__sttOptionPushContext = context
        frame.__sttIgnoreCheck:SetChecked(false)
        RefreshPopupFrame(frame)
        frame:Show()
        SendOptionAck(context.sender, context.commMeta, "shown", "popup")
    end
end

function Share:OnReceive(sender, payload, meta)
    if SameShortName(sender, GetPlayerFullName()) then
        return
    end
    if ReadPath(C.DB, "raidLead.optionPushAccept", true) == false then
        Debug("RejectedAcceptOff sender=%s", tostring(sender))
        SendOptionAck(sender, meta, "reject", "accept_off")
        return
    end
    if self:IsSenderIgnored(sender) then
        Debug("RejectedIgnored sender=%s", tostring(sender))
        SendOptionAck(sender, meta, "reject", "ignored_sender")
        return
    end
    if not IsSenderLeaderOrAssistant(sender) then
        Debug("RejectedSenderNotLead sender=%s", tostring(sender))
        SendOptionAck(sender, meta, "reject", "sender_not_leader")
        return
    end
    local context, err = self:BuildReceiveContext(sender, payload, meta)
    if not context then
        Debug("BadPayload sender=%s err=%s", tostring(sender), tostring(err))
        SendOptionAck(sender, meta, "reject", tostring(err))
        return
    end
    if #(context.entries or {}) <= 0 then
        T.msg(string.format(Text("PUSH_NO_CHANGES", "%s 下发的设置没有可应用变更。"), tostring(sender)))
        Debug("NoApplicableChanges sender=%s mode=%s label=%s unknownCount=%d", tostring(sender), tostring(payload.mode), tostring(payload.label), #(context.unknown or {}))
        SendOptionAck(sender, meta, "noop", "no_applicable_changes")
        return
    end
    Debug("STT_OPT_PUSH_RECEIVED sender=%s mode=%s label=%s entryCount=%d", tostring(sender), tostring(payload.mode), tostring(payload.label), #(context.entries or {}))
    self:ShowPopup(context)
end

function Share:AttachShiftTooltip(frame, itemDef, moduleDef)
    if not frame or frame.__sttOptionPushTooltip then
        return
    end
    frame.__sttOptionPushTooltip = true
    frame:HookScript("OnEnter", function(owner)
        if not (IsShiftKeyDown and IsShiftKeyDown() and Share:CanPush(true) and Share:IsPushable(itemDef)) then
            return
        end
        if not (GameTooltip and GameTooltip:GetOwner() == owner) then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", -20, 10)
        end
        GameTooltip:AddLine(Text("TIP_SHIFT_PUSH", "[Shift+点击] 下发此设置给团队"), 0.35, 0.85, 1, false)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function(owner)
        if GameTooltip and GameTooltip:GetOwner() == owner then
            GameTooltip:Hide()
        end
    end)
end

function Share:AttachNavShiftTooltip(frame, moduleId)
    if not (frame and IsShiftKeyDown and IsShiftKeyDown() and self:CanPush(true)) then
        return
    end
    local moduleDef = T.OptionEngine and T.OptionEngine:GetModuleById(moduleId)
    if not BuildModulePayload(moduleDef) then
        return
    end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT", -20, 10)
    GameTooltip:AddLine(Text("TIP_SHIFT_PUSH_MODULE", "[Shift+点击] 下发此页设置给团队"), 0.35, 0.85, 1, false)
    GameTooltip:Show()
end

Share:EnsureCommReady()

end)
