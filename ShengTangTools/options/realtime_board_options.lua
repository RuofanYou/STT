local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("realtimeBoard.enabled", function()

local function ApplyRealtimeBoard()
    if T.RealtimeBoard and T.RealtimeBoard.RefreshConfig then
        T.RealtimeBoard:RefreshConfig()
    end
end

local scheduledApplyToken = 0
local function ScheduleRealtimeBoardApply()
    scheduledApplyToken = scheduledApplyToken + 1
    local token = scheduledApplyToken
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if token == scheduledApplyToken then
                ApplyRealtimeBoard()
            end
        end)
    else
        ApplyRealtimeBoard()
    end
end

local function FormatBoardDecimal(value)
    return string.format("%.2f", tonumber(value) or 0)
end

local function FormatBoardPercent(value)
    return string.format("%d%%", math.floor((tonumber(value) or 0) * 100 + 0.5))
end

local function CopyColor3(value, fallback)
    local src = type(value) == "table" and value or fallback or { 1, 1, 1 }
    return {
        math.max(0, math.min(1, tonumber(src[1]) or 1)),
        math.max(0, math.min(1, tonumber(src[2]) or 1)),
        math.max(0, math.min(1, tonumber(src[3]) or 1)),
    }
end

local function OpenColorPicker(color, onChange, onCancel)
    local original = CopyColor3(color)
    if T.ShowColorPicker then
        T.ShowColorPicker({
            color = original,
            onChange = function(r, g, b)
                onChange({ r, g, b })
            end,
            onCancel = onCancel,
        })
        return
    end

    ColorPickerFrame:Hide()
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame:SetClampedToScreen(true)
    local function commit()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        onChange({ r, g, b })
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            hasOpacity = false,
            r = original[1],
            g = original[2],
            b = original[3],
            swatchFunc = commit,
            cancelFunc = onCancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(original[1], original[2], original[3])
        ColorPickerFrame.func = commit
        ColorPickerFrame.cancelFunc = onCancel
        ColorPickerFrame:Show()
    end
end

local function BuildColorItem(key, textKey, dbPath, defaultColor, visible)
    return {
        key = key,
        type = "custom",
        textKey = textKey,
        dbPath = dbPath,
        default = defaultColor,
        width = 0.5,
        height = 58,
        visible = visible,
        newSince = "260603.9",
        render = function(slot, ctx)
            local itemDef = ctx.itemDef
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

            local function refresh()
                local color = CopyColor3(ctx.engine:GetItemValue(itemDef), itemDef.default)
                colorTex:SetColorTexture(color[1], color[2], color[3], 1)
            end
            local function commit(color)
                ctx.engine:ApplyItem(itemDef, color, ctx.moduleDef)
                ApplyRealtimeBoard()
                refresh()
            end

            local pickerButton = T.CreateActionButton(slot, {
                width = 96,
                height = 24,
                point = { "LEFT", swatch, "RIGHT", 10, 0 },
                textFn = function()
                    return L["GUI_BAR_PICK_COLOR"] or "选择颜色"
                end,
                onClick = function()
                    local original = CopyColor3(ctx.engine:GetItemValue(itemDef), itemDef.default)
                    OpenColorPicker(original, commit, function()
                        commit(original)
                    end)
                end,
            })

            swatch:SetScript("OnClick", function()
                pickerButton:Click()
            end)

            refresh()
            pickerButton:Refresh()

            return { height = 58, refresh = refresh }
        end,
    }
end

local function BuildTextureOptions()
    local names = { "flat", "blizzard", "default", "smooth" }
    local seen = {}
    for _, name in ipairs(names) do
        seen[name] = true
    end
    if T.GetAvailableTextures then
        for _, name in ipairs(T.GetAvailableTextures()) do
            if not seen[name] then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end
    local options = {}
    for _, name in ipairs(names) do
        options[#options + 1] = { text = tostring(name), value = name }
    end
    return options
end

local function IsFocusStyle(engine)
    return engine:GetValue("realtimeBoard.displayStyle", "classic") == "focus"
end

local function IsListStyle(engine)
    return engine:GetValue("realtimeBoard.displayStyle", "classic") ~= "focus"
end

local function IsClassicStyle(engine)
    return engine:GetValue("realtimeBoard.displayStyle", "classic") == "classic"
end

local function IsClassicGlowEnabled(engine)
    return IsClassicStyle(engine) and engine:GetValue("realtimeBoard.activeHighlight.glowEnabled", false) == true
end

local function ApplyDisplayStyle(value, engine)
    if value == "focus" and engine and engine.SetValue then
        engine:SetValue("realtimeBoard.showHeader", false)
        engine:SetValue("realtimeBoard.bgAlpha", 0)
    elseif value == "focus" then
        C.DB.realtimeBoard = C.DB.realtimeBoard or {}
        C.DB.realtimeBoard.showHeader = false
        C.DB.realtimeBoard.bgAlpha = 0
        if STT_DB then
            STT_DB.realtimeBoard = C.DB.realtimeBoard
        end
    end
    ApplyRealtimeBoard()
    if engine and engine.Rebuild then
        engine:Rebuild()
    end
end

T.RegisterOptionModule({
    id = "realtime",
    category = "tactic",
    order = 50,
    titleKey = "GUI_NAV_REALTIME",
    masterToggle = {
        dbPath = "realtimeBoard.enabled",
        default = false,
        apply = ApplyRealtimeBoard,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_GENERAL" },
        {
            key = "toggleLock",
            type = "button",
            width = 0.5,
            textKey = "GUI_ACTION_TOGGLE_LOCK",
            displayFunc = function()
                if T.RealtimeBoard and T.RealtimeBoard.IsLocked and T.RealtimeBoard:IsLocked() then
                    return L["解锁位置"] or "解锁位置"
                end
                return L["锁定位置"] or "锁定位置"
            end,
            onClick = function()
                if T.RealtimeBoard and T.RealtimeBoard.SetLocked then
                    T.RealtimeBoard:SetLocked(not T.RealtimeBoard:IsLocked())
                end
            end,
        },
        {
            key = "resetPosition",
            type = "button",
            width = 0.5,
            textKey = "重置位置",
            onClick = function()
                if T.RealtimeBoard and T.RealtimeBoard.ResetPosition then
                    T.RealtimeBoard:ResetPosition()
                end
            end,
        },
        {
            key = "persistentOutOfCombat",
            type = "check",
            textKey = "战斗外常驻显示",
            tooltipKey = "战斗外常驻显示_TOOLTIP",
            width = 1,
            dbPath = "realtimeBoard.persistentOutOfCombat",
            default = false,
            newSince = "260510.1",
            apply = function(value)
                if not T.TimelineRunner then
                    return
                end
                if value then
                    if not InCombatLockdown() then
                        T.TimelineRunner:StartStaticPreview()
                    end
                else
                    T.TimelineRunner:StopStaticPreview()
                end
            end,
        },
        { type = "subtitle", textKey = "GUI_BOARD_COMMON_DISPLAY" },
        {
            key = "displayStyle",
            type = "dropdown",
            textKey = "GUI_BOARD_DISPLAY_STYLE",
            width = 0.5,
            dbPath = "realtimeBoard.displayStyle",
            default = "classic",
            options = {
                { textKey = "GUI_BOARD_DISPLAY_CLASSIC", value = "classic" },
                { textKey = "GUI_BOARD_DISPLAY_FOCUS", value = "focus" },
                { textKey = "GUI_BOARD_DISPLAY_CONCISE", value = "concise" },
            },
            apply = ApplyDisplayStyle,
        },
        {
            key = "scale",
            type = "slider",
            textKey = "缩放",
            width = 0.5,
            dbPath = "realtimeBoard.scale",
            default = 1,
            min = 0.6,
            max = 1.6,
            step = 0.05,
            formatFunc = FormatBoardDecimal,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "fontSize",
            type = "slider",
            textKey = "GUI_BOARD_FONT_SIZE",
            width = 0.5,
            dbPath = "realtimeBoard.fontSize",
            default = 13,
            min = 10,
            max = 20,
            step = 1,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "rowHeight",
            type = "slider",
            textKey = "行高",
            width = 0.5,
            dbPath = "realtimeBoard.rowHeight",
            default = 32,
            min = 24,
            max = 48,
            step = 1,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "spellDisplayMode",
            type = "dropdown",
            textKey = "GUI_BOARD_SPELL_DISPLAY_MODE",
            width = 0.5,
            dbPath = "realtimeBoard.spellDisplayMode",
            default = "iconText",
            options = {
                { textKey = "SR_SPELL_DISPLAY_ICON_TEXT", value = "iconText" },
                { textKey = "SR_SPELL_DISPLAY_ICON", value = "icon" },
                { textKey = "SR_SPELL_DISPLAY_TEXT", value = "text" },
            },
            newSince = "260520.15",
            apply = ApplyRealtimeBoard,
        },
        {
            key = "showAudienceName",
            type = "check",
            textKey = "GUI_BOARD_SHOW_AUDIENCE_NAME",
            width = 0.5,
            dbPath = "realtimeBoard.showAudienceName",
            default = true,
            newSince = "260519.48",
            apply = ApplyRealtimeBoard,
        },
        {
            key = "countdownFormat",
            type = "dropdown",
            textKey = "GUI_BOARD_COUNTDOWN_FORMAT",
            width = 0.5,
            dbPath = "realtimeBoard.countdownFormat",
            default = "precise",
            options = {
                { textKey = "小数", value = "precise" },
                { textKey = "整数", value = "seconds" },
                { textKey = "分秒", value = "full" },
                { textKey = "战斗时长", value = "elapsed" },
            },
            apply = ApplyRealtimeBoard,
        },
        {
            key = "timePosition",
            type = "dropdown",
            textKey = "GUI_BOARD_TIME_POSITION",
            width = 0.5,
            dbPath = "realtimeBoard.timePosition",
            default = "right",
            options = {
                { textKey = "GUI_BOARD_TIME_RIGHT_EDGE", value = "right" },
                { textKey = "GUI_BOARD_TIME_BEFORE_ICON", value = "left" },
            },
            apply = ApplyRealtimeBoard,
        },
        {
            key = "showAllEvents",
            type = "check",
            textKey = "GUI_BOARD_SHOW_ALL_EVENTS",
            width = 1,
            dbPath = "realtimeBoard.showAllEvents",
            default = false,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "cellStyle",
            type = "dropdown",
            textKey = "条目样式",
            width = 1,
            dbPath = "realtimeBoard.cellStyle",
            default = "clean",
            options = {
                { textKey = "清爽", value = "clean" },
                { textKey = "卡片", value = "card" },
            },
            apply = ApplyRealtimeBoard,
        },
        { type = "subtitle", textKey = "GUI_BOARD_ACTIVE_HIGHLIGHT_SECTION", visible = IsClassicStyle },
        BuildColorItem("activeHighlightColor", "GUI_BOARD_ACTIVE_HIGHLIGHT_COLOR", "realtimeBoard.activeHighlight.color", { 0.20, 0.50, 0.35 }, IsClassicStyle),
        {
            key = "activeHighlightAlpha",
            type = "slider",
            textKey = "GUI_BOARD_ACTIVE_HIGHLIGHT_ALPHA",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.alpha",
            default = 0.25,
            min = 0,
            max = 1,
            step = 0.01,
            visible = IsClassicStyle,
            formatFunc = FormatBoardPercent,
            newSince = "260603.9",
            apply = ScheduleRealtimeBoardApply,
        },
        {
            key = "activeHighlightTexture",
            type = "dropdown",
            textKey = "GUI_BOARD_ACTIVE_HIGHLIGHT_TEXTURE",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.texture",
            default = "flat",
            options = BuildTextureOptions,
            visible = IsClassicStyle,
            newSince = "260603.9",
            apply = ApplyRealtimeBoard,
        },
        {
            key = "activeHighlightIndicatorWidth",
            type = "slider",
            textKey = "GUI_BOARD_ACTIVE_HIGHLIGHT_INDICATOR_WIDTH",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.indicatorWidth",
            default = 3,
            min = 1,
            max = 10,
            step = 1,
            visible = IsClassicStyle,
            newSince = "260603.9",
            apply = ScheduleRealtimeBoardApply,
        },
        {
            key = "activeHighlightGlowEnabled",
            type = "check",
            textKey = "GUI_BOARD_ACTIVE_HIGHLIGHT_GLOW_ENABLED",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.glowEnabled",
            default = false,
            visible = IsClassicStyle,
            newSince = "260603.9",
            apply = function(value, engine)
                ApplyRealtimeBoard()
                if engine and engine.Rebuild then
                    engine:Rebuild()
                end
            end,
        },
        BuildColorItem("activeHighlightGlowColor", "GUI_BOARD_ACTIVE_HIGHLIGHT_GLOW_COLOR", "realtimeBoard.activeHighlight.glowColor", { 1.00, 0.95, 0.10 }, IsClassicGlowEnabled),
        {
            key = "activeHighlightGlowAlpha",
            type = "slider",
            textKey = "GUI_BOARD_ACTIVE_HIGHLIGHT_GLOW_ALPHA",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.glowAlpha",
            default = 0.9,
            min = 0,
            max = 1,
            step = 0.01,
            visible = IsClassicGlowEnabled,
            formatFunc = FormatBoardPercent,
            newSince = "260603.9",
            apply = ScheduleRealtimeBoardApply,
        },
        {
            key = "activeHighlightGlowLines",
            type = "slider",
            textKey = "SR_PIXEL_GLOW_LINES",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.glowLines",
            default = 4,
            min = 1,
            max = 30,
            step = 1,
            visible = IsClassicGlowEnabled,
            newSince = "260603.18",
            apply = ScheduleRealtimeBoardApply,
        },
        {
            key = "activeHighlightGlowFrequency",
            type = "slider",
            textKey = "SR_PIXEL_GLOW_FREQUENCY",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.glowFrequency",
            default = 0.12,
            min = -2,
            max = 2,
            step = 0.05,
            visible = IsClassicGlowEnabled,
            formatFunc = FormatBoardDecimal,
            newSince = "260603.18",
            apply = ScheduleRealtimeBoardApply,
        },
        {
            key = "activeHighlightGlowLength",
            type = "slider",
            textKey = "SR_PIXEL_GLOW_LENGTH",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.glowLength",
            default = 8,
            min = 1,
            max = 60,
            step = 1,
            visible = IsClassicGlowEnabled,
            newSince = "260603.18",
            apply = ScheduleRealtimeBoardApply,
        },
        {
            key = "activeHighlightGlowThickness",
            type = "slider",
            textKey = "SR_PIXEL_GLOW_THICKNESS",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.glowThickness",
            default = 1,
            min = 1,
            max = 12,
            step = 1,
            visible = IsClassicGlowEnabled,
            newSince = "260603.18",
            apply = ScheduleRealtimeBoardApply,
        },
        {
            key = "activeHighlightGlowXOffset",
            type = "slider",
            textKey = "SR_PIXEL_GLOW_X_OFFSET",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.glowXOffset",
            default = 0,
            min = -50,
            max = 50,
            step = 1,
            visible = IsClassicGlowEnabled,
            newSince = "260603.18",
            apply = ScheduleRealtimeBoardApply,
        },
        {
            key = "activeHighlightGlowYOffset",
            type = "slider",
            textKey = "SR_PIXEL_GLOW_Y_OFFSET",
            width = 0.5,
            dbPath = "realtimeBoard.activeHighlight.glowYOffset",
            default = 0,
            min = -50,
            max = 50,
            step = 1,
            visible = IsClassicGlowEnabled,
            newSince = "260603.18",
            apply = ScheduleRealtimeBoardApply,
        },
        { type = "subtitle", textKey = "GUI_BOARD_LIST_SETTINGS", visible = IsListStyle },
        {
            key = "bgAlpha",
            type = "slider",
            textKey = "GUI_BOARD_BG_ALPHA",
            width = 0.5,
            dbPath = "realtimeBoard.bgAlpha",
            default = 0.65,
            min = 0,
            max = 0.95,
            step = 0.05,
            visible = IsListStyle,
            formatFunc = FormatBoardPercent,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "showHeader",
            type = "check",
            textKey = "GUI_BOARD_SHOW_HEADER",
            width = 0.5,
            dbPath = "realtimeBoard.showHeader",
            default = true,
            visible = IsListStyle,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "autoScrollDelay",
            type = "slider",
            textKey = "GUI_BOARD_AUTO_SCROLL_DELAY",
            width = 0.5,
            dbPath = "realtimeBoard.autoScrollDelay",
            default = 3,
            min = 1,
            max = 8,
            step = 0.5,
            visible = IsListStyle,
            formatFunc = FormatBoardDecimal,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "smoothSpeed",
            type = "slider",
            textKey = "GUI_BOARD_SMOOTH_SPEED",
            width = 0.5,
            dbPath = "realtimeBoard.smoothSpeed",
            default = 8,
            min = 2,
            max = 16,
            step = 0.5,
            visible = IsListStyle,
            formatFunc = FormatBoardDecimal,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "expiredMode",
            type = "dropdown",
            textKey = "GUI_BOARD_EXPIRED_MODE",
            width = 0.5,
            dbPath = "realtimeBoard.expiredMode",
            default = "gray",
            options = {
                { textKey = "保留", value = "gray" },
                { textKey = "淡出", value = "fade" },
                { textKey = "GUI_HIDE_IMMEDIATELY", value = "hide" },
            },
            visible = IsListStyle,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "anchorPosition",
            type = "dropdown",
            textKey = "GUI_BOARD_ACTIVE_POSITION",
            width = 0.5,
            dbPath = "realtimeBoard.anchorPosition",
            default = "flow",
            options = {
                { textKey = "自然滚动", value = "flow" },
                { textKey = "顶部固定", value = "top" },
                { textKey = "底部固定", value = "bottom" },
            },
            visible = IsListStyle,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "timeDirection",
            type = "dropdown",
            textKey = "GUI_BOARD_TIME_DIRECTION",
            width = 0.5,
            dbPath = "realtimeBoard.timeDirection",
            default = "down",
            options = {
                { textKey = "向下", value = "down" },
                { textKey = "向上", value = "up" },
            },
            visible = IsListStyle,
            apply = ApplyRealtimeBoard,
        },
        { type = "subtitle", textKey = "GUI_BOARD_FOCUS_SETTINGS", visible = IsFocusStyle },
        {
            key = "focusUpNeighbors",
            type = "slider",
            textKey = "GUI_BOARD_FOCUS_UP_NEIGHBORS",
            width = 0.5,
            dbPath = "realtimeBoard.focus.upNeighbors",
            default = 2,
            min = 0,
            max = 4,
            step = 1,
            visible = IsFocusStyle,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "focusDownNeighbors",
            type = "slider",
            textKey = "GUI_BOARD_FOCUS_DOWN_NEIGHBORS",
            width = 0.5,
            dbPath = "realtimeBoard.focus.downNeighbors",
            default = 2,
            min = 0,
            max = 4,
            step = 1,
            visible = IsFocusStyle,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "focusEmphasis",
            type = "slider",
            textKey = "GUI_BOARD_FOCUS_EMPHASIS",
            width = 1,
            dbPath = "realtimeBoard.focus.emphasis",
            default = 0.55,
            min = 0,
            max = 1,
            step = 0.01,
            visible = IsFocusStyle,
            formatFunc = FormatBoardPercent,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "focusWidthRatio",
            type = "slider",
            textKey = "GUI_BOARD_FOCUS_WIDTH_RATIO",
            width = 0.5,
            dbPath = "realtimeBoard.focus.widthRatio",
            default = 1.00,
            min = 0.50,
            max = 1.00,
            step = 0.01,
            visible = IsFocusStyle,
            formatFunc = FormatBoardPercent,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "focusSpacing",
            type = "slider",
            textKey = "GUI_BOARD_FOCUS_SPACING",
            width = 0.5,
            dbPath = "realtimeBoard.focus.spacingPx",
            default = 4,
            min = 0,
            max = 24,
            step = 1,
            visible = IsFocusStyle,
            formatFunc = function(value)
                return string.format("%d px", math.floor((tonumber(value) or 0) + 0.5))
            end,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "focusHoldSeconds",
            type = "slider",
            textKey = "GUI_BOARD_FOCUS_HOLD_SECONDS",
            width = 0.5,
            dbPath = "realtimeBoard.focus.holdSeconds",
            default = 0.7,
            min = 0,
            max = 3,
            step = 0.1,
            visible = IsFocusStyle,
            formatFunc = function(value)
                return string.format("%.1fs", tonumber(value) or 0)
            end,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "focusDepartureEnabled",
            type = "check",
            textKey = "GUI_BOARD_FOCUS_DEPARTURE_ENABLED",
            width = 0.5,
            dbPath = "realtimeBoard.focus.departureEnabled",
            default = true,
            clickLabel = true,
            visible = IsFocusStyle,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "focusAlign",
            type = "dropdown",
            textKey = "GUI_BOARD_FOCUS_ALIGN",
            width = 0.5,
            dbPath = "realtimeBoard.focus.align",
            default = "left",
            options = {
                { textKey = "GUI_BOARD_ALIGN_LEFT", value = "left" },
                { textKey = "GUI_BOARD_ALIGN_CENTER", value = "center" },
                { textKey = "GUI_BOARD_ALIGN_RIGHT", value = "right" },
            },
            visible = IsFocusStyle,
            apply = ApplyRealtimeBoard,
        },
        {
            key = "maxLookahead",
            type = "slider",
            textKey = "GUI_BOARD_MAX_LOOKAHEAD",
            width = 1,
            dbPath = "realtimeBoard.maxLookahead",
            default = 0,
            min = 0,
            max = 120,
            step = 5,
            visible = IsListStyle,
            apply = ApplyRealtimeBoard,
        },
        }
    end,
})

end)
