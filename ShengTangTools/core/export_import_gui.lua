local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local dialog
local previewToken = 0

local function Trim(text)
    local normalized = tostring(text or "")
    normalized = normalized:gsub("^%s+", "")
    normalized = normalized:gsub("%s+$", "")
    return normalized
end

local function FormatExportTime(timestamp)
    local value = tonumber(timestamp)
    if not value or value <= 0 or not date then
        return "-"
    end
    return date("%Y-%m-%d %H:%M", value)
end

local function GetExportInfo(dataType)
    local exportImport = T.ExportImport
    if not exportImport then
        return nil
    end

    if dataType == "raid" then
        return {
            title = L["导出团本战术板"] or "导出团本战术板",
            export = function()
                return exportImport:ExportRaidPlans()
            end,
        }
    end

    if dataType == "dungeon" then
        return {
            title = L["导出大秘境战术板"] or "导出大秘境战术板",
            export = function()
                return exportImport:ExportDungeonPlans()
            end,
        }
    end

    if dataType == "settings" then
        return {
            title = L["导出设置配置"] or "导出设置配置",
            export = function()
                return exportImport:ExportSettings()
            end,
        }
    end

    return nil
end

local function SetSummary(line1, line2, isError)
    if not dialog then
        return
    end

    dialog.summaryLine1:SetText(line1 or "")
    dialog.summaryLine2:SetText(line2 or "")

    local r, g, b = 0.85, 0.82, 0.62
    if isError then
        r, g, b = 1, 0.35, 0.35
    end

    dialog.summaryLine1:SetTextColor(r, g, b, 1)
    dialog.summaryLine2:SetTextColor(r, g, b, 1)
end

local function ShowReloadPopup()
    if not StaticPopupDialogs["STT_EXPORT_IMPORT_RELOAD_UI"] then
        StaticPopupDialogs["STT_EXPORT_IMPORT_RELOAD_UI"] = {
            text = L["设置导入后建议重载界面以确保所有设置生效"] or "设置导入后建议重载界面以确保所有设置生效",
            button1 = L["重载界面"] or "重载界面",
            button2 = L["稍后"] or "稍后",
            OnAccept = function()
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    else
        StaticPopupDialogs["STT_EXPORT_IMPORT_RELOAD_UI"].text =
            L["设置导入后建议重载界面以确保所有设置生效"] or "设置导入后建议重载界面以确保所有设置生效"
        StaticPopupDialogs["STT_EXPORT_IMPORT_RELOAD_UI"].button1 = L["重载界面"] or "重载界面"
        StaticPopupDialogs["STT_EXPORT_IMPORT_RELOAD_UI"].button2 = L["稍后"] or "稍后"
    end

    StaticPopup_Show("STT_EXPORT_IMPORT_RELOAD_UI")
end

local function ExecuteImport(mode)
    if not (dialog and dialog.editBox and T.ExportImport) then
        return
    end

    local text = dialog.editBox:GetText() or ""
    local summary = T.ExportImport:Preview(text)
    local ok, result = T.ExportImport:Import(text, mode)
    if not ok then
        SetSummary(L["导入失败"] or "导入失败", tostring(result or ""), true)
        return
    end

    SetSummary(L["导入成功"] or "导入成功", tostring(result or ""), false)
    T.msg(result)

    if summary and summary.typeCode == "S" then
        ShowReloadPopup()
    end
end

local function ShowReplaceConfirm()
    if not dialog then
        return
    end

    local text = dialog.editBox and dialog.editBox:GetText() or ""
    local summary, err
    if T.ExportImport then
        summary, err = T.ExportImport:Preview(text)
    end
    if not summary then
        SetSummary(L["导入失败"] or "导入失败", tostring(err or ""), true)
        return
    end

    local message = string.format(
        L["将清空当前类型的现有内容并导入新的%s，是否继续？"] or "将清空当前类型的现有内容并导入新的%s，是否继续？",
        summary.typeName or ""
    )

    if not StaticPopupDialogs["STT_EXPORT_IMPORT_REPLACE"] then
        StaticPopupDialogs["STT_EXPORT_IMPORT_REPLACE"] = {
            text = "%s",
            button1 = L["替换导入"] or "替换导入",
            button2 = L["取消"] or "取消",
            OnAccept = function()
                ExecuteImport("replace")
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    else
        StaticPopupDialogs["STT_EXPORT_IMPORT_REPLACE"].button1 = L["替换导入"] or "替换导入"
        StaticPopupDialogs["STT_EXPORT_IMPORT_REPLACE"].button2 = L["取消"] or "取消"
    end

    StaticPopup_Show("STT_EXPORT_IMPORT_REPLACE", message)
end

local function RefreshImportPreview()
    if not (dialog and dialog.mode == "import" and T.ExportImport) then
        return
    end

    local text = Trim(dialog.editBox:GetText() or "")
    if text == "" then
        SetSummary(
            L["尚未粘贴导入字符串"] or "尚未粘贴导入字符串",
            L["请粘贴 STT:1:R/D/S 开头的分享字符串"] or "请粘贴 STT:1:R/D/S 开头的分享字符串",
            false
        )
        dialog.primaryButton:Disable()
        dialog.secondaryButton:Disable()
        return
    end

    local summary, err = T.ExportImport:Preview(text)
    if not summary then
        SetSummary(L["导入预览失败"] or "导入预览失败", tostring(err or ""), true)
        dialog.primaryButton:Disable()
        dialog.secondaryButton:Disable()
        return
    end

    local line1 = string.format(
        "%s: %s | %s: %s",
        L["类型"] or "类型",
        summary.typeName or "",
        L["来源"] or "来源",
        summary.exporterName ~= "" and summary.exporterName or "-"
    )
    local line2
    if summary.typeCode == "S" then
        line2 = string.format(
            "%s: %d | %s: %s | %s: %s",
            L["设置项数"] or "设置项数",
            summary.settingsCount or 0,
            L["版本"] or "版本",
            summary.exporterVersion ~= "" and summary.exporterVersion or "-",
            L["导出时间"] or "导出时间",
            FormatExportTime(summary.exportTime)
        )
    else
        line2 = string.format(
            "%s: %d | %s: %d | %s: %s",
            L["团队方案数"] or "团队方案数",
            summary.planCount or 0,
            L["个人方案数"] or "个人方案数",
            summary.personalPlanCount or 0,
            L["导出时间"] or "导出时间",
            FormatExportTime(summary.exportTime)
        )
    end

    SetSummary(line1, line2, false)
    dialog.primaryButton:Enable()
    dialog.secondaryButton:Enable()
end

local function SchedulePreviewRefresh()
    previewToken = previewToken + 1
    local token = previewToken
    C_Timer.After(0.3, function()
        if token ~= previewToken then
            return
        end
        RefreshImportPreview()
    end)
end

local function EnsureDialog()
    if dialog then
        return dialog
    end

    dialog = T.CreatePopupWindow(nil, {
        name = (T.addon_name or "STT") .. "_ExportImportDialog",
        width = 700,
        height = 500,
        strata = "DIALOG",
        alpha = 0.92,
        title = "",
    })
    dialog.title:ClearAllPoints()
    dialog.title:SetPoint("TOP", 0, -10)
    dialog.title:SetFontObject(GameFontNormalLarge)

    local editor = T.NoteEditor and T.NoteEditor.CreateSimpleEditor and T.NoteEditor:CreateSimpleEditor(dialog)
    if editor then
        editor:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -42)
        editor:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 92)
        dialog.editor = editor
        dialog.editBox = editor.editBox
        if editor.placeholder then
            editor.placeholder:SetText(L["点击此处开始编辑"] or "点击此处开始编辑...")
        end
    end

    dialog.summaryLine1 = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dialog.summaryLine1:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 56)
    dialog.summaryLine1:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 56)
    dialog.summaryLine1:SetJustifyH("LEFT")

    dialog.summaryLine2 = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.summaryLine2:SetPoint("TOPLEFT", dialog.summaryLine1, "BOTTOMLEFT", 0, -4)
    dialog.summaryLine2:SetPoint("TOPRIGHT", dialog.summaryLine1, "BOTTOMRIGHT", 0, -4)
    dialog.summaryLine2:SetJustifyH("LEFT")

    dialog.primaryButton = T.CreateButton(dialog, {
        width = 120,
        height = 26,
        point = { "BOTTOM", dialog, "BOTTOM", -68, 16 },
    })
    dialog.secondaryButton = T.CreateButton(dialog, {
        width = 120,
        height = 26,
        point = { "LEFT", dialog.primaryButton, "RIGHT", 16, 0 },
    })

    dialog.primaryButton:SetScript("OnClick", function()
        if dialog.mode == "export" then
            if dialog.editBox then
                dialog.editBox:SetFocus()
                dialog.editBox:HighlightText()
            end
            T.msg(L["已复制，若未生效请手动全选复制"] or "已复制，若未生效请手动全选复制")
            return
        end
        ExecuteImport("merge")
    end)

    dialog.secondaryButton:SetScript("OnClick", function()
        if dialog.mode == "import" then
            ShowReplaceConfirm()
            return
        end
        dialog:Hide()
    end)

    if dialog.editBox then
        dialog.editBox:SetScript("OnTextChanged", function(_, userInput)
            if dialog.mode ~= "import" or not userInput then
                return
            end
            SchedulePreviewRefresh()
        end)
        dialog.editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dialog:Hide()
        end)
    end

    return dialog
end

local function ShowExport(dataType)
    local frame = EnsureDialog()
    local info = GetExportInfo(dataType)
    if not info then
        return
    end

    local exportText, err = info.export()
    frame.mode = "export"
    frame.dataType = dataType
    frame.title:SetText(info.title)
    frame.primaryButton:SetText(L["全选复制"] or "全选复制")
    frame.secondaryButton:SetText(CLOSE or "关闭")
    frame.primaryButton:Enable()
    frame.secondaryButton:Enable()
    frame:Show()

    if not exportText then
        frame.editBox:SetText("")
        SetSummary(L["导出失败"] or "导出失败", tostring(err or ""), true)
        frame.primaryButton:Disable()
        return
    end

    frame.editBox:SetText(exportText)
    local summary, previewErr = T.ExportImport:Preview(exportText)
    if not summary then
        SetSummary(L["导出失败"] or "导出失败", tostring(previewErr or ""), true)
        frame.primaryButton:Disable()
        return
    end

    local line1 = string.format(
        "%s: %s | %s: %s",
        L["类型"] or "类型",
        summary.typeName or "",
        L["导出者"] or "导出者",
        summary.exporterName ~= "" and summary.exporterName or "-"
    )
    local line2
    if summary.typeCode == "S" then
        line2 = string.format(
            "%s: %d | %s: %d",
            L["设置项数"] or "设置项数",
            summary.settingsCount or 0,
            L["字符串长度"] or "字符串长度",
            #exportText
        )
    else
        line2 = string.format(
            "%s: %d | %s: %d | %s: %d",
            L["团队方案数"] or "团队方案数",
            summary.planCount or 0,
            L["个人方案数"] or "个人方案数",
            summary.personalPlanCount or 0,
            L["字符串长度"] or "字符串长度",
            #exportText
        )
    end
    SetSummary(line1, line2, false)

    C_Timer.After(0, function()
        if not (dialog and dialog:IsShown() and dialog.mode == "export") then
            return
        end
        dialog.editBox:SetFocus()
        dialog.editBox:HighlightText()
    end)
end

local function ShowImportDialog()
    local frame = EnsureDialog()
    frame.mode = "import"
    frame.dataType = nil
    frame.title:SetText(L["导入配置"] or "导入配置")
    frame.primaryButton:SetText(L["合并导入"] or "合并导入")
    frame.secondaryButton:SetText(L["替换导入"] or "替换导入")
    frame.primaryButton:Disable()
    frame.secondaryButton:Disable()
    frame:Show()
    frame.editBox:SetText("")
    frame.editBox:SetFocus()
    if frame.editor and frame.editor.placeholder then
        frame.editor.placeholder:SetText(L["粘贴导入字符串到这里..."] or "粘贴导入字符串到这里...")
        frame.editor.placeholder:Show()
    end
    RefreshImportPreview()
end

function T.ShowExportImportDialog(mode, dataType)
    if mode == "import" then
        ShowImportDialog()
        return
    end

    ShowExport(dataType)
end

end)
