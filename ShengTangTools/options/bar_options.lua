local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("Bar.Enabled", function()

local function RefreshBars()
    if T.SegmentedBar and T.SegmentedBar.RefreshActiveStyle then
        T.SegmentedBar:RefreshActiveStyle()
    end
end

local function CopyColor(value, fallback)
    local src = type(value) == "table" and value or fallback or { 1, 1, 1, 1 }
    return {
        tonumber(src[1]) or 1,
        tonumber(src[2]) or 1,
        tonumber(src[3]) or 1,
        tonumber(src[4]) or 1,
    }
end

local function BuildColorItem(key, textKey, dbPath, defaultColor)
    return {
        key = key,
        type = "custom",
        textKey = textKey,
        dbPath = dbPath,
        default = defaultColor,
        height = 58,
        render = function(slot, ctx)
            local itemDef = ctx.itemDef
            local refresh

            T.CreateLabel(slot, {
                point = { "TOPLEFT", slot, "TOPLEFT", 4, -2 },
                text = ctx.engine:ResolveText(itemDef.textKey, itemDef.key),
                size = 12,
            })

            local swatch = CreateFrame("Button", nil, slot)
            swatch:SetSize(48, 24)
            swatch:SetPoint("TOPLEFT", slot, "TOPLEFT", 4, -24)
            T.ApplyBackdrop(swatch, {
                alpha = 0.28,
                style = "tooltip",
                borderColor = { 0.55, 0.55, 0.55, 0.9 },
            })

            local colorTex = swatch:CreateTexture(nil, "BACKGROUND")
            colorTex:SetPoint("TOPLEFT", swatch, "TOPLEFT", 3, -3)
            colorTex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -3, 3)

            local valueText = T.CreateLabel(slot, {
                point = { "LEFT", swatch, "RIGHT", 10, 0 },
                text = "",
                size = 11,
                color = { 0.92, 0.92, 0.92, 1 },
            })

            local function commitColor(color)
                ctx.engine:ApplyItem(itemDef, color, ctx.moduleDef)
                RefreshBars()
                if refresh then
                    refresh()
                end
            end

            local pickerButton = T.CreateActionButton(slot, {
                width = 86,
                height = 24,
                point = { "TOPRIGHT", slot, "TOPRIGHT", -4, -24 },
                textFn = function()
                    return L["GUI_BAR_PICK_COLOR"] or "选择颜色"
                end,
                onClick = function()
                    local original = CopyColor(ctx.engine:GetItemValue(itemDef), itemDef.default)
                    ColorPickerFrame:Hide()
                    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                    ColorPickerFrame:SetFrameLevel(slot:GetFrameLevel() + 10)
                    ColorPickerFrame:SetClampedToScreen(true)

                    local function readPickerColor()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or original[4]
                        return { r, g, b, a }
                    end

                    if ColorPickerFrame.SetupColorPickerAndShow then
                        ColorPickerFrame:SetupColorPickerAndShow({
                            hasOpacity = true,
                            r = original[1],
                            g = original[2],
                            b = original[3],
                            opacity = original[4],
                            swatchFunc = function()
                                commitColor(readPickerColor())
                            end,
                            opacityFunc = function()
                                commitColor(readPickerColor())
                            end,
                            cancelFunc = function()
                                commitColor(original)
                            end,
                        })
                    else
                        ColorPickerFrame.hasOpacity = true
                        ColorPickerFrame.opacity = 1 - (original[4] or 1)
                        ColorPickerFrame:SetColorRGB(original[1], original[2], original[3])
                        ColorPickerFrame.func = function()
                            local r, g, b = ColorPickerFrame:GetColorRGB()
                            local a = 1 - (OpacitySliderFrame:GetValue() or 0)
                            commitColor({ r, g, b, a })
                        end
                        ColorPickerFrame.opacityFunc = ColorPickerFrame.func
                        ColorPickerFrame.cancelFunc = function()
                            commitColor(original)
                        end
                        ColorPickerFrame:Show()
                    end
                end,
            })

            swatch:SetScript("OnClick", function()
                pickerButton:Click()
            end)

            refresh = function()
                local color = CopyColor(ctx.engine:GetItemValue(itemDef), itemDef.default)
                colorTex:SetColorTexture(color[1], color[2], color[3], color[4])
                valueText:SetText(string.format("%.2f / %.2f / %.2f / %.2f", color[1], color[2], color[3], color[4]))
                pickerButton:Refresh()
            end
            refresh()

            return { height = 58, refresh = refresh }
        end,
    }
end

T.RegisterOptionModule({
    id = "segmented_bar",
    category = "tactic",
    order = 13,
    titleKey = "GUI_NAV_SEGMENTED_BAR",
    masterToggle = {
        dbPath = "Bar.Enabled",
        default = true,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_SEGMENTED_BAR" },
        {
            key = "barTest",
            type = "button",
            width = 0.5,
            textKey = "GUI_BAR_TEST",
            onClick = function()
                if T.SegmentedBar and T.SegmentedBar.ShowTest then
                    T.SegmentedBar:ShowTest()
                end
            end,
        },
        {
            key = "barClear",
            type = "button",
            width = 0.5,
            textKey = "GUI_BAR_CLEAR",
            onClick = function()
                if T.ClearAllBars then
                    T.ClearAllBars()
                end
            end,
        },
        {
            key = "barAnchorToggle",
            type = "custom",
            width = 0.5,
            height = 28,
            render = function(slot)
                T.CreateActionButton(slot, {
                    width = 160,
                    height = 24,
                    point = { "TOPLEFT", slot, "TOPLEFT", 0, -2 },
                    textFn = function()
                        if T.SegmentedBar and T.SegmentedBar:IsAnchorUnlocked() then
                            return L["OPT_ANCHOR_LOCK"] or "锁定锚点"
                        end
                        return L["OPT_ANCHOR_UNLOCK"] or "解锁锚点"
                    end,
                    onClick = function()
                        if T.SegmentedBar and T.SegmentedBar.ToggleAnchorLock then
                            T.SegmentedBar:ToggleAnchorLock()
                        end
                    end,
                })
                return 28
            end,
            newSince = "260516.24",
        },
        {
            key = "barWidth",
            type = "slider",
            textKey = "GUI_BAR_WIDTH",
            width = 0.5,
            dbPath = "Bar.Style.width",
            default = 240,
            min = 120,
            max = 520,
            step = 1,
            apply = RefreshBars,
            tooltipKey = "STT_TT_BAR_WIDTH",
        },
        {
            key = "barHeight",
            type = "slider",
            textKey = "GUI_BAR_HEIGHT",
            width = 0.5,
            dbPath = "Bar.Style.height",
            default = 22,
            min = 10,
            max = 48,
            step = 1,
            apply = RefreshBars,
        },
        {
            key = "barSpacing",
            type = "slider",
            textKey = "GUI_BAR_SPACING",
            width = 0.5,
            dbPath = "Bar.Container.spacing",
            default = 4,
            min = 0,
            max = 24,
            step = 1,
            apply = RefreshBars,
        },
        {
            key = "barGrowth",
            type = "dropdown",
            textKey = "GUI_BAR_GROWTH",
            width = 0.5,
            dbPath = "Bar.Container.growth",
            default = "DOWN",
            options = {
                { textKey = "GUI_BAR_GROW_DOWN", value = "DOWN" },
                { textKey = "GUI_BAR_GROW_UP", value = "UP" },
            },
            apply = RefreshBars,
        },
        {
            key = "barTickFontSize",
            type = "slider",
            textKey = "GUI_BAR_TICK_FONT_SIZE",
            width = 0.5,
            dbPath = "Bar.Style.tickFontSize",
            default = 13,
            min = 8,
            max = 24,
            step = 1,
            apply = RefreshBars,
        },
        {
            key = "barLabelFontSize",
            type = "slider",
            textKey = "GUI_BAR_LABEL_FONT_SIZE",
            width = 0.5,
            dbPath = "Bar.Style.labelFontSize",
            default = 13,
            min = 8,
            max = 24,
            step = 1,
            apply = RefreshBars,
        },
        {
            key = "barTickWidth",
            type = "slider",
            textKey = "GUI_BAR_TICK_WIDTH",
            width = 0.5,
            dbPath = "Bar.Style.tickWidth",
            default = 2,
            min = 1,
            max = 8,
            step = 1,
            apply = RefreshBars,
        },
        {
            key = "barIconSize",
            type = "slider",
            textKey = "GUI_BAR_ICON_SIZE",
            width = 0.5,
            dbPath = "Bar.Style.iconSize",
            default = 22,
            min = 0,
            max = 48,
            step = 1,
            apply = RefreshBars,
        },
        {
            key = "barIconGap",
            type = "slider",
            textKey = "GUI_BAR_ICON_GAP",
            width = 0.5,
            dbPath = "Bar.Style.iconGap",
            default = 2,
            min = 0,
            max = 16,
            step = 1,
            apply = RefreshBars,
        },
        {
            key = "barLabelOffset",
            type = "slider",
            textKey = "GUI_BAR_LABEL_OFFSET",
            width = 0.5,
            dbPath = "Bar.Style.labelOffset",
            default = 4,
            min = 0,
            max = 20,
            step = 1,
            apply = RefreshBars,
        },
        {
            key = "barWarnThreshold",
            type = "slider",
            textKey = "GUI_BAR_WARN_THRESHOLD",
            width = 0.5,
            dbPath = "Bar.Style.tickWarnThreshold",
            default = 0.5,
            min = 0,
            max = 2,
            step = 0.1,
            apply = RefreshBars,
        },
        {
            key = "barLabelRemainFmt",
            type = "editbox",
            textKey = "GUI_BAR_LABEL_REMAIN_FMT",
            width = 0.5,
            dbPath = "Bar.Style.labelRemainFmt",
            default = " (%.1f)",
            apply = RefreshBars,
        },
        { type = "subtitle", textKey = "GUI_SUBTITLE_SEGMENTED_BAR_COLORS" },
        BuildColorItem("barBgColor", "GUI_BAR_BG_COLOR", "Bar.Style.bgColor", { 0, 0, 0, 0.55 }),
        BuildColorItem("barColor", "GUI_BAR_FILL_COLOR", "Bar.Style.barColor", { 0.55, 0.25, 0.85, 1 }),
        BuildColorItem("barBorderColor", "GUI_BAR_BORDER_COLOR", "Bar.Style.borderColor", { 0, 0, 0, 1 }),
        BuildColorItem("barTickColor", "GUI_BAR_TICK_COLOR", "Bar.Style.tickColor", { 1, 1, 1, 0.85 }),
        BuildColorItem("barTickFontColor", "GUI_BAR_TICK_FONT_COLOR", "Bar.Style.tickFontColor", { 1, 1, 1, 1 }),
        BuildColorItem("barTickWarnColor", "GUI_BAR_TICK_WARN_COLOR", "Bar.Style.tickWarnColor", { 1, 0.3, 0.3, 1 }),
        BuildColorItem("barLabelFontColor", "GUI_BAR_LABEL_FONT_COLOR", "Bar.Style.labelFontColor", { 1, 1, 1, 1 }),
        }
    end,
})

end)
