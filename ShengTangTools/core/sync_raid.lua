local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({ "semanticTimeline.editorLoaded", "rosterPlanner.enabled" }, function()

local SyncRaid = {}
T.SyncRaid = SyncRaid

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function SplitLines(text)
    local normalized = tostring(text or ""):gsub("\r\n", "\n")
    if normalized == "" then
        return {}, normalized
    end

    local lines = {}
    local start = 1
    local len = #normalized
    while start <= len + 1 do
        local pos = normalized:find("\n", start, true)
        if not pos then
            lines[#lines + 1] = normalized:sub(start)
            break
        end
        lines[#lines + 1] = normalized:sub(start, pos - 1)
        start = pos + 1
    end
    return lines, normalized
end

local function AppendPersonnelSection(output, rosterLines)
    output[#output + 1] = "[人员]"
    for _, line in ipairs(rosterLines or {}) do
        output[#output + 1] = line
    end
    output[#output + 1] = ""
end

local function HasRealHeader(info, sectionName)
    local section = info and info.sections and info.sections[sectionName] or nil
    local rawLine = section and info.rawLines and info.rawLines[section.headerLine] or nil
    return Trim(rawLine) == "[" .. sectionName .. "]"
end

local function GetPersonnelBody(info)
    local section = info and info.sections and info.sections["人员"] or nil
    if not section then
        return {}
    end

    local rawLines = info.rawLines or {}
    local lines = {}
    local startLine = (tonumber(section.headerLine) or 0) + 1
    local endLine = tonumber(section.lastLine) or startLine - 1
    for lineNumber = startLine, endLine do
        lines[#lines + 1] = rawLines[lineNumber] or ""
    end
    return lines
end

local function HasNonEmptyBody(lines)
    for _, line in ipairs(lines or {}) do
        if Trim(line) ~= "" then
            return true
        end
    end
    return false
end

local function CountList(list)
    return type(list) == "table" and #list or 0
end

local function ReasonText(reason)
    local key = "MSG_SYNC_RAID_REASON_" .. tostring(reason or "no_spec"):gsub("[^%w_]", "_")
    return L[key] or tostring(reason or "no_spec")
end

local function MissingSummary(stats)
    local missing = stats and stats.missing or {}
    local output = {}
    local limit = math.min(#missing, 8)
    for index = 1, limit do
        local item = missing[index] or {}
        output[#output + 1] = string.format("%s(%s)", tostring(item.name or "?"), ReasonText(item.reason))
    end
    if #missing > limit then
        output[#output + 1] = string.format("...+%d", #missing - limit)
    end
    return table.concat(output, "、")
end

local function SourceSummary(stats)
    local sources = stats and stats.sources or {}
    local output = {}
    for source, count in pairs(sources) do
        output[#output + 1] = tostring(source) .. "=" .. tostring(count)
    end
    table.sort(output)
    return table.concat(output, ",")
end

local function ParseKey(line)
    local key = tostring(line or ""):match("^%s*([^=]+)%s*=")
    return Trim(key)
end

local function MergeRosterLines(existingLines, rosterLines)
    local generated = {}
    local generatedOrder = {}
    for _, line in ipairs(rosterLines or {}) do
        local key = ParseKey(line)
        if key ~= "" and not generated[key] then
            generatedOrder[#generatedOrder + 1] = key
        end
        if key ~= "" then
            generated[key] = line
        end
    end

    local seen = {}
    local output = {}
    for _, line in ipairs(existingLines or {}) do
        local key = ParseKey(line)
        if key ~= "" and generated[key] then
            output[#output + 1] = generated[key]
            seen[key] = true
        else
            output[#output + 1] = line
            if key ~= "" then
                seen[key] = true
            end
        end
    end

    for _, key in ipairs(generatedOrder) do
        if not seen[key] then
            output[#output + 1] = generated[key]
        end
    end
    return output
end

function SyncRaid.BuildText(text, rosterLines, mode)
    local rawLines, normalized = SplitLines(text)
    local preprocess = T.STNTemplate and T.STNTemplate.PreprocessText
    local info = preprocess and preprocess(normalized, { relaxed = true }) or nil

    if not info or info.hasBlocks ~= true then
        local output = {}
        AppendPersonnelSection(output, rosterLines)
        output[#output + 1] = "[时间轴]"
        for _, line in ipairs(rawLines) do
            output[#output + 1] = line
        end
        return table.concat(output, "\n")
    end

    local output = {}
    local personnelSection = info.sections and info.sections["人员"] or nil
    local bodyName = (info.sections and info.sections["触发轴"] and "触发轴") or (info.sections and info.sections["时间轴"] and "时间轴") or nil
    local bodySection = bodyName and info.sections[bodyName] or nil
    local bodyHasRealHeader = bodyName and HasRealHeader(info, bodyName) or false

    if not personnelSection then
        local insertAt = bodySection and tonumber(bodySection.headerLine) or (#rawLines + 1)
        for index = 1, insertAt - 1 do
            output[#output + 1] = rawLines[index]
        end
        AppendPersonnelSection(output, rosterLines)
        if bodySection and not bodyHasRealHeader then
            output[#output + 1] = "[时间轴]"
        elseif not bodySection then
            output[#output + 1] = "[时间轴]"
        end
        for index = insertAt, #rawLines do
            output[#output + 1] = rawLines[index]
        end
        return table.concat(output, "\n")
    end

    local startLine = (tonumber(personnelSection.headerLine) or 0) + 1
    local endLine = tonumber(personnelSection.lastLine) or startLine - 1
    local existingLines = GetPersonnelBody(info)
    local nextLines = mode == "merge" and MergeRosterLines(existingLines, rosterLines) or rosterLines

    for index = 1, startLine - 1 do
        output[#output + 1] = rawLines[index]
    end
    for _, line in ipairs(nextLines or {}) do
        output[#output + 1] = line
    end
    if bodySection and not bodyHasRealHeader then
        output[#output + 1] = ""
        output[#output + 1] = "[时间轴]"
    end
    for index = endLine + 1, #rawLines do
        output[#output + 1] = rawLines[index]
    end
    if not bodySection then
        output[#output + 1] = ""
        output[#output + 1] = "[时间轴]"
    end
    return table.concat(output, "\n")
end

local function EnsurePopup()
    if type(StaticPopupDialogs) ~= "table" then
        return
    end
    StaticPopupDialogs["STT_SYNC_RAID_CONFIRM"] = {
        text = L["POPUP_SYNC_RAID_TEXT"] or "[人员] 段已存在内容，如何处理？",
        button1 = L["POPUP_SYNC_RAID_OVERWRITE"] or "覆盖",
        button2 = CANCEL or (L["取消"] or "取消"),
        button3 = L["POPUP_SYNC_RAID_MERGE"] or "合并",
        OnAccept = function(_, data)
            if data and data.overwrite then
                data.overwrite()
            end
        end,
        OnAlt = function(_, data)
            if data and data.merge then
                data.merge()
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

local function EnsureIncompletePopup()
    if type(StaticPopupDialogs) ~= "table" then
        return
    end
    StaticPopupDialogs["STT_SYNC_RAID_INCOMPLETE"] = {
        text = L["POPUP_SYNC_RAID_INCOMPLETE_TEXT"] or "还有 %d 名在线团员未识别专精：\n%s\n\n可以先覆盖已识别条目，未识别的旧条目会保留原样。",
        button1 = L["POPUP_SYNC_RAID_OVERWRITE_RECOGNIZED"] or "覆盖已识别",
        button2 = CANCEL or (L["取消"] or "取消"),
        button3 = L["POPUP_SYNC_RAID_WAIT"] or "继续等待",
        OnAccept = function(_, data)
            if data and data.overwriteRecognized then
                data.overwriteRecognized()
            end
        end,
        OnAlt = function(_, data)
            if data and data.wait then
                data.wait()
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

local function ApplyText(ctx, rosterLines, stats, mode)
    local editorBox = ctx and ctx.editorBox or nil
    if not editorBox then
        return
    end

    local oldText = editorBox:GetText() or ""
    local newText = SyncRaid.BuildText(oldText, rosterLines, mode)
    if ctx.preserveText then
        ctx.preserveText(newText, editorBox:GetCursorPosition(), "sync_raid_roster")
    else
        editorBox:SetText(newText)
    end
    if ctx.applyEditorText then
        ctx.applyEditorText("sync_raid_roster")
    end
    if T.msg then
        T.msg(string.format(
            L["MSG_SYNC_RAID_SUMMARY"] or "已导入 %d 名团员（跳过离线 %d，未识别专精 %d）",
            tonumber(stats and stats.included) or 0,
            tonumber(stats and stats.skippedOffline) or 0,
            tonumber(stats and stats.skippedNoSpec) or 0
        ))
    end
    if T.debug then
        T.debug(string.format(
            "[SyncRaid] total=%d included=%d skippedOffline=%d skippedNoSpec=%d mode=%s sources=%s",
            tonumber(stats and stats.total) or 0,
            tonumber(stats and stats.included) or 0,
            tonumber(stats and stats.skippedOffline) or 0,
            tonumber(stats and stats.skippedNoSpec) or 0,
            tostring(mode or "overwrite"),
            SourceSummary(stats)
        ))
    end
end

local function ShowReadFailure(reason)
    if not T.msg then
        return
    end
    if reason == "combat" then
        T.msg(L["MSG_SYNC_RAID_COMBAT"] or "战斗中不能读取团队专精，请脱战后再导入")
    elseif reason == "busy" then
        T.msg(L["MSG_SYNC_RAID_BUSY"] or "正在读取团队专精，请稍候")
    elseif reason == "not_group" then
        T.msg(L["MSG_SYNC_RAID_NOT_IN_GROUP"] or "请在队伍或团队中使用导入团员")
    else
        T.msg(L["MSG_SYNC_RAID_NOT_READY"] or "专精数据未就绪，请稍候再试")
    end
end

local BeginRead

local function ShowIncomplete(ctx, rosterLines, stats)
    local missingText = MissingSummary(stats)
    if missingText == "" then
        missingText = L["MSG_SYNC_RAID_UNKNOWN_MISSING"] or "未知"
    end
    if T.msg then
        T.msg(string.format(
            L["MSG_SYNC_RAID_INCOMPLETE"] or "还有 %d 名在线团员未识别专精，可先覆盖已识别条目",
            tonumber(stats and stats.skippedNoSpec) or 0
        ))
    end
    if T.debug then
        T.debug(string.format(
            "[SyncRaid] incomplete total=%d included=%d skippedNoSpec=%d missing=%s sources=%s",
            tonumber(stats and stats.total) or 0,
            tonumber(stats and stats.included) or 0,
            tonumber(stats and stats.skippedNoSpec) or 0,
            missingText,
            SourceSummary(stats)
        ))
    end
    EnsureIncompletePopup()
    StaticPopup_Show("STT_SYNC_RAID_INCOMPLETE", tonumber(stats and stats.skippedNoSpec) or 0, missingText, {
        overwriteRecognized = function()
            if CountList(rosterLines) == 0 then
                ShowReadFailure("not_ready")
                return
            end
            ApplyText(ctx, rosterLines, stats, "merge")
        end,
        wait = function()
            if BeginRead then
                BeginRead(ctx)
            end
        end,
    })
end

local function ApplyMembers(ctx, members)
    local rosterLines, stats = T.SpecAliases.GenerateRosterLines(members)
    if (tonumber(stats and stats.skippedNoSpec) or 0) > 0 then
        ShowIncomplete(ctx, rosterLines, stats)
        return
    end

    if #rosterLines == 0 then
        ShowReadFailure("not_ready")
        if T.debug then
            T.debug(string.format(
                "[SyncRaid] no_ready total=%d skippedOffline=%d skippedNoSpec=%d",
                tonumber(stats and stats.total) or 0,
                tonumber(stats and stats.skippedOffline) or 0,
                tonumber(stats and stats.skippedNoSpec) or 0
            ))
        end
        return
    end

    local editorBox = ctx.editorBox
    local text = editorBox and (editorBox:GetText() or "") or ""
    local info = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(text, { relaxed = true }) or nil
    local existingBody = GetPersonnelBody(info)
    if HasNonEmptyBody(existingBody) then
        EnsurePopup()
        StaticPopup_Show("STT_SYNC_RAID_CONFIRM", nil, nil, {
            overwrite = function()
                ApplyText(ctx, rosterLines, stats, "overwrite")
            end,
            merge = function()
                ApplyText(ctx, rosterLines, stats, "merge")
            end,
        })
        return
    end

    ApplyText(ctx, rosterLines, stats, "overwrite")
end

BeginRead = function(ctx)
    if T.msg then
        T.msg(L["MSG_SYNC_RAID_READING"] or "正在读取团队专精")
    end
    local started, reason = T.RaidSpecReader:ReadCurrentGroup(function(result)
        if not result or result.ok ~= true then
            ShowReadFailure(result and result.reason or "not_ready")
            return
        end
        ApplyMembers(ctx, result.members)
    end)
    if not started then
        ShowReadFailure(reason)
    end
end

function SyncRaid.HandleSemanticEditor(ctx)
    ctx = type(ctx) == "table" and ctx or {}
    if ctx.activeTab == "personal" then
        return
    end

    if not IsInGroup or not IsInGroup() then
        if T.msg then
            T.msg(L["MSG_SYNC_RAID_NOT_IN_GROUP"] or "请在队伍或团队中使用导入团员")
        end
        return
    end

    if not (T.RaidSpecReader and T.RaidSpecReader.ReadCurrentGroup and T.SpecAliases and T.SpecAliases.GenerateRosterLines) then
        ShowReadFailure("not_ready")
        return
    end

    BeginRead(ctx)
end

end)
