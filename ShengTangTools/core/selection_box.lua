local T = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local SelectionBox = {}
T.TimelineSelectionBox = SelectionBox

local active
local selected = {}
local selectedByKey = {}
local highlightedChips = {}
local dragFrame
local primaryKey
local primaryCtx

local MIN_DRAG = 4
local RECT_COLOR = { 1.0, 0.78, 0.18, 0.18 }
local BORDER_COLOR = { 1.0, 0.82, 0.22, 0.85 }

local function CursorPoint()
    local scale = UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    return (x or 0) / scale, (y or 0) / scale
end

local function FrameBounds(frame)
    if not (frame and frame.GetLeft) then
        return nil
    end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then
        return nil
    end
    return left, right, top, bottom
end

local function Intersects(aLeft, aRight, aTop, aBottom, bLeft, bRight, bTop, bBottom)
    return aLeft <= bRight and aRight >= bLeft and aBottom <= bTop and aTop >= bBottom
end

local function TokenKey(ctx, chip)
    local item = ctx and (ctx.item or (chip and chip.item)) or (chip and chip.item)
    return table.concat({
        tostring(ctx and ctx.editorTab or ""),
        tostring(ctx and ctx.rowKey or ""),
        tostring(ctx and ctx.sourceLineNum or ""),
        tostring(ctx and ctx.rowID or ""),
        tostring(ctx and ctx.spellID or ""),
        tostring(ctx and ctx.time or ""),
        tostring(item and item.sourceSegmentIndex or ""),
        tostring(item and item.fullText or ""),
    }, "|")
end

local function EnsureDragFrame(owner)
    if dragFrame then
        dragFrame:SetParent(owner.root or UIParent)
        dragFrame:SetFrameStrata((owner.root and owner.root:GetFrameStrata()) or "DIALOG")
        dragFrame:SetFrameLevel(((owner.root and owner.root:GetFrameLevel()) or 1) + 30)
        return dragFrame
    end
    dragFrame = CreateFrame("Frame", nil, owner.root or UIParent, "BackdropTemplate")
    dragFrame.bg = dragFrame:CreateTexture(nil, "BACKGROUND")
    dragFrame.bg:SetAllPoints()
    dragFrame.bg:SetColorTexture(unpack(RECT_COLOR))
    dragFrame.border = {}
    for index = 1, 4 do
        local line = dragFrame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(unpack(BORDER_COLOR))
        dragFrame.border[index] = line
    end
    dragFrame:Hide()
    return dragFrame
end

local function LayoutBorder(frame)
    local top, right, bottom, left = frame.border[1], frame.border[2], frame.border[3], frame.border[4]
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(1)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(1)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(1)
end

local function SetRect(frame, x1, y1, x2, y2)
    local left = math.min(x1, x2)
    local right = math.max(x1, x2)
    local bottom = math.min(y1, y2)
    local top = math.max(y1, y2)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    frame:SetSize(math.max(1, right - left), math.max(1, top - bottom))
    LayoutBorder(frame)
    return left, right, top, bottom
end

local function ClearHighlights()
    for chip in pairs(highlightedChips) do
        if chip.selectionTex then
            chip.selectionTex:Hide()
        end
        if chip.primarySelectionTex then
            chip.primarySelectionTex:Hide()
        end
    end
    wipe(highlightedChips)
end

local function HighlightChip(chip, isPrimary)
    if not chip then
        return
    end
    if not chip.selectionTex then
        chip.selectionTex = chip:CreateTexture(nil, "OVERLAY")
        chip.selectionTex:SetPoint("TOPLEFT", chip, "TOPLEFT", -2, 2)
        chip.selectionTex:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", 2, -2)
        chip.selectionTex:SetColorTexture(1, 0.82, 0.18, 0.32)
    end
    chip.selectionTex:Show()
    if not chip.primarySelectionTex then
        chip.primarySelectionTex = chip:CreateTexture(nil, "OVERLAY")
        chip.primarySelectionTex:SetPoint("TOPLEFT", chip, "TOPLEFT", -4, 4)
        chip.primarySelectionTex:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", 4, -4)
        chip.primarySelectionTex:SetColorTexture(1, 1, 0.78, 0.36)
    end
    chip.primarySelectionTex:SetShown(isPrimary == true)
    highlightedChips[chip] = true
end

local function BuildContext(owner, row, chip)
    local item = chip and chip.item
    if not (owner and row and item) then
        return nil
    end
    local ctx = owner.BuildContextForRowTime and owner:BuildContextForRowTime(row.rowKey, tonumber(item.time) or 0) or nil
    if type(ctx) ~= "table" then
        return nil
    end
    ctx.item = item
    ctx.rowID = item.rowID or ctx.rowID
    ctx.spellID = item.spellID or ctx.spellID
    ctx.dur = item.duration or ctx.dur
    ctx.time = tonumber(item.time) or tonumber(ctx.time) or 0
    ctx.rawTime = ctx.time
    ctx.sourceLineNum = item.lineNum or ctx.sourceLineNum
    ctx.editorTab = item.editorTab or ctx.editorTab
    ctx.hitToken = true
    ctx.chip = chip
    ctx.row = row
    return ctx
end

local function AddSelection(ctx, chip, makePrimary)
    if type(ctx) ~= "table" then
        return false
    end
    local key = TokenKey(ctx, chip)
    if key == "" then
        return false
    end
    ctx.chip = chip or ctx.chip
    if not selectedByKey[key] then
        selectedByKey[key] = ctx
        selected[#selected + 1] = ctx
    else
        selectedByKey[key].chip = chip or selectedByKey[key].chip
    end
    if makePrimary then
        primaryKey = key
        primaryCtx = selectedByKey[key]
    elseif not primaryKey then
        primaryKey = key
        primaryCtx = selectedByKey[key]
    end
    HighlightChip(chip or ctx.chip, primaryKey == key)
    return true
end

local function RemoveSelection(ctx, chip)
    local key = TokenKey(ctx, chip)
    if key == "" or not selectedByKey[key] then
        return false
    end
    local old = selectedByKey[key]
    selectedByKey[key] = nil
    for index = #selected, 1, -1 do
        if selected[index] == old or TokenKey(selected[index], selected[index].chip) == key then
            table.remove(selected, index)
            break
        end
    end
    if old.chip then
        if old.chip.selectionTex then
            old.chip.selectionTex:Hide()
        end
        if old.chip.primarySelectionTex then
            old.chip.primarySelectionTex:Hide()
        end
        highlightedChips[old.chip] = nil
    end
    if primaryKey == key then
        primaryKey = nil
        primaryCtx = nil
        if selected[1] then
            primaryCtx = selected[#selected]
            primaryKey = TokenKey(primaryCtx, primaryCtx.chip)
        end
    end
    return true
end

local function RepaintHighlights(owner)
    ClearHighlights()
    for _, row in ipairs(owner and owner.rowFrames or {}) do
        if row:IsShown() and row.chips then
            for _, chip in ipairs(row.chips) do
                if chip:IsShown() and chip.item then
                    local ctx = BuildContext(owner, row, chip)
                    local key = TokenKey(ctx, chip)
                    if selectedByKey[key] then
                        selectedByKey[key].chip = chip
                        selectedByKey[key].row = row
                        HighlightChip(chip, key == primaryKey)
                    end
                end
            end
        end
    end
end

local function SelectRect(owner, left, right, top, bottom, mode)
    if mode ~= "toggle" then
        wipe(selected)
        wipe(selectedByKey)
        primaryKey = nil
        primaryCtx = nil
        ClearHighlights()
    end
    for _, row in ipairs(owner.rowFrames or {}) do
        if row:IsShown() and row.chips then
            for _, chip in ipairs(row.chips) do
                if chip:IsShown() and chip.item then
                    local cLeft, cRight, cTop, cBottom = FrameBounds(chip)
                    if cLeft and Intersects(left, right, top, bottom, cLeft, cRight, cTop, cBottom) then
                        local ctx = BuildContext(owner, row, chip)
                        if ctx then
                            local key = TokenKey(ctx, chip)
                            if mode == "toggle" and active and active.toggledKeys and not active.toggledKeys[key] then
                                active.toggledKeys[key] = true
                                if SelectionBox.Contains(ctx, chip) then
                                    RemoveSelection(ctx, chip)
                                else
                                    AddSelection(ctx, chip, true)
                                end
                            elseif mode ~= "toggle" then
                                AddSelection(ctx, chip, true)
                            end
                        end
                    end
                end
            end
        end
    end
end

function SelectionBox.Start(owner)
    if not (owner and owner.root) then
        return false
    end
    local x, y = CursorPoint()
    local mode = (SelectionBox.IsToggleModifierDown and SelectionBox.IsToggleModifierDown()) and "toggle" or "replace"
    if mode ~= "toggle" then
        SelectionBox.Clear("new_drag")
    end
    active = {
        owner = owner,
        startX = x,
        startY = y,
        moved = false,
        mode = mode,
        toggledKeys = mode == "toggle" and {} or nil,
    }
    local frame = EnsureDragFrame(owner)
    SetRect(frame, x, y, x + 1, y + 1)
    frame:SetAlpha(0)
    frame:Show()
    frame:SetScript("OnUpdate", function()
        SelectionBox.Update()
    end)
    return true
end

function SelectionBox.Update()
    if not active then
        return
    end
    local owner = active.owner
    local x, y = CursorPoint()
    local moved = math.abs(x - active.startX) >= MIN_DRAG or math.abs(y - active.startY) >= MIN_DRAG
    if not moved and not active.moved then
        return
    end
    active.moved = true
    local frame = EnsureDragFrame(owner)
    local left, right, top, bottom = SetRect(frame, active.startX, active.startY, x, y)
    frame:SetAlpha(1)
    frame:Show()
    SelectRect(owner, left, right, top, bottom, active.mode)
end

function SelectionBox.Finish(reason)
    if not active then
        return false
    end
    local owner = active.owner
    local moved = active.moved
    if dragFrame then
        dragFrame:SetScript("OnUpdate", nil)
        dragFrame:SetAlpha(1)
        dragFrame:Hide()
    end
    active = nil
    if not moved then
        if reason and T.debug then
            T.debug(string.format("[STT_TIMELINE_SELECTION_CLICK] reason=%s", tostring(reason)))
        end
    elseif T.debug then
        T.debug(string.format("[STT_TIMELINE_SELECTION_DONE] count=%d", #selected))
    end
    return moved
end

function SelectionBox.IsActive(owner)
    return active ~= nil and (not owner or active.owner == owner)
end

function SelectionBox.Clear(reason)
    active = nil
    if dragFrame then
        dragFrame:SetScript("OnUpdate", nil)
        dragFrame:SetAlpha(1)
        dragFrame:Hide()
    end
    wipe(selected)
    wipe(selectedByKey)
    primaryKey = nil
    primaryCtx = nil
    ClearHighlights()
end

function SelectionBox.GetTargets(ctx)
    if #selected > 0 then
        return selected
    end
    if type(ctx) == "table" and ctx.hitToken == true then
        return { ctx }
    end
    return {}
end

function SelectionBox.Count()
    return #selected
end

function SelectionBox.IsChipSelected(chip)
    return chip ~= nil and highlightedChips[chip] == true
end

function SelectionBox.IsToggleModifierDown()
    return (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
end

function SelectionBox.Contains(ctx, chip)
    return selectedByKey[TokenKey(ctx, chip)] ~= nil
end

function SelectionBox.SelectOnly(owner, row, chip, ctx, reason)
    if not ctx then
        ctx = BuildContext(owner, row, chip)
    end
    SelectionBox.Clear(reason or "select_only")
    AddSelection(ctx, chip, true)
    RepaintHighlights(owner)
    return ctx
end

function SelectionBox.Toggle(owner, row, chip, ctx, reason)
    if not ctx then
        ctx = BuildContext(owner, row, chip)
    end
    if not ctx then
        return nil
    end
    if SelectionBox.Contains(ctx, chip) then
        RemoveSelection(ctx, chip)
    else
        AddSelection(ctx, chip, true)
    end
    RepaintHighlights(owner)
    if reason and T.debug then
        T.debug(string.format("[STT_TIMELINE_SELECTION_TOGGLE] count=%d reason=%s", #selected, tostring(reason)))
    end
    return ctx
end

function SelectionBox.SelectRow(owner, row, mode, reason)
    if not (owner and row and row.chips) then
        return 0
    end
    if mode ~= "toggle" then
        SelectionBox.Clear(reason or "select_row")
    end
    local count = 0
    for _, chip in ipairs(row.chips) do
        if chip:IsShown() and chip.item then
            local ctx = BuildContext(owner, row, chip)
            if ctx then
                if mode == "toggle" and SelectionBox.Contains(ctx, chip) then
                    RemoveSelection(ctx, chip)
                else
                    AddSelection(ctx, chip, count == 0)
                    count = count + 1
                end
            end
        end
    end
    RepaintHighlights(owner)
    return count
end

function SelectionBox.SelectContexts(owner, contexts, mode, reason)
    if type(contexts) ~= "table" then
        return 0
    end
    if mode ~= "toggle" and mode ~= "append" then
        SelectionBox.Clear(reason or "select_contexts")
    end
    local count = 0
    for _, ctx in ipairs(contexts) do
        if type(ctx) == "table" then
            if mode == "toggle" and SelectionBox.Contains(ctx, ctx.chip) then
                RemoveSelection(ctx, ctx.chip)
            else
                if AddSelection(ctx, ctx.chip, count == 0) then
                    count = count + 1
                end
            end
        end
    end
    RepaintHighlights(owner)
    return count
end

function SelectionBox.SelectAll(owner, reason)
    if not owner then
        return 0
    end
    SelectionBox.Clear(reason or "select_all")
    local count = 0
    for _, row in ipairs(owner.rowFrames or {}) do
        if row:IsShown() and row.chips then
            for _, chip in ipairs(row.chips) do
                if chip:IsShown() and chip.item then
                    local ctx = BuildContext(owner, row, chip)
                    if ctx and AddSelection(ctx, chip, count == 0) then
                        count = count + 1
                    end
                end
            end
        end
    end
    RepaintHighlights(owner)
    return count
end

function SelectionBox.SelectRange(owner, targetRow, targetChip, targetCtx, reason)
    if not (owner and targetRow and targetChip) then
        return nil
    end
    local base = primaryCtx
    if not base then
        return SelectionBox.SelectOnly(owner, targetRow, targetChip, targetCtx, reason or "range_without_primary")
    end
    targetCtx = targetCtx or BuildContext(owner, targetRow, targetChip)
    if not targetCtx then
        return nil
    end

    local rowA = tonumber(base.rowIndex) or 0
    local rowB = tonumber(targetCtx.rowIndex) or rowA
    local minRow, maxRow = math.min(rowA, rowB), math.max(rowA, rowB)
    local timeA = tonumber(base.time) or 0
    local timeB = tonumber(targetCtx.time) or timeA
    local minTime, maxTime = math.min(timeA, timeB), math.max(timeA, timeB)

    SelectionBox.Clear(reason or "range_select")
    local count = 0
    for _, row in ipairs(owner.rowFrames or {}) do
        if row:IsShown() and row.chips then
            for _, chip in ipairs(row.chips) do
                if chip:IsShown() and chip.item then
                    local ctx = BuildContext(owner, row, chip)
                    local rowIndex = tonumber(ctx and ctx.rowIndex) or 0
                    local timeValue = tonumber(ctx and ctx.time) or 0
                    if rowIndex >= minRow and rowIndex <= maxRow and timeValue >= minTime and timeValue <= maxTime then
                        if AddSelection(ctx, chip, count == 0) then
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    AddSelection(targetCtx, targetChip, true)
    RepaintHighlights(owner)
    return targetCtx
end

function SelectionBox.FocusPrimary(ctx)
    if type(ctx) == "table" then
        primaryCtx = ctx
        primaryKey = TokenKey(ctx, ctx.chip)
    end
    return primaryCtx
end

function SelectionBox.GetPrimary()
    return primaryCtx
end

function SelectionBox.Refresh(owner)
    RepaintHighlights(owner)
end

end)
