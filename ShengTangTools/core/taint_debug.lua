local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("debugMode", function()

-- 仅在调试模式下启用的 taint 监控
local seen = {}
local function onTaintEvent(event, addon, func)
    local key = tostring(event).."|"..tostring(addon).."|"..tostring(func)
    if seen[key] then return end
    seen[key] = true
    local fn = tostring(func)
    T.debug("|cffff0000STT Taint|r:", event, "addon=", tostring(addon), "func=", fn)
    local trace = debugstack and debugstack(2, 6, 8) or "<no stack>"
    T.debug("|cffff0000STT Stack|r:\n" .. tostring(trace))
end

local function Init()
    -- 仅在调试模式下启用监控
    if not (C and C.DB and C.DB.debugMode) then
        return
    end
    -- 先注册监控，再输出状态，避免错过事件
    local monitor = CreateFrame("Frame")
    monitor:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    monitor:RegisterEvent("ADDON_ACTION_BLOCKED")
    monitor:RegisterEvent("UI_ERROR_MESSAGE")
    monitor:SetScript("OnEvent", function(self, event, ...)
        if event == "UI_ERROR_MESSAGE" then
            local _, msg = ...
            if type(msg) == "string" and (msg:find("Interface action failed") or msg:find("AddOn")) then
                T.debug("|cffff0000STT UI_ERROR|r:", msg)
            end
        else
            local a1, a2 = ...
            onTaintEvent(event, a1, a2)
        end
    end)

    -- 安全钩住弹窗（只读钩子）
    if hooksecurefunc then
        hooksecurefunc("StaticPopup_Show", function(which)
            if which == "ADDON_ACTION_FORBIDDEN" or which == "ADDON_ACTION_BLOCKED" then
                T.debug("|cffff0000STT Popup|r:", which)
            end
        end)
    end

    -- 直接挂到弹窗帧上，兜底记录
    for i = 1, 4 do
        local pf = _G["StaticPopup"..i]
        if pf and pf.HookScript then
            pf:HookScript("OnShow", function(self)
                local w = rawget(self, "which") or self.which
                if w == "ADDON_ACTION_FORBIDDEN" or w == "ADDON_ACTION_BLOCKED" then
                    T.debug("|cffff0000STT PopupFrame|r:", tostring(w))
                end
            end)
        end
    end

    -- 周期巡检：若弹窗可见，打印键名与文本前缀（避免错过 OnShow 钩子）
    local lastSeen = nil
    C_Timer.NewTicker(0.5, function()
        for i = 1, 4 do
            local f = _G["StaticPopup"..i]
            if f and f:IsShown() then
                local w = rawget(f, "which") or f.which or "<nil>"
                if w ~= lastSeen then
                    lastSeen = w
                    local txt = (f.text and f.text.GetText and f.text:GetText()) or ""
                    txt = tostring(txt):gsub("\n", " "):sub(1, 120)
                    T.debug("|cffff8800STT PopupSeen|r:", w, "|", txt)
                end
                break
            end
        end
    end)
end

T.RegisterInitCallback(Init)

end)
