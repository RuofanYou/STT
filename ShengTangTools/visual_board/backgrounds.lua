local T, C, L = unpack(select(2, ...))
do

local Backgrounds = {}
T.VisualBoardBackgrounds = Backgrounds

local DEFAULT_ARENA_TEXTURE = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\default_arena.tga"
local ENCOUNTER_BACKGROUNDS = {
    [3176] = { instanceType = "raid", instanceID = 1307, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.voidspire\\01.averzian-alt.tga", name = "元首阿福扎恩" },
    [3177] = { instanceType = "raid", instanceID = 1307, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.voidspire\\02.vorasius-alt.tga", name = "弗拉希乌斯" },
    [3179] = { instanceType = "raid", instanceID = 1307, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.voidspire\\03.salhadaar-alt.tga", name = "陨落之王萨哈达尔" },
    [3178] = { instanceType = "raid", instanceID = 1307, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.voidspire\\04.dragons-alt.tga", name = "威厄高尔和艾佐拉克" },
    [3180] = { instanceType = "raid", instanceID = 1307, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.voidspire\\05.vanguard-alt.tga", name = "光盲先锋军" },
    [3181] = { instanceType = "raid", instanceID = 1307, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.voidspire\\06.crown-main.tga", name = "宇宙之冕" },
    [3182] = { instanceType = "raid", instanceID = 1308, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.marchonqueldanas\\01.beloren-center.tga", name = "贝洛朗，奥的子嗣" },
    [3183] = { instanceType = "raid", instanceID = 1308, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.marchonqueldanas\\02.midnightfalls-main.tga", name = "至暗之夜降临" },
    [3306] = { instanceType = "raid", instanceID = 1314, texture = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\backgrounds\\maps\\wow.dreamrift\\01.chimaerus-main.tga", name = "奇美鲁斯，未梦之神" },
}

local ENCOUNTER_ORDER = {
    3176, 3177, 3179, 3178, 3180, 3181,
    3182, 3183,
    3306,
}

local function CopyBackground(bg, bossKeyText, encounterID)
    if type(bg) ~= "table" or type(bg.texture) ~= "string" or bg.texture == "" then
        return nil
    end
    return {
        type = "texture",
        texture = bg.texture,
        name = bg.name,
        bossKeyText = bossKeyText,
        encounterID = tonumber(encounterID) or nil,
        instanceType = bg.instanceType,
        instanceID = tonumber(bg.instanceID) or nil,
    }
end

function Backgrounds:GetCurrentBossContext()
    local semantic = T.SemanticTimeline
    if not (semantic and semantic.GetCurrentBossSelectorKey) then
        return nil
    end

    local bossKey = semantic:GetCurrentBossSelectorKey()
    if type(bossKey) ~= "table" then
        return nil
    end

    local bossKeyText = nil
    if semantic.SerializeBossSelectorKey then
        bossKeyText = semantic:SerializeBossSelectorKey(bossKey)
    end
    return bossKey, bossKeyText
end

function Backgrounds:ResolveDefaultForCurrentBoss()
    local bossKey, bossKeyText = self:GetCurrentBossContext()
    local encounterID = type(bossKey) == "table" and tonumber(bossKey.encounterID) or nil
    if not encounterID then
        return nil, bossKey, bossKeyText
    end

    local bg = ENCOUNTER_BACKGROUNDS[encounterID] or { texture = DEFAULT_ARENA_TEXTURE, name = "Default Arena" }
    return CopyBackground(bg, bossKeyText, encounterID), bossKey, bossKeyText
end

function Backgrounds:ResolveForEncounter(encounterID, bossKeyText)
    local id = tonumber(encounterID)
    local bg = id and ENCOUNTER_BACKGROUNDS[id] or nil
    if not bg then
        return nil
    end
    return CopyBackground(bg, bossKeyText, id)
end

function Backgrounds:GetAllMaps()
    local maps = {}
    for _, encounterID in ipairs(ENCOUNTER_ORDER) do
        local bg = ENCOUNTER_BACKGROUNDS[encounterID]
        if bg then
            local instanceType = tostring(bg.instanceType or "raid")
            local instanceID = tonumber(bg.instanceID) or 0
            maps[#maps + 1] = {
                value = encounterID,
                encounterID = encounterID,
                text = bg.name,
                name = bg.name,
                texture = bg.texture,
                bossKeyText = T.BuildSemanticBossKeyText and T.BuildSemanticBossKeyText(instanceType, instanceID, encounterID) or nil,
            }
        end
    end
    return maps
end

end
