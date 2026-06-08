local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("visualBoard.editorLoaded", function()

-- 视觉战术板组件抽屉（契约 §3 panels-owner、§6.5）。
-- 复用 skill_drawer 的“边框句柄开抽屉 + GetScaledCursorPosition 拖拽到目标”交互骨架，
-- 但本抽屉自持拖拽态（self.dragState），不污染 T.SkillDrawer 的全局 dragState。
-- 内容 = 固定组件（person/text/shape/marker/icon）+ 按当前激活方案 [人员] 段自动生成的 person 预设。
-- 落到画布释放 → 经 callbacks.OnDropComponent(kind, presetData, screenX, screenY) 回调，
-- editor 据此 ScreenToBoard 换算落点逻辑坐标后调 Data:AddElementAt / Data:AddPersonAt 建元素。
local Drawer = {}
T.VisualBoardComponentDrawer = Drawer

local PANEL_WIDTH = 220
local HANDLE_WIDTH = 32
local HANDLE_HEIGHT = 36
local HANDLE_OPEN_INSET = 8
local HANDLE_CLOSED_OUTSET = 30
local HANDLE_ATLAS_NORMAL = "common-dropdown-a-button"
local HANDLE_ATLAS_HOVER = "common-dropdown-a-button-hover"
local HANDLE_ATLAS_PRESSED = "common-dropdown-a-button-pressed"
local DRAWER_RIGHT_GAP = 4
local DRAWER_ANIM_DURATION = 0.22
local ROW_HEIGHT = 40
local HEADER_HEIGHT = 22
local DRAG_THRESHOLD = 8
local DEFAULT_ICON_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"
-- 人员预设的中性兜底图标：当 slotName 既无作者手填 [人员图标]、也无黑话可推（连职业都认不出）时用此通用人员图标，
-- 而非刺眼的问号；与固定 person 组件同一张暴雪人员图标，不硬编码 .tga、不臆造 specID。
local PERSON_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_GroupLooking"

-- 固定组件。拖出后 editor 按 kind 建对应默认元素。
local FIXED_COMPONENTS = {
    { kind = "person", icon = PERSON_FALLBACK_ICON,
      labelKey = "VISUAL_BOARD_DRAWER_PERSON", labelFallback = "人员" },
    { kind = "icon", icon = "Interface\\Icons\\INV_Misc_QuestionMark",
      labelKey = "VISUAL_BOARD_DRAWER_ICON", labelFallback = "图标" },
    { kind = "text", icon = "Interface\\Icons\\INV_Inscription_ScrollOfWisdom_01",
      labelKey = "VISUAL_BOARD_DRAWER_TEXT", labelFallback = "文字" },
    { kind = "shape", icon = "Interface\\Icons\\INV_Misc_Gem_Variety_02",
      labelKey = "VISUAL_BOARD_DRAWER_SHAPE", labelFallback = "形状" },
    { kind = "marker", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
      labelKey = "VISUAL_BOARD_DRAWER_MARKER", labelFallback = "团队标记" },
}

local function Text(key, fallback)
    local value = L and L[key]
    if type(value) == "string" and value ~= "" then
        return value
    end
    return fallback
end

local function GetScaledCursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    return (x or 0) / scale, (y or 0) / scale
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

local function ApplyBackdrop(target)
    if T.ApplyBackdrop then
        T.ApplyBackdrop(target, {
            alpha = 0.94,
            borderColor = { 0.9, 0.68, 0.25, 0.85 },
        })
    end
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

-- 取当前激活方案的 [人员] 映射（契约 §6.5：复用 Note:GetActivePlan → Template.PreprocessText 单一权威入口）。
-- 返回 info（含 info.slots / info.slotVisualSpecs）；无激活方案 / 无 content 返回 nil。
local function ResolveActiveInfo()
    local Note = T.Note
    local plan = Note and Note.GetActivePlan and Note:GetActivePlan() or nil
    local content = type(plan) == "table" and tostring(plan.content or "") or ""
    if content == "" then
        return nil
    end
    local Template = T.STNTemplate
    if not (Template and Template.PreprocessText) then
        return nil
    end
    return Template.PreprocessText(content)
end

-- 单条 vs 空格并集组判定（契约 §6.5）：
-- 只为“单条映射”生成预设——即 info.slots[slot] 的 value 经 Template.ResolveSlotAtRuntime 解析为单人（返回 string）。
-- 空格分隔的并集组（如 种子=咕咕2 SS1）ResolveSlotAtRuntime 返回 table → 不生成预设。
-- 复用 ResolveSlotAtRuntime 单一权威，不在本文件重造空格/并集解析。
local function BuildPersonPresets(info)
    local presets = {}
    if type(info) ~= "table" or type(info.slots) ~= "table" then
        return presets
    end
    local Template = T.STNTemplate
    for slotName, slotValue in pairs(info.slots) do
        if type(slotName) == "string" and slotName ~= "" then
            local isUnion = false
            if Template and Template.ResolveSlotAtRuntime and type(slotValue) == "string" and slotValue ~= "" then
                isUnion = type(Template.ResolveSlotAtRuntime(slotValue)) == "table"
            end
            if not isUnion then
                -- 预设图标：经 data 单一权威 ResolvePersonDefaultIcon（按 slotName→手填/黑话 specID→spec 图标，或职业图标兜底）；
                -- 仍解析不到（连职业都认不出）落中性人员图标而非问号。本文件不重造 specID→icon 映射。
                local icon = PERSON_FALLBACK_ICON
                if T.VisualBoardData and T.VisualBoardData.ResolvePersonDefaultIcon then
                    local resolved = T.VisualBoardData:ResolvePersonDefaultIcon({ type = "person", params = { slotName = slotName } }, info)
                    if resolved then
                        icon = resolved
                    end
                end
                presets[#presets + 1] = {
                    slotName = slotName,
                    icon = icon,
                    label = slotName,
                }
            elseif T.debug then
                T.debug("[STT_VBOARD_DRAWER] skipUnionSlot slot='" .. slotName .. "' value='" .. tostring(slotValue) .. "'")
            end
        end
    end
    table.sort(presets, function(a, b)
        return tostring(a.slotName) < tostring(b.slotName)
    end)
    return presets
end

-- ============================================================
-- 抽屉实例：自持帧、句柄、卡片池与拖拽态（self.dragState），与 skill_drawer 全局态隔离。
-- ============================================================

local function RefreshHandleVisual(self)
    local handle = self.frame and self.frame.handle
    if not (handle and handle.bg) then
        return
    end
    -- 照抄 skill_drawer：收起时箭头指向左（=面板弹出方向，“点我展开”），展开时反向指右。
    -- 用显式 handleArrowOpen 标志，不依赖动画期间已为 true 的 IsShown。
    local direction = self.frame.handleArrowOpen and "right" or "left"
    local visual = handle.isPressed and "pressed" or handle.isHovered and "hover" or "normal"
    local state = direction .. ":" .. visual
    if handle.visualState == state then
        return
    end
    local atlas = visual == "pressed" and HANDLE_ATLAS_PRESSED or visual == "hover" and HANDLE_ATLAS_HOVER or HANDLE_ATLAS_NORMAL
    if ApplyAtlas(handle.bg, atlas, direction) or ApplyAtlas(handle.bg, HANDLE_ATLAS_NORMAL, direction) then
        handle.visualState = state
    end
end

local function PositionHandle(self, attachedToDrawer)
    local frame = self.frame
    if not (frame and frame.handle) then
        return
    end
    local attached = attachedToDrawer and frame:IsShown()
    RefreshHandleVisual(self)
    frame.handle:ClearAllPoints()
    if attached then
        frame.handle:SetPoint("RIGHT", frame, "LEFT", HANDLE_OPEN_INSET, 0)
    else
        frame.handle:SetPoint("RIGHT", frame.ownerFrame, "LEFT", -HANDLE_CLOSED_OUTSET, 0)
    end
end

local function SetDrawerWidth(self, width)
    if self.frame then
        self.frame:SetWidth(math.max(1, width or PANEL_WIDTH))
        PositionHandle(self, true)
    end
end

local function StopAnim(self)
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
    end
end

local function Ease(t)
    t = math.max(0, math.min(1, t or 0))
    return t * t * (3 - 2 * t)
end

local function DoOpen(self)
    local frame = self.frame
    if not frame then
        return
    end
    StopAnim(self)
    frame.handleArrowOpen = true
    RefreshHandleVisual(self)
    self:Refresh()
    frame:Show()
    frame:SetAlpha(0)
    SetDrawerWidth(self, 1)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(f, delta)
        elapsed = elapsed + (delta or 0)
        local progress = Ease(elapsed / DRAWER_ANIM_DURATION)
        f:SetAlpha(progress)
        SetDrawerWidth(self, PANEL_WIDTH * progress)
        if progress >= 1 then
            StopAnim(self)
            f:SetAlpha(1)
            SetDrawerWidth(self, PANEL_WIDTH)
        end
    end)
end

local function DoClose(self)
    local frame = self.frame
    if not (frame and frame:IsShown()) then
        return
    end
    StopAnim(self)
    frame.handleArrowOpen = false
    RefreshHandleVisual(self)
    local startProgress = math.max(0, math.min(1, (frame:GetWidth() or PANEL_WIDTH) / PANEL_WIDTH))
    local elapsed = 0
    frame:SetScript("OnUpdate", function(f, delta)
        elapsed = elapsed + (delta or 0)
        local eased = Ease(elapsed / DRAWER_ANIM_DURATION)
        local progress = startProgress * (1 - eased)
        f:SetAlpha(progress)
        SetDrawerWidth(self, PANEL_WIDTH * progress)
        if eased >= 1 then
            StopAnim(self)
            f:Hide()
            f:SetAlpha(1)
            SetDrawerWidth(self, PANEL_WIDTH)
            RefreshHandleVisual(self)
        end
    end)
end

local function ClearDragState(self)
    local state = self.dragState
    if state and state.sourceRow then
        state.sourceRow:SetAlpha(1)
    end
    self.dragState = nil
    if self.dragFrame then
        self.dragFrame:Hide()
    end
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

-- 拖拽落地：移动够阈值则回调 editor（OnDropComponent 算落点逻辑坐标并建元素），否则视为点击（不建元素，仅清理）。
local function FinishDrag(self, fromGlobal)
    local state = self.dragState
    if not state then
        return
    end
    local moved = state.active or HasDragMoved(state)
    if moved then
        local x, y = GetScaledCursorPosition()
        if type(self.callbacks.OnDropComponent) == "function" then
            self.callbacks.OnDropComponent(state.kind, state.presetData, x, y)
        end
        if T.debug then
            T.debug(string.format("[STT_VBOARD_DRAWER] drop kind=%s slot=%s x=%.1f y=%.1f", tostring(state.kind), tostring(state.presetData and state.presetData.slotName or ""), x, y))
        end
    end
    ClearDragState(self)
end

local function EnsureDragFrame(self)
    if self.dragFrame then
        return self.dragFrame
    end
    local controller = CreateFrame("Frame", nil, UIParent)
    controller:SetSize(32, 32)
    controller:SetFrameStrata("TOOLTIP")
    controller:SetFrameLevel(220)
    controller:EnableMouse(false)
    controller:SetAlpha(0)
    controller.icon = controller:CreateTexture(nil, "ARTWORK")
    controller.icon:SetAllPoints()
    controller.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    controller:Hide()
    controller:RegisterEvent("GLOBAL_MOUSE_UP")
    controller:SetScript("OnEvent", function(_, _, button)
        if button == "LeftButton" and self.dragState then
            FinishDrag(self, true)
        end
    end)
    controller:SetScript("OnUpdate", function()
        local state = self.dragState
        if not state then
            controller:Hide()
            return
        end
        local x, y = GetScaledCursorPosition()
        if not state.active and HasDragMoved(state) then
            state.active = true
            controller.icon:SetTexture(state.icon or DEFAULT_ICON_TEXTURE)
            if state.sourceRow then
                state.sourceRow:SetAlpha(0.45)
            end
            controller:SetAlpha(0.94)
        end
        if state.active then
            controller:ClearAllPoints()
            controller:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        end
    end)
    self.dragFrame = controller
    return controller
end

local function StartDrag(self, row)
    if not (row and row.dragKind) then
        return
    end
    local x, y = GetScaledCursorPosition()
    self.dragState = {
        kind = row.dragKind,
        presetData = row.presetData,
        icon = row.icon and row.icon:GetTexture() or DEFAULT_ICON_TEXTURE,
        startX = x or 0,
        startY = y or 0,
        sourceRow = row,
        active = false,
    }
    local controller = EnsureDragFrame(self)
    controller.icon:SetTexture(self.dragState.icon or DEFAULT_ICON_TEXTURE)
    controller:SetAlpha(0)
    controller:ClearAllPoints()
    controller:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x or 0, y or 0)
    controller:Show()
end

local function AcquireRow(self, index)
    local row = self.frame.rows[index]
    if row then
        row:Show()
        return row
    end
    row = CreateFrame("Button", nil, self.frame.scroll.content, "BackdropTemplate")
    row:SetSize(PANEL_WIDTH - 30, ROW_HEIGHT - 4)
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
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.headerText:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.headerText:SetJustifyH("LEFT")
    row.headerText:Hide()
    row.headerLine = row:CreateTexture(nil, "ARTWORK")
    row.headerLine:SetPoint("LEFT", row.headerText, "RIGHT", 8, 0)
    row.headerLine:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.headerLine:SetHeight(1)
    row.headerLine:SetColorTexture(1, 0.82, 0.18, 0.35)
    row.headerLine:Hide()
    row:SetScript("OnEnter", function(r)
        if not r.isHeader then
            r.hover:Show()
            if r.SetBackdropBorderColor then
                r:SetBackdropBorderColor(1, 0.82, 0.24, 0.92)
            end
        end
    end)
    row:SetScript("OnLeave", function(r)
        r.hover:Hide()
        if r.SetBackdropBorderColor then
            r:SetBackdropBorderColor(0.42, 0.35, 0.22, 0.55)
        end
    end)
    row:SetScript("OnMouseDown", function(r, button)
        if button == "LeftButton" and not r.isHeader then
            StartDrag(self, r)
        end
    end)
    row:SetScript("OnMouseUp", function(r, button)
        if button == "LeftButton" and not r.isHeader then
            FinishDrag(self, false)
        end
    end)
    self.frame.rows[index] = row
    return row
end

-- 行模型：固定四组件区 + 分隔 header + 人员预设区（或空态提示行）。
local function BuildRows(self)
    local rows = {}
    rows[#rows + 1] = { isHeader = true, label = Text("VISUAL_BOARD_DRAWER_COMPONENTS", "组件") }
    for _, comp in ipairs(FIXED_COMPONENTS) do
        rows[#rows + 1] = {
            kind = comp.kind,
            icon = comp.icon,
            label = Text(comp.labelKey, comp.labelFallback),
        }
    end

    rows[#rows + 1] = { isHeader = true, label = Text("VISUAL_BOARD_DRAWER_PERSON_PRESETS", "人员预设") }
    local info = ResolveActiveInfo()
    local presets = BuildPersonPresets(info)
    if #presets == 0 then
        -- 契约 §6.5：无激活方案 / 方案无 [人员] 段 → 空态提示（不报错、不留空白歧义）。
        rows[#rows + 1] = { isEmpty = true, label = Text("VISUAL_BOARD_DRAWER_NO_PLAN", "请先在战术方案里配置[人员]") }
    else
        for _, preset in ipairs(presets) do
            rows[#rows + 1] = {
                kind = "person",
                icon = preset.icon,
                label = preset.label,
                presetData = { slotName = preset.slotName },
            }
        end
    end
    return rows
end

function Drawer:Refresh()
    local frame = self.frame
    if not frame then
        return
    end
    for _, row in ipairs(frame.rows) do
        row:Hide()
    end
    local model = BuildRows(self)
    local y = 0
    for index, item in ipairs(model) do
        local row = AcquireRow(self, index)
        row.isHeader = item.isHeader == true
        row.isEmpty = item.isEmpty == true
        row.dragKind = (not row.isHeader and not row.isEmpty) and item.kind or nil
        row.presetData = item.presetData
        row:SetEnabled(row.dragKind ~= nil)
        local plain = row.isHeader or row.isEmpty
        if row.SetBackdropColor then
            row:SetBackdropColor(0.02, 0.02, 0.025, plain and 0 or 0.78)
            row:SetBackdropBorderColor(0.42, 0.35, 0.22, plain and 0 or 0.55)
        end
        row.edge:SetShown(not plain)
        row.hover:Hide()
        row.icon:SetShown(not plain)
        row.name:SetShown(not row.isHeader)
        row.headerText:SetShown(row.isHeader)
        row.headerLine:SetShown(row.isHeader)
        if row.isHeader then
            row:SetHeight(HEADER_HEIGHT)
            row.headerText:SetText(item.label or "")
        elseif row.isEmpty then
            row:SetHeight(ROW_HEIGHT - 4)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row, "LEFT", 10, 0)
            row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.name:SetText(item.label or "")
            row.name:SetWordWrap(true)
        else
            row:SetHeight(ROW_HEIGHT - 4)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.name:SetWordWrap(false)
            row.icon:SetTexture(item.icon or DEFAULT_ICON_TEXTURE)
            row.name:SetText(item.label or "")
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scroll.content, "TOPLEFT", 4, -y)
        y = y + (row.isHeader and HEADER_HEIGHT or ROW_HEIGHT)
        row:Show()
    end
    frame.scroll:SetContentHeight(math.max(1, y))
end

function Drawer:Create(parent)
    if self.frame or not parent then
        return self.frame
    end
    self.callbacks = self.callbacks or {}
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self.frame = frame
    frame:SetWidth(PANEL_WIDTH)
    -- 照抄 skill_drawer：面板【右边】贴 owner 窗口【左边】外侧（TOPRIGHT→TOPLEFT），向左延展到窗口外，不覆盖窗口内部（图层/画布）。
    frame:SetPoint("TOPRIGHT", parent, "TOPLEFT", -DRAWER_RIGHT_GAP, -10)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", -DRAWER_RIGHT_GAP, 10)
    frame:SetFrameStrata(parent:GetFrameStrata())
    frame:SetFrameLevel((parent:GetFrameLevel() or 0) + 30)
    ApplyBackdrop(frame)
    frame.ownerFrame = parent
    frame.rows = {}
    frame:Hide()
    frame:HookScript("OnShow", function()
        PositionHandle(self, true)
    end)
    frame:HookScript("OnHide", function()
        PositionHandle(self, false)
        ClearDragState(self)
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
    frame.handle:SetScript("OnEnter", function(h)
        h.isHovered = true
        RefreshHandleVisual(self)
        GameTooltip:SetOwner(h, "ANCHOR_LEFT")
        GameTooltip:AddLine(Text("VISUAL_BOARD_DRAWER_TITLE", "组件"))
        GameTooltip:Show()
    end)
    frame.handle:SetScript("OnLeave", function(h)
        h.isHovered = false
        h.isPressed = false
        RefreshHandleVisual(self)
        GameTooltip:Hide()
    end)
    frame.handle:SetScript("OnMouseDown", function(h)
        h.isPressed = true
        RefreshHandleVisual(self)
    end)
    frame.handle:SetScript("OnMouseUp", function(h)
        h.isPressed = false
        RefreshHandleVisual(self)
    end)
    frame.handle:SetScript("OnClick", function()
        self:Toggle()
    end)
    PositionHandle(self, false)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    frame.title:SetText(Text("VISUAL_BOARD_DRAWER_TITLE", "组件"))

    frame.scroll = T.CreateScrollPanel(frame, {
        point1 = { "TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8 },
        point2 = { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 12 },
        backdrop = true,
        backdropAlpha = 0.12,
    })

    return frame
end

function Drawer:SetCallbacks(callbacks)
    self.callbacks = type(callbacks) == "table" and callbacks or {}
end

function Drawer:IsOpen()
    return self.frame and self.frame:IsShown()
end

function Drawer:Open()
    DoOpen(self)
end

function Drawer:Close()
    DoClose(self)
end

function Drawer:Toggle()
    if self:IsOpen() then
        DoClose(self)
    else
        DoOpen(self)
    end
end
end)
