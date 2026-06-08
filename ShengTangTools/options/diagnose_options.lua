local T, C, L = unpack(select(2, ...))

local CARD_GAP = 12
local HEADER_HEIGHT = 42
local STEP_HEIGHT = 132
local STEP2_HEIGHT = 190
local STEP3_HEIGHT = 156
local GUIDE_URL = "https://docs.qq.com/doc/DSFBSRk94TGdDRHNn?nlc=1"

local STATUS_OK = "|cff22c55e●|r"
local STATUS_WARN = "|cfffacc15●|r"
local STATUS_BAD = "|cffff5555●|r"

local function BuildDiagnoseItems()
local function Text(key, fallback)
    local value = key and rawget(L, key)
    if value ~= nil then
        return value
    end
    return fallback or key
end

local function Debug(message, ...)
    if T.debug then
        T.debug("[Diagnose] " .. string.format(message, ...))
    end
end

local function SetStatus(fontString, dot, text)
    if fontString then
        fontString:SetText(string.format("%s %s", dot or STATUS_WARN, text or ""))
    end
end

local function IsTTSEnabled()
    return not (C and C.DB and C.DB.ttsEnabled == false)
end

local function ApplyRealtimeBoard()
    if T.RealtimeBoard and T.RealtimeBoard.RefreshConfig then
        T.RealtimeBoard:RefreshConfig()
    end
end

local function GetShowAllEvents()
    return C and C.DB and C.DB.realtimeBoard and C.DB.realtimeBoard.showAllEvents == true
end

local function SetShowAllEvents(value)
    C.DB.realtimeBoard = C.DB.realtimeBoard or {}
    C.DB.realtimeBoard.showAllEvents = value == true
    if type(STT_DB) == "table" then
        STT_DB.realtimeBoard = C.DB.realtimeBoard
    end
    ApplyRealtimeBoard()
    if T.OptionEngine and T.OptionEngine.RefreshWidgetValues then
        T.OptionEngine:RefreshWidgetValues()
    end
    Debug("ShowAllEvents value=%s", tostring(C.DB.realtimeBoard.showAllEvents))
end

local function TestTTS(status)
    local ok, result = pcall(function()
        if not T.Speaker or not T.Speaker.Enqueue then
            return false
        end
        return T.Speaker:Enqueue(Text("GUI_DIAGNOSE_STEP1_PROBE_TEXT"))
    end)

    if ok and result then
        SetStatus(status, STATUS_OK, Text("GUI_DIAGNOSE_STEP1_OK"))
        Debug("TestTTS result=queued")
        return true
    end

    SetStatus(status, STATUS_BAD, Text("GUI_DIAGNOSE_STEP1_FAIL"))
    if T.msg then
        T.msg(Text("GUI_DIAGNOSE_STEP1_FAIL"))
    end
    Debug("TestTTS result=failed error=%s", tostring(ok and result or result))
    return false
end

local function ResolveEventTTSText(event)
    if T.NoteParser and T.NoteParser.GetResolvedEventTTSText then
        return T.NoteParser:GetResolvedEventTTSText(event) or ""
    end
    return ""
end

local function HasDisplayOnlyPayload(event)
    if type(event) ~= "table" then
        return false
    end

    local modifiers = type(event.modifiers) == "table" and event.modifiers or nil
    if modifiers and (modifiers.bar or modifiers.ct or modifiers.sound) then
        return true
    end
    if type(event.visualBoards) == "table" and #event.visualBoards > 0 then
        return true
    end
    if T.NoteParser and T.NoteParser.GetResolvedEventScreenText then
        return (T.NoteParser:GetResolvedEventScreenText(event) or "") ~= ""
    end
    return false
end

local function CollectHitsFromText(result, text, opts)
    local ok, parsed = pcall(function()
        return T.NoteParser:ParseNote(text, opts and opts.parseOpts or nil)
    end)
    if not ok or type(parsed) ~= "table" then
        Debug("CollectHitsFromText result=parse_failed error=%s", tostring(parsed))
        return false
    end

    for _, event in ipairs(parsed) do
        if opts and opts.personal then
            event.isPersonal = true
        end
        if T.NoteParser:ShouldTriggerEvent(event) then
            local speakText = ResolveEventTTSText(event)
            if speakText ~= "" then
                result.events[#result.events + 1] = {
                    event = event,
                    text = speakText,
                }
            elseif HasDisplayOnlyPayload(event) then
                result.displayEvents[#result.displayEvents + 1] = {
                    event = event,
                }
            end
        end
    end

    return true
end

local function ScanSTNBundleHits(result, bundle)
    if type(bundle) ~= "table" then
        return false
    end

    local resolveSource = bundle.resolveSource or "team_plus_personal"
    local scanned = false
    if resolveSource ~= "personal" then
        local teamText = tostring(bundle.runtimeTeamText or bundle.teamText or "")
        if teamText ~= "" then
            scanned = CollectHitsFromText(result, teamText) or scanned
        end
    end
    if resolveSource ~= "team" then
        local personalText = tostring(bundle.personalText or "")
        if personalText ~= "" then
            scanned = CollectHitsFromText(result, personalText, {
                personal = true,
                parseOpts = { relaxed = true },
            }) or scanned
        end
    end
    return scanned
end

local function ScanSelfHits()
    if not (T.GetTimelineSourceText and T.NoteParser and T.NoteParser.ParseNote and T.NoteParser.ShouldTriggerEvent) then
        Debug("ScanSelfHits result=module_missing")
        return { ttsHits = 0, displayHits = 0, events = {}, displayEvents = {}, reason = "module_missing" }
    end

    local text, source, bundle = T.GetTimelineSourceText({ silent = true })
    if type(text) ~= "string" or text == "" then
        Debug("ScanSelfHits result=no_source source=%s", tostring(source))
        return { ttsHits = 0, displayHits = 0, events = {}, displayEvents = {}, reason = "no_source", source = source }
    end

    local result = {
        events = {},
        displayEvents = {},
    }
    local scanned = source == "STN" and ScanSTNBundleHits(result, bundle)
    if not scanned and not CollectHitsFromText(result, text) then
        return { ttsHits = 0, displayHits = 0, events = {}, displayEvents = {}, reason = "parse_failed", source = source }
    end

    local ttsEvents = result.events
    local displayEvents = result.displayEvents
    local reason = "no_hit"
    if #ttsEvents > 0 then
        reason = "ok"
    elseif #displayEvents > 0 then
        reason = "display_only"
    end

    return {
        count = #ttsEvents,
        ttsHits = #ttsEvents,
        displayHits = #displayEvents,
        events = ttsEvents,
        displayEvents = displayEvents,
        reason = reason,
        source = source,
    }
end

local function PlaySelfHits(status, button)
    local result = ScanSelfHits()
    if result.ttsHits <= 0 then
        local message
        local dot = STATUS_BAD
        if result.reason == "no_source" then
            message = Text("GUI_DIAGNOSE_STEP2_EMPTY")
            dot = STATUS_WARN
        elseif result.displayHits > 0 then
            message = string.format(Text("GUI_DIAGNOSE_STEP2_DISPLAY_FMT"), result.displayHits)
            dot = STATUS_WARN
        else
            message = Text("GUI_DIAGNOSE_STEP2_NOHIT")
        end
        SetStatus(status, dot, message)
        if button then
            button:Disable()
        end
        if T.msg then
            T.msg(message)
        end
        return false
    end

    for _, item in ipairs(result.events) do
        if T.Speaker and T.Speaker.Enqueue then
            T.Speaker:Enqueue(item.text)
        end
    end
    SetStatus(status, STATUS_OK, string.format(Text("GUI_DIAGNOSE_STEP2_HIT_FMT"), result.ttsHits))
    if button then
        button:Enable()
    end
    Debug("PlaySelfHits queued=%d", result.ttsHits)
    return true
end

local function TestRealtimeBoard(status)
    if not (T.RealtimeBoard and T.RealtimeBoard.RunTest) then
        SetStatus(status, STATUS_BAD, Text("GUI_DIAGNOSE_STEP3_UNAVAILABLE"))
        Debug("TestRealtimeBoard result=module_missing")
        return false
    end

    local ok, result = pcall(function()
        return T.RealtimeBoard:RunTest()
    end)
    if ok and result ~= false then
        Debug("TestRealtimeBoard result=started")
        return true
    end

    SetStatus(status, STATUS_WARN, Text("GUI_DIAGNOSE_STEP3_TEST_FAIL"))
    Debug("TestRealtimeBoard result=failed error=%s", tostring(ok and result or result))
    return false
end

local function StopRealtimeBoardTest(status)
    if T.TimelineRunner and T.TimelineRunner.Stop then
        T.TimelineRunner:Stop()
        SetStatus(status, STATUS_WARN, Text("测试结束"))
        return
    end
    if T.RealtimeBoard and T.RealtimeBoard.Stop then
        T.RealtimeBoard:Stop("manual_stop")
        SetStatus(status, STATUS_WARN, Text("测试结束"))
    end
end

local function CreateCard(parent, y, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    frame:SetSize(width, height)
    T.ApplyBackdrop(frame, {
        alpha = 0.28,
        style = "chat",
        borderColor = { 0.62, 0.52, 0.2, 0.55 },
    })
    return frame
end

local function CreateReadonlyLinkBox(parent, point, width)
    local editBox = T.CreateEditBox(parent, {
        point = point,
        width = width,
        height = 24,
    })

    local function SelectLink(self)
        self:SetText(GUIDE_URL)
        self:SetCursorPosition(0)
        self:HighlightText()
    end

    editBox:SetText(GUIDE_URL)
    editBox:SetCursorPosition(0)
    editBox:SetScript("OnEditFocusGained", SelectLink)
    editBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        SelectLink(self)
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetCursorPosition(0)
        self:HighlightText(0, 0)
    end)
    editBox:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= GUIDE_URL then
            SelectLink(self)
        end
    end)
    return editBox
end

local function RenderHeader(parent, y, width)
    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", 0, y },
        width = width,
        text = Text("GUI_DIAGNOSE_HEADER"),
        size = 13,
        wordWrap = true,
        color = { 0.92, 0.86, 0.68, 1 },
    })
    return y - HEADER_HEIGHT
end

local function RenderStep1(parent, y, width, refreshers)
    local card = CreateCard(parent, y, width, STEP_HEIGHT)
    T.CreateGroupTitle(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -12 },
        text = Text("GUI_DIAGNOSE_STEP1_TITLE"),
        fontSize = 14,
    })
    local status = T.CreateLabel(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -36 },
        width = width - 28,
        size = 12,
        text = "",
        color = { 1, 1, 1, 1 },
    })
    T.CreateLabel(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -60 },
        width = width - 28,
        size = 12,
        wordWrap = true,
        text = Text("GUI_DIAGNOSE_STEP1_DESC"),
        color = { 0.82, 0.82, 0.82, 1 },
    })
    local button = T.CreateActionButton(card, {
        point = { "BOTTOMLEFT", card, "BOTTOMLEFT", 14, 14 },
        width = 160,
        height = 26,
        textFn = function()
            return Text("GUI_DIAGNOSE_STEP1_BUTTON")
        end,
        onClick = function()
            TestTTS(status)
        end,
    })
    button:Refresh()

    local function Refresh()
        SetStatus(status, IsTTSEnabled() and STATUS_OK or STATUS_BAD,
            IsTTSEnabled() and Text("GUI_DIAGNOSE_STEP1_OK") or Text("GUI_DIAGNOSE_STEP1_OFF"))
    end
    refreshers[#refreshers + 1] = Refresh
    Refresh()
    return y - STEP_HEIGHT - CARD_GAP
end

local function RenderStep2(parent, y, width)
    local card = CreateCard(parent, y, width, STEP2_HEIGHT)
    T.CreateGroupTitle(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -12 },
        text = Text("GUI_DIAGNOSE_STEP2_TITLE"),
        fontSize = 14,
    })
    local status = T.CreateLabel(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -36 },
        width = width - 28,
        size = 12,
        text = "",
        color = { 1, 1, 1, 1 },
    })
    T.CreateLabel(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -60 },
        width = width - 28,
        size = 12,
        wordWrap = true,
        text = Text("GUI_DIAGNOSE_STEP2_DESC"),
        color = { 0.82, 0.82, 0.82, 1 },
    })
    local guide = T.CreateLabel(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -94 },
        width = width - 28,
        size = 12,
        text = Text("GUI_DIAGNOSE_STEP2_GUIDE"),
        color = { 0.64, 0.8, 1, 1 },
    })
    guide:SetJustifyH("LEFT")

    CreateReadonlyLinkBox(card, { "TOPLEFT", card, "TOPLEFT", 14, -116 }, math.min(width - 28, 520))

    local playButton
    local function RefreshScan()
        local result = ScanSelfHits()
        if result.ttsHits > 0 then
            SetStatus(status, STATUS_OK, string.format(Text("GUI_DIAGNOSE_STEP2_HIT_FMT"), result.ttsHits))
            if playButton then
                playButton:Enable()
            end
        elseif result.displayHits > 0 then
            SetStatus(status, STATUS_WARN, string.format(Text("GUI_DIAGNOSE_STEP2_DISPLAY_FMT"), result.displayHits))
            if playButton then
                playButton:Disable()
            end
        elseif result.reason == "no_source" then
            SetStatus(status, STATUS_WARN, Text("GUI_DIAGNOSE_STEP2_EMPTY"))
            if playButton then
                playButton:Disable()
            end
        else
            SetStatus(status, STATUS_BAD, Text("GUI_DIAGNOSE_STEP2_NOHIT"))
            if playButton then
                playButton:Disable()
            end
        end
    end

    playButton = T.CreateActionButton(card, {
        point = { "BOTTOMLEFT", card, "BOTTOMLEFT", 14, 14 },
        width = 260,
        height = 26,
        textFn = function()
            return Text("GUI_DIAGNOSE_STEP2_BUTTON")
        end,
        onClick = function()
            PlaySelfHits(status, playButton)
        end,
    })
    playButton:Refresh()
    RefreshScan()
    return y - STEP2_HEIGHT - CARD_GAP
end

local function RenderStep3(parent, y, width, refreshers)
    local card = CreateCard(parent, y, width, STEP3_HEIGHT)
    T.CreateGroupTitle(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -12 },
        text = Text("GUI_DIAGNOSE_STEP3_TITLE"),
        fontSize = 14,
    })
    local status = T.CreateLabel(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -36 },
        width = width - 28,
        size = 12,
        text = "",
        color = { 1, 1, 1, 1 },
    })
    local desc = T.CreateLabel(card, {
        point = { "TOPLEFT", card, "TOPLEFT", 14, -60 },
        width = width - 28,
        size = 12,
        wordWrap = true,
        text = "",
        color = { 0.82, 0.82, 0.82, 1 },
    })

    local function RefreshShowAll()
        local showAll = GetShowAllEvents()
        SetStatus(status, showAll and STATUS_OK or STATUS_WARN,
            showAll and Text("GUI_DIAGNOSE_STEP3_STATUS_ALL") or Text("GUI_DIAGNOSE_STEP3_STATUS_FILTERED"))
        desc:SetText(showAll and Text("GUI_DIAGNOSE_STEP3_DESC_ALL") or Text("GUI_DIAGNOSE_STEP3_DESC_FILTERED"))
    end

    local checkbox = T.CreateCheckbox(card, {
        point = { "BOTTOMLEFT", card, "BOTTOMLEFT", 14, 48 },
        label = Text("GUI_DIAGNOSE_STEP3_TOGGLE"),
        getter = GetShowAllEvents,
        setter = function(value)
            SetShowAllEvents(value)
        end,
        onApply = RefreshShowAll,
    })
    checkbox.Refresh()

    local button = T.CreateActionButton(card, {
        point = { "BOTTOMLEFT", card, "BOTTOMLEFT", 14, 14 },
        width = 190,
        height = 26,
        textFn = function()
            return Text("GUI_DIAGNOSE_STEP3_BUTTON")
        end,
        onClick = function()
            TestRealtimeBoard(status)
        end,
    })
    button:Refresh()
    if not (T.RealtimeBoard and T.RealtimeBoard.RunTest) then
        button:Disable()
    end

    local stopButton = T.CreateActionButton(card, {
        point = { "BOTTOMLEFT", card, "BOTTOMLEFT", 218, 14 },
        width = 140,
        height = 26,
        textFn = function()
            return Text("GUI_BOARD_STOP_TEST")
        end,
        onClick = function()
            StopRealtimeBoardTest(status)
        end,
    })
    stopButton:Refresh()
    if not ((T.TimelineRunner and T.TimelineRunner.Stop) or (T.RealtimeBoard and T.RealtimeBoard.Stop)) then
        stopButton:Disable()
    end

    local function Refresh()
        checkbox:Refresh()
        RefreshShowAll()
    end
    refreshers[#refreshers + 1] = Refresh
    Refresh()
    return y - STEP3_HEIGHT - CARD_GAP
end

local function RenderDiagnosePanel(slot, ctx)
    local width = math.max(1, tonumber(ctx and ctx.width) or slot:GetWidth() or 650)
    local refreshers = {}
    local y = 0
    y = RenderHeader(slot, y, width)
    y = RenderStep1(slot, y, width, refreshers)
    y = RenderStep2(slot, y, width)
    y = RenderStep3(slot, y, width, refreshers)
    return {
        height = math.abs(y) + 4,
        setEnabled = function() end,
        refresh = function()
            for _, refresh in ipairs(refreshers) do
                refresh()
            end
        end,
    }
end

    T.Diagnose = T.Diagnose or {}
    T.Diagnose.ScanSelfHits = ScanSelfHits

    return {
    {
        key = "diagnosePanel",
        type = "custom",
        textKey = "GUI_NAV_DIAGNOSE",
        width = 1,
        render = RenderDiagnosePanel,
        height = HEADER_HEIGHT + STEP_HEIGHT + STEP2_HEIGHT + STEP3_HEIGHT + CARD_GAP * 3 + 4,
    },
    }
end

T.RegisterOptionModule({
    id = "diagnose",
    category = "tactic",
    order = 5,
    titleKey = "GUI_NAV_DIAGNOSE",
    itemsFactory = BuildDiagnoseItems,
})
