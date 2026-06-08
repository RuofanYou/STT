local T, C, L = unpack(select(2, ...))

local function Clamp(value, minValue, maxValue, fallback)
    local numberValue = tonumber(value)
    if not numberValue then
        return fallback or minValue
    end
    if numberValue < minValue then
        return minValue
    end
    if numberValue > maxValue then
        return maxValue
    end
    return numberValue
end

local function Round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local Style = {
    BASE = {
        SIDEBAR_WIDTH = 210,
        SIDEBAR_INNER_PAD = 20,
        CATEGORY_HEIGHT = 30,
        ITEM_HEIGHT = 26,
        ITEM_GAP = 2,
        CATEGORY_TOP_PAD = 8,
        CATEGORY_BOTTOM_PAD = 4,
        ITEM_INDENT = 17,
        MODULE_TITLE_FONT_SIZE = 14,
        SUBGROUP_FONT_SIZE = 12,
        LABEL_FONT_SIZE = 12,
        NAV_CATEGORY_FONT_SIZE = 13,
        NAV_ITEM_FONT_SIZE = 12,
        SELECTOR_FONT_SIZE = 11,
        SCROLL_BAR_WIDTH = 8,
        CHECKBOX_SIZE = 24,
        CHECKBOX_MARK_SIZE = 14,
        SLIDER_HEIGHT = 20,
        DROPDOWN_HEIGHT = 26,
        BUTTON_HEIGHT = 26,
        DEFAULT_GUI_WIDTH = 900,
        DEFAULT_GUI_HEIGHT = 680,
        LINE_HEIGHT_RATIO = 1.4,
        SLOT_GAP_RATIO = 1.6,
    },
    Color = {
        KYRIAN_GOLD = { 0.98, 0.86, 0.52, 1 },
        TEXT_INACTIVE = { 0.78, 0.78, 0.78, 1 },
        TEXT_HOVER = { 1, 1, 1, 1 },
        SECTION_LINE = { 0.65, 0.55, 0.32, 0.5 },
        SUBGROUP_BAR = { 0.98, 0.86, 0.52, 0.55 },
    },
    Nav = {
        SIDEBAR_WIDTH = 210,
        CATEGORY_HEIGHT = 30,
        ITEM_HEIGHT = 26,
        ITEM_GAP = 2,
        CATEGORY_TOP_PAD = 8,
        CATEGORY_BOTTOM_PAD = 4,
        ITEM_INDENT = 17,
        CATEGORY_DIVIDER_ATLAS = "Options_HorizontalDivider",
        ITEM_ACTIVE_ATLAS = "Options_List_Active",
        ITEM_HOVER_ATLAS = "Options_List_Hover",
    },
    Section = {
        MODULE_TITLE_FONT_SIZE = 14,
        SUBGROUP_FONT_SIZE = 12,
        MODULE_TOP_PAD = 10,
        MODULE_BOTTOM_PAD = 6,
        SUBGROUP_LEFT_BAR_WIDTH = 2,
        ROW_GAP = 2,
        GROUP_GAP = 6,
    },
    Font = {
        NAV_CATEGORY = "GameFontNormal",
        NAV_ITEM = "GameFontHighlightSmall",
        SECTION_TITLE = "GameFontNormalLarge",
        SUBGROUP = "GameFontHighlight",
    },
}

Style._scaledFonts = setmetatable({}, { __mode = "k" })

function Style.GetFontScale()
    local ui = C and C.DB and C.DB.semanticTimeline and C.DB.semanticTimeline.ui
    local scale = Clamp(ui and ui.fontScale, 0.9, 1.6, 1.0)
    if ui and ui.fontScale ~= scale then
        ui.fontScale = scale
    end
    return scale
end

function Style.Scale(value)
    return Round((tonumber(value) or 0) * Style.GetFontScale())
end

function Style.Scaled(token)
    return Style.Scale(Style.BASE[token])
end

function Style.ScaledFontSize(token)
    return math.max(1, Style.Scale(Style.BASE[token]))
end

function Style.LineHeight(fontSize)
    local ratio = tonumber(Style.BASE.LINE_HEIGHT_RATIO) or 1.4
    return math.max(1, Round((tonumber(fontSize) or 1) * ratio / 2) * 2)
end

function Style.RegisterFontString(fontString, config)
    if not (fontString and fontString.SetFont) then
        return
    end
    local cfg = config or {}
    Style._scaledFonts[fontString] = {
        font = cfg.font or STANDARD_TEXT_FONT,
        baseSize = tonumber(cfg.baseSize) or tonumber(cfg.size) or 13,
        flags = cfg.flags,
    }
end

function Style.ApplyRegisteredFonts()
    local scale = Style.GetFontScale()
    for fontString, meta in pairs(Style._scaledFonts) do
        if fontString and fontString.SetFont and meta then
            fontString:SetFont(meta.font or STANDARD_TEXT_FONT, math.max(1, Round((meta.baseSize or 13) * scale)), meta.flags)
        end
    end
end

function Style.ApplyFontScale(reason)
    Style.ApplyRegisteredFonts()
    if T.RefreshSettingsFontScaleLayout then
        T.RefreshSettingsFontScaleLayout(reason or "font_scale")
    elseif T.OptionEngine and T.OptionEngine.Rebuild then
        T.OptionEngine:Rebuild()
    end
end

T.Style = Style
