local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("rosterPlanner.enabled", function()

local RP = T.RosterPlanner
if not RP then
    return
end

local GUI = {
    inline = nil,
}
T.RosterPlannerGUI = GUI

-- 固定布局常量；列宽/按钮宽/对照列宽在渲染时按真实 context.width 计算（不写死宽度）
local LAYOUT = {
    edge = 6,
    rowGap = 8,
    sourceHeight = 140,
    statusHeight = 18,
    buttonHeight = 24,
    buttonGap = 6,
    buttonCount = 5,
    cols = 4,                 -- 8 个小队按 4 列 × 2 行铺满真实宽度
    groupHeaderHeight = 16,
    cellHeight = 22,
    cellGapY = 3,
    blockGapY = 12,
    diffCols = 3,
    diffRowHeight = 18,
    diffRowsPerCol = 14,
}

local function Text(key, fallback)
    return (L and L[key]) or fallback or key
end

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormalizeName(name)
    if RP.NormalizeRosterName then
        return RP:NormalizeRosterName(name)
    end
    local text = Trim(name):gsub("%s+", "")
    return string.lower(text:match("^([^%-]+)") or text)
end

-- BOSS 名归一：忽略空格与大小写，用于严格匹配
local function NormalizeBossLabel(name)
    return string.lower(Trim(name):gsub("%s+", ""))
end

-- 按真实内容宽度计算列宽、按钮宽、网格尺寸等度量
local function ComputeMetrics(contentWidth)
    local m = {}
    m.contentWidth = contentWidth
    m.groupColWidth = math.floor(contentWidth / LAYOUT.cols)
    m.cellWidth = math.max(60, m.groupColWidth - 16)
    m.rowHeight = LAYOUT.cellHeight + LAYOUT.cellGapY
    m.groupBlockHeight = LAYOUT.groupHeaderHeight + 5 * m.rowHeight + LAYOUT.blockGapY
    m.rowBlocks = math.ceil(8 / LAYOUT.cols)
    m.gridHeight = m.rowBlocks * m.groupBlockHeight
    m.buttonWidth = math.floor((contentWidth - (LAYOUT.buttonCount - 1) * LAYOUT.buttonGap) / LAYOUT.buttonCount)
    m.diffColWidth = math.floor((contentWidth - (LAYOUT.diffCols - 1) * LAYOUT.buttonGap) / LAYOUT.diffCols)
    return m
end

local function GetCellPoint(metrics, index)
    local group = math.floor((index - 1) / 5) + 1
    local pos = ((index - 1) % 5) + 1
    local col = (group - 1) % LAYOUT.cols
    local rowBlock = math.floor((group - 1) / LAYOUT.cols)
    local x = col * metrics.groupColWidth
    local y = -(rowBlock * metrics.groupBlockHeight) - LAYOUT.groupHeaderHeight - (pos - 1) * metrics.rowHeight
    return x, y
end

local function ApplyCellPoint(panel, cell)
    local x, y = GetCellPoint(panel.metrics, cell.index)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", cell:GetParent(), "TOPLEFT", x, y)
end

local function SetCellText(cell, text)
    cell._settingText = true
    cell:SetText(Trim(text))
    cell:SetCursorPosition(0)
    cell._settingText = nil
end

local function GetLayout(panel)
    local layout = {}
    for i = 1, 40 do
        local cell = panel.cells and panel.cells[i]
        layout[i] = cell and Trim(cell:GetText()) or ""
    end
    return layout
end

local function SaveLayout(panel)
    if not panel or panel.loadingCells or not panel.matched or not panel.bossIndex then
        return
    end
    RP:SaveBossLayout(panel.bossIndex, GetLayout(panel))
end

local function FindHoveredCell(panel, source)
    for _, cell in ipairs(panel.cells or {}) do
        if cell ~= source and cell:IsMouseOver() then
            return cell
        end
    end
end

local function UpdateCellColor(cell)
    local name = Trim(cell:GetText())
    if name == "" then
        cell:SetTextColor(0.55, 0.55, 0.55, 1)
        if cell.ColorBorder then
            cell:ColorBorder()
        end
        return
    end
    local color = nil
    local parsed = RP:GetParsed()
    local resolved = RP:ResolveCharacter(name, parsed)
    if resolved and resolved.primaryName then
        local classFileName = UnitClass and select(2, UnitClass(resolved.primaryName))
        color = classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName]
    end
    if color then
        cell:SetTextColor(color.r, color.g, color.b, 1)
    else
        cell:SetTextColor(0.92, 0.92, 0.92, 1)
    end
end

local function LoadLayoutToCells(panel, layout)
    panel.loadingCells = true
    for i = 1, 40 do
        SetCellText(panel.cells[i], layout and layout[i] or "")
        UpdateCellColor(panel.cells[i])
    end
    panel.loadingCells = nil
end

local function SetGridEnabled(panel, enabled)
    for _, cell in ipairs(panel.cells or {}) do
        if enabled then
            cell:Enable()
            cell:EnableMouse(true)
        else
            cell:ClearFocus()
            cell:Disable()
            cell:EnableMouse(false)
        end
    end
end

local function SetActionsEnabled(panel, enabled)
    for _, btn in ipairs(panel.actionButtons or {}) do
        if btn.SetEnabled then
            btn:SetEnabled(enabled)
        elseif enabled then
            btn:Enable()
        else
            btn:Disable()
        end
    end
end

local function CreateRosterCell(panel, grid, index)
    local cell = T.CreateEditBox(grid, {
        width = panel.metrics.cellWidth,
        height = LAYOUT.cellHeight,
        fontObject = ChatFontNormal,
        autoFocus = false,
        justifyH = "LEFT",
    })
    cell.index = index
    ApplyCellPoint(panel, cell)
    cell:SetMovable(true)
    cell:RegisterForDrag("LeftButton")
    cell:SetScript("OnDragStart", function(self)
        if not panel.matched then
            return
        end
        self:StartMoving()
    end)
    cell:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if panel.matched then
            local target = FindHoveredCell(panel, self)
            if target then
                local mine = self:GetText()
                SetCellText(self, target:GetText())
                SetCellText(target, mine)
                SaveLayout(panel)
            end
        end
        ApplyCellPoint(panel, self)
        self:ClearFocus()
    end)
    cell:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        SaveLayout(panel)
    end)
    cell:HookScript("OnTextChanged", function(self)
        if self._settingText then
            return
        end
        UpdateCellColor(self)
    end)
    cell:SetScript("OnEditFocusLost", function()
        SaveLayout(panel)
    end)
    panel.cells[index] = cell
    return cell
end

local function CreateGroupHeaders(panel, grid)
    panel.groupHeaders = {}
    for group = 1, 8 do
        local x, y = GetCellPoint(panel.metrics, (group - 1) * 5 + 1)
        panel.groupHeaders[group] = T.CreateLabel(grid, {
            point = { "TOPLEFT", grid, "TOPLEFT", x + 2, y + LAYOUT.groupHeaderHeight },
            text = string.format("%s %d", GROUP or "Group", group),
            size = 12,
            color = { 1, 0.86, 0.32, 1 },
        })
    end
end

local function BuildCurrentMap()
    local map = {}
    for _, entry in ipairs(RP:GetCurrentRaidMembers()) do
        if entry.name then
            map[NormalizeName(entry.name)] = entry
        end
    end
    return map
end

local function AddStatus(rows, text, color)
    rows[#rows + 1] = {
        text = text,
        color = color,
    }
end

-- 单一权威：从 BossSpells 取当前 locale 的显示名（无兜底拼接）
local function ResolveBossDisplayName(encounterID)
    local id = tonumber(encounterID) or 0
    if id <= 0 then
        return nil
    end
    local bossData = T.Data and T.Data.BossSpells and T.Data.BossSpells[id]
    if not bossData then
        return nil
    end
    local locale = GetLocale and GetLocale() or ""
    if locale == "zhTW" then
        return bossData.nameZhTW or bossData.nameZh or bossData.name
    elseif locale == "zhCN" then
        return bossData.nameZh or bossData.name
    end
    return bossData.name or bossData.nameZh
end

-- 读取“当前战术方案 Boss”：优先当前方案 bossKey，其次工作台选择；只取 encounterID 与显示名
local function GetCurrentTacticalBossInfo()
    local sem = T.SemanticTimeline
    local selection = nil
    if T.Note and T.Note.GetCurrentBossKey and T.ParseSemanticBossKeyText then
        local bossKeyText = T.Note:GetCurrentBossKey()
        if bossKeyText then
            selection = T.ParseSemanticBossKeyText(bossKeyText)
        end
    end
    if not selection and sem and sem.GetWorkbenchSelection then
        selection = sem:GetWorkbenchSelection()
    end
    if not selection then
        return nil
    end
    local encounterID = tonumber(selection.encounterID) or 0
    if encounterID <= 0 then
        return nil
    end
    return {
        encounterID = encounterID,
        name = ResolveBossDisplayName(encounterID),
    }
end

-- 严格匹配：当前 Boss 显示名 == [块名]（忽略空格大小写）。不匹配不回退、不猜、不用唯一块
local function ResolveCurrentBossIndex(parsed)
    local info = GetCurrentTacticalBossInfo()
    if not info or not info.name or Trim(info.name) == "" then
        return nil, info
    end
    local target = NormalizeBossLabel(info.name)
    for index, boss in ipairs(parsed.bosses or {}) do
        if NormalizeBossLabel(boss.name) == target then
            return index, info
        end
    end
    return nil, info
end

local function BuildComparisonRows(parsed, boss)
    local rows = {}
    local currentMap = BuildCurrentMap()
    local wanted = {}
    for _, token in ipairs(boss.mainAll or {}) do
        local resolved = RP:ResolveCharacter(token, parsed)
        local key = NormalizeName(resolved.primaryName)
        wanted[key] = true
        local aliasKnown = parsed.aliasToKey and parsed.aliasToKey[NormalizeName(token)] ~= nil
        local current = currentMap[key]
        if current then
            local color = current.classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[current.classFileName]
            AddStatus(rows, string.format("%s  %s", token, Text("RP_DIFF_PRESENT", "已到")), color and { color.r, color.g, color.b, 1 } or { 0.55, 1, 0.55, 1 })
        elseif aliasKnown then
            AddStatus(rows, string.format("%s  %s", token, Text("RP_DIFF_MISSING", "未到")), { 1, 0.66, 0.28, 1 })
        else
            AddStatus(rows, string.format("%s  %s", token, Text("RP_DIFF_UNKNOWN", "未知昵称")), { 1, 0.35, 0.35, 1 })
        end
    end

    local playerKey = NormalizeName(UnitName and UnitName("player") or "")
    for _, entry in ipairs(RP:GetCurrentRaidMembers()) do
        local key = NormalizeName(entry.name)
        if key ~= playerKey and not wanted[key] then
            AddStatus(rows, string.format("%s  %s", entry.name, Text("RP_DIFF_EXTRA", "多余")), { 0.66, 0.66, 0.66, 1 })
        end
    end
    return rows
end

local function RefreshComparison(panel, parsed, boss, info)
    local rows
    if boss then
        rows = BuildComparisonRows(parsed, boss)
    else
        rows = {}
        if info then
            AddStatus(rows, Text("RP_DIFF_UNMATCHED_HINT", "当前战术方案 Boss 未匹配到阵容块，请把对应 BOSS 块命名为当前 Boss 名。"), { 1, 0.66, 0.4, 1 })
        else
            AddStatus(rows, Text("RP_EMPTY_HINT", "还没有 BOSS 阵容块。"), { 0.75, 0.75, 0.75, 1 })
        end
    end

    local total = #rows
    local cap = #(panel.diffRows or {})
    for i, row in ipairs(panel.diffRows or {}) do
        if i == cap and total > cap then
            row:SetText(string.format(Text("RP_DIFF_OVERFLOW_FMT", "… 还有 %d 项"), total - cap + 1))
            row:SetTextColor(0.7, 0.7, 0.7, 1)
            row:Show()
        elseif rows[i] then
            local data = rows[i]
            row:SetText(data.text)
            local color = data.color or { 0.8, 0.8, 0.8, 1 }
            row:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            row:Show()
        else
            row:SetText("")
            row:Hide()
        end
    end

    if panel.diffHint then
        local label = (boss and boss.name) or Text("RP_BOSS_UNMATCHED", "未匹配阵容块")
        panel.diffHint:SetText(string.format(Text("RP_DIFF_TITLE_FMT", "实时对照：%s"), label))
    end
end

local function RefreshBossNav(panel, parsed, bossIndex, info)
    if panel.bossLabel then
        local shown
        if info and info.name and Trim(info.name) ~= "" then
            shown = info.name
        elseif info then
            shown = "#" .. tostring(info.encounterID)
        end

        local text, matched
        if not info then
            text = string.format("%s: %s", Text("RP_CURRENT_BOSS", "当前 BOSS"), Text("RP_NO_BOSS", "无当前 Boss"))
            matched = false
        elseif bossIndex then
            text = string.format("%s: %s", Text("RP_CURRENT_BOSS", "当前 BOSS"), shown)
            matched = true
        else
            text = string.format("%s: %s（%s）", Text("RP_CURRENT_BOSS", "当前 BOSS"), shown, Text("RP_BOSS_UNMATCHED", "未匹配阵容块"))
            matched = false
        end
        panel.bossLabel:SetText(text)
        if matched then
            panel.bossLabel:SetTextColor(1, 0.86, 0.32, 1)
        else
            panel.bossLabel:SetTextColor(1, 0.55, 0.35, 1)
        end
    end
    if panel.parseLabel then
        panel.parseLabel:SetText(string.format(Text("RP_STATUS_FMT", "BOSS %d 个，错误 %d 个，警告 %d 个"), #(parsed.bosses or {}), #(parsed.errors or {}), #(parsed.warnings or {})))
    end
end

function GUI:Refresh()
    local panel = self.inline
    if not panel then
        return
    end
    local db = RP:EnsureDB()
    local parsed = RP:GetParsed()
    local bossIndex, info = ResolveCurrentBossIndex(parsed)
    local boss = bossIndex and parsed.bosses and parsed.bosses[bossIndex] or nil
    panel.matched = boss ~= nil
    panel.bossIndex = bossIndex
    -- EnsureDB 已令 STT_DB.rosterPlanner === db（单一权威），写 db 即落盘，无需重复双写
    db.activeBossIndex = bossIndex or 0

    if panel.sourceEdit and panel.sourceEdit.editBox and not panel.sourceEdit.editBox:HasFocus() then
        panel.sourceEdit:SetText(db.sourceText or "")
    end

    if panel.matched then
        LoadLayoutToCells(panel, RP:GetBossLayout(bossIndex, false, parsed))
        SetGridEnabled(panel, true)
    else
        LoadLayoutToCells(panel, {})
        SetGridEnabled(panel, false)
    end
    SetActionsEnabled(panel, panel.matched)

    RefreshBossNav(panel, parsed, bossIndex, info)
    RefreshComparison(panel, parsed, boss, info)
end

function GUI:RenderSettingsPanel(parent, context)
    local width = math.max(420, math.floor(tonumber(context and context.width) or 598))
    local contentWidth = width - LAYOUT.edge * 2
    local metrics = ComputeMetrics(contentWidth)

    local panel = {
        root = parent,
        cells = {},
        diffRows = {},
        actionButtons = {},
        metrics = metrics,
        matched = false,
        bossIndex = nil,
    }
    self.inline = panel

    local y = -2

    T.CreateGroupTitle(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", LAYOUT.edge, y },
        text = Text("RP_SOURCE_TITLE", "源文本（单一权威）"),
    })
    y = y - 20

    local source = T.CreateScrollEditBox(parent, {
        width = contentWidth,
        height = LAYOUT.sourceHeight,
        fontObject = ChatFontNormal,
        autoFocus = false,
    })
    source:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.edge, y)
    panel.sourceEdit = source
    source.editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    source.editBox:SetScript("OnEditFocusLost", function()
        local db = RP:EnsureDB()
        local text = source:GetText()
        if db.sourceText ~= text then
            db.sourceText = text
            if STT_DB and STT_DB.rosterPlanner then
                STT_DB.rosterPlanner.sourceText = text
            end
            RP:RecomputeParsed("source_edit")
        end
    end)
    y = y - (LAYOUT.sourceHeight + LAYOUT.rowGap)

    panel.bossLabel = T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", LAYOUT.edge, y },
        width = contentWidth,
        text = "",
        size = 13,
        color = { 1, 0.86, 0.32, 1 },
    })
    y = y - LAYOUT.statusHeight

    panel.parseLabel = T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", LAYOUT.edge, y },
        width = contentWidth,
        text = "",
        size = 12,
        color = { 0.82, 0.82, 0.82, 1 },
    })
    y = y - (LAYOUT.statusHeight + LAYOUT.rowGap)

    local buttonDefs = {
        {
            key = "RP_GROUP_LOAD_CURRENT", fallback = "读取当前团队",
            onClick = function()
                if not panel.matched then
                    return
                end
                local layout, ok = RP:ReadCurrentRaidLayout()
                if not ok then
                    if T.msg then
                        T.msg(Text("RP_MSG_GROUP_READ_NOT_RAID", "当前不在团队中，无法读取团队阵型。"))
                    end
                    return
                end
                LoadLayoutToCells(panel, layout)
                SaveLayout(panel)
                if T.msg then
                    T.msg(Text("RP_MSG_GROUP_READ_DONE", "已读取当前团队阵型，可拖拽调整后应用。"))
                end
            end,
        },
        {
            key = "RP_GROUP_APPLY", fallback = "应用到团队",
            onClick = function()
                if not panel.matched then
                    return
                end
                RP:ApplyRaidLayout(RP:GetBossLayout(panel.bossIndex, true))
            end,
        },
        {
            key = "RP_GROUP_CLEAR", fallback = "清空",
            onClick = function()
                if not panel.matched then
                    return
                end
                LoadLayoutToCells(panel, {})
                SaveLayout(panel)
                if T.msg then
                    T.msg(Text("RP_MSG_GROUP_CLEAR_DONE", "已清空当前 BOSS 阵型。"))
                end
            end,
        },
        {
            key = "RP_BTN_INVITE", fallback = "一键邀请此 BOSS",
            onClick = function()
                if not panel.matched then
                    return
                end
                RP:InviteForBoss(panel.bossIndex, RP:EnsureDB().inviteMode)
            end,
        },
        {
            key = "RP_BTN_BROADCAST", fallback = "推送给替补",
            onClick = function()
                if not panel.matched then
                    return
                end
                if RP.Broadcast then
                    RP:Broadcast()
                end
            end,
        },
    }
    for i, def in ipairs(buttonDefs) do
        local bx = LAYOUT.edge + (i - 1) * (metrics.buttonWidth + LAYOUT.buttonGap)
        panel.actionButtons[i] = T.CreateActionButton(parent, {
            width = metrics.buttonWidth,
            height = LAYOUT.buttonHeight,
            point = { "TOPLEFT", parent, "TOPLEFT", bx, y },
            textFn = function() return Text(def.key, def.fallback) end,
            onClick = def.onClick,
        })
    end
    y = y - (LAYOUT.buttonHeight + LAYOUT.rowGap)

    local grid = CreateFrame("Frame", nil, parent)
    grid:SetPoint("TOPLEFT", parent, "TOPLEFT", LAYOUT.edge, y)
    grid:SetSize(contentWidth, metrics.gridHeight)
    panel.grid = grid
    CreateGroupHeaders(panel, grid)
    for i = 1, 40 do
        CreateRosterCell(panel, grid, i)
    end
    y = y - (metrics.gridHeight + LAYOUT.rowGap)

    panel.diffHint = T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", LAYOUT.edge, y },
        width = contentWidth,
        text = "",
        size = 12,
        color = { 1, 0.86, 0.32, 1 },
    })
    y = y - 20

    for i = 1, LAYOUT.diffCols * LAYOUT.diffRowsPerCol do
        local col = math.floor((i - 1) / LAYOUT.diffRowsPerCol)
        local rowInCol = (i - 1) % LAYOUT.diffRowsPerCol
        local rx = LAYOUT.edge + col * (metrics.diffColWidth + LAYOUT.buttonGap)
        local ry = y - rowInCol * LAYOUT.diffRowHeight
        local row = T.CreateLabel(parent, {
            point = { "TOPLEFT", parent, "TOPLEFT", rx, ry },
            width = metrics.diffColWidth,
            text = "",
            size = 12,
            color = { 0.8, 0.8, 0.8, 1 },
        })
        row:Hide()
        panel.diffRows[i] = row
    end
    y = y - (LAYOUT.diffRowsPerCol * LAYOUT.diffRowHeight)

    local totalHeight = -y + LAYOUT.edge
    parent:SetHeight(totalHeight)

    GUI:Refresh()

    return {
        height = totalHeight,
        refresh = function()
            GUI:Refresh()
        end,
    }
end

end)
