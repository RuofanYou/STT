local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("raidCommandPanel.enabled", function()

local GUI = {}
T.RaidCommandPanelGUI = GUI

local ui = nil
local BASE_ROW_HEIGHT = 18
local BASE_TOP_HEIGHT = 24
local BASE_PADDING = 8
local BASE_MIN_WIDTH = 220
local BASE_MIN_TOP_WIDTH = 128
local SCALE_MIN = 0.8
local SCALE_MAX = 1.8
local MAX_ROWS = 12
local REBIRTH_SPELL_ID = 20484
local BLOODLUST_SPELL_ID = 2825
local CLOCK_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

local COLORS = {
    title = { 0.9, 0.85, 0.7, 1 },
    time = { 0.58, 0.58, 0.62, 1 },
    death = { 1.0, 0.28, 0.26, 1 },
    rez = { 0.34, 1.0, 0.55, 1 },
    soulstone = { 0.36, 0.68, 1.0, 1 },
    text = { 0.88, 0.88, 0.9, 1 },
    divider = { 0.45, 0.4, 0.22, 0.75 },
}

local function Round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function ClampScale(value)
    local scale = tonumber(value) or 1
    if scale < SCALE_MIN then
        return SCALE_MIN
    end
    if scale > SCALE_MAX then
        return SCALE_MAX
    end
    return scale
end

local function GetMetrics(db)
    local scale = ClampScale(db and db.styleScale)
    return {
        scale = scale,
        rowHeight = Round(BASE_ROW_HEIGHT * scale),
        topHeight = Round(BASE_TOP_HEIGHT * scale),
        padding = Round(BASE_PADDING * scale),
        minWidth = Round(BASE_MIN_WIDTH * scale),
        minTopWidth = Round(BASE_MIN_TOP_WIDTH * scale),
        iconSize = Round(14 * (0.75 + scale * 0.25)),
        iconWidth = Round((14 * (0.75 + scale * 0.25)) + (4 * scale)),
        topFontSize = Round(12 * scale),
        rowTimeFontSize = Round(11 * scale),
        rowNameFontSize = Round(12 * scale),
        rowStatusFontSize = Round(11 * scale),
        arrowFontSize = Round(11 * scale),
        topCenterY = -Round((BASE_TOP_HEIGHT * scale) / 2),
        rowGap = Round(4 * scale),
        rowTopGap = Round(2 * scale),
        rowTimeWidth = Round(46 * scale),
        rowNameWidth = Round(110 * scale),
        rowStatusWidth = Round(124 * scale),
        rowStatusRight = Round(16 * scale),
        minWidthExtra = Round(18 * scale),
    }
end

local function SetFontSize(fontString, size)
    if not fontString or not fontString.GetFont or not fontString.SetFont then
        return
    end
    local font, _, flags = fontString:GetFont()
    fontString:SetFont(font or STANDARD_TEXT_FONT, size, flags)
end

local function ApplyTextMetrics(frame, metrics)
    if not frame then
        return
    end
    if frame.topText then
        frame.topText:ClearAllPoints()
        frame.topText:SetPoint("LEFT", frame, "TOPLEFT", metrics.padding, metrics.topCenterY)
        frame.topText:SetPoint("RIGHT", frame, "TOPRIGHT", -metrics.padding, metrics.topCenterY)
        SetFontSize(frame.topText, metrics.topFontSize)
    end
    if frame.measureText then
        SetFontSize(frame.measureText, metrics.topFontSize)
    end
end

local function ApplyRowMetrics(row, index, metrics)
    row:SetHeight(metrics.rowHeight)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", ui.divider, "BOTTOMLEFT", 0, -((index - 1) * metrics.rowHeight) - metrics.rowTopGap)
    row:SetPoint("RIGHT", ui, "RIGHT", -metrics.padding, 0)

    row.time:ClearAllPoints()
    row.time:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.time:SetWidth(metrics.rowTimeWidth)
    SetFontSize(row.time, metrics.rowTimeFontSize)

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row.time, "RIGHT", metrics.rowGap, 0)
    row.name:SetWidth(metrics.rowNameWidth)
    SetFontSize(row.name, metrics.rowNameFontSize)

    row.status:ClearAllPoints()
    row.status:SetPoint("RIGHT", row, "RIGHT", -metrics.rowStatusRight, 0)
    row.status:SetWidth(metrics.rowStatusWidth)
    SetFontSize(row.status, metrics.rowStatusFontSize)

    row.arrow:ClearAllPoints()
    row.arrow:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    SetFontSize(row.arrow, metrics.arrowFontSize)
end

local function ResolveColor(classFile, fallback)
    if classFile and C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(classFile)
        if color then
            if color.GetRGB then
                return color:GetRGB()
            end
            return color.r, color.g, color.b
        end
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local color = RAID_CLASS_COLORS[classFile]
        return color.r, color.g, color.b
    end
    local base = fallback or COLORS.text
    return base[1], base[2], base[3]
end

local function FormatClock(seconds)
    local total = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

local function FormatRemaining(expirationTime)
    if not expirationTime then
        return nil
    end
    return math.max(0, math.floor(expirationTime - GetTime() + 0.5))
end

local function FormatRemainingClock(expirationTime)
    local remaining = FormatRemaining(expirationTime)
    if remaining == nil then
        return "-"
    end
    return FormatClock(remaining)
end

local function FormatSessionElapsed(session)
    if not session or not session.startTime then
        return FormatClock(0)
    end
    local endTime = tonumber(session.endTime) or GetTime()
    return FormatClock(endTime - (tonumber(session.startTime) or endTime))
end

local function GetSpellIconText(spellID, metrics)
    local texture
    if C_Spell and C_Spell.GetSpellTexture then
        texture = C_Spell.GetSpellTexture(spellID)
    elseif GetSpellTexture then
        texture = GetSpellTexture(spellID)
    end
    if not texture then
        return ""
    end
    local size = metrics and metrics.iconSize or 14
    return string.format("|T%s:%d:%d:0:0|t ", tostring(texture), size, size)
end

local function GetTextureIconText(texture, metrics)
    local size = metrics and metrics.iconSize or 14
    return string.format("|T%s:%d:%d:0:0|t ", tostring(texture), size, size)
end

local function EstimateInlineTextWidth(text, metrics)
    if not ui or not ui.measureText then
        return 0
    end
    local plain, iconCount = tostring(text or ""):gsub("|T.-|t%s*", "")
    ui.measureText:SetText(plain)
    return (ui.measureText:GetStringWidth() or 0) + iconCount * (metrics and metrics.iconWidth or 18)
end

local function BuildStatusText(death)
    if death.method == "soulstone" then
        return L["RCP_SOULSTONE"] or "灵魂石自救", COLORS.soulstone
    end
    if death.resurrected then
        local source = death.resurrectedBy or (UNKNOWN or "Unknown")
        return string.format(L["RCP_RESURRECTED_BY"] or "被%s战复", source), COLORS.rez
    end
    return L["RCP_DEATH"] or "死亡", COLORS.death
end

local function SavePosition(frame)
    if not frame or not C.DB or not C.DB.raidCommandPanel then
        return
    end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    local pos = C.DB.raidCommandPanel.position
    pos.point = point or pos.point or "CENTER"
    pos.relPoint = relPoint or pos.relPoint or "CENTER"
    pos.x = math.floor((x or 0) + 0.5)
    pos.y = math.floor((y or 0) + 0.5)
    pos.width = math.floor((frame:GetWidth() or pos.width or 320) + 0.5)
    if STT_DB then
        STT_DB.raidCommandPanel = C.DB.raidCommandPanel
    end
end

local function EnsureRow(index, metrics)
    local frame = ui.rows[index]
    if frame then
        ApplyRowMetrics(frame, index, metrics)
        return frame
    end
    frame = CreateFrame("Frame", nil, ui)
    frame:EnableMouse(true)
    frame.hover = frame:CreateTexture(nil, "HIGHLIGHT")
    frame.hover:SetAllPoints()
    frame.hover:SetColorTexture(0.8, 0.7, 0.35, 0.14)
    frame.time = T.CreateFontString(frame, {
        template = "GameFontNormalSmall",
        point = { "LEFT", frame, "LEFT", 0, 0 },
        width = 46,
        justifyH = "LEFT",
        color = COLORS.time,
        size = 11,
    })
    frame.name = T.CreateFontString(frame, {
        template = "GameFontNormal",
        point = { "LEFT", frame.time, "RIGHT", 4, 0 },
        width = 110,
        justifyH = "LEFT",
        size = 12,
    })
    frame.status = T.CreateFontString(frame, {
        template = "GameFontNormalSmall",
        point = { "RIGHT", frame, "RIGHT", -16, 0 },
        width = 124,
        justifyH = "RIGHT",
        size = 11,
    })
    frame.arrow = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.arrow:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame.arrow:SetText(">")
    frame.arrow:Hide()
    frame:SetScript("OnEnter", function(self)
        if self.deathRef and self.recapEnabled and SetCursor then
            SetCursor("Interface/CURSOR/Point.blp")
        end
    end)
    frame:SetScript("OnLeave", function()
        if SetCursor then
            SetCursor(nil)
        end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.deathRef and self.recapEnabled and T.RaidCommandPanel and T.RaidCommandPanel.Recap then
            T.RaidCommandPanel.Recap:Open(self.deathRef)
        end
    end)
    ui.rows[index] = frame
    ApplyRowMetrics(frame, index, metrics)
    return frame
end

function GUI:Ensure()
    if ui then
        return ui
    end

    local db = C.DB.raidCommandPanel or C.defaults.raidCommandPanel
    local pos = db.position or C.defaults.raidCommandPanel.position
    local metrics = GetMetrics(db)
    ui = CreateFrame("Frame", "STT_RaidCommandPanel", UIParent, "BackdropTemplate")
    ui:SetFrameStrata("HIGH")
    ui:SetClampedToScreen(true)
    ui:SetMovable(true)
    ui:EnableMouse(false)
    ui:RegisterForDrag()
    ui:SetSize(pos.width or 320, metrics.topHeight + metrics.padding)
    ui:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 200)
    T.ApplyBackdrop(ui, {
        style = "chat",
        alpha = 0.8,
        borderColor = COLORS.divider,
    })

    ui.topText = T.CreateFontString(ui, {
        template = "GameFontNormal",
        point = { "LEFT", ui, "TOPLEFT", metrics.padding, metrics.topCenterY },
        justifyH = "LEFT",
        color = COLORS.title,
        size = metrics.topFontSize,
        wordWrap = false,
    })
    if ui.topText.SetNonSpaceWrap then
        ui.topText:SetNonSpaceWrap(false)
    end
    ui.topText:SetPoint("RIGHT", ui, "TOPRIGHT", -metrics.padding, metrics.topCenterY)

    ui.measureText = T.CreateFontString(ui, {
        template = "GameFontNormal",
        point = { "TOPLEFT", ui, "TOPLEFT", -1000, 1000 },
        size = metrics.topFontSize,
        wordWrap = false,
    })
    ui.measureText:Hide()

    ui.divider = ui:CreateTexture(nil, "ARTWORK")
    ui.divider:SetPoint("TOPLEFT", ui, "TOPLEFT", metrics.padding, -metrics.topHeight)
    ui.divider:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -metrics.padding, -metrics.topHeight)
    ui.divider:SetHeight(1)
    ui.divider:SetColorTexture(unpack(COLORS.divider))

    ui.rows = {}
    ui:SetScript("OnDragStart", function(self)
        if T.RaidCommandPanel and T.RaidCommandPanel:IsLocked() then
            return
        end
        self:StartMoving()
    end)
    ui:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    ApplyTextMetrics(ui, metrics)
    return ui
end

function GUI:LoadPosition()
    local frame = self:Ensure()
    local pos = C.DB.raidCommandPanel and C.DB.raidCommandPanel.position or C.defaults.raidCommandPanel.position
    local metrics = GetMetrics(C.DB.raidCommandPanel or C.defaults.raidCommandPanel)
    frame:ClearAllPoints()
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 200)
    frame:SetWidth(pos.width or 320)
    ApplyTextMetrics(frame, metrics)
end

function GUI:ApplyLockState(rcp)
    local frame = self:Ensure()
    local locked = rcp and rcp:IsLocked()
    frame:EnableMouse(locked == false)
    if locked then
        frame:RegisterForDrag()
    else
        frame:RegisterForDrag("LeftButton")
    end
end

function GUI:Hide()
    if ui then
        ui:Hide()
    end
end

function GUI:GetFrame()
    return ui
end

local function BuildTopText(snapshot, metrics)
    local db = snapshot.db
    local topRow = snapshot.topRow
    local session = snapshot.session
    local parts = {}
    local elapsedText = FormatSessionElapsed(session)
    if db.rezTracker.enabled then
        local rezPrefix = GetSpellIconText(REBIRTH_SPELL_ID, metrics) .. (L["RCP_REZ_LABEL"] or "战复")
        local charges = topRow.charges
        local rezText
        if charges ~= nil then
            rezText = string.format(L["RCP_REZ_COUNT_FMT"] or "%s %d次", rezPrefix, charges)
        else
            rezText = string.format("%s -", rezPrefix)
        end
        if topRow.nextChargeETA then
            rezText = string.format("%s %s", rezText, FormatClock(topRow.nextChargeETA))
        end
        parts[#parts + 1] = rezText
    end
    if db.lustMonitor.enabled then
        local lustPrefix = GetSpellIconText(BLOODLUST_SPELL_ID, metrics) .. (L["RCP_LUST_LABEL"] or "嗜血")
        if topRow.lustState == "active" then
            parts[#parts + 1] = string.format("%s %s", lustPrefix, FormatRemainingClock(topRow.lustExpiration))
        elseif topRow.lustState == "sated" then
            parts[#parts + 1] = string.format("%s %s", lustPrefix, FormatRemainingClock(topRow.lustExpiration))
        else
            parts[#parts + 1] = string.format("%s -", lustPrefix)
        end
    end
    if db.encounterTimer.enabled and elapsedText then
        parts[#parts + 1] = GetTextureIconText(CLOCK_ICON, metrics) .. elapsedText
    end
    if session and session.endTime then
        if session.success == "timeout" then
            parts[#parts + 1] = L["RCP_STATUS_TIMEOUT"] or "[超时]"
        else
            parts[#parts + 1] = L["RCP_STATUS_ENDED"] or "[已结束]"
        end
    end
    return table.concat(parts, "  ")
end

local function HasTopRow(snapshot)
    local db = snapshot.db
    local session = snapshot.session
    return db.rezTracker.enabled or db.lustMonitor.enabled or db.encounterTimer.enabled or (session and session.endTime)
end

function GUI:RefreshCountdowns(rcp)
    if not ui or not ui:IsShown() or not rcp then
        return
    end
    local snapshot = rcp:GetSnapshot()
    local metrics = GetMetrics(snapshot.db)
    ApplyTextMetrics(ui, metrics)
    ui.topText:SetText(BuildTopText(snapshot, metrics))
    if ui.topText:IsShown() then
        local minWidth = math.max(metrics.minTopWidth, math.ceil(EstimateInlineTextWidth(ui.topText:GetText(), metrics) + metrics.padding * 2 + metrics.minWidthExtra))
        if minWidth > (ui:GetWidth() or 0) then
            ui:SetWidth(minWidth)
        end
    end
end

function GUI:Refresh(rcp)
    local snapshot = rcp:GetSnapshot()
    if not snapshot.mainEnabled or not snapshot.allowed or not snapshot.hasAnySubModule then
        self:Hide()
        return
    end

    local db = snapshot.db
    local metrics = GetMetrics(db)
    local session = snapshot.session
    local deathEnabled = db.deathLog.enabled == true
    local recapEnabled = db.deathLog.showRecap ~= false
    local deathCount = deathEnabled and session and #(session.deaths or {}) or 0
    local topVisible = HasTopRow(snapshot)
    if not topVisible and deathCount == 0 and not (deathEnabled and session) then
        self:Hide()
        return
    end

    local frame = self:Ensure()
    self:ApplyLockState(rcp)
    ApplyTextMetrics(frame, metrics)

    local rowsToShow = math.min(deathCount, MAX_ROWS)
    local listHeight = rowsToShow * metrics.rowHeight

    if topVisible then
        frame.topText:SetText(BuildTopText(snapshot, metrics))
        frame.topText:Show()
        frame.divider:ClearAllPoints()
        frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.padding, -metrics.topHeight)
        frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -metrics.padding, -metrics.topHeight)
    else
        frame.topText:Hide()
        frame.divider:ClearAllPoints()
        frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", metrics.padding, -metrics.padding)
        frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -metrics.padding, -metrics.padding)
    end
    if deathEnabled and (topVisible or deathCount == 0) then
        frame.divider:Show()
    else
        frame.divider:Hide()
    end

    local topOnly = topVisible and not deathEnabled
    local width = math.max(metrics.minWidth, tonumber(db.position and db.position.width) or 320)
    if topVisible then
        width = math.max(width, metrics.minTopWidth, math.ceil(EstimateInlineTextWidth(frame.topText:GetText(), metrics) + metrics.padding * 2 + metrics.minWidthExtra))
    end
    local height
    if topOnly then
        height = metrics.topHeight
    else
        height = metrics.padding + (topVisible and metrics.topHeight or 0) + (deathEnabled and 1 or 0) + listHeight + metrics.padding
    end
    frame:SetSize(width, math.max(metrics.topHeight, height))

    for index = 1, math.max(#frame.rows, rowsToShow) do
        local row = frame.rows[index]
        if row then
            row:Hide()
        end
    end
    if deathEnabled and session then
        for index = 1, rowsToShow do
            local death = session.deaths[index]
            local row = EnsureRow(index, metrics)
            row.deathRef = death
            row.recapEnabled = recapEnabled
            row.time:SetText(rcp:FormatSessionTime(death.time))
            row.name:SetText(death.name or UNKNOWN or "Unknown")
            local r, g, b = ResolveColor(death.class, COLORS.text)
            row.name:SetTextColor(r, g, b, 1)
            local status, color = BuildStatusText(death)
            row.status:SetText(status)
            row.status:SetTextColor(unpack(color))
            local recapID = tonumber(death.recapID)
            if recapEnabled and recapID and recapID >= 0 then
                row.arrow:Show()
            else
                row.arrow:Hide()
            end
            row:Show()
        end
    end
    frame:Show()
end

end)
