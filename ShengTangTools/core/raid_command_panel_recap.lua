local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("raidCommandPanel.enabled", function()

local RCP = T.RaidCommandPanel
if not RCP then
    return
end

local Recap = {}
RCP.Recap = Recap

local FRAME_WIDTH = 800
local FRAME_MIN_HEIGHT = 150
local FRAME_MARGIN = 12
local DIVIDER_TOP = 38
local HEADER_GAP = 8
local HEADER_HEIGHT = 18
local BODY_GAP = 2
local ROW_HEIGHT = 26
local ROW_COUNT = 15
local CONTENT_INDENT = 6
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local AUTO_ATTACK_ICON = "Interface\\Icons\\INV_Sword_04"

local COL_TIME = 60
local COL_TYPE = 58
local COL_SPELL = 170
local COL_AMOUNT = 155
local COL_HP = 110
local COL_ACTOR = 134

local COLORS = {
    title = { 0.94, 0.86, 0.62, 1 },
    text = { 0.88, 0.88, 0.9, 1 },
    muted = { 0.55, 0.55, 0.6, 1 },
    damage = { 1, 0.48, 0.32, 1 },
    heal = { 0.32, 1, 0.62, 1 },
    absorb = { 0.35, 0.68, 1, 1 },
    fatal = { 0.95, 0.16, 0.12, 1 },
    hp = { 0.25, 0.78, 0.36, 0.8 },
    divider = { 0.45, 0.4, 0.22, 0.75 },
}

local ui = nil

local function IsSecretValue(value)
    return RCP.IsSecretValue and RCP:IsSecretValue(value)
end

local function ResolveText(key, fallback)
    return L[key] or fallback
end

local function GetEnvironmentText()
    return ResolveText("RCP_RECAP_SOURCE_ENVIRONMENT", "环境")
end

local function SavePosition(frame)
    local db = RCP:EnsureDB()
    if type(db.deathLog) ~= "table" then
        db.deathLog = {}
    end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    db.deathLog.recapWindowPos = {
        point = point or "CENTER",
        relPoint = relPoint or "CENTER",
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
    if STT_DB then
        STT_DB.raidCommandPanel = db
    end
end

local function ApplySavedPosition(frame)
    local db = RCP:EnsureDB()
    local pos = db.deathLog and db.deathLog.recapWindowPos
    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 120)
    elseif T.RaidCommandPanelGUI and T.RaidCommandPanelGUI.GetFrame then
        local anchor = T.RaidCommandPanelGUI:GetFrame()
        if anchor then
            frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function ResolveSpellInfo(spellID)
    local id = tonumber(spellID)
    if not id or IsSecretValue(spellID) then
        return nil, QUESTION_ICON
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" then
            return info.name, info.iconID or info.iconFileID or QUESTION_ICON
        elseif type(info) == "string" then
            return info, (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or QUESTION_ICON
        end
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(id)
        return name, icon or QUESTION_ICON
    end
    return tostring(id), QUESTION_ICON
end

local function GetEventTimestamp(eventInfo)
    if type(eventInfo) ~= "table" or IsSecretValue(eventInfo) then
        return nil
    end
    return tonumber(eventInfo.eventTime or eventInfo.capturedAt or eventInfo.timestamp)
end

local function ResolveDeathTimestamp(events)
    if type(events) ~= "table" then
        return nil
    end
    local first = GetEventTimestamp(events[1])
    if first then
        return first
    end
    local latest = nil
    for _, eventInfo in ipairs(events) do
        local t = GetEventTimestamp(eventInfo)
        if t and (not latest or t > latest) then
            latest = t
        end
    end
    return latest
end

local function ResolveEventDisplay(evType, spellID, eventInfo)
    local spellName, icon = ResolveSpellInfo(spellID)
    local eventName = evType and tostring(evType) or nil
    if eventName == "STT_HEALTH_GAIN" then
        return ResolveText("RCP_RECAP_HEALTH_GAIN", "生命值恢复"), QUESTION_ICON
    end
    if spellName then
        return spellName, icon or QUESTION_ICON
    end
    if eventName == "SWING_DAMAGE" or eventName == "SWING_MISSED" or eventName == "SWING_DAMAGE_LANDED" then
        local _, autoIcon = ResolveSpellInfo(6603)
        return ResolveText("RCP_RECAP_AUTO_ATTACK", "自动攻击"), autoIcon or AUTO_ATTACK_ICON
    end
    if DeathRecapFrame_GetEventInfo then
        local ok, _, name, texture = pcall(DeathRecapFrame_GetEventInfo, eventInfo)
        if ok and name then
            return name, texture or QUESTION_ICON
        end
    end
    return eventName or (spellID and tostring(spellID)) or ResolveText("RCP_RECAP_UNKNOWN_EVENT", "未知事件"), QUESTION_ICON
end

local function FormatAmount(value)
    if value == nil or IsSecretValue(value) then
        return "?"
    end
    local amount = tonumber(value)
    if not amount then
        return tostring(value)
    end
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(math.floor(amount + 0.5))
    end
    return tostring(math.floor(amount + 0.5))
end

local function FormatOffset(eventTime, deathTime)
    local eventSeconds = tonumber(eventTime)
    local deathSeconds = tonumber(deathTime)
    if not eventSeconds or not deathSeconds or IsSecretValue(eventTime) then
        return "--"
    end
    return string.format("%+.2fs", eventSeconds - deathSeconds)
end

local function GetSortOffset(eventTime, deathTime)
    local eventSeconds = tonumber(eventTime)
    local deathSeconds = tonumber(deathTime)
    if not eventSeconds or not deathSeconds or IsSecretValue(eventTime) then
        return nil
    end
    return eventSeconds - deathSeconds
end

local function FormatHP(value)
    if value == nil or IsSecretValue(value) then
        return nil
    end
    local pct = tonumber(value)
    if not pct then
        return nil
    end
    if pct <= 1 then
        pct = pct * 100
    end
    return math.max(0, math.min(100, pct))
end

local function ResolveEventKind(evType, amount, overkill)
    local eventName = evType and tostring(evType) or ""
    if tonumber(overkill) and tonumber(overkill) > 0 then
        return "death"
    end
    if eventName == "STT_HEALTH_GAIN" then
        return "heal"
    end
    if eventName == "SPELL_HEAL_ABSORBED" then
        return "heal_absorb"
    end
    if eventName == "SPELL_ABSORBED" or eventName:find("_ABSORB") then
        return "damage_absorb"
    end
    if eventName:find("_HEAL") then
        return "heal"
    end
    if eventName:find("_DAMAGE") or eventName == "SWING_DAMAGE" or tonumber(amount) then
        return "damage"
    end
    return "other"
end

local function GetKindLabel(kind)
    if kind == "death" then
        return ResolveText("RCP_RECAP_TYPE_DEATH", "死亡")
    elseif kind == "heal" then
        return ResolveText("RCP_RECAP_TYPE_HEAL", "治疗")
    elseif kind == "heal_absorb" then
        return ResolveText("RCP_RECAP_TYPE_HEAL_ABSORB", "治疗吸收")
    elseif kind == "damage_absorb" then
        return ResolveText("RCP_RECAP_TYPE_DAMAGE_ABSORB", "伤害吸收")
    elseif kind == "absorb" then
        return ResolveText("RCP_RECAP_TYPE_ABSORB", "吸收")
    elseif kind == "damage" then
        return ResolveText("RCP_RECAP_TYPE_DAMAGE", "伤害")
    end
    return ResolveText("RCP_RECAP_TYPE_OTHER", "事件")
end

local function GetKindColor(kind)
    if kind == "death" then
        return COLORS.fatal
    elseif kind == "heal" then
        return COLORS.heal
    elseif kind == "absorb" or kind == "heal_absorb" or kind == "damage_absorb" then
        return COLORS.absorb
    elseif kind == "damage" then
        return COLORS.damage
    end
    return COLORS.text
end

local function FormatSignedAmount(kind, amount, absorbed)
    local amountText = FormatAmount(amount)
    if kind == "heal" then
        amountText = "+" .. amountText
    elseif kind == "damage_absorb" then
        amountText = "+" .. amountText
    elseif kind == "damage" or kind == "death" or kind == "heal_absorb" then
        amountText = "-" .. amountText
    end
    if (kind == "damage" or kind == "death") and tonumber(absorbed) and tonumber(absorbed) > 0 then
        amountText = amountText .. string.format(" |cff5da8ff(%s %s)|r", ResolveText("RCP_RECAP_DAMAGE_ABSORB_DETAIL", "伤害吸收"), FormatAmount(absorbed))
    end
    return amountText
end

local function FormatHealthText(currentHP, hpPct)
    if currentHP ~= nil and not IsSecretValue(currentHP) then
        local hpText = FormatAmount(currentHP)
        if hpPct then
            return string.format("%s · %.0f%%", hpText, hpPct)
        end
        return hpText
    end
    if hpPct then
        return string.format("%.0f%%", hpPct)
    end
    return nil
end

local function UnpackEvent(eventInfo, deathTime, maxHealth)
    if type(eventInfo) ~= "table" or IsSecretValue(eventInfo) then
        return nil
    end
    local evType = eventInfo.event
    local spellID = eventInfo.spellID or eventInfo.spellId
    local amount = eventInfo.amount
    local eventTime = eventInfo.eventTime or eventInfo.capturedAt or eventInfo.timestamp

    local spellName, icon = ResolveEventDisplay(evType, spellID, eventInfo)
    local numericSpellID = (spellID ~= nil and not IsSecretValue(spellID)) and tonumber(spellID) or nil
    local sourceName = eventInfo.sourceName
    local destName = eventInfo.destName
    local absorbed = eventInfo.absorbed
    local overkill = tonumber(eventInfo.overkill) or 0
    local critical = eventInfo.criticalHit == true or eventInfo.critical == true
    local currentHP = eventInfo.currentHP
    local hpPct = FormatHP(eventInfo.healthPercent)
    if not hpPct and currentHP and maxHealth and tonumber(maxHealth) and tonumber(maxHealth) > 0 then
        hpPct = FormatHP((tonumber(currentHP) or 0) / tonumber(maxHealth))
    end
    local kind = ResolveEventKind(evType, amount, overkill)
    local amountText = FormatSignedAmount(kind, amount, absorbed)
    if critical then
        amountText = amountText .. "!"
    end
    local eventSeconds = tonumber(eventTime)
    local sortOffset = GetSortOffset(eventTime, deathTime)
    return {
        raw = false,
        eventTime = eventSeconds,
        offsetText = FormatOffset(eventTime, deathTime),
        sortOffset = sortOffset,
        spellID = numericSpellID,
        spellName = spellName,
        sourceText = (sourceName and not IsSecretValue(sourceName)) and tostring(sourceName) or GetEnvironmentText(),
        targetText = (destName and not IsSecretValue(destName)) and tostring(destName) or nil,
        amountText = amountText,
        hpPct = hpPct,
        hpText = FormatHealthText(currentHP, hpPct),
        icon = icon or QUESTION_ICON,
        kind = kind,
        fatal = kind == "death",
    }
end

local function IsPreciseRecentHeal(eventInfo)
    if type(eventInfo) ~= "table" or eventInfo.event == "STT_HEALTH_GAIN" then
        return false
    end
    local eventName = eventInfo.event and tostring(eventInfo.event) or ""
    return eventName == "SPELL_HEAL" or eventName == "SPELL_PERIODIC_HEAL" or eventName == "SPELL_HEAL_ABSORBED"
end

local function ShouldSkipSyntheticHealthGain(eventInfo, recentEvents)
    if type(eventInfo) ~= "table" or eventInfo.event ~= "STT_HEALTH_GAIN" or type(recentEvents) ~= "table" then
        return false
    end
    local eventTime = tonumber(eventInfo.eventTime or eventInfo.capturedAt)
    local destName = eventInfo.destName
    for _, other in ipairs(recentEvents) do
        if IsPreciseRecentHeal(other) then
            local otherTime = tonumber(other.eventTime or other.capturedAt)
            local sameTarget = destName == nil or other.destName == nil or other.destName == destName
            if eventTime and otherTime and sameTarget and math.abs(eventTime - otherTime) <= 0.6 then
                return true
            end
        end
    end
    return false
end

local function BuildEvents(recapData, deathEntry)
    local list = {}
    recapData = recapData or {}
    local deathTime = ResolveDeathTimestamp(recapData.events) or deathEntry.recapDeathTimeSeconds or deathEntry.time
    for _, eventInfo in ipairs(recapData.events or {}) do
        local item = UnpackEvent(eventInfo, deathTime, recapData.maxHealth)
        if item then
            list[#list + 1] = item
        end
    end
    local recentDeathTime = tonumber(deathEntry.capturedAt) or deathTime
    local recentEvents = (RCP.GetDeathRecentEvents and RCP:GetDeathRecentEvents(deathEntry)) or {}
    for _, eventInfo in ipairs(recentEvents) do
        if not ShouldSkipSyntheticHealthGain(eventInfo, recentEvents) then
            local item = UnpackEvent(eventInfo, recentDeathTime, recapData.maxHealth)
            if item then
                list[#list + 1] = item
            end
        end
    end
    table.sort(list, function(a, b)
        return (tonumber(a.sortOffset) or 0) < (tonumber(b.sortOffset) or 0)
    end)
    local hasFatal = false
    for _, item in ipairs(list) do
        if item.fatal then
            hasFatal = true
            item.kind = "death"
        end
        if not item.targetText or item.targetText == "" then
            item.targetText = deathEntry.name
        end
    end
    if not hasFatal and #list > 0 then
        local last = list[#list]
        if last.kind == "damage" then
            last.kind = "death"
            last.fatal = true
        end
    end
    return list
end

local function SetFontColor(fs, color)
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function ShowLineTooltip(line)
    local item = line and line.eventItem
    if not (item and T.UITooltip) then
        return
    end
    local lines = {}
    if item.amountText then
        lines[#lines + 1] = string.format("%s: %s", ResolveText("RCP_RECAP_COL_AMOUNT", "数值"), item.amountText)
    end
    if item.sourceText or item.targetText then
        lines[#lines + 1] = string.format("%s |cff888888->|r %s", item.sourceText or GetEnvironmentText(), item.targetText or "--")
    end
    T.UITooltip.Show(line, {
        title = item.spellName or ResolveText("RCP_RECAP_UNKNOWN_EVENT", "未知事件"),
        description = table.concat(lines, "\n"),
        concepts = item.spellID and { "spell" } or nil,
    }, { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
end

local function HideLineTooltip(line)
    if T.UITooltip then
        T.UITooltip.ScheduleHide()
    end
end

local function ResizeFrame(frame, rowCount)
    local rows = math.max(1, math.min(ROW_COUNT, tonumber(rowCount) or 1))
    local bodyHeight = rows * ROW_HEIGHT
    frame.body:SetHeight(bodyHeight)
    frame.noData:SetWidth(FRAME_WIDTH - FRAME_MARGIN * 2)
    frame:SetSize(FRAME_WIDTH, math.max(FRAME_MIN_HEIGHT, DIVIDER_TOP + HEADER_GAP + HEADER_HEIGHT + BODY_GAP + bodyHeight + FRAME_MARGIN))
end

local function CreateButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 22)
    T.ApplyBackdrop(button, { alpha = 0.35, borderColor = COLORS.divider })
    button.text = T.CreateFontString(button, {
        template = "GameFontNormalSmall",
        point = { "CENTER", button, "CENTER", 0, 0 },
        width = width - 10,
        justifyH = "CENTER",
        size = 11,
        text = text,
    })
    return button
end

local function EnsureLine(index)
    local line = ui.lines[index]
    if line then
        return line
    end
    line = CreateFrame("Frame", nil, ui.body)
    line:SetHeight(ROW_HEIGHT)
    line:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    line:SetPoint("RIGHT", ui.body, "RIGHT", 0, 0)
    line:EnableMouse(true)
    line:SetScript("OnEnter", ShowLineTooltip)
    line:SetScript("OnLeave", HideLineTooltip)

    line.fatalBar = line:CreateTexture(nil, "BACKGROUND")
    line.fatalBar:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.fatalBar:SetSize(3, ROW_HEIGHT - 4)
    line.fatalBar:SetColorTexture(unpack(COLORS.fatal))

    line.time = T.CreateFontString(line, {
        template = "GameFontNormalSmall",
        point = { "LEFT", line, "LEFT", CONTENT_INDENT, 0 },
        width = COL_TIME,
        justifyH = "LEFT",
        color = COLORS.muted,
        size = 11,
    })
    line.type = T.CreateFontString(line, {
        template = "GameFontNormalSmall",
        point = { "LEFT", line.time, "RIGHT", 4, 0 },
        width = COL_TYPE,
        justifyH = "LEFT",
        color = COLORS.text,
        size = 11,
    })
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetPoint("LEFT", line.type, "RIGHT", 4, 0)
    line.icon:SetSize(22, 22)

    line.spell = T.CreateFontString(line, {
        template = "GameFontNormalSmall",
        point = { "LEFT", line.icon, "RIGHT", 6, 0 },
        width = COL_SPELL,
        justifyH = "LEFT",
        color = COLORS.text,
        size = 11,
        wordWrap = false,
    })
    line.amount = T.CreateFontString(line, {
        template = "GameFontNormalSmall",
        point = { "LEFT", line.spell, "RIGHT", 6, 0 },
        width = COL_AMOUNT,
        justifyH = "RIGHT",
        color = COLORS.damage,
        size = 11,
        wordWrap = false,
    })
    line.hpBg = line:CreateTexture(nil, "BACKGROUND")
    line.hpBg:SetPoint("LEFT", line.amount, "RIGHT", 10, 0)
    line.hpBg:SetSize(COL_HP, 8)
    line.hpBg:SetColorTexture(0, 0, 0, 0.45)
    line.hpFill = line:CreateTexture(nil, "ARTWORK")
    line.hpFill:SetPoint("LEFT", line.hpBg, "LEFT", 0, 0)
    line.hpFill:SetHeight(8)
    line.hpFill:SetColorTexture(unpack(COLORS.hp))
    line.hpText = T.CreateFontString(line, {
        template = "GameFontNormalSmall",
        point = { "CENTER", line.hpBg, "CENTER", 0, 0 },
        width = COL_HP,
        justifyH = "CENTER",
        color = COLORS.text,
        size = 9,
    })
    line.actor = T.CreateFontString(line, {
        template = "GameFontNormalSmall",
        point = { "LEFT", line.hpBg, "RIGHT", 10, 0 },
        width = COL_ACTOR,
        justifyH = "LEFT",
        color = COLORS.text,
        size = 10,
        wordWrap = false,
    })
    ui.lines[index] = line
    return line
end

function Recap:Ensure()
    if ui then
        return ui
    end
    ui = CreateFrame("Frame", "STT_RaidCommandPanelRecap", UIParent, "BackdropTemplate")
    ui:SetFrameStrata("DIALOG")
    ui:SetClampedToScreen(true)
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetSize(FRAME_WIDTH, FRAME_MIN_HEIGHT)
    T.ApplyBackdrop(ui, { style = "chat", alpha = 0.9, borderColor = COLORS.divider })

    ui:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    ui:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)

    ui.title = T.CreateFontString(ui, {
        template = "GameFontNormal",
        point = { "TOPLEFT", ui, "TOPLEFT", FRAME_MARGIN, -10 },
        width = FRAME_WIDTH - FRAME_MARGIN * 2 - 32,
        justifyH = "LEFT",
        color = COLORS.title,
        size = 13,
        wordWrap = false,
    })
    ui.closeButton = CreateButton(ui, "X", 24)
    ui.closeButton:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -FRAME_MARGIN, -8)
    ui.closeButton:SetScript("OnClick", function()
        ui:Hide()
    end)

    ui.divider = ui:CreateTexture(nil, "ARTWORK")
    ui.divider:SetPoint("TOPLEFT", ui, "TOPLEFT", FRAME_MARGIN, -DIVIDER_TOP)
    ui.divider:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -FRAME_MARGIN, -DIVIDER_TOP)
    ui.divider:SetHeight(1)
    ui.divider:SetColorTexture(unpack(COLORS.divider))

    ui.header = CreateFrame("Frame", nil, ui)
    ui.header:SetPoint("TOPLEFT", ui.divider, "BOTTOMLEFT", 0, -HEADER_GAP)
    ui.header:SetPoint("TOPRIGHT", ui.divider, "BOTTOMRIGHT", 0, -HEADER_GAP)
    ui.header:SetHeight(HEADER_HEIGHT)

    ui.headerTime = T.CreateFontString(ui.header, {
        template = "GameFontNormalSmall",
        point = { "LEFT", ui.header, "LEFT", CONTENT_INDENT, 0 },
        width = COL_TIME,
        justifyH = "LEFT",
        color = COLORS.muted,
        size = 10,
        text = ResolveText("RCP_RECAP_COL_TIME", "时间"),
    })
    ui.headerType = T.CreateFontString(ui.header, {
        template = "GameFontNormalSmall",
        point = { "LEFT", ui.headerTime, "RIGHT", 4, 0 },
        width = COL_TYPE,
        justifyH = "LEFT",
        color = COLORS.muted,
        size = 10,
        text = ResolveText("RCP_RECAP_COL_TYPE", "类型"),
    })
    ui.headerSpell = T.CreateFontString(ui.header, {
        template = "GameFontNormalSmall",
        point = { "LEFT", ui.headerType, "RIGHT", 32, 0 },
        width = COL_SPELL,
        justifyH = "LEFT",
        color = COLORS.muted,
        size = 10,
        text = ResolveText("RCP_RECAP_COL_SPELL", "技能"),
    })
    ui.headerAmount = T.CreateFontString(ui.header, {
        template = "GameFontNormalSmall",
        point = { "LEFT", ui.headerSpell, "RIGHT", 6, 0 },
        width = COL_AMOUNT,
        justifyH = "RIGHT",
        color = COLORS.muted,
        size = 10,
        text = ResolveText("RCP_RECAP_COL_AMOUNT", "数值"),
    })
    ui.headerHP = T.CreateFontString(ui.header, {
        template = "GameFontNormalSmall",
        point = { "LEFT", ui.headerAmount, "RIGHT", 10, 0 },
        width = COL_HP,
        justifyH = "CENTER",
        color = COLORS.muted,
        size = 10,
        text = ResolveText("RCP_RECAP_COL_HP", "生命值"),
    })
    ui.headerActor = T.CreateFontString(ui.header, {
        template = "GameFontNormalSmall",
        point = { "LEFT", ui.headerHP, "RIGHT", 10, 0 },
        width = COL_ACTOR,
        justifyH = "LEFT",
        color = COLORS.muted,
        size = 10,
        text = ResolveText("RCP_RECAP_COL_SOURCE", "来源 → 目标"),
    })

    ui.body = CreateFrame("Frame", nil, ui)
    ui.body:SetPoint("TOPLEFT", ui.header, "BOTTOMLEFT", 0, -BODY_GAP)
    ui.body:SetPoint("TOPRIGHT", ui.header, "BOTTOMRIGHT", 0, -BODY_GAP)
    ui.body:SetHeight(ROW_HEIGHT)
    ui.lines = {}

    ui.noData = T.CreateFontString(ui.body, {
        template = "GameFontNormal",
        point = { "CENTER", ui.body, "CENTER", 0, 0 },
        width = FRAME_WIDTH - FRAME_MARGIN * 2,
        justifyH = "CENTER",
        color = COLORS.muted,
        size = 13,
        wordWrap = true,
    })

    ApplySavedPosition(ui)
    return ui
end

local function RenderEvents(events)
    for index = 1, ROW_COUNT do
        local line = EnsureLine(index)
        local item = events[index]
        if item then
            line.eventItem = item
            line.time:SetText(item.offsetText or "--")
            line.type:SetText(GetKindLabel(item.kind))
            SetFontColor(line.type, GetKindColor(item.kind))
            line.icon:SetTexture(item.icon or QUESTION_ICON)
            line.spell:SetText(item.spellName or "--")
            line.amount:SetText(item.amountText or "?")
            SetFontColor(line.amount, GetKindColor(item.kind))
            if item.hpPct then
                line.hpBg:Show()
                line.hpFill:SetWidth(math.max(1, COL_HP * item.hpPct / 100))
                line.hpFill:Show()
                line.hpText:SetText(item.hpText or string.format("%.0f%%", item.hpPct))
                line.hpText:Show()
            else
                line.hpBg:Hide()
                line.hpFill:Hide()
                line.hpText:Hide()
            end
            line.actor:SetText(string.format("%s |cff888888→|r %s", item.sourceText or GetEnvironmentText(), item.targetText or "--"))
            line.fatalBar:SetShown(item.fatal == true)
            line:Show()
        else
            HideLineTooltip(line)
            line.eventItem = nil
            line:Hide()
        end
    end
end

function Recap:Open(deathEntry)
    if type(deathEntry) ~= "table" then
        return
    end
    local db = RCP:EnsureDB()
    if db.deathLog and db.deathLog.showRecap == false then
        return
    end
    local frame = self:Ensure()
    ApplySavedPosition(frame)
    local name = deathEntry.name or (UNKNOWN or "Unknown")
    frame.title:SetText(string.format("%s - %s", tostring(name), ResolveText("RCP_RECAP_TITLE", "死亡详情")))

    local recapID = RCP:ResolveDeathRecap(deathEntry, "open")
    local data = RCP:GetDeathRecapData(recapID)
    if not data or data.hasEvents ~= true then
        local events = BuildEvents({ events = {} }, deathEntry)
        if #events > 0 then
            ResizeFrame(frame, #events)
            RenderEvents(events)
            frame.noData:Hide()
            frame.header:Show()
            frame:Show()
        else
            ResizeFrame(frame, 3)
            RenderEvents({})
            frame.noData:SetText(ResolveText("RCP_RECAP_NO_DATA", "无可回放数据（非战斗死亡或暴雪未生成回放）"))
            frame.noData:Show()
            frame.header:Hide()
            frame:Show()
        end
        return
    end

    local events = BuildEvents(data, deathEntry)
    ResizeFrame(frame, #events)
    RenderEvents(events)
    frame.noData:Hide()
    frame.header:Show()
    frame:Show()
end

end)
