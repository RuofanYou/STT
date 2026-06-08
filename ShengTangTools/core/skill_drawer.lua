local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local Drawer = {}
T.SkillDrawer = Drawer

local PANEL_WIDTH = 348
local HANDLE_WIDTH = 32
local HANDLE_HEIGHT = 36
local HANDLE_OPEN_INSET = 8
local HANDLE_CLOSED_OUTSET = 30
local HANDLE_ATLAS_NORMAL = "common-dropdown-a-button"
local HANDLE_ATLAS_HOVER = "common-dropdown-a-button-hover"
local HANDLE_ATLAS_PRESSED = "common-dropdown-a-button-pressed"
local DRAWER_RIGHT_GAP = 4
local DRAWER_ANIM_DURATION = 0.22
local ROW_HEIGHT = 44
local HEADER_HEIGHT = 22
local MAX_RENDER_ROWS = 160
local DRAG_THRESHOLD = 8
local CLASS_ORDER = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK",
    "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local frame
local currentContext
local currentCategory = { mode = "all", value = "all", label = "全部" }
local categoryLookup
local dragState
local dragFrame
local ClearDragState

local function GetScaledCursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    return (x or 0) / scale, (y or 0) / scale
end

local function ApplySolidBackdrop(target, alpha, borderAlpha)
    if not (target and target.SetBackdrop) then
        return
    end
    target:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    target:SetBackdropColor(0.02, 0.02, 0.025, alpha or 0.82)
    target:SetBackdropBorderColor(0.42, 0.35, 0.22, borderAlpha or 0.55)
end

local function ApplyBackdrop(target, alpha)
    if T.ApplyBackdrop then
        T.ApplyBackdrop(target, {
            alpha = alpha or 0.94,
            borderColor = { 0.9, 0.68, 0.25, 0.85 },
        })
    end
end

local function ApplyAtlas(texture, atlas, direction)
    local atlasInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if not atlasInfo then
        return false
    end
    local textureFile = atlasInfo.file or atlasInfo.filename
    if not (textureFile and atlasInfo.leftTexCoord and atlasInfo.rightTexCoord and atlasInfo.topTexCoord and atlasInfo.bottomTexCoord) then
        return false
    end

    texture:SetTexture(textureFile)
    if direction == "left" then
        texture:SetTexCoord(
            atlasInfo.leftTexCoord, atlasInfo.bottomTexCoord,
            atlasInfo.rightTexCoord, atlasInfo.bottomTexCoord,
            atlasInfo.leftTexCoord, atlasInfo.topTexCoord,
            atlasInfo.rightTexCoord, atlasInfo.topTexCoord
        )
    elseif direction == "right" then
        texture:SetTexCoord(
            atlasInfo.rightTexCoord, atlasInfo.topTexCoord,
            atlasInfo.leftTexCoord, atlasInfo.topTexCoord,
            atlasInfo.rightTexCoord, atlasInfo.bottomTexCoord,
            atlasInfo.leftTexCoord, atlasInfo.bottomTexCoord
        )
    else
        texture:SetTexCoord(atlasInfo.leftTexCoord, atlasInfo.rightTexCoord, atlasInfo.topTexCoord, atlasInfo.bottomTexCoord)
    end
    return true
end

local function RefreshHandleVisual()
    if not (frame and frame.handle and frame.handle.bg) then
        return
    end
    local direction = frame.handleArrowOpen and "right" or "left"
    local visual = frame.handle.isPressed and "pressed" or frame.handle.isHovered and "hover" or "normal"
    local state = direction .. ":" .. visual
    if frame.handle.visualState == state then
        return
    end
    local atlas = visual == "pressed" and HANDLE_ATLAS_PRESSED or visual == "hover" and HANDLE_ATLAS_HOVER or HANDLE_ATLAS_NORMAL
    if ApplyAtlas(frame.handle.bg, atlas, direction) or ApplyAtlas(frame.handle.bg, HANDLE_ATLAS_NORMAL, direction) then
        frame.handle.visualState = state
    end
end

local function PositionHandle(attachedToDrawer)
    if not (frame and frame.handle) then
        return
    end
    local attached = attachedToDrawer and frame:IsShown()
    RefreshHandleVisual()
    frame.handle:ClearAllPoints()
    if attached then
        frame.handle:SetPoint("RIGHT", frame, "LEFT", HANDLE_OPEN_INSET, 0)
    else
        frame.handle:SetPoint("RIGHT", frame.ownerFrame, "LEFT", -HANDLE_CLOSED_OUTSET, 0)
    end
end

local function SetDrawerWidth(width)
    if frame then
        frame:SetWidth(math.max(1, width or PANEL_WIDTH))
        PositionHandle(true)
    end
end

local function StopDrawerAnimation()
    if frame then
        frame:SetScript("OnUpdate", nil)
    end
end

local function EaseDrawer(t)
    t = math.max(0, math.min(1, t or 0))
    return t * t * (3 - 2 * t)
end

local function OpenDrawer()
    if not frame then
        return
    end
    StopDrawerAnimation()
    frame.handleArrowOpen = true
    RefreshHandleVisual()
    frame:Show()
    frame:SetAlpha(0)
    SetDrawerWidth(1)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + (delta or 0)
        local progress = EaseDrawer(elapsed / DRAWER_ANIM_DURATION)
        self:SetAlpha(progress)
        SetDrawerWidth(PANEL_WIDTH * progress)
        if progress >= 1 then
            StopDrawerAnimation()
            self:SetAlpha(1)
            SetDrawerWidth(PANEL_WIDTH)
        end
    end)
end

local function CloseDrawer()
    if not (frame and frame:IsShown()) then
        return
    end
    StopDrawerAnimation()
    frame.handleArrowOpen = false
    RefreshHandleVisual()
    local startProgress = math.max(0, math.min(1, (frame:GetWidth() or PANEL_WIDTH) / PANEL_WIDTH))
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + (delta or 0)
        local eased = EaseDrawer(elapsed / DRAWER_ANIM_DURATION)
        local progress = startProgress * (1 - eased)
        self:SetAlpha(progress)
        SetDrawerWidth(PANEL_WIDTH * progress)
        if eased >= 1 then
            StopDrawerAnimation()
            self:Hide()
            self:SetAlpha(1)
            SetDrawerWidth(PANEL_WIDTH)
        end
    end)
end

local function ClassLabel(classFile)
    if T.SkillPickerLogic and T.SkillPickerLogic.GetClassLabel then
        return T.SkillPickerLogic.GetClassLabel(classFile)
    end
    return tostring(classFile or "")
end

local function SpecLabel(specKey)
    if T.SkillPickerLogic and T.SkillPickerLogic.GetSpecLabel then
        return T.SkillPickerLogic.GetSpecLabel(specKey)
    end
    return tostring(specKey or "")
end

local function EnsureCategoryLookup()
    if not categoryLookup then
        categoryLookup = {}
    end
    return categoryLookup
end

local function RegisterCategory(category)
    if type(category) ~= "table" or type(category.value) ~= "string" then
        return
    end
    EnsureCategoryLookup()[category.value] = category
end

local function BuildCategoryMenu()
    categoryLookup = {}
    local menu = {}
    local all = { mode = "all", value = "all", label = "全部" }
    RegisterCategory(all)
    menu[#menu + 1] = { text = "全部", value = all.value }

    local classItems = {}
    for _, classFile in ipairs(CLASS_ORDER) do
        local classData = T.Data and T.Data.ClassSpells and T.Data.ClassSpells[classFile]
        if type(classData) == "table" then
            local category = {
                mode = "class",
                value = "class:" .. classFile,
                class = classFile,
                label = string.format("职业 / %s", ClassLabel(classFile)),
            }
            RegisterCategory(category)
            classItems[#classItems + 1] = { text = ClassLabel(classFile), value = category.value }
        end
    end
    if #classItems > 0 then
        menu[#menu + 1] = { text = "职业", value = "group:class", items = classItems }
    end

    local bossItems = {}
    local bossIDs = {}
    for bossID in pairs(T.Data and T.Data.BossSpells or {}) do
        bossIDs[#bossIDs + 1] = bossID
    end
    table.sort(bossIDs)
    for _, bossID in ipairs(bossIDs) do
        local boss = T.Data.BossSpells[bossID]
        local category = {
            mode = "boss",
            value = "boss:" .. tostring(bossID),
            bossID = bossID,
            label = string.format("副本 / %s", boss.nameZh or boss.name or tostring(bossID)),
        }
        RegisterCategory(category)
        bossItems[#bossItems + 1] = { text = boss.nameZh or boss.name or tostring(bossID), value = category.value }
    end
    if #bossItems > 0 then
        menu[#menu + 1] = { text = "副本", value = "group:boss", items = bossItems }
    end
    return menu
end

local function SetCategory(category)
    currentCategory = category or EnsureCategoryLookup().all or { mode = "all", value = "all", label = "全部" }
    if frame and frame.categoryBtn then
        frame.categoryBtn:SetSelectedValue(currentCategory.value or "all", currentCategory.label or "全部")
        if frame.categoryBtn.SetValueText then
            frame.categoryBtn:SetValueText(currentCategory.label or "全部")
        end
    end
end

local function SetCategoryByValue(value)
    local category = EnsureCategoryLookup()[tostring(value or "all")] or EnsureCategoryLookup().all
    SetCategory(category)
end

local function GetSortedClassBuckets(classFile)
    local classData = T.Data and T.Data.ClassSpells and T.Data.ClassSpells[classFile]
    local buckets = {}
    if type(classData) ~= "table" then
        return buckets
    end
    if type(classData.GENERAL) == "table" and next(classData.GENERAL) then
        buckets[#buckets + 1] = "GENERAL"
    end
    local rest = {}
    for key, bucket in pairs(classData) do
        if key ~= "GENERAL" and type(bucket) == "table" and next(bucket) then
            rest[#rest + 1] = key
        end
    end
    table.sort(rest, function(a, b)
        return tostring(SpecLabel(a)) < tostring(SpecLabel(b))
    end)
    for _, key in ipairs(rest) do
        buckets[#buckets + 1] = key
    end
    return buckets
end

local function GetClassSectionItems(classFile)
    local out = {}
    if not T.SkillPickerLogic then
        return out
    end
    for _, bucketKey in ipairs(GetSortedClassBuckets(classFile)) do
        local items = T.SkillPickerLogic.GetClassSpells(classFile, bucketKey)
        if #items > 0 then
            out[#out + 1] = {
                isHeader = true,
                label = SpecLabel(bucketKey),
            }
            for _, item in ipairs(items) do
                item.breadcrumb = SpecLabel(bucketKey)
                out[#out + 1] = item
            end
        end
    end
    return out
end

local function GetItems()
    if not T.SkillPickerLogic then
        return {}
    end
    local keyword = frame and frame.searchBox and frame.searchBox:GetText() or ""
    if keyword ~= "" then
        return T.SkillPickerLogic.SearchSpells(keyword)
    end
    if currentCategory.mode == "class" then
        return GetClassSectionItems(currentCategory.class)
    end
    if currentCategory.mode == "boss" then
        return T.SkillPickerLogic.GetBossSpells(currentCategory.bossID)
    end
    return T.SkillPickerLogic.SearchSpells("")
end

local function AcquireCard(index)
    local row = frame.cards[index]
    if row then
        row:Show()
        return row
    end
    row = CreateFrame("Button", nil, frame.scroll.content, "BackdropTemplate")
    row:SetSize(PANEL_WIDTH - 30, ROW_HEIGHT - 4)
    row:RegisterForClicks("LeftButtonUp")
    ApplySolidBackdrop(row, 0.78, 0.45)
    row.edge = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    row.edge:SetWidth(3)
    row.edge:SetColorTexture(0.95, 0.72, 0.18, 0.78)
    row.hover = row:CreateTexture(nil, "BORDER")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 0.82, 0.18, 0.10)
    row.hover:Hide()
    row.pushed = row:CreateTexture(nil, "BORDER", nil, 1)
    row.pushed:SetAllPoints()
    row.pushed:SetColorTexture(1, 0.82, 0.18, 0.18)
    row.pushed:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.path = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.path:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.path:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.path:SetJustifyH("LEFT")
    row.path:SetWordWrap(false)
    row.headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.headerText:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.headerText:SetWidth(86)
    row.headerText:SetJustifyH("LEFT")
    row.headerText:Hide()
    row.headerLine = row:CreateTexture(nil, "ARTWORK")
    row.headerLine:SetPoint("LEFT", row.headerText, "RIGHT", 8, 0)
    row.headerLine:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.headerLine:SetHeight(1)
    row.headerLine:SetColorTexture(1, 0.82, 0.18, 0.35)
    row.headerLine:Hide()
    row:SetScript("OnEnter", function(self)
        if not self.isHeader then
            self.hover:Show()
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(1, 0.82, 0.24, 0.92)
            end
        end
        if self.spellID then
            if T.UITooltip and T.UITooltip.ShowSpellItem then
                T.UITooltip.ShowSpellItem(self, {
                    spellID = self.spellID,
                    spellIcon = self.spellIcon,
                    text = self.spellName,
                    source = self.spellSource,
                }, { anchor = "ANCHOR_RIGHT" })
            end
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        self.pushed:Hide()
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(0.42, 0.35, 0.22, 0.55)
        end
        if T.UITooltip then
            T.UITooltip.ScheduleHide()
        else
            GameTooltip:Hide()
        end
    end)
    row:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not self.isHeader then
            self.pushed:Show()
            Drawer.StartCardPress(self)
        end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        self.pushed:Hide()
        if button == "LeftButton" and not self.isHeader then
            Drawer.FinishCardPress(self)
        end
    end)
    frame.cards[index] = row
    return row
end

function Drawer.Render()
    if not frame then
        return
    end
    for _, row in ipairs(frame.cards) do
        row:Hide()
    end
    local items = GetItems()
    local count = math.min(#items, MAX_RENDER_ROWS)
    local y = 0
    for index = 1, count do
        local item = items[index]
        local row = AcquireCard(index)
        row.isHeader = item.isHeader == true
        row.spellID = row.isHeader and nil or item.spellID
        row.spellIcon = row.isHeader and nil or item.icon
        row.spellName = row.isHeader and nil or item.name
        row.spellSource = row.isHeader and nil or item.breadcrumb
        row.dur = row.isHeader and nil or item.dur
        row:SetEnabled(not row.isHeader)
        if row.SetBackdropColor then
            row:SetBackdropColor(0.02, 0.02, 0.025, row.isHeader and 0 or 0.78)
            row:SetBackdropBorderColor(0.42, 0.35, 0.22, row.isHeader and 0 or 0.55)
        end
        row.edge:SetShown(not row.isHeader)
        row.hover:Hide()
        row.pushed:Hide()
        row.icon:SetShown(not row.isHeader)
        row.name:SetShown(not row.isHeader)
        row.path:SetShown(not row.isHeader)
        row.headerText:SetShown(row.isHeader)
        row.headerLine:SetShown(row.isHeader)
        if row.isHeader then
            row:SetHeight(HEADER_HEIGHT)
            row.headerText:SetText(item.label or "")
        else
            row:SetHeight(ROW_HEIGHT - 4)
            row.icon:SetTexture(item.icon or 134400)
            row.name:SetText(item.name or tostring(item.spellID))
            row.path:SetText(item.breadcrumb or "")
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scroll.content, "TOPLEFT", 4, -y)
        y = y + (row.isHeader and HEADER_HEIGHT or ROW_HEIGHT)
        row:Show()
    end
    frame.empty:SetShown(count == 0)
    frame.limit:SetShown(#items > MAX_RENDER_ROWS)
    frame.scroll:SetContentHeight(math.max(1, y))
end

local function ResolveDropContext()
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.ResolveHorizontalContextAtCursor then
        return T.SemanticTimelineGUI.ResolveHorizontalContextAtCursor()
    end
    return nil
end

local function ResolveClickContext()
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead then
        return T.SemanticTimelineGUI.ResolveHorizontalContextAtPlayhead(currentContext)
    end
    return nil
end

local function ClearDropPreview(reason)
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.ClearHorizontalExternalSkillDragPreview then
        T.SemanticTimelineGUI.ClearHorizontalExternalSkillDragPreview(reason)
    end
end

local function PreviewDropContext(state)
    if not (state and T.SemanticTimelineGUI and T.SemanticTimelineGUI.PreviewHorizontalExternalSkillDrag) then
        return nil
    end
    return T.SemanticTimelineGUI.PreviewHorizontalExternalSkillDrag({
        spellID = state.spellID,
        dur = state.dur,
        icon = state.icon,
        name = state.name,
    })
end

local function InsertCardAtContext(ctx, spellID, dur, source)
    if not (ctx and T.SkillPickerLogic and T.SkillPickerLogic.InsertSkillToken) then
        if T.msg then
            T.msg("请先在水平时间轴选择目标行，或把技能拖到目标行")
        end
        return false
    end
    local ok, reason = T.SkillPickerLogic.InsertSkillToken(ctx, spellID, dur)
    if ok and T.debug then
        T.debug(string.format("[STT_SKILL_DRAWER_%s] spellID=%s time=%.1f row=%s", string.upper(tostring(source or "click")), tostring(spellID), tonumber(ctx.time) or 0, tostring(ctx.who or "")))
    end
    return ok
end

local function HasDragMoved(state)
    if not state then
        return false
    end
    local x, y = GetScaledCursorPosition()
    local dx = (x or 0) - (state.startX or 0)
    local dy = (y or 0) - (state.startY or 0)
    return ((dx * dx) + (dy * dy)) >= (DRAG_THRESHOLD * DRAG_THRESHOLD)
end

local function EnsureDragFrame()
    if dragFrame then
        return dragFrame
    end
    dragFrame = CreateFrame("Frame", "STT_SkillDrawerDragIcon", UIParent)
    dragFrame:SetSize(32, 32)
    dragFrame:SetFrameStrata("TOOLTIP")
    dragFrame:SetFrameLevel(200)
    dragFrame:EnableMouse(false)
    dragFrame:SetAlpha(0)
    dragFrame.icon = dragFrame:CreateTexture(nil, "ARTWORK")
    dragFrame.icon:SetAllPoints()
    dragFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dragFrame:Hide()
    dragFrame:RegisterEvent("GLOBAL_MOUSE_UP")
    dragFrame:SetScript("OnEvent", function(_, _, button)
        if button == "LeftButton" and dragState then
            if dragState.active or HasDragMoved(dragState) then
                Drawer.FinishCardPress(nil, true)
            elseif C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if dragState then
                        ClearDragState()
                    end
                end)
            else
                ClearDragState()
            end
        end
    end)
    dragFrame:SetScript("OnUpdate", function()
        if not dragState then
            dragFrame:Hide()
            return
        end
        local x, y = GetScaledCursorPosition()
        local dx = (x or 0) - (dragState.startX or 0)
        local dy = (y or 0) - (dragState.startY or 0)
        if not dragState.active and ((dx * dx) + (dy * dy)) >= (DRAG_THRESHOLD * DRAG_THRESHOLD) then
            dragState.active = true
            dragFrame.icon:SetTexture(dragState.icon or 134400)
            if dragState.sourceRow then
                dragState.sourceRow:SetAlpha(0.45)
            end
            dragFrame:SetAlpha(0.94)
            if T.debug then
                T.debug(string.format("[STT_SKILL_DRAWER_DRAG_START] spellID=%s", tostring(dragState.spellID or "")))
            end
        end
        if dragState.active then
            local ctx = PreviewDropContext(dragState)
            dragFrame:ClearAllPoints()
            dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x or 0) + (dragState.offsetX or 0), (y or 0) + (dragState.offsetY or 0))
            dragFrame:SetAlpha(ctx and 0 or 0.78)
        end
    end)
    return dragFrame
end

function ClearDragState()
    if dragState and dragState.sourceRow then
        dragState.sourceRow:SetAlpha(1)
    end
    dragState = nil
    if dragFrame then
        dragFrame:Hide()
    end
    ClearDropPreview("clear")
end

function Drawer.StartCardPress(row)
    if not (row and row.spellID) then
        return
    end
    local x, y = GetScaledCursorPosition()
    dragState = {
        spellID = row.spellID,
        dur = row.dur,
        icon = row.icon and row.icon:GetTexture() or 134400,
        name = row.name and row.name:GetText() or nil,
        startX = x or 0,
        startY = y or 0,
        offsetX = 0,
        offsetY = 0,
        sourceRow = row,
        active = false,
    }
    local controller = EnsureDragFrame()
    controller.icon:SetTexture(dragState.icon or 134400)
    controller:SetAlpha(0)
    controller:ClearAllPoints()
    controller:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x or 0) + (dragState.offsetX or 0), (y or 0) + (dragState.offsetY or 0))
    controller:Show()
end

function Drawer.FinishCardPress(row, fromGlobal)
    if not dragState then
        return
    end
    local state = dragState
    local movedEnough = HasDragMoved(state)
    if state.active or movedEnough then
        local ctx = ResolveDropContext()
        if ctx then
            InsertCardAtContext(ctx, state.spellID, state.dur, "drop")
        elseif T.msg then
            T.msg("拖到水平时间轴目标行后松开")
            if T.debug then
                T.debug(string.format("[STT_SKILL_DRAWER_CANCEL] reason=outside spellID=%s", tostring(state.spellID or "")))
            end
        end
        ClearDragState()
        return
    end

    ClearDragState()
    if fromGlobal then
        return
    end
    InsertCardAtContext(ResolveClickContext(), row and row.spellID or state.spellID, row and row.dur or state.dur, "click")
end

function Drawer.Init(parent)
    if frame or not parent then
        return
    end
    frame = CreateFrame("Frame", "STT_SkillDrawer", parent, "BackdropTemplate")
    frame:SetWidth(PANEL_WIDTH)
    frame:SetPoint("TOPRIGHT", parent, "TOPLEFT", -DRAWER_RIGHT_GAP, -10)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", -DRAWER_RIGHT_GAP, 10)
    frame:SetFrameStrata(parent:GetFrameStrata())
    frame:SetFrameLevel((parent:GetFrameLevel() or 0) + 30)
    ApplyBackdrop(frame)
    frame.ownerFrame = parent
    frame.cards = {}
    frame:Hide()
    BuildCategoryMenu()
    frame:HookScript("OnShow", function()
        PositionHandle(true)
    end)
    frame:HookScript("OnHide", function()
        PositionHandle(false)
        ClearDragState()
        if T.HideSelectorMenu then
            T.HideSelectorMenu()
        end
    end)

    frame.handle = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame.handle:SetSize(HANDLE_WIDTH, HANDLE_HEIGHT)
    frame.handle:SetFrameLevel(math.max(0, (parent:GetFrameLevel() or 1) - 1))
    frame.handle.bg = frame.handle:CreateTexture(nil, "BACKGROUND")
    frame.handle.bg:SetAllPoints()
    frame.handleArrowOpen = false
    if not ApplyAtlas(frame.handle.bg, HANDLE_ATLAS_NORMAL, "left") then
        ApplySolidBackdrop(frame.handle, 0.88, 0.75)
    end
    frame.handle:SetScript("OnEnter", function(self)
        self.isHovered = true
        RefreshHandleVisual()
        if not self.bg and self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(1, 0.82, 0.25, 1)
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("技能")
        GameTooltip:Show()
    end)
    frame.handle:SetScript("OnLeave", function(self)
        self.isHovered = false
        self.isPressed = false
        RefreshHandleVisual()
        if not self.bg and self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(0.9, 0.68, 0.25, 0.85)
        end
        GameTooltip:Hide()
    end)
    frame.handle:SetScript("OnMouseDown", function(self)
        self.isPressed = true
        RefreshHandleVisual()
    end)
    frame.handle:SetScript("OnMouseUp", function(self)
        self.isPressed = false
        RefreshHandleVisual()
    end)
    frame.handle:SetScript("OnClick", function()
        if frame:IsShown() then
            CloseDrawer()
        else
            currentContext = currentContext or nil
            SetCategory(currentCategory or { mode = "all", label = "全部" })
            Drawer.Render()
            OpenDrawer()
        end
    end)
    PositionHandle(false)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    frame.title:SetText("添加技能")

    frame.searchBox = T.CreateEditBox(frame, {
        width = PANEL_WIDTH - 24,
        height = 24,
        point = { "TOPLEFT", frame, "TOPLEFT", 12, -34 },
        placeholder = "搜索技能 / spellID / 拼音",
        autoFocus = false,
    })
    frame.searchBox:SetScript("OnTextChanged", function()
        Drawer.Render()
    end)

    frame.categoryBtn = T.CreateSelectorButton(frame, {
        label = "分类",
        labelWidth = 34,
        selectedValue = "all",
        valueText = "全部",
        menuBuilder = BuildCategoryMenu,
        ownerFrame = frame,
        width = PANEL_WIDTH - 24,
        height = 24,
        point = { "TOPLEFT", frame.searchBox, "BOTTOMLEFT", 0, -8 },
        onSelect = function(value)
            SetCategoryByValue(value)
            Drawer.Render()
        end,
    })

    frame.scroll = T.CreateScrollPanel(frame, {
        point1 = { "TOPLEFT", frame.categoryBtn, "BOTTOMLEFT", 0, -8 },
        point2 = { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 30 },
        backdrop = true,
        backdropAlpha = 0.12,
    })

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("CENTER", frame.scroll.scroll, "CENTER", 0, 0)
    frame.empty:SetText("没有匹配技能")
    frame.empty:Hide()

    frame.limit = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.limit:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
    frame.limit:SetText("结果较多，继续输入可缩小范围")
    frame.limit:Hide()

    SetCategoryByValue("all")
end

function Drawer.OpenWithContext(ctx)
    if not frame then
        return
    end
    currentContext = ctx
    BuildCategoryMenu()
    local categoryValue = "all"
    if ctx and ctx.kind == "player" and ctx.class then
        categoryValue = "class:" .. tostring(ctx.class)
    elseif ctx and ctx.kind == "boss" and ctx.bossID then
        categoryValue = "boss:" .. tostring(tonumber(ctx.bossID) or ctx.bossID)
    end
    SetCategoryByValue(categoryValue)
    if frame.searchBox then
        frame.searchBox:SetText("")
    end
    Drawer.Render()
    OpenDrawer()
    if T.debug then
        T.debug(string.format("[STT_SKILL_DRAWER_OPEN] kind=%s class=%s bossID=%s", tostring(ctx and ctx.kind or "generic"), tostring(ctx and ctx.class or ""), tostring(ctx and ctx.bossID or "")))
    end
end

function Drawer.IsOpen()
    return frame and frame:IsShown()
end

function Drawer.SetContext(ctx)
    currentContext = ctx
    if T.debug then
        T.debug(string.format("[STT_SKILL_DRAWER_CONTEXT] kind=%s class=%s bossID=%s", tostring(ctx and ctx.kind or "generic"), tostring(ctx and ctx.class or ""), tostring(ctx and ctx.bossID or "")))
    end
end

end)
