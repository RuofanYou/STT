-- screen_reminder/options_panel.lua
-- 屏幕提醒 V2 GUI 总装：在 540×约580 内布局
--   头部启用复选（由 option_engine 的 masterToggle 提供）
--   预览区 140 高
--   左 1/3 列表 + 右 2/3 配置（各自独立滚动）
--   底部按钮：解锁 / 测试 / 导入导出 / 重置下发黑名单

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

local Schema = T.ScreenReminderSchema
local Preview = T.ScreenReminderPreview
local PanelList = T.ScreenReminderPanelList
local PanelConfig = T.ScreenReminderPanelConfig

local OptionsPanel = {}
T.ScreenReminderOptionsPanel = OptionsPanel

-- 高度严格压缩在 settings 主面板视野内。长内容靠 list / config 内嵌 scroll 处理。
local PANEL_HEIGHT = 410
local PREVIEW_HEIGHT = 90
local GLOBAL_ROW_HEIGHT = 28
local BOTTOM_BUTTONS_HEIGHT = 28
local COL_GAP = 12
local BOTTOM_BUTTON_WIDTH = 104
local BOTTOM_BUTTON_GAP = 4
local IO_PREFIX = "STT:SR:1:"
local IO_FORMAT = "STT_SCREEN_REMINDER"
local ioDialog
local ioPreviewToken = 0
local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)

local function AttachTooltip(frame, text)
    if T.UITooltip then
        T.UITooltip.AttachSimple(frame, text, { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
    end
end

local function Trim(text)
    local value = tostring(text or "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function EncodeScreenReminderConfig()
    if not (LibSerialize and LibDeflate and Schema.DeepCopy and Schema.GetRoot) then
        return nil, L["通信库未加载"] or "通信库未加载"
    end
    local payload = {
        _format = IO_FORMAT,
        _exportTime = time and time() or 0,
        _exporterVersion = tostring(T and T.Version or ""),
        _exporterName = tostring(UnitName and (UnitName("player") or "") or ""),
        screenReminder = Schema.DeepCopy(Schema.GetRoot()),
    }
    local serialized = LibSerialize:Serialize(payload)
    if not serialized then
        return nil, L["序列化失败"] or "序列化失败"
    end
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then
        return nil, L["压缩失败"] or "压缩失败"
    end
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, L["编码失败"] or "编码失败"
    end
    return IO_PREFIX .. encoded, nil
end

local function DecodeScreenReminderConfig(text)
    if not (LibSerialize and LibDeflate) then
        return nil, L["通信库未加载"] or "通信库未加载"
    end
    local raw = Trim(text)
    if raw == "" then
        return nil, L["导入数据为空"] or "导入数据为空"
    end
    local encoded = raw:match("^" .. IO_PREFIX:gsub("([^%w])", "%%%1") .. "(.+)$")
    if not encoded then
        return nil, L["SR_IMPORT_PREFIX_HINT"] or "请粘贴 STT:SR:1: 开头的屏幕提醒配置"
    end
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then
        return nil, L["数据损坏：解码失败"] or "数据损坏：解码失败"
    end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, L["数据损坏：解压失败"] or "数据损坏：解压失败"
    end
    local ok, payload = LibSerialize:Deserialize(decompressed)
    if ok ~= true or type(payload) ~= "table" then
        return nil, L["数据损坏：反序列化失败"] or "数据损坏：反序列化失败"
    end
    if payload._format ~= IO_FORMAT or type(payload.screenReminder) ~= "table" then
        return nil, L["数据格式无效"] or "数据格式无效"
    end
    return payload, nil
end

local function CountIndicators(payload)
    local root = payload and payload.screenReminder
    return type(root and root.indicators) == "table" and #root.indicators or 0
end

local function RefreshImportedConfig(stats)
    if T.ScreenReminder then
        if T.ScreenReminder.ClearAll then
            T.ScreenReminder:ClearAll()
        end
        if T.ScreenReminder.CleanupOrphans then
            T.ScreenReminder:CleanupOrphans()
        end
    end
    OptionsPanel:RefreshAll()
    if T.ScreenReminder and T.ScreenReminder.SyncIndicator and type(stats and stats.touchedIDs) == "table" then
        for _, id in ipairs(stats.touchedIDs) do
            T.ScreenReminder:SyncIndicator(id)
        end
    end
end

local function SetIODialogSummary(line1, line2, isError)
    if not ioDialog then
        return
    end
    ioDialog.summaryLine1:SetText(line1 or "")
    ioDialog.summaryLine2:SetText(line2 or "")
    local r, g, b = 0.85, 0.82, 0.62
    if isError then
        r, g, b = 1, 0.35, 0.35
    end
    ioDialog.summaryLine1:SetTextColor(r, g, b, 1)
    ioDialog.summaryLine2:SetTextColor(r, g, b, 1)
end

local function ApplyScreenReminderConfigImport(mode)
    if not (ioDialog and ioDialog.editBox and Schema.ApplyImportPayload) then
        return
    end
    local payload, err = DecodeScreenReminderConfig(ioDialog.editBox:GetText())
    if not payload then
        SetIODialogSummary(L["导入失败"] or "导入失败", tostring(err or ""), true)
        return
    end
    local stats = Schema.ApplyImportPayload(payload.screenReminder, mode)
    if not stats then
        SetIODialogSummary(L["导入失败"] or "导入失败", L["数据格式无效"] or "数据格式无效", true)
        return
    end
    RefreshImportedConfig(stats)
    local message = string.format(L["SR_IMPORT_DONE"] or "屏幕提醒导入完成：新增 %d，替换 %d，重命名 %d。",
        tonumber(stats.added) or 0,
        tonumber(stats.replaced) or 0,
        tonumber(stats.renamed) or 0)
    SetIODialogSummary(L["导入成功"] or "导入成功", message, false)
    T.msg(message)
end

local function RefreshIOImportPreview()
    if not (ioDialog and ioDialog.mode == "import") then
        return
    end
    local text = Trim(ioDialog.editBox:GetText())
    if text == "" then
        SetIODialogSummary(
            L["尚未粘贴导入字符串"] or "尚未粘贴导入字符串",
            L["SR_IMPORT_PREFIX_HINT"] or "请粘贴 STT:SR:1: 开头的屏幕提醒配置",
            false)
        ioDialog.primaryButton:Disable()
        ioDialog.secondaryButton:Disable()
        return
    end
    local payload, err = DecodeScreenReminderConfig(text)
    if not payload then
        SetIODialogSummary(L["导入预览失败"] or "导入预览失败", tostring(err or ""), true)
        ioDialog.primaryButton:Disable()
        ioDialog.secondaryButton:Disable()
        return
    end
    local line1 = string.format("%s: %s | %s: %s",
        L["类型"] or "类型",
        L["SR_CONFIG_TYPE"] or "屏幕提醒配置",
        L["导出者"] or "导出者",
        tostring(payload._exporterName or ""))
    local line2 = string.format("%s: %d | %s: %s",
        L["SR_INDICATOR_COUNT"] or "指示器数量",
        CountIndicators(payload),
        L["版本"] or "版本",
        tostring(payload._exporterVersion or ""))
    SetIODialogSummary(line1, line2, false)
    ioDialog.primaryButton:Enable()
    ioDialog.secondaryButton:Enable()
end

local function ScheduleIOPreviewRefresh()
    ioPreviewToken = ioPreviewToken + 1
    local token = ioPreviewToken
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if token == ioPreviewToken then
                RefreshIOImportPreview()
            end
        end)
    else
        RefreshIOImportPreview()
    end
end

local function EnsureIODialog()
    if ioDialog then
        return ioDialog
    end
    ioDialog = T.CreatePopupWindow(nil, {
        name = (T.addon_name or "STT") .. "_ScreenReminderConfigIODialog",
        width = 680,
        height = 460,
        strata = "DIALOG",
        alpha = 0.92,
        title = "",
    })
    ioDialog.title:ClearAllPoints()
    ioDialog.title:SetPoint("TOP", 0, -10)
    ioDialog.title:SetFontObject(GameFontNormalLarge)

    local editor = T.NoteEditor and T.NoteEditor.CreateSimpleEditor and T.NoteEditor:CreateSimpleEditor(ioDialog)
    if editor then
        editor:SetPoint("TOPLEFT", ioDialog, "TOPLEFT", 12, -42)
        editor:SetPoint("BOTTOMRIGHT", ioDialog, "BOTTOMRIGHT", -12, 92)
        ioDialog.editor = editor
        ioDialog.editBox = editor.editBox
    end

    ioDialog.summaryLine1 = ioDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ioDialog.summaryLine1:SetPoint("BOTTOMLEFT", ioDialog, "BOTTOMLEFT", 16, 56)
    ioDialog.summaryLine1:SetPoint("BOTTOMRIGHT", ioDialog, "BOTTOMRIGHT", -16, 56)
    ioDialog.summaryLine1:SetJustifyH("LEFT")

    ioDialog.summaryLine2 = ioDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ioDialog.summaryLine2:SetPoint("TOPLEFT", ioDialog.summaryLine1, "BOTTOMLEFT", 0, -4)
    ioDialog.summaryLine2:SetPoint("TOPRIGHT", ioDialog.summaryLine1, "BOTTOMRIGHT", 0, -4)
    ioDialog.summaryLine2:SetJustifyH("LEFT")

    ioDialog.primaryButton = T.CreateButton(ioDialog, {
        width = 120,
        height = 26,
        point = { "BOTTOM", ioDialog, "BOTTOM", -68, 16 },
    })
    ioDialog.secondaryButton = T.CreateButton(ioDialog, {
        width = 120,
        height = 26,
        point = { "LEFT", ioDialog.primaryButton, "RIGHT", 16, 0 },
    })

    ioDialog.primaryButton:SetScript("OnClick", function()
        if ioDialog.mode == "export" then
            if ioDialog.editBox then
                ioDialog.editBox:SetFocus()
                ioDialog.editBox:HighlightText()
            end
            T.msg(L["已复制，若未生效请手动全选复制"] or "已复制，若未生效请手动全选复制")
            return
        end
        ApplyScreenReminderConfigImport("merge")
    end)

    ioDialog.secondaryButton:SetScript("OnClick", function()
        if ioDialog.mode == "import" then
            ApplyScreenReminderConfigImport("replace")
            return
        end
        ioDialog:Hide()
    end)

    if ioDialog.editBox then
        ioDialog.editBox:SetScript("OnTextChanged", function(_, userInput)
            if ioDialog.mode == "import" and userInput then
                ScheduleIOPreviewRefresh()
            end
        end)
        ioDialog.editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            ioDialog:Hide()
        end)
    end

    return ioDialog
end

local function ShowScreenReminderExport()
    local frame = EnsureIODialog()
    if not (frame and frame.editBox) then
        return
    end
    local text, err = EncodeScreenReminderConfig()
    frame.mode = "export"
    frame.title:SetText(L["SR_EXPORT_CONFIG"] or "导出屏幕提醒配置")
    frame.primaryButton:SetText(L["全选复制"] or "全选复制")
    frame.secondaryButton:SetText(CLOSE or "关闭")
    frame.primaryButton:Enable()
    frame.secondaryButton:Enable()
    frame:Show()
    if not text then
        frame.editBox:SetText("")
        SetIODialogSummary(L["导出失败"] or "导出失败", tostring(err or ""), true)
        frame.primaryButton:Disable()
        return
    end
    frame.editBox:SetText(text)
    SetIODialogSummary(
        L["SR_CONFIG_TYPE"] or "屏幕提醒配置",
        string.format("%s: %d | %s: %d",
            L["SR_INDICATOR_COUNT"] or "指示器数量",
            #(Schema.GetRoot().indicators or {}),
            L["字符串长度"] or "字符串长度",
            #text),
        false)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if ioDialog and ioDialog:IsShown() and ioDialog.mode == "export" then
                ioDialog.editBox:SetFocus()
                ioDialog.editBox:HighlightText()
            end
        end)
    end
end

local function ShowScreenReminderImport()
    local frame = EnsureIODialog()
    if not (frame and frame.editBox) then
        return
    end
    frame.mode = "import"
    frame.title:SetText(L["SR_IMPORT_CONFIG"] or "导入屏幕提醒配置")
    frame.primaryButton:SetText(L["合并导入"] or "合并导入")
    frame.secondaryButton:SetText(L["替换导入"] or "替换导入")
    frame.primaryButton:Disable()
    frame.secondaryButton:Disable()
    frame:Show()
    frame.editBox:SetText("")
    frame.editBox:SetFocus()
    if frame.editor and frame.editor.placeholder then
        frame.editor.placeholder:SetText(L["SR_IMPORT_PREFIX_HINT"] or "请粘贴 STT:SR:1: 开头的屏幕提醒配置")
        frame.editor.placeholder:Show()
    end
    RefreshIOImportPreview()
end

local function CreateGlobalLeadRow(parent, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, GLOBAL_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(PREVIEW_HEIGHT + 4))
    AttachTooltip(row, L["SR_GLOBAL_LEAD_TOOLTIP"] or "大部分屏幕提醒的默认提前显示时间。未写 {sr:N} 的文本会按这里显示，默认 3 秒。")

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", row, "LEFT", 4, 0)
    label:SetWidth(120)
    label:SetJustifyH("LEFT")
    label:SetText(L["SR_GLOBAL_LEAD_TIME"] or "全局提前量")
    label:SetTextColor(1, 0.86, 0.32, 1)

    local valueFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    valueFS:SetWidth(56)
    valueFS:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", row, "LEFT", 132, 0)
    slider:SetPoint("RIGHT", valueFS, "LEFT", -8, 0)
    slider:Init(Schema.GetGlobalLeadTime(), 0, 10, 20, {})
    if slider.SetTooltipText then slider:SetTooltipText("") end
    AttachTooltip(slider, L["SR_GLOBAL_LEAD_TOOLTIP"] or "大部分屏幕提醒的默认提前显示时间。未写 {sr:N} 的文本会按这里显示，默认 3 秒。")

    local function refresh()
        row.refreshing = true
        local value = Schema.GetGlobalLeadTime()
        slider:SetValue(value)
        valueFS:SetText(string.format("%.1fs", value))
        row.refreshing = false
    end

    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if row.refreshing then return end
        local lead = math.floor(((tonumber(value) or 0) * 2) + 0.5) / 2
        Schema.SetGlobalLeadTime(lead)
        valueFS:SetText(string.format("%.1fs", Schema.GetGlobalLeadTime()))
        if Preview and Preview.Refresh then
            Preview:Refresh()
        end
    end)

    row.refresh = refresh
    refresh()
    return row
end

function OptionsPanel:Render(slot, ctx)
    local width = ctx and ctx.width or 540
    slot:SetHeight(PANEL_HEIGHT)
    self.frame = slot

    -- 预览区
    Preview:Create(slot, {
        width = width,
        height = PREVIEW_HEIGHT,
        point = { "TOPLEFT", slot, "TOPLEFT", 0, 0 },
    })

    slot.globalLeadRow = CreateGlobalLeadRow(slot, width)

    -- 列表 / 配置容器（共享高度）
    local mainHeight = PANEL_HEIGHT - PREVIEW_HEIGHT - GLOBAL_ROW_HEIGHT - BOTTOM_BUTTONS_HEIGHT - 18
    local listWidth = math.floor((width - COL_GAP) / 3)
    local configWidth = width - listWidth - COL_GAP

    PanelList:Create(slot, {
        width = listWidth,
        height = mainHeight,
        point = { "TOPLEFT", slot, "TOPLEFT", 0, -(PREVIEW_HEIGHT + GLOBAL_ROW_HEIGHT + 8) },
    })
    PanelConfig:Create(slot, {
        width = configWidth,
        height = mainHeight,
        point = { "TOPLEFT", slot, "TOPLEFT", listWidth + COL_GAP, -(PREVIEW_HEIGHT + GLOBAL_ROW_HEIGHT + 8) },
    })

    -- 底部按钮（直接锚到 slot 底部，确保始终可见）
    local btnUnlock = T.CreateActionButton(slot, {
        width = BOTTOM_BUTTON_WIDTH, height = 24,
        point = { "BOTTOMLEFT", slot, "BOTTOMLEFT", 2, 2 },
        textFn = function()
            return L["SR_BTN_UNLOCK"] or "解锁锚点"
        end,
        onClick = function()
            local session = T.ScreenReminderEditSession
            if session and session.Enter then
                session:Enter()
            else
                T.ScreenReminder:SetLocked(false)
            end
        end,
    })
    local btnTest = T.CreateActionButton(slot, {
        width = BOTTOM_BUTTON_WIDTH, height = 24,
        point = { "LEFT", btnUnlock, "RIGHT", BOTTOM_BUTTON_GAP, 0 },
        textFn = function() return L["SR_BTN_TEST"] or "测试" end,
        onClick = function()
            T.ScreenReminder:RunTest()
        end,
    })
    local btnImport = T.CreateActionButton(slot, {
        width = BOTTOM_BUTTON_WIDTH, height = 24,
        point = { "LEFT", btnTest, "RIGHT", BOTTOM_BUTTON_GAP, 0 },
        textFn = function() return L["SR_BTN_IMPORT_CONFIG"] or "导入配置" end,
        onClick = function()
            ShowScreenReminderImport()
        end,
    })
    local btnExport = T.CreateActionButton(slot, {
        width = BOTTOM_BUTTON_WIDTH, height = 24,
        point = { "LEFT", btnImport, "RIGHT", BOTTOM_BUTTON_GAP, 0 },
        textFn = function() return L["SR_BTN_EXPORT_CONFIG"] or "导出配置" end,
        onClick = function()
            ShowScreenReminderExport()
        end,
    })
    T.CreateActionButton(slot, {
        width = BOTTOM_BUTTON_WIDTH, height = 24,
        point = { "LEFT", btnExport, "RIGHT", BOTTOM_BUTTON_GAP, 0 },
        textFn = function() return L["SR_BTN_RESET_PUSH_IGNORE"] or "重置下发黑名单" end,
        onClick = function()
            if T.OptionShare and T.OptionShare.ResetIgnored then
                T.OptionShare:ResetIgnored()
            else
                T.msg("设置下发模块未加载")
            end
        end,
    })

    -- 协调：列表/配置/预览的事件钩子
    PanelList.onSelected = function(_, id)
        Schema.SetSelectedIndicator(id)
        PanelConfig:Refresh()
        Preview:OnIndicatorSelected(id)
    end
    PanelList.onPushClick = function(_, id)
        if T.ScreenReminderOptionPush and T.ScreenReminderOptionPush.SendIndicator then
            T.ScreenReminderOptionPush.SendIndicator(id)
        end
    end
    PanelList.onNewClick = function()
        PanelList:OpenKindMenu()
    end
    PanelList.onPickKind = function(_, kind)
        local ind = Schema.CreateIndicator(kind)
        PanelList:Refresh()
        PanelConfig:Refresh()
        Preview:OnIndicatorSelected(ind.id)
    end
    PanelList.onCloneClick = function()
        local id = Schema.GetRoot().selectedIndicatorID
        if id then
            local copy = Schema.CloneIndicator(id)
            PanelList:Refresh()
            PanelConfig:Refresh()
            if copy then Preview:OnIndicatorSelected(copy.id) end
        end
    end
    PanelList.onDeleteClick = function()
        local id = Schema.GetRoot().selectedIndicatorID
        if id then
            local nextInd = Schema.DeleteIndicator(id)
            if T.ScreenReminder and T.ScreenReminder.CleanupOrphans then
                T.ScreenReminder:CleanupOrphans()
            end
            PanelList:Refresh()
            PanelConfig:Refresh()
            if nextInd then Preview:OnIndicatorSelected(nextInd.id) end
        end
    end
    PanelList.onChanged = function()
        PanelList:Refresh()
    end
    PanelConfig.onChanged = function()
        Preview:Refresh()
        PanelList:Refresh()  -- name / enabled / kind 改变时刷新列表
        -- 同步当前选中 indicator 的活动实例（位置/字号/颜色等实时反映在屏幕上的预览实例）
        local root = Schema.GetRoot()
        if root.selectedIndicatorID and T.ScreenReminder and T.ScreenReminder.SyncIndicator then
            T.ScreenReminder:SyncIndicator(root.selectedIndicatorID)
        end
    end

    T.ScreenReminder:SetOnAnchorChanged(function(_)
        PanelConfig:Refresh()
        Preview:Refresh()
    end)
    T.ScreenReminder:SetOnAnchorClicked(function(id, anchorFrame)
        local session = T.ScreenReminderEditSession
        if session and session.OnAnchorClicked then
            session:OnAnchorClicked(id, anchorFrame)
        end
    end)

    OptionsPanel:RefreshAll()

    return {
        height = PANEL_HEIGHT,
        refresh = function()
            OptionsPanel:RefreshAll()
        end,
        setEnabled = function() end,
    }
end

function OptionsPanel:RefreshAll()
    if self.frame and self.frame.globalLeadRow and self.frame.globalLeadRow.refresh then
        self.frame.globalLeadRow:refresh()
    end
    if PanelList.Refresh then PanelList:Refresh() end
    if PanelConfig.Refresh then PanelConfig:Refresh() end
    local sel = Schema.GetSelectedIndicator()
    if Preview and Preview.OnIndicatorSelected and sel then
        Preview:OnIndicatorSelected(sel.id)
    end
end

end)
