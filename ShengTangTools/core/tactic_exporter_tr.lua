local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("tacticTranslator.enabled", function()

local Exporter = {}
T.TacticExporterTR = Exporter

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetLibs()
    local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    return LibSerialize, LibDeflate
end

local function ReadTimelineBody(text)
    if T.STNTemplate and T.STNTemplate.PreprocessText then
        local info = T.STNTemplate.PreprocessText(text or "", { relaxed = true })
        if info and type(info.processedText) == "string" and info.processedText ~= "" then
            return info.processedText
        end
    end
    return tostring(text or "")
end

local function BuildRelativeTo(event, encounterID)
    if not (event and event.phase and encounterID) then return nil end
    local phaseName, roundText = tostring(event.phase):match("^([pi]%d+)r(%d+)$")
    if not phaseName then return nil end

    local anchors = T.PhaseAnchorsS14 and T.PhaseAnchorsS14[tonumber(encounterID)]
    local rule = anchors and anchors.templateRules and anchors.templateRules[phaseName]
    local spellID = rule and rule.type == "spell" and tonumber(rule.spellID) or nil
    if not spellID then return nil end

    return {
        value = spellID,
        count = tonumber(roundText) or 1,
    }
end

local function BuildLoadFromSegment(segment)
    if type(segment) ~= "table" then
        return { type = "ALL" }
    end

    local condition = Trim(segment.condition)
    if condition == "tank" then
        return { type = "ROLE", role = "TANK" }
    elseif condition == "healer" then
        return { type = "ROLE", role = "HEALER" }
    elseif condition == "dps" then
        return { type = "ROLE", role = "DAMAGER" }
    elseif condition == "melee" then
        return { type = "POSITION", position = "MELEE" }
    elseif condition == "ranged" then
        return { type = "POSITION", position = "RANGED" }
    end

    local group = condition:match("^g([1-8])$")
    if group then
        return { type = "GROUP", group = tonumber(group) }
    end

    local players = segment.players
    local name = type(players) == "table" and Trim(players[1]) or ""
    if name ~= "" and not name:find(",", 1, true) then
        return { type = "NAME", name = name }
    end
    return { type = "ALL" }
end

local function BuildDisplay(event)
    local spellID = tonumber(event and event.primarySpellID)
    if spellID and spellID > 0 then
        return {
            type = "SPELL",
            spellID = spellID,
        }
    end
    return {
        type = "TEXT",
        text = Trim(event and (event.displayText or event.content) or ""),
    }
end

local function BuildReminder(event, encounterID)
    local segment = event and event.segments and event.segments[1] or nil
    local modifiers = type(event and event.modifiers) == "table" and event.modifiers or {}
    local ct = modifiers.ct and tonumber(modifiers.ct.value) or nil
    local sound = modifiers.sound
    local soundPath = type(sound) == "table" and Trim(sound.label or sound.path) or ""

    return {
        trigger = {
            time = tonumber(event.time) or 0,
            relativeTo = BuildRelativeTo(event, encounterID),
        },
        load = BuildLoadFromSegment(segment),
        display = BuildDisplay(event),
        countdown = {
            enabled = ct ~= nil,
            start = ct,
        },
        sound = {
            enabled = soundPath ~= "",
            file = soundPath ~= "" and soundPath or nil,
        },
    }
end

function Exporter:Export(text, options)
    if not (C and C.DB and C.DB.debugMode == true) then
        return nil, "debug_only"
    end

    local syntax = T.TimelineSyntax
    if not (syntax and syntax.ParseTimelineText) then
        return nil, "timeline_syntax_missing"
    end

    local LibSerialize, LibDeflate = GetLibs()
    if not (LibSerialize and LibDeflate) then
        return nil, "libs_missing"
    end

    local encounterID = tonumber(options and options.encounterID)
    local events = syntax.ParseTimelineText(ReadTimelineBody(text))
    if type(events) ~= "table" or #events == 0 then
        return nil, "empty"
    end

    local payload = {
        v = 1,
        id = encounterID,
        r = {},
    }
    for index, event in ipairs(events) do
        payload.r[index] = BuildReminder(event, encounterID)
    end

    local serialized = LibSerialize:Serialize(payload)
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    local encoded = compressed and LibDeflate:EncodeForPrint(compressed) or nil
    if not encoded then
        return nil, "encode_failed"
    end
    return "!TR:" .. encoded, nil
end

end)
