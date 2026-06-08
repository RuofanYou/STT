local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("personalAuraAlert.enabled", function()

local DB_KEY = "personalAuraAlert"
local DEFAULT_INDICATOR_NAME = "环形#1"
local NEW_SINCE = "260520.46"
local FULL_CONFIG_PATH = DB_KEY .. ".__fullConfig"
local RULE_MERGE_PATH = DB_KEY .. ".__ruleMerge"

local TEXT = {
    zhCN = {
        title = "个人光环提醒",
        subtitle = "按 BOSS 管理个人提醒；内置预设负责开箱即用，自定义规则直接在对应 BOSS 下新增和编辑。",
        add = "新增规则",
        observed = "观测记录",
        edit = "编辑",
        delete = "删除",
        test = "测试",
        save = "保存",
        cancel = "取消",
        dialogNew = "新增个人警告规则",
        dialogEdit = "编辑个人警告规则",
        observedTitle = "本场个人警告观测",
        observedCopyHint = "这里列出最近一场战斗中 STT 收到的 ENCOUNTER_WARNING，已按 Boss、难度、severity、公开名称/SpellID 去重。",
        observedEmpty = "暂无观测记录。进战斗后被个人警告点名一次，再打开这里查看。",
        observedHeader = "Boss %s · 难度 %s · 记录 %d 条",
        observedRow = "%02d. 名称=%s | severity=%s | spellID=%s | 图标=%s | 原始时长=%s | 次数=%d | 首次=%.1fs",
        unknown = "未知",
        enabled = "启用",
        encounter = "Boss ID",
        difficulty = "难度",
        severity = "严重等级",
        text = "显示名称",
        duration = "倒计时秒数",
        timeWindow = "时间窗口",
        countdownAudio = "倒数语音",
        requireShouldPlaySound = "仅匹配应播放声音",
        indicator = "显示样式",
        empty = "暂无规则。点击“新增规则”创建。",
        missing = "当前选择：%s（未找到）",
        invalidEncounter = "个人光环提醒：Boss ID 必须是数字",
        invalidSeverity = "个人光环提醒：严重等级必须是数字",
        invalidDuration = "个人光环提醒：倒计时秒数必须大于 0",
        invalidTimeWindow = "个人光环提醒：时间窗口格式应类似 0:05-1:30, 2:10-2:40",
        invalidText = "个人光环提醒：显示名称不能为空",
        allTimeWindow = "全程",
        audioOn = "语音",
        soundRequiredShort = "本机音",
        allDifficulty = "全部难度",
        story = "剧情 (220)",
        lfr = "随机 (7/17)",
        normal = "普通 (14)",
        heroic = "英雄 (15)",
        mythic = "史诗 (16)",
        mplus = "大秘境 (8)",
        customDifficulty = "自定义难度：%s",
        rowFormat = "%s · Boss %s · %s · severity %s · %s · %.1fs · %s · %s · %s",
        disabledTag = "已停用",
        enabledTag = "启用",
        hint = "命中 ENCOUNTER_WARNING 时按 Boss、难度、severity、时间窗口和可选 shouldPlaySound 精确匹配；空难度表示全部难度，空时间窗口表示全程。倒计时固定按规则秒数显示，不使用屏幕提醒样式的提前量；倒数语音按规则倒计时秒数播放。",
    },
    zhTW = {
        title = "個人光環提醒",
        subtitle = "按 BOSS 管理個人提醒；內建預設負責開箱即用，自訂規則直接在對應 BOSS 下新增和編輯。",
        add = "新增規則",
        observed = "觀測記錄",
        edit = "編輯",
        delete = "刪除",
        test = "測試",
        save = "儲存",
        cancel = "取消",
        dialogNew = "新增個人警告規則",
        dialogEdit = "編輯個人警告規則",
        observedTitle = "本場個人警告觀測",
        observedCopyHint = "這裡列出最近一場戰鬥中 STT 收到的 ENCOUNTER_WARNING，已按 Boss、難度、severity、公開名稱/SpellID 去重。",
        observedEmpty = "暫無觀測記錄。進戰鬥後被個人警告點名一次，再打開這裡查看。",
        observedHeader = "Boss %s · 難度 %s · 記錄 %d 條",
        observedRow = "%02d. 名稱=%s | severity=%s | spellID=%s | 圖示=%s | 原始時長=%s | 次數=%d | 首次=%.1fs",
        unknown = "未知",
        enabled = "啟用",
        encounter = "Boss ID",
        difficulty = "難度",
        severity = "嚴重等級",
        text = "顯示名稱",
        duration = "倒數秒數",
        timeWindow = "時間窗口",
        countdownAudio = "倒數語音",
        requireShouldPlaySound = "僅匹配應播放聲音",
        indicator = "顯示樣式",
        empty = "暫無規則。點擊「新增規則」建立。",
        missing = "目前選擇：%s（未找到）",
        invalidEncounter = "個人光環提醒：Boss ID 必須是數字",
        invalidSeverity = "個人光環提醒：嚴重等級必須是數字",
        invalidDuration = "個人光環提醒：倒數秒數必須大於 0",
        invalidTimeWindow = "個人光環提醒：時間窗口格式應類似 0:05-1:30, 2:10-2:40",
        invalidText = "個人光環提醒：顯示名稱不能為空",
        allTimeWindow = "全程",
        audioOn = "語音",
        soundRequiredShort = "本機音",
        allDifficulty = "全部難度",
        story = "劇情 (220)",
        lfr = "隨機 (7/17)",
        normal = "普通 (14)",
        heroic = "英雄 (15)",
        mythic = "傳奇 (16)",
        mplus = "傳奇鑰石 (8)",
        customDifficulty = "自訂難度：%s",
        rowFormat = "%s · Boss %s · %s · severity %s · %s · %.1fs · %s · %s · %s",
        disabledTag = "已停用",
        enabledTag = "啟用",
        hint = "命中 ENCOUNTER_WARNING 時按 Boss、難度、severity、時間窗口和可選 shouldPlaySound 精確匹配；空難度表示全部難度，空時間窗口表示全程。倒數固定按規則秒數顯示，不使用螢幕提醒樣式的提前量；倒數語音按規則倒數秒數播放。",
    },
    enUS = {
        title = "Personal Aura Alert",
        subtitle = "Manage personal alerts by BOSS. Built-in presets work out of the box, and custom rules are added or edited under the matching BOSS.",
        add = "Add rule",
        observed = "Observed",
        edit = "Edit",
        delete = "Delete",
        test = "Test",
        save = "Save",
        cancel = "Cancel",
        dialogNew = "Add Personal Warning Rule",
        dialogEdit = "Edit Personal Warning Rule",
        observedTitle = "Observed Personal Warnings",
        observedCopyHint = "This lists ENCOUNTER_WARNING events STT received in the latest encounter, deduped by Boss, difficulty, severity, public name, and SpellID.",
        observedEmpty = "No observed warnings yet. Enter combat, receive a personal warning, then open this window.",
        observedHeader = "Boss %s · Difficulty %s · %d records",
        observedRow = "%02d. name=%s | severity=%s | spellID=%s | icon=%s | rawDuration=%s | count=%d | first=%.1fs",
        unknown = "Unknown",
        enabled = "Enabled",
        encounter = "Boss ID",
        difficulty = "Difficulty",
        severity = "Severity",
        text = "Display name",
        duration = "Countdown seconds",
        timeWindow = "Time window",
        countdownAudio = "Countdown audio",
        requireShouldPlaySound = "Require shouldPlaySound",
        indicator = "Display style",
        empty = "No rules yet. Click Add rule to create one.",
        missing = "Current selection: %s (not found)",
        invalidEncounter = "Personal Aura Alert: Boss ID must be a number",
        invalidSeverity = "Personal Aura Alert: severity must be a number",
        invalidDuration = "Personal Aura Alert: countdown seconds must be greater than 0",
        invalidTimeWindow = "Personal Aura Alert: time window should look like 0:05-1:30, 2:10-2:40",
        invalidText = "Personal Aura Alert: display name cannot be empty",
        allTimeWindow = "All fight",
        audioOn = "Audio",
        soundRequiredShort = "SoundOnly",
        allDifficulty = "All difficulties",
        story = "Story (220)",
        lfr = "LFR (7/17)",
        normal = "Normal (14)",
        heroic = "Heroic (15)",
        mythic = "Mythic (16)",
        mplus = "Mythic+ (8)",
        customDifficulty = "Custom difficulty: %s",
        rowFormat = "%s · Boss %s · %s · severity %s · %s · %.1fs · %s · %s · %s",
        disabledTag = "Disabled",
        enabledTag = "Enabled",
        hint = "When ENCOUNTER_WARNING fires, rules match Boss, difficulty, severity, time window, and optional shouldPlaySound exactly. Empty difficulty means all, and an empty time window means the whole fight. The countdown uses the rule seconds and ignores the screen reminder lead time; countdown audio follows the rule countdown seconds.",
    },
}

local TXT = TEXT[T.Client] or TEXT.enUS
L[TXT.title] = TXT.title

local LOCALE_FIELDS = {
    screenReminderSettings = "PERSONAL_AURA_ALERT_SCREEN_REMINDER_SETTINGS",
    newCustom = "PERSONAL_AURA_ALERT_NEW_CUSTOM",
    builtInTag = "PERSONAL_AURA_ALERT_BUILT_IN_TAG",
    customTag = "PERSONAL_AURA_ALERT_CUSTOM_TAG",
    uncalibratedTag = "PERSONAL_AURA_ALERT_EXPERIMENTAL_TAG",
    colName = "PERSONAL_AURA_ALERT_COL_NAME",
    colIndicator = "PERSONAL_AURA_ALERT_COL_INDICATOR",
    newBossGroup = "PERSONAL_AURA_ALERT_NEW_BOSS_GROUP",
    newBossGroupHint = "PERSONAL_AURA_ALERT_NEW_BOSS_GROUP_HINT",
    bossNameInput = "PERSONAL_AURA_ALERT_BOSS_NAME_INPUT",
    bossIDInput = "PERSONAL_AURA_ALERT_BOSS_ID_INPUT",
    createBossGroup = "PERSONAL_AURA_ALERT_CREATE_BOSS_GROUP",
    invalidBossGroup = "PERSONAL_AURA_ALERT_INVALID_BOSS_GROUP",
    uncalibratedHint = "PERSONAL_AURA_ALERT_EXPERIMENTAL_HINT",
    deletePresetHint = "PERSONAL_AURA_ALERT_DELETE_PRESET_HINT",
    deleteBossGroup = "PERSONAL_AURA_ALERT_DELETE_BOSS_GROUP",
    deleteBossGroupConfirm = "PERSONAL_AURA_ALERT_DELETE_BOSS_GROUP_CONFIRM",
    deleteBossGroupAccept = "PERSONAL_AURA_ALERT_DELETE_BOSS_GROUP_ACCEPT",
    shiftPushHint = "PERSONAL_AURA_ALERT_SHIFT_PUSH_HINT",
    importConflictTag = "PERSONAL_AURA_ALERT_IMPORT_CONFLICT_TAG",
    importHeader = "PERSONAL_AURA_ALERT_IMPORT_HEADER",
    importModeHelp = "PERSONAL_AURA_ALERT_IMPORT_MODE_HELP",
    importModuleSwitch = "PERSONAL_AURA_ALERT_IMPORT_MODULE_SWITCH",
    importPresetBossState = "PERSONAL_AURA_ALERT_IMPORT_PRESET_BOSS_STATE",
    importRuleListTitle = "PERSONAL_AURA_ALERT_IMPORT_RULE_LIST_TITLE",
    importHiddenMore = "PERSONAL_AURA_ALERT_IMPORT_HIDDEN_MORE",
    importFailed = "PERSONAL_AURA_ALERT_IMPORT_FAILED",
    fullConfigText = "PERSONAL_AURA_ALERT_FULL_CONFIG_TEXT",
    ruleMergeText = "PERSONAL_AURA_ALERT_RULE_MERGE_TEXT",
    ruleLabelPrefix = "PERSONAL_AURA_ALERT_RULE_LABEL_PREFIX",
}
for field, key in pairs(LOCALE_FIELDS) do
    TXT[field] = L[key]
end

local DIFFICULTY_PRESETS = {
    { key = "all", textKey = "allDifficulty", ids = {} },
    { key = "story", textKey = "story", ids = { 220 } },
    { key = "lfr", textKey = "lfr", ids = { 7, 17 } },
    { key = "normal", textKey = "normal", ids = { 14 } },
    { key = "heroic", textKey = "heroic", ids = { 15 } },
    { key = "mythic", textKey = "mythic", ids = { 16 } },
    { key = "mplus", textKey = "mplus", ids = { 8 } },
}

local dialog
local observedDialog
local expandedBossGroups = {}

local function Msg(text)
    if T.msg then
        T.msg(text)
    end
end

local function ApplyEnabled()
    if T.PersonalAuraAlert and T.PersonalAuraAlert.RefreshConfig then
        T.PersonalAuraAlert:RefreshConfig("option")
    end
end

local function RebuildSoon(engine)
    if not (engine and engine.Rebuild) then
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if engine and engine.Rebuild then
                engine:Rebuild()
            end
        end)
    else
        engine:Rebuild()
    end
end

local function GetFullConfig()
    if T.PersonalAuraAlert and T.PersonalAuraAlert.BuildImportPayload then
        return T.PersonalAuraAlert:BuildImportPayload()
    end
    return { rules = {} }
end

local function RefreshPersonalAuraImport(stats)
    if T.OptionEngine then
        if T.OptionEngine.RefreshWidgetValues then
            T.OptionEngine:RefreshWidgetValues()
        end
        if T.OptionEngine.RefreshDependStates then
            T.OptionEngine:RefreshDependStates()
        end
        if T.OptionEngine.Rebuild then
            T.OptionEngine:Rebuild()
        end
    end
end

local function ApplyPersonalAuraImport(value, mode)
    if type(value) ~= "table" then
        return nil
    end
    if not (T.PersonalAuraAlert and T.PersonalAuraAlert.ApplyImportPayload) then
        return nil
    end
    local stats = T.PersonalAuraAlert:ApplyImportPayload(value, mode)
    if not stats then
        return nil
    end
    RefreshPersonalAuraImport(stats)
    if T.debug then
        local rules = T.PersonalAuraAlert.GetRules and T.PersonalAuraAlert:GetRules() or {}
        T.debug(string.format("[OptionPush] PersonalAuraImportApplied mode=%s sourceCount=%d added=%d replaced=%d presetTouched=%d customBossTouched=%d ruleCount=%d",
            tostring(stats.mode),
            tonumber(stats.sourceCount) or 0,
            tonumber(stats.added) or 0,
            tonumber(stats.replaced) or 0,
            tonumber(stats.presetTouched) or 0,
            tonumber(stats.customBossTouched) or 0,
            type(rules) == "table" and #rules or 0))
        if type(stats.details) == "table" then
            for _, detail in ipairs(stats.details) do
                if detail.action == "replace" then
                    T.debug(string.format("[OptionPush] PersonalAuraRuleReplaced sourceKey=%s localID=%s text=%s",
                        tostring(detail.sourceKey),
                        tostring(detail.localID),
                        tostring(detail.text)))
                else
                    T.debug(string.format("[OptionPush] PersonalAuraRuleMerged sourceKey=%s localID=%s text=%s",
                        tostring(detail.sourceKey),
                        tostring(detail.localID),
                        tostring(detail.text)))
                end
            end
        end
    end
    return stats
end

local function SetFullConfig(value)
    ApplyPersonalAuraImport(value, "replace")
end

local function ApplyFullConfig()
end

local function SetRuleMerge(value)
    ApplyPersonalAuraImport(value, "merge")
end

local function ApplyRuleMerge()
end

local function CopyIDs(ids)
    local out = {}
    if type(ids) == "table" then
        for _, value in ipairs(ids) do
            local id = tonumber(value)
            if id and id > 0 then
                out[#out + 1] = id
            end
        end
    end
    table.sort(out)
    return out
end

local function SameIDs(a, b)
    local aa = CopyIDs(a)
    local bb = CopyIDs(b)
    if #aa ~= #bb then
        return false
    end
    for index, value in ipairs(aa) do
        if value ~= bb[index] then
            return false
        end
    end
    return true
end

local function JoinIDs(ids)
    local parts = {}
    for _, value in ipairs(CopyIDs(ids)) do
        parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, "/")
end

local function DifficultyKeyFromIDs(ids)
    local normalized = CopyIDs(ids)
    for _, preset in ipairs(DIFFICULTY_PRESETS) do
        if SameIDs(normalized, preset.ids) then
            return preset.key
        end
    end
    return "custom"
end

local function IDsFromDifficultyKey(key, originalIDs)
    if key == "custom" then
        return CopyIDs(originalIDs)
    end
    for _, preset in ipairs(DIFFICULTY_PRESETS) do
        if preset.key == key then
            return CopyIDs(preset.ids)
        end
    end
    return {}
end

local function DifficultyLabel(ids)
    local key = DifficultyKeyFromIDs(ids)
    for _, preset in ipairs(DIFFICULTY_PRESETS) do
        if preset.key == key then
            return TXT[preset.textKey]
        end
    end
    local joined = JoinIDs(ids)
    return string.format(TXT.customDifficulty, joined ~= "" and joined or "-")
end

local function BuildDifficultyItems(selectedKey, originalIDs)
    local items = {}
    for _, preset in ipairs(DIFFICULTY_PRESETS) do
        items[#items + 1] = { text = TXT[preset.textKey], value = preset.key }
    end
    if selectedKey == "custom" then
        items[#items + 1] = {
            text = string.format(TXT.customDifficulty, JoinIDs(originalIDs)),
            value = "custom",
            disabled = true,
        }
    end
    return items
end

local function BuildIndicatorItems(selected)
    local selectedValue = tostring(selected or DEFAULT_INDICATOR_NAME)
    local selectedSeen = false
    local options = {}
    local schema = T.ScreenReminderSchema
    local indicators = {}
    if schema and schema.ListIndicators then
        local ok, list = pcall(schema.ListIndicators)
        if ok and type(list) == "table" then
            indicators = list
        end
    end
    for _, indicator in ipairs(indicators) do
        local name = tostring(indicator and indicator.name or "")
        if name ~= "" then
            selectedSeen = selectedSeen or name == selectedValue
            options[#options + 1] = { text = name, value = name }
        end
    end
    if selectedValue ~= "" and not selectedSeen then
        table.insert(options, 1, {
            text = string.format(TXT.missing, selectedValue),
            value = selectedValue,
            disabled = true,
        })
    end
    return options
end

local function FormatNumber(value)
    local number = tonumber(value) or 0
    if math.abs(number - math.floor(number + 0.5)) < 0.0001 then
        return tostring(math.floor(number + 0.5))
    end
    return tostring(number)
end

local function FormatMaybeNumber(value)
    if value == nil or value == "" then
        return TXT.unknown
    end
    return FormatNumber(value)
end

local function FormatValue(value)
    if value == nil or value == "" then
        return TXT.unknown
    end
    return tostring(value)
end

local function ParseTimeWindowInput(text)
    if not (T.PersonalAuraAlert and T.PersonalAuraAlert.ParseTimeWindows) then
        return {}, nil
    end
    return T.PersonalAuraAlert:ParseTimeWindows(text)
end

local function FormatTimeWindows(windows)
    if T.PersonalAuraAlert and T.PersonalAuraAlert.FormatTimeWindows then
        return T.PersonalAuraAlert:FormatTimeWindows(windows)
    end
    return ""
end

local function TimeWindowLabel(windows)
    local text = FormatTimeWindows(windows)
    return text ~= "" and text or TXT.allTimeWindow
end

local function CountdownAudioLabel(rule)
    return rule and rule.countdownAudioEnabled == true and TXT.audioOn or "-"
end

local function ShouldPlaySoundLabel(rule)
    return rule and rule.requireShouldPlaySound == true and TXT.soundRequiredShort or "-"
end

local function BuildObservedText()
    local session = T.PersonalAuraAlert and T.PersonalAuraAlert:GetObservedWarnings()
    local items = type(session) == "table" and session.items or nil
    if type(items) ~= "table" or #items == 0 then
        return TXT.observedEmpty
    end

    local lines = {
        TXT.observedCopyHint,
        "",
        string.format(TXT.observedHeader,
            FormatValue(session.encounterID),
            FormatValue(session.difficultyID),
            #items),
        "",
    }
    local startedAt = tonumber(session.startedAt) or 0
    for index, item in ipairs(items) do
        local firstSeen = tonumber(item.firstSeen) or startedAt
        local firstOffset = startedAt > 0 and math.max(0, firstSeen - startedAt) or 0
        lines[#lines + 1] = string.format(TXT.observedRow,
            index,
            FormatValue(item.name),
            FormatValue(item.severity),
            FormatValue(item.tooltipSpellID),
            FormatValue(item.iconFileID),
            FormatMaybeNumber(item.duration),
            tonumber(item.count) or 0,
            firstOffset)
    end
    return table.concat(lines, "\n")
end

local function ReadRuleFromDialog()
    local encounterID = tonumber(dialog.encounterEdit:GetText())
    if not encounterID then
        Msg(TXT.invalidEncounter)
        return nil
    end
    local severity = tonumber(dialog.severityEdit:GetText())
    if not severity then
        Msg(TXT.invalidSeverity)
        return nil
    end
    local duration = tonumber(dialog.durationEdit:GetText())
    if not duration or duration <= 0 then
        Msg(TXT.invalidDuration)
        return nil
    end
    local text = tostring(dialog.textEdit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        Msg(TXT.invalidText)
        return nil
    end
    local timeWindows = ParseTimeWindowInput(dialog.timeWindowEdit and dialog.timeWindowEdit:GetText() or "")
    if not timeWindows then
        Msg(TXT.invalidTimeWindow)
        return nil
    end
    local difficultyKey = dialog.difficultySelector:GetSelectedValue() or "all"
    return {
        enabled = dialog.enabledCheck:GetChecked() == true,
        encounterID = encounterID,
        difficultyIDs = IDsFromDifficultyKey(difficultyKey, dialog.originalDifficultyIDs),
        severity = severity,
        text = text,
        durationSec = duration,
        timeWindows = timeWindows,
        countdownAudioEnabled = dialog.countdownAudioCheck and dialog.countdownAudioCheck:GetChecked() == true,
        requireShouldPlaySound = dialog.requireShouldPlaySoundCheck and dialog.requireShouldPlaySoundCheck:GetChecked() == true,
        indicatorName = dialog.indicatorSelector:GetSelectedValue() or DEFAULT_INDICATOR_NAME,
    }
end

local function EnsureDialog()
    if dialog then
        return dialog
    end

    dialog = T.CreatePopupWindow(UIParent, {
        width = 520,
        height = 484,
        title = TXT.dialogEdit,
        alpha = 0.94,
        style = "chat",
        strata = "DIALOG",
    })

    dialog.enabledCheck = T.CreateCheckbox(dialog, {
        point = { "TOPLEFT", dialog, "TOPLEFT", 22, -48 },
        label = TXT.enabled,
        clickLabel = true,
    })

    T.CreateLabel(dialog, { point = { "TOPLEFT", dialog, "TOPLEFT", 22, -82 }, text = TXT.encounter, size = 12 })
    dialog.encounterEdit = T.CreateEditBox(dialog, {
        width = 210,
        height = 26,
        point = { "TOPLEFT", dialog, "TOPLEFT", 22, -102 },
        placeholder = "3183",
    })

    T.CreateLabel(dialog, { point = { "TOPLEFT", dialog, "TOPLEFT", 272, -82 }, text = TXT.severity, size = 12 })
    dialog.severityEdit = T.CreateEditBox(dialog, {
        width = 210,
        height = 26,
        point = { "TOPLEFT", dialog, "TOPLEFT", 272, -102 },
        placeholder = "1",
    })

    T.CreateLabel(dialog, { point = { "TOPLEFT", dialog, "TOPLEFT", 22, -140 }, text = TXT.text, size = 12 })
    dialog.textEdit = T.CreateEditBox(dialog, {
        width = 210,
        height = 26,
        point = { "TOPLEFT", dialog, "TOPLEFT", 22, -160 },
        placeholder = "星辰裂片",
    })

    T.CreateLabel(dialog, { point = { "TOPLEFT", dialog, "TOPLEFT", 272, -140 }, text = TXT.duration, size = 12 })
    dialog.durationEdit = T.CreateEditBox(dialog, {
        width = 210,
        height = 26,
        point = { "TOPLEFT", dialog, "TOPLEFT", 272, -160 },
        placeholder = "2.9",
    })

    T.CreateLabel(dialog, { point = { "TOPLEFT", dialog, "TOPLEFT", 22, -202 }, text = TXT.timeWindow, size = 12 })
    dialog.timeWindowEdit = T.CreateEditBox(dialog, {
        width = 460,
        height = 26,
        point = { "TOPLEFT", dialog, "TOPLEFT", 22, -222 },
        placeholder = "留空=全程；例：0:05-1:30, 2:10-2:40",
    })

    dialog.difficultySelector = T.CreateSelectorButton(dialog, {
        width = 460,
        height = 26,
        point = { "TOPLEFT", dialog, "TOPLEFT", 22, -270 },
        label = TXT.difficulty,
        labelWidth = 96,
        ownerFrame = dialog,
    })

    dialog.indicatorSelector = T.CreateSelectorButton(dialog, {
        width = 460,
        height = 26,
        point = { "TOPLEFT", dialog, "TOPLEFT", 22, -308 },
        label = TXT.indicator,
        labelWidth = 96,
        ownerFrame = dialog,
    })

    dialog.countdownAudioCheck = T.CreateCheckbox(dialog, {
        point = { "TOPLEFT", dialog, "TOPLEFT", 22, -348 },
        label = TXT.countdownAudio,
        clickLabel = true,
    })

    dialog.requireShouldPlaySoundCheck = T.CreateCheckbox(dialog, {
        point = { "TOPLEFT", dialog, "TOPLEFT", 22, -382 },
        label = TXT.requireShouldPlaySound,
        clickLabel = true,
    })

    dialog.saveButton = T.CreateButton(dialog, { width = 86, height = 26, point = { "BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -112, 18 } })
    dialog.saveButton:SetText(TXT.save)
    dialog.saveButton:SetScript("OnClick", function()
        local values = ReadRuleFromDialog()
        if not values then
            return
        end
        if dialog.presetKey then
            T.PersonalAuraAlert:UpdatePresetRule(dialog.presetKey, values)
        elseif dialog.ruleID then
            T.PersonalAuraAlert:UpdateRule(dialog.ruleID, values)
        else
            T.PersonalAuraAlert:CreateRule(values)
        end
        dialog:Hide()
        if dialog.engine and dialog.engine.Rebuild then
            dialog.engine:Rebuild()
        end
    end)

    dialog.cancelButton = T.CreateButton(dialog, { width = 86, height = 26, point = { "LEFT", dialog.saveButton, "RIGHT", 8, 0 } })
    dialog.cancelButton:SetText(TXT.cancel)
    dialog.cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)

    return dialog
end

local function RefreshObservedDialog()
    if not observedDialog then
        return
    end
    observedDialog.title:SetText(TXT.observedTitle)
    observedDialog.editor:SetText(BuildObservedText())
end

local function EnsureObservedDialog()
    if observedDialog then
        return observedDialog
    end

    observedDialog = T.CreatePopupWindow(UIParent, {
        width = 760,
        height = 440,
        title = TXT.observedTitle,
        alpha = 0.94,
        style = "chat",
        strata = "DIALOG",
    })

    local hint = observedDialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", observedDialog, "TOPLEFT", 14, -36)
    hint:SetPoint("RIGHT", observedDialog, "RIGHT", -14, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(TXT.observedCopyHint)
    observedDialog.hint = hint

    observedDialog.editor = T.CreateScrollEditBox(observedDialog, {
        stepSize = 36,
        blendSpeed = 0.12,
        textInsets = { 8, 8, 8, 8 },
        fontObject = ChatFontNormal,
        disableCursorAutoScroll = true,
    })
    observedDialog.editor:SetPoint("TOPLEFT", observedDialog, "TOPLEFT", 14, -58)
    observedDialog.editor:SetPoint("BOTTOMRIGHT", observedDialog, "BOTTOMRIGHT", -14, 52)
    observedDialog.editor.editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    observedDialog.closeButton = T.CreateButton(observedDialog, { width = 86, height = 26, point = { "BOTTOMRIGHT", observedDialog, "BOTTOMRIGHT", -18, 18 } })
    observedDialog.closeButton:SetText(TXT.cancel)
    observedDialog.closeButton:SetScript("OnClick", function()
        observedDialog:Hide()
    end)

    observedDialog:HookScript("OnShow", RefreshObservedDialog)
    return observedDialog
end

local function OpenObservedDialog()
    local frame = EnsureObservedDialog()
    RefreshObservedDialog()
    frame:Show()
end

local function EnsureDeleteBossGroupPopup()
    if StaticPopupDialogs["STT_PERSONAL_AURA_DELETE_BOSS_GROUP"] then
        return
    end
    StaticPopupDialogs["STT_PERSONAL_AURA_DELETE_BOSS_GROUP"] = {
        text = TXT.deleteBossGroupConfirm,
        button1 = TXT.deleteBossGroupAccept,
        button2 = TXT.cancel,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function(_, data)
            if type(data) ~= "table" then
                return
            end
            if T.PersonalAuraAlert and T.PersonalAuraAlert.DeleteCustomBossGroup then
                T.PersonalAuraAlert:DeleteCustomBossGroup(data.encounterID)
            end
            expandedBossGroups[tonumber(data.encounterID)] = nil
            RebuildSoon(data.engine)
        end,
    }
end

local function ConfirmDeleteBossGroup(group, engine)
    EnsureDeleteBossGroupPopup()
    StaticPopup_Show("STT_PERSONAL_AURA_DELETE_BOSS_GROUP", tostring(group and group.name or ""), nil, {
        encounterID = group and group.encounterID,
        engine = engine,
    })
end

local function OpenRuleDialog(rule, engine, templateEncounterID)
    local frame = EnsureDialog()
    local data = rule or (T.PersonalAuraAlert and T.PersonalAuraAlert:BuildRuleTemplate(templateEncounterID)) or {}
    local encounterLocked = (rule and rule.isPreset == true) or templateEncounterID ~= nil
    frame.engine = engine
    frame.ruleID = rule and rule.id or nil
    frame.presetKey = rule and rule.presetKey or nil
    frame.encounterLocked = encounterLocked
    frame.originalDifficultyIDs = CopyIDs(data.difficultyIDs)
    frame.title:SetText(rule and TXT.dialogEdit or TXT.dialogNew)
    frame.enabledCheck:SetChecked(data.enabled ~= false)
    frame.encounterEdit:SetText(tostring(data.encounterID or 3183))
    if frame.encounterEdit.SetEnabled then
        frame.encounterEdit:SetEnabled(not encounterLocked)
    end
    frame.severityEdit:SetText(tostring(data.severity or 1))
    frame.textEdit:SetText(tostring(data.text or "星辰裂片"))
    frame.durationEdit:SetText(FormatNumber(data.durationSec or 2.9))
    frame.timeWindowEdit:SetText(FormatTimeWindows(data.timeWindows))
    frame.countdownAudioCheck:SetChecked(data.countdownAudioEnabled == true)
    frame.requireShouldPlaySoundCheck:SetChecked(data.requireShouldPlaySound == true)

    local difficultyKey = DifficultyKeyFromIDs(data.difficultyIDs)
    frame.difficultySelector:SetItems(BuildDifficultyItems(difficultyKey, data.difficultyIDs))
    frame.difficultySelector:SetSelectedValue(difficultyKey)

    local indicatorName = tostring(data.indicatorName or DEFAULT_INDICATOR_NAME)
    frame.indicatorSelector:SetItems(BuildIndicatorItems(indicatorName))
    frame.indicatorSelector:SetSelectedValue(indicatorName)
    frame:Show()
end

local function RuleSummary(rule)
    local tag = rule.enabled == false and TXT.disabledTag or TXT.enabledTag
    return string.format(TXT.rowFormat,
        tag,
        tostring(rule.encounterID or "-"),
        DifficultyLabel(rule.difficultyIDs),
        tostring(rule.severity or "-"),
        TimeWindowLabel(rule.timeWindows),
        tonumber(rule.durationSec) or 0,
        CountdownAudioLabel(rule),
        ShouldPlaySoundLabel(rule),
        tostring(rule.text or ""))
end

local function ImportRuleKey(rule)
    local difficultyText = JoinIDs(rule and rule.difficultyIDs)
    if difficultyText == "" then
        difficultyText = "all"
    end
    local windowText = FormatTimeWindows(rule and rule.timeWindows)
    if windowText == "" then
        windowText = "all"
    end
    return table.concat({
        tostring(tonumber(rule and rule.encounterID) or 0),
        difficultyText,
        tostring(tonumber(rule and rule.severity) or 0),
        tostring(rule and rule.text or ""),
        windowText,
    }, "|")
end

local function BuildImportDiff(value, expanded)
    local sourceRules = type(value) == "table" and type(value.rules) == "table" and value.rules or {}
    local localKeys = {}
    if T.PersonalAuraAlert and T.PersonalAuraAlert.GetRules then
        for _, rule in ipairs(T.PersonalAuraAlert:GetRules()) do
            localKeys[ImportRuleKey(rule)] = true
        end
    end

    local conflictCount = 0
    local lines = {}
    for _, rule in ipairs(sourceRules) do
        local key = ImportRuleKey(rule)
        local conflict = localKeys[key] == true
        if conflict then
            conflictCount = conflictCount + 1
        end
        if expanded and #lines < 8 then
            lines[#lines + 1] = string.format("%s%s", RuleSummary(rule), conflict and TXT.importConflictTag or "")
        end
    end

    local header = {
        string.format(TXT.importHeader, #sourceRules, conflictCount),
        TXT.importModeHelp,
    }
    if type(value) == "table" and value.applyModuleFields == true then
        local enabled = C and C.DB and C.DB[DB_KEY] and C.DB[DB_KEY].enabled == true
        header[#header + 1] = string.format(TXT.importModuleSwitch, tostring(enabled), tostring(value.enabled == true))
        local presetCount = 0
        for _ in pairs(type(value.presetState) == "table" and value.presetState or {}) do
            presetCount = presetCount + 1
        end
        local bossCount = type(value.customBosses) == "table" and #value.customBosses or 0
        if presetCount > 0 or bossCount > 0 then
            header[#header + 1] = string.format(TXT.importPresetBossState, presetCount, bossCount)
        end
    end
    if expanded then
        if #lines > 0 then
            header[#header + 1] = TXT.importRuleListTitle
            for _, line in ipairs(lines) do
                header[#header + 1] = " - " .. line
            end
        end
        if #sourceRules > #lines then
            header[#header + 1] = string.format(TXT.importHiddenMore, #sourceRules - #lines)
        end
    end
    return table.concat(header, "\n")
end

T.PersonalAuraAlertOptionPush = T.PersonalAuraAlertOptionPush or {}
function T.PersonalAuraAlertOptionPush.IsImportPath(dbPath)
    return dbPath == FULL_CONFIG_PATH or dbPath == RULE_MERGE_PATH
end

function T.PersonalAuraAlertOptionPush.BuildImport(value, dbPath)
    if not T.PersonalAuraAlertOptionPush.IsImportPath(dbPath) then
        return nil
    end
    return {
        kind = dbPath == FULL_CONFIG_PATH and "full" or "rule",
        value = value,
        buildDiffText = BuildImportDiff,
        moduleText = TXT.title,
        failedText = TXT.importFailed,
    }
end

function T.PersonalAuraAlertOptionPush.ApplyImport(value, mode, kind)
    return ApplyPersonalAuraImport(value, mode)
end

function T.PersonalAuraAlertOptionPush.SendRule(ruleID)
    local share = T.OptionShare
    if not (T.PersonalAuraAlert and T.PersonalAuraAlert.BuildImportPayload and share and share.SendPayload) then
        return false
    end
    local payload = T.PersonalAuraAlert:BuildImportPayload(ruleID)
    if not payload then
        return false
    end
    local rule = payload.rules and payload.rules[1]
    local itemLabel = rule and RuleSummary(rule) or tostring(ruleID or "")
    return share:SendPayload({
        v = T.Version or "0",
        mode = "item",
        moduleId = "personalAuraAlert",
        label = TXT.title .. " > " .. itemLabel,
        entries = {
            [RULE_MERGE_PATH] = payload,
        },
        labels = {
            [RULE_MERGE_PATH] = TXT.ruleLabelPrefix .. itemLabel,
        },
    })
end

local function RuleRowName(rule)
    local tag = rule.isPreset and "" or TXT.customTag
    if rule.isPreset and rule.calibrated ~= true then
        tag = TXT.uncalibratedTag
    end
    if tag == "" then
        return tostring(rule.text or "")
    end
    return string.format("%s (%s)", tostring(rule.text or ""), tag)
end

local function ResolveRenderWidth(slot, context)
    local contextWidth = tonumber(context and context.width)
    local slotWidth = slot and slot.GetWidth and tonumber(slot:GetWidth()) or nil
    local width = contextWidth or slotWidth or 520
    if slotWidth and slotWidth > 0 then
        width = math.min(width, slotWidth)
    end
    return math.max(420, width - 16)
end

local function ResolveRuleColumns(width)
    local buttonWidth = 54
    local buttonGap = 6
    local rightPad = 12
    local selectorGap = 18
    local enabledX = 8
    local enabledWidth = 58
    local nameX = 76
    local deleteX = width - rightPad - buttonWidth
    local editX = deleteX - buttonGap - buttonWidth
    local testX = editX - buttonGap - buttonWidth
    local selectorWidth = math.min(210, math.max(150, math.floor(width * 0.24)))
    local selectorX = testX - selectorGap - selectorWidth
    local nameWidth = selectorX - nameX - selectorGap

    if nameWidth < 110 then
        selectorWidth = math.max(130, selectorWidth - (110 - nameWidth))
        selectorX = testX - selectorGap - selectorWidth
        nameWidth = selectorX - nameX - selectorGap
    end

    return {
        buttonWidth = buttonWidth,
        enabledX = enabledX,
        enabledWidth = enabledWidth,
        checkX = 20,
        nameX = nameX,
        nameWidth = math.max(90, nameWidth),
        selectorX = selectorX,
        selectorWidth = selectorWidth,
        testX = testX,
        editX = editX,
        deleteX = deleteX,
    }
end

local function RenderRuleRow(parent, context, rule, index, width, y)
    local columns = ResolveRuleColumns(width)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetSize(width, 42)
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(_, button)
        if rule.isPreset then
            return
        end
        if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() and T.PersonalAuraAlertOptionPush then
            T.PersonalAuraAlertOptionPush.SendRule(rule.id)
        end
    end)
    row:SetScript("OnEnter", function(owner)
        if rule.isPreset and rule.calibrated ~= true then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", -20, 10)
            GameTooltip:AddLine(TXT.uncalibratedHint, 1, 0.82, 0.2, true)
            GameTooltip:Show()
            return
        end
        if rule.isPreset or not (IsShiftKeyDown and IsShiftKeyDown() and T.OptionShare and T.OptionShare:CanPush(true)) then
            return
        end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", -20, 10)
        GameTooltip:AddLine(TXT.shiftPushHint, 0.35, 0.85, 1, false)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(owner)
        if GameTooltip and GameTooltip:GetOwner() == owner then
            GameTooltip:Hide()
        end
    end)
    T.ApplyBackdrop(row, {
        alpha = index % 2 == 0 and 0.28 or 0.18,
        style = "tooltip",
        borderColor = { 0.45, 0.38, 0.2, 0.45 },
    })

    local check = T.CreateCheckbox(row, {
        point = { "LEFT", row, "LEFT", columns.checkX, 0 },
        label = "",
        getter = function() return rule.enabled ~= false end,
        setter = function(value)
            if T.PersonalAuraAlert then
                local updated = T.PersonalAuraAlert:SetRuleEnabled(rule.id, value == true)
                if not updated and rule.isPreset and rule.calibrated ~= true then
                    Msg(TXT.uncalibratedHint)
                end
            end
            ApplyEnabled()
            if context.engine and context.engine.Rebuild then
                context.engine:Rebuild()
            end
        end,
    })
    check:SetHitRectInsets(0, 0, 0, 0)
    T.CreateLabel(row, {
        point = { "LEFT", row, "LEFT", columns.nameX, 0 },
        width = columns.nameWidth,
        text = RuleRowName(rule),
        size = 11,
        justifyH = "LEFT",
        justifyV = "MIDDLE",
        color = rule.enabled == false and { 0.62, 0.62, 0.62, 1 } or { 1, 1, 1, 1 },
        wordWrap = false,
    })

    T.CreateSelectorButton(row, {
        width = columns.selectorWidth,
        height = 24,
        point = { "LEFT", row, "LEFT", columns.selectorX, 0 },
        label = "",
        labelWidth = 0,
        selectedValue = tostring(rule.indicatorName or DEFAULT_INDICATOR_NAME),
        items = BuildIndicatorItems(rule.indicatorName),
        ownerFrame = row,
        onSelect = function(value)
            if T.PersonalAuraAlert then
                T.PersonalAuraAlert:SetRuleIndicator(rule.id, value)
            end
            ApplyEnabled()
            if context.engine and context.engine.Rebuild then
                context.engine:Rebuild()
            end
        end,
    })

    T.CreateActionButton(row, {
        width = columns.buttonWidth,
        height = 24,
        point = { "LEFT", row, "LEFT", columns.testX, 0 },
        textFn = function() return TXT.test end,
        onClick = function()
            if T.PersonalAuraAlert then
                T.PersonalAuraAlert:RunTest(rule.id)
            end
        end,
    })
    T.CreateActionButton(row, {
        width = columns.buttonWidth,
        height = 24,
        point = { "LEFT", row, "LEFT", columns.editX, 0 },
        textFn = function() return TXT.edit end,
        onClick = function()
            OpenRuleDialog(rule, context.engine)
        end,
    })
    local deleteButton = T.CreateActionButton(row, {
        width = columns.buttonWidth,
        height = 24,
        point = { "LEFT", row, "LEFT", columns.deleteX, 0 },
        textFn = function() return TXT.delete end,
        onClick = function()
            if rule.isPreset then
                Msg(TXT.deletePresetHint)
                return
            end
            if T.PersonalAuraAlert and T.PersonalAuraAlert:DeleteRule(rule.id) then
                if context.engine and context.engine.Rebuild then
                    context.engine:Rebuild()
                end
            end
        end,
    })
    if rule.isPreset and deleteButton.Disable then
        deleteButton:Disable()
    end
end

local function RenderBossGroupContent(parent, context, group, width)
    local y = 0
    local columns = ResolveRuleColumns(width)
    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", columns.enabledX, y },
        width = columns.enabledWidth,
        text = TXT.enabled,
        size = 11,
        justifyH = "CENTER",
        color = { 0.72, 0.72, 0.72, 1 },
    })
    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", columns.nameX, y },
        width = columns.nameWidth,
        text = TXT.colName,
        size = 11,
        justifyH = "LEFT",
        color = { 0.72, 0.72, 0.72, 1 },
    })
    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", columns.selectorX, y },
        width = columns.selectorWidth,
        text = TXT.colIndicator,
        size = 11,
        justifyH = "LEFT",
        color = { 0.72, 0.72, 0.72, 1 },
    })
    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", columns.testX, y },
        width = columns.buttonWidth,
        text = TXT.test,
        size = 11,
        justifyH = "CENTER",
        color = { 0.72, 0.72, 0.72, 1 },
    })
    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", columns.editX, y },
        width = columns.buttonWidth,
        text = TXT.edit,
        size = 11,
        justifyH = "CENTER",
        color = { 0.72, 0.72, 0.72, 1 },
    })
    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", columns.deleteX, y },
        width = columns.buttonWidth,
        text = TXT.delete,
        size = 11,
        justifyH = "CENTER",
        color = { 0.72, 0.72, 0.72, 1 },
    })
    y = y - 24

    local rules = T.PersonalAuraAlert and T.PersonalAuraAlert:ListRulesForBoss(group.encounterID) or {}
    if #rules == 0 then
        T.CreateLabel(parent, {
            point = { "TOPLEFT", parent, "TOPLEFT", 8, y },
            width = width - 16,
            text = TXT.empty,
            size = 12,
            color = { 0.72, 0.72, 0.72, 1 },
        })
        y = y - 32
    else
        for index, rule in ipairs(rules) do
            RenderRuleRow(parent, context, rule, index, width, y)
            y = y - 48
        end
    end
    return math.abs(y) + 4
end

local function EstimateBossGroupContentHeight(group)
    local rules = T.PersonalAuraAlert and T.PersonalAuraAlert:ListRulesForBoss(group.encounterID) or {}
    local rowHeight = #rules > 0 and (#rules * 48) or 32
    return 24 + rowHeight + 4
end

local function EstimateBossSectionHeight(group)
    return 30 + 4 + EstimateBossGroupContentHeight(group) + 12 + 10
end

local function RelayoutBossSections(layout, refreshSections)
    if not (layout and layout.slot) then
        return
    end

    local y = -44
    for _, section in ipairs(layout.sections or {}) do
        if refreshSections ~= false and section.RefreshLayout then
            section:RefreshLayout()
        end
        section:ClearAllPoints()
        section:SetPoint("TOPLEFT", layout.slot, "TOPLEFT", 4, y)
        y = y - section:GetHeight() - 10
    end

    if layout.addBlock then
        layout.addBlock:ClearAllPoints()
        layout.addBlock:SetPoint("TOPLEFT", layout.slot, "TOPLEFT", 4, y)
        y = y - (layout.addHeight or 0)
    end

    if layout.hintLabel then
        layout.hintLabel:ClearAllPoints()
        layout.hintLabel:SetPoint("TOPLEFT", layout.slot, "TOPLEFT", 8, y - 4)
        y = y - 54
    end

    layout.currentHeight = math.max(math.abs(y) + 8, 1)
    layout.slot:SetHeight(layout.currentHeight)
end

local function RenderNewBossGroup(slot, context, width, y)
    local block = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    block:SetPoint("TOPLEFT", slot, "TOPLEFT", 4, y)
    block:SetSize(width - 8, 86)
    T.ApplyBackdrop(block, {
        alpha = 0.18,
        style = "tooltip",
        borderColor = { 0.72, 0.55, 0.12, 0.55 },
    })

    T.CreateLabel(block, {
        point = { "TOPLEFT", block, "TOPLEFT", 12, -10 },
        text = "+ " .. TXT.newBossGroup,
        size = 13,
        color = { 1, 0.86, 0.32, 1 },
    })
    T.CreateLabel(block, {
        point = { "TOPRIGHT", block, "TOPRIGHT", -12, -12 },
        width = 260,
        text = TXT.newBossGroupHint,
        size = 11,
        color = { 0.72, 0.72, 0.72, 1 },
        justifyH = "RIGHT",
    })

    local inputAreaWidth = math.max(240, width - 32 - 104 - 20)
    local nameWidth = math.max(120, math.floor(inputAreaWidth * 0.52))
    local idWidth = math.max(100, inputAreaWidth - nameWidth - 10)

    local nameEdit = T.CreateEditBox(block, {
        width = nameWidth,
        height = 24,
        point = { "TOPLEFT", block, "TOPLEFT", 12, -42 },
        placeholder = TXT.bossNameInput,
    })
    local idEdit = T.CreateEditBox(block, {
        width = idWidth,
        height = 24,
        point = { "LEFT", nameEdit, "RIGHT", 10, 0 },
        placeholder = TXT.bossIDInput,
    })
    T.CreateActionButton(block, {
        width = 104,
        height = 24,
        point = { "TOPRIGHT", block, "TOPRIGHT", -12, -42 },
        textFn = function() return TXT.createBossGroup end,
        onClick = function()
            local id, name = nil, nil
            if T.PersonalAuraAlert and T.PersonalAuraAlert.ResolveBossInput then
                id, name = T.PersonalAuraAlert:ResolveBossInput(nameEdit:GetText(), idEdit:GetText())
            end
            if not id then
                Msg(TXT.invalidBossGroup)
                return
            end
            T.PersonalAuraAlert:EnsureCustomBossGroup(id, name)
            expandedBossGroups[tonumber(id)] = true
            if context.engine and context.engine.Rebuild then
                context.engine:Rebuild()
            end
        end,
    })

    return block, 94
end

local function RenderRules(slot, context)
    local width = ResolveRenderWidth(slot, context)
    local groups = (T.PersonalAuraAlert and T.PersonalAuraAlert:ListBossGroups()) or {}
    local layout = {
        slot = slot,
        sections = {},
    }

    T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -2 },
        width = math.max(120, width - 278),
        text = TXT.subtitle,
        size = 11,
        color = { 0.82, 0.82, 0.82, 1 },
        wordWrap = true,
    })

    T.CreateActionButton(slot, {
        width = 110,
        height = 26,
        point = { "TOPRIGHT", slot, "TOPRIGHT", -12, -4 },
        textFn = function() return TXT.observed end,
        onClick = OpenObservedDialog,
    })
    T.CreateActionButton(slot, {
        width = 132,
        height = 26,
        point = { "TOPRIGHT", slot, "TOPRIGHT", -126, -4 },
        textFn = function() return TXT.screenReminderSettings end,
        onClick = function()
            if T.OpenSettingsModule then
                T.OpenSettingsModule("screen_remind")
            end
        end,
    })

    local reservedY = -44
    for index, group in ipairs(groups) do
        if expandedBossGroups[group.encounterID] == nil then
            expandedBossGroups[group.encounterID] = index == 1
        end
        reservedY = reservedY - EstimateBossSectionHeight(group) - 10
        local label = string.format("%s  %s %d · %s %d",
            tostring(group.name or group.encounterID),
            TXT.builtInTag,
            tonumber(group.presetCount) or 0,
            TXT.customTag,
            tonumber(group.customCount) or 0)
        local hasDeleteGroup = group.isCustomBossGroup == true and (tonumber(group.presetCount) or 0) == 0
        local headerReserve = hasDeleteGroup and 220 or 130
        local section = T.CreateCollapsibleSection(slot, {
            point = { "TOPLEFT", slot, "TOPLEFT", 4, reservedY },
            width = width - 8,
            headerWidth = math.max(160, width - headerReserve),
            headerHeight = 30,
            padding = { left = 10, right = 10, top = 12, bottom = 10 },
            getExpanded = function()
                return expandedBossGroups[group.encounterID] == true
            end,
            setExpanded = function(value)
                expandedBossGroups[group.encounterID] = value == true
            end,
            label = label,
            renderContent = function(content)
                return RenderBossGroupContent(content, context, group, width - 28)
            end,
            onToggle = function()
                RelayoutBossSections(layout, false)
            end,
        })
        layout.sections[#layout.sections + 1] = section
        if hasDeleteGroup then
            T.CreateActionButton(section, {
                width = 86,
                height = 24,
                point = { "TOPRIGHT", section, "TOPRIGHT", -124, -3 },
                textFn = function() return TXT.deleteBossGroup end,
                onClick = function()
                    ConfirmDeleteBossGroup(group, context.engine)
                end,
            })
        end
        T.CreateActionButton(section, {
            width = 108,
            height = 24,
            point = { "TOPRIGHT", section, "TOPRIGHT", -12, -3 },
            textFn = function() return "+ " .. TXT.newCustom end,
            onClick = function()
                OpenRuleDialog(nil, context.engine, group.encounterID)
            end,
        })
    end

    local addBlock, addHeight = RenderNewBossGroup(slot, context, width, reservedY)
    layout.addBlock = addBlock
    layout.addHeight = addHeight
    reservedY = reservedY - addHeight
    layout.hintLabel = T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 8, reservedY - 4 },
        width = width - 16,
        text = TXT.hint,
        size = 11,
        color = { 0.72, 0.72, 0.72, 1 },
        wordWrap = true,
    })
    reservedY = reservedY - 54

    RelayoutBossSections(layout)

    return { height = layout.currentHeight or math.abs(reservedY) + 8 }
end

T.RegisterOptionModule({
    id = "personalAuraAlert",
    category = "utility",
    order = 45,
    titleKey = TXT.title,
    newSince = NEW_SINCE,
    masterToggle = {
        dbPath = DB_KEY .. ".enabled",
        default = false,
        apply = ApplyEnabled,
    },
    itemsFactory = function()
        return {
        {
            key = "rules",
            type = "custom",
            width = 1,
            height = 420,
            text = TXT.subtitle,
            ignoreModuleDisabled = true,
            render = RenderRules,
            newSince = NEW_SINCE,
        },
        {
            key = "personal_aura_full_config_push",
            type = "custom",
            visible = false,
            optionPush = true,
            text = TXT.fullConfigText,
            dbPath = FULL_CONFIG_PATH,
            getter = GetFullConfig,
            setter = SetFullConfig,
            apply = ApplyFullConfig,
        },
        {
            key = "personal_aura_rule_merge_push",
            type = "custom",
            visible = false,
            optionPush = true,
            text = TXT.ruleMergeText,
            dbPath = RULE_MERGE_PATH,
            getter = function()
                return nil
            end,
            setter = SetRuleMerge,
            apply = ApplyRuleMerge,
        },
        }
    end,
})

end)
