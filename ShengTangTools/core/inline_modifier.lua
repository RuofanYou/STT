local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

local Modifier = {}
T.InlineModifier = Modifier

local COUNTDOWN_SYNTAX_VERSION = 1
local BUILTIN_SOUND_PATH = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\"

local function Debug(message)
    if T and T.debug then
        T.debug(message)
    end
end

local function DebugInvalidModifier(name, value)
    if name == "dur" and tostring(value) == "0" then
        return
    end
    Debug("[Modifier] invalid name=" .. tostring(name) .. " value=" .. tostring(value))
end

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function ParsePositiveNumber(value)
    if type(value) ~= "string" or not value:match("^%d+%.?%d*$") then
        return nil
    end
    local number = tonumber(value)
    if number and number > 0 then
        return number
    end
    return nil
end

local function ParseBarValue(value)
    if type(value) ~= "string" then
        return nil
    end

    local durationText, rest = value:match("^%s*(%d+%.?%d*)(.*)$")
    local duration = ParsePositiveNumber(durationText)
    if not duration or duration > 600 then
        return nil
    end

    local out = { duration = duration }
    rest = rest or ""
    if Trim(rest) == "" then
        return out
    end

    local labelText
    rest = rest:gsub(",%s*label%s*:%s*<([^>]*)>", function(text)
        labelText = text
        return ""
    end)
    if labelText ~= nil then
        out.labelOverride = labelText
    end

    local consumed = rest
    for key, rawValue in rest:gmatch(",%s*(%w+)%s*:%s*([^,]+)") do
        local normalizedKey = key:lower()
        local arg = Trim(rawValue)
        if normalizedKey == "tick" then
            local tick = ParsePositiveNumber(arg)
            if not tick or tick > duration then
                return nil
            end
            out.tickInterval = tick
        elseif normalizedKey == "spell" then
            if not arg:match("^%d+$") then
                return nil
            end
            local spellID = tonumber(arg)
            if not spellID or spellID <= 0 then
                return nil
            end
            out.spellID = spellID
        elseif normalizedKey == "icon" then
            if arg == "" or arg:find("[{}\r\n]") then
                return nil
            end
            out.iconOverride = tonumber(arg) or arg
        else
            return nil
        end
    end

    consumed = consumed
        :gsub(",%s*[Tt][Ii][Cc][Kk]%s*:%s*%d+%.?%d*", "")
        :gsub(",%s*[Ss][Pp][Ee][Ll][Ll]%s*:%s*%d+", "")
        :gsub(",%s*[Ii][Cc][Oo][Nn]%s*:%s*[^,]+", "")
    if Trim(consumed) ~= "" then
        return nil
    end

    return out
end

local function ValidateDurationValue(value)
    local duration = ParsePositiveNumber(Trim(value))
    if duration and duration <= 600 then
        return true, duration
    end
    return false
end

local function ValidateCountdownValue(value)
    local text = Trim(value)
    if not text:match("^%d+$") then
        return false
    end
    local number = tonumber(text)
    if number and number >= 1 and number <= 10 then
        return true, number
    end
    return false
end

local function ValidateScreenReminderLeadValue(value)
    local text = Trim(value)
    if not text:match("^%d+%.?%d*$") then
        return false
    end
    local number = tonumber(text)
    if number and number >= 0 and number <= 10 then
        return true, number
    end
    return false
end

Modifier.KNOWN = {
    ct = {
        validate = ValidateCountdownValue,
    },
    sr = {
        validate = ValidateScreenReminderLeadValue,
    },
    dur = {
        validate = ValidateDurationValue,
    },
    bar = {
        multiple = true,
        validate = function(value)
            local parsed = ParseBarValue(value)
            if parsed then
                return true, parsed
            end
            return false
        end,
    },
}

local function NormalizeSoundPath(value)
    local payload = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if payload == "" or payload:find("[{}\r\n]") then
        return nil
    end

    payload = payload:gsub("/", "\\")
    if payload:find("\\", 1, true) then
        return payload, payload
    end
    return BUILTIN_SOUND_PATH .. payload, payload
end

local function FindSoundToken(text, startIndex)
    local closeIndex = text:find("}", startIndex + 2, true)
    if not closeIndex then
        return #text, text:sub(startIndex + 2), false
    end

    local endIndex = closeIndex
    while text:sub(endIndex + 1, endIndex + 1) == "}" do
        endIndex = endIndex + 1
    end
    return endIndex, text:sub(startIndex + 2, closeIndex - 1), true
end

local function ScanSoundTokens(text, mods)
    local strippedParts = {}
    local cursor = 1
    local found = false

    while true do
        local startIndex = text:find("{@", cursor, true)
        if not startIndex then
            strippedParts[#strippedParts + 1] = text:sub(cursor)
            break
        end

        strippedParts[#strippedParts + 1] = text:sub(cursor, startIndex - 1)
        local endIndex, payload, closed = FindSoundToken(text, startIndex)
        found = true
        if mods.sound then
            Debug("[Modifier] duplicate name=sound ignored")
        else
            local path, label
            if closed then
                path, label = NormalizeSoundPath(payload)
            end
            if path then
                mods.sound = { path = path, label = label }
            else
                DebugInvalidModifier("sound", payload)
            end
        end
        cursor = endIndex + 1
    end

    if found then
        return table.concat(strippedParts)
    end
    return text
end

local function StoreModifier(mods, name, value)
    local def = Modifier.KNOWN[name]
    if not def then
        return
    end
    if def.multiple then
        local ok, parsed = def.validate(value)
        if ok then
            if not mods[name] then
                mods[name] = { value = parsed, values = { parsed } }
            else
                mods[name].values = mods[name].values or {}
                mods[name].values[#mods[name].values + 1] = parsed
            end
        else
            DebugInvalidModifier(name, value)
        end
        return
    end
    if mods[name] then
        Debug("[Modifier] duplicate name=" .. tostring(name) .. " ignored")
        return
    end
    local ok, parsed = def.validate(value)
    if ok then
        mods[name] = { value = parsed }
    else
        DebugInvalidModifier(name, value)
    end
end

local function ScanSpellAttachedDuration(text, mods)
    local stripped = tostring(text or "")
    stripped = stripped:gsub("{spell:(%d+)(:%d+),%s*dur%s*:%s*([^,{}]+)%s*}", function(spellID, occurrence, value)
        StoreModifier(mods, "dur", value)
        return "{spell:" .. spellID .. occurrence .. "}"
    end)
    stripped = stripped:gsub("{spell:(%d+),%s*dur%s*:%s*([^,{}]+)%s*}", function(spellID, value)
        StoreModifier(mods, "dur", value)
        return "{spell:" .. spellID .. "}"
    end)
    return stripped
end

function Modifier.Scan(text)
    if type(text) ~= "string" or text == "" then
        return { modifiers = {}, stripped = text or "" }
    end

    local mods = {}
    text = ScanSoundTokens(text, mods)
    text = ScanSpellAttachedDuration(text, mods)
    for name, def in pairs(Modifier.KNOWN) do
        local pattern = "{(" .. name .. "):([^{}]*)}"
        for _, value in text:gmatch(pattern) do
            StoreModifier(mods, name, value)
        end
    end

    local stripped = text
    for name in pairs(Modifier.KNOWN) do
        stripped = stripped:gsub("{" .. name .. ":[^{}]*}", "")
    end
    stripped = stripped:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

    return { modifiers = mods, stripped = stripped }
end

local function FormatModifierNumber(value)
    local number = tonumber(value)
    if not number then
        return nil
    end
    if math.abs(number - math.floor(number + 0.5)) < 0.0001 then
        return tostring(math.floor(number + 0.5))
    end
    return tostring(number)
end

local function ReadModifierValue(entry)
    if type(entry) == "table" and entry.value ~= nil then
        return entry.value
    end
    return entry
end

local function ComposeBarValue(bar)
    local value = ReadModifierValue(bar)
    if type(value) ~= "table" then
        return nil
    end
    local duration = FormatModifierNumber(value.duration or value.n)
    if not duration then
        return nil
    end

    local parts = { duration }
    local tick = FormatModifierNumber(value.tickInterval or value.tick)
    if tick then
        parts[#parts + 1] = "tick:" .. tick
    end
    local spellID = tonumber(value.spellID or value.spell)
    if spellID and spellID > 0 then
        parts[#parts + 1] = "spell:" .. tostring(math.floor(spellID + 0.5))
    end
    local label = Trim(value.labelOverride or value.label)
    if label ~= "" and not label:find("[{}\r\n]") then
        parts[#parts + 1] = "label:<" .. label .. ">"
    end
    local icon = value.iconOverride or value.icon
    if icon ~= nil then
        local iconText = Trim(icon)
        if iconText ~= "" and not iconText:find("[{}\r\n,]") then
            parts[#parts + 1] = "icon:" .. iconText
        end
    end
    return "{bar:" .. table.concat(parts, ",") .. "}"
end

function Modifier.Compose(modifiers)
    if type(modifiers) ~= "table" then
        return ""
    end

    local parts = {}
    local ct = tonumber(ReadModifierValue(modifiers.ct))
    if ct and ct >= 1 and ct <= 10 then
        parts[#parts + 1] = "{ct:" .. tostring(math.floor(ct + 0.5)) .. "}"
    end

    local sr = FormatModifierNumber(ReadModifierValue(modifiers.sr))
    if sr and tonumber(sr) and tonumber(sr) >= 0 and tonumber(sr) <= 10 then
        parts[#parts + 1] = "{sr:" .. sr .. "}"
    end

    local dur = FormatModifierNumber(ReadModifierValue(modifiers.dur))
    if dur then
        parts[#parts + 1] = "{dur:" .. dur .. "}"
    end

    local barToken = ComposeBarValue(modifiers.bar)
    if barToken then
        parts[#parts + 1] = barToken
    end

    local sound = ReadModifierValue(modifiers.sound)
    if type(sound) == "table" then
        sound = sound.label or sound.path
    end
    sound = Trim(sound)
    if sound ~= "" and not sound:find("[{}\r\n]") then
        parts[#parts + 1] = "{@" .. sound .. "}"
    end

    return table.concat(parts, "")
end

function Modifier.GetBarValues(source)
    local modifiers = type(source and source.modifiers) == "table" and source.modifiers or source
    local modifier = type(modifiers) == "table" and modifiers.bar or nil
    if type(modifier) ~= "table" then
        return nil
    end
    if type(modifier.values) == "table" and #modifier.values > 0 then
        return modifier.values
    end
    if type(modifier.value) == "table" then
        return { modifier.value }
    end
    return nil
end

function Modifier.MigrateLegacyCountdownText(text)
    if type(text) ~= "string" or text == "" then
        return text, false
    end

    local changed = false
    local migrated = text:gsub("%[倒计时:(%d+)%]", function(value)
        changed = true
        return "{ct:" .. tostring(value) .. "}"
    end)
    return migrated, changed
end

function Modifier.MigrateSavedVariables()
    if type(STT_DB) ~= "table" then
        return false
    end
    local currentVersion = tonumber(STT_DB._countdownSyntaxVersion) or 0
    if currentVersion >= COUNTDOWN_SYNTAX_VERSION then
        return false
    end

    local changedCount = 0

    local function MigratePlanTable(plans)
        if type(plans) ~= "table" then
            return
        end
        for id, content in pairs(plans) do
            local migrated, changed = Modifier.MigrateLegacyCountdownText(content)
            if changed then
                plans[id] = migrated
                changedCount = changedCount + 1
            end
        end
    end

    MigratePlanTable(STT_DB.Plans)
    if type(STT_DB.Profiles) == "table" then
        for _, profile in pairs(STT_DB.Profiles) do
            if type(profile) == "table" then
                MigratePlanTable(profile.Plans)
                local migratedSelfNote, changedSelfNote = Modifier.MigrateLegacyCountdownText(profile.SelfNote)
                if changedSelfNote then
                    profile.SelfNote = migratedSelfNote
                    changedCount = changedCount + 1
                end
            end
        end
    end

    local migratedCurrentSTN, changedCurrentSTN = Modifier.MigrateLegacyCountdownText(STT_DB.currentSTNNote)
    if changedCurrentSTN then
        STT_DB.currentSTNNote = migratedCurrentSTN
        changedCount = changedCount + 1
    end
    local migratedCurrentNote, changedCurrentNote = Modifier.MigrateLegacyCountdownText(STT_DB.currentNote)
    if changedCurrentNote then
        STT_DB.currentNote = migratedCurrentNote
        changedCount = changedCount + 1
    end

    STT_DB._countdownSyntaxVersion = COUNTDOWN_SYNTAX_VERSION
    if changedCount > 0 then
        Debug("[CountdownMigration] changed=" .. tostring(changedCount))
    end
    return changedCount > 0
end

end)
