local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("interruptRotation.enabled", function()

local function ApplyInterruptRotation()
    if T.ModuleLoader then
        T.ModuleLoader:Reconcile("interrupt_rotation_option")
    end
end

local function IsDisplayLocked()
    if T.InterruptRotationDisplayEdit and T.InterruptRotationDisplayEdit.IsLocked then
        return T.InterruptRotationDisplayEdit:IsLocked()
    end
    return true
end

local function SetDisplayLocked(locked)
    if T.InterruptRotationDisplayEdit and T.InterruptRotationDisplayEdit.SetLocked then
        T.InterruptRotationDisplayEdit:SetLocked(locked)
    end
end

local function ResetDisplayPosition()
    if T.InterruptRotationDisplayEdit and T.InterruptRotationDisplayEdit.ResetPosition then
        T.InterruptRotationDisplayEdit:ResetPosition()
    end
end

local function FormatSeconds(value)
    return string.format("%.1fs", tonumber(value) or 0)
end

local function FormatScale(value)
    return string.format("%.1fx", tonumber(value) or 0)
end

local function BuildSelectorItems(options)
    local items = {}
    for _, option in ipairs(options or {}) do
        items[#items + 1] = {
            text = L[option.textKey] or option.text or tostring(option.value),
            value = option.value,
        }
    end
    return items
end

local MIDNIGHT_GROUP_OPTIONS = {
    { textKey = "OPT_IR_MACRO_GROUP_1", value = 1 },
    { textKey = "OPT_IR_MACRO_GROUP_2", value = 2 },
    { textKey = "OPT_IR_MACRO_GROUP_3", value = 3 },
}

local MIDNIGHT_KICK_OPTIONS = {
    { textKey = "OPT_IR_MACRO_KICK_1", value = 1 },
    { textKey = "OPT_IR_MACRO_KICK_2", value = 2 },
    { textKey = "OPT_IR_MACRO_KICK_3", value = 3 },
    { textKey = "OPT_IR_MACRO_KICK_4", value = 4 },
}

local function RenderSyntaxHelp(slot, context)
    local width = math.max(200, (context and context.width or 0) - 8)
    local innerWidth = width - 8
    local sampleText = L["OPT_IR_SYNTAX_SAMPLE"] or "[打断]\n1: DK2 DK1 LR1 DKT1\n2: 咕咕2 SS1 FS1 SS2\n3: DH1 AM1 LR2 元素1"

    local title = T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -4 },
        text = L["OPT_IR_SYNTAX_TITLE"] or "范例参考：这里不是编辑入口",
        size = 13,
        width = innerWidth,
        color = { 1, 0.82, 0.25, 1 },
        wordWrap = true,
    })

    local intro = T.CreateLabel(slot, {
        point = { "TOPLEFT", title, "BOTTOMLEFT", 0, -4 },
        text = L["OPT_IR_SYNTAX_INTRO"] or "点击下方文本框会全选示例；复制后粘贴到「战术方案 → 团队方案」。这里修改不会保存，也不会同步给团员。",
        size = 12,
        width = innerWidth,
        color = { 0.72, 0.72, 0.72, 1 },
        wordWrap = true,
    })

    local sampleBox = T.CreateEditBox(slot, {
        point = { "TOPLEFT", intro, "BOTTOMLEFT", 0, -8 },
        width = innerWidth,
        height = 68,
        multiLine = true,
        autoFocus = false,
        justifyH = "LEFT",
        justifyV = "TOP",
        fontObject = "ChatFontNormal",
        backdropAlpha = 0.18,
        borderColor = { 1, 0.82, 0.25, 0.78 },
    })

    local restoring = false
    local function SelectSample(self)
        restoring = true
        self:SetText(sampleText)
        restoring = false
        self:SetCursorPosition(0)
        self:HighlightText()
    end

    sampleBox:SetText(sampleText)
    sampleBox:SetCursorPosition(0)
    sampleBox:SetScript("OnEditFocusGained", SelectSample)
    sampleBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        SelectSample(self)
    end)
    sampleBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetCursorPosition(0)
        self:HighlightText(0, 0)
    end)
    sampleBox:SetScript("OnTextChanged", function(self)
        if not restoring and self:GetText() ~= sampleText then
            SelectSample(self)
        end
    end)

    local label = T.CreateLabel(slot, {
        point = { "TOPLEFT", sampleBox, "BOTTOMLEFT", 0, -8 },
        text = L["OPT_IR_SYNTAX_HELP"] or "",
        size = 12,
        width = innerWidth,
        wordWrap = true,
        color = { 0.62, 0.62, 0.62, 1 },
    })
    if label.SetJustifyH then
        label:SetJustifyH("LEFT")
    end
    return { height = 220 }
end

local function RenderMidnightMacro(slot, context)
    local width = math.max(280, tonumber(context and context.width) or 280)
    local iconColumnWidth = 82
    local selectorWidth = math.max(180, width - iconColumnWidth - 18)
    local groupItems = BuildSelectorItems(MIDNIGHT_GROUP_OPTIONS)
    local kickItems = BuildSelectorItems(MIDNIGHT_KICK_OPTIONS)

    local title = T.CreateGroupTitle(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -2 },
        text = L["OPT_IR_MACRO_TITLE"] or "鲁拉打断宏（实验）",
        fontSize = 13,
    })
    local hint = T.CreateLabel(slot, {
        point = { "TOPLEFT", title, "BOTTOMLEFT", 0, -4 },
        width = width - 8,
        text = L["OPT_IR_MACRO_HINT"] or "拖拽到动作条；团队方案同步后会自动切换目标和第几断。",
        size = 11,
        color = { 0.75, 0.75, 0.75, 1 },
        wordWrap = true,
    })

    local iconButton = CreateFrame("Button", nil, slot)
    iconButton:SetSize(48, 48)
    iconButton:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 8, -14)
    T.ApplyBackdrop(iconButton, {
        style = "tooltip",
        alpha = 0.2,
        borderColor = { 0.55, 0.55, 0.55, 0.9 },
    })

    local groupButton = T.CreateSelectorButton(slot, {
        width = selectorWidth,
        height = 26,
        point = { "TOPLEFT", hint, "BOTTOMLEFT", iconColumnWidth + 10, -10 },
        ownerFrame = context and context.engine and context.engine.ownerFrame or UIParent,
        label = (L["OPT_IR_MACRO_GROUP"] or "打断目标") .. ":",
        labelWidth = 72,
        items = groupItems,
    })
    local kickButton = T.CreateSelectorButton(slot, {
        width = selectorWidth,
        height = 26,
        point = { "TOPLEFT", groupButton, "BOTTOMLEFT", 0, -10 },
        ownerFrame = context and context.engine and context.engine.ownerFrame or UIParent,
        label = (L["OPT_IR_MACRO_KICK"] or "第几断") .. ":",
        labelWidth = 72,
        items = kickItems,
    })

    local icon = iconButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconButton, "TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -4, 4)
    icon:SetTexture(136243)

    local hl = iconButton:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")

    iconButton:RegisterForDrag("LeftButton")
    iconButton:SetScript("OnDragStart", function()
        local runtime = T.InterruptRotationMacro
        if runtime and runtime.PickupMacro then
            runtime:PickupMacro()
        end
    end)
    iconButton:SetScript("OnEnter", function(self)
        local runtime = T.InterruptRotationMacro
        local spellName
        if runtime and runtime.GetSpellMeta then
            local _, resolvedName = runtime:GetSpellMeta()
            spellName = resolvedName
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(spellName or (L["OPT_IR_MACRO_DRAG"] or "拖拽打断宏"), 1, 1, 1)
        GameTooltip:AddLine(L["OPT_IR_MACRO_DRAG_TIP"] or "左键拖拽到动作条；STT 会自动创建或更新一个通用宏。\n宏未经过测试，不保真能使用。", 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", GameTooltip_Hide)

    local function refresh()
        local runtime = T.InterruptRotationMacro
        if not runtime or not runtime.GetSelection then
            groupButton:SetSelectorEnabled(false)
            kickButton:SetSelectorEnabled(false)
            iconButton:Disable()
            icon:SetDesaturated(true)
            icon:SetTexture(136243)
            return
        end

        local group, kick = runtime:GetSelection()
        local spellIcon
        if runtime.GetSpellMeta then
            local _, _, resolvedIcon = runtime:GetSpellMeta()
            spellIcon = resolvedIcon
        end
        groupButton:SetItems(groupItems)
        kickButton:SetItems(kickItems)
        groupButton:SetSelectedValue(group)
        kickButton:SetSelectedValue(kick)
        groupButton:SetSelectorEnabled(true)
        kickButton:SetSelectorEnabled(true)
        iconButton:Enable()
        icon:SetDesaturated(spellIcon == nil)
        icon:SetTexture(spellIcon or 136243)
    end

    groupButton.onSelect = function(value)
        local runtime = T.InterruptRotationMacro
        if runtime and runtime.SetManualSelection then
            local _, kick = runtime:GetSelection()
            runtime:SetManualSelection(value, kick)
        end
        refresh()
    end
    kickButton.onSelect = function(value)
        local runtime = T.InterruptRotationMacro
        if runtime and runtime.SetManualSelection then
            local group = runtime:GetSelection()
            runtime:SetManualSelection(group, value)
        end
        refresh()
    end

    refresh()
    return {
        height = 148,
        refresh = refresh,
        setEnabled = function(enabled)
            groupButton:SetSelectorEnabled(enabled)
            kickButton:SetSelectorEnabled(enabled)
            if enabled then
                iconButton:Enable()
            else
                iconButton:Disable()
            end
        end,
    }
end

T.RegisterOptionModule({
    id = "interruptRotation",
    category = "dungeon",
    order = 49,
    titleKey = "GUI_NAV_INTERRUPT_ROTATION",
    newSince = "260509.20",
    masterToggle = {
        dbPath = "interruptRotation.enabled",
        default = true,
        apply = ApplyInterruptRotation,
    },
    itemsFactory = function()
        return {
        {
            key = "syntaxHelp",
            type = "custom",
            height = 220,
            render = RenderSyntaxHelp,
        },
        {
            key = "uiStyle",
            type = "dropdown",
            textKey = "OPT_IR_STYLE",
            dbPath = "interruptRotation.uiStyle",
            default = "banner",
            width = 0.5,
            options = {
                { textKey = "OPT_IR_STYLE_CARD", value = "card" },
                { textKey = "OPT_IR_STYLE_BANNER", value = "banner" },
            },
            newSince = "260511.34",
            apply = function(value)
                if value ~= "card" and T.InterruptRotationView then
                    T.InterruptRotationView:Hide()
                elseif T.InterruptRotationView and T.InterruptRotation and T.InterruptRotation.Interrupts then
                    local interrupts = T.InterruptRotation.Interrupts
                    T.InterruptRotationView:Rebuild(interrupts.myTable or {}, interrupts.myKick or 0, interrupts.max or 0)
                end
                if T.InterruptRotationDisplayEdit and T.InterruptRotationDisplayEdit.OnStyleChanged then
                    T.InterruptRotationDisplayEdit:OnStyleChanged(value)
                end
            end,
        },
        { type = "subtitle", textKey = "OPT_IR_BANNER_SECTION" },
        {
            type = "check",
            textKey = "OPT_IR_BANNER_SELF_CHECK",
            dbPath = "interruptRotation.bannerSelf",
            default = true,
            width = 0.5,
            newSince = "260509.20",
        },
        {
            type = "check",
            textKey = "OPT_IR_BANNER_NEXT_CHECK",
            dbPath = "interruptRotation.bannerNext",
            default = false,
            width = 0.5,
            newSince = "260509.20",
        },
        {
            type = "check",
            textKey = "OPT_IR_BANNER_OTHERS",
            tooltipKey = "OPT_IR_BANNER_OTHERS_TIP",
            dbPath = "interruptRotation.bannerOthers",
            default = false,
            width = 0.5,
            newSince = "260509.20",
        },
        {
            key = "bannerDurationSec",
            type = "slider",
            textKey = "OPT_IR_BANNER_DURATION",
            dbPath = "interruptRotation.bannerDurationSec",
            default = 2,
            min = 1,
            max = 12,
            step = 0.5,
            width = 1,
            formatFunc = FormatSeconds,
            newSince = "260509.30",
        },
        {
            key = "bannerScale",
            type = "slider",
            textKey = "OPT_IR_BANNER_SCALE",
            dbPath = "interruptRotation.bannerScale",
            default = 3,
            min = 1,
            max = 5,
            step = 0.1,
            width = 1,
            formatFunc = FormatScale,
            newSince = "260513.25",
            apply = function()
                if T.InterruptRotationBanner and T.InterruptRotationBanner.RefreshScale then
                    T.InterruptRotationBanner:RefreshScale()
                end
            end,
        },
        {
            key = "toggleDisplayPositionLock",
            type = "button",
            width = 0.5,
            newSince = "260601.35",
            displayFunc = function()
                if IsDisplayLocked() then
                    return L["OPT_IR_UNLOCK_POSITION"] or "解锁显示位置"
                end
                return L["OPT_IR_LOCK_POSITION"] or "锁定显示位置"
            end,
            onClick = function(engine)
                SetDisplayLocked(not IsDisplayLocked())
                if engine and engine.RefreshWidgetValues then
                    engine:RefreshWidgetValues()
                end
            end,
        },
        {
            key = "resetDisplayPosition",
            type = "button",
            width = 0.5,
            textKey = "OPT_IR_RESET_POSITION",
            newSince = "260601.35",
            onClick = function()
                ResetDisplayPosition()
            end,
        },
        { type = "subtitle", textKey = "OPT_IR_CUE_SECTION" },
        {
            type = "check",
            textKey = "OPT_IR_TTS_ON_PREPARE",
            dbPath = "interruptRotation.ttsOnPrepare",
            default = false,
            width = 0.5,
            newSince = "260509.20",
        },
        {
            type = "check",
            textKey = "OPT_IR_SOUND_ON_SELF",
            dbPath = "interruptRotation.soundOnSelf",
            default = true,
            width = 0.5,
            newSince = "260509.20",
        },
        {
            key = "soundFile",
            type = "editbox",
            textKey = "OPT_IR_SOUND_FILE",
            dbPath = "interruptRotation.soundFile",
            default = "",
            width = 1,
            maxLetters = 120,
            placeholderTextKey = "OPT_IR_SOUND_FILE_PLACEHOLDER",
            newSince = "260509.30",
        },

        { type = "subtitle", textKey = "OPT_IR_BOSS_SECTION" },
        {
            type = "check",
            textKey = "OPT_IR_BOSS_3183",
            dbPath = "interruptRotation.bossEnabled.3183",
            default = true,
            width = 0.5,
            newSince = "260509.20",
            apply = function()
                if T.InterruptRotation and T.InterruptRotation.RefreshBossEnabledState then
                    T.InterruptRotation:RefreshBossEnabledState()
                end
            end,
        },
        {
            type = "check",
            textKey = "OPT_IR_BOSS_OVERLAY",
            tooltipKey = "OPT_IR_BOSS_OVERLAY_TIP",
            dbPath = "interruptRotation.bossOverlayEnabled",
            default = false,
            width = 1,
            newSince = "260516.1",
            apply = function(value)
                if not value and T.InterruptRotationBossOverlay then
                    T.InterruptRotationBossOverlay:Hide()
                end
            end,
        },
        {
            key = "runTest",
            type = "button",
            textKey = "OPT_IR_RUN_TEST",
            width = 0.5,
            onClick = function()
                if T.InterruptRotation and T.InterruptRotation.RunTest then
                    T.InterruptRotation:RunTest()
                end
            end,
        },
        {
            key = "midnightMacro",
            type = "custom",
            height = 148,
            newSince = "260513.31",
            render = RenderMidnightMacro,
        },
        }
    end,
})

end)
