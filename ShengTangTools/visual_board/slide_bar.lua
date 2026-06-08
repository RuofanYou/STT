local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("visualBoard.editorLoaded", function()

-- 视觉战术板左栏 slide 幻灯片导航（editor-owner，契约 §6.1/§6.2）。
-- 朴素模块：竖排列出 board.slides（Keynote 式：序号 + 帧名 + 停留/过渡时长），点击选中“当前编辑帧”。
-- 数据全走 Data slide 冻结接口（AddSlide/DeleteSlide/RenameSlide/ReorderSlides/SetSlideMorph/
-- GetSlide/GetSlideCount），本模块不自存帧数据、不重算覆写合并。
-- 选中帧只写回 editor（callbacks.SetCurrentSlideIndex），由 editor 据此切当前编辑帧并重渲。
local SlideBar = {}
T.VisualBoardSlideBar = SlideBar

local Style = T.Style

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

local function GetData()
    return T.VisualBoardData
end

-- 幻灯片导航几何常量（全部经 Style.Scale）。竖排：每项占满列表宽，固定行高。
local function Metrics()
    return {
        edgePad = Sz(6),       -- 列表内边距 / 条目内文字内边距
        rowGap = Sz(6),        -- 条目竖向间距
        addHeight = Style.Scaled("BUTTON_HEIGHT"), -- “+新增幻灯片”按钮高度
        tileHeight = Sz(72),   -- 条目高度（序号+名 一行 + 停留行 + 过渡行）
        controlSize = Sz(16),  -- 删除按钮点击区
        morphHeight = Sz(18),  -- 时长输入高度
        durationWidth = Sz(60),-- hold/morph 时长输入宽度（需容纳右对齐 5 字符如 "100.0"；竖排占满宽时不再按比例算）
        rowH = Sz(22),         -- 停留/过渡每行行高（行距一致，标签与输入框在此行竖向居中）
    }
end

-- 读取 editor 注入的会话态（boardID / 当前帧）。
local function GetBoardID(self)
    local cb = self.callbacks or {}
    return cb.GetBoardID and cb.GetBoardID() or nil
end

local function GetCurrentSlideIndex(self)
    local cb = self.callbacks or {}
    return tonumber(cb.GetCurrentSlideIndex and cb.GetCurrentSlideIndex()) or 1
end

-- 选中某帧：写回 editor，由 editor 切当前编辑帧并立即重渲画布。本模块只刷新自身高亮。
-- 契约（editor 必须遵守）：cb.SetCurrentSlideIndex(index) 内除了写 currentSlideIndex，
-- 还必须立刻 RenderEdit() 把画布切到该帧；否则点帧后画布会停留在旧帧，要等下次交互才重渲。
-- 选帧不走 OnChanged（OnChanged 会清选中态），故重渲只能由 SetCurrentSlideIndex 自身负责。
local function SelectSlide(self, index)
    local cb = self.callbacks or {}
    if cb.SetCurrentSlideIndex then
        cb.SetCurrentSlideIndex(index)
    end
    SlideBar:Refresh()
end

-- 数据变动后统一收尾：通知 editor 刷新（可选），再重画帧条。
local function NotifyChanged(self)
    local cb = self.callbacks or {}
    if cb.OnChanged then
        cb.OnChanged()
    end
    SlideBar:Refresh()
end

-- 条目池按 slide.id 复用，避免增删/排序后条目与帧错位。
local function AcquireTile(self, slideID)
    local frame = self.frame
    local tile = frame.tilePool[slideID]
    if tile then
        return tile
    end
    local m = Metrics()
    tile = CreateFrame("Button", nil, frame.list.content)
    tile:SetHeight(m.tileHeight)
    tile:RegisterForClicks("LeftButtonUp")
    tile:RegisterForDrag("LeftButton")
    T.ApplyBackdrop(tile, { alpha = 0.18, style = "tooltip" })

    -- 选中高亮：整条目金色底。
    tile.highlight = tile:CreateTexture(nil, "BACKGROUND")
    tile.highlight:SetAllPoints(tile)
    tile.highlight:Hide()

    -- hover 描底（淡白）。
    tile.hover = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile.hover:SetAllPoints(tile)
    tile.hover:Hide()

    -- 帧名（序号/作者命名），双击改名。
    tile.nameText = T.CreateFontString(tile, {
        template = Style.Font.NAV_ITEM,
        size = Style.BASE.NAV_ITEM_FONT_SIZE,
        justifyH = "LEFT",
        wordWrap = false,
        color = Color("TEXT_INACTIVE"),
        point = { "TOPLEFT", tile, "TOPLEFT", m.edgePad, -m.edgePad },
    })
    tile.nameText:SetPoint("RIGHT", tile, "RIGHT", -(m.controlSize + m.edgePad), 0)
    if tile.nameText.SetMaxLines then
        tile.nameText:SetMaxLines(1)
    end

    -- 改名编辑框（双击呼出）。竖排时宽度随条目（占满），用左右锚而非固定宽。
    tile.nameEdit = T.CreateEditBox(tile, { width = Sz(80), height = Sz(18), autoFocus = false })
    tile.nameEdit:SetPoint("TOPLEFT", tile, "TOPLEFT", m.edgePad, -m.edgePad)
    tile.nameEdit:SetPoint("RIGHT", tile, "RIGHT", -(m.controlSize + m.edgePad), 0)
    tile.nameEdit:Hide()

    -- 删除按钮（右上角小叉，至少留 1 帧时禁用）。
    tile.deleteButton = CreateFrame("Button", nil, tile)
    tile.deleteButton:SetSize(m.controlSize, m.controlSize)
    tile.deleteButton:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -Sz(2), -Sz(2))
    tile.deleteButton.icon = tile.deleteButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.deleteButton.icon:SetPoint("CENTER")
    tile.deleteButton.icon:SetText("×")

    -- 停留/过渡两行对齐线（契约 §6.2）：每行=标签左对齐(统一左 x edgePad)+输入框右对齐(统一右 x -edgePad)，
    -- 标签与输入框锚到同一行竖向中心(rowCenterY)，故同行水平居中、跨卡片左右 x 一致。两行行距 rowH 一致。
    -- 底行=过渡(morph，首帧隐藏)，上行=停留(hold，所有帧)。行中心从条目底沿上推：过渡居 rowH/2，停留再 +rowH。
    local morphCenterY = m.edgePad + m.rowH * 0.5
    local holdCenterY = morphCenterY + m.rowH

    -- morph 标签 + 过渡时长输入（morphFromPrev，秒）。首帧无上一帧，无意义不显示（底行）。
    tile.morphLabel = T.CreateFontString(tile, {
        template = "GameFontDisableSmall",
        size = Style.BASE.SELECTOR_FONT_SIZE,
        justifyH = "LEFT",
        color = Color("TEXT_INACTIVE"),
        point = { "LEFT", tile, "BOTTOMLEFT", m.edgePad, morphCenterY },
        text = Text("VISUAL_BOARD_SLIDE_MORPH_LABEL", "过渡"),
    })
    tile.morphEdit = T.CreateEditBox(tile, {
        width = m.durationWidth,
        height = m.morphHeight,
        autoFocus = false,
        justifyH = "RIGHT",
        maxLetters = 5,
    })
    tile.morphEdit:SetPoint("RIGHT", tile, "BOTTOMRIGHT", -m.edgePad, morphCenterY)

    -- hold 标签 + 停留时长输入（holdTime，秒，§6.2）。所有帧都有，置于过渡行之上（上行）。
    tile.holdLabel = T.CreateFontString(tile, {
        template = "GameFontDisableSmall",
        size = Style.BASE.SELECTOR_FONT_SIZE,
        justifyH = "LEFT",
        color = Color("TEXT_INACTIVE"),
        point = { "LEFT", tile, "BOTTOMLEFT", m.edgePad, holdCenterY },
        text = Text("VISUAL_BOARD_SLIDE_HOLD_LABEL", "停留"),
    })
    tile.holdEdit = T.CreateEditBox(tile, {
        width = m.durationWidth,
        height = m.morphHeight,
        autoFocus = false,
        justifyH = "RIGHT",
        maxLetters = 5,
    })
    tile.holdEdit:SetPoint("RIGHT", tile, "BOTTOMRIGHT", -m.edgePad, holdCenterY)

    -- 字段说明 tooltip（复用 T.UITooltip.AttachSimple；HookScript 一次性，随条目复用不重挂）。
    -- 挂在输入框（天然可悬停），文案走 locale 键，enUS 权威，三语补齐。
    if T.UITooltip then
        T.UITooltip.AttachSimple(tile.holdEdit, Text("VISUAL_BOARD_SLIDE_HOLD_TIP", "本帧静止停留时长（秒）"), { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
        T.UITooltip.AttachSimple(tile.morphEdit, Text("VISUAL_BOARD_SLIDE_MORPH_TIP", "从上一张幻灯片平滑切到本张的时长（秒）；第一张没有过渡"), { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
    end

    frame.tilePool[slideID] = tile
    return tile
end

-- 单帧条目数据绑定（每次 Refresh 完整重写，杜绝复用残留）。
local function BindTile(self, tile, slide, index, boardID, count, currentIndex)
    local m = Metrics()
    local gold = Color("KYRIAN_GOLD")
    local inactive = Color("TEXT_INACTIVE")
    local hover = Color("TEXT_HOVER")
    local isSelected = index == currentIndex

    tile.slideID = slide.id
    tile.slideIndex = index

    -- Keynote 式“序号. 名”：序号始终是 index（拖拽重排后即时反映新位置）。
    tile.nameText:SetText(index .. ". " .. tostring(slide.name or index))
    local nameColor = isSelected and gold or inactive
    tile.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4] or 1)

    -- 先清空改名脚本再隐藏：避免 Hide 触发 OnEditFocusLost 时用到上一帧的 index。
    tile.nameEdit:SetScript("OnEnterPressed", nil)
    tile.nameEdit:SetScript("OnEscapePressed", nil)
    tile.nameEdit:SetScript("OnEditFocusLost", nil)
    tile.nameEdit.committed = false
    tile.nameEdit:Hide()
    tile.nameText:Show()

    -- 选中金底 + hover 淡白。
    tile.highlight:SetColorTexture(gold[1], gold[2], gold[3], 0.22)
    tile.highlight:SetShown(isSelected)
    tile.hover:SetColorTexture(hover[1], hover[2], hover[3], 0.08)
    tile.hover:Hide()
    tile:SetScript("OnEnter", function() if not isSelected then tile.hover:Show() end end)
    tile:SetScript("OnLeave", function() tile.hover:Hide() end)

    -- 点击选中当前帧。
    tile:SetScript("OnClick", function()
        SelectSlide(self, index)
    end)
    -- 双击改名。
    tile:SetScript("OnDoubleClick", function()
        SlideBar:BeginRename(tile, slide, index, boardID)
    end)

    -- 删除：至少保留 1 帧时禁用。
    if count > 1 then
        tile.deleteButton.icon:SetTextColor(0.9, 0.4, 0.4, 1)
        tile.deleteButton:Enable()
        tile.deleteButton:SetScript("OnClick", function()
            local data = GetData()
            if data and boardID and data:DeleteSlide(boardID, index) then
                -- 删除后当前帧可能越界，由 editor 在 OnChanged 内 clamp；这里仅通知刷新。
                NotifyChanged(self)
            end
        end)
        tile.deleteButton:Show()
    else
        tile.deleteButton:SetScript("OnClick", nil)
        tile.deleteButton:Hide()
    end

    -- hold 输入（停留时长，秒，§6.2）：所有帧都有，绑定 SetSlideHold。
    tile.holdLabel:Show()
    tile.holdEdit:SetText(string.format("%.1f", tonumber(slide.holdTime) or 0))
    tile.holdEdit:SetScript("OnEnterPressed", function(editSelf)
        local data = GetData()
        local seconds = tonumber(editSelf:GetText())
        if data and boardID and seconds and data.SetSlideHold then
            data:SetSlideHold(boardID, index, seconds)
        end
        editSelf:ClearFocus()
        NotifyChanged(self)
    end)
    tile.holdEdit:SetScript("OnEscapePressed", function(editSelf)
        editSelf:ClearFocus()
        SlideBar:Refresh()
    end)
    tile.holdEdit:Show()

    -- morph 输入（过渡时长，秒）：首帧无上一帧，隐藏；其余帧绑定 SetSlideMorph。
    if index > 1 then
        tile.morphLabel:Show()
        tile.morphEdit:SetText(string.format("%.1f", tonumber(slide.morphFromPrev) or 0))
        tile.morphEdit:SetScript("OnEnterPressed", function(editSelf)
            local data = GetData()
            local seconds = tonumber(editSelf:GetText())
            if data and boardID and seconds then
                data:SetSlideMorph(boardID, index, seconds)
            end
            editSelf:ClearFocus()
            NotifyChanged(self)
        end)
        tile.morphEdit:SetScript("OnEscapePressed", function(editSelf)
            editSelf:ClearFocus()
            SlideBar:Refresh()
        end)
        tile.morphEdit:Show()
    else
        tile.morphLabel:Hide()
        tile.morphEdit:SetScript("OnEnterPressed", nil)
        tile.morphEdit:SetScript("OnEscapePressed", nil)
        tile.morphEdit:Hide()
    end

    -- 拖拽排序：拖起记源 id，落到目标帧触发重排。
    tile:SetScript("OnDragStart", function()
        self.dragging = slide.id
    end)
    tile:SetScript("OnReceiveDrag", function()
        SlideBar:HandleDrop(slide.id, boardID)
    end)
    tile:SetScript("OnDragStop", function()
        self.dragging = nil
    end)
end

-- 拖拽落点：把源帧移动到目标帧位置，按 slide.id 数组重排写回 ReorderSlides。
function SlideBar:HandleDrop(targetID, boardID)
    local sourceID = self.dragging
    self.dragging = nil
    if not (sourceID and targetID and sourceID ~= targetID and boardID) then
        return
    end
    local data = GetData()
    local board = data and data:GetBoard(boardID) or nil
    if not board or type(board.slides) ~= "table" then
        return
    end
    local order = {}
    local fromIndex, toIndex
    for index, slide in ipairs(board.slides) do
        order[index] = slide.id
        if slide.id == sourceID then fromIndex = index end
        if slide.id == targetID then toIndex = index end
    end
    if not (fromIndex and toIndex) then
        return
    end
    table.remove(order, fromIndex)
    if fromIndex < toIndex then
        toIndex = toIndex - 1
    end
    table.insert(order, toIndex, sourceID)
    if data:ReorderSlides(boardID, order) then
        NotifyChanged(self)
    end
end

-- 双击改名：呼出内联编辑框，回车/失焦提交 RenameSlide，Esc 取消。
function SlideBar:BeginRename(tile, slide, index, boardID)
    local edit = tile.nameEdit
    tile.nameText:Hide()
    edit:SetText(tostring(slide.name or index))
    edit:Show()
    edit:SetFocus()
    edit:HighlightText()
    local function commit(value)
        local data = GetData()
        if data and boardID and value then
            data:RenameSlide(boardID, index, value)
        end
        edit:Hide()
        NotifyChanged(SlideBar)
    end
    edit:SetScript("OnEnterPressed", function(editSelf)
        editSelf.committed = true
        editSelf:ClearFocus()
        commit(editSelf:GetText())
    end)
    edit:SetScript("OnEscapePressed", function(editSelf)
        editSelf.committed = true
        editSelf:ClearFocus()
        edit:Hide()
        SlideBar:Refresh()
    end)
    edit:SetScript("OnEditFocusLost", function(editSelf)
        if editSelf.committed then
            editSelf.committed = false
            return
        end
        commit(editSelf:GetText())
    end)
end

function SlideBar:Refresh()
    local frame = self.frame
    if not frame then
        return
    end
    local boardID = GetBoardID(self)
    local data = GetData()
    local board = boardID and data and data:GetBoard(boardID) or nil
    local slides = (type(board) == "table" and type(board.slides) == "table") and board.slides or {}
    local count = #slides
    local currentIndex = GetCurrentSlideIndex(self)

    -- 条目池整批隐藏，本轮用到的再 Show；按 slide.id 复用避免错位。
    for _, tile in pairs(frame.tilePool) do
        tile:Hide()
    end

    local m = Metrics()
    local content = frame.list.content
    -- 竖向 y 递减布局：条目自上而下排列，占满列表宽（左右锚到 content）。
    local y = -m.rowGap
    for index, slide in ipairs(slides) do
        local tile = AcquireTile(self, slide.id)
        BindTile(self, tile, slide, index, boardID, count, currentIndex)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", content, "TOPLEFT", m.edgePad, y)
        tile:SetPoint("RIGHT", content, "RIGHT", -m.edgePad, 0)
        tile:Show()
        y = y - (m.tileHeight + m.rowGap)
    end

    -- “+新增幻灯片”按钮：接在最后一项之下，占满列表宽；新增后选中新帧。
    frame.addButton:ClearAllPoints()
    frame.addButton:SetPoint("TOPLEFT", content, "TOPLEFT", m.edgePad, y)
    frame.addButton:SetPoint("RIGHT", content, "RIGHT", -m.edgePad, 0)
    frame.addButton:SetShown(board ~= nil)
    if board ~= nil then
        y = y - (m.addHeight + m.rowGap)
    end

    frame.list:SetContentHeight(math.max(Sz(10), -y + m.rowGap))

    -- 空状态提示（无板）。
    if frame.emptyText then
        frame.emptyText:SetShown(board == nil)
    end
end

function SlideBar:Create(parent)
    if self.frame then
        self.frame:SetParent(parent)
        self.frame:ClearAllPoints()
        self.frame:SetAllPoints(parent)
        self:Refresh()
        return self.frame
    end
    local frame = CreateFrame("Frame", nil, parent)

    frame.tilePool = {}

    local m = Metrics()
    -- 竖向滚动容器（复用 CreateScrollPanel，与图层面板同款），容纳多帧条目。
    frame.list = T.CreateScrollPanel(frame, {
        point1 = { "TOPLEFT", frame, "TOPLEFT", 0, 0 },
        point2 = { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0 },
    })

    -- “+新增幻灯片”按钮置于滚动内容内，随列表滚动，占满列表宽（锚点在 Refresh 内设）。
    frame.addButton = T.CreateButton(frame.list.content, {
        height = m.addHeight,
        text = Text("VISUAL_BOARD_SLIDE_ADD", "+ 新增幻灯片"),
    })
    frame.addButton:SetScript("OnClick", function()
        local boardID = GetBoardID(self)
        local data = GetData()
        if not (data and boardID) then
            return
        end
        local _, index = data:AddSlide(boardID)
        if index then
            -- 加帧后选中新帧（写回 editor），再统一刷新。
            local cb = self.callbacks or {}
            if cb.SetCurrentSlideIndex then
                cb.SetCurrentSlideIndex(index)
            end
            NotifyChanged(self)
        end
    end)

    frame.emptyText = T.CreateFontString(frame, {
        template = "GameFontDisableSmall",
        point = { "CENTER", frame.list.scroll, "CENTER", 0, 0 },
        size = Style.BASE.LABEL_FONT_SIZE,
        color = Color("TEXT_INACTIVE"),
        text = Text("VISUAL_BOARD_SLIDE_EMPTY", "请先选择或新建战术板"),
        justifyH = "CENTER",
    })
    frame.emptyText:Hide()
    frame:HookScript("OnSizeChanged", function()
        SlideBar:Refresh()
    end)

    self.frame = frame
    return frame
end

function SlideBar:SetCallbacks(callbacks)
    self.callbacks = callbacks or {}
end
end)
