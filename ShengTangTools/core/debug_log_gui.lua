local T, C, L = unpack(select(2, ...))

local WINDOW_NAME = "STTDebugLogWindow"

local function RefreshWindow(frame)
    local count = T.GetDebugLogCount and T.GetDebugLogCount() or 0
    frame.title:SetText(string.format("STT 诊断日志 (%d)", count))
    frame.editor:SetText((T.BuildDebugLogCSV and T.BuildDebugLogCSV()) or "序号;时间;运行秒;来源;消息")
    frame.editor:SetFocus()
    frame.editor.editBox:HighlightText(0, -1)
end

local function CreateWindow()
    local frame = T.CreatePopupWindow(UIParent, {
        name = WINDOW_NAME,
        width = 860,
        height = 520,
        title = "STT 诊断日志",
        point = { "CENTER" },
        strata = "DIALOG",
    })

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
    hint:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("点击文本框后按 Ctrl/Cmd+A 全选，再复制给开发者。")
    frame.hint = hint

    local editor = T.CreateScrollEditBox(frame, {
        stepSize = 40,
        blendSpeed = 0.12,
        textInsets = { 8, 8, 8, 8 },
        fontObject = ChatFontNormal,
        disableCursorAutoScroll = true,
    })
    editor:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -54)
    editor:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    editor.editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    frame.editor = editor

    frame:HookScript("OnShow", function(self)
        C_Timer.After(0, function()
            if self:IsShown() then
                RefreshWindow(self)
            end
        end)
    end)

    return frame
end

function T.ShowDebugLogWindow()
    if not T.CreatePopupWindow or not T.CreateScrollEditBox then
        T.msg("诊断日志窗口模块未加载")
        return
    end

    local frame = _G[WINDOW_NAME] or CreateWindow()
    frame:Show()
    RefreshWindow(frame)
end
