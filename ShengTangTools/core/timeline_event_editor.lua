local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local Editor = {}
T.TimelineEventEditor = Editor

local WINDOW_WIDTH = 560
local WINDOW_HEIGHT = 740
local FIELD_LEFT = 24
local FIELD_WIDTH = 228
local SECTION_LEFT = 18
local SECTION_WIDTH = WINDOW_WIDTH - SECTION_LEFT * 2
local SECTION_PAD_X = 12
local SECTION_INNER_WIDTH = SECTION_WIDTH - SECTION_PAD_X * 2
local RIGHT_COL_X = SECTION_WIDTH - SECTION_PAD_X - FIELD_WIDTH
local SECTION_TITLE_Y = -8
local SECTION_CONTENT_Y = -32
local CONTROL_ROW_Y = SECTION_CONTENT_Y - 18
local SPELL_ID_X = SECTION_PAD_X
local SPELL_OCC_X = 150
local MARKER_X = RIGHT_COL_X
local MOD_AUX_X = 134
local MOD_LEFT_VALUE_X = RIGHT_COL_X - 76
local MOD_RIGHT_VALUE_X = SECTION_PAD_X + SECTION_INNER_WIDTH - 70
local MOD_NOTE_STYLE_WIDTH = 156
local MOD_NOTE_STYLE_X = SECTION_PAD_X + SECTION_INNER_WIDTH - MOD_NOTE_STYLE_WIDTH
local MOD_NOTE_TEXT_WIDTH = MOD_NOTE_STYLE_X - MOD_AUX_X - 8
local HERO_TITLE_WIDTH = WINDOW_WIDTH - 175
local HERO_TITLE_MAX_SIZE = 24
local HERO_TITLE_MIN_SIZE = 15
local SCREEN_REMINDER_NONE = "__none"
local SCREEN_REMINDER_CUSTOM = "__custom"

local TARGET_ITEMS = {
    { text = "所有人", value = "all" },
    { text = "坦克", value = "condition:坦克" },
    { text = "治疗", value = "condition:治疗" },
    { text = "输出", value = "condition:输出" },
    { text = "近战", value = "condition:近战" },
    { text = "远程", value = "condition:远程" },
    { text = "战士", value = "condition:战士" },
    { text = "圣骑士", value = "condition:圣骑士" },
    { text = "猎人", value = "condition:猎人" },
    { text = "潜行者", value = "condition:潜行者" },
    { text = "牧师", value = "condition:牧师" },
    { text = "死亡骑士", value = "condition:死亡骑士" },
    { text = "萨满祭司", value = "condition:萨满祭司" },
    { text = "法师", value = "condition:法师" },
    { text = "术士", value = "condition:术士" },
    { text = "武僧", value = "condition:武僧" },
    { text = "德鲁伊", value = "condition:德鲁伊" },
    { text = "恶魔猎手", value = "condition:恶魔猎手" },
    { text = "唤魔师", value = "condition:唤魔师" },
    { text = "自定义点名", value = "players" },
}

local MARKER_ITEMS = {
    { text = "无", value = "" },
    { text = "rt1 / star", value = "rt1" },
    { text = "rt2 / circle", value = "rt2" },
    { text = "rt3 / diamond", value = "rt3" },
    { text = "rt4 / triangle", value = "rt4" },
    { text = "rt5 / moon", value = "rt5" },
    { text = "rt6 / square", value = "rt6" },
    { text = "rt7 / cross", value = "rt7" },
    { text = "rt8 / skull", value = "rt8" },
}

local function Text(key, fallback)
    return L[key] or fallback or key
end

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function BuildNoteStyleItems()
    return {
        { text = Text("TIMELINE_EVENT_EDITOR_NOTE_STYLE_SOFT", "仅显示(~~)"), value = "soft" },
        { text = Text("TIMELINE_EVENT_EDITOR_NOTE_STYLE_HARD", "完全隐藏(<>)"), value = "hard" },
    }
end

local function ListScreenReminderNames()
    local schema = T.ScreenReminderSchema
    if not (schema and schema.ListIndicators) then
        return {}
    end
    local ok, indicators = pcall(schema.ListIndicators)
    if not ok or type(indicators) ~= "table" then
        return {}
    end
    local names = {}
    for _, indicator in ipairs(indicators) do
        local name = Trim(indicator and indicator.name)
        if name ~= "" then
            names[#names + 1] = name
        end
    end
    return names
end

local function ScreenReminderNameExists(name)
    local target = Trim(name)
    if target == "" then
        return false
    end
    for _, existing in ipairs(ListScreenReminderNames()) do
        if existing == target then
            return true
        end
    end
    return false
end

local function BuildScreenReminderItems(selectedValue)
    local items = {
        { text = Text("TIMELINE_EVENT_EDITOR_SCREEN_REMINDER_NONE", "不指定"), value = SCREEN_REMINDER_NONE },
    }
    if selectedValue == SCREEN_REMINDER_CUSTOM then
        items[#items + 1] = { text = Text("TIMELINE_EVENT_EDITOR_SCREEN_REMINDER_CUSTOM", "保留当前自定义"), value = SCREEN_REMINDER_CUSTOM }
    end
    for _, name in ipairs(ListScreenReminderNames()) do
        items[#items + 1] = { text = name, value = name }
    end
    return items
end

local function AttachTooltip(widget, text)
    if T.UITooltip then
        if type(text) == "table" then
            T.UITooltip.AttachRich(widget, text, { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
        else
            T.UITooltip.AttachSimple(widget, text, { anchor = "ANCHOR_RIGHT", x = 0, y = 0 })
        end
    end
end

local function Debug(message)
    if T.debug then
        T.debug("[TimelineEventEditor] " .. tostring(message or ""))
    end
end

local function Msg(message)
    if T.msg then
        T.msg(message)
    end
end

local function FormatNumber(value)
    local number = tonumber(value)
    if not number then
        return ""
    end
    if math.abs(number - math.floor(number + 0.5)) < 0.0001 then
        return tostring(math.floor(number + 0.5))
    end
    return tostring(number)
end

local function FormatTime(seconds)
    local value = math.max(0, tonumber(seconds) or 0)
    local precision = math.abs(value - math.floor(value + 0.5)) >= 0.0001 and 1 or 0
    local factor = 10 ^ precision
    value = math.floor(value * factor + 0.5) / factor
    local min = math.floor(value / 60)
    local sec = value - min * 60
    if precision == 0 then
        return string.format("%d:%02d", min, sec)
    end
    return string.format("%d:%04.1f", min, sec)
end

local function ParseTime(text)
    local value = Trim(text)
    local min, sec = value:match("^(%d+):(%d+%.?%d*)$")
    if min and sec then
        return (tonumber(min) or 0) * 60 + (tonumber(sec) or 0)
    end
    local onlySec = value:match("^(%d+%.?%d*)$")
    return onlySec and tonumber(onlySec) or nil
end

local function SplitPlayers(text)
    local players = {}
    for name in tostring(text or ""):gmatch("[^,\n]+") do
        local normalized = Trim(name)
        if normalized ~= "" then
            players[#players + 1] = normalized
        end
    end
    return players
end

local function NormalizeTargetCondition(condition)
    local value = Trim(condition)
    local lower = value:lower()
    if lower == "tank" then
        return "坦克"
    elseif lower == "healer" or lower == "heal" then
        return "治疗"
    elseif lower == "dps" or lower == "dd" or lower == "damager" then
        return "输出"
    elseif lower == "melee" then
        return "近战"
    elseif lower == "ranged" then
        return "远程"
    end
    return value
end

local function FitHeroTitle(fontString, text)
    if not fontString then
        return
    end
    fontString:SetText(text or "")
    local size = HERO_TITLE_MAX_SIZE
    fontString:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    while size > HERO_TITLE_MIN_SIZE and (fontString:GetStringWidth() or 0) > HERO_TITLE_WIDTH do
        size = size - 1
        fontString:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    end
end

local function IsAudienceToken(token)
    local value = Trim(token)
    if value == "" or value:match("^spell:%d+") or value:sub(1, 1) == "@" then
        return false
    end
    local name = value:match("^([%w_]+)%s*:")
    if name and T.InlineModifier and T.InlineModifier.KNOWN and T.InlineModifier.KNOWN[name] then
        return false
    end
    if value:match("^rt[1-8]$") or value == "star" or value == "circle" or value == "diamond" or value == "triangle"
        or value == "moon" or value == "square" or value == "cross" or value == "skull" then
        return false
    end
    return true
end

local function SplitSourceSegments(line)
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI._segmentMove and T.SemanticTimelineGUI._segmentMove.SplitSourceSegments then
        return T.SemanticTimelineGUI._segmentMove.SplitSourceSegments(line)
    end
    local content = tostring(line or ""):gsub("{time:[^}]+}", "", 1)
    local segments = {}
    local currentStart, currentHasBody, pendingAudienceStart
    local pos = 1

    local function Push(endPos)
        if currentStart and currentHasBody then
            local text = Trim(content:sub(currentStart, endPos))
            if text ~= "" then
                segments[#segments + 1] = text
            end
        end
        currentStart, currentHasBody, pendingAudienceStart = nil, false, nil
    end

    while true do
        local b, e = content:find("%b{}", pos)
        if not b then
            if currentStart then
                if Trim(content:sub(pos)) ~= "" then
                    currentHasBody = true
                end
                Push(#content)
            end
            break
        end
        if currentStart and Trim(content:sub(pos, b - 1)) ~= "" then
            currentHasBody = true
        elseif pendingAudienceStart and Trim(content:sub(pos, b - 1)) ~= "" then
            currentStart, currentHasBody, pendingAudienceStart = pendingAudienceStart, true, nil
        end
        local token = content:sub(b + 1, e - 1)
        if IsAudienceToken(token) then
            if currentStart and currentHasBody then
                Push(b - 1)
            end
            pendingAudienceStart = pendingAudienceStart or b
        else
            currentStart = currentStart or pendingAudienceStart or b
            pendingAudienceStart = nil
            currentHasBody = true
        end
        pos = e + 1
    end
    return segments
end

local function FindSegmentIndex(parsed, item)
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI._segmentMove and T.SemanticTimelineGUI._segmentMove.FindSegmentIndex then
        return T.SemanticTimelineGUI._segmentMove.FindSegmentIndex(parsed and parsed.segments, item)
    end
    return tonumber(item and item.sourceSegmentIndex) or 1
end

local function ExtractLeadingAudience(segmentText)
    local body = tostring(segmentText or "")
    local condition = ""
    local players = {}
    local pos = 1
    while true do
        local first = body:find("%S", pos)
        if not first then
            return condition, players, ""
        end
        local b, e = body:find("%b{}", first)
        if b ~= first then
            return condition, players, Trim(body:sub(first))
        end
        local token = body:sub(b + 1, e - 1)
        if not IsAudienceToken(token) then
            return condition, players, Trim(body:sub(b))
        end
        if T.IsGroupConditionToken and T.IsGroupConditionToken(token) then
            condition = token
        else
            players[#players + 1] = token
        end
        pos = e + 1
    end
end

local function ReadModifier(entry)
    if type(entry) == "table" and entry.value ~= nil then
        return entry.value
    end
    return entry
end

local function NormalizeModifiers(scanned)
    local source = type(scanned) == "table" and scanned.modifiers or nil
    source = type(source) == "table" and source or {}
    local bar = ReadModifier(source.bar)
    local sound = ReadModifier(source.sound)
    return {
        ct = tonumber(ReadModifier(source.ct)),
        sr = tonumber(ReadModifier(source.sr)),
        dur = tonumber(ReadModifier(source.dur)),
        bar = type(bar) == "table" and {
            n = tonumber(bar.duration or bar.n),
            tick = tonumber(bar.tickInterval or bar.tick),
            spell = tonumber(bar.spellID or bar.spell),
            label = tostring(bar.labelOverride or bar.label or ""),
            icon = bar.iconOverride or bar.icon,
        } or nil,
        sound = type(sound) == "table" and tostring(sound.label or sound.path or "") or tostring(sound or ""),
    }
end

local function ExtractTrailingNote(body)
    local value = Trim(body)
    if value == "" then
        return "", "", "soft"
    end

    local before, softNote = value:match("^(.-)%s*~~([^~<>]-)~~%s*$")
    if softNote then
        return Trim(before), Trim(softNote), "soft"
    end

    local hardBefore, hardNote = value:match("^(.-)%s*<([^<>]-)>%s*$")
    if hardNote then
        return Trim(hardBefore), Trim(hardNote), "hard"
    end

    return value, "", "soft"
end

local function ExtractScreenReminderRoute(text)
    local foundTokens = {}
    local firstTargets = nil
    local cleaned = tostring(text or ""):gsub("{to:([^}]*)}", function(payload)
        local tokenText = "{to:" .. tostring(payload or "") .. "}"
        foundTokens[#foundTokens + 1] = tokenText
        if not firstTargets then
            local targets = {}
            for name in tostring(payload or ""):gmatch("[^,]+") do
                local normalized = Trim(name)
                if normalized ~= "" then
                    targets[#targets + 1] = normalized
                end
            end
            firstTargets = targets
        end
        return ""
    end)

    if #foundTokens == 0 then
        return Trim(cleaned), SCREEN_REMINDER_NONE, nil
    end

    if #foundTokens == 1 and firstTargets and #firstTargets == 1 and ScreenReminderNameExists(firstTargets[1]) then
        return Trim(cleaned), firstTargets[1], nil
    end

    return Trim(cleaned), SCREEN_REMINDER_CUSTOM, table.concat(foundTokens)
end

local function ParseSegment(segmentText)
    local route, routeValue, routeCustomToken = ExtractScreenReminderRoute(segmentText)
    local condition, players, body = ExtractLeadingAudience(route)

    local scanned = T.InlineModifier and T.InlineModifier.Scan and T.InlineModifier.Scan(body) or nil
    local cleanBody = scanned and scanned.stripped or body
    local modifiers = NormalizeModifiers(scanned)
    local noteText, noteStyle
    cleanBody, noteText, noteStyle = ExtractTrailingNote(cleanBody)
    local raidMarker = nil
    cleanBody = cleanBody:gsub("{([%a%d]+)}", function(token)
        local key = tostring(token or ""):lower()
        if not raidMarker and (key:match("^rt[1-8]$") or key == "star" or key == "circle" or key == "diamond" or key == "triangle"
            or key == "moon" or key == "square" or key == "cross" or key == "skull") then
            raidMarker = key:match("^rt[1-8]$") and key or ({
                star = "rt1", circle = "rt2", diamond = "rt3", triangle = "rt4",
                moon = "rt5", square = "rt6", cross = "rt7", skull = "rt8",
            })[key]
            return ""
        end
        return "{" .. token .. "}"
    end)

    local spellID, spellOcc
    cleanBody = cleanBody:gsub("{spell:(%d+):?(%d*)}", function(id, occ)
        if not spellID then
            spellID = tonumber(id)
            spellOcc = tonumber(occ)
            return ""
        end
        return "{spell:" .. id .. (occ ~= "" and ":" .. occ or "") .. "}"
    end, 1)

    local targetKind = "all"
    local customPlayers = ""
    if condition ~= "" then
        if condition == "所有人" or condition == "everyone" or condition == "all" or condition == "全团" then
            targetKind = "all"
        else
            targetKind = "condition:" .. NormalizeTargetCondition(condition)
        end
    elseif #players > 0 then
        targetKind = "players"
        customPlayers = table.concat(players, ",")
    end

    return {
        targetKind = targetKind,
        customPlayers = customPlayers,
        spellID = spellID,
        spellOcc = spellOcc,
        text = Trim(cleanBody),
        modifiers = modifiers,
        raidMarker = raidMarker,
        noteText = noteText,
        noteStyle = noteStyle,
        screenReminderRoute = routeValue,
        screenReminderCustomToken = routeCustomToken,
    }
end

local function ComposeTarget(state)
    if state.targetKind == "all" then
        return "{所有人}"
    end
    local condition = tostring(state.targetKind or ""):match("^condition:(.+)$")
    if condition and condition ~= "" then
        return "{" .. condition .. "}"
    end
    if state.targetKind == "players" then
        local parts = {}
        for _, name in ipairs(SplitPlayers(state.customPlayers)) do
            parts[#parts + 1] = "{" .. name .. "}"
        end
        return table.concat(parts)
    end
    return ""
end

local function ComposeSegment(state)
    local parts = { ComposeTarget(state) }
    local srLead = state.modifiers and tonumber(state.modifiers.sr) or nil
    if srLead and srLead >= 0 and srLead <= 10 then
        parts[#parts + 1] = "{sr:" .. FormatNumber(srLead) .. "}"
    end
    local route = state.screenReminderRoute
    if route == SCREEN_REMINDER_CUSTOM then
        local customToken = Trim(state.screenReminderCustomToken)
        if customToken ~= "" then
            parts[#parts + 1] = customToken
        end
    elseif route and route ~= "" and route ~= SCREEN_REMINDER_NONE then
        parts[#parts + 1] = "{to:" .. tostring(route) .. "}"
    end
    if state.raidMarker and state.raidMarker ~= "" then
        parts[#parts + 1] = "{" .. state.raidMarker .. "}"
    end
    local spellID = tonumber(state.spellID)
    if spellID and spellID > 0 then
        local spell = "{spell:" .. tostring(math.floor(spellID + 0.5))
        local occ = tonumber(state.spellOcc)
        if occ and occ > 0 then
            spell = spell .. ":" .. tostring(math.floor(occ + 0.5))
        end
        parts[#parts + 1] = spell .. "}"
    end
    parts[#parts + 1] = Trim(state.text)

    local composeModifiers = {}
    for key, value in pairs(state.modifiers or {}) do
        if key ~= "sr" then
            composeModifiers[key] = value
        end
    end
    local modText = T.InlineModifier and T.InlineModifier.Compose and T.InlineModifier.Compose(composeModifiers) or ""
    return table.concat(parts) .. modText
end

local function ComposeLine(state)
    local timeText = FormatTime(state.timeSec)
    local tails = {}
    if Trim(state.phase) ~= "" then
        tails[#tails + 1] = Trim(state.phase)
    end
    if type(state.ttsAdvanceOverride) == "number" and state.ttsAdvanceOverride >= 0 then
        tails[#tails + 1] = "-" .. FormatNumber(state.ttsAdvanceOverride)
    end
    if #tails > 0 then
        timeText = timeText .. "," .. table.concat(tails, ",")
    end
    local timeToken = "{time:" .. timeText .. "}"
    local segmentText = ComposeSegment(state)
    local noteText = Trim(state.noteText)
    if noteText ~= "" and not noteText:find("[~<>{}\r\n]") then
        if state.noteStyle == "hard" then
            segmentText = segmentText .. " <" .. noteText .. ">"
        else
            segmentText = segmentText .. " ~~" .. noteText .. "~~"
        end
    end
    local segments = type(state.sourceSegments) == "table" and state.sourceSegments or {}
    if #segments <= 1 then
        return timeToken .. " " .. segmentText
    end

    local parts = {}
    for index, segment in ipairs(segments) do
        if index == state.segmentIndex then
            parts[#parts + 1] = segmentText
        else
            parts[#parts + 1] = segment
        end
    end
    return timeToken .. " " .. table.concat(parts)
end

local function ResolveTTSTextFromState(state)
    local line = ComposeLine(state)
    local syntax = T.TimelineSyntax
    local event = syntax and syntax.ParseTimelineLine and syntax.ParseTimelineLine(line) or nil
    if not event then
        return ""
    end
    if T.NoteParser and T.NoteParser.GetResolvedEventTTSText then
        return T.NoteParser:GetResolvedEventTTSText(event) or ""
    end
    if syntax and syntax.ResolveTextForCurrentPlayer then
        local matched, text = syntax.ResolveTextForCurrentPlayer(event.content or "", { target = "tts" })
        if matched then
            return text or ""
        end
    end
    return event.displayText or event.content or ""
end

local function ResolveSpellVisual(spellID)
    local id = tonumber(spellID)
    if not id then
        return nil, nil
    end
    local spellName, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then
            spellName = info.name
            icon = info.iconID or info.originalIconID
        end
    end
    if not icon and T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        icon = T.TimelineSyntax.ResolveSpellIcon(id)
    end
    return spellName, icon
end

local function CreateLabel(parent, text, x, y, width)
    local label = T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", x, y },
        text = text,
        size = 12,
    })
    if width then
        label:SetWidth(width)
    end
    return label
end

local function CreateSection(parent, title, y, height)
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", SECTION_LEFT, y)
    section:SetSize(SECTION_WIDTH, height)

    local bar = section:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -9)
    bar:SetSize(T.Style and T.Style.Section and T.Style.Section.SUBGROUP_LEFT_BAR_WIDTH or 2, 16)
    bar:SetColorTexture(0.98, 0.86, 0.52, 0.55)

    local titleText = T.CreateGroupTitle(section, {
        point = { "TOPLEFT", section, "TOPLEFT", 10, SECTION_TITLE_Y },
        text = title,
        fontSize = T.Style and T.Style.Section and T.Style.Section.SUBGROUP_FONT_SIZE or 12,
        template = T.Style and T.Style.Font and T.Style.Font.SUBGROUP or "GameFontHighlight",
        color = T.Style and T.Style.Color and T.Style.Color.KYRIAN_GOLD or { 0.98, 0.86, 0.52, 1 },
    })
    T.CreateSeparator(section, {
        point = { "TOPLEFT", titleText, "BOTTOMLEFT", 0, -4 },
        width = SECTION_WIDTH - 22,
        color = T.Style and T.Style.Color and T.Style.Color.SECTION_LINE or { 0.65, 0.55, 0.32, 0.5 },
    })
    return section
end

local function SetEditEnabled(edit, enabled)
    if not edit then
        return
    end
    if enabled then
        edit:Enable()
        edit:SetTextColor(1, 1, 1, 1)
    else
        edit:Disable()
        edit:SetTextColor(0.55, 0.55, 0.55, 1)
    end
end

function Editor:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = T.CreatePopupWindow(UIParent, {
        width = WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
        title = Text("TIMELINE_EVENT_EDITOR_TITLE", "编辑事件"),
        alpha = 0.94,
        style = "chat",
    })
    self.frame = frame
    self.controls = {}
    if frame.closeButton then
        frame.closeButton:SetScript("OnClick", function()
            Editor.Close()
        end)
    end

    frame.hero = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.hero:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -36)
    frame.hero:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -36)
    frame.hero:SetHeight(78)
    T.ApplyBackdrop(frame.hero, {
        alpha = 0.42,
        style = "tooltip",
        borderColor = T.Style and T.Style.Color and T.Style.Color.SECTION_LINE or { 0.65, 0.55, 0.32, 0.5 },
    })
    frame.hero.accent = frame.hero:CreateTexture(nil, "ARTWORK")
    frame.hero.accent:SetPoint("TOPLEFT", frame.hero, "TOPLEFT", 1, -1)
    frame.hero.accent:SetPoint("TOPRIGHT", frame.hero, "TOPRIGHT", -1, -1)
    frame.hero.accent:SetHeight(2)
    frame.hero.accent:SetColorTexture(0.98, 0.86, 0.52, 0.72)

    frame.hero.iconBack = frame.hero:CreateTexture(nil, "BACKGROUND")
    frame.hero.iconBack:SetSize(56, 56)
    frame.hero.iconBack:SetPoint("LEFT", frame.hero, "LEFT", 12, 0)
    frame.hero.iconBack:SetColorTexture(0.02, 0.02, 0.025, 0.72)
    frame.hero.icon = frame.hero:CreateTexture(nil, "ARTWORK")
    frame.hero.icon:SetSize(48, 48)
    frame.hero.icon:SetPoint("CENTER", frame.hero.iconBack, "CENTER", 0, 0)
    frame.hero.iconFallback = T.CreateFontString(frame.hero, {
        template = "GameFontNormalLarge",
        point = { "CENTER", frame.hero.iconBack, "CENTER", 0, 0 },
        size = 24,
        flags = "OUTLINE",
        color = { 0.98, 0.86, 0.52, 1 },
        text = "?",
    })

    frame.hero.title = T.CreateFontString(frame.hero, {
        template = "GameFontNormalLarge",
        point = { "CENTER", frame.hero, "CENTER", 0, 1 },
        size = HERO_TITLE_MAX_SIZE,
        flags = "OUTLINE",
        color = { 0.98, 0.86, 0.52, 1 },
        width = HERO_TITLE_WIDTH,
        justifyH = "CENTER",
        justifyV = "MIDDLE",
        wordWrap = false,
        text = "",
    })
    if frame.hero.title.SetNonSpaceWrap then
        frame.hero.title:SetNonSpaceWrap(false)
    end
    if frame.hero.title.SetMaxLines then
        frame.hero.title:SetMaxLines(1)
    end
    local baseSection = CreateSection(frame, Text("TIMELINE_EVENT_EDITOR_SECTION_BASIC", "基础"), -122, 72)
    CreateLabel(baseSection, Text("TIMELINE_EVENT_EDITOR_TIME", "时间(M:SS.ms)"), SECTION_PAD_X, SECTION_CONTENT_Y, 180)
    CreateLabel(baseSection, Text("TIMELINE_EVENT_EDITOR_PHASE", "相位"), RIGHT_COL_X, SECTION_CONTENT_Y, 180)
    self.controls.time = T.CreateEditBox(baseSection, { width = FIELD_WIDTH, height = 24, point = { "TOPLEFT", baseSection, "TOPLEFT", SECTION_PAD_X, CONTROL_ROW_Y } })
    self.controls.phase = T.CreateEditBox(baseSection, { width = FIELD_WIDTH, height = 24, point = { "TOPLEFT", baseSection, "TOPLEFT", RIGHT_COL_X, CONTROL_ROW_Y }, placeholder = "p1r1" })
    AttachTooltip(self.controls.time, {
        title = "时间",
        description = "决定事件触发时机。",
        examples = { "{time:00:10}", "{time:00:10,p2r1}" },
        concepts = { "time", "time-absolute", "phase-tag", "phase-relative-time" },
    })
    AttachTooltip(self.controls.phase, {
        title = "阶段",
        description = "标记事件所属阶段。",
        examples = { "p1", "p2r1" },
        concepts = { "phase-tag", "phase-relative-time" },
    })

    local audienceSection = CreateSection(frame, Text("TIMELINE_EVENT_EDITOR_SECTION_TARGET", "播报对象"), -202, 74)
    self.controls.target = T.CreateSelectorButton(audienceSection, {
        width = FIELD_WIDTH,
        height = 26,
        point = { "TOPLEFT", audienceSection, "TOPLEFT", SECTION_PAD_X, SECTION_CONTENT_Y },
        label = Text("TIMELINE_EVENT_EDITOR_TARGET", "目标"),
        labelWidth = 62,
        items = TARGET_ITEMS,
        ownerFrame = frame,
    })
    self.controls.players = T.CreateEditBox(audienceSection, { width = FIELD_WIDTH, height = 24, point = { "TOPLEFT", audienceSection, "TOPLEFT", RIGHT_COL_X, SECTION_CONTENT_Y }, placeholder = Text("TIMELINE_EVENT_EDITOR_CUSTOM_PLAYERS", "自定义点名") })
    AttachTooltip(self.controls.target, {
        title = "受众",
        description = "决定谁会收到播报。",
        concepts = { "audience", "audience-all", "role-tank", "role-healer", "role-dps", "class", "specialization", "spec-disambiguation", "boolean-and", "boolean-or" },
    })
    AttachTooltip(self.controls.players, {
        title = "自定义点名",
        description = "直接指定玩家或岗位。",
        concepts = { "audience", "personnel-mapping", "personnel-fallback" },
    })

    local contentSection = CreateSection(frame, Text("TIMELINE_EVENT_EDITOR_SECTION_CONTENT", "内容"), -284, 150)
    CreateLabel(contentSection, Text("TIMELINE_EVENT_EDITOR_SPELL_ID", "技能 ID"), SPELL_ID_X, SECTION_CONTENT_Y, 90)
    CreateLabel(contentSection, Text("TIMELINE_EVENT_EDITOR_SPELL_OCC", "重复序号"), SPELL_OCC_X, SECTION_CONTENT_Y, 90)
    CreateLabel(contentSection, Text("TIMELINE_EVENT_EDITOR_RAID_MARKER", "团队标记"), MARKER_X, SECTION_CONTENT_Y, 90)
    self.controls.spellID = T.CreateEditBox(contentSection, { width = 118, height = 24, point = { "TOPLEFT", contentSection, "TOPLEFT", SPELL_ID_X, CONTROL_ROW_Y } })
    self.controls.spellOcc = T.CreateEditBox(contentSection, { width = 92, height = 24, point = { "TOPLEFT", contentSection, "TOPLEFT", SPELL_OCC_X, CONTROL_ROW_Y } })
    self.controls.marker = T.CreateSelectorButton(contentSection, {
        width = FIELD_WIDTH,
        height = 26,
        point = { "TOPLEFT", contentSection, "TOPLEFT", MARKER_X, CONTROL_ROW_Y },
        label = Text("TIMELINE_EVENT_EDITOR_RAID_MARKER", "团队标记"),
        labelWidth = 74,
        items = MARKER_ITEMS,
        ownerFrame = frame,
    })
    AttachTooltip(self.controls.spellID, {
        title = "技能 ID",
        description = "用于显示技能或触发。",
        concepts = { "spell", "trigger-on-spell", "color-code" },
    })
    AttachTooltip(self.controls.spellOcc, {
        title = "重复序号",
        description = "区分同技能多次出现。",
        concepts = { "trigger-count", "spell" },
    })
    AttachTooltip(self.controls.marker, {
        title = "团队标记",
        description = "给提示加团队标记。",
        concepts = { "team-marker", "color-code", "spell" },
    })

    self.controls.screenReminder = T.CreateSelectorButton(contentSection, {
        width = SECTION_INNER_WIDTH,
        height = 26,
        point = { "TOPLEFT", contentSection, "TOPLEFT", SECTION_PAD_X, -78 },
        label = Text("TIMELINE_EVENT_EDITOR_SCREEN_REMINDER", "屏幕提醒"),
        labelWidth = 74,
        items = BuildScreenReminderItems(),
        ownerFrame = frame,
    })
    AttachTooltip(self.controls.screenReminder, {
        title = "屏幕提醒",
        description = "选择显示样式路由。",
        concepts = { "screen-alert", "indicator-routing", "sr-advance" },
    })

    CreateLabel(contentSection, Text("TIMELINE_EVENT_EDITOR_TEXT", "播报/显示文本"), SECTION_PAD_X, -110, 180)
    self.controls.bodyText = T.CreateEditBox(contentSection, { width = SECTION_INNER_WIDTH, height = 28, point = { "TOPLEFT", contentSection, "TOPLEFT", SECTION_PAD_X, -128 }, multiLine = true })
    AttachTooltip(self.controls.bodyText, {
        title = "播报文本",
        description = "填写要播报的内容。",
        concepts = { "spell", "team-marker", "color-code", "inline-sfx", "remark" },
    })

    local modsSection = CreateSection(frame, Text("TIMELINE_EVENT_EDITOR_SECTION_MODS", "修饰"), -438, 180)
    self.controls.ctEnabled = T.CreateCheckbox(modsSection, { point = { "TOPLEFT", modsSection, "TOPLEFT", SECTION_PAD_X, SECTION_CONTENT_Y }, label = Text("TIMELINE_EVENT_EDITOR_CT", "倒数音效(ct)") })
    self.controls.ctValue = T.CreateEditBox(modsSection, { width = 52, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_LEFT_VALUE_X, SECTION_CONTENT_Y + 2 } })
    AttachTooltip(self.controls.ctEnabled, {
        title = "倒数音效",
        description = "准时点前播放倒数。",
        concepts = { "countdown-audio", "ct", "voice-pack" },
    })
    AttachTooltip(self.controls.ctValue, {
        title = "倒数秒数",
        description = "设置提前几秒倒数。",
        concepts = { "ct", "countdown-audio", "time" },
    })
    self.controls.durEnabled = T.CreateCheckbox(modsSection, { point = { "TOPLEFT", modsSection, "TOPLEFT", RIGHT_COL_X, SECTION_CONTENT_Y }, label = Text("TIMELINE_EVENT_EDITOR_DUR", "持续时长(dur)") })
    self.controls.durValue = T.CreateEditBox(modsSection, { width = 70, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_RIGHT_VALUE_X, SECTION_CONTENT_Y + 2 } })
    AttachTooltip(self.controls.durEnabled, {
        title = "持续条",
        description = "显示一段持续时间。",
        concepts = { "duration-bar", "segment-bar" },
    })
    AttachTooltip(self.controls.durValue, {
        title = "持续秒数",
        description = "填写持续显示秒数。",
        concepts = { "duration-bar", "time" },
    })

    self.controls.leadEnabled = T.CreateCheckbox(modsSection, { point = { "TOPLEFT", modsSection, "TOPLEFT", SECTION_PAD_X, -62 }, label = Text("TIMELINE_EVENT_EDITOR_LEAD", "自定义 TTS 提前(-N 秒)") })
    self.controls.leadValue = T.CreateEditBox(modsSection, { width = 52, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_LEFT_VALUE_X, -60 }, placeholder = "3" })
    AttachTooltip(self.controls.leadEnabled, {
        title = "TTS 提前",
        description = "覆盖本条语音提前量。",
        concepts = { "trigger-advance", "time" },
    })
    AttachTooltip(self.controls.leadValue, {
        title = "提前秒数",
        description = "填写本条提前秒数。",
        concepts = { "trigger-advance", "time" },
    })

    self.controls.srEnabled = T.CreateCheckbox(modsSection, { point = { "TOPLEFT", modsSection, "TOPLEFT", RIGHT_COL_X, -62 }, label = Text("TIMELINE_EVENT_EDITOR_SR", "屏幕提醒提前(sr)") })
    self.controls.srValue = T.CreateEditBox(modsSection, { width = 70, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_RIGHT_VALUE_X, -60 }, placeholder = "3" })
    AttachTooltip(self.controls.srEnabled, {
        title = "屏幕提前",
        description = "覆盖屏幕提醒提前量。",
        concepts = { "sr-advance", "screen-alert" },
    })
    AttachTooltip(self.controls.srValue, {
        title = "屏幕提前秒数",
        description = "填写屏幕提前秒数。",
        concepts = { "sr-advance", "screen-alert", "time" },
    })

    self.controls.barEnabled = T.CreateCheckbox(modsSection, { point = { "TOPLEFT", modsSection, "TOPLEFT", SECTION_PAD_X, -92 }, label = Text("TIMELINE_EVENT_EDITOR_BAR", "进度条(bar)") })
    self.controls.barN = T.CreateEditBox(modsSection, { width = 48, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_AUX_X, -90 }, placeholder = "N" })
    self.controls.barTick = T.CreateEditBox(modsSection, { width = 58, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_AUX_X + 54, -90 }, placeholder = "tick" })
    self.controls.barSpell = T.CreateEditBox(modsSection, { width = 82, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_AUX_X + 118, -90 }, placeholder = "spell" })
    self.controls.barLabel = T.CreateEditBox(modsSection, { width = 92, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_AUX_X + 206, -90 }, placeholder = "label" })
    self.controls.barIcon = T.CreateEditBox(modsSection, { width = 74, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_AUX_X + 304, -90 }, placeholder = "icon" })
    AttachTooltip(self.controls.barEnabled, {
        title = "进度条",
        description = "给事件添加视觉条。",
        concepts = { "duration-bar", "segment-bar", "screen-alert" },
    })

    self.controls.soundEnabled = T.CreateCheckbox(modsSection, { point = { "TOPLEFT", modsSection, "TOPLEFT", SECTION_PAD_X, -122 }, label = Text("TIMELINE_EVENT_EDITOR_SOUND", "音效(@)") })
    self.controls.soundPath = T.CreateEditBox(modsSection, { width = SECTION_PAD_X + SECTION_INNER_WIDTH - MOD_AUX_X, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_AUX_X, -120 }, placeholder = "ding.ogg" })
    AttachTooltip(self.controls.soundEnabled, {
        title = "行内音效",
        description = "播放指定音效文件。",
        concepts = { "inline-sfx", "voice-pack", "countdown-audio" },
    })
    AttachTooltip(self.controls.soundPath, {
        title = "音效文件",
        description = "填写音效文件名。",
        examples = { "ding.ogg" },
        concepts = { "inline-sfx", "voice-pack" },
    })

    CreateLabel(modsSection, Text("TIMELINE_EVENT_EDITOR_NOTE", "备注"), SECTION_PAD_X, -152, 42)
    self.controls.noteText = T.CreateEditBox(modsSection, { width = MOD_NOTE_TEXT_WIDTH, height = 24, point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_AUX_X, -150 }, placeholder = Text("TIMELINE_EVENT_EDITOR_NOTE_PLACEHOLDER", "可选屏幕提示") })
    AttachTooltip(self.controls.noteText, {
        title = "备注",
        description = "补充不播报的说明。",
        concepts = { "remark", "silent-mark", "screen-alert" },
    })
    self.controls.noteStyle = T.CreateSelectorButton(modsSection, {
        width = MOD_NOTE_STYLE_WIDTH,
        height = 26,
        point = { "TOPLEFT", modsSection, "TOPLEFT", MOD_NOTE_STYLE_X, -151 },
        label = "",
        labelWidth = 0,
        items = BuildNoteStyleItems(),
        ownerFrame = frame,
    })
    AttachTooltip(self.controls.noteStyle, {
        title = "备注显示",
        description = "选择备注显示方式。",
        concepts = { "remark", "silent-mark", "screen-alert" },
    })

    local sourceSection = CreateSection(frame, Text("TIMELINE_EVENT_EDITOR_SOURCE", "源文本(只读)"), -622, 70)
    self.controls.preview = T.CreateEditBox(sourceSection, { width = SECTION_INNER_WIDTH, height = 28, point = { "TOPLEFT", sourceSection, "TOPLEFT", SECTION_PAD_X, SECTION_CONTENT_Y }, multiLine = true })
    self.controls.preview:Disable()

    self.controls.test = T.CreateButton(frame, { width = 94, height = 26, point = { "BOTTOMLEFT", frame, "BOTTOMLEFT", SECTION_LEFT + SECTION_PAD_X, 18 } })
    self.controls.test:SetText(Text("TIMELINE_EVENT_EDITOR_TEST_PLAY", "测试播放"))
    self.controls.seek = T.CreateButton(frame, { width = 94, height = 26, point = { "LEFT", self.controls.test, "RIGHT", 8, 0 } })
    self.controls.seek:SetText(Text("TIMELINE_EVENT_EDITOR_SEEK", "跳到此处"))
    self.controls.save = T.CreateButton(frame, { width = 78, height = 26, point = { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -112, 18 } })
    self.controls.save:SetText(Text("TIMELINE_EVENT_EDITOR_SAVE", "保存"))
    self.controls.cancel = T.CreateButton(frame, { width = 78, height = 26, point = { "LEFT", self.controls.save, "RIGHT", 8, 0 } })
    self.controls.cancel:SetText(Text("TIMELINE_EVENT_EDITOR_CANCEL", "取消"))

    self:BindControls()
    return frame
end

function Editor:ReadControls()
    local c = self.controls
    local state = self.state
    if not state then
        return nil
    end
    state.timeSec = ParseTime(c.time:GetText()) or state.timeSec
    state.phase = Trim(c.phase:GetText())
    state.targetKind = c.target:GetSelectedValue() or "all"
    state.customPlayers = c.players:GetText() or ""
    state.spellID = tonumber(c.spellID:GetText())
    state.spellOcc = tonumber(c.spellOcc:GetText())
    state.raidMarker = c.marker:GetSelectedValue()
    state.screenReminderRoute = c.screenReminder:GetSelectedValue() or SCREEN_REMINDER_NONE
    if state.screenReminderRoute ~= SCREEN_REMINDER_CUSTOM then
        state.screenReminderCustomToken = nil
    end
    state.text = c.bodyText:GetText() or ""
    if c.leadEnabled:GetChecked() then
        local lead = tonumber(c.leadValue:GetText())
        state.ttsAdvanceOverride = lead and math.max(0, lead) or nil
    else
        state.ttsAdvanceOverride = nil
    end
    state.noteText = c.noteText:GetText() or ""
    state.noteStyle = c.noteStyle:GetSelectedValue() or "soft"
    state.modifiers = {}
    if c.ctEnabled:GetChecked() then
        state.modifiers.ct = tonumber(c.ctValue:GetText())
    end
    if c.srEnabled:GetChecked() then
        state.modifiers.sr = tonumber(c.srValue:GetText())
    end
    if c.durEnabled:GetChecked() then
        state.modifiers.dur = tonumber(c.durValue:GetText())
    end
    if c.barEnabled:GetChecked() then
        state.modifiers.bar = {
            n = tonumber(c.barN:GetText()),
            tick = tonumber(c.barTick:GetText()),
            spell = tonumber(c.barSpell:GetText()),
            label = c.barLabel:GetText(),
            icon = c.barIcon:GetText(),
        }
    end
    if c.soundEnabled:GetChecked() then
        state.modifiers.sound = c.soundPath:GetText()
    end
    return state
end

function Editor:RefreshHero()
    if not (self.frame and self.frame.hero and self.state) then
        return
    end
    local state = self.state
    local hero = self.frame.hero
    local spellName, spellIcon = ResolveSpellVisual(state.spellID)
    local icon = state.item and state.item.spellIcon or spellIcon
    local title = Trim(spellName or state.text or (state.item and state.item.fullText) or "")
    if title == "" then
        title = state.spellID and ("spellID " .. tostring(state.spellID)) or "未命名事件"
    end

    if icon then
        hero.icon:SetTexture(icon)
        hero.icon:Show()
        hero.iconFallback:Hide()
    else
        hero.icon:SetTexture(nil)
        hero.icon:Hide()
        hero.iconFallback:SetText("?")
        hero.iconFallback:Show()
    end

    FitHeroTitle(hero.title, title)
end

function Editor:RefreshPreview()
    local ok, line = pcall(function()
        return ComposeLine(self:ReadControls())
    end)
    local c = self.controls
    if ok and line and line ~= "" then
        c.preview:SetText(line)
        c.save:Enable()
        self:RefreshHero()
        SetEditEnabled(c.players, c.target:GetSelectedValue() == "players")
        SetEditEnabled(c.ctValue, c.ctEnabled:GetChecked())
        SetEditEnabled(c.srValue, c.srEnabled:GetChecked())
        SetEditEnabled(c.leadValue, c.leadEnabled:GetChecked())
        SetEditEnabled(c.durValue, c.durEnabled:GetChecked())
        local barEnabled = c.barEnabled:GetChecked()
        SetEditEnabled(c.barN, barEnabled)
        SetEditEnabled(c.barTick, barEnabled)
        SetEditEnabled(c.barSpell, barEnabled)
        SetEditEnabled(c.barLabel, barEnabled)
        SetEditEnabled(c.barIcon, barEnabled)
        SetEditEnabled(c.soundPath, c.soundEnabled:GetChecked())
        return
    end
    c.preview:SetText(Text("TIMELINE_EVENT_EDITOR_SERIALIZE_FAILED", "序列化失败"))
    c.save:Disable()
end

function Editor:BindControls()
    local c = self.controls
    local function changed()
        Editor:RefreshPreview()
    end
    for _, edit in ipairs({ c.time, c.phase, c.players, c.spellID, c.spellOcc, c.bodyText, c.ctValue, c.srValue, c.leadValue, c.durValue, c.barN, c.barTick, c.barSpell, c.barLabel, c.barIcon, c.soundPath, c.noteText }) do
        edit:HookScript("OnTextChanged", changed)
    end
    for _, checkbox in ipairs({ c.ctEnabled, c.srEnabled, c.leadEnabled, c.durEnabled, c.barEnabled, c.soundEnabled }) do
        checkbox:HookScript("OnClick", changed)
    end
    c.target.onSelect = changed
    c.marker.onSelect = changed
    c.screenReminder.onSelect = changed
    c.noteStyle.onSelect = changed
    c.cancel:SetScript("OnClick", function()
        Editor.Close()
    end)
    c.save:SetScript("OnClick", function()
        Editor:Save()
    end)
    c.seek:SetScript("OnClick", function()
        local state = Editor:ReadControls()
        if state and T.TimelineRunner and T.TimelineRunner.Seek then
            T.TimelineRunner:Seek(state.timeSec or 0, { silent = true, preserveState = false })
        end
    end)
    c.test:SetScript("OnClick", function()
        local state = Editor:ReadControls()
        local ttsText = state and ResolveTTSTextFromState(state) or ""
        if ttsText ~= "" and T.PlayTTS then
            T.PlayTTS(ttsText)
        end
    end)
end

function Editor:HydrateControls(state)
    local c = self.controls
    c.time:SetText(FormatTime(state.timeSec))
    c.phase:SetText(state.phase or "")
    c.target:SetSelectedValue(state.targetKind or "all")
    c.players:SetText(state.customPlayers or "")
    c.spellID:SetText(state.spellID and tostring(state.spellID) or "")
    c.spellOcc:SetText(state.spellOcc and tostring(state.spellOcc) or "")
    c.screenReminder:SetItems(BuildScreenReminderItems(state.screenReminderRoute))
    c.screenReminder:SetSelectedValue(state.screenReminderRoute or SCREEN_REMINDER_NONE)
    c.bodyText:SetText(state.text or "")
    c.marker:SetSelectedValue(state.raidMarker or "")
    c.leadEnabled:SetChecked(state.ttsAdvanceOverride ~= nil)
    c.leadValue:SetText(state.ttsAdvanceOverride ~= nil and FormatNumber(state.ttsAdvanceOverride) or "3")
    c.noteText:SetText(state.noteText or "")
    c.noteStyle:SetSelectedValue(state.noteStyle or "soft")
    c.ctEnabled:SetChecked(state.modifiers and state.modifiers.ct ~= nil)
    c.ctValue:SetText(state.modifiers and state.modifiers.ct and tostring(state.modifiers.ct) or "3")
    c.srEnabled:SetChecked(state.modifiers and state.modifiers.sr ~= nil)
    c.srValue:SetText(state.modifiers and state.modifiers.sr and FormatNumber(state.modifiers.sr) or "3")
    c.durEnabled:SetChecked(state.modifiers and state.modifiers.dur ~= nil)
    c.durValue:SetText(state.modifiers and state.modifiers.dur and FormatNumber(state.modifiers.dur) or "")
    local bar = state.modifiers and state.modifiers.bar or nil
    c.barEnabled:SetChecked(type(bar) == "table")
    c.barN:SetText(bar and bar.n and FormatNumber(bar.n) or "")
    c.barTick:SetText(bar and bar.tick and FormatNumber(bar.tick) or "")
    c.barSpell:SetText(bar and bar.spell and tostring(bar.spell) or "")
    c.barLabel:SetText(bar and bar.label or "")
    c.barIcon:SetText(bar and bar.icon and tostring(bar.icon) or "")
    c.soundEnabled:SetChecked(state.modifiers and Trim(state.modifiers.sound) ~= "")
    c.soundPath:SetText(state.modifiers and state.modifiers.sound or "")
    self:RefreshPreview()
end

function Editor:BuildState(item, resolved, parsed)
    local sourceSegments = SplitSourceSegments(resolved.line)
    local segmentIndex = FindSegmentIndex(parsed, item) or 1
    local segmentText = sourceSegments[segmentIndex] or sourceSegments[1] or tostring(item and item.sourceSegmentText or "")
    if Trim(segmentText) == "" and parsed and parsed.segments and parsed.segments[segmentIndex] then
        segmentText = parsed.segments[segmentIndex].rawText or parsed.segments[segmentIndex].text or ""
    end
    local segmentState = ParseSegment(segmentText)
    segmentState.timeSec = tonumber(parsed and parsed.time) or tonumber(item and item.sourceTime) or tonumber(item and item.time) or 0
    local itemPhase = T.HorizontalTimelineData and T.HorizontalTimelineData.ExtractPhaseFromTimePayload
        and T.HorizontalTimelineData.ExtractPhaseFromTimePayload(item and item.timePayload)
        or nil
    segmentState.phase = parsed and parsed.phase or itemPhase or ""
    segmentState.ttsAdvanceOverride = parsed and parsed.ttsAdvanceOverride or nil
    segmentState.item = item
    segmentState.lineNum = resolved.lineNum
    segmentState.originalLine = resolved.line
    segmentState.sourceSegments = sourceSegments
    segmentState.segmentIndex = segmentIndex
    return segmentState
end

function Editor:Save()
    local state = self:ReadControls()
    local ok, newLine = pcall(function()
        return ComposeLine(state)
    end)
    if not ok or Trim(newLine) == "" then
        Msg(Text("TIMELINE_EVENT_EDITOR_SERIALIZE_FAILED", "序列化失败"))
        return
    end
    if not (T.SemanticTimelineGUI and T.SemanticTimelineGUI.RewriteTimelineItemLine) then
        Msg(Text("TIMELINE_EVENT_EDITOR_SAVE_FAILED", "保存失败"))
        return
    end
    local saved, reason = T.SemanticTimelineGUI.RewriteTimelineItemLine(state.item, newLine)
    if saved then
        Debug("save line=" .. tostring(state.lineNum))
        Editor.Close()
        return
    end
    Msg((Text("TIMELINE_EVENT_EDITOR_SAVE_FAILED", "保存失败")) .. ": " .. tostring(reason or "unknown"))
end

function Editor.Open(item)
    if type(item) ~= "table" then
        Msg(Text("TIMELINE_EVENT_EDITOR_OPEN_FAILED", "无法打开事件编辑器"))
        return
    end
    local gui = T.SemanticTimelineGUI
    if not (gui and gui.GetTimelineItemLine) then
        Msg(Text("TIMELINE_EVENT_EDITOR_OPEN_FAILED", "无法打开事件编辑器"))
        return
    end
    local resolved, reason = gui.GetTimelineItemLine(item, "event_editor_open")
    if not resolved then
        Msg((Text("TIMELINE_EVENT_EDITOR_OPEN_FAILED", "无法打开事件编辑器")) .. ": " .. tostring(reason or "unknown"))
        return
    end
    local syntax = T.TimelineSyntax
    local parsed = syntax and syntax.ParseTimelineLine and syntax.ParseTimelineLine(resolved.line) or nil
    if not parsed then
        Msg(Text("TIMELINE_EVENT_EDITOR_PARSE_FAILED", "解析失败，无法编辑这一行"))
        return
    end

    local frame = Editor:EnsureFrame()
    Editor.state = Editor:BuildState(item, resolved, parsed)
    Editor:HydrateControls(Editor.state)
    frame.title:SetText(Text("TIMELINE_EVENT_EDITOR_TITLE", "编辑事件") .. " · " .. FormatTime(Editor.state.timeSec))
    frame:Show()
    Debug("open line=" .. tostring(resolved.lineNum) .. " segment=" .. tostring(Editor.state.segmentIndex))
end

function Editor.Close()
    if Editor.frame then
        Editor.frame:Hide()
    end
    Editor.state = nil
end

end)
