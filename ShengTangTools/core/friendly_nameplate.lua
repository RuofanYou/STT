-- 友方姓名版优化模块
-- 功能：去除服务器名后缀 + 只显示名字（隐藏血条）+ 职业颜色 + 友方玩家名字字体增强

local T, C, L = unpack(select(2, ...))

local FNP = {
    isRuntimeApplied = false,
    ui = nil,
    originalCVars = nil,
    serverNameNeedsReload = false,
    baseFontObjects = nil,
    systemFontSnapshots = nil,
    fontHooksInstalled = false,
    nameRegionFontCache = setmetatable({}, { __mode = "k" }),
}
T.FriendlyNameplate = FNP

local function IsFeatureEnabled()
    return C.DB and C.DB.friendlyNameplate and C.DB.friendlyNameplate.enabled == true
end

-- Font Object 中间层：滑块/下拉菜单只更新此对象，避免从 tainted 代码直接操作暴雪受保护 FontString
local customFontObject = CreateFont("STT_FriendlyNameplate_Font")

local CVAR_KEYS = {
    friendlyPlayers = "nameplateshowfriendlyPlayers",
    nameOnly = "nameplateShowOnlyNameForFriendlyPlayerUnits",
    classColor = "nameplateUseClassColorForFriendlyPlayerUnitNames",
}

local OUTLINE_OPTIONS = {
    { value = "DEFAULT", textKey = "描边默认" },
    { value = "NONE", textKey = "描边关闭" },
    { value = "OUTLINE", textKey = "描边开启" },
}

local SYSTEM_FONT_OBJECTS = {
    { key = "normal", name = "SystemFont_NamePlate" },
    { key = "fixed", name = "SystemFont_NamePlateFixed" },
    { key = "outlined", name = "SystemFont_NamePlate_Outlined" },
}

----------------------------------------------------------------
-- PurgeKey：安全清除受保护表的指定键
----------------------------------------------------------------
local function PurgeKey(t, k)
    t[k] = nil
    local c = 42
    repeat
        if t[c] == nil then
            t[c] = nil
        end
        c = c + 1
    until issecurevariable(t, k)
end

local function IsInInstanceZone()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "party" or instanceType == "raid" or instanceType == "scenario"
end

local function EnsureConfigTables()
    C.DB.friendlyNameplate = C.DB.friendlyNameplate or {}
    STT_DB.friendlyNameplate = STT_DB.friendlyNameplate or {}
    return C.DB.friendlyNameplate, STT_DB.friendlyNameplate
end

local function SetConfigValue(key, value)
    local cfg, db = EnsureConfigTables()
    cfg[key] = value
    db[key] = value
    return cfg
end

local function RefreshFriendlyNameplates()
    local current = GetCVar("UnitNameFriendlyPlayerName")
    if current ~= nil then
        SetCVar("UnitNameFriendlyPlayerName", current)
    end
end

local function FormatToggleText(label, enabled)
    if enabled then
        return label .. ": |cff00ff00" .. L["开"] .. "|r"
    end
    return label .. ": |cffff0000" .. L["关"] .. "|r"
end

local function FormatFlags(flags)
    return tostring(flags or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetOutlineText(value)
    for _, option in ipairs(OUTLINE_OPTIONS) do
        if option.value == value then
            return L[option.textKey]
        end
    end
    return L["描边默认"]
end

local function BuildOutlineFlags(baseFlags, mode)
    baseFlags = FormatFlags(baseFlags)
    if mode == "NONE" then
        return ""
    end
    if mode == "OUTLINE" then
        return "OUTLINE"
    end
    return baseFlags
end

function FNP:ResetNameFontCache()
    self.nameRegionFontCache = setmetatable({}, { __mode = "k" })
end

function FNP:GetSystemFontObjects()
    local objects = {}
    for _, info in ipairs(SYSTEM_FONT_OBJECTS) do
        local fontObject = _G[info.name]
        if fontObject then
            objects[#objects + 1] = {
                key = info.key,
                name = info.name,
                object = fontObject,
            }
        end
    end
    return objects
end

function FNP:CaptureSystemFontSnapshots()
    if self.systemFontSnapshots then
        return
    end

    self.systemFontSnapshots = {}
    for _, info in ipairs(self:GetSystemFontObjects()) do
        local path, size, flags = info.object:GetFont()
        self.systemFontSnapshots[info.key] = {
            name = info.name,
            object = info.object,
            path = path,
            size = size,
            flags = FormatFlags(flags),
        }
    end
end

function FNP:RestoreSystemFontObjects()
    if not self.systemFontSnapshots then
        return
    end

    for _, snapshot in pairs(self.systemFontSnapshots) do
        if snapshot.object and snapshot.path and snapshot.size then
            snapshot.object:SetFont(snapshot.path, snapshot.size, snapshot.flags)
        end
    end
end

function FNP:CaptureBaseFontObjects()
    if self.baseFontObjects then
        return
    end

    self:CaptureSystemFontSnapshots()

    local normalSnapshot = self.systemFontSnapshots and self.systemFontSnapshots.normal
    local outlinedSnapshot = self.systemFontSnapshots and self.systemFontSnapshots.outlined
    local normalPath = normalSnapshot and normalSnapshot.path
    local normalSize = normalSnapshot and normalSnapshot.size
    local normalFlags = normalSnapshot and normalSnapshot.flags
    local outlinedPath = outlinedSnapshot and outlinedSnapshot.path
    local outlinedSize = outlinedSnapshot and outlinedSnapshot.size
    local outlinedFlags = outlinedSnapshot and outlinedSnapshot.flags
    local fallbackPath = normalPath or outlinedPath or STANDARD_TEXT_FONT
    local fallbackSize = normalSize or outlinedSize or 9

    self.baseFontObjects = {
        normal = {
            path = normalPath or fallbackPath,
            size = normalSize or fallbackSize,
            flags = FormatFlags(normalFlags),
        },
        outlined = {
            path = outlinedPath or fallbackPath,
            size = outlinedSize or fallbackSize,
            flags = FormatFlags(outlinedFlags ~= nil and outlinedFlags or "OUTLINE"),
        },
    }
end

function FNP:CaptureOriginalCVars()
    if self.originalCVars then
        return
    end
    self.originalCVars = {
        friendlyPlayers = GetCVar(CVAR_KEYS.friendlyPlayers),
        nameOnly = GetCVar(CVAR_KEYS.nameOnly),
        classColor = GetCVar(CVAR_KEYS.classColor),
    }
end

function FNP:ClearOriginalCVars()
    self.originalCVars = nil
end

function FNP:GetCurrentFontConfig()
    local cfg = C.DB.friendlyNameplate or {}
    local fontSize = tonumber(cfg.fontSize) or 12
    if fontSize < 9 then
        fontSize = 9
    elseif fontSize > 20 then
        fontSize = 20
    end
    local fontOutline = cfg.fontOutline
    if fontOutline ~= "NONE" and fontOutline ~= "OUTLINE" then
        fontOutline = "DEFAULT"
    end
    return fontSize, fontOutline
end

function FNP:SyncFontObjects(source)
    local fontSize, fontOutline = self:GetCurrentFontConfig()
    self:CaptureBaseFontObjects()
    self:CaptureSystemFontSnapshots()

    local base = self.baseFontObjects.normal
    local flags = BuildOutlineFlags(base.flags, fontOutline)

    customFontObject:SetFont(base.path, fontSize, flags)

    for _, info in ipairs(self:GetSystemFontObjects()) do
        info.object:SetFont(base.path, fontSize, flags)
    end
end

function FNP:UpdateCustomFontObject()
    local fontSize, fontOutline = self:GetCurrentFontConfig()
    self:CaptureBaseFontObjects()

    local base = self.baseFontObjects.normal
    local flags = BuildOutlineFlags(base.flags, fontOutline)
    customFontObject:SetFont(base.path, fontSize, flags)
end

function FNP:RememberNameRegionFont(nameRegion)
    if not nameRegion or self.nameRegionFontCache[nameRegion] then
        return self.nameRegionFontCache[nameRegion]
    end

    -- 记录原始 FontObject 引用（不调用 :GetFont()，避免 taint）
    -- pcall 保护：nameplate 回收后 FontString 可能变成 bad self
    local ok, origObj = pcall(nameRegion.GetFontObject, nameRegion)
    if not ok then
        return nil
    end
    self.nameRegionFontCache[nameRegion] = origObj or SystemFont_NamePlate
    return self.nameRegionFontCache[nameRegion]
end

function FNP:ShouldOverrideUnitFrame(unitFrame)
    if type(unitFrame) ~= "table" or type(unitFrame.name) ~= "table" then
        return false
    end
    if type(unitFrame.IsFriend) ~= "function" or not unitFrame:IsFriend() then
        return false
    end
    if type(unitFrame.IsPlayer) ~= "function" or not unitFrame:IsPlayer() then
        return false
    end
    return true
end

function FNP:ApplyFontToNameRegion(nameRegion)
    if not nameRegion then
        return false
    end

    if not self:RememberNameRegionFont(nameRegion) then
        return false
    end
    local ok = pcall(nameRegion.SetFontObject, nameRegion, customFontObject)
    return ok
end

function FNP:ApplyFontToUnitFrame(unitFrame)
    if not self:ShouldOverrideUnitFrame(unitFrame) then
        return false
    end
    return self:ApplyFontToNameRegion(unitFrame.name)
end

function FNP:RestoreFontForUnitFrame(unitFrame)
    if type(unitFrame) ~= "table" or type(unitFrame.name) ~= "table" then
        return false
    end

    local origObj = self.nameRegionFontCache[unitFrame.name]
    if not origObj then
        return false
    end

    unitFrame.name:SetFontObject(origObj)
    self.nameRegionFontCache[unitFrame.name] = nil
    return true
end

function FNP:RestoreAllTrackedFonts()
    for nameRegion, origObj in pairs(self.nameRegionFontCache) do
        if nameRegion and origObj then
            nameRegion:SetFontObject(origObj)
        end
    end
    self:ResetNameFontCache()
end

function FNP:RefreshVisibleNameplateFonts(source)
    if not C_NamePlate or type(C_NamePlate.GetNamePlates) ~= "function" then
        return
    end

    local totalCount = 0
    local appliedCount = 0
    local restoredCount = 0

    for _, plateFrame in ipairs(C_NamePlate.GetNamePlates(true) or {}) do
        totalCount = totalCount + 1
        local unitFrame = plateFrame and plateFrame.UnitFrame
        if self.isRuntimeApplied and self:ShouldOverrideUnitFrame(unitFrame) then
            if self:ApplyFontToUnitFrame(unitFrame) then
                appliedCount = appliedCount + 1
            end
        elseif self:RestoreFontForUnitFrame(unitFrame) then
            restoredCount = restoredCount + 1
        end
    end

end

function FNP:ScheduleDelayedFontRefresh(source)
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end

    C_Timer.After(0.1, function()
        if FNP.isRuntimeApplied then
            FNP:SyncFontObjects((source or "unknown") .. "Delayed")
            FNP:RefreshVisibleNameplateFonts((source or "unknown") .. "Delayed")
        end
    end)
end

function FNP:EnsureFontHooks()
    if self.fontHooksInstalled or type(hooksecurefunc) ~= "function" then
        return
    end

    self.fontHooksInstalled = true

    if NamePlateDriverFrame then
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function()
            if not FNP.isRuntimeApplied then
                return
            end
            FNP:SyncFontObjects("OnNamePlateAdded")
            FNP:RefreshVisibleNameplateFonts("OnNamePlateAdded")
        end)

        hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateSize", function()
            if not FNP.isRuntimeApplied then
                return
            end
            FNP:SyncFontObjects("UpdateNamePlateSize")
            FNP:RefreshVisibleNameplateFonts("UpdateNamePlateSize")
            FNP:ScheduleDelayedFontRefresh("UpdateNamePlateSize")
        end)
    end
end

function FNP:Apply(source)
    local cfg = C.DB.friendlyNameplate
    if not cfg or not cfg.enabled then
        return false
    end

    self:CaptureOriginalCVars()
    self:CaptureBaseFontObjects()
    self:SyncFontObjects(source or "Apply")
    self:EnsureFontHooks()

    SetCVar(CVAR_KEYS.friendlyPlayers, "1")
    SetCVar(CVAR_KEYS.nameOnly, cfg.nameOnly and "1" or "0")
    SetCVar(CVAR_KEYS.classColor, cfg.useClassColor and "1" or "0")

    if cfg.removeServerName and NamePlateFriendlyFrameOptions then
        PurgeKey(NamePlateFriendlyFrameOptions, "updateNameUsesGetUnitName")
        self.serverNameNeedsReload = true
    end

    RefreshFriendlyNameplates()
    self.isRuntimeApplied = true
    self:RefreshVisibleNameplateFonts(source or "Apply")
    self:ScheduleDelayedFontRefresh(source or "Apply")
    return true
end

function FNP:Revert(source)
    if not self.originalCVars then
        self.isRuntimeApplied = false
        self:RestoreAllTrackedFonts()
        self:RestoreSystemFontObjects()
        RefreshFriendlyNameplates()
        self:RefreshVisibleNameplateFonts(source or "Revert")
        return false
    end

    SetCVar(CVAR_KEYS.friendlyPlayers, self.originalCVars.friendlyPlayers)
    SetCVar(CVAR_KEYS.nameOnly, self.originalCVars.nameOnly)
    SetCVar(CVAR_KEYS.classColor, self.originalCVars.classColor)
    RefreshFriendlyNameplates()

    self.isRuntimeApplied = false
    self:RestoreAllTrackedFonts()
    self:RestoreSystemFontObjects()
    self:RefreshVisibleNameplateFonts(source or "Revert")
    self:ClearOriginalCVars()
    return true
end

function FNP:RefreshByCurrentZone()
    local cfg = C.DB.friendlyNameplate
    local inInstance = IsInInstanceZone()

    if not cfg or not cfg.enabled then
        self:Revert("ZoneRefresh")
        return false
    end

    if cfg.autoInInstance and not inInstance then
        self:Revert("ZoneRefresh")
        return false
    end

    return self:Apply("ZoneRefresh")
end

function FNP:GetStatus()
    local cfg = C.DB.friendlyNameplate
    if not cfg or not cfg.enabled then
        return L["友方姓名版优化已禁用"]
    end
    if self.isRuntimeApplied then
        return L["友方姓名版优化已应用"]
    end
    return L["友方姓名版优化配置已启用"]
end

----------------------------------------------------------------
-- 开关切换（供命令行和 GUI 使用）
----------------------------------------------------------------
function FNP:Toggle()
    local cfg = SetConfigValue("enabled", not C.DB.friendlyNameplate.enabled)

    if cfg.enabled then
        self:EnableEventFrame()
        self:CaptureBaseFontObjects()
        self:EnsureFontHooks()
        T.msg(L["友方姓名版优化配置已启用"])
    else
        self:DisableEventFrame()
        local reverted = self:Revert()
        T.msg(L["友方姓名版优化配置已禁用"])
        if reverted then
            T.msg(L["友方姓名版设置已恢复"])
        end
        if self.serverNameNeedsReload then
            T.msg(L["姓名版恢复说明_需重载"])
        end
    end

    self:RefreshTexts()
    return cfg.enabled
end

function FNP:ApplyNow()
    local cfg = C.DB.friendlyNameplate
    if not cfg or not cfg.enabled then
        T.msg(L["友方姓名版优化已禁用"])
        return false
    end

    local applied = self:Apply("ApplyNow")
    if applied then
        T.msg(L["友方姓名版优化已应用"])
    end
    self:RefreshTexts()
    return applied
end

function FNP:SetOption(key, value)
    SetConfigValue(key, value)

    if key == "enabled" then
        if value then
            self:EnsureEventFrame()
            self:EnableEventFrame()
            self:CaptureBaseFontObjects()
            self:EnsureFontHooks()
        else
            self:DisableEventFrame()
            self:Revert("DisableOption")
        end
    elseif key == "autoInInstance" then
        self:RefreshByCurrentZone()
    elseif self.isRuntimeApplied then
        if key == "fontSize" or key == "fontOutline" then
            self:SyncFontObjects("SetOption")
            self:RefreshVisibleNameplateFonts("SetOption")
        else
            self:Apply("SetOption")
        end
    end

    if key == "removeServerName" and (not value) and self.serverNameNeedsReload then
        T.msg(L["姓名版恢复说明_需重载"])
    end

    self:RefreshTexts()
end

----------------------------------------------------------------
-- 事件监听帧（进出副本自动切换）
----------------------------------------------------------------
function FNP:EnsureEventFrame()
    if self.eventFrame then
        return
    end

    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function()
        FNP:RefreshByCurrentZone()
        FNP:RefreshTexts()
    end)
    self.eventFrame = f
end

function FNP:EnableEventFrame()
    self:EnsureEventFrame()
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function FNP:DisableEventFrame()
    if self.eventFrame then
        self.eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end

local function CreateNameplateFontString(parent, config)
    local cfg = config or {}
    if type(T.CreateFontString) == "function" then
        return T.CreateFontString(parent, cfg)
    end

    local fs = parent and parent.CreateFontString and parent:CreateFontString(nil, "OVERLAY", cfg.template or "GameFontNormal")
    if fs then
        if cfg.point and fs.SetPoint then
            fs:SetPoint(unpack(cfg.point))
        end
        if cfg.width and fs.SetWidth then
            fs:SetWidth(cfg.width)
        end
        if cfg.justifyH and fs.SetJustifyH then
            fs:SetJustifyH(cfg.justifyH)
        end
        if cfg.color and fs.SetTextColor then
            fs:SetTextColor(unpack(cfg.color))
        end
    end
    return fs
end

local function CreateValueLabel(parent, x, y)
    return CreateNameplateFontString(parent, {
        template = "GameFontNormal",
        point = {"TOP", parent, "TOP", x, y},
        color = {0.9, 0.85, 0.7, 1},
    })
end

local function CreateNameplateSliderRow(parent, config)
    if type(T.CreateSliderRow) == "function" then
        return T.CreateSliderRow(parent, config)
    end

    local cfg = config or {}
    local label = CreateNameplateFontString(parent, {
        template = "GameFontNormal",
        point = { "TOP", parent, "TOP", 0, cfg.y or 0 },
        width = tonumber(cfg.sliderWidth) or 300,
        justifyH = "CENTER",
    })
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOP", parent, "TOP", 0, (cfg.y or 0) - 22)
    slider:SetSize(tonumber(cfg.sliderWidth) or 300, 20)
    if slider.SetMinMaxValues then
        slider:SetMinMaxValues(cfg.min or 0, cfg.max or 1)
    end
    if slider.SetValueStep then
        slider:SetValueStep(cfg.step or 1)
    end
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

    local function refresh()
        local value = cfg.getter and cfg.getter() or 0
        slider.isRefreshing = true
        if slider.SetValue then
            slider:SetValue(value)
        end
        slider.isRefreshing = false
        label:SetText(string.format("%s: %s", tostring(cfg.label or ""), tostring(value)))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if self.isRefreshing then
            return
        end
        local normalized = tonumber(value) or 0
        local step = tonumber(cfg.step) or 1
        if step > 0 then
            normalized = math.floor((normalized / step) + 0.5) * step
        end
        if cfg.setter then
            cfg.setter(normalized)
        end
        refresh()
    end)

    local row = {
        label = label,
        slider = slider,
        Refresh = refresh,
    }
    refresh()
    return row
end

local function BuildOutlineSelectorItems()
    local items = {}
    for _, option in ipairs(OUTLINE_OPTIONS) do
        items[#items + 1] = {
            text = L[option.textKey],
            value = option.value,
        }
    end
    return items
end

function FNP:OnEnable()
    self:EnableEventFrame()
    self:CaptureBaseFontObjects()
    self:UpdateCustomFontObject()
    self:EnsureFontHooks()
    self:RefreshByCurrentZone()
end

function FNP:OnDisable()
    self:DisableEventFrame()
    self:Revert("ModuleDisable")
end

----------------------------------------------------------------
-- GUI: CreateInterface（延迟初始化，由 gui.lua OnShow 调用）
----------------------------------------------------------------
function FNP.CreateInterface(panel)
    if panel.__friendlyNameplateUI then
        FNP.ui = panel.__friendlyNameplateUI
        FNP:RefreshTexts()
        return
    end

    local BUTTON_WIDTH = 250
    local BUTTON_SPACING = 30
    local TITLE_SPACING = 20
    local SEPARATOR_SPACING = 12
    local SEPARATOR_WIDTH = 650
    local left_x = -150
    local right_x = 150
    local y = -30
    local ui = {
        panel = panel,
        toggles = {},
        descriptions = {},
    }

    T.CreateGroupTitle(panel, { text = L["友方姓名版优化"], point = { "TOP", panel, "TOP", 0, y } })
    y = y - TITLE_SPACING
    T.CreateSeparator(panel, { point = { "TOP", panel, "TOP", 0, y }, width = SEPARATOR_WIDTH })
    y = y - SEPARATOR_SPACING

    ui.enableBtn = T.CreateButton(panel, { text = "", width = BUTTON_WIDTH, point = { "TOP", panel, "TOP", 0, y } })
    ui.enableBtn:SetScript("OnClick", function()
        FNP:Toggle()
    end)
    y = y - BUTTON_SPACING - SEPARATOR_SPACING

    T.CreateGroupTitle(panel, { text = L["功能设置"], point = { "TOP", panel, "TOP", 0, y } })
    y = y - TITLE_SPACING
    T.CreateSeparator(panel, { point = { "TOP", panel, "TOP", 0, y }, width = SEPARATOR_WIDTH })
    y = y - SEPARATOR_SPACING

    local function CreateToggle(key, label, x, yPos)
        local btn = T.CreateButton(panel, { text = "", width = BUTTON_WIDTH, point = { "TOP", panel, "TOP", x, yPos } })
        btn:SetScript("OnClick", function()
            FNP:SetOption(key, not C.DB.friendlyNameplate[key])
        end)
        ui.toggles[key] = {
            btn = btn,
            label = label,
        }
        return btn
    end

    CreateToggle("removeServerName", L["去除服务器名"], left_x, y)
    CreateToggle("nameOnly", L["只显示名字"], right_x, y)
    y = y - BUTTON_SPACING
    CreateToggle("useClassColor", L["使用职业颜色"], left_x, y)
    CreateToggle("autoInInstance", L["仅副本内生效"], right_x, y)
    y = y - BUTTON_SPACING - SEPARATOR_SPACING

    T.CreateGroupTitle(panel, { text = L["字体设置"], point = { "TOP", panel, "TOP", 0, y } })
    y = y - TITLE_SPACING
    T.CreateSeparator(panel, { point = { "TOP", panel, "TOP", 0, y }, width = SEPARATOR_WIDTH })
    y = y - SEPARATOR_SPACING

    ui.fontSizeRow = CreateNameplateSliderRow(panel, {
        y = y,
        label = "名字字号",
        min = 9,
        max = 20,
        step = 1,
        getter = function()
            return tonumber(C.DB.friendlyNameplate.fontSize) or 12
        end,
        setter = function(value)
            FNP:SetOption("fontSize", value)
        end,
    })
    ui.fontSizeLabel = ui.fontSizeRow.label
    ui.fontSizeSlider = ui.fontSizeRow.slider
    y = y - 40

    ui.fontOutlineLabel = CreateValueLabel(panel, 0, y)
    y = y - 22

    if type(T.CreateSelectorButton) == "function" then
        ui.fontOutlineDropdown = T.CreateSelectorButton(panel, {
            width = 180,
            height = 26,
            point = { "TOP", panel, "TOP", 0, y },
            ownerFrame = panel:GetParent() or panel,
            emptyText = L["描边默认"],
        })
        ui.fontOutlineDropdown:SetItems(BuildOutlineSelectorItems())
        ui.fontOutlineDropdown.onSelect = function(value, item)
            ui.fontOutlineDropdown:SetSelectedValue(value, item and item.text)
            FNP:SetOption("fontOutline", value)
        end
    end
    y = y - 36 - SEPARATOR_SPACING

    T.CreateGroupTitle(panel, { text = L["说明"], point = { "TOP", panel, "TOP", 0, y } })
    y = y - TITLE_SPACING
    T.CreateSeparator(panel, { point = { "TOP", panel, "TOP", 0, y }, width = SEPARATOR_WIDTH })
    y = y - SEPARATOR_SPACING

    local descriptionKeys = {
        "姓名版说明_去服务器名",
        "姓名版说明_只显示名字",
        "姓名版说明_仅副本内",
        "姓名版说明_字体",
    }
    for _, key in ipairs(descriptionKeys) do
        local text = CreateNameplateFontString(panel, {
            template = "GameFontNormal",
            point = {"TOP", panel, "TOP", 0, y},
            width = 550,
            color = {0.8, 0.8, 0.8, 1},
            justifyH = "LEFT",
        })
        ui.descriptions[#ui.descriptions + 1] = {
            key = key,
            widget = text,
        }
        y = y - 30
    end

    y = y - SEPARATOR_SPACING

    ui.applyBtn = T.CreateButton(panel, { text = "", width = BUTTON_WIDTH, point = { "TOP", panel, "TOP", 0, y } })
    ui.applyBtn:SetScript("OnClick", function()
        FNP:ApplyNow()
    end)

    panel.__friendlyNameplateUI = ui
    FNP.ui = ui
    FNP:RefreshTexts()
end

function FNP.RefreshTexts()
    local ui = FNP.ui
    if not ui then
        return
    end

    if ui.enableBtn then
        ui.enableBtn:SetText(FormatToggleText(L["友方姓名版优化"], C.DB.friendlyNameplate.enabled))
    end

    for key, entry in pairs(ui.toggles or {}) do
        entry.btn:SetText(FormatToggleText(entry.label, C.DB.friendlyNameplate[key]))
    end

    if ui.fontSizeRow then
        ui.fontSizeRow.Refresh()
    end

    if ui.fontOutlineLabel then
        ui.fontOutlineLabel:SetText(L["名字描边"])
    end

    if ui.fontOutlineDropdown then
        ui.fontOutlineDropdown:SetSelectedValue(C.DB.friendlyNameplate.fontOutline, GetOutlineText(C.DB.friendlyNameplate.fontOutline))
    end

    if ui.applyBtn then
        ui.applyBtn:SetText(L["立即应用"])
    end

    for _, entry in ipairs(ui.descriptions or {}) do
        entry.widget:SetText(L[entry.key])
    end
end
