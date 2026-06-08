local T = unpack(select(2, ...))
T.RegisterColdFile("realtimeBoard.enabled", function()

local RealtimeBoard = T.RealtimeBoard
if not RealtimeBoard then
    return
end

local deps = RealtimeBoard._ConciseDeps or {}
local Concise = {}
T.RealtimeBoardConcise = Concise

local DEFAULT_HEX = "FFD15A"
local colorCache = {}
local cacheVersion = 0

local function EnsureDB()
    return deps.EnsureDB and deps.EnsureDB() or {}
end

local function ToHex(r, g, b)
    return string.format(
        "%02X%02X%02X",
        math.floor(math.max(0, math.min(1, tonumber(r) or 1)) * 255 + 0.5),
        math.floor(math.max(0, math.min(1, tonumber(g) or 1)) * 255 + 0.5),
        math.floor(math.max(0, math.min(1, tonumber(b) or 1)) * 255 + 0.5)
    )
end

local function NormalizeName(name)
    if type(name) ~= "string" then
        return ""
    end
    return name:gsub("%s+", ""):match("^([^-]+)") or name
end

local function GetLeftTimeSlotWidth()
    if deps.GetLeftTimeSlotWidth then
        return deps.GetLeftTimeSlotWidth()
    end
    return 0
end

local function ResolveClassHex(classFile)
    if not classFile or not C_ClassColor or not C_ClassColor.GetClassColor then
        return nil
    end

    local color = C_ClassColor.GetClassColor(classFile)
    if not color then
        return nil
    end
    if color.GenerateHexColor then
        local hex = color:GenerateHexColor()
        return hex and hex:sub(-6) or nil
    end
    return ToHex(color.r, color.g, color.b)
end

local function ResolveRosterClassFile(name)
    if not (IsInRaid and IsInRaid() and GetNumGroupMembers and GetRaidRosterInfo) then
        return nil
    end

    local target = NormalizeName(name)
    if target == "" then
        return nil
    end

    for index = 1, GetNumGroupMembers() do
        local rosterName, _, _, _, _, classFile = GetRaidRosterInfo(index)
        if NormalizeName(rosterName) == target then
            return classFile
        end
    end
    return nil
end

local function ResolvePlayerHex(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local key = NormalizeName(name)
    local cached = colorCache[key]
    if cached ~= nil then
        return cached ~= "" and cached or nil
    end

    local _, classFile = UnitClass(name)
    classFile = classFile or ResolveRosterClassFile(name)
    local hex = ResolveClassHex(classFile)
    colorCache[key] = hex or ""
    return hex
end

function Concise.ResolveWhoColorHex(who, whoType)
    if whoType == "player" then
        return ResolvePlayerHex(who) or DEFAULT_HEX
    end
    if whoType == "condition" then
        local color = T.HorizontalTimelineData
            and T.HorizontalTimelineData.ResolveConditionColor
            and T.HorizontalTimelineData.ResolveConditionColor(who)
        if color then
            return ToHex(color[1], color[2], color[3])
        end
    end
    return DEFAULT_HEX
end

function Concise.BuildLineMarkup(event)
    if type(event) ~= "table" then
        return ""
    end
    local db = EnsureDB()
    local spellDisplayMode = db.spellDisplayMode or "iconText"
    local showIcon = spellDisplayMode ~= "text"
    local showWho = db.showAudienceName ~= false
    if event._conciseMarkup
        and event._conciseMarkupSpellDisplayMode == spellDisplayMode
        and event._conciseMarkupShowWho == showWho
        and event._conciseMarkupCacheVersion == cacheVersion
    then
        return event._conciseMarkup
    end

    local cells = event.cells
    if not (cells and #cells > 0) then
        local text = event.screenText or event.text or ""
        event._conciseMarkup = text
        event._conciseMarkupSpellDisplayMode = spellDisplayMode
        event._conciseMarkupShowWho = showWho
        event._conciseMarkupCacheVersion = cacheVersion
        return text
    end

    local parts = {}
    for _, cell in ipairs(cells) do
        local segment = ""
        local who = cell and cell.who or nil
        if showWho and type(who) == "string" and who ~= "" then
            segment = string.format("|cff%s%s|r", Concise.ResolveWhoColorHex(who, cell.whoType), who)
        end
        if showIcon and cell and cell.spellIcon then
            segment = segment .. (segment ~= "" and " " or "") .. string.format("|T%s:0|t", tostring(cell.spellIcon))
        end
        local actionText = cell and ((spellDisplayMode == "icon" and cell.spellHiddenActionText) or cell.actionText) or nil
        if type(actionText) == "string" and actionText ~= "" then
            segment = segment .. (segment ~= "" and " " or "") .. actionText
        end
        if segment ~= "" then
            parts[#parts + 1] = segment
        end
    end

    local markup = table.concat(parts, "  ")
    event._conciseMarkup = markup
    event._conciseMarkupSpellDisplayMode = spellDisplayMode
    event._conciseMarkupShowWho = showWho
    event._conciseMarkupCacheVersion = cacheVersion
    return markup
end

function Concise.ApplyRowLayout(row, db)
    local rowHeight = math.min(tonumber(db.rowHeight) or 22, 22)
    row:SetHeight(rowHeight)
    row.indicator:Hide()
    row.rowBg:SetColorTexture(0, 0, 0, 0)
    row.iconFrame:Hide()
    row.cellClipFrame:Hide()

    local content = row.contentFrame or row
    row.descText:Show()
    row.descText:ClearAllPoints()
    row.descText:SetFont(STANDARD_TEXT_FONT, db.fontSize or 13, "OUTLINE")
    row.descText:SetJustifyH("LEFT")
    row.descText:SetWordWrap(false)

    row.timeText:ClearAllPoints()
    row.timeText:SetFont(STANDARD_TEXT_FONT, db.timeFontSize or 12, "OUTLINE")
    if db.timePosition == "left" then
        local timeWidth = GetLeftTimeSlotWidth()
        row.timeText:SetWidth(timeWidth)
        row.timeText:SetJustifyH("RIGHT")
        row.timeText:SetPoint("LEFT", content, "LEFT", 8, 0)
        row.descText:SetPoint("LEFT", content, "LEFT", 8 + timeWidth + 6, 0)
        row.descText:SetPoint("RIGHT", content, "RIGHT", -8, 0)
    else
        row.timeText:SetWidth(64)
        row.timeText:SetJustifyH("RIGHT")
        row.timeText:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        row.descText:SetPoint("LEFT", content, "LEFT", 8, 0)
        row.descText:SetPoint("RIGHT", content, "RIGHT", -72, 0)
    end
end

function Concise.ApplyRowChrome(row, state, remaining)
    row.indicator:Hide()
    row.rowBg:SetColorTexture(0, 0, 0, 0)
    row.iconBorder:SetColorTexture(0, 0, 0, 0)
    if state == "expired" then
        local db = EnsureDB()
        if db.expiredMode == "fade" then
            row:SetAlpha(math.max(0.3, 1 + (tonumber(remaining) or 0) / 2))
            return
        end
        row:SetAlpha(0.5)
        return
    end
    row:SetAlpha(1)
end

function Concise:BindRow(row, event)
    row.descText:SetText(Concise.BuildLineMarkup(event))
end

function Concise.InvalidateColorCache()
    wipe(colorCache)
    cacheVersion = cacheVersion + 1
end

local watcher

function Concise.SetColorWatcherEnabled(enabled)
    if not enabled then
        if watcher then
            watcher:UnregisterAllEvents()
        end
        return
    end
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", Concise.InvalidateColorCache)
    end
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_LEAVING_WORLD")
end

end)
