local T, C, L = unpack(select(2, ...))

local function BuildFrameSkinOptions()
    if T.FrameSkin and T.FrameSkin.GetPresetList then
        return T.FrameSkin:GetPresetList()
    end
    return {
        { text = L["FRAMESKIN_NAME_KYRIAN"] or "Kyrian", value = "kyrian" },
    }
end

T.RegisterOptionModule({
    id = "frame_skin",
    category = "system",
    order = 15,
    titleKey = "GUI_NAV_FRAME_SKIN",
    itemsFactory = function()
        return {
        { type = "subtitle", textKey = "GUI_NAV_FRAME_SKIN" },
        {
            key = "frameSkin",
            type = "dropdown",
            textKey = "FRAMESKIN_DROPDOWN_LABEL",
            width = 1,
            default = "kyrian",
            options = BuildFrameSkinOptions,
            getter = function()
                if T.FrameSkin and T.FrameSkin.GetActive then
                    return T.FrameSkin:GetActive()
                end
                return C.DB.frameSkin or "kyrian"
            end,
            setter = function(value)
                if T.FrameSkin and T.FrameSkin.SetActive then
                    T.FrameSkin:SetActive(value)
                else
                    C.DB.frameSkin = value
                    if type(STT_DB) == "table" then
                        STT_DB.frameSkin = value
                    end
                end
            end,
        },
        {
            key = "frameSkinDesc",
            type = "custom",
            width = 1,
            height = 44,
            searchText = "窗体外观 frame appearance",
            render = function(parent)
                local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                text:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
                text:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
                text:SetJustifyH("LEFT")
                text:SetText(L["FRAMESKIN_DESC"] or "切换 STT 设置主窗的边框、背景与标题条外观。")
                return 44
            end,
        },
        }
    end,
})
