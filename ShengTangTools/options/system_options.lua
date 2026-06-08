local T, C, L = unpack(select(2, ...))

local FONT_SCALE_PRESETS = {
    { key = "STT_FONT_SCALE_PRESET_S", value = 0.9, fallback = "小" },
    { key = "STT_FONT_SCALE_PRESET_N", value = 1.0, fallback = "标准" },
    { key = "STT_FONT_SCALE_PRESET_L", value = 1.2, fallback = "大" },
    { key = "STT_FONT_SCALE_PRESET_XL", value = 1.4, fallback = "特大" },
    { key = "STT_FONT_SCALE_PRESET_XXL", value = 1.6, fallback = "最大" },
}

local function RoundFontScale(value)
    return math.floor((tonumber(value) or 1) / 0.05 + 0.5) * 0.05
end

local function ApplyFontScale(value, engine, itemDef)
    local ui = C and C.DB and C.DB.semanticTimeline and C.DB.semanticTimeline.ui
    local oldScale = itemDef and itemDef.__oldScale or (ui and ui.fontScale) or 1
    if T.ApplySettingsFontScale then
        T.ApplySettingsFontScale(value, oldScale, "slider")
    elseif T.Style and T.Style.ApplyFontScale then
        T.Style.ApplyFontScale("font_scale_option")
    end
end

local function RenderFontScalePresets(parent, context)
    local width = math.max(1, tonumber(context.width) or 1)
    local gap = T.Style and T.Style.Scale and T.Style.Scale(6) or 6
    local buttonWidth = math.floor((width - gap * (#FONT_SCALE_PRESETS - 1)) / #FONT_SCALE_PRESETS)

    for index, preset in ipairs(FONT_SCALE_PRESETS) do
        local button = T.CreateActionButton(parent, {
            width = buttonWidth,
            height = T.Style and T.Style.BASE and T.Style.BASE.BUTTON_HEIGHT or 26,
            point = { "TOPLEFT", parent, "TOPLEFT", (index - 1) * (buttonWidth + gap), 0 },
            textFn = function()
                return L[preset.key] or preset.fallback
            end,
            onClick = function()
                local ui = C and C.DB and C.DB.semanticTimeline and C.DB.semanticTimeline.ui
                local oldScale = ui and ui.fontScale or 1
                if ui then
                    ui.fontScale = preset.value
                end
                if T.ApplySettingsFontScale then
                    T.ApplySettingsFontScale(preset.value, oldScale, "preset")
                elseif T.OptionEngine and T.OptionEngine.Rebuild then
                    T.OptionEngine:Rebuild()
                end
            end,
        })
        button:Show()
    end

    return T.Style and T.Style.Scale and T.Style.Scale(36) or 36
end

local function IsMinimapButtonVisible()
    return not (C and C.DB and C.DB.minimap and C.DB.minimap.hide == true)
end

local function SetMinimapButtonVisible(value, engine)
    if engine and engine.SetValue then
        engine:SetValue("minimap.hide", value ~= true)
    end
end

local function ApplyMinimapButtonVisible(value)
    if T.RefreshMinimapButton and T.RefreshMinimapButton() then
        return
    end
    if value == true then
        T.msg(L["STT_ENTRY_RELOAD_REQUIRED"] or "该入口显示设置需要 /reload 后完全生效。")
    end
end

local function ApplyBlizzardOptionsVisible(value)
    if value == true and T.RegisterBlizzardOptionsPanel and T.RegisterBlizzardOptionsPanel() then
        return
    end
    T.msg(L["STT_ENTRY_RELOAD_REQUIRED"] or "该入口显示设置需要 /reload 后完全生效。")
end

T.RegisterOptionModule({
    id = "system",
    category = "system",
    order = 10,
    titleKey = "GUI_NAV_SYSTEM_SETTINGS",
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "STT_ENTRY_SECTION" },
        {
            key = "showMinimapButton",
            type = "check",
            textKey = "STT_SHOW_MINIMAP_BUTTON",
            tooltipKey = "STT_SHOW_MINIMAP_BUTTON_TIP",
            width = 1,
            getter = IsMinimapButtonVisible,
            setter = SetMinimapButtonVisible,
            apply = ApplyMinimapButtonVisible,
            newSince = "260601.32",
            noPush = true,
        },
        {
            key = "showInBlizzardOptions",
            type = "check",
            textKey = "STT_SHOW_BLIZZARD_OPTIONS",
            tooltipKey = "STT_SHOW_BLIZZARD_OPTIONS_TIP",
            dbPath = "system.showInBlizzardOptions",
            default = true,
            width = 1,
            apply = ApplyBlizzardOptionsVisible,
            newSince = "260601.32",
            noPush = true,
        },

        { type = "subtitle", textKey = "GUI_SUBTITLE_SETTINGS_PANEL" },
        {
            key = "fontScale",
            type = "slider",
            textKey = "STT_FONT_SCALE_LABEL",
            tooltipKey = "STT_FONT_SCALE_TOOLTIP",
            dbPath = "semanticTimeline.ui.fontScale",
            default = 1.0,
            min = 0.9,
            max = 1.6,
            step = 0.05,
            width = 1,
            newSince = "260521.33",
            setter = function(value, engine, itemDef)
                local ui = C and C.DB and C.DB.semanticTimeline and C.DB.semanticTimeline.ui
                itemDef.__oldScale = ui and ui.fontScale or 1
                engine:SetValue(itemDef.dbPath, RoundFontScale(value))
            end,
            apply = ApplyFontScale,
            formatFunc = function(value)
                return string.format("%.2fx", tonumber(value) or 1)
            end,
        },
        {
            key = "fontScalePresets",
            type = "custom",
            width = 1,
            height = 36,
            newSince = "260521.33",
            render = RenderFontScalePresets,
        },
        { type = "subtitle", textKey = "GUI_SUBTITLE_DEBUG_TOOLS" },
        {
            key = "openPerfLog",
            type = "button",
            width = 0.5,
            textKey = "GUI_OPEN_PERF_LOG",
            newSince = "260510.17",
            onClick = function()
                if SlashCmdList and SlashCmdList["ST"] then
                    SlashCmdList["ST"]("plog")
                end
            end,
        },
        {
            key = "checkTTS",
            type = "button",
            width = 0.5,
            textKey = "检查TTS",
            onClick = function()
                if SlashCmdList and SlashCmdList["ST"] then
                    SlashCmdList["ST"]("tts")
                end
            end,
        },

        { type = "subtitle", textKey = "OPT_PUSH_SECTION" },
        {
            key = "optionPushAccept",
            type = "check",
            textKey = "OPT_PUSH_ACCEPT",
            tooltipKey = "OPT_PUSH_ACCEPT_TIP",
            dbPath = "raidLead.optionPushAccept",
            default = true,
            width = 1,
            newSince = "260513.24",
            noPush = true,
        },

        { type = "subtitle", textKey = "语言设置" },
        {
            key = "preferredLocale",
            type = "dropdown",
            textKey = "选择界面语言",
            width = 1,
            dbPath = "preferredLocale",
            default = "auto",
            options = {
                { textKey = "自动检测", value = "auto" },
                { textKey = "中文简体", value = "zhCN" },
                { textKey = "中文繁體", value = "zhTW" },
                { textKey = "English", value = "enUS" },
            },
            setter = function(value, engine, itemDef)
                itemDef.__oldLocale = T.GetActiveLocale and T.GetActiveLocale() or GetLocale()
                engine:SetValue(itemDef.dbPath, value)
            end,
            apply = function(value, _, itemDef)
                local oldLocale = itemDef.__oldLocale
                local activeLocale = T.SetLocale and T.SetLocale(value) or value
                if oldLocale and activeLocale and oldLocale ~= activeLocale then
                    StaticPopup_Show("STT_RELOAD_UI")
                end
            end,
        },

        { type = "subtitle", textKey = "配置导入导出" },
        {
            key = "exportRaidPlans",
            type = "button",
            width = 0.5,
            textKey = "导出团本战术板",
            onClick = function()
                if T.ShowExportImportDialog then
                    T.ShowExportImportDialog("export", "raid")
                end
            end,
        },
        {
            key = "exportDungeonPlans",
            type = "button",
            width = 0.5,
            textKey = "导出大秘境战术板",
            onClick = function()
                if T.ShowExportImportDialog then
                    T.ShowExportImportDialog("export", "dungeon")
                end
            end,
        },
        {
            key = "exportSettings",
            type = "button",
            width = 0.5,
            textKey = "导出设置配置",
            onClick = function()
                if T.ShowExportImportDialog then
                    T.ShowExportImportDialog("export", "settings")
                end
            end,
        },
        {
            key = "importData",
            type = "button",
            width = 0.5,
            textKey = "导入配置",
            onClick = function()
                if T.ShowExportImportDialog then
                    T.ShowExportImportDialog("import")
                end
            end,
        },

        { type = "subtitle", textKey = "GUI_SUBTITLE_RESET" },
        {
            key = "reset",
            type = "button",
            width = 0.5,
            textKey = "恢复默认设置",
            onClick = function()
                if T.ShowFactoryResetPopup then
                    T.ShowFactoryResetPopup()
                end
            end,
        },
        {
            key = "reload",
            type = "button",
            width = 0.5,
            textKey = "重载界面",
            onClick = function()
                ReloadUI()
            end,
        },
        }
    end,
})
