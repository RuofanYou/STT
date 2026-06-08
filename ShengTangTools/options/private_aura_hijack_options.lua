local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("privateAuraHijack.enabled", function()

local DB_KEY = "privateAuraHijack"
local NEW_SINCE = "260521.46"

local function Apply()
    if T.PrivateAuraHijack then
        T.PrivateAuraHijack:ApplySettings()
    end
end

local function GetColor(index, defaultValue)
    return function()
        local db = C.DB and C.DB[DB_KEY] or {}
        local color = db.fontColor or {}
        local value = color[index]
        if value == nil then
            value = defaultValue
        end
        return math.floor((tonumber(value) or defaultValue) * 100 + 0.5)
    end
end

local function SetColor(index)
    return function(value)
        if type(C.DB) ~= "table" then
            return
        end
        C.DB[DB_KEY] = C.DB[DB_KEY] or {}
        C.DB[DB_KEY].fontColor = C.DB[DB_KEY].fontColor or { 1, 0.2, 0.2, 1 }
        C.DB[DB_KEY].fontColor[index] = math.max(0, math.min(100, tonumber(value) or 0)) / 100
        if type(STT_DB) == "table" then
            STT_DB[DB_KEY] = STT_DB[DB_KEY] or {}
            STT_DB[DB_KEY].fontColor = C.DB[DB_KEY].fontColor
        end
    end
end

local function FormatPct(value)
    return tostring(math.floor((tonumber(value) or 0) + 0.5)) .. "%"
end

local function FormatSeconds(value)
    return string.format("%.1fs", tonumber(value) or 0)
end

local function RenderHint(slot, context)
    local text = T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -4 },
        width = math.max(1, (context and context.width or 0) - 12),
        text = L["PAH_HINT"] or "",
        size = 11,
        color = { 1, 0.82, 0, 1 },
        wordWrap = true,
    })
    return math.max(48, math.ceil(text:GetStringHeight() or 48) + 10)
end

T.RegisterOptionModule({
    id = "privateAuraHijack",
    category = "utility",
    order = 91,
    beta = true,
    titleKey = "PRIVATE_AURA_HIJACK_TITLE",
    newSince = NEW_SINCE,
    masterToggle = {
        dbPath = DB_KEY .. ".enabled",
        default = false,
        apply = Apply,
    },
    itemsFactory = function()
        return {
        { key = "hint", type = "custom", width = 1, render = RenderHint, height = 58, newSince = NEW_SINCE },
        { key = "dispelTextEnabled", type = "check", textKey = "PAH_TEXT_ENABLED", dbPath = DB_KEY .. ".dispelTextEnabled", default = true, apply = Apply, newSince = NEW_SINCE },
        { key = "hideBlizzardOverlay", type = "check", textKey = "PAH_HIDE_BLIZZ", dbPath = DB_KEY .. ".hideBlizzardOverlay", default = true, apply = Apply, newSince = NEW_SINCE },
        { key = "dispelText", type = "editbox", textKey = "PAH_TEXT", dbPath = DB_KEY .. ".dispelText", default = "驱散!", maxLetters = 16, apply = Apply, newSince = NEW_SINCE },
        { key = "fontSize", type = "slider", textKey = "PAH_FONT_SIZE", dbPath = DB_KEY .. ".fontSize", min = 12, max = 64, step = 1, default = 28, apply = Apply, newSince = NEW_SINCE },
        {
            key = "outline",
            type = "dropdown",
            textKey = "PAH_OUTLINE",
            dbPath = DB_KEY .. ".outline",
            default = "OUTLINE",
            options = {
                { textKey = "PAH_OUTLINE_NORMAL", value = "OUTLINE" },
                { textKey = "PAH_OUTLINE_THICK", value = "THICKOUTLINE" },
                { textKey = "PAH_OUTLINE_NONE", value = "NONE" },
            },
            apply = Apply,
            newSince = NEW_SINCE,
        },
        {
            key = "anchor",
            type = "dropdown",
            textKey = "PAH_ANCHOR",
            dbPath = DB_KEY .. ".anchor",
            default = "CENTER",
            options = {
                { textKey = "PAH_ANCHOR_CENTER", value = "CENTER" },
                { textKey = "PAH_ANCHOR_TOP", value = "TOP" },
                { textKey = "PAH_ANCHOR_BOTTOM", value = "BOTTOM" },
            },
            apply = Apply,
            newSince = NEW_SINCE,
        },
        { key = "offsetX", type = "slider", textKey = "PAH_OFFSET_X", dbPath = DB_KEY .. ".offsetX", min = -80, max = 80, step = 1, default = 0, apply = Apply, newSince = NEW_SINCE },
        { key = "offsetY", type = "slider", textKey = "PAH_OFFSET_Y", dbPath = DB_KEY .. ".offsetY", min = -80, max = 80, step = 1, default = 0, apply = Apply, newSince = NEW_SINCE },
        { type = "subtitle", textKey = "PAH_COLOR", newSince = NEW_SINCE },
        { key = "fontR", type = "slider", textKey = "PAH_COLOR_R", getter = GetColor(1, 1), setter = SetColor(1), min = 0, max = 100, step = 1, default = 100, formatFunc = FormatPct, apply = Apply, newSince = NEW_SINCE },
        { key = "fontG", type = "slider", textKey = "PAH_COLOR_G", getter = GetColor(2, 0.2), setter = SetColor(2), min = 0, max = 100, step = 1, default = 20, formatFunc = FormatPct, apply = Apply, newSince = NEW_SINCE },
        { key = "fontB", type = "slider", textKey = "PAH_COLOR_B", getter = GetColor(3, 0.2), setter = SetColor(3), min = 0, max = 100, step = 1, default = 20, formatFunc = FormatPct, apply = Apply, newSince = NEW_SINCE },
        { key = "fontA", type = "slider", textKey = "PAH_COLOR_A", getter = GetColor(4, 1), setter = SetColor(4), min = 0, max = 100, step = 1, default = 100, formatFunc = FormatPct, apply = Apply, newSince = NEW_SINCE },
        { type = "subtitle", textKey = "PAH_EFFECTS", newSince = NEW_SINCE },
        { key = "flashEnabled", type = "check", textKey = "PAH_FLASH", dbPath = DB_KEY .. ".flashEnabled", default = false, apply = Apply, newSince = NEW_SINCE },
        { key = "flashInterval", type = "slider", textKey = "PAH_FLASH_INTERVAL", dbPath = DB_KEY .. ".flashInterval", min = 0.1, max = 2.0, step = 0.1, default = 0.5, formatFunc = FormatSeconds, apply = Apply, newSince = NEW_SINCE },
        { key = "soundEnabled", type = "check", textKey = "PAH_SOUND", dbPath = DB_KEY .. ".soundEnabled", default = false, apply = Apply, newSince = NEW_SINCE },
        { key = "soundPath", type = "editbox", textKey = "PAH_SOUND_PATH", dbPath = DB_KEY .. ".soundPath", default = "", apply = Apply, newSince = NEW_SINCE },
        }
    end,
})

end)
