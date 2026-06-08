local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("CountdownEnabled", function()

local Packs = {}
T.CountdownPacks = Packs

local BASE_PATH = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\"
local DEFAULT_PACK_ID = "stt_default"
local MAX_COUNTDOWN = 10

local BUILTIN = {
    { id = DEFAULT_PACK_ID, nameKey = "CT_PACK_STT_DEFAULT", basePath = BASE_PATH, pattern = "Announcer_%d.ogg", min = 1, max = 5 },
    { id = "jaina", nameKey = "CT_PACK_JAINA", basePath = BASE_PATH .. "jaina\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "illidan", nameKey = "CT_PACK_ILLIDAN", basePath = BASE_PATH .. "illidan\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "tyrael", nameKey = "CT_PACK_TYRAEL", basePath = BASE_PATH .. "tyrael\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "hots_anduin_tw", nameKey = "CT_PACK_HOTS_ANDUIN_TW", basePath = BASE_PATH .. "hots_anduin_tw\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "hots_alexstrasza_tw", nameKey = "CT_PACK_HOTS_ALEXSTRASZA_TW", basePath = BASE_PATH .. "hots_alexstrasza_tw\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "hots_maiev_tw", nameKey = "CT_PACK_HOTS_MAIEV_TW", basePath = BASE_PATH .. "hots_maiev_tw\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "overwatch_mei_zh", nameKey = "CT_PACK_OW_MEI_ZH", basePath = BASE_PATH .. "overwatch_mei_zh\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "overwatch_dva_tw", nameKey = "CT_PACK_OW_DVA_TW", basePath = BASE_PATH .. "overwatch_dva_tw\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "overwatch_hanzo_tw", nameKey = "CT_PACK_OW_HANZO_TW", basePath = BASE_PATH .. "overwatch_hanzo_tw\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "overwatch_genji_en", nameKey = "CT_PACK_OW_GENJI_EN", basePath = BASE_PATH .. "overwatch_genji_en\\", pattern = "%d.ogg", min = 1, max = 5 },
    { id = "overwatch_mercy_en", nameKey = "CT_PACK_OW_MERCY_EN", basePath = BASE_PATH .. "overwatch_mercy_en\\", pattern = "%d.ogg", min = 1, max = 5 },
}

local BUILTIN_BY_ID = {}
for _, def in ipairs(BUILTIN) do
    BUILTIN_BY_ID[def.id] = def
end

local VALID_CHANNELS = {
    Master = true,
    SFX = true,
    Dialog = true,
}

local function Text(key, fallback)
    if key and L and L[key] and L[key] ~= "" then
        return L[key]
    end
    return fallback or key or ""
end

local function NormalizeCountdownNumber(value)
    local number = tonumber(value)
    if not number or number < 1 or number > MAX_COUNTDOWN or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function EnsureDB()
    C.DB = C.DB or {}
    if type(C.DB.countdown) ~= "table" then
        C.DB.countdown = {}
    end
    if type(C.DB.countdown.activePackId) ~= "string" or not BUILTIN_BY_ID[C.DB.countdown.activePackId] then
        C.DB.countdown.activePackId = DEFAULT_PACK_ID
    end
    if type(STT_DB) == "table" then
        STT_DB.countdown = C.DB.countdown
    end
    return C.DB.countdown
end

local function ResolveBuiltinPath(def, number)
    if not def or number < (def.min or 1) or number > (def.max or MAX_COUNTDOWN) then
        return nil
    end
    return (def.basePath or "") .. string.format(def.pattern or "%d.ogg", number)
end

local function ResolvePackPath(packId, number)
    local builtin = BUILTIN_BY_ID[packId]
    if builtin then
        return ResolveBuiltinPath(builtin, number)
    end
    return nil
end

local function DebugResolve(packId, number, path)
    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format("[Countdown] Resolve pack=%s n=%s path=%s", tostring(packId), tostring(number), tostring(path)))
    end
end

function Packs.Resolve(number)
    local n = NormalizeCountdownNumber(number)
    if not n then
        return nil
    end
    local db = EnsureDB()
    local active = db.activePackId or DEFAULT_PACK_ID
    local path = ResolvePackPath(active, n)
    if not path and active ~= DEFAULT_PACK_ID then
        path = ResolvePackPath(DEFAULT_PACK_ID, n)
    end
    DebugResolve(active, n, path)
    return path
end

function Packs.GetDropdownOptions()
    EnsureDB()
    local options = {}
    for _, def in ipairs(BUILTIN) do
        local text = Text(def.nameKey, def.id)
        if def.id ~= DEFAULT_PACK_ID then
            text = string.format("%s [%s]", text, def.id)
        end
        options[#options + 1] = {
            text = text,
            value = def.id,
        }
    end
    return options
end

function Packs.GetChannel()
    local channel = C.DB and C.DB.CountdownChannel or "Master"
    if not VALID_CHANNELS[channel] then
        channel = "Master"
    end
    return channel
end

function Packs.Preview(maxNumber)
    local maxN = math.min(NormalizeCountdownNumber(maxNumber) or 5, 5)
    for offset = 0, maxN - 1 do
        local number = maxN - offset
        C_Timer.After(offset, function()
            local path = Packs.Resolve(number)
            if path then
                PlaySoundFile(path, Packs.GetChannel())
            end
        end)
    end
end

end)
