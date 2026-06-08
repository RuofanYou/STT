-- screen_reminder/panel_config.lua
-- 右列：当前选中 indicator 的配置面板。
-- 统一行布局：[LABEL固定100宽 左对齐] [控件填充剩余宽度] [value/箭头右对齐]
-- 每行固定高度 ROW_HEIGHT=28。
-- 4 个折叠分区：触发 / 位置 / 样式 / 倒数。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

local Schema = T.ScreenReminderSchema
local Config = {}
T.ScreenReminderPanelConfig = Config

local ROW_HEIGHT = 28
local LABEL_WIDTH = 96
local VALUE_WIDTH = 56

local ANCHOR_POINTS = {
    "TOP", "BOTTOM", "LEFT", "RIGHT",
    "CENTER",
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
}

local STACK_DIRECTIONS = { "UP", "DOWN", "LEFT", "RIGHT" }
local SPELL_DISPLAY_ITEMS = {
    { value = "text", text = L["SR_SPELL_DISPLAY_TEXT"] or "仅文本" },
    { value = "icon", text = L["SR_SPELL_DISPLAY_ICON"] or "仅图标" },
    { value = "iconText", text = L["SR_SPELL_DISPLAY_ICON_TEXT"] or "图标+文本" },
}

local LEAD_MODE_ITEMS = {
    { value = "global", text = L["SR_LEAD_MODE_GLOBAL"] or "使用全局提前量" },
    { value = "custom", text = L["SR_LEAD_MODE_CUSTOM"] or "自定义提前量" },
}

local function AttachTooltip(frame, text)
    if T.UITooltip then
        T.UITooltip.AttachSimple(frame, text, { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
    end
end

local function ToItems(arr, labelMap)
    local list = {}
    for _, v in ipairs(arr) do
        list[#list + 1] = {
            value = v,
            text = (labelMap and labelMap[v]) or tostring(v),
        }
    end
    return list
end

local function PathSetter(getID, path)
    return function(value)
        local id = getID()
        if id then Schema.SetField(id, path, value) end
        if Config.onChanged then Config:onChanged() end
    end
end

local function PathGetter(getID, path, fallback)
    return function()
        local id = getID()
        if not id then return fallback end
        local v = Schema.GetField(id, path)
        if v == nil then return fallback end
        return v
    end
end

local function HexToRGB(hex)
    if type(hex) ~= "string" or #hex < 6 then return 1, 1, 1 end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
           (tonumber(hex:sub(3, 4), 16) or 255) / 255,
           (tonumber(hex:sub(5, 6), 16) or 255) / 255
end

local function RGBToHex(r, g, b)
    return string.format("%02X%02X%02X",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5))
end

-- ──────────────────────────────────────────────────────────────────────
-- 通用行容器：left label + 填充 control + right value
-- ──────────────────────────────────────────────────────────────────────
local function CreateRow(content, idx)
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT - 4)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((idx - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((idx - 1) * ROW_HEIGHT))
    return row
end

local function AddLabel(row, text)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", row, "LEFT", 4, 0)
    fs:SetWidth(LABEL_WIDTH)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    fs:SetTextColor(1, 0.86, 0.32, 1)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

-- ──────────────────────────────────────────────────────────────────────
-- Slider 行（用 12.0+ MinimalSliderWithSteppersTemplate）+ value 双击编辑
-- ──────────────────────────────────────────────────────────────────────
local function MakeSliderRow(content, idx, label, getter, setter, min, max, step, fmt, enabledGetter, tooltip)
    local row = CreateRow(content, idx)
    AddLabel(row, label)
    AttachTooltip(row, tooltip)

    -- value 区域：默认 FontString 显示；双击切换为 EditBox 精确输入
    local valueFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    valueFS:SetWidth(VALUE_WIDTH)
    valueFS:SetJustifyH("RIGHT")

    local valueEdit = CreateFrame("EditBox", nil, row)
    valueEdit:SetSize(VALUE_WIDTH, 18)
    valueEdit:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    valueEdit:SetFontObject("GameFontHighlightSmall")
    valueEdit:SetJustifyH("RIGHT")
    valueEdit:SetAutoFocus(false)
    valueEdit:SetMaxLetters(12)
    valueEdit:Hide()

    local slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH + 8, 0)
    slider:SetPoint("RIGHT", valueFS, "LEFT", -6, 0)
    AttachTooltip(slider, tooltip)

    local steps = math.max(1, math.floor((max - min) / step + 0.5))
    slider:Init(tonumber(getter()) or min, min, max, steps, {})
    if slider.SetTooltipText then slider:SetTooltipText("") end

    local function isEnabled()
        return not enabledGetter or enabledGetter() ~= false
    end

    local function quantize(v)
        v = tonumber(v) or min
        v = math.max(min, math.min(max, v))
        return math.floor((v - min) / step + 0.5) * step + min
    end

    local clickOverlay
    local function refresh()
        local v = quantize(getter())
        slider:SetValue(v)
        valueFS:SetText(fmt and fmt(v) or tostring(v))
        local enabled = isEnabled()
        if slider.SetEnabled then slider:SetEnabled(enabled) end
        slider:SetAlpha(enabled and 1 or 0.35)
        valueFS:SetTextColor(enabled and 1 or 0.45, enabled and 1 or 0.45, enabled and 1 or 0.45, 1)
        if clickOverlay then
            if clickOverlay.SetEnabled then
                clickOverlay:SetEnabled(enabled)
            elseif enabled and clickOverlay.Enable then
                clickOverlay:Enable()
            elseif clickOverlay.Disable then
                clickOverlay:Disable()
            end
        end
    end

    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if not isEnabled() then return end
        local q = quantize(value)
        setter(q)
        valueFS:SetText(fmt and fmt(q) or tostring(q))
    end)

    -- 双击 value 文字 → 切换到 EditBox 输入
    clickOverlay = CreateFrame("Button", nil, row)
    clickOverlay:SetAllPoints(valueFS)
    clickOverlay:EnableMouse(true)
    clickOverlay:RegisterForClicks("LeftButtonDown")
    local lastClick = 0
    clickOverlay:SetScript("OnClick", function()
        if not isEnabled() then return end
        local now = GetTime()
        if now - lastClick < 0.35 then
            -- 双击：进入编辑模式
            valueFS:Hide()
            clickOverlay:Hide()
            valueEdit:Show()
            valueEdit:SetText(tostring(quantize(getter())))
            valueEdit:SetFocus()
            valueEdit:HighlightText()
        end
        lastClick = now
    end)
    clickOverlay:SetScript("OnEnter", function()
        if T.UITooltip then
            T.UITooltip.Show(clickOverlay, { description = L["SR_DBLCLICK_EDIT"] or "双击精确输入" }, { anchor = "ANCHOR_TOP", x = 0, y = 0 })
        end
    end)
    clickOverlay:SetScript("OnLeave", function()
        if T.UITooltip then T.UITooltip.ScheduleHide() end
    end)

    local function commitEdit()
        if not isEnabled() then
            valueEdit:Hide()
            valueFS:Show()
            clickOverlay:Show()
            return
        end
        local v = tonumber(valueEdit:GetText())
        if v then
            local q = quantize(v)
            setter(q)
            slider:SetValue(q)
            valueFS:SetText(fmt and fmt(q) or tostring(q))
        end
        valueEdit:Hide()
        valueFS:Show()
        clickOverlay:Show()
    end
    local function cancelEdit()
        valueEdit:Hide()
        valueFS:Show()
        clickOverlay:Show()
    end
    valueEdit:SetScript("OnEnterPressed", function(self) commitEdit() self:ClearFocus() end)
    valueEdit:SetScript("OnEscapePressed", function(self) cancelEdit() self:ClearFocus() end)
    valueEdit:SetScript("OnEditFocusLost", function() commitEdit() end)

    refresh()
    return row
end

-- ──────────────────────────────────────────────────────────────────────
-- Dropdown 行（用 T.CreateSelectorButton 但放在我们自己的 row 里）
-- ──────────────────────────────────────────────────────────────────────
local function MakeDropdownRow(content, idx, label, items, getter, setter, ownerFrame, tooltip)
    local row = CreateRow(content, idx)
    AddLabel(row, label)
    AttachTooltip(row, tooltip)

    local btn
    btn = T.CreateSelectorButton(row, {
        width = 160, height = 22,
        label = "",
        labelWidth = 1,
        items = items,
        selectedValue = getter(),
        onSelect = function(value)
            setter(value)
            if btn and btn.SetSelectedValue then
                btn:SetSelectedValue(value)
            end
        end,
        ownerFrame = ownerFrame,
    })
    -- 双锚定：左侧 label 右边、右侧 row 右边，width 自动跟随，避免依赖 content:GetWidth()
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH + 8, 0)
    btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    AttachTooltip(btn, tooltip)
    return row
end

local function MakeSpellDisplayRow(content, idx, getID)
    MakeDropdownRow(content, idx, L["SR_SPELL_DISPLAY"] or "技能显示",
        SPELL_DISPLAY_ITEMS,
        PathGetter(getID, "style.spellTokenDisplay", "text"),
        PathSetter(getID, "style.spellTokenDisplay"), content)
end

-- ──────────────────────────────────────────────────────────────────────
-- Check 行
-- ──────────────────────────────────────────────────────────────────────
local function MakeCheckRow(content, idx, label, getter, setter, tooltip)
    local row = CreateRow(content, idx)
    AddLabel(row, label)
    local cb = T.CreateCheckbox(row, {
        point = { "LEFT", row, "LEFT", LABEL_WIDTH + 8, 0 },
        label = "",
        getter = getter,
        setter = setter,
    })
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            if T.UITooltip then
                T.UITooltip.Show(self, { description = tooltip }, { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
            end
        end)
        cb:SetScript("OnLeave", function()
            if T.UITooltip then T.UITooltip.ScheduleHide() end
        end)
    end
    return row
end

local function MakeRightCheckRow(content, idx, label, getter, setter, tooltip)
    local row = CreateRow(content, idx)
    local cb = T.CreateCheckbox(row, {
        point = { "RIGHT", row, "RIGHT", -4, 0 },
        label = "",
        getter = getter,
        setter = setter,
    })
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", row, "LEFT", 4, 0)
    fs:SetPoint("RIGHT", cb, "LEFT", -8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(label or "")
    fs:SetTextColor(1, 0.86, 0.32, 1)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            if T.UITooltip then
                T.UITooltip.Show(self, { description = tooltip }, { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
            end
        end)
        cb:SetScript("OnLeave", function()
            if T.UITooltip then T.UITooltip.ScheduleHide() end
        end)
    end
    return row
end

local function MakeEditRow(content, idx, label, getter, setter)
    local row = CreateRow(content, idx)
    AddLabel(row, label)

    local edit = T.CreateEditBox(row, {
        width = 180,
        height = 20,
        point = { "LEFT", row, "LEFT", LABEL_WIDTH + 8, 0 },
        fontObject = "GameFontHighlightSmall",
        autoFocus = false,
        maxLetters = 24,
    })
    edit:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    edit:SetText(tostring(getter() or ""))

    local committing = false
    local function commit()
        if committing then return end
        committing = true
        setter(edit:GetText() or "")
        edit:SetText(tostring(getter() or ""))
        committing = false
    end

    edit:SetScript("OnEnterPressed", function(self)
        commit()
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(getter() or ""))
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function()
        commit()
    end)

    return row
end

-- ──────────────────────────────────────────────────────────────────────
-- ColorPicker 行
-- ──────────────────────────────────────────────────────────────────────
local function MakeColorRow(content, idx, label, getter, setter)
    local row = CreateRow(content, idx)
    AddLabel(row, label)

    local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
    swatch:SetSize(36, 18)
    swatch:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH + 8, 0)
    if swatch.SetBackdrop then
        swatch:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        swatch:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    swatch.color = swatch:CreateTexture(nil, "BACKGROUND")
    swatch.color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
    swatch.color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)

    local hexFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hexFS:SetPoint("LEFT", swatch, "RIGHT", 8, 0)

    local function refresh()
        local hex = getter() or "FFFFFF"
        local r, g, b = HexToRGB(hex)
        swatch.color:SetColorTexture(r, g, b, 1)
        hexFS:SetText("#" .. hex)
    end
    refresh()

    swatch:SetScript("OnClick", function()
        T.ShowColorPicker({
            color = getter(),
            onChange = function(r, g, b)
                local hex = RGBToHex(r, g, b)
                setter(hex)
                refresh()
            end,
        })
    end)
    return row
end

-- ──────────────────────────────────────────────────────────────────────
-- 各分区 renderer：返回总行数 → 高度 = 行数 * ROW_HEIGHT
-- ──────────────────────────────────────────────────────────────────────
local function RenderTrigger(content, getID)
    local i = 1
    MakeEditRow(content, i, L["SR_INDICATOR_NAME"] or "名称",
        function()
            local id = getID and getID()
            local ind = id and Schema.GetIndicator(id)
            return ind and ind.name or ""
        end,
        function(value)
            local id = getID and getID()
            if id and Schema.SetName then
                Schema.SetName(id, value)
                if Config.onChanged then Config:onChanged() end
            end
        end)
    i = i + 1
    MakeDropdownRow(content, i, L["SR_LEAD_MODE"] or "提前量模式",
        LEAD_MODE_ITEMS,
        PathGetter(getID, "leadTimeMode", "global"),
        function(v)
            PathSetter(getID, "leadTimeMode")(v == "custom" and "custom" or "global")
            Config:Refresh()
        end, content,
        L["SR_LEAD_MODE_TOOLTIP"] or "使用全局：跟随设置里的全局屏幕提醒提前量；如果战术文本写了 {sr:N}，本条提醒会按 N 秒提前显示。自定义：本指示器只按自己的提前量显示，忽略全局和 {sr:N}。")
    i = i + 1
    MakeSliderRow(content, i, L["SR_LEAD_TIME"] or "提前量",
        PathGetter(getID, "leadTimeSec", 3),
        PathSetter(getID, "leadTimeSec"),
        0, 10, 0.5,
        function(v) return string.format("%.1fs", v) end,
        function()
            local id = getID and getID()
            local ind = id and Schema.GetIndicator(id)
            return ind and ind.leadTimeMode == "custom"
        end,
        L["SR_LEAD_TIME_TOOLTIP"] or "仅在“自定义提前量”模式下生效。用于让这个屏幕提醒样式固定提前显示，例如永远提前 8 秒。")
    i = i + 1
    MakeSliderRow(content, i, L["SR_LINGER"] or "延后显示",
        PathGetter(getID, "lingerSec", 0),
        PathSetter(getID, "lingerSec"),
        0, 10, 0.5,
        function(v) return string.format("%.1fs", v) end)
    i = i + 1
    MakeRightCheckRow(content, i, L["SR_LINGER_FADE"] or "延后淡出",
        PathGetter(getID, "lingerFadeEnabled", true),
        PathSetter(getID, "lingerFadeEnabled"))
    i = i + 1
    local curID = getID and getID()
    local curInd = curID and Schema.GetIndicator(curID)
    local refName = (curInd and curInd.name) or "文本#1"
    MakeRightCheckRow(content, i, L["SR_EXCLUSIVE_MODE"] or "不参与通用文本提醒",
        PathGetter(getID, "exclusiveMode", false),
        PathSetter(getID, "exclusiveMode"),
        string.format(L["SR_EXCLUSIVE_MODE_HINT"] or "勾选后，此样式不会被通用文本提醒自动使用，仅当文本里写 {to:%s} 点名或被其他功能单独调用时显示。", refName))
    i = i + 1
    -- 仅 text/icon/bar 支持堆叠。
    if curInd and curInd.kind ~= "circle" then
        MakeDropdownRow(content, i, L["SR_STACK_DIRECTION"] or "Growth",
            ToItems(STACK_DIRECTIONS, {
                UP = L["SR_STACK_DIR_UP"] or "Up",
                DOWN = L["SR_STACK_DIR_DOWN"] or "Down",
                LEFT = L["SR_STACK_DIR_LEFT"] or "Left",
                RIGHT = L["SR_STACK_DIR_RIGHT"] or "Right",
            }),
            PathGetter(getID, "style.stackDir", "UP"),
            PathSetter(getID, "style.stackDir"), content)
        i = i + 1
        MakeSliderRow(content, i, L["SR_STACK_SPACING"] or "Spacing",
            PathGetter(getID, "style.stackSpacing", 2),
            PathSetter(getID, "style.stackSpacing"),
            0, 30, 1,
            function(v) return string.format("%dpx", v) end)
        i = i + 1
    end
    return (i - 1) * ROW_HEIGHT
end

local function RenderPosition(content, getID)
    local i = 1
    MakeDropdownRow(content, i, L["SR_ANCHOR"] or "锚点",
        ToItems(ANCHOR_POINTS),
        PathGetter(getID, "anchor.point", "CENTER"),
        function(v)
            PathSetter(getID, "anchor.point")(v)
            PathSetter(getID, "anchor.relativePoint")(v)
        end, content)
    i = i + 1
    MakeSliderRow(content, i, L["SR_X_OFFSET"] or "X 偏移",
        PathGetter(getID, "anchor.x", 0),
        PathSetter(getID, "anchor.x"),
        -800, 800, 1,
        function(v) return tostring(math.floor(v)) end)
    i = i + 1
    MakeSliderRow(content, i, L["SR_Y_OFFSET"] or "Y 偏移",
        PathGetter(getID, "anchor.y", 0),
        PathSetter(getID, "anchor.y"),
        -600, 600, 1,
        function(v) return tostring(math.floor(v)) end)
    return i * ROW_HEIGHT
end

local function RenderCountdown(content, getID)
    local function getFontSizeDefault()
        local id = getID()
        local ind = id and Schema.GetIndicator(id)
        local style = (ind and ind.style) or {}
        if ind and ind.kind == "text" then
            return tonumber(style.fontSize) or 18
        elseif ind and ind.kind == "icon" then
            return math.max(10, math.floor((tonumber(style.size) or 36) * 0.45))
        elseif ind and ind.kind == "circle" then
            return math.max(10, math.floor((tonumber(style.radius) or 60) * 0.6))
        end
        return 13
    end

    local function getFontSize()
        local id = getID()
        local ind = id and Schema.GetIndicator(id)
        local countdown = ind and ind.countdown
        if type(countdown) == "table" and countdown.fontSize ~= nil then
            return countdown.fontSize
        end
        return getFontSizeDefault()
    end

    local function setFontSize(value)
        local id = getID()
        if not id then return end
        local size = math.floor((tonumber(value) or getFontSizeDefault()) + 0.5)
        if size < 8 then size = 8 end
        if size > 100 then size = 100 end
        local ind = Schema.GetIndicator(id)
        local countdown = ind and ind.countdown
        if type(countdown) == "table" and countdown.fontSize == nil and size == getFontSizeDefault() then
            return
        end
        Schema.SetField(id, "countdown.fontSize", size)
        if Config.onChanged then Config:onChanged() end
    end

    local i = 1
    MakeCheckRow(content, i, L["SR_CD_ENABLE"] or "显示倒数",
        PathGetter(getID, "countdown.enabled", true),
        PathSetter(getID, "countdown.enabled"))
    i = i + 1
    MakeSliderRow(content, i, L["SR_CD_FONT_SIZE"] or "倒数字号",
        getFontSize,
        setFontSize,
        8, 100, 1, tostring)
    i = i + 1
    MakeDropdownRow(content, i, L["SR_CD_POSITION"] or "位置",
        ToItems({ "left", "right", "above", "below", "overlay" }, {
            left = L["SR_POS_LEFT"] or "左侧",
            right = L["SR_POS_RIGHT"] or "右侧",
            above = L["SR_POS_ABOVE"] or "上方",
            below = L["SR_POS_BELOW"] or "下方",
            overlay = L["SR_POS_OVERLAY"] or "叠加",
        }),
        PathGetter(getID, "countdown.position", "left"),
        PathSetter(getID, "countdown.position"), content)
    i = i + 1
    MakeDropdownRow(content, i, L["SR_CD_DECIMALS"] or "小数位",
        {
            { value = 0, text = L["SR_DEC_0"] or "0 位" },
            { value = 1, text = L["SR_DEC_1"] or "1 位" },
            { value = 2, text = L["SR_DEC_2"] or "2 位" },
        },
        PathGetter(getID, "countdown.decimals", 1),
        function(v) PathSetter(getID, "countdown.decimals")(tonumber(v) or 1) end, content)
    i = i + 1
    MakeDropdownRow(content, i, L["SR_CD_UNIT"] or "单位",
        {
            { value = "s",  text = "s" },
            { value = "秒", text = "秒" },
            { value = "",   text = L["SR_UNIT_NONE"] or "无" },
        },
        PathGetter(getID, "countdown.unit", "s"),
        PathSetter(getID, "countdown.unit"), content)
    i = i + 1
    MakeDropdownRow(content, i, L["SR_CD_WRAP"] or "包裹",
        {
            { value = "none", text = L["SR_WRAP_NONE"] or "无" },
            { value = "()",   text = "( )" },
            { value = "[]",   text = "[ ]" },
            { value = "{}",   text = "{ }" },
            { value = "<>",   text = "< >" },
        },
        PathGetter(getID, "countdown.wrap", "none"),
        PathSetter(getID, "countdown.wrap"), content)
    i = i + 1
    MakeCheckRow(content, i, L["SR_CD_COLOR_BY_TIME"] or "随时间变色",
        PathGetter(getID, "countdown.colorByTime", false),
        PathSetter(getID, "countdown.colorByTime"))
    return i * ROW_HEIGHT
end

local function RenderPixelGlow(content, getID)
    local i = 1
    MakeRightCheckRow(content, i, L["SR_PIXEL_GLOW_ENABLE"] or "显示发光效果",
        PathGetter(getID, "effects.pixelGlow.enabled", false),
        PathSetter(getID, "effects.pixelGlow.enabled")); i = i + 1
    MakeRightCheckRow(content, i, L["SR_PIXEL_GLOW_USE_COLOR"] or "使用自定义颜色",
        PathGetter(getID, "effects.pixelGlow.useColor", false),
        PathSetter(getID, "effects.pixelGlow.useColor")); i = i + 1
    MakeColorRow(content, i, L["SR_PIXEL_GLOW_COLOR"] or "自定义颜色",
        PathGetter(getID, "effects.pixelGlow.color", "FFFFFF"),
        PathSetter(getID, "effects.pixelGlow.color")); i = i + 1
    local durationModeGetter = PathGetter(getID, "effects.pixelGlow.durationMode", "custom")
    MakeDropdownRow(content, i, L["SR_PIXEL_GLOW_DURATION_MODE"] or "显示时长",
        {
            { value = "custom", text = L["SR_PIXEL_GLOW_MODE_CUSTOM"] or "自定义时长" },
            { value = "linger", text = L["SR_PIXEL_GLOW_MODE_LINGER"] or "跟随延后显示" },
        },
        durationModeGetter,
        function(v)
            PathSetter(getID, "effects.pixelGlow.durationMode")(v)
            Config:Refresh()
        end, content); i = i + 1
    MakeSliderRow(content, i, L["SR_PIXEL_GLOW_DURATION"] or "自定义时长",
        PathGetter(getID, "effects.pixelGlow.duration", 0.4),
        PathSetter(getID, "effects.pixelGlow.duration"), 0.1, 1.5, 0.1,
        function(v) return string.format("%.1fs", v) end,
        function() return durationModeGetter() == "custom" end); i = i + 1
    MakeSliderRow(content, i, L["SR_PIXEL_GLOW_LINES"] or "线条和粒子",
        PathGetter(getID, "effects.pixelGlow.lines", 8),
        PathSetter(getID, "effects.pixelGlow.lines"), 1, 30, 1, tostring); i = i + 1
    MakeSliderRow(content, i, L["SR_PIXEL_GLOW_FREQUENCY"] or "频率",
        PathGetter(getID, "effects.pixelGlow.frequency", 0.25),
        PathSetter(getID, "effects.pixelGlow.frequency"), -2, 2, 0.05,
        function(v) return string.format("%.2f", v) end); i = i + 1
    MakeSliderRow(content, i, L["SR_PIXEL_GLOW_LENGTH"] or "长度",
        PathGetter(getID, "effects.pixelGlow.length", 10),
        PathSetter(getID, "effects.pixelGlow.length"), 1, 60, 1, tostring); i = i + 1
    MakeSliderRow(content, i, L["SR_PIXEL_GLOW_THICKNESS"] or "粗细",
        PathGetter(getID, "effects.pixelGlow.thickness", 1),
        PathSetter(getID, "effects.pixelGlow.thickness"), 1, 12, 1, tostring); i = i + 1
    MakeSliderRow(content, i, L["SR_PIXEL_GLOW_X_OFFSET"] or "X 偏移",
        PathGetter(getID, "effects.pixelGlow.xOffset", 0),
        PathSetter(getID, "effects.pixelGlow.xOffset"), -50, 50, 1, tostring); i = i + 1
    MakeSliderRow(content, i, L["SR_PIXEL_GLOW_Y_OFFSET"] or "Y 偏移",
        PathGetter(getID, "effects.pixelGlow.yOffset", 0),
        PathSetter(getID, "effects.pixelGlow.yOffset"), -50, 50, 1, tostring)
    return i * ROW_HEIGHT
end

local function RenderStyle_Text(content, getID)
    local i = 1
    MakeSpellDisplayRow(content, i, getID); i = i + 1
    MakeSliderRow(content, i, L["SR_FONT_SIZE"] or "字号",
        PathGetter(getID, "style.fontSize", 48),
        PathSetter(getID, "style.fontSize"), 1, 100, 1, tostring); i = i + 1
    MakeColorRow(content, i, L["SR_FONT_COLOR"] or "颜色",
        PathGetter(getID, "style.color", "FFFFFF"),
        PathSetter(getID, "style.color")); i = i + 1
    MakeCheckRow(content, i, L["SR_BOLD"] or "加粗",
        PathGetter(getID, "style.bold", false),
        PathSetter(getID, "style.bold")); i = i + 1
    MakeCheckRow(content, i, L["SR_OUTLINE"] or "描边",
        PathGetter(getID, "style.outline", true),
        PathSetter(getID, "style.outline")); i = i + 1
    MakeColorRow(content, i, L["SR_OUTLINE_COLOR"] or "描边颜色",
        PathGetter(getID, "style.outlineColor", "000000"),
        PathSetter(getID, "style.outlineColor")); i = i + 1
    MakeCheckRow(content, i, L["SR_SHADOW"] or "阴影",
        PathGetter(getID, "style.shadow", true),
        PathSetter(getID, "style.shadow")); i = i + 1
    MakeSliderRow(content, i, L["SR_SCALE"] or "缩放",
        PathGetter(getID, "style.scale", 1.0),
        PathSetter(getID, "style.scale"), 0.5, 3, 0.1,
        function(v) return string.format("%.1fx", v) end)
    return i * ROW_HEIGHT
end

local function RenderStyle_Icon(content, getID)
    local i = 1
    MakeSliderRow(content, i, L["SR_ICON_SIZE"] or "大小",
        PathGetter(getID, "style.size", 36),
        PathSetter(getID, "style.size"), 16, 96, 1, tostring); i = i + 1
    MakeDropdownRow(content, i, L["SR_ICON_SOURCE"] or "图标来源",
        {
            { value = "context", text = L["SR_ICON_CTX"]   or "跟随触发" },
            { value = "spellID", text = L["SR_ICON_SPELL"] or "法术 ID" },
            { value = "texture", text = L["SR_ICON_TEX"]   or "自定义贴图" },
        },
        PathGetter(getID, "style.source", "context"),
        PathSetter(getID, "style.source"), content); i = i + 1
    MakeCheckRow(content, i, L["SR_DESATURATE"] or "去色",
        PathGetter(getID, "style.desaturated", false),
        PathSetter(getID, "style.desaturated")); i = i + 1
    MakeCheckRow(content, i, L["SR_BORDER"] or "描边",
        PathGetter(getID, "style.borderEnabled", true),
        PathSetter(getID, "style.borderEnabled")); i = i + 1
    MakeColorRow(content, i, L["SR_BORDER_COLOR"] or "描边颜色",
        PathGetter(getID, "style.borderColor", "000000"),
        PathSetter(getID, "style.borderColor")); i = i + 1
    MakeCheckRow(content, i, L["SR_COOLDOWN_SWIPE"] or "CD 转盘",
        PathGetter(getID, "style.cooldownSwipeEnabled", true),
        PathSetter(getID, "style.cooldownSwipeEnabled")); i = i + 1
    MakeCheckRow(content, i, L["SR_SHOW_LABEL"] or "显示文字标签",
        PathGetter(getID, "style.showLabel", false),
        PathSetter(getID, "style.showLabel"))
    return i * ROW_HEIGHT
end

local function RenderStyle_Bar(content, getID)
    local i = 1
    MakeSliderRow(content, i, L["SR_BAR_WIDTH"] or "宽度",
        PathGetter(getID, "style.width", 240),
        PathSetter(getID, "style.width"), 80, 500, 10, tostring); i = i + 1
    MakeSliderRow(content, i, L["SR_BAR_HEIGHT"] or "高度",
        PathGetter(getID, "style.height", 20),
        PathSetter(getID, "style.height"), 10, 60, 1, tostring); i = i + 1
    MakeColorRow(content, i, L["SR_BAR_COLOR"] or "前景色",
        PathGetter(getID, "style.barColor", "33CC66"),
        PathSetter(getID, "style.barColor")); i = i + 1
    MakeColorRow(content, i, L["SR_BG_COLOR"] or "背景色",
        PathGetter(getID, "style.bgColor", "222222"),
        PathSetter(getID, "style.bgColor")); i = i + 1
    MakeDropdownRow(content, i, L["SR_FILL_MODE"] or "填充模式",
        {
            { value = "drain", text = L["SR_FILL_DRAIN"] or "消减" },
            { value = "fill",  text = L["SR_FILL_FILL"]  or "蓄满" },
        },
        PathGetter(getID, "style.fillMode", "drain"),
        PathSetter(getID, "style.fillMode"), content); i = i + 1
    MakeCheckRow(content, i, L["SR_TEXT_ON_BAR"] or "叠加文本",
        PathGetter(getID, "style.textOnBar", true),
        PathSetter(getID, "style.textOnBar")); i = i + 1
    MakeCheckRow(content, i, L["SR_ICON_ON_LEFT"] or "左侧图标",
        PathGetter(getID, "style.iconOnLeft", true),
        PathSetter(getID, "style.iconOnLeft")); i = i + 1
    MakeCheckRow(content, i, L["SR_BORDER"] or "描边",
        PathGetter(getID, "style.border", true),
        PathSetter(getID, "style.border")); i = i + 1
    MakeDropdownRow(content, i, L["SR_BAR_TEXTURE"] or "材质",
        (T.ScreenReminderMediaPresets and T.ScreenReminderMediaPresets.GetDropdownItems("statusbar")) or {},
        PathGetter(getID, "style.barTexture", "blizzard"),
        PathSetter(getID, "style.barTexture"), content)
    return i * ROW_HEIGHT
end

local function RenderStyle_Circle(content, getID)
    local i = 1
    MakeSliderRow(content, i, L["SR_RADIUS"] or "半径",
        PathGetter(getID, "style.radius", 60),
        PathSetter(getID, "style.radius"), 12, 120, 1, tostring); i = i + 1
    MakeSliderRow(content, i, L["SR_THICKNESS"] or "厚度",
        PathGetter(getID, "style.thickness", 8),
        PathSetter(getID, "style.thickness"), 2, 32, 1, tostring); i = i + 1
    MakeColorRow(content, i, L["SR_CIRCLE_COLOR"] or "颜色",
        PathGetter(getID, "style.color", "33CCFF"),
        PathSetter(getID, "style.color")); i = i + 1
    MakeColorRow(content, i, L["SR_BG_COLOR"] or "背景色",
        PathGetter(getID, "style.bgColor", "222222"),
        PathSetter(getID, "style.bgColor")); i = i + 1
    MakeDropdownRow(content, i, L["SR_DIRECTION"] or "方向",
        {
            { value = "ccw", text = L["SR_DIR_CCW"] or "逆时针" },
            { value = "cw",  text = L["SR_DIR_CW"]  or "顺时针" },
        },
        PathGetter(getID, "style.direction", "ccw"),
        PathSetter(getID, "style.direction"), content); i = i + 1
    MakeDropdownRow(content, i, L["SR_FILL_MODE"] or "填充模式",
        {
            { value = "drain", text = L["SR_FILL_DRAIN"] or "消减" },
            { value = "fill",  text = L["SR_FILL_FILL"]  or "蓄满" },
        },
        PathGetter(getID, "style.fillMode", "drain"),
        PathSetter(getID, "style.fillMode"), content); i = i + 1
    MakeCheckRow(content, i, L["SR_SHOW_ICON"] or "显示图标",
        PathGetter(getID, "style.showIcon", false),
        PathSetter(getID, "style.showIcon")); i = i + 1
    MakeSliderRow(content, i, L["SR_ICON_SIZE"] or "图标大小",
        PathGetter(getID, "style.iconSize", 48),
        PathSetter(getID, "style.iconSize"), 8, 120, 1, tostring); i = i + 1
    MakeCheckRow(content, i, L["SR_SHOW_TEXT"] or "显示文本",
        PathGetter(getID, "style.showText", false),
        PathSetter(getID, "style.showText")); i = i + 1
    MakeSliderRow(content, i, L["SR_TEXT_FONT_SIZE"] or "文本字号",
        PathGetter(getID, "style.textFontSize", 16),
        PathSetter(getID, "style.textFontSize"), 8, 48, 1, tostring); i = i + 1
    MakeDropdownRow(content, i, L["SR_TEXT_POSITION"] or "文本位置",
        {
            { value = "above", text = L["SR_POS_ABOVE"] or "上方" },
            { value = "below", text = L["SR_POS_BELOW"] or "下方" },
            { value = "left",  text = L["SR_POS_LEFT"]  or "左侧（竖排）" },
            { value = "right", text = L["SR_POS_RIGHT"] or "右侧（竖排）" },
        },
        PathGetter(getID, "style.textPosition", "below"),
        PathSetter(getID, "style.textPosition"), content); i = i + 1
    MakeDropdownRow(content, i, L["SR_BAR_TEXTURE"] or "材质",
        (T.ScreenReminderMediaPresets and T.ScreenReminderMediaPresets.GetDropdownItems("circle")) or {},
        PathGetter(getID, "style.texturePreset", "flat"),
        PathSetter(getID, "style.texturePreset"), content)
    return i * ROW_HEIGHT
end

local STYLE_RENDERERS = {
    text = RenderStyle_Text,
    icon = RenderStyle_Icon,
    bar  = RenderStyle_Bar,
    circle = RenderStyle_Circle,
}

-- ──────────────────────────────────────────────────────────────────────
-- 主入口
-- ──────────────────────────────────────────────────────────────────────
function Config:Create(parent, opts)
    opts = opts or {}
    -- 缓存宽度。Frame SetPoint 锚定后 GetWidth 要等 layout pass，
    -- 首次 Render 时直接读 scroll:GetWidth() 会拿到 0，导致 section 渲染塌缩到不可见。
    self.width = opts.width or 350
    self.contentWidth = self.width - 18  -- 扣 SimpleScroll 右侧滚动条宽

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(self.width, opts.height or 248)
    if opts.point then frame:SetPoint(unpack(opts.point)) end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    title:SetText(L["SR_CONFIG_TITLE"] or "设置")
    frame.titleFS = title

    frame.enableCheck = T.CreateCheckbox(frame, {
        point = { "TOPRIGHT", frame, "TOPRIGHT", -4, 2 },
        label = "",
        getter = function()
            local id = Config:CurrentID()
            if not id then return false end
            local ind = Schema.GetIndicator(id)
            return ind and ind.enabled ~= false
        end,
        setter = function(v)
            local id = Config:CurrentID()
            if id then Schema.SetField(id, "enabled", v == true) end
            if Config.onChanged then Config:onChanged() end
        end,
    })
    frame.enableLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.enableLabel:SetPoint("RIGHT", frame.enableCheck, "LEFT", -6, 0)
    frame.enableLabel:SetText(L["SR_INDICATOR_ENABLED"] or "启用")
    frame.enableLabel:SetTextColor(1, 0.86, 0.32, 1)
    title:SetPoint("RIGHT", frame.enableLabel, "LEFT", -8, 0)
    title:SetJustifyH("LEFT")
    if title.SetWordWrap then title:SetWordWrap(false) end

    local scroll = T.CreateSimpleScroll(frame, {})
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -22)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.scroll = scroll

    self.frame = frame
    self.sections = {}
    return frame
end

function Config:CurrentID()
    return Schema.GetRoot().selectedIndicatorID
end

function Config:DestroySections()
    for _, s in ipairs(self.sections or {}) do
        s:Hide()
        s:SetParent(nil)
    end
    self.sections = {}
end

local function CreateSection(parent, label, w, renderer)
    local section = T.CreateCollapsibleSection(parent, {
        width = w,
        headerWidth = w,
        headerHeight = 24,
        contentGap = 4,
        padding = { left = 6, right = 6, top = 8, bottom = 8 },
        label = label,
        expanded = true,
        renderContent = function(content)
            return renderer(content, function() return Config:CurrentID() end)
        end,
        onToggle = function()
            Config:RelayoutSections()
        end,
    })
    return section
end

function Config:RelayoutSections()
    if not self.frame or not self.sections then return end
    local content = self.frame.scroll.content
    local y = 0
    for _, sec in ipairs(self.sections) do
        sec:ClearAllPoints()
        sec:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        y = y - (sec:GetHeight() + 6)
    end
    self.frame.scroll:SetContentHeight(math.abs(y) + 8)
end

function Config:Refresh()
    if not self.frame then return end
    self:DestroySections()

    local id = self:CurrentID()
    local ind = id and Schema.GetIndicator(id)
    if not ind then
        self.frame.titleFS:SetText(L["SR_CONFIG_TITLE"] or "设置")
        self.frame.enableCheck:Refresh()
        self.frame.scroll:SetContentHeight(0)
        return
    end

    self.frame.titleFS:SetText(string.format("%s · %s",
        L["SR_CONFIG_TITLE"] or "设置", ind.name or ""))
    self.frame.enableCheck:Refresh()

    local w = self.contentWidth
    local content = self.frame.scroll.content

    local function addSection(label, renderer)
        local sec = CreateSection(content, label, w, renderer)
        sec:RefreshLayout()
        self.sections[#self.sections + 1] = sec
    end

    addSection(L["SR_SECTION_TRIGGER"]   or "触发", RenderTrigger)
    addSection(L["SR_SECTION_POSITION"]  or "位置", RenderPosition)
    addSection(L["SR_SECTION_STYLE"]     or "样式", STYLE_RENDERERS[ind.kind] or RenderStyle_Text)
    if ind.kind ~= "circle" then
        addSection(L["SR_SECTION_PIXEL_GLOW"] or "发光像素", RenderPixelGlow)
    end
    addSection(L["SR_SECTION_COUNTDOWN"] or "倒数", RenderCountdown)

    self:RelayoutSections()
end

end)
