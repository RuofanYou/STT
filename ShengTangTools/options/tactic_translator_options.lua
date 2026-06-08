local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("tacticTranslator.enabled", function()

-- 战术板翻译器（通用）— 设置页里的一个模块节点
-- UI 走 option_engine 的 type=custom + itemDef.render，复用既有组件库
-- 具体格式由 T.TacticTranslator 注册表提供，dropdown 动态列出

local state = {}
local translateToken = 0
local THROTTLE_SECONDS = 0.2

local function Tr(key, fallback)
    if key and L and L[key] and L[key] ~= "" then
        return L[key]
    end
    return fallback or key or ""
end

local function GetFormatOptions()
    local opts = {}
    if T.TacticTranslator then
        for _, def in ipairs(T.TacticTranslator:GetAll()) do
            opts[#opts + 1] = {
                text = Tr(def.nameKey, def.name or def.id),
                value = def.id,
            }
        end
    end
    if #opts == 0 then
        opts[#opts + 1] = { text = "NSRT", value = "nsrt" }
    end
    return opts
end

local function HasNextRoundFlag(def)
    if type(def) ~= "table" or type(def.anchors) ~= "table" then
        return false
    end
    for _, rules in pairs(def.anchors) do
        if type(rules) == "table" then
            for _, rule in ipairs(rules) do
                if type(rule) == "table" and rule.nextRound then
                    return true
                end
            end
        end
    end
    return false
end

local function GetMRTBossOptions()
    local opts = {
        { text = Tr("TACTIC_TRANSLATOR_MRT_BOSS_AUTO", "自动 / 朴素直译 (pgN -> pN)"), value = 0 },
    }
    local ids = {}
    for encounterID in pairs(T.PhaseAnchorsS14 or {}) do
        ids[#ids + 1] = tonumber(encounterID) or encounterID
    end
    table.sort(ids, function(a, b)
        return tostring(a) < tostring(b)
    end)

    for _, encounterID in ipairs(ids) do
        local def = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[encounterID]
        local label = def and def.phaseLabels and def.phaseLabels.p1 or tostring(encounterID)
        local bossName = label:match(":%s*(.+)$") or label
        local suffix = HasNextRoundFlag(def)
            and Tr("TACTIC_TRANSLATOR_MRT_BOSS_ROTATION", "轮换 P1/P2")
            or Tr("TACTIC_TRANSLATOR_MRT_BOSS_LINEAR", "级进")
        opts[#opts + 1] = {
            text = string.format("%s (%s)", bossName, suffix),
            value = encounterID,
        }
    end
    return opts
end

local function GetCurrentFormatId()
    local stored = C and C.DB and C.DB.tacticTranslatorFormat
    if stored and T.TacticTranslator and T.TacticTranslator:GetById(stored) then
        return stored
    end
    return (T.TacticTranslator and T.TacticTranslator:GetDefaultId()) or "nsrt"
end

local function GetCurrentAdapter()
    local id = GetCurrentFormatId()
    return T.TacticTranslator and T.TacticTranslator:GetById(id) or nil
end

local function SetStatus(text, isError)
    if not state.statusLabel then return end
    state.statusLabel:SetText(text or "")
    if isError then
        state.statusLabel:SetTextColor(1.0, 0.35, 0.35, 1)
    else
        state.statusLabel:SetTextColor(0.85, 0.82, 0.62, 1)
    end
end

local function RunTranslate()
    local inputBox = state.inputBox
    local outputBox = state.outputBox
    if not (inputBox and outputBox) then return end

    local raw = inputBox:GetText() or ""
    if raw:gsub("%s+", "") == "" then
        outputBox:SetText("")
        SetStatus(Tr("TACTIC_TRANSLATOR_STATUS_EMPTY", "在左侧粘贴战术板文本后会自动翻译"), false)
        return
    end

    if not T.TacticTranslator then
        SetStatus(Tr("TACTIC_TRANSLATOR_STATUS_NO_MODULE", "翻译器模块未加载"), true)
        return
    end

    local formatId = GetCurrentFormatId()
    local result, err = T.TacticTranslator:Translate(formatId, raw)
    if not result then
        outputBox:SetText("")
        SetStatus(string.format(Tr("TACTIC_TRANSLATOR_STATUS_ERROR_FMT", "翻译失败: %s"), tostring(err)), true)
        return
    end

    outputBox:SetText(result.stn or "")

    local fmt = Tr("TACTIC_TRANSLATOR_STATUS_OK_FMT", "已解析 %d 个事件 / Phase 数: %d / 跳过 %d 行")
    SetStatus(string.format(fmt, result.eventCount or 0, result.phaseCount or 0, result.skipped or 0), false)
end

local function RunExportTR()
    local inputBox = state.inputBox
    local outputBox = state.outputBox
    if not (inputBox and outputBox) then return end

    if not (C and C.DB and C.DB.debugMode == true) then
        SetStatus(Tr("TACTIC_TRANSLATOR_TR_EXPORT_DEBUG_ONLY", "TR 导出仅在 debug on 时启用"), true)
        return
    end
    if not (T.TacticExporterTR and T.TacticExporterTR.Export) then
        SetStatus(Tr("TACTIC_TRANSLATOR_TR_EXPORT_MISSING", "TR 导出模块未加载"), true)
        return
    end

    local raw = inputBox:GetText() or ""
    if raw:gsub("%s+", "") == "" then
        outputBox:SetText("")
        SetStatus(Tr("TACTIC_TRANSLATOR_STATUS_EMPTY", "在左侧粘贴战术板文本后会自动翻译"), false)
        return
    end

    local result, err = T.TacticExporterTR:Export(raw, {
        encounterID = C and C.DB and C.DB.tacticTranslatorMRTBoss,
    })
    if not result then
        outputBox:SetText("")
        SetStatus(string.format(Tr("TACTIC_TRANSLATOR_TR_EXPORT_ERROR_FMT", "导出 TR 失败: %s"), tostring(err)), true)
        return
    end

    outputBox:SetText(result)
    SetStatus(string.format(Tr("TACTIC_TRANSLATOR_TR_EXPORT_OK_FMT", "已导出 TR 字符串 / 长度: %d"), #result), false)
end

local function ScheduleTranslate()
    translateToken = translateToken + 1
    local token = translateToken
    C_Timer.After(THROTTLE_SECONDS, function()
        if token ~= translateToken then return end
        RunTranslate()
    end)
end

local function RefreshPlaceholder()
    if not state.inputBox or not state.inputBox.Instructions then return end
    local adapter = GetCurrentAdapter()
    local sample = adapter and (Tr(adapter.sampleKey, adapter.sample) or "") or ""
    local prefix = Tr("TACTIC_TRANSLATOR_INPUT_PLACEHOLDER", "粘贴战术板文本到这里\n示例:\n")
    state.inputBox.Instructions:SetText(prefix .. sample)
end

-- 创建一个嵌入卡片内的多行编辑框（BugSack 风格：UIPanelScrollFrameTemplate + 手动 EditBox）
-- 比 InputScrollFrameTemplate 稳：12.0 下 InputScrollFrameTemplate 的 EditBox 即使 multiLine=true
-- 也会在粘贴时吞掉 \n，导致 NSRT 多行文本被合并成单行。手动创建可避开这个坑。
local function CreateEmbeddedEditBox(container, opts)
    opts = opts or {}

    local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -24, 6) -- 右侧 24px 留给滚动条

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(0)
    edit:SetCountInvisibleLetters(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetAutoFocus(false)
    edit:SetTextInsets(4, 4, 4, 4)
    edit:SetJustifyH("LEFT")
    edit:SetJustifyV("TOP")
    edit:EnableMouse(true)
    edit:SetSize(1, 1) -- 占位，下面 syncEditWidth 会调
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    scroll:SetScrollChild(edit)

    -- placeholder：自己用 FontString 实现，挂 ScrollFrame 上层
    local placeholder = scroll:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    placeholder:SetPoint("TOPLEFT", scroll, "TOPLEFT", 8, -4)
    placeholder:SetPoint("RIGHT", scroll, "RIGHT", -8, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetJustifyV("TOP")
    placeholder:SetTextColor(0.45, 0.45, 0.45, 0.7)
    if opts.placeholder then
        placeholder:SetText(opts.placeholder)
    end
    edit.Instructions = placeholder -- 兼容 RefreshPlaceholder 现有引用

    edit:HookScript("OnTextChanged", function(self)
        placeholder:SetShown((self:GetText() or "") == "")
    end)
    edit:HookScript("OnEditFocusGained", function() placeholder:Hide() end)
    edit:HookScript("OnEditFocusLost", function(self)
        if (self:GetText() or "") == "" then placeholder:Show() end
    end)

    -- 宽度同步（手动 EditBox 必须显式 SetWidth，否则多行 wrap 失效）
    local function syncEditWidth()
        local w = scroll:GetWidth() or 0
        if w <= 0 then return end
        edit:SetWidth(w)
    end
    scroll:SetScript("OnSizeChanged", syncEditWidth)
    syncEditWidth()

    -- 点击 ScrollFrame 任意位置都聚焦 EditBox
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)

    -- 只读：拦截用户输入，保留 SetText 程序写入；Ctrl+A/Ctrl+C 仍可用
    if opts.readOnly then
        local origSetText = edit.SetText
        edit.SetText = function(self, value)
            local v = value or ""
            self.__readOnlyValue = v
            origSetText(self, v)
        end
        edit.__readOnlyValue = ""
        edit:HookScript("OnTextChanged", function(self, userInput)
            if userInput then
                origSetText(self, self.__readOnlyValue or "")
            end
        end)
    end

    return scroll, edit
end

local function RenderBodyImpl(parent)
    local HEIGHT = 420
    local GAP = 10
    local EDITOR_HEIGHT = 300
    local EDITOR_TOP = -22
    local BUTTON_Y = -8   -- 负数：按钮顶部在容器底部之下 8px，避免与编辑框重叠
    local STATUS_Y = -4   -- 负数：状态栏顶部在按钮底部之下 4px

    -- 左栏标题
    local leftTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
    leftTitle:SetJustifyH("LEFT")
    leftTitle:SetTextColor(0.95, 0.88, 0.6, 1)
    leftTitle:SetText(Tr("TACTIC_TRANSLATOR_INPUT_TITLE", "原文"))
    state.leftTitle = leftTitle

    -- 左编辑框容器（暗背景卡片）
    local leftContainer = CreateFrame("Frame", nil, parent)
    leftContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, EDITOR_TOP)
    leftContainer:SetPoint("TOPRIGHT", parent, "TOP", -GAP / 2, EDITOR_TOP)
    leftContainer:SetHeight(EDITOR_HEIGHT)
    T.ApplyBackdrop(leftContainer, { alpha = 0.15 })

    local _, inputBox = CreateEmbeddedEditBox(leftContainer)
    state.inputBox = inputBox
    RefreshPlaceholder()
    if T.UITooltip then
        T.UITooltip.AttachRich(leftContainer, {
            title = "输入格式",
            description = "粘贴外部战术文本。",
            concepts = { "format-nsrt", "format-mrt", "format-comparison" },
        })
    end

    -- 右栏标题
    local rightTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightTitle:SetPoint("TOPLEFT", parent, "TOP", GAP / 2, -2)
    rightTitle:SetJustifyH("LEFT")
    rightTitle:SetTextColor(0.95, 0.88, 0.6, 1)
    rightTitle:SetText(Tr("TACTIC_TRANSLATOR_OUTPUT_TITLE", "STT 格式(预览)"))
    state.rightTitle = rightTitle

    -- 右编辑框容器（暗背景卡片，只读）
    local rightContainer = CreateFrame("Frame", nil, parent)
    rightContainer:SetPoint("TOPLEFT", parent, "TOP", GAP / 2, EDITOR_TOP)
    rightContainer:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, EDITOR_TOP)
    rightContainer:SetHeight(EDITOR_HEIGHT)
    T.ApplyBackdrop(rightContainer, { alpha = 0.15 })

    local _, outputBox = CreateEmbeddedEditBox(rightContainer, {
        readOnly = true,
        placeholder = Tr("TACTIC_TRANSLATOR_OUTPUT_PLACEHOLDER", "翻译结果会自动出现在这里"),
    })
    state.outputBox = outputBox
    if T.UITooltip then
        T.UITooltip.AttachRich(rightContainer, {
            title = "STT 格式",
            description = "预览转换后的文本。",
            concepts = { "format-comparison", "time", "audience", "phase-tag" },
        })
    end

    -- 清空按钮
    local clearBtn = T.CreateButton(parent, {
        width = 100,
        height = 26,
        text = Tr("TACTIC_TRANSLATOR_BTN_CLEAR", "清空"),
        point = { "TOPLEFT", leftContainer, "BOTTOMLEFT", 0, BUTTON_Y },
    })
    clearBtn:SetScript("OnClick", function()
        if state.inputBox then
            state.inputBox:SetText("")
        end
        if state.outputBox then
            state.outputBox:SetText("")
        end
        SetStatus(Tr("TACTIC_TRANSLATOR_STATUS_EMPTY", "在左侧粘贴战术板文本后会自动翻译"), false)
    end)
    state.clearBtn = clearBtn

    -- 复制按钮
    local copyBtn = T.CreateButton(parent, {
        width = 120,
        height = 26,
        text = Tr("TACTIC_TRANSLATOR_BTN_COPY", "全选复制"),
        point = { "TOPRIGHT", rightContainer, "BOTTOMRIGHT", 0, BUTTON_Y },
    })
    copyBtn:SetScript("OnClick", function()
        local edit = state.outputBox
        if not edit then return end
        local content = edit:GetText() or ""
        if content == "" then
            T.msg(Tr("TACTIC_TRANSLATOR_MSG_NOTHING", "还没有翻译结果可复制"))
            return
        end
        edit:SetFocus()
        edit:HighlightText()
        T.msg(Tr("TACTIC_TRANSLATOR_MSG_COPY_HINT", "已全选 STT 文本,按 Ctrl+C 复制后粘贴到战术方案编辑框"))
    end)
    state.copyBtn = copyBtn

    if C and C.DB and C.DB.debugMode == true then
        local exportTRBtn = T.CreateButton(parent, {
            width = 100,
            height = 26,
            text = Tr("TACTIC_TRANSLATOR_BTN_EXPORT_TR", "导出TR"),
            point = { "TOPRIGHT", copyBtn, "TOPLEFT", -6, 0 },
        })
        exportTRBtn:SetScript("OnClick", RunExportTR)
        state.exportTRBtn = exportTRBtn
    end

    -- 状态栏（按钮下方）
    local statusLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLabel:SetPoint("TOPLEFT", clearBtn, "BOTTOMLEFT", 0, STATUS_Y)
    statusLabel:SetPoint("TOPRIGHT", copyBtn, "BOTTOMRIGHT", 0, STATUS_Y)
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetTextColor(0.85, 0.82, 0.62, 1)
    state.statusLabel = statusLabel

    SetStatus(Tr("TACTIC_TRANSLATOR_STATUS_EMPTY", "在左侧粘贴战术板文本后会自动翻译"), false)

    -- 监听左框实时翻译（200ms 节流）
    inputBox:HookScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        ScheduleTranslate()
    end)

    return { height = HEIGHT }
end

-- 外层 pcall 保护：即使内部渲染崩溃也不能拖垮整个 options 页
local function RenderBody(parent)
    local ok, result = xpcall(function()
        return RenderBodyImpl(parent)
    end, function(err)
        return tostring(err) .. "\n" .. (debugstack and debugstack(2, 10, 10) or "")
    end)

    if ok then
        return result
    end

    -- 渲染失败：打印错误到聊天框，返回一个占位高度避免后续布局错乱
    if T.msg then
        T.msg("|cffff5555[战术板翻译器] 渲染失败:|r " .. tostring(result))
    end
    if T.debug then
        T.debug("[TacticTranslator] render error: %s", tostring(result))
    end

    -- 占位 FontString 让用户知道这里本应是翻译器
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    label:SetText("|cffff5555战术板翻译器渲染失败，查看聊天框错误信息|r")
    return { height = 40 }
end

T.RegisterOptionModule({
    id = "tacticTranslator",
    category = "utility",
    order = 12,
    titleKey = "OPTIONS_TACTIC_TRANSLATOR_TITLE",
    masterToggle = {
        dbPath = "tacticTranslator.enabled",
        default = false,
    },
    itemsFactory = function()
        return {
        {
            type = "subtitle",
            textKey = "OPTIONS_TACTIC_TRANSLATOR_SUBTITLE",
        },
        {
            key = "tacticTranslatorFormat",
            type = "dropdown",
            textKey = "OPTIONS_TACTIC_TRANSLATOR_FORMAT",
            tooltip = {
                title = "输入格式",
                description = "选择原文格式。",
                concepts = { "format-nsrt", "format-mrt", "format-comparison" },
            },
            width = 1,
            dbPath = "tacticTranslatorFormat",
            default = "nsrt",
            options = GetFormatOptions,
            apply = function()
                RefreshPlaceholder()
                RunTranslate()
            end,
        },
        {
            key = "tacticTranslatorMRTBoss",
            type = "dropdown",
            textKey = "OPTIONS_TACTIC_TRANSLATOR_MRT_BOSS",
            width = 1,
            dbPath = "tacticTranslatorMRTBoss",
            default = 0,
            options = GetMRTBossOptions,
            depend = { key = "tacticTranslatorFormat", value = "mrt" },
            apply = function()
                RunTranslate()
            end,
            newSince = "260519.69",
        },
        {
            key = "tacticTranslatorBody",
            type = "custom",
            width = 1,
            render = RenderBody,
            height = 420,
        },
        }
    end,
})

end)
