-- screen_reminder/panel_list.lua
-- 左列：指示器列表 + 新建/复制/删除按钮 + 拖拽排序

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

local Schema = T.ScreenReminderSchema
local List = {}
T.ScreenReminderPanelList = List

local KIND_LABEL = {
    text = { fallback = "文本", icon = "T" },
    icon = { fallback = "图标", icon = "I" },
    bar  = { fallback = "计时条", icon = "B" },
    circle = { fallback = "环形", icon = "O" },
}

local function ResolveKindLabel(kind)
    local meta = KIND_LABEL[kind] or KIND_LABEL.text
    return L["SR_KIND_" .. string.upper(kind or "TEXT")] or meta.fallback
end

local function ReleaseKindSelector(self)
    if not self.kindSelector then
        return
    end
    self.kindSelector:Hide()
    self.kindSelector:SetParent(nil)
    self.kindSelector = nil
end

function List:Create(parent, opts)
    opts = opts or {}
    ReleaseKindSelector(self)

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(opts.width or 170, opts.height or 412)
    if opts.point then frame:SetPoint(unpack(opts.point)) end

    -- 标题
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    title:SetText(L["SR_LIST_TITLE"] or "指示器列表")

    -- 顶部按钮区：[新建▼][复制][删除]（箭头用 NPE_ArrowDown atlas）
    local btnNew = T.CreateActionButton(frame, {
        width = 66, height = 22,
        point = { "TOPLEFT", frame, "TOPLEFT", 0, -22 },
        textFn = function() return (L["SR_BTN_NEW"] or "新建") .. " |A:NPE_ArrowDown:10:10|a" end,
        onClick = function()
            if List.onNewClick then List:onNewClick() end
        end,
    })
    local btnClone = T.CreateActionButton(frame, {
        width = 46, height = 22,
        point = { "LEFT", btnNew, "RIGHT", 4, 0 },
        textFn = function() return L["SR_BTN_CLONE"] or "复制" end,
        onClick = function()
            if List.onCloneClick then List:onCloneClick() end
        end,
    })
    local btnDel = T.CreateActionButton(frame, {
        width = 46, height = 22,
        point = { "LEFT", btnClone, "RIGHT", 4, 0 },
        textFn = function() return L["SR_BTN_DELETE"] or "删除" end,
        onClick = function()
            if List.onDeleteClick then List:onDeleteClick() end
        end,
    })

    frame.btnNew = btnNew

    -- 列表滚动区
    local scroll = T.CreateSimpleScroll(frame, {})
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -50)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 0)

    self.frame = frame
    self.scroll = scroll
    self.rows = {}
    return frame
end

local ROW_HEIGHT = 26
local ROW_GAP = 2

function List:GetRowsSnapshot()
    return self.rows
end

function List:OnReorder(rowFrom, rowTarget)
    if not rowFrom or not rowFrom.data then return end
    local indicators = Schema.ListIndicators()
    local fromID = rowFrom.data.id
    local targetID = rowTarget and rowTarget.data and rowTarget.data.id
    local newOrder = {}
    if targetID then
        for _, ind in ipairs(indicators) do
            if ind.id == fromID then
                -- skip; insert before target
            elseif ind.id == targetID then
                newOrder[#newOrder + 1] = fromID
                newOrder[#newOrder + 1] = ind.id
            else
                newOrder[#newOrder + 1] = ind.id
            end
        end
    else
        -- 没命中目标（拖到列表外）→ 移到末尾
        for _, ind in ipairs(indicators) do
            if ind.id ~= fromID then
                newOrder[#newOrder + 1] = ind.id
            end
        end
        newOrder[#newOrder + 1] = fromID
    end
    Schema.Reorder(newOrder)
    if List.onChanged then List:onChanged() end
end

function List:Refresh()
    -- 释放或隐藏所有行
    for _, row in ipairs(self.rows) do
        row:Hide()
    end

    local indicators = Schema.ListIndicators()
    local selectedID = Schema.GetRoot().selectedIndicatorID

    for i, ind in ipairs(indicators) do
        local row = self.rows[i]
        if not row then
            row = T.CreateDraggableListRow(self.scroll.content, {
                width = 168, height = ROW_HEIGHT,
                getRowsSnapshot = function() return self:GetRowsSnapshot() end,
                onReorder = function(rowFrom, rowTarget)
                    self:OnReorder(rowFrom, rowTarget)
                end,
                onSelect = function(r)
                    if r.data and r.data.id then
                        if IsShiftKeyDown and IsShiftKeyDown() and List.onPushClick then
                            List:onPushClick(r.data.id)
                            return
                        end
                        Schema.SetSelectedIndicator(r.data.id)
                        self:Refresh()
                        if List.onSelected then List:onSelected(r.data.id) end
                    end
                end,
            })
            -- 左侧 4px 金色色条作为"可拖拽"视觉提示（替代 ☰ Unicode 字符）
            row.handle = row:CreateTexture(nil, "ARTWORK")
            row.handle:SetSize(3, 18)
            row.handle:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.handle:SetColorTexture(0.85, 0.65, 0.18, 0.7)

            row.enableCheck = row:CreateTexture(nil, "ARTWORK")
            row.enableCheck:SetSize(12, 12)
            row.enableCheck:SetPoint("LEFT", row, "LEFT", 14, 0)
            row.enableCheck:SetAtlas("common-icon-checkmark-yellow")

            row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameFS:SetPoint("LEFT", row.enableCheck, "RIGHT", 6, 0)
            row.nameFS:SetPoint("RIGHT", row, "RIGHT", -42, 0)
            row.nameFS:SetJustifyH("LEFT")
            if row.nameFS.SetWordWrap then row.nameFS:SetWordWrap(false) end

            row.kindFS = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.kindFS:SetPoint("RIGHT", row, "RIGHT", -6, 0)

            self.rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -((i - 1) * (ROW_HEIGHT + ROW_GAP)))
        row:SetData(ind)
        row:Show()
        row.handle:SetColorTexture(0.85, 0.65, 0.18, 0.7)
        row.nameFS:SetText(ind.name or "")
        if ind.exclusiveMode == true then
            row.handle:SetColorTexture(0.46, 0.46, 0.5, 0.85)
        end
        row.kindFS:SetText(ResolveKindLabel(ind.kind))
        row.enableCheck:SetShown(ind.enabled ~= false)
        row:SetSelected(ind.id == selectedID)
    end

    local total = #indicators
    self.scroll:SetContentHeight(total * (ROW_HEIGHT + ROW_GAP))
end

-- 新建下拉：弹出 4 类菜单，借助 widget_api 的 SelectorButton 内部菜单系统
function List:OpenKindMenu()
    -- 使用 selectorbutton-like 直接构建一个临时按钮触发菜单。
    -- 但更简单：用一个隐藏的 SelectorButton 当锚点，按钮 onSelect 直接走 onPick。
    if not self.kindSelector then
        self.kindSelector = T.CreateSelectorButton(self.frame, {
            width = 1, height = 1,
            point = { "TOPLEFT", self.frame.btnNew, "BOTTOMLEFT", 0, -2 },
            label = "",
            valueText = "",
            items = {
                { value = "text",   text = L["SR_KIND_TEXT"]   or "文本" },
                { value = "icon",   text = L["SR_KIND_ICON"]   or "图标" },
                { value = "bar",    text = L["SR_KIND_BAR"]    or "计时条" },
                { value = "circle", text = L["SR_KIND_CIRCLE"] or "环形" },
            },
            onSelect = function(value)
                if List.onPickKind then List:onPickKind(value) end
            end,
            ownerFrame = self.frame:GetParent() or UIParent,
        })
        self.kindSelector:SetAlpha(0)
    end
    -- 模拟点击让菜单弹出
    self.kindSelector:Click()
end

end)
