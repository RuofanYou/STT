local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("selfMarker.enabled", function()

local SOLID_BLOCK_TEXTURE = "__solid_block__"
local DEFAULT_SOLID_COLOR = { 0.1, 1, 0.1, 1 }
local NEW_SINCE = "260602.20"

local function CopyColor(value, fallback)
    local src = type(value) == "table" and value or fallback or DEFAULT_SOLID_COLOR
    return {
        tonumber(src[1]) or DEFAULT_SOLID_COLOR[1],
        tonumber(src[2]) or DEFAULT_SOLID_COLOR[2],
        tonumber(src[3]) or DEFAULT_SOLID_COLOR[3],
        tonumber(src[4]) or 1,
    }
end

local function IsSolidBlock(engine)
    return engine:GetValue("selfMarker.texture", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3") == SOLID_BLOCK_TEXTURE
end

local function ApplyEnabledState()
    if T.ModuleLoader then
        if C.DB and C.DB.selfMarker and C.DB.selfMarker.enabled == true then
            T.ModuleLoader:Enable("SelfMarker", "option")
        else
            T.ModuleLoader:Disable("SelfMarker", "option")
        end
    end
end

local function Refresh()
    if T.SelfMarker and T.SelfMarker.Refresh then
        T.SelfMarker:Refresh()
    end
end

local function ApplyTextureOption(_, engine)
    Refresh()
    if engine and engine.Rebuild then
        engine:Rebuild()
    end
end

local function RenderSolidColor(slot, ctx)
    local itemDef = ctx.itemDef
    local swatch
    local button
    local refresh
    local enabled = true

    T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -2 },
        text = ctx.engine:ResolveText(itemDef.textKey, itemDef.key),
        size = 12,
    })

    swatch = CreateFrame("Button", nil, slot)
    swatch:SetSize(46, 22)
    swatch:SetPoint("TOPLEFT", slot, "TOPLEFT", 4, -24)
    T.ApplyBackdrop(swatch, {
        alpha = 0.28,
        style = "tooltip",
        borderColor = { 0.55, 0.55, 0.55, 0.9 },
    })

    local colorTex = swatch:CreateTexture(nil, "BACKGROUND")
    colorTex:SetPoint("TOPLEFT", swatch, "TOPLEFT", 3, -3)
    colorTex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -3, 3)

    local function commit(color)
        ctx.engine:ApplyItem(itemDef, CopyColor(color, DEFAULT_SOLID_COLOR), ctx.moduleDef)
        Refresh()
        if refresh then
            refresh()
        end
    end

    local function openPicker()
        if not enabled then return end
        local original = CopyColor(ctx.engine:GetItemValue(itemDef), itemDef.default)
        ColorPickerFrame:Hide()
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetFrameLevel(slot:GetFrameLevel() + 10)
        ColorPickerFrame:SetClampedToScreen(true)

        local function readPickerColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            return { r, g, b, 1 }
        end

        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                hasOpacity = false,
                r = original[1],
                g = original[2],
                b = original[3],
                swatchFunc = function()
                    commit(readPickerColor())
                end,
                cancelFunc = function()
                    commit(original)
                end,
            })
        else
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame:SetColorRGB(original[1], original[2], original[3])
            ColorPickerFrame.func = function()
                commit(readPickerColor())
            end
            ColorPickerFrame.cancelFunc = function()
                commit(original)
            end
            ColorPickerFrame:Show()
        end
    end

    button = T.CreateActionButton(slot, {
        width = 96,
        height = 24,
        point = { "LEFT", swatch, "RIGHT", 10, 0 },
        textFn = function()
            return L["OPT_SELF_MARKER_PICK_COLOR"] or "选择颜色"
        end,
        onClick = openPicker,
    })
    swatch:SetScript("OnClick", openPicker)

    refresh = function()
        local color = CopyColor(ctx.engine:GetItemValue(itemDef), itemDef.default)
        colorTex:SetColorTexture(color[1], color[2], color[3], 1)
        button:Refresh()
    end
    refresh()

    return {
        height = 54,
        refresh = refresh,
        setEnabled = function(state)
            enabled = state == true
            swatch:SetEnabled(enabled)
            button:SetEnabled(enabled)
        end,
    }
end

local function ResetPosition()
    if T.SelfMarker and T.SelfMarker.ResetPosition then
        T.SelfMarker:ResetPosition()
    end
end

local function RenderAnchorToggle(slot)
    T.CreateActionButton(slot, {
        width = 160,
        height = 24,
        point = { "TOPLEFT", slot, "TOPLEFT", 0, -2 },
        textFn = function()
            if T.SelfMarker and T.SelfMarker:IsEditing() then
                return L["OPT_ANCHOR_LOCK"] or "锁定锚点"
            end
            return L["OPT_ANCHOR_UNLOCK"] or "解锁锚点"
        end,
        onClick = function()
            if T.SelfMarker and T.SelfMarker.ToggleEditMode then
                T.SelfMarker:ToggleEditMode()
            end
        end,
    })
    return 28
end

T.RegisterOptionModule({
    id = "self_marker",
    category = "interface",
    order = 30,
    titleKey = "OPT_SELF_MARKER_TITLE",
    newSince = "260516.16",
    masterToggle = {
        dbPath = "selfMarker.enabled",
        default = false,
        apply = ApplyEnabledState,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "OPT_SELF_MARKER_SECTION_LOOK" },
        {
            key = "texture",
            type = "dropdown",
            textKey = "OPT_SELF_MARKER_TEXTURE",
            width = 0.5,
            dbPath = "selfMarker.texture",
            default = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
            options = {
                { textKey = "OPT_SELF_MARKER_TEX_DIAMOND",   value = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
                { textKey = "OPT_SELF_MARKER_TEX_STAR",      value = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
                { textKey = "OPT_SELF_MARKER_TEX_SQUARE",    value = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
                { textKey = "OPT_SELF_MARKER_TEX_SKULL",     value = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
                { textKey = "OPT_SELF_MARKER_TEX_CROSSHAIR", value = "atlas:crosshair_crosshairs_128" },
                { textKey = "OPT_SELF_MARKER_TEX_ARROW",     value = "Interface\\Minimap\\MinimapArrow" },
                { textKey = "OPT_SELF_MARKER_TEX_SOLID_BLOCK", value = SOLID_BLOCK_TEXTURE },
                { textKey = "OPT_SELF_MARKER_TEX_CUSTOM",    value = "__custom__" },
            },
            apply = ApplyTextureOption,
            newSince = NEW_SINCE,
        },
        {
            key = "solidColor",
            type = "custom",
            textKey = "OPT_SELF_MARKER_SOLID_COLOR",
            width = 0.5,
            height = 54,
            dbPath = "selfMarker.solidColor",
            default = DEFAULT_SOLID_COLOR,
            visible = IsSolidBlock,
            render = RenderSolidColor,
            newSince = NEW_SINCE,
        },
        {
            key = "solidBorder",
            type = "check",
            textKey = "OPT_SELF_MARKER_SOLID_BORDER",
            width = 0.5,
            dbPath = "selfMarker.solidBorder",
            default = true,
            visible = IsSolidBlock,
            apply = Refresh,
            newSince = NEW_SINCE,
        },
        {
            key = "textureCustom",
            type = "editbox",
            textKey = "OPT_SELF_MARKER_TEXTURE_CUSTOM",
            placeholderTextKey = "OPT_SELF_MARKER_TEXTURE_CUSTOM_PLACEHOLDER",
            width = 0.5,
            dbPath = "selfMarker.textureCustom",
            default = "",
            apply = Refresh,
            newSince = "260516.16",
        },
        {
            key = "size",
            type = "slider",
            textKey = "OPT_SELF_MARKER_SIZE",
            width = 0.5,
            dbPath = "selfMarker.size",
            default = 16,
            min = 1,
            max = 100,
            step = 1,
            apply = Refresh,
            newSince = "260516.16",
        },
        {
            key = "alpha",
            type = "slider",
            textKey = "OPT_SELF_MARKER_ALPHA",
            width = 0.5,
            dbPath = "selfMarker.alpha",
            default = 0.5,
            min = 0,
            max = 1,
            step = 0.05,
            apply = Refresh,
            newSince = "260516.16",
        },

        { type = "subtitle", textKey = "OPT_SELF_MARKER_SECTION_ANIM" },
        {
            key = "animation",
            type = "dropdown",
            textKey = "OPT_SELF_MARKER_ANIM",
            width = 0.5,
            dbPath = "selfMarker.animation",
            default = "none",
            options = {
                { textKey = "OPT_SELF_MARKER_ANIM_NONE",   value = "none" },
                { textKey = "OPT_SELF_MARKER_ANIM_PULSE",  value = "pulse" },
                { textKey = "OPT_SELF_MARKER_ANIM_BLINK",  value = "blink" },
                { textKey = "OPT_SELF_MARKER_ANIM_ROTATE", value = "rotate" },
            },
            apply = Refresh,
            newSince = "260516.16",
        },
        {
            key = "animPeriod",
            type = "slider",
            textKey = "OPT_SELF_MARKER_ANIM_PERIOD",
            width = 0.5,
            dbPath = "selfMarker.animPeriod",
            default = 1.5,
            min = 0.5,
            max = 5,
            step = 0.1,
            apply = Refresh,
            newSince = "260516.16",
        },

        { type = "subtitle", textKey = "OPT_SELF_MARKER_SECTION_COMBAT" },
        {
            key = "onlyInCombat",
            type = "check",
            textKey = "OPT_SELF_MARKER_ONLY_IN_COMBAT",
            width = 1,
            dbPath = "selfMarker.onlyInCombat",
            default = true,
            apply = Refresh,
            newSince = "260516.16",
        },

        { type = "subtitle", textKey = "OPT_SELF_MARKER_SECTION_POSITION" },
        {
            key = "anchorToggle",
            type = "custom",
            width = 0.5,
            height = 28,
            render = RenderAnchorToggle,
            newSince = "260516.16",
        },
        {
            key = "resetPosition",
            type = "button",
            textKey = "OPT_SELF_MARKER_RESET_POS",
            width = 0.5,
            onClick = ResetPosition,
            newSince = "260516.16",
        },
        }
    end,
})

end)
