local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("visualBoard.editorLoaded", function()

local LayerPanel = {}
T.VisualBoardLayerPanel = LayerPanel

local Style = T.Style

local function S(token)
    return Style.Scaled(token)
end

local function Sz(value)
    return Style.Scale(value)
end

local function Color(name)
    return Style.Color[name]
end

local function Text(key, fallback)
    local value = L and L[key]
    if value == nil or value == key then
        return fallback or key
    end
    return value
end

-- 折叠状态:groupID -> true 表示折叠
local collapsed = {}

local function GetData()
    return T.VisualBoardData
end

-- 团队标记名(与 editor_gui 一致:星/圈/菱/三角/月/方/叉/骷髅)。
local MARKER_NAMES = {
    Text("VISUAL_BOARD_LAYER_MARKER_1", "星"),
    Text("VISUAL_BOARD_LAYER_MARKER_2", "圈"),
    Text("VISUAL_BOARD_LAYER_MARKER_3", "菱"),
    Text("VISUAL_BOARD_LAYER_MARKER_4", "三角"),
    Text("VISUAL_BOARD_LAYER_MARKER_5", "月"),
    Text("VISUAL_BOARD_LAYER_MARKER_6", "方"),
    Text("VISUAL_BOARD_LAYER_MARKER_7", "叉"),
    Text("VISUAL_BOARD_LAYER_MARKER_8", "骷髅"),
}

-- 形状子类型名(rect/circle/line/arrow,与 data schema 的 shapeKind 一致)。
local SHAPE_NAMES = {
    rect = Text("VISUAL_BOARD_LAYER_SHAPE_RECT", "矩形"),
    circle = Text("VISUAL_BOARD_LAYER_SHAPE_CIRCLE", "圆"),
    line = Text("VISUAL_BOARD_LAYER_SHAPE_LINE", "线"),
    arrow = Text("VISUAL_BOARD_LAYER_SHAPE_ARROW", "箭头"),
}

-- 由元素类型与内容推导显示名(按 data schema 的真实字段:person→slotName / text→params.text /
-- shape→shapeKind 名 / marker→markerIndex 名 / icon→图标)。优先用用户改过的 element.name。
local function DeriveElementName(element)
    if type(element) ~= "table" then
        return "?"
    end
    if type(element.name) == "string" and element.name ~= "" then
        return element.name
    end
    local params = type(element.params) == "table" and element.params or {}
    local kind = element.type
    if kind == "person" then
        local slotName = type(params.slotName) == "string" and params.slotName or ""
        if slotName ~= "" then
            return slotName
        end
        return Text("VISUAL_BOARD_LAYER_TYPE_PERSON", "站位")
    elseif kind == "text" then
        local content = type(params.text) == "string" and params.text or ""
        if content ~= "" then
            return content
        end
        return Text("VISUAL_BOARD_LAYER_TYPE_TEXT", "文字")
    elseif kind == "shape" then
        return SHAPE_NAMES[params.shapeKind] or Text("VISUAL_BOARD_LAYER_TYPE_SHAPE", "形状")
    elseif kind == "marker" then
        local index = tonumber(params.markerIndex)
        return (index and MARKER_NAMES[index]) or Text("VISUAL_BOARD_LAYER_TYPE_MARKER", "标记")
    elseif kind == "icon" then
        return Text("VISUAL_BOARD_TYPE_ICON", "图标")
    end
    return tostring(kind or "?")
end

-- 元素/组的类型图标(纯文本字形,跟随名称对齐;按 data schema 的真实类型)。
local TYPE_GLYPH = {
    person = "○",
    text = "T",
    shape = "▢",
    marker = "◆",
    icon = "I",
}

local function ElementGlyph(elementType)
    return TYPE_GLYPH[elementType] or "•"
end

-- 构建展示行模型:自顶到底(z 最大在最上)。
-- 顶层项 = 组(取组内成员最大 z 作为排序键) + 无组顶层元素。
-- 组展开时其成员紧随其后(同样 z 降序)。
local function BuildRows(board)
    local rows = {}
    if type(board) ~= "table" then
        return rows
    end
    local elements = board.elements or {}
    local groups = type(board.groups) == "table" and board.groups or {}

    local groupMembers = {}
    local topLevel = {}
    for _, element in ipairs(elements) do
        local gid = element.groupID
        if gid and groups[gid] then
            groupMembers[gid] = groupMembers[gid] or {}
            table.insert(groupMembers[gid], element)
        else
            table.insert(topLevel, { kind = "element", element = element, sortZ = tonumber(element.z) or 0 })
        end
    end

    for gid, group in pairs(groups) do
        local members = groupMembers[gid] or {}
        local maxZ = 0
        for _, element in ipairs(members) do
            maxZ = math.max(maxZ, tonumber(element.z) or 0)
        end
        table.insert(topLevel, { kind = "group", group = group, members = members, sortZ = maxZ })
    end

    table.sort(topLevel, function(a, b)
        return a.sortZ > b.sortZ
    end)

    for _, item in ipairs(topLevel) do
        if item.kind == "group" then
            rows[#rows + 1] = {
                kind = "group",
                stableKey = "g:" .. item.group.id,
                id = item.group.id,
                name = item.group.name,
                indent = 0,
                hasChildren = #item.members > 0,
                collapsed = collapsed[item.group.id] == true,
            }
            if collapsed[item.group.id] ~= true then
                local members = item.members
                table.sort(members, function(a, b)
                    return (tonumber(a.z) or 0) > (tonumber(b.z) or 0)
                end)
                for _, element in ipairs(members) do
                    rows[#rows + 1] = {
                        kind = "element",
                        stableKey = "e:" .. element.id,
                        id = element.id,
                        name = DeriveElementName(element),
                        elementType = element.type,
                        indent = 1,
                        inGroup = true,
                    }
                end
            end
        else
            local element = item.element
            rows[#rows + 1] = {
                kind = "element",
                stableKey = "e:" .. element.id,
                id = element.id,
                name = DeriveElementName(element),
                elementType = element.type,
                indent = 0,
            }
        end
    end

    return rows
end

-- 由当前行模型推算"顶层项"自顶到底的元素 ID 序列,供拖拽重排写回 SetElementOrder。
-- 只考虑顶层元素(无组),组作为整体保持其成员相对顺序不打散(MVP)。
local function CollectTopLevelOrder(board)
    local order = {}
    if type(board) ~= "table" then
        return order
    end
    local groups = type(board.groups) == "table" and board.groups or {}
    local list = {}
    for _, element in ipairs(board.elements or {}) do
        local gid = element.groupID
        if not (gid and groups[gid]) then
            list[#list + 1] = element
        end
    end
    table.sort(list, function(a, b)
        return (tonumber(a.z) or 0) > (tonumber(b.z) or 0)
    end)
    for _, element in ipairs(list) do
        order[#order + 1] = element.id
    end
    return order
end

-- Figma 风格图层行的几何常量(全部经 Style.Scale)。
local function RowMetrics()
    local rowHeight = S("ITEM_HEIGHT")
    return {
        rowHeight = rowHeight,
        rowGap = S("ITEM_GAP"),
        indentStep = S("ITEM_INDENT"),
        edgePad = Sz(4),        -- 行左右内边距
        toggleSize = Sz(14),    -- 折叠箭头点击区
        controlSize = rowHeight - Sz(8), -- 批量按钮高度(竖直留白对齐)
        gap = Sz(4),            -- 控件间距
    }
end

-- 行池按稳定 ID 复用(契约 §9.1):stableKey = "g:"..groupID / "e:"..elementID。
-- 同一 model 永远复用同一物理 row,组折叠/展开导致的 rows 长度变化不再让行与数据错位。
local function AcquireRow(self, stableKey)
    local frame = self.frame
    local row = frame.rowPool[stableKey]
    if row then
        return row
    end
    local m = RowMetrics()
    row = CreateFrame("Button", nil, frame.list.content)
    row:SetHeight(m.rowHeight)
    -- 单击/双击都要响应:LeftButtonUp 供 OnClick,框架据此派发 OnDoubleClick。
    row:RegisterForClicks("LeftButtonUp")
    row:RegisterForDrag("LeftButton")

    -- 选中高亮:整行金色底色(KYRIAN_GOLD)。
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:Hide()

    -- hover 反馈:整行淡色描底,鼠标进入显示。
    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hover:SetAllPoints(row)
    row.hover:Hide()

    -- 折叠箭头(仅组):无按钮底纹的纯图标点击区,竖直居中、固定左缩进。
    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetSize(m.toggleSize, m.toggleSize)
    row.toggle:SetPoint("LEFT", row, "LEFT", m.edgePad, 0)
    row.toggle.icon = row.toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.toggle.icon:SetPoint("CENTER")

    -- 类型图标:与折叠区同列起点,组/元素统一对齐。
    row.typeIcon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.typeIcon:SetPoint("LEFT", row, "LEFT", m.edgePad, 0)

    row.nameText = T.CreateFontString(row, {
        template = Style.Font.NAV_ITEM,
        size = Style.BASE.NAV_ITEM_FONT_SIZE,
        justifyH = "LEFT",
        wordWrap = false,
        color = Color("TEXT_INACTIVE"),
    })
    -- 位置由 Refresh 统一负责(ClearAllPoints + 重新锚定),此处不预设锚点。
    if row.nameText.SetMaxLines then
        row.nameText:SetMaxLines(1)
    end

    row.nameEdit = T.CreateEditBox(row, { width = Sz(120), height = m.rowHeight - Sz(6), autoFocus = false })
    row.nameEdit:Hide()

    -- 批量编辑入口(仅组头使用):右对齐、竖直居中,Refresh 按 isGroup 显隐与绑定。
    row.batchButton = T.CreateButton(row, {
        width = Sz(40),
        height = m.controlSize,
        text = Text("VISUAL_BOARD_LAYER_BATCH_BUTTON", "批量"),
    })
    row.batchButton:SetPoint("RIGHT", row, "RIGHT", -m.edgePad, 0)
    row.batchButton:Hide()

    -- hover 反馈绑定在行级,与具体数据无关,创建时一次性挂好。
    row:SetScript("OnEnter", function() row.hover:Show() end)
    row:SetScript("OnLeave", function() row.hover:Hide() end)

    frame.rowPool[stableKey] = row
    return row
end

function LayerPanel:Refresh()
    local frame = self.frame
    if not frame then
        return
    end
    local callbacks = self.callbacks or {}
    local boardID = callbacks.GetBoardID and callbacks.GetBoardID() or nil
    local data = GetData()
    local board = boardID and data and data:GetBoard(boardID) or nil
    local selected = callbacks.GetSelectedIDs and callbacks.GetSelectedIDs() or {}

    local rows = BuildRows(board)

    -- 行池按 stableKey 存(契约 §9.1),先整池隐藏;本轮用到的行在主循环再 Show。
    for _, row in pairs(frame.rowPool) do
        row:Hide()
    end

    local m = RowMetrics()
    local gold = Color("KYRIAN_GOLD")
    local inactive = Color("TEXT_INACTIVE")
    local hover = Color("TEXT_HOVER")

    local y = -m.rowGap
    for _, model in ipairs(rows) do
        local row = AcquireRow(self, model.stableKey)
        -- 行池复用:每次 Refresh 完整重写该行所有数据绑定与脚本,
        -- 不残留上次的 id/文本/图标/显隐锁/点击闭包,杜绝行与元素错位。
        row.model = model
        row:SetHeight(m.rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.list.content, "TOPLEFT", m.edgePad, y)
        row:SetPoint("RIGHT", frame.list.content, "RIGHT", -m.edgePad, 0)

        local isGroup = model.kind == "group"
        local isSelected = selected[model.id] == true
        -- 缩进列:层级缩进 + 固定折叠箭头沟槽(无论是否有箭头都预留,保证同层图标列对齐)。
        local indentX = m.edgePad + model.indent * m.indentStep
        local glyphX = indentX + m.toggleSize + m.gap

        -- 折叠箭头(仅组且有成员):无底纹纯图标,落在缩进沟槽内,竖直居中。
        if isGroup and model.hasChildren then
            row.toggle:ClearAllPoints()
            row.toggle:SetPoint("LEFT", row, "LEFT", indentX, 0)
            row.toggle.icon:SetText(model.collapsed and "|A:NPE_ArrowRight:12:12|a" or "|A:NPE_ArrowDown:12:12|a")
            row.toggle:SetScript("OnClick", function()
                collapsed[model.id] = not collapsed[model.id]
                LayerPanel:Refresh()
            end)
            row.toggle:Show()
        else
            row.toggle:SetScript("OnClick", nil)
            row.toggle:Hide()
        end

        -- 类型图标:统一落在缩进沟槽之后,同层级所有行的图标/名称严格对齐。
        row.typeIcon:ClearAllPoints()
        row.typeIcon:SetPoint("LEFT", row, "LEFT", glyphX, 0)
        row.typeIcon:SetText(isGroup and "▣" or ElementGlyph(model.elementType))
        local iconColor = isSelected and gold or inactive
        row.typeIcon:SetTextColor(iconColor[1], iconColor[2], iconColor[3], iconColor[4] or 1)

        -- 名称:紧随类型图标,右边界让位右侧控件(组头让位"批量"按钮,元素直接撑到行右内边距);选中金色。
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", row.typeIcon, "RIGHT", m.gap, 0)
        if isGroup then
            row.nameText:SetPoint("RIGHT", row.batchButton, "LEFT", -m.gap, 0)
        else
            row.nameText:SetPoint("RIGHT", row, "RIGHT", -m.edgePad, 0)
        end
        row.nameText:SetText(tostring(model.name or ""))
        local nameColor = isSelected and gold or inactive
        row.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4] or 1)
        -- 先清空改名脚本再隐藏:避免 Hide 触发 OnEditFocusLost 时用到上一行的 model。
        row.nameEdit:SetScript("OnEnterPressed", nil)
        row.nameEdit:SetScript("OnEscapePressed", nil)
        row.nameEdit:SetScript("OnEditFocusLost", nil)
        row.nameEdit.committed = false
        row.nameEdit:Hide()
        row.nameText:Show()

        -- 批量编辑入口:仅组头显示;点击对组内全部 person 套同一属性(契约 §9.2)。
        if isGroup then
            row.batchButton:SetScript("OnClick", function()
                LayerPanel:OpenBatchPanel(model, boardID)
            end)
            row.batchButton:Show()
        else
            row.batchButton:SetScript("OnClick", nil)
            row.batchButton:Hide()
        end

        -- 选中高亮(整行金色底)与 hover 描底(淡白)。
        row.highlight:SetColorTexture(gold[1], gold[2], gold[3], 0.22)
        row.highlight:SetShown(isSelected)
        row.hover:SetColorTexture(hover[1], hover[2], hover[3], 0.08)
        row.hover:Hide()

        -- 点击选中(Shift 累加)/ 双击改名:闭包捕获本行 model,id 与显示一致。
        row:SetScript("OnClick", function()
            if callbacks.OnSelect then
                local additive = IsShiftKeyDown and IsShiftKeyDown() or false
                callbacks.OnSelect(model.id, isGroup, additive)
            end
        end)
        row:SetScript("OnDoubleClick", function()
            LayerPanel:BeginRename(row, model, boardID)
        end)

        -- 拖拽重排(MVP:仅顶层项)。复用行务必清空非顶层行的拖拽脚本。
        if model.indent == 0 then
            row:SetScript("OnDragStart", function()
                self.dragging = model.id
            end)
            row:SetScript("OnReceiveDrag", function()
                LayerPanel:HandleDrop(model.id, boardID)
            end)
            row:SetScript("OnDragStop", function()
                self.dragging = nil
            end)
        else
            row:SetScript("OnDragStart", nil)
            row:SetScript("OnReceiveDrag", nil)
            row:SetScript("OnDragStop", nil)
        end

        row:Show()
        y = y - (m.rowHeight + m.rowGap)
    end

    frame.list:SetContentHeight(math.max(Sz(10), -y + m.rowGap))

    if frame.emptyText then
        frame.emptyText:SetShown(#rows == 0)
    end
end

-- 顶层项之间重排:把被拖项移动到目标项位置,重算 z 并写回。
function LayerPanel:HandleDrop(targetID, boardID)
    local sourceID = self.dragging
    self.dragging = nil
    if not (sourceID and targetID and sourceID ~= targetID and boardID) then
        return
    end
    local data = GetData()
    local board = data and data:GetBoard(boardID) or nil
    if not board then
        return
    end
    local order = CollectTopLevelOrder(board)
    local fromIndex, toIndex
    for index, id in ipairs(order) do
        if id == sourceID then fromIndex = index end
        if id == targetID then toIndex = index end
    end
    if not (fromIndex and toIndex) then
        return
    end
    table.remove(order, fromIndex)
    if fromIndex < toIndex then
        toIndex = toIndex - 1
    end
    table.insert(order, toIndex, sourceID)
    data:SetElementOrder(boardID, order)
    self:Refresh()
end

function LayerPanel:BeginRename(row, model, boardID)
    local m = RowMetrics()
    local edit = row.nameEdit
    row.nameText:Hide()
    -- 编辑框对齐到名称起点(类型图标右侧),右边界与名称一致(组头让位批量按钮,元素撑到行右内边距)。
    edit:ClearAllPoints()
    edit:SetPoint("LEFT", row.typeIcon, "RIGHT", m.gap, 0)
    if model.kind == "group" then
        edit:SetPoint("RIGHT", row.batchButton, "LEFT", -m.gap, 0)
    else
        edit:SetPoint("RIGHT", row, "RIGHT", -m.edgePad, 0)
    end
    edit:SetText(tostring(model.name or ""))
    edit:Show()
    edit:SetFocus()
    edit:HighlightText()
    local function commit(value)
        local data = GetData()
        if data and boardID and value then
            if model.kind == "group" then
                data:RenameGroup(boardID, model.id, value)
            else
                data:SetElementName(boardID, model.id, value)
            end
        end
        edit:Hide()
        LayerPanel:Refresh()
    end
    edit:SetScript("OnEnterPressed", function(self)
        self.committed = true
        self:ClearFocus()
        commit(self:GetText())
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self.committed = true
        self:ClearFocus()
        edit:Hide()
        LayerPanel:Refresh()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if self.committed then
            self.committed = false
            return
        end
        commit(self:GetText())
    end)
end

-- RGB(0–1) → 6 位 HEX(person 颜色统一为 6 位 hex 字符串,见 data.lua NormalizeHexColor)。
local function RGBToHex(r, g, b)
    return string.format("%02X%02X%02X",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5))
end

-- 取组内首个 person 成员的当前属性作批量面板初值(预填,不改写)。
local function FirstGroupPersonParams(board, groupID)
    if type(board) ~= "table" then
        return nil
    end
    for _, element in ipairs(board.elements or {}) do
        if element.groupID == groupID and element.type == "person" then
            return type(element.params) == "table" and element.params or {}
        end
    end
    return nil
end

-- 组头"批量"小面板(契约 §9.2):对组内全部 person 批量套 circle.radius / circle.color / text.fontSize。
-- 提交直接走 data:BatchUpdateGroup(一条撤销,与本面板 rename/order 同走 data 的单一权威),
-- 再通知 callbacks.OnBatchEdit 让上层(canvas 等)刷新。
function LayerPanel:OpenBatchPanel(model, boardID)
    if not (self.frame and model and boardID) then
        return
    end
    local data = GetData()
    local board = data and data:GetBoard(boardID) or nil
    local params = board and FirstGroupPersonParams(board, model.id) or nil
    if not params then
        T.msg(Text("VISUAL_BOARD_LAYER_BATCH_NO_PERSON", "该组内没有可批量编辑的人物"))
        return
    end

    local panel = self.batchPanel
    if not panel then
        panel = CreateFrame("Frame", nil, self.frame)
        panel:SetSize(Sz(220), Sz(170))
        panel:SetFrameStrata("DIALOG")
        T.ApplyBackdrop(panel, { alpha = 0.95, style = "tooltip" })
        panel:EnableMouse(true)
        panel:Hide()

        panel.title = T.CreateGroupTitle(panel, {
            point = { "TOPLEFT", panel, "TOPLEFT", Sz(10), -Sz(8) },
            color = Color("KYRIAN_GOLD"),
            text = Text("VISUAL_BOARD_LAYER_BATCH_TITLE", "批量编辑组内成员"),
        })

        -- 三项编辑值持有在面板上,getter 读它、setter 写它,应用时一次性下发。
        panel.values = { radius = 58, fontSize = 19, color = "33CC66" }

        local body = CreateFrame("Frame", nil, panel)
        body:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -Sz(8))
        body:SetPoint("RIGHT", panel, "RIGHT", -Sz(10), 0)
        body:SetHeight(Sz(70))

        panel.radiusRow = T.CreateSliderRow(body, {
            y = 0,
            sliderWidth = Sz(180),
            label = "VISUAL_BOARD_LAYER_BATCH_RADIUS",
            min = 10, max = 200, step = 1,
            getter = function() return panel.values.radius end,
            setter = function(v) panel.values.radius = v end,
            formatter = function(v) return tostring(math.floor(v + 0.5)) end,
        })
        panel.fontRow = T.CreateSliderRow(body, {
            y = -Sz(40),
            sliderWidth = Sz(180),
            label = "VISUAL_BOARD_LAYER_BATCH_FONTSIZE",
            min = 8, max = 60, step = 1,
            getter = function() return panel.values.fontSize end,
            setter = function(v) panel.values.fontSize = v end,
            formatter = function(v) return tostring(math.floor(v + 0.5)) end,
        })

        panel.colorButton = T.CreateButton(panel, {
            width = Sz(95),
            height = Sz(22),
            text = Text("VISUAL_BOARD_LAYER_BATCH_COLOR", "圈颜色"),
        })
        panel.colorButton:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -Sz(6))
        panel.colorButton:SetScript("OnClick", function()
            T.ShowColorPicker({
                color = panel.values.color,
                onChange = function(r, g, b)
                    panel.values.color = RGBToHex(r, g, b)
                end,
            })
        end)

        panel.applyButton = T.CreateButton(panel, {
            width = Sz(95),
            height = Sz(22),
            text = Text("VISUAL_BOARD_LAYER_BATCH_APPLY", "应用"),
        })
        panel.applyButton:SetPoint("TOPRIGHT", body, "BOTTOMRIGHT", 0, -Sz(6))
        panel.applyButton:SetScript("OnClick", function()
            local fields = {
                params = {
                    circle = { radius = panel.values.radius, color = panel.values.color },
                    text = { fontSize = panel.values.fontSize },
                },
            }
            local boardForApply = panel.boardID
            local groupForApply = panel.groupID
            local d = GetData()
            if d and boardForApply and groupForApply then
                d:BatchUpdateGroup(boardForApply, groupForApply, fields)
                if self.callbacks and self.callbacks.OnBatchEdit then
                    self.callbacks.OnBatchEdit(groupForApply, fields)
                end
            end
            panel:Hide()
            LayerPanel:Refresh()
        end)

        self.batchPanel = panel
    end

    -- 每次打开:绑定当前组、用首个 person 当前值预填,刷新 slider 显示。
    panel.boardID = boardID
    panel.groupID = model.id
    local circle = type(params.circle) == "table" and params.circle or {}
    local text = type(params.text) == "table" and params.text or {}
    panel.values.radius = tonumber(circle.radius) or 58
    panel.values.color = type(circle.color) == "string" and circle.color or "33CC66"
    panel.values.fontSize = tonumber(text.fontSize) or 19
    panel.radiusRow.Refresh()
    panel.fontRow.Refresh()

    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", Sz(4), 0)
    panel:Show()
end

function LayerPanel:Create(parent)
    if self.frame then
        self.frame:SetParent(parent)
        return self.frame
    end
    local frame = CreateFrame("Frame", nil, parent)
    T.ApplyBackdrop(frame, { alpha = 0.18, style = "tooltip" })

    frame.list = T.CreateScrollPanel(frame, {
        point1 = { "TOPLEFT", frame, "TOPLEFT", Sz(6), -Sz(6) },
        point2 = { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Sz(6), Sz(6) },
        backdrop = true,
        backdropAlpha = 0.10,
    })

    frame.emptyText = T.CreateFontString(frame, {
        template = "GameFontDisableSmall",
        point = { "CENTER", frame.list.scroll, "CENTER", 0, 0 },
        size = Style.BASE.LABEL_FONT_SIZE,
        color = Color("TEXT_INACTIVE"),
        text = Text("VISUAL_BOARD_LAYER_EMPTY", "暂无图层"),
        justifyH = "CENTER",
    })
    frame.emptyText:Hide()

    frame.rowPool = {}

    self.frame = frame
    return frame
end

function LayerPanel:SetCallbacks(callbacks)
    self.callbacks = callbacks or {}
end
end)
