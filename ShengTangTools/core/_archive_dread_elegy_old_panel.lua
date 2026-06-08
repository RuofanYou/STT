local T = unpack(select(2, ...))
T.RegisterColdFile("dreadElegy.enabled", function()

-- ═══════════════════════════════════════════════════════════════
-- [归档] 旧版符文顺序面板 + 侧栏快捷录入
-- 已被 ChatMirror 圆形累积显示替代，保留仅供样式参考。
-- 此文件不加载（不在 TOC 中），不影响运行。
-- ═══════════════════════════════════════════════════════════════

--[[

-- ── 显示系统 ─────────────────────────────────────────────────
local HEADER_HEIGHT = 22

local function CreateContainerFrame()
    if containerFrame then return containerFrame end

    local f = CreateFrame("Frame", "STT_DreadElegyDisplay", UIParent, "BackdropTemplate")
    f:SetSize(CONTAINER_SIZE, CONTAINER_SIZE + HEADER_HEIGHT)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" })
    header:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.header = header

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    title:SetPoint("CENTER", header, "CENTER", 0, 0)
    title:SetTextColor(1, 0.82, 0)
    f.title = title

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.content = content

    local bossIcon = content:CreateTexture(nil, "ARTWORK", nil, 0)
    bossIcon:SetSize(ICON_SIZE * 1.25, ICON_SIZE * 1.25)
    bossIcon:SetPoint("CENTER", content, "CENTER", 0, 18)
    bossIcon:SetTexture("Interface\\AddOns\\ShengTangTools\\media\\lura.tga")
    bossIcon:SetAlpha(0.85)
    f.bossIcon = bossIcon

    local bossLabel = content:CreateFontString(nil, "OVERLAY")
    bossLabel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    bossLabel:SetPoint("CENTER", bossIcon, "CENTER", 0, 0)
    bossLabel:SetTextColor(1, 1, 1)
    bossLabel:SetText("BOSS")
    f.bossLabel = bossLabel

    local fadeOut = f:CreateAnimationGroup()
    local alpha = fadeOut:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetDuration(FADE_OUT_DURATION)
    fadeOut:SetScript("OnFinished", function()
        f:Hide()
        f:SetAlpha(1)
    end)
    f.fadeOut = fadeOut

    containerFrame = f
    return f
end

-- ── 侧栏快捷录入 ────────────────────────────────────────────

local function UpdateSidebarProgress()
    if not sidebarFrame then return end
    sidebarFrame.progress:SetText(sidebarSlot .. "/" .. RUNE_COUNT)
end

local function SidebarOnRuneClick(runeId)
    -- ... 侧栏点击处理
end

SidebarReset = function(broadcast)
    -- ... 侧栏重置
end

local function CreateSidebarFrame()
    -- ... 侧栏 UI 创建（5 个符文按钮 + 重置 + 顺逆切换）
end

ShowSidebar = function()
    local db = GetDB()
    if db.commanderEnabled and containerFrame and containerFrame:IsShown() then
        CreateSidebarFrame()
        sidebarFrame:SetAlpha(containerFrame:GetAlpha())
        sidebarFrame:Show()
    end
end

HideSidebar = function()
    if sidebarFrame then sidebarFrame:Hide() end
end

local function GetOrCreateRuneFrame(index)
    -- ... 单个符文框架创建（图标 + 序号 + 入场动画）
end

function DreadElegy:ShowRuneOrder(sequence, persistent)
    -- ... 圆形排列显示符文顺序
end

function DreadElegy:HideRuneOrder()
    -- ... 隐藏面板
end

]]--

end)
