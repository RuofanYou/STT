local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("visualBoard.editorLoaded", function()

local IconPicker = {}
T.VisualBoardIconPicker = IconPicker

local Style = T.Style
local GRID_COLUMNS = 8

local function S(value)
    return Style.Scale(value)
end

local function Text(key, fallback)
    local value = L and L[key]
    if value == nil or value == key then
        return fallback or key
    end
    return value
end

local function GetSpecIcons()
    return T.VisualBoardSpecIcons
end

-- 弹出层单例
local function EnsureFrame()
    if IconPicker.frame then
        return IconPicker.frame
    end

    local cellSize = S(40)
    local cellGap = S(6)
    local pad = S(12)
    local panelWidth = GRID_COLUMNS * (cellSize + cellGap) + pad * 2
    local panelHeight = S(440)

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(panelWidth, panelHeight)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(true)
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    T.ApplyBackdrop(frame, { alpha = 0.96, style = "tooltip" })
    frame:Hide()

    frame.cellSize = cellSize
    frame.cellGap = cellGap
    frame.pad = pad

    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            IconPicker:Close()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    frame.titleText = T.CreateGroupTitle(frame, {
        text = Text("VISUAL_BOARD_ICONPICKER_TITLE", "选择专精图标"),
        point = { "TOPLEFT", frame, "TOPLEFT", pad, -S(10) },
        fontSize = 14,
        color = Style.Color.KYRIAN_GOLD,
    })

    frame.closeButton = T.CreateButton(frame, { width = S(24), height = S(24), text = "x" })
    frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -S(8), -S(8))
    frame.closeButton:SetScript("OnClick", function()
        IconPicker:Close()
    end)

    frame.searchBox = T.CreateEditBox(frame, {
        width = panelWidth - pad * 2,
        height = Style.Scaled("DROPDOWN_HEIGHT"),
        autoFocus = false,
        placeholder = Text("VISUAL_BOARD_ICONPICKER_SEARCH", "搜索职业 / 专精…"),
    })
    frame.searchBox:SetPoint("TOPLEFT", frame.titleText, "BOTTOMLEFT", 0, -S(8))
    frame.searchBox:SetScript("OnTextChanged", function(self)
        IconPicker:RenderList(self:GetText())
    end)
    frame.searchBox:SetScript("OnEscapePressed", function()
        IconPicker:Close()
    end)

    frame.list = T.CreateScrollPanel(frame, {
        point1 = { "TOPLEFT", frame.searchBox, "BOTTOMLEFT", 0, -S(8) },
        point2 = { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -S(8), S(10) },
        backdrop = true,
        backdropAlpha = 0.12,
    })

    frame.emptyText = T.CreateFontString(frame, {
        template = "GameFontDisableSmall",
        size = Style.BASE.LABEL_FONT_SIZE,
        point = { "CENTER", frame.list.scroll, "CENTER", 0, 0 },
        text = Text("VISUAL_BOARD_ICONPICKER_EMPTY", "没有匹配的图标"),
        color = Style.Color.TEXT_INACTIVE,
    })
    frame.emptyText:Hide()

    frame.cells = {}
    frame.headers = {}

    IconPicker.frame = frame
    return frame
end

-- 取出一个单元格按钮(图标格),用对象池复用
local function AcquireCell(frame, index)
    local cell = frame.cells[index]
    if cell then
        return cell
    end
    cell = CreateFrame("Button", nil, frame.list.content)
    cell:SetSize(frame.cellSize, frame.cellSize)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints(cell)
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    cell.border = cell:CreateTexture(nil, "OVERLAY")
    cell.border:SetPoint("TOPLEFT", cell, "TOPLEFT", -S(2), S(2))
    cell.border:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", S(2), -S(2))
    cell.border:SetColorTexture(unpack(Style.Color.KYRIAN_GOLD))
    cell.border:Hide()

    cell:SetScript("OnEnter", function(self)
        self.border:Show()
        if self.label then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label)
            GameTooltip:Show()
        end
    end)
    cell:SetScript("OnLeave", function(self)
        self.border:Hide()
        GameTooltip:Hide()
    end)
    cell:SetScript("OnClick", function(self)
        if IconPicker.onPick and self.iconID then
            IconPicker.onPick({ icon = self.iconID, label = self.label })
        end
        IconPicker:Close()
    end)

    frame.cells[index] = cell
    return cell
end

-- 取出一个职业分组标题,用对象池复用
local function AcquireHeader(frame, index)
    local header = frame.headers[index]
    if header then
        return header
    end
    header = T.CreateFontString(frame.list.content, {
        template = "GameFontNormal",
        size = Style.BASE.SUBGROUP_FONT_SIZE,
        justifyH = "LEFT",
    })
    frame.headers[index] = header
    return header
end

-- 渲染:无 query 时按职业分组网格;有 query 时扁平搜索结果
function IconPicker:RenderList(query)
    local frame = self.frame
    if not frame then
        return
    end
    local specIcons = GetSpecIcons()
    if not specIcons then
        return
    end

    local cellSize = frame.cellSize
    local cellGap = frame.cellGap
    local pad = frame.pad
    local cellStep = cellSize + cellGap

    local content = frame.list.content
    for _, cell in ipairs(frame.cells) do
        cell:Hide()
    end
    for _, header in ipairs(frame.headers) do
        header:Hide()
    end

    query = type(query) == "string" and query:gsub("^%s+", ""):gsub("%s+$", "") or ""

    local cellIndex = 0
    local headerIndex = 0
    local y = -S(4)
    local rowCount = 0

    local function placeGridItem(iconID, label)
        cellIndex = cellIndex + 1
        local cell = AcquireCell(frame, cellIndex)
        local col = rowCount % GRID_COLUMNS
        if col == 0 and rowCount > 0 then
            y = y - cellStep
        end
        local x = pad + col * cellStep
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        cell.icon:SetTexture(iconID)
        cell.iconID = iconID
        cell.label = label
        cell:Show()
        rowCount = rowCount + 1
    end

    if query ~= "" then
        local results = specIcons:Search(query)
        for _, item in ipairs(results or {}) do
            placeGridItem(item.icon, item.label)
        end
        if rowCount > 0 then
            y = y - cellStep
        end
        frame.emptyText:SetShown(rowCount == 0)
    else
        frame.emptyText:Hide()
        local classes = specIcons:GetClasses()
        for _, classInfo in ipairs(classes or {}) do
            headerIndex = headerIndex + 1
            local header = AcquireHeader(frame, headerIndex)
            local color = classInfo.color or { r = 1, g = 1, b = 1 }
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y - S(4))
            header:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
            header:SetText(tostring(classInfo.className or classInfo.classFile or ""))
            header:Show()
            y = y - S(24)
            rowCount = 0

            for _, spec in ipairs(classInfo.specs or {}) do
                local label = string.format("%s · %s", tostring(spec.name or ""), tostring(classInfo.className or ""))
                placeGridItem(spec.icon, label)
            end
            if rowCount > 0 then
                y = y - cellStep
            end
            y = y - S(6)
            rowCount = 0
        end
    end

    frame.list:SetContentHeight(math.max(S(10), -y + S(10)))
end

function IconPicker:Open(anchor, onPick)
    local frame = EnsureFrame()
    self.onPick = onPick
    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", S(8), 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame.searchBox:SetText("")
    self:RenderList("")
    frame:Show()
    frame:Raise()
end

function IconPicker:Close()
    if self.frame then
        self.frame:Hide()
    end
    self.onPick = nil
end
end)
