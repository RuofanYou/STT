local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

-- 单例补全菜单：解析区 cell 点感叹号 icon 时弹出，列出该 cell 内可改写的技能名。
-- 玩家逐条 [接受]，或多条时 [全部接受此行]，或 [忽略] 关闭。
-- 回写源文本走 T.SemanticTimelineGUI 导出的 ApplyAliasReplacement(Batch)。

local Menu = {}
T.SpellAliasSuggestionMenu = Menu

local frame
local currentCell

local function EnsureItem(index)
    local pool = frame.itemPool
    if pool[index] then
        return pool[index]
    end
    local item = {}
    item.root = CreateFrame("Frame", nil, frame)
    item.root:SetHeight(22)
    item.label = item.root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    item.label:SetPoint("LEFT", item.root, "LEFT", 6, 0)
    item.label:SetJustifyH("LEFT")
    if item.label.SetWordWrap then
        item.label:SetWordWrap(false)
    end
    item.acceptBtn = T.CreateButton(item.root, { width = 56, height = 20 })
    item.acceptBtn:SetPoint("RIGHT", item.root, "RIGHT", -4, 0)
    item.acceptBtn:SetText(L["接受"] or "接受")
    item.label:SetPoint("RIGHT", item.acceptBtn, "LEFT", -6, 0)
    pool[index] = item
    return item
end

local function EnsureFrame()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetSize(340, 80)
    frame:Hide()
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        frame:SetBackdropBorderColor(0.55, 0.48, 0.28, 1)
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    frame.title:SetTextColor(0.95, 0.88, 0.6, 1)

    frame.itemPool = {}

    frame.footer = CreateFrame("Frame", nil, frame)
    frame.footer:SetHeight(24)
    frame.footer.dismissBtn = T.CreateButton(frame.footer, { width = 56, height = 20 })
    frame.footer.dismissBtn:SetPoint("RIGHT", frame.footer, "RIGHT", -4, 0)
    frame.footer.dismissBtn:SetText(L["忽略"] or "忽略")
    frame.footer.dismissBtn:SetScript("OnClick", function()
        Menu.Close()
    end)
    frame.footer.allBtn = T.CreateButton(frame.footer, { width = 104, height = 20 })
    frame.footer.allBtn:SetPoint("RIGHT", frame.footer.dismissBtn, "LEFT", -6, 0)
    frame.footer.allBtn:SetText(L["全部接受此行"] or "全部接受此行")

    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            Menu.Close()
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    frame:EnableKeyboard(true)

    return frame
end

function Menu.Close()
    if frame then
        frame:Hide()
        frame:EnableKeyboard(false)
    end
    currentCell = nil
end

function Menu.Open(cell)
    if not cell or not cell.cellData then
        if T and T.debug then T.debug("[SpellAlias:Menu] abort nil_cell_or_data") end
        return
    end
    local hits = cell.cellData.aliasSuggestions
    if type(hits) ~= "table" or #hits == 0 then
        if T and T.debug then T.debug("[SpellAlias:Menu] abort no_hits") end
        return
    end

    EnsureFrame()

    if currentCell == cell and frame:IsShown() then
        Menu.Close()
        if T and T.debug then T.debug("[SpellAlias:Menu] toggled_close") end
        return
    end
    currentCell = cell

    frame.title:SetText(string.format("%s（%d）", L["可改写"] or "可改写", #hits))

    for i = 1, #frame.itemPool do
        frame.itemPool[i].root:Hide()
    end

    local lineY = -28
    for i = 1, #hits do
        local hit = hits[i]
        local item = EnsureItem(i)
        item.root:ClearAllPoints()
        item.root:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, lineY)
        item.root:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, lineY)
        item.label:SetText(string.format(
            "|cffffcc00%s|r  →  |cff8ce0ff{spell:%d}|r",
            hit.word, hit.spellID
        ))
        item.acceptBtn:SetScript("OnClick", function()
            Menu.Accept(hit)
        end)
        item.root:Show()
        lineY = lineY - 24
    end

    frame.footer:ClearAllPoints()
    frame.footer:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, lineY - 4)
    frame.footer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, lineY - 4)
    if #hits > 1 then
        frame.footer.allBtn:Show()
        frame.footer.allBtn:SetScript("OnClick", function()
            Menu.AcceptAll(hits)
        end)
    else
        frame.footer.allBtn:Hide()
    end

    frame:SetHeight(-lineY + 36)

    frame:ClearAllPoints()
    -- 默认锚到 cell 下方；若 cell 到屏幕底部不够 100px 就翻到上方
    local cellBottom = cell:GetBottom()
    local screenHeight = UIParent:GetHeight()
    if cellBottom and cellBottom < 120 then
        frame:SetPoint("BOTTOMLEFT", cell, "TOPLEFT", 0, 4)
    else
        frame:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, -4)
    end

    frame:Show()
    frame:EnableKeyboard(true)
    if T and T.debug then
        T.debug("[SpellAlias:Menu] shown h=%s w=%s strata=%s lvl=%s",
            tostring(math.floor(frame:GetHeight() or 0)),
            tostring(math.floor(frame:GetWidth() or 0)),
            tostring(frame:GetFrameStrata()),
            tostring(frame:GetFrameLevel()))
    end
end

function Menu.Accept(hit)
    local cell = currentCell
    Menu.Close()
    if not cell or not cell.rowData or not hit then
        return
    end
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.ApplyAliasReplacement then
        T.SemanticTimelineGUI.ApplyAliasReplacement(cell.rowData, hit)
    end
end

function Menu.AcceptAll(hits)
    local cell = currentCell
    Menu.Close()
    if not cell or not cell.rowData or type(hits) ~= "table" or #hits == 0 then
        return
    end
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.ApplyAliasReplacementBatch then
        T.SemanticTimelineGUI.ApplyAliasReplacementBatch(cell.rowData, hits)
    end
end

function Menu.CloseIfCell(cell)
    if currentCell == cell then
        Menu.Close()
    end
end

end)
