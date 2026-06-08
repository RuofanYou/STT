-- screen_reminder/widgets.lua
-- 屏幕提醒 V2 专用薄包装。**只允许包含两个新增函数**，其余一律复用 widget_api / smooth_scroll / bar_widget。
--   1) T.ShowColorPicker(opts) - 包装原生 ColorPickerFrame
--   2) T.CreateDraggableListRow(parent, def) - 包装 SetMovable + OnDragStart/Stop
-- 红线：在此文件添加任何其他 widget 工厂均视为造轮子，违反 spec §1.4。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

-- ──────────────────────────────────────────────────────────────────────
-- 1) ShowColorPicker
--    opts = { color = "RRGGBB" or {r,g,b}, hasOpacity = false, onChange = fn(r,g,b), onCancel = fn() }
-- ──────────────────────────────────────────────────────────────────────
local function NormalizeColor(color)
    if type(color) == "table" then
        return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    end
    if type(color) == "string" and #color >= 6 then
        local r = (tonumber(color:sub(1, 2), 16) or 255) / 255
        local g = (tonumber(color:sub(3, 4), 16) or 255) / 255
        local b = (tonumber(color:sub(5, 6), 16) or 255) / 255
        return r, g, b, 1
    end
    return 1, 1, 1, 1
end

function T.ShowColorPicker(opts)
    opts = type(opts) == "table" and opts or {}
    local r, g, b, a = NormalizeColor(opts.color)

    ColorPickerFrame:Hide()
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame:SetClampedToScreen(true)

    local function readPickerColor()
        local cr, cg, cb = ColorPickerFrame:GetColorRGB()
        return cr, cg, cb
    end

    local function commit()
        local cr, cg, cb = readPickerColor()
        if opts.onChange then opts.onChange(cr, cg, cb) end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            hasOpacity = opts.hasOpacity == true,
            r = r, g = g, b = b, opacity = a,
            swatchFunc = commit,
            opacityFunc = commit,
            cancelFunc = function()
                if opts.onCancel then opts.onCancel() end
            end,
        })
    else
        ColorPickerFrame.hasOpacity = opts.hasOpacity == true
        ColorPickerFrame.opacity = 1 - (a or 1)
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame.func = commit
        ColorPickerFrame.opacityFunc = commit
        ColorPickerFrame.cancelFunc = function()
            if opts.onCancel then opts.onCancel() end
        end
        ColorPickerFrame:Show()
    end
end

-- ──────────────────────────────────────────────────────────────────────
-- 2) CreateDraggableListRow
--    def = {
--      width, height,           -- 行尺寸
--      onSelect = fn(row),
--      onReorder = fn(rowDraggedFrom, rowDraggedTo),  -- 由 Drop 命中目标行后回调
--      getRowsSnapshot = fn() -> {row1, row2, ...}    -- 拖拽时遍历兄弟行做命中
--    }
--    row 实例提供 :SetSelected(bool) / :SetData(any) / 内部维护拖拽逻辑。
-- ──────────────────────────────────────────────────────────────────────
function T.CreateDraggableListRow(parent, def)
    def = type(def) == "table" and def or {}
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(def.width or 168, def.height or 26)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp")
    row:SetMovable(true)
    row:RegisterForDrag("LeftButton")

    -- 视觉
    if row.SetBackdrop then
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.1, 0.1, 0.12, 0.6)
        row:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.8)
    end

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.25, 0.45, 0.8, 0.25)

    -- 选中高亮：金色横条 + 内描边
    row.selectedBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.selectedBg:SetAllPoints()
    row.selectedBg:SetColorTexture(0.85, 0.65, 0.18, 0.55)
    row.selectedBg:Hide()

    function row:SetSelected(state)
        self.selectedBg:SetShown(state == true)
    end

    function row:SetData(data)
        self.data = data
    end

    -- 拖拽
    local originalParent
    row:SetScript("OnDragStart", function(self)
        originalParent = self:GetParent()
        self:SetFrameStrata("TOOLTIP")
        self:StartMoving()
        self.isDragging = true
    end)

    row:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetFrameStrata(originalParent and originalParent:GetFrameStrata() or "DIALOG")
        self.isDragging = false

        if not def.onReorder or not def.getRowsSnapshot then
            return
        end

        -- 找到鼠标位置命中的目标行（用 row top 比较鼠标 Y）
        local mouseX, mouseY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        mouseY = mouseY / scale

        local rows = def.getRowsSnapshot() or {}
        local target = nil
        for _, sibling in ipairs(rows) do
            if sibling ~= self and sibling.GetTop then
                local top = sibling:GetTop()
                local bottom = sibling:GetBottom()
                if top and bottom and mouseY <= top and mouseY >= bottom then
                    target = sibling
                    break
                end
            end
        end
        def.onReorder(self, target)
    end)

    row:SetScript("OnClick", function(self)
        if def.onSelect then def.onSelect(self) end
    end)

    return row
end

end)
