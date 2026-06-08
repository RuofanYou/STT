local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.editorLoaded", "screenReminder.enabled", "realtimeBoard.enabled", "buffCheck.enabled", "raidCommandPanel.enabled", "rosterPlanner.enabled", "dreadElegy.enabled", "tacticTranslator.enabled"}, function()

local UITooltip = T.UITooltip or {}
T.UITooltip = UITooltip

local MAX_LEVEL = 6
local WIDTH_ROOT = 320
local WIDTH_CONCEPT = 260
local MIN_TIMELINE_TOOLTIP_WIDTH = 220
local PADDING = 12
local GAP = 8
local LINE_GAP = 5
local TOKEN_GAP = 6
local TRANSIT_MARGIN = 18

local COLORS = {
    title = { 1, 0.82, 0 },
    desc = { 1, 1, 1 },
    body = { 0.86, 0.88, 0.92 },
    example = { 0.45, 1, 0.45 },
    tips = { 0.52, 0.78, 1 },
    hint = { 0.62, 0.62, 0.62 },
    token = { 0.5, 0.83, 1 },
}

local ALIAS_TO_KEY = {
    target = "audience",
    ["{谁}"] = "audience",
    ["谁"] = "audience",
    scope = "scheme-team",
    ["团长方案"] = "scheme-team",
    ["私人方案"] = "scheme-personal",
    ["mrt-nsrt-stt"] = "format-comparison",
    bar = "duration-bar",
    sr = "screen-alert",
    tank = "role-tank",
    T = "role-tank",
    ["坦克"] = "role-tank",
    healer = "role-healer",
    heal = "role-healer",
    ["治疗"] = "role-healer",
    ["奶妈"] = "role-healer",
    dps = "role-dps",
    dd = "role-dps",
    ["输出"] = "role-dps",
    melee = "role-melee",
    ["近战"] = "role-melee",
    ranged = "role-ranged",
    ["远程"] = "role-ranged",
    BOSS = "boss-display",
    boss = "boss-display",
    dur = "duration-modifier",
    to = "indicator-routing",
    rt = "team-marker",
    red = "color-code",
    ["{全团}"] = "audience-all",
    ["{all}"] = "audience-all",
    ["{everyone}"] = "audience-all",
    ["{所有人}"] = "audience-all",
    ["所有人"] = "audience-all",
    all = "audience-all",
    everyone = "audience-all",
}

local BORDER_PENDING = { 0.46, 0.46, 0.52, 0.95 }
local BORDER_LOCKED = { 1, 0.82, 0.18, 1 }

local pool = {}
local chain = { stack = {}, owner = nil, locked = false }
local currentPayload
local currentOpts
local helpFrame
local debugAnchor
local modifierFrame
local timelineTooltipResetHooked = false
local LockNode
local UnlockNode
local AnyMouseOver

local function Debug(text)
    if T.debug then
        T.debug("[UITooltip] " .. tostring(text or ""))
    end
end

local function SetNodeMouseEnabled(node, enabled)
    if node and node.frame and node.frame.EnableMouse then
        node.frame:EnableMouse(enabled == true)
    end
end

local function CancelLock()
    for _, node in pairs(pool) do
        if node then
            node.locked = false
            SetNodeMouseEnabled(node, false)
        end
    end
    chain.locked = false
end

local function SetColor(fs, color)
    color = color or COLORS.desc
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function Trim(text)
    return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function MapAlias(rawKey)
    local key = Trim(rawKey)
    if key == "" then
        return key
    end
    local mapped = ALIAS_TO_KEY[key]
    if mapped then
        return mapped
    end
    local lower = key:lower()
    mapped = ALIAS_TO_KEY[lower]
    if mapped then
        return mapped
    end
    return key
end

local function ResolveConcept(rawKey)
    local registry = T.TooltipConcepts and T.TooltipConcepts.registry or {}
    local key = MapAlias(rawKey)
    if registry[key] then
        return key, registry[key]
    end

    local base = key:match("^([^:,]+)")
    base = base and MapAlias(base) or base
    if base and registry[base] then
        return base, registry[base]
    end

    for conceptKey, def in pairs(registry) do
        if type(def) == "table" and def.pattern then
            local captures = { key:match(def.pattern) }
            if #captures > 0 then
                return conceptKey, def, captures
            end
        end
    end
    return key, nil
end

local function RenderText(value, captures)
    if type(value) == "function" then
        return value(unpack(captures or {}))
    end
    if type(value) == "string" and L[value] then
        return L[value]
    end
    return tostring(value or "")
end

local function GetConceptTitle(rawKey, fallback)
    local _, def, captures = ResolveConcept(rawKey)
    if not def then
        return tostring(fallback or rawKey or "")
    end
    return RenderText(def.titleKey or def.title or fallback or rawKey, captures)
end

local function NormalizeBraceKey(inner)
    local value = Trim(inner)
    if value == "time" then
        return "time"
    end
    if value:match("^time:") then
        return value
    end
    if value == "spell" then
        return "spell"
    end
    if value:match("^spell:") then
        return "spell"
    end
    if value == "on" or value:match("^on:") then
        return "trigger-axis"
    end
    if value == "ct" then
        return "ct"
    end
    if value:match("^ct:") then
        return "ct"
    end
    if value == "bar" then
        return "duration-bar"
    end
    if value:match("^bar:") then
        return "duration-bar"
    end
    if value == "dur" or value:match("^dur:") or value:match("[,:]dur:") then
        return "duration-modifier"
    end
    if value == "sr" then
        return "screen-alert"
    end
    if value:match("^sr:") then
        return "screen-alert"
    end
    if value == "to" or value:match("^to:") then
        return "indicator-routing"
    end
    if value:match("^rt%d+$") then
        return "team-marker"
    end
    if value:match("^@") then
        return "inline-sfx"
    end
    if value:match("^[pP]%d+r?%d*$") then
        return value:lower()
    end
    if value == "pN" or value == "pn" then
        return "pN"
    end
    local mapped = MapAlias(value)
    local conceptKey, def = ResolveConcept(mapped)
    if def then
        return conceptKey
    end
    return "audience"
end

local function AddUniqueToken(tokens, seen, key, label, allowedConcepts)
    key = Trim(key)
    label = tostring(label or key)
    if key == "" or seen[key .. "\001" .. label] then
        return
    end
    local conceptKey, def = ResolveConcept(key)
    if not def then
        return
    end
    if allowedConcepts and not allowedConcepts[conceptKey] then
        return
    end
    seen[key .. "\001" .. label] = true
    tokens[#tokens + 1] = { key = key, label = label }
end

local function ExtractTokens(text, allowedConcepts)
    local tokens, seen = {}, {}
    text = tostring(text or "")
    text:gsub("{([^{}]+)}", function(inner)
        AddUniqueToken(tokens, seen, NormalizeBraceKey(inner), "{" .. inner .. "}", allowedConcepts)
    end)
    text:gsub("%f[%w](p%d+r?%d*)%f[%W]", function(token)
        AddUniqueToken(tokens, seen, token:lower(), token, allowedConcepts)
    end)
    text:gsub("%f[%w](pN)%f[%W]", function(token)
        AddUniqueToken(tokens, seen, "pN", token, allowedConcepts)
    end)
    return tokens
end

function UITooltip.FormatLine(text)
    text = tostring(text or "")
    if text == "" then
        return text
    end
    text = text:gsub("({([^{}]+)})", function(full, inner)
        local key = NormalizeBraceKey(inner)
        local conceptKey, def = ResolveConcept(key)
        if def then
            return ("|cff7fd4ff|Hstt:concept:%s|h%s|h|r"):format(conceptKey, full)
        end
        return full
    end)
    text = text:gsub("%f[%w](p%d+r?%d*)%f[%W]", function(token)
        local conceptKey, def = ResolveConcept(token:lower())
        if def then
            return ("|cff7fd4ff|Hstt:concept:%s|h[%s]|h|r"):format(conceptKey, token)
        end
        return token
    end)
    text = text:gsub("%f[%w](pN)%f[%W]", function(token)
        local conceptKey, def = ResolveConcept(token)
        if def then
            return ("|cff7fd4ff|Hstt:concept:%s|h[%s]|h|r"):format(conceptKey, token)
        end
        return token
    end)
    return text
end

function UITooltip.RegisterConcept(key, def)
    if type(key) ~= "string" or key == "" or type(def) ~= "table" then
        return
    end
    T.TooltipConcepts = T.TooltipConcepts or {}
    T.TooltipConcepts.registry = T.TooltipConcepts.registry or {}
    T.TooltipConcepts.registry[key] = def
end

local function CreateNode(level)
    local frame = CreateFrame("Frame", "STTTooltipFrame" .. tostring(level), UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()
    if T.ApplyBackdrop then
        T.ApplyBackdrop(frame, { alpha = 0.94, style = "tooltip" })
    elseif frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.94)
        frame:SetBackdropBorderColor(0.46, 0.46, 0.52, 1)
    end

    local node = {
        level = level,
        frame = frame,
        textSurface = frame,
        widgets = {},
        fontStrings = {},
        tokenButtons = {},
        lastHoverAt = 0,
        locked = false,
        lockSource = nil,
    }

    node.lockBadge = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    node.lockBadge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -8)
    node.lockBadge:SetJustifyH("RIGHT")

    frame.__sttTooltipNode = node
    frame:SetScript("OnEnter", function(self)
        local current = self.__sttTooltipNode
        if current then
            current.lastHoverAt = GetTime and GetTime() or 0
        end
    end)
    frame:SetScript("OnLeave", function()
        UITooltip.ScheduleChainHide("frame-leave")
    end)
    frame:SetScript("OnHide", function()
        if frame.__sttTooltipNode then
            frame.__sttTooltipNode.conceptKey = nil
            frame.__sttTooltipNode.parent = nil
            frame.__sttTooltipNode.lockSource = nil
            frame.__sttTooltipNode.locked = false
            SetNodeMouseEnabled(frame.__sttTooltipNode, false)
        end
    end)

    return node
end

local function SetNodeLockedVisual(node, locked)
    if not node or not node.frame then
        return
    end
    if node.frame.sd and node.frame.sd.SetBackdropBorderColor then
        local color = locked and BORDER_LOCKED or BORDER_PENDING
        node.frame.sd:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
    elseif node.frame.SetBackdropBorderColor then
        local color = locked and BORDER_LOCKED or BORDER_PENDING
        node.frame:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
    end
    if node.lockBadge then
        if locked then
            node.lockBadge:SetText("|cffffd24aAlt锁定|r")
        else
            node.lockBadge:SetText("|cff888888按住Alt锁定|r")
        end
        node.lockBadge:Show()
    end
end

LockNode = function(node)
    if not (node and node.frame and node.frame:IsShown()) then
        return
    end
    node.locked = true
    SetNodeMouseEnabled(node, true)
    SetNodeLockedVisual(node, true)
end

UnlockNode = function(node)
    if not (node and node.frame and node.frame:IsShown()) then
        return
    end
    node.locked = false
    SetNodeMouseEnabled(node, false)
    SetNodeLockedVisual(node, false)
end

local function RefreshChainVisual()
    for _, node in ipairs(chain.stack) do
        if node and node.frame and node.frame:IsShown() then
            SetNodeLockedVisual(node, node.locked)
        end
    end
end

local function IsAltLockActive()
    return IsAltKeyDown and IsAltKeyDown() == true
end

local function AcquireNode(level)
    if level > MAX_LEVEL then
        Debug("拒绝展开过深 Tooltip：" .. tostring(level))
        return nil
    end
    if not pool[level] then
        pool[level] = CreateNode(level)
    end
    return pool[level]
end

local function HideWidget(widget)
    if widget and widget.Hide then
        widget:Hide()
    end
end

local function ResetNode(node)
    for _, widget in ipairs(node.widgets) do
        HideWidget(widget)
    end
    node.widgets = {}
    node.fsIndex = 0
    node.btnIndex = 0
    node.cursorY = -PADDING
    node.measureCache = {}
    if node.lockBadge then
        node.lockBadge:Show()
    end
end

local function GetFrameRect(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
        return nil
    end
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    if not (left and right and top and bottom) then
        return nil
    end
    return left, right, top, bottom
end
T.GetFrameRect = T.GetFrameRect or GetFrameRect

local function IsCursorInRect(left, right, top, bottom, margin)
    if not GetCursorPosition or not UIParent or not UIParent.GetEffectiveScale then
        return false
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    if scale == 0 then
        scale = 1
    end
    x = x / scale
    y = y / scale
    margin = margin or 0
    return x >= left - margin and x <= right + margin and y <= top + margin and y >= bottom - margin
end

local function IsInLockedTransitPath(node)
    if not (node and node.locked and node.lockSource and node.frame and node.frame:IsShown()) then
        return false
    end
    local sourceLeft, sourceRight, sourceTop, sourceBottom = GetFrameRect(node.lockSource)
    local frameLeft, frameRight, frameTop, frameBottom = GetFrameRect(node.frame)
    if not (sourceLeft and frameLeft) then
        return false
    end
    local left = math.min(sourceLeft, frameLeft)
    local right = math.max(sourceRight, frameRight)
    local top = math.max(sourceTop, frameTop)
    local bottom = math.min(sourceBottom, frameBottom)
    return IsCursorInRect(left, right, top, bottom, TRANSIT_MARGIN)
end

local function AcquireFontString(node, index, fontObject)
    local fs = node.fontStrings[index]
    if not fs then
        fs = node.frame:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
        node.fontStrings[index] = fs
    else
        fs:SetFontObject(fontObject or "GameFontHighlightSmall")
    end
    fs:ClearAllPoints()
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:Show()
    node.widgets[#node.widgets + 1] = fs
    return fs
end

local function AcquireTokenButton(node, index)
    local btn = node.tokenButtons[index]
    if not btn then
        btn = CreateFrame("Button", nil, node.frame)
        btn:EnableMouse(true)
        btn:SetScript("OnEnter", function(self)
            UITooltip.PushConcept(node, self.conceptKey, self)
        end)
        btn:SetScript("OnLeave", function(self)
            local child = chain.stack[(tonumber(node.level) or 1) + 1]
            if child and child.lockSource == self and not child.locked then
                UITooltip.PopAfter(node.level)
                return
            end
            UITooltip.ScheduleChainHide("token-leave")
        end)
        btn:RegisterForClicks("AnyUp")
        btn:SetScript("OnClick", function(self)
            UITooltip.PushConcept(node, self.conceptKey, self)
        end)
        node.tokenButtons[index] = btn
    end
    btn:ClearAllPoints()
    btn:Show()
    node.widgets[#node.widgets + 1] = btn
    return btn
end

local function MeasureText(node, text, fontObject)
    local cache = node.measureCache
    local key
    if cache then
        key = tostring(fontObject or "GameFontHighlightSmall") .. "\001" .. tostring(text or "")
        if cache[key] then
            return cache[key]
        end
    end
    node.measureText = node.measureText or node.frame:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    node.measureText:SetFontObject(fontObject or "GameFontHighlightSmall")
    node.measureText:SetText(tostring(text or ""))
    node.measureText:Hide()
    local width = node.measureText.GetStringWidth and node.measureText:GetStringWidth() or 0
    if cache and key then
        cache[key] = width
    end
    return width
end

local function ParseInlineParts(text)
    local parts = {}
    local cursor = 1
    text = tostring(text or "")
    while cursor <= #text do
        local braceStart, braceEnd, inner = text:find("{([^{}]+)}", cursor)
        local phaseStart, phaseEnd, phase = text:find("%f[%w](p%d+r?%d*)%f[%W]", cursor)
        local phaseGenericStart, phaseGenericEnd, phaseGeneric = text:find("%f[%w](pN)%f[%W]", cursor)
        if phaseGenericStart and (not phaseStart or phaseGenericStart < phaseStart) then
            phaseStart, phaseEnd, phase = phaseGenericStart, phaseGenericEnd, phaseGeneric
        end
        if braceStart and (not phaseStart or braceStart <= phaseStart) then
            if braceStart > cursor then
                parts[#parts + 1] = { text = text:sub(cursor, braceStart - 1) }
            end
            parts[#parts + 1] = { text = "{" .. inner .. "}", conceptKey = NormalizeBraceKey(inner) }
            cursor = braceEnd + 1
        elseif phaseStart then
            if phaseStart > cursor then
                parts[#parts + 1] = { text = text:sub(cursor, phaseStart - 1) }
            end
            parts[#parts + 1] = { text = phase, conceptKey = phase == "pN" and "pN" or phase:lower() }
            cursor = phaseEnd + 1
        else
            parts[#parts + 1] = { text = text:sub(cursor) }
            break
        end
    end
    if #parts == 0 then
        parts[1] = { text = text }
    end
    return parts
end

local function AddTextLine(node, text, color, fontObject)
    node.fsIndex = (node.fsIndex or 0) + 1
    local fs = AcquireFontString(node, node.fsIndex, fontObject)
    fs:SetText(tostring(text or " "))
    SetColor(fs, color)
    fs:SetWidth((node.width or WIDTH_ROOT) - PADDING * 2)
    fs:SetPoint("TOPLEFT", node.frame, "TOPLEFT", PADDING, node.cursorY)

    local height = fs.GetStringHeight and fs:GetStringHeight() or 0
    if not height or height < 12 then
        height = 16
    end
    node.cursorY = node.cursorY - height - LINE_GAP
    return fs
end

local function AddSpacer(node, size)
    node.cursorY = node.cursorY - (size or 7)
end

local function SplitUTF8Chars(value)
    value = tostring(value or "")
    local chars = {}
    local index = 1
    local length = #value
    while index <= length do
        local byte = value:byte(index) or 0
        local size = 1
        if byte >= 240 then
            size = 4
        elseif byte >= 224 then
            size = 3
        elseif byte >= 192 then
            size = 2
        end
        chars[#chars + 1] = value:sub(index, math.min(length, index + size - 1))
        index = index + size
    end
    return chars
end

local function AddInlineLine(node, text, color, fontObject, allowedConcepts)
    local parts = ParseInlineParts(text)
    local x = PADDING
    local y = node.cursorY
    local maxX = (node.width or WIDTH_ROOT) - PADDING
    local lineHeight = 18

    local function NewLine(extraHeight)
        x = PADDING
        y = y - (extraHeight or lineHeight)
    end

    local function AddPlainChunk(value)
        if value == "" then
            return
        end
        local font = fontObject or "GameFontHighlightSmall"
        local function AddPlainSegment(segment, width)
            node.fsIndex = (node.fsIndex or 0) + 1
            local fs = AcquireFontString(node, node.fsIndex, font)
            fs:SetText(segment)
            SetColor(fs, color)
            fs:SetWordWrap(false)
            fs:SetWidth(width)
            fs:SetPoint("TOPLEFT", node.frame, "TOPLEFT", x, y)
            x = x + width
        end

        local available = maxX - x
        local width = math.max(1, math.ceil(MeasureText(node, value, font)))
        if width <= available then
            AddPlainSegment(value, width)
            return
        end
        if x > PADDING then
            NewLine()
            available = maxX - x
            if width <= available then
                AddPlainSegment(value, width)
                return
            end
        end

        local chars = SplitUTF8Chars(value)
        local index = 1
        while index <= #chars do
            available = maxX - x
            if available <= 1 and x > PADDING then
                NewLine()
                available = maxX - x
            end

            local best = index
            local low = index
            local high = #chars
            while low <= high do
                local mid = math.floor((low + high) / 2)
                local candidate = table.concat(chars, "", index, mid)
                if MeasureText(node, candidate, font) <= available or mid == index then
                    best = mid
                    low = mid + 1
                else
                    high = mid - 1
                end
            end

            local segment = table.concat(chars, "", index, best)
            width = math.max(1, math.ceil(MeasureText(node, segment, font)))
            AddPlainSegment(segment, width)
            index = best + 1
        end
    end

    for _, part in ipairs(parts) do
        local value = tostring(part.text or "")
        if value ~= "" then
            local def
            if part.conceptKey then
                local resolvedKey, resolved = ResolveConcept(part.conceptKey)
                if allowedConcepts and not allowedConcepts[resolvedKey] then
                    resolved = nil
                end
                def = resolved
            end
            if part.conceptKey and def then
                local label = GetConceptTitle(part.conceptKey, value)
                local conceptKey = ResolveConcept(part.conceptKey)
                if node.conceptKey and conceptKey == node.conceptKey then
                    AddPlainChunk(label)
                else
                    node.btnIndex = (node.btnIndex or 0) + 1
                    local button = AcquireTokenButton(node, node.btnIndex)
                    button.conceptKey = part.conceptKey
                    local font = fontObject or "GameFontHighlightSmall"
                    local textWidth = MeasureText(node, label, font)
                    local width = math.max(1, math.ceil(textWidth))
                    if x + width > maxX and x > PADDING then
                        NewLine()
                    end
                    width = math.min(width, maxX - PADDING)
                    node.fsIndex = (node.fsIndex or 0) + 1
                    local fs = AcquireFontString(node, node.fsIndex, font)
                    fs:SetText(label)
                    SetColor(fs, COLORS.token)
                    fs:SetWordWrap(false)
                    fs:SetWidth(width)
                    fs:SetPoint("TOPLEFT", node.frame, "TOPLEFT", x, y)
                    button:SetSize(width, lineHeight)
                    button:SetPoint("TOPLEFT", node.frame, "TOPLEFT", x, y)
                    x = x + width
                end
            else
                AddPlainChunk(value)
            end
        end
    end
    node.cursorY = y - lineHeight - LINE_GAP
end

local function AddParagraph(node, text, color, fontObject, includeTokens, allowedConcepts)
    text = RenderText(text)
    if text == "" then
        return
    end
    if includeTokens ~= false and #ExtractTokens(text, allowedConcepts) > 0 then
        AddInlineLine(node, text, color, fontObject, allowedConcepts)
    else
        AddTextLine(node, text, color, fontObject)
    end
end

local function AddAllowedConcept(set, key)
    local conceptKey, def = ResolveConcept(key)
    if def then
        set[conceptKey] = true
    end
end

local function BuildAllowedConcepts(node, payload)
    local concepts = payload and (payload.concepts or payload.related)
    if not concepts and not node.conceptKey then
        return nil
    end

    local set = {}
    if type(concepts) == "table" then
        for _, key in ipairs(concepts) do
            AddAllowedConcept(set, key)
        end
    elseif type(concepts) == "string" then
        AddAllowedConcept(set, concepts)
    end
    if node.conceptKey then
        AddAllowedConcept(set, node.conceptKey)
    end
    return set
end

local function RenderPayload(node, payload, fullMode, isConcept)
    if type(payload) == "string" then
        payload = { description = payload }
    end
    if type(payload) ~= "table" then
        payload = { description = "" }
    end

    ResetNode(node)
    node.width = node.level == 1 and WIDTH_ROOT or WIDTH_CONCEPT
    node.frame:SetWidth(node.width)

    local title = RenderText(payload.titleKey or payload.title)
    local summary = RenderText(payload.summaryKey or payload.summary or payload.descriptionKey or payload.description)
    local allowedConcepts = BuildAllowedConcepts(node, payload)

    local hasTitle = title and title ~= ""
    if hasTitle then
        AddTextLine(node, title, COLORS.title, "GameFontNormalLarge")
    end

    if summary and summary ~= "" then
        if hasTitle then
            AddTextLine(node, "----------------", COLORS.hint, "GameFontDisableSmall")
        else
            node.cursorY = node.cursorY - 14
        end
        AddParagraph(node, summary, COLORS.desc, "GameFontHighlightSmall", true, allowedConcepts)
    end

    if fullMode then
        local body = payload.body or payload.desc
        if body then
            AddSpacer(node, 3)
            if type(body) == "table" then
                for _, line in ipairs(body) do
                    AddParagraph(node, line, COLORS.body, "GameFontHighlightSmall", true, allowedConcepts)
                end
            else
                AddParagraph(node, body, COLORS.body, "GameFontHighlightSmall", true, allowedConcepts)
            end
        end
    end

    if payload.tips and payload.tips ~= "" then
        AddSpacer(node, 3)
        AddParagraph(node, payload.tips, COLORS.tips, "GameFontDisableSmall", true, allowedConcepts)
    end

    local height = math.max(46, math.abs(node.cursorY) + PADDING - LINE_GAP)
    node.frame:SetSize(node.width, height)
end

function UITooltip._RenderBrief(node, payload)
    RenderPayload(node, payload, false, false)
end

function UITooltip._RenderFull(node, payload)
    RenderPayload(node, payload, true, false)
end

function UITooltip._RenderConcept(node, rawKey)
    local conceptKey, def, captures = ResolveConcept(rawKey)
    if not def then
        RenderPayload(node, {
            title = "未知概念：" .. tostring(rawKey or ""),
            summary = "当前版本没有注册这个 Tooltip 词条。",
        }, true, true)
        return
    end

    RenderPayload(node, {
        title = RenderText(def.titleKey or def.title or conceptKey, captures),
        summary = RenderText(def.summaryKey or def.summary or def.desc, captures),
        body = def.body,
        examples = def.examples,
        related = def.related,
    }, true, true)
end

AnyMouseOver = function()
    if chain.owner and chain.owner.IsMouseOver and chain.owner:IsMouseOver() then
        return true
    end
    for _, node in ipairs(chain.stack) do
        if node and node.frame and node.frame.IsShown and node.frame:IsShown() and node.frame.IsMouseOver and node.frame:IsMouseOver() then
            return true
        end
        if node and node.lockSource and node.lockSource.IsMouseOver and node.lockSource:IsMouseOver() then
            return true
        end
        if IsInLockedTransitPath(node) then
            return true
        end
    end
    return false
end

local function HideAll()
    CancelLock()
    for level = #chain.stack, 1, -1 do
        local node = chain.stack[level]
        if node and node.frame then
            SetNodeMouseEnabled(node, false)
            node.frame:Hide()
        end
        chain.stack[level] = nil
    end
    chain.owner = nil
    chain.locked = false
    currentPayload = nil
    currentOpts = nil
end

local function FormatTimelineTime(value)
    local seconds = tonumber(value)
    if not seconds then
        return ""
    end

    local centiseconds = math.max(0, math.floor(seconds * 100 + 0.5))
    local minutes = math.floor(centiseconds / 6000)
    local remaining = centiseconds % 6000
    local wholeSeconds = math.floor(remaining / 100)
    local fraction = remaining % 100
    return string.format("%d:%02d.%02d", minutes, wholeSeconds, fraction)
end

local function ResolveTimelineSpellName(spellID, fallback)
    local normalized = tonumber(spellID)
    local fallbackText = Trim(fallback or "")
    if not normalized then
        return fallbackText
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(normalized)
        if info and info.name and info.name ~= "" then
            return info.name
        end
    elseif GetSpellInfo then
        local name = GetSpellInfo(normalized)
        if name and name ~= "" then
            return name
        end
    end

    return fallbackText
end

local function ResetTimelineTooltipWidth()
    if GameTooltip and GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(0)
    end
end

local function EnsureTimelineTooltipResetHook()
    if timelineTooltipResetHooked or not (GameTooltip and GameTooltip.HookScript) then
        return
    end
    GameTooltip:HookScript("OnHide", ResetTimelineTooltipWidth)
    timelineTooltipResetHooked = true
end

local function HideTimelineTooltip()
    ResetTimelineTooltipWidth()
    if GameTooltip and GameTooltip.Hide then
        GameTooltip:Hide()
    end
end

local function ApplyTimelineTooltipTitle(payload)
    local left = _G.GameTooltipTextLeft1
    if not left then
        return ""
    end

    local spellName = ResolveTimelineSpellName(payload.spellID, payload.text or payload.fullText or payload.actionText)
    local icon = payload.spellIcon
    local title = spellName
    if icon and spellName ~= "" then
        title = string.format("|T%s:16:16:0:0|t %s", tostring(icon), spellName)
    end

    if title ~= "" then
        left:SetText(title)
    end
    return title
end

local function AddSpellIDLine(spellID)
    if not spellID then
        return
    end
    local label = L["TOOLTIP_SPELL_ID_LABEL"] or "技能ID"
    GameTooltip:AddLine(label .. "：" .. tostring(spellID), 0.72, 0.72, 0.72, false)
end

local function AddTimelineTooltipMeta(payload)
    local target = Trim(payload.tag or payload.who or "")
    local timeText = Trim(payload.timeText or FormatTimelineTime(payload.time or payload.timeSec))
    local source = Trim(payload.source or "")
    local sourceTab = Trim(payload.sourceTab or payload.editorTab or "")
    if source == "" and sourceTab ~= "" then
        source = sourceTab == "personal" and (L["个人方案"] or "个人方案") or (L["团队方案"] or "团队方案")
    end

    if target ~= "" then
        GameTooltip:AddDoubleLine(L["目标"] or "目标", target, 0.62, 0.62, 0.62, 1, 0.82, 0)
    end

    if timeText ~= "" or source ~= "" then
        GameTooltip:AddLine(" ", 1, 1, 1, false)
        GameTooltip:AddDoubleLine(timeText, source, 1, 0.82, 0, 0.62, 0.62, 0.62)
    end
end

function UITooltip.ShowSpellItem(owner, payload, opts)
    if not (owner and type(payload) == "table" and GameTooltip) then
        return
    end

    HideAll()
    opts = opts or {}
    GameTooltip:SetOwner(owner, opts.anchor or "ANCHOR_RIGHT")
    EnsureTimelineTooltipResetHook()
    GameTooltip:ClearLines()
    if GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(MIN_TIMELINE_TOOLTIP_WIDTH)
    end

    local shownSpell = false
    local spellID = tonumber(payload.spellID)
    if spellID and GameTooltip.SetSpellByID then
        shownSpell = pcall(GameTooltip.SetSpellByID, GameTooltip, spellID) == true
    end

    if shownSpell then
        ApplyTimelineTooltipTitle(payload)
    else
        local text = Trim(payload.text or payload.fullText or payload.actionText)
        if payload.spellIcon and text ~= "" then
            text = string.format("|T%s:16:16:0:0|t %s", tostring(payload.spellIcon), text)
        end
        GameTooltip:AddLine(text ~= "" and text or " ", 1, 1, 1, true)
    end

    AddSpellIDLine(spellID)
    AddTimelineTooltipMeta(payload)
    GameTooltip:Show()
end

function UITooltip.ShowTimelineItem(owner, payload, opts)
    UITooltip.ShowSpellItem(owner, payload, opts)
end

local function AnchorRoot(node, owner, opts)
    node.frame:ClearAllPoints()
    opts = opts or {}
    local anchor = opts.anchor or "ANCHOR_RIGHT"
    local x = opts.x or 10
    local y = opts.y or 0
    if anchor == "ANCHOR_TOP" then
        node.frame:SetPoint("BOTTOM", owner, "TOP", x, y + 8)
    elseif anchor == "ANCHOR_BOTTOM" then
        node.frame:SetPoint("TOP", owner, "BOTTOM", x, y - 8)
    elseif anchor == "ANCHOR_LEFT" then
        node.frame:SetPoint("TOPRIGHT", owner, "TOPLEFT", x - 8, y)
    else
        node.frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", x, y)
    end
end

function UITooltip.PopAfter(level)
    local keep = tonumber(level) or 1
    for index = #chain.stack, keep + 1, -1 do
        local node = chain.stack[index]
        if node and node.frame then
            node.lockSource = nil
            node.locked = false
            SetNodeMouseEnabled(node, false)
            node.frame:Hide()
        end
        chain.stack[index] = nil
    end
end

function UITooltip._PopLevel(level)
    UITooltip.PopAfter(level)
end

function UITooltip.ScheduleChainHide(reason)
    if IsAltLockActive() and chain.stack[1] then
        return
    end
    HideAll()
    HideTimelineTooltip()
end

function UITooltip.ScheduleHide()
    UITooltip.ScheduleChainHide("legacy")
end

function UITooltip.LockChain()
    CancelLock()
    if not chain.stack[1] then
        return
    end
    chain.locked = true
    for _, node in ipairs(chain.stack) do
        LockNode(node)
    end
    RefreshChainVisual()
end

function UITooltip.UnlockChain()
    chain.locked = false
    for _, node in ipairs(chain.stack) do
        UnlockNode(node)
    end
    RefreshChainVisual()
    if not AnyMouseOver() then
        UITooltip.ScheduleChainHide("alt-unlock")
    end
end

local function EnsureModifierFrame()
    if modifierFrame or not CreateFrame then
        return
    end

    modifierFrame = CreateFrame("Frame")
    modifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    modifierFrame:SetScript("OnEvent", function(_, _, key)
        if key ~= "LALT" and key ~= "RALT" then
            return
        end
        local root = chain.stack[1]
        if not (root and root.frame and root.frame:IsShown()) then
            return
        end
        if IsAltLockActive() then
            UITooltip.LockChain()
        else
            UITooltip.UnlockChain()
        end
    end)
end

local function PositionChild(node, parentNode)
    local parentFrame = parentNode and parentNode.frame
    if not parentFrame then
        return
    end

    node.frame:ClearAllPoints()
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or GetScreenWidth and GetScreenWidth() or 0
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or GetScreenHeight and GetScreenHeight() or 0
    local parentLeft = parentFrame.GetLeft and parentFrame:GetLeft() or 0
    local parentRight = parentFrame.GetRight and parentFrame:GetRight() or 0
    local parentTop = parentFrame.GetTop and parentFrame:GetTop() or 0
    local parentBottom = parentFrame.GetBottom and parentFrame:GetBottom() or 0
    local childWidth = node.frame.GetWidth and node.frame:GetWidth() or WIDTH_CONCEPT
    local childHeight = node.frame.GetHeight and node.frame:GetHeight() or 80

    if screenWidth <= 0 or screenHeight <= 0 then
        node.frame:SetPoint("TOPLEFT", parentFrame, "TOPRIGHT", GAP, 0)
        return
    end

    local function MakeRect(left, top)
        return {
            left = left,
            right = left + childWidth,
            top = top,
            bottom = top - childHeight,
        }
    end

    local offset = GAP * math.max(0, (tonumber(node.level) or 1) - 2)
    local candidates = {
        MakeRect(parentRight + GAP, parentTop - offset),
        MakeRect(parentLeft - GAP - childWidth, parentTop - offset),
        MakeRect(parentLeft + offset, parentBottom - GAP),
        MakeRect(parentLeft + offset, parentTop + GAP + childHeight),
    }

    local function OverlapArea(a, b)
        local w = math.max(0, math.min(a.right, b.right) - math.max(a.left, b.left))
        local h = math.max(0, math.min(a.top, b.top) - math.max(a.bottom, b.bottom))
        return w * h
    end

    local existing = {}
    for level, existingNode in ipairs(chain.stack) do
        if existingNode and existingNode ~= node and existingNode.frame and existingNode.frame:IsShown() then
            local left = existingNode.frame.GetLeft and existingNode.frame:GetLeft()
            local right = existingNode.frame.GetRight and existingNode.frame:GetRight()
            local top = existingNode.frame.GetTop and existingNode.frame:GetTop()
            local bottom = existingNode.frame.GetBottom and existingNode.frame:GetBottom()
            if left and right and top and bottom then
                existing[#existing + 1] = { left = left, right = right, top = top, bottom = bottom }
            end
        end
    end

    local function Score(rect)
        local penalty = 0
        if rect.left < PADDING then
            penalty = penalty + (PADDING - rect.left) * 1000
        end
        if rect.right > screenWidth - PADDING then
            penalty = penalty + (rect.right - (screenWidth - PADDING)) * 1000
        end
        if rect.bottom < PADDING then
            penalty = penalty + (PADDING - rect.bottom) * 1000
        end
        if rect.top > screenHeight - PADDING then
            penalty = penalty + (rect.top - (screenHeight - PADDING)) * 1000
        end
        for _, other in ipairs(existing) do
            penalty = penalty + OverlapArea(rect, other) * 10
        end
        return penalty + math.abs(rect.left - parentRight) + math.abs(rect.top - parentTop) * 0.1
    end

    local best = candidates[1]
    local bestScore = Score(best)
    for index = 2, #candidates do
        local score = Score(candidates[index])
        if score < bestScore then
            best = candidates[index]
            bestScore = score
        end
    end

    if bestScore >= 1000 then
        local maxWidth = math.max(180, screenWidth - PADDING * 2)
        if childWidth > maxWidth then
            node.width = maxWidth
            node.frame:SetWidth(maxWidth)
            childWidth = maxWidth
            childHeight = node.frame.GetHeight and node.frame:GetHeight() or childHeight
            best = MakeRect(math.min(math.max(best.left, PADDING), screenWidth - PADDING - childWidth), best.top)
        end
    end

    local left = math.min(math.max(best.left, PADDING), math.max(PADDING, screenWidth - PADDING - childWidth))
    local top = math.min(math.max(best.top, PADDING + childHeight), screenHeight - PADDING)
    if math.abs(left - parentLeft) < GAP and math.abs(top - parentTop) < GAP then
        left = math.min(screenWidth - PADDING - childWidth, left + GAP)
    end
    node.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function UITooltip.PushConcept(parentNode, conceptKey, anchorFrame)
    if not parentNode then
        return
    end
    local resolvedKey = ResolveConcept(conceptKey)
    if parentNode.conceptKey and resolvedKey == parentNode.conceptKey then
        return parentNode
    end
    local parentLevel = tonumber(parentNode.level) or 1
    for levelIndex, existingNode in ipairs(chain.stack) do
        if existingNode and existingNode.conceptKey == resolvedKey then
            if levelIndex <= parentLevel then
                UITooltip.PopAfter(existingNode.level)
                return existingNode
            end
            break
        end
    end
    local level = parentLevel + 1
    if level > MAX_LEVEL then
        Debug("拒绝展开过深词条：" .. tostring(conceptKey))
        return
    end

    UITooltip.PopAfter(parentLevel)

    local node = AcquireNode(level)
    if not node then
        return
    end
    node.level = level
    node.parent = parentNode
    node.conceptKey = resolvedKey
    node.locked = false
    node.lockSource = anchorFrame

    UITooltip._RenderConcept(node, resolvedKey)
    PositionChild(node, parentNode)
    node.frame:Show()
    chain.stack[level] = node
    if IsAltLockActive() then
        chain.locked = true
        LockNode(node)
    else
        node.locked = false
        SetNodeLockedVisual(node, false)
    end
    return node
end

function UITooltip._PushLevel(parentLevel, conceptKey, anchorFrame)
    local parentNode = chain.stack[tonumber(parentLevel) or 1]
    UITooltip.PushConcept(parentNode, conceptKey, anchorFrame)
end

function UITooltip.ShowRoot(owner, payload, opts)
    if not owner then
        return
    end
    EnsureModifierFrame()
    opts = opts or {}
    HideTimelineTooltip()
    CancelLock()
    UITooltip.PopAfter(0)

    local node = AcquireNode(1)
    if not node then
        return
    end

    chain.owner = owner
    chain.locked = false
    chain.stack[1] = node
    node.level = 1
    node.parent = nil
    node.conceptKey = nil
    node.locked = false
    currentPayload = payload
    currentOpts = opts

    UITooltip._RenderBrief(node, payload)
    AnchorRoot(node, owner, opts)
    node.frame:Show()
    if IsAltLockActive() then
        UITooltip.LockChain()
    else
        SetNodeMouseEnabled(node, false)
        SetNodeLockedVisual(node, false)
    end
end

function UITooltip.Show(owner, payload, opts)
    UITooltip.ShowRoot(owner, payload, opts)
end

function UITooltip.AttachRich(frame, payload, opts)
    if not (frame and frame.HookScript and payload) then
        return
    end
    frame:HookScript("OnEnter", function(self)
        UITooltip.ShowRoot(self, payload, opts)
    end)
    frame:HookScript("OnLeave", function()
        UITooltip.ScheduleChainHide("owner-leave")
    end)
    frame:HookScript("OnHide", function()
        UITooltip.ScheduleChainHide("owner-hide")
    end)
end

function UITooltip.AttachSimple(frame, textOrGetter, opts)
    if not (frame and frame.HookScript and textOrGetter) then
        return
    end
    frame:HookScript("OnEnter", function(self)
        local text = type(textOrGetter) == "function" and textOrGetter(self) or textOrGetter
        if text and text ~= "" then
            UITooltip.ShowRoot(self, { summary = text }, opts)
        end
    end)
    frame:HookScript("OnLeave", function()
        UITooltip.ScheduleChainHide("owner-leave")
    end)
    frame:HookScript("OnHide", function()
        UITooltip.ScheduleChainHide("owner-hide")
    end)
end

function UITooltip._GetChain()
    return chain
end

local function GetConceptKeys()
    local keys = {}
    local registry = T.TooltipConcepts and T.TooltipConcepts.registry or {}
    for key in pairs(registry) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function EnsureHelpFrame()
    if helpFrame then
        return helpFrame
    end
    local frame = CreateFrame("Frame", "STTTooltipConceptHelpFrame", UIParent, "BackdropTemplate")
    frame:SetSize(430, 300)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if T.ApplyBackdrop then
        T.ApplyBackdrop(frame, { alpha = 0.92, style = "tooltip" })
    elseif frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.92)
        frame:SetBackdropBorderColor(0.45, 0.38, 0.18, 1)
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, -14)
    frame.title:SetJustifyH("LEFT")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    frame.body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.body:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -14)
    frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    frame.body:SetJustifyH("LEFT")
    frame.body:SetJustifyV("TOP")
    frame.body:SetWordWrap(true)

    helpFrame = frame
    return frame
end

function UITooltip.ShowConceptWindow(rawKey)
    local frame = EnsureHelpFrame()
    local key = Trim(rawKey)
    if key == "" then
        local keys = GetConceptKeys()
        frame.title:SetText("STT Tooltip 词条")
        frame.body:SetText("可用词条：\n" .. table.concat(keys, "  "))
        frame:Show()
        return
    end

    local conceptKey, def, captures = ResolveConcept(key)
    if not def then
        frame.title:SetText("未知概念：" .. key)
        frame.body:SetText("当前版本没有注册这个 Tooltip 词条。")
        frame:Show()
        return
    end

    local lines = {}
    lines[#lines + 1] = RenderText(def.summaryKey or def.summary or def.desc, captures)
    if def.body then
        lines[#lines + 1] = ""
        if type(def.body) == "table" then
            for _, bodyLine in ipairs(def.body) do
                lines[#lines + 1] = RenderText(bodyLine, captures)
            end
        else
            lines[#lines + 1] = RenderText(def.body, captures)
        end
    end
    frame.title:SetText(RenderText(def.titleKey or def.title or conceptKey, captures))
    frame.body:SetText(table.concat(lines, "\n"))
    frame:Show()
end

function UITooltip.ShowDebug()
    if not debugAnchor then
        debugAnchor = CreateFrame("Frame", "STTTooltipDebugAnchor", UIParent)
        debugAnchor:SetSize(24, 24)
        debugAnchor:SetPoint("CENTER", UIParent, "CENTER", -180, 40)
        debugAnchor:EnableMouse(true)
        debugAnchor:Show()
    end

    UITooltip.ShowRoot(debugAnchor, {
        title = "Tooltip Debug",
        summary = "{time:00:10,p2r1}{ct:5} {坦克} 嘲讽。",
        related = { "time", "role-tank", "p2r1", "ct" },
    }, { anchor = "ANCHOR_RIGHT", x = 12, y = 0 })
end

end)
