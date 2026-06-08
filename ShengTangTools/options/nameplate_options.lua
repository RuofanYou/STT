local T, C, L = unpack(select(2, ...))

local function ApplyNameplate(key)
    return function(value)
        if T.FriendlyNameplate and T.FriendlyNameplate.SetOption then
            T.FriendlyNameplate:SetOption(key, value)
        end
    end
end

T.RegisterOptionModule({
    id = "nameplate",
    category = "interface",
    order = 10,
    titleKey = "GUI_NAV_NAMEPLATE",
    masterToggle = {
        dbPath = "friendlyNameplate.enabled",
        default = false,
        apply = ApplyNameplate("enabled"),
    },
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_SUBTITLE_DISPLAY_OPTIONS" },
        {
            key = "removeServerName",
            type = "check",
            textKey = "去除服务器名",
            width = 0.5,
            dbPath = "friendlyNameplate.removeServerName",
            default = true,
            apply = ApplyNameplate("removeServerName"),
        },
        {
            key = "nameOnly",
            type = "check",
            textKey = "只显示名字",
            width = 0.5,
            dbPath = "friendlyNameplate.nameOnly",
            default = true,
            apply = ApplyNameplate("nameOnly"),
        },
        {
            key = "useClassColor",
            type = "check",
            textKey = "使用职业颜色",
            width = 0.5,
            dbPath = "friendlyNameplate.useClassColor",
            default = true,
            apply = ApplyNameplate("useClassColor"),
        },
        {
            key = "autoInInstance",
            type = "check",
            textKey = "仅副本内生效",
            width = 0.5,
            dbPath = "friendlyNameplate.autoInInstance",
            default = true,
            apply = ApplyNameplate("autoInInstance"),
        },

        { type = "subtitle", textKey = "字体设置" },
        {
            key = "fontSize",
            type = "slider",
            textKey = "字号",
            width = 1,
            dbPath = "friendlyNameplate.fontSize",
            default = 12,
            min = 9,
            max = 20,
            step = 1,
            apply = ApplyNameplate("fontSize"),
        },
        {
            key = "fontOutline",
            type = "dropdown",
            textKey = "名字描边",
            width = 1,
            dbPath = "friendlyNameplate.fontOutline",
            default = "DEFAULT",
            options = {
                { textKey = "描边默认", value = "DEFAULT" },
                { textKey = "描边关闭", value = "NONE" },
                { textKey = "描边开启", value = "OUTLINE" },
            },
            apply = ApplyNameplate("fontOutline"),
        },
        }
    end,
})
