-- screen_reminder/media_presets.lua
-- 屏幕提醒 statusbar / circle 材质 preset 注册表（单一权威）
-- 新增 preset 仅修改本文件的数据表，消费方（schema / GUI / indicator）无需改动。
-- texture 字段支持两种形式：
--   "Interface\\..." 文件路径 → 用 SetTexture 加载（tga / blp / png）
--   "atlas:<name>"           → 用 SetAtlas 加载 WoW 内置 atlas（需 12.0+）

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

local MEDIA_BASE = "Interface\\AddOns\\ShengTangTools\\media\\textures\\"

local Presets = {
    statusbar = {
        -- WoW 内置纹理（LSM 库默认 4 个）
        { key = "blizzard",        displayKey = "SR_PRESET_BLIZZARD",
          texture = "Interface\\TargetingFrame\\UI-StatusBar" },
        { key = "blizzard_skills", displayKey = "SR_PRESET_BLIZZARD_SKILLS",
          texture = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
        { key = "blizzard_raid",   displayKey = "SR_PRESET_BLIZZARD_RAID",
          texture = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
        { key = "flat",            displayKey = "SR_PRESET_FLAT",
          texture = "Interface\\Buttons\\WHITE8X8" },

        -- WoW 12.0+ 内置职业资源 atlas（无需 tga 文件，UI 源码社区惯用）
        { key = "atlas_energy",      displayKey = "SR_PRESET_ATLAS_ENERGY",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-Energy" },
        { key = "atlas_focus",       displayKey = "SR_PRESET_ATLAS_FOCUS",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-Focus" },
        { key = "atlas_fury",        displayKey = "SR_PRESET_ATLAS_FURY",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-Fury" },
        { key = "atlas_insanity",    displayKey = "SR_PRESET_ATLAS_INSANITY",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-Insanity" },
        { key = "atlas_lunarpower",  displayKey = "SR_PRESET_ATLAS_LUNARPOWER",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-LunarPower" },
        { key = "atlas_maelstrom",   displayKey = "SR_PRESET_ATLAS_MAELSTROM",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-Maelstrom" },
        { key = "atlas_mana",        displayKey = "SR_PRESET_ATLAS_MANA",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-Mana" },
        { key = "atlas_pain",        displayKey = "SR_PRESET_ATLAS_PAIN",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-Pain" },
        { key = "atlas_rage",        displayKey = "SR_PRESET_ATLAS_RAGE",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-Rage" },
        { key = "atlas_runicpower",  displayKey = "SR_PRESET_ATLAS_RUNICPOWER",
          texture = "atlas:UI-HUD-UnitFrame-Player-PortraitOff-Bar-RunicPower" },

        -- 社区经典纹理（自带 tga）
        { key = "smooth",    displayKey = "SR_PRESET_SMOOTH",
          texture = MEDIA_BASE .. "preset_bar_smooth.tga" },
        { key = "glaze",     displayKey = "SR_PRESET_GLAZE",
          texture = MEDIA_BASE .. "preset_bar_glaze.tga" },
        { key = "glass",     displayKey = "SR_PRESET_GLASS",
          texture = MEDIA_BASE .. "preset_bar_glass.tga" },
        { key = "gloss",     displayKey = "SR_PRESET_GLOSS",
          texture = MEDIA_BASE .. "preset_bar_gloss.tga" },
        { key = "glamour",   displayKey = "SR_PRESET_GLAMOUR",
          texture = MEDIA_BASE .. "preset_bar_glamour.tga" },
        { key = "frost",     displayKey = "SR_PRESET_FROST",
          texture = MEDIA_BASE .. "preset_bar_frost.tga" },
        { key = "steel",     displayKey = "SR_PRESET_STEEL",
          texture = MEDIA_BASE .. "preset_bar_steel.tga" },
        { key = "aluminium", displayKey = "SR_PRESET_ALUMINIUM",
          texture = MEDIA_BASE .. "preset_bar_aluminium.tga" },
        { key = "charcoal",  displayKey = "SR_PRESET_CHARCOAL",
          texture = MEDIA_BASE .. "preset_bar_charcoal.tga" },
        { key = "healbot",   displayKey = "SR_PRESET_HEALBOT",
          texture = MEDIA_BASE .. "preset_bar_healbot.tga" },
        { key = "otravi",    displayKey = "SR_PRESET_OTRAVI",
          texture = MEDIA_BASE .. "preset_bar_otravi.tga" },
        { key = "tube",      displayKey = "SR_PRESET_TUBE",
          texture = MEDIA_BASE .. "preset_bar_tube.tga" },
    },

    -- circle preset 由 Tools/build_circle_presets.py 从对应 statusbar 极坐标卷绕生成
    -- 视觉风格与同名 statusbar 一致（横向纹理卷成一圈、纵向剖面成径向）
    circle = {
        { key = "flat",      displayKey = "SR_PRESET_FLAT",
          texture = MEDIA_BASE .. "circle_white.png" },
        { key = "smooth",    displayKey = "SR_PRESET_SMOOTH",
          texture = MEDIA_BASE .. "preset_circle_smooth.tga" },
        { key = "glaze",     displayKey = "SR_PRESET_GLAZE",
          texture = MEDIA_BASE .. "preset_circle_glaze.tga" },
        { key = "glass",     displayKey = "SR_PRESET_GLASS",
          texture = MEDIA_BASE .. "preset_circle_glass.tga" },
        { key = "gloss",     displayKey = "SR_PRESET_GLOSS",
          texture = MEDIA_BASE .. "preset_circle_gloss.tga" },
        { key = "glamour",   displayKey = "SR_PRESET_GLAMOUR",
          texture = MEDIA_BASE .. "preset_circle_glamour.tga" },
        { key = "frost",     displayKey = "SR_PRESET_FROST",
          texture = MEDIA_BASE .. "preset_circle_frost.tga" },
        { key = "steel",     displayKey = "SR_PRESET_STEEL",
          texture = MEDIA_BASE .. "preset_circle_steel.tga" },
        { key = "aluminium", displayKey = "SR_PRESET_ALUMINIUM",
          texture = MEDIA_BASE .. "preset_circle_aluminium.tga" },
        { key = "charcoal",  displayKey = "SR_PRESET_CHARCOAL",
          texture = MEDIA_BASE .. "preset_circle_charcoal.tga" },
        { key = "healbot",   displayKey = "SR_PRESET_HEALBOT",
          texture = MEDIA_BASE .. "preset_circle_healbot.tga" },
        { key = "otravi",    displayKey = "SR_PRESET_OTRAVI",
          texture = MEDIA_BASE .. "preset_circle_otravi.tga" },
        { key = "tube",      displayKey = "SR_PRESET_TUBE",
          texture = MEDIA_BASE .. "preset_circle_tube.tga" },
    },
}

function Presets.GetTexture(category, key)
    local list = Presets[category]
    if not list then return nil end
    for _, p in ipairs(list) do
        if p.key == key then return p.texture end
    end
    return list[1] and list[1].texture or nil
end

function Presets.GetDropdownItems(category)
    local list = Presets[category]
    local items = {}
    if not list then return items end
    -- statusbar 横长条 60×12；circle 正方形 16×16 避免压扁
    local iconSize = category == "circle" and { 16, 16 } or { 60, 12 }
    for _, p in ipairs(list) do
        items[#items + 1] = {
            value    = p.key,
            text     = L[p.displayKey] or p.key,
            icon     = p.texture,
            iconSize = iconSize,
        }
    end
    return items
end

T.ScreenReminderMediaPresets = Presets

end)
