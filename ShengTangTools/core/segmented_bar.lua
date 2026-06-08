local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("Bar.Enabled", function()

local SegmentedBar = {}
T.SegmentedBar = SegmentedBar

local activeInstances = {}
local containerFrame = nil
local warnedOverLimit = false

local DEFAULT_POSITION = {
    point = "CENTER",
    relPoint = "CENTER",
    x = 0,
    y = 100,
}

local function GetDB()
    C.DB.Bar = C.DB.Bar or {}
    local db = C.DB.Bar
    db.Container = db.Container or {}
    if type(db.Container.position) ~= "table" then
        db.Container.position = {}
    end
    db.Style = db.Style or {}
    return db
end

local function GetContainerConfig()
    local db = GetDB()
    local cfg = db.Container
    cfg.spacing = tonumber(cfg.spacing) or 4
    cfg.growth = cfg.growth == "UP" and "UP" or "DOWN"
    if type(cfg.position) ~= "table" then
        cfg.position = {}
    end
    return cfg
end

local function ResolveSpellName(spellID)
    local id = tonumber(spellID)
    if not id or id <= 0 then
        return nil
    end
    if T.SemanticTimeline and T.SemanticTimeline.GetSpellName then
        local name = T.SemanticTimeline:GetSpellName(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    return nil
end

local function ResolveSpellIcon(spellID)
    if T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        local icon = T.TimelineSyntax.ResolveSpellIcon(spellID)
        if icon then
            return icon
        end
    end
    local id = tonumber(spellID)
    if id and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and (info.iconID or info.originalIconID) or nil
    end
    return nil
end

local function ApplyContainerPosition(frame)
    local cfg = GetContainerConfig()
    local pos = cfg.position or DEFAULT_POSITION
    frame:ClearAllPoints()
    frame:SetPoint(
        pos.point or DEFAULT_POSITION.point,
        UIParent,
        pos.relPoint or DEFAULT_POSITION.relPoint,
        tonumber(pos.x) or DEFAULT_POSITION.x,
        tonumber(pos.y) or DEFAULT_POSITION.y
    )
end

local function SaveContainerPosition()
    if not containerFrame then
        return
    end
    local cfg = GetContainerConfig()
    local point, _, relPoint, x, y = containerFrame:GetPoint(1)
    cfg.position = cfg.position or {}
    cfg.position.point = point or DEFAULT_POSITION.point
    cfg.position.relPoint = relPoint or DEFAULT_POSITION.relPoint
    cfg.position.x = x or 0
    cfg.position.y = y or 0
    if T.debug then
        T.debug(string.format("[SegmentedBar] position_saved point=%s x=%.1f y=%.1f", tostring(point), tonumber(x) or 0, tonumber(y) or 0))
    end
end

local function GetDisplayName()
    return L["GUI_NAV_SEGMENTED_BAR"] or "分段进度条"
end

local function EnsureContainer()
    if containerFrame then
        return containerFrame
    end

    containerFrame = CreateFrame("Frame", "STTSegmentedBarContainer", UIParent, "BackdropTemplate")
    containerFrame:SetSize(280, 40)
    containerFrame:SetClampedToScreen(true)
    containerFrame:Hide()
    ApplyContainerPosition(containerFrame)

    if T.EditMode and T.EditMode.Register then
        T.EditMode:Register({
            frame = containerFrame,
            displayName = GetDisplayName(),
            saveFunc = function() SaveContainerPosition() end,
            group = "solo",
            onEnter = function()
                containerFrame:Show()
            end,
            onExit = function()
                containerFrame:SetShown(#activeInstances > 0)
            end,
        })
    end
    return containerFrame
end

local function LayoutInstances()
    local container = EnsureContainer()
    local cfg = GetContainerConfig()
    local spacing = cfg.spacing
    local maxWidth = 1
    local totalHeight = 1
    local cursorY = 0

    ApplyContainerPosition(container)

    for _, widget in ipairs(activeInstances) do
        local width, height = widget:GetSize()
        maxWidth = math.max(maxWidth, width)
        widget.frame:ClearAllPoints()
        if cfg.growth == "UP" then
            widget.frame:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, cursorY)
        else
            widget.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -cursorY)
        end
        cursorY = cursorY + height + spacing
        totalHeight = cursorY
    end

    container:SetSize(maxWidth, math.max(40, totalHeight))
    container:SetShown(#activeInstances > 0 or (T.IsUnlocked and T.IsUnlocked()))
end

local function RemoveInstance(widget)
    for index, instance in ipairs(activeInstances) do
        if instance == widget then
            table.remove(activeInstances, index)
            break
        end
    end
    if widget and widget.Destroy then
        widget:Destroy()
    end
    LayoutInstances()
end

function SegmentedBar:Show(opts)
    opts = type(opts) == "table" and opts or {}
    local db = GetDB()
    if db.Enabled == false then
        return nil
    end

    local duration = tonumber(opts.duration)
    if not duration or duration <= 0 then
        return nil
    end

    local softLimit = tonumber(db.SoftLimit) or 5
    if #activeInstances >= softLimit and not warnedOverLimit then
        warnedOverLimit = true
        if T.debug then
            T.debug("[SegmentedBar] soft_limit count=" .. tostring(#activeInstances + 1) .. " limit=" .. tostring(softLimit))
        end
    end

    local label = opts.labelOverride
        or ResolveSpellName(opts.spellID)
        or opts.fallbackLabel
        or ""
    local iconTexture = opts.iconOverride
        or ResolveSpellIcon(opts.spellID)
        or nil

    local widget = T.BarWidget and T.BarWidget:Create(EnsureContainer(), {
        duration = duration,
        tickInterval = opts.tickInterval,
        iconTexture = iconTexture,
        label = label,
        style = db.Style,
        onFinish = RemoveInstance,
    }) or nil
    if not widget then
        return nil
    end

    widget.eventID = opts.eventID
    widget.phase = opts.phase
    activeInstances[#activeInstances + 1] = widget
    LayoutInstances()
    widget:Start(opts.startTime)

    if C.DB and C.DB.debugMode and T.debug then
        T.debug(string.format(
            "[SegmentedBar] show duration=%.1f tick=%s label=%s event=%s",
            duration,
            tostring(opts.tickInterval),
            tostring(label),
            tostring(opts.eventID)
        ))
    end
    return widget
end

function SegmentedBar:ToggleAnchorLock()
    EnsureContainer()
    if T.EditMode and T.EditMode.Toggle then
        T.EditMode:Toggle(containerFrame)
    end
end

function SegmentedBar:IsAnchorUnlocked()
    if not (containerFrame and T.EditMode and T.EditMode.IsEditing) then
        return false
    end
    return T.EditMode:IsEditing(containerFrame)
end

function SegmentedBar:ClearAll()
    for index = #activeInstances, 1, -1 do
        local widget = activeInstances[index]
        activeInstances[index] = nil
        if widget and widget.Destroy then
            widget:Destroy()
        end
    end
    warnedOverLimit = false
    if containerFrame then
        containerFrame:Hide()
    end
end

function SegmentedBar:RefreshActiveStyle()
    local db = GetDB()
    for _, widget in ipairs(activeInstances) do
        if widget.SetStyle then
            widget:SetStyle(db.Style)
        end
    end
    LayoutInstances()
end

function SegmentedBar:DelayActive(phaseKey, delay)
    local normalizedDelay = tonumber(delay)
    if not normalizedDelay or normalizedDelay <= 0 then
        return 0
    end

    local count = 0
    for _, widget in ipairs(activeInstances) do
        if widget and widget.phase == phaseKey and widget.startTime then
            widget.startTime = widget.startTime + normalizedDelay
            if widget.UpdateVisual then
                widget.elapsed = math.max(0, GetTime() - widget.startTime)
                widget:UpdateVisual(widget.elapsed)
            end
            count = count + 1
        end
    end
    return count
end

function SegmentedBar:HasActiveEvent(eventID)
    if eventID == nil then
        return false
    end
    local target = tostring(eventID)
    for _, widget in ipairs(activeInstances) do
        if widget and tostring(widget.eventID) == target then
            return true
        end
    end
    return false
end

function SegmentedBar:ShowTest()
    return self:Show({
        duration = 28,
        tickInterval = 3.5,
        spellID = 1246709,
        fallbackLabel = "分段进度条测试",
        eventID = "slash_test",
    })
end

T.ShowBar = function(opts)
    return SegmentedBar:Show(opts)
end

T.ClearAllBars = function()
    SegmentedBar:ClearAll()
end

T.DelayActiveBars = function(phaseKey, delay)
    return SegmentedBar:DelayActive(phaseKey, delay)
end

T.HasActiveBarEvent = function(eventID)
    return SegmentedBar:HasActiveEvent(eventID)
end

T.RegisterUnlockCallback(function()
    EnsureContainer()
    LayoutInstances()
end)

T.RegisterLockCallback(function()
    LayoutInstances()
end)

end)
