local T, _, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.editorLoaded", "realtimeBoard.enabled"}, function()

-- 单元格渲染器（SSOT）：解析区与实时战术板共用。
-- 每个调用方通过 T.CreateCellRenderer() 创建独立实例，各自持有 pool 和 activeCells。

local FALLBACK_SPELL_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function TrimText(text)
    if type(text) ~= "string" then
        return ""
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

function T.ShowTimelineItemTooltip(owner, payload, anchor)
    if not (owner and type(payload) == "table" and T.UITooltip and T.UITooltip.ShowTimelineItem) then
        return
    end
    T.UITooltip.ShowTimelineItem(owner, payload, { anchor = anchor or "ANCHOR_RIGHT" })
end

local function ResetCellFrame(cell)
    if not cell then
        return
    end
    cell:Hide()
    cell:ClearAllPoints()
    cell:SetParent(nil)
    cell.rowData = nil
    cell.cellData = nil
    if cell.icon then
        cell.icon:Hide()
        cell.icon:SetTexture(nil)
    end
    if cell.whoLabel then
        cell.whoLabel:SetText("")
    end
    if cell.actionText then
        cell.actionText:SetText("")
    end
    if cell.bg then
        cell.bg:SetColorTexture(0, 0, 0, 0)
    end
    if cell.aliasHint then
        if T.SpellAliasSuggestionMenu and T.SpellAliasSuggestionMenu.CloseIfCell then
            T.SpellAliasSuggestionMenu.CloseIfCell(cell)
        end
        cell.aliasHint:Hide()
    end
end

local function ApplyCellVisualStyle(cell, cellData, cellStyle)
    local clean = cellStyle == "clean"

    if cellData.isError then
        if clean then
            cell.bg:SetColorTexture(0, 0, 0, 0)
        else
            cell.bg:SetColorTexture(0.35, 0.12, 0.12, 0.75)
        end
        cell.whoLabel:SetTextColor(1, 0.6, 0.6, 1)
        cell.actionText:SetTextColor(1, 0.75, 0.75, 1)
        return
    end

    if clean then
        cell.bg:SetColorTexture(0, 0, 0, 0)
    else
        cell.bg:SetColorTexture(0.15, 0.15, 0.2, 0.7)
    end
    cell.whoLabel:SetTextColor(1, 0.82, 0.35, 1)
    cell.actionText:SetTextColor(1, 1, 1, 1)
end

local function GetFontStringWidth(fontString)
    if not fontString or not fontString.GetStringWidth then
        return 0
    end
    return math.ceil(fontString:GetStringWidth() or 0)
end

local function ResolveCleanCellWidth(cell, hasIcon, iconSize, hasWho, hasAction, hasSuggestions)
    local width = 0
    if hasIcon then
        width = width + 2 + iconSize + 2
    else
        width = width + 4
    end
    if hasWho then
        width = width + GetFontStringWidth(cell.whoLabel)
        if hasAction then
            width = width + 2
        end
    end
    if hasAction then
        width = width + GetFontStringWidth(cell.actionText)
    end
    if hasSuggestions then
        width = width + 18
    end
    return math.max(width + 2, 1)
end

local CellRenderer = {}
CellRenderer.__index = CellRenderer

function CellRenderer:AcquireCell(parent)
    local cell = table.remove(self.pool)
    if not cell then
        cell = CreateFrame("Button", nil, parent)
        cell.bg = cell:CreateTexture(nil, "BACKGROUND")
        cell.bg:SetAllPoints()
        cell.bg:SetColorTexture(0, 0, 0, 0)

        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("LEFT", cell, "LEFT", 2, 0)

        cell.whoLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.whoLabel:SetPoint("LEFT", cell.icon, "RIGHT", 2, 0)
        cell.whoLabel:SetJustifyH("LEFT")
        cell.whoLabel:SetTextColor(1, 0.82, 0.35, 1)
        if cell.whoLabel.SetWordWrap then
            cell.whoLabel:SetWordWrap(false)
        end
        if cell.whoLabel.SetNonSpaceWrap then
            cell.whoLabel:SetNonSpaceWrap(false)
        end

        cell.actionText = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.actionText:SetPoint("LEFT", cell.whoLabel, "RIGHT", 2, 0)
        cell.actionText:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
        cell.actionText:SetJustifyH("LEFT")
        cell.actionText:SetTextColor(1, 1, 1, 1)
        if cell.actionText.SetWordWrap then
            cell.actionText:SetWordWrap(false)
        end
        if cell.actionText.SetNonSpaceWrap then
            cell.actionText:SetNonSpaceWrap(false)
        end

        cell:SetScript("OnEnter", function(self)
            local data = self.cellData
            if not data then
                return
            end

            T.ShowTimelineItemTooltip(self, {
                spellID = data.spellID,
                spellIcon = data.spellIcon,
                text = data.actionText,
                fullText = data.fullText,
                who = data.who,
                timeSec = self.rowData and self.rowData.timeSec or nil,
                sourceTab = self.rowData and self.rowData.editorTab or nil,
                tag = data.who,
            })
        end)
        cell:SetScript("OnLeave", function()
            if T.UITooltip then
                T.UITooltip.ScheduleHide()
            else
                GameTooltip:Hide()
            end
        end)

        -- 未转换技能名提示按钮：解析后若该 cell 的 actionText 里含已知技能名，
        -- 右上角亮黄色"!"；点击弹 T.SpellAliasSuggestionMenu 逐条接受/忽略
        cell.aliasHint = CreateFrame("Button", nil, cell)
        cell.aliasHint:SetSize(14, 14)
        cell.aliasHint:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -2)
        cell.aliasHint:SetFrameLevel(cell:GetFrameLevel() + 2)
        cell.aliasHint:Hide()
        cell.aliasHint.tex = cell.aliasHint:CreateTexture(nil, "OVERLAY")
        cell.aliasHint.tex:SetAllPoints()
        local atlasInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestNormal")
        if atlasInfo then
            cell.aliasHint.tex:SetAtlas("QuestNormal")
        else
            cell.aliasHint.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        cell.aliasHint.tex:SetVertexColor(1, 0.82, 0.2, 1)
        cell.aliasHint:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            local hits = parent and parent.cellData and parent.cellData.aliasSuggestions or nil
            if type(hits) ~= "table" or #hits == 0 then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(string.format(L["有 %d 个技能名可改写"] or "有 %d 个技能名可改写", #hits), 1, 0.82, 0.35, true)
            GameTooltip:Show()
        end)
        cell.aliasHint:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        cell.aliasHint:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell.aliasHint:SetScript("OnClick", function(self)
            local parent = self:GetParent()
            if T.debug then
                T.debug("[SpellAlias] iconClicked hits=%d",
                    (parent and parent.cellData and parent.cellData.aliasSuggestions and #parent.cellData.aliasSuggestions) or 0)
            end
            if T.SpellAliasSuggestionMenu and T.SpellAliasSuggestionMenu.Open then
                T.SpellAliasSuggestionMenu.Open(parent)
            end
        end)
    end

    cell:SetParent(parent)
    cell:Show()
    self.active[#self.active + 1] = cell
    return cell
end

function CellRenderer:ReleaseAll()
    for index = #self.active, 1, -1 do
        local cell = self.active[index]
        ResetCellFrame(cell)
        self.pool[#self.pool + 1] = cell
        self.active[index] = nil
    end
end

function CellRenderer:PopulateCell(cell, cellData, uiConfig, xOffset)
    local clean = uiConfig and uiConfig.cellStyle == "clean"
    local spellDisplayMode = uiConfig and uiConfig.spellDisplayMode or "iconText"
    local hasIcon = spellDisplayMode ~= "text" and uiConfig.showIcon ~= false and cellData.spellID ~= nil and cellData.isError ~= true
    local showWho = not uiConfig or uiConfig.showWho ~= false
    local iconSize = hasIcon and uiConfig.iconSize or 0
    local cellHeight = math.max(uiConfig.rowHeight - 2, 18)

    cell:SetSize(uiConfig.cellWidth, cellHeight)
    cell:SetPoint("LEFT", cell:GetParent(), "LEFT", xOffset, 0)
    cell.cellData = cellData

    ApplyCellVisualStyle(cell, cellData, uiConfig and uiConfig.cellStyle)

    cell.icon:ClearAllPoints()
    if hasIcon then
        cell.icon:SetSize(iconSize, iconSize)
        cell.icon:SetPoint("LEFT", cell, "LEFT", 2, 0)
        cell.icon:SetTexture(cellData.spellIcon or FALLBACK_SPELL_ICON)
        cell.icon:Show()
    else
        cell.icon:Hide()
    end

    cell.whoLabel:ClearAllPoints()
    if hasIcon then
        cell.whoLabel:SetPoint("LEFT", cell.icon, "RIGHT", 2, 0)
    else
        cell.whoLabel:SetPoint("LEFT", cell, "LEFT", 4, 0)
    end
    local whoText = showWho and TrimText(cellData.who or "") or ""
    cell.whoLabel:SetText(whoText)

    cell.actionText:ClearAllPoints()
    if whoText ~= "" then
        cell.actionText:SetPoint("LEFT", cell.whoLabel, "RIGHT", 2, 0)
    elseif hasIcon then
        cell.actionText:SetPoint("LEFT", cell.icon, "RIGHT", 2, 0)
    else
        cell.actionText:SetPoint("LEFT", cell, "LEFT", 4, 0)
    end

    local actionText = TrimText((spellDisplayMode == "icon" and cellData.spellHiddenActionText) or cellData.actionText or "")
    local hasWho = whoText ~= ""
    local hasAction = actionText ~= ""

    -- 仅在"团队方案"tab 下显示补全 icon：team+personal 合并解析时，
    -- cell 可能来自 personal plan 的 row，但编辑器只显示当前 tab 的文本，
    -- 无法可靠地把 rowID 映射回正确 plan 的源行（会出现 no_line_for_row /
    -- line_out_of_range 等静默失败）。所以补全功能只服务于主编辑对象——team 方案。
    local activeTab = T.SemanticTimelineGUI and T.SemanticTimelineGUI.GetActiveEditorTab
        and T.SemanticTimelineGUI.GetActiveEditorTab() or "team"
    local hasSuggestions = activeTab == "team"
        and type(cellData.aliasSuggestions) == "table"
        and #cellData.aliasSuggestions > 0
    if cell.aliasHint then
        if hasSuggestions then
            -- cell 用对象池复用，换 parent 时 FrameLevel 会自动重算，aliasHint 的旧 level
            -- 可能比新 cell level 低，导致点击事件被父 cell 吃掉。每次 Populate 都强制重设
            cell.aliasHint:SetFrameLevel(cell:GetFrameLevel() + 10)
            cell.aliasHint:Show()
            cell.actionText:SetPoint("RIGHT", cell.aliasHint, "LEFT", -4, 0)
        else
            cell.aliasHint:Hide()
            if not clean then
                cell.actionText:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
            end
        end
    elseif not clean then
        cell.actionText:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    end

    cell.actionText:SetText(actionText)

    if clean then
        local actualWidth = ResolveCleanCellWidth(cell, hasIcon, iconSize, hasWho, hasAction, hasSuggestions)
        cell:SetWidth(actualWidth)
        return actualWidth
    end

    return uiConfig.cellWidth
end

function CellRenderer:ApplyStyle(cell, cellData)
    ApplyCellVisualStyle(cell, cellData)
end

function T.CreateCellRenderer()
    return setmetatable({ pool = {}, active = {} }, CellRenderer)
end

end)
