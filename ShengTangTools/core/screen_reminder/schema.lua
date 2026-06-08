-- screen_reminder/schema.lua
-- 屏幕提醒 V2 数据层：schemaVersion / 默认值 / 一次性清理 / CRUD
-- 旧 STT_DB.screenReminder（bannerSettings/textSettings/iconSettings/barSettings 等）首次加载静默丢弃。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

T.ScreenReminderSchema = T.ScreenReminderSchema or {}
local Schema = T.ScreenReminderSchema

-- v5: 屏幕提醒提前量改为全局/自定义两态；全局默认 3 秒，文本可用 {sr:N} 覆盖全局态。
Schema.SCHEMA_VERSION = 5

local function ClampLeadTime(value, fallback)
    local number = tonumber(value)
    if not number then
        number = tonumber(fallback) or 3
    end
    if number < 0 then
        number = 0
    elseif number > 10 then
        number = 10
    end
    return number
end

local function NormalizeLeadTimeMode(value)
    if value == "custom" then
        return "custom"
    end
    return "global"
end

local function GenID()
    return string.format("ind_%x_%x", math.floor(GetTime() * 1000), math.random(0, 0xffff))
end

-- ──────────────────────────────────────────────────────────────────────
-- 默认 countdown token（4 类 indicator 共用）
-- 阈值/颜色对齐旧 STT tactical_notice 默认（critical/warning/normal）
-- ──────────────────────────────────────────────────────────────────────
local function DefaultCountdown(overrides)
    local def = {
        enabled = true,
        position = "left",     -- left|right|above|below|overlay(图标/环形/进度条 上)
        decimals = 1,           -- 0|1|2
        unit = "s",             -- "s"|"秒"|""
        wrap = "none",          -- none|()|[]|{}|<>
        colorByTime = true,     -- 默认动态变色，对齐旧 STT
        critical = { threshold = 3.0, color = "FF5555" },
        warning  = { threshold = 5.0, color = "FFCC55" },
        normal   = { color = "50FF50" },
    }
    if type(overrides) == "table" then
        for k, v in pairs(overrides) do
            def[k] = v
        end
    end
    return def
end

local function DefaultAnchor(point, x, y)
    return {
        point = point or "CENTER",
        relativeTo = "UIParent",
        relativePoint = point or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

local function DefaultEffects()
    return {
        pixelGlow = {
            enabled = false,
            durationMode = "custom",
            duration = 0.4,
            useColor = false,
            color = "FFFFFF",
            lines = 8,
            frequency = 0.25,
            length = 10,
            thickness = 1,
            xOffset = 0,
            yOffset = 0,
        },
    }
end

-- ──────────────────────────────────────────────────────────────────────
-- 单类型默认 style + indicator 模板
-- ──────────────────────────────────────────────────────────────────────
local KIND_DEFAULTS = {
    text = {
        nameKey = "SR_KIND_TEXT",
        nameFallback = "文本",
        -- 默认位置：屏幕中心上方 80px
        anchor = function() return DefaultAnchor("CENTER", 0, 80) end,
        countdown = function() return DefaultCountdown({ position = "left" }) end,
        style = function()
            return {
                fontSize = 32,           -- 副本提示醒目但不喧宾夺主
                fontFace = "default",
                color = "FADE85",        -- 金黄色（KYRIAN_GOLD 风格）
                bold = false,
                outline = true,
                outlineColor = "000000",
                shadow = true,
                scale = 1.0,
                spellTokenDisplay = "text",
                stackDir = "UP",         -- 多实例堆叠方向 UP|DOWN|LEFT|RIGHT
                stackSpacing = 2,
            }
        end,
        effects = DefaultEffects,
    },
    icon = {
        nameKey = "SR_KIND_ICON",
        nameFallback = "图标",
        anchor = function() return DefaultAnchor("CENTER", -120, 60) end,
        countdown = function() return DefaultCountdown({ position = "overlay" }) end,
        style = function()
            return {
                size = 36,
                source = "context",   -- context|spellID|texture
                spellID = 0,
                texture = "",
                desaturated = false,
                borderEnabled = true,
                borderColor = "000000",
                cooldownSwipeEnabled = true,
                showLabel = false,
                stackDir = "UP",
                stackSpacing = 2,
            }
        end,
        effects = DefaultEffects,
    },
    bar = {
        nameKey = "SR_KIND_BAR",
        nameFallback = "计时条",
        anchor = function() return DefaultAnchor("CENTER", 0, 0) end,
        countdown = function() return DefaultCountdown({ position = "right" }) end,
        style = function()
            return {
                width = 240,
                height = 20,
                growDir = "right",      -- 进度条填充方向 right|left|up|down
                barColor = "33CC66",
                bgColor = "222222",
                fillMode = "drain",     -- fill|drain
                textOnBar = true,
                iconOnLeft = true,
                iconSize = 20,
                border = true,
                stackDir = "UP",        -- 多实例堆叠方向 UP|DOWN|LEFT|RIGHT
                stackSpacing = 2,
                barTexture = "blizzard", -- preset key，见 media_presets.statusbar
            }
        end,
        effects = DefaultEffects,
    },
    circle = {
        nameKey = "SR_KIND_CIRCLE",
        nameFallback = "环形",
        anchor = function() return DefaultAnchor("CENTER", 0, -35) end,
        countdown = function() return DefaultCountdown({ position = "overlay" }) end,
        style = function()
            return {
                radius = 60,
                thickness = 8,
                color = "33CCFF",
                bgColor = "222222",
                direction = "ccw",      -- ccw|cw
                fillMode = "drain",
                showIcon = false,
                iconSize = 48,
                showText = false,       -- 是否显示 chip 文本（同播报文案）
                textPosition = "below", -- above|below|left|right；左右自动竖排
                textFontSize = 16,
                texturePreset = "flat", -- preset key，见 media_presets.circle；默认扁平
            }
        end,
    },
}

Schema.KIND_DEFAULTS = KIND_DEFAULTS
Schema.KIND_ORDER = { "text", "icon", "bar", "circle" }

local function ApplyKindDefaults(indicator, kind)
    local meta = KIND_DEFAULTS[kind] or KIND_DEFAULTS.text
    indicator.style = meta.style()
    indicator.anchor = meta.anchor()
    indicator.countdown = meta.countdown()
    indicator.effects = meta.effects and meta.effects() or nil
end

local function NormalizeEffects(indicator)
    if not indicator or indicator.kind == "circle" then
        return
    end
    indicator.effects = indicator.effects or {}
    indicator.effects.hitFlash = nil
    indicator.effects.pixelGlow = indicator.effects.pixelGlow or {}
    local glow = indicator.effects.pixelGlow
    if glow.enabled == nil then glow.enabled = false end
    if glow.durationMode == nil then
        glow.durationMode = glow.followLinger and "linger" or "custom"
    end
    if glow.durationMode ~= "linger" then glow.durationMode = "custom" end
    glow.followLinger = nil
    if glow.duration == nil then glow.duration = 0.4 end
    if glow.useColor == nil then glow.useColor = false end
    if glow.color == nil then glow.color = "FFFFFF" end
    if glow.lines == nil then glow.lines = 8 end
    if glow.frequency == nil then glow.frequency = 0.25 end
    if glow.length == nil then glow.length = 10 end
    if glow.thickness == nil then glow.thickness = 1 end
    if glow.xOffset == nil then glow.xOffset = 0 end
    if glow.yOffset == nil then glow.yOffset = 0 end
    glow.border = nil
end

local function NormalizeStyle(indicator)
    if not indicator then return end
    indicator.style = indicator.style or {}
    if indicator.kind == "icon" and indicator.style.cooldownSwipeEnabled == nil then
        indicator.style.cooldownSwipeEnabled = true
    elseif indicator.kind == "text" and indicator.style.outlineColor == nil then
        indicator.style.outlineColor = "000000"
    end
    if indicator.kind == "text" or indicator.kind == "icon" or indicator.kind == "bar" then
        local dir = indicator.style.stackDir
        if dir ~= "UP" and dir ~= "DOWN" and dir ~= "LEFT" and dir ~= "RIGHT" then
            indicator.style.stackDir = "UP"
        end
        if indicator.style.stackSpacing == nil then
            indicator.style.stackSpacing = 2
        end
    end
    if indicator.kind == "text" then
        local spellDisplay = indicator.style.spellTokenDisplay
        if spellDisplay ~= "icon" and spellDisplay ~= "iconText" then
            indicator.style.spellTokenDisplay = "text"
        end
    else
        indicator.style.spellTokenDisplay = nil
    end
end

local function NormalizeIndicatorName(name, fallback)
    local value = tostring(name or "")
    value = value:gsub("%s+", "")
    if value == "" then
        return fallback or "指示器"
    end
    return value
end

local function NameExists(list, name, ignoreID)
    for _, ind in ipairs(list or {}) do
        if ind.id ~= ignoreID and ind.name == name then
            return true
        end
    end
    return false
end

local function MakeUniqueName(list, name, ignoreID)
    local base = NormalizeIndicatorName(name)
    if not NameExists(list, base, ignoreID) then
        return base
    end
    local index = 2
    local candidate = string.format("%s-%d", base, index)
    while NameExists(list, candidate, ignoreID) do
        index = index + 1
        candidate = string.format("%s-%d", base, index)
    end
    return candidate
end

function Schema.NewIndicator(kind, name, order)
    kind = KIND_DEFAULTS[kind] and kind or "text"
    local fallbackName = KIND_DEFAULTS[kind].nameFallback .. "#" .. tostring(order or 1)
    local ind = {
        id = GenID(),
        kind = kind,
        enabled = true,
        exclusiveMode = false,
        name = NormalizeIndicatorName(name, fallbackName),
        order = tonumber(order) or 1,
        leadTimeMode = "global",
        leadTimeSec = 3,        -- 默认提前 3 秒显示
        lingerSec = 0,          -- 到点后延后停留秒数（0=立即消失；>0 触发淡出）
        lingerFadeEnabled = true,
    }
    ApplyKindDefaults(ind, kind)
    return ind
end

local function DefaultIndicators()
    local text = Schema.NewIndicator("text", "文本#1", 1)
    local bar = Schema.NewIndicator("bar", "计时条#1", 2)
    local circle = Schema.NewIndicator("circle", "环形#1", 3)
    bar.exclusiveMode = true
    circle.exclusiveMode = true
    return { text, bar, circle }
end

-- ──────────────────────────────────────────────────────────────────────
-- 默认 SavedVariables 顶层
-- ──────────────────────────────────────────────────────────────────────
local function DefaultRoot()
    local root = {
        schemaVersion = Schema.SCHEMA_VERSION,
        enabled = true,
        locked = true,
        globalLeadTimeSec = 3,
        selectedIndicatorID = nil,
        indicators = DefaultIndicators(),
    }
    root.selectedIndicatorID = root.indicators[1].id
    return root
end

Schema.DefaultRoot = DefaultRoot

local function EnsureIndicatorList(root)
    if type(root) ~= "table" then
        return {}
    end

    local list = root.indicators
    if type(list) == "table" then
        local compact = {}
        local changed = false
        for _, ind in ipairs(list) do
            if type(ind) == "table" then
                compact[#compact + 1] = ind
            else
                changed = true
            end
        end
        if changed then
            root.indicators = compact
            list = compact
        end
    end

    if type(list) ~= "table" or #list == 0 then
        root.indicators = DefaultIndicators()
        list = root.indicators
        root.selectedIndicatorID = list[1] and list[1].id or nil
    end

    return list
end

-- ──────────────────────────────────────────────────────────────────────
-- 一次性清理：旧 schemaVersion 缺失或不等于当前版本 → 整子表覆盖默认值
-- 不弹 StaticPopup，不输出玩家可见提示。
-- ──────────────────────────────────────────────────────────────────────
function Schema.Migrate()
    if type(C.DB) ~= "table" then
        return false
    end

    local current = C.DB.screenReminder
    local needsReset = type(current) ~= "table"

    if needsReset then
        local default = DefaultRoot()
        C.DB.screenReminder = default
        if type(STT_DB) == "table" then
            STT_DB.screenReminder = default
        end
        if T.debug then
            T.debug(string.format(
                "[STT_SCREEN_SCHEMA_MIGRATED] fromVersion=%s toVersion=%d",
                tostring(current and current.schemaVersion or "nil"),
                Schema.SCHEMA_VERSION
            ))
        end
        return true
    end

    -- 已是当前版本：补缺字段（不擦除现有）
    if current.enabled == nil then current.enabled = true end
    if current.locked == nil then current.locked = true end
    current.globalLeadTimeSec = ClampLeadTime(current.globalLeadTimeSec or current.advanceTime, 3)
    current.advanceTime = nil
    local indicators = EnsureIndicatorList(current)
    -- 旧 indicator 字段平滑迁移：durationMode/fixedDurationSec → lingerSec
    local selectedExists = false
    for _, ind in ipairs(indicators) do
        ind.durationMode = nil
        ind.fixedDurationSec = nil
        if ind.lingerSec == nil then ind.lingerSec = 0 end
        if ind.lingerFadeEnabled == nil then ind.lingerFadeEnabled = true end
        local rawLead = tonumber(ind.leadTimeSec)
        if ind.leadTimeMode == nil then
            if not rawLead or math.abs(rawLead - 3) < 0.0001 then
                ind.leadTimeMode = "global"
            else
                ind.leadTimeMode = "custom"
            end
        else
            ind.leadTimeMode = NormalizeLeadTimeMode(ind.leadTimeMode)
        end
        ind.leadTimeSec = ClampLeadTime(ind.leadTimeSec, 3)
        if ind.exclusiveMode == nil then ind.exclusiveMode = false end
        ind.name = MakeUniqueName(indicators, ind.name, ind.id)
        NormalizeStyle(ind)
        NormalizeEffects(ind)
        if ind.id == current.selectedIndicatorID then
            selectedExists = true
        end
        -- 材质 preset 新字段补缺：bar / circle
        if ind.kind == "bar" then
            ind.style = ind.style or {}
            if ind.style.barTexture == nil then ind.style.barTexture = "blizzard" end
        elseif ind.kind == "circle" then
            ind.style = ind.style or {}
            if ind.style.texturePreset == nil then ind.style.texturePreset = "flat" end
            -- 已废弃的辉光字段：视觉效果不佳，下放给材质 preset 承担差异化
            ind.style.glowEnabled = nil
            ind.style.glowSize = nil
            ind.style.glowAlpha = nil
        end
    end
    if not selectedExists then
        current.selectedIndicatorID = indicators[1] and indicators[1].id or nil
    end
    current.schemaVersion = Schema.SCHEMA_VERSION
    return false
end

-- ──────────────────────────────────────────────────────────────────────
-- 列表访问助手（GUI/runtime 都用同一份）
-- ──────────────────────────────────────────────────────────────────────
function Schema.GetRoot()
    if type(C.DB.screenReminder) ~= "table" then
        Schema.Migrate()
    end
    EnsureIndicatorList(C.DB.screenReminder)
    return C.DB.screenReminder
end

function Schema.ListIndicators()
    local root = Schema.GetRoot()
    local list = EnsureIndicatorList(root)
    table.sort(list, function(a, b)
        return (tonumber(a.order) or 0) < (tonumber(b.order) or 0)
    end)
    return list
end

function Schema.GetIndicator(id)
    if not id then return nil end
    for _, ind in ipairs(Schema.ListIndicators()) do
        if ind.id == id then
            return ind
        end
    end
    return nil
end

function Schema.GetSelectedIndicator()
    local root = Schema.GetRoot()
    local ind = Schema.GetIndicator(root.selectedIndicatorID)
    if ind then return ind end
    local list = Schema.ListIndicators()
    ind = list[1]
    if ind then
        root.selectedIndicatorID = ind.id
    end
    return ind
end

function Schema.SetSelectedIndicator(id)
    local root = Schema.GetRoot()
    root.selectedIndicatorID = id
end

local function NextOrder(list)
    local maxOrder = 0
    for _, ind in ipairs(list) do
        if (tonumber(ind.order) or 0) > maxOrder then
            maxOrder = tonumber(ind.order) or 0
        end
    end
    return maxOrder + 1
end

local function NextName(list, kind)
    local base = KIND_DEFAULTS[kind] and KIND_DEFAULTS[kind].nameFallback or "条目"
    local count = 0
    for _, ind in ipairs(list) do
        if ind.kind == kind then
            count = count + 1
        end
    end
    return MakeUniqueName(list, string.format("%s#%d", base, count + 1))
end

function Schema.CreateIndicator(kind)
    kind = KIND_DEFAULTS[kind] and kind or "text"
    local root = Schema.GetRoot()
    local list = EnsureIndicatorList(root)
    local indicator = Schema.NewIndicator(kind, NextName(list, kind), NextOrder(list))
    list[#list + 1] = indicator
    root.selectedIndicatorID = indicator.id
    return indicator
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
        out[k] = DeepCopy(v)
    end
    return out
end

Schema.DeepCopy = DeepCopy

local function FindIndicatorIndexByName(list, name)
    for index, ind in ipairs(list or {}) do
        if ind.name == name then
            return index, ind
        end
    end
    return nil, nil
end

local function BuildImportedIndicator(source, name, order, id)
    if type(source) ~= "table" then
        return nil
    end
    local kind = KIND_DEFAULTS[source.kind] and source.kind or "text"
    local imported = Schema.NewIndicator(kind, name, order)
    local nextID = id or imported.id
    local nextOrder = tonumber(order) or imported.order
    local nextName = NormalizeIndicatorName(name or source.name, imported.name)
    for key, value in pairs(source) do
        imported[key] = DeepCopy(value)
    end
    imported.kind = kind
    imported.id = nextID
    imported.order = nextOrder
    imported.name = nextName
    NormalizeStyle(imported)
    NormalizeEffects(imported)
    return imported
end

local function ApplyRootImportFields(root, source)
    if type(root) ~= "table" or type(source) ~= "table" then
        return
    end
    if source.enabled ~= nil then
        root.enabled = source.enabled ~= false
    end
    if source.locked ~= nil then
        root.locked = source.locked ~= false
    end
    if source.globalLeadTimeSec ~= nil then
        root.globalLeadTimeSec = ClampLeadTime(source.globalLeadTimeSec, root.globalLeadTimeSec)
    end
    root.schemaVersion = Schema.SCHEMA_VERSION
end

function Schema.ApplyImportPayload(payload, mode)
    if type(payload) ~= "table" then
        return nil
    end
    local root = Schema.GetRoot()
    local list = EnsureIndicatorList(root)
    mode = mode == "replace" and "replace" or "merge"
    local fullConfig = type(payload.indicators) == "table"
    local sourceList = fullConfig and payload.indicators or { payload }
    local stats = {
        mode = mode,
        fullConfig = fullConfig,
        sourceCount = 0,
        added = 0,
        replaced = 0,
        renamed = 0,
        touchedIDs = {},
        details = {},
    }

    if mode == "replace" and fullConfig then
        ApplyRootImportFields(root, payload)
    end

    for _, source in ipairs(sourceList) do
        if type(source) == "table" then
            local kind = KIND_DEFAULTS[source.kind] and source.kind or "text"
            local fallbackName = KIND_DEFAULTS[kind].nameFallback .. "#" .. tostring(NextOrder(list))
            local sourceName = NormalizeIndicatorName(source.name, fallbackName)
            stats.sourceCount = stats.sourceCount + 1

            if mode == "replace" then
                local index, existing = FindIndicatorIndexByName(list, sourceName)
                if existing then
                    local replacement = BuildImportedIndicator(source, existing.name, existing.order, existing.id)
                    list[index] = replacement
                    root.selectedIndicatorID = replacement.id
                    stats.touchedIDs[#stats.touchedIDs + 1] = replacement.id
                    stats.details[#stats.details + 1] = {
                        action = "replace",
                        sourceName = sourceName,
                        name = replacement.name,
                        id = replacement.id,
                    }
                    stats.replaced = stats.replaced + 1
                else
                    local finalName = MakeUniqueName(list, sourceName)
                    local imported = BuildImportedIndicator(source, finalName, NextOrder(list))
                    list[#list + 1] = imported
                    root.selectedIndicatorID = imported.id
                    stats.touchedIDs[#stats.touchedIDs + 1] = imported.id
                    stats.details[#stats.details + 1] = {
                        action = "add",
                        sourceName = sourceName,
                        name = imported.name,
                        id = imported.id,
                    }
                    stats.added = stats.added + 1
                    if finalName ~= sourceName then
                        stats.renamed = stats.renamed + 1
                    end
                end
            else
                local finalName = MakeUniqueName(list, sourceName)
                local imported = BuildImportedIndicator(source, finalName, NextOrder(list))
                list[#list + 1] = imported
                root.selectedIndicatorID = imported.id
                stats.touchedIDs[#stats.touchedIDs + 1] = imported.id
                stats.details[#stats.details + 1] = {
                    action = "add",
                    sourceName = sourceName,
                    name = imported.name,
                    id = imported.id,
                }
                stats.added = stats.added + 1
                if finalName ~= sourceName then
                    stats.renamed = stats.renamed + 1
                end
            end
        end
    end

    return stats
end

function Schema.CloneIndicator(id)
    local src = Schema.GetIndicator(id)
    if not src then return nil end
    local root = Schema.GetRoot()
    local list = EnsureIndicatorList(root)
    local copy = DeepCopy(src)
    copy.id = GenID()
    copy.order = NextOrder(list)
    copy.name = MakeUniqueName(list, (src.name or "") .. "副本")
    list[#list + 1] = copy
    root.selectedIndicatorID = copy.id
    return copy
end

function Schema.ImportIndicator(indicator)
    local stats = Schema.ApplyImportPayload(indicator, "merge")
    if not (stats and stats.touchedIDs and stats.touchedIDs[1]) then
        return nil
    end
    return Schema.GetIndicator(stats.touchedIDs[1])
end

function Schema.SetName(id, name)
    local ind = Schema.GetIndicator(id)
    if not ind then return false end
    local root = Schema.GetRoot()
    ind.name = MakeUniqueName(EnsureIndicatorList(root), name, id)
    return true
end

function Schema.DeleteIndicator(id)
    local root = Schema.GetRoot()
    local list = EnsureIndicatorList(root)
    for i, ind in ipairs(list) do
        if ind.id == id then
            table.remove(list, i)
            break
        end
    end
    -- 永远至少保留一条
    if #list == 0 then
        root.indicators = DefaultIndicators()
        root.selectedIndicatorID = root.indicators[1].id
        return root.indicators[1]
    end
    if root.selectedIndicatorID == id then
        root.selectedIndicatorID = list[math.min(#list, 1)].id
    end
    -- 重排 order 以保持密集
    for i, ind in ipairs(list) do
        ind.order = i
    end
    return Schema.GetSelectedIndicator()
end

function Schema.Reorder(idArray)
    if type(idArray) ~= "table" then return end
    local root = Schema.GetRoot()
    local list = EnsureIndicatorList(root)
    local lookup = {}
    for _, ind in ipairs(list) do
        lookup[ind.id] = ind
    end
    local newList = {}
    for i, id in ipairs(idArray) do
        local ind = lookup[id]
        if ind then
            ind.order = i
            newList[#newList + 1] = ind
            lookup[id] = nil
        end
    end
    -- 未在 idArray 中的（极端情况）追加在末尾
    for _, ind in pairs(lookup) do
        ind.order = #newList + 1
        newList[#newList + 1] = ind
    end
    root.indicators = newList
end

-- ──────────────────────────────────────────────────────────────────────
-- 字段路径写入：fieldPath="style.fontSize" → indicator.style.fontSize=value
-- ──────────────────────────────────────────────────────────────────────
function Schema.SetField(id, fieldPath, value)
    local ind = Schema.GetIndicator(id)
    if not ind then return false end
    if type(fieldPath) ~= "string" or fieldPath == "" then return false end
    local parts = {}
    for seg in string.gmatch(fieldPath, "[^%.]+") do
        parts[#parts + 1] = seg
    end
    local current = ind
    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    current[parts[#parts]] = value
    return true
end

function Schema.GetField(id, fieldPath)
    local ind = Schema.GetIndicator(id)
    if not ind then return nil end
    if type(fieldPath) ~= "string" or fieldPath == "" then return nil end
    local current = ind
    for seg in string.gmatch(fieldPath, "[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[seg]
    end
    return current
end

function Schema.ClearAll()
    local root = Schema.GetRoot()
    root.indicators = DefaultIndicators()
    root.selectedIndicatorID = root.indicators[1].id
end

function Schema.IsLocked()
    return Schema.GetRoot().locked ~= false
end

function Schema.SetLocked(locked)
    Schema.GetRoot().locked = locked == true
end

function Schema.IsEnabled()
    return Schema.GetRoot().enabled ~= false
end

function Schema.SetEnabled(enabled)
    Schema.GetRoot().enabled = enabled == true
end

function Schema.GetGlobalLeadTime()
    return ClampLeadTime(Schema.GetRoot().globalLeadTimeSec, 3)
end

function Schema.SetGlobalLeadTime(value)
    Schema.GetRoot().globalLeadTimeSec = ClampLeadTime(value, 3)
end

function Schema.ResolveIndicatorLeadTime(indicator, eventLeadTime)
    if type(indicator) ~= "table" then
        return Schema.GetGlobalLeadTime()
    end
    if NormalizeLeadTimeMode(indicator.leadTimeMode) == "custom" then
        return ClampLeadTime(indicator.leadTimeSec, 3)
    end
    local inlineLead = tonumber(eventLeadTime)
    if inlineLead then
        return ClampLeadTime(inlineLead, Schema.GetGlobalLeadTime())
    end
    return Schema.GetGlobalLeadTime()
end

-- 所有启用 indicator 中最大的可能提前量；用于 timeline_runner 决定"事件多早进入提醒窗口"
-- 整体禁用或全为 0 时返回 0；调用方按需做下限兜底。
function Schema.GetMaxLeadTime(eventLeadTime)
    if not Schema.IsEnabled() then return 0 end
    local maxLead = 0
    for _, ind in ipairs(Schema.ListIndicators()) do
        if ind.enabled ~= false then
            local lt = Schema.ResolveIndicatorLeadTime(ind, eventLeadTime)
            if lt > maxLead then maxLead = lt end
        end
    end
    return maxLead
end

end)
