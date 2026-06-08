local T, C, L = unpack(select(2, ...))

local function RenderAbout(parent, context)
    local width = context.width

    local infoTitle = T.CreateGroupTitle(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", 0, 0 },
        text = L["GUI_ABOUT_TITLE_INFO"] or "插件信息",
        fontSize = 14,
    })
    local versionText = T.CreateLabel(parent, {
        point = { "TOPLEFT", infoTitle, "BOTTOMLEFT", 0, -8 },
        width = width,
        text = string.format("%s: v%s", L["GUI_ABOUT_VERSION"] or "版本", T.Version or "dev"),
    })

    local contactTitle = T.CreateGroupTitle(parent, {
        point = { "TOPLEFT", versionText, "BOTTOMLEFT", 0, -18 },
        text = L["GUI_ABOUT_TITLE_CONTACT"] or "联系方式",
        fontSize = 14,
    })
    local contactText = T.CreateLabel(parent, {
        point = { "TOPLEFT", contactTitle, "BOTTOMLEFT", 0, -8 },
        width = width,
        text = L["GUI_ABOUT_CONTACT_LINES"] or "bilibili：瑟小瑟",
        wordWrap = true,
    })
    local qqLine = CreateFrame("Button", nil, parent)
    qqLine:SetPoint("TOP", contactText, "BOTTOM", 0, -8)
    qqLine:SetSize(width, 24)
    qqLine:RegisterForClicks("LeftButtonUp")
    local qqNumber = T.QQ_GROUP_NUMBER or L["QQ群号"] or "637144370"
    local qqLabel = (L["STT_QQ_CHAT_LINK_LABEL"] or "{%s}"):format(qqNumber)
    local qqLink = T.GetQQGroupLink and T.GetQQGroupLink(qqLabel) or qqNumber
    T.CreateLabel(qqLine, {
        point = { "CENTER", qqLine, "CENTER", 0, 0 },
        width = width,
        justifyH = "CENTER",
        text = string.format(L["GUI_ABOUT_QQ_LINE"] or "QQ群：%s", qqLink),
    })
    qqLine:SetScript("OnClick", function()
        if T.ShowQQGroupPopup then
            T.ShowQQGroupPopup()
        end
    end)

    return 140
end

T.RegisterOptionModule({
    id = "about",
    category = "about",
    order = 10,
    titleKey = "GUI_NAV_ABOUT_PAGE",
    itemsFactory = function()
        return {
        {
            key = "aboutContent",
            type = "custom",
            textKey = "GUI_NAV_ABOUT_PAGE",
            width = 1,
            render = RenderAbout,
            height = 140,
        },
        }
    end,
})
