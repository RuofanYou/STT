local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("buffCheck.enabled", function()

local BuffCheck = T.BuffCheck
local UI = BuffCheck.UI or {}
BuffCheck.UI = UI

local COLORS = {
    title = { 0.93, 0.88, 0.72, 1 },
    accent = { 1, 0.86, 0.32, 1 },
    text = { 0.88, 0.88, 0.88, 1 },
    muted = { 0.58, 0.58, 0.58, 1 },
    ok = { 0.34, 0.82, 0.44, 1 },
    warn = { 1.0, 0.82, 0.25, 1 },
    miss = { 0.95, 0.28, 0.26, 1 },
    unknown = { 0.62, 0.62, 0.62, 1 },
    row = { 0.13, 0.09, 0.09, 0.72 },
    rowAlt = { 0.17, 0.12, 0.12, 0.72 },
    header = { 0.14, 0.11, 0.08, 0.96 },
    summary = { 0.19, 0.14, 0.06, 0.96 },
}

local PANEL_STRATA = "DIALOG"
local PANEL_LEVEL = 126
local DEFAULT_ICON = 134400
local DURABILITY_ICON = "Interface\\MINIMAP\\TRACKING\\Repair"

local PERSONAL_ROW_HEIGHT = 34
local RAID_ROW_HEIGHT = 34
local RAID_NAME_WIDTH = 188
local RAID_CELL_SIZE = 22
local RAID_CELL_STEP = 34

local personalPanel
local raidPanel
local repairReminderToast

local RAID_COLUMNS = {
    { key = "food", spellID = 396092, labelKey = "GUI_BUFF_CHECK_FOOD" },
    { key = "flask", spellID = 1236763, labelKey = "GUI_BUFF_CHECK_FLASK" },
    { key = "rune", spellID = 1264426, labelKey = "GUI_BUFF_CHECK_RUNE" },
    { key = "vantus", spellID = 384233, labelKey = "GUI_BUFF_CHECK_VANTUS" },
    { key = "weaponEnchantMain", spellID = 33757, labelKey = "GUI_BUFF_CHECK_WEAPON_ENCHANT" },
    { key = "durability", texture = DURABILITY_ICON, labelKey = "GUI_BUFF_CHECK_DURABILITY" },
    { key = "ap", spellID = 6673, labelKey = "GUI_BUFF_RAIDBUFF_AP" },
    { key = "stamina", spellID = 21562, labelKey = "GUI_BUFF_RAIDBUFF_STAMINA" },
    { key = "intellect", spellID = 1459, labelKey = "GUI_BUFF_RAIDBUFF_INTELLECT" },
    { key = "versatility", spellID = 1126, labelKey = "GUI_BUFF_RAIDBUFF_VERSATILITY" },
    { key = "mastery", spellID = 462854, labelKey = "GUI_BUFF_RAIDBUFF_MASTERY" },
    { key = "movement", spellID = 381748, labelKey = "GUI_BUFF_RAIDBUFF_MOVEMENT" },
}

local function DB()
    C.DB.buffCheck = C.DB.buffCheck or {}
    C.DB.buffCheck.ui = C.DB.buffCheck.ui or {}
    C.DB.buffCheck.ui.panels = C.DB.buffCheck.ui.panels or {}
    return C.DB.buffCheck
end

local function SavePanelPosition(frame, panelKey)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    local panels = DB().ui.panels
    panels[panelKey] = panels[panelKey] or {}
    panels[panelKey].position = { point = point or "CENTER", relPoint = relPoint or "CENTER", x = x or 0, y = y or 100 }
    if T.OptionEngine and T.OptionEngine.SetValue then
        T.OptionEngine:SetValue("buffCheck.ui.panels." .. panelKey .. ".position", panels[panelKey].position)
    end
end

local function RestorePanelPosition(frame, panelKey)
    local panelDB = DB().ui.panels[panelKey] or {}
    local pos = panelDB.position or { point = "CENTER", relPoint = "CENTER", x = 0, y = 100 }
    frame:ClearAllPoints()
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or pos.point or "CENTER", tonumber(pos.x) or 0, tonumber(pos.y) or 100)
end

local function RaisePanel(frame)
    if not frame then
        return
    end
    frame:SetFrameStrata(PANEL_STRATA)
    frame:SetFrameLevel(PANEL_LEVEL)
    frame:SetToplevel(true)
    frame:Raise()
end

local function GetTexture(spellID, texture)
    if texture then
        return texture
    end
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and icon then
            return icon
        end
    end
    if spellID and GetSpellTexture then
        local ok, icon = pcall(GetSpellTexture, spellID)
        if ok and icon then
            return icon
        end
    end
    return DEFAULT_ICON
end

local function GetMetaIcon(meta)
    if not meta then
        return DEFAULT_ICON
    end
    return GetTexture(meta.spellID, meta.icon or meta.texture)
end

local function CreateTitleBar(frame, titleText, closeFunc)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    bar:SetHeight(28)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.2)
    T.CreateFontString(bar, {
        point = { "LEFT", bar, "LEFT", 12, 0 },
        text = titleText,
        size = 14,
        flags = "OUTLINE",
        color = COLORS.accent,
    })
    local close = T.CreateButton(bar, { width = 28, height = 22, point = { "RIGHT", bar, "RIGHT", -5, 0 }, text = "X" })
    close:SetScript("OnClick", closeFunc)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePanelPosition(frame, frame.__sttBuffCheckPanelKey)
    end)
    return bar
end

local function CreateIntegratedStrip(parent, height, color)
    local strip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    strip:SetHeight(height)
    T.ApplyBackdrop(strip, {
        bg = color,
        border = { 0.55, 0.43, 0.13, 0.85 },
    })
    return strip
end

local function CreateEmptyState(parent)
    local empty = CreateFrame("Frame", nil, parent)
    empty.icon = empty:CreateTexture(nil, "ARTWORK")
    empty.icon:SetSize(60, 60)
    empty.icon:SetPoint("TOP", empty, "TOP", 0, -18)
    empty.icon:SetAtlas("ReadyCheck-Waiting")
    empty.title = T.CreateFontString(empty, {
        point = { "TOP", empty.icon, "BOTTOM", 0, -12 },
        size = 24,
        flags = "OUTLINE",
        color = COLORS.accent,
        justifyH = "CENTER",
        text = "",
    })
    empty.subtitle = T.CreateFontString(empty, {
        point = { "TOP", empty.title, "BOTTOM", 0, -10 },
        size = 13,
        flags = "OUTLINE",
        color = COLORS.title,
        justifyH = "CENTER",
        text = "",
    })
    return empty
end

local function CreateLoadingState(parent)
    local loading = CreateFrame("Frame", nil, parent)
    loading.icon = loading:CreateTexture(nil, "ARTWORK")
    loading.icon:SetSize(48, 48)
    loading.icon:SetPoint("CENTER", loading, "CENTER", 0, 10)
    loading.icon:SetAtlas("ReadyCheck-Waiting")
    loading.text = T.CreateFontString(loading, {
        point = { "TOP", loading.icon, "BOTTOM", 0, -12 },
        size = 14,
        flags = "OUTLINE",
        color = COLORS.muted,
        justifyH = "CENTER",
        text = L["BUFF_LOADING"] or "正在扫描全团...",
    })
    return loading
end

local function FadeFrame(frame, fromAlpha, toAlpha, duration, onDone)
    if not frame then
        return
    end
    local elapsed = 0
    frame:SetAlpha(fromAlpha)
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local progress = duration > 0 and math.min(1, elapsed / duration) or 1
        self:SetAlpha(fromAlpha + (toAlpha - fromAlpha) * progress)
        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            if onDone then
                onDone(self)
            end
        end
    end)
end

local function GetInventorySlotText(slotID)
    if not slotID then
        return L["BUFF_REPAIR_REMINDER_SLOT_UNKNOWN"] or "未知槽位"
    end
    if GetInventoryItemLink then
        local link = GetInventoryItemLink("player", slotID)
        if link then
            return link
        end
    end
    return string.format(L["BUFF_REPAIR_REMINDER_SLOT_FALLBACK"] or "装备槽 %d", slotID)
end

local function EnsureRepairReminderToast()
    if repairReminderToast then
        return repairReminderToast
    end
    local frame = CreateFrame("Frame", "STTRepairReminderToast", UIParent, "BackdropTemplate")
    frame:SetSize(292, 50)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -128)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(130)
    frame:EnableMouse(true)
    T.ApplyBackdrop(frame, {
        bg = { 0.08, 0.06, 0.04, 0.94 },
        border = { 0.55, 0.43, 0.13, 0.9 },
    })

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(30, 30)
    frame.icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
    frame.icon:SetTexture(DURABILITY_ICON)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.title = T.CreateFontString(frame, {
        point = { "LEFT", frame.icon, "RIGHT", 10, 8 },
        size = 13,
        flags = "OUTLINE",
        color = COLORS.title,
        text = "",
    })
    frame.detail = T.CreateFontString(frame, {
        point = { "LEFT", frame.icon, "RIGHT", 10, -10 },
        size = 11,
        flags = "OUTLINE",
        color = COLORS.muted,
        text = "",
    })
    frame.percent = T.CreateFontString(frame, {
        point = { "RIGHT", frame, "RIGHT", -12, 0 },
        size = 18,
        flags = "OUTLINE",
        color = COLORS.warn,
        justifyH = "RIGHT",
        text = "",
    })
    frame:SetScript("OnEnter", function(self)
        local data = self.__repairData
        if not data then
            return
        end
        local lines = {
            string.format(L["BUFF_REPAIR_REMINDER_THRESHOLD_HINT"] or "提醒阈值：低于 %d%%", data.threshold or 25),
            GetInventorySlotText(data.minSlot),
        }
        if data.minCurrent and data.minMaximum then
            lines[#lines + 1] = string.format(L["BUFF_REPAIR_REMINDER_DURABILITY_HINT"] or "当前耐久：%d / %d", data.minCurrent, data.minMaximum)
        end
        if data.criticalThreshold then
            lines[#lines + 1] = string.format(L["BUFF_REPAIR_REMINDER_CRITICAL_HINT"] or "严重阈值：%d%%", data.criticalThreshold)
        end
        if T.UITooltip then
            T.UITooltip.Show(self, {
                title = self.title:GetText() or "",
                description = table.concat(lines, "\n"),
            }, { anchor = "ANCHOR_RIGHT", x = -18, y = 8 })
        end
    end)
    frame:SetScript("OnLeave", function()
        if T.UITooltip then
            T.UITooltip.ScheduleHide()
        end
    end)
    frame:Hide()
    repairReminderToast = frame
    return frame
end

function UI:ShowRepairReminder(data)
    if type(data) ~= "table" then
        return
    end
    local frame = EnsureRepairReminderToast()
    local pct = tonumber(data.percent) or 0
    local color = data.critical and COLORS.miss or COLORS.warn
    local title = L["BUFF_REPAIR_REMINDER_LOW"] or "装备耐久偏低"
    local detail = string.format(L["BUFF_REPAIR_REMINDER_DETAIL"] or "最低耐久低于 %d%%", data.threshold or 25)

    frame.__repairData = data
    frame.title:SetText(title)
    frame.detail:SetText(detail)
    frame.percent:SetText(string.format("%d%%", pct))
    frame.percent:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(color[1], color[2], color[3], 0.9)
    end

    frame.__hideToken = (frame.__hideToken or 0) + 1
    local token = frame.__hideToken
    frame:Show()
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(130)
    FadeFrame(frame, 0, 1, 0.18)
    C_Timer.After(tonumber(data.durationSec) or 5, function()
        if repairReminderToast ~= frame or frame.__hideToken ~= token or not frame:IsShown() then
            return
        end
        FadeFrame(frame, frame:GetAlpha() or 1, 0, 0.3, function(self)
            self:Hide()
            self:SetAlpha(1)
        end)
    end)
end

function UI:HideRepairReminder()
    if repairReminderToast then
        repairReminderToast.__hideToken = (repairReminderToast.__hideToken or 0) + 1
        repairReminderToast:SetScript("OnUpdate", nil)
        repairReminderToast:Hide()
        repairReminderToast:SetAlpha(1)
    end
end

local function SetTooltip(frame, result)
    frame:SetScript("OnEnter", function(self)
        if self.hover then
            self.hover:Show()
        end
        local labels = BuffCheck:GetMissingLabels(result)
        local lines = {}
        if #labels == 0 then
            lines[#lines + 1] = L["BUFF_TOOLTIP_ALL_OK"] or "所有启用维度均已齐备"
        else
            lines[#lines + 1] = (L["BUFF_PERSONAL_HINT"] or "缺少：") .. table.concat(labels, "、")
        end
        local durabilityState, durabilityPct = BuffCheck:GetDurabilityState(result)
        if durabilityState == "unknown" then
            lines[#lines + 1] = L["BUFF_DURABILITY_UNKNOWN_HINT"] or "耐久未上报"
        elseif durabilityState == "low" and durabilityPct then
            lines[#lines + 1] = string.format(L["BUFF_DURABILITY_LOW_HINT"] or "最低耐久 %d%%", durabilityPct)
        end
        if T.UITooltip then
            T.UITooltip.Show(self, {
                title = result.shortName or result.unitName or "",
                description = table.concat(lines, "\n"),
            }, { anchor = "ANCHOR_RIGHT", x = -18, y = 8 })
        end
    end)
    frame:SetScript("OnLeave", function(self)
        if self.hover then
            self.hover:Hide()
        end
        if T.UITooltip then
            T.UITooltip.ScheduleHide()
        end
    end)
end

local function CreateHeaderIcon(parent, iconTexture, tooltipText)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(26, 26)
    T.ApplyBackdrop(holder, {
        bg = { 0.09, 0.09, 0.09, 0.9 },
        border = { 0.42, 0.34, 0.14, 0.9 },
    })
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", holder, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(iconTexture or DEFAULT_ICON)
    if tooltipText and tooltipText ~= "" then
        holder:EnableMouse(true)
        if T.UITooltip then
            T.UITooltip.AttachSimple(holder, tooltipText, { anchor = "ANCHOR_TOP", x = 0, y = 0 })
        end
    end
    return holder
end

local function CreateRaidCell(parent)
    local cell = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    cell:SetSize(RAID_CELL_SIZE, RAID_CELL_SIZE)
    T.ApplyBackdrop(cell, {
        bg = { 0.08, 0.08, 0.08, 0.85 },
        border = { 0.24, 0.24, 0.24, 0.9 },
    })
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
    cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cell.badge = T.CreateFontString(cell, {
        point = { "TOPRIGHT", cell, "TOPRIGHT", -1, -1 },
        size = 11,
        flags = "OUTLINE",
        color = COLORS.accent,
        text = "",
    })
    cell.value = T.CreateFontString(cell, {
        point = { "CENTER", cell, "CENTER", 0, 0 },
        size = 10,
        flags = "OUTLINE",
        color = COLORS.title,
        text = "",
    })
    function cell:SetState(iconTexture, state, valueText)
        self.icon:SetTexture(iconTexture or DEFAULT_ICON)
        self.badge:SetText("")
        self.value:SetText(valueText or "")
        self.icon:SetDesaturated(false)
        self.icon:SetAlpha(1)
        self.icon:SetVertexColor(1, 1, 1, 1)
        if state == "ok" then
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.23, 0.46, 0.24, 0.95)
            end
            if self.SetBackdropColor then
                self:SetBackdropColor(0.06, 0.11, 0.06, 0.9)
            end
            self.value:SetTextColor(0.86, 0.95, 0.86, 1)
        elseif state == "miss" then
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.88, 0.24, 0.21, 0.95)
            end
            if self.SetBackdropColor then
                self:SetBackdropColor(0.24, 0.06, 0.06, 0.92)
            end
            self.icon:SetVertexColor(1, 0.86, 0.86, 1)
            self.badge:SetText("!")
            self.badge:SetTextColor(1, 0.85, 0.2, 1)
            self.value:SetTextColor(1, 0.92, 0.92, 1)
        elseif state == "unknown" then
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.42, 0.42, 0.42, 0.95)
            end
            if self.SetBackdropColor then
                self:SetBackdropColor(0.11, 0.11, 0.11, 0.88)
            end
            self.icon:SetDesaturated(true)
            self.icon:SetAlpha(0.42)
            self.badge:SetText("·")
            self.badge:SetTextColor(0.75, 0.75, 0.75, 1)
            self.value:SetTextColor(0.74, 0.74, 0.74, 1)
        else
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.24, 0.24, 0.24, 0.8)
            end
            if self.SetBackdropColor then
                self:SetBackdropColor(0.06, 0.06, 0.06, 0.7)
            end
            self.icon:SetDesaturated(true)
            self.icon:SetAlpha(0.16)
            self.value:SetTextColor(0.45, 0.45, 0.45, 1)
        end
    end
    cell:SetState(DEFAULT_ICON, "disabled", "")
    return cell
end

local function GetColumnIcon(result, key)
    if key == "food" then
        return (result.food and result.food.icon) or GetTexture(396092)
    end
    if key == "flask" then
        return (result.flask and result.flask.icon) or GetTexture(1236763)
    end
    if key == "rune" then
        return (result.rune and result.rune.icon) or GetTexture(1264426)
    end
    if key == "vantus" then
        return (result.vantus and result.vantus.icon) or GetTexture(384233)
    end
    for _, column in ipairs(RAID_COLUMNS) do
        if column.key == key then
            return GetMetaIcon(column)
        end
    end
    return DEFAULT_ICON
end

local function GetCellState(result, missing, key)
    if missing.unavailable == true then
        return "disabled", nil
    end
    if key == "weaponEnchantMain" and result.weaponEnchant and result.weaponEnchant.unavailable then
        return "disabled", nil
    end
    if key == "durability" then
        local durabilityState, pct = BuffCheck:GetDurabilityState(result)
        if durabilityState == "ok" then
            return "ok", pct and (tostring(pct) .. "%") or nil
        end
        if durabilityState == "low" then
            return "miss", pct and (tostring(pct) .. "%") or nil
        end
        if durabilityState == "unknown" then
            return "unknown", nil
        end
        return "disabled", nil
    end
    if missing[key] then
        return "miss", nil
    end
    return "ok", nil
end

local function GetFirstResult()
    for _, result in pairs(BuffCheck.state.results or {}) do
        return result
    end
    return nil
end

local function EnsurePersonalPanel()
    if personalPanel then
        return personalPanel
    end
    local frame = CreateFrame("Frame", "STTBuffCheckPersonalPanel", UIParent, "BackdropTemplate")
    frame:SetSize(392, 382)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame.__sttBuffCheckPanelKey = "personal"
    T.ApplyBackdrop(frame, { style = "chat" })
    CreateTitleBar(frame, L["BUFF_PERSONAL_TITLE"] or "STT · 消耗品自检", function() frame:Hide() end)

    frame.summary = CreateIntegratedStrip(frame, 44, COLORS.summary)
    frame.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    frame.summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -36)
    frame.summary.text = T.CreateFontString(frame.summary, {
        point = { "CENTER", frame.summary, "CENTER", 0, 0 },
        size = 17,
        flags = "OUTLINE",
        color = COLORS.accent,
        justifyH = "CENTER",
        text = "",
    })

    frame.empty = CreateEmptyState(frame)
    frame.empty:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -12)
    frame.empty:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -12)
    frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 16)
    frame.content.rows = {}

    RestorePanelPosition(frame, "personal")
    frame:HookScript("OnShow", RaisePanel)
    frame:Hide()
    personalPanel = frame
    return frame
end

local function AcquirePersonalRow(frame, index)
    local row = frame.content.rows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, frame.content, "BackdropTemplate")
    row:SetHeight(PERSONAL_ROW_HEIGHT)
    T.ApplyBackdrop(row, {
        bg = { 0.08, 0.08, 0.08, 0.65 },
        border = { 0.18, 0.18, 0.18, 0.65 },
    })
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.label = T.CreateFontString(row, {
        point = { "LEFT", row.icon, "RIGHT", 10, 0 },
        size = 13,
        flags = "OUTLINE",
        color = COLORS.title,
        text = "",
    })
    row.status = T.CreateFontString(row, {
        point = { "RIGHT", row, "RIGHT", -10, 0 },
        size = 12,
        flags = "OUTLINE",
        color = COLORS.text,
        text = "",
    })
    frame.content.rows[index] = row
    return row
end

local function RefreshPersonal()
    local frame = EnsurePersonalPanel()
    local result
    if BuffCheck.testMode then
        result = GetFirstResult()
    elseif BuffCheck.ScanSafely then
        result = BuffCheck:ScanSafely("scan_self", function()
            return BuffCheck:ScanSelf()
        end, "personal_refresh")
    else
        result = BuffCheck:ScanSelf()
    end
    result = result or GetFirstResult()
    if type(result) ~= "table" then
        frame.summary.text:SetText(L["BUFF_NO_PERSONAL_DATA"] or "暂无个人数据")
        frame.empty:Show()
        frame.content:Hide()
        frame.empty.title:SetText(L["BUFF_NO_PERSONAL_DATA"] or "暂无个人数据")
        frame.empty.subtitle:SetText(L["BUFF_PANEL_OPEN_FAILED"] or "团队检查面板打开失败，请查看调试日志")
        frame:SetHeight(230)
        if BuffCheck.DebugEvent then
            BuffCheck:DebugEvent("PersonalRenderSkipped", {
                reason = "no_scan_result",
                source = "personal_refresh",
            })
        end
        return
    end

    local missing = BuffCheck:EvaluateMissing(result)
    local checks = (BuffCheck.Data and BuffCheck.Data.PersonalChecks) or {}
    local rowCount = 0

    frame.summary.text:SetText(BuffCheck:BuildSummaryText({ result }, true))
    frame.empty:Hide()
    frame.content:Show()

    for _, row in ipairs(frame.content.rows or {}) do
        row:Hide()
    end

    for _, meta in ipairs(checks) do
        if meta.id ~= "weaponEnchantOff" or (C.DB.buffCheck and C.DB.buffCheck.checks and C.DB.buffCheck.checks.weaponEnchantOff) then
            if meta.checkKey and ((C.DB.buffCheck.checks or {})[meta.checkKey] ~= false) then
                rowCount = rowCount + 1
                local row = AcquirePersonalRow(frame, rowCount)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(rowCount - 1) * (PERSONAL_ROW_HEIGHT + 8))
                row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, -(rowCount - 1) * (PERSONAL_ROW_HEIGHT + 8))
                row.icon:SetTexture(GetMetaIcon(meta))
                row.label:SetText(L[meta.labelKey] or meta.labelKey or meta.id)

                local statusText = L["BUFF_STATUS_OK"] or "已齐备"
                local statusColor = COLORS.ok
                if meta.id == "durability" then
                    local state, pct = BuffCheck:GetDurabilityState(result)
                    if state == "low" then
                        statusText = string.format(L["BUFF_DURABILITY_LOW_HINT"] or "最低耐久 %d%%", pct or 0)
                        statusColor = COLORS.warn
                    elseif state == "unknown" then
                        statusText = L["BUFF_DURABILITY_UNKNOWN_HINT"] or "耐久未上报"
                        statusColor = COLORS.unknown
                    else
                        statusText = pct and string.format("%d%%", pct) or (L["BUFF_STATUS_OK"] or "已齐备")
                    end
                elseif missing[meta.id] then
                    statusText = L[meta.missingKey] or meta.id
                    statusColor = COLORS.miss
                else
                    statusText = L["BUFF_STATUS_OK"] or "已齐备"
                end

                row.status:SetText(statusText)
                row.status:SetTextColor(statusColor[1], statusColor[2], statusColor[3], statusColor[4] or 1)
                SetTooltip(row, result)
                row:Show()
            end
        end
    end

    if rowCount == 0 then
        frame.empty:Show()
        frame.content:Hide()
        frame.empty.title:SetText(L["BUFF_NO_PERSONAL_DATA"] or "暂无个人数据")
        frame.empty.subtitle:SetText(L["BUFF_PANEL_OPEN_FAILED"] or "团队检查面板打开失败，请查看调试日志")
        frame:SetHeight(230)
        return
    end

    frame:SetHeight(math.min(540, 122 + rowCount * (PERSONAL_ROW_HEIGHT + 8)))
end

local function EnsureRaidPanel()
    if raidPanel then
        return raidPanel
    end
    local width = 860
    local frame = CreateFrame("Frame", "STTBuffCheckRaidPanel", UIParent, "BackdropTemplate")
    frame:SetSize(width, 420)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame.__sttBuffCheckPanelKey = "raid"
    T.ApplyBackdrop(frame, { style = "chat" })
    CreateTitleBar(frame, L["BUFF_SUMMARY_TITLE"] or "STT · 团队检查", function() frame:Hide() end)

    frame.summary = CreateIntegratedStrip(frame, 42, COLORS.summary)
    frame.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    frame.summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -36)
    frame.summary.text = T.CreateFontString(frame.summary, {
        point = { "CENTER", frame.summary, "CENTER", 0, 0 },
        size = 17,
        flags = "OUTLINE",
        color = COLORS.accent,
        justifyH = "CENTER",
        text = "",
    })

    frame.headers = CreateIntegratedStrip(frame, 36, COLORS.header)
    frame.headers:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -1)
    frame.headers:SetPoint("TOPRIGHT", frame.summary, "BOTTOMRIGHT", 0, -1)
    frame.headerName = T.CreateFontString(frame.headers, {
        point = { "LEFT", frame.headers, "LEFT", 18, 0 },
        size = 13,
        flags = "OUTLINE",
        color = COLORS.title,
        text = L["BUFF_COL_NAME"] or "名字",
    })
    frame.headerIcons = {}
    for index, column in ipairs(RAID_COLUMNS) do
        local icon = CreateHeaderIcon(frame.headers, GetMetaIcon(column), L[column.labelKey] or column.labelKey or column.key)
        icon:SetPoint("LEFT", frame.headers, "LEFT", RAID_NAME_WIDTH + 24 + (index - 1) * RAID_CELL_STEP, 0)
        frame.headerIcons[column.key] = icon
    end

    frame.empty = CreateEmptyState(frame)
    frame.empty:SetPoint("TOPLEFT", frame.headers, "BOTTOMLEFT", 0, -10)
    frame.empty:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    frame.loading = CreateLoadingState(frame)
    frame.loading:SetPoint("TOPLEFT", frame.headers, "BOTTOMLEFT", 0, 0)
    frame.loading:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.loading:Hide()

    frame.scroll = T.CreateSimpleScroll(frame, { stepSize = 96 })
    frame.scroll:SetPoint("TOPLEFT", frame.headers, "BOTTOMLEFT", 0, -8)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 58)
    frame.content = frame.scroll.content
    frame.rows = {}

    frame.noDataLabel = T.CreateFontString(frame.content, {
        point = { "TOPLEFT", frame.content, "TOPLEFT", 18, -10 },
        size = 13,
        flags = "OUTLINE",
        color = COLORS.muted,
        text = L["BUFF_NO_RAID_DATA"] or "暂无团队数据",
    })

    frame.buttons = CreateFrame("Frame", nil, frame)
    frame.buttons:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    frame.buttons:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    frame.buttons:SetHeight(28)
    local refresh = T.CreateButton(frame.buttons, { width = 120, height = 24, point = { "LEFT", frame.buttons, "LEFT", 0, 0 }, text = L["BUFF_REFRESH_BUTTON"] or "刷新" })
    refresh:SetScript("OnClick", function()
        BuffCheck:ScanRaidIfLead()
        BuffCheck:BroadcastOwnDurability("manual_refresh", true)
        UI:Refresh()
    end)
    local broadcast = T.CreateButton(frame.buttons, { width = 140, height = 24, point = { "LEFT", refresh, "RIGHT", 12, 0 }, text = L["BUFF_BROADCAST_BUTTON"] or "聊天汇总" })
    broadcast:SetScript("OnClick", function()
        BuffCheck:ChatBroadcast()
    end)
    local hide = T.CreateButton(frame.buttons, { width = 120, height = 24, point = { "LEFT", broadcast, "RIGHT", 12, 0 }, text = L["BUFF_HIDE_BUTTON"] or "隐藏" })
    hide:SetScript("OnClick", function()
        frame:Hide()
    end)

    RestorePanelPosition(frame, "raid")
    frame:HookScript("OnShow", RaisePanel)
    frame:Hide()
    raidPanel = frame
    return frame
end

local function AcquireRaidRow(frame, index)
    local row = frame.rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, frame.content, "BackdropTemplate")
    row:SetHeight(RAID_ROW_HEIGHT)
    row:RegisterForClicks("RightButtonUp")
    T.ApplyBackdrop(row, {
        bg = COLORS.row,
        border = { 0.12, 0.12, 0.12, 0.38 },
    })
    row.alt = row:CreateTexture(nil, "BACKGROUND")
    row.alt:SetAllPoints()
    row.alt:SetColorTexture(unpack(COLORS.rowAlt))
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(0.28, 0.36, 0.62, 0.18)
    row.classBar = row:CreateTexture(nil, "ARTWORK")
    row.classBar:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.classBar:SetSize(4, RAID_ROW_HEIGHT)
    row.name = T.CreateFontString(row, {
        point = { "LEFT", row, "LEFT", 16, 0 },
        size = 13,
        flags = "OUTLINE",
        width = RAID_NAME_WIDTH - 26,
        wordWrap = false,
        color = COLORS.text,
        text = "",
    })
    row.cells = {}
    for colIndex, column in ipairs(RAID_COLUMNS) do
        local cell = CreateRaidCell(row)
        cell:SetPoint("LEFT", row, "LEFT", RAID_NAME_WIDTH + 24 + (colIndex - 1) * RAID_CELL_STEP, 0)
        row.cells[column.key] = cell
    end
    row:SetScript("OnClick", function(_, button)
        if button ~= "RightButton" then
            return
        end
        local result = row.__result
        if type(result) ~= "table" then
            return
        end
        local labels = BuffCheck:GetMissingLabels(result)
        if #labels == 0 then
            return
        end
        SendChatMessage(string.format("[STT] %s %s", L["BUFF_WHISPER_PREFIX"] or "请补", table.concat(labels, "、")), "WHISPER", nil, result.unitName)
    end)
    frame.rows[index] = row
    return row
end

local function UpdateRaidRow(frame, index, result, y)
    local row = AcquireRaidRow(frame, index)
    local missing = BuffCheck:EvaluateMissing(result)
    local hasMissing = BuffCheck:HasMissing(result)
    local hasUnknown = BuffCheck:HasUnknownDurability(result)

    row.__result = result
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", -20, y)
    row.alt:SetShown(index % 2 == 0)

    if row.SetBackdropColor then
        if hasMissing then
            row:SetBackdropColor(0.19, 0.07, 0.07, 0.8)
        elseif hasUnknown then
            row:SetBackdropColor(0.11, 0.11, 0.11, 0.78)
        else
            row:SetBackdropColor(0.08, 0.09, 0.08, 0.76)
        end
    end

    local r, g, b = BuffCheck:GetClassColor(result.class)
    row.classBar:SetColorTexture(r, g, b, 1)
    row.name:SetText(result.shortName or result.unitName)
    row.name:SetTextColor(r, g, b, result.connected and 1 or 0.55)

    for _, column in ipairs(RAID_COLUMNS) do
        local state, valueText = GetCellState(result, missing, column.key)
        row.cells[column.key]:SetState(GetColumnIcon(result, column.key), state, valueText)
    end

    SetTooltip(row, result)
    row:Show()
end

local function RefreshRaid()
    local frame = EnsureRaidPanel()
    local results = BuffCheck:GetSortedResults()
    local summary = BuffCheck:GetSummary(results)
    local hasRows = #results > 0
    local hasIssues = summary.ready ~= summary.total

    frame.summary.text:SetText(BuffCheck:BuildSummaryText(results, false))
    frame.empty:Hide()
    frame.scroll:Show()
    frame.headers:SetShown(hasRows)
    frame.noDataLabel:SetShown(not hasRows)

    for _, row in ipairs(frame.rows or {}) do
        row:Hide()
    end

    if not hasRows then
        frame.scroll:Show()
        frame:SetHeight(276)
        if frame.scroll and frame.scroll.SetContentHeight then
            frame.scroll:SetContentHeight(80)
        end
        return
    end

    if not hasIssues and (summary.counts.durabilityUnknown or 0) == 0 then
        frame.empty:Show()
        frame.scroll:Hide()
        frame.headers:Show()
        frame.empty.title:SetText(L["BUFF_RAID_ALL_OK_SHORT"] or "全团准备就绪")
        frame.empty.subtitle:SetText(L["BUFF_RAID_ALL_OK"] or "所有消耗品与团队增益已齐备")
        frame:SetHeight(276)
        return
    end

    local y = -6
    for index, result in ipairs(results) do
        UpdateRaidRow(frame, index, result, y)
        y = y - (RAID_ROW_HEIGHT + 4)
    end

    if frame.scroll and frame.scroll.SetContentHeight then
        frame.scroll:SetContentHeight(math.max(80, #results * (RAID_ROW_HEIGHT + 4) + 12))
    end
    frame:SetHeight(math.min(660, 170 + #results * (RAID_ROW_HEIGHT + 4)))
end

function UI:ShowPersonal()
    local frame = EnsurePersonalPanel()
    RefreshPersonal()
    RaisePanel(frame)
    frame:Show()
    return frame
end

function UI:ShowRaid()
    local frame = EnsureRaidPanel()
    if not frame.__loaded then
        frame.loading:Show()
        frame.empty:Hide()
        frame.scroll:Hide()
        frame.headers:Hide()
        frame:Show()
        RaisePanel(frame)
        C_Timer.After(0, function()
            if not frame:IsShown() then
                return
            end
            frame.loading:Hide()
            frame.__loaded = true
            RefreshRaid()
        end)
        return frame
    end
    RefreshRaid()
    RaisePanel(frame)
    frame:Show()
    return frame
end

function UI:HideAll()
    if personalPanel then
        personalPanel:Hide()
    end
    if raidPanel then
        raidPanel:Hide()
    end
end

function UI:IsRaidShown()
    return raidPanel and raidPanel:IsShown()
end

function UI:Refresh()
    if personalPanel and personalPanel:IsShown() then
        RefreshPersonal()
    end
    if raidPanel and raidPanel:IsShown() then
        RefreshRaid()
    end
end

function BuffCheck:GetClassColor(className)
    local color = className and RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end
    return 0.72, 0.72, 0.72
end

end)
