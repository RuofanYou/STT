local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("dreadElegy.enabled", function()
local RUNE_BUTTON_COUNT = 6

local function ApplyEnabled()
    if T.DreadElegy then
        T.DreadElegy:ApplyRaidOnlyChange()
    end
    -- 主开关切换联动屏幕符文按钮条显隐
    if T.LuraButtonsMVP and T.LuraButtonsMVP.ApplyEnabled then
        T.LuraButtonsMVP:ApplyEnabled()
    end
end

local function RefreshRuneButtons()
    if T.DreadElegy and T.DreadElegy.RefreshRuneButtons then
        T.DreadElegy:RefreshRuneButtons()
    end
end

local function ApplyChatType(value)
    if T.DreadElegy and T.DreadElegy.ApplyChatTypeChange then
        T.DreadElegy:ApplyChatTypeChange(value)
    else
        RefreshRuneButtons()
    end
end

local function CleanupRuneMacros()
    if T.DreadElegy and T.DreadElegy.CleanupRuneMacros then
        T.DreadElegy:CleanupRuneMacros()
    end
end

local function ApplyPanelBackdropOpacity()
    if T.DreadElegy and T.DreadElegy.ApplyPanelBackdropOpacity then
        T.DreadElegy:ApplyPanelBackdropOpacity()
    end
end

local function FormatPercent(value)
    return string.format("%d%%", tonumber(value) or 0)
end

local function Locale(key)
    return (L and L[key]) or key
end

local function RenderRuneDragTray(slot, context)
    local runtime = T.DreadElegy
    local width = math.max(280, tonumber(context and context.width) or 280)
    local title = T.CreateGroupTitle(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -2 },
        text = Locale("RUNE_DRAG_TITLE"),
        fontSize = 13,
    })
    local hint = T.CreateLabel(slot, {
        point = { "TOPLEFT", title, "BOTTOMLEFT", 0, -4 },
        width = width - 8,
        text = Locale("RUNE_DRAG_HINT"),
        size = 11,
        color = { 0.75, 0.75, 0.75, 1 },
        wordWrap = true,
    })

    if not runtime or not runtime.GetRuneMeta then
        T.CreateLabel(slot, {
            point = { "TOPLEFT", hint, "BOTTOMLEFT", 0, -10 },
            width = width - 8,
            text = Locale("DREAD_ELEGY_RUNTIME_NOT_READY"),
            size = 11,
            color = { 1, 0.3, 0.3, 1 },
            wordWrap = true,
        })
        return { height = 84 }
    end

    local btnSize = 48
    local gap = 12
    local totalWidth = RUNE_BUTTON_COUNT * btnSize + (RUNE_BUTTON_COUNT - 1) * gap
    local startX = math.max(4, math.floor((width - totalWidth) / 2))

    for i = 1, RUNE_BUTTON_COUNT do
        local runeName, _, iconFileID = runtime:GetRuneMeta(i)
        local btn = CreateFrame("Button", nil, slot)
        btn:SetSize(btnSize, btnSize)
        btn:SetPoint("TOPLEFT", slot, "TOPLEFT", startX + (i - 1) * (btnSize + gap), -48)
        T.ApplyBackdrop(btn, {
            style = "tooltip",
            alpha = 0.2,
            borderColor = { 0.55, 0.55, 0.55, 0.9 },
        })

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
        icon:SetTexture(iconFileID)

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")

        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function()
            runtime:PickupRuneMacro(i)
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(runeName or string.format(Locale("RUNE_DRAG_FALLBACK_NAME"), i), 1, 1, 1)
            GameTooltip:AddLine(Locale("RUNE_DRAG_TOOLTIP"), 0.82, 0.82, 0.82, true)
            local preview = runtime:GetRuneMacroPreview(i)
            if preview and preview ~= "" then
                GameTooltip:AddLine(Locale("RUNE_DRAG_CURRENT_SEND") .. ":", 0.6, 0.82, 1, true)
                GameTooltip:AddLine(preview, 0.5, 1, 0.5, true)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)

        T.CreateLabel(slot, {
            point = { "TOP", btn, "BOTTOM", 0, -4 },
            width = btnSize + 12,
            text = runeName or string.format(Locale("RUNE_DRAG_FALLBACK_NAME"), i),
            size = 11,
            color = { 0.88, 0.88, 0.88, 1 },
            justifyH = "CENTER",
        })
    end

    return { height = 118 }
end

T.RegisterOptionModule({
    id = "dreadElegy",
    category = "dungeon",
    order = 48,
    titleKey = "GUI_NAV_DREAD_ELEGY",
    advancedTitleKey = "DREAD_ELEGY_ADVANCED_TITLE",
    masterToggle = {
        dbPath = "dreadElegy.enabled",
        default = false,
        apply = ApplyEnabled,
    },
    itemsFactory = function()
        return {
        -- ── 主推：屏幕常驻符文按钮条（独立于动作条，进副本自动出现） ──
        {
            type = "check",
            textKey = "DREAD_ELEGY_LURA_BUTTONS_ENABLE",
            tooltipKey = "DREAD_ELEGY_LURA_BUTTONS_ENABLE_TIP",
            dbPath = "dreadElegy.lurabuttonsMVP",
            default = false,
            newSince = "260525.8",
            apply = function()
                if T.LuraButtonsMVP and T.LuraButtonsMVP.ApplyEnabled then
                    T.LuraButtonsMVP:ApplyEnabled()
                end
            end,
        },
        {
            type = "check",
            textKey = "DREAD_ELEGY_LURA_BUTTONS_ZONE_ONLY",
            tooltipKey = "DREAD_ELEGY_LURA_BUTTONS_ZONE_ONLY_TIP",
            dbPath = "dreadElegy.lurabuttonsMVPZoneOnly",
            default = true,
            newSince = "260525.8",
            apply = function()
                if T.LuraButtonsMVP and T.LuraButtonsMVP.ApplyEnabled then
                    T.LuraButtonsMVP:ApplyEnabled()
                end
            end,
        },
        {
            type = "check",
            textKey = "DREAD_ELEGY_LURA_BUTTONS_ENCOUNTER_ONLY",
            tooltipKey = "DREAD_ELEGY_LURA_BUTTONS_ENCOUNTER_ONLY_TIP",
            dbPath = "dreadElegy.lurabuttonsMVPEncounterOnly",
            default = false,
            newSince = "260530.14",
            depend = { dbPath = "dreadElegy.lurabuttonsMVPZoneOnly", notValue = false },
            apply = function()
                if T.LuraButtonsMVP and T.LuraButtonsMVP.ApplyEnabled then
                    T.LuraButtonsMVP:ApplyEnabled()
                end
            end,
        },
        {
            key = "luraMVPCreateMacros",
            type = "button",
            width = 1,
            textKey = "DREAD_ELEGY_LURA_BUTTONS_CREATE_MACROS",
            tooltipKey = "DREAD_ELEGY_LURA_BUTTONS_CREATE_MACROS_TIP",
            newSince = "260525.8",
            onClick = function()
                if T.LuraButtonsMVP and T.LuraButtonsMVP.CreateOrRebuildRuneMacros then
                    T.LuraButtonsMVP:CreateOrRebuildRuneMacros()
                end
            end,
        },
        {
            key = "luraMVPToggleLock",
            type = "button",
            width = 0.5,
            textKey = "DREAD_ELEGY_LURA_BUTTONS_UNLOCK_POS",
            displayFunc = function()
                if T.LuraButtonsMVP and T.LuraButtonsMVP.IsLocked and T.LuraButtonsMVP:IsLocked() then
                    return Locale("DREAD_ELEGY_LURA_BUTTONS_UNLOCK_POS")
                end
                return Locale("DREAD_ELEGY_LURA_BUTTONS_LOCK_POS")
            end,
            newSince = "260525.8",
            onClick = function()
                if T.LuraButtonsMVP and T.LuraButtonsMVP.SetLocked then
                    T.LuraButtonsMVP:SetLocked(not T.LuraButtonsMVP:IsLocked())
                end
            end,
        },
        {
            key = "luraMVPResetPos",
            type = "button",
            width = 0.5,
            textKey = "DREAD_ELEGY_LURA_BUTTONS_RESET_POS",
            newSince = "260525.8",
            onClick = function()
                if T.LuraButtonsMVP and T.LuraButtonsMVP.ResetPosition then
                    T.LuraButtonsMVP:ResetPosition()
                end
            end,
        },
        {
            type = "check",
            textKey = "DREAD_ELEGY_RAID_ONLY",
            dbPath = "dreadElegy.raidOnly",
            default = true,
            apply = function()
                if T.DreadElegy and T.DreadElegy.ApplyRaidOnlyChange then
                    T.DreadElegy:ApplyRaidOnlyChange()
                end
            end,
        },
        {
            type = "dropdown",
            textKey = "DREAD_ELEGY_ROUTE_MODE",
            tooltipKey = "DREAD_ELEGY_ROUTE_MODE_TIP",
            dbPath = "dreadElegy.runeRouteMode",
            default = "event",
            newSince = "260511.55",
            options = {
                { textKey = "DREAD_ELEGY_ROUTE_MODE_EVENT", value = "event" },
                { textKey = "DREAD_ELEGY_ROUTE_MODE_SEQUENTIAL", value = "sequential" },
            },
            apply = function()
                if T.DreadElegy and T.DreadElegy.ApplyRuneRouteModeChange then
                    T.DreadElegy:ApplyRuneRouteModeChange()
                end
            end,
        },
        {
            type = "check",
            textKey = "DREAD_ELEGY_ANNOUNCE_ONSHOW_LABEL",
            tooltipKey = "DREAD_ELEGY_ANNOUNCE_ONSHOW_TIP",
            dbPath = "dreadElegy.announceNumberOnShow",
            default = false,
            newSince = "260509.1",
        },
        {
            key = "toggleLock",
            type = "button",
            width = 0.5,
            textKey = "DREAD_ELEGY_TOGGLE_LOCK",
            displayFunc = function()
                if T.DreadElegy and T.DreadElegy.IsLocked and T.DreadElegy:IsLocked() then
                    return Locale("DREAD_ELEGY_UNLOCK")
                end
                return Locale("DREAD_ELEGY_LOCK")
            end,
            onClick = function()
                if T.DreadElegy and T.DreadElegy.SetLocked then
                    T.DreadElegy:SetLocked(not T.DreadElegy:IsLocked())
                end
            end,
        },
        {
            key = "resetPos",
            type = "button",
            width = 0.5,
            textKey = "DREAD_ELEGY_RESET_POS",
            onClick = function()
                if T.DreadElegy and T.DreadElegy.ResetPanelPosition then
                    T.DreadElegy:ResetPanelPosition()
                end
            end,
        },
        {
            type = "slider",
            textKey = "DREAD_ELEGY_PANEL_BG_OPACITY",
            dbPath = "dreadElegy.panelOpacity",
            default = 85,
            min = 0,
            max = 100,
            step = 5,
            formatFunc = FormatPercent,
            apply = ApplyPanelBackdropOpacity,
            newSince = "260513.18",
        },
        {
            type = "slider",
            textKey = "DREAD_ELEGY_AUTO_HIDE",
            dbPath = "dreadElegy.autoHideSeconds",
            default = 10,
            min = 5,
            max = 20,
            step = 1,
        },
        {
            type = "dropdown",
            textKey = "DREAD_ELEGY_CHAT_TYPE",
            dbPath = "dreadElegy.chatType",
            default = "raid",
            apply = ApplyChatType,
            options = {
                { textKey = "DREAD_ELEGY_CHANNEL_RAID_WITH_PATH", value = "raid" },
                { textKey = "DREAD_ELEGY_CHANNEL_YELL_WITH_PATH", value = "yell" },
                { textKey = "DREAD_ELEGY_CHANNEL_EMOTE_WITH_PATH", value = "emote" },
                { textKey = "DREAD_ELEGY_CHANNEL_SAY_WITH_PATH", value = "say" },
            },
        },
        -- ── Legacy 模式（fallback）：把符文宏拖到 ElvUI/暴雪动作条上 ──
        -- 标 advanced=true，由 option_engine 统一收进底部「高级设置」折叠组（单一权威）
        {
            key = "runeDragTray",
            type = "custom",
            textKey = "RUNE_DRAG_TITLE",
            width = 1,
            height = 118,
            advanced = true,
            render = RenderRuneDragTray,
        },
        {
            key = "runeMacroInit",
            type = "button",
            width = 1,
            textKey = "RUNE_MACRO_CLEANUP_BUTTON",
            advanced = true,
            onClick = CleanupRuneMacros,
        },
        {
            key = "yellWarning",
            type = "custom",
            width = 1,
            height = 176,
            render = function(slot, context)
                local width = math.max(280, tonumber(context and context.width) or 280)
                T.CreateLabel(slot, {
                    point = { "TOPLEFT", slot, "TOPLEFT", 4, -4 },
                    width = width - 8,
                    text = Locale("DREAD_ELEGY_YELL_WARNING"),
                    size = 11,
                    color = { 0.75, 0.75, 0.75, 1 },
                    wordWrap = true,
                })
                return { height = 176 }
            end,
        },
        }
    end,
})

end)
