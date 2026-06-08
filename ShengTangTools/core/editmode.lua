-- T.EditMode：STT 可拖拽编辑位置的单一权威。
-- 视觉：暴雪 EditMode 原生 NineSlice 金边 + GameFontNormalLarge 居中标签。
-- 两种触发方式：
--   group = "blizz"：随暴雪 EditModeManagerFrame OnShow/OnHide 自动 enter/exit
--   group = "solo" ：业务代码手动调 T.EditMode:Enter/Exit/Toggle
-- 拖拽落定时调 saveFunc(point, relPoint, x, y) 写回 DB。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.editorLoaded", "screenReminder.enabled", "selfMarker.enabled", "dreadElegy.enabled", "luraCrystal.enabled", "auraColorAlert.enabled", "interruptRotation.enabled"}, function()

-- 编辑态视觉：半透明黑底 + 金黄边框，风格对齐暴雪 EditMode；不依赖 NineSlice atlas 套件
local OVERLAY_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
local OVERLAY_BG_COLOR     = { 0, 0, 0, 0.25 }
local OVERLAY_BORDER_COLOR = { 1, 0.82, 0, 1 }
local CLICK_THRESHOLD = 6

local entries = {}     -- frame(table) -> entry
local hooksBound = false

local function Debug(fmt, ...)
    if not T.debug then return end
    if select("#", ...) > 0 then
        T.debug(string.format("[EditMode] " .. tostring(fmt), ...))
    else
        T.debug("[EditMode] " .. tostring(fmt))
    end
end

local function RunCallbacks(callbacks, eventName)
    for _, func in ipairs(callbacks or {}) do
        local ok, err = xpcall(func, geterrorhandler())
        if not ok then
            Debug("callback_failed event=%s err=%s", tostring(eventName), tostring(err))
        end
    end
end

local function CreateOverlay(frame, displayName)
    local overlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    overlay:SetAllPoints(frame)
    -- strata/level 跟随 target frame 之上，避免被高 strata 的业务 frame（如 DIALOG）盖住吃掉鼠标事件
    local strata = frame.GetFrameStrata and frame:GetFrameStrata() or "HIGH"
    overlay:SetFrameStrata(strata)
    local baseLevel = frame.GetFrameLevel and frame:GetFrameLevel() or 0
    overlay:SetFrameLevel(baseLevel + 50)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetClampedToScreen(true)
    overlay:Hide()

    if overlay.SetBackdrop then
        overlay:SetBackdrop(OVERLAY_BACKDROP)
        overlay:SetBackdropColor(OVERLAY_BG_COLOR[1], OVERLAY_BG_COLOR[2], OVERLAY_BG_COLOR[3], OVERLAY_BG_COLOR[4])
        overlay:SetBackdropBorderColor(OVERLAY_BORDER_COLOR[1], OVERLAY_BORDER_COLOR[2], OVERLAY_BORDER_COLOR[3], OVERLAY_BORDER_COLOR[4])
    end

    overlay.Label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    overlay.Label:SetPoint("CENTER")
    overlay.Label:SetText(displayName or "")
    overlay.Label:SetTextColor(1, 0.82, 0, 1)
    overlay.Label:SetShadowOffset(1, -1)
    overlay.Label:SetShadowColor(0, 0, 0, 1)

    return overlay
end

local function EnterEntry(entry)
    if not entry or entry.editing then return end
    entry.editing = true
    entry.frame:SetMovable(true)
    if not entry.frame:IsShown() then
        entry.frame:Show()
        entry._forcedShow = true
    end
    if entry.overlay then entry.overlay:Show() end
    if entry.onEnter then
        local ok, err = xpcall(entry.onEnter, geterrorhandler())
        if not ok then Debug("onEnter_failed name=%s err=%s", tostring(entry.displayName), tostring(err)) end
    end
end

local function ExitEntry(entry)
    if not entry or not entry.editing then return end
    entry.editing = false
    if entry.overlay then entry.overlay:Hide() end
    if entry.onExit then
        local ok, err = xpcall(entry.onExit, geterrorhandler())
        if not ok then Debug("onExit_failed name=%s err=%s", tostring(entry.displayName), tostring(err)) end
    elseif entry._forcedShow then
        entry.frame:Hide()
    end
    entry._forcedShow = nil
end

local function BindEditModeHooks()
    if hooksBound then return true end
    if not EditModeManagerFrame then
        Debug("manager_unavailable")
        return false
    end

    EditModeManagerFrame:HookScript("OnShow", function()
        Debug("blizz_enter entries=%d", #entries)
        RunCallbacks(T.Unlock_callbacks, "enter")
        for _, entry in pairs(entries) do
            if entry.group == "blizz" then EnterEntry(entry) end
        end
    end)

    EditModeManagerFrame:HookScript("OnHide", function()
        Debug("blizz_exit")
        RunCallbacks(T.Lock_callbacks, "exit")
        for _, entry in pairs(entries) do
            if entry.group == "blizz" then ExitEntry(entry) end
        end
    end)

    hooksBound = true
    return true
end

T.EditMode = T.EditMode or {}

-- Register({frame, displayName, saveFunc, group="blizz"|"solo", onEnter?, onExit?, onClick?}) -> entry
function T.EditMode:Register(cfg)
    if type(cfg) ~= "table" or not cfg.frame then
        Debug("register_missing_frame")
        return nil
    end
    if entries[cfg.frame] then
        self:Unregister(cfg.frame)
    end

    local frame = cfg.frame
    local overlay = CreateOverlay(frame, cfg.displayName)
    local entry = {
        frame       = frame,
        overlay     = overlay,
        displayName = cfg.displayName,
        saveFunc    = cfg.saveFunc,
        group       = cfg.group == "solo" and "solo" or "blizz",
        onEnter     = cfg.onEnter,
        onExit      = cfg.onExit,
        onClick     = cfg.onClick,
        editing     = false,
    }

    overlay:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not entry.onClick then
            return
        end
        entry._downX, entry._downY = GetCursorPosition()
        entry._wasDragging = false
    end)
    overlay:SetScript("OnDragStart", function()
        entry._wasDragging = true
        frame:StartMoving()
    end)
    overlay:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if entry.saveFunc then
            local point, _, relPoint, x, y = frame:GetPoint(1)
            local ok, err = xpcall(function()
                entry.saveFunc(point, relPoint, x, y)
            end, geterrorhandler())
            if not ok then
                Debug("save_failed name=%s err=%s", tostring(entry.displayName), tostring(err))
            end
        end
    end)

    if entry.group == "solo" or entry.onClick then
        overlay:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" and entry.group == "solo" then
                T.EditMode:Exit(frame)
                return
            end
            if button == "LeftButton" and entry.onClick then
                local downX, downY = entry._downX, entry._downY
                local upX, upY = GetCursorPosition()
                local moved = 0
                if downX and downY and upX and upY then
                    local dx = upX - downX
                    local dy = upY - downY
                    moved = math.sqrt(dx * dx + dy * dy)
                end
                local wasDragging = entry._wasDragging == true
                entry._downX, entry._downY, entry._wasDragging = nil, nil, false
                if not wasDragging and moved < CLICK_THRESHOLD then
                    local ok, err = xpcall(function()
                        entry.onClick(frame)
                    end, geterrorhandler())
                    if not ok then
                        Debug("onClick_failed name=%s err=%s", tostring(entry.displayName), tostring(err))
                    end
                end
            end
        end)
    end

    entries[frame] = entry
    BindEditModeHooks()

    if entry.group == "blizz" and T.IsUnlocked and T.IsUnlocked() then
        EnterEntry(entry)
    end

    return entry
end

function T.EditMode:Unregister(frame)
    local entry = entries[frame]
    if not entry then return end
    ExitEntry(entry)
    if entry.overlay then
        entry.overlay:Hide()
        entry.overlay:SetParent(nil)
    end
    entries[frame] = nil
end

function T.EditMode:Enter(frame)
    EnterEntry(entries[frame])
end

function T.EditMode:Exit(frame)
    ExitEntry(entries[frame])
end

function T.EditMode:Toggle(frame)
    local entry = entries[frame]
    if not entry then return end
    if entry.editing then
        ExitEntry(entry)
    else
        EnterEntry(entry)
    end
end

function T.EditMode:IsEditing(frame)
    local entry = entries[frame]
    return entry and entry.editing or false
end

function T.EditMode:GetOverlay(frame)
    local entry = entries[frame]
    return entry and entry.overlay or nil
end

function T.EditMode:SetDisplayName(frame, name)
    local entry = entries[frame]
    if not entry then return end
    entry.displayName = name
    if entry.overlay and entry.overlay.Label then
        entry.overlay.Label:SetText(name or "")
    end
end

-- 全局收口：把所有 group="solo" 的解锁锚点全部锁回。
-- 触发场景：STT 主面板关闭 → 防止玩家忘记关锚点框找不到关闭入口。
-- 不影响 group="blizz"（暴雪 EditMode 联动），那一组由暴雪自己管。
function T.EditMode:ExitAllSolo()
    for _, entry in pairs(entries) do
        if entry.group == "solo" and entry.editing then
            ExitEntry(entry)
        end
    end
end

BindEditModeHooks()

end)
