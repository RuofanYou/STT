local T, C, L = unpack(select(2, ...))

local font = STANDARD_TEXT_FONT

local TERTIARY_ATLAS = {
    normal = "common-button-tertiary-normal-small",
    highlight = "common-button-tertiary-hover-small",
    pushed = "common-button-tertiary-pressed-small",
    disabled = "common-button-tertiary-disabled-small",
}

local selectorMenuFrames = {}
local selectorMenuRows = {}
local selectorMenuAnchor
local selectorDismissLayer
local selectorOwnerRoot
local SELECTOR_DEFAULT_FONT_SIZE = 11
local SELECTOR_MIN_FONT_SIZE = 9

local function ApplyPoint(frame, point)
    if point then
        frame:SetPoint(unpack(point))
    end
end

local function ResolveColor(color, defaultColor)
    local source = type(color) == "table" and color or defaultColor or {}
    return
        source[1] or 1,
        source[2] or 1,
        source[3] or 1,
        source[4] == nil and 1 or source[4]
end

local function IsSettingsScaledOwner(parent, cfg)
    if cfg and cfg.scaleWithSettings == false then
        return false
    end
    if cfg and cfg.scaleWithSettings == true then
        return true
    end
    return T.IsSettingsPanelDescendant and T.IsSettingsPanelDescendant(parent) == true
end

local function ScaleForSettings(parent, value, cfg)
    if IsSettingsScaledOwner(parent, cfg) and T.Style and T.Style.Scale then
        return T.Style.Scale(value)
    end
    return tonumber(value) or 0
end

local function RegisterSettingsFont(parent, fontString, baseSize, fontPath, flags, cfg)
    if IsSettingsScaledOwner(parent, cfg) and T.Style and T.Style.RegisterFontString then
        T.Style.RegisterFontString(fontString, {
            font = fontPath or font,
            baseSize = baseSize,
            flags = flags,
        })
    end
end

function T.MarkPingBlocker(frame, makeTopLevel)
    if not frame then
        return
    end
    -- 只标记为 Ping 接收器，避免插件代码直接操作 Blizzard Ping 安全链路。
    if frame.SetAttribute then
        frame:SetAttribute("ping-receiver", true)
    end
    if makeTopLevel and frame.SetToplevel then
        frame:SetToplevel(true)
    end
end

local BACKDROP_STYLES = {
    chat = {
        backdrop = {
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 2, bottom = 3 },
        },
        bgColor = { 0.12, 0.12, 0.12, 0.8 },
        borderColor = { 0.5, 0.5, 0.5, 1 },
        offsets = { -3, 3, 3, -3 },
    },
    tooltip = {
        backdrop = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        },
        bgColor = { 0, 0, 0, 0.9 },
        borderColor = { 0.6, 0.6, 0.6, 1 },
        offsets = { -3, 3, 3, -3 },
    },
}

-- ═══════════════════════════════════════════════════════════════
-- L1: 装饰与基础工具 (Theme & Utilities)
-- 不依赖 L2/L3，仅依赖 WoW 原生 API
-- ═══════════════════════════════════════════════════════════════

function T.ApplyBackdrop(frame, config)
    if not frame then
        return nil
    end

    local cfg = type(config) == "table" and config or { alpha = config }
    local style = BACKDROP_STYLES[cfg.style or "chat"] or BACKDROP_STYLES.chat
    local backdrop = frame.sd
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.sd = backdrop
    end

    local level = tonumber(frame:GetFrameLevel()) or 0
    backdrop:SetFrameLevel(level == 0 and 1 or math.max(1, level - 1))
    if backdrop.SetBackdrop then
        backdrop:SetBackdrop(style.backdrop)
    end

    local offsets = cfg.offsets or style.offsets
    backdrop:ClearAllPoints()
    backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", offsets[1], offsets[2])
    backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offsets[3], offsets[4])

    local bgR, bgG, bgB, bgA = ResolveColor(cfg.bgColor, style.bgColor)
    if cfg.alpha ~= nil then
        bgA = tonumber(cfg.alpha) or bgA
    end
    if backdrop.SetBackdropColor then
        backdrop:SetBackdropColor(bgR, bgG, bgB, bgA)
    end

    local borderR, borderG, borderB, borderA = ResolveColor(cfg.borderColor, style.borderColor)
    if cfg.borderAlpha ~= nil then
        borderA = tonumber(cfg.borderAlpha) or borderA
    end
    if backdrop.SetBackdropBorderColor then
        backdrop:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
    end
    backdrop:Show()
    return backdrop
end

function T.CreateFontString(parent, config)
    local cfg = config or {}
    local text = parent:CreateFontString(nil, cfg.layer or "OVERLAY", cfg.template)
    local baseSize = tonumber(cfg.size) or 13
    text:SetFont(cfg.font or font, ScaleForSettings(parent, baseSize, cfg), cfg.flags)
    RegisterSettingsFont(parent, text, baseSize, cfg.font or font, cfg.flags, cfg)

    if cfg.justifyH then
        text:SetJustifyH(cfg.justifyH)
    end
    if cfg.justifyV then
        text:SetJustifyV(cfg.justifyV)
    end
    if cfg.width then
        text:SetWidth(cfg.width)
    end
    if cfg.wordWrap ~= nil and text.SetWordWrap then
        text:SetWordWrap(cfg.wordWrap)
    end
    if cfg.color then
        text:SetTextColor(ResolveColor(cfg.color))
    end
    ApplyPoint(text, cfg.point)
    if cfg.text ~= nil then
        text:SetText(cfg.text)
    end
    return text
end

function T.CreateSeparator(parent, config)
    local cfg = config or {}
    local line = parent:CreateTexture(nil, cfg.layer or "OVERLAY")
    ApplyPoint(line, cfg.point or { "TOP", parent, "TOP", 0, 0 })
    line:SetSize(tonumber(cfg.width) or 650, tonumber(cfg.height) or 1)
    line:SetColorTexture(ResolveColor(cfg.color, { 0.5, 0.5, 0.5, 0.3 }))
    return line
end

function T.CreateGroupTitle(parent, config)
    local cfg = config or {}
    return T.CreateFontString(parent, {
        layer = cfg.layer or "OVERLAY",
        template = cfg.template or "GameFontNormal",
        point = cfg.point,
        size = cfg.fontSize or 13,
        color = cfg.color or { 0.9, 0.85, 0.7, 1 },
        justifyH = cfg.justifyH,
        justifyV = cfg.justifyV,
        text = cfg.text or "",
        flags = cfg.flags,
    })
end

function T.GetDisclosureText(expanded, text)
    local icon = expanded
        and "|A:NPE_ArrowDown:12:12|a"
        or  "|A:NPE_ArrowRight:12:12|a"
    return string.format("%s %s", icon, text or "")
end

local function UpdateButtonTextColor(button)
    if not button or not button.Text then
        return
    end

    if not button:IsEnabled() then
        button.Text:SetTextColor(0.55, 0.55, 0.55, 1)
    elseif button.isMouseOver then
        button.Text:SetTextColor(1, 1, 0, 1)
    else
        button.Text:SetTextColor(1, 1, 1, 1)
    end
end

local function ResetButtonTextPosition(button)
    if button and button.Text then
        button.Text:ClearAllPoints()
        button.Text:SetPoint("CENTER", button.textOffsetX or 0, button.textOffsetY or 0)
    end
end

local function MaybeShowTooltip(button)
    local text = button and button.tooltipText
    if not text or text == "" then
        return
    end
    if button.tooltipWhenDisabledOnly and button:IsEnabled() then
        return
    end
    T.UITooltip.Show(button, { description = text }, { anchor = button.tooltipAnchor or "ANCHOR_RIGHT" })
end

local function MaybeHideTooltip(button)
    if T.UITooltip then
        T.UITooltip.ScheduleHide(button)
    end
end

local function SetFontStringSize(fontString, size)
    if fontString and fontString.SetFont and font then
        local finalSize = size
        if T.Style and T.Style._scaledFonts and T.Style._scaledFonts[fontString] and T.Style.Scale then
            finalSize = T.Style.Scale(size)
        end
        fontString:SetFont(font, finalSize, "")
    end
end

local function FitFontString(fontString, text, maxWidth, preferredSize, minSize)
    if not fontString then
        return
    end
    fontString:SetText(text or "")
    maxWidth = tonumber(maxWidth) or 0
    preferredSize = tonumber(preferredSize) or SELECTOR_DEFAULT_FONT_SIZE
    minSize = tonumber(minSize) or SELECTOR_MIN_FONT_SIZE
    if maxWidth <= 0 then
        SetFontStringSize(fontString, preferredSize)
        return
    end

    local size = preferredSize
    SetFontStringSize(fontString, size)
    while size > minSize and (fontString:GetStringWidth() or 0) > maxWidth do
        size = size - 1
        SetFontStringSize(fontString, size)
    end
end

local function CreateAtlasButton(parent, config, atlas)
    local width = tonumber(config and config.width) or 100
    if width <= 0 then
        width = 100
    end

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, ScaleForSettings(parent, tonumber(config and config.height) or 28, config))
    ApplyPoint(button, config and config.point)

    button:SetNormalAtlas(atlas.normal)
    button:SetHighlightAtlas(atlas.highlight)
    button:SetPushedAtlas(atlas.pushed)
    button:SetDisabledAtlas(atlas.disabled)

    local text = button:CreateFontString(nil, "OVERLAY")
    local baseFontSize = tonumber(config and config.fontSize) or 12
    text:SetFont(font, ScaleForSettings(parent, baseFontSize, config), "OUTLINE")
    RegisterSettingsFont(parent, text, baseFontSize, font, "OUTLINE", config)
    button.textOffsetX = tonumber(config and config.textOffsetX) or 0
    button.textOffsetY = tonumber(config and config.textOffsetY) or 0
    button.textPressedOffsetX = tonumber(config and config.textPressedOffsetX) or 2
    button.textPressedOffsetY = tonumber(config and config.textPressedOffsetY) or 0
    button:SetFontString(text)
    button.Text = text
    button.tooltipText = config and config.tooltip or nil
    button.tooltipWhenDisabledOnly = config and config.tooltipWhenDisabledOnly == true or false
    button.tooltipAnchor = config and config.tooltipAnchor or nil

    function button:SetText(value)
        self.Text:SetText(value or "")
    end

    function button:GetText()
        return self.Text and self.Text:GetText() or ""
    end

    ResetButtonTextPosition(button)
    button:SetText(config and config.text or "")
    UpdateButtonTextColor(button)

    button:HookScript("OnEnter", function(self)
        self.isMouseOver = true
        UpdateButtonTextColor(self)
        MaybeShowTooltip(self)
    end)
    button:HookScript("OnLeave", function(self)
        self.isMouseOver = false
        UpdateButtonTextColor(self)
        MaybeHideTooltip(self)
    end)
    button:HookScript("OnMouseDown", function(self)
        if not self:IsEnabled() then
            return
        end
        self.Text:ClearAllPoints()
        self.Text:SetPoint("CENTER", self.textPressedOffsetX, self.textPressedOffsetY)
    end)
    button:HookScript("OnMouseUp", ResetButtonTextPosition)
    button:HookScript("OnHide", function(self)
        self.isMouseOver = false
        ResetButtonTextPosition(self)
        UpdateButtonTextColor(self)
        MaybeHideTooltip(self)
    end)
    button:HookScript("OnEnable", function(self)
        UpdateButtonTextColor(self)
    end)
    button:HookScript("OnDisable", function(self)
        ResetButtonTextPosition(self)
        UpdateButtonTextColor(self)
        MaybeHideTooltip(self)
    end)

    return button
end

function T.CreateButton(parent, config)
    return CreateAtlasButton(parent, config or {}, TERTIARY_ATLAS)
end

function T.CreateToggleButton(parent, config)
    local cfg = config or {}
    local button = T.CreateButton(parent, {
        width = cfg.width or 180,
        height = cfg.height or 24,
        point = cfg.point,
        tooltip = cfg.tooltip,
    })

    local function refresh()
        local state = cfg.getter and cfg.getter() or false
        local stateText = state
            and ("|cff00ff00" .. (L["开"] or "开") .. "|r")
            or ("|cffff0000" .. (L["关"] or "关") .. "|r")
        button:SetText(string.format("%s: %s", L[cfg.label] or cfg.label or "", stateText))
    end

    button:SetScript("OnClick", function()
        if cfg.setter then
            cfg.setter(not (cfg.getter and cfg.getter() or false))
        end
        if cfg.onApply then
            cfg.onApply()
        end
        refresh()
    end)

    button.Refresh = refresh
    if cfg.refreshList then
        cfg.refreshList[#cfg.refreshList + 1] = refresh
    end
    refresh()
    return button
end

function T.CreateCycleButton(parent, config)
    local cfg = config or {}
    local button = T.CreateButton(parent, {
        width = cfg.width or 180,
        height = cfg.height or 24,
        point = cfg.point,
        tooltip = cfg.tooltip,
    })

    local function resolveText(value)
        if cfg.textResolver then
            return cfg.textResolver(value)
        end
        for _, item in ipairs(cfg.values or {}) do
            if item.value == value then
                return item.text
            end
        end
        return tostring(value)
    end

    local function refresh()
        local current = nil
        if cfg.getter then
            current = cfg.getter()
        end
        button:SetText(string.format("%s: %s", L[cfg.label] or cfg.label or "", resolveText(current)))
    end

    button:SetScript("OnClick", function()
        local values = cfg.values or {}
        if #values == 0 then
            return
        end

        local current = nil
        if cfg.getter then
            current = cfg.getter()
        end
        local nextIndex = 1
        for index, item in ipairs(values) do
            if item.value == current then
                nextIndex = index + 1
                break
            end
        end
        if nextIndex > #values then
            nextIndex = 1
        end

        if cfg.setter then
            cfg.setter(values[nextIndex].value)
        end
        if cfg.onApply then
            cfg.onApply()
        end
        refresh()
    end)

    button.Refresh = refresh
    if cfg.refreshList then
        cfg.refreshList[#cfg.refreshList + 1] = refresh
    end
    refresh()
    return button
end

function T.CreateActionButton(parent, config)
    local cfg = config or {}
    local button = T.CreateButton(parent, {
        width = cfg.width,
        height = cfg.height or 24,
        point = cfg.point,
        tooltip = cfg.tooltip,
    })

    local function refresh()
        button:SetText(cfg.textFn and cfg.textFn() or "")
    end

    button:SetScript("OnClick", function()
        if cfg.onClick then
            cfg.onClick()
        end
        refresh()
    end)

    button.Refresh = refresh
    if cfg.refreshList then
        cfg.refreshList[#cfg.refreshList + 1] = refresh
    end
    refresh()
    return button
end

-- ═══════════════════════════════════════════════════════════════
-- L2: 原子组件 (Atomic Widgets)
-- 可依赖 L1
-- ═══════════════════════════════════════════════════════════════

function T.CreateLabel(parent, configOrText, x, y, size)
    if type(configOrText) == "table" then
        local cfg = configOrText
        return T.CreateFontString(parent, {
            layer = cfg.layer or "OVERLAY",
            template = cfg.template or "GameFontNormal",
            point = cfg.point or { "TOPLEFT", parent, "TOPLEFT", cfg.x or 0, cfg.y or 0 },
            size = cfg.size or 13,
            flags = cfg.flags or "OUTLINE",
            justifyH = cfg.justifyH,
            justifyV = cfg.justifyV,
            color = cfg.color or { 1, 0.86, 0.32, 1 },
            text = cfg.text or "",
            width = cfg.width,
            wordWrap = cfg.wordWrap,
        })
    end

    return T.CreateFontString(parent, {
        layer = "OVERLAY",
        template = "GameFontNormal",
        point = { "TOPLEFT", parent, "TOPLEFT", x or 0, y or 0 },
        size = size or 13,
        flags = "OUTLINE",
        color = { 1, 0.86, 0.32, 1 },
        text = configOrText or "",
    })
end

function T.CreateCheckbox(parent, config)
    local cfg = config or {}
    local checkbox = CreateFrame("CheckButton", nil, parent)
    local boxSize = ScaleForSettings(parent, T.Style and T.Style.BASE and T.Style.BASE.CHECKBOX_SIZE or 24, cfg)
    checkbox:SetSize(boxSize, boxSize)
    ApplyPoint(checkbox, cfg.point)
    checkbox:RegisterForClicks("LeftButtonUp")

    local box = checkbox:CreateTexture(nil, "BACKGROUND")
    box:SetAllPoints()
    box:SetColorTexture(0.08, 0.08, 0.1, 0.75)
    T.ApplyBackdrop(checkbox, {
        alpha = cfg.backdropAlpha or 0.25,
        style = cfg.backdropStyle or "tooltip",
        borderColor = cfg.borderColor or { 0.5, 0.5, 0.5, 0.8 },
    })

    local mark = checkbox:CreateTexture(nil, "ARTWORK")
    local markSize = ScaleForSettings(parent, T.Style and T.Style.BASE and T.Style.BASE.CHECKBOX_MARK_SIZE or 14, cfg)
    mark:SetSize(markSize, markSize)
    mark:SetPoint("CENTER")
    mark:SetAtlas("common-icon-checkmark-yellow")
    mark:Hide()
    checkbox.mark = mark

    local label = T.CreateFontString(parent, {
        layer = "OVERLAY",
        template = "GameFontNormalSmall",
        point = { "LEFT", checkbox, "RIGHT", 6, 0 },
        size = cfg.fontSize or 12,
        flags = cfg.flags or "OUTLINE",
        color = cfg.color or { 1, 1, 1, 1 },
        text = cfg.label or "",
    })
    checkbox.label = label

    function checkbox:SetChecked(value)
        self.__sttChecked = value == true
        self.mark:SetShown(self.__sttChecked)
    end

    function checkbox:GetChecked()
        return self.__sttChecked == true
    end

    local function refresh()
        if cfg.label ~= nil then
            label:SetText(cfg.label or "")
        end
        if cfg.clickLabel and checkbox.SetHitRectInsets then
            local labelWidth = label.GetStringWidth and label:GetStringWidth() or 0
            checkbox:SetHitRectInsets(0, -math.min(260, math.max(0, labelWidth + 8)), 0, 0)
        end
        local checked = checkbox:GetChecked()
        if cfg.getter then
            checked = cfg.getter() == true
        end
        checkbox:SetChecked(checked)
    end

    checkbox:SetScript("OnClick", function(self)
        local nextValue = not self:GetChecked()
        self:SetChecked(nextValue)
        if cfg.setter then
            cfg.setter(nextValue)
        end
        if cfg.onApply then
            cfg.onApply()
        end
        refresh()
    end)

    checkbox.Refresh = refresh
    if cfg.refreshList then
        cfg.refreshList[#cfg.refreshList + 1] = refresh
    end
    refresh()
    return checkbox
end

function T.CreateEditBox(parent, config)
    local cfg = config or {}
    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetSize(tonumber(cfg.width) or 200, tonumber(cfg.height) or 24)
    ApplyPoint(edit, cfg.point)
    edit:SetMultiLine(cfg.multiLine == true)
    edit:SetAutoFocus(cfg.autoFocus == true)
    edit:SetCountInvisibleLetters(false)
    if cfg.maxLetters then
        edit:SetMaxLetters(cfg.maxLetters)
    end

    local fontObject = cfg.fontObject or "ChatFontNormal"
    if type(fontObject) == "string" then
        fontObject = _G[fontObject]
    end
    if fontObject then
        edit:SetFontObject(fontObject)
    end
    if cfg.justifyH then
        edit:SetJustifyH(cfg.justifyH)
    end
    if cfg.justifyV then
        edit:SetJustifyV(cfg.justifyV)
    end
    if cfg.backdrop ~= false then
        T.ApplyBackdrop(edit, {
            alpha = cfg.backdropAlpha or 0.5,
            style = cfg.backdropStyle or "chat",
            borderColor = cfg.borderColor,
        })
    end
    if edit.SetTextInsets then
        edit:SetTextInsets(5, 5, 0, 0)
    end

    if cfg.placeholder then
        local placeholder = T.CreateFontString(parent, {
            layer = "OVERLAY",
            template = "GameFontDisableSmall",
            point = { "LEFT", edit, "LEFT", 6, 0 },
            size = cfg.placeholderSize or 12,
            color = cfg.placeholderColor or { 0.55, 0.55, 0.55, 1 },
            text = cfg.placeholder,
        })
        placeholder:SetShown(false)
        edit.placeholder = placeholder

        local function refreshPlaceholder()
            local text = edit:GetText() or ""
            local hasFocus = edit:HasFocus()
            placeholder:SetShown(text == "" and not hasFocus)
        end

        edit:HookScript("OnTextChanged", refreshPlaceholder)
        edit:HookScript("OnEditFocusGained", refreshPlaceholder)
        edit:HookScript("OnEditFocusLost", refreshPlaceholder)
        refreshPlaceholder()
    end

    return edit
end

local function NormalizeSliderValue(value, step)
    if (tonumber(step) or 1) >= 1 then
        return math.floor((tonumber(value) or 0) + 0.5)
    end
    return math.floor((tonumber(value) or 0) / step + 0.5) * step
end

function T.CreateSliderRow(parent, config)
    local cfg = config or {}
    local sliderWidth = tonumber(cfg.sliderWidth) or 300
    local sliderHeight = ScaleForSettings(parent, T.Style and T.Style.BASE and T.Style.BASE.SLIDER_HEIGHT or 20, cfg)
    local sliderOffset = ScaleForSettings(parent, 22, cfg)
    local label = T.CreateLabel(parent, {
        point = { "TOP", parent, "TOP", 0, cfg.y or 0 },
        size = 12,
        justifyH = "CENTER",
        text = "",
        width = sliderWidth,
    })
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOP", parent, "TOP", 0, (cfg.y or 0) - sliderOffset)
    slider:SetSize(sliderWidth, sliderHeight)
    slider:SetMinMaxValues(cfg.min or 0, cfg.max or 1)
    slider:SetValueStep(cfg.step or 1)
    slider:SetObeyStepOnDrag(true)
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end

    local function refresh()
        local value = cfg.getter and cfg.getter() or 0
        slider.isRefreshing = true
        slider:SetValue(value)
        slider.isRefreshing = false
        local text = cfg.formatter and cfg.formatter(value) or tostring(value)
        label:SetText(string.format("%s: %s", L[cfg.label] or cfg.label or "", text))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if self.isRefreshing then
            return
        end

        local normalized = NormalizeSliderValue(value, cfg.step or 1)
        if cfg.setter then
            cfg.setter(normalized)
        end
        if cfg.onApply then
            cfg.onApply()
        end
        if math.abs((self:GetValue() or 0) - normalized) > 0.0001 then
            self:SetValue(normalized)
        end
        refresh()
    end)

    local row = {
        label = label,
        slider = slider,
        Refresh = refresh,
    }

    if cfg.refreshList then
        cfg.refreshList[#cfg.refreshList + 1] = refresh
    end
    refresh()  -- 初始填充 label，避免控件首次显示时 label 为空
    return row
end

local function EnsureSelectorOwnerRoot(root)
    local owner = root or UIParent
    if selectorOwnerRoot == owner and selectorDismissLayer then
        return
    end

    selectorOwnerRoot = owner
    selectorDismissLayer = CreateFrame("Button", nil, owner)
    selectorDismissLayer:SetAllPoints(owner)
    selectorDismissLayer:SetFrameStrata(owner:GetFrameStrata())
    selectorDismissLayer:SetFrameLevel(owner:GetFrameLevel() + 15)
    selectorDismissLayer:RegisterForClicks("AnyUp")
    selectorDismissLayer:SetScript("OnClick", function()
        T.HideSelectorMenu()
    end)
    selectorDismissLayer:Hide()

    if not owner.__sttSelectorHideHooked then
        owner:HookScript("OnHide", function()
            T.HideSelectorMenu()
        end)
        owner.__sttSelectorHideHooked = true
    end
end

local function EnsureSelectorMenuFrame(root, depth)
    EnsureSelectorOwnerRoot(root)
    depth = depth or 1

    local frame = selectorMenuFrames[depth]
    if frame and frame:GetParent() ~= selectorOwnerRoot then
        frame:SetParent(selectorOwnerRoot)
    end
    if frame then
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(selectorOwnerRoot:GetFrameLevel() + 40 + depth)
        return frame
    end

    frame = CreateFrame("Frame", nil, selectorOwnerRoot, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(selectorOwnerRoot:GetFrameLevel() + 40 + depth)
    frame:Hide()
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.03, 0.03, 0.04, 0.96)
        frame:SetBackdropBorderColor(0.45, 0.38, 0.18, 0.9)
    end

    selectorMenuFrames[depth] = frame
    selectorMenuRows[depth] = selectorMenuRows[depth] or {}
    return frame
end

local function EnsureSelectorMenuRows(parent, depth, count)
    local rows = selectorMenuRows[depth]
    while #rows < count do
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(20)

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.25, 0.45, 0.8, 0.25)

        local check = row:CreateTexture(nil, "ARTWORK")
        check:SetSize(12, 12)
        check:SetPoint("LEFT", row, "LEFT", 7, 0)
        check:SetAtlas("common-icon-checkmark-yellow")
        check:Hide()

        local arrow = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        arrow:SetText(">")
        arrow:Hide()

        -- 可选预览：item.icon 路径存在时显示在 arrow 左侧（材质缩略图）
        local preview = row:CreateTexture(nil, "ARTWORK")
        preview:SetSize(60, 12)
        preview:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
        preview:Hide()

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", check, "RIGHT", 6, 0)
        text:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
        text:SetJustifyH("LEFT")
        if STANDARD_TEXT_FONT and text.SetFont then
            text:SetFont(STANDARD_TEXT_FONT, SELECTOR_DEFAULT_FONT_SIZE, "")
        end
        if text.SetWordWrap then
            text:SetWordWrap(false)
        end

        row.check = check
        row.arrow = arrow
        row.text = text
        row.preview = preview
        rows[#rows + 1] = row
    end
    return rows
end

local function UpdateSelectorState(button)
    if not button or not button.bg then
        return
    end

    if button.disabled then
        button.bg:SetAtlas("common-dropdown-b-button-disabled")
        button.hover:Hide()
        button.pressed:Hide()
        button.pressedHover:Hide()
        button.labelText:SetTextColor(0.62, 0.55, 0.3, 1)
        button.valueText:SetTextColor(0.55, 0.55, 0.55, 1)
        button.arrow:SetAlpha(0.35)
        return
    end

    button.labelText:SetTextColor(1, 0.82, 0, 1)
    button.valueText:SetTextColor(1, 1, 1, 1)
    button.arrow:SetAlpha(1)

    if button.isOpen and not button.isOver and not button.isDown then
        button.bg:SetAtlas("common-dropdown-b-button-open")
    else
        button.bg:SetAtlas("common-dropdown-b-button")
    end

    if button.isDown and button.isOver then
        button.pressedHover:Show()
        button.hover:Hide()
        button.pressed:Hide()
    elseif button.isDown then
        button.pressed:Show()
        button.hover:Hide()
        button.pressedHover:Hide()
    elseif button.isOver then
        button.hover:Show()
        button.pressed:Hide()
        button.pressedHover:Hide()
    else
        button.hover:Hide()
        button.pressed:Hide()
        button.pressedHover:Hide()
    end
end

local function HideSelectorMenusFromDepth(depth)
    for index = depth or 1, #selectorMenuFrames do
        local frame = selectorMenuFrames[index]
        if frame then
            frame:Hide()
        end
    end
end

function T.HideSelectorMenu()
    HideSelectorMenusFromDepth(1)
    if selectorDismissLayer then
        selectorDismissLayer:Hide()
    end
    if selectorMenuAnchor then
        selectorMenuAnchor.isOpen = false
        UpdateSelectorState(selectorMenuAnchor)
    end
    selectorMenuAnchor = nil
end

local function ResolveSelectorText(items, value)
    for _, item in ipairs(items or {}) do
        if item.value == value then
            return item.text or "-"
        end
        if type(item.items) == "table" then
            local nestedText = ResolveSelectorText(item.items, value)
            if nestedText then
                return nestedText
            end
        end
    end
end

local function ShowSelectorMenuLevel(button, items, anchor, depth)
    if not button or type(items) ~= "table" or #items == 0 then
        HideSelectorMenusFromDepth(depth or 1)
        return
    end

    local ownerRoot = button.selectorOwnerRoot or button:GetParent() or UIParent
    depth = depth or 1
    local menuFrame = EnsureSelectorMenuFrame(ownerRoot, depth)

    HideSelectorMenusFromDepth(depth + 1)

    if depth == 1 and menuFrame:IsShown() and selectorMenuAnchor == button then
        T.HideSelectorMenu()
        return
    end

    if depth == 1 then
        T.HideSelectorMenu()
        selectorMenuAnchor = button
        button.isOpen = true
        UpdateSelectorState(button)
        if selectorDismissLayer then
            selectorDismissLayer:Show()
        end
    end

    local rows = EnsureSelectorMenuRows(menuFrame, depth, #items)

    local measure = menuFrame._measureText
    if not measure then
        measure = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        menuFrame._measureText = measure
    end

    local maxItemWidth = 0
    for _, item in ipairs(items) do
        measure:SetText(tostring(item.text or "-"))
        local sideWidth = item.radio == true and 30 or 18
        if item.value ~= nil then
            sideWidth = math.max(sideWidth, 30)
        end
        if type(item.items) == "table" and #item.items > 0 then
            sideWidth = sideWidth + 12
        end
        maxItemWidth = math.max(maxItemWidth, math.ceil(measure:GetStringWidth() or 0) + sideWidth)
    end

    local rowHeight = 18
    local padding = 2
    local menuWidth = math.max(button:GetWidth(), maxItemWidth)
    local idealHeight = (#items * rowHeight) + padding * 2

    -- 计算可用屏幕空间，决定是否需要滚动
    local screenHeight = UIParent:GetHeight()
    local needsScroll = false
    local menuHeight = idealHeight
    local openUpward = false

    if depth == 1 then
        local _, buttonBottom = button:GetCenter()
        local availableDown = math.max((buttonBottom or 0) - 4 - 20, 0)
        local availableUp = math.max(screenHeight - (buttonBottom or 0) - 20, 0)

        if idealHeight > availableDown then
            if availableUp > availableDown then
                -- 向上展开
                openUpward = true
                if idealHeight > availableUp then
                    needsScroll = true
                    menuHeight = availableUp
                end
            else
                needsScroll = true
                menuHeight = availableDown
            end
        end
    else
        -- 子菜单：简单限制为屏幕 80% 高度
        local maxSub = screenHeight * 0.8
        if idealHeight > maxSub then
            needsScroll = true
            menuHeight = maxSub
        end
    end

    -- 滚动内容容器
    local rowParent = menuFrame
    if needsScroll then
        if not menuFrame.scrollContent then
            menuFrame.scrollContent = CreateFrame("Frame", nil, menuFrame)
        end
        local sc = menuFrame.scrollContent
        sc:SetSize(menuWidth, idealHeight)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 0, 0)
        sc:Show()
        rowParent = sc

        menuFrame:SetClipsChildren(true)
        menuFrame.scrollOffset = 0
        menuFrame.maxScroll = idealHeight - menuHeight
        menuFrame:EnableMouseWheel(true)
        menuFrame:SetScript("OnMouseWheel", function(self, delta)
            local step = rowHeight * 3
            self.scrollOffset = math.max(0, math.min(self.maxScroll, self.scrollOffset - delta * step))
            self.scrollContent:ClearAllPoints()
            self.scrollContent:SetPoint("TOPLEFT", self, "TOPLEFT", 0, self.scrollOffset)
        end)
    else
        if menuFrame.scrollContent then
            menuFrame.scrollContent:Hide()
        end
        menuFrame:SetClipsChildren(false)
        menuFrame:EnableMouseWheel(false)
        menuFrame:SetScript("OnMouseWheel", nil)
    end

    menuFrame:ClearAllPoints()
    if depth == 1 then
        if openUpward then
            menuFrame:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 4)
        else
            menuFrame:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
        end
    else
        menuFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 0)
    end
    menuFrame:SetSize(menuWidth, menuHeight)
    menuFrame:Show()

    for index, row in ipairs(rows) do
        local item = items[index]
        if item then
            local hasChildren = type(item.items) == "table" and #item.items > 0
            local isTitle = item.isTitle == true
            local isDivider = item.isDivider == true
            local isDisabled = item.disabled == true or isTitle or isDivider
            row:SetParent(rowParent)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", padding, -padding - ((index - 1) * rowHeight))
            row:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -padding, -padding - ((index - 1) * rowHeight))
            row.text:SetText(isDivider and "────────────" or tostring(item.text or "-"))
            row.check:ClearAllPoints()
            row.text:ClearAllPoints()
            row.arrow:ClearAllPoints()
            row.arrow:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.arrow:SetShown(hasChildren)
            if item.radio == true then
                row.check:SetTexture("Interface\\Common\\UI-DropDownRadioChecks")
                if item.radioChecked == true then
                    row.check:SetTexCoord(0, 0.5, 0.5, 1)
                else
                    row.check:SetTexCoord(0.5, 1, 0.5, 1)
                end
                row.check:SetSize(16, 16)
                row.check:SetPoint("LEFT", row, "LEFT", 1, 0)
                row.check:Show()
                row.text:SetPoint("LEFT", row.check, "RIGHT", 3, 0)
            elseif (not hasChildren) and item.value == button.selectedValue then
                row.check:SetTexture(nil)
                row.check:SetAtlas("common-icon-checkmark-yellow")
                row.check:SetTexCoord(0, 1, 0, 1)
                row.check:SetSize(12, 12)
                row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.check:Show()
                row.text:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
            else
                row.check:Hide()
                row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
            end
            -- 材质预览：item.icon 是纹理路径时，缩略显示在 arrow 左侧；文本右边界让位
            -- item.iconSize = {w, h} 控制尺寸；默认 60×12（statusbar 横条）
            if row.preview then
                if type(item.icon) == "string" and item.icon ~= "" and not isDivider and not isTitle then
                    local iw, ih = 60, 12
                    if type(item.iconSize) == "table" then
                        iw = tonumber(item.iconSize[1]) or iw
                        ih = tonumber(item.iconSize[2]) or ih
                    end
                    row.preview:SetSize(iw, ih)
                    local atlasName = item.icon:match("^atlas:(.+)$")
                    if atlasName and row.preview.SetAtlas then
                        row.preview:SetAtlas(atlasName)
                    else
                        row.preview:SetTexture(item.icon)
                    end
                    row.preview:Show()
                    row.text:SetPoint("RIGHT", row.preview, "LEFT", -4, 0)
                else
                    row.preview:Hide()
                    row.preview:SetTexture(nil)
                    row.text:SetPoint("RIGHT", row.arrow, "LEFT", -3, 0)
                end
            else
                row.text:SetPoint("RIGHT", row.arrow, "LEFT", -3, 0)
            end
            if isDivider then
                row.text:SetTextColor(0.45, 0.45, 0.45, 1)
            elseif isTitle then
                row.text:SetTextColor(1, 0.82, 0, 1)
            elseif isDisabled then
                row.text:SetTextColor(0.55, 0.55, 0.55, 1)
            else
                row.text:SetTextColor(1, 1, 1, 1)
            end
            row:SetEnabled(not isDisabled)
            row:SetScript("OnEnter", function()
                if hasChildren then
                    ShowSelectorMenuLevel(button, item.items, row, depth + 1)
                else
                    HideSelectorMenusFromDepth(depth + 1)
                end
            end)
            row:SetScript("OnClick", function()
                if isDisabled then
                    return
                end
                if hasChildren then
                    ShowSelectorMenuLevel(button, item.items, row, depth + 1)
                    return
                end
                if item.onClick then
                    T.HideSelectorMenu()
                    item.onClick(item)
                    return
                end
                button:SetSelectedValue(item.value, item.text)
                T.HideSelectorMenu()
                if button.onSelect then
                    button.onSelect(item.value, item)
                end
            end)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function ShowSelectorMenu(button)
    local items = button and button.items or nil
    if button and button.menuBuilder then
        items = button:menuBuilder() or {}
        button.items = items
    end
    if not button or button.disabled or type(items) ~= "table" or #items == 0 then
        T.HideSelectorMenu()
        return
    end
    ShowSelectorMenuLevel(button, items, button, 1)
end

T.ResolveSelectorText = function(items, value, defaultText)
    local text = ResolveSelectorText(items, value)
    if text ~= nil then
        return text
    end
    if defaultText ~= nil then
        return defaultText
    end
    return "-"
end

function T.CreateSelectorButton(parent, config)
    local cfg = config or {}
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(cfg.width or 160, ScaleForSettings(parent, cfg.height or 26, cfg))
    ApplyPoint(button, cfg.point)

    button.selectorOwnerRoot = cfg.ownerFrame or cfg.menuRoot or parent
    button.items = cfg.items or {}
    button.menuBuilder = cfg.menuBuilder
    button.selectedValue = cfg.selectedValue
    button.onSelect = cfg.onSelect
    button.disabled = cfg.enabled == false
    button.emptyText = cfg.emptyText or "-"
    button.selectorLabelFontSize = tonumber(cfg.labelFontSize) or SELECTOR_DEFAULT_FONT_SIZE
    button.selectorValueFontSize = tonumber(cfg.valueFontSize) or SELECTOR_DEFAULT_FONT_SIZE
    button.selectorMinFontSize = tonumber(cfg.minFontSize) or SELECTOR_MIN_FONT_SIZE

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetAtlas("common-dropdown-b-button")

    button.hover = button:CreateTexture(nil, "ARTWORK")
    button.hover:SetAllPoints()
    button.hover:SetAtlas("common-dropdown-b-button-hover")
    button.hover:Hide()

    button.pressed = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.pressed:SetAllPoints()
    button.pressed:SetAtlas("common-dropdown-b-button-pressed")
    button.pressed:Hide()

    button.pressedHover = button:CreateTexture(nil, "ARTWORK", nil, 2)
    button.pressedHover:SetAllPoints()
    button.pressedHover:SetAtlas("common-dropdown-b-button-pressedhover")
    button.pressedHover:Hide()

    button.labelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.labelText:SetPoint("LEFT", button, "LEFT", 10, 0)
    button.labelText:SetWidth(tonumber(cfg.labelWidth) or 44)
    button.labelText:SetJustifyH("LEFT")
    RegisterSettingsFont(parent, button.labelText, button.selectorLabelFontSize, font, "", cfg)
    SetFontStringSize(button.labelText, button.selectorLabelFontSize)
    if button.labelText.SetWordWrap then
        button.labelText:SetWordWrap(false)
    end

    button.arrow = button:CreateTexture(nil, "OVERLAY")
    button.arrow:SetSize(12, 12)
    button.arrow:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    button.arrow:SetAtlas("common-dropdown-c-button-arrow-down")

    button.valueText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.valueText:SetPoint("LEFT", button.labelText, "RIGHT", 6, 0)
    button.valueText:SetPoint("RIGHT", button.arrow, "LEFT", -6, 0)
    button.valueText:SetJustifyH("LEFT")
    RegisterSettingsFont(parent, button.valueText, button.selectorValueFontSize, font, "", cfg)
    SetFontStringSize(button.valueText, button.selectorValueFontSize)
    button.valueText:SetWidth(math.max(1, (cfg.width or 160) - (tonumber(cfg.labelWidth) or 44) - 34))
    if button.valueText.SetWordWrap then
        button.valueText:SetWordWrap(false)
    end

    function button:GetSelectorValueWidth()
        local width = tonumber(self:GetWidth()) or 0
        local labelWidth = tonumber(self.labelText:GetWidth()) or 0
        return math.max(1, width - labelWidth - 34)
    end

    function button:SetItems(items)
        self.items = items or {}
        self:SetSelectedValue(self.selectedValue, self.emptyText)
    end

    function button:SetMenuBuilder(menuBuilder)
        self.menuBuilder = menuBuilder
    end

    function button:SetSelectedValue(value, fallbackText)
        self.selectedValue = value
        self:SetValueText(T.ResolveSelectorText(self.items, value, fallbackText or self.emptyText))
    end

    function button:SetLabel(text)
        self.labelText:SetWidth(self.labelText:GetWidth())
        FitFontString(self.labelText, text or "", self.labelText:GetWidth(), self.selectorLabelFontSize, self.selectorMinFontSize)
    end

    function button:SetValueText(text)
        self.valueText:SetWidth(self:GetSelectorValueWidth())
        FitFontString(self.valueText, text or "-", self:GetSelectorValueWidth(), self.selectorValueFontSize, self.selectorMinFontSize)
    end

    function button:SetSelectorWidth(width)
        self:SetWidth(width)
        if self.valueText then
            self.valueText:SetWidth(self:GetSelectorValueWidth())
        end
        self:SetLabel(self.labelText and self.labelText:GetText() or "")
        self:SetValueText(self.valueText and self.valueText:GetText() or self.emptyText)
    end

    function button:GetValueText()
        return (self.valueText and self.valueText.GetText and self.valueText:GetText()) or ""
    end

    function button:GetSelectedValue()
        return self.selectedValue
    end

    function button:SetSelectorEnabled(enabled)
        self.disabled = enabled == false
        if self.disabled then
            self:Disable()
        else
            self:Enable()
        end
        UpdateSelectorState(self)
    end

    button:SetScript("OnClick", function(self)
        if self.disabled then
            return
        end
        ShowSelectorMenu(self)
    end)

    button:SetScript("OnEnter", function(self)
        self.isOver = true
        UpdateSelectorState(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.isOver = false
        UpdateSelectorState(self)
    end)
    button:SetScript("OnMouseDown", function(self)
        self.isDown = true
        UpdateSelectorState(self)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.isDown = false
        UpdateSelectorState(self)
    end)
    button:HookScript("OnHide", function(self)
        if selectorMenuAnchor == self then
            T.HideSelectorMenu()
        end
        self.isOpen = false
        UpdateSelectorState(self)
    end)
    button:HookScript("OnDisable", function(self)
        self.disabled = true
        UpdateSelectorState(self)
    end)
    button:HookScript("OnEnable", function(self)
        self.disabled = false
        UpdateSelectorState(self)
    end)

    button:SetLabel(cfg.label or "")
    button:SetSelectedValue(cfg.selectedValue)
    if cfg.valueText ~= nil then
        button:SetValueText(cfg.valueText)
    end
    button:SetSelectorEnabled(cfg.enabled ~= false)
    return button
end

-- ═══════════════════════════════════════════════════════════════
-- L3: 复合组件 (Composite Widgets)
-- 可依赖 L1 + L2
-- ═══════════════════════════════════════════════════════════════

function T.CreatePopupWindow(parent, config)
    local cfg = config or {}
    local frame = CreateFrame("Frame", cfg.name, parent or UIParent, "BackdropTemplate")
    frame:SetSize(tonumber(cfg.width) or 520, tonumber(cfg.height) or 300)
    ApplyPoint(frame, cfg.point or { "CENTER" })
    frame:SetFrameStrata(cfg.strata or "DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetToplevel(true)
    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown or not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:HookScript("OnShow", function(self)
        self:SetFrameStrata(cfg.strata or "DIALOG")
        self:SetToplevel(true)
        self:Raise()
    end)
    frame:Hide()

    T.ApplyBackdrop(frame, {
        alpha = cfg.alpha == nil and 0.9 or cfg.alpha,
        style = cfg.style or "tooltip",
        borderColor = cfg.borderColor,
    })

    frame.title = T.CreateFontString(frame, {
        layer = "OVERLAY",
        template = "GameFontHighlight",
        point = { "TOPLEFT", frame, "TOPLEFT", 10, -10 },
        text = cfg.title or "",
        color = cfg.titleColor or { 1, 0.82, 0, 1 },
    })

    if cfg.showClose ~= false then
        frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        frame.closeButton:SetPoint("TOPRIGHT", 6, 6)
    end

    if cfg.escClose ~= false then
        frame:EnableKeyboard(true)
        frame:HookScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
            end
        end)
    end

    return frame
end

local function SetButtonTabState(button, isActive)
    if not button then
        return
    end

    button:SetEnabled(not isActive)
    local fontString = button.GetFontString and button:GetFontString() or button.Text
    if fontString then
        if isActive then
            fontString:SetTextColor(1, 0.92, 0.6, 1)
        else
            fontString:SetTextColor(1, 1, 1, 1)
        end
    end
end

function T.CreateTabGroup(parent, config)
    local cfg = config or {}
    local group = {
        activeKey = nil,
        buttons = {},
        buttonByKey = {},
        tabs = cfg.tabs or {},
        onChange = cfg.onChange,
        style = cfg.style or "button",
    }

    local previous
    for index, tabInfo in ipairs(group.tabs) do
        local key = tabInfo.key or tabInfo[1] or index
        local text = tabInfo.text or tabInfo[2] or tostring(key)
        local button

        if group.style == "panel" then
            button = CreateFrame("Button", tabInfo.name, parent, cfg.template or "PanelTabButtonTemplate")
            button:SetID(index)
            button:SetText(text)
            if index == 1 then
                ApplyPoint(button, cfg.point or { "TOPLEFT", parent, "TOPLEFT", 0, 0 })
            else
                button:SetPoint("TOPLEFT", previous, "TOPRIGHT", cfg.spacing or 2, 0)
            end
            button.SetTabActive = function(self, isActive)
                if isActive then
                    PanelTemplates_SelectTab(self)
                else
                    PanelTemplates_DeselectTab(self)
                end
            end
        else
            button = T.CreateButton(parent, {
                width = tabInfo.width or cfg.buttonWidth or 84,
                height = tabInfo.height or cfg.buttonHeight or 22,
                point = index == 1 and (cfg.point or { "TOPLEFT", parent, "TOPLEFT", 0, 0 }) or nil,
                tooltip = tabInfo.tooltip,
            })
            if index > 1 then
                button:SetPoint("LEFT", previous, "RIGHT", cfg.spacing or 6, 0)
            end
            button:SetText(text)
            button.SetTabActive = SetButtonTabState
        end

        button.__sttTabKey = key
        button.__sttTabGroup = group
        button:SetScript("OnClick", function()
            group:SetActiveTab(key)
        end)

        group.buttons[index] = button
        group.buttonByKey[key] = button
        previous = button
    end

    function group:SetActiveTab(key, silent)
        if self.activeKey == key and not silent then
            return
        end

        for tabKey, button in pairs(self.buttonByKey) do
            button:SetTabActive(tabKey == key)
        end
        self.activeKey = key

        if not silent and type(self.onChange) == "function" then
            self.onChange(key)
        end
    end

    function group:GetActiveTab()
        return self.activeKey
    end

    function group:Refresh()
        for _, tabInfo in ipairs(self.tabs) do
            local key = tabInfo.key or tabInfo[1]
            local button = self.buttonByKey[key]
            if button then
                button:SetText(tabInfo.text or tabInfo[2] or tostring(key))
                button:SetTabActive(self.activeKey == key)
            end
        end
    end

    if #group.tabs > 0 then
        group:SetActiveTab(cfg.defaultTab or group.tabs[1].key or group.tabs[1][1] or 1, true)
    end

    return group
end

function T.CreateCollapsibleSection(parent, config)
    local cfg = type(config) == "table" and config or {}
    local section = CreateFrame("Frame", nil, parent)
    local headerHeight = tonumber(cfg.headerHeight) or 30
    local contentGap = tonumber(cfg.contentGap) or 4
    local headerWidth = math.min(tonumber(cfg.width) or 160, tonumber(cfg.headerWidth) or 160)
    local padding = cfg.padding or {}
    local padLeft = tonumber(padding.left) or 12
    local padTop = tonumber(padding.top) or 12
    local padRight = tonumber(padding.right) or 12
    local padBottom = tonumber(padding.bottom) or 10

    ApplyPoint(section, cfg.point)
    section:SetSize(tonumber(cfg.width) or headerWidth, headerHeight)

    local function resolveLabel()
        if type(cfg.label) == "function" then
            return cfg.label(section) or ""
        end
        return cfg.label or ""
    end

    function section:GetExpanded()
        if type(cfg.getExpanded) == "function" then
            return cfg.getExpanded(section) == true
        end
        return self.__expanded == true
    end

    function section:RefreshHeader()
        if self.headerButton and self.headerButton.Refresh then
            self.headerButton:Refresh()
        end
    end

    section.headerButton = T.CreateActionButton(section, {
        width = headerWidth,
        height = headerHeight,
        point = { "TOPLEFT", section, "TOPLEFT", 0, 0 },
        textFn = function()
            return T.GetDisclosureText(section:GetExpanded(), resolveLabel())
        end,
        onClick = function()
            section:Toggle()
        end,
    })

    section.container = CreateFrame("Frame", nil, section)
    section.container:SetPoint("TOPLEFT", section.headerButton, "BOTTOMLEFT", 0, -contentGap)
    section.container:SetWidth(section:GetWidth())
    section.container:SetFrameStrata(section:GetFrameStrata())
    section.container:SetFrameLevel((section:GetFrameLevel() or 0) + 1)

    if cfg.backdrop ~= false then
        local backdropCfg = type(cfg.backdrop) == "table" and cfg.backdrop or {}
        T.ApplyBackdrop(section.container, {
            alpha = backdropCfg.alpha,
            style = backdropCfg.style,
            borderColor = backdropCfg.borderColor,
            borderAlpha = backdropCfg.borderAlpha,
            bgColor = backdropCfg.bgColor,
            offsets = backdropCfg.offsets,
        })
    end

    section.content = CreateFrame("Frame", nil, section.container)
    section.content:SetPoint("TOPLEFT", section.container, "TOPLEFT", padLeft, -padTop)
    section.content:SetFrameStrata(section.container:GetFrameStrata())
    section.content:SetFrameLevel(math.max(
        (section.container:GetFrameLevel() or 0) + 1,
        ((section.container.sd and section.container.sd:GetFrameLevel()) or 0) + 1
    ))

    local function setExpandedState(state)
        if type(cfg.setExpanded) == "function" then
            cfg.setExpanded(state == true, section)
        else
            section.__expanded = state == true
        end
    end

    function section:RefreshLayout()
        local width = tonumber(cfg.width) or self:GetWidth() or headerWidth
        local expanded = self:GetExpanded()
        local contentWidth = math.max(1, width - padLeft - padRight)
        local contentHeight = tonumber(self.contentHeight) or 0

        self:SetWidth(width)
        self.headerButton:SetWidth(math.min(width, headerWidth))
        self.container:SetWidth(width)
        self.content:SetWidth(contentWidth)

        if expanded and not self.contentRendered and type(cfg.renderContent) == "function" then
            local renderedHeight = cfg.renderContent(self.content, self)
            if tonumber(renderedHeight) then
                self.contentHeight = tonumber(renderedHeight)
                contentHeight = self.contentHeight
            end
            self.contentRendered = true
        end

        if expanded and type(cfg.measureHeight) == "function" then
            local measuredHeight = cfg.measureHeight(self.content, self)
            if tonumber(measuredHeight) then
                self.contentHeight = tonumber(measuredHeight)
                contentHeight = self.contentHeight
            end
        end

        if expanded then
            local containerHeight = math.max(1, contentHeight + padTop + padBottom)
            self.container:Show()
            self.content:SetHeight(math.max(1, contentHeight))
            self.container:SetHeight(containerHeight)
            self:SetHeight(headerHeight + contentGap + containerHeight)
        else
            self.container:Hide()
            self:SetHeight(headerHeight)
        end
    end

    function section:SetExpanded(state)
        local nextState = state == true
        if self:GetExpanded() == nextState then
            self:RefreshHeader()
            self:RefreshLayout()
            return
        end

        setExpandedState(nextState)
        self:RefreshHeader()
        self:RefreshLayout()

        if type(cfg.onToggle) == "function" then
            cfg.onToggle(nextState, self)
        end
    end

    function section:Toggle()
        self:SetExpanded(not self:GetExpanded())
    end

    if type(cfg.getExpanded) ~= "function" then
        section.__expanded = cfg.expanded == true
    end

    section:RefreshHeader()
    section:RefreshLayout()
    return section
end

function T.CreateScrollPanel(parent, config)
    local cfg = config or {}
    local scroll = T.CreateSimpleScroll(parent, cfg)
    if cfg.point1 then
        scroll:SetPoint(unpack(cfg.point1))
    end
    if cfg.point2 then
        scroll:SetPoint(unpack(cfg.point2))
    end
    if cfg.backdrop then
        T.ApplyBackdrop(scroll, {
            alpha = cfg.backdropAlpha or 0.15,
            style = cfg.backdropStyle or "chat",
            borderColor = cfg.borderColor,
        })
    end

    local panel = {
        scroll = scroll,
        content = scroll.content,
    }

    function panel:SetContentHeight(height)
        scroll:SetContentHeight(height)
    end

    if cfg.contentHeight then
        panel:SetContentHeight(cfg.contentHeight)
    end

    return panel
end
