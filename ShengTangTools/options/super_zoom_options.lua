local T, C = unpack(select(2, ...))
T.RegisterColdFile("superZoom.enabled", function()

local DB_KEY = "superZoom"

local function FormatZoom(value)
    return string.format("%.1f", tonumber(value) or 0)
end

local function ApplyEnabled()
    if T.SuperZoom then
        T.SuperZoom:ApplyAll()
    end
end

local function ApplyMaxZoom(value)
    if T.SuperZoom and T.SuperZoom:IsEnabled() then
        T.SuperZoom:ApplyMaxZoom(value)
    end
end

local function ResetMaxZoom(engine)
    if not T.SuperZoom then
        return
    end
    T.SuperZoom:ResetMaxZoom()
    if engine and engine.RefreshWidgetValues then
        engine:RefreshWidgetValues()
    end
end

T.RegisterOptionModule({
    id = "superZoom",
    category = "interface",
    order = 25,
    titleKey = "GUI_NAV_SUPER_ZOOM",
    newSince = "260519.8",
    masterToggle = {
        dbPath = DB_KEY .. ".enabled",
        default = false,
        apply = ApplyEnabled,
    },
    itemsFactory = function()
        return {
        {
            key = "hint",
            type = "custom",
            width = 1,
            height = 70,
            render = function(slot, ctx)
                -- GetStringHeight 在 SetText 之后立即调用时，WordWrap 尚未 layout，
                -- 返回的是单行高度，会让 slot 高度严重不足导致下方 slider 叠加。
                -- 直接给一个能容下中英多语 4-5 行的稳定高度。
                local fs = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetPoint("TOPLEFT", slot, "TOPLEFT", 4, -4)
                fs:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -8, 4)
                fs:SetJustifyH("LEFT")
                fs:SetJustifyV("TOP")
                fs:SetWordWrap(true)
                fs:SetTextColor(1, 0.82, 0)
                fs:SetText(ctx.engine:ResolveText("SUPER_ZOOM_SUBTITLE", ""))
                return { height = 70 }
            end,
        },
        {
            key = "maxZoom",
            type = "slider",
            textKey = "SUPER_ZOOM_MAX_ZOOM",
            dbPath = DB_KEY .. ".maxZoom",
            default = 39,
            min = 15,
            max = 39,
            step = 0.5,
            formatFunc = FormatZoom,
            apply = ApplyMaxZoom,
        },
        {
            key = "resetMaxZoom",
            type = "button",
            width = 0.5,
            textKey = "SUPER_ZOOM_RESET_MAX_ZOOM",
            onClick = ResetMaxZoom,
        },
        }
    end,
})

end)
