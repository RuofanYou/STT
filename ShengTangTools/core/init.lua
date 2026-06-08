-- 初始化方式
local addon, ns = ...
ns[1] = {} -- T, functions, constants, variables
ns[2] = {} -- C, config
ns[3] = {} -- L, localization

STT = ns

local T, C, L = unpack(select(2, ...))

-- 全局信息
T.addon_name = addon
T.addon_cname = select(2, C_AddOns.GetAddOnInfo(addon))
T.Client = GetLocale()
-- 版本号以 TOC 为单一权威（DRY）
do
    local ver = nil
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        ver = C_AddOns.GetAddOnMetadata(addon, "Version")
    elseif GetAddOnMetadata then
        ver = GetAddOnMetadata(addon, "Version")
    end
    T.Version = ver or "dev"
end

T.PlayerName = UnitName("player")
T.PlayerGUID = UnitGUID("player")
T.RuntimeColdFeatures = T.RuntimeColdFeatures or {}

local function ReadRawSavedPath(path)
    local current = type(STT_DB) == "table" and STT_DB or nil
    if type(path) ~= "string" or path == "" then
        return nil
    end
    for key in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
    end
    return current
end

function T.ShouldLoadFeature(path, defaultEnabled)
    if T.RuntimeColdFeatures and T.RuntimeColdFeatures[path] == true then
        return true
    end
    local value = ReadRawSavedPath(path)
    if value == nil then
        return defaultEnabled == true
    end
    return value == true
end

function T.ActivateColdFeature(path)
    if type(path) ~= "string" or path == "" then
        return 0
    end
    T.RuntimeColdFeatures[path] = true
    if T.LoadColdFilesForDesired then
        return T.LoadColdFilesForDesired()
    end
    return 0
end

function T.ShouldLoadAnyFeature(paths)
    if type(paths) ~= "table" then
        return false
    end
    for _, entry in ipairs(paths) do
        if type(entry) == "table" then
            if T.ShouldLoadFeature(entry[1], entry[2] == true) then
                return true
            end
        elseif T.ShouldLoadFeature(entry, false) then
            return true
        end
    end
    return false
end

T.ColdFiles = T.ColdFiles or {
    order = {},
}

local function NormalizeColdFeatureSpec(featureSpec)
    if type(featureSpec) == "string" then
        return { featureSpec }
    end
    if type(featureSpec) == "table" then
        return featureSpec
    end
    return {}
end

function T.RegisterColdFile(featureSpec, loader)
    if type(loader) ~= "function" then
        return
    end
    local entry = {
        features = NormalizeColdFeatureSpec(featureSpec),
        loader = loader,
        loaded = false,
    }
    table.insert(T.ColdFiles.order, entry)
end

local function IsColdFileDesired(features)
    for _, entry in ipairs(features or {}) do
        if type(entry) == "table" then
            if T.ShouldLoadFeature(entry[1], entry[2] == true) then
                return true
            end
        elseif T.ShouldLoadFeature(entry, false) then
            return true
        end
    end
    return false
end

function T.LoadColdFilesForDesired()
    local loaded = 0
    for _, entry in ipairs(T.ColdFiles.order) do
        if not entry.loaded and not entry.loading and IsColdFileDesired(entry.features) then
            entry.loading = true
            local ok, err = pcall(entry.loader)
            entry.loading = false
            if ok then
                entry.loaded = true
                loaded = loaded + 1
            elseif T.debug then
                T.debug("[ColdFile] load failed: " .. tostring(err))
            end
        end
    end
    return loaded
end

function T.ShouldLoadMinimapButton()
    return ReadRawSavedPath("minimap.hide") ~= true
end

local LIB_SERIALIZE_FEATURES = {
    { "semanticTimeline.runtimeEnabled", true },
    "semanticTimeline.editorLoaded",
    "raidCommandPanel.enabled",
    "rosterPlanner.enabled",
    "earlyPull.enabled",
    "dreadElegy.enabled",
    "buffCheck.enabled",
    "castRecorder.backendEnabled",
    "raidLead.optionPushAccept",
    "versionCheck.enabled",
    "tacticTranslator.enabled",
    "screenReminder.enabled",
    "debugMode",
}

local LIB_COMM_FEATURES = {
    { "semanticTimeline.runtimeEnabled", true },
    "semanticTimeline.editorLoaded",
    "raidCommandPanel.enabled",
    "rosterPlanner.enabled",
    "earlyPull.enabled",
    "dreadElegy.enabled",
    "buffCheck.enabled",
    "castRecorder.backendEnabled",
    "raidLead.optionPushAccept",
    "versionCheck.enabled",
    "tacticTranslator.enabled",
}

local LIB_CALLBACK_FEATURES = {
    { "semanticTimeline.runtimeEnabled", true },
    "semanticTimeline.editorLoaded",
    "raidCommandPanel.enabled",
    "rosterPlanner.enabled",
    "earlyPull.enabled",
    "dreadElegy.enabled",
    "buffCheck.enabled",
    "castRecorder.backendEnabled",
    "raidLead.optionPushAccept",
    "versionCheck.enabled",
    "tacticTranslator.enabled",
}

function T.ShouldLoadLibrary(libraryName)
    libraryName = tostring(libraryName or "")
    if libraryName == "LibDataBroker-1.1" or libraryName == "LibDBIcon-1.0" then
        return T.ShouldLoadMinimapButton()
    end
    if libraryName == "LibSerialize" or libraryName == "LibDeflate" then
        return T.ShouldLoadAnyFeature(LIB_SERIALIZE_FEATURES)
    end
    if libraryName == "AceComm-3.0" or libraryName == "ChatThrottleLib" then
        return T.ShouldLoadAnyFeature(LIB_COMM_FEATURES)
    end
    if libraryName == "CallbackHandler-1.0" then
        return T.ShouldLoadMinimapButton() or T.ShouldLoadAnyFeature(LIB_CALLBACK_FEATURES)
    end
    return false
end

-- 初始化配置
C.DB = {}

-- 默认配置
C.defaults = {
    enabled = true,
    Profiles = {},
    _nextProfileID = 1,
    _profileSchemaVersion = 0,
    useRaidNote = true,
    useSelfNote = true,
    ttsEnabled = true,
    ttsVolume = 100,
    ttsAdvanceTime = 0,
    ttsVoiceID = 0,
    ttsRate = 0,
    customAudioEnabled = true,
    customAudioPack = "ShengTangTools",
    CountdownEnabled = true,
    CountdownChannel = "Master",
    countdown = {
        activePackId = "stt_default",
    },
    Bar = {
        Enabled = true,
        SoftLimit = 5,
        Container = {
            spacing = 4,
            growth = "DOWN",
            position = {
                point = "CENTER",
                relPoint = "CENTER",
                x = 0,
                y = 100,
            },
        },
        Style = {
            width = 240,
            height = 22,
            bgColor = { 0, 0, 0, 0.55 },
            barColor = { 0.55, 0.25, 0.85, 1 },
            borderSize = 1,
            borderColor = { 0, 0, 0, 1 },
            tickColor = { 1, 1, 1, 0.85 },
            tickWidth = 2,
            tickFontSize = 13,
            tickFontColor = { 1, 1, 1, 1 },
            tickWarnColor = { 1, 0.3, 0.3, 1 },
            tickWarnThreshold = 0.5,
            tickFontOutline = "OUTLINE",
            tickMinSegWidth = 1.2,
            iconSize = 22,
            iconGap = 2,
            labelFont = STANDARD_TEXT_FONT,
            labelFontSize = 13,
            labelFontColor = { 1, 1, 1, 1 },
            labelOffset = 4,
            labelRemainFmt = " (%.1f)",
        },
    },
    filterClass = true,   -- 监控职业相关提示（默认开启）
    filterRole = true,    -- 监控职责相关提示（默认开启）
    filterPos = true,     -- 监控站位相关提示（默认开启）
    filterAll = true,     -- 监控所有人相关提示（默认开启）
    filterParty = true,   -- 监控小队相关提示（默认开启）
    onlyInRaid = true, -- 仅在团队副本中播报（默认开启）
    debugMode = false,
    frameSkin = "kyrian",
    system = {
        showInBlizzardOptions = true,
    },
    optionsGuiNavExpanded = {},
    printEventsToChat = false, -- 聊天框打印播报文本（独立于 debug）
    superZoom = {
        enabled = false,
        maxZoom = 39,
    },
    privateAuraList = {
        enabled = false,              -- beta 默认关
        maxIconsPerUnit = 2,
        iconSize = 36,
        rowHeight = 40,
        spacing = 4,
        growthDirection = "DOWN",
        verboseProbeLog = true,       -- beta 阶段默认开详细日志
        pos = { point = "CENTER", relPoint = "CENTER", x = 200, y = 0 },
    },
    privateAuraHijack = {
        enabled = false,
        dispelTextEnabled = true,
        dispelText = "驱散!",
        fontSize = 28,
        fontColor = { 1, 0.2, 0.2, 1 },
        outline = "OUTLINE",
        anchor = "CENTER",
        offsetX = 0,
        offsetY = 0,
        flashEnabled = false,
        flashInterval = 0.5,
        hideBlizzardOverlay = true,
        soundEnabled = false,
        soundPath = "",
    },
    personalAuraAlert = {
        enabled = false,
        nextRuleID = 2,
    },
    dataSource = "STN",   -- 默认使用 STN 数据源
    syncOnlyFromLeader = true, -- 仅接收团长的方案推送
    raidLead = {
        optionPushAccept = true,
    },
    versionCheck = {
        enabled = true,
    },
    blizzardTimeline = {
        enabled = false,
        injectOnEncounterStart = true,
        injectInTest = false,
        iconSource = "default",
        defaultIconFileID = 237550,
        severityMode = "default",
        defaultSeverity = "Medium",
        indicatorIconMask = 0,
        maxQueueDuration = 3,
        viewIconScale = 1.0,
        viewTextEnabled = true,
        viewCountdownEnabled = true,
        viewTooltipsEnabled = true,
        viewIndicatorIconMask = 1023,
        viewBackgroundAlpha = 1.0,
        viewOrientation = "Horizontal",
        viewDirection = "Right",
        viewCrossAxisOffset = 0,
        viewCrossAxisExtent = 55,
        pipIconShown = true,
        pipTextShown = true,
        pipDuration = 5,
        recoveryEnabled = true,
        recoveryMode = "safe",
        recoveryAllowIfScriptExists = false,
        recoveryMaxLookahead = 120,
        recoveryManualButton = true,
        debugInjection = false,
        debugRecovery = false,
    },
    semanticTimeline = {
        runtimeEnabled = true,
        enabled = false,
        mode = "combine",
        centerTrigger = "highlight",
        resolveSource = "team_plus_personal",
        personalOverridesTeam = true,
        notes = {},
        editor = {
            recentSkills = {},
        },
        ui = {
            viewMode = "horizontal",
            enabled = false,
            cellWidth = 120,
            rowHeight = 26,
            iconSize = 16,
            cellGap = 2,
            durationBarHeight = 6,
            planWidth = 900,
            planHeight = 680,
            planPosX = nil,
            planPosY = nil,
            fontScale = 1.0,
            dividerRatio = 0.5,
            lastTab = 1,
            visualBoardLeftCollapsed = false,
            visualBoardRightCollapsed = false,
            perViewMode = {
                vertical = {
                    dividerRatio = 0.5,
                    cellWidth = 120,
                    rowHeight = 26,
                    iconSize = 16,
                    cellGap = 2,
                    scrollY = 0,
                },
                horizontal = {
                    dividerRatio = 0.8,
                    pxPerSecond = 50,
                    scrollX = 0,
                    scrollY = 0,
                    firstColMinW = 80,
                    firstColMaxW = 200,
                    rowHeight = 28,
                    iconSize = 24,
                },
            },
            playerCacheById = {},
            bossPortraitCache = {},
            bossIconCache = {},
            bossJournalEncounterCache = {},
        },
        templateVersion = "mn_s1_text_v2",
    },
    -- 屏幕提醒 V2：指示器模型，4 类 indicator(text/icon/bar/circle)。
    -- 屏幕提醒数据完全由 core/screen_reminder/schema.lua 接管。
    -- C.defaults 保留总开关，schemaVersion / indicators 等运行时由 Schema.Migrate 写入。
    screenReminder = {
        enabled = true,
    },
    -- 实时战术板：侧边结构化时间轴视图，与屏幕提醒并列独立。
    realtimeBoard = {
        enabled = false,
        -- 战斗外常驻：解析当前选中 boss 方案，把完整时间轴静态铺给战术板。
        persistentOutOfCombat = false,
        locked = true,
        position = {
            point = "TOPLEFT",
            relPoint = "TOPLEFT",
            x = 20,
            y = -20,
            width = 280,
            height = 400,
        },
        bgAlpha = 0.65,
        scale = 1.0,
        fontSize = 13,
        timeFontSize = 12,
        rowHeight = 32,
        rowSpacing = 2,
        spellDisplayMode = "iconText",
        showAudienceName = true,
        iconSize = 22,
        showHeader = true,
        headerHeight = 28,
        indicatorWidth = 3,
        autoScrollDelay = 3.0,
        smoothSpeed = 8.0,
        -- 过期事件显示策略：保留 / 淡出 / 立即隐藏。
        expiredMode = "gray",
        -- 当前事件锚点位置：自然滚动 / 顶部固定 / 底部固定。
        anchorPosition = "flow",
        -- 是否在战术板显示全部事件；不影响 TTS / 屏幕提醒的过滤链路。
        showAllEvents = false,
        -- 条目样式：clean=清爽（默认，无背景框）/ card=卡片（深色单元格背景）。
        cellStyle = "clean",
        -- 当前条目强调：仅经典样式使用，聚焦和简洁各有独立视觉体系。
        activeHighlight = {
            color = { 0.20, 0.50, 0.35 },
            alpha = 0.25,
            texture = "flat",
            indicatorWidth = 3,
            glowEnabled = false,
            glowColor = { 1.00, 0.95, 0.10 },
            glowAlpha = 0.9,
            glowLines = 4,
            glowFrequency = 0.12,
            glowLength = 8,
            glowThickness = 1,
            glowXOffset = 0,
            glowYOffset = 0,
        },
        -- 显示样式：classic=经典列表，focus=聚焦轮选，concise=简洁文本。
        displayStyle = "classic",
        -- 倒数位置：right=右侧，left=图标前。
        timePosition = "right",
        focus = {
            upNeighbors = 2,
            downNeighbors = 2,
            emphasis = 0.55,
            spacingPx = 4,
            holdSeconds = 0.7,
            departureEnabled = true,
            blendSpeed = 0.18,
            align = "left",
            widthRatio = 1.00,
        },
        -- 未来事件显示窗口；0 表示不限。
        maxLookahead = 0,
        -- 时间方向：down=正序，up=倒序。
        timeDirection = "down",
        -- 时间格式：小数 / 整数 / 分秒 / 战斗时长。
        countdownFormat = "precise",
        maxFPS = 30,
    },
    castRecorder = {
        backendEnabled = false,
        maxRecords = 1,
        showInGantt = true,
    },
    raidCommandPanel = {
        enabled = false,
        onlyInInstance = true,
        locked = true,
        styleScale = 1,
        position = {
            point = "CENTER",
            relPoint = "CENTER",
            x = 0,
            y = 200,
            width = 320,
        },
        rezTracker = {
            enabled = true,
            ttsOnUse = false,
            ttsOnUseText = "",
        },
        lustMonitor = {
            enabled = true,
            ttsEnding = false,
            ttsEndingText = "",
        },
        encounterTimer = {
            enabled = true,
        },
        deathLog = {
            enabled = true,
            showRecap = true,
            ttsOnDeath = false,
            ttsDeathLimit = 2,
            ttsOnDeathText = "",
        },
    },
    rosterPlanner = {
        enabled = false,
        sourceText = "",
        activeBossIndex = 1,
        inviteMode = "inviteOnly",
        confirmKick = true,
        difficultyMode = "auto",
        aliasGuidCache = {},
        subPanel = {
            broadcastChannel = "GUILD_AND_WHISPER",
            showSelfOnly = false,
            position = {
                point = "CENTER",
                relPoint = "CENTER",
                x = 0,
                y = 0,
            },
        },
    },
    interruptRotation = {
        enabled = true,
        defaultEnabledApplied = false,
        uiStyle = "banner",
        bannerSelf = true,
        bannerNext = false,
        bannerOthers = false,
        bannerDurationSec = 2,
        bannerScale = 3.0,
        ttsOnPrepare = false,
        soundOnSelf = true,
        soundFile = "",
        bossEnabled = {
            ["3183"] = true,
        },
        midnightMacroGroup = 1,
        midnightMacroKick = 1,
        bossOverlayEnabled = false,
        bossOverlayX = nil,
        bossOverlayY = nil,
    },
    friendlyNameplate = {
        enabled = false,          -- 总开关（默认关闭，用户手动开启）
        removeServerName = true,  -- 去服务器名后缀
        nameOnly = true,          -- 只显示名字（隐藏血条）
        useClassColor = true,     -- 使用职业颜色
        autoInInstance = true,    -- 仅副本内生效
        fontSize = 12,            -- 友方玩家姓名板名字字号
        fontOutline = "DEFAULT",  -- DEFAULT / NONE / OUTLINE
    },
    preferredLocale = "auto", -- 语言偏好: "auto", "zhCN", "enUS", "zhTW"
    showSTNFeatures = true, -- 显示STN相关功能（默认开启）
    safeMode = false, -- 安全模式：仅加载核心与播报，不创建GUI/下拉
    suppressForbiddenPopup = true, -- 过滤暴雪“受保护动作”弹窗
    devMode = false, -- 开发模式：任意战斗开始可触发测试播报
    tacticTranslator = {
        enabled = false,
    },
    tacticTranslatorFormat = "nsrt",
    tacticTranslatorMRTBoss = 0,
    autoLogging = {
        enabled = false,
        raidMythic = true,
        raidHeroic = true,
        raidNormal = false,
        raidLFR = false,
        mythicPlus = true,
        dungeon = false,
        checkAdvanced = true,
    },
    earlyPull = {
        enabled = false,
        raidOnly = true,
        bigText = true,
        tts = false,
    },
    dreadElegy = {
        enabled = false,
        lurabuttonsMVP = false,
        lurabuttonsMVPZoneOnly = true,
        lurabuttonsMVPEncounterOnly = false,
        raidOnly = true,
        runeRouteMode = "event",
        announceNumberOnShow = false,
        panelOpacity = 85,
        autoHideSeconds = 10,
        chatType = "raid",
    },
    luraCrystal = {
        enabled = false,
        indicatorName = "计时条#1",
        durationSec = 3,
        countdownAudioEnabled = true,
    },
    auraColorAlert = {
        enabled = false,
        pulse = true,
        showName = true,
        audioEnabled = false,
        scale = 1.0,
        alpha = 1.0,
        pos = {
            point = "TOP",
            relPoint = "TOP",
            x = 0,
            y = -100,
        },
    },
    buffCheck = {
        enabled = false,
        autoShowOnReadyCheck = true,
        autoHideDelaySec = 15,
        minFoodTier = 0,
        minFlaskTier = 0,
        minDurabilityPct = 50,
        repairReminder = {
            enabled = false,
            thresholdPct = 25,
            criticalPct = 10,
            durationSec = 5,
            repeatMinutes = 10,
            combatEndReminder = true,
            autoRepair = true,
            autoRepairGuildFunds = true,
            autoRepairShowSummary = true,
            tts = false,
        },
        chatBroadcastChannel = "NONE",
        checks = {
            food = true,
            flask = true,
            rune = true,
            vantus = true,
            weaponEnchantMain = true,
            weaponEnchantOff = false,
            durability = true,
            raidBuffAP = true,
            raidBuffStamina = true,
            raidBuffIntellect = true,
            raidBuffVersatility = true,
            raidBuffMastery = true,
            raidBuffMovement = true,
        },
        ui = {
            scale = 1.0,
            panels = {
                personal = {
                    position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 100 },
                },
                raid = {
                    position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 100 },
                    sortBy = "class",
                },
            },
        },
    },
    selfMarker = {
        enabled = false,
        onlyInCombat = true,
        texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
        textureCustom = "",
        solidColor = { 0.1, 1, 0.1, 1 },
        solidBorder = true,
        size = 16,
        alpha = 0.5,
        animation = "none",
        animPeriod = 1.5,
        pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    },
    minimap = { hide = false },
}

-- 简单的消息函数
T.msg = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end

    local text = table.concat(parts, " ")
    if text == "" then
        return
    end

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    else
        print(text)
    end
end

local DEBUG_LOG_LIMIT = 1000
local DEBUG_LOG_HEADER = "序号;时间;运行秒;来源;消息"
local debugLog = {
    start = 1,
    count = 0,
    nextSeq = 1,
    entries = {},
}

local function EscapeCSVField(value)
    local text = tostring(value or "")
    if text:find("[;\"\r\n]") then
        text = text:gsub("\"", "\"\"")
        return "\"" .. text .. "\""
    end
    return text
end

local function DebugLogEntryAt(relativeIndex)
    if relativeIndex < 1 or relativeIndex > debugLog.count then
        return nil
    end
    local index = ((debugLog.start + relativeIndex - 2) % DEBUG_LOG_LIMIT) + 1
    return debugLog.entries[index]
end

function T.RecordDebugLog(message, source)
    local index
    if debugLog.count < DEBUG_LOG_LIMIT then
        index = ((debugLog.start + debugLog.count - 1) % DEBUG_LOG_LIMIT) + 1
        debugLog.count = debugLog.count + 1
    else
        index = debugLog.start
        debugLog.start = (debugLog.start % DEBUG_LOG_LIMIT) + 1
    end

    debugLog.entries[index] = {
        seq = debugLog.nextSeq,
        timeText = date("%Y-%m-%d %H:%M:%S"),
        runtime = string.format("%.3f", (debugprofilestop() or 0) / 1000),
        source = tostring(source or "STT"),
        message = message or "",
    }
    debugLog.nextSeq = debugLog.nextSeq + 1
end

function T.GetDebugLogCount()
    return debugLog.count
end

function T.BuildDebugLogCSV()
    local lines = { DEBUG_LOG_HEADER }
    if debugLog.count == 0 then
        lines[#lines + 1] = ";;;;" .. EscapeCSVField("暂无诊断日志；可先执行 /st mem，或开启 /st debug 后复现问题")
        return table.concat(lines, "\n")
    end

    for i = 1, debugLog.count do
        local entry = DebugLogEntryAt(i)
        if entry then
            lines[#lines + 1] = table.concat({
                EscapeCSVField(entry.seq),
                EscapeCSVField(entry.timeText),
                EscapeCSVField(entry.runtime),
                EscapeCSVField(entry.source),
                EscapeCSVField(entry.message),
            }, ";")
        end
    end

    return table.concat(lines, "\n")
end

local debugOnceKeys = {}

function T.debugOnce(key, ...)
    key = tostring(key or "")
    if key == "" or debugOnceKeys[key] or not (C.DB and C.DB.debugMode) then
        return
    end
    debugOnceKeys[key] = true
    if T.debug then
        T.debug(...)
    end
end

T.debug = function(...)
    if not (C.DB and C.DB.debugMode) then
        return
    end

    local parts = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        local ok, text = pcall(function()
            return table.concat({ tostring(value) }, "")
        end)
        parts[i] = ok and text or "<secret>"
    end
    T.RecordDebugLog(table.concat(parts, " "), "DEBUG")
    print("|cff00ff00STT Debug:|r", table.concat(parts, " "))
end

-- 性能剖析工具：debugMode 关闭时返回 nil（零开销）。
-- 用法：local perf = T.CreatePerfProfile("标签")
--       if perf then perf:Mark("步骤") end
--       if perf then perf:Finish() end
T.CreatePerfProfile = function(label)
    if not (C.DB and C.DB.debugMode) then
        return nil
    end
    local profile = {
        label = label,
        startTime = debugprofilestop(),
        steps = {},
    }
    function profile:Mark(stepName)
        self.steps[#self.steps + 1] = {
            name = stepName,
            time = debugprofilestop(),
        }
    end
    function profile:Finish()
        local now = debugprofilestop()
        local totalMs = now - self.startTime
        local parts = {}
        local prev = self.startTime
        for _, step in ipairs(self.steps) do
            local stepMs = step.time - prev
            parts[#parts + 1] = string.format("%s=%.1fms", step.name, stepMs)
            prev = step.time
        end
        local tailMs = now - prev
        if tailMs > 0.01 then
            parts[#parts + 1] = string.format("tail=%.1fms", tailMs)
        end
        if totalMs < 50 then
            return totalMs
        end
        T.debug(string.format(
            "[Perf] %s total=%.1fms | %s",
            self.label,
            totalMs,
            table.concat(parts, " ")
        ))
        return totalMs
    end
    return profile
end

-- 初始化回调
T.Init_callbacks = {}
T.RegisterInitCallback = function(func)
    table.insert(T.Init_callbacks, func)
end

T.events = T.events or {}
T.events._listeners = T.events._listeners or {}

function T.events:Register(eventName, owner, handler)
    if type(eventName) ~= "string" or type(handler) ~= "function" then
        return
    end
    local listeners = self._listeners[eventName]
    if not listeners then
        listeners = {}
        self._listeners[eventName] = listeners
    end
    listeners[#listeners + 1] = {
        owner = owner,
        handler = handler,
    }
end

function T.events:Fire(eventName, ...)
    local listeners = self._listeners[eventName]
    if type(listeners) ~= "table" then
        return
    end
    for _, entry in ipairs(listeners) do
        if entry.owner ~= nil then
            entry.handler(entry.owner, ...)
        else
            entry.handler(...)
        end
    end
end

-- 编辑模式回调（仅表示暴雪编辑模式是否激活，不表示业务解锁状态）
T.Unlock_callbacks = {}
T.Lock_callbacks = {}

T.RegisterUnlockCallback = function(func)
    table.insert(T.Unlock_callbacks, func)
end

T.RegisterLockCallback = function(func)
    table.insert(T.Lock_callbacks, func)
end

T.IsUnlocked = function()
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
        return EditModeManagerFrame:IsEditModeActive()
    end
    return EditModeManagerFrame and EditModeManagerFrame:IsShown() or false
end

-- TTS语音列表
T.ttsSpeakers = {}

-- 获取TTS语音列表
T.GetTTSVoices = function()
    T.ttsSpeakers = {}
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local voices = C_VoiceChat.GetTtsVoices()
        if voices then
            for i, v in ipairs(voices) do
                table.insert(T.ttsSpeakers, {v.voiceID, v.name})
            end
        end
    end
    
    -- 如果没有语音，添加一个默认的
    if #T.ttsSpeakers == 0 then
        table.insert(T.ttsSpeakers, {0, "默认语音"})
    end
end

T.debug("正在加载... (统一选择器: 已启用)")

-- 语言系统
-- 健壮性：为本地化表 L 增加 __index 兜底到“键自身”。
-- 说明：这是 UI 文本层的容错，避免缺失翻译导致字符串拼接报错；不改变业务字段（遵循单一权威）。
do
    local mt = getmetatable(L)
    if not mt then mt = {} end
    mt.__index = function(t, k)
        rawset(t, k, k) -- 写回，避免重复触发 __index
        return k
    end
    setmetatable(L, mt)
end

T.LoadLocale = function(locale)
    -- 清空当前L表
    for k in pairs(L) do
        L[k] = nil
    end
    
    -- 根据locale调用对应的加载函数
    if locale == "enUS" or locale == "enGB" then
        if T.LoadLocale_enUS then
            T.LoadLocale_enUS()
        end
    elseif locale == "zhCN" then
        if T.LoadLocale_zhCN then
            T.LoadLocale_zhCN()
        end
    elseif locale == "zhTW" then
        if T.LoadLocale_zhTW then
            T.LoadLocale_zhTW()
        end
    else
        -- 默认使用中文
        if T.LoadLocale_zhCN then
            T.LoadLocale_zhCN()
        end
    end

    -- 合并自动补齐区（由 Tools/check_locale.sh 生成的自动翻译表）
    if T.ApplyLocaleAuto then
        T.ApplyLocaleAuto(locale)
    end
end

-- 获取当前活动语言
T.GetActiveLocale = function()
    if C.DB.preferredLocale and C.DB.preferredLocale ~= "auto" then
        return C.DB.preferredLocale
    end
    return T.Client
end

-- 设置语言
T.SetLocale = function(locale)
    C.DB.preferredLocale = locale
    local activeLocale = T.GetActiveLocale()
    T.LoadLocale(activeLocale)
    
    -- 触发UI刷新回调
    if T.RefreshUI then
        T.RefreshUI()
    end

    return activeLocale
end

-- 将自动补齐的本地化键合并进当前 L（仅在缺失时生效，不覆盖已有翻译）
T.ApplyLocaleAuto = function(locale)
    local active = locale or T.GetActiveLocale()
    local auto
    if active == "enUS" or active == "enGB" then
        auto = _G.STT_LOCALE_AUTO_enUS
    elseif active == "zhTW" then
        auto = _G.STT_LOCALE_AUTO_zhTW
    elseif active == "zhCN" then
        auto = _G.STT_LOCALE_AUTO_zhCN
    end
    if type(auto) == "table" then
        for k, v in pairs(auto) do
            if rawget(L, k) == nil then
                L[k] = v
            end
        end
    end
end
