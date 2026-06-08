local T, C, L = unpack(select(2, ...))

local addon_name = T.addon_name

local function MergeDefaults(target, defaults)
    if type(defaults) ~= "table" then
        return target
    end
    if type(target) ~= "table" then
        target = {}
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            target[k] = MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

local function PruneSavedRuntimeCaches(db)
    if type(db) ~= "table" then
        return
    end

    db._backup_v1 = nil

    if type(db.perf) == "table" then
        db.perf.lastMemorySnapshot = nil
        db.perf.baseline = nil
    end

    local semantic = db.semanticTimeline
    if type(semantic) == "table" then
        semantic.captured = nil

        local workbench = semantic.workbench
        if type(workbench) == "table" then
            workbench.plansInitialized = nil
            workbench.bossTemplateDigest = nil
            workbench.bossTemplateVer = nil
            workbench.planRowBindings = nil
        end

        local ui = semantic.ui
        if type(ui) == "table" then
            ui.playerCacheById = nil
            ui.bossPortraitCache = nil
            ui.bossIconCache = nil
            ui.bossJournalEncounterCache = nil
            ui.npcPortraitCache = nil
            ui.npcIconCache = nil
        end
    end
end

local function CountEntries(values)
    local count = 0
    for _ in pairs(values or {}) do
        count = count + 1
    end
    return count
end

local function FormatInstantiationState(instantiated)
    return instantiated and "已实例化" or "未实例化"
end

local function FormatBoolState(value)
    return value and "开" or "关"
end

local function ClearSemanticUICaches()
    local ui = C and C.DB and C.DB.semanticTimeline and C.DB.semanticTimeline.ui
    if type(ui) ~= "table" then
        return 0
    end
    local cleared = 0
    for _, key in ipairs({
        "playerCacheById",
        "bossPortraitCache",
        "bossIconCache",
        "npcPortraitCache",
        "npcIconCache",
        "bossJournalEncounterCache",
    }) do
        if type(ui[key]) == "table" then
            cleared = cleared + CountEntries(ui[key])
            wipe(ui[key])
        end
    end
    return cleared
end

local function PruneEmptySemanticRowBindings()
    local wb = C and C.DB and C.DB.semanticTimeline and C.DB.semanticTimeline.workbench
    local bindings = wb and wb.planRowBindings
    if type(bindings) ~= "table" then
        return 0
    end
    local removed = 0
    for key, binding in pairs(bindings) do
        local lineCount = CountEntries(type(binding) == "table" and binding.lineToRowID or nil)
        local rowCount = CountEntries(type(binding) == "table" and binding.rowToLine or nil)
        if lineCount == 0 and rowCount == 0 then
            bindings[key] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function TrimCastRecordStore()
    if T.CastRecorder and T.CastRecorder.TrimSavedRecords then
        return T.CastRecorder:TrimSavedRecords()
    end
    return 0, STT_CDB and type(STT_CDB.castRecords) == "table" and #STT_CDB.castRecords or 0
end

local DEBUG_EVENT_KEYS = {
    "bossKey",
    "tab",
    "planID",
    "prevBossKey",
    "prevTab",
    "prevPlanID",
    "nextBossKey",
    "nextTab",
    "nextPlanID",
    "len",
    "oldLen",
    "newLen",
    "offset",
    "cursor",
    "sender",
    "digest",
    "cause",
    "costMs",
    "errorCount",
    "rowCount",
    "result",
}

function T.LogDebugEvent(eventName, fields)
    if not (eventName and T.debug and C and C.DB and C.DB.debugMode) then
        return
    end

    local parts = { tostring(eventName) }
    local payload = type(fields) == "table" and fields or nil
    if payload then
        for _, key in ipairs(DEBUG_EVENT_KEYS) do
            local value = payload[key]
            if value ~= nil then
                parts[#parts + 1] = string.format("%s=%s", key, tostring(value))
            end
        end
    end

    T.debug(table.concat(parts, " "))
end

-- 事件框架
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_LOGIN")

-- 材质转聊天内嵌文本
local function GetTextureStr(tex, width, height)
    return string.format("|T%s:%d:%d|t", tex, height or 0, width or 0)
end

-- QQ 群推送
local stt_icon = GetTextureStr("Interface\\AddOns\\ShengTangTools\\media\\logo.png", 16, 16)
local QQ_GROUP_NUMBER = "637144370"
local QQ_GROUP_LINK = "stt:qqgroup"

T.QQ_GROUP_NUMBER = QQ_GROUP_NUMBER

StaticPopupDialogs["STT_QQ_GROUP"] = {
    text = "|cff00ff00《STT》|r魔兽世界插件交流群\n\n选中下方群号，Ctrl+C 复制：",
    button1 = OKAY,
    hasEditBox = true,
    editBoxWidth = 160,
    OnShow = function(self)
        self.editBox:SetText(QQ_GROUP_NUMBER)
        self.editBox:SetAutoFocus(false)
        self.editBox:HighlightText()
    end,
    EditBoxOnTextChanged = function(self)
        self:SetText(QQ_GROUP_NUMBER)
        self:HighlightText()
    end,
    hideOnEscape = 1,
    whileDead = true,
}

function T.ShowQQGroupPopup()
    StaticPopup_Show("STT_QQ_GROUP")
end

function T.GetQQGroupLink(label)
    return string.format("|cff00ccff|H%s|h%s|h|r", QQ_GROUP_LINK, label or QQ_GROUP_NUMBER)
end

hooksecurefunc("SetItemRef", function(link)
    if link == QQ_GROUP_LINK then
        T.ShowQQGroupPopup()
    end
end)

-- 出厂重置：统一弹窗与执行函数（单一权威）
-- 注意：该功能会清空所有 SavedVariables 并强制重载界面
StaticPopupDialogs["STT_RESET_ALL"] = {
    text = L["确认重置_正文"],
    button1 = L["确认重置"],
    button2 = L["取消"],
    OnAccept = function()
        -- 彻底出厂：清空全局存档并重载
        STT_DB = nil
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

T.ShowFactoryResetPopup = function()
    StaticPopup_Show("STT_RESET_ALL")
end

-- 初始化函数
local function Initialize()
    -- 加载保存的配置
    STT_DB = STT_DB or {}

    -- 配置迁移：将旧的disableInDungeon迁移到新的onlyInRaid
    if STT_DB.disableInDungeon ~= nil then
        -- 如果存在旧配置，进行迁移
        STT_DB.onlyInRaid = STT_DB.disableInDungeon
        STT_DB.disableInDungeon = nil -- 删除旧配置
    end

    -- 配置迁移：旧版 blizzardTimelineEnabled -> blizzardTimeline.enabled
    if STT_DB.blizzardTimelineEnabled ~= nil then
        if type(STT_DB.blizzardTimeline) ~= "table" then
            STT_DB.blizzardTimeline = {}
        end
        STT_DB.blizzardTimeline.enabled = STT_DB.blizzardTimelineEnabled
        STT_DB.blizzardTimelineEnabled = nil
    end

    -- 配置迁移：旧版 realtimeBoard.showSpellIcon -> realtimeBoard.spellDisplayMode
    if type(STT_DB.realtimeBoard) == "table" then
        if STT_DB.realtimeBoard.spellDisplayMode == nil then
            STT_DB.realtimeBoard.spellDisplayMode = (STT_DB.realtimeBoard.showSpellIcon == false) and "text" or "iconText"
        end
        STT_DB.realtimeBoard.showSpellIcon = nil
    end

    STT_DB = MergeDefaults(STT_DB, C.defaults)
    PruneSavedRuntimeCaches(STT_DB)

    -- 版本检测是团长检查团员安装状态的基础通信能力，不提供禁用入口。
    if type(STT_DB.versionCheck) ~= "table" then
        STT_DB.versionCheck = {}
    end
    STT_DB.versionCheck.enabled = true

    if type(STT_DB.realtimeBoard) == "table" then
        local mode = STT_DB.realtimeBoard.spellDisplayMode
        if mode ~= "iconText" and mode ~= "icon" and mode ~= "text" then
            STT_DB.realtimeBoard.spellDisplayMode = "iconText"
        end
        STT_DB.realtimeBoard.showSpellIcon = nil
    end

    if type(STT_DB.semanticTimeline.notes) ~= "table" then
        STT_DB.semanticTimeline.notes = {}
    end
    if type(STT_DB.semanticTimeline.ui) ~= "table" then
        STT_DB.semanticTimeline.ui = {}
    end
    STT_DB.semanticTimeline.runtimeEnabled = true

    C.DB = STT_DB
    if T.FrameSkin and T.FrameSkin.NormalizeSavedValue then
        T.FrameSkin:NormalizeSavedValue()
    end

    -- 屏幕提醒 V2 一次性清理：旧 schemaVersion 缺失/不为 2 时整体覆盖默认值
    if T.ScreenReminderSchema and T.ScreenReminderSchema.Migrate then
        T.ScreenReminderSchema.Migrate()
    end

    -- 基于玩家偏好重新应用语言（修复/reload后语言回退）
    -- 说明：locale/*.lua 在载入过程中会按客户端语言写入 L，
    -- 这里在拿到持久化的 STT_DB 后，以用户的 preferredLocale 为单一权威，
    -- 再次调用 T.LoadLocale 覆盖，从而保证重载后仍保持用户选择的语言。
    if T and T.GetActiveLocale and T.LoadLocale then
        local active = T.GetActiveLocale()
        T.LoadLocale(active)
    end

    -- 12.0 一次性迁移（仅首次）：保留 STN 功能并将默认数据源切到 STN
    if not C.DB.migrated_to_12 then
        C.DB.showSTNFeatures = true
        C.DB.dataSource = "STN"
        C.DB.migrated_to_12 = true
        STT_DB.showSTNFeatures = true
        STT_DB.dataSource = "STN"
        STT_DB.migrated_to_12 = true
    end

    if T.LoadColdFilesForDesired then
        T.LoadColdFilesForDesired()
    end

    -- 确保mynickname字段存在
    if C.DB.mynickname == nil then
        C.DB.mynickname = ""
        STT_DB.mynickname = ""
    end

    local initialProfileID
    if T.Profile then
        T.Profile:MigrateLegacyNote()
        T.Profile:MigrateActiveProfileToByChar()
        initialProfileID = T.Profile:EnsureBindingForChar()
    end
    if T.InlineModifier and T.InlineModifier.MigrateSavedVariables then
        T.InlineModifier.MigrateSavedVariables()
    end
    if type(C.DB.interruptRotation) == "table" and C.DB.interruptRotation.defaultEnabledApplied ~= true then
        C.DB.interruptRotation.defaultEnabledApplied = true
        STT_DB.interruptRotation.defaultEnabledApplied = true
    end

    -- 只在调试模式下显示加载信息
    if C.DB.debugMode then
        T.msg("v" .. T.Version .. " 已加载")
    end

    -- 执行初始化回调；单个模块初始化失败不能阻断后续壳子回调和性能审计续跑。
    for index, func in ipairs(T.Init_callbacks) do
        local ok, err = pcall(func)
        if not ok and T.debug then
            T.debug("[InitCallback] index=%s error=%s", tostring(index), tostring(err))
        end
    end
    if T.ModuleLoader and T.ModuleLoader.Reconcile then
        T.ModuleLoader:Reconcile("initialize")
    end

    if T.events and T.Profile then
        T.events:Fire("STT_PROFILE_CHANGED", initialProfileID, nil, T.Profile:GetCharKey())
    end

    -- 保留用户配置；默认值在 C.defaults 中已开启

    -- 主 GUI 改为按需创建，避免登录时直接常驻整套窗口树。
end

-- 命令处理函数
local function HandleCommand(msg)
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd = msg:lower()
    
    if cmd == "" then
        if T.ToggleGUI then
            T.ToggleGUI()
        else
            T.msg("GUI模块未加载")
        end
        
    elseif cmd == "tooltipdebug" then
        if T.UITooltip and T.UITooltip.ShowDebug then
            T.UITooltip.ShowDebug()
        else
            T.msg("Tooltip 调试模块未加载")
        end

    elseif cmd == "ver" or cmd == "version" then
        if T.VersionCheck and T.VersionCheck.StartScan then
            T.VersionCheck:StartScan()
        else
            T.msg("版本检测模块未加载")
        end

    elseif cmd == "commtest" or cmd:match("^commtest%s+") then
        if T.Comm and T.Comm.RunSelfTest then
            T.Comm:RunSelfTest(msg:match("^commtest%s+(.+)$") or "self")
        else
            T.msg("通信模块未加载")
        end

    elseif cmd == "test" then
        if T.RuntimeTestControls and T.RuntimeTestControls.Start then
            T.RuntimeTestControls:Start()
        else
            T.msg("测试模块尚未加载")
        end

    elseif cmd == "bar test" then
        if T.SegmentedBar and T.SegmentedBar.ShowTest then
            T.SegmentedBar:ShowTest()
            T.msg("已显示分段进度条测试")
        else
            T.msg("分段进度条模块未加载")
        end

    elseif cmd == "rcp" or cmd:match("^rcp%s+") then
        if T.RaidCommandPanel and T.RaidCommandPanel.HandleCommand then
            T.RaidCommandPanel:HandleCommand(msg:match("^rcp%s*(.*)$") or "")
        else
            T.msg("团本指挥面板模块未加载")
        end

    elseif cmd == "reset" then
        -- 出厂重置入口：二次确认弹窗
        T.ShowFactoryResetPopup()

    elseif cmd == "pushreset" then
        if T.OptionShare and T.OptionShare.ResetIgnored then
            T.OptionShare:ResetIgnored()
        else
            T.msg("设置下发模块未加载")
        end

    -- 条件触发模拟命令已移除（12.0）
    elseif cmd:match("^dev") then
        local arg = msg:match("^dev%s*(.*)$") or ""
        if arg == "on" then
            C.DB.devMode = true; STT_DB.devMode = true; T.msg("开发模式: ON")
        elseif arg == "off" then
            C.DB.devMode = false; STT_DB.devMode = false; T.msg("开发模式: OFF")
        else
            C.DB.devMode = not C.DB.devMode; STT_DB.devMode = C.DB.devMode; T.msg("开发模式: " .. (C.DB.devMode and "ON" or "OFF"))
        end
        
    elseif cmd == "source" then
        -- 显示当前数据源
        local dataSource = C.DB.dataSource or "STN"
        T.msg(L["当前数据源"] .. ": " .. (dataSource == "MRT" and L["MRT笔记"] or L["圣糖战术板(STN)"]))
        if dataSource == "STN" and T.SemanticTimeline then
            local sem = T.SemanticTimeline
            local bundle = sem.GetCurrentPlanBundle and sem:GetCurrentPlanBundle({ allowActiveFallback = false }) or nil
            local title = bundle and bundle.title or nil
            local resolveSource = sem.GetResolveSource and sem:GetResolveSource() or "team"
            local resolveTextMap = {
                team = L["仅团队方案"] or "仅团队方案",
                personal = L["仅个人方案"] or "仅个人方案",
                team_plus_personal = L["团队+个人"] or "团队+个人",
            }
            if title and title ~= "" then
                T.msg("  STN方案: " .. title)
            end
            T.msg("  解析方案: " .. (resolveTextMap[resolveSource] or tostring(resolveSource)))
        elseif dataSource == "MRT" then
            T.msg("  读取团队笔记: " .. (C.DB.useRaidNote and "是" or "否"))
            T.msg("  读取个人笔记: " .. (C.DB.useSelfNote and "是" or "否"))
        end
        
    elseif cmd == "rollback" then
        -- 回滚到 v1 数据结构（仅在存在备份时）
        if STT_DB and STT_DB._backup_v1 then
            local b = STT_DB._backup_v1
            STT_DB.notes = b.notes or {}
            STT_DB.personalNotes = b.personalNotes or {}
            STT_DB.drafts = b.drafts or {}
            STT_DB.currentNote = b.currentNote
            STT_DB.currentSTNNote = b.currentSTNNote
            STT_DB._backup_v1 = nil
            STT_DB.Profiles = nil
            STT_DB.CurrentProfileByChar = nil
            STT_DB.ActiveProfileID = nil
            STT_DB.ActiveProfileIDByChar = nil
            STT_DB.DefaultProfileID = nil
            STT_DB._nextProfileID = nil
            STT_DB._profileSchemaVersion = nil
            STT_DB._schema = nil
            T.msg("已回滚到旧版数据结构，请 /reload 使之生效。")
        else
            T.msg("没有可用的备份，无法回滚。")
        end
        
    elseif cmd == "debug" then
        C.DB.debugMode = not C.DB.debugMode
        T.msg(L["调试模式"] .. ": " .. (C.DB.debugMode and "ON" or "OFF"))
        STT_DB.debugMode = C.DB.debugMode
        T.msg("需要 /reload 生效")

    elseif cmd == "log" then
        if T.ShowDebugLogWindow then
            T.ShowDebugLogWindow()
        else
            T.msg("诊断日志窗口模块未加载")
        end

    elseif cmd == "blizztimeline" or cmd == "bt" then
        if type(C.DB.blizzardTimeline) ~= "table" then
            C.DB.blizzardTimeline = {}
            STT_DB.blizzardTimeline = C.DB.blizzardTimeline
        end
        C.DB.blizzardTimeline.enabled = not C.DB.blizzardTimeline.enabled
        STT_DB.blizzardTimeline.enabled = C.DB.blizzardTimeline.enabled
        T.msg("暴雪时间轴注入: " .. (C.DB.blizzardTimeline.enabled and "|cff00ff00开启|r" or "|cffff0000关闭|r"))

    elseif cmd == "sem" then
        if T.ToggleGUI then
            if not (T.GUI and T.GUI:IsShown()) then
                T.ToggleGUI()
            end
            if T.SwitchToSemanticTab then
                T.SwitchToSemanticTab()
            end
        else
            T.msg("GUI模块未加载")
        end

    elseif cmd:match("^phase") then
        local phaseKey = cmd:match("^phase%s+(%S+)$")
        if not phaseKey then
            T.msg("用法: /st phase <p1|i1|p2|p1r2>")
            return
        end
        if not (T.PhaseDetector and T.PhaseDetector.IsRunning and T.PhaseDetector:IsRunning()) then
            T.msg("当前无运行中的时间轴")
            return
        end
        if not (T.PhaseDetector._SetPhase and T.PhaseDetector.GetCurrentPhase) then
            T.msg("阶段检测模块未加载")
            return
        end
        local ok = T.PhaseDetector:_SetPhase(phaseKey, "manual", {
            previousPhase = T.PhaseDetector:GetCurrentPhase(),
        })
        if ok then
            T.msg("已手动切换阶段: " .. tostring(T.PhaseDetector:GetCurrentPhase() or phaseKey))
        else
            T.msg("阶段未变化或阶段标签无效")
        end

    elseif cmd == "semdiag" then
        if not T.SemanticTimeline then
            T.msg("语义时间轴模块未加载")
            return
        end

        local sem = T.SemanticTimeline
        if sem.EnsureTemplateReady then
            sem:EnsureTemplateReady()
        end

        local totalInstances = #(sem.instances or {})
        local raidCount, dungeonCount = 0, 0
        for _, inst in ipairs(sem.instances or {}) do
            if inst.type == "dungeon" then
                dungeonCount = dungeonCount + 1
            else
                raidCount = raidCount + 1
            end
        end

        local selection = sem.GetWorkbenchSelection and sem:GetWorkbenchSelection() or nil
        local instanceType = selection and selection.instanceType or "nil"
        local instanceID = selection and selection.instanceID or 0
        local encounterID = selection and selection.encounterID or 0

        local instanceOptions = sem.GetWorkbenchInstanceList and sem:GetWorkbenchInstanceList(instanceType) or {}
        local encounterOptions = sem.GetWorkbenchEncounterList and sem:GetWorkbenchEncounterList(instanceType, instanceID) or {}

        T.msg(string.format(
            "semdiag: template=%s instances=%d (raid=%d,dungeon=%d) sel={type=%s,instance=%d,boss=%d} opts={instance=%d,boss=%d}",
            tostring((sem.template and sem.template.version) or "nil"),
            totalInstances,
            raidCount,
            dungeonCount,
            tostring(instanceType),
            tonumber(instanceID) or 0,
            tonumber(encounterID) or 0,
            #instanceOptions,
            #encounterOptions
        ))

    elseif cmd:match("^semmode") then
        local mode = cmd:match("^semmode%s+(%S+)$")
        if not mode then
            T.msg("用法: /st semmode <override|combine|center>")
            return
        end

        mode = mode:lower()
        if mode == "center" then
            mode = "center"
        elseif mode == "override" then
            mode = "override"
        elseif mode == "combine" then
            mode = "combine"
        else
            T.msg("无效模式: " .. tostring(mode))
            T.msg("可选: override / combine / center")
            return
        end

        if T.SemanticTimeline and T.SemanticTimeline.SetMode then
            local ok = T.SemanticTimeline:SetMode(mode)
            if ok then
                local modeText = (mode == "override" and "完全覆盖") or (mode == "combine" and "组合显示") or "中上提醒"
                T.msg("语义时间轴模式: " .. modeText)
                if T.SemanticTimelineGUI and T.SemanticTimelineGUI.RefreshData then
                    T.SemanticTimelineGUI.RefreshData()
                end
            else
                T.msg("设置语义模式失败")
            end
        else
            T.msg("语义时间轴模块未加载")
        end

    elseif cmd == "safemode" then
        C.DB.safeMode = not C.DB.safeMode
        STT_DB.safeMode = C.DB.safeMode
        if C.DB.safeMode then
            T.msg("安全模式: ON （不创建GUI/下拉，仅保留核心功能）")
        else
            T.msg("安全模式: OFF")
        end
        T.msg("需要 /reload 生效")
    
    elseif cmd == "errorfilter" or cmd == "forbidden" then
        C.DB.suppressForbiddenPopup = not C.DB.suppressForbiddenPopup
        STT_DB.suppressForbiddenPopup = C.DB.suppressForbiddenPopup
        if C.DB.suppressForbiddenPopup then
            T.msg("拦截受保护动作弹窗: ON")
        else
            T.msg("拦截受保护动作弹窗: OFF")
        end

    elseif cmd == "config" then
        T.msg("当前配置:")
        T.msg("  TTS启用: " .. (C.DB.ttsEnabled and "是" or "否"))
        T.msg("  TTS音量: " .. (C.DB.ttsVolume or 100))
        T.msg("  TTS语速: " .. (C.DB.ttsRate or 0))
        T.msg("  语音提前时间: " .. (C.DB.ttsAdvanceTime or 0) .. "秒")
        T.msg("  调试模式: " .. (C.DB.debugMode and "是" or "否"))
        T.msg("  暴雪时间轴注入: " .. ((C.DB.blizzardTimeline and C.DB.blizzardTimeline.enabled) and "开启" or "关闭"))
        T.msg("  弹窗过滤: " .. (C.DB.suppressForbiddenPopup == true and "开启" or "关闭"))
        T.msg("  屏幕提醒: " .. (((C.DB.screenReminder and C.DB.screenReminder.enabled) ~= false) and "开启" or "关闭"))
        T.msg("  实时战术板: " .. (((C.DB.realtimeBoard and C.DB.realtimeBoard.enabled) ~= false) and "开启" or "关闭"))

    elseif cmd == "triggerlog" then
        if T.TriggerRunner and T.TriggerRunner.DumpLog then
            T.TriggerRunner:DumpLog()
        else
            T.msg(L["触发日志为空"] or "触发日志为空")
        end
        
    elseif cmd:sub(1, 3) == "tts" then
        local args = msg:match("^tts%s+(.+)")
        if args then
            local subcmd, param = args:match("^(%S+)%s*(.*)$")
            if subcmd == "search" or subcmd == "find" then
                -- 搜索语音
                if param == "" then
                    T.msg("用法: /st tts search <关键词>")
                else
                    local searchTerm = param:lower()
                    T.msg("搜索语音: " .. param)
                    local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices() or {}
                    local found = false

                    for _, voice in ipairs(voices) do
                        if voice.name:lower():find(searchTerm) then
                            T.msg(string.format("  [%d] %s", voice.voiceID, voice.name))
                            found = true
                        end
                    end

                    if not found then
                        T.msg("  没有找到包含 '" .. param .. "' 的语音")
                    else
                        T.msg("  使用 /st tts set <ID> 来设置语音")
                    end
                end
            elseif subcmd == "list" then
                -- 分页显示所有语音
                local page = tonumber(param) or 1
                local pageSize = 10
                local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices() or {}
                local totalPages = math.ceil(#voices / pageSize)

                if #voices == 0 then
                    T.msg("没有可用的TTS语音")
                    return
                end

                if page < 1 then page = 1 end
                if page > totalPages then page = totalPages end

                T.msg(string.format("TTS语音列表 (第%d/%d页):", page, totalPages))

                local startIdx = (page - 1) * pageSize + 1
                local endIdx = math.min(page * pageSize, #voices)

                for i = startIdx, endIdx do
                    local voice = voices[i]
                    T.msg(string.format("  [%d] %s", voice.voiceID, voice.name))
                end

                if totalPages > 1 then
                    if page < totalPages then
                        T.msg(string.format("  查看下一页: /st tts list %d", page + 1))
                    end
                    if page > 1 then
                        T.msg(string.format("  查看上一页: /st tts list %d", page - 1))
                    end
                end
                T.msg("  搜索语音: /st tts search <关键词>")
                T.msg("  设置语音: /st tts set <ID>")
            elseif subcmd == "set" and param ~= "" then
                local voiceID = tonumber(param)
                if voiceID then
                    -- 验证语音ID是否有效
                    local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices() or {}
                    local validVoice = false
                    local voiceName = ""

                    for _, voice in ipairs(voices) do
                        if voice.voiceID == voiceID then
                            validVoice = true
                            voiceName = voice.name
                            break
                        end
                    end

                    if validVoice then
                        C.DB.ttsVoiceID = voiceID
                        STT_DB.ttsVoiceID = voiceID
                        T.msg("TTS语音已切换为: [" .. voiceID .. "] " .. voiceName)

                        -- 测试新语音
                        if C_VoiceChat and C_VoiceChat.SpeakText then
                            C_VoiceChat.StopSpeakingText()
                            C_Timer.After(0.1, function()
                            -- 12.0签名：voiceID, text, rate, volume, overlap
                            C_VoiceChat.SpeakText(voiceID, "语音切换成功", C.DB.ttsRate or 0, C.DB.ttsVolume or 100, false)
                            end)
                        end
                    else
                        T.msg("无效的语音ID: " .. voiceID .. "，请使用 /st tts 查看可用语音")
                    end
                else
                    T.msg("用法: /st tts set <语音ID>")
                end
            else
                T.msg("用法: /st tts set <语音ID>")
            end
        else
            -- 原来的tts命令逻辑
            T.msg("TTS系统检查:")
            T.msg("  TTS启用: " .. (C.DB.ttsEnabled and "是" or "否"))
            T.msg("  音量: " .. (C.DB.ttsVolume or 100))
            T.msg("  语速: " .. (C.DB.ttsRate or 0))
            T.msg("  语音ID: " .. (C.DB.ttsVoiceID or 0))

            -- 提示使用新的命令
            T.msg("  ---")
            T.msg("  查看语音列表: /st tts list")
            T.msg("  搜索语音: /st tts search <关键词>")
            T.msg("  设置语音: /st tts set <ID>")
            T.msg("  ---")
            T.msg("  示例: /st tts search 婷婷")
            T.msg("  示例: /st tts search zh-CN")

            -- 测试播放
            T.msg("测试播放: 'STTTTS测试'")
            if C_VoiceChat and C_VoiceChat.SpeakText then
                C_VoiceChat.StopSpeakingText()
                C_Timer.After(0.1, function()
                    -- 12.0签名：voiceID, text, rate, volume, overlap
                    C_VoiceChat.SpeakText(C.DB.ttsVoiceID or 0, "STTTTS测试", C.DB.ttsRate or 0, C.DB.ttsVolume or 100, false)
                    T.msg("  已发送TTS播放请求")
                end)
            else
                T.msg("  C_VoiceChat.SpeakText 不可用")
            end
        end

    elseif cmd == "paste" or cmd == "notepad" then
        if T.ShowPastePad then
            T.ShowPastePad()
        else
            T.msg("粘贴板模块未加载")
        end

    elseif cmd:match("^export") then
        local exportType = cmd:match("^export%s+(%S+)$")
        if not T.ShowExportImportDialog then
            T.msg("导入导出模块未加载")
            return
        end
        if exportType == "raid" then
            T.ShowExportImportDialog("export", "raid")
        elseif exportType == "dungeon" then
            T.ShowExportImportDialog("export", "dungeon")
        elseif exportType == "settings" then
            T.ShowExportImportDialog("export", "settings")
        else
            T.msg("用法: /st export raid|dungeon|settings")
        end

    elseif cmd == "import" then
        if T.ShowExportImportDialog then
            T.ShowExportImportDialog("import")
        else
            T.msg("导入导出模块未加载")
        end

    elseif cmd == "match" then
        -- 测试精确匹配功能
        T.msg("测试精确匹配功能:")
        T.msg("  当前玩家: " .. T.PlayerName)
        T.msg("  玩家GUID: " .. (T.PlayerGUID or "无"))
        
        if T.TestNameMatching then
            T.TestNameMatching()
        else
            T.msg("  测试函数未加载")
        end
        
    elseif cmd == "filter" then
        -- 显示过滤器状态
        T.msg("播报过滤器状态:")
        T.msg("  播报职业相关: " .. (C.DB.filterClass and "|cff00ff00开启|r" or "|cffff0000关闭|r"))
        T.msg("  播报职责相关: " .. (C.DB.filterRole and "|cff00ff00开启|r" or "|cffff0000关闭|r"))
        T.msg("  播报站位相关: " .. (C.DB.filterPos and "|cff00ff00开启|r" or "|cffff0000关闭|r"))
        T.msg("  播报{所有人}条件: " .. (C.DB.filterAll and "|cff00ff00开启|r" or "|cffff0000关闭|r"))
        T.msg("  播报小队相关: " .. (C.DB.filterParty and "|cff00ff00开启|r" or "|cffff0000关闭|r"))
        T.msg("  仅在团队副本播报: " .. (C.DB.onlyInRaid and "|cff00ff00开启|r" or "|cffff0000关闭|r"))
        
    elseif cmd == "checkdungeon" then
        -- 检测当前实例类型
        T.msg("检测当前实例类型:")
        local name, instanceType, difficultyID, difficultyName, maxPlayers = GetInstanceInfo()
        T.msg("  实例名称: " .. (name or "无"))
        T.msg("  实例类型: " .. (instanceType or "无"))
        T.msg("  难度ID: " .. (difficultyID or 0))
        T.msg("  难度名称: " .. (difficultyName or "无"))
        T.msg("  最大玩家数: " .. (maxPlayers or 0))

        if T.IsInRaid and T.IsInRaid() then
            T.msg("  |cff00ff00当前在团队副本中|r")
            T.msg("  |cff00ff00语音播报正常|r")
        elseif T.IsInDungeon and T.IsInDungeon() then
            T.msg("  |cffffff00当前在地下城中|r")
            if C.DB.onlyInRaid then
                T.msg("  |cffff0000语音播报已禁用（仅在团队副本播报）|r")
            else
                T.msg("  |cff00ff00语音播报正常|r")
            end
        else
            T.msg("  |cffff0000当前不在副本中|r")
            if C.DB.onlyInRaid then
                T.msg("  |cffff0000语音播报已禁用（仅在团队副本播报）|r")
            else
                T.msg("  |cff00ff00语音播报正常|r")
            end
        end
        
    elseif cmd == "checkvars" then
        local MRT = _G.VMRT or _G.VExRT
        local hasNoteTable = type(MRT) == "table" and type(MRT.Note) == "table"
        local raidText = hasNoteTable and tostring(MRT.Note.Text1 or "") or ""
        local selfText = hasNoteTable and tostring(MRT.Note.SelfText or "") or ""
        T.msg("MRT 笔记可用性检查:")
        T.msg("  MRT主表: " .. (type(MRT) == "table" and "|cff00ff00可用|r" or "|cffff0000不可用|r"))
        T.msg("  Note表: " .. (hasNoteTable and "|cff00ff00可用|r" or "|cffff0000不可用|r"))
        T.msg("  团队笔记长度: " .. #raidText)
        T.msg("  个人笔记长度: " .. #selfText)
        T.msg("  当前数据源: " .. tostring(C.DB.dataSource or "STN"))
    elseif cmd == "showmrt" then
        local MRT = _G.VMRT or _G.VExRT
        if type(MRT) ~= "table" or type(MRT.Note) ~= "table" then
            T.msg("当前未检测到 MRT 笔记")
            return
        end

        local raidText = tostring(MRT.Note.Text1 or "")
        local selfText = tostring(MRT.Note.SelfText or "")
        T.msg("当前 MRT 笔记摘要:")
        T.msg("  团队笔记长度: " .. #raidText)
        if raidText ~= "" then
            T.msg("  团队笔记内容:")
            T.msg(raidText)
        end
        T.msg("  个人笔记长度: " .. #selfText)
        if selfText ~= "" then
            T.msg("  个人笔记内容:")
            T.msg(selfText)
        end
        if raidText == "" and selfText == "" then
            T.msg("  当前 MRT 团队笔记和个人笔记都为空")
        end

    elseif cmd == "clear" then
        -- 清除当前配置相关运行缓存
        T.msg("清除当前配置缓存...")
        
        -- 停止播报器
        if T.StopScheduler then
            T.StopScheduler()
        end
        
        -- 清空timeline
        if T.ClearTimeline then
            T.ClearTimeline()
        end

        -- 清理暴雪时间轴注入事件
        if T.BlizzardTimeline and T.BlizzardTimeline.ClearInjected then
            T.BlizzardTimeline:ClearInjected()
        end
        
        -- 清空TTS队列
        if T.ClearTTSQueue then
            T.ClearTTSQueue()
        end
        
        if T.Note then
            T.Note:InitDB()
        end
        if T.TacticalNotice and T.TacticalNotice.ClearAll then
            T.TacticalNotice:ClearAll()
        end
        if T.RealtimeBoard and T.RealtimeBoard.Stop then
            T.RealtimeBoard:Stop()
        end
        if T.ClearAllBars then
            T.ClearAllBars()
        end
        if (C.DB.dataSource or "STN") == "STN" then
            T.msg("已重新加载 STN 数据")
        else
            T.msg("已重置内部缓存；MRT 数据源仍按需实时读取")
        end
        
        -- 清理编译缓存
        if T.SemanticTimeline and T.SemanticTimeline.WipeCompiledPlanCache then
            T.SemanticTimeline:WipeCompiledPlanCache()
        end
        local semanticUICleared = ClearSemanticUICaches()
        local rowBindingsRemoved = PruneEmptySemanticRowBindings()
        local castRecordsRemoved, castRecordsLeft = TrimCastRecordStore()
        collectgarbage("collect")

        T.msg("缓存已清除")
        T.msg(string.format(
            "GUI缓存清理: 图标/玩家缓存=%d, 空行绑定=%d, 施法旧记录=%d(剩余%d)",
            semanticUICleared,
            rowBindingsRemoved,
            castRecordsRemoved,
            castRecordsLeft
        ))

    elseif cmd:match("^perf") then
        if T.PerfProbe and T.PerfProbe.HandlePerfCommand then
            T.PerfProbe:HandlePerfCommand(msg:match("^perf%s*(.*)$") or "")
        else
            T.msg("性能探针模块未加载")
        end

    elseif cmd:match("^plog") then
        if T.PerfProbe and T.PerfProbe.HandlePlogCommand then
            T.PerfProbe:HandlePlogCommand(msg:match("^plog%s*(.*)$") or "")
        else
            T.msg("性能日志模块未加载")
        end

    elseif cmd:match("^mod") or cmd:match("^modules") then
        if T.PerfProbe and T.PerfProbe.HandleModCommand then
            T.PerfProbe:HandleModCommand(msg:match("^mod%s*(.*)$") or msg:match("^modules%s*(.*)$") or "")
        else
            T.msg("模块管理器未加载")
        end

    elseif cmd == "mem" then
        if T.PerfProbe and T.PerfProbe.PrintMemorySnapshot then
            T.PerfProbe:PrintMemorySnapshot()
            return
        end
        UpdateAddOnMemoryUsage()
        local rawKB = tonumber(GetAddOnMemoryUsage("ShengTangTools")) or 0
        collectgarbage("collect")
        UpdateAddOnMemoryUsage()
        local postGcKB = tonumber(GetAddOnMemoryUsage("ShengTangTools")) or 0
        local reclaimedKB = math.max(0, rawKB - postGcKB)
        local reclaimedRatio = rawKB > 0 and (reclaimedKB / rawKB) or 0

        local semantic = T.SemanticTimeline or {}
        local guiState = T.GetGUIMemoryState and T.GetGUIMemoryState() or {}
        local semanticGUIState = T.SemanticTimelineGUI and T.SemanticTimelineGUI.GetMemoryState and T.SemanticTimelineGUI.GetMemoryState() or {}
        local horizontalState = semanticGUIState.horizontal or {}
        local breathState = T.DreadBreathAlert and T.DreadBreathAlert.GetMemoryState and T.DreadBreathAlert:GetMemoryState() or {}
        local auraColorState = T.AuraColorAlert and T.AuraColorAlert.GetMemoryState and T.AuraColorAlert:GetMemoryState() or {}

        local gcConclusion
        if reclaimedKB <= math.max(256, rawKB * 0.05) then
            gcConclusion = "GC回收有限，更像常驻内存偏高"
        elseif postGcKB >= rawKB * 0.8 then
            gcConclusion = "回收了一部分临时对象，但 post_gc 仍代表主要常驻基线"
        else
            gcConclusion = "当前存在可回收临时对象，但 post_gc 仍是后续排查基线"
        end

        T.msg(string.format("=== STT 内存快照 ==="))
        T.msg(string.format("原始内存: %.2f MB (%.0f KB)", rawKB / 1024, rawKB))
        T.msg(string.format("GC后内存: %.2f MB (%.0f KB)", postGcKB / 1024, postGcKB))
        T.msg(string.format("GC回收: %.2f MB (%.0f KB)", reclaimedKB / 1024, reclaimedKB))
        T.msg("结论: " .. gcConclusion)

        local compiledCacheCount = CountEntries(semantic.planCompiledCache)
        local triggerTemplateCount = CountEntries(semantic._triggerTemplateCache)
        local spellNameCacheCount = CountEntries(semantic.spellNameCache)
        T.msg(string.format(
            "语义缓存: 编译方案=%d, 触发模板=%d, 法术名=%d",
            compiledCacheCount,
            triggerTemplateCount,
            spellNameCacheCount
        ))

        local recvCount, processedCount, sendCount = 0, 0, 0
        if T.Note then
            recvCount = CountEntries(T.Note._recv)
            processedCount = CountEntries(T.Note._processed)
            sendCount = CountEntries(T.Note._sendStreams)
        end
        T.msg(string.format("通信缓存: 接收流=%d, 去重=%d, 发送流=%d", recvCount, processedCount, sendCount))

        if T.TacticalNotice and T.TacticalNotice.pools then
            local p = T.TacticalNotice.pools
            T.msg(string.format("战术提醒池: text=%d, icon=%d, bar=%d", #(p.text or {}), #(p.icon or {}), #(p.bar or {})))
        end
        T.msg(string.format(
            "窗口实例: GUI=%s, 设置页=%s, 战术页=%s",
            FormatInstantiationState(guiState.root == true),
            FormatInstantiationState(guiState.settings == true),
            FormatInstantiationState(guiState.plan == true)
        ))
        T.msg(string.format(
            "语义GUI: 可见=%s, rows=%d, display=%d, cells=%d/%d, timers=%s/%s/%s",
            FormatBoolState(semanticGUIState.visible == true),
            tonumber(semanticGUIState.rows) or 0,
            tonumber(semanticGUIState.displayRows) or 0,
            tonumber(semanticGUIState.cellActive) or 0,
            tonumber(semanticGUIState.cellPool) or 0,
            FormatBoolState(semanticGUIState.saveTimer == true),
            FormatBoolState(semanticGUIState.formSaveTimer == true),
            FormatBoolState(semanticGUIState.statusTicker == true)
        ))
        T.msg(string.format(
            "水平时间轴: 可见=%s, 事件=%s/%s, OnUpdate=%d, source=%d, display=%d, perRow=%d, rows=%d, chips=%d, inspect=%d",
            FormatBoolState(horizontalState.visible == true),
            FormatBoolState(horizontalState.rosterEvents == true),
            FormatBoolState(horizontalState.inputEvents == true),
            tonumber(horizontalState.activeOnUpdate) or 0,
            tonumber(horizontalState.sourceRows) or 0,
            tonumber(horizontalState.displayRows) or 0,
            tonumber(horizontalState.perRow) or 0,
            tonumber(horizontalState.rowFrames) or 0,
            tonumber(horizontalState.chips) or 0,
            tonumber(horizontalState.pendingInspect) or 0
        ))
        local semanticDB = C and C.DB and C.DB.semanticTimeline or {}
        local semanticUI = semanticDB.ui or {}
        local workbench = semanticDB.workbench or {}
        local castRecords = STT_CDB and type(STT_CDB.castRecords) == "table" and #STT_CDB.castRecords or 0
        T.msg(string.format(
            "存档计数: 行绑定=%d, 玩家缓存=%d, Boss图标=%d, NPC图标=%d, 施法记录=%d",
            CountEntries(workbench.planRowBindings),
            CountEntries(semanticUI.playerCacheById),
            CountEntries(semanticUI.bossIconCache),
            CountEntries(semanticUI.npcIconCache),
            castRecords
        ))
        T.msg(string.format(
            "提醒实例: 吐息UI=%s, 颜色UI=%s, 颜色事件=%s",
            FormatInstantiationState(breathState.overlay == true),
            FormatInstantiationState(auraColorState.overlay == true),
            FormatInstantiationState(auraColorState.eventFrame == true)
        ))

    --[[ STN功能切换命令已禁用，如需恢复请取消注释
    elseif cmd == "stn" then
        -- 切换STN功能显示
        C.DB.showSTNFeatures = not C.DB.showSTNFeatures
        STT_DB.showSTNFeatures = C.DB.showSTNFeatures

        if C.DB.showSTNFeatures then
            T.msg("STN功能已|cff00ff00启用|r")
            T.msg("请|cffffff00重载界面|r以显示战术方案标签页和STN数据源选项")
            T.msg("  输入 /reload 重载界面")
        else
            T.msg("STN功能已|cffff0000隐藏|r")
            T.msg("请|cffffff00重载界面|r以隐藏战术方案标签页")
            T.msg("  输入 /reload 重载界面")
        end
    ]]--

    elseif cmd == "nameplate" or cmd == "np" then
        if T.FriendlyNameplate then
            T.FriendlyNameplate:Toggle()
        else
            T.msg("友方姓名版模块未加载")
        end

    elseif cmd:match("^rune") then
        local args = cmd:match("^rune%s*(.*)$") or ""
        if T.HandleDreadElegyCommand then
            T.HandleDreadElegyCommand(args)
        else
            T.msg("死亡挽歌符文模块未加载")
        end

    elseif cmd == "pull" or cmd:match("^pull%s") then
        local args = msg:match("^pull%s*(.*)$") or ""
        if T.HandleEarlyPullCommand then
            T.HandleEarlyPullCommand(args)
        else
            T.msg("提前开怪检测模块未加载")
        end

    elseif cmd == "breath" then
        if T.TestDreadBreathAlert then
            T.TestDreadBreathAlert()
        else
            T.msg("亡者吐息警告模块未加载")
        end

    elseif cmd == "auracolor" then
        if T.TestAuraColorAlert then
            T.TestAuraColorAlert()
        else
            T.msg("光环颜色警告模块未加载")
        end


    elseif cmd:match("^board") then
        local args = cmd:match("^board%s*(.*)$") or ""
        if T.HandleRealtimeBoardCommand then
            if not T.HandleRealtimeBoardCommand("board", args) then
                T.msg("实时战术板命令处理失败")
            end
        else
            T.msg("实时战术板模块未加载")
        end

    elseif cmd == "bc" or cmd:match("^bc%s") then
        local args = msg:match("^bc%s*(.*)$") or ""
        if T.HandleBuffCheckCommand then
            T.HandleBuffCheckCommand(args)
        else
            T.msg("团队检查模块未加载")
        end

    else
        T.msg("未知命令: " .. cmd)
    end
end

-- 事件处理
EventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addon_name then
        Initialize()
        
    elseif event == "PLAYER_LOGIN" then
        -- 注册命令（关键修复：必须用数字1结尾）
        SLASH_ST1 = "/st"
        SlashCmdList["ST"] = HandleCommand
        SLASH_SHENGTANGTOOLS1 = "/stt"
        SlashCmdList["SHENGTANGTOOLS"] = HandleCommand

        if C.DB.debugMode then
            T.msg("命令已注册: /st, /stt")
        end

        -- 登录欢迎消息
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00STT|r v%s  使用|cff00ccff/stt|r呼出插件", stt_icon, T.Version))
        DEFAULT_CHAT_FRAME:AddMessage("如果在使用STT的过程中感觉仍然有痛点，欢迎进群提出。STT就是为了解决痛点而生！")
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            L["STT_QQ_CHAT_LINE"] or "加入STT-QQ群获取最新资讯：%s",
            T.GetQQGroupLink((L["STT_QQ_CHAT_LINK_LABEL"] or "{%s}"):format(QQ_GROUP_NUMBER))
        ))

        -- 暴雪时间轴：只在模块 desired=true 的会话恢复视图与注入。
        if T.BlizzardTimeline and T.ModuleLoader and T.ModuleLoader:IsDbEnabled("BlizzardTimeline") then
            C_Timer.After(1, function()
                if T.BlizzardTimeline.ApplyViewSettings then
                    T.BlizzardTimeline:ApplyViewSettings()
                end
                if T.BlizzardTimeline.RecoverIfNeeded then
                    T.BlizzardTimeline:RecoverIfNeeded({ reason = "login" })
                end
            end)
        end

        -- 技能别名字典：延迟 1 秒构建（给 C_Spell API 充分加载时间），
        -- 监听 SPELL_DATA_LOAD_RESULT 重试首次查不到的 ID
        local shouldBuildSpellAlias = T.ModuleLoader
            and (T.ModuleLoader:IsDbEnabled("SemanticTimeline") or T.ModuleLoader:IsDbEnabled("TacticalUI"))
        if shouldBuildSpellAlias and T.SpellAliasIndex and T.SpellAliasIndex.Build then
            C_Timer.After(1, function()
                T.SpellAliasIndex.Build()
            end)
            local retryFrame = CreateFrame("Frame")
            retryFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
            retryFrame:SetScript("OnEvent", function()
                if T.SpellAliasIndex.RetryPending then
                    T.SpellAliasIndex.RetryPending()
                end
            end)
        end

    end
end)
