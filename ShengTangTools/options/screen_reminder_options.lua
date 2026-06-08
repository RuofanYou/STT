-- 屏幕提醒 V2 设置页注册：仅一个 custom item，把 540 宽区域全权移交给 ScreenReminderOptionsPanel。
-- 旧的 40+ 个 banner/text/icon/bar 全局开关已废弃，由 V2 指示器模型替代（schema 一次性清理）。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

local FULL_CONFIG_PATH = "screenReminder.__fullConfig"
local INDICATOR_MERGE_PATH = "screenReminder.__indicatorMerge"

local function GetFullConfig()
    local schema = T.ScreenReminderSchema
    if not (schema and schema.GetRoot and schema.DeepCopy) then
        return {}
    end
    return schema.DeepCopy(schema.GetRoot())
end

local function RefreshScreenReminderImport(stats)
    if T.ScreenReminder then
        if T.ScreenReminder.ClearAll then
            T.ScreenReminder:ClearAll()
        end
        if T.ScreenReminder.CleanupOrphans then
            T.ScreenReminder:CleanupOrphans()
        end
    end
    if T.ScreenReminderOptionsPanel and T.ScreenReminderOptionsPanel.RefreshAll then
        T.ScreenReminderOptionsPanel:RefreshAll()
    end
    if T.ScreenReminder and T.ScreenReminder.SyncIndicator and type(stats and stats.touchedIDs) == "table" then
        for _, id in ipairs(stats.touchedIDs) do
            T.ScreenReminder:SyncIndicator(id)
        end
    end
end

local function ApplyScreenReminderImport(value, mode)
    if type(value) ~= "table" then
        return nil
    end
    local schema = T.ScreenReminderSchema
    if not (schema and schema.ApplyImportPayload) then
        return nil
    end
    local stats = schema.ApplyImportPayload(value, mode)
    if not stats then
        return nil
    end
    RefreshScreenReminderImport(stats)

    local root = schema.GetRoot and schema.GetRoot()
    local indicatorCount = type(root and root.indicators) == "table" and #root.indicators or 0
    if T.debug then
        T.debug(string.format("[OptionPush] ScreenReminderImportApplied mode=%s sourceCount=%d added=%d replaced=%d renamed=%d indicatorCount=%d globalLeadTimeSec=%s",
            tostring(stats.mode),
            tonumber(stats.sourceCount) or 0,
            tonumber(stats.added) or 0,
            tonumber(stats.replaced) or 0,
            tonumber(stats.renamed) or 0,
            indicatorCount,
            tostring(root and root.globalLeadTimeSec)))
        if type(stats.details) == "table" then
            for _, detail in ipairs(stats.details) do
                if detail.action == "replace" then
                    T.debug(string.format("[OptionPush] ScreenReminderIndicatorReplaced sourceName=%s name=%s indicatorCount=%d",
                        tostring(detail.sourceName),
                        tostring(detail.name),
                        indicatorCount))
                elseif detail.sourceName ~= detail.name then
                    T.debug(string.format("[OptionPush] ScreenReminderIndicatorMerged sourceName=%s name=%s indicatorCount=%d",
                        tostring(detail.sourceName),
                        tostring(detail.name),
                        indicatorCount))
                end
            end
        end
    end
    return stats
end

local function SetFullConfig(value)
    ApplyScreenReminderImport(value, "replace")
end

local function ApplyFullConfig()
    -- SetFullConfig 已经通过统一入口完成应用；保留空 apply 以兼容 OptionEngine 调用链。
end

local function SetIndicatorMerge(value)
    ApplyScreenReminderImport(value, "merge")
end

local function ApplyIndicatorMerge(value)
    -- SetIndicatorMerge 已经通过统一入口完成应用；保留空 apply 以兼容 OptionEngine 调用链。
end

T.ScreenReminderOptionPush = T.ScreenReminderOptionPush or {}
function T.ScreenReminderOptionPush.IsImportPath(dbPath)
    return dbPath == FULL_CONFIG_PATH or dbPath == INDICATOR_MERGE_PATH
end

function T.ScreenReminderOptionPush.BuildImport(value, dbPath)
    if not T.ScreenReminderOptionPush.IsImportPath(dbPath) then
        return nil
    end
    return {
        kind = dbPath == FULL_CONFIG_PATH and "full" or "indicator",
        value = value,
    }
end

function T.ScreenReminderOptionPush.ApplyImport(value, mode, kind)
    return ApplyScreenReminderImport(value, mode)
end

function T.ScreenReminderOptionPush.SendIndicator(indicatorID)
    local schema = T.ScreenReminderSchema
    local share = T.OptionShare
    if not (schema and schema.GetIndicator and schema.DeepCopy and share and share.SendPayload) then
        return false
    end
    local indicator = schema.GetIndicator(indicatorID)
    if not indicator then
        return false
    end
    local copy = schema.DeepCopy(indicator)
    local moduleLabel = (L and L["GUI_NAV_SCREEN_REMIND"]) or "屏幕提醒"
    local itemLabel = tostring(copy.name or "样式")
    return share:SendPayload({
        v = T.Version or "0",
        mode = "item",
        moduleId = "screen_remind",
        label = moduleLabel .. " > " .. itemLabel,
        entries = {
            [INDICATOR_MERGE_PATH] = copy,
        },
        labels = {
            [INDICATOR_MERGE_PATH] = "样式：" .. itemLabel,
        },
    })
end

T.RegisterOptionModule({
    id = "screen_remind",
    category = "interface",
    order = 40,
    titleKey = "GUI_NAV_SCREEN_REMIND",
    masterToggle = {
        dbPath = "screenReminder.enabled",
        default = true,
    },
    itemsFactory = function()
        return {
        {
            key = "screen_reminder_v2_panel",
            type = "custom",
            width = 1,
            render = function(slot, ctx)
                if T.ScreenReminderOptionsPanel and T.ScreenReminderOptionsPanel.Render then
                    return T.ScreenReminderOptionsPanel:Render(slot, ctx)
                end
                return { height = 60 }
            end,
        },
        {
            key = "screen_reminder_full_config_push",
            type = "custom",
            visible = false,
            optionPush = true,
            text = "完整屏幕提醒配置",
            dbPath = FULL_CONFIG_PATH,
            getter = GetFullConfig,
            setter = SetFullConfig,
            apply = ApplyFullConfig,
        },
        {
            key = "screen_reminder_indicator_merge_push",
            type = "custom",
            visible = false,
            optionPush = true,
            text = "单条屏幕提醒样式",
            dbPath = INDICATOR_MERGE_PATH,
            getter = function()
                return nil
            end,
            setter = SetIndicatorMerge,
            apply = ApplyIndicatorMerge,
        },
        }
    end,
})

end)
