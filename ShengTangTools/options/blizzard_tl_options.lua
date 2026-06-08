local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("blizzardTimeline.enabled", function()

local function ApplyBlizzardTimeline()
    if T.BlizzardTimeline and T.BlizzardTimeline.ApplyViewSettings then
        T.BlizzardTimeline:ApplyViewSettings()
    end
end

local function FormatDecimal(value)
    local number = tonumber(value) or 0
    return string.format("%.2f", number)
end

local function RenderIndicatorMask(parent, context)
    local engine = context.engine
    local itemDef = context.itemDef
    local defs = (T.BlizzardTimeline and T.BlizzardTimeline.IndicatorIconMaskDefs) or {}
    local currentMask = tonumber(engine:GetValue(itemDef.dbPath, itemDef.default)) or 0
    local enabled = {}

    local title = T.CreateGroupTitle(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", 0, 0 },
        text = L[itemDef.textKey] or itemDef.textKey,
        fontSize = 13,
    })
    T.CreateSeparator(parent, {
        point = { "TOPLEFT", title, "BOTTOMLEFT", 0, -5 },
        width = context.width,
    })

    local y = -26
    local left = 0
    local height = 60
    local tracked = {}

    for index, def in ipairs(defs) do
        local row = math.floor((index - 1) / 4)
        local col = (index - 1) % 4
        local bitValue = tonumber(def.value) or 0
        local checkbox = T.CreateCheckbox(parent, {
            point = { "TOPLEFT", parent, "TOPLEFT", left + col * 118, y - row * 24 },
            label = L[def.labelKey] or def.labelKey,
            getter = function()
                local mask = tonumber(engine:GetValue(itemDef.dbPath, itemDef.default)) or 0
                return bit.band(mask, bitValue) ~= 0
            end,
            setter = function(value)
                local mask = tonumber(engine:GetValue(itemDef.dbPath, itemDef.default)) or 0
                if value then
                    mask = bit.bor(mask, bitValue)
                else
                    mask = bit.band(mask, bit.bnot(bitValue))
                end
                engine:ApplyItem(itemDef, mask, context.moduleDef)
            end,
        })
        tracked[#tracked + 1] = checkbox
    end

    return {
        height = height,
        setEnabled = function(state)
            for _, checkbox in ipairs(tracked) do
                if state then
                    checkbox:Enable()
                    if checkbox.label then
                        checkbox.label:SetTextColor(1, 1, 1, 1)
                    end
                else
                    checkbox:Disable()
                    if checkbox.label then
                        checkbox.label:SetTextColor(0.6, 0.6, 0.6, 1)
                    end
                end
            end
        end,
    }
end

T.RegisterOptionModule({
    id = "blizzard_tl",
    category = "tactic",
    order = 20,
    titleKey = "GUI_NAV_BLIZZARD_TL",
    masterToggle = {
        dbPath = "blizzardTimeline.enabled",
        default = false,
        apply = function()
            ApplyBlizzardTimeline()
        end,
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "基础设置" },
        {
            key = "injectOnEncounterStart",
            type = "check",
            textKey = "战斗开始注入",
            width = 0.5,
            dbPath = "blizzardTimeline.injectOnEncounterStart",
            default = true,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "injectInTest",
            type = "check",
            textKey = "测试模式注入",
            width = 0.5,
            dbPath = "blizzardTimeline.injectInTest",
            default = false,
            apply = ApplyBlizzardTimeline,
        },

        { type = "subtitle", textKey = "事件样式" },
        {
            key = "iconSource",
            type = "dropdown",
            textKey = "图标来源",
            width = 0.5,
            dbPath = "blizzardTimeline.iconSource",
            default = "default",
            options = {
                { textKey = "默认", value = "default" },
                { textKey = "法术", value = "spell" },
                { textKey = "映射表", value = "mapping" },
            },
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "severityMode",
            type = "dropdown",
            textKey = "严重度来源",
            width = 0.5,
            dbPath = "blizzardTimeline.severityMode",
            default = "default",
            options = {
                { textKey = "默认", value = "default" },
                { textKey = "文本标记", value = "text-tag" },
                { textKey = "映射表", value = "mapping" },
            },
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "defaultSeverity",
            type = "dropdown",
            textKey = "默认严重度",
            width = 0.5,
            dbPath = "blizzardTimeline.defaultSeverity",
            default = "Medium",
            options = {
                { textKey = "GUI_SEVERITY_LOW", value = "Low" },
                { textKey = "GUI_SEVERITY_MEDIUM", value = "Medium" },
                { textKey = "GUI_SEVERITY_HIGH", value = "High" },
            },
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "maxQueueDuration",
            type = "slider",
            textKey = "排队时长",
            width = 1,
            dbPath = "blizzardTimeline.maxQueueDuration",
            default = 3,
            min = 0,
            max = 10,
            step = 1,
            apply = ApplyBlizzardTimeline,
        },

        {
            key = "indicatorIconMask",
            type = "custom",
            textKey = "指示图标",
            width = 1,
            dbPath = "blizzardTimeline.indicatorIconMask",
            default = 0,
            advanced = true,
            render = RenderIndicatorMask,
            apply = ApplyBlizzardTimeline,
            height = 60,
        },

        { type = "subtitle", textKey = "官方时间轴显示", advanced = true },
        {
            key = "viewTextEnabled",
            type = "check",
            textKey = "显示事件文字",
            width = 0.5,
            dbPath = "blizzardTimeline.viewTextEnabled",
            default = true,
            advanced = true,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "viewCountdownEnabled",
            type = "check",
            textKey = "显示倒计时",
            width = 0.5,
            dbPath = "blizzardTimeline.viewCountdownEnabled",
            default = true,
            advanced = true,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "viewTooltipsEnabled",
            type = "check",
            textKey = "显示Tooltip",
            width = 0.5,
            dbPath = "blizzardTimeline.viewTooltipsEnabled",
            default = true,
            advanced = true,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "viewIconScale",
            type = "slider",
            textKey = "图标缩放",
            width = 0.5,
            dbPath = "blizzardTimeline.viewIconScale",
            default = 1,
            min = 0.7,
            max = 1.5,
            step = 0.05,
            advanced = true,
            formatFunc = FormatDecimal,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "viewBackgroundAlpha",
            type = "slider",
            textKey = "背景透明",
            width = 0.5,
            dbPath = "blizzardTimeline.viewBackgroundAlpha",
            default = 1,
            min = 0.3,
            max = 1.0,
            step = 0.05,
            advanced = true,
            formatFunc = FormatDecimal,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "viewCrossAxisOffset",
            type = "slider",
            textKey = "偏移",
            width = 0.5,
            dbPath = "blizzardTimeline.viewCrossAxisOffset",
            default = 0,
            min = -30,
            max = 30,
            step = 1,
            advanced = true,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "viewCrossAxisExtent",
            type = "slider",
            textKey = "高度",
            width = 0.5,
            dbPath = "blizzardTimeline.viewCrossAxisExtent",
            default = 55,
            min = 30,
            max = 80,
            step = 1,
            advanced = true,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "viewOrientation",
            type = "dropdown",
            textKey = "方向",
            width = 0.5,
            dbPath = "blizzardTimeline.viewOrientation",
            default = "Horizontal",
            advanced = true,
            options = {
                { textKey = "横向", value = "Horizontal" },
                { textKey = "纵向", value = "Vertical" },
            },
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "viewDirection",
            type = "dropdown",
            textKey = "朝向",
            width = 0.5,
            dbPath = "blizzardTimeline.viewDirection",
            default = "Right",
            advanced = true,
            options = {
                { textKey = "向左", value = "Left" },
                { textKey = "向右", value = "Right" },
                { textKey = "向上", value = "Top" },
                { textKey = "向下", value = "Bottom" },
            },
            apply = ApplyBlizzardTimeline,
        },

        { type = "subtitle", textKey = "Pip标记", advanced = true },
        {
            key = "pipIconShown",
            type = "check",
            textKey = "显示Pip图标",
            width = 0.5,
            dbPath = "blizzardTimeline.pipIconShown",
            default = true,
            advanced = true,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "pipTextShown",
            type = "check",
            textKey = "显示Pip数字",
            width = 0.5,
            dbPath = "blizzardTimeline.pipTextShown",
            default = true,
            advanced = true,
            apply = ApplyBlizzardTimeline,
        },
        {
            key = "pipDuration",
            type = "slider",
            textKey = "Pip间隔",
            width = 1,
            dbPath = "blizzardTimeline.pipDuration",
            default = 5,
            min = 1,
            max = 10,
            step = 1,
            advanced = true,
            apply = ApplyBlizzardTimeline,
        },

        { type = "subtitle", textKey = "恢复与调试", advanced = true },
        {
            key = "recoveryEnabled",
            type = "check",
            textKey = "崩溃重载恢复",
            width = 0.5,
            dbPath = "blizzardTimeline.recoveryEnabled",
            default = true,
            advanced = true,
        },
        {
            key = "recoveryAllowIfScriptExists",
            type = "check",
            textKey = "允许脚本事件存在时恢复",
            width = 0.5,
            dbPath = "blizzardTimeline.recoveryAllowIfScriptExists",
            default = false,
            advanced = true,
        },
        {
            key = "debugInjection",
            type = "check",
            textKey = "注入调试日志",
            width = 0.5,
            dbPath = "blizzardTimeline.debugInjection",
            default = false,
            advanced = true,
        },
        {
            key = "debugRecovery",
            type = "check",
            textKey = "恢复调试日志",
            width = 0.5,
            dbPath = "blizzardTimeline.debugRecovery",
            default = false,
            advanced = true,
        },
        {
            key = "recoveryMode",
            type = "dropdown",
            textKey = "恢复策略",
            width = 1,
            dbPath = "blizzardTimeline.recoveryMode",
            default = "safe",
            advanced = true,
            options = {
                { textKey = "安全", value = "safe" },
                { textKey = "强制", value = "force" },
            },
        },
        {
            key = "recoveryMaxLookahead",
            type = "slider",
            textKey = "最大恢复窗口",
            width = 1,
            dbPath = "blizzardTimeline.recoveryMaxLookahead",
            default = 120,
            min = 0,
            max = 120,
            step = 5,
            advanced = true,
        },
        }
    end,
})

end)
