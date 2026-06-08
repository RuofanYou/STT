local T, C, L = unpack(select(2, ...))

local NavTree = {}
T.NavTree = NavTree

local Style = T.Style

local function S(token)
    if Style and Style.Scaled then
        return Style.Scaled(token)
    end
    return Style.BASE and Style.BASE[token] or Style.Nav[token] or 0
end

local function FontSize(token, fallback)
    if Style and Style.ScaledFontSize then
        return Style.ScaledFontSize(token)
    end
    return fallback
end

local function ApplyColor(region, color)
    if region and color then
        region:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function ApplyAtlas(texture, atlas, useAtlasSize)
    if texture and atlas then
        texture:SetAtlas(atlas, useAtlasSize == true)
    end
end

local function ResolveText(textKey, fallback)
    local value = textKey and rawget(L, textKey)
    if value ~= nil then
        return value
    end
    return fallback or textKey or ""
end

local function FormatNavLabel(text, isBeta)
    if isBeta then
        return (text or "") .. " |cFF888888(beta)|r"
    end
    return text or ""
end

local function FormatCategoryLabel(text, isBeta)
    return FormatNavLabel(text, isBeta)
end

local function CreateCategoryHeader(parent, width)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, S("CATEGORY_HEIGHT"))

    local text = T.CreateFontString(frame, {
        template = Style.Font.NAV_CATEGORY,
        point = { "LEFT", frame, "LEFT", 0, 2 },
        size = Style.BASE.NAV_CATEGORY_FONT_SIZE,
        color = Style.Color.KYRIAN_GOLD,
        justifyH = "LEFT",
        wordWrap = false,
    })
    text:SetPoint("RIGHT", frame, "RIGHT", T.NewBadge and -42 or -4, 2)
    if text.SetMaxLines then
        text:SetMaxLines(1)
    end

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas(Style.Nav.CATEGORY_DIVIDER_ATLAS, true)
    divider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -5)
    divider:SetWidth(math.max(1, width - 12))

    local button = CreateFrame("Button", nil, frame)
    button:SetAllPoints(frame)

    local newTag = nil
    if T.NewBadge then
        newTag = T.NewBadge:CreateBadge(frame, {
            anchor = "RIGHT",
            offsetX = -8,
            offsetY = 2,
            width = 28,
            height = 19,
        })
    end

    return {
        frame = frame,
        text = text,
        divider = divider,
        button = button,
        newTag = newTag,
    }
end

local function CreateNavItem(parent, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, S("ITEM_HEIGHT"))

    local bgHighlight = button:CreateTexture(nil, "BACKGROUND")
    bgHighlight:SetPoint("TOPLEFT", button, "TOPLEFT", -10, 0)
    bgHighlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 20, 0)
    bgHighlight:Hide()

    local text = T.CreateFontString(button, {
        template = Style.Font.NAV_ITEM,
        point = { "LEFT", button, "LEFT", S("ITEM_INDENT"), 0 },
        size = Style.BASE.NAV_ITEM_FONT_SIZE,
        color = Style.Color.TEXT_INACTIVE,
        justifyH = "LEFT",
        wordWrap = false,
    })
    text:SetPoint("RIGHT", button, "RIGHT", T.NewBadge and -42 or -4, 0)
    if text.SetMaxLines then
        text:SetMaxLines(1)
    end

    button.text = text
    button.bgHighlight = bgHighlight
    if T.NewBadge then
        button.newTag = T.NewBadge:CreateBadge(button, {
            anchor = "RIGHT",
            offsetX = -6,
            offsetY = 0,
            width = 28,
            height = 19,
        })
    end

    button:SetScript("OnEnter", function(self)
        if not self.isActive then
            ApplyAtlas(self.bgHighlight, Style.Nav.ITEM_HOVER_ATLAS, true)
            self.bgHighlight:Show()
            ApplyColor(self.text, Style.Color.TEXT_HOVER)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self.isActive then
            ApplyAtlas(self.bgHighlight, Style.Nav.ITEM_ACTIVE_ATLAS, true)
            self.bgHighlight:Show()
            ApplyColor(self.text, Style.Color.KYRIAN_GOLD)
        else
            self.bgHighlight:Hide()
            ApplyColor(self.text, Style.Color.TEXT_INACTIVE)
        end
    end)

    return button
end

local function RefreshHeaderMetrics(headerObj, width)
    if not headerObj then
        return
    end
    headerObj.frame:SetSize(width, S("CATEGORY_HEIGHT"))
    headerObj.text:SetFont(STANDARD_TEXT_FONT, FontSize("NAV_CATEGORY_FONT_SIZE", 13), nil)
    if headerObj.divider then
        headerObj.divider:SetWidth(math.max(1, width - 12))
    end
end

local function RefreshItemMetrics(button, width)
    if not button then
        return
    end
    button:SetSize(width, S("ITEM_HEIGHT"))
    if button.text then
        button.text:ClearAllPoints()
        button.text:SetPoint("LEFT", button, "LEFT", S("ITEM_INDENT"), 0)
        button.text:SetPoint("RIGHT", button, "RIGHT", T.NewBadge and -42 or -4, 0)
        button.text:SetFont(STANDARD_TEXT_FONT, FontSize("NAV_ITEM_FONT_SIZE", 12), nil)
    end
end

local function SetItemActive(button, active)
    if not button then
        return
    end
    button.isActive = active == true
    if button.isActive then
        ApplyAtlas(button.bgHighlight, Style.Nav.ITEM_ACTIVE_ATLAS, true)
        button.bgHighlight:Show()
        ApplyColor(button.text, Style.Color.KYRIAN_GOLD)
    else
        button.bgHighlight:Hide()
        ApplyColor(button.text, Style.Color.TEXT_INACTIVE)
    end
end

local function SetCategoryHeaderLabel(headerObj, label)
    if not headerObj then
        return
    end
    headerObj.text:SetText(label or "")
    ApplyColor(headerObj.text, Style.Color.KYRIAN_GOLD)
    if headerObj.divider then
        headerObj.divider:SetWidth(math.max(1, (headerObj.frame:GetWidth() or 1) - 12))
    end
end

function NavTree.Create(parent, width)
    local tree = CreateFrame("Frame", nil, parent)
    tree:SetSize(width, 1)

    tree.width = width
    tree.categoryButtons = {}
    tree.itemButtons = {}
    if C and C.DB then
        if type(C.DB.optionsGuiNavExpanded) ~= "table" then
            C.DB.optionsGuiNavExpanded = {}
        end
        tree.expanded = C.DB.optionsGuiNavExpanded
    else
        tree.expanded = {}
    end

    function tree:SetOnNavigate(callback)
        self.onNavigate = callback
    end

    function tree:SetModules(categories)
        self.categories = categories or {}

        for _, category in ipairs(self.categories) do
            if self.expanded[category.id] == nil then
                self.expanded[category.id] = true
            end
        end

        self:Render()
    end

    function tree:SetActiveModule(moduleId)
        self.activeModuleId = moduleId
        for id, button in pairs(self.itemButtons) do
            SetItemActive(button, id == moduleId)
        end
    end

    function tree:SetTreeWidth(width)
        self.width = math.max(1, tonumber(width) or self.width or 1)
        self:SetWidth(self.width)
        self:Render()
    end

    function tree:RefreshTexts()
        for categoryId, headerObj in pairs(self.categoryButtons) do
            local node
            for _, category in ipairs(self.categories or {}) do
                if category.id == categoryId then
                    node = category
                    break
                end
            end
            if node then
                SetCategoryHeaderLabel(headerObj, FormatCategoryLabel(ResolveText(node.textKey, node.id), node.beta))
                if headerObj.newTag then
                    headerObj.newTag:SetShown(node.hasNew == true)
                end
            end
        end

        for moduleId, button in pairs(self.itemButtons) do
            for _, category in ipairs(self.categories or {}) do
                for _, child in ipairs(category.children or {}) do
                    if child.id == moduleId then
                        button.text:SetText(FormatNavLabel(ResolveText(child.textKey, child.id), child.beta))
                        if button.newTag then
                            button.newTag:SetShown(child.hasNew == true)
                        end
                    end
                end
            end
        end
    end

    function tree:Render()
        local y = 0

        for _, headerObj in pairs(self.categoryButtons) do
            headerObj.frame:Hide()
        end
        for _, button in pairs(self.itemButtons) do
            button:Hide()
        end

        for _, category in ipairs(self.categories or {}) do
            y = y + S("CATEGORY_TOP_PAD")
            local categoryId = category.id
            local headerObj = self.categoryButtons[categoryId]
            if not headerObj then
                headerObj = CreateCategoryHeader(self, self.width)
                headerObj.button:SetScript("OnClick", function()
                    self.expanded[categoryId] = not (self.expanded[categoryId] ~= false)
                    self:Render()
                end)
                self.categoryButtons[categoryId] = headerObj
            end
            RefreshHeaderMetrics(headerObj, self.width)

            local expanded = self.expanded[categoryId] ~= false
            headerObj.frame:ClearAllPoints()
            headerObj.frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
            SetCategoryHeaderLabel(headerObj, FormatCategoryLabel(ResolveText(category.textKey, category.id), category.beta))
            if headerObj.newTag then
                headerObj.newTag:SetShown(category.hasNew == true)
            end
            headerObj.frame:Show()
            y = y + S("CATEGORY_HEIGHT") + S("CATEGORY_BOTTOM_PAD")

            if expanded then
                for _, child in ipairs(category.children or {}) do
                    local childId = child.id
                    local itemButton = self.itemButtons[childId]
                    if not itemButton then
                        itemButton = CreateNavItem(self, self.width)
                        itemButton:SetScript("OnClick", function()
                            if IsShiftKeyDown and IsShiftKeyDown() and T.OptionShare then
                                T.OptionShare:OnNavShiftClick(childId)
                                return
                            end
                            local changed = T.NewBadge and T.NewBadge:MarkSeen(childId) == true
                            if changed and T.OptionEngine and type(T.OptionEngine.Rebuild) == "function" then
                                T.OptionEngine:Rebuild()
                            end
                            if type(self.onNavigate) == "function" then
                                self.onNavigate(childId)
                            end
                        end)
                        itemButton:HookScript("OnEnter", function(owner)
                            if T.OptionShare then
                                T.OptionShare:AttachNavShiftTooltip(owner, childId)
                            end
                        end)
                        itemButton:HookScript("OnLeave", function(owner)
                            if GameTooltip and GameTooltip:GetOwner() == owner then
                                GameTooltip:Hide()
                            end
                        end)
                        self.itemButtons[childId] = itemButton
                    end
                    RefreshItemMetrics(itemButton, self.width)
                    itemButton:ClearAllPoints()
                    itemButton:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
                    itemButton.text:SetText(FormatNavLabel(ResolveText(child.textKey, child.id), child.beta))
                    if itemButton.newTag then
                        itemButton.newTag:SetShown(child.hasNew == true)
                    end
                    SetItemActive(itemButton, self.activeModuleId == childId)
                    itemButton:Show()
                    y = y + S("ITEM_HEIGHT") + S("ITEM_GAP")
                end
            end
        end

        self:SetHeight(math.max(1, y))
    end

    return tree
end
