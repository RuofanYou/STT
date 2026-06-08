local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("auraColorAlert.enabled", function()

local DB_KEY = "auraColorAlert"

local function ApplyEnabled()
    if T.AuraColorAlert then
        local db = C.DB[DB_KEY] or {}
        T.AuraColorAlert:SetEnabled(db.enabled ~= false)
    end
end

local function ApplyScale()
    if T.AuraColorAlert and T.AuraColorAlert.RefreshScale then
        T.AuraColorAlert:RefreshScale()
    end
end

local function ApplyAlpha()
    if T.AuraColorAlert and T.AuraColorAlert.RefreshAlpha then
        T.AuraColorAlert:RefreshAlpha()
    end
end

local function ApplyAudio()
    if T.AuraColorAlert and T.AuraColorAlert.RefreshAudio then
        T.AuraColorAlert:RefreshAudio()
    end
end

local function FormatDecimal(value)
    return string.format("%.2f", tonumber(value) or 1)
end

local function RenderAudioHint(slot, context)
    local width = math.max(1, (context and context.width or 0) - 44)
    local hint = T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 36, -2 },
        width = width,
        text = L["AURA_COLOR_AUDIO_DESC"] or "",
        size = 11,
        color = { 0.62, 0.62, 0.62, 1 },
        wordWrap = true,
    })

    local height = hint:GetStringHeight() or 0
    return math.max(30, math.ceil(height) + 6)
end

T.RegisterOptionModule({
    id = "auraColor",
    category = "dungeon",
    order = 49,
    titleKey = "GUI_NAV_AURA_COLOR",
    masterToggle = {
        dbPath = DB_KEY .. ".enabled",
        default = false,
        apply = ApplyEnabled,
    },
    itemsFactory = function()
        return {
        {
            type = "check",
            textKey = "AURA_COLOR_PULSE",
            dbPath = DB_KEY .. ".pulse",
            default = true,
        },
        {
            type = "check",
            textKey = "AURA_COLOR_SHOW_NAME",
            dbPath = DB_KEY .. ".showName",
            default = true,
        },
        {
            type = "check",
            textKey = "AURA_COLOR_AUDIO",
            dbPath = DB_KEY .. ".audioEnabled",
            default = false,
            apply = ApplyAudio,
        },
        {
            key = "audioHint",
            type = "custom",
            textKey = "AURA_COLOR_AUDIO_DESC",
            width = 1,
            render = RenderAudioHint,
            height = 34,
        },
        {
            key = "scale",
            type = "slider",
            textKey = "AURA_COLOR_SCALE",
            width = 0.5,
            dbPath = DB_KEY .. ".scale",
            default = 1.0,
            min = 0.1,
            max = 2.5,
            step = 0.05,
            formatFunc = FormatDecimal,
            apply = ApplyScale,
        },
        {
            key = "alpha",
            type = "slider",
            textKey = "AURA_COLOR_ALPHA",
            width = 0.5,
            dbPath = DB_KEY .. ".alpha",
            default = 1.0,
            min = 0.2,
            max = 1.0,
            step = 0.05,
            formatFunc = FormatDecimal,
            apply = ApplyAlpha,
        },
        {
            key = "togglePositionLock",
            type = "button",
            width = 0.5,
            newSince = "260601.35",
            displayFunc = function()
                if T.AuraColorAlert and T.AuraColorAlert.IsLocked and not T.AuraColorAlert:IsLocked() then
                    return L["AURA_COLOR_LOCK_POSITION"] or "锁定提示框位置"
                end
                return L["AURA_COLOR_UNLOCK_POSITION"] or "解锁提示框位置"
            end,
            onClick = function(engine)
                if T.AuraColorAlert and T.AuraColorAlert.SetLocked and T.AuraColorAlert.IsLocked then
                    T.AuraColorAlert:SetLocked(not T.AuraColorAlert:IsLocked())
                end
                if engine and engine.RefreshWidgetValues then
                    engine:RefreshWidgetValues()
                end
            end,
        },
        {
            key = "resetPosition",
            type = "button",
            width = 0.5,
            textKey = "AURA_COLOR_RESET_POSITION",
            onClick = function()
                if T.AuraColorAlert and T.AuraColorAlert.ResetPosition then
                    T.AuraColorAlert:ResetPosition()
                end
            end,
        },
        {
            key = "runTest",
            type = "button",
            width = 0.5,
            textKey = "AURA_COLOR_TEST",
            onClick = function()
                if T.TestAuraColorAlert then
                    T.TestAuraColorAlert()
                end
            end,
        },
        {
            type = "subtitle",
            textKey = "AURA_COLOR_EDIT_HINT",
        },
        }
    end,
})

end)
