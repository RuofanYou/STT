local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

-- 文本编辑器组件
local Editor = {}
T.NoteEditor = Editor

-- 极简多行编辑器（单一权威）：仅用于"可粘贴/可输入"，无任何额外按钮
function Editor:CreateSimpleEditor(parent, width, height)
    local frame = T.CreateScrollEditBox(parent, {
        width = width,
        height = height,
        stepSize = 40,
        blendSpeed = 0.15,
        textInsets = { 6, 6, 6, 6 },
        fontObject = ChatFontNormal,
    })
    local scroll = frame.scrollView
    local edit = frame.editBox

    local placeholder = frame:CreateFontString(nil, "OVERLAY")
    placeholder:SetFontObject(ChatFontNormal)
    placeholder:SetPoint("TOPLEFT", 8, -8)
    placeholder:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
    placeholder:SetTextColor(0.45, 0.45, 0.45, 0.6)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetJustifyV("TOP")
    placeholder:SetText(L["点击此处开始编辑"] or "点击此处开始编辑...")

    edit:HookScript("OnEditFocusGained", function()
        placeholder:Hide()
    end)
    edit:HookScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            placeholder:Show()
        end
    end)
    edit:HookScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)

    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    frame.placeholder = placeholder
    frame:RefreshMetrics()
    placeholder:SetShown(edit:GetText() == "")
    return frame
end

end)
