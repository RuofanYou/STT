local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local HorizontalTimelineGUI = {}
T.HorizontalTimelineGUI = HorizontalTimelineGUI

local RULER_HEIGHT = 34
local HSCROLL_HEIGHT = 8
local HSCROLL_BOTTOM = 8
local SHORTCUT_HINT_BOTTOM = (T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.bottom) or (HSCROLL_BOTTOM + HSCROLL_HEIGHT + 4)
local SHORTCUT_HINT_HEIGHT = (T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.height) or 18
local PHASE_MARKER_BOTTOM = SHORTCUT_HINT_BOTTOM + SHORTCUT_HINT_HEIGHT + 2
local SCRUB_EDGE_MARGIN = 28
local SCRUB_EDGE_SCROLL_SPEED = 520
local ROW_SIDE_PADDING = 4
local DEFAULT_PX_PER_SECOND = 50
local MIN_PX_PER_SECOND = 0.05
local MAX_PX_PER_SECOND = 300
local DEFAULT_ROW_HEIGHT = 28
local DEFAULT_ICON_SIZE = 24
local DEFAULT_DURATION_BAR_HEIGHT = 6
local DEFAULT_DURATION_BAR_COLOR = { 0.4, 0.7, 1.0, 0.55 }
local DEFAULT_FIRST_COL_MIN_W = 80
local DEFAULT_FIRST_COL_MAX_W = 200
local DEFAULT_ICON = 134400
local CREATURE_ICON_CACHE_VERSION = 4
local ENCOUNTER_ICON_OVERRIDES = {
    [3183] = 7448204,
}
local ENCOUNTER_BOSS_NAME_OVERRIDES = {
    [3183] = {
        ["鲁拉"] = true,
        ["L'ura"] = true,
    },
    [53159] = {
        ["腐沼"] = true,
        ["Rotmire"] = true,
    },
}
local ENCOUNTER_ACTOR_SPELL_ICON_OVERRIDES = {
    [53159] = {
        ["腐沼"] = 1221787,
        ["Rotmire"] = 1221787,
        ["孢盖"] = 1221717,
        ["爆燃蕈菇"] = 1221965,
    },
}
local DRAG_PIXEL_THRESHOLD = 5
local PLAYHEAD_COLOR = { 1, 0.82, 0.18, 0.95 }
local PLAYHEAD_PAUSED_COLOR = { 0.62, 0.62, 0.62, 0.82 }
local TRANSPORT_BUTTON_ATLAS = {
    normal = "common-button-tertiary-normal-small",
    highlight = "common-button-tertiary-hover-small",
    pushed = "common-button-tertiary-pressed-small",
    disabled = "common-button-tertiary-disabled-small",
}
local TRANSPORT_PLAY_ATLAS = "common-icon-forwardarrow"
local TRANSPORT_PAUSE_ATLAS = "common-icon-pause"
local ROLE_ICON_TEXTURE = "Interface\\LFGFrame\\UI-LFG-Icon-PortraitRoles"
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local ZOOM_STEP = 1.15
local HSCROLL_BLEND_SPEED = 0.15
local CHIP_WINDOW_BEFORE_VIEW = 0.75
local CHIP_WINDOW_AFTER_VIEW = 1.75
local CHIP_WINDOW_BUCKET_RATIO = 0.5
local SCROLL_PROFILE_IDLE_SECONDS = 0.25

local EXPAND_TOGGLE_SIZE = 14
local EXPAND_LABEL_INDENT = 16
local DISCLOSURE_ANIM_DURATION = 0.26
local EXPAND_ANIM_Y_OFFSET = -8
local TOGGLE_FADE_DURATION = 0.12
local TOGGLE_PLUS_TEXTURE = "Interface\\Buttons\\UI-PlusButton-UP"
local TOGGLE_MINUS_TEXTURE = "Interface\\Buttons\\UI-MinusButton-UP"

local ALL_VISUAL = {
    kind = "texture",
    texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
}

local SELF_VISUAL = {
    kind = "atlas",
    atlas = "common-icon-checkmark-yellow",
}

local SELF_CONDITION_TOKENS = {
    ["自己"] = true,
    self = true,
    me = true,
}

local ROLE_VISUALS = {
    HEALER = {
        kind = "atlas",
        atlas = "roleicon-tiny-healer",
        fallbackTexture = ROLE_ICON_TEXTURE,
        texCoord = { 0.3125, 0.59375, 0, 0.296875 },
    },
    DAMAGER = {
        kind = "atlas",
        atlas = "roleicon-tiny-dps",
        fallbackTexture = ROLE_ICON_TEXTURE,
        texCoord = { 0.3125, 0.59375, 0.328125, 0.625 },
    },
    TANK = {
        kind = "atlas",
        atlas = "roleicon-tiny-tank",
        fallbackTexture = ROLE_ICON_TEXTURE,
        texCoord = { 0, 0.28125, 0.328125, 0.625 },
    },
}

local CLASS_ORDER = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true,
    PRIEST = true, DEATHKNIGHT = true, SHAMAN = true, MAGE = true,
    WARLOCK = true, MONK = true, DRUID = true, DEMONHUNTER = true,
    EVOKER = true,
}

local CLASS_ICON_TEX_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 },
    MAGE = { 0.25, 0.5, 0, 0.25 },
    ROGUE = { 0.5, 0.75, 0, 0.25 },
    DRUID = { 0.75, 1, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 },
    SHAMAN = { 0.25, 0.5, 0.25, 0.5 },
    PRIEST = { 0.5, 0.75, 0.25, 0.5 },
    WARLOCK = { 0.75, 1, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
    DEATHKNIGHT = { 0.25, 0.5, 0.5, 0.75 },
    MONK = { 0.5, 0.75, 0.5, 0.75 },
    DEMONHUNTER = { 0.75, 1, 0.5, 0.75 },
}

local Prototype = {}
Prototype.__index = Prototype
local unpackFunc = unpack or table.unpack

local function Clamp(value, minValue, maxValue)
    local number = tonumber(value) or minValue
    if number < minValue then
        return minValue
    end
    if number > maxValue then
        return maxValue
    end
    return number
end

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeActorName(value)
    return Trim(value):gsub("%s+%d+$", "")
end

local function ExtractPersonnelContext(text)
    local data = T.HorizontalTimelineData
    if data and data.ExtractPersonnelContext then
        return data.ExtractPersonnelContext(text)
    end
    return nil, nil
end

local function BlockMousePropagation(frame)
    if not frame then
        return
    end
    if T.MarkPingBlocker then
        T.MarkPingBlocker(frame)
    end
end

local function GetSemanticUI()
    local db = C and C.DB and C.DB.semanticTimeline
    db = type(db) == "table" and db or {}
    db.ui = type(db.ui) == "table" and db.ui or {}
    db.ui.perViewMode = type(db.ui.perViewMode) == "table" and db.ui.perViewMode or {}
    db.ui.perViewMode.horizontal = type(db.ui.perViewMode.horizontal) == "table" and db.ui.perViewMode.horizontal or {}
    db.ui.playerCacheById = type(db.ui.playerCacheById) == "table" and db.ui.playerCacheById or {}
    if tonumber(db.ui.creatureIconCacheVersion) ~= CREATURE_ICON_CACHE_VERSION then
        db.ui.bossPortraitCache = {}
        db.ui.bossIconCache = {}
        db.ui.npcPortraitCache = {}
        db.ui.npcIconCache = {}
        db.ui.bossJournalEncounterCache = {}
        db.ui.creatureIconCacheVersion = CREATURE_ICON_CACHE_VERSION
    end
    db.ui.bossPortraitCache = type(db.ui.bossPortraitCache) == "table" and db.ui.bossPortraitCache or {}
    db.ui.bossIconCache = type(db.ui.bossIconCache) == "table" and db.ui.bossIconCache or {}
    db.ui.npcPortraitCache = type(db.ui.npcPortraitCache) == "table" and db.ui.npcPortraitCache or {}
    db.ui.npcIconCache = type(db.ui.npcIconCache) == "table" and db.ui.npcIconCache or {}
    db.ui.bossJournalEncounterCache = type(db.ui.bossJournalEncounterCache) == "table" and db.ui.bossJournalEncounterCache or {}
    return db.ui
end

local function GetPrefs()
    local ui = GetSemanticUI()
    local prefs = ui.perViewMode.horizontal
    prefs.dividerRatio = Clamp(prefs.dividerRatio, 0, 1)
    prefs.pxPerSecond = Clamp(prefs.pxPerSecond, MIN_PX_PER_SECOND, MAX_PX_PER_SECOND)
    prefs.scrollX = math.max(0, tonumber(prefs.scrollX) or 0)
    prefs.scrollY = math.max(0, tonumber(prefs.scrollY) or 0)
    prefs.firstColMinW = math.max(40, tonumber(prefs.firstColMinW) or DEFAULT_FIRST_COL_MIN_W)
    prefs.firstColMaxW = math.max(prefs.firstColMinW, tonumber(prefs.firstColMaxW) or DEFAULT_FIRST_COL_MAX_W)
    prefs.rowHeight = math.max(20, tonumber(prefs.rowHeight) or DEFAULT_ROW_HEIGHT)
    prefs.iconSize = math.max(16, tonumber(prefs.iconSize) or DEFAULT_ICON_SIZE)
    prefs.expanded = type(prefs.expanded) == "table" and prefs.expanded or {}
    return prefs
end

local function IsOwnerExpanded(ownerKey)
    if type(ownerKey) ~= "string" or ownerKey == "" then
        return false
    end
    local prefs = GetPrefs()
    return prefs.expanded[ownerKey] and true or false
end

local function SetOwnerExpanded(ownerKey, state)
    if type(ownerKey) ~= "string" or ownerKey == "" then
        return
    end
    local prefs = GetPrefs()
    prefs.expanded[ownerKey] = state and true or nil
end

local function GetDurationBarStyle()
    local ui = GetSemanticUI()
    local height = Clamp(tonumber(ui.durationBarHeight) or DEFAULT_DURATION_BAR_HEIGHT, 2, 14)
    local color = type(ui.durationBarColor) == "table" and ui.durationBarColor or DEFAULT_DURATION_BAR_COLOR
    return height, {
        tonumber(color[1]) or DEFAULT_DURATION_BAR_COLOR[1],
        tonumber(color[2]) or DEFAULT_DURATION_BAR_COLOR[2],
        tonumber(color[3]) or DEFAULT_DURATION_BAR_COLOR[3],
        tonumber(color[4]) or DEFAULT_DURATION_BAR_COLOR[4],
    }
end

local function FormatTime(seconds, precision, forcePrecision)
    local value = math.max(0, tonumber(seconds) or 0)
    local decimals = math.max(0, tonumber(precision) or 0)
    if not forcePrecision and decimals > 0 and math.abs(value - math.floor(value + 0.5)) < 0.0001 then
        decimals = 0
    end
    if decimals <= 0 then
        local rounded = math.floor(value + 0.5)
        local min = math.floor(rounded / 60)
        local sec = rounded % 60
        return string.format("%d:%02d", min, sec)
    end
    local factor = 10 ^ decimals
    local rounded = math.floor(value * factor + 0.5) / factor
    local min = math.floor(rounded / 60)
    local sec = rounded - min * 60
    return string.format("%d:%0" .. tostring(decimals + 3) .. "." .. tostring(decimals) .. "f", min, sec)
end

local function JoinSignature(parts)
    for index = 1, #parts do
        parts[index] = tostring(parts[index] or "")
    end
    return table.concat(parts, "\031")
end

local function BuildEntryRenderSignature(entry)
    if not entry then
        return ""
    end
    if entry._sttRenderSignature then
        return entry._sttRenderSignature
    end
    local meta = entry.meta or {}
    local parts = {
        meta.displayText,
        meta.kind,
        meta.role,
        meta.classFile,
        meta.specIcon,
        meta.iconTexture,
        meta.encounterID,
        meta.instanceID,
        meta.encounterIcon,
        #(entry.items or {}),
    }
    for _, item in ipairs(entry.items or {}) do
        parts[#parts + 1] = item.lineNum
        parts[#parts + 1] = item.rowID
        parts[#parts + 1] = item.editorTab
        parts[#parts + 1] = item.sourcePlanID
        parts[#parts + 1] = item.time
        parts[#parts + 1] = item.spellID
        parts[#parts + 1] = item.spellIcon
        parts[#parts + 1] = item.duration
        parts[#parts + 1] = item.castFailed
        parts[#parts + 1] = item.fullText
        parts[#parts + 1] = #(item.collisions or {})
    end
    entry._sttRenderSignature = JoinSignature(parts)
    return entry._sttRenderSignature
end

local function BuildChipRenderSignature(item, pxPerSecond, iconSize)
    local barHeight, barColor = GetDurationBarStyle()
    return JoinSignature({
        item and item.lineNum,
        item and item.rowID,
        item and item.editorTab,
        item and item.sourcePlanID,
        item and item.time,
        item and item.spellID,
        item and item.spellIcon,
        item and item.duration,
        item and item.castFailed,
        item and item.fullText,
        item and #(item.collisions or {}),
        math.floor((tonumber(pxPerSecond) or 0) * 100 + 0.5),
        iconSize,
        barHeight,
        barColor[1], barColor[2], barColor[3], barColor[4],
    })
end

local function IsDataOnlyRefreshCause(cause)
    return cause == "editor_save_refresh"
        or cause == "skill_picker"
        or cause == "event_editor"
        or cause == "context_menu_paste"
        or cause == "context_menu_delete"
        or cause == "timeline_key_delete"
        or cause == "STT_EDITOR_UNDO"
        or cause == "drag"
end

local function ShouldPersistScrollX(cause)
    return cause == "wheel"
        or cause == "bar"
        or cause == "bar_jump"
        or cause == "middle_drag"
        or cause == "zoom"
end

local function IsViewportRestoreCause(cause)
    return cause == "initial_open"
        or cause == "panel_show"
        or cause == "boss_change"
        or cause == "profile_changed"
        or cause == "reset"
        or cause == "sync_apply"
        or cause == "tab_switch"
end

local function ShowTimelineTooltip(owner, item)
    if not (T.ShowTimelineItemTooltip and owner and item) then
        return
    end

    T.ShowTimelineItemTooltip(owner, {
        spellID = item.spellID,
        spellIcon = item.spellIcon,
        text = item.fullText,
        fullText = item.fullText,
        who = item.who,
        time = item.time,
        sourceTab = item.editorTab,
        tag = item.tooltipTag or item.who,
    })
end

local function SetFontColor(fontString, color)
    if not fontString then
        return
    end
    fontString:SetTextColor(
        tonumber(color and color[1]) or 1,
        tonumber(color and color[2]) or 1,
        tonumber(color and color[3]) or 1,
        tonumber(color and color[4]) or 1
    )
end

local function GetFirstUTF8Char(text)
    local value = tostring(text or "")
    local first = value:match("^[%z\1-\127\194-\244][\128-\191]*")
    return (first and first ~= "") and first or value:sub(1, 1)
end

local function ApplyBackdrop(frame, opts)
    if T.ApplyBackdrop then
        T.ApplyBackdrop(frame, opts)
    elseif frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        frame:SetBackdropColor(0, 0, 0, opts and opts.alpha or 0.35)
        frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)
    end
end

local function AtlasExists(atlas)
    return atlas and atlas ~= "" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function ApplyButtonAtlas(button)
    if not button then
        return
    end
    if button.SetNormalAtlas then
        button:SetNormalAtlas(TRANSPORT_BUTTON_ATLAS.normal)
        button:SetHighlightAtlas(TRANSPORT_BUTTON_ATLAS.highlight)
        button:SetPushedAtlas(TRANSPORT_BUTTON_ATLAS.pushed)
        button:SetDisabledAtlas(TRANSPORT_BUTTON_ATLAS.disabled)
    end
end

local function TextureVisual(texture, texCoord)
    if texture then
        return { kind = "texture", texture = texture, texCoord = texCoord }
    end
    return nil
end

local function ResolveActorSpellIcon(spellID)
    local id = tonumber(spellID)
    if not id then
        return nil
    end
    local resolver = T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon
    if resolver then
        local texture = resolver(id)
        if texture then
            return texture
        end
    end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, id)
        if ok and texture then
            return texture
        end
    end
    if GetSpellTexture then
        local ok, texture = pcall(GetSpellTexture, id)
        if ok and texture then
            return texture
        end
    end
    return nil
end

local function ResolveActorSpellOverrideVisual(encounterID, actorName)
    local overrides = ENCOUNTER_ACTOR_SPELL_ICON_OVERRIDES[tonumber(encounterID) or 0]
    local spellID = overrides and overrides[Trim(actorName)]
    return TextureVisual(ResolveActorSpellIcon(spellID), { 0, 1, 0, 0.95 })
end

local function PortraitVisual(displayInfoID)
    local id = tonumber(displayInfoID)
    if id and id > 0 then
        return { kind = "portrait", displayInfoID = id }
    end
    return nil
end

local function ClassVisual(classFile)
    local token = type(classFile) == "string" and classFile:upper() or nil
    if not (token and CLASS_ORDER[token]) then
        return nil
    end
    if token == "EVOKER" then
        return TextureVisual("Interface\\Icons\\ClassIcon_Evoker")
    end
    return TextureVisual(CLASS_ICON_TEXTURE, CLASS_ICON_TEX_COORDS[token])
end

local function ApplyTextureVisual(texture, visual, color)
    if not texture then
        return
    end

    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1, 1)

    if visual and visual.kind == "portrait" and SetPortraitTextureFromCreatureDisplayID then
        local ok = pcall(SetPortraitTextureFromCreatureDisplayID, texture, visual.displayInfoID)
        if ok then
            texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
            texture:Show()
            return
        end
    end

    if visual and visual.kind == "atlas" and visual.atlas and texture.SetAtlas then
        local ok = pcall(texture.SetAtlas, texture, visual.atlas, false)
        if ok then
            texture:SetVertexColor(1, 1, 1, 1)
            texture:Show()
            return
        end
    end

    if visual and (visual.texture or visual.fallbackTexture) then
        texture:SetTexture(visual.texture or visual.fallbackTexture)
        if visual.texCoord then
            texture:SetTexCoord(unpackFunc(visual.texCoord))
        end
        texture:Show()
        return
    end

    texture:SetTexture(DEFAULT_ICON)
    texture:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1, 0.55)
    texture:Show()
end

local function PickRowBackgroundColor(dataIndex, defaultOdd, defaultEven, readOnlyColor, readOnly)
    if readOnly then
        return readOnlyColor
    end
    return (dataIndex % 2) == 1 and defaultOdd or defaultEven
end

local function IsSelfCondition(text)
    local token = type(text) == "string" and text:lower() or ""
    return SELF_CONDITION_TOKENS[token] == true
end

local function ResolveClassColor(classFile)
    local token = type(classFile) == "string" and classFile:upper() or nil
    if not (token and CLASS_ORDER[token]) then
        return nil
    end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(token)
        if color then
            return { color.r or 1, color.g or 1, color.b or 1, 1 }
        end
    end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
        local color = RAID_CLASS_COLORS[token]
        return { color.r or 1, color.g or 1, color.b or 1, 1 }
    end
    return nil
end

local function CaptureSpecInfoByIndex(index, isInspect)
    local specIndex = tonumber(index)
    if not specIndex then
        return nil
    end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local ok, id, name, description, icon, role, classFile = pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex, isInspect == true)
        if ok then
            if type(id) == "table" then
                return {
                    specID = tonumber(id.specID or id.id),
                    icon = id.icon or id.iconID,
                    classFile = id.classFile,
                }
            end
            return {
                specID = tonumber(id),
                icon = icon,
                classFile = classFile,
            }
        end
    end

    if GetSpecializationInfo then
        local ok, id, name, description, icon, role, classFile = pcall(GetSpecializationInfo, specIndex, isInspect == true)
        if ok then
            return {
                specID = tonumber(id),
                icon = icon,
                classFile = classFile,
            }
        end
    end
    return nil
end

local function CaptureSpecInfoByID(specID)
    local idValue = tonumber(specID)
    if not idValue then
        return nil
    end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID then
        local ok, id, name, description, icon, role, classFile = pcall(C_SpecializationInfo.GetSpecializationInfoByID, idValue)
        if ok then
            if type(id) == "table" then
                return {
                    specID = tonumber(id.specID or id.id or idValue),
                    icon = id.icon or id.iconID,
                    classFile = id.classFile,
                }
            end
            return {
                specID = tonumber(id) or idValue,
                icon = icon,
                classFile = classFile,
            }
        end
    end

    if GetSpecializationInfoByID then
        local ok, id, name, description, icon, role, classFile = pcall(GetSpecializationInfoByID, idValue)
        if ok then
            return {
                specID = tonumber(id) or idValue,
                icon = icon,
                classFile = classFile,
            }
        end
    end
    return nil
end

local function GetCursorXInFrame(frame)
    if not frame then
        return 0
    end
    local cursorX = GetCursorPosition()
    local scale = frame:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
    return (cursorX / scale) - (frame:GetLeft() or 0)
end

local function GetCursorYInFrame(frame)
    if not frame then
        return 0
    end
    local _, cursorY = GetCursorPosition()
    local scale = frame:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
    return (cursorY / scale) - (frame:GetBottom() or 0)
end

local function IsCursorInsideFrame(frame)
    if not frame then
        return false
    end
    local cursorX, cursorY = GetCursorPosition()
    local scale = frame:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
    local x = cursorX / scale
    local y = cursorY / scale
    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    return left and right and bottom and top
        and x >= left and x <= right
        and y >= bottom and y <= top
end

function HorizontalTimelineGUI.Create(parent, opts)
    if not parent then
        return nil
    end
    local self = setmetatable({}, Prototype)
    self.parent = parent
    self.opts = type(opts) == "table" and opts or {}
    self.perRow = {}
    self.orderedKeys = {}
    self.rowFrames = {}
    self.rulerTicks = {}
    self.phaseMarkers = {}
    self.playerCacheByName = {}
    self.pendingInspect = {}
    self.bossPortraitMissLogged = {}
    self.bossIconMissLogged = {}
    self.npcIconMissLogged = {}
    self.inputConsumeLogSeen = {}
    self.scrollX = 0
    self.totalSeconds = 30
    self.runnerTime = 0
    self.autoFollow = true
    self.contentWidth = 1
    self.firstColWidth = DEFAULT_FIRST_COL_MIN_W
    self.drawerHideToken = 0
    self:CreateFrames(parent)
    self:RegisterRosterEvents()
    return self
end

local function CountTableEntries(values)
    local count = 0
    for _ in pairs(values or {}) do
        count = count + 1
    end
    return count
end

function Prototype:CreateFrames(parent)
    local root = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    root:SetAllPoints(parent)
    root:EnableMouse(true)
    root:EnableMouseWheel(true)
    BlockMousePropagation(root)
    root:SetScript("OnMouseWheel", function(_, delta)
        self:HandleMouseWheel(delta, self.rulerClip)
    end)
    root:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            if T.TimelineSelectionBox then
                T.TimelineSelectionBox.Start(self)
            end
            return
        end
        self:StartMiddleDrag(button)
    end)
    root:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and T.TimelineSelectionBox and T.TimelineSelectionBox.IsActive(self) then
            local moved = T.TimelineSelectionBox.Finish("root_mouse_up")
            if not moved then
                T.TimelineSelectionBox.Clear("root_click")
            end
            return
        end
        self:StopMiddleDrag(button)
    end)
    root:SetScript("OnEvent", function(_, event, button)
        if event == "GLOBAL_MOUSE_DOWN" and button == "MiddleButton" then
            if root:IsShown() and root:IsMouseOver() then
                self:StartMiddleDrag(button)
            end
        elseif event == "GLOBAL_MOUSE_UP" and button == "MiddleButton" then
            self:StopMiddleDrag(button)
        elseif event == "GLOBAL_MOUSE_UP" and button == "LeftButton" and T.TimelineSelectionBox and T.TimelineSelectionBox.IsActive(self) then
            local moved = T.TimelineSelectionBox.Finish("global_mouse_up")
            if not moved then
                T.TimelineSelectionBox.Clear("global_click")
            end
        end
    end)
    ApplyBackdrop(root, { alpha = 0.10 })
    self.root = root
    self:BindShortcutHintHover(root)

    self.emptyText = root:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.emptyText:SetPoint("CENTER", root, "CENTER", 0, 0)
    self.emptyText:SetText(L["TIMELINE_VIEW_NO_ROWS"] or "当前方案没有可显示的时间轴行")
    self.emptyText:Hide()

    self.measureText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.measureText:SetPoint("TOPLEFT", root, "TOPLEFT", -10000, 10000)
    self.measureText:Hide()

    local rulerLabel = CreateFrame("Frame", nil, root)
    rulerLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    rulerLabel:SetHeight(RULER_HEIGHT)
    rulerLabel:SetWidth(self.firstColWidth)
    rulerLabel.bg = rulerLabel:CreateTexture(nil, "BACKGROUND")
    rulerLabel.bg:SetAllPoints()
    rulerLabel.bg:SetColorTexture(0.08, 0.08, 0.10, 0.85)
    rulerLabel:EnableMouse(true)
    BlockMousePropagation(rulerLabel)
    self:BindShortcutHintHover(rulerLabel)
    rulerLabel.text = rulerLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rulerLabel.text:SetPoint("LEFT", rulerLabel, "LEFT", 8, 0)
    rulerLabel.text:SetText(L["TIMELINE_VIEW_TARGET"] or "对象")
    rulerLabel:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            self:SortRowsByObjectOnce()
        elseif button == "RightButton" then
            self:HandleHeaderRightClick("target")
        end
    end)
    self.rulerLabel = rulerLabel

    local rulerClip = CreateFrame("Frame", nil, root)
    rulerClip:SetPoint("TOPLEFT", rulerLabel, "TOPRIGHT", 0, 0)
    rulerClip:SetPoint("TOPRIGHT", root, "TOPRIGHT", -2, 0)
    rulerClip:SetHeight(RULER_HEIGHT)
    if rulerClip.SetClipsChildren then
        rulerClip:SetClipsChildren(true)
    end
    rulerClip:EnableMouse(true)
    rulerClip:EnableMouseWheel(true)
    BlockMousePropagation(rulerClip)
	rulerClip:SetScript("OnMouseWheel", function(_, delta)
		self:HandleMouseWheel(delta, rulerClip)
	end)
	rulerClip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			self:BeginRulerSeekClick()
		else
			self:StartMiddleDrag(button)
		end
	end)
	rulerClip:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			self:FinishRulerSeekClick()
        elseif button == "RightButton" then
            self:HandleHeaderRightClick("ruler")
		else
			self:StopMiddleDrag(button)
		end
	end)
    self.rulerClip = rulerClip
    self:BindShortcutHintHover(rulerClip)

    local rulerContent = CreateFrame("Frame", nil, rulerClip)
    rulerContent:SetPoint("TOPLEFT", rulerClip, "TOPLEFT", 0, 0)
    rulerContent:SetHeight(RULER_HEIGHT)
    self.rulerContent = rulerContent

    local rowsScroll = T.CreateVirtualScroll(root, {
        rowHeight = DEFAULT_ROW_HEIGHT,
        stepSize = DEFAULT_ROW_HEIGHT * 3,
        rowBuffer = 2,
        viewRefreshThrottle = 0.033,
    })
    rowsScroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -RULER_HEIGHT)
    rowsScroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -2, PHASE_MARKER_BOTTOM)
    rowsScroll:EnableMouse(true)
    BlockMousePropagation(rowsScroll)
    self:BindShortcutHintHover(rowsScroll)
    rowsScroll:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and T.TimelineSelectionBox then
            T.TimelineSelectionBox.Start(self)
        end
    end)
    rowsScroll:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and self:IsCursorInFirstColumn() then
            self:HandleHeaderRightClick("target")
            return
        end
        if button == "LeftButton" and T.TimelineSelectionBox and T.TimelineSelectionBox.IsActive(self) then
            local moved = T.TimelineSelectionBox.Finish("scroll_mouse_up")
            if not moved then
                T.TimelineSelectionBox.Clear("scroll_click")
            end
        end
    end)
    if rowsScroll.viewport then
        rowsScroll.viewport:EnableMouse(true)
        BlockMousePropagation(rowsScroll.viewport)
        self:BindShortcutHintHover(rowsScroll.viewport)
        rowsScroll.viewport:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and T.TimelineSelectionBox then
                T.TimelineSelectionBox.Start(self)
            end
        end)
        rowsScroll.viewport:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" and self:IsCursorInFirstColumn() then
                self:HandleHeaderRightClick("target")
                return
            end
            if button == "LeftButton" and T.TimelineSelectionBox and T.TimelineSelectionBox.IsActive(self) then
                local moved = T.TimelineSelectionBox.Finish("viewport_mouse_up")
                if not moved then
                    T.TimelineSelectionBox.Clear("viewport_click")
                end
            end
        end)
    end
    rowsScroll:SetRowFactory(function(scrollParent)
        return self:CreateRowFrame(scrollParent)
    end)
    rowsScroll:SetRenderCallback(function(row, dataIndex)
        self:RenderRow(row, dataIndex)
    end)
    rowsScroll:SetRowHeightProvider(function(dataIndex)
        return self:GetDisplayRowHeight(dataIndex)
    end)
    rowsScroll:SetViewRefreshCallback(function()
        self:RecordScrollProfileViewRefresh()
    end)
    rowsScroll:SetScrollChangedCallback(function(_, offset)
        self:RecordScrollProfileFrame()
        GetPrefs().scrollY = math.max(0, tonumber(offset) or 0)
    end)
    self.rowsScrollBaseOnMouseWheel = rowsScroll.OnMouseWheel
    rowsScroll.OnMouseWheel = function(scrollFrame, delta)
        self:HandleMouseWheel(delta, self.rulerClip, function(nextDelta)
            if self.rowsScrollBaseOnMouseWheel then
                self.rowsScrollBaseOnMouseWheel(scrollFrame, nextDelta)
            end
        end)
    end
    self.rowsScroll = rowsScroll

    self.hScrollBar = T.CreateHorizontalScrollBar(root, {
        height = HSCROLL_HEIGHT,
        getRange = function()
            return self:GetScrollRange()
        end,
        getOffset = function()
            return self.scrollX
        end,
        getPageSize = function()
            return self:GetTrackWidth()
        end,
        setOffset = function(value)
            self:SetScrollX(value, "bar")
        end,
        scrollToOffset = function(value)
            self:SetScrollX(value, "bar_jump")
        end,
        stopOffset = function()
            self:StopHorizontalMotion()
        end,
    })
    self.hScrollBar:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", self.firstColWidth + 2, HSCROLL_BOTTOM)
    self.hScrollBar:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -6, HSCROLL_BOTTOM)
    self.hScrollBar:SetFrameLevel((root:GetFrameLevel() or 0) + 10)
    BlockMousePropagation(self.hScrollBar)
    self:BindShortcutHintHover(self.hScrollBar)

    self:CreateShortcutHint()
    self:CreateTransport()
    self:CreatePlayhead()
    if T.KeyboardCapture then
        T.KeyboardCapture.Bind(root, {
            {
                key = "SPACE",
                handler = function()
                    self:ToggleTransport()
                    return true
                end,
            },
            {
                key = "A",
                ctrl = true,
                handler = function()
                    return self:HandleSelectAllShortcut()
                end,
            },
            {
                key = "ESCAPE",
                handler = function()
                    return self:HandleClearSelectionShortcut()
                end,
            },
            {
                key = "DELETE",
                handler = function()
                    return self:HandleDeleteSelectionShortcut()
                end,
            },
            {
                key = "BACKSPACE",
                handler = function()
                    return self:HandleDeleteSelectionShortcut()
                end,
            },
            {
                key = "LEFT",
                handler = function()
                    return self:HandleSelectionStep(-1)
                end,
            },
            {
                key = "RIGHT",
                handler = function()
                    return self:HandleSelectionStep(1)
                end,
            },
            {
                key = "UP",
                handler = function()
                    return self:HandleSelectionStepRow(-1)
                end,
            },
            {
                key = "DOWN",
                handler = function()
                    return self:HandleSelectionStepRow(1)
                end,
            },
        })
    end
    if T.TimelineRunner and T.TimelineRunner.Subscribe then
        self.unsubscribeRunner = T.TimelineRunner:Subscribe(function(state)
            self:OnRunnerTick(state)
        end)
    end

    self:CreateDrawer()
    root:HookScript("OnSizeChanged", function()
        self:RefreshLayout("size_changed")
    end)
end

function Prototype:CreateShortcutHint()
    if T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.Create then
        self.shortcutHintController = T.HorizontalTimelineShortcutHint.Create(self)
    end
end

function Prototype:BindShortcutHintHover(frame)
    if T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.BindHover then
        T.HorizontalTimelineShortcutHint.BindHover(self, frame)
    end
end

function Prototype:LayoutShortcutHint()
    if self.shortcutHintController and self.shortcutHintController.Layout then
        self.shortcutHintController:Layout()
    end
end

function Prototype:SetShortcutHintActive(active)
    if self.shortcutHintController and self.shortcutHintController.SetActive then
        self.shortcutHintController:SetActive(active)
    end
end

function Prototype:SetShortcutHintText(text, activeSeconds)
    if self.shortcutHintController and self.shortcutHintController.SetText then
        self.shortcutHintController:SetText(text, activeSeconds)
    end
end

function Prototype:SetEditFeedback(text, key, seconds)
    self:SetShortcutHintText(text, seconds or (T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds))
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.SetStatus then
        T.SemanticTimelineGUI.SetStatus(text, key)
    end
end

function Prototype:RestoreShortcutHintText()
    if self.shortcutHintController and self.shortcutHintController.RestoreText then
        self.shortcutHintController:RestoreText()
    end
end

function Prototype:IsShortcutHintMouseOver()
    return self.shortcutHintController and self.shortcutHintController.IsMouseOver and self.shortcutHintController:IsMouseOver()
end

function Prototype:ScheduleShortcutHintDim(delay)
    if self.shortcutHintController and self.shortcutHintController.ScheduleDim then
        self.shortcutHintController:ScheduleDim(delay)
    end
end

function Prototype:CreateTransport()
    local parent = self.opts.transportParent or self.rulerLabel
    local content = CreateFrame("Frame", nil, parent)
    content:SetSize(146, 24)
    content:SetPoint("CENTER", parent, "CENTER", 0, 0)
    content:SetFrameLevel((parent:GetFrameLevel() or 0) + 4)

    local button = CreateFrame("Button", nil, content)
    button:SetSize(28, 24)
    button:SetPoint("LEFT", content, "LEFT", 0, 0)
    button:SetFrameLevel((content:GetFrameLevel() or 0) + 1)
    ApplyButtonAtlas(button)
    BlockMousePropagation(button)

    button.icon = button:CreateTexture(nil, "OVERLAY")
    button.icon:SetSize(13, 13)
    button.icon:SetPoint("CENTER", button, "CENTER", 1, 0)

    button.pauseLeft = button:CreateTexture(nil, "OVERLAY")
    button.pauseLeft:SetSize(3, 12)
    button.pauseLeft:SetPoint("CENTER", button, "CENTER", -3, 0)
    button.pauseLeft:SetColorTexture(1, 0.82, 0.18, 1)
    button.pauseLeft:Hide()

    button.pauseRight = button:CreateTexture(nil, "OVERLAY")
    button.pauseRight:SetSize(3, 12)
    button.pauseRight:SetPoint("CENTER", button, "CENTER", 3, 0)
    button.pauseRight:SetColorTexture(1, 0.82, 0.18, 1)
    button.pauseRight:Hide()

    button:SetScript("OnClick", function()
        self:ToggleTransport()
    end)
    self.transportButton = button
    self.transportContent = content

    local timeText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetPoint("LEFT", button, "RIGHT", 8, 0)
    timeText:SetWidth(74)
    timeText:SetJustifyH("CENTER")
    timeText:SetText("0:00.00")
    self.transportTimeText = timeText

    local stopButton = CreateFrame("Button", nil, content)
    stopButton:SetSize(28, 24)
    stopButton:SetPoint("LEFT", timeText, "RIGHT", 8, 0)
    stopButton:SetFrameLevel((content:GetFrameLevel() or 0) + 1)
    ApplyButtonAtlas(stopButton)
    BlockMousePropagation(stopButton)

    stopButton.icon = stopButton:CreateTexture(nil, "OVERLAY")
    stopButton.icon:SetSize(10, 10)
    stopButton.icon:SetPoint("CENTER", stopButton, "CENTER", 0, 0)
    stopButton.icon:SetColorTexture(1, 0.82, 0.18, 1)

    stopButton:SetScript("OnClick", function()
        self:StopTransport()
    end)
    self.transportStopButton = stopButton

    self:SetTransportPlaying(false)

    if parent == self.rulerLabel and self.rulerLabel.text then
        self.rulerLabel.text:Hide()
    end
end

function Prototype:CreatePlayhead()
    local frame = CreateFrame("Frame", nil, self.root)
    frame:SetSize(14, RULER_HEIGHT + DEFAULT_ROW_HEIGHT)
    frame:SetFrameLevel((self.root:GetFrameLevel() or 0) + 35)
    frame:EnableMouse(false)
    frame:Hide()

    frame.line = frame:CreateTexture(nil, "OVERLAY")
    frame.line:SetPoint("TOP", frame, "TOP", 0, -RULER_HEIGHT)
    frame.line:SetWidth(2)
    frame.line:SetColorTexture(unpackFunc(PLAYHEAD_PAUSED_COLOR))

    local handle = CreateFrame("Frame", nil, frame)
    handle:SetSize(14, 14)
    handle:SetPoint("TOP", frame, "TOP", 0, -2)
    handle:EnableMouse(true)
    BlockMousePropagation(handle)
    handle.text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    handle.text:SetPoint("CENTER", handle, "CENTER", 0, 0)
    handle.text:SetText("v")
    handle:SetScript("OnMouseDown", function(_, button)
        self:StartPlayheadDrag(button)
    end)
    handle:SetScript("OnMouseUp", function(_, button)
        self:StopPlayheadDrag(button)
    end)
    frame.handle = handle

    self.playhead = frame
end

function Prototype:CreateDrawer()
    local drawer = CreateFrame("Frame", nil, self.root, "BackdropTemplate")
    drawer:SetSize(260, 80)
    drawer:SetFrameLevel((self.root:GetFrameLevel() or 0) + 40)
    drawer:EnableMouse(true)
    BlockMousePropagation(drawer)
    ApplyBackdrop(drawer, { alpha = 0.92 })
    drawer:Hide()

    drawer.title = drawer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    drawer.title:SetPoint("TOPLEFT", drawer, "TOPLEFT", 10, -8)
    drawer.title:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -10, -8)
    drawer.title:SetJustifyH("LEFT")

    drawer.items = {}
    drawer:SetScript("OnEnter", function()
        self.drawerInside = true
    end)
    drawer:SetScript("OnLeave", function()
        self.drawerInside = false
        self:ScheduleDrawerHide()
    end)

    self.drawer = drawer
end

function Prototype:RegisterRosterEvents()
    if self.eventFrame then
        return
    end
    local frame = CreateFrame("Frame")
    frame.owner = self
    frame:SetScript("OnEvent", function(eventFrame, event, ...)
        eventFrame.owner:OnEvent(event, ...)
    end)
    self.eventFrame = frame
end

function Prototype:RegisterInputEvents()
    if self.inputEventsRegistered or not self.root then
        return
    end
    self.root:RegisterEvent("GLOBAL_MOUSE_DOWN")
    self.root:RegisterEvent("GLOBAL_MOUSE_UP")
    self.inputEventsRegistered = true
end

function Prototype:UnregisterInputEvents()
    if not (self.inputEventsRegistered and self.root) then
        return
    end
    self.root:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    self.root:UnregisterEvent("GLOBAL_MOUSE_UP")
    self.inputEventsRegistered = false
end

function Prototype:Activate()
    self:RegisterRosterEvents()
    if self.eventFrame and not self.rosterEventsRegistered then
        self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:RegisterEvent("INSPECT_READY")
        self.rosterEventsRegistered = true
    end
    self:RegisterInputEvents()
end

function Prototype:Deactivate()
    self:UnregisterInputEvents()
    if self.eventFrame and self.rosterEventsRegistered then
        self.eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
        self.eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:UnregisterEvent("INSPECT_READY")
        self.rosterEventsRegistered = false
    end

    self.drawerHideToken = (self.drawerHideToken or 0) + 1
    self.rulerLabelFlashToken = (self.rulerLabelFlashToken or 0) + 1
    self.rulerSeekClick = nil
    self.playheadDrag = nil
    self.dragging = false

    if self.rulerClip then
        self.rulerClip:SetScript("OnUpdate", nil)
    end
    if self.playhead then
        self.playhead:SetScript("OnUpdate", nil)
    end
    if self.root then
        self.root:SetScript("OnUpdate", nil)
    end
    if self.scrollProfileFrame then
        self.scrollProfileFrame:SetScript("OnUpdate", nil)
    end
    if self.disclosureAnimFrame then
        self.disclosureAnimFrame:SetScript("OnUpdate", nil)
    end
    if self._disclosureAnim then
        SetOwnerExpanded(self._disclosureAnim.ownerKey, self._disclosureAnim.to == 1)
        self._disclosureAnim = nil
    end

    for _, row in ipairs(self.rowFrames or {}) do
        if row.toggleBtn then
            row.toggleBtn:SetScript("OnUpdate", nil)
        end
        for _, chip in ipairs(row.chips or {}) do
            chip:SetScript("OnUpdate", nil)
        end
    end

    if T.TimelineSelectionBox and T.TimelineSelectionBox.IsActive and T.TimelineSelectionBox.IsActive(self) then
        T.TimelineSelectionBox.Clear("timeline_deactivate")
    end

    self.scrollProfile = nil
    self:CleanupChipDrag()
    self:HideDrawer()
end

function Prototype:ReleaseData()
    self.sourceRows = {}
    self.perRow = {}
    self.orderedKeys = {}
    self.displayRows = {}
    self.sourceRowOrder = nil
    self.pendingInspect = {}
    self.phaseDisplayStats = nil
    self.durationItemCount = 0
    self.selectedRowKey = nil
    self.dragTargetRowKey = nil
    self.rowsRenderSignature = nil
    self.layoutSignature = nil
    wipe(self.playerCacheByName)
    wipe(self.inputConsumeLogSeen)
    wipe(self.bossPortraitMissLogged)
    wipe(self.bossIconMissLogged)
    wipe(self.npcIconMissLogged)

    if self.rowsScroll then
        self.rowsScroll:SetDataCount(0)
        self.rowsScroll:SnapTo(0)
    end
    if self.emptyText then
        self.emptyText:Hide()
    end
    for _, row in ipairs(self.rowFrames or {}) do
        row.entry = nil
        row.displayRow = nil
        row.rowKey = nil
        row._sttRenderSignature = nil
        row._effectiveRowHeight = nil
        row._disclosureProgress = nil
        row._disclosureYOffset = nil
        if row.toggleBtn then
            row.toggleBtn:SetScript("OnUpdate", nil)
            row.toggleBtn:Hide()
        end
        for _, chip in ipairs(row.chips or {}) do
            chip.item = nil
            chip.row = nil
            chip:SetScript("OnUpdate", nil)
            self:HideChip(chip)
        end
        row:Hide()
    end
end

function Prototype:GetMemoryState()
    local chipCount = 0
    for _, row in ipairs(self.rowFrames or {}) do
        chipCount = chipCount + #(row.chips or {})
    end
    local activeOnUpdate = 0
    if self.rulerSeekClick then activeOnUpdate = activeOnUpdate + 1 end
    if self.playheadDrag then activeOnUpdate = activeOnUpdate + 1 end
    if self.dragging then activeOnUpdate = activeOnUpdate + 1 end
    if self.dragState then activeOnUpdate = activeOnUpdate + 1 end
    if self.scrollProfile then activeOnUpdate = activeOnUpdate + 1 end
    if self._disclosureAnim then activeOnUpdate = activeOnUpdate + 1 end
    return {
        root = self.root ~= nil,
        visible = self.root and self.root.IsVisible and self.root:IsVisible() or false,
        rosterEvents = self.rosterEventsRegistered == true,
        inputEvents = self.inputEventsRegistered == true,
        activeOnUpdate = activeOnUpdate,
        sourceRows = #(self.sourceRows or {}),
        displayRows = #(self.displayRows or {}),
        perRow = CountTableEntries(self.perRow),
        orderedKeys = #(self.orderedKeys or {}),
        rowFrames = #(self.rowFrames or {}),
        chips = chipCount,
        pendingInspect = CountTableEntries(self.pendingInspect),
    }
end

function Prototype:OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local ui = GetSemanticUI()
        wipe(ui.playerCacheById)
        wipe(ui.bossPortraitCache)
        wipe(ui.bossIconCache)
        wipe(ui.npcPortraitCache)
        wipe(ui.npcIconCache)
        wipe(ui.bossJournalEncounterCache)
        wipe(self.playerCacheByName)
        self:RefreshRosterCache()
        self:RefreshVisibleRows()
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        self:RefreshRosterCache()
        self:RefreshVisibleRows()
        return
    end

    if event == "INSPECT_READY" then
        local guid = ...
        self:StoreInspectSpec(guid)
        self:RefreshVisibleRows()
    end
end

function Prototype:BuildUnitList()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for index = 1, 40 do
            units[#units + 1] = "raid" .. index
        end
    elseif IsInGroup and IsInGroup() then
        for index = 1, 4 do
            units[#units + 1] = "party" .. index
        end
    end
    return units
end

function Prototype:GetUnitSpec(unit)
    if unit == "player" then
        local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization() or (GetSpecialization and GetSpecialization())
        return CaptureSpecInfoByIndex(specIndex, false)
    end

    if GetInspectSpecialization then
        local ok, specID = pcall(GetInspectSpecialization, unit)
        if ok and tonumber(specID) and tonumber(specID) > 0 then
            return CaptureSpecInfoByID(specID) or { specID = tonumber(specID) }
        end
    end
    return nil
end

function Prototype:StoreUnitCache(unit)
    if not (unit and UnitExists and UnitExists(unit)) then
        return
    end
    local name, realm = UnitName(unit)
    if not name or name == "" then
        return
    end

    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    end

    local localizedClass, classFile = UnitClass(unit)
    local guid = UnitGUID(unit)
    local spec = self:GetUnitSpec(unit)
    local record = {
        name = name,
        realm = realm,
        classFile = classFile,
        specID = spec and spec.specID or nil,
        specIcon = spec and spec.icon or nil,
        ts = time and time() or 0,
        unit = unit,
        guid = guid,
    }

    local fullKey = realm and realm ~= "" and (name .. "-" .. realm) or name
    self.playerCacheByName[name] = record
    self.playerCacheByName[fullKey] = record

    local ui = GetSemanticUI()
    if guid and guid ~= "" then
        ui.playerCacheById[guid] = {
            name = name,
            realm = realm,
            classFile = classFile,
            specID = record.specID,
            specIcon = record.specIcon,
            ts = record.ts,
        }
    end

    if unit ~= "player" and guid and not record.specID then
        self:RequestInspect(unit, guid)
    end
end

function Prototype:RefreshRosterCache()
    wipe(self.playerCacheByName)
    for _, unit in ipairs(self:BuildUnitList()) do
        self:StoreUnitCache(unit)
    end
end

function Prototype:RequestInspect(unit, guid)
    if not (NotifyInspect and CanInspect and UnitIsPlayer and unit and guid) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if self.pendingInspect[guid] then
        return
    end
    if not UnitIsPlayer(unit) or not CanInspect(unit) then
        return
    end

    self.pendingInspect[guid] = unit
    pcall(NotifyInspect, unit)
end

function Prototype:StoreInspectSpec(guid)
    local unit = self.pendingInspect[guid]
    self.pendingInspect[guid] = nil
    if not unit then
        for _, candidate in ipairs(self:BuildUnitList()) do
            if UnitGUID(candidate) == guid then
                unit = candidate
                break
            end
        end
    end
    if not unit then
        return
    end
    self:StoreUnitCache(unit)
end

function Prototype:FindPlayerCache(playerInfo, displayText)
    local name = playerInfo and playerInfo.name or displayText
    local realm = playerInfo and playerInfo.realm or nil
    if realm and realm ~= "" then
        local fullKey = tostring(name or "") .. "-" .. tostring(realm)
        if self.playerCacheByName[fullKey] then
            return self.playerCacheByName[fullKey]
        end
    end
    return self.playerCacheByName[tostring(name or displayText or "")]
end

function Prototype:ResolveBossJournalEncounterID(encounterID, instanceIDHint)
    local id = tonumber(encounterID)
    local jiid = tonumber(instanceIDHint)
    if not id or id <= 0 or not jiid or jiid <= 0 or not EJ_GetEncounterInfoByIndex then
        return nil
    end

    local ui = GetSemanticUI()
    local cached = ui.bossJournalEncounterCache[id]
    if cached ~= nil then
        return tonumber(cached) and tonumber(cached) > 0 and tonumber(cached) or nil
    end

    local sem = T and T.SemanticTimeline or nil
    if sem and sem.EnsureEncounterJournalLoaded then
        sem:EnsureEncounterJournalLoaded()
    end

    if EJ_SelectInstance then
        pcall(EJ_SelectInstance, jiid)
    end

    local resolved = nil
    for index = 1, 30 do
        local ok, name, _, jeid, _, _, _, deid = pcall(EJ_GetEncounterInfoByIndex, index, jiid)
        if not ok or type(name) ~= "string" or name == "" then
            break
        end
        if tonumber(deid) == id or tonumber(jeid) == id then
            resolved = tonumber(jeid)
            break
        end
    end

    ui.bossJournalEncounterCache[id] = resolved or 0
    return resolved
end

function Prototype:ResolveBossVisual(encounterID, instanceIDHint, encounterIcon)
    local id = tonumber(encounterID)
    if not id or id <= 0 then
        return TextureVisual(DEFAULT_ICON)
    end
    local staticIcon = tonumber(encounterIcon)
    if staticIcon and staticIcon > 0 then
        return TextureVisual(staticIcon, { 0, 1, 0, 0.95 })
    end
    local overrideIcon = ENCOUNTER_ICON_OVERRIDES[id]
    if overrideIcon then
        return TextureVisual(overrideIcon, { 0, 1, 0, 0.95 })
    end

    local ui = GetSemanticUI()
    local cachedIcon = ui.bossIconCache[id]
    if cachedIcon ~= nil then
        return TextureVisual(cachedIcon ~= 0 and cachedIcon or nil, { 0, 1, 0, 0.95 })
            or PortraitVisual(ui.bossPortraitCache[id])
            or TextureVisual(DEFAULT_ICON)
    end

    local journalEncounterID = self:ResolveBossJournalEncounterID(id, instanceIDHint) or id
    local iconImage = nil
    local displayInfoID = nil
    if EJ_SelectEncounter and journalEncounterID then
        pcall(EJ_SelectEncounter, journalEncounterID)
    end
    if EJ_GetCreatureInfo then
        for index = 1, 8 do
            local ok, creatureID, name, description, displayInfo, icon = pcall(EJ_GetCreatureInfo, index, journalEncounterID)
            if ok and creatureID then
                if not iconImage and icon then
                    iconImage = icon
                end
                if not displayInfoID and tonumber(displayInfo) and tonumber(displayInfo) > 0 then
                    displayInfoID = tonumber(displayInfo)
                end
            end
            if iconImage then
                break
            end
        end
    end

    ui.bossIconCache[id] = iconImage or 0
    ui.bossPortraitCache[id] = displayInfoID or 0
    if not iconImage and C and C.DB and C.DB.debugMode and T.debug and not self.bossIconMissLogged[id] then
        self.bossIconMissLogged[id] = true
        T.debug(string.format("[STT_HTG_BOSS_ICON_MISS] encounterID=%d journalEncounterID=%s", id, tostring(journalEncounterID)))
    end
    return TextureVisual(iconImage, { 0, 1, 0, 0.95 }) or PortraitVisual(displayInfoID) or TextureVisual(DEFAULT_ICON)
end

function Prototype:ResolveNpcVisual(encounterID, npcName, instanceIDHint, spellIconFallback, encounterIconFallback)
    local id = tonumber(encounterID)
    local targetName = type(npcName) == "string" and NormalizeActorName(npcName) or ""
    if not id or id <= 0 or targetName == "" then
        return TextureVisual(spellIconFallback, { 0, 1, 0, 0.95 })
            or TextureVisual(encounterIconFallback, { 0, 1, 0, 0.95 })
            or TextureVisual(DEFAULT_ICON)
    end

    local ui = GetSemanticUI()
    local cacheKey = tostring(id) .. ":" .. targetName
    local cachedIcon = ui.npcIconCache[cacheKey]
    if cachedIcon ~= nil then
        return TextureVisual(cachedIcon ~= 0 and cachedIcon or nil, { 0, 1, 0, 0.95 })
            or PortraitVisual(ui.npcPortraitCache[cacheKey])
            or TextureVisual(spellIconFallback, { 0, 1, 0, 0.95 })
            or TextureVisual(encounterIconFallback, { 0, 1, 0, 0.95 })
            or TextureVisual(DEFAULT_ICON)
    end

    local journalEncounterID = self:ResolveBossJournalEncounterID(id, instanceIDHint) or id
    local iconImage = nil
    local displayInfoID = nil
    if EJ_SelectEncounter and journalEncounterID then
        pcall(EJ_SelectEncounter, journalEncounterID)
    end
    if EJ_GetCreatureInfo then
        for index = 1, 30 do
            local ok, creatureID, name, _, displayInfo, icon = pcall(EJ_GetCreatureInfo, index, journalEncounterID)
            if not ok or not creatureID then
                break
            end
            if NormalizeActorName(name) == targetName then
                iconImage = icon
                if tonumber(displayInfo) and tonumber(displayInfo) > 0 then
                    displayInfoID = tonumber(displayInfo)
                end
                break
            end
        end
    end

    ui.npcIconCache[cacheKey] = iconImage or 0
    ui.npcPortraitCache[cacheKey] = displayInfoID or 0
    if not iconImage and C and C.DB and C.DB.debugMode and T.debug and not self.npcIconMissLogged[cacheKey] then
        self.npcIconMissLogged[cacheKey] = true
        T.debug(string.format("[STT_HTG_NPC_ICON_MISS] encounterID=%d journalEncounterID=%s npc=%s", id, tostring(journalEncounterID), targetName))
    end
    return TextureVisual(iconImage, { 0, 1, 0, 0.95 })
        or PortraitVisual(displayInfoID)
        or TextureVisual(spellIconFallback, { 0, 1, 0, 0.95 })
        or TextureVisual(encounterIconFallback, { 0, 1, 0, 0.95 })
        or TextureVisual(DEFAULT_ICON)
end

local function GetEntryFirstSpellIcon(entry)
    for _, item in ipairs((entry and entry.items) or {}) do
        local icon = item.spellIcon or ResolveActorSpellIcon(item.spellID)
        if icon then
            return icon
        end
    end
    return nil
end

function Prototype:GetTrackWidth()
    if not self.rulerClip then
        return 0
    end
    return math.max(0, tonumber(self.rulerClip:GetWidth()) or 0)
end

function Prototype:GetScrollRange()
    return math.max(0, (tonumber(self.contentWidth) or 0) - self:GetTrackWidth())
end

function Prototype:GetTimeGrid()
    local data = T.HorizontalTimelineData
    if data and data.BuildTimeGrid then
        return data.BuildTimeGrid(self.pxPerSecond or DEFAULT_PX_PER_SECOND, self:GetTrackWidth())
    end
    return {
        minorStep = 10,
        majorStep = 30,
        labelStep = 30,
        snapStep = 1,
        precision = 0,
        minorVisible = true,
    }
end

function Prototype:LogRulerScaleIfChanged(grid)
end

function Prototype:GetMinPxPerSecond()
    local trackWidth = self:GetTrackWidth()
    local totalSeconds = math.max(1, tonumber(self.totalSeconds) or 30)
    if trackWidth <= 0 then
        return MIN_PX_PER_SECOND
    end
    return Clamp(trackWidth / totalSeconds, MIN_PX_PER_SECOND, MAX_PX_PER_SECOND)
end

function Prototype:RefreshContentWidth()
    self.contentWidth = math.max(1, math.ceil((tonumber(self.totalSeconds) or 30) * (self.pxPerSecond or DEFAULT_PX_PER_SECOND)))
end

function Prototype:GetRulerRenderSignature()
    local grid = self:GetTimeGrid()
    local markerParts = {}
    for _, marker in ipairs(self.phaseDisplayStats and self.phaseDisplayStats.markers or {}) do
        markerParts[#markerParts + 1] = tostring(marker.displayKey or marker.key or "")
        markerParts[#markerParts + 1] = tostring(math.floor((tonumber(marker.time) or 0) * 10 + 0.5))
    end
    return JoinSignature({
        math.floor((tonumber(self.scrollX) or 0) * 10 + 0.5),
        math.floor((tonumber(self.pxPerSecond) or 0) * 100 + 0.5),
        math.floor((tonumber(self.totalSeconds) or 0) * 10 + 0.5),
        math.floor((tonumber(self.contentWidth) or 0) + 0.5),
        math.floor((tonumber(self.firstColWidth) or 0) + 0.5),
        math.floor((tonumber(self:GetTrackWidth()) or 0) + 0.5),
        grid.minorStep,
        grid.labelStep,
        grid.precision,
        table.concat(markerParts, "\030"),
    })
end

function Prototype:RenderRulerIfNeeded(force)
    local signature = self:GetRulerRenderSignature()
    if force ~= true and signature == self.rulerRenderSignature then
        self:UpdatePlayhead(self.runnerTime or 0, self.lastRunnerPlaying == true)
        return false
    end
    self.rulerRenderSignature = signature
    self:RenderRuler()
    return true
end

function Prototype:ApplyPxPerSecondBounds()
    local prefs = GetPrefs()
    local oldValue = self.pxPerSecond or prefs.pxPerSecond or DEFAULT_PX_PER_SECOND
    local newValue = Clamp(oldValue, self:GetMinPxPerSecond(), MAX_PX_PER_SECOND)
    if math.abs(newValue - oldValue) < 0.01 then
        return false
    end
    self.pxPerSecond = newValue
    prefs.pxPerSecond = newValue
    self:RefreshContentWidth()
    return true
end

function Prototype:StopHorizontalMotion()
    if self.horizontalDriver then
        self.horizontalDriver:StopScrolling()
    end
end

function Prototype:GetHorizontalWheelStep()
    return math.max(80, math.floor((self.pxPerSecond or DEFAULT_PX_PER_SECOND) * 5))
end

function Prototype:EnsureHorizontalDriver()
    if not T.CreateSmoothValueDriver then
        return nil
    end
    local range = self:GetScrollRange()
    if not self.horizontalDriver then
        self.horizontalDriver = T.CreateSmoothValueDriver({
            offset = self.scrollX or 0,
            range = range,
            stepSize = self:GetHorizontalWheelStep(),
            blendSpeed = HSCROLL_BLEND_SPEED,
            onValueChanged = function(_, offset)
                self:SetScrollX(offset, "wheel")
            end,
        })
    else
        self.horizontalDriver:SetScrollRange(range)
        self.horizontalDriver:SetStepSize(self:GetHorizontalWheelStep())
        self.horizontalDriver:SetBlendSpeed(HSCROLL_BLEND_SPEED)
    end
    return self.horizontalDriver
end

function Prototype:SetScrollX(value, cause)
	local range = self:GetScrollRange()
	local nextValue = Clamp(value, 0, range)
    if cause == "wheel" or cause == "bar" or cause == "bar_jump" or cause == "middle_drag" or cause == "zoom" then
        self.autoFollow = false
    end
	self.scrollX = nextValue
    if ShouldPersistScrollX(cause) then
        GetPrefs().scrollX = nextValue
    end
    self:RecordScrollProfileFrame()
    if self.horizontalDriver and cause ~= "wheel" then
        self.horizontalDriver:SetScrollRange(range)
        self.horizontalDriver:SnapTo(nextValue)
    end
	self:RenderRulerIfNeeded()
	self:ApplyHorizontalOffset()
    self:RefreshVisibleRowsForHorizontalWindow()
    self:UpdatePlayhead(self.runnerTime or 0)
	if self.hScrollBar and self.hScrollBar.Refresh then
		self.hScrollBar:Refresh()
	end
end

function Prototype:ScrollHorizontalBy(delta)
    local step = self:GetHorizontalWheelStep()
    local driver = self:EnsureHorizontalDriver()
    if driver then
        driver:SetStepSize(step)
        driver:ScrollBy(-((tonumber(delta) or 0) * step))
        return
    end
    self:SetScrollX((self.scrollX or 0) - ((tonumber(delta) or 0) * step), "wheel")
end

function Prototype:ApplyRowHorizontalOffset(row)
    if not (row and row.trackContent and row.trackClip) then
        return
    end

    local yOffset = tonumber(row._disclosureYOffset) or 0
    row.trackContent:ClearAllPoints()
    row.trackContent:SetPoint("TOPLEFT", row.trackClip, "TOPLEFT", -self.scrollX, yOffset)
    row.trackContent:SetPoint("BOTTOMLEFT", row.trackClip, "BOTTOMLEFT", -self.scrollX, yOffset)
    row.trackContent:SetWidth(math.max(1, self.contentWidth))
end

function Prototype:ApplyHorizontalOffset()
	if self.rulerContent and self.rulerClip then
		self.rulerContent:ClearAllPoints()
		self.rulerContent:SetPoint("TOPLEFT", self.rulerClip, "TOPLEFT", -self.scrollX, 0)
        self.rulerContent:SetHeight(RULER_HEIGHT)
        self.rulerContent:SetWidth(math.max(1, self.contentWidth))
    end

    for _, row in ipairs(self.rowFrames or {}) do
        self:ApplyRowHorizontalOffset(row)
	end
end

function Prototype:GetChipWindowBucket()
    local trackWidth = math.max(1, self:GetTrackWidth())
    local bucketSize = math.max(1, math.floor(trackWidth * CHIP_WINDOW_BUCKET_RATIO + 0.5))
    return math.floor((tonumber(self.scrollX) or 0) / bucketSize)
end

function Prototype:GetChipWindowRenderKey()
    return string.format("%d:%d", self:GetChipWindowBucket(), math.floor((tonumber(self:GetTrackWidth()) or 0) + 0.5))
end

function Prototype:GetVisibleChipTimeWindow()
    local px = math.max(0.0001, tonumber(self.pxPerSecond) or DEFAULT_PX_PER_SECOND)
    local trackWidth = math.max(1, self:GetTrackWidth())
    local scrollX = tonumber(self.scrollX) or 0
    local startPx = math.max(0, scrollX - (trackWidth * CHIP_WINDOW_BEFORE_VIEW))
    local endPx = scrollX + (trackWidth * CHIP_WINDOW_AFTER_VIEW)
    return startPx / px, endPx / px
end

function Prototype:IsItemInVisibleChipWindow(item, windowStart, windowEnd)
    local startTime = tonumber(item and item.time) or 0
    local duration = tonumber(item and item.duration) or 0
    local endTime = startTime + math.max(0, duration)
    return startTime <= windowEnd and endTime >= windowStart
end

function Prototype:RefreshVisibleRowsForHorizontalWindow()
    local bucket = self:GetChipWindowBucket()
    if bucket == self.lastChipWindowBucket then
        return
    end
    self.lastChipWindowBucket = bucket
    self:RefreshVisibleRows()
end

function Prototype:GetRulerTimeFromCursor()
    local px = math.max(0.0001, tonumber(self.pxPerSecond) or DEFAULT_PX_PER_SECOND)
    local cursorX = GetCursorXInFrame(self.rulerClip)
    return math.max(0, ((tonumber(self.scrollX) or 0) + cursorX) / px)
end

function Prototype:UpdateScrubEdgeAutoScroll(elapsed)
    if not self.rulerClip then
        return
    end
    local trackWidth = self:GetTrackWidth()
    local range = self:GetScrollRange()
    if trackWidth <= 0 or range <= 0 then
        return
    end

    local cursorX = GetCursorXInFrame(self.rulerClip)
    local direction, distance = nil, 0
    if cursorX < SCRUB_EDGE_MARGIN then
        direction = -1
        distance = SCRUB_EDGE_MARGIN - cursorX
    elseif cursorX > trackWidth - SCRUB_EDGE_MARGIN then
        direction = 1
        distance = cursorX - (trackWidth - SCRUB_EDGE_MARGIN)
    end
    if not direction then
        return
    end

    local dt = Clamp(tonumber(elapsed) or 0.016, 0.001, 0.05)
    local intensity = Clamp(distance / SCRUB_EDGE_MARGIN, 0.25, 2.0)
    self:SetScrollX((tonumber(self.scrollX) or 0) + direction * SCRUB_EDGE_SCROLL_SPEED * intensity * dt, "scrub_auto_scroll")
end

function Prototype:SetTransportPlaying(playing)
    local button = self.transportButton
    if not button or not button.icon then
        return
    end

    button.icon:Hide()
    if button.pauseLeft then
        button.pauseLeft:Hide()
    end
    if button.pauseRight then
        button.pauseRight:Hide()
    end

    if playing then
        if AtlasExists(TRANSPORT_PAUSE_ATLAS) then
            button.icon:ClearAllPoints()
            button.icon:SetAtlas(TRANSPORT_PAUSE_ATLAS, false)
            button.icon:SetSize(13, 13)
            button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
            button.icon:Show()
        else
            if button.pauseLeft then
                button.pauseLeft:Show()
            end
            if button.pauseRight then
                button.pauseRight:Show()
            end
        end
    else
        button.icon:ClearAllPoints()
        button.icon:SetAtlas(TRANSPORT_PLAY_ATLAS, false)
        button.icon:SetSize(13, 13)
        button.icon:SetPoint("CENTER", button, "CENTER", 1, 0)
        button.icon:Show()
    end
end

function Prototype:SetTransportTime(timeValue)
    if self.transportTimeText then
        self.transportTimeText:SetText(FormatTime(timeValue or 0, 2, true))
    end
end

function Prototype:ToggleTransport()
    local runner = T.TimelineRunner
    if not (runner and runner.GetState and runner.Play and runner.Pause) then
        return
    end
    local state = runner:GetState()
    if state and state.playing then
        runner:Pause()
    else
        self.autoFollow = true
        runner:Play(state and state.currentTime or self.runnerTime or 0)
    end
    self:LogInputConsumeOnce("transport_toggle")
    self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_PLAY"] or "Space 播放/暂停", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
end

function Prototype:StopTransport()
    local runner = T.TimelineRunner
    if not (runner and runner.Stop) then
        return
    end
    runner:Stop()
    self.autoFollow = false
    self:LogInputConsumeOnce("transport_stop")
    self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_STOP"] or "已停止播放", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
end

function Prototype:BeginRulerSeekClick()
    local runner = T.TimelineRunner
    local state = runner and runner.GetState and runner:GetState() or {}
    self.rulerSeekClick = {
        x = GetCursorXInFrame(self.rulerClip),
        time = self:GetRulerTimeFromCursor(),
        wasPlaying = state.playing == true,
    }
    if self.rulerClip and self.rulerClip.SetScript then
        self.rulerClip:SetScript("OnUpdate", function(_, elapsed)
            self:UpdateRulerSeekDrag(elapsed)
        end)
    end
    if self.rulerSeekClick.wasPlaying and runner and runner.Pause then
        runner:Pause()
    end
    self:UpdateRulerSeekDrag(0)
end

function Prototype:FinishRulerSeekClick()
    local click = self.rulerSeekClick
    self.rulerSeekClick = nil
    if self.rulerClip and self.rulerClip.SetScript then
        self.rulerClip:SetScript("OnUpdate", nil)
    end
    if not click then
        return
    end
    local targetTime = tonumber(click.time) or self:GetRulerTimeFromCursor()
    if T.TimelineRunner and T.TimelineRunner.Seek then
        T.TimelineRunner:Seek(targetTime, { silent = true, preserveState = false })
        if click.wasPlaying and T.TimelineRunner.Play then
            self.autoFollow = true
            T.TimelineRunner:Play(targetTime)
        end
        self:LogInputConsumeOnce("ruler_seek")
        self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_SEEK"] or "已定位 · 拖动播放头或单击时间尺继续定位", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
    end
end

function Prototype:UpdateRulerSeekDrag(elapsed)
    if not self.rulerSeekClick then
        return
    end
    self:UpdateScrubEdgeAutoScroll(elapsed)
    local rawTime = self:GetRulerTimeFromCursor()
    local targetTime = rawTime
    if T.HorizontalTimelineData and T.HorizontalTimelineData.GetDragTargetTime then
        targetTime = T.HorizontalTimelineData.GetDragTargetTime(rawTime, IsShiftKeyDown and IsShiftKeyDown(), self:GetTimeGrid())
    end
    self.rulerSeekClick.time = targetTime
    self.runnerTime = targetTime
    if T.TimelineRunner and T.TimelineRunner.Seek then
        if math.abs(targetTime - (tonumber(self.rulerSeekClick.lastSeekTime) or -99999)) >= 0.01 then
            self.rulerSeekClick.lastSeekTime = targetTime
            T.TimelineRunner:Seek(targetTime, { silent = true, preserveState = false })
        end
    else
        self:SetTransportTime(targetTime)
        self:UpdatePlayhead(targetTime)
    end
end

function Prototype:StartPlayheadDrag(button)
    if button ~= "LeftButton" then
        return
    end
    local runner = T.TimelineRunner
    local state = runner and runner.GetState and runner:GetState() or {}
    self.playheadDrag = {
        wasPlaying = state.playing == true,
        time = tonumber(state.currentTime) or self.runnerTime or 0,
    }
    if self.playhead and self.playhead.SetScript then
        self.playhead:SetScript("OnUpdate", function(_, elapsed)
            self:UpdatePlayheadDrag(elapsed)
        end)
    end
    if self.playheadDrag.wasPlaying and runner and runner.Pause then
        runner:Pause()
    end
    self:LogInputConsumeOnce("playhead_drag")
    self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_PLAYHEAD"] or "拖动播放头定位 · 松开确认", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
end

function Prototype:UpdatePlayheadDrag(elapsed)
    if not self.playheadDrag then
        return
    end
    self:UpdateScrubEdgeAutoScroll(elapsed)
    local rawTime = self:GetRulerTimeFromCursor()
    local targetTime = rawTime
    if T.HorizontalTimelineData and T.HorizontalTimelineData.GetDragTargetTime then
        targetTime = T.HorizontalTimelineData.GetDragTargetTime(rawTime, IsShiftKeyDown and IsShiftKeyDown(), self:GetTimeGrid())
    end
    self.playheadDrag.time = targetTime
    self.runnerTime = targetTime
    self:SetTransportTime(targetTime)
    self:UpdatePlayhead(targetTime)
end

function Prototype:StopPlayheadDrag(button)
    if button ~= "LeftButton" or not self.playheadDrag then
        return
    end
    if self.playhead then
        self.playhead:SetScript("OnUpdate", nil)
    end
    local drag = self.playheadDrag
    self.playheadDrag = nil
    local targetTime = tonumber(drag.time) or self.runnerTime or 0
    if T.TimelineRunner and T.TimelineRunner.Seek then
        T.TimelineRunner:Seek(targetTime, { silent = true, preserveState = false })
        if drag.wasPlaying and T.TimelineRunner.Play then
            self.autoFollow = true
            T.TimelineRunner:Play(targetTime)
        end
    end
end

function Prototype:UpdatePlayhead(timeValue, playing)
    if not (self.playhead and self.rulerClip) then
        return
    end
    local trackWidth = self:GetTrackWidth()
    local px = self.pxPerSecond or DEFAULT_PX_PER_SECOND
    local x = (math.max(0, tonumber(timeValue) or 0) * px) - (tonumber(self.scrollX) or 0)
    if x < -8 or x > trackWidth + 8 then
        self.playhead:Hide()
        return
    end
    self.playhead:ClearAllPoints()
    self.playhead:SetPoint("TOPLEFT", self.rulerClip, "TOPLEFT", math.floor(x - 7 + 0.5), 0)
    self.playhead:SetHeight(math.max(RULER_HEIGHT + DEFAULT_ROW_HEIGHT, self.root:GetHeight() or 0))
    if self.playhead.line then
        self.playhead.line:SetHeight(math.max(1, (self.playhead:GetHeight() or 0) - RULER_HEIGHT))
        self.playhead.line:SetColorTexture(unpackFunc(playing and PLAYHEAD_COLOR or PLAYHEAD_PAUSED_COLOR))
    end
    self.playhead:Show()
end

function Prototype:AutoFollowPlayhead(timeValue)
    if not self.autoFollow then
        return
    end
    local trackWidth = self:GetTrackWidth()
    if trackWidth <= 0 then
        return
    end
    local px = self.pxPerSecond or DEFAULT_PX_PER_SECOND
    local x = (math.max(0, tonumber(timeValue) or 0) * px) - (tonumber(self.scrollX) or 0)
    if x > trackWidth * 0.82 then
        self:SetScrollX((timeValue * px) - (trackWidth * 0.45), "follow")
    elseif x < trackWidth * 0.12 then
        self:SetScrollX((timeValue * px) - (trackWidth * 0.25), "follow")
    end
end

function Prototype:OnRunnerTick(state)
    state = type(state) == "table" and state or {}
    local playing = state.playing == true
    if playing and not self.lastRunnerPlaying then
        self.autoFollow = true
    end
    self.lastRunnerPlaying = playing
    self.runnerTime = tonumber(state.currentTime) or self.runnerTime or 0
    self:SetTransportPlaying(playing)
    self:SetTransportTime(self.runnerTime)
    if playing then
        self:AutoFollowPlayhead(self.runnerTime)
    end
    self:UpdatePlayhead(self.runnerTime, playing)
end

function Prototype:SetPxPerSecond(value, cursorFrame)
    local prefs = GetPrefs()
    local oldValue = self.pxPerSecond or prefs.pxPerSecond or DEFAULT_PX_PER_SECOND
    local minPxPerSecond = self:GetMinPxPerSecond()
    local newValue = Clamp(value, minPxPerSecond, MAX_PX_PER_SECOND)
    if math.abs(newValue - oldValue) < 0.01 then
        return
    end

    local frame = cursorFrame or self.rulerClip
    local cursorX = GetCursorXInFrame(frame)
    local trackWidth = self:GetTrackWidth()
    if cursorX < 0 or cursorX > trackWidth then
        cursorX = trackWidth * 0.5
    end

    local zoomTime = (self.scrollX + cursorX) / oldValue
    self.pxPerSecond = newValue
    prefs.pxPerSecond = newValue
    self:RefreshContentWidth()
    self:SetScrollX(zoomTime * newValue - cursorX, "zoom")
    self:RefreshVisibleRows()

    if C and C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format(
            "[STT_HTG_ZOOM] pxPerSecond=%.2f minPx=%.2f maxTime=%.1f scrollX=%.0f",
            newValue,
            minPxPerSecond,
            tonumber(self.maxTime) or 0,
            self.scrollX or 0
        ))
    end
end

function Prototype:ScrollVerticalByWheel(delta)
    if self.rowsScroll and self.rowsScrollBaseOnMouseWheel then
        self.rowsScrollBaseOnMouseWheel(self.rowsScroll, delta)
    end
end

function Prototype:LogInputConsumeOnce(action)
    local key = tostring(action or "")
    if key == "" then
        return
    end
    self.inputConsumeLogSeen = self.inputConsumeLogSeen or {}
    if self.inputConsumeLogSeen[key] then
        return
    end
    self.inputConsumeLogSeen[key] = true
    if T and T.LogDebugEvent then
        T.LogDebugEvent("STT_PLAN_INPUT_CONSUME", {
            action = key,
            view = "horizontal",
        })
    end
end

function Prototype:IsScrollProfileEnabled()
    if not (C and C.DB and C.DB.debugMode and T.debug) then
        return false
    end
    return true
end

function Prototype:BeginScrollProfile(route)
    if not self:IsScrollProfileEnabled() then
        return nil
    end

    local profile = self.scrollProfile
    if not profile then
        profile = {}
        self.scrollProfile = profile
    end

    if not profile.active then
        profile.active = true
        profile.route = route or "unknown"
        profile.startTime = debugprofilestop and debugprofilestop() or 0
        profile.idleElapsed = 0
        profile.wheelEvents = 0
        profile.updateFrames = 0
        profile.viewRefreshes = 0
        profile.renderRows = 0
        profile.renderChips = 0
        profile.createdChips = 0
        profile.hiddenChips = 0
        profile.rangeX = self:GetScrollRange()
        profile.rangeY = self.rowsScroll and self.rowsScroll.GetScrollRange and self.rowsScroll:GetScrollRange() or 0

        if not self.scrollProfileFrame then
            self.scrollProfileFrame = CreateFrame("Frame", nil, UIParent)
            self.scrollProfileFrame.owner = self
        end
        self.scrollProfileFrame:SetScript("OnUpdate", function(frame, elapsed)
            frame.owner:UpdateScrollProfile(elapsed)
        end)
    end

    profile.route = route or profile.route or "unknown"
    profile.idleElapsed = 0
    return profile
end

function Prototype:RecordScrollProfileInput(route)
    local profile = self:BeginScrollProfile(route)
    if profile then
        profile.wheelEvents = (profile.wheelEvents or 0) + 1
    end
end

function Prototype:RecordScrollProfileFrame()
    local profile = self.scrollProfile
    if profile and profile.active then
        profile.updateFrames = (profile.updateFrames or 0) + 1
        profile.idleElapsed = 0
    end
end

function Prototype:RecordScrollProfileViewRefresh()
    local profile = self.scrollProfile
    if profile and profile.active then
        profile.viewRefreshes = (profile.viewRefreshes or 0) + 1
    end
end

function Prototype:AddScrollProfileCount(key)
    local profile = self.scrollProfile
    if profile and profile.active then
        profile[key] = (profile[key] or 0) + 1
    end
end

function Prototype:UpdateScrollProfile(elapsed)
    local profile = self.scrollProfile
    if not (profile and profile.active) then
        if self.scrollProfileFrame then
            self.scrollProfileFrame:SetScript("OnUpdate", nil)
        end
        return
    end

    profile.idleElapsed = (profile.idleElapsed or 0) + (tonumber(elapsed) or 0)
    local verticalScrolling = self.rowsScroll and self.rowsScroll.isScrolling
    local horizontalScrolling = self.horizontalDriver and self.horizontalDriver.isScrolling
    if profile.idleElapsed < SCROLL_PROFILE_IDLE_SECONDS or verticalScrolling or horizontalScrolling then
        return
    end

    self:FinishScrollProfile()
end

function Prototype:FinishScrollProfile()
    local profile = self.scrollProfile
    if not (profile and profile.active) then
        return
    end

    profile.active = false
    if self.scrollProfileFrame then
        self.scrollProfileFrame:SetScript("OnUpdate", nil)
    end

    local now = debugprofilestop and debugprofilestop() or 0
    local elapsedMs = math.max(0, now - (tonumber(profile.startTime) or now))
    local rowsScroll = self.rowsScroll
    T.debug(string.format(
        "STT_HTG_SCROLL_PROFILE route=%s wheelEvents=%d updateFrames=%d viewRefreshes=%d renderRows=%d renderChips=%d createdChips=%d hiddenChips=%d elapsedMs=%.1f rangeX=%.1f rangeY=%.1f first=%d rows=%d",
        tostring(profile.route or "unknown"),
        tonumber(profile.wheelEvents) or 0,
        tonumber(profile.updateFrames) or 0,
        tonumber(profile.viewRefreshes) or 0,
        tonumber(profile.renderRows) or 0,
        tonumber(profile.renderChips) or 0,
        tonumber(profile.createdChips) or 0,
        tonumber(profile.hiddenChips) or 0,
        elapsedMs,
        tonumber(profile.rangeX) or self:GetScrollRange(),
        tonumber(profile.rangeY) or (rowsScroll and rowsScroll.GetScrollRange and rowsScroll:GetScrollRange() or 0),
        rowsScroll and rowsScroll.GetFirstVisibleDataIndex and rowsScroll:GetFirstVisibleDataIndex() or 0,
        #(self.orderedKeys or {})
    ))
end

function Prototype:HandleMouseWheel(delta, cursorFrame, verticalFallback)
    if IsAltKeyDown and IsShiftKeyDown and IsAltKeyDown() and IsShiftKeyDown() then
        self:LogInputConsumeOnce("horizontal_zoom")
        self:RecordScrollProfileInput("zoom")
        local factor = (tonumber(delta) or 0) > 0 and ZOOM_STEP or (1 / ZOOM_STEP)
        self:SetPxPerSecond((self.pxPerSecond or DEFAULT_PX_PER_SECOND) * factor, cursorFrame)
        self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_ZOOM"] or "已缩放 · Alt/Option+Shift+滚轮继续缩放", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
        return
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        self:LogInputConsumeOnce("horizontal_pan")
        self:RecordScrollProfileInput("horizontal")
        self:ScrollHorizontalBy(delta)
        self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_PAN"] or "已横移 · Shift+滚轮继续横移", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
        return
    end
    self:RecordScrollProfileInput("vertical")
    if verticalFallback then
        verticalFallback(delta)
        return
    end
    self:ScrollVerticalByWheel(delta)
end

function Prototype:StartMiddleDrag(button)
    if button ~= "MiddleButton" then
        return
    end
    self:LogInputConsumeOnce("middle_drag")
    self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_MIDDLE_DRAG"] or "中键拖动横移 · 松开停止", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
    self.dragging = true
    self.dragStartX = GetCursorXInFrame(UIParent)
    self.dragStartScrollX = self.scrollX or 0
    self.root:SetScript("OnUpdate", function()
        if IsMouseButtonDown and not IsMouseButtonDown() then
            self:StopMiddleDrag("MiddleButton")
            return
        end
        local cursorX = GetCursorXInFrame(UIParent)
        self:SetScrollX((self.dragStartScrollX or 0) - (cursorX - (self.dragStartX or cursorX)), "middle_drag")
    end)
end

function Prototype:StopMiddleDrag(button)
    if button ~= "MiddleButton" or not self.dragging then
        return
    end
    self.dragging = false
    self.root:SetScript("OnUpdate", nil)
end

function Prototype:SetAllChipAlpha(alpha)
    local value = tonumber(alpha) or 1
    for _, row in ipairs(self.rowFrames or {}) do
        for _, chip in ipairs(row.chips or {}) do
            if chip and chip.SetAlpha then
                chip:SetAlpha(value)
            end
        end
    end
end

function Prototype:EnsureSnapGuide()
    if self.snapGuide then
        return self.snapGuide
    end
    local guide = self.root:CreateTexture(nil, "OVERLAY")
    guide:SetWidth(2)
    guide:SetColorTexture(1, 0.86, 0.18, 0.85)
    guide:Hide()
    self.snapGuide = guide
    return guide
end

function Prototype:HideSnapGuide()
    if self.snapGuide then
        self.snapGuide:Hide()
    end
    if self.dragTimeBadge then
        self.dragTimeBadge:Hide()
    end
    self.lastGuideX = nil
    self.lastBadgeX = nil
    self.lastGuideColorSource = nil
    self.lastGuideSource = nil
    self.lastGuideLabelValue = nil
    self.lastGuidePrecision = nil
end

function Prototype:EnsureDragTimeBadge()
    if self.dragTimeBadge then
        return self.dragTimeBadge
    end
    local badge = CreateFrame("Frame", nil, self.root, "BackdropTemplate")
    badge:SetSize(72, 22)
    badge:SetFrameLevel((self.root:GetFrameLevel() or 0) + 60)
    ApplyBackdrop(badge, { alpha = 0.92 })
    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge:Hide()
    self.dragTimeBadge = badge
    return badge
end

function Prototype:UpdateDragGuide(targetTime, source, precision)
    if targetTime == nil then
        self:HideSnapGuide()
        return
    end
    local guide = self:EnsureSnapGuide()
    local x = self.firstColWidth + math.floor(((tonumber(targetTime) or 0) * (self.pxPerSecond or DEFAULT_PX_PER_SECOND)) - (self.scrollX or 0) + 0.5)
    if self.lastGuideColorSource ~= source then
        if source == "integer" or source == "snap" then
            guide:SetColorTexture(0.55, 0.80, 1, 0.86)
        else
            guide:SetColorTexture(1, 1, 1, 0.72)
        end
        self.lastGuideColorSource = source
    end
    if self.lastGuideX ~= x then
        guide:ClearAllPoints()
        guide:SetPoint("TOPLEFT", self.root, "TOPLEFT", x, -RULER_HEIGHT)
        guide:SetPoint("BOTTOMLEFT", self.root, "BOTTOMLEFT", x, PHASE_MARKER_BOTTOM)
        self.lastGuideX = x
    end
    guide:Show()

    local badge = self:EnsureDragTimeBadge()
    local labelPrecision = math.max(0, tonumber(precision) or 0)
    local factor = 10 ^ labelPrecision
    local labelValue = math.floor((tonumber(targetTime) or 0) * factor + 0.5) / factor
    if self.lastGuideLabelValue ~= labelValue or self.lastGuideSource ~= source or self.lastGuidePrecision ~= labelPrecision then
        badge.text:SetText(FormatTime(labelValue, labelPrecision))
        self.lastGuideLabelValue = labelValue
        self.lastGuideSource = source
        self.lastGuidePrecision = labelPrecision
    end
    if self.lastBadgeX ~= x then
        badge:ClearAllPoints()
        badge:SetPoint("BOTTOM", self.root, "TOPLEFT", x, -RULER_HEIGHT + 2)
        self.lastBadgeX = x
    end
    badge:Show()
end

function Prototype:EnsureGhostChip(row)
    if self.ghostChip and self.ghostChip:GetParent() ~= row.trackContent then
        self.ghostChip:SetParent(row.trackContent)
    end
    if self.ghostChip then
        return self.ghostChip
    end

    local ghost = CreateFrame("Frame", nil, row.trackContent, "BackdropTemplate")
    ghost:SetFrameLevel((row.trackContent:GetFrameLevel() or 0) + 20)
    ghost:SetAlpha(0.55)
    ApplyBackdrop(ghost, { alpha = 0.36 })
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetPoint("TOPLEFT", ghost, "TOPLEFT", 2, -2)
    ghost.icon:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", -2, 2)
    ghost.textCue = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ghost.textCue:SetPoint("CENTER", ghost, "CENTER", 0, 0)
    ghost.textCue:SetJustifyH("CENTER")
    ghost:Hide()
    self.ghostChip = ghost
    return ghost
end

function Prototype:EnsureBatchGhost(index)
    self.batchGhostChips = self.batchGhostChips or {}
    local ghost = self.batchGhostChips[index]
    if ghost then
        ghost:SetParent(self.root)
        ghost:SetFrameLevel((self.root:GetFrameLevel() or 0) + 65)
        return ghost
    end
    ghost = CreateFrame("Frame", nil, self.root, "BackdropTemplate")
    ghost:SetFrameLevel((self.root:GetFrameLevel() or 0) + 65)
    ghost:SetAlpha(0.55)
    ApplyBackdrop(ghost, { alpha = 0.36 })
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetPoint("TOPLEFT", ghost, "TOPLEFT", 2, -2)
    ghost.icon:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", -2, 2)
    ghost.textCue = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ghost.textCue:SetPoint("CENTER", ghost, "CENTER", 0, 0)
    ghost.textCue:SetJustifyH("CENTER")
    ghost:Hide()
    self.batchGhostChips[index] = ghost
    return ghost
end

function Prototype:HideBatchGhostChips()
    for _, ghost in ipairs(self.batchGhostChips or {}) do
        ghost:Hide()
    end
end

function Prototype:ApplyGhostVisual(ghost, item, iconSize)
    if not (ghost and item) then
        return
    end
    if ghost._sttIconSize ~= iconSize then
        ghost:SetSize(iconSize, iconSize)
        ghost._sttIconSize = iconSize
    end
    if item.spellIcon then
        ghost.icon:SetTexture(item.spellIcon)
        ghost.textCue:Hide()
    else
        ghost.icon:SetColorTexture(0.03, 0.03, 0.04, 0.55)
        ghost.textCue:SetText(GetFirstUTF8Char(item.fullText))
        ghost.textCue:Show()
    end
end

function Prototype:PrepareGhostChip(state)
    local row = state and state.row
    local item = state and state.item
    if not (row and item) then
        return
    end
    local iconSize = state.iconSize or DEFAULT_ICON_SIZE
    if state.tokens and #state.tokens > 1 then
        if self.ghostChip then
            self.ghostChip:Hide()
        end
        state.batchGhosts = {}
        local rootLeft = self.root:GetLeft() or 0
        local rootTop = self.root:GetTop() or 0
        local primaryTime = tonumber(item.time) or 0
        local ghostIndex = 0
        for _, token in ipairs(state.tokens) do
            local tokenItem = token.item or token
            local chip = token.chip
            if tokenItem then
                ghostIndex = ghostIndex + 1
                local ghost = self:EnsureBatchGhost(ghostIndex)
                self:ApplyGhostVisual(ghost, tokenItem, iconSize)
                local top = chip and chip.GetTop and chip:GetTop() or nil
                state.batchGhosts[ghostIndex] = {
                    ghost = ghost,
                    item = tokenItem,
                    timeOffset = (tonumber(tokenItem.time) or 0) - primaryTime,
                    topOffset = top and (top - rootTop) or -RULER_HEIGHT,
                }
                ghost:Show()
            end
        end
        for index = ghostIndex + 1, #(self.batchGhostChips or {}) do
            self.batchGhostChips[index]:Hide()
        end
        state.lastBatchGhostKey = nil
        return
    end
    self:HideBatchGhostChips()
    local ghost = self:EnsureGhostChip(row)
    self:ApplyGhostVisual(ghost, item, iconSize)
    ghost:Show()
    state.ghost = ghost
    state.lastGhostX = nil
end

function Prototype:UpdateGhostChip(state, visualTime)
    if state and state.batchGhosts and #state.batchGhosts > 0 then
        local px = state.pxPerSecond or self.pxPerSecond or DEFAULT_PX_PER_SECOND
        local baseTime = tonumber(visualTime) or 0
        local scrollX = tonumber(self.scrollX) or 0
        local targetTopByRowKey = state.batchTargetTopByRowKey
        local rootKey = tostring(math.floor((baseTime * px - scrollX) + 0.5)) .. "|" .. tostring(scrollX) .. "|" .. tostring(targetTopByRowKey)
        if state.lastBatchGhostKey == rootKey then
            return
        end
        for _, entry in ipairs(state.batchGhosts) do
            local ghost = entry.ghost
            local x = self.firstColWidth + math.floor(((baseTime + (entry.timeOffset or 0)) * px) - scrollX + 0.5)
            local rowKey = tostring(entry.item and entry.item.rowKey or "")
            local y = tonumber(targetTopByRowKey and targetTopByRowKey[rowKey]) or tonumber(entry.topOffset) or -RULER_HEIGHT
            ghost:ClearAllPoints()
            ghost:SetPoint("TOPLEFT", self.root, "TOPLEFT", x, y)
            ghost:Show()
        end
        state.lastBatchGhostKey = rootKey
        return
    end
    local row = state and (state.targetRow or state.row)
    local ghost = state and state.ghost
    if not (row and ghost) then
        return
    end
    if ghost:GetParent() ~= row.trackContent then
        ghost:SetParent(row.trackContent)
        ghost:SetFrameLevel((row.trackContent:GetFrameLevel() or 0) + 20)
        state.lastGhostX = nil
    end
    local x = math.floor((tonumber(visualTime) or 0) * (state.pxPerSecond or self.pxPerSecond or DEFAULT_PX_PER_SECOND) + 0.5)
    if state.lastGhostX ~= x then
        ghost:ClearAllPoints()
        ghost:SetPoint("LEFT", row.trackContent, "LEFT", x, 0)
        state.lastGhostX = x
    end
end

function Prototype:CleanupChipDrag()
    if self.ghostChip then
        self.ghostChip:Hide()
    end
    self:HideBatchGhostChips()
    self:HideSnapGuide()
    self:SetAllChipAlpha(1)
    if self.dragState and self.dragState.chip then
        self.dragState.chip:SetScript("OnUpdate", nil)
    end
    self:SetDragTargetRowKey(nil)
    self.dragState = nil
end

function Prototype:GetDragTimeFromCursor(state, cursorX)
    local deltaX = cursorX - (state.startCursorX or cursorX)
    local pxPerSecond = state.pxPerSecond or math.max(0.0001, tonumber(self.pxPerSecond) or DEFAULT_PX_PER_SECOND)
    return math.max(0, (tonumber(state.startTime) or 0) + deltaX / pxPerSecond)
end

function Prototype:UpdateDragContentWidth(targetTime)
    local neededSeconds = math.max(30, math.ceil(((tonumber(targetTime) or 0) + 30) / 30) * 30)
    if neededSeconds <= (tonumber(self.totalSeconds) or 30) then
        return
    end
    self.totalSeconds = neededSeconds
    self:RefreshContentWidth()
    self:RenderRulerIfNeeded()
    self:ApplyHorizontalOffset()
    if self.hScrollBar and self.hScrollBar.Refresh then
        self.hScrollBar:Refresh()
    end
end

function Prototype:SetDragTargetRowKey(rowKey)
    local key = rowKey and tostring(rowKey) or nil
    if key == self.dragTargetRowKey then
        return
    end
    self.dragTargetRowKey = key
    for _, row in ipairs(self.rowFrames or {}) do
        if row.dragTargetTex then
            row.dragTargetTex:SetShown(key ~= nil and row.rowKey == key)
        end
    end
end

function Prototype:FindDragTargetRowAtCursor()
    for _, row in ipairs(self.rowFrames or {}) do
        if row:IsShown() and row.entry and row.entry.readOnly ~= true and IsCursorInsideFrame(row) then
            return row
        end
    end
    return nil
end

function Prototype:BuildTargetAudienceForEntry(rowKey, entry)
    if entry and entry.readOnly == true then
        return nil
    end
    local meta = entry and entry.meta or nil
    local who = Trim(meta and meta.displayText or "")
    if who == "" then
        return nil
    end
    local kind = tostring(meta and meta.kind or "")
    local audience = {
        rowKey = rowKey,
        who = who,
        kind = kind,
    }
    local sampleItem = entry and entry.items and entry.items[1] or nil
    local sourceCondition = Trim(sampleItem and sampleItem.sourceCondition or "")
    local sourcePlayers = {}
    for name in tostring(sampleItem and sampleItem.sourcePlayersText or ""):gmatch("[^\n]+") do
        local normalized = Trim(name)
        if normalized ~= "" then
            sourcePlayers[#sourcePlayers + 1] = normalized
        end
    end
    if sourceCondition ~= "" or #sourcePlayers > 0 then
        audience.condition = sourceCondition ~= "" and sourceCondition or nil
        audience.players = #sourcePlayers > 0 and sourcePlayers or nil
        audience.whoType = sourceCondition ~= "" and "condition" or "player"
    elseif kind == "player" then
        audience.players = { who }
        audience.whoType = "player"
    else
        audience.condition = who
        audience.whoType = "condition"
    end
    return audience
end

function Prototype:BuildTargetAudience(row)
    return self:BuildTargetAudienceForEntry(row and row.rowKey, row and row.entry)
end

function Prototype:FindRowOrderIndex(rowKey)
    local key = tostring(rowKey or "")
    if key == "" then
        return nil
    end
    for index, currentKey in ipairs(self.orderedKeys or {}) do
        if tostring(currentKey or "") == key then
            return index
        end
    end
    return nil
end

function Prototype:BuildBatchTargetAudiences(state)
    if not (state and state.tokens and #state.tokens > 1 and state.targetAudience and state.targetRow and state.item) then
        return nil
    end
    local sourceIndex = self:FindRowOrderIndex(state.item.rowKey)
    local targetIndex = self:FindRowOrderIndex(state.targetRow.rowKey)
    if not (sourceIndex and targetIndex) then
        return nil
    end
    local rowDelta = targetIndex - sourceIndex
    if rowDelta == 0 then
        return nil
    end
    local audiences = {}
    for _, token in ipairs(state.tokens) do
        local item = token.item or token
        local sourceRowKey = tostring(item and item.rowKey or token.rowKey or "")
        local itemIndex = self:FindRowOrderIndex(sourceRowKey)
        local targetKey = itemIndex and self.orderedKeys[itemIndex + rowDelta] or nil
        local targetEntry = targetKey and self.perRow and self.perRow[targetKey] or nil
        local audience = targetEntry and self:BuildTargetAudienceForEntry(targetKey, targetEntry) or nil
        if audience then
            audiences[sourceRowKey] = audience
        end
    end
    return next(audiences) and audiences or nil
end

function Prototype:UpdateBatchGhostTargetRows(state)
    state.batchTargetTopByRowKey = nil
    if not (state and state.tokens and #state.tokens > 1 and state.targetAudience and state.targetRow and state.item and self.root) then
        return
    end
    local sourceIndex = self:FindRowOrderIndex(state.item.rowKey)
    local targetIndex = self:FindRowOrderIndex(state.targetRow.rowKey)
    if not (sourceIndex and targetIndex) then
        return
    end
    local rowDelta = targetIndex - sourceIndex
    if rowDelta == 0 then
        return
    end
    local rootTop = self.root:GetTop() or 0
    local topByRowKey = {}
    for _, token in ipairs(state.tokens) do
        local item = token.item or token
        local sourceRowKey = tostring(item and item.rowKey or token.rowKey or "")
        local itemIndex = self:FindRowOrderIndex(sourceRowKey)
        local targetKey = itemIndex and self.orderedKeys[itemIndex + rowDelta] or nil
        for _, row in ipairs(self.rowFrames or {}) do
            if targetKey and row:IsShown() and tostring(row.rowKey or "") == tostring(targetKey) then
                local targetTop = row.GetTop and row:GetTop() or nil
                if targetTop then
                    topByRowKey[sourceRowKey] = targetTop - rootTop
                end
                break
            end
        end
    end
    state.batchTargetTopByRowKey = next(topByRowKey) and topByRowKey or nil
end

function Prototype:UpdateDragTargetRow(state)
    local row = self:FindDragTargetRowAtCursor() or state.row
    if row == state.targetRow then
        return
    end
    state.targetRow = row
    state.targetAudience = nil
    if row and state.item and tostring(row.rowKey or "") ~= tostring(state.item.rowKey or "") then
        state.targetAudience = self:BuildTargetAudience(row)
    end
    self:SetDragTargetRowKey(row and row.rowKey or nil)
    self:UpdateBatchGhostTargetRows(state)
    state.lastGhostX = nil
    state.lastBatchGhostKey = nil
    if T.debug then
        local audience = state.targetAudience
        T.debug(string.format(
            "[STT_HTG_DRAG_TARGET_ROW] sourceRowKey=%s targetRowKey=%s targetWho=%s targetKind=%s",
            tostring(state.item and state.item.rowKey or ""),
            tostring(row and row.rowKey or ""),
            tostring(audience and audience.who or row and row.entry and row.entry.meta and row.entry.meta.displayText or ""),
            tostring(audience and audience.kind or row and row.entry and row.entry.meta and row.entry.meta.kind or "")
        ))
    end
end

function Prototype:UpdateChipDrag()
    local state = self.dragState
    if not (state and state.chip and state.item) then
        return
    end
    if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
        self:FinishChipDrag(true)
        return
    end

    local cursorX = GetCursorXInFrame(UIParent)
    local cursorY = GetCursorYInFrame(UIParent)
    local moved = math.max(
        math.abs(cursorX - (state.startCursorX or cursorX)),
        math.abs(cursorY - (state.startCursorY or cursorY))
    )
    if state.mode == "maybe_drag" and moved < DRAG_PIXEL_THRESHOLD then
        return
    end

    if state.mode ~= "dragging" then
        state.mode = "dragging"
        if T.TimelineSelectionBox and (not T.TimelineSelectionBox.IsChipSelected or not T.TimelineSelectionBox.IsChipSelected(state.chip)) then
            T.TimelineSelectionBox.SelectOnly(self, state.row, state.chip, self:BuildSelectionContext(state.row, state.item, state.chip), "chip_drag_start")
        end
        self:HideDrawer()
        self:SetAllChipAlpha(0.5)
        state.chip:SetAlpha(0.2)
        self:EnsureSnapGuide()
        self:EnsureDragTimeBadge()
        self:PrepareGhostChip(state)
        if state.tokens and #state.tokens > 1 then
            self:SetShortcutHintText("拖动已框选技能点批量改时间 · 按住 Shift 可自由移动", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
        else
            self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_CHIP_DRAG"] or "拖动技能点改时间 · 按住 Shift 可自由移动", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
        end
        if T.debug then
            local activeTab = T.SemanticTimelineGUI and T.SemanticTimelineGUI.GetActiveEditorTab and T.SemanticTimelineGUI.GetActiveEditorTab() or "unknown"
            T.debug(string.format(
                "[STT_HTG_DRAG_START] line=%s time=%.2f activeTab=%s sourceTab=%s sourcePlanID=%s rowID=%s sourceRowKey=%s",
                tostring(state.item.lineNum),
                tonumber(state.item.time) or 0,
                tostring(activeTab),
                tostring(state.item.editorTab or ""),
                tostring(state.item.sourcePlanID or ""),
                tostring(state.item.rowID or ""),
                tostring(state.item.rowKey or "")
            ))
        end
    end

    self:UpdateDragTargetRow(state)
    local rawTime = self:GetDragTimeFromCursor(state, cursorX)
    local targetTime, targetSource, targetPrecision = state.dragTargetFunc(rawTime, IsShiftKeyDown and IsShiftKeyDown(), state.timeGrid)
    state.rawTime = rawTime
    state.snapSource = targetSource
    state.timePrecision = targetPrecision
    state.currentTime = targetTime
    self:UpdateDragContentWidth(math.max(rawTime, targetTime))
    self:UpdateGhostChip(state, rawTime)
    self:UpdateDragGuide(targetTime, targetSource, targetPrecision)
end

function Prototype:StartChipDrag(chip, button)
    if button ~= "LeftButton" or not (chip and chip.item) then
        return
    end
    if chip.item.readOnly == true then
        return
    end
    local batchTokens
    if T.TimelineSelectionBox and T.TimelineSelectionBox.IsChipSelected and T.TimelineSelectionBox.IsChipSelected(chip) and T.TimelineSelectionBox.Count and T.TimelineSelectionBox.Count() > 1 then
        batchTokens = T.TimelineSelectionBox.GetTargets()
    end
    if not batchTokens and #(chip.item.collisions or {}) > 0 then
        self.dragState = {
            mode = "click_collision",
            chip = chip,
            item = chip.item,
            tokens = batchTokens,
        }
        return
    end
    self.dragState = {
        mode = "maybe_drag",
        chip = chip,
        row = chip.row,
        item = chip.item,
        startCursorX = GetCursorXInFrame(UIParent),
        startCursorY = GetCursorYInFrame(UIParent),
        startTime = tonumber(chip.item.time) or 0,
        pxPerSecond = math.max(0.0001, tonumber(self.pxPerSecond) or DEFAULT_PX_PER_SECOND),
        timeGrid = self:GetTimeGrid(),
        iconSize = GetPrefs().iconSize or DEFAULT_ICON_SIZE,
        dragTargetFunc = T.HorizontalTimelineData.GetDragTargetTime,
        tokens = batchTokens,
    }
    chip:SetScript("OnUpdate", function()
        self:UpdateChipDrag()
    end)
end

function Prototype:FinishChipDrag(commit)
    local state = self.dragState
    if not state then
        return
    end
    if state.chip then
        state.chip:SetScript("OnUpdate", nil)
    end

    if state.mode == "click_collision" then
        if self:IsSelectionToggleDown() then
            self:HandleCollisionChipToggle(state.chip)
        else
            self:ShowDrawerForChip(state.chip)
        end
        self.dragState = nil
        return
    end

    if state.mode ~= "dragging" then
        local chip = state.chip
        self:CleanupChipDrag()
        self:HandleChipClick(chip)
        return
    end

    local item = state.item
    local targetTime = state.currentTime
    local snapSource = state.snapSource or "raw"
    local rewriteOpts = {
        precision = tonumber(state.timePrecision) or 0,
    }
    if state.tokens and #state.tokens > 1 then
        rewriteOpts.targetAudienceByRowKey = self:BuildBatchTargetAudiences(state)
    elseif state.targetAudience then
        rewriteOpts.targetAudience = state.targetAudience
    end
    local sourceRowKey = tostring(item and item.rowKey or "")
    local targetRowKey = tostring((state.targetAudience and state.targetAudience.rowKey) or (state.targetRow and state.targetRow.rowKey) or sourceRowKey)
    local targetWho = tostring((state.targetAudience and state.targetAudience.who) or "")
    self:CleanupChipDrag()
    if commit and item and targetTime then
        local ok, reason = false, "rewrite_missing"
        if state.tokens and #state.tokens > 1 and T.TimelineEdit and T.TimelineEdit.MoveTokens then
            ok, reason = T.TimelineEdit.MoveTokens(state.tokens, item, targetTime, rewriteOpts)
        elseif T.SemanticTimelineGUI and T.SemanticTimelineGUI.RewriteTimelineItemTime then
            ok, reason = T.SemanticTimelineGUI.RewriteTimelineItemTime(item, targetTime, rewriteOpts)
        end
        if ok then
            self:SetEditFeedback(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_CHIP_DONE"] or "已改写时间 · Ctrl/Command+Z 可撤销", "timeline_drag")
            if T.debug then
                T.debug(string.format(
                    "[STT_HTG_DRAG_END] line=%s newTime=%.2f snap=%s sourceRowKey=%s targetRowKey=%s targetWho=%s",
                    tostring(item.lineNum),
                    tonumber(targetTime) or 0,
                    tostring(snapSource),
                    sourceRowKey,
                    targetRowKey,
                    targetWho
                ))
            end
        elseif T.debug then
            T.debug(string.format("[STT_HTG_DRAG_REWRITE_FAIL] line=%s reason=%s", tostring(item and item.lineNum), tostring(reason)))
        end
    end
end

function Prototype:SetSelectedRowKey(rowKey, cause)
    local key = tostring(rowKey or "")
    if key == "" or key == self.selectedRowKey then
        return
    end
    self.selectedRowKey = key
    self:RefreshVisibleRows()
    if cause and T.debug then
        T.debug(string.format("[STT_HTG_ROW_SELECT] row=%s cause=%s", key, tostring(cause)))
    end
end

function Prototype:IsSelectionToggleDown()
    return T.TimelineSelectionBox and T.TimelineSelectionBox.IsToggleModifierDown and T.TimelineSelectionBox.IsToggleModifierDown()
end

function Prototype:BuildSelectionContext(row, item, chip)
    if not (row and item) then
        return nil
    end
    local ctx = self:BuildContextForRowTime(row.rowKey, tonumber(item.time) or 0)
    if type(ctx) ~= "table" then
        return nil
    end
    ctx.item = item
    ctx.rowID = item.rowID or ctx.rowID
    ctx.spellID = item.spellID or ctx.spellID
    ctx.dur = item.duration or ctx.dur
    ctx.time = tonumber(item.time) or tonumber(ctx.time) or 0
    ctx.rawTime = ctx.time
    ctx.sourceLineNum = item.lineNum or ctx.sourceLineNum
    ctx.editorTab = item.editorTab or ctx.editorTab
    ctx.hitToken = true
    ctx.chip = chip
    ctx.row = row
    return ctx
end

function Prototype:BuildSelectionContextsForChip(chip)
    local row = chip and chip.row
    local item = chip and chip.item
    if not (row and item) then
        return {}
    end
    local contexts = {}
    local primary = self:BuildSelectionContext(row, item, chip)
    if primary then
        contexts[#contexts + 1] = primary
    end
    for _, collision in ipairs(item.collisions or {}) do
        local ctx = self:BuildSelectionContext(row, collision, nil)
        if ctx then
            contexts[#contexts + 1] = ctx
        end
    end
    return contexts
end

function Prototype:FocusSelectionContext(ctx)
    local item = ctx and (ctx.item or ctx)
    if item then
        self:JumpToItem(item)
    end
end

function Prototype:HandleChipClick(chip)
    if not (chip and chip.item and T.TimelineSelectionBox) then
        self:JumpToItem(chip and chip.item)
        return
    end
    local row = chip.row
    local ctx = self:BuildSelectionContext(row, chip.item, chip)
    if not ctx then
        self:JumpToItem(chip.item)
        return
    end

    if IsShiftKeyDown and IsShiftKeyDown() then
        ctx = T.TimelineSelectionBox.SelectRange(self, row, chip, ctx, "chip_shift_click") or ctx
    elseif self:IsSelectionToggleDown() then
        ctx = T.TimelineSelectionBox.Toggle(self, row, chip, ctx, "chip_toggle_click") or ctx
    else
        ctx = T.TimelineSelectionBox.SelectOnly(self, row, chip, ctx, "chip_click") or ctx
    end
    T.TimelineSelectionBox.FocusPrimary(ctx)
    self:SetSelectedRowKey(row and row.rowKey, "chip_click")
    self:FocusSelectionContext(ctx)
end

function Prototype:HandleCollisionChipToggle(chip)
    if not (chip and T.TimelineSelectionBox) then
        return false
    end
    local contexts = self:BuildSelectionContextsForChip(chip)
    if #contexts == 0 then
        return false
    end
    T.TimelineSelectionBox.SelectContexts(self, contexts, "toggle", "collision_toggle")
    T.TimelineSelectionBox.FocusPrimary(contexts[1])
    self:SetSelectedRowKey(chip.row and chip.row.rowKey, "collision_toggle")
    self:FocusSelectionContext(contexts[1])
    self:SetShortcutHintText(string.format("已切换 %d 个重叠技能点选区", #contexts), T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
    return true
end

function Prototype:SelectRowEvents(row, mode, cause)
    if not (row and T.TimelineSelectionBox and T.TimelineSelectionBox.SelectContexts) then
        return 0
    end
    local contexts = {}
    for _, chip in ipairs(row.chips or {}) do
        if chip:IsShown() and chip.item then
            for _, ctx in ipairs(self:BuildSelectionContextsForChip(chip)) do
                contexts[#contexts + 1] = ctx
            end
        end
    end
    local selectionMode = mode
    if mode == "toggle" then
        local allSelected = #contexts > 0
        for _, ctx in ipairs(contexts) do
            if not T.TimelineSelectionBox.Contains(ctx, ctx.chip) then
                allSelected = false
                break
            end
        end
        selectionMode = allSelected and "toggle" or "append"
    end
    local count = T.TimelineSelectionBox.SelectContexts(self, contexts, selectionMode, cause)
    self:SetSelectedRowKey(row.rowKey, cause or "row_select")
    if count > 0 then
        self:SetShortcutHintText(string.format("已选中本行 %d 个技能点", count), T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
    end
    return count
end

function Prototype:HandleRowLabelClick(row)
    if not row then
        return
    end
    if self:IsSelectionToggleDown() then
        self:SelectRowEvents(row, "toggle", "row_toggle")
        return
    end

    local now = GetTime and GetTime() or 0
    local isDouble = row._lastLabelClickAt and (now - row._lastLabelClickAt) <= 0.32
    row._lastLabelClickAt = now
    if isDouble then
        if self:OpenPersonnelRowEditor(row) then
            return
        end
        self:SelectRowEvents(row, "replace", "row_double_click")
        return
    end

    if T.TimelineSelectionBox then
        T.TimelineSelectionBox.Clear("row_click")
    end
    self:SelectRow(row, "row_click")
end

function Prototype:BuildContextForRow(row, item)
    if not (T.TimelineCoords and T.TimelineCoords.ResolveAt) then
        return nil
    end
    local ctx = T.TimelineCoords.ResolveAt(self, row, item)
    if not ctx then
        return nil
    end
    if ctx.meta and ctx.meta.kind == "player" and self.FindPlayerCache then
        local cache = self:FindPlayerCache(ctx.meta.playerInfo, ctx.meta.displayText)
        if cache and cache.classFile then
            ctx.meta.classFile = ctx.meta.classFile or cache.classFile
            ctx.class = cache.classFile
        end
    end
    return ctx
end

function Prototype:GetRowPersonnelContext(row)
    local meta = row and row.entry and row.entry.meta or nil
    if not (meta and meta.kind == "player") then
        return nil
    end
    local rowName = meta.personnelSlotName or meta.displayText
    if rowName == nil or tostring(rowName) == "" then
        return nil
    end
    return {
        rowName = tostring(rowName),
        displayName = tostring(meta.displayText or ""),
        specID = tonumber(meta.personnelSpecID or meta.specID),
        declared = meta.personnelSlotName ~= nil,
    }
end

function Prototype:OpenPersonnelRowEditor(row)
    local personnel = self:GetRowPersonnelContext(row)
    if not personnel then
        return false
    end
    if T.TimelinePersonnelRowEditor and T.TimelinePersonnelRowEditor.Open then
        T.TimelinePersonnelRowEditor.Open({
            mode = "edit",
            rowName = personnel.rowName,
            specID = personnel.specID,
            allowCreateFromTarget = personnel.declared ~= true,
        })
        return true
    end
    return false
end

function Prototype:IsCursorInFirstColumn()
    if not (self.root and self.root.GetLeft and GetCursorPosition) then
        return false
    end
    local cursorX = GetCursorPosition()
    local scale = self.root:GetEffectiveScale() or 1
    local left = self.root:GetLeft() or 0
    local localX = (cursorX / scale) - left
    return localX >= 0 and localX <= (tonumber(self.firstColWidth) or 0)
end

function Prototype:HandleRowHeaderRightClick(row)
    local personnel = self:GetRowPersonnelContext(row)
    if self.opts and self.opts.onContextMenu then
        self.opts.onContextMenu(self, {
            kind = "header",
            headerArea = "target",
            title = "轨道管理",
            rowName = personnel and personnel.rowName or nil,
            displayName = personnel and personnel.displayName or nil,
            specID = personnel and personnel.specID or nil,
            allowCreateFromTarget = personnel and personnel.declared ~= true or nil,
            canEditPersonnelRow = personnel ~= nil,
        })
    end
end

function Prototype:HandleHeaderRightClick(area)
    if self.opts and self.opts.onContextMenu then
        self.opts.onContextMenu(self, {
            kind = "header",
            headerArea = area or "target",
            title = "轨道管理",
        })
    end
end

function Prototype:GetCurrentRunnerTimeForEdit()
    local runner = T.TimelineRunner
    local state = runner and runner.GetState and runner:GetState() or nil
    return math.max(0, tonumber(state and state.currentTime) or tonumber(self.runnerTime) or 0)
end

function Prototype:BuildContextForRowTime(rowKey, timeValue)
    if not (T.TimelineCoords and T.TimelineCoords.ResolveForRowTime) then
        return nil
    end
    local ctx = T.TimelineCoords.ResolveForRowTime(self, rowKey, timeValue)
    if not ctx then
        return nil
    end
    if ctx.meta and ctx.meta.kind == "player" and self.FindPlayerCache then
        local cache = self:FindPlayerCache(ctx.meta.playerInfo, ctx.meta.displayText)
        if cache and cache.classFile then
            ctx.meta.classFile = ctx.meta.classFile or cache.classFile
            ctx.class = cache.classFile
        end
    end
    return ctx
end

function Prototype:SelectContext(ctx, cause)
    if type(ctx) ~= "table" then
        return
    end
    self:SetSelectedRowKey(ctx.rowKey, cause or "context_menu")
end

function Prototype:SelectRow(row, cause)
    if not (row and row.rowKey) then
        return
    end
    self:SetSelectedRowKey(row.rowKey, cause or "row_click")
end

function Prototype:BuildAllSelectionContexts()
    local contexts = {}
    for _, rowKey in ipairs(self.orderedKeys or {}) do
        local entry = self.perRow and self.perRow[rowKey] or nil
        for _, item in ipairs(entry and entry.readOnly ~= true and entry.items or {}) do
            local ctx = self:BuildContextForRowTime(rowKey, tonumber(item.time) or 0)
            if ctx then
                ctx.item = item
                ctx.rowID = item.rowID or ctx.rowID
                ctx.spellID = item.spellID or ctx.spellID
                ctx.dur = item.duration or ctx.dur
                ctx.time = tonumber(item.time) or tonumber(ctx.time) or 0
                ctx.rawTime = ctx.time
                ctx.sourceLineNum = item.lineNum or ctx.sourceLineNum
                ctx.editorTab = item.editorTab or ctx.editorTab
                ctx.hitToken = true
                contexts[#contexts + 1] = ctx
                for _, collision in ipairs(item.collisions or {}) do
                    local collisionCtx = self:BuildContextForRowTime(rowKey, tonumber(collision.time) or 0)
                    if collisionCtx then
                        collisionCtx.item = collision
                        collisionCtx.rowID = collision.rowID or collisionCtx.rowID
                        collisionCtx.spellID = collision.spellID or collisionCtx.spellID
                        collisionCtx.dur = collision.duration or collisionCtx.dur
                        collisionCtx.time = tonumber(collision.time) or tonumber(collisionCtx.time) or 0
                        collisionCtx.rawTime = collisionCtx.time
                        collisionCtx.sourceLineNum = collision.lineNum or collisionCtx.sourceLineNum
                        collisionCtx.editorTab = collision.editorTab or collisionCtx.editorTab
                        collisionCtx.hitToken = true
                        contexts[#contexts + 1] = collisionCtx
                    end
                end
            end
        end
    end
    return contexts
end

function Prototype:HandleSelectAllShortcut()
    if not (T.TimelineSelectionBox and T.TimelineSelectionBox.SelectContexts) then
        return false
    end
    local contexts = {}
    if self.selectedRowKey and self.perRow and self.perRow[self.selectedRowKey] then
        local entry = self.perRow[self.selectedRowKey]
        for _, item in ipairs(entry.readOnly ~= true and entry.items or {}) do
            local ctx = self:BuildContextForRowTime(self.selectedRowKey, tonumber(item.time) or 0)
            if ctx then
                ctx.item = item
                ctx.rowID = item.rowID or ctx.rowID
                ctx.spellID = item.spellID or ctx.spellID
                ctx.sourceLineNum = item.lineNum or ctx.sourceLineNum
                ctx.editorTab = item.editorTab or ctx.editorTab
                ctx.hitToken = true
                contexts[#contexts + 1] = ctx
                for _, collision in ipairs(item.collisions or {}) do
                    local collisionCtx = self:BuildContextForRowTime(self.selectedRowKey, tonumber(collision.time) or 0)
                    if collisionCtx then
                        collisionCtx.item = collision
                        collisionCtx.rowID = collision.rowID or collisionCtx.rowID
                        collisionCtx.spellID = collision.spellID or collisionCtx.spellID
                        collisionCtx.sourceLineNum = collision.lineNum or collisionCtx.sourceLineNum
                        collisionCtx.editorTab = collision.editorTab or collisionCtx.editorTab
                        collisionCtx.hitToken = true
                        contexts[#contexts + 1] = collisionCtx
                    end
                end
            end
        end
    end
    if #contexts == 0 or (T.TimelineSelectionBox.Count and T.TimelineSelectionBox.Count() >= #contexts) then
        contexts = self:BuildAllSelectionContexts()
    end
    if #contexts == 0 then
        return false
    end
    local count = T.TimelineSelectionBox.SelectContexts(self, contexts, "replace", "select_all_shortcut")
    self:SetShortcutHintText(string.format("已选中 %d 个技能点", count), T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
    return true
end

function Prototype:HandleClearSelectionShortcut()
    if T.TimelineSelectionBox and T.TimelineSelectionBox.Count and T.TimelineSelectionBox.Count() > 0 then
        T.TimelineSelectionBox.Clear("escape")
        self:SetShortcutHintText("已清空技能点选区", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
        return true
    end
    return false
end

function Prototype:HandleDeleteSelectionShortcut()
    if T.TimelineEdit and T.TimelineSelectionBox and T.TimelineSelectionBox.Count and T.TimelineSelectionBox.Count() > 0 then
        T.TimelineEdit.DeleteTokens(T.TimelineSelectionBox.GetTargets(), "timeline_key_delete")
        return true
    end
    return false
end

function Prototype:FlattenSelectionItems()
    local out = {}
    for _, rowKey in ipairs(self.orderedKeys or {}) do
        local entry = self.perRow and self.perRow[rowKey] or nil
        for _, item in ipairs(entry and entry.readOnly ~= true and entry.items or {}) do
            out[#out + 1] = { rowKey = rowKey, item = item }
            for _, collision in ipairs(item.collisions or {}) do
                out[#out + 1] = { rowKey = rowKey, item = collision }
            end
        end
    end
    return out
end

function Prototype:SelectFlattenedIndex(index)
    local items = self:FlattenSelectionItems()
    if #items == 0 then
        return false
    end
    local target = items[math.max(1, math.min(#items, index))]
    local ctx = self:BuildContextForRowTime(target.rowKey, tonumber(target.item.time) or 0)
    if not ctx then
        return false
    end
    ctx.item = target.item
    ctx.rowID = target.item.rowID or ctx.rowID
    ctx.spellID = target.item.spellID or ctx.spellID
    ctx.sourceLineNum = target.item.lineNum or ctx.sourceLineNum
    ctx.editorTab = target.item.editorTab or ctx.editorTab
    ctx.hitToken = true
    T.TimelineSelectionBox.SelectContexts(self, { ctx }, "replace", "keyboard_step")
    T.TimelineSelectionBox.FocusPrimary(ctx)
    self:SetSelectedRowKey(target.rowKey, "keyboard_step")
    self:FocusSelectionContext(ctx)
    return true
end

function Prototype:FindPrimaryFlatIndex()
    local primary = T.TimelineSelectionBox and T.TimelineSelectionBox.GetPrimary and T.TimelineSelectionBox.GetPrimary() or nil
    local primaryItem = primary and (primary.item or primary) or nil
    local items = self:FlattenSelectionItems()
    for index, entry in ipairs(items) do
        if entry.item == primaryItem then
            return index
        end
    end
    return 0
end

function Prototype:HandleSelectionStep(delta)
    if not (T.TimelineSelectionBox and T.TimelineSelectionBox.SelectContexts) then
        return false
    end
    return self:SelectFlattenedIndex(self:FindPrimaryFlatIndex() + (tonumber(delta) or 1))
end

function Prototype:HandleSelectionStepRow(delta)
    if not (T.TimelineSelectionBox and T.TimelineSelectionBox.SelectContexts) then
        return false
    end
    local rowIndex = self:FindRowOrderIndex(self.selectedRowKey)
    if not rowIndex then
        return self:HandleSelectionStep(delta)
    end
    local targetKey = self.orderedKeys[rowIndex + (tonumber(delta) or 1)]
    local entry = targetKey and self.perRow and self.perRow[targetKey] or nil
    local item = entry and entry.items and entry.items[1] or nil
    if not item then
        return false
    end
    local flat = self:FlattenSelectionItems()
    for index, candidate in ipairs(flat) do
        if candidate.item == item then
            return self:SelectFlattenedIndex(index)
        end
    end
    return false
end


function Prototype:FindContextAtCursor(selectCause)
    for _, row in ipairs(self.rowFrames or {}) do
        if row:IsShown() and row.trackClip and row.trackClip:IsShown() and row:IsMouseOver() then
            local ctx = self:BuildContextForRow(row)
            if ctx then
                if selectCause then
                    self:SelectContext(ctx, selectCause)
                end
                return ctx, row
            end
        end
    end
    return nil, nil
end

function Prototype:ResolveContextAtCursor()
    local ctx = self:FindContextAtCursor("drawer_drop")
    return ctx
end

function Prototype:ResolveContextAtPlayhead(baseCtx)
    local rowKey = tostring(self.selectedRowKey or (baseCtx and baseCtx.rowKey) or "")
    if rowKey == "" then
        return nil
    end
    local ctx = self:BuildContextForRowTime(rowKey, self:GetCurrentRunnerTimeForEdit())
    if ctx then
        self:SelectContext(ctx, "drawer_click")
        return ctx
    end
    return nil
end

function Prototype:HandleTrackRightClick(row, item, chip)
    local ctx = self:BuildContextForRow(row, item)
    if not ctx then
        return
    end
    local targetTime = tonumber(ctx.time)
    if targetTime and T.TimelineRunner and T.TimelineRunner.Seek then
        T.TimelineRunner:Seek(targetTime, { silent = true, preserveState = false })
    end
    if item and T.TimelineSelectionBox then
        local selectCtx = self:BuildSelectionContext(row, item, chip) or ctx
        if T.TimelineSelectionBox.IsChipSelected and T.TimelineSelectionBox.IsChipSelected(chip) then
            T.TimelineSelectionBox.FocusPrimary(selectCtx)
        else
            T.TimelineSelectionBox.SelectOnly(self, row, chip, selectCtx, "context_menu_chip")
            T.TimelineSelectionBox.FocusPrimary(selectCtx)
        end
    end
    self:SelectContext(ctx, item and "context_menu_chip" or "context_menu")
    if self.opts and self.opts.onContextMenu then
        self.opts.onContextMenu(self, ctx)
    end
end

function Prototype:ClearExternalSkillDragPreview(reason)
    if not self.externalSkillDragState then
        return
    end
    if self.ghostChip then
        self.ghostChip:Hide()
    end
    self:HideBatchGhostChips()
    self:HideSnapGuide()
    self.externalSkillDragState = nil
    if reason and T.debug then
        T.debug(string.format("[STT_SKILL_DRAWER_PREVIEW_CLEAR] reason=%s", tostring(reason)))
    end
end

function Prototype:PreviewExternalSkillDrag(payload)
    if type(payload) ~= "table" then
        self:ClearExternalSkillDragPreview("missing_payload")
        return nil
    end

    local ctx, row = self:FindContextAtCursor(nil)
    if not (ctx and row) then
        self:ClearExternalSkillDragPreview("outside")
        return nil
    end

    local spellID = tonumber(payload.spellID)
    local item = {
        spellID = spellID,
        spellIcon = payload.icon or payload.spellIcon,
        fullText = payload.name or payload.label or (spellID and tostring(spellID)) or "",
        duration = payload.dur,
    }
    local state = self.externalSkillDragState
    local iconSize = GetPrefs().iconSize or DEFAULT_ICON_SIZE
    if not state or state.row ~= row or state.spellID ~= spellID or state.spellIcon ~= item.spellIcon then
        state = {
            mode = "external_skill_drag",
            row = row,
            item = item,
            spellID = spellID,
            spellIcon = item.spellIcon,
            iconSize = iconSize,
        }
        self.externalSkillDragState = state
        self:PrepareGhostChip(state)
    else
        state.item = item
        state.iconSize = iconSize
    end

    local rawTime = tonumber(ctx.rawTime) or tonumber(ctx.time) or 0
    local targetTime = rawTime
    local targetSource = "raw"
    local targetPrecision = 0
    if T.HorizontalTimelineData and T.HorizontalTimelineData.GetDragTargetTime then
        targetTime, targetSource, targetPrecision = T.HorizontalTimelineData.GetDragTargetTime(rawTime, IsShiftKeyDown and IsShiftKeyDown(), self:GetTimeGrid())
    end
    state.currentTime = targetTime
    state.rawTime = rawTime
    self:UpdateDragContentWidth(math.max(rawTime, targetTime))
    self:UpdateGhostChip(state, rawTime)
    self:UpdateDragGuide(targetTime, targetSource, targetPrecision)
    return ctx
end

function Prototype:CreateRowFrame(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(DEFAULT_ROW_HEIGHT)
    if row.SetClipsChildren then
        row:SetClipsChildren(true)
    end
    row.chips = {}

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.selectTex = row:CreateTexture(nil, "BORDER")
    row.selectTex:SetAllPoints()
    row.selectTex:SetColorTexture(1, 0.82, 0.18, 0.16)
    row.selectTex:Hide()

    row.dragTargetTex = row:CreateTexture(nil, "BORDER")
    row.dragTargetTex:SetAllPoints()
    row.dragTargetTex:SetColorTexture(0.28, 0.58, 1.0, 0.20)
    row.dragTargetTex:Hide()

    row.labelFrame = CreateFrame("Frame", nil, row)
    row.labelFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.labelFrame:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.labelFrame:SetWidth(self.firstColWidth)
    row.labelFrame:EnableMouse(true)
    BlockMousePropagation(row.labelFrame)
    self:BindShortcutHintHover(row.labelFrame)
    row.labelFrame:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            self:HandleRowLabelClick(row)
        elseif button == "RightButton" then
            self:HandleRowHeaderRightClick(row)
        end
    end)

    row.labelIcon = row.labelFrame:CreateTexture(nil, "ARTWORK")
    row.labelIcon:SetSize(20, 20)
    row.labelIcon:SetPoint("LEFT", row.labelFrame, "LEFT", 6, 0)

    row.labelText = row.labelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.labelText:SetJustifyH("LEFT")
    if row.labelText.SetWordWrap then
        row.labelText:SetWordWrap(false)
    end

    row.toggleBtn = CreateFrame("Button", nil, row.labelFrame)
    row.toggleBtn:SetSize(EXPAND_TOGGLE_SIZE, EXPAND_TOGGLE_SIZE)
    row.toggleBtn:SetPoint("RIGHT", row.labelFrame, "RIGHT", -4, 0)
    row.toggleBtn:RegisterForClicks("LeftButtonUp")
    BlockMousePropagation(row.toggleBtn)
    row.toggleBtn:Hide()
    row.toggleBtn.tex = row.toggleBtn:CreateTexture(nil, "ARTWORK")
    row.toggleBtn.tex:SetAllPoints()
    row.toggleBtn.tex:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
    row.toggleBtn:SetScript("OnEnter", function(selfBtn)
        selfBtn._hovered = true
        self:RefreshToggleButtonVisual(selfBtn)
    end)
    row.toggleBtn:SetScript("OnLeave", function(selfBtn)
        selfBtn._hovered = nil
        self:RefreshToggleButtonVisual(selfBtn)
    end)
    row.toggleBtn:SetScript("OnClick", function(selfBtn)
        local ownerKey = selfBtn._ownerKey
        if ownerKey then
            self:OnOwnerToggleClick(ownerKey)
        end
    end)

    row.trackClip = CreateFrame("Frame", nil, row)
    row.trackClip:SetPoint("TOPLEFT", row.labelFrame, "TOPRIGHT", 0, 0)
    row.trackClip:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_SIDE_PADDING, 0)
    if row.trackClip.SetClipsChildren then
        row.trackClip:SetClipsChildren(true)
    end
    row.trackClip:EnableMouse(true)
    row.trackClip:EnableMouseWheel(true)
    BlockMousePropagation(row.trackClip)
    self:BindShortcutHintHover(row.trackClip)
    row.trackClip:SetScript("OnMouseWheel", function(_, delta)
        self:HandleMouseWheel(delta, row.trackClip)
    end)
    row.trackClip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            if T.TimelineSelectionBox then
                T.TimelineSelectionBox.Start(self)
            end
            return
        end
        self:StartMiddleDrag(button)
    end)
    row.trackClip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            self:HandleTrackRightClick(row)
            return
        end
        if button == "LeftButton" then
            if T.TimelineSelectionBox and T.TimelineSelectionBox.IsActive(self) then
                local moved = T.TimelineSelectionBox.Finish("track_mouse_up")
                if moved then
                    return
                end
            end
            if T.TimelineSelectionBox then
                T.TimelineSelectionBox.Clear("track_click")
            end
            self:SelectRow(row, "row_click")
            return
        end
        self:StopMiddleDrag(button)
    end)

    row.trackContent = CreateFrame("Frame", nil, row.trackClip)
    row.trackContent:SetPoint("TOPLEFT", row.trackClip, "TOPLEFT", 0, 0)
    row.trackContent:SetPoint("BOTTOMLEFT", row.trackClip, "BOTTOMLEFT", 0, 0)
    row.trackContent:SetWidth(1)
    row.trackContent.ownerRow = row

    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
    row.line:SetColorTexture(1, 1, 1, 0.06)

    self.rowFrames[#self.rowFrames + 1] = row
    return row
end

function Prototype:AcquireChip(row, index)
    local chip = row.chips[index]
    if chip then
        chip:Show()
        return chip
    end

    chip = CreateFrame("Button", nil, row.trackContent, "BackdropTemplate")
    chip.owner = self
    chip.row = row
    chip:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
    BlockMousePropagation(chip)
    ApplyBackdrop(chip, { alpha = 0.18 })

    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetPoint("TOPLEFT", chip, "TOPLEFT", 2, -2)
    chip.icon:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -2, 2)

    chip.durationBar = chip:CreateTexture(nil, "BACKGROUND", nil, -1)
    chip.durationBar:SetColorTexture(DEFAULT_DURATION_BAR_COLOR[1], DEFAULT_DURATION_BAR_COLOR[2], DEFAULT_DURATION_BAR_COLOR[3], DEFAULT_DURATION_BAR_COLOR[4])
    chip.durationBar:Hide()

    chip.textCue = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chip.textCue:SetPoint("CENTER", chip, "CENTER", 0, 0)
    chip.textCue:SetJustifyH("CENTER")
    chip.textCue:Hide()

    chip.countText = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chip.countText:SetPoint("TOPRIGHT", chip, "TOPRIGHT", 4, 5)
    chip.countText:SetTextColor(1, 0.92, 0.35, 1)
    chip.countText:Hide()

    chip:SetScript("OnEnter", function(selfChip)
        selfChip.owner:HandleChipEnter(selfChip)
    end)
    chip:SetScript("OnLeave", function(selfChip)
        selfChip.owner:HandleChipLeave(selfChip)
    end)
    chip:SetScript("OnMouseDown", function(selfChip, button)
        if button == "MiddleButton" then
            selfChip.owner:StartMiddleDrag(button)
            return
        end
        if button == "RightButton" then
            return
        end
        selfChip.owner:StartChipDrag(selfChip, button)
    end)
    chip:SetScript("OnMouseUp", function(selfChip, button)
        if button == "MiddleButton" then
            selfChip.owner:StopMiddleDrag(button)
            return
        end
        if button == "RightButton" then
            if selfChip.item and selfChip.item.readOnly == true then
                return
            end
            selfChip.owner:HandleTrackRightClick(selfChip.row, selfChip.item, selfChip)
            return
        end
        if button == "LeftButton" then
            if selfChip.item and selfChip.item.readOnly == true then
                return
            end
            local now = GetTime and GetTime() or 0
            local last = tonumber(selfChip._lastLeftClick) or 0
            if now > 0 and last > 0 and now - last < 0.3 then
                selfChip._lastLeftClick = 0
                selfChip.owner:CleanupChipDrag()
                if T.TimelineEventEditor and T.TimelineEventEditor.Open then
                    T.TimelineEventEditor.Open(selfChip.item)
                end
                return
            end
            selfChip._lastLeftClick = now
            selfChip.owner:FinishChipDrag(true)
        end
    end)

    row.chips[index] = chip
    self:AddScrollProfileCount("createdChips")
    return chip
end

function Prototype:HideChip(chip)
    if not chip then
        return
    end
    if chip:IsShown() then
        self:AddScrollProfileCount("hiddenChips")
    end
    chip:Hide()
    chip:ClearAllPoints()
    chip.item = nil
    chip._sttRenderSignature = nil
    chip:SetAlpha(1)
    chip._enterAnimAt = nil
    chip._exitAnimAt = nil
    if chip.selectionTex then
        chip.selectionTex:Hide()
    end
    if chip.durationBar then
        chip.durationBar:Hide()
        if chip.durationBar.SetAlpha then
            chip.durationBar:SetAlpha(1)
        end
    end
    if chip.countText then
        chip.countText:SetAlpha(1)
    end
end

function Prototype:RenderChip(chip, item)
    local prefs = GetPrefs()
    local iconSize = prefs.iconSize
    chip.item = item
    chip.row = chip:GetParent() and chip:GetParent().ownerRow or chip.row
    local signature = BuildChipRenderSignature(item, self.pxPerSecond or DEFAULT_PX_PER_SECOND, iconSize)
    if chip._sttRenderSignature == signature then
        return
    end
    chip._sttRenderSignature = signature
    self:AddScrollProfileCount("renderChips")

    chip:SetSize(iconSize, iconSize)

    chip:ClearAllPoints()
    chip:SetPoint("LEFT", chip:GetParent(), "LEFT", math.floor((item.time or 0) * (self.pxPerSecond or DEFAULT_PX_PER_SECOND) + 0.5), 0)

    local duration = tonumber(item.duration)
    if duration and duration > 0 then
        local pps = self.pxPerSecond or DEFAULT_PX_PER_SECOND
        local barHeight, barColor = GetDurationBarStyle()
        if item.castFailed == true then
            barColor = { 1.0, 0.18, 0.12, 0.85 }
        end
        local barWidth = math.max(2, math.floor(duration * pps + 0.5))
        chip.durationBar:ClearAllPoints()
        chip.durationBar:SetColorTexture(barColor[1], barColor[2], barColor[3], barColor[4])
        chip.durationBar:SetSize(barWidth, barHeight)
        chip.durationBar:SetPoint("LEFT", chip, "RIGHT", 0, 0)
        chip.durationBar:Show()
    else
        chip.durationBar:Hide()
    end

    if item.spellIcon then
        chip.icon:SetTexture(item.spellIcon)
        chip.textCue:Hide()
    else
        chip.icon:SetColorTexture(0.03, 0.03, 0.04, 0.55)
        chip.textCue:SetText(GetFirstUTF8Char(item.fullText))
        chip.textCue:Show()
    end

    if item.castFailed == true and chip.SetBackdropBorderColor then
        chip:SetBackdropBorderColor(1.0, 0.18, 0.12, 1)
    elseif item.readOnly == true and chip.SetBackdropBorderColor then
        chip:SetBackdropBorderColor(0.30, 0.92, 1.0, 1)
    elseif chip.SetBackdropBorderColor then
        chip:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)
    end

    local collisionCount = #(item.collisions or {})
    local parentRow = chip.row
    local displayRow = parentRow and parentRow.displayRow or nil
    if displayRow and displayRow.kind == "spellRow" then
        collisionCount = 0
    end
    if collisionCount > 0 then
        chip.countText:SetText(tostring(collisionCount + 1) .. "+")
        chip.countText:Show()
    else
        chip.countText:Hide()
    end
end

function Prototype:ResolveEntryVisual(entry)
    local meta = entry and entry.meta or {}
    local visual = TextureVisual(meta.iconTexture)
    local color = meta.color or { 1, 1, 1, 1 }
    local actorOverrideVisual = ResolveActorSpellOverrideVisual(meta.encounterID, meta.displayText)

    if IsSelfCondition(meta.displayText) then
        visual = SELF_VISUAL
    elseif actorOverrideVisual then
        visual = actorOverrideVisual
    elseif meta.kind == "boss"
        or (ENCOUNTER_BOSS_NAME_OVERRIDES[tonumber(meta.encounterID) or 0]
            and ENCOUNTER_BOSS_NAME_OVERRIDES[tonumber(meta.encounterID) or 0][tostring(meta.displayText or "")]) then
        visual = self:ResolveBossVisual(meta.encounterID, meta.instanceID, meta.encounterIcon)
    elseif meta.kind == "npc" then
        visual = self:ResolveNpcVisual(meta.encounterID, meta.displayText, meta.instanceID, GetEntryFirstSpellIcon(entry), meta.encounterIcon)
    elseif meta.kind == "castLog" then
        color = ResolveClassColor(meta.classFile) or color
    elseif meta.kind == "player" then
        local cache = self:FindPlayerCache(meta.playerInfo, meta.displayText)
        if cache then
            local classFile = cache.classFile or meta.classFile
            local specIcon = cache.specIcon or meta.specIcon
            local classColor = ResolveClassColor(classFile)
            color = classColor or color
            visual = TextureVisual(specIcon) or ClassVisual(classFile)
        elseif meta.classFile or meta.specIcon then
            local classColor = ResolveClassColor(meta.classFile)
            color = classColor or color
            visual = TextureVisual(meta.specIcon) or ClassVisual(meta.classFile)
        end
    elseif meta.specIcon then
        color = ResolveClassColor(meta.classFile) or color
        visual = TextureVisual(meta.specIcon) or ClassVisual(meta.classFile)
    elseif meta.role == "ALL" then
        visual = ALL_VISUAL
    elseif meta.role and ROLE_VISUALS[meta.role] then
        visual = ROLE_VISUALS[meta.role]
    elseif meta.playerInfo and meta.playerInfo.classFile then
        local classColor = ResolveClassColor(meta.playerInfo.classFile)
        color = classColor or color
        visual = ClassVisual(meta.playerInfo.classFile) or visual
    end

    return visual, color
end

function Prototype:RefreshToggleButtonVisual(button)
    if not (button and button.tex) then
        return
    end
    if button._flashStartAt then
        button.tex:SetVertexColor(1.0, 0.82, 0.24, 1)
        return
    end
    if button._hovered then
        button.tex:SetVertexColor(1.0, 0.86, 0.30, 0.95)
    else
        button.tex:SetVertexColor(0.92, 0.94, 1.0, 0.88)
    end
end

function Prototype:SetToggleButtonExpanded(button, expanded, animate)
    if not (button and button.tex) then
        return
    end
    local texture = expanded and TOGGLE_MINUS_TEXTURE or TOGGLE_PLUS_TEXTURE
    button._ownerExpanded = expanded and true or false
    button.tex:SetTexture(texture)
    button._toggleTexture = texture
    if not animate then
        button._flashStartAt = nil
        button.tex:SetAlpha(1)
        button:SetScript("OnUpdate", nil)
        self:RefreshToggleButtonVisual(button)
        return
    end

    button._flashStartAt = GetTime and GetTime() or 0
    button.tex:SetAlpha(0.45)
    local owner = self
    button:SetScript("OnUpdate", function(selfButton)
        local now = GetTime and GetTime() or 0
        local progress = Clamp((now - (selfButton._flashStartAt or now)) / TOGGLE_FADE_DURATION, 0, 1)
        local eased = 1 - (1 - progress) * (1 - progress)
        selfButton.tex:SetAlpha(0.45 + 0.55 * eased)
        if progress >= 1 then
            selfButton._flashStartAt = nil
            selfButton.tex:SetAlpha(1)
            owner:RefreshToggleButtonVisual(selfButton)
            selfButton:SetScript("OnUpdate", nil)
            return
        end
        selfButton.tex:SetVertexColor(1.0, 0.82, 0.24, 1)
    end)
    self:RefreshToggleButtonVisual(button)
end

function Prototype:PulseToggleButton(button, expanded)
    if not button then
        return
    end
    self:SetToggleButtonExpanded(button, expanded, true)
end

function Prototype:GetOwnerDisclosureProgress(ownerKey)
    local anim = self._disclosureAnim
    if anim and anim.ownerKey == ownerKey then
        local elapsed = (GetTime and GetTime() or 0) - (anim.startAt or 0)
        local raw = Clamp(elapsed / DISCLOSURE_ANIM_DURATION, 0, 1)
        local eased = 1 - (1 - raw) * (1 - raw) * (1 - raw)
        return Clamp((tonumber(anim.from) or 0) + ((tonumber(anim.to) or 0) - (tonumber(anim.from) or 0)) * eased, 0, 1)
    end
    return IsOwnerExpanded(ownerKey) and 1 or 0
end

function Prototype:GetDisplayRowHeight(dataIndex)
    local prefs = GetPrefs()
    local rowHeight = math.max(1, tonumber(prefs.rowHeight) or DEFAULT_ROW_HEIGHT)
    local displayRow = self.displayRows and self.displayRows[dataIndex] or nil
    if displayRow and displayRow.kind == "spellRow" then
        return rowHeight * self:GetOwnerDisclosureProgress(displayRow.ownerKey)
    end
    return rowHeight
end

function Prototype:UpdateDisclosureAnim()
    local anim = self._disclosureAnim
    if not anim then
        return
    end
    local elapsed = (GetTime and GetTime() or 0) - (anim.startAt or 0)
    if elapsed >= DISCLOSURE_ANIM_DURATION then
        local ownerKey = anim.ownerKey
        local targetExpanded = anim.to == 1
        self._disclosureAnim = nil
        if self.disclosureAnimFrame then
            self.disclosureAnimFrame:SetScript("OnUpdate", nil)
        end
        SetOwnerExpanded(ownerKey, targetExpanded)
        self:Refresh(self.sourceRows, { cause = "toggle_expand" })
        return
    end
    if self.rowsScroll then
        self.rowsScroll:Refresh(true)
    end
end

function Prototype:StartOwnerDisclosureAnim(ownerKey, targetExpanded)
    local current = self:GetOwnerDisclosureProgress(ownerKey)
    local target = targetExpanded and 1 or 0
    if self._disclosureAnim and self._disclosureAnim.ownerKey ~= ownerKey then
        SetOwnerExpanded(self._disclosureAnim.ownerKey, self._disclosureAnim.to == 1)
        self._disclosureAnim = nil
    end
    SetOwnerExpanded(ownerKey, true)
    self._disclosureAnim = {
        ownerKey = ownerKey,
        from = current,
        to = target,
        startAt = GetTime and GetTime() or 0,
    }
    if not self.disclosureAnimFrame then
        self.disclosureAnimFrame = CreateFrame("Frame", nil, self.root)
    end
    local owner = self
    self.disclosureAnimFrame:SetScript("OnUpdate", function()
        owner:UpdateDisclosureAnim()
    end)
    self:Refresh(self.sourceRows, { cause = "toggle_expand" })
end

function Prototype:ApplySpellRowDisclosureVisual(row, progress)
    if not row.trackContent then
        return
    end
    local clamped = Clamp(progress, 0, 1)
    row._disclosureYOffset = EXPAND_ANIM_Y_OFFSET * (1 - clamped)
    row.trackContent:SetAlpha(clamped)
    if row.labelFrame then
        row.labelFrame:SetAlpha(clamped)
    end
    self:ApplyRowHorizontalOffset(row)
end

function Prototype:RenderRow(row, dataIndex)
    local displayRow = self.displayRows and self.displayRows[dataIndex] or nil
    if not displayRow then
        row._sttRenderSignature = nil
        row.displayRow = nil
        row._effectiveRowHeight = nil
        row._disclosureProgress = nil
        row._disclosureYOffset = nil
        if row.labelFrame then
            row.labelFrame:SetAlpha(1)
        end
        if row.trackContent then
            row.trackContent:SetAlpha(1)
        end
        row:Hide()
        return
    end
    row._effectiveRowHeight = self:GetDisplayRowHeight(dataIndex)
    if displayRow.kind == "spellRow" then
        row._disclosureProgress = self:GetOwnerDisclosureProgress(displayRow.ownerKey)
    else
        row._disclosureProgress = nil
        row._disclosureYOffset = nil
    end
    if displayRow.kind == "ownerHeader" then
        self:RenderOwnerHeaderRow(row, dataIndex, displayRow)
    else
        self:RenderSpellRow(row, dataIndex, displayRow)
    end
end

-- 只读行（施法记录临时行等）：同一行模型，仅在表现层加记录层视觉。
function Prototype:ApplyReadOnlyRowVisual(row, readOnly, bgColor)
    if row.bg and bgColor then
        row.bg:SetColorTexture(unpackFunc(bgColor))
    end
    if readOnly then
        if not row._readOnlyRail then
            row._readOnlyRail = row:CreateTexture(nil, "OVERLAY")
            row._readOnlyRail:SetWidth(3)
        end
        row._readOnlyRail:SetColorTexture(0.30, 0.88, 1.0, 1)
        row._readOnlyRail:ClearAllPoints()
        row._readOnlyRail:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row._readOnlyRail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row._readOnlyRail:Show()
    elseif row._readOnlyRail then
        row._readOnlyRail:Hide()
    end
end

function Prototype:RenderOwnerHeaderRow(row, dataIndex, displayRow)
    local entry = displayRow.entry
    local key = displayRow.ownerKey
    local prefs = GetPrefs()

    row.dataIndex = dataIndex
    row.rowKey = key
    row.entry = entry
    row.displayRow = displayRow
    if not entry then
        row._sttRenderSignature = nil
        row:Hide()
        return
    end

    row.selectTex:SetShown(self.selectedRowKey ~= nil and key == self.selectedRowKey)
    row.dragTargetTex:SetShown(self.dragTargetRowKey ~= nil and key == self.dragTargetRowKey)

    local showToggle = displayRow.hasSpells and true or false
    local disclosureAnim = self._disclosureAnim
    local targetExpanded = displayRow.expanded
    if disclosureAnim and disclosureAnim.ownerKey == key then
        targetExpanded = disclosureAnim.to == 1
    end
    local signature = JoinSignature({
        "owner",
        key,
        dataIndex % 2,
        displayRow.expanded and 1 or 0,
        targetExpanded and 1 or 0,
        showToggle and 1 or 0,
        prefs.rowHeight,
        self.firstColWidth,
        self.contentWidth,
        self:GetChipWindowRenderKey(),
        BuildEntryRenderSignature(entry),
    })
    if row._sttRenderSignature == signature then
        return
    end
    row._sttRenderSignature = signature
    self:AddScrollProfileCount("renderRows")

    row:SetHeight(prefs.rowHeight)
    row._disclosureYOffset = nil
    if row.labelFrame then
        row.labelFrame:SetAlpha(1)
    end
    if row.trackContent then
        row.trackContent:SetAlpha(1)
    end
    row.labelFrame:SetWidth(self.firstColWidth)
    row.trackClip:ClearAllPoints()
    row.trackClip:SetPoint("TOPLEFT", row.labelFrame, "TOPRIGHT", 0, 0)
    row.trackClip:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_SIDE_PADDING, 0)

    self:ApplyReadOnlyRowVisual(row, entry.readOnly == true, PickRowBackgroundColor(
        dataIndex,
        { 0.10, 0.10, 0.15, 0.52 },
        { 0.06, 0.06, 0.10, 0.35 },
        { 0.10, 0.17, 0.20, 0.55 },
        entry.readOnly == true
    ))

    local visual, color = self:ResolveEntryVisual(entry)
    row.labelIcon:Show()
    row.labelIcon:SetSize(20, 20)
    row.labelIcon:ClearAllPoints()
    row.labelIcon:SetPoint("LEFT", row.labelFrame, "LEFT", 6, 0)
    row.labelText:SetText(entry.meta.displayText or key)
    SetFontColor(row.labelText, color)
    ApplyTextureVisual(row.labelIcon, visual, color)

    row.labelText:ClearAllPoints()
    row.labelText:SetPoint("LEFT", row.labelIcon, "RIGHT", 6, 0)
    if showToggle then
        row.toggleBtn._ownerKey = key
        self:SetToggleButtonExpanded(row.toggleBtn, targetExpanded, row.toggleBtn._flashStartAt ~= nil)
        row.toggleBtn:Show()
        row.labelText:SetPoint("RIGHT", row.toggleBtn, "LEFT", -4, 0)
    else
        row.toggleBtn:SetScript("OnUpdate", nil)
        row.toggleBtn:Hide()
        row.toggleBtn._ownerKey = nil
        row.labelText:SetPoint("RIGHT", row.labelFrame, "RIGHT", -6, 0)
    end

    row.trackContent:SetWidth(math.max(1, self.contentWidth))
    local chipIndex = 0
    if not displayRow.expanded then
        local windowStart, windowEnd = self:GetVisibleChipTimeWindow()
        for _, item in ipairs(entry.items or {}) do
            if self:IsItemInVisibleChipWindow(item, windowStart, windowEnd) then
                chipIndex = chipIndex + 1
                self:RenderChip(self:AcquireChip(row, chipIndex), item)
            end
        end
    end
    for index = chipIndex + 1, #row.chips do
        self:HideChip(row.chips[index])
    end
    if T.TimelineSelectionBox and T.TimelineSelectionBox.Refresh then
        T.TimelineSelectionBox.Refresh(self)
    end
    self:ApplyRowHorizontalOffset(row)
end

function Prototype:RenderSpellRow(row, dataIndex, displayRow)
    local entry = displayRow.entry
    local key = displayRow.ownerKey
    local prefs = GetPrefs()

    row.dataIndex = dataIndex
    row.rowKey = key
    row.entry = entry
    row.displayRow = displayRow
    if not entry or type(displayRow.items) ~= "table" then
        row._sttRenderSignature = nil
        row:Hide()
        return
    end

    row.selectTex:SetShown(self.selectedRowKey ~= nil and key == self.selectedRowKey)
    row.dragTargetTex:SetShown(self.dragTargetRowKey ~= nil and key == self.dragTargetRowKey)

    local signature = JoinSignature({
        "spell",
        key,
        displayRow.spellID,
        dataIndex % 2,
        prefs.rowHeight,
        math.floor((tonumber(row._effectiveRowHeight) or prefs.rowHeight) * 100 + 0.5),
        math.floor((tonumber(row._disclosureProgress) or 1) * 1000 + 0.5),
        self.firstColWidth,
        self.contentWidth,
        self:GetChipWindowRenderKey(),
        #displayRow.items,
        displayRow.label,
        displayRow.spellIcon,
    })
    if row._sttRenderSignature == signature then
        return
    end
    row._sttRenderSignature = signature
    self:AddScrollProfileCount("renderRows")

    local effectiveHeight = math.max(0, tonumber(row._effectiveRowHeight) or prefs.rowHeight)
    row:SetHeight(effectiveHeight)
    row.labelFrame:SetWidth(self.firstColWidth)
    row.trackClip:ClearAllPoints()
    row.trackClip:SetPoint("TOPLEFT", row.labelFrame, "TOPRIGHT", 0, 0)
    row.trackClip:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_SIDE_PADDING, 0)

    self:ApplyReadOnlyRowVisual(row, entry.readOnly == true, PickRowBackgroundColor(
        dataIndex,
        { 0.08, 0.08, 0.12, 0.40 },
        { 0.05, 0.05, 0.08, 0.28 },
        { 0.09, 0.15, 0.17, 0.45 },
        entry.readOnly == true
    ))

    row.labelIcon:SetSize(16, 16)
    row.labelIcon:ClearAllPoints()
    row.labelIcon:SetPoint("LEFT", row.labelFrame, "LEFT", 6 + EXPAND_LABEL_INDENT, 0)
    if displayRow.spellIcon then
        row.labelIcon:SetTexture(displayRow.spellIcon)
        row.labelIcon:SetVertexColor(1, 1, 1, 1)
        row.labelIcon:Show()
    else
        row.labelIcon:Hide()
    end

    row.labelText:SetText(displayRow.label or "")
    SetFontColor(row.labelText, { 0.85, 0.85, 0.90, 1 })
    row.labelText:ClearAllPoints()
    row.labelText:SetPoint("LEFT", row.labelIcon, "RIGHT", 6, 0)
    row.labelText:SetPoint("RIGHT", row.labelFrame, "RIGHT", -6, 0)

    row.toggleBtn:Hide()
    row.toggleBtn._ownerKey = nil

    row.trackContent:SetWidth(math.max(1, self.contentWidth))
    local chipIndex = 0
    local windowStart, windowEnd = self:GetVisibleChipTimeWindow()
    for _, item in ipairs(displayRow.items or {}) do
        if self:IsItemInVisibleChipWindow(item, windowStart, windowEnd) then
            chipIndex = chipIndex + 1
            self:RenderChip(self:AcquireChip(row, chipIndex), item)
        end
    end
    for index = chipIndex + 1, #row.chips do
        self:HideChip(row.chips[index])
    end
    if T.TimelineSelectionBox and T.TimelineSelectionBox.Refresh then
        T.TimelineSelectionBox.Refresh(self)
    end
    self:ApplySpellRowDisclosureVisual(row, row._disclosureProgress or 1)
end

function Prototype:OnOwnerToggleClick(ownerKey)
    if type(ownerKey) ~= "string" or ownerKey == "" then
        return
    end
    local anim = self._disclosureAnim
    local nextState
    if anim and anim.ownerKey == ownerKey then
        nextState = anim.to ~= 1
    else
        nextState = not IsOwnerExpanded(ownerKey)
    end
    local button
    for _, row in ipairs(self.rowFrames or {}) do
        if row.displayRow and row.displayRow.kind == "ownerHeader" and row.displayRow.ownerKey == ownerKey then
            button = row.toggleBtn
            break
        end
    end
    self:PulseToggleButton(button, nextState)
    self:StartOwnerDisclosureAnim(ownerKey, nextState)
end

function Prototype:RefreshVisibleRows()
    if self.rowsScroll then
        self.rowsScroll:Refresh(true)
    end
end

function Prototype:RememberCurrentRowOrder()
    self.sourceRowOrder = {}
    for index, key in ipairs(self.orderedKeys or {}) do
        self.sourceRowOrder[index] = key
    end
end

function Prototype:ApplyStableSourceRowOrder()
    local existingOrder = self.sourceRowOrder
    local nextKeys, seen = {}, {}
    if existingOrder then
        for _, key in ipairs(existingOrder) do
            if self.perRow and self.perRow[key] then
                nextKeys[#nextKeys + 1] = key
                seen[key] = true
            end
        end
    end
    for _, key in ipairs(self.orderedKeys or {}) do
        if not seen[key] then
            nextKeys[#nextKeys + 1] = key
            seen[key] = true
        end
    end
    self.orderedKeys = nextKeys
    self:RememberCurrentRowOrder()
end

function Prototype:FlashRulerLabel()
    local bg = self.rulerLabel and self.rulerLabel.bg
    if not bg then
        return
    end
    bg:SetColorTexture(0.24, 0.19, 0.08, 0.95)
    self.rulerLabelFlashToken = (self.rulerLabelFlashToken or 0) + 1
    local token = self.rulerLabelFlashToken
    if C_Timer and C_Timer.After then
        C_Timer.After(0.12, function()
            if self.rulerLabelFlashToken == token and bg.SetColorTexture then
                bg:SetColorTexture(0.08, 0.08, 0.10, 0.85)
            end
        end)
    end
end

function Prototype:SortRowsByObjectOnce()
    table.sort(self.orderedKeys, function(leftKey, rightKey)
        local left = self.perRow and self.perRow[leftKey] or nil
        local right = self.perRow and self.perRow[rightKey] or nil
        local leftOrder = tonumber(left and left.sortOrder) or 4
        local rightOrder = tonumber(right and right.sortOrder) or 4
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        local leftIndex = tonumber(left and left.firstSortIndex) or 0
        local rightIndex = tonumber(right and right.firstSortIndex) or 0
        if leftIndex ~= rightIndex then
            return leftIndex < rightIndex
        end
        return tostring(left and left.meta and left.meta.displayText or leftKey) < tostring(right and right.meta and right.meta.displayText or rightKey)
    end)
    self:RememberCurrentRowOrder()
    self.rowsRenderSignature = nil
    self:RefreshVisibleRows()
    self:FlashRulerLabel()
    self:SetShortcutHintText(L["TIMELINE_SHORTCUT_HINT_FEEDBACK_ROW_SORT"] or "已按对象整理行顺序", T.HorizontalTimelineShortcutHint and T.HorizontalTimelineShortcutHint.feedbackSeconds)
    if T.debug then
        T.debug("[STT_HTG_ROW_SORT] mode=manual_once")
    end
end

function Prototype:GetFirstColumnMeasureSignature()
    local prefs = GetPrefs()
    local parts = {
        prefs.firstColMinW,
        prefs.firstColMaxW,
        #(self.orderedKeys or {}),
        #(self.displayRows or {}),
    }
    for _, key in ipairs(self.orderedKeys or {}) do
        local entry = self.perRow and self.perRow[key] or nil
        local text = entry and entry.meta and entry.meta.displayText or key
        parts[#parts + 1] = "o:" .. tostring(text)
    end
    for _, dr in ipairs(self.displayRows or {}) do
        if dr.kind == "spellRow" then
            parts[#parts + 1] = "s:" .. tostring(dr.label or "")
        end
    end
    return JoinSignature(parts)
end

function Prototype:GetRowsRenderSignature()
    local parts = {
        #(self.orderedKeys or {}),
        math.floor((tonumber(self.maxTime) or 0) * 10 + 0.5),
        math.floor((tonumber(self.pxPerSecond) or 0) * 100 + 0.5),
        math.floor((tonumber(self.contentWidth) or 0) + 0.5),
    }
    for _, key in ipairs(self.orderedKeys or {}) do
        parts[#parts + 1] = key
        parts[#parts + 1] = BuildEntryRenderSignature(self.perRow and self.perRow[key])
    end
    return JoinSignature(parts)
end

function Prototype:MeasureFirstColumn()
    local signature = self:GetFirstColumnMeasureSignature()
    if self.firstColMeasureSignature == signature and self.firstColWidth then
        return self.firstColWidth
    end

    local prefs = GetPrefs()
    local maxWidth = prefs.firstColMinW
    local OWNER_LABEL_PADDING = 6 + 20 + 6 + 4 + EXPAND_TOGGLE_SIZE + 4
    local SPELL_LABEL_PADDING = 6 + EXPAND_LABEL_INDENT + 16 + 6 + 6
    for _, key in ipairs(self.orderedKeys or {}) do
        local entry = self.perRow[key]
        local text = entry and entry.meta and entry.meta.displayText or key
        self.measureText:SetText(tostring(text or ""))
        local width = math.ceil((self.measureText:GetStringWidth() or #(tostring(text or "")) * 8) + OWNER_LABEL_PADDING)
        if width > maxWidth then
            maxWidth = width
        end
    end
    for _, dr in ipairs(self.displayRows or {}) do
        if dr.kind == "spellRow" then
            local text = tostring(dr.label or "")
            self.measureText:SetText(text)
            local width = math.ceil((self.measureText:GetStringWidth() or #text * 8) + SPELL_LABEL_PADDING)
            if width > maxWidth then
                maxWidth = width
            end
        end
    end
    self.firstColMeasureSignature = signature
    self.firstColWidth = Clamp(maxWidth, prefs.firstColMinW, prefs.firstColMaxW)
    return self.firstColWidth
end

function Prototype:AcquirePhaseMarker(index)
    local marker = self.phaseMarkers[index]
    if marker then
        return marker
    end

    marker = CreateFrame("Frame", nil, self.root)
    marker:SetWidth(1)
    marker.line = marker:CreateTexture(nil, "OVERLAY")
    marker.line:SetAllPoints(marker)
    marker.line:SetColorTexture(0.95, 0.78, 0.18, 0.46)
    marker.label = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    marker.label:SetTextColor(0.98, 0.86, 0.28, 1)
    marker.label:SetShadowOffset(1, -1)
    marker.label:SetJustifyH("CENTER")
    self.phaseMarkers[index] = marker
    return marker
end

function Prototype:RenderPhaseMarkers()
    local markers = self.phaseDisplayStats and self.phaseDisplayStats.markers or nil
    local markerCount = 0
    local px = math.max(0.0001, tonumber(self.pxPerSecond) or DEFAULT_PX_PER_SECOND)
    local scrollX = tonumber(self.scrollX) or 0
    local trackWidth = self:GetTrackWidth()
    local leftEdge = tonumber(self.firstColWidth) or 0
    local rightEdge = leftEdge + trackWidth
    local lastLabelMax = leftEdge

    for _, info in ipairs(markers or {}) do
        local time = tonumber(info.time)
        if time then
            local x = leftEdge + math.floor(time * px - scrollX + 0.5)
            if x >= leftEdge - 1 and x <= rightEdge + 1 then
                markerCount = markerCount + 1
                local marker = self:AcquirePhaseMarker(markerCount)
                local text = tostring(info.displayKey or info.key or "")
                marker:ClearAllPoints()
                marker:SetPoint("TOPLEFT", self.root, "TOPLEFT", x, 0)
                marker:SetPoint("BOTTOMLEFT", self.root, "BOTTOMLEFT", x, PHASE_MARKER_BOTTOM)
                marker.label:SetText(text)
                marker.label:ClearAllPoints()

                local width = marker.label:GetStringWidth() or (#text * 7)
                local labelLeft = x - width * 0.5
                local offset = 0
                if labelLeft < leftEdge + 4 then
                    offset = (leftEdge + 4) - labelLeft
                    labelLeft = leftEdge + 4
                end
                if labelLeft < lastLabelMax + 8 then
                    offset = offset + (lastLabelMax + 8 - labelLeft)
                    labelLeft = lastLabelMax + 8
                end
                lastLabelMax = labelLeft + width

                marker.label:SetPoint("TOP", marker, "TOP", offset, -18)
                marker:SetShown(true)
            end
        end
    end

    for index = markerCount + 1, #self.phaseMarkers do
        self.phaseMarkers[index]:Hide()
    end
end

function Prototype:RenderRuler()
    local px = self.pxPerSecond or DEFAULT_PX_PER_SECOND
    local totalSeconds = math.max(30, tonumber(self.totalSeconds) or 30)
    local trackWidth = self:GetTrackWidth()
    local grid = self:GetTimeGrid()
    local step = math.max(0.1, tonumber(grid.minorStep) or tonumber(grid.labelStep) or 10)
    local labelStep = math.max(step, tonumber(grid.labelStep) or step)
    local precision = math.max(0, tonumber(grid.precision) or 0)
    local startTime = math.max(0, ((tonumber(self.scrollX) or 0) / math.max(0.0001, px)) - step)
    local endTime = math.min(totalSeconds, (((tonumber(self.scrollX) or 0) + math.max(1, trackWidth)) / math.max(0.0001, px)) + step)
    local firstTick = math.floor(startTime / step) * step
    local tickCount = 0

    self.rulerContent:SetWidth(math.max(1, self.contentWidth))
    self:LogRulerScaleIfChanged(grid)

    for index = 0, math.max(0, math.ceil((endTime - firstTick) / step)) do
        local second = math.floor((firstTick + index * step) * 10 + 0.5) / 10
        if second >= 0 and second <= totalSeconds + 0.0001 then
            tickCount = tickCount + 1
            local tick = self.rulerTicks[tickCount]
            if not tick then
                tick = CreateFrame("Frame", nil, self.rulerContent)
                tick.line = tick:CreateTexture(nil, "ARTWORK")
                tick.line:SetPoint("BOTTOM", tick, "BOTTOM", 0, 0)
                tick.line:SetWidth(1)
                tick.label = tick:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                self.rulerTicks[tickCount] = tick
            end

            local major = math.abs((second / labelStep) - math.floor((second / labelStep) + 0.5)) < 0.0001
            tick:ClearAllPoints()
            tick:SetPoint("TOPLEFT", self.rulerContent, "TOPLEFT", math.floor(second * px + 0.5), 0)
            tick:SetSize(1, RULER_HEIGHT)
            tick.label:ClearAllPoints()
            if second == 0 then
                tick.label:SetPoint("TOPLEFT", tick, "TOPLEFT", 2, -3)
            else
                tick.label:SetPoint("TOP", tick, "TOP", 0, -3)
            end
            tick.line:SetHeight(major and 24 or 12)
            tick.line:SetColorTexture(1, 1, 1, major and 0.42 or 0.20)
            tick.label:SetText(major and FormatTime(second, precision) or "")
            tick:SetShown(true)
        end
    end

    for index = tickCount + 1, #self.rulerTicks do
        self.rulerTicks[index]:Hide()
    end
    self:RenderPhaseMarkers()
    self:UpdatePlayhead(self.runnerTime or 0, self.lastRunnerPlaying == true)
end

function Prototype:RefreshLayout(cause, forceRows)
    local prefs = GetPrefs()
    self.firstColWidth = self:MeasureFirstColumn()
    local pxChanged = self:ApplyPxPerSecondBounds()
    local layoutSignature = JoinSignature({
        self.firstColWidth,
        prefs.rowHeight,
        math.floor((tonumber(self.contentWidth) or 0) + 0.5),
        math.floor((tonumber(self:GetTrackWidth()) or 0) + 0.5),
    })
    local layoutChanged = layoutSignature ~= self.layoutSignature
    self.layoutSignature = layoutSignature

    if layoutChanged then
        self.rulerLabel:SetWidth(self.firstColWidth)
        self.rulerClip:ClearAllPoints()
        self.rulerClip:SetPoint("TOPLEFT", self.rulerLabel, "TOPRIGHT", 0, 0)
        self.rulerClip:SetPoint("TOPRIGHT", self.root, "TOPRIGHT", -2, 0)
	    self.rulerClip:SetHeight(RULER_HEIGHT)
    end
    if self.playhead then
        self:UpdatePlayhead(self.runnerTime or 0, self.lastRunnerPlaying == true)
    end

    if layoutChanged then
	    self.hScrollBar:ClearAllPoints()
        self.hScrollBar:SetPoint("BOTTOMLEFT", self.root, "BOTTOMLEFT", self.firstColWidth + 2, HSCROLL_BOTTOM)
        self.hScrollBar:SetPoint("BOTTOMRIGHT", self.root, "BOTTOMRIGHT", -6, HSCROLL_BOTTOM)
        self:LayoutShortcutHint()
    end

    self:SetScrollX(self.scrollX, cause or "layout")
    if forceRows or layoutChanged or pxChanged then
        self:RefreshVisibleRows()
    end
end

function Prototype:Refresh(rows, opts)
    opts = type(opts) == "table" and opts or {}
    local prefs = GetPrefs()
    local shouldRestoreViewport = opts.restoreViewport == true
        or self.didRestoreViewport ~= true
        or IsViewportRestoreCause(opts.cause)
    local beforeScrollX = tonumber(self.scrollX) or 0
    local beforePxPerSecond = tonumber(self.pxPerSecond) or 0
    if shouldRestoreViewport then
        self.pxPerSecond = prefs.pxPerSecond or DEFAULT_PX_PER_SECOND
        self.scrollX = prefs.scrollX or 0
        self.didRestoreViewport = true
    else
        self.pxPerSecond = self.pxPerSecond or prefs.pxPerSecond or DEFAULT_PX_PER_SECOND
        self.scrollX = self.scrollX or prefs.scrollX or 0
    end
    if not self.didRefreshRosterCache or not IsDataOnlyRefreshCause(opts.cause) then
        self:RefreshRosterCache()
        self.didRefreshRosterCache = true
    end

    if opts.cause == "initial_open" or opts.cause == "panel_show" or opts.cause == "boss_change" or opts.cause == "profile_changed" or opts.cause == "reset" or opts.cause == "sync_apply" then
        self.sourceRowOrder = nil
    end

    local data = T.HorizontalTimelineData
    self.sourceRows = rows
    if data and data.BuildPerRow then
        local personnelKeys = opts.personnelKeys
        local audienceDisplayByLine = opts.audienceDisplayByLine
        if not personnelKeys and not audienceDisplayByLine then
            personnelKeys, audienceDisplayByLine = ExtractPersonnelContext(opts.fullText)
        end
        self.perRow, self.orderedKeys, self.maxTime, self.phaseDisplayStats = data.BuildPerRow(rows, {
            personnelKeys = personnelKeys,
            audienceDisplayByLine = audienceDisplayByLine,
        })
    else
        self.perRow, self.orderedKeys, self.maxTime = {}, {}, 0
        self.phaseDisplayStats = nil
    end
    self:ApplyStableSourceRowOrder()
    if self.selectedRowKey and not self.perRow[self.selectedRowKey] then
        self.selectedRowKey = nil
    end

    local durationItemCount = 0
    for _, entry in pairs(self.perRow or {}) do
        for _, item in ipairs(entry.items or {}) do
            if tonumber(item.duration) and tonumber(item.duration) > 0 then
                durationItemCount = durationItemCount + 1
            end
        end
    end
    self.durationItemCount = durationItemCount

    if T.CastLogRow then T.CastLogRow.Inject(self) end
    self.totalSeconds = math.max(30, (tonumber(self.maxTime) or 0) + 30)
    self:RefreshContentWidth()
    self.emptyText:SetShown(#self.orderedKeys == 0)

    if data and data.BuildHorizontalDisplayRows then
        self.displayRows = data.BuildHorizontalDisplayRows(self.perRow, self.orderedKeys, prefs.expanded)
    else
        self.displayRows = {}
    end
    self.rowsScroll:SetRowHeight(prefs.rowHeight)
    self.rowsScroll:SetDataCount(#self.displayRows)
    if opts.restoreScrollY == true or not self.didRestoreScrollY then
        self.rowsScroll:SnapTo(prefs.scrollY or 0)
        self.didRestoreScrollY = true
    end

    local rowsRenderSignature = self:GetRowsRenderSignature()
    local rowsChanged = rowsRenderSignature ~= self.rowsRenderSignature
    self.rowsRenderSignature = rowsRenderSignature
    self:RefreshLayout(opts.cause or "refresh", rowsChanged or opts.force == true)
    if C and C.DB and C.DB.debugMode and T.debug then
        local afterScrollX = tonumber(self.scrollX) or 0
        local afterPxPerSecond = tonumber(self.pxPerSecond) or 0
    end
end

function Prototype:Show()
    self:Activate()
    wipe(self.inputConsumeLogSeen)
    self.root:Show()
    self:RefreshRosterCache()
    if self.rowsScroll then
        self.rowsScroll:SnapTo(GetPrefs().scrollY or 0)
    end
end

function Prototype:Hide()
    self:Deactivate()
    self:HideDrawer()
    self.root:Hide()
end

function Prototype:GetCurrentScrollX()
    return self.scrollX or 0
end

function Prototype:GetCurrentPxPerSecond()
    return self.pxPerSecond or GetPrefs().pxPerSecond or DEFAULT_PX_PER_SECOND
end

function Prototype:BuildDrawerItems(item)
    local out = { item }
    for _, collision in ipairs(item and item.collisions or {}) do
        out[#out + 1] = collision
    end
    table.sort(out, function(a, b)
        return (a.lineNum or 0) < (b.lineNum or 0)
    end)
    return out
end

function Prototype:AcquireDrawerItem(index)
    local drawer = self.drawer
    local button = drawer.items[index]
    if button then
        button:Show()
        return button
    end

    button = CreateFrame("Button", nil, drawer)
    button:SetHeight(22)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("LEFT", button, "LEFT", 0, 0)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
    button.text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    button.text:SetJustifyH("LEFT")
    button.hover = button:CreateTexture(nil, "BACKGROUND")
    button.hover:SetAllPoints()
    button.hover:SetColorTexture(0.25, 0.45, 0.85, 0.25)
    button.hover:Hide()
    BlockMousePropagation(button)
    button:SetScript("OnEnter", function(selfButton)
        selfButton.hover:Show()
        ShowTimelineTooltip(selfButton, selfButton.item)
    end)
    button:SetScript("OnLeave", function(selfButton)
        selfButton.hover:Hide()
        if T.UITooltip then
            T.UITooltip.ScheduleHide()
        else
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnClick", function(selfButton)
        if selfButton.item then
            local chip = self.drawer and self.drawer.ownerChip
            local row = chip and chip.row
            if row and T.TimelineSelectionBox and T.TimelineSelectionBox.SelectContexts then
                local ctx = self:BuildSelectionContext(row, selfButton.item, selfButton.item == (chip and chip.item) and chip or nil)
                if ctx then
                    if self:IsSelectionToggleDown() then
                        T.TimelineSelectionBox.SelectContexts(self, { ctx }, "toggle", "drawer_toggle")
                    else
                        T.TimelineSelectionBox.SelectContexts(self, { ctx }, "replace", "drawer_click")
                    end
                    T.TimelineSelectionBox.FocusPrimary(ctx)
                    self:SetSelectedRowKey(row.rowKey, "drawer_click")
                    self:FocusSelectionContext(ctx)
                    return
                end
            end
            self:JumpToItem(selfButton.item)
        end
    end)
    drawer.items[index] = button
    return button
end

function Prototype:ShowDrawerForChip(chip)
    local item = chip and chip.item
    if not item then
        return
    end
    local items = self:BuildDrawerItems(item)
    local drawer = self.drawer
    drawer.ownerChip = chip
    drawer.title:SetText(string.format("%s · %d %s", FormatTime(item.time), #items, L["TIMELINE_VIEW_ITEMS"] or "项"))

    local top = -30
    for index, drawerItem in ipairs(items) do
        local button = self:AcquireDrawerItem(index)
        button.item = drawerItem
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", drawer, "TOPLEFT", 10, top - (index - 1) * 24)
        button:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -10, top - (index - 1) * 24)
        if drawerItem.spellIcon then
            button.icon:SetTexture(drawerItem.spellIcon)
        else
            button.icon:SetTexture(DEFAULT_ICON)
        end
        button.text:SetText(drawerItem.fullText ~= "" and drawerItem.fullText or (L["TIMELINE_VIEW_EMPTY_TEXT"] or "空文本"))
    end
    for index = #items + 1, #drawer.items do
        drawer.items[index]:Hide()
        drawer.items[index].item = nil
    end

    drawer:SetHeight(math.max(64, 40 + #items * 24))
    drawer:ClearAllPoints()
    drawer:SetPoint("TOPLEFT", chip, "TOPRIGHT", 8, 8)
    drawer:Show()
end

function Prototype:HideDrawer()
    if self.drawer then
        self.drawer:Hide()
        self.drawer.ownerChip = nil
    end
end

function Prototype:ScheduleDrawerHide()
    self.drawerHideToken = self.drawerHideToken + 1
    local token = self.drawerHideToken
    C_Timer.After(0.12, function()
        if token ~= self.drawerHideToken then
            return
        end
        local drawer = self.drawer
        local chip = drawer and drawer.ownerChip
        if self.drawerInside or (chip and chip.IsMouseOver and chip:IsMouseOver()) then
            return
        end
        self:HideDrawer()
    end)
end

function Prototype:HandleChipEnter(chip)
    local item = chip and chip.item
    if not item then
        return
    end
    self.drawerHideToken = self.drawerHideToken + 1
    if #(item.collisions or {}) > 0 then
        if T.UITooltip then
            T.UITooltip.ScheduleHide()
        else
            GameTooltip:Hide()
        end
        self:ShowDrawerForChip(chip)
        return
    end

    self:HideDrawer()
    ShowTimelineTooltip(chip, item)
end

function Prototype:HandleChipLeave(chip)
    if T.UITooltip then
        T.UITooltip.ScheduleHide()
    else
        GameTooltip:Hide()
    end
    self:ScheduleDrawerHide()
end

function Prototype:JumpToItem(item)
    if not item then
        return
    end
    self:HideDrawer()
    if self.opts and type(self.opts.focusItem) == "function" then
        self.opts.focusItem(item)
        return
    end
    local lineNum = tonumber(item.lineNum)
    if lineNum and lineNum > 0 then
        if self.opts and type(self.opts.focusLine) == "function" then
            self.opts.focusLine(lineNum)
        elseif T.SemanticTimelineGUI and T.SemanticTimelineGUI.FocusEditorLine then
            T.SemanticTimelineGUI.FocusEditorLine(lineNum)
        end
    end
end

end)
