-- ═══════════════════════════════════════════════════════════════
-- 鲁拉符文助手 (L'ura Rune Helper)
-- 至暗之夜 S1 · 进军奎尔丹纳斯 · L'ura（至暗降临）
--
-- 机制：L'ura 施放 Death's Dirge（1244412），依次点亮 5 个位置的
--       Dark Rune（1249609）。5 名被点名的玩家必须按照符文亮起的
--       顺序，沿顺时针排开。乱序会触发 Dissonance（全团 DoT，团灭级）。
--
-- 工作方式：指挥通过动作条直发宏，默认 /raid + 符文图片路径 payload。
--           仅在鲁拉战斗（encounterID=3183）期间、且处于符文阶段窗口期
--           才动态注册聊天监听 —— 窗口外完全不监听，团员平时 yell 互动不会误触发。
--
-- 通信：独立前缀 STTRUNE，协议：
--   S:raid:event:ts   — 团长战斗外同步频道与分配模式
--   R:3,1,5,2,4:ts  — 符文顺序（addon message 通道）
--
-- 命令：/st rune clear    — 清除符文显示
--       /st rune test     — 测试显示
--       /st rune macro    — 已弃用，改为设置页拖拽
-- ═══════════════════════════════════════════════════════════════
local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("dreadElegy.enabled", function()

local function DreadElegyDebug(...)
end

-- ── 常量 ─────────────────────────────────────────────────────
local ChannelSync = T.DreadElegyChannelSync
local RUNE_PREFIX = (ChannelSync and ChannelSync.PREFIX) or "STTRUNE"
local RUNE_COUNT = 5
local RUNE_UNDO_INDEX = RUNE_COUNT + 1
local RUNE_MACRO_COUNT = RUNE_COUNT + 1
local DISPLAY_DURATION = 10      -- 临时显示持续秒数
local FADE_OUT_DURATION = 2      -- 淡出时长
local LEGACY_RUNE_MACRO_NAME_PREFIX = "STT符文"
local RUNE_DRAG_TEMP_STRATA = "LOW"
local RUNE_MACRO_NAME_SUMMARY = "◇STT / △STT / TSTT / ○STT / XSTT / 撤回STT"
local RUNE_UNDO_MACRO_BODY = "/rw 撤回"

local RUNE_PATH = "Interface/AddOns/ShengTangTools/media/"
local RUNE_ICON_TEXTURE_FILES = {
    [1] = "Interface\\AddOns\\ShengTangTools\\media\\rune_rhom.tga",
    [2] = "Interface\\AddOns\\ShengTangTools\\media\\rune_tran.tga",
    [3] = "Interface\\AddOns\\ShengTangTools\\media\\rune_t.tga",
    [4] = "Interface\\AddOns\\ShengTangTools\\media\\rune_circle.tga",
    [5] = "Interface\\AddOns\\ShengTangTools\\media\\rune_x.tga",
    [RUNE_UNDO_INDEX] = "Interface\\RAIDFRAME\\ReadyCheck-NotReady",
}
local POS_TEXTURES = {
    [1] = RUNE_PATH .. "rune_rhom",    -- 菱形
    [2] = RUNE_PATH .. "rune_tran",    -- 三角
    [3] = RUNE_PATH .. "rune_t",       -- T形
    [4] = RUNE_PATH .. "rune_circle",  -- 圆圈
    [5] = RUNE_PATH .. "rune_x",       -- 叉叉
    [RUNE_UNDO_INDEX] = "Interface\\RAIDFRAME\\ReadyCheck-NotReady",
}

-- 位置颜色（图集自带蓝色，不额外染色）
local POS_COLORS = {
    [1] = { 1, 1, 1 },
    [2] = { 1, 1, 1 },
    [3] = { 1, 1, 1 },
    [4] = { 1, 1, 1 },
    [5] = { 1, 1, 1 },
}

local POS_SYMBOLS = {
    [1] = "◇", [2] = "△", [3] = "T", [4] = "○", [5] = "X",
    [RUNE_UNDO_INDEX] = "撤",
}

local RUNE_MACRO_NAMES = {
    [1] = "◇STT",
    [2] = "△STT",
    [3] = "TSTT",
    [4] = "○STT",
    [5] = "XSTT",
    [RUNE_UNDO_INDEX] = "撤回STT",
}

local POS_NAMES = {
    [1] = "菱形", [2] = "三角", [3] = "T形", [4] = "圆圈", [5] = "叉叉",
    [RUNE_UNDO_INDEX] = "撤回",
}

-- ── 显示常量 ─────────────────────────────────────────────────
local ICON_SIZE = 56
local ORDER_FONT_SIZE = 20
local NAME_FONT_SIZE = 12
local RING_RADIUS = 100
local BOSS_DOT_SIZE = 36
local CONTAINER_SIZE = 250
local DEFAULT_PANEL_POS = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 80, y = -120 }
local RUNE_GUIDE_BG_TEXTURE = "Interface\\AddOns\\ShengTangTools\\media\\textures\\circle_white.png"
local RUNE_GUIDE_BG_SIZE = 74
local RUNE_GUIDE_BACKGROUNDS = {
    [2] = { 1.00, 0.08, 0.04, 0.22 },
    [3] = { 0.08, 0.42, 1.00, 0.22 },
    [5] = { 1.00, 0.08, 0.04, 0.22 },
}

-- 侧栏（快捷录入）
local SIDEBAR_BTN_SIZE = 32
local SIDEBAR_WIDTH    = 38
local SIDEBAR_GAP      = 4

-- 5个位置的角度（顺时针：2点、4点、6点、8点、10点）
local POS_ANGLES = {
    [1] = 60,   [2] = 120,  [3] = 180,  [4] = 240,  [5] = 300,
}

-- ── 模块状态 ─────────────────────────────────────────────────
local DreadElegy = T.ModuleLoader:NewModule({
    name = "DreadElegy",
    dbKey = "dreadElegy.enabled",
    defaultEnabled = false,
})
T.DreadElegy = DreadElegy

local displaySequence = nil
local displaySender = nil
local inEncounter = false            -- encounter 状态追踪
local LURA_ENCOUNTER_ID = 3183

-- 每个符文阶段开始前提前注册聊天监听，覆盖 STT 自身的预提示时间
-- 时间戳单位：encounter 开始后的秒数，按难度 ID 查表
-- 14=Normal, 15=Heroic, 16=Mythic；LFR(17) 不跑鲁拉机制，表里不列
local LURA_RUNE_WINDOW_STARTS = {
    [14] = {10, 80, 150},
    [15] = {10, 80, 150},
    [16] = {33, 95, 157},
}
local LURA_RUNE_WINDOW_PRE_ENABLE = 6   -- 阶段开始前多少秒开启监听
local LURA_RUNE_HIDE_AFTER_MSG    = 15
local LURA_RUNE_HIDE_AFTER_MSG_P4 = 13
local LURA_RUNE_ABSOLUTE_STOP     = 200 -- encounter 开始后多少秒强制终止所有符文窗口（兜底）
local LURA_P4_RESET_WINDOWS       = { 20, 40, 75, 95, 130, 150 }

local luraEncounterActive = false    -- 当前是否在鲁拉 encounter
local luraChatEventsRegistered = false
local luraDifficultyID = 0
local luraPhase = 1
local luraPhaseSwapTime = 0
local luraWindowArmTimers = {}       -- 预启用 timer 数组
local luraP4ResetTimers = {}
local luraWindowHideTimer = nil      -- 收到消息后 N 秒关闭的 timer
local luraAbsoluteStopTimer = nil    -- encounter 全局兜底 timer
local luraRoutedSlots = {}
local luraRuneRouteHistory = {}
local lastLuraRuneSenderKey = nil
local pendingRuneMacroSync = false
local pendingRuneMacroIconRefreshReason = nil
local didScheduleRuneStartupRefresh = false
local RUNE_MACRO_STARTUP_ICON_REFRESH_DELAYS = { 1, 3, 6, 10 }
local runeDragRestoreStrata = nil
local resolvedRuneMacroIcons = {}
local resolvedRuneMacroIconSources = {}
local pendingRuneMacroDisplayRestore = nil
local runeNoticeFrame = nil
local lastRuneNoticeText = nil
local lastRuneNoticeAt = 0
local chatMirrorFrame = nil
local RefreshChatMirrorOrderLabels

-- 频道配置选项（默认 raid；/y /e /say 作为可选备用）
local CHAT_TYPES = {
    { key = "raid",    label = "团队（默认）— 发送: /raid 路径" },
    { key = "yell",    label = "大喊 — 发送: /y 路径" },
    { key = "emote",   label = "表情 — 发送: /e 路径" },
    { key = "say",     label = "说 — 发送: /say 路径" },
}

-- 聊天发送用 TGA 路径（接收方 SetFormattedText("|T%s:48:48|t", secret) 直接渲染自制蓝色符文）
local RUNE_CHAT_PATHS = {
    [1] = RUNE_PATH .. "rune_rhom",    -- 菱形
    [2] = RUNE_PATH .. "rune_tran",    -- 三角
    [3] = RUNE_PATH .. "rune_t",       -- T形
    [4] = RUNE_PATH .. "rune_circle",  -- 圆圈
    [5] = RUNE_PATH .. "rune_x",       -- 叉叉
}

local RUNE_POINT_SOUND_PATHS = {
    [1] = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\1rune.ogg",
    [2] = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\2rune.ogg",
    [3] = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\3rune.ogg",
    [4] = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\4rune.ogg",
    [5] = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\5rune.ogg",
}

local RUNE_MACRO_TRANSPORT_ICON_IDS = {
    [1] = 340528,
    [2] = 351033,
    [3] = 7242384,
    [4] = 134635,
    [5] = 236903,
    [RUNE_UNDO_INDEX] = 132284,
}

-- 原理：动作条宏通过配置的聊天命令发送纯文本路径，接收方 CHAT_MSG 事件拿到 secret value，
-- string.format("|T%s:48:48|t", secret) 允许操作，C++ 渲染引擎解析 |T 时直接读字节流，不受 Lua secret 限制。
local GetDB
local MarkRuneMacroSyncPending

local function GetRuneChatCode(runeId)
    return RUNE_CHAT_PATHS[runeId] or tostring(runeId)
end

local function PlayRunePointSound(index)
    if not (index and index >= 1 and index <= RUNE_COUNT and T.PlayInlineSound) then
        return false
    end
    local path = RUNE_POINT_SOUND_PATHS[index]
    return T.PlayInlineSound(path, tostring(index) .. "rune.ogg")
end


local GetChatPrefix  -- 前置声明（定义在 GetDB 之后）


local RUNE_ROUTE_MODE_SEQUENTIAL = "sequential"
local RUNE_ROUTE_MODE_EVENT = "event"
local LEGACY_RUNE_ROUTE_ENABLED_KEY = "leader" .. "SplitEnabled"
local LEGACY_RUNE_ROUTE_SCHEMA_KEY = "leader" .. "SplitDefaultSchemaVersion"

local function NormalizeRuneRouteMode(mode)
    if mode == RUNE_ROUTE_MODE_EVENT or mode == "sender" then
        return RUNE_ROUTE_MODE_EVENT
    end
    return RUNE_ROUTE_MODE_SEQUENTIAL
end

local function NormalizePanelBackdropOpacity(value)
    local opacity = tonumber(value)
    if not opacity then return 85 end
    return math.max(0, math.min(100, opacity))
end

local function GetPanelBackdropAlpha()
    return NormalizePanelBackdropOpacity(GetDB().panelOpacity) / 100
end

-- ── DB 存取 ──────────────────────────────────────────────────
GetDB = function()
    if not C.DB.dreadElegy then
        C.DB.dreadElegy = {
            chatType = "raid",    -- 频道类型: raid/yell/emote/say
        }
    end
    -- 兼容旧 DB
    local db = C.DB.dreadElegy
    if db.enabled == nil then db.enabled = false end
    if db.raidOnly == nil then db.raidOnly = true end
    if db.runeRouteMode == nil then
        db.runeRouteMode = RUNE_ROUTE_MODE_EVENT
    else
        db.runeRouteMode = NormalizeRuneRouteMode(db.runeRouteMode)
    end
    db[LEGACY_RUNE_ROUTE_ENABLED_KEY] = nil
    db[LEGACY_RUNE_ROUTE_SCHEMA_KEY] = nil
    -- schemaVersion 4：默认切到 raid，仍发送 STT 自有贴图路径 payload。
    if db.chatTypeSchemaVersion ~= 4 then
        db.chatType = "raid"
        db.chatChannel = nil
        db.chatTypeSchemaVersion = 4
    end
    if not (ChannelSync and ChannelSync.IsValidChatType and ChannelSync.IsValidChatType(db.chatType)) then
        db.chatType = "raid"
    end
    if db.announceNumberOnShow == nil then db.announceNumberOnShow = false end
    db["receiver" .. "Enabled"] = nil
    if db.runeSoundVolume ~= nil then db.runeSoundVolume = nil end
    if db.runeImageMode ~= nil then db.runeImageMode = nil end
    if db.locked == nil then db.locked = true end
    if db.panelScale == nil then db.panelScale = 1.0 end
    db.panelOpacity = NormalizePanelBackdropOpacity(db.panelOpacity)
    db.crystalAlertEnabled = nil
    db.crystalAlertIndicatorName = nil
    db.crystalAlertDurationSec = nil
    return C.DB.dreadElegy
end

function DreadElegy:GetLuraButtonBarDefaultPoint(buttonBarWidth, buttonBarGap)
    local width = tonumber(buttonBarWidth) or CONTAINER_SIZE
    local gap = tonumber(buttonBarGap) or 10
    return {
        point = "TOPLEFT",
        relPoint = DEFAULT_PANEL_POS.relPoint,
        x = DEFAULT_PANEL_POS.x + math.floor((CONTAINER_SIZE - width) / 2 + 0.5),
        y = DEFAULT_PANEL_POS.y - (CONTAINER_SIZE + 30) - gap,
    }
end

local function ApplyPanelBackdropOpacity()
    if chatMirrorFrame then
        chatMirrorFrame:SetBackdropColor(0, 0, 0, GetPanelBackdropAlpha())
    end
end

-- ── 聊天频道与动作条宏工具（必须在 GetDB 之后定义）─────────────
GetChatPrefix = function()
    local db = GetDB()
    local ctype = db.chatType or "raid"
    if ctype == "raid" then return "/raid "
    elseif ctype == "say" then return "/say "
    elseif ctype == "yell" then return "/y "
    elseif ctype == "emote" then return "/e "
    else return "/raid "
    end
end

local function CanShowRuneNotice(msg)
    local now = GetTime and GetTime() or 0
    if msg == lastRuneNoticeText and (now - lastRuneNoticeAt) < 0.6 then
        return false
    end
    lastRuneNoticeText = msg
    lastRuneNoticeAt = now
    return true
end

local function AcquireRuneNoticeFrame()
    if runeNoticeFrame and runeNoticeFrame.SetParent then
        return runeNoticeFrame
    end

    local frame = CreateFrame("ScrollingMessageFrame", "STT_DreadElegyNoticeFrame", UIParent)
    frame:SetSize(1024, 64)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(120)
    frame:SetToplevel(true)
    frame:SetJustifyH("CENTER")
    if GameFontHighlightLarge then
        frame:SetFontObject(GameFontHighlightLarge)
    elseif GameFontNormalLarge then
        frame:SetFontObject(GameFontNormalLarge)
    end
    frame:SetShadowOffset(1, -1)
    frame:SetFading(true)
    frame:SetFadeDuration(0.5)
    frame:SetTimeVisible(2.0)
    frame:SetMaxLines(2)
    frame:EnableMouse(false)

    runeNoticeFrame = frame
    return frame
end

local function ShowRuneTopNotice(msg)
    if not msg or msg == "" or not CanShowRuneNotice(msg) then
        return
    end

    local color = _G.YELLOW_FONT_COLOR or (ChatTypeInfo and ChatTypeInfo.SYSTEM)
    local r, g, b = 1, 0.82, 0
    if color then
        if color.r then
            r, g, b = color.r, color.g, color.b
        elseif color.GetRGB then
            r, g, b = color:GetRGB()
        end
    end

    local frame = AcquireRuneNoticeFrame()
    if frame and frame.AddMessage then
        if frame.Clear then
            frame:Clear()
        end
        frame:AddMessage(tostring(msg), r, g, b)
    end
end

local function GetRunePlainNoticeText(msg)
    return tostring(msg or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function ShowRuneMacroWarning(msg)
    if not msg or msg == "" then
        return
    end

    T.msg(msg)

    local plainText = GetRunePlainNoticeText(msg)
    if plainText == "" then
        return
    end

    if T.TacticalNotice and T.TacticalNotice.ShowBanner then
        local shown = T.TacticalNotice:ShowBanner({
            text = plainText,
            duration = 3.5,
            severity = "warning",
            force = true,
            bypassCooldown = true,
        })
        if shown then
            return
        end
    end

    ShowRuneTopNotice(plainText)
end

local function GetLegacyRuneMacroName(runeIndex)
    return LEGACY_RUNE_MACRO_NAME_PREFIX .. tostring(runeIndex)
end

local function GetRuneMacroName(runeIndex)
    return RUNE_MACRO_NAMES[runeIndex]
end

local function GetRuneMacroDisplayIcon(runeIndex)
    local cached = resolvedRuneMacroIcons[runeIndex]
    if cached ~= nil then
        return cached, resolvedRuneMacroIconSources[runeIndex] or "addon_texture"
    end

    local icon = nil
    local iconSource = "addon_texture"
    local texturePath = RUNE_ICON_TEXTURE_FILES[runeIndex]
    if texturePath and type(GetFileIDFromPath) == "function" then
        local ok, fileID = pcall(GetFileIDFromPath, texturePath)
        if ok and type(fileID) == "number" and fileID ~= 0 then
            icon = fileID
        elseif runeIndex <= RUNE_COUNT then
            DreadElegyDebug(string.format(
                "[DreadElegy] RuneMacroDisplayIconUnresolved rune=%d texture=%s reason=icon_unresolved ok=%s fileID=%s",
                runeIndex,
                tostring(texturePath),
                tostring(ok),
                tostring(fileID)
            ))
        end
    elseif texturePath and runeIndex <= RUNE_COUNT then
        DreadElegyDebug(string.format(
            "[DreadElegy] RuneMacroDisplayIconUnresolved rune=%d texture=%s reason=get_file_id_unavailable",
            runeIndex,
            tostring(texturePath)
        ))
    end

    if not icon and runeIndex == RUNE_UNDO_INDEX then
        icon = texturePath
        iconSource = "builtin_texture_path"
    end

    if not icon then
        icon = RUNE_MACRO_TRANSPORT_ICON_IDS[runeIndex] or "INV_MISC_QUESTIONMARK"
        iconSource = "builtin_fallback"
    end

    resolvedRuneMacroIcons[runeIndex] = icon
    resolvedRuneMacroIconSources[runeIndex] = iconSource
    return icon, iconSource
end

local function IsRuneMacroDisplayIconUnresolved(runeIndex, iconSource)
    return runeIndex and runeIndex <= RUNE_COUNT and iconSource == "builtin_fallback"
end

local function GetRuneMacroTransportIcon(runeIndex)
    local icon = RUNE_MACRO_TRANSPORT_ICON_IDS[runeIndex] or "INV_MISC_QUESTIONMARK"
    return icon, "builtin_transport"
end

local function ClearPendingRuneMacroDisplayRestore()
    pendingRuneMacroDisplayRestore = nil
end

local function ClearResolvedRuneMacroIconCache()
    resolvedRuneMacroIcons = {}
    resolvedRuneMacroIconSources = {}
end

local function GetRuneMacroBody(runeIndex)
    if runeIndex == RUNE_UNDO_INDEX then
        return RUNE_UNDO_MACRO_BODY
    end
    return GetChatPrefix() .. GetRuneChatCode(runeIndex)
end

local function IsGeneratedRuneMacroBody(runeIndex, body)
    body = tostring(body or "")
    if runeIndex == RUNE_UNDO_INDEX then
        return body == RUNE_UNDO_MACRO_BODY
    end

    local code = GetRuneChatCode(runeIndex)
    return body == "/raid " .. code
        or body == "/say " .. code
        or body == "/y " .. code
        or body == "/e " .. code
end

local function FindMacroByName(macroName)
    local numAccount = GetNumMacros()
    for idx = 1, numAccount do
        local name = GetMacroInfo(idx)
        if name == macroName then
            return idx, "account"
        end
    end

    return nil, nil
end

local function DeleteOwnedRuneMacro(runeIndex)
    local macroName = GetRuneMacroName(runeIndex)
    local macroID, scope = FindMacroByName(macroName)
    if not macroID then
        return false, "missing"
    end

    local _, _, body = GetMacroInfo(macroID)
    if not IsGeneratedRuneMacroBody(runeIndex, body) then
        DreadElegyDebug(string.format(
            "[DreadElegy] RuneMacroDeleteSkipped rune=%d macroID=%d scope=%s reason=body_mismatch",
            runeIndex,
            macroID,
            tostring(scope or "unknown")
        ))
        return false, "body_mismatch"
    end

    DeleteMacro(macroID)
    DreadElegyDebug(string.format(
        "[DreadElegy] RuneMacroDeleted rune=%d macroID=%d scope=%s name=%s",
        runeIndex,
        macroID,
        tostring(scope or "unknown"),
        macroName
    ))
    return true, "deleted"
end

local function CleanupLegacyRuneMacro(runeIndex, keepMacroID)
    if runeIndex > RUNE_COUNT then
        return false
    end
    local legacyMacroID = FindMacroByName(GetLegacyRuneMacroName(runeIndex))
    if legacyMacroID and legacyMacroID ~= keepMacroID then
        DeleteMacro(legacyMacroID)
        DreadElegyDebug(string.format(
            "[DreadElegy] RuneMacroLegacyDeleted rune=%d macroID=%d name=%s",
            runeIndex,
            legacyMacroID,
            GetLegacyRuneMacroName(runeIndex)
        ))
        return true
    end
    return false
end

local function CleanupDuplicateLegacyRuneMacros()
    local deletedCount = 0
    for i = 1, RUNE_COUNT do
        local currentMacroID = FindMacroByName(GetRuneMacroName(i))
        local legacyMacroID = FindMacroByName(GetLegacyRuneMacroName(i))
        if currentMacroID and legacyMacroID and currentMacroID ~= legacyMacroID then
            DeleteMacro(legacyMacroID)
            deletedCount = deletedCount + 1
            DreadElegyDebug(string.format(
                "[DreadElegy] RuneMacroLegacyDeleted rune=%d macroID=%d name=%s reason=duplicate_current",
                i,
                legacyMacroID,
                GetLegacyRuneMacroName(i)
            ))
        end
    end
    return deletedCount
end

local function RestorePendingRuneMacroDisplayIcon(reason)
    local pending = pendingRuneMacroDisplayRestore
    if not pending then
        return false
    end

    ClearPendingRuneMacroDisplayRestore()

    if InCombatLockdown() then
        MarkRuneMacroSyncPending("combat")
        DreadElegyDebug(string.format(
            "[DreadElegy] RuneMacroDisplayIconRestoreDeferred rune=%d macroID=%d reason=%s displayIconSource=%s",
            pending.runeIndex,
            pending.macroID,
            tostring(reason or "unknown"),
            tostring(pending.displayIconSource or "unknown")
        ))
        return false
    end

    local currentName, currentIcon = GetMacroInfo(pending.macroID)
    if not currentName then
        DreadElegyDebug(string.format(
            "[DreadElegy] RuneMacroDisplayIconRestoreSkipped rune=%d macroID=%d reason=%s missing_macro=true",
            pending.runeIndex,
            pending.macroID,
            tostring(reason or "unknown")
        ))
        return false
    end

    local changed = false
    if currentIcon ~= pending.displayIcon then
        EditMacro(pending.macroID, nil, pending.displayIcon)
        changed = true
    end

    DreadElegyDebug(string.format(
        "[DreadElegy] RuneMacroDisplayIconRestored rune=%d macroID=%d reason=%s icon=%s displayIconSource=%s changed=%s",
        pending.runeIndex,
        pending.macroID,
        tostring(reason or "unknown"),
        tostring(pending.displayIcon),
        tostring(pending.displayIconSource or "unknown"),
        tostring(changed)
    ))
    return true
end

local function PrepareRuneMacroTransportIcon(runeIndex, macroID)
    local transportIcon, dragIconSource = GetRuneMacroTransportIcon(runeIndex)
    local displayIcon, displayIconSource = GetRuneMacroDisplayIcon(runeIndex)
    local _, currentIcon = GetMacroInfo(macroID)
    local changed = false

    if currentIcon ~= transportIcon then
        EditMacro(macroID, nil, transportIcon)
        changed = true
    end

    if displayIcon ~= transportIcon then
        pendingRuneMacroDisplayRestore = {
            runeIndex = runeIndex,
            macroID = macroID,
            displayIcon = displayIcon,
            displayIconSource = displayIconSource,
        }
    else
        ClearPendingRuneMacroDisplayRestore()
    end

    DreadElegyDebug(string.format(
        "[DreadElegy] RuneMacroTransportIconApplied rune=%d macroID=%d icon=%s dragIconSource=%s displayIconSource=%s changed=%s restorePending=%s",
        runeIndex,
        macroID,
        tostring(transportIcon),
        tostring(dragIconSource),
        tostring(displayIconSource),
        tostring(changed),
        tostring(pendingRuneMacroDisplayRestore ~= nil)
    ))
end

local function FindRuneMacro(runeIndex)
    local macroID, scope = FindMacroByName(GetRuneMacroName(runeIndex))
    if macroID then
        return macroID, scope, "current"
    end

    local legacyName = runeIndex <= RUNE_COUNT and GetLegacyRuneMacroName(runeIndex) or nil
    if legacyName and legacyName ~= GetRuneMacroName(runeIndex) then
        macroID, scope = FindMacroByName(legacyName)
        if macroID then
            return macroID, scope, "legacy"
        end
    end

    return nil, nil, nil
end

local function GetRuneMacroStats()
    local numAccount = GetNumMacros()
    local existingCount = 0
    local missingCount = 0

    for i = 1, RUNE_MACRO_COUNT do
        if FindRuneMacro(i) then
            existingCount = existingCount + 1
        else
            missingCount = missingCount + 1
        end
    end

    return existingCount, missingCount, numAccount
end

MarkRuneMacroSyncPending = function(reason)
    if pendingRuneMacroSync then
        return false
    end
    pendingRuneMacroSync = true
    DreadElegyDebug("[DreadElegy] RuneMacroSyncDeferred reason=" .. tostring(reason or "unknown"))
    return true
end

local function SyncRuneMacro(runeIndex, createMissing)
    if not runeIndex or runeIndex < 1 or runeIndex > RUNE_MACRO_COUNT then
        return nil, false, false
    end
    if InCombatLockdown() then
        MarkRuneMacroSyncPending("combat")
        return nil, false, false
    end

    local macroID, scope, origin = FindRuneMacro(runeIndex)
    local macroName = GetRuneMacroName(runeIndex)
    local macroIcon, iconSource = GetRuneMacroDisplayIcon(runeIndex)
    local macroBody = GetRuneMacroBody(runeIndex)

    if macroID then
        local currentName, currentIcon = GetMacroInfo(macroID)
        local currentBody = GetMacroBody(macroID) or ""
        if currentName ~= macroName or currentIcon ~= macroIcon or currentBody ~= macroBody or origin == "legacy" then
            EditMacro(macroID, macroName, macroIcon, macroBody)
            CleanupLegacyRuneMacro(runeIndex, macroID)
            DreadElegyDebug(string.format(
                "[DreadElegy] RuneMacroUpdated rune=%d macroID=%d scope=%s origin=%s name=%s icon=%s iconSource=%s",
                runeIndex,
                macroID,
                tostring(scope or "unknown"),
                tostring(origin or "unknown"),
                macroName,
                tostring(macroIcon),
                tostring(iconSource)
            ))
            return macroID, false, true
        end
        CleanupLegacyRuneMacro(runeIndex, macroID)
        return macroID, false, false
    end

    if not createMissing then
        return nil, false, false
    end

    local numAccount = GetNumMacros()
    if numAccount >= MAX_ACCOUNT_MACROS then
        ShowRuneMacroWarning(L["RUNE_MACRO_SLOTS_FULL"])
        DreadElegyDebug(string.format("[DreadElegy] RuneMacroCreateFailed rune=%d reason=account_slots_full", runeIndex))
        return nil, false, false
    end

    macroID = CreateMacro(macroName, macroIcon, macroBody, false)
    if macroID then
        DreadElegyDebug(string.format(
            "[DreadElegy] RuneMacroCreated rune=%d macroID=%d scope=account name=%s icon=%s iconSource=%s",
            runeIndex,
            macroID,
            macroName,
            tostring(macroIcon),
            tostring(iconSource)
        ))
        return macroID, true, true
    end

    DreadElegyDebug(string.format("[DreadElegy] RuneMacroCreateFailed rune=%d reason=create_macro_nil", runeIndex))
    return nil, false, false
end

local function SyncExistingRuneMacros()
    if InCombatLockdown() then
        MarkRuneMacroSyncPending("combat")
        return false
    end

    for i = 1, RUNE_MACRO_COUNT do
        SyncRuneMacro(i, false)
    end
    return true
end

local function RefreshExistingRuneMacroIcons(reason)
    if InCombatLockdown() then
        pendingRuneMacroIconRefreshReason = reason or "combat"
        DreadElegyDebug("[DreadElegy] RuneMacroStartupIconRefreshDeferred reason=" .. tostring(reason or "combat"))
        return false
    end

    ClearResolvedRuneMacroIconCache()

    local refreshedCount = 0
    local missingCount = 0
    local unresolvedCount = 0
    local unchangedCount = 0
    for i = 1, RUNE_MACRO_COUNT do
        local macroName = GetRuneMacroName(i)
        local macroID, scope = FindMacroByName(macroName)
        if macroID then
            local displayIcon, iconSource = GetRuneMacroDisplayIcon(i)
            if IsRuneMacroDisplayIconUnresolved(i, iconSource) then
                unresolvedCount = unresolvedCount + 1
                DreadElegyDebug(string.format(
                    "[DreadElegy] RuneMacroStartupIconRefreshSkipped rune=%d macroID=%d scope=%s reason=%s iconSource=%s icon_unresolved=true",
                    i,
                    macroID,
                    tostring(scope or "unknown"),
                    tostring(reason or "unknown"),
                    tostring(iconSource)
                ))
            else
                local macroBody = GetRuneMacroBody(i)
                local currentName, currentIcon = GetMacroInfo(macroID)
                local currentBody = GetMacroBody(macroID) or ""
                if currentName ~= macroName or currentIcon ~= displayIcon or currentBody ~= macroBody then
                    EditMacro(macroID, macroName, displayIcon, macroBody)
                    refreshedCount = refreshedCount + 1
                    DreadElegyDebug(string.format(
                        "[DreadElegy] RuneMacroStartupIconRefreshed rune=%d macroID=%d scope=%s icon=%s iconSource=%s reason=%s",
                        i,
                        macroID,
                        tostring(scope or "unknown"),
                        tostring(displayIcon),
                        tostring(iconSource),
                        tostring(reason or "unknown")
                    ))
                else
                    unchangedCount = unchangedCount + 1
                end
            end
        else
            missingCount = missingCount + 1
        end
    end

    if refreshedCount > 0 or unresolvedCount > 0 then
        DreadElegyDebug(string.format(
            "[DreadElegy] RuneMacroStartupIconRefresh reason=%s refreshed=%d unchanged=%d missing=%d unresolved=%d",
            tostring(reason or "unknown"),
            refreshedCount,
            unchangedCount,
            missingCount,
            unresolvedCount
        ))
    end
    return refreshedCount > 0
end

local function ScheduleRuneMacroStartupIconRefresh(reason, delaySec)
    if GetDB().enabled == false then
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delaySec or 0, function()
            if GetDB().enabled ~= false then
                RefreshExistingRuneMacroIcons(reason)
            end
        end)
        return
    end

    RefreshExistingRuneMacroIcons(reason)
end

local function ScheduleRuneMacroStartupIconRefreshes(reason)
    if didScheduleRuneStartupRefresh then
        return
    end

    didScheduleRuneStartupRefresh = true
    for _, delaySec in ipairs(RUNE_MACRO_STARTUP_ICON_REFRESH_DELAYS) do
        ScheduleRuneMacroStartupIconRefresh(
            string.format("%s:%ss", tostring(reason or "startup"), tostring(delaySec)),
            delaySec
        )
    end
end

local function RestoreRuneDragGui(reason)
    local gui = T.GUI
    if gui and runeDragRestoreStrata then
        gui:SetFrameStrata(runeDragRestoreStrata)
    end
    if runeDragRestoreStrata then
        DreadElegyDebug("[DreadElegy] RuneDragGuiRestored reason=" .. tostring(reason or "unknown"))
    end
    runeDragRestoreStrata = nil
end

local function BeginRuneDragGui()
    local gui = T.GUI
    if not gui or not gui:IsShown() or runeDragRestoreStrata then
        return
    end

    runeDragRestoreStrata = gui:GetFrameStrata()
    gui:SetFrameStrata(RUNE_DRAG_TEMP_STRATA)
    DreadElegyDebug(string.format(
        "[DreadElegy] RuneDragGuiLowered from=%s to=%s",
        tostring(runeDragRestoreStrata),
        RUNE_DRAG_TEMP_STRATA
    ))
end

local runeStateFrame

local function OnRuneStateEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingRuneMacroSync then
            pendingRuneMacroSync = false
            SyncExistingRuneMacros()
        end
        if pendingRuneMacroIconRefreshReason then
            local reason = pendingRuneMacroIconRefreshReason
            pendingRuneMacroIconRefreshReason = nil
            RefreshExistingRuneMacroIcons(reason .. ":regen")
        end
    elseif event == "PLAYER_LOGIN" then
        ScheduleRuneMacroStartupIconRefreshes("player_login")
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScheduleRuneMacroStartupIconRefreshes("player_entering_world")
    elseif event == "CURSOR_CHANGED" and runeDragRestoreStrata and not GetCursorInfo() then
        if runeStateFrame then
            runeStateFrame:UnregisterEvent("CURSOR_CHANGED")
        end
        RestoreRuneDragGui("cursor_clear")
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                RestorePendingRuneMacroDisplayIcon("cursor_clear")
            end)
        else
            RestorePendingRuneMacroDisplayIcon("cursor_clear")
        end
    end
end

local function EnsureRuneStateFrame()
    if not runeStateFrame then
        runeStateFrame = CreateFrame("Frame")
        runeStateFrame:SetScript("OnEvent", OnRuneStateEvent)
    end
    return runeStateFrame
end

local function RegisterRuneStateEvents()
    local frame = EnsureRuneStateFrame()
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function UnregisterRuneStateEvents()
    if runeStateFrame then
        runeStateFrame:UnregisterAllEvents()
    end
end

function DreadElegy:GetRuneMeta(runeIndex)
    if runeIndex == RUNE_UNDO_INDEX then
        return L["RUNE_UNDO_DRAG_LABEL"] or POS_NAMES[runeIndex], POS_SYMBOLS[runeIndex], POS_TEXTURES[runeIndex]
    end
    return POS_NAMES[runeIndex], POS_SYMBOLS[runeIndex], POS_TEXTURES[runeIndex]
end

function DreadElegy:HasAllRuneMacros()
    local _, missingCount = GetRuneMacroStats()
    return missingCount == 0
end

function DreadElegy:CreateOrRebuildRuneMacros()
    if InCombatLockdown() then
        T.msg(L["RUNE_MACRO_CREATE_COMBAT"])
        DreadElegyDebug("[DreadElegy] RuneMacroBatchCreateBlocked reason=combat")
        return false
    end

    local deletedLegacyCount = CleanupDuplicateLegacyRuneMacros()

    local existingCount, missingCount, numAccount = GetRuneMacroStats()
    DreadElegyDebug(string.format(
        "[DreadElegy] RuneMacroBatchCreateStart missing=%d existing=%d total=%d deletedLegacy=%d",
        missingCount,
        existingCount,
        numAccount,
        deletedLegacyCount
    ))

    if numAccount + missingCount > MAX_ACCOUNT_MACROS then
        ShowRuneMacroWarning(L["RUNE_MACRO_SLOTS_FULL"])
        DreadElegyDebug(string.format(
            "[DreadElegy] RuneMacroBatchCreateBlocked reason=account_slots_full missing=%d total=%d",
            missingCount,
            numAccount
        ))
        return false
    end

    local createdCount = 0
    local updatedCount = 0
    local allSucceeded = true

    for i = 1, RUNE_MACRO_COUNT do
        local macroID, created, updated = SyncRuneMacro(i, true)
        if not macroID then
            allSucceeded = false
        elseif created then
            createdCount = createdCount + 1
        elseif updated then
            updatedCount = updatedCount + 1
        end
    end

    DreadElegyDebug(string.format(
        "[DreadElegy] RuneMacroBatchCreateDone created=%d updated=%d",
        createdCount,
        updatedCount
    ))

    if allSucceeded then
        T.msg(L["RUNE_MACRO_BATCH_READY"])
        return true
    end

    return false
end

function DreadElegy:CleanupRuneMacros()
    if InCombatLockdown() then
        T.msg(L["RUNE_MACRO_CLEANUP_COMBAT"] or "|cffff0000战斗中无法清理符文宏|r")
        DreadElegyDebug("[DreadElegy] RuneMacroCleanupBlocked reason=combat")
        return false
    end

    ClearPendingRuneMacroDisplayRestore()

    local deletedCount = 0
    local skippedCount = 0
    for i = 1, RUNE_MACRO_COUNT do
        local deleted, reason = DeleteOwnedRuneMacro(i)
        if deleted then
            deletedCount = deletedCount + 1
        elseif reason == "body_mismatch" then
            skippedCount = skippedCount + 1
        end
    end

    T.msg(string.format(L["RUNE_MACRO_CLEANUP_DONE"] or "已清理 %d 个 STT 符文宏。", deletedCount))
    if skippedCount > 0 then
        T.msg(string.format(L["RUNE_MACRO_CLEANUP_SKIPPED"] or "有 %d 个同名宏正文不匹配，已跳过。", skippedCount))
    end
    DreadElegyDebug(string.format("[DreadElegy] RuneMacroCleanupDone deleted=%d skipped=%d", deletedCount, skippedCount))
    return true
end

function DreadElegy:GetRuneMacroPreview(runeIndex)
    if not runeIndex or runeIndex < 1 or runeIndex > RUNE_MACRO_COUNT then
        return nil
    end
    return GetRuneMacroBody(runeIndex)
end

function DreadElegy:RefreshRuneButtons()
    return SyncExistingRuneMacros()
end

function DreadElegy:ApplyChatTypeChange(chatType)
    local db = GetDB()
    local selected = chatType or db.chatType or "raid"
    if not (ChannelSync and ChannelSync.IsValidChatType and ChannelSync.IsValidChatType(selected)) then
        selected = "raid"
    end
    db.chatType = selected
    local refreshed = SyncExistingRuneMacros()
    if ChannelSync and ChannelSync.Send then
        ChannelSync.Send(selected, inEncounter, db.runeRouteMode)
    end
    return refreshed
end

function DreadElegy:PickupRuneMacro(runeIndex)
    if not runeIndex or runeIndex < 1 or runeIndex > RUNE_MACRO_COUNT then
        return false
    end
    if InCombatLockdown() then
        T.msg(L["RUNE_COMBAT_LOCKDOWN"])
        return false
    end

    local macroID = SyncRuneMacro(runeIndex, true)
    if not macroID then
        DreadElegyDebug(string.format("[DreadElegy] RuneMacroPickupBlocked reason=create_failed rune=%d", runeIndex))
        return false
    end

    PrepareRuneMacroTransportIcon(runeIndex, macroID)
    PickupMacro(macroID)
    local cursorType, cursorValue, cursorExtra = GetCursorInfo()
    if cursorType then
        BeginRuneDragGui()
        EnsureRuneStateFrame():RegisterEvent("CURSOR_CHANGED")
    else
        if runeStateFrame then
            runeStateFrame:UnregisterEvent("CURSOR_CHANGED")
        end
        RestoreRuneDragGui("pickup_empty")
        RestorePendingRuneMacroDisplayIcon("pickup_empty")
        DreadElegyDebug(string.format("[DreadElegy] RuneMacroPickupBlocked reason=pickup_empty rune=%d macroID=%d", runeIndex, macroID))
        return false
    end
    DreadElegyDebug(string.format(
        "[DreadElegy] RuneMacroPicked rune=%d macroID=%d cursorType=%s cursorValue=%s cursorExtra=%s",
        runeIndex,
        macroID,
        tostring(cursorType),
        tostring(cursorValue),
        tostring(cursorExtra)
    ))
    return true
end

-- ── UI 元素 ──────────────────────────────────────────────────

-- ── 通信 ─────────────────────────────────────────────────────
local commFrame = nil
local commEventsRegistered = false
local commRegistered = false

local CHAT_EVENT_MAP = {
    CHAT_MSG_RAID = "raid",
    CHAT_MSG_RAID_LEADER = "raid",
    CHAT_MSG_SAY = "say",
    CHAT_MSG_YELL = "yell",
    CHAT_MSG_EMOTE = "emote",
}

local function IsCommRuntimeEnabled()
    local db = GetDB()
    return db.enabled ~= false
end

local function ApproximatelyEqual(a, b, tolerance)
    return type(a) == "number" and math.abs(a - b) <= (tolerance or 0.2)
end

local LURA_DETECTED_DURATIONS = {
    [15] = {
        [1] = { time = 45, phase = 2 },
        [2] = { time = 97, phase = 3 },
        [3] = { time = 180, phase = 4 },
    },
    [16] = {
        [1] = { time = 45, phase = 2 },
        [2] = { time = 97, phase = 3 },
        [3] = { time = 180, phase = 4 },
    },
}

-- ── 鲁拉 encounter-gate：符文阶段窗口机制 ─────────
-- 核心：只在 encounter 3183 的符文阶段窗口期才注册聊天监听，窗口外完全不监听
local RegisterLuraChatEvents
local UnregisterLuraChatEvents
local BeginLuraEncounter
local EndLuraEncounter
local EnterLuraP4
local HandleLuraTimelineEvent
local HandleLuraEngageUnit
local IsLuraP4
local RouteLuraRuneEvent
local ShowChatMirrorAtSlot
local PushLuraRuneRouteHistory

local function CancelLuraP4ResetTimers()
    for i, timer in ipairs(luraP4ResetTimers) do
        if timer and timer.Cancel then timer:Cancel() end
        luraP4ResetTimers[i] = nil
    end
    luraP4ResetTimers = {}
end

RegisterLuraChatEvents = function(reason)
    if luraChatEventsRegistered then return end
    if not commFrame then return end
    commFrame:RegisterEvent("CHAT_MSG_RAID")
    commFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
    commFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
    commFrame:RegisterEvent("CHAT_MSG_SAY")
    commFrame:RegisterEvent("CHAT_MSG_YELL")
    commFrame:RegisterEvent("CHAT_MSG_EMOTE")
    luraChatEventsRegistered = true
end

UnregisterLuraChatEvents = function(reason)
    if not luraChatEventsRegistered then return end
    if GetDB().raidOnly == false and reason ~= "raidOnly=true outside encounter" then
        return
    end
    if commFrame then
        commFrame:UnregisterEvent("CHAT_MSG_RAID")
        commFrame:UnregisterEvent("CHAT_MSG_RAID_LEADER")
        commFrame:UnregisterEvent("CHAT_MSG_RAID_WARNING")
        commFrame:UnregisterEvent("CHAT_MSG_SAY")
        commFrame:UnregisterEvent("CHAT_MSG_YELL")
        commFrame:UnregisterEvent("CHAT_MSG_EMOTE")
    end
    luraChatEventsRegistered = false
    if luraWindowHideTimer then
        luraWindowHideTimer:Cancel()
        luraWindowHideTimer = nil
    end
end

local function CancelLuraWindowTimers(reason)
    for i, timer in ipairs(luraWindowArmTimers) do
        if timer and timer.Cancel then timer:Cancel() end
        luraWindowArmTimers[i] = nil
    end
    luraWindowArmTimers = {}
    if luraWindowHideTimer then
        luraWindowHideTimer:Cancel()
        luraWindowHideTimer = nil
    end
    if luraAbsoluteStopTimer then
        luraAbsoluteStopTimer:Cancel()
        luraAbsoluteStopTimer = nil
    end
    CancelLuraP4ResetTimers()
    DreadElegyDebug("[DreadElegy] LuraTimers canceled reason=" .. tostring(reason or "unknown"))
end

BeginLuraEncounter = function(difficultyID)
    luraEncounterActive = true
    luraDifficultyID = tonumber(difficultyID) or 0
    luraPhase = 1
    luraPhaseSwapTime = GetTime and GetTime() or 0
    CancelLuraWindowTimers("begin_reset")

    local windows = LURA_RUNE_WINDOW_STARTS[luraDifficultyID]
    if not windows then
        DreadElegyDebug("[DreadElegy] LuraEncounter: unsupported difficulty=" .. tostring(luraDifficultyID) .. "，不安排符文窗口")
        return
    end

    for i, startSec in ipairs(windows) do
        local armAt = math.max(0, startSec - LURA_RUNE_WINDOW_PRE_ENABLE)
        luraWindowArmTimers[i] = C_Timer.NewTimer(armAt, function()
            RegisterLuraChatEvents(string.format("window#%d arm@%ds", i, armAt))
        end)
    end

    luraAbsoluteStopTimer = C_Timer.NewTimer(LURA_RUNE_ABSOLUTE_STOP, function()
        UnregisterLuraChatEvents("absolute_stop")
    end)

    DreadElegyDebug(string.format("[DreadElegy] LuraEncounter begin difficulty=%s windows=%s",
        tostring(luraDifficultyID), table.concat(windows, ",")))
end

EndLuraEncounter = function(reason)
    if not luraEncounterActive then return end
    luraEncounterActive = false
    luraDifficultyID = 0
    luraPhase = 1
    luraPhaseSwapTime = 0
    CancelLuraWindowTimers("encounter_end")
    UnregisterLuraChatEvents("encounter_end")
    DreadElegyDebug("[DreadElegy] LuraEncounter end reason=" .. tostring(reason or "unknown"))
end

EnterLuraP4 = function()
    if luraDifficultyID ~= 16 then return end
    DreadElegy:ResetChatMirror()
    if DreadElegy.ApplyLuraDisplayLayout then
        DreadElegy:ApplyLuraDisplayLayout()
    end
    RegisterLuraChatEvents("p4_enter")
    CancelLuraP4ResetTimers()
    for i, sec in ipairs(LURA_P4_RESET_WINDOWS) do
        luraP4ResetTimers[i] = C_Timer.NewTimer(math.max(0, sec - 2), function()
            DreadElegy:ResetChatMirror()
            DreadElegy:HideChatMirror()
            DreadElegyDebug("[DreadElegy] LuraP4 window reset")
        end)
    end
    DreadElegyDebug("[DreadElegy] LuraPhaseEntered phase=4")
end

HandleLuraTimelineEvent = function(event, info)
    if not luraEncounterActive or type(info) ~= "table" then return end
    if event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then return end

    local now = GetTime and GetTime() or 0
    if not luraPhaseSwapTime or not (now > luraPhaseSwapTime + 5) then return end

    local phaseInfo = LURA_DETECTED_DURATIONS[luraDifficultyID] and LURA_DETECTED_DURATIONS[luraDifficultyID][luraPhase]
    if not phaseInfo or not ApproximatelyEqual(tonumber(info.duration), phaseInfo.time, 0.2) then return end

    if phaseInfo.phase <= luraPhase then return end
    luraPhase = phaseInfo.phase
    luraPhaseSwapTime = now
    DreadElegyDebug(string.format("[DreadElegy] LuraPhaseChanged phase=%d duration=%s", luraPhase, tostring(info.duration)))

    if luraPhase == 4 then
        EnterLuraP4()
    elseif luraPhase == 2 then
        UnregisterLuraChatEvents("phase2")
        DreadElegy:ResetChatMirror()
        DreadElegy:HideChatMirror()
    end
end

HandleLuraEngageUnit = function()
    if not luraEncounterActive or luraDifficultyID ~= 16 or luraPhase ~= 4 then return end
    local now = GetTime and GetTime() or 0
    if not luraPhaseSwapTime or not (now > luraPhaseSwapTime + 20) then return end
    if not UnitExists("boss2") then
        luraPhase = 5
        luraPhaseSwapTime = now
        UnregisterLuraChatEvents("phase5")
        DreadElegy:ResetChatMirror()
        DreadElegy:HideChatMirror()
        DreadElegyDebug("[DreadElegy] LuraPhaseChanged phase=5")
    end
end

local function GetLuraRuneSenderMeta(sender)
    local shortSender
    if sender and Ambiguate then
        local ok, value = pcall(Ambiguate, sender, "short")
        if ok then shortSender = value end
    else
        shortSender = sender
    end

    local senderKey = "sender_unknown"
    if shortSender then
        local ok, value = pcall(function()
            return table.concat({ shortSender }, "")
        end)
        if ok and value and value ~= "" then
            shortSender = value
            senderKey = value
        else
            shortSender = nil
        end
    end

    local okSame, sameAsPrev = pcall(function()
        return lastLuraRuneSenderKey == senderKey
    end)
    if not okSame then
        senderKey = "sender_unknown"
        sameAsPrev = false
    end
    lastLuraRuneSenderKey = senderKey

    local raidIndex, rank, role, combatRole, assignedRole
    if IsInRaid() then
        for i = 1, MAX_RAID_MEMBERS do
            local name, rosterRank, _, _, _, _, _, _, _, rosterRole, _, rosterCombatRole = GetRaidRosterInfo(i)
            local unit = "raid" .. i
            local matched = false
            if shortSender and name and Ambiguate then
                local ok, value = pcall(function()
                    return Ambiguate(name, "short") == shortSender
                end)
                matched = ok and value
            end
            if matched then
                raidIndex = i
                rank = rosterRank
                role = rosterRole
                combatRole = rosterCombatRole
                if UnitGroupRolesAssigned then
                    local ok, value = pcall(UnitGroupRolesAssigned, unit)
                    if ok then assignedRole = value end
                end
                break
            end
        end
    end

    return {
        shortSender = shortSender,
        senderKey = senderKey,
        raidIndex = raidIndex,
        rank = rank,
        role = role,
        combatRole = combatRole,
        assignedRole = assignedRole,
        sameAsPrev = sameAsPrev,
    }
end

local function EnsureCommFrame()
    if commFrame then
        return commFrame
    end

    commFrame = CreateFrame("Frame")
    commFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, ...)
        if CHAT_EVENT_MAP[event] then
            if not IsCommRuntimeEnabled() then return end
            -- raidOnly=true（默认）：只在鲁拉 encounter 符文窗口期收到的消息才渲染
            -- raidOnly=false：调试/测试用，无门槛
            if GetDB().raidOnly ~= false and not luraEncounterActive then return end
            local expectedType = GetDB().chatType or "raid"
            local eventType = CHAT_EVENT_MAP[event]
            local sender = arg2
            local senderMeta = GetLuraRuneSenderMeta(sender)
            local routedSlot, routeHandled, routeMode, senderSlot, senderCount = RouteLuraRuneEvent(event, senderMeta)
            if routedSlot then
                ShowChatMirrorAtSlot(arg1, routedSlot)
                PushLuraRuneRouteHistory({
                    slot = routedSlot,
                    mode = routeMode,
                    senderKey = senderMeta and senderMeta.senderKey,
                    senderSlot = senderSlot,
                    senderCount = senderCount,
                })
                -- 收到一条后启动兜底关窗 timer
                if luraEncounterActive then
                    if luraWindowHideTimer then luraWindowHideTimer:Cancel() end
                    local hideAfter = (luraPhase == 4) and LURA_RUNE_HIDE_AFTER_MSG_P4 or LURA_RUNE_HIDE_AFTER_MSG
                    luraWindowHideTimer = C_Timer.NewTimer(hideAfter, function()
                        DreadElegy:ResetChatMirror()
                        DreadElegy:HideChatMirror()
                        if not IsLuraP4() then
                            UnregisterLuraChatEvents("hide_timeout")
                        end
                    end)
                end
            elseif (not routeHandled) and eventType == expectedType then
                DreadElegy:ShowChatMirror(arg1)
                -- 收到一条后启动兜底关窗 timer
                if luraEncounterActive then
                    if luraWindowHideTimer then luraWindowHideTimer:Cancel() end
                    local hideAfter = (luraPhase == 4) and LURA_RUNE_HIDE_AFTER_MSG_P4 or LURA_RUNE_HIDE_AFTER_MSG
                    luraWindowHideTimer = C_Timer.NewTimer(hideAfter, function()
                        DreadElegy:ResetChatMirror()
                        DreadElegy:HideChatMirror()
                        if not IsLuraP4() then
                            UnregisterLuraChatEvents("hide_timeout")
                        end
                    end)
                end
            end

        elseif event == "CHAT_MSG_RAID_WARNING" then
            if not IsCommRuntimeEnabled() then return end
            if GetDB().raidOnly ~= false and not luraEncounterActive then return end
            DreadElegy:UndoLastChatMirrorSlot()

        elseif event == "ENCOUNTER_START" then
            inEncounter = true
            local encounterID = tonumber(arg1)
            local difficultyID = tonumber(arg3)
            DreadElegyDebug(string.format(
                "[DreadElegy] EncounterStarted encounterID=%s difficulty=%s",
                tostring(encounterID or "nil"),
                tostring(difficultyID or "nil")
            ))
            if encounterID == LURA_ENCOUNTER_ID then
                BeginLuraEncounter(difficultyID or 0)
            elseif GetDB().raidOnly == false then
                DreadElegy:ResetChatMirror()
                DreadElegy:HideChatMirror()
            end

        elseif event == "ENCOUNTER_END" then
            inEncounter = false
            local encounterID = tonumber(arg1)
            local keepDebugMirror = GetDB().raidOnly == false and encounterID ~= LURA_ENCOUNTER_ID
            if not keepDebugMirror then
                DreadElegy:ResetChatMirror()
                DreadElegy:HideChatMirror()
            end
            EndLuraEncounter("encounter_end_event")
            DreadElegyDebug("[DreadElegy] EncounterEnded keepDebugMirror=" .. tostring(keepDebugMirror))
            if displaySequence and #displaySequence > 0 then
                C_Timer.After(1.0, function()
                    BroadcastRuneOrder(displaySequence)
                    DreadElegyDebug("[DreadElegy] encounter结束，自动重同步")
                end)
            end
        elseif event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
            HandleLuraTimelineEvent(event, arg1)
        elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            HandleLuraEngageUnit()
        end
    end)
    if T.Comm and not commRegistered then
        local ok, err = T.Comm:Register("dreadElegy", "legacy", function(payload, sender, meta)
            if not IsCommRuntimeEnabled() then return end
            if type(payload) ~= "table" or payload.type ~= "legacy" or type(payload.message) ~= "string" then
                return
            end
            local channel = meta and meta.channel or nil
            DreadElegy:OnAddonMessage(payload.message, channel, sender)
        end)
        commRegistered = ok == true
        if not ok then
            DreadElegyDebug("[DreadElegy] CommRegisterFailed err=" .. tostring(err))
        end
    end
    return commFrame
end

local function UpdateCommRegistration(reason)
    if not IsCommRuntimeEnabled() then
        if commFrame and commEventsRegistered then
            commFrame:UnregisterAllEvents()
            commEventsRegistered = false
        end
        inEncounter = false
        EndLuraEncounter("runtime_disable")
        luraChatEventsRegistered = false
        DreadElegy:ResetChatMirror()
        DreadElegy:HideChatMirror()
        return false
    end

    local frame = EnsureCommFrame()
    if not frame then
        return false
    end
    if not commEventsRegistered then
        -- 永久注册 encounter 状态事件；插件通信由 T.Comm 统一接管
        frame:RegisterEvent("ENCOUNTER_START")
        frame:RegisterEvent("ENCOUNTER_END")
        frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
        frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        commEventsRegistered = true
    end

    -- 聊天事件注册策略：
    -- raidOnly=true（默认）：由 BeginLuraEncounter 的 timer 动态注册/注销
    -- raidOnly=false（调试）：永久注册，让非 encounter 环境也能测试
    local db = GetDB()
    if db.raidOnly == false then
        if not luraChatEventsRegistered then
            RegisterLuraChatEvents("raidOnly=false global")
        end
    else
        -- raidOnly=true 时：如果不在 encounter 窗口但之前是 global 注册状态，撤回
        if luraChatEventsRegistered and not luraEncounterActive then
            UnregisterLuraChatEvents("raidOnly=true outside encounter")
        end
    end
    return true
end

local function InitComm()
    return UpdateCommRegistration("init")
end

-- ── 发送 ─────────────────────────────────────────────────────
local function CancelPendingBroadcast()
    if pendingBroadcastTimer then
        pendingBroadcastTimer:Cancel()
        pendingBroadcastTimer = nil
    end
end

local function BroadcastMessage(msg)
    if not IsInRaid() and not IsInGroup() then return false end

    if not T.Comm then
        DreadElegyDebug("[DreadElegy] addon广播失败: missing T.Comm")
        return false
    end
    local ok, err = T.Comm:Send("dreadElegy", "legacy", { type = "legacy", message = msg }, { target = "group", prio = "ALERT" })
    if ok then
        CancelPendingBroadcast()
        return true
    end

    DreadElegyDebug("[DreadElegy] addon广播失败 err=" .. tostring(err) .. " msg=" .. msg)

    return false
end

local function BroadcastRuneOrder(sequence)
    local msg = "R:" .. table.concat(sequence, ",") .. ":" .. math.floor(GetTime())
    return BroadcastMessage(msg)
end


local function BroadcastReset()
    local msg = "C:" .. math.floor(GetTime())
    return BroadcastMessage(msg)
end

-- ── 权限验证（复用） ────────────────────────────────────────
local function IsLeaderOrAssist(sender)
    local shortSender = Ambiguate(sender, "short")
    if IsInRaid() then
        for i = 1, MAX_RAID_MEMBERS do
            local name, rank = GetRaidRosterInfo(i)
            if name then
                if Ambiguate(name, "short") == shortSender then
                    return rank and rank >= 1
                end
            end
        end
        return false
    else
        return UnitIsGroupLeader(shortSender)
    end
end

-- ── 接收 ─────────────────────────────────────────────────────
function DreadElegy:OnAddonMessage(message, channel, sender)
    -- 忽略自己的广播回传
    if Ambiguate(sender, "short") == T.PlayerName then return end

    if ChannelSync and ChannelSync.HandleAddonMessage and ChannelSync.HandleAddonMessage(message, channel, sender) then
        return
    end

    local proto, data, ts = strsplit(":", message)

    if not IsLeaderOrAssist(sender) then
        DreadElegyDebug("[DreadElegy] 忽略非团长/助手: " .. tostring(sender))
        return
    end

    if proto == "R" and data then
        -- 符文顺序
        local runes = { strsplit(",", data) }
        if #runes < 1 or #runes > RUNE_COUNT then return end
        local sequence = {}
        for i, v in ipairs(runes) do
            local n = tonumber(v)
            if not n or n < 1 or n > RUNE_COUNT then return end
            sequence[i] = n
        end
        displaySender = Ambiguate(sender, "short")
        DreadElegy:ShowRuneOrder(sequence)
    end
end

-- 给 options 的 raidOnly check 切换用：重跑注册策略
function DreadElegy:ApplyRaidOnlyChange()
    UpdateCommRegistration("raidOnly_toggle")
end

function DreadElegy:ApplyRuneRouteModeChange()
    local db = GetDB()
    db.runeRouteMode = NormalizeRuneRouteMode(db.runeRouteMode)
    DreadElegy:ResetChatMirror()
    if ChannelSync and ChannelSync.Send then
        ChannelSync.Send(db.chatType, inEncounter, db.runeRouteMode)
    end
end


-- 兼容存根
SchedulePendingBroadcast = function() end
function DreadElegy:ShowRuneOrder() end
function DreadElegy:HideRuneOrder() end

-- ── Chat Mirror（encounter 中不解析 secret value，直接 SetText 渲染）──
-- 原理：不解析聊天内容，按收到顺序依次放到圆形 5 个位置。
--       第 1 条消息 → 位置 1，第 2 条 → 位置 2，以此类推。

local chatMirrorSlots = {}   -- 5 个 FontString 槽位
local chatMirrorOrders = {}  -- 5 个序号标签
local chatMirrorGuides = {}  -- 2/3/5 位置的分场提示背景
local chatMirrorCount = 0    -- 当前已填充到第几个

-- ChatMirror 用的圆形布局常量（与主显示完全一致）
local CM_CENTER_Y = 10       -- 圆心 Y 偏移，与主显示的 +10 一致

local function GetChatMirrorSlotIndex(logicalIndex)
    return logicalIndex
end

local function IsLuraTankView()
    return UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") == "TANK"
end

RefreshChatMirrorOrderLabels = function()
    local routedMode = next(luraRoutedSlots) ~= nil
    for logicalIndex = 1, RUNE_COUNT do
        local visualIndex = GetChatMirrorSlotIndex(logicalIndex)
        local order = chatMirrorOrders[visualIndex]
        if order then
            order:SetText(logicalIndex)
            if (routedMode and luraRoutedSlots[logicalIndex]) or ((not routedMode) and logicalIndex <= chatMirrorCount) then
                order:SetTextColor(1, 0.82, 0)
            else
                order:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
end

IsLuraP4 = function()
    return luraDifficultyID == 16 and luraPhase == 4
end

RouteLuraRuneEvent = function(event, senderMeta)
    local mode = NormalizeRuneRouteMode(GetDB().runeRouteMode)
    if mode == RUNE_ROUTE_MODE_SEQUENTIAL then
        return nil, false, mode
    end

    -- 横条阶段不区分团长/团员，统一按收到顺序显示。
    if IsLuraP4() then
        return nil, false, mode
    end

    local debugRouting = GetDB().raidOnly == false
    if not debugRouting and (not luraEncounterActive or luraDifficultyID ~= 16) then
        return nil, false, mode
    end

    if mode == RUNE_ROUTE_MODE_EVENT and event == "CHAT_MSG_RAID_LEADER" then
        local slot = luraRoutedSlots[1] and 4 or 1
        luraRoutedSlots[slot] = true
        return slot, true, mode
    elseif mode == RUNE_ROUTE_MODE_EVENT and event == "CHAT_MSG_RAID" then
        local slot = 2
        if luraRoutedSlots[slot] then slot = 3 end
        if luraRoutedSlots[slot] then slot = 5 end
        luraRoutedSlots[slot] = true
        return slot, true, mode
    end

    return nil, false, mode
end

function DreadElegy:ApplyLuraDisplayLayout()
    local f = chatMirrorFrame
    if not f then return end

    local p4 = IsLuraP4()
    local tankView = (not p4) and IsLuraTankView()
    f:SetWidth(p4 and 300 or CONTAINER_SIZE)
    f:SetHeight(p4 and 60 or (CONTAINER_SIZE + 30))

    if f.bossIcon then
        f.bossIcon:SetShown(not p4)
    end
    if f.bossLabel then
        f.bossLabel:SetShown(not p4)
    end
    if f.resetBtn then
        f.resetBtn:SetShown(not p4)
    end

    for i = 1, RUNE_COUNT do
        local guide = chatMirrorGuides[i]
        local slot = chatMirrorSlots[i]
        local order = chatMirrorOrders[i]
        if guide then guide:ClearAllPoints() end
        if slot then slot:ClearAllPoints() end
        if order then order:ClearAllPoints() end

        if p4 then
            if guide then guide:Hide() end
            if slot then slot:SetPoint("LEFT", f, "LEFT", (i - 1) * 60, 0) end
            if order then order:SetPoint("LEFT", f, "LEFT", (i - 1) * 60 + 22, 30) end
        else
            local angle = POS_ANGLES[i] or ((i - 1) * 72)
            local rad = math.rad(angle)
            local x = math.sin(rad) * RING_RADIUS
            local y = math.cos(rad) * RING_RADIUS
            if tankView then
                x = x * -1
                y = y * -1
            end
            if guide then
                guide:SetPoint("CENTER", f, "CENTER", x, y + CM_CENTER_Y)
                guide:Show()
            end
            if slot then slot:SetPoint("CENTER", f, "CENTER", x, y + CM_CENTER_Y) end
            if order then order:SetPoint("TOP", slot, "BOTTOM", 0, -2) end
        end
    end
end

local function CreateChatMirrorFrame()
    if chatMirrorFrame then return chatMirrorFrame end

    local f = CreateFrame("Frame", "STT_DreadElegyChatMirror", UIParent, "BackdropTemplate")
    f:SetSize(CONTAINER_SIZE, CONTAINER_SIZE + 30)
    local db = GetDB()
    if db.panelPos then
        f:SetPoint(db.panelPos.point, UIParent, db.panelPos.relPoint, db.panelPos.x, db.panelPos.y)
    else
        f:SetPoint(DEFAULT_PANEL_POS.point, UIParent, DEFAULT_PANEL_POS.relPoint, DEFAULT_PANEL_POS.x, DEFAULT_PANEL_POS.y)
    end
    f:SetScale(db.panelScale or 1)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0, 0, 0, GetPanelBackdropAlpha())
    f:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then self:Hide() end
    end)

    -- 标题
    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    label:SetPoint("TOP", f, "TOP", 0, -4)
    label:SetTextColor(1, 0.82, 0)
    label:SetText("STT - 鲁拉符文顺序")
    f.label = label

    -- 计数器（右上角）
    local counter = f:CreateFontString(nil, "OVERLAY")
    counter:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    counter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -4)
    counter:SetTextColor(0.6, 0.6, 0.6)
    counter:SetText("0/5")
    f.counter = counter

    -- 关闭按钮（右上角）
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- 重置按钮（右下角，与侧栏重置按钮一致的 Atlas 图标）
    local resetBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    resetBtn:SetSize(SIDEBAR_BTN_SIZE, SIDEBAR_BTN_SIZE)
    resetBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 24)
    resetBtn:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    resetBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    resetBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
    local resetIcon = resetBtn:CreateTexture(nil, "ARTWORK")
    resetIcon:SetSize(SIDEBAR_BTN_SIZE - 8, SIDEBAR_BTN_SIZE - 8)
    resetIcon:SetPoint("CENTER")
    resetIcon:SetAtlas("transmog-icon-revert")
    resetBtn:SetScript("OnClick", function()
        DreadElegy:ResetChatMirror()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("重置符文显示", 1, 1, 1)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
        GameTooltip:Hide()
    end)

    -- BOSS 中心图标（与主显示完全一致：lura.tga + "BOSS"文字覆盖）
    local bossIcon = f:CreateTexture(nil, "ARTWORK", nil, 0)
    bossIcon:SetSize(ICON_SIZE * 1.25, ICON_SIZE * 1.25)
    bossIcon:SetPoint("CENTER", f, "CENTER", 0, CM_CENTER_Y)
    bossIcon:SetTexture("Interface\\AddOns\\ShengTangTools\\media\\lura.tga")
    bossIcon:SetAlpha(0.85)
    f.bossIcon = bossIcon

    local bossLabel = f:CreateFontString(nil, "OVERLAY")
    bossLabel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    bossLabel:SetPoint("CENTER", bossIcon, "CENTER", 0, 0)
    bossLabel:SetTextColor(1, 1, 1)
    bossLabel:SetText("BOSS")
    f.bossLabel = bossLabel

    -- 5 个圆形位置的 FontString 槽位（与主显示 ShowRuneOrder 完全一致的位置公式）
    for i = 1, RUNE_COUNT do
        local guideColor = RUNE_GUIDE_BACKGROUNDS[i]
        if guideColor then
            local guide = f:CreateTexture(nil, "BORDER")
            guide:SetTexture(RUNE_GUIDE_BG_TEXTURE)
            guide:SetSize(RUNE_GUIDE_BG_SIZE, RUNE_GUIDE_BG_SIZE)
            guide:SetVertexColor(guideColor[1], guideColor[2], guideColor[3], guideColor[4])
            chatMirrorGuides[i] = guide
        end

        -- 内容显示（不解析，直接 SetText 透传）
        local slot = f:CreateFontString(nil, "OVERLAY")
        slot:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
        slot:SetJustifyH("CENTER")
        slot:SetTextColor(1, 1, 1)
        slot:SetText("")
        slot:Hide()
        chatMirrorSlots[i] = slot

        -- 序号标签（位置编号，始终显示）
        local order = f:CreateFontString(nil, "OVERLAY")
        order:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
        order:SetTextColor(0.5, 0.5, 0.5)
        order:SetText(i)
        chatMirrorOrders[i] = order
    end

    f.resetBtn = resetBtn
    DreadElegy:ApplyLuraDisplayLayout()
    RefreshChatMirrorOrderLabels()

    -- 倒计时标签（左下角）
    local countdown = f:CreateFontString(nil, "OVERLAY")
    countdown:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    countdown:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 6)
    countdown:SetTextColor(0.7, 0.7, 0.7)
    countdown:SetText("")
    f.countdown = countdown

    -- 缩放角标（右下角，仅解锁时显示）
    local resizer = CreateFrame("Button", nil, f)
    resizer:SetSize(18, 18)
    resizer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or GetDB().locked ~= false then return end
        local cx, cy = GetCursorPosition()
        self.startX = cx
        self.startY = cy
        self.startScale = f:GetScale()
        self:SetScript("OnUpdate", function(self)
            local nx, ny = GetCursorPosition()
            local ues = UIParent:GetEffectiveScale()
            local dx = (nx - self.startX) / ues
            local dy = (self.startY - ny) / ues
            local delta = (dx + dy) / 200
            local newScale = math.max(0.5, math.min(2.0, self.startScale + delta))
            f:SetScale(newScale)
        end)
    end)
    resizer:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        GetDB().panelScale = f:GetScale()
    end)
    f.resizer = resizer
    if GetDB().locked ~= false then
        resizer:Hide()
    end

    f:Hide()
    chatMirrorFrame = f

    if T.EditMode and T.EditMode.Register then
        local editEntry = T.EditMode:Register({
            frame = f,
            displayName = "鲁拉符文面板",
            saveFunc = function(point, relPoint, x, y)
                GetDB().panelPos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            group = "solo",
        })
        if editEntry and editEntry.overlay then
            resizer:SetFrameStrata(editEntry.overlay:GetFrameStrata())
            resizer:SetFrameLevel(editEntry.overlay:GetFrameLevel() + 1)
        end
    end

    return f
end

local function GetAutoHideSeconds()
    if IsLuraP4() then
        return LURA_RUNE_HIDE_AFTER_MSG_P4
    end
    return GetDB().autoHideSeconds or 10
end
local cmCountdownTimer = nil   -- C_Timer ticker
local cmHideTimer = nil        -- C_Timer 最终隐藏
local cmSecondsLeft = 0

local function StopChatMirrorTimers()
    if cmCountdownTimer then cmCountdownTimer:Cancel(); cmCountdownTimer = nil end
    if cmHideTimer then cmHideTimer:Cancel(); cmHideTimer = nil end
    cmSecondsLeft = 0
    if chatMirrorFrame and chatMirrorFrame.countdown then
        chatMirrorFrame.countdown:SetText("")
    end
end

local function StartChatMirrorAutoHide()
    StopChatMirrorTimers()
    local seconds = GetAutoHideSeconds()
    cmSecondsLeft = seconds

    if chatMirrorFrame and chatMirrorFrame.countdown then
        chatMirrorFrame.countdown:SetText(cmSecondsLeft .. "秒后消失...")
    end

    cmCountdownTimer = C_Timer.NewTicker(1, function()
        cmSecondsLeft = cmSecondsLeft - 1
        if cmSecondsLeft > 0 and chatMirrorFrame and chatMirrorFrame.countdown then
            chatMirrorFrame.countdown:SetText(cmSecondsLeft .. "秒后消失...")
        end
    end, seconds - 1)

    cmHideTimer = C_Timer.NewTimer(seconds, function()
        DreadElegy:ResetChatMirror()
        DreadElegy:HideChatMirror()
    end)
end

PushLuraRuneRouteHistory = function(entry)
    if type(entry) ~= "table" or not entry.slot then return end
    luraRuneRouteHistory[#luraRuneRouteHistory + 1] = entry
end

function DreadElegy:ShowChatMirror(text)
    local f = CreateChatMirrorFrame()
    DreadElegy:ApplyLuraDisplayLayout()

    chatMirrorCount = chatMirrorCount + 1
    if chatMirrorCount > RUNE_COUNT then return end  -- 最多 5 条

    if GetDB().announceNumberOnShow then
        PlayRunePointSound(chatMirrorCount)
    end

    local slotIndex = GetChatMirrorSlotIndex(chatMirrorCount)
    local slot = chatMirrorSlots[slotIndex]
    -- |T 纹理渲染：text 可能是 secret value，string.format 对 secret 允许操作，
    -- C++ 渲染引擎解析 |T 时直接读字节流，不受 Lua secret 限制
    pcall(function() slot:SetFormattedText("|T%s:38:38|t", text) end)
    slot:SetTextColor(1, 1, 1)
    slot:Show()
    PushLuraRuneRouteHistory({ slot = chatMirrorCount, mode = RUNE_ROUTE_MODE_SEQUENTIAL })

    RefreshChatMirrorOrderLabels()

    -- 更新计数器
    pcall(function() f.counter:SetText(chatMirrorCount .. "/5") end)

    f:Show()

    -- 每次收到新消息重置倒计时
    StartChatMirrorAutoHide()

end

ShowChatMirrorAtSlot = function(text, slotIndex)
    local slot = tonumber(slotIndex)
    if not slot or slot < 1 or slot > RUNE_COUNT then return end

    local f = CreateChatMirrorFrame()
    DreadElegy:ApplyLuraDisplayLayout()

    if GetDB().announceNumberOnShow then
        PlayRunePointSound(slot)
    end

    local visualIndex = GetChatMirrorSlotIndex(slot)
    local slotFrame = chatMirrorSlots[visualIndex]
    pcall(function() slotFrame:SetFormattedText("|T%s:38:38|t", text) end)
    slotFrame:SetTextColor(1, 1, 1)
    slotFrame:Show()

    chatMirrorCount = math.min(chatMirrorCount + 1, RUNE_COUNT)
    RefreshChatMirrorOrderLabels()
    pcall(function() f.counter:SetText(chatMirrorCount .. "/5") end)
    f:Show()
    StartChatMirrorAutoHide()

end

function DreadElegy:UndoLastChatMirrorSlot()
    local entry = table.remove(luraRuneRouteHistory)
    if not entry then return nil end

    local slot = tonumber(entry.slot)
    if slot and slot >= 1 and slot <= RUNE_COUNT then
        local visualIndex = GetChatMirrorSlotIndex(slot)
        local slotFrame = chatMirrorSlots[visualIndex]
        if slotFrame then
            slotFrame:SetText("")
            slotFrame:Hide()
        end
        luraRoutedSlots[slot] = nil
    end

    chatMirrorCount = math.max((tonumber(chatMirrorCount) or 0) - 1, 0)

    RefreshChatMirrorOrderLabels()
    if chatMirrorFrame and chatMirrorFrame.counter then
        chatMirrorFrame.counter:SetText(chatMirrorCount .. "/5")
    end
    return entry
end

function DreadElegy:ResetChatMirror()
    StopChatMirrorTimers()
    chatMirrorCount = 0
    luraRoutedSlots = {}
    luraRuneRouteHistory = {}
    lastLuraRuneSenderKey = nil
    for i = 1, RUNE_COUNT do
        if chatMirrorSlots[i] then
            chatMirrorSlots[i]:SetText("")
            chatMirrorSlots[i]:Hide()
        end
    end
    RefreshChatMirrorOrderLabels()
    if chatMirrorFrame and chatMirrorFrame.counter then
        chatMirrorFrame.counter:SetText("0/5")
    end
end

function DreadElegy:HideChatMirror()
    if chatMirrorFrame then chatMirrorFrame:Hide() end
end

-- ── TTS 播报 ─────────────────────────────────────────────────
function DreadElegy:AnnounceRuneOrder(sequence)
    if not (C.DB and C.DB.ttsEnabled) then return end
    local nums = {}
    for i, runeId in ipairs(sequence) do
        nums[i] = tostring(runeId)
    end
    local text = "符文顺序：" .. table.concat(nums, "，")
    if T.TTSQueue and T.TTSQueue.Speak then
        T.TTSQueue:Speak(text)
    elseif C_VoiceChat and C_VoiceChat.SpeakText then
        local voiceID = C.DB.ttsVoiceID or 0
        local rate = C.DB.ttsRate or 0
        local volume = C.DB.ttsVolume or 100
        C_VoiceChat.SpeakText(voiceID, text, 0, rate, volume)
    end
end

-- ── 锁定与缩放 ──────────────────────────────────────────────
function DreadElegy:IsLocked()
    return GetDB().locked ~= false
end

function DreadElegy:SetLocked(locked)
    GetDB().locked = locked and true or false
    if not locked then
        -- 解锁时确保面板可见，停止自动消失，给 300 秒方便调整
        local f = CreateChatMirrorFrame()
        StopChatMirrorTimers()
        f:Show()
        f.resizer:Show()
        if T.EditMode and T.EditMode.Enter then
            T.EditMode:Enter(f)
        end
        -- 300 秒后自动锁定+隐藏，防止玩家忘记
        cmHideTimer = C_Timer.NewTimer(300, function()
            DreadElegy:SetLocked(true)
            DreadElegy:HideChatMirror()
        end)
    elseif chatMirrorFrame then
        if T.EditMode and T.EditMode.Exit then
            T.EditMode:Exit(chatMirrorFrame)
        end
        chatMirrorFrame.resizer:Hide()
        chatMirrorFrame:Hide()
        StopChatMirrorTimers()
    end
    T.msg("符文面板 " .. (locked and "|cff00ff00已锁定|r" or "|cffff9900已解锁|r"))
end

function DreadElegy:ResetPanelPosition()
    local db = GetDB()
    db.panelPos = nil
    db.panelScale = 1.0
    if chatMirrorFrame then
        chatMirrorFrame:ClearAllPoints()
        chatMirrorFrame:SetPoint(DEFAULT_PANEL_POS.point, UIParent, DEFAULT_PANEL_POS.relPoint, DEFAULT_PANEL_POS.x, DEFAULT_PANEL_POS.y)
        chatMirrorFrame:SetScale(1.0)
    end
    T.msg("符文面板位置已重置")
end

function DreadElegy:ApplyPanelBackdropOpacity()
    ApplyPanelBackdropOpacity()
end

-- ── 命令入口 ─────────────────────────────────────────────────
function DreadElegy:HandleCommand(args)
    if args == "clear" then
        DreadElegy:ResetChatMirror()
        DreadElegy:HideChatMirror()
        T.msg("符文显示已清除")

    elseif args == "test" then
        DreadElegy:ResetChatMirror()
        for i = 1, RUNE_COUNT do
            DreadElegy:ShowChatMirror(GetRuneChatCode(i))
        end
        T.msg("符文顺序测试显示（发送格式：|cff00ff00路径|r）")

    elseif args == "macro" then
        T.msg(L["RUNE_MACRO_DEPRECATED"])
        T.msg(L["RUNE_MACRO_USE_DRAG"])

    else
        T.msg("用法:")
        T.msg("  /st rune clear — 清除符文显示")
        T.msg("  /st rune test — 测试显示")
        T.msg("  /st rune macro — 已弃用，改为设置页直接拖拽符文宏")
    end
end

T.HandleDreadElegyCommand = function(args)
    DreadElegy:HandleCommand(args)
end

function DreadElegy:OnRegister()
    T.DreadElegy = self
end

function DreadElegy:OnEnable()
    RegisterRuneStateEvents()
    InitComm()
    if GetDB().enabled ~= false then
        SyncExistingRuneMacros()
    end
end

function DreadElegy:OnDisable()
    UnregisterRuneStateEvents()
    UpdateCommRegistration("module_disable")
    EndLuraEncounter("module_disable")
    self:ResetChatMirror()
    self:HideChatMirror()
    RestoreRuneDragGui("module_disable")
    RestorePendingRuneMacroDisplayIcon("module_disable")
end

end)
