local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("rosterPlanner.enabled", function()

local RP = T.RosterPlanner
if not RP then
    return
end

local Panel = {
    frame = nil,
    rows = {},
}
T.RosterPlannerSubPanel = Panel

local function Text(key, fallback)
    return (L and L[key]) or fallback or key
end

local function EnsureFrame()
    if Panel.frame then
        return Panel.frame
    end
    local frame = T.CreatePopupWindow(UIParent, {
        name = "STT_RosterPlannerSubPanel",
        width = 360,
        height = 330,
        title = Text("RP_SUB_PANEL_TITLE", "STT 替补面板"),
    })
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = RP:EnsureDB()
        local point, _, relPoint, x, y = self:GetPoint(1)
        db.subPanel.position = { point = point or "CENTER", relPoint = relPoint or "CENTER", x = x or 0, y = y or 0 }
        if STT_DB and STT_DB.rosterPlanner then
            STT_DB.rosterPlanner.subPanel = db.subPanel
        end
    end)
    frame.header = T.CreateLabel(frame, {
        point = { "TOPLEFT", frame, "TOPLEFT", 14, -44 },
        width = 330,
        text = "",
        color = { 1, 0.86, 0.32, 1 },
    })
    frame.notes = T.CreateLabel(frame, {
        point = { "TOPLEFT", frame.header, "BOTTOMLEFT", 0, -8 },
        width = 330,
        wordWrap = true,
        text = "",
        color = { 0.85, 0.85, 0.85, 1 },
    })
    frame.list = CreateFrame("Frame", nil, frame)
    frame.list:SetPoint("TOPLEFT", frame.notes, "BOTTOMLEFT", 0, -18)
    frame.list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    for i = 1, 12 do
        local row = frame.list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -((i - 1) * 18))
        row:SetPoint("RIGHT", frame.list, "RIGHT", 0, 0)
        row:SetJustifyH("LEFT")
        Panel.rows[i] = row
    end
    Panel.frame = frame
    return frame
end

function Panel:ApplyPosition()
    local frame = EnsureFrame()
    local db = RP:EnsureDB()
    local pos = db.subPanel and db.subPanel.position or {}
    frame:ClearAllPoints()
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", tonumber(pos.x) or 0, tonumber(pos.y) or 0)
end

function Panel:Refresh()
    local frame = EnsureFrame()
    local snapshot = RP.runtime and RP.runtime.receivedSnapshot
    if not snapshot then
        frame.header:SetText(Text("RP_SUB_EMPTY", "尚未收到团长推送。"))
        frame.notes:SetText("")
        for _, row in ipairs(self.rows) do
            row:SetText("")
        end
        return
    end
    local parsed = snapshot.parsed or RP.Parse(snapshot.sourceText or "")
    local playerKey = RP:GetPlayerRosterKey(parsed)
    frame.header:SetText(string.format(Text("RP_SUB_HEADER_FMT", "团长：%s"), tostring(snapshot.senderName or "")))
    frame.notes:SetText(parsed.notes or "")
    for _, row in ipairs(self.rows) do
        row:SetText("")
    end
    local db = RP:EnsureDB()
    local showSelfOnly = db.subPanel and db.subPanel.showSelfOnly == true
    local index = 1
    for _, boss in ipairs(parsed.bosses or {}) do
        local status = RP:GetBossStatusForPlayer(parsed, boss, playerKey)
        if not showSelfOnly or status ~= "none" then
            local row = self.rows[index]
            if not row then
                break
            end
            local label = Text("RP_STATUS_NONE", "不参战")
            local r, g, b = 0.7, 0.7, 0.7
            if status == "main" then
                label = Text("RP_STATUS_MAIN", "主力")
                r, g, b = 0.55, 1, 0.55
            elseif status == "sub" then
                label = Text("RP_STATUS_SUB", "替补")
                r, g, b = 1, 0.82, 0.35
            end
            row:SetText(string.format("%s  ·  %s", boss.name, label))
            row:SetTextColor(r, g, b, 1)
            index = index + 1
        end
    end
end

function Panel:Show()
    self:ApplyPosition()
    self:Refresh()
    EnsureFrame():Show()
end

function Panel:Toggle()
    local frame = EnsureFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        self:Show()
    end
end

function RP:ShowSubPanel()
    if self.BlockIfNotDebug and self:BlockIfNotDebug() then
        return
    end
    Panel:Show()
end

function RP:ToggleSubPanel()
    if self.BlockIfNotDebug and self:BlockIfNotDebug() then
        return
    end
    Panel:Toggle()
end

function RP:ResetSubPanelPosition()
    if self.BlockIfNotDebug and self:BlockIfNotDebug() then
        return
    end
    local db = RP:EnsureDB()
    db.subPanel.position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    if STT_DB and STT_DB.rosterPlanner then
        STT_DB.rosterPlanner.subPanel = db.subPanel
    end
    Panel:ApplyPosition()
    Panel:Refresh()
end

end)
