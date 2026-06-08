local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("realtimeBoard.enabled", function()

local RealtimeBoardGUI = {
    refreshers = {},
}
T.RealtimeBoardGUI = RealtimeBoardGUI

local rootFrame
local scrollContent
local focusWidgets = {}

local function DB()
    C.DB.realtimeBoard = C.DB.realtimeBoard or {}
    if STT_DB then
        STT_DB.realtimeBoard = C.DB.realtimeBoard
    end
    return C.DB.realtimeBoard
end

local function AddRefresher(fn)
    RealtimeBoardGUI.refreshers[#RealtimeBoardGUI.refreshers + 1] = fn
    return fn
end

local function ApplySettings()
    if STT_DB then
        STT_DB.realtimeBoard = C.DB.realtimeBoard
    end
    if T.RealtimeBoard and T.RealtimeBoard.RefreshConfig then
        T.RealtimeBoard:RefreshConfig()
    end
end

local function NormalizeSpellDisplayMode(value)
    if value == "iconText" or value == "icon" or value == "text" then
        return value
    end
    return "iconText"
end

local function SetFocusWidgetsShown()
    local shown = DB().displayStyle == "focus"
    for _, frame in ipairs(focusWidgets or {}) do
        if frame and frame.SetShown then
            frame:SetShown(shown)
        end
    end
end

local function BuildSection(parent, titleKey, startY)
    local title = T.CreateGroupTitle(parent, {
        text = L[titleKey],
        point = {"TOPLEFT", parent, "TOPLEFT", 12, startY},
        fontSize = 14,
    })
    T.CreateSeparator(parent, {
        point = {"TOPLEFT", title, "BOTTOMLEFT", 0, -6},
        width = 640,
        color = {0.5, 0.5, 0.5, 0.35},
    })
    return startY - 18
end

function RealtimeBoardGUI.CreateInterface(parent)
    if rootFrame == parent and scrollContent then
        return
    end

    rootFrame = parent
    RealtimeBoardGUI.refreshers = {}
    focusWidgets = {}

    local scroll = T.CreateSimpleScroll(parent, { stepSize = 40 })
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -26, 0)

    local content = scroll.content
    scrollContent = content

    local y = -12
    y = BuildSection(content, "实时战术板", y)

    T.CreateToggleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y - 10 },
        label = "实时战术板",
        getter = function()
            return DB().enabled ~= false
        end,
        setter = function(value)
            DB().enabled = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateActionButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 210, y - 10 },
        width = 140,
        textFn = function()
            return L["测试"]
        end,
        onClick = function()
            if T.RealtimeBoard and T.RealtimeBoard.RunTest then
                T.RealtimeBoard:RunTest()
            end
        end,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateActionButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 364, y - 10 },
        width = 140,
        textFn = function()
            if T.RealtimeBoard and T.RealtimeBoard.IsLocked and T.RealtimeBoard:IsLocked() then
                return L["解锁位置"]
            end
            return L["锁定位置"]
        end,
        onClick = function()
            if not T.RealtimeBoard then
                return
            end
            if T.RealtimeBoard:IsLocked() then
                T.RealtimeBoard:SetLocked(false)
            else
                T.RealtimeBoard:SetLocked(true)
            end
        end,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateActionButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 518, y - 10 },
        width = 120,
        textFn = function()
            return L["重置位置"]
        end,
        onClick = function()
            if T.RealtimeBoard and T.RealtimeBoard.ResetPosition then
                T.RealtimeBoard:ResetPosition()
            end
        end,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 56
    y = BuildSection(content, "外观", y)

    T.CreateSliderRow(content, {
        y = y,
        label = "背景透明度",
        min = 0,
        max = 0.95,
        step = 0.05,
        getter = function()
            return DB().bgAlpha or 0.65
        end,
        setter = function(value)
            DB().bgAlpha = value
        end,
        formatter = function(value)
            return string.format("%d%%", math.floor(value * 100 + 0.5))
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    T.CreateSliderRow(content, {
        y = y,
        label = "缩放",
        min = 0.6,
        max = 1.6,
        step = 0.05,
        getter = function()
            return DB().scale or 1
        end,
        setter = function(value)
            DB().scale = value
        end,
        formatter = function(value)
            return string.format("%d%%", math.floor(value * 100 + 0.5))
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    T.CreateSliderRow(content, {
        y = y,
        label = "文字大小",
        min = 10,
        max = 20,
        step = 1,
        getter = function()
            return DB().fontSize or 13
        end,
        setter = function(value)
            DB().fontSize = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    T.CreateSliderRow(content, {
        y = y,
        label = "行高",
        min = 24,
        max = 48,
        step = 1,
        getter = function()
            return DB().rowHeight or 32
        end,
        setter = function(value)
            DB().rowHeight = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y },
        width = 190,
        label = "GUI_BOARD_SPELL_DISPLAY_MODE",
        values = {
            { value = "iconText", text = L["SR_SPELL_DISPLAY_ICON_TEXT"] or "图标+文本" },
            { value = "icon", text = L["SR_SPELL_DISPLAY_ICON"] or "仅图标" },
            { value = "text", text = L["SR_SPELL_DISPLAY_TEXT"] or "仅文本" },
        },
        getter = function()
            return NormalizeSpellDisplayMode(DB().spellDisplayMode)
        end,
        setter = function(value)
            DB().spellDisplayMode = NormalizeSpellDisplayMode(value)
            DB().showSpellIcon = nil
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateToggleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 210, y },
        label = "显示头部",
        getter = function()
            return DB().showHeader ~= false
        end,
        setter = function(value)
            DB().showHeader = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 46
    y = BuildSection(content, "行为", y)

    T.CreateSliderRow(content, {
        y = y,
        label = "自动恢复延迟",
        min = 1,
        max = 8,
        step = 0.5,
        getter = function()
            return DB().autoScrollDelay or 3
        end,
        setter = function(value)
            DB().autoScrollDelay = value
        end,
        formatter = function(value)
            return string.format("%.1fs", value)
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    T.CreateSliderRow(content, {
        y = y,
        label = "滚动速度",
        min = 2,
        max = 16,
        step = 0.5,
        getter = function()
            return DB().smoothSpeed or 8
        end,
        setter = function(value)
            DB().smoothSpeed = value
        end,
        formatter = function(value)
            return string.format("%.1f", value)
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 46
    y = BuildSection(content, "风格", y)

    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y - 10 },
        width = 190,
        label = "过期事件",
        values = {
            { value = "gray", text = L["保留"] },
            { value = "fade", text = L["淡出"] },
            { value = "hide", text = L["隐藏"] },
        },
        getter = function()
            return DB().expiredMode or "gray"
        end,
        setter = function(value)
            DB().expiredMode = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 214, y - 10 },
        width = 210,
        label = "当前事件位置",
        values = {
            { value = "flow", text = L["自然滚动"] },
            { value = "top", text = L["顶部固定"] },
            { value = "bottom", text = L["底部固定"] },
        },
        getter = function()
            return DB().anchorPosition or "flow"
        end,
        setter = function(value)
            DB().anchorPosition = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 436, y - 10 },
        width = 200,
        label = "显示范围",
        values = {
            { value = false, text = L["仅与我相关"] },
            { value = true, text = L["显示全部"] },
        },
        getter = function()
            return DB().showAllEvents == true
        end,
        setter = function(value)
            DB().showAllEvents = value and true or false
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 46
    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y },
        width = 180,
        label = "条目样式",
        values = {
            { value = "clean", text = L["清爽"] },
            { value = "card", text = L["卡片"] },
        },
        getter = function()
            return DB().cellStyle or "clean"
        end,
        setter = function(value)
            DB().cellStyle = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 204, y },
        width = 180,
        label = "时间方向",
        values = {
            { value = "down", text = string.format("%s %s", L["正序"], L["↓"]) },
            { value = "up", text = string.format("%s %s", L["倒序"], L["↑"]) },
        },
        getter = function()
            return DB().timeDirection or "down"
        end,
        setter = function(value)
            DB().timeDirection = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 396, y },
        width = 180,
        label = "时间格式",
        values = {
            { value = "precise", text = L["小数"] },
            { value = "seconds", text = L["整数"] },
            { value = "full", text = L["分秒"] },
            { value = "elapsed", text = L["战斗时长"] },
        },
        getter = function()
            return DB().countdownFormat or "precise"
        end,
        setter = function(value)
            DB().countdownFormat = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 46
    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y },
        width = 180,
        label = "显示样式",
        values = {
            { value = "classic", text = L["GUI_BOARD_DISPLAY_CLASSIC"] },
            { value = "focus", text = L["GUI_BOARD_DISPLAY_FOCUS"] },
            { value = "concise", text = L["GUI_BOARD_DISPLAY_CONCISE"] },
        },
        getter = function()
            return DB().displayStyle or "classic"
        end,
        setter = function(value)
            DB().displayStyle = (value == "focus" or value == "concise") and value or "classic"
            SetFocusWidgetsShown()
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 204, y },
        width = 180,
        label = L["GUI_BOARD_TIME_POSITION"],
        values = {
            { value = "right", text = L["GUI_BOARD_TIME_RIGHT_EDGE"] },
            { value = "left", text = L["GUI_BOARD_TIME_BEFORE_ICON"] },
        },
        getter = function()
            return DB().timePosition or "right"
        end,
        setter = function(value)
            DB().timePosition = value == "left" and "left" or "right"
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 52
    local focusTitle = T.CreateGroupTitle(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y },
        text = L["GUI_BOARD_FOCUS_SETTINGS"],
        fontSize = 13,
    })
    focusWidgets[#focusWidgets + 1] = focusTitle
    local focusSep = T.CreateSeparator(content, {
        point = { "TOPLEFT", focusTitle, "BOTTOMLEFT", 0, -5 },
        width = 620,
    })
    focusWidgets[#focusWidgets + 1] = focusSep

    y = y - 34
    focusWidgets[#focusWidgets + 1] = T.CreateSliderRow(content, {
        y = y,
        label = L["GUI_BOARD_FOCUS_UP_NEIGHBORS"],
        min = 0,
        max = 4,
        step = 1,
        getter = function()
            return DB().focus and DB().focus.upNeighbors or 2
        end,
        setter = function(value)
            DB().focus = DB().focus or {}
            DB().focus.upNeighbors = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    focusWidgets[#focusWidgets + 1] = T.CreateSliderRow(content, {
        y = y,
        label = L["GUI_BOARD_FOCUS_DOWN_NEIGHBORS"],
        min = 0,
        max = 4,
        step = 1,
        getter = function()
            return DB().focus and DB().focus.downNeighbors or 2
        end,
        setter = function(value)
            DB().focus = DB().focus or {}
            DB().focus.downNeighbors = value
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    focusWidgets[#focusWidgets + 1] = T.CreateSliderRow(content, {
        y = y,
        label = L["GUI_BOARD_FOCUS_EMPHASIS"],
        min = 0,
        max = 1,
        step = 0.01,
        getter = function()
            return DB().focus and DB().focus.emphasis or 0.55
        end,
        setter = function(value)
            DB().focus = DB().focus or {}
            DB().focus.emphasis = math.max(0, math.min(1, tonumber(value) or 0.55))
        end,
        formatter = function(value)
            return string.format("%d%%", math.floor((tonumber(value) or 0) * 100 + 0.5))
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    focusWidgets[#focusWidgets + 1] = T.CreateSliderRow(content, {
        y = y,
        label = L["GUI_BOARD_FOCUS_WIDTH_RATIO"],
        min = 0.50,
        max = 1.00,
        step = 0.01,
        getter = function()
            return DB().focus and DB().focus.widthRatio or 1.00
        end,
        setter = function(value)
            DB().focus = DB().focus or {}
            DB().focus.widthRatio = math.max(0.50, math.min(1.00, tonumber(value) or 1.00))
        end,
        formatter = function(value)
            return string.format("%d%%", math.floor((tonumber(value) or 0) * 100 + 0.5))
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    focusWidgets[#focusWidgets + 1] = T.CreateSliderRow(content, {
        y = y,
        label = L["GUI_BOARD_FOCUS_SPACING"],
        min = 0,
        max = 24,
        step = 1,
        getter = function()
            return DB().focus and DB().focus.spacingPx or 4
        end,
        setter = function(value)
            DB().focus = DB().focus or {}
            DB().focus.spacingPx = math.max(0, math.min(24, tonumber(value) or 4))
            DB().focus.gapPx = nil
        end,
        formatter = function(value)
            return string.format("%d px", math.floor((tonumber(value) or 0) + 0.5))
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    focusWidgets[#focusWidgets + 1] = T.CreateSliderRow(content, {
        y = y,
        label = L["GUI_BOARD_FOCUS_HOLD_SECONDS"],
        min = 0,
        max = 3,
        step = 0.1,
        getter = function()
            return DB().focus and DB().focus.holdSeconds or 0.7
        end,
        setter = function(value)
            DB().focus = DB().focus or {}
            DB().focus.holdSeconds = math.max(0, math.min(3, tonumber(value) or 0.7))
        end,
        formatter = function(value)
            return string.format("%.1fs", tonumber(value) or 0)
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 42
    focusWidgets[#focusWidgets + 1] = T.CreateCheckbox(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y },
        label = L["GUI_BOARD_FOCUS_DEPARTURE_ENABLED"],
        clickLabel = true,
        getter = function()
            return not (DB().focus and DB().focus.departureEnabled == false)
        end,
        setter = function(value)
            DB().focus = DB().focus or {}
            DB().focus.departureEnabled = value == true
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 52
    focusWidgets[#focusWidgets + 1] = T.CreateCycleButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y },
        width = 180,
        label = L["GUI_BOARD_FOCUS_ALIGN"],
        values = {
            { value = "left", text = L["GUI_BOARD_ALIGN_LEFT"] },
            { value = "center", text = L["GUI_BOARD_ALIGN_CENTER"] },
            { value = "right", text = L["GUI_BOARD_ALIGN_RIGHT"] },
        },
        getter = function()
            return DB().focus and DB().focus.align or "left"
        end,
        setter = function(value)
            DB().focus = DB().focus or {}
            DB().focus.align = (value == "center" or value == "right") and value or "left"
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 52

    T.CreateSliderRow(content, {
        y = y,
        label = "远期隐藏",
        min = 0,
        max = 120,
        step = 5,
        getter = function()
            return DB().maxLookahead or 0
        end,
        setter = function(value)
            DB().maxLookahead = value
        end,
        formatter = function(value)
            if tonumber(value) == 0 then
                return L["不限"]
            end
            return string.format("%ds", tonumber(value) or 0)
        end,
        onApply = ApplySettings,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    y = y - 62
    y = BuildSection(content, "位置", y)

    T.CreateActionButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 12, y - 10 },
        width = 180,
        textFn = function()
            return L["锁定位置"]
        end,
        onClick = function()
            if T.RealtimeBoard and T.RealtimeBoard.SetLocked then
                T.RealtimeBoard:SetLocked(true)
            end
        end,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateActionButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 210, y - 10 },
        width = 180,
        textFn = function()
            return L["解锁位置"]
        end,
        onClick = function()
            if T.RealtimeBoard and T.RealtimeBoard.SetLocked then
                T.RealtimeBoard:SetLocked(false)
            end
        end,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    T.CreateActionButton(content, {
        point = { "TOPLEFT", content, "TOPLEFT", 408, y - 10 },
        width = 180,
        textFn = function()
            return L["重置位置"]
        end,
        onClick = function()
            if T.RealtimeBoard and T.RealtimeBoard.ResetPosition then
                T.RealtimeBoard:ResetPosition()
            end
        end,
        refreshList = RealtimeBoardGUI.refreshers,
    })

    SetFocusWidgetsShown()
    scroll:SetContentHeight(1376)
end

function RealtimeBoardGUI.RefreshTexts()
    for _, fn in ipairs(RealtimeBoardGUI.refreshers or {}) do
        fn()
    end
end

function RealtimeBoardGUI.RefreshLocalization()
    RealtimeBoardGUI.RefreshTexts()
end

end)
