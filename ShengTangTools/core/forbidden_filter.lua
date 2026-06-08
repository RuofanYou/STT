local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("suppressForbiddenPopup", function()

-- 拦截并隐藏暴雪的受保护动作弹窗（ADDON_ACTION_FORBIDDEN/BLOCKED）
-- 目的：在不改变游戏受保护逻辑的前提下，避免弹窗打断体验。
-- 实现：
-- 1) 钩住 StaticPopup_Show 事后立即隐藏目标弹窗；
-- 2) 对 StaticPopup1..4 的 OnShow 做兜底隐藏；
-- 3) 允许通过配置开关（C.DB.suppressForbiddenPopup）启用/禁用。

local FILTER_KEYS = {
    ADDON_ACTION_FORBIDDEN = true,
    ADDON_ACTION_BLOCKED = true,
}

local initialized = false
local dialogRefreshTicker = nil
local hookRefreshTicker = nil
local activeRefresh = false
local eventFrame = nil

local function IsForbiddenKey(which)
    if FILTER_KEYS[which] then return true end
    if type(which) == "string" then
        which = which:upper()
        return which:find("FORBIDDEN", 1, true) or which:find("BLOCKED", 1, true)
    end
    return false
end

local function ShouldSuppress()
    if not C or not C.DB then return false end
    return C.DB.suppressForbiddenPopup == true
end

local function HideForbiddenPopups()
    if not ShouldSuppress() then return end
    for i = 1, 4 do
        local f = _G["StaticPopup"..i]
        if f and f:IsShown() then
            local which = rawget(f, "which") or f.which
            if which and IsForbiddenKey(which) then
                f:Hide()
            end
        end
    end
end

local function HookFrames()
    for i = 1, 4 do
        local f = _G["StaticPopup"..i]
        if f and f.HookScript and not f.__stt_forbidden_hooked then
            f:HookScript("OnShow", function(self)
                if not ShouldSuppress() then return end
                local w = rawget(self, "which") or self.which
                if w and IsForbiddenKey(w) then
                    self:Hide()
                end
            end)
            f.__stt_forbidden_hooked = true
        end
    end
end

local function EnsureSilentDialog(key)
    if type(StaticPopupDialogs) ~= "table" then return end
    local dlg = StaticPopupDialogs[key]
    if dlg and dlg.__stt_silent then return end
    StaticPopupDialogs[key] = {
        text = "",
        button1 = OKAY,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
        OnShow = function(self) self:Hide() end,
        OnAccept = function(self) self:Hide() end,
        OnCancel = function(self) self:Hide() end,
        __stt_silent = true,
    }
end

local function EnsureAllSilent()
    for key in pairs(FILTER_KEYS) do
        EnsureSilentDialog(key)
    end
end

local function CancelTicker(ticker)
    if ticker and ticker.Cancel then
        ticker:Cancel()
    end
end

local function StopActiveRefresh()
    activeRefresh = false
    CancelTicker(dialogRefreshTicker)
    CancelTicker(hookRefreshTicker)
    dialogRefreshTicker = nil
    hookRefreshTicker = nil
end

local function StartActiveRefresh()
    if activeRefresh or not ShouldSuppress() then
        return
    end
    activeRefresh = true
    EnsureAllSilent()
    HookFrames()

    if C_Timer and C_Timer.NewTicker then
        dialogRefreshTicker = C_Timer.NewTicker(3, function()
            if ShouldSuppress() then
                EnsureAllSilent()
            end
        end)
        hookRefreshTicker = C_Timer.NewTicker(2, function()
            if ShouldSuppress() then
                HookFrames()
            end
        end)
    end
end

local function Init()
    if initialized then
        return
    end
    initialized = true

    -- 将相关对话框替换为“静默模板”，防止 Blizzard 代码报错
    EnsureAllSilent()
    -- 事后隐藏（确保即便别的插件先显示了弹窗，我们也能马上关掉）
    if hooksecurefunc then
        hooksecurefunc("StaticPopup_Show", function(which)
            if not ShouldSuppress() then return end
            if IsForbiddenKey(which) then
                EnsureAllSilent()
                if StaticPopup_Hide then
                    StaticPopup_Hide(which)
                end
                C_Timer.After(0, HideForbiddenPopups)
            end
        end)
    end

    -- 兜底：所有静态弹窗帧都做一次 OnShow 屏蔽
    HookFrames()

    -- 过滤 UI_ERROR_MESSAGE 中的相关提示语（不影响其他错误）
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
    eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(self, event, messageType, message)
        -- Dragonflight 起参数为 (event, messageType, message)
        if event == "UI_ERROR_MESSAGE" then
            local msg = tostring(message)
            if msg:find("Interface action failed") or msg:find("AddOn") then
                return -- 吞掉该错误
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            StartActiveRefresh()
        elseif event == "PLAYER_REGEN_ENABLED" then
            StopActiveRefresh()
            EnsureAllSilent()
            HookFrames()
        else
            -- 事件级：一旦触发就立刻关闭相关弹窗
            if ShouldSuppress() then
                if StaticPopup_Hide then
                    StaticPopup_Hide("ADDON_ACTION_FORBIDDEN")
                    StaticPopup_Hide("ADDON_ACTION_BLOCKED")
                end
                HideForbiddenPopups()
            end
        end
    end)
end

if T.ModuleLoader then
    local Filter = T.ModuleLoader:NewModule({
        name = "ForbiddenFilter",
        dbKey = "suppressForbiddenPopup",
        defaultEnabled = false,
    })

    function Filter:OnEnable()
        Init()
    end

    function Filter:OnDisable()
        StopActiveRefresh()
        if eventFrame then
            eventFrame:UnregisterAllEvents()
        end
    end
end

end)
