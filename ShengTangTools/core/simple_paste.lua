local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

-- 最简“粘贴板”窗口：只提供一个可粘贴的多行文本框
-- 目的：在高级编辑器出现异常时，仍能把外部编辑好的文本粘贴进来供 TTS 使用

local frame

local function EnsureFrame()
    if frame then return frame end

    frame = T.CreatePopupWindow(nil, {
        name = T.addon_name.."_PastePad",
        width = 700,
        height = 420,
        strata = "DIALOG",
        alpha = 0.9,
        title = "圣糖战术板 - 粘贴文本",
    })
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOP", 0, -10)
    frame.title:SetFontObject(GameFontNormalLarge)

    -- 统一使用极简编辑器（与战术方案页共享实现）
    local editor = (T.NoteEditor and T.NoteEditor.CreateSimpleEditor and T.NoteEditor:CreateSimpleEditor(frame)) or nil
    editor:SetPoint("TOPLEFT", 12, -40)
    editor:SetPoint("BOTTOMRIGHT", -12, 46)
    local edit = editor and editor.editBox

    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)

    -- 写入按钮：覆盖当前 STN 方案内容
    local writeBtn = T.CreateButton(frame, {
        text = "写入当前方案",
        width = 140,
        height = 24,
        point = { "BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12 },
    })
    writeBtn:SetScript("OnClick", function()
        local sem = T.SemanticTimeline
        local tab = sem and sem.GetCurrentEditorTab and sem:GetCurrentEditorTab() or "team"
        if not (sem and sem.SavePlanContentForTab and sem.GetCurrentPlanForTab) then
            return
        end
        local plan = sem:GetCurrentPlanForTab(tab)
        if not (plan and plan.id) then
            T.msg("没有可写入的固定文档，请先在语义时间轴页选择 Boss")
            return
        end
        local ok = sem:SavePlanContentForTab(tab, edit:GetText() or "")
        if ok then
            T.msg("已覆盖当前方案内容")
        else
            T.msg("写入失败：找不到当前方案")
        end
    end)

    -- 关闭按钮（底部）
    local closeBtn = T.CreateButton(frame, {
        text = CLOSE,
        width = 80,
        height = 24,
        point = { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12 },
    })
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    frame.Edit = edit
    return frame
end

function T.ShowPastePad()
    local f = EnsureFrame()
    -- 预填：当前 STN 方案内容（若有）
    local sem = T.SemanticTimeline
    local tab = sem and sem.GetCurrentEditorTab and sem:GetCurrentEditorTab() or "team"
    if sem and sem.GetCurrentPlanForTab then
        local plan = sem:GetCurrentPlanForTab(tab)
        if plan then
            f.Edit:SetText(plan.content or "")
            f.Edit:HighlightText()
        else
            f.Edit:SetText("")
        end
    else
        f.Edit:SetText("")
    end
    f:Show()
    f.Edit:SetFocus()
end

end)
