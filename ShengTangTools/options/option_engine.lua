local T, C, L = unpack(select(2, ...))

T.OptionDefinitions = T.OptionDefinitions or {}

local OptionEngine = {
    moduleAnchors = {},
    allWidgets = {},
    advancedStates = {},
    searchQuery = "",
}
T.OptionEngine = OptionEngine

local Style = T.Style
local ITEM_GAP = 18
local ROW_GAP = Style.Section.ROW_GAP
local MODULE_GAP = Style.Section.MODULE_BOTTOM_PAD + 16
local CONTENT_PADDING = 12
local HEADER_HEIGHT = 40
local MASTER_TOGGLE_Y_OFFSET = 8

local function ApplyTextureColor(texture, color)
    if texture and color then
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

local function IsDebugMode()
    return C and C.DB and C.DB.debugMode == true
end

local CATEGORY_META = {
    tactic    = { order = 10, textKey = "GUI_NAV_TACTIC" },
    interface = { order = 30, textKey = "GUI_NAV_INTERFACE" },
    raidlead  = { order = 40, textKey = "GUI_NAV_RAIDLEAD" },
    dungeon   = { order = 50, textKey = "GUI_NAV_DUNGEON" },
    utility   = { order = 60, textKey = "GUI_NAV_UTILITY" },
    system    = { order = 70, textKey = "GUI_NAV_SYSTEM" },
    about     = { order = 80, textKey = "GUI_NAV_ABOUT" },
}

local ITEM_HEIGHTS = {
    check = 36,
    slider = 60,
    dropdown = 56,
    editbox = 56,
    button = 36,
    subtitle = 36,
    custom = 72,
}

local function S(value)
    if T.Style and T.Style.Scale then
        return T.Style.Scale(value)
    end
    return tonumber(value) or 0
end

local function ItemGap()
    return S(ITEM_GAP)
end

local function RowGap()
    return S(ROW_GAP)
end

local function ContentPadding()
    return S(CONTENT_PADDING)
end

local function HeaderHeight()
    return S(HEADER_HEIGHT)
end

local function ModuleGap()
    return S(MODULE_GAP)
end

local function MasterToggleYOffset()
    return S(MASTER_TOGGLE_Y_OFFSET)
end

local function ItemHeight(kind)
    return S(ITEM_HEIGHTS[kind or "button"] or ITEM_HEIGHTS.button)
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function ResolveText(textKey, fallback)
    local value = textKey and rawget(L, textKey)
    if value ~= nil then
        return value
    end
    if fallback ~= nil then
        return fallback
    end
    return textKey or ""
end

local function ResolveTooltipPayload(itemDef)
    if type(itemDef) ~= "table" then
        return nil
    end
    if type(itemDef.tooltip) == "table" then
        return itemDef.tooltip
    end
    if itemDef.tooltipKey and T.TooltipPayloads and T.TooltipPayloads.Resolve then
        local payload = T.TooltipPayloads.Resolve(itemDef.tooltipKey)
        if payload then
            return payload
        end
    end
    local tooltipText = ResolveText(itemDef.tooltipKey, itemDef.tooltip)
    if tooltipText and tooltipText ~= "" then
        return { description = tooltipText }
    end
    return nil
end

local function ApplyItemTooltip(widget, itemDef)
    local payload = ResolveTooltipPayload(itemDef)
    if not (widget and payload and T.UITooltip) then
        return
    end
    T.UITooltip.AttachRich(widget, payload)
end

local function ResolvePath(path)
    local parts = {}
    if type(path) ~= "string" or path == "" then
        return parts
    end
    for segment in path:gmatch("[^%.]+") do
        parts[#parts + 1] = segment
    end
    return parts
end

local function ReadPath(root, path)
    local parts = ResolvePath(path)
    local current = root
    for index = 1, #parts do
        if type(current) ~= "table" then
            return nil
        end
        current = current[parts[index]]
    end
    return current
end

local function WritePath(root, path, value)
    local parts = ResolvePath(path)
    if #parts == 0 or type(root) ~= "table" then
        return
    end
    local current = root
    for index = 1, #parts - 1 do
        local key = parts[index]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    current[parts[#parts]] = value
end

local function DisableSlider(row, enabled)
    if not row then
        return
    end
    if row.slider then
        if enabled then
            row.slider:Enable()
        else
            row.slider:Disable()
        end
    end
    if row.label then
        if enabled then
            row.label:SetTextColor(1, 0.86, 0.32, 1)
        else
            row.label:SetTextColor(0.6, 0.6, 0.6, 1)
        end
    end
end

local function ShowSearchHighlight(meta, shown)
    if not meta or not meta.container then
        return
    end

    if not meta.highlight then
        local highlight = CreateFrame("Frame", nil, meta.container, "BackdropTemplate")
        if highlight.SetBackdrop then
            highlight:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            highlight:SetBackdropColor(0.75, 0.58, 0.08, 0.12)
            highlight:SetBackdropBorderColor(0.95, 0.8, 0.25, 0.9)
        end
        highlight:SetPoint("TOPLEFT", meta.container, "TOPLEFT", -4, 4)
        highlight:SetPoint("BOTTOMRIGHT", meta.container, "BOTTOMRIGHT", 4, -4)
        highlight:SetFrameLevel(meta.container:GetFrameLevel() - 1)
        highlight:Hide()
        meta.highlight = highlight
    end

    meta.highlight:SetShown(shown == true)
end

function T.RegisterOptionModule(moduleDef)
    if type(moduleDef) ~= "table" or not moduleDef.id then
        return
    end
    for index, existing in ipairs(T.OptionDefinitions) do
        if existing and existing.id == moduleDef.id then
            T.OptionDefinitions[index] = moduleDef
            return
        end
    end
    T.OptionDefinitions[#T.OptionDefinitions + 1] = moduleDef
end

function T.RegisterOptionStubModule(def)
    if type(def) ~= "table" or type(def.id) ~= "string" then
        return
    end
    T.RegisterOptionModule({
        id = def.id,
        category = def.category or "system",
        order = def.order or 0,
        titleKey = def.titleKey or def.id,
        beta = def.beta == true,
        stubDescKey = def.stubDescKey,
        masterToggle = {
            dbPath = def.dbPath,
            default = def.default == true,
        },
        itemsFactory = function()
            return {}
        end,
    })
end

local OPTION_STUBS = {
    { id = "voice", category = "tactic", order = 10, titleKey = "GUI_NAV_VOICE", dbPath = "ttsEnabled" },
    { id = "countdown", category = "tactic", order = 12, titleKey = "GUI_NAV_COUNTDOWN", dbPath = "CountdownEnabled" },
    { id = "segmented_bar", category = "tactic", order = 13, titleKey = "GUI_NAV_SEGMENTED_BAR", dbPath = "Bar.Enabled", default = true },
    { id = "blizzard_tl", category = "tactic", order = 20, titleKey = "GUI_NAV_BLIZZARD_TL", dbPath = "blizzardTimeline.enabled" },
    { id = "tactical_ui", category = "tactic", order = 30, titleKey = "GUI_NAV_TACTICAL_UI", dbPath = "semanticTimeline.ui.enabled" },
    { id = "realtime", category = "tactic", order = 50, titleKey = "GUI_NAV_REALTIME", dbPath = "realtimeBoard.enabled" },
    { id = "cast_recorder", category = "tactic", order = 55, titleKey = "OPT_CAST_RECORDER_TITLE", dbPath = "castRecorder.backendEnabled" },
    { id = "nameplate", category = "interface", order = 10, titleKey = "GUI_NAV_NAMEPLATE", dbPath = "friendlyNameplate.enabled" },
    { id = "superZoom", category = "interface", order = 25, titleKey = "GUI_NAV_SUPER_ZOOM", dbPath = "superZoom.enabled" },
    { id = "self_marker", category = "interface", order = 30, titleKey = "OPT_SELF_MARKER_TITLE", dbPath = "selfMarker.enabled" },
    { id = "durability_check", category = "interface", order = 35, titleKey = "GUI_NAV_DURABILITY_CHECK", dbPath = "buffCheck.repairReminder.enabled" },
    { id = "screen_remind", category = "interface", order = 40, titleKey = "GUI_NAV_SCREEN_REMIND", dbPath = "screenReminder.enabled", default = true },
    { id = "earlyPull", category = "raidlead", order = 45, titleKey = "GUI_NAV_EARLY_PULL", dbPath = "earlyPull.enabled", beta = true },
    { id = "buff_check", category = "raidlead", order = 46, titleKey = "GUI_NAV_BUFF_CHECK", dbPath = "buffCheck.enabled", beta = true },
    { id = "raid_command_panel", category = "raidlead", order = 47, titleKey = "GUI_NAV_RAID_COMMAND_PANEL", dbPath = "raidCommandPanel.enabled" },
    { id = "roster_planner", category = "raidlead", order = 48, titleKey = "GUI_NAV_ROSTER_PLANNER", dbPath = "rosterPlanner.enabled", beta = true },
    { id = "dreadElegy", category = "dungeon", order = 48, titleKey = "GUI_NAV_DREAD_ELEGY", dbPath = "dreadElegy.enabled" },
    { id = "luraCrystalProgress", category = "dungeon", order = 48.1, titleKey = "GUI_NAV_LURA_CRYSTAL_PROGRESS", dbPath = "luraCrystal.enabled" },
    { id = "luraCrystal", category = "dungeon", order = 48.5, titleKey = "GUI_NAV_LURA_CRYSTAL", dbPath = "luraCrystal.enabled" },
    { id = "auraColor", category = "dungeon", order = 49, titleKey = "GUI_NAV_AURA_COLOR", dbPath = "auraColorAlert.enabled" },
    { id = "interruptRotation", category = "dungeon", order = 49, titleKey = "GUI_NAV_INTERRUPT_ROTATION", dbPath = "interruptRotation.enabled", default = true },
    { id = "tacticTranslator", category = "utility", order = 12, titleKey = "OPTIONS_TACTIC_TRANSLATOR_TITLE", dbPath = "tacticTranslator.enabled" },
    { id = "personalAuraAlert", category = "utility", order = 45, titleKey = "PERSONAL_AURA_ALERT_TITLE", dbPath = "personalAuraAlert.enabled" },
    { id = "autoLogging", category = "utility", order = 46, titleKey = "GUI_NAV_AUTO_LOGGING", dbPath = "autoLogging.enabled" },
    { id = "privateAuraList", category = "utility", order = 90, titleKey = "PRIVATE_AURA_LIST_TITLE", dbPath = "privateAuraList.enabled", beta = true },
    { id = "privateAuraHijack", category = "utility", order = 91, titleKey = "PRIVATE_AURA_HIJACK_TITLE", dbPath = "privateAuraHijack.enabled", beta = true },
}

for _, stub in ipairs(OPTION_STUBS) do
    T.RegisterOptionStubModule(stub)
end

function T.GetOptionModuleItems(moduleDef, engine)
    if type(moduleDef) ~= "table" then
        return {}
    end
    if type(moduleDef.itemsFactory) == "function" then
        local ok, items = pcall(moduleDef.itemsFactory, engine or T.OptionEngine, moduleDef)
        if ok and type(items) == "table" then
            return items
        end
        if T.debug then
            T.debug("[Options] itemsFactory failed module=%s err=%s", tostring(moduleDef.id), tostring(items))
        end
        return {}
    end
    return moduleDef.items or {}
end

function OptionEngine:SetRenderCallback(callback)
    self.onRendered = callback
end

function OptionEngine:Initialize(contentFrame, ownerFrame, scrollFrame)
    if T.NewBadge and not self._newBadgeInited then
        self._newBadgeInited = T.NewBadge.Init(T.Version or "0.0.0") == true
    end
    self.contentFrame = contentFrame
    self.ownerFrame = ownerFrame
    self.scrollFrame = scrollFrame
end

function OptionEngine:CancelRenderRelease()
    self.releaseSerial = (self.releaseSerial or 0) + 1
end

function OptionEngine:ReleaseRenderTree(reason)
    self:CancelRenderRelease()
    self.allWidgets = {}
    self.moduleAnchors = {}
    if self.renderRoot then
        self.renderRoot:Hide()
        self.renderRoot:SetParent(nil)
        self.renderRoot = nil
    end
    if self.scrollFrame and self.scrollFrame.SetContentHeight then
        self.scrollFrame:SetContentHeight(1)
    end
    if self.contentFrame then
        self.contentFrame:SetSize(1, 1)
    end
    if T.debug then
        T.debug("[Options] ReleaseRenderTree reason=%s", tostring(reason or "idle"))
    end
    pcall(collectgarbage, "collect")
end

function OptionEngine:ScheduleRenderRelease(delaySec)
    self.releaseSerial = (self.releaseSerial or 0) + 1
    local serial = self.releaseSerial
    local delay = tonumber(delaySec) or 60
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            if serial == self.releaseSerial then
                self:ReleaseRenderTree("idle")
            end
        end)
        return
    end
    self:ReleaseRenderTree("no_timer")
end

function OptionEngine:ResolveText(textKey, fallback)
    return ResolveText(textKey, fallback)
end

function OptionEngine:GetValue(path, defaultValue)
    if type(path) ~= "string" or path == "" then
        return defaultValue
    end
    local value = ReadPath(C.DB, path)
    if value == nil then
        return defaultValue
    end
    return value
end

function OptionEngine:SetValue(path, value)
    if type(path) ~= "string" or path == "" then
        return
    end
    WritePath(C.DB, path, value)
    if type(STT_DB) == "table" then
        WritePath(STT_DB, path, value)
    end
end

function OptionEngine:GetDefinitions()
    local list = {}
    local debugOn = IsDebugMode()
    for _, moduleDef in ipairs(T.OptionDefinitions or {}) do
        local visible = true
        if type(moduleDef.visible) == "function" then
            visible = moduleDef.visible(self) ~= false
        elseif moduleDef.visible ~= nil then
            visible = moduleDef.visible ~= false
        end
        if visible and moduleDef.beta == true and not debugOn then
            visible = false
        end
        if visible then
            local categoryMeta = CATEGORY_META[moduleDef.category or "system"]
            if categoryMeta and categoryMeta.beta == true and not debugOn then
                visible = false
            end
        end
        if visible then
            list[#list + 1] = moduleDef
        end
    end
    table.sort(list, function(a, b)
        local aMeta = CATEGORY_META[a.category or "system"] or CATEGORY_META.system
        local bMeta = CATEGORY_META[b.category or "system"] or CATEGORY_META.system
        if aMeta.order ~= bMeta.order then
            return aMeta.order < bMeta.order
        end
        if (a.order or 0) ~= (b.order or 0) then
            return (a.order or 0) < (b.order or 0)
        end
        return ResolveText(a.titleKey, a.id) < ResolveText(b.titleKey, b.id)
    end)
    return list
end

function OptionEngine:GetCategoryTree()
    local grouped = {}
    local ordered = {}
    for _, moduleDef in ipairs(self:GetDefinitions()) do
        local categoryId = moduleDef.category or "system"
        local meta = CATEGORY_META[categoryId] or CATEGORY_META.system
        if not grouped[categoryId] then
            grouped[categoryId] = {
                id = categoryId,
                textKey = meta.textKey,
                beta = meta.beta == true,
                hasNew = false,
                children = {},
            }
            ordered[#ordered + 1] = grouped[categoryId]
        end
        local moduleNew = T.NewBadge and T.NewBadge:IsModuleNew(moduleDef) or false
        grouped[categoryId].children[#grouped[categoryId].children + 1] = {
            id = moduleDef.id,
            textKey = moduleDef.titleKey,
            beta = moduleDef.beta == true,
            hasNew = moduleNew,
        }
        if moduleNew then
            grouped[categoryId].hasNew = true
        end
    end

    table.sort(ordered, function(a, b)
        local aOrder = (CATEGORY_META[a.id] or CATEGORY_META.system).order
        local bOrder = (CATEGORY_META[b.id] or CATEGORY_META.system).order
        return aOrder < bOrder
    end)
    return ordered
end

function OptionEngine:GetModuleById(moduleId)
    for _, moduleDef in ipairs(T.OptionDefinitions or {}) do
        if moduleDef.id == moduleId then
            return moduleDef
        end
    end
    return nil
end

function OptionEngine:GetItemValue(itemDef)
    if type(itemDef.getter) == "function" then
        return itemDef.getter(self, itemDef)
    end
    if itemDef.dbPath then
        return self:GetValue(itemDef.dbPath, itemDef.default)
    end
    return itemDef.default
end

function OptionEngine:SetItemValue(itemDef, value)
    if type(itemDef.setter) == "function" then
        itemDef.setter(value, self, itemDef)
        return
    end
    if itemDef.dbPath then
        self:SetValue(itemDef.dbPath, value)
    end
end

function OptionEngine:ApplyItem(itemDef, value, moduleDef)
    self:SetItemValue(itemDef, value)
    if type(itemDef.apply) == "function" then
        itemDef.apply(value, self, itemDef, moduleDef)
    end
    self:RefreshWidgetValues()
    self:RefreshDependStates()
end

function OptionEngine:GetAdvancedState(moduleId)
    if self.advancedStates[moduleId] == nil then
        self.advancedStates[moduleId] = false
    end
    return self.advancedStates[moduleId]
end

function OptionEngine:SetAdvancedState(moduleId, state)
    self.advancedStates[moduleId] = state == true
    T.debug(string.format(
        "[Options] AdvancedSectionToggle module=%s expanded=%s",
        tostring(moduleId),
        tostring(self.advancedStates[moduleId])
    ))
    self:Rebuild()
end

function OptionEngine:ToggleAdvanced(moduleId)
    self:SetAdvancedState(moduleId, not self:GetAdvancedState(moduleId))
end

function OptionEngine:ResolveDependPath(moduleDef, itemDef)
    local depend = itemDef and itemDef.depend
    if type(depend) ~= "table" then
        return nil
    end
    if depend.dbPath then
        return depend.dbPath
    end
    if depend.key then
        for _, candidate in ipairs(T.GetOptionModuleItems(moduleDef, self)) do
            if candidate.key == depend.key then
                return candidate.dbPath
            end
        end
    end
    return nil
end

function OptionEngine:IsModuleEnabled(moduleDef)
    if not moduleDef or not moduleDef.masterToggle or not moduleDef.masterToggle.dbPath then
        return true
    end
    return self:GetValue(moduleDef.masterToggle.dbPath, moduleDef.masterToggle.default) ~= false
end

function OptionEngine:GetRuntimeModule(moduleDef)
    if not (moduleDef and moduleDef.masterToggle and moduleDef.masterToggle.dbPath and T.ModuleLoader) then
        return nil
    end
    return T.ModuleLoader:GetByDbKey(moduleDef.masterToggle.dbPath)
end

function OptionEngine:ShouldRenderStub(moduleDef)
    local module = self:GetRuntimeModule(moduleDef)
    if not module then
        return false
    end
    return not (module.enabled == true and module.pendingReload ~= true)
end

local function GetRuntimeStatusText(module)
    if not module then
        return ResolveText("MODULE_STATUS_UNREGISTERED", "未接入")
    end
    if module.pendingReload == true and T.ModuleLoader and T.ModuleLoader:IsDbEnabled(module) then
        return ResolveText("MODULE_STATUS_PENDING_LOAD", "待加载")
    end
    if module.pendingReload == true then
        return ResolveText("MODULE_STATUS_PENDING_UNLOAD", "待卸载")
    end
    if module.enabled == true then
        return ResolveText("MODULE_STATUS_LOADED", "已加载")
    end
    if module.firstLoaded == true then
        return ResolveText("MODULE_STATUS_SOFT_DISABLED", "已软停")
    end
    if T.ModuleLoader and T.ModuleLoader:IsDbEnabled(module) then
        return ResolveText("MODULE_STATUS_PENDING_LOAD", "待加载")
    end
    return ResolveText("MODULE_STATUS_COLD", "未加载")
end

function OptionEngine:RenderModuleStub(parent, moduleDef, module, startY, availWidth)
    local desired = T.ModuleLoader and T.ModuleLoader:IsDbEnabled(module) == true
    local statusText = GetRuntimeStatusText(module)
    local desc
    if module.pendingReload == true and desired then
        desc = ResolveText("MODULE_STUB_DESC_PENDING_LOAD", "已写入配置：启用。为了保持 STT 启动壳子最小化，该模块不会在当前会话热加载；/reload 后才会创建运行体、事件监听与完整设置页。")
    elseif module.pendingReload == true then
        desc = ResolveText("MODULE_STUB_DESC_PENDING_UNLOAD", "已写入配置：禁用。当前会话已停止可停止的事件、定时器与 UI 引用；/reload 后彻底卸载运行体。")
    elseif desired then
        desc = ResolveText("MODULE_STUB_DESC_ENABLED_NOT_LOADED", "该模块已启用，但当前会话尚未加载完整运行体；/reload 后加载完整功能与设置。")
    else
        desc = ResolveText("MODULE_STUB_DESC_COLD", "该模块当前未加载运行体，不会创建 Frame、注册事件或构建完整设置页；启用后需要 /reload 才会加载。")
    end
    if moduleDef.stubDescKey then
        desc = ResolveText(moduleDef.stubDescKey, desc) .. "\n\n" .. desc
    end

    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", 0, startY },
        width = availWidth,
        size = 13,
        color = { 0.85, 0.9, 1, 1 },
        text = string.format(ResolveText("MODULE_STATUS_PREFIX", "状态：%s"), statusText),
    })
    T.CreateLabel(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", 0, startY - S(24) },
        width = availWidth,
        size = 12,
        color = { 0.78, 0.78, 0.78, 1 },
        wordWrap = true,
        text = desc,
    })
    T.CreateActionButton(parent, {
        width = S(132),
        height = S(26),
        point = { "TOPLEFT", parent, "TOPLEFT", 0, startY - S(78) },
        textFn = function()
            return ResolveText("MODULE_RELOAD_NOW", "立即 /reload")
        end,
        onClick = function()
            ReloadUI()
        end,
    })
    return startY - S(moduleDef.stubDescKey and 148 or 120)
end

function OptionEngine:IsItemEnabled(moduleDef, itemDef)
    if itemDef and itemDef.key == "__master_toggle" then
        return true
    end
    if not self:IsModuleEnabled(moduleDef) and not (itemDef and itemDef.ignoreModuleDisabled == true) then
        return false
    end
    local dependPath = self:ResolveDependPath(moduleDef, itemDef)
    if not dependPath then
        return true
    end
    local depend = itemDef.depend
    local currentValue = self:GetValue(dependPath)
    if depend.notValue ~= nil then
        return currentValue ~= depend.notValue
    end
    if depend.values then
        for _, allowed in ipairs(depend.values) do
            if currentValue == allowed then
                return true
            end
        end
        return false
    end
    if depend.value ~= nil then
        return currentValue == depend.value
    end
    return currentValue ~= nil and currentValue ~= false
end

function OptionEngine:IsItemVisible(moduleDef, itemDef)
    if not itemDef then
        return true
    end
    if itemDef.beta == true and not IsDebugMode() then
        return false
    end
    if type(itemDef.visible) == "function" then
        return itemDef.visible(self, itemDef, moduleDef) ~= false
    end
    if itemDef.visible ~= nil then
        return itemDef.visible ~= false
    end
    return true
end

function OptionEngine:TrackWidget(meta)
    self.allWidgets[#self.allWidgets + 1] = meta
    return meta
end

function OptionEngine:AttachNewBadgeIfNeeded(meta)
    if not (T.NewBadge and meta and meta.container) then
        return
    end
    if not T.NewBadge:IsItemNew(meta.moduleDef, meta.itemDef) then
        return
    end

    local badge = T.NewBadge:CreateBadge(meta.container, {
        anchor = "TOPRIGHT",
        offsetX = -2,
        offsetY = 4,
        width = 26,
        height = 17,
    })
    if badge then
        badge:Show()
        meta.newBadge = badge
    end
end

function OptionEngine:RefreshWidgetValue(meta)
    if not meta then
        return
    end
    if meta.kind == "custom" and type(meta.refresh) == "function" then
        meta.refresh()
        return
    end
    if meta.control and type(meta.control.Refresh) == "function" then
        meta.control:Refresh()
    end
end

function OptionEngine:RefreshWidgetValues()
    for _, meta in ipairs(self.allWidgets or {}) do
        self:RefreshWidgetValue(meta)
    end
end

function OptionEngine:SetWidgetEnabled(meta, enabled)
    if not meta or not meta.container then
        return
    end

    meta.container:SetAlpha(enabled and 1 or 0.45)
    if meta.kind == "checkbox" then
        if enabled then
            meta.control:Enable()
        else
            meta.control:Disable()
        end
        if meta.control.label then
            if enabled then
                meta.control.label:SetTextColor(1, 1, 1, 1)
            else
                meta.control.label:SetTextColor(0.6, 0.6, 0.6, 1)
            end
        end
    elseif meta.kind == "dropdown" then
        meta.control:SetSelectorEnabled(enabled)
        if meta.control.labelText then
            if enabled then
                meta.control.labelText:SetTextColor(1, 1, 1, 1)
            else
                meta.control.labelText:SetTextColor(0.6, 0.6, 0.6, 1)
            end
        end
    elseif meta.kind == "editbox" then
        if enabled then
            meta.control:Enable()
        else
            meta.control:Disable()
        end
        if meta.label then
            if enabled then
                meta.label:SetTextColor(1, 0.86, 0.32, 1)
            else
                meta.label:SetTextColor(0.6, 0.6, 0.6, 1)
            end
        end
    elseif meta.kind == "slider" then
        DisableSlider(meta.control, enabled)
    elseif meta.kind == "button" then
        if enabled then
            meta.control:Enable()
        else
            meta.control:Disable()
        end
    elseif meta.kind == "custom" then
        if type(meta.setEnabled) == "function" then
            meta.setEnabled(enabled)
        end
    end
end

function OptionEngine:RefreshDependStates()
    for _, meta in ipairs(self.allWidgets or {}) do
        local enabled = self:IsItemEnabled(meta.moduleDef, meta.itemDef)
        self:SetWidgetEnabled(meta, enabled)
    end
end

function OptionEngine:GetItemSearchText(moduleDef, itemDef)
    local parts = {
        ResolveText(moduleDef.titleKey, moduleDef.id),
    }

    if itemDef.sectionKey then
        parts[#parts + 1] = ResolveText(itemDef.sectionKey, itemDef.sectionKey)
    end
    if itemDef.textKey or itemDef.text then
        parts[#parts + 1] = ResolveText(itemDef.textKey, itemDef.text)
    end
    if itemDef.searchText then
        parts[#parts + 1] = itemDef.searchText
    end
    return table.concat(parts, " "):lower()
end

function OptionEngine:ClearHighlights()
    for _, meta in ipairs(self.allWidgets or {}) do
        ShowSearchHighlight(meta, false)
    end
end

function OptionEngine:SetSearchQuery(query)
    self.searchQuery = tostring(query or "")
    self:ClearHighlights()

    local needle = self.searchQuery:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if needle == "" then
        return
    end

    local firstMatch
    for _, meta in ipairs(self.allWidgets or {}) do
        if meta.searchText and meta.searchText:find(needle, 1, true) then
            ShowSearchHighlight(meta, true)
            firstMatch = firstMatch or meta
        end
    end

    if firstMatch and self.scrollFrame and self.moduleAnchors[firstMatch.moduleId] then
        self.scrollFrame:ScrollTo(self.moduleAnchors[firstMatch.moduleId])
    end
end

function OptionEngine:GetActiveModuleForOffset(offset)
    local active
    local activeOffset = -1
    for moduleId, anchor in pairs(self.moduleAnchors or {}) do
        if anchor <= offset + S(24) and anchor >= activeOffset then
            active = moduleId
            activeOffset = anchor
        end
    end
    if active then
        return active
    end

    local firstId
    local firstOffset
    for moduleId, anchor in pairs(self.moduleAnchors or {}) do
        if not firstOffset or anchor < firstOffset then
            firstId = moduleId
            firstOffset = anchor
        end
    end
    return firstId
end

function OptionEngine:CreateSlot(parent, x, y, width, height)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slot:SetSize(width, height)
    return slot
end

function OptionEngine:BuildSelectorItems(itemDef)
    local options = itemDef.options
    if type(options) == "function" then
        options = options(self, itemDef)
    end
    local items = {}
    for _, option in ipairs(options or {}) do
        items[#items + 1] = {
            text = ResolveText(option.textKey, option.text or tostring(option.value)),
            value = option.value,
            disabled = option.disabled == true,
            items = option.items,
            isTitle = option.isTitle == true,
        }
    end
    return items
end

function OptionEngine:RenderCheck(parent, moduleDef, itemDef, x, y, width)
    local slot = self:CreateSlot(parent, x, y, width, ItemHeight("check"))
    local checkbox = T.CreateCheckbox(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", S(4), -S(8) },
        label = ResolveText(itemDef.textKey, itemDef.text or itemDef.key),
        clickLabel = itemDef.clickLabel == true,
        getter = function()
            local value = self:GetItemValue(itemDef)
            if itemDef.invert then
                return not value
            end
            return value == true
        end,
        setter = function(value)
            if IsShiftKeyDown and IsShiftKeyDown() and T.OptionShare then
                T.OptionShare:OnShiftClick(itemDef, moduleDef)
                self:RefreshWidgetValues()
                return
            end
            local finalValue = itemDef.invert and (not value) or value
            self:ApplyItem(itemDef, finalValue, moduleDef)
        end,
    })
    ApplyItemTooltip(checkbox, itemDef)
    if T.OptionShare then
        T.OptionShare:AttachShiftTooltip(checkbox, itemDef, moduleDef)
    end

    local meta = self:TrackWidget({
        kind = "checkbox",
        container = slot,
        control = checkbox,
        moduleId = moduleDef.id,
        moduleDef = moduleDef,
        itemDef = itemDef,
        searchText = self:GetItemSearchText(moduleDef, itemDef),
    })
    self:AttachNewBadgeIfNeeded(meta)
    return meta
end

function OptionEngine:RenderSlider(parent, moduleDef, itemDef, x, y, width)
    local slot = self:CreateSlot(parent, x, y, width, ItemHeight("slider"))
    local row
    row = T.CreateSliderRow(slot, {
        y = -S(2),
        label = ResolveText(itemDef.textKey, itemDef.text or itemDef.key),
        min = itemDef.min,
        max = itemDef.max,
        step = itemDef.step,
        getter = function()
            return self:GetItemValue(itemDef)
        end,
        setter = function(value)
            if IsShiftKeyDown and IsShiftKeyDown() and T.OptionShare then
                if row and not row.__sttOptionPushSent then
                    T.OptionShare:OnShiftClick(itemDef, moduleDef)
                    row.__sttOptionPushSent = true
                end
                if row and row.Refresh then
                    row.Refresh()
                end
                return
            end
            self:SetItemValue(itemDef, value)
        end,
        onApply = function()
            local value = self:GetItemValue(itemDef)
            if type(itemDef.apply) == "function" then
                itemDef.apply(value, self, itemDef, moduleDef)
            end
            self:RefreshDependStates()
        end,
        formatter = function(value)
            if type(itemDef.formatFunc) == "function" then
                return itemDef.formatFunc(value, self, itemDef)
            end
            return tostring(value)
        end,
    })
    row.slider:SetWidth(math.max(S(180), width - S(16)))
    row.Refresh()
    ApplyItemTooltip(row.slider, itemDef)
    if row.slider then
        row.slider:HookScript("OnMouseDown", function()
            if IsShiftKeyDown and IsShiftKeyDown() and T.OptionShare then
                T.OptionShare:OnShiftClick(itemDef, moduleDef)
                row.__sttOptionPushSent = true
                row.Refresh()
            end
        end)
        row.slider:HookScript("OnMouseUp", function()
            row.__sttOptionPushSent = nil
            row.Refresh()
        end)
        if T.OptionShare then
            T.OptionShare:AttachShiftTooltip(row.slider, itemDef, moduleDef)
        end
    end

    local meta = self:TrackWidget({
        kind = "slider",
        container = slot,
        control = row,
        moduleId = moduleDef.id,
        moduleDef = moduleDef,
        itemDef = itemDef,
        searchText = self:GetItemSearchText(moduleDef, itemDef),
    })
    self:AttachNewBadgeIfNeeded(meta)
    return meta
end

function OptionEngine:RenderDropdown(parent, moduleDef, itemDef, x, y, width)
    local slot = self:CreateSlot(parent, x, y, width, ItemHeight("dropdown"))
    local function refreshItems(button)
        local items = self:BuildSelectorItems(itemDef)
        button:SetItems(items)
        button:SetSelectedValue(self:GetItemValue(itemDef), ResolveText(itemDef.emptyTextKey, itemDef.emptyText))
        button:SetLabel((ResolveText(itemDef.textKey, itemDef.text or itemDef.key) or "") .. ":")
    end

    local button = T.CreateSelectorButton(slot, {
        width = math.max(S(140), width - S(8)),
        height = T.Style and T.Style.BASE and T.Style.BASE.DROPDOWN_HEIGHT or 26,
        point = { "TOPLEFT", slot, "TOPLEFT", S(4), -S(10) },
        ownerFrame = self.ownerFrame or UIParent,
        label = (ResolveText(itemDef.textKey, itemDef.text or itemDef.key) or "") .. ":",
        labelWidth = itemDef.labelWidth or 88,
        emptyText = ResolveText(itemDef.emptyTextKey, itemDef.emptyText),
    })
    button.onSelect = function(value)
        self:ApplyItem(itemDef, value, moduleDef)
        refreshItems(button)
    end
    refreshItems(button)
    ApplyItemTooltip(button, itemDef)
    local originalOnClick = button:GetScript("OnClick")
    button:SetScript("OnClick", function(owner, ...)
        if IsShiftKeyDown and IsShiftKeyDown() and T.OptionShare then
            T.OptionShare:OnShiftClick(itemDef, moduleDef)
            refreshItems(button)
            return
        end
        if originalOnClick then
            originalOnClick(owner, ...)
        end
    end)
    if T.OptionShare then
        T.OptionShare:AttachShiftTooltip(button, itemDef, moduleDef)
    end

    local meta = self:TrackWidget({
        kind = "dropdown",
        container = slot,
        control = button,
        moduleId = moduleDef.id,
        moduleDef = moduleDef,
        itemDef = itemDef,
        searchText = self:GetItemSearchText(moduleDef, itemDef),
    })
    self:AttachNewBadgeIfNeeded(meta)
    return meta
end

function OptionEngine:RenderEditBox(parent, moduleDef, itemDef, x, y, width)
    local slot = self:CreateSlot(parent, x, y, width, ItemHeight("editbox"))
    local label = T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", S(4), -S(2) },
        text = ResolveText(itemDef.textKey, itemDef.text or itemDef.key),
        size = 12,
    })

    local editBox = T.CreateEditBox(slot, {
        width = math.max(S(160), width - S(8)),
        height = S(26),
        point = { "TOPLEFT", slot, "TOPLEFT", S(4), -S(24) },
        placeholder = ResolveText(itemDef.placeholderTextKey, itemDef.placeholderText),
        maxLetters = itemDef.maxLetters,
    })

    local function refresh()
        if editBox:HasFocus() then
            return
        end
        local value = self:GetItemValue(itemDef)
        value = value == nil and "" or tostring(value)
        if editBox:GetText() ~= value then
            editBox:SetText(value)
            editBox:SetCursorPosition(0)
            editBox:HighlightText(0, 0)
        end
    end

    local function commit()
        if editBox.__sttApplying then
            return
        end
        local rawValue = editBox:GetText() or ""
        editBox.__sttApplying = true
        self:ApplyItem(itemDef, rawValue, moduleDef)
        editBox.__sttApplying = false
        if T.debug then
            T.debug(string.format(
                "[Options] EditBoxCommit module=%s key=%s value=%s",
                tostring(moduleDef and moduleDef.id or ""),
                tostring(itemDef and itemDef.key or ""),
                tostring(rawValue)
            ))
        end
        refresh()
    end

    editBox:SetScript("OnEnterPressed", function(self)
        commit()
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        refresh()
    end)
    editBox:SetScript("OnEditFocusLost", function()
        commit()
    end)
    refresh()
    ApplyItemTooltip(editBox, itemDef)

    local meta = self:TrackWidget({
        kind = "editbox",
        container = slot,
        control = editBox,
        label = label,
        moduleId = moduleDef.id,
        moduleDef = moduleDef,
        itemDef = itemDef,
        searchText = self:GetItemSearchText(moduleDef, itemDef),
    })
    self:AttachNewBadgeIfNeeded(meta)
    return meta
end

function OptionEngine:RenderButton(parent, moduleDef, itemDef, x, y, width)
    local slot = self:CreateSlot(parent, x, y, width, ItemHeight("button"))
    local button = T.CreateActionButton(slot, {
        width = math.max(S(120), width - S(8)),
        height = T.Style and T.Style.BASE and T.Style.BASE.BUTTON_HEIGHT or 26,
        point = { "TOPLEFT", slot, "TOPLEFT", S(4), -S(10) },
        textFn = function()
            if type(itemDef.displayFunc) == "function" then
                return itemDef.displayFunc(self:GetItemValue(itemDef), self, itemDef, moduleDef)
            end
            return ResolveText(itemDef.textKey, itemDef.text or itemDef.key)
        end,
        onClick = function()
            if type(itemDef.onClick) == "function" then
                itemDef.onClick(self, itemDef, moduleDef)
            end
        end,
    })
    button:Refresh()
    ApplyItemTooltip(button, itemDef)

    local meta = self:TrackWidget({
        kind = "button",
        container = slot,
        control = button,
        moduleId = moduleDef.id,
        moduleDef = moduleDef,
        itemDef = itemDef,
        searchText = self:GetItemSearchText(moduleDef, itemDef),
    })
    self:AttachNewBadgeIfNeeded(meta)
    return meta
end

function OptionEngine:RenderSubtitle(parent, itemDef, y, width)
    local bar = parent:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - S(2))
    bar:SetSize(S(Style.Section.SUBGROUP_LEFT_BAR_WIDTH), S(16))
    ApplyTextureColor(bar, Style.Color.SUBGROUP_BAR)

    local title = T.CreateGroupTitle(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", S(8), y },
        text = ResolveText(itemDef.textKey, itemDef.text),
        fontSize = Style.Section.SUBGROUP_FONT_SIZE,
        template = Style.Font.SUBGROUP,
        color = Style.Color.KYRIAN_GOLD,
    })
    T.CreateSeparator(parent, {
        point = { "TOPLEFT", title, "BOTTOMLEFT", 0, -S(4) },
        width = math.max(1, width - S(8)),
        color = Style.Color.SECTION_LINE,
    })
end

function OptionEngine:RenderCustom(parent, moduleDef, itemDef, x, y, width)
    local slot = self:CreateSlot(parent, x, y, width, 1)
    local customMeta = {
        kind = "custom",
        container = slot,
        control = slot,
        moduleId = moduleDef.id,
        moduleDef = moduleDef,
        itemDef = itemDef,
        searchText = self:GetItemSearchText(moduleDef, itemDef),
    }
    local result = nil
    if type(itemDef.render) == "function" then
        result = itemDef.render(slot, {
            engine = self,
            moduleDef = moduleDef,
            itemDef = itemDef,
            width = width,
        })
    end
    if type(result) == "table" then
        slot:SetHeight(tonumber(result.height) or ItemHeight("custom"))
        customMeta.setEnabled = result.setEnabled
        customMeta.refresh = result.refresh
    else
        slot:SetHeight(tonumber(result) or ItemHeight("custom"))
    end
    return self:TrackWidget(customMeta)
end

function OptionEngine:GetItemHeight(itemDef)
    if itemDef.type == "custom" and itemDef.height then
        return S(itemDef.height)
    end
    return ItemHeight(itemDef.type or "button")
end

function OptionEngine:RenderItem(parent, moduleDef, itemDef, x, y, width)
    if itemDef.type == "check" then
        return self:RenderCheck(parent, moduleDef, itemDef, x, y, width)
    elseif itemDef.type == "slider" then
        return self:RenderSlider(parent, moduleDef, itemDef, x, y, width)
    elseif itemDef.type == "dropdown" then
        return self:RenderDropdown(parent, moduleDef, itemDef, x, y, width)
    elseif itemDef.type == "editbox" then
        return self:RenderEditBox(parent, moduleDef, itemDef, x, y, width)
    elseif itemDef.type == "button" then
        return self:RenderButton(parent, moduleDef, itemDef, x, y, width)
    elseif itemDef.type == "custom" then
        return self:RenderCustom(parent, moduleDef, itemDef, x, y, width)
    end
    return nil
end

function OptionEngine:RenderItems(parent, moduleDef, items, startY, availWidth)
    local currentY = startY
    local cursorX = 0
    local rowHeight = 0
    local rowHasItems = false

    local function flushRow()
        if rowHasItems then
            currentY = currentY - rowHeight - RowGap()
            cursorX = 0
            rowHeight = 0
            rowHasItems = false
        end
    end

    for _, itemDef in ipairs(items or {}) do
        if not self:IsItemVisible(moduleDef, itemDef) then
            -- 上下文专属设置从布局中移除，避免只置灰仍占位置。
        elseif itemDef.type == "subtitle" then
            flushRow()
            self:RenderSubtitle(parent, itemDef, currentY, availWidth)
            currentY = currentY - ItemHeight("subtitle")
        else
            local widthFactor = Clamp(itemDef.width or 1, 0.2, 1)
            local itemHeight = self:GetItemHeight(itemDef)
            local itemWidth = widthFactor >= 0.999 and availWidth or math.floor((availWidth - ItemGap()) * widthFactor)

            if itemDef.type == "custom" then
                flushRow()
                local meta = self:RenderItem(parent, moduleDef, itemDef, 0, currentY, availWidth)
                currentY = currentY - ((meta and meta.container and meta.container:GetHeight()) or itemHeight) - RowGap()
            else
                if rowHasItems and cursorX + itemWidth > availWidth then
                    flushRow()
                end
                self:RenderItem(parent, moduleDef, itemDef, cursorX, currentY, itemWidth)
                cursorX = cursorX + itemWidth + ItemGap()
                rowHeight = math.max(rowHeight, itemHeight)
                rowHasItems = true
            end
        end
    end

    flushRow()
    return currentY
end

function OptionEngine:RenderModule(moduleDef, parent, startY, availWidth)
    self.moduleAnchors[moduleDef.id] = math.max(0, -startY - ContentPadding())

    local titleBar = parent:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, startY - S(2))
    titleBar:SetSize(S(3), S(18))
    ApplyTextureColor(titleBar, Style.Color.KYRIAN_GOLD)

    local title = T.CreateGroupTitle(parent, {
        point = { "TOPLEFT", parent, "TOPLEFT", S(10), startY },
        text = ResolveText(moduleDef.titleKey, moduleDef.id),
        fontSize = Style.Section.MODULE_TITLE_FONT_SIZE,
        template = Style.Font.SECTION_TITLE,
        color = Style.Color.KYRIAN_GOLD,
    })
    T.CreateSeparator(parent, {
        point = { "TOPLEFT", title, "BOTTOMLEFT", 0, -S(7) },
        width = math.max(1, availWidth - S(10)),
        color = Style.Color.SECTION_LINE,
    })

    if moduleDef.masterToggle and moduleDef.masterToggle.dbPath then
        local originalApply = moduleDef.masterToggle.apply
        local toggleItem = {
            key = "__master_toggle",
            type = "check",
            text = ResolveText("GUI_LABEL_ENABLED", "启用"),
            dbPath = moduleDef.masterToggle.dbPath,
            default = moduleDef.masterToggle.default,
            apply = function(value, engine, itemDef, ownerModuleDef)
                local runtimeModule = self:GetRuntimeModule(moduleDef)
                if runtimeModule and T.ModuleLoader then
                    T.ModuleLoader:SetDesired(runtimeModule.name, value == true, "option")
                    self:Rebuild()
                    return
                end
                if type(originalApply) == "function" then
                    originalApply(value, engine, itemDef, ownerModuleDef)
                end
            end,
        }
        -- 主开关与标题首行对齐，避免压到标题下方分割线。
        self:RenderCheck(parent, moduleDef, toggleItem, availWidth - S(96), startY + MasterToggleYOffset(), S(96))
    end

    local runtimeModule = self:GetRuntimeModule(moduleDef)
    if runtimeModule and self:ShouldRenderStub(moduleDef) then
        local stubEndY = self:RenderModuleStub(parent, moduleDef, runtimeModule, startY - HeaderHeight(), availWidth)
        return stubEndY - ModuleGap()
    end

    local basicItems = {}
    local advancedItems = {}
    local moduleItems = T.GetOptionModuleItems(moduleDef, self)
    for _, itemDef in ipairs(moduleItems) do
        if itemDef.advanced then
            advancedItems[#advancedItems + 1] = itemDef
        else
            basicItems[#basicItems + 1] = itemDef
        end
    end

    local currentY = startY - HeaderHeight()
    currentY = self:RenderItems(parent, moduleDef, basicItems, currentY, availWidth)

    if #advancedItems > 0 then
        local advancedSection = T.CreateCollapsibleSection(parent, {
                width = availWidth,
            point = { "TOPLEFT", parent, "TOPLEFT", 0, currentY },
            label = function()
                if moduleDef.advancedTitle then
                    return moduleDef.advancedTitle
                end
                if moduleDef.advancedTitleKey then
                    return ResolveText(moduleDef.advancedTitleKey, moduleDef.advancedTitleKey)
                end
                return ResolveText("GUI_ADVANCED_SETTINGS", "高级设置")
            end,
            getExpanded = function()
                return self:GetAdvancedState(moduleDef.id)
            end,
            setExpanded = function(state)
                self.advancedStates[moduleDef.id] = state == true
            end,
            backdrop = {
                alpha = 0.16,
                style = "chat",
                borderColor = { 0.62, 0.52, 0.2, 0.55 },
            },
            padding = { left = S(12), top = S(12), right = S(12), bottom = S(10) },
            renderContent = function(content)
                local innerWidth = math.max(1, content:GetWidth() or (availWidth - S(24)))
                local innerEndY = self:RenderItems(content, moduleDef, advancedItems, -S(2), innerWidth)
                return math.abs(innerEndY) + S(10)
            end,
            onToggle = function(expanded)
                self:SetAdvancedState(moduleDef.id, expanded)
            end,
        })
        currentY = currentY - advancedSection:GetHeight() - S(16)
    end

    return currentY - ModuleGap()
end

function OptionEngine:RenderAll(contentFrame, availWidth)
    self:CancelRenderRelease()
    self.allWidgets = {}
    self.moduleAnchors = {}
    self.availableWidth = availWidth

    if self.renderRoot then
        self.renderRoot:Hide()
        self.renderRoot:SetParent(nil)
        self.renderRoot = nil
    end

    local root = CreateFrame("Frame", nil, contentFrame)
    root:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", ContentPadding(), -ContentPadding())
    root:SetWidth(availWidth)
    self.renderRoot = root

    local currentY = -ContentPadding()
    for _, moduleDef in ipairs(self:GetDefinitions()) do
        -- 外层 pcall 保护：单个 module 崩溃不能拖垮整个设置页
        local ok, resultOrErr = xpcall(function()
            return self:RenderModule(moduleDef, root, currentY, availWidth)
        end, function(err)
            return tostring(err) .. "\n" .. (debugstack and debugstack(2, 10, 10) or "")
        end)
        if ok then
            currentY = resultOrErr
        else
            if T.msg then
                T.msg(string.format("|cffff5555[Options] 模块 %s 渲染失败:|r %s",
                    tostring(moduleDef and moduleDef.id or "?"), tostring(resultOrErr)))
            end
            if T.debug then
                T.debug("[Options] RenderModule failed module=%s err=%s",
                    tostring(moduleDef and moduleDef.id or "?"), tostring(resultOrErr))
            end
            -- 让出一点垂直空间留白，继续渲染后续 module
            currentY = currentY - 20
        end
    end

    local totalHeight = math.max(1, math.abs(currentY) + ContentPadding())
    root:SetHeight(totalHeight)
    contentFrame:SetSize(availWidth + ContentPadding() * 2, totalHeight)
    if self.scrollFrame and self.scrollFrame.SetContentHeight then
        self.scrollFrame:SetContentHeight(totalHeight + ContentPadding() * 2)
    end

    self:RefreshDependStates()
    if type(self.onRendered) == "function" then
        self.onRendered(self:GetCategoryTree(), self.moduleAnchors)
    end
    if self.searchQuery and self.searchQuery ~= "" then
        self:SetSearchQuery(self.searchQuery)
    end
end

function OptionEngine:Rebuild()
    if not self.contentFrame or not self.availableWidth then
        return
    end
    self:RenderAll(self.contentFrame, self.availableWidth)
end

function OptionEngine:RefreshAllTexts()
    self:Rebuild()
end
