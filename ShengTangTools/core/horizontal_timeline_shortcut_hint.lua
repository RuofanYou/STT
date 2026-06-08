local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local ShortcutHint = {}
T.HorizontalTimelineShortcutHint = ShortcutHint

local HSCROLL_HEIGHT = 8
local HSCROLL_BOTTOM = 8
local HINT_HEIGHT = 18
local HINT_BOTTOM = HSCROLL_BOTTOM + HSCROLL_HEIGHT + 4
local DIM_ALPHA = 0.42
local ACTIVE_ALPHA = 1
local INITIAL_SECONDS = 7
local HIDE_DELAY = 0.35
local FEEDBACK_SECONDS = 3.5
local POPOVER_WIDTH = 760
local POPOVER_HEIGHT = 260

ShortcutHint.height = HINT_HEIGHT
ShortcutHint.bottom = HINT_BOTTOM
ShortcutHint.feedbackSeconds = FEEDBACK_SECONDS

local Controller = {}
Controller.__index = Controller

local function BlockMousePropagation(frame)
    if not frame then
        return
    end
    if T.MarkPingBlocker then
        T.MarkPingBlocker(frame)
    end
end

local function ApplyBackdrop(frame, alpha)
    if T.ApplyBackdrop then
        T.ApplyBackdrop(frame, { alpha = alpha or 0.92 })
    elseif frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        frame:SetBackdropColor(0, 0, 0, alpha or 0.92)
        frame:SetBackdropBorderColor(0.32, 0.32, 0.34, 0.72)
    end
end

local function AddText(parent, template, x, y, width, color)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontDisableSmall")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then
        text:SetWordWrap(false)
    end
    if color then
        text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    return text
end

local function AddSection(parent, title, items, x, y, columnWidth, keyWidth)
    local header = AddText(parent, "GameFontNormalSmall", x, y, columnWidth, { 0.72, 0.75, 0.78, 1 })
    header:SetText(title)
    y = y - 20

    for _, item in ipairs(items) do
        local key = AddText(parent, "GameFontHighlightSmall", x, y, keyWidth, { 0.86, 0.88, 0.90, 1 })
        key:SetText(item[1])

        local action = AddText(parent, "GameFontDisableSmall", x + keyWidth + 8, y + 1, columnWidth - keyWidth - 8, { 0.58, 0.61, 0.65, 1 })
        action:SetText(item[2])
        y = y - 18
    end

    return y - 8
end

function ShortcutHint.Create(owner)
    if not (owner and owner.root) then
        return nil
    end
    if owner.shortcutHintController then
        return owner.shortcutHintController
    end
    local controller = setmetatable({ owner = owner }, Controller)
    owner.shortcutHintController = controller
    controller:CreateHint()
    return controller
end

function ShortcutHint.BindHover(owner, frame)
    if not (owner and frame and frame.HookScript) then
        return
    end
    frame:HookScript("OnEnter", function()
        if owner.shortcutHintController then
            owner.shortcutHintController:SetActive(true)
        end
    end)
    frame:HookScript("OnLeave", function()
        if owner.shortcutHintController then
            owner.shortcutHintController:ScheduleDim(HIDE_DELAY)
        end
    end)
end

function Controller:CreateHint()
    local root = self.owner.root
    local hint = CreateFrame("Button", nil, root)
    hint:SetHeight(HINT_HEIGHT)
    hint:SetFrameLevel((root:GetFrameLevel() or 0) + 12)
    hint:EnableMouse(true)
    BlockMousePropagation(hint)

    hint.bg = hint:CreateTexture(nil, "BACKGROUND")
    hint.bg:SetAllPoints()
    hint.bg:SetColorTexture(0.10, 0.10, 0.12, 0.0)

    hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint.text:SetPoint("LEFT", hint, "LEFT", 8, 0)
    hint.text:SetPoint("RIGHT", hint, "RIGHT", -8, 0)
    hint.text:SetJustifyH("LEFT")
    hint.text:SetText(L["TIMELINE_SHORTCUT_HINT_COMPACT"] or "Shift+滚轮 横移 · Alt/Option+Shift+滚轮 缩放 · 点击查看全部")
    if hint.text.SetWordWrap then
        hint.text:SetWordWrap(false)
    end

    hint:SetScript("OnEnter", function()
        self:SetActive(true)
    end)
    hint:SetScript("OnLeave", function()
        self:ScheduleDim(HIDE_DELAY)
    end)
    hint:SetScript("OnClick", function()
        self:TogglePopover()
    end)

    self.hint = hint
    self:Layout()
    self:SetActive(true)
    self:ScheduleDim(INITIAL_SECONDS)
end

function Controller:Layout()
    local hint = self.hint
    local owner = self.owner
    if not (hint and owner and owner.root) then
        return
    end
    hint:ClearAllPoints()
    hint:SetPoint("BOTTOMLEFT", owner.root, "BOTTOMLEFT", (owner.firstColWidth or 0) + 2, HINT_BOTTOM)
    hint:SetPoint("BOTTOMRIGHT", owner.root, "BOTTOMRIGHT", -6, HINT_BOTTOM)

    local popover = self.popover
    if popover then
        popover:SetSize(POPOVER_WIDTH, POPOVER_HEIGHT)
        popover:ClearAllPoints()
        popover:SetPoint("BOTTOMLEFT", hint, "TOPLEFT", 0, 4)
    end
end

function Controller:SetActive(active)
    local hint = self.hint
    if not hint then
        return
    end
    local isActive = active == true or (self.popover and self.popover:IsShown())
    hint:SetAlpha(isActive and ACTIVE_ALPHA or DIM_ALPHA)
    if hint.bg then
        hint.bg:SetColorTexture(0.10, 0.10, 0.12, isActive and 0.22 or 0.0)
    end
end

function Controller:SetText(text, activeSeconds)
    if not (self.hint and self.hint.text) then
        return
    end
    local value = tostring(text or "")
    if value == "" then
        value = L["TIMELINE_SHORTCUT_HINT_COMPACT"] or "Shift+滚轮 横移 · Alt/Option+Shift+滚轮 缩放 · 点击查看全部"
    end
    self.hint.text:SetText(value)
    self:SetActive(true)

    local delay = tonumber(activeSeconds)
    if delay and delay > 0 then
        self.textToken = (self.textToken or 0) + 1
        local token = self.textToken
        if C_Timer and C_Timer.After then
            C_Timer.After(delay, function()
                if token == self.textToken then
                    self:RestoreText()
                end
            end)
        end
    end
end

function Controller:RestoreText()
    if self.hint and self.hint.text then
        self.hint.text:SetText(L["TIMELINE_SHORTCUT_HINT_COMPACT"] or "Shift+滚轮 横移 · Alt/Option+Shift+滚轮 缩放 · 点击查看全部")
    end
end

function Controller:IsMouseOver()
    local owner = self.owner
    if owner and owner.root and owner.root:IsMouseOver() then
        return true
    end
    if self.hint and self.hint:IsMouseOver() then
        return true
    end
    if self.popover and self.popover:IsShown() and self.popover:IsMouseOver() then
        return true
    end
    return false
end

function Controller:ScheduleDim(delay)
    self.dimToken = (self.dimToken or 0) + 1
    local token = self.dimToken
    local waitSeconds = math.max(0, tonumber(delay) or 0)
    if C_Timer and C_Timer.After then
        C_Timer.After(waitSeconds, function()
            if token ~= self.dimToken or self:IsMouseOver() then
                return
            end
            self:HidePopover()
            self:SetActive(false)
        end)
    elseif not self:IsMouseOver() then
        self:HidePopover()
        self:SetActive(false)
    end
end

function Controller:CreatePopover()
    if self.popover then
        return self.popover
    end
    local owner = self.owner
    local root = owner and owner.root
    if not root then
        return nil
    end

    local popover = CreateFrame("Frame", nil, root, "BackdropTemplate")
    popover:SetFrameLevel((root:GetFrameLevel() or 0) + 45)
    popover:EnableMouse(true)
    BlockMousePropagation(popover)
    ApplyBackdrop(popover, 0.92)
    popover:Hide()

    popover:SetScript("OnEnter", function()
        self:SetActive(true)
    end)
    popover:SetScript("OnLeave", function()
        self:ScheduleDim(HIDE_DELAY)
    end)

    local title = AddText(popover, "GameFontHighlightSmall", 12, -10, 530, { 0.86, 0.88, 0.90, 1 })
    title:SetText(L["TIMELINE_SHORTCUT_HINT_TITLE"] or "水平时间轴快捷操作")

    AddSection(popover, L["TIMELINE_SHORTCUT_HINT_BROWSE"] or "浏览", {
        { L["TIMELINE_SHORTCUT_KEY_PAN"] or "Shift+滚轮", L["TIMELINE_SHORTCUT_HINT_PAN"] or "横向移动" },
        { L["TIMELINE_SHORTCUT_KEY_ZOOM"] or "Alt+Shift+滚轮", L["TIMELINE_SHORTCUT_HINT_ZOOM"] or "围绕鼠标时间缩放" },
        { L["TIMELINE_SHORTCUT_HINT_MIDDLE_DRAG"] or "中键拖动", L["TIMELINE_SHORTCUT_HINT_MIDDLE_DRAG_ACTION"] or "横向拖动画布" },
        { L["TIMELINE_SHORTCUT_HINT_SCROLLBAR"] or "底部滚动条", L["TIMELINE_SHORTCUT_HINT_SCROLLBAR_ACTION"] or "横向移动" },
    }, 14, -34, 340, 118)

    AddSection(popover, L["TIMELINE_SHORTCUT_HINT_PLAYBACK"] or "播放", {
        { "Space", L["TIMELINE_SHORTCUT_HINT_SPACE"] or "播放/暂停" },
        { L["TIMELINE_SHORTCUT_HINT_PLAYHEAD"] or "拖动播放头", L["TIMELINE_SHORTCUT_HINT_PLAYHEAD_ACTION"] or "定位时间" },
        { L["TIMELINE_SHORTCUT_HINT_RULER"] or "单击时间尺", L["TIMELINE_SHORTCUT_HINT_RULER_ACTION"] or "跳转到该时间" },
    }, 14, -124, 340, 118)

	    AddSection(popover, L["TIMELINE_SHORTCUT_HINT_EDIT"] or "编辑", {
	        { L["TIMELINE_SHORTCUT_KEY_SELECT_MULTI"] or "Ctrl/Command+点击", L["TIMELINE_SHORTCUT_HINT_SELECT_MULTI"] or "切换技能点选区" },
	        { L["TIMELINE_SHORTCUT_KEY_SELECT_RANGE"] or "Shift+点击", L["TIMELINE_SHORTCUT_HINT_SELECT_RANGE"] or "范围选择技能点" },
	        { L["TIMELINE_SHORTCUT_KEY_SELECT_ROW"] or "Ctrl/Command+点击行头", L["TIMELINE_SHORTCUT_HINT_SELECT_ROW"] or "选中本行技能点" },
	        { L["TIMELINE_SHORTCUT_HINT_DRAG_CHIP"] or "左拖技能点", L["TIMELINE_SHORTCUT_HINT_DRAG_CHIP_ACTION"] or "改写时间" },
	        { L["TIMELINE_SHORTCUT_KEY_FREE_DRAG"] or "Shift+拖动", L["TIMELINE_SHORTCUT_HINT_FREE_DRAG"] or "不吸附网格" },
	        { L["TIMELINE_SHORTCUT_HINT_RIGHT_CLICK_ADD"] or "右键轨道", L["TIMELINE_SHORTCUT_HINT_RIGHT_CLICK_ADD_ACTION"] or "添加技能" },
	        { L["TIMELINE_SHORTCUT_KEY_DELETE"] or "Delete/Backspace", L["TIMELINE_SHORTCUT_HINT_DELETE"] or "删除选中技能点" },
	        { L["TIMELINE_SHORTCUT_KEY_UNDO"] or "Ctrl/Cmd+Z", L["TIMELINE_SHORTCUT_HINT_UNDO"] or "撤销" },
	        { L["TIMELINE_SHORTCUT_KEY_REDO"] or "Ctrl/Cmd+Shift+Z/Y", L["TIMELINE_SHORTCUT_HINT_REDO"] or "重做" },
	    }, 390, -34, 348, 168)

    self.popover = popover
    self:Layout()
    return popover
end

function Controller:ShowPopover()
    local popover = self:CreatePopover()
    if not popover then
        return
    end
    self:Layout()
    popover:Show()
    self:SetActive(true)

    if not self.logged and T and T.LogDebugEvent then
        self.logged = true
        T.LogDebugEvent("STT_HTG_SHORTCUT_HINT", {
            action = "show",
            view = "horizontal",
        })
    end
end

function Controller:HidePopover()
    if self.popover then
        self.popover:Hide()
    end
end

function Controller:TogglePopover()
    if self.popover and self.popover:IsShown() then
        self:HidePopover()
        self:SetActive(self:IsMouseOver())
    else
        self:ShowPopover()
    end
end

end)
