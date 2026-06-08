local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.ui.enabled", function()

local function ApplyTacticalUI()
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.RefreshTimelineStyle then
        T.SemanticTimelineGUI.RefreshTimelineStyle()
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
                ApplyTacticalUI()
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
    id = "tactical_ui",
    category = "tactic",
    order = 30,
    titleKey = "GUI_NAV_TACTICAL_UI",
    masterToggle = {
        dbPath = "semanticTimeline.ui.enabled",
        default = false,
        apply = ApplyTacticalUI,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_CELL_STYLE" },
        {
            key = "cellWidth",
            type = "slider",
            textKey = "单元格宽度",
            width = 0.5,
            dbPath = "semanticTimeline.ui.cellWidth",
            default = 120,
            min = 80,
            max = 200,
            step = 1,
            apply = ApplyTacticalUI,
        },
        {
            key = "rowHeight",
            type = "slider",
            textKey = "行高",
            width = 0.5,
            dbPath = "semanticTimeline.ui.rowHeight",
            default = 26,
            min = 20,
            max = 40,
            step = 1,
            apply = ApplyTacticalUI,
        },
        {
            key = "iconSize",
            type = "slider",
            textKey = "图标大小",
            width = 0.5,
            dbPath = "semanticTimeline.ui.iconSize",
            default = 16,
            min = 12,
            max = 24,
            step = 1,
            apply = ApplyTacticalUI,
        },
        {
            key = "cellGap",
            type = "slider",
            textKey = "单元格间距",
            width = 0.5,
            dbPath = "semanticTimeline.ui.cellGap",
            default = 2,
            min = 0,
            max = 10,
            step = 1,
            apply = ApplyTacticalUI,
        },
        { type = "subtitle", textKey = "GUI_SUBTITLE_HORIZONTAL_TIMELINE" },
        {
            key = "durationBarHeight",
            type = "slider",
            textKey = "GUI_DURATION_BAR_HEIGHT",
            width = 0.5,
            dbPath = "semanticTimeline.ui.durationBarHeight",
            default = 6,
            min = 2,
            max = 14,
            step = 1,
            apply = ApplyTacticalUI,
        },
        BuildColorItem("durationBarColor", "GUI_DURATION_BAR_COLOR", "semanticTimeline.ui.durationBarColor", { 0.4, 0.7, 1.0, 0.55 }),
        { type = "subtitle", textKey = "GUI_SUBTITLE_SOURCE" },
        {
            key = "dataSource",
            type = "dropdown",
            textKey = "数据源选择",
            width = 1,
            dbPath = "dataSource",
            default = "STN",
            options = {
                { textKey = "圣糖战术板(STN)", value = "STN" },
                { textKey = "MRT笔记", value = "MRT" },
            },
        },
        {
            key = "useRaidNote",
            type = "check",
            textKey = "读取团队笔记",
            width = 0.5,
            dbPath = "useRaidNote",
            default = true,
            depend = { key = "dataSource", value = "MRT" },
        },
        {
            key = "useSelfNote",
            type = "check",
            textKey = "读取个人笔记",
            width = 0.5,
            dbPath = "useSelfNote",
            default = true,
            depend = { key = "dataSource", value = "MRT" },
        },
        { type = "subtitle", textKey = "GUI_SUBTITLE_PLAN_RESOLVE" },
        {
            key = "personalOverridesTeam",
            type = "check",
            textKey = "PERSONAL_OVERRIDES_TEAM_PLAN",
            width = 1,
            dbPath = "semanticTimeline.personalOverridesTeam",
            default = true,
            depend = {
                dbPath = "semanticTimeline.resolveSource",
                value = "team_plus_personal",
            },
        },
        { type = "subtitle", textKey = "GUI_SUBTITLE_PLAN_SYNC" },
        {
            key = "syncOnlyFromLeader",
            type = "check",
            textKey = "SYNC_ONLY_FROM_LEADER",
            width = 1,
            dbPath = "syncOnlyFromLeader",
            default = true,
        },
        { type = "subtitle", textKey = "GUI_SUBTITLE_LAYOUT_RESET" },
        {
            key = "resetPlanLayout",
            type = "button",
            width = 1,
            textKey = "RESET_PLAN_LAYOUT",
            onClick = function()
                StaticPopup_Show("STT_RESET_PLAN_LAYOUT")
            end,
        },
        }
    end,
})

end)
