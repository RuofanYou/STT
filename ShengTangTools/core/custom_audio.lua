local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

-- 自定义配音语音包系统（纯解析，不做播放）
-- 播放统一由 tts_queue 的队列调度，避免同帧 Stop+Play 冲突。

local CustomAudio = {}
T.CustomAudio = CustomAudio

local packs = {}
local packIndex = {}
local discoveryStarted = false
local discoveryFrame = nil

local BUILTIN_ADDON = "ShengTangTools"
local BUILTIN_NAME = "STT默认配音包"
local BUILTIN_PATH = "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\Voice\\"
packs[1] = { BUILTIN_ADDON, BUILTIN_NAME, BUILTIN_PATH }
packIndex[BUILTIN_ADDON] = true

local function GetActivePathPrefix()
    local selected = C.DB.customAudioPack or BUILTIN_ADDON
    for _, pack in ipairs(packs) do
        if pack[1] == selected then
            return pack[3]
        end
    end
    return BUILTIN_PATH
end

local function SanitizeFileName(text)
    return text:gsub("：", ""):gsub(":", "")
end

-- 构建音频文件路径（不播放，只拼路径）
local function BuildPath(fileName)
    return GetActivePathPrefix() .. SanitizeFileName(fileName) .. ".mp3"
end

-- 解析文本，返回匹配到的音频路径和剩余文本。不做任何播放。
-- 成功：path, label, remainder
-- 失败：nil
function CustomAudio.Resolve(text)
    if not text or text == "" then return nil end
    if C.DB.customAudioEnabled == false then return nil end
    CustomAudio.EnsureDiscovery()

    -- 1) 完整文本精确匹配
    local path = BuildPath(text)
    -- 用 "尝试"标记，实际验证交给队列播放时的 PlaySoundFile
    -- 这里无法预判文件是否存在，直接返回路径让队列去试
    -- 但为了避免所有文本都进音频队列，我们仍需做一次 PlaySoundFile 探测
    -- 不对——探测会触发播放。改为：返回候选列表，让队列逐个尝试。

    -- 返回候选列表：每项 = {path, label, remainder}
    -- 队列依次尝试 PlaySoundFile，第一个成功的就用
    local candidates = {}

    -- 候选1：完整文本
    candidates[1] = { path = BuildPath(text), label = text, remainder = "" }

    -- 候选2+：按空格从左截断的前缀
    local pos = 1
    while true do
        local spacePos = text:find(" ", pos)
        if not spacePos then break end
        local prefix = text:sub(1, spacePos - 1)
        if prefix ~= "" then
            candidates[#candidates + 1] = {
                path = BuildPath(prefix),
                label = prefix,
                remainder = text:sub(spacePos + 1),
            }
        end
        pos = spacePos + 1
    end

    return candidates
end

function CustomAudio.GetPacks()
    CustomAudio.EnsureDiscovery()
    local options = {}
    for _, pack in ipairs(packs) do
        options[#options + 1] = { text = pack[2], value = pack[1] }
    end
    return options
end

local function GetMetadata(addon, key)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, key)
    end
    if GetAddOnMetadata then
        return GetAddOnMetadata(addon, key)
    end
    return nil
end

local function DiscoverPack(addon)
    if packIndex[addon] then return end
    local name = GetMetadata(addon, "X-STT-VoicePack-Name")
    local path = GetMetadata(addon, "X-STT-VoicePack-Path")
    if name and path then
        path = path:gsub("/", "\\")
        if path:sub(-1) ~= "\\" then
            path = path .. "\\"
        end
        packs[#packs + 1] = { addon, name, path }
        packIndex[addon] = true
        T.debug("发现语音包: " .. name .. " (" .. addon .. ")")
    end
end

local function ScanLoadedAddons()
    local count = nil
    if C_AddOns and C_AddOns.GetNumAddOns then
        count = C_AddOns.GetNumAddOns()
    elseif GetNumAddOns then
        count = GetNumAddOns()
    end
    if not count then
        return
    end

    for i = 1, count do
        local addon = nil
        if C_AddOns and C_AddOns.GetAddOnInfo then
            addon = (select(1, C_AddOns.GetAddOnInfo(i)))
        elseif GetAddOnInfo then
            addon = (select(1, GetAddOnInfo(i)))
        end
        if addon then
            DiscoverPack(addon)
        end
    end
end

function CustomAudio.EnsureDiscovery()
    if discoveryStarted then
        return
    end
    discoveryStarted = true

    ScanLoadedAddons()
    if not CreateFrame then
        return
    end

    discoveryFrame = CreateFrame("Frame")
    discoveryFrame:RegisterEvent("ADDON_LOADED")
    discoveryFrame:SetScript("OnEvent", function(_, _, addon)
        DiscoverPack(addon)
    end)
end

end)
