-- 媒体文件注册
local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.editorLoaded", "CountdownEnabled", "auraColorAlert.enabled", "personalAuraAlert.enabled", "dreadElegy.enabled", "luraCrystal.enabled", "realtimeBoard.enabled"}, function()

-- 尝试获取LibSharedMedia
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- 内置材质定义
local BUILTIN_TEXTURES = {
    default = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    smooth = "Interface\\TargetingFrame\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}

-- 获取指定的材质
T.GetBarTexture = function(textureName)
    if not textureName then
        textureName = "default"
    end

    -- 首先检查内置材质
    if BUILTIN_TEXTURES[textureName] then
        return BUILTIN_TEXTURES[textureName]
    end

    -- 如果有LSM，尝试从LSM获取
    if LSM then
        local texture = LSM:Fetch("statusbar", textureName, true)
        if texture then
            return texture
        end
    end

    -- 如果是特定材质名，尝试常用路径
    if textureName == "Melli" then
        local paths = {
            "Interface\\AddOns\\ElvUI\\Core\\Media\\Textures\\Melli",
            "Interface\\AddOns\\ElvUI\\Media\\Textures\\Melli",
            "Interface\\AddOns\\ElvUI_BenikUI\\media\\textures\\Melli",
            "Interface\\AddOns\\SharedMedia\\statusbar\\Melli",
            "Interface\\AddOns\\SharedMedia_MyMedia\\statusbar\\Melli",
        }

        for _, path in ipairs(paths) do
            -- 尝试加载纹理
            local test = CreateFrame("Frame")
            local tex = test:CreateTexture()
            tex:SetTexture(path)
            if tex:GetTexture() then
                test:Hide()
                return path
            end
            test:Hide()
        end
    end

    -- 返回默认材质
    return BUILTIN_TEXTURES.default
end

-- 获取可用材质列表
T.GetAvailableTextures = function()
    local textures = {}

    -- 添加内置材质
    for name, _ in pairs(BUILTIN_TEXTURES) do
        table.insert(textures, name)
    end

    -- 如果有LSM，添加LSM材质
    if LSM then
        local mediaList = LSM:List("statusbar")
        if mediaList then
            for _, name in ipairs(mediaList) do
                -- 避免重复
                local exists = false
                for _, existing in ipairs(textures) do
                    if existing == name then
                        exists = true
                        break
                    end
                end
                if not exists and name ~= "None" then
                    table.insert(textures, name)
                end
            end
        end
    end

    return textures
end

end)
