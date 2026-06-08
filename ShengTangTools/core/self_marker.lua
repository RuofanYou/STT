-- 自我位置标记（Self Marker）
-- 在屏幕固定位置（默认正中）显示一张静态贴图，帮助玩家定位自己角色。
-- 提供多种材质 / 动效 / 透明度 / 尺寸 / 位置 / 仅战斗中显示。
-- 注意：屏幕中心贴图在自由视角 / 锁视角偏移时与角色实际位置会错位，这是该形态的固有缺陷。
-- 编辑态视觉与拖拽完全走 T.EditMode 单一权威（core/editmode.lua）。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("selfMarker.enabled", function()

local DB_KEY = "selfMarker"

local SelfMarker = T.ModuleLoader:NewModule({
    name = "SelfMarker",
    dbKey = "selfMarker.enabled",
    defaultEnabled = false,
})

function SelfMarker:OnRegister()
    T.SelfMarker = self
end
T.SelfMarker = SelfMarker

local mover = nil
local border = nil
local texture = nil
local eventFrame = nil
local pulseAG = nil
local blinkAG = nil
local rotateAngle = 0
local inCombat = false

local FALLBACK_TEXTURE = [[Interface\TargetingFrame\UI-RaidTargetingIcon_3]]
local SOLID_BLOCK_TEXTURE = "__solid_block__"
local LEGACY_SOLID_GREEN_TEXTURE = "__solid_green__"
local DEFAULT_SOLID_COLOR = { 0.1, 1, 0.1, 1 }

local function CopyColor(value, fallback)
    local src = type(value) == "table" and value or fallback or DEFAULT_SOLID_COLOR
    return {
        tonumber(src[1]) or DEFAULT_SOLID_COLOR[1],
        tonumber(src[2]) or DEFAULT_SOLID_COLOR[2],
        tonumber(src[3]) or DEFAULT_SOLID_COLOR[3],
        tonumber(src[4]) or 1,
    }
end

local function GetDB()
    C.DB[DB_KEY] = C.DB[DB_KEY] or {}
    if C.DB[DB_KEY].texture == LEGACY_SOLID_GREEN_TEXTURE then
        C.DB[DB_KEY].texture = SOLID_BLOCK_TEXTURE
    end
    if type(STT_DB) == "table" then
        STT_DB[DB_KEY] = C.DB[DB_KEY]
    end
    return C.DB[DB_KEY]
end

local function IsEditing()
    return mover and T.EditMode and T.EditMode.IsEditing and T.EditMode:IsEditing(mover) or false
end

local function ClampNumber(value, lo, hi, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function ResolveTexturePath(db)
    local preset = db.texture or "atlas:Crosshair_Target"
    if preset == "__custom__" then
        local custom = db.textureCustom
        if type(custom) == "string" and custom ~= "" then
            return custom
        end
        return FALLBACK_TEXTURE
    end
    return preset
end

local function ApplyTexture()
    if not texture then return end
    local db = GetDB()
    if border then
        border:Hide()
    end
    texture:ClearAllPoints()
    texture:SetAllPoints(mover)

    if db.texture == SOLID_BLOCK_TEXTURE then
        local color = CopyColor(db.solidColor, DEFAULT_SOLID_COLOR)
        local size = mover and mover.GetWidth and mover:GetWidth() or 16
        local showBorder = db.solidBorder ~= false and size > 2
        if border then
            border:SetColorTexture(0, 0, 0, 1)
            border:SetShown(showBorder)
        end
        if showBorder then
            local inset = size >= 8 and 2 or 1
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", mover, "TOPLEFT", inset, -inset)
            texture:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", -inset, inset)
        end
        texture:SetTexture(nil)
        texture:SetColorTexture(color[1], color[2], color[3], 1)
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end

    local path = ResolveTexturePath(db)
    local atlasName = type(path) == "string" and path:match("^atlas:(.+)$") or nil
    if atlasName and texture.SetAtlas then
        local ok = pcall(texture.SetAtlas, texture, atlasName)
        if not ok then
            texture:SetTexture(FALLBACK_TEXTURE)
        end
    else
        local ok = pcall(texture.SetTexture, texture, path)
        if not ok then
            texture:SetTexture(FALLBACK_TEXTURE)
        end
    end
    texture:SetTexCoord(0, 1, 0, 1)
end

local function ApplySize()
    if not mover then return end
    local size = ClampNumber(GetDB().size, 1, 100, 16)
    mover:SetSize(size, size)
end

local function ApplyAlpha()
    if not mover then return end
    local alpha = ClampNumber(GetDB().alpha, 0, 1, 0.5)
    mover:SetAlpha(alpha)
end

local function ApplyPosition()
    if not mover then return end
    local pos = GetDB().pos or {}
    local point = pos.point or "CENTER"
    local relPoint = pos.relPoint or "CENTER"
    local x = tonumber(pos.x) or 0
    local y = tonumber(pos.y) or 0
    mover:ClearAllPoints()
    mover:SetPoint(point, UIParent, relPoint, x, y)
end

local function SavePosition()
    if not mover then return end
    local point, _, relPoint, x, y = mover:GetPoint(1)
    local db = GetDB()
    db.pos = db.pos or {}
    db.pos.point = point or "CENTER"
    db.pos.relPoint = relPoint or "CENTER"
    db.pos.x = x or 0
    db.pos.y = y or 0
end

local function StopAllAnimations()
    if pulseAG and pulseAG:IsPlaying() then pulseAG:Stop() end
    if blinkAG and blinkAG:IsPlaying() then blinkAG:Stop() end
    if mover then
        mover:SetScript("OnUpdate", nil)
    end
    if texture then
        texture:SetRotation(0)
    end
    if border then
        border:SetRotation(0)
    end
    rotateAngle = 0
end

local function BuildPulseAG()
    if pulseAG or not mover then return end
    pulseAG = mover:CreateAnimationGroup()
    pulseAG:SetLooping("REPEAT")
    local up = pulseAG:CreateAnimation("Scale")
    up:SetScale(1.2, 1.2)
    up:SetDuration(0.5)
    up:SetOrder(1)
    up:SetSmoothing("IN_OUT")
    local down = pulseAG:CreateAnimation("Scale")
    down:SetScale(1 / 1.2, 1 / 1.2)
    down:SetDuration(0.5)
    down:SetOrder(2)
    down:SetSmoothing("IN_OUT")
    pulseAG._up = up
    pulseAG._down = down
end

local function BuildBlinkAG()
    if blinkAG or not mover then return end
    blinkAG = mover:CreateAnimationGroup()
    blinkAG:SetLooping("REPEAT")
    local fadeOut = blinkAG:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.1)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(1)
    fadeOut:SetSmoothing("IN_OUT")
    local fadeIn = blinkAG:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.1)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(2)
    fadeIn:SetSmoothing("IN_OUT")
    blinkAG._fadeOut = fadeOut
    blinkAG._fadeIn = fadeIn
end

local function ApplyAnimation()
    if not mover then return end
    StopAllAnimations()
    local db = GetDB()
    local mode = db.animation or "none"
    local period = ClampNumber(db.animPeriod, 0.5, 5, 1.5)

    if mode == "pulse" then
        BuildPulseAG()
        if pulseAG then
            local half = period * 0.5
            pulseAG._up:SetDuration(half)
            pulseAG._down:SetDuration(half)
            if mover:IsShown() then pulseAG:Play() end
        end
    elseif mode == "blink" then
        BuildBlinkAG()
        if blinkAG then
            local half = period * 0.5
            blinkAG._fadeOut:SetDuration(half)
            blinkAG._fadeIn:SetDuration(half)
            if mover:IsShown() then blinkAG:Play() end
        end
    elseif mode == "rotate" then
        local speed = (2 * math.pi) / period
        mover:SetScript("OnUpdate", function(_, elapsed)
            rotateAngle = rotateAngle + elapsed * speed
            if rotateAngle > math.pi * 2 then
                rotateAngle = rotateAngle - math.pi * 2
            end
            if texture then
                texture:SetRotation(rotateAngle)
            end
            if border then
                border:SetRotation(rotateAngle)
            end
        end)
    end
end

local function ComputeShouldShow()
    if IsEditing() then return true end
    local db = GetDB()
    if db.enabled ~= true then return false end
    if db.onlyInCombat == true and not inCombat then
        return false
    end
    return true
end

local function ApplyVisibility()
    if not mover then return end
    if ComputeShouldShow() then
        mover:Show()
        local mode = GetDB().animation or "none"
        if mode == "pulse" and pulseAG then pulseAG:Play() end
        if mode == "blink" and blinkAG then blinkAG:Play() end
    else
        StopAllAnimations()
        mover:Hide()
    end
end

local function EnsureUI()
    if mover then return mover end

    mover = CreateFrame("Frame", "STT_SelfMarker", UIParent)
    mover:SetFrameStrata("BACKGROUND")
    mover:SetFrameLevel(1)
    mover:SetClampedToScreen(true)
    mover:Hide()

    border = mover:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(mover)
    border:Hide()

    texture = mover:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(mover)

    ApplyPosition()
    ApplySize()
    ApplyTexture()
    ApplyAlpha()
    ApplyAnimation()

    if T.EditMode and T.EditMode.Register then
        T.EditMode:Register({
            frame = mover,
            displayName = L["OPT_SELF_MARKER_TITLE"] or "自我位置标记",
            saveFunc = function() SavePosition() end,
            group = "solo",
            onEnter = function()
                mover:Show()
            end,
            onExit = function()
                ApplyVisibility()
            end,
        })
    end

    return mover
end

local function EnsureEventFrame()
    if eventFrame then return eventFrame end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
        end
        ApplyVisibility()
    end)
    return eventFrame
end

function SelfMarker:Refresh()
    if not mover then return end
    ApplyTexture()
    ApplySize()
    ApplyAlpha()
    ApplyPosition()
    ApplyAnimation()
    ApplyVisibility()
end

function SelfMarker:ResetPosition()
    local db = GetDB()
    db.pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    if mover then ApplyPosition() end
    if T.msg then
        T.msg(L["OPT_SELF_MARKER_POS_RESET_MSG"] or "自我位置标记已回到屏幕中央。")
    end
end

function SelfMarker:ToggleEditMode()
    EnsureUI()
    if T.EditMode and T.EditMode.Toggle then
        T.EditMode:Toggle(mover)
    end
end

function SelfMarker:IsEditing()
    return IsEditing()
end

function SelfMarker:OnEnable()
    inCombat = (InCombatLockdown and InCombatLockdown()) or false
    EnsureUI()
    EnsureEventFrame()
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:Refresh()
end

function SelfMarker:OnDisable()
    if eventFrame then
        eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    if mover and T.EditMode and T.EditMode.Exit then
        T.EditMode:Exit(mover)
    end
    StopAllAnimations()
    if mover then mover:Hide() end
end

end)
