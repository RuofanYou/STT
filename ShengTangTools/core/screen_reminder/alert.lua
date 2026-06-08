-- 屏幕提醒倒计时共享入口
-- 只封装“立即显示一条倒计时”这类业务提醒，具体样式仍由 ScreenReminder 指示器负责。

local T = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

local Alert = T.ScreenReminderAlert or {}
T.ScreenReminderAlert = Alert

local function ListIndicators()
    local schema = T.ScreenReminderSchema
    if not (schema and schema.ListIndicators) then
        return nil
    end
    local ok, list = pcall(schema.ListIndicators)
    if ok and type(list) == "table" then
        return list
    end
    return nil
end

function Alert:IndicatorExists(name)
    local target = tostring(name or "")
    if target == "" then
        return false
    end
    local list = ListIndicators()
    if not list then
        return false
    end
    for _, indicator in ipairs(list) do
        if tostring(indicator and indicator.name or "") == target then
            return true
        end
    end
    return false
end

function Alert:BuildIndicatorItems(selected, defaultName, missingFormat)
    local selectedValue = tostring(selected or defaultName or "")
    local selectedSeen = false
    local options = {}
    local list = ListIndicators() or {}
    for _, indicator in ipairs(list) do
        local name = tostring(indicator and indicator.name or "")
        if name ~= "" then
            selectedSeen = selectedSeen or name == selectedValue
            options[#options + 1] = { text = name, value = name }
        end
    end
    if selectedValue ~= "" and not selectedSeen then
        table.insert(options, 1, {
            text = string.format(tostring(missingFormat or "%s"), selectedValue),
            value = selectedValue,
            disabled = true,
        })
    end
    return options
end

function Alert:ShowImmediateCountdown(opts)
    if type(opts) ~= "table" then
        return false
    end
    local duration = tonumber(opts.durationSec or opts.duration)
    if not duration or duration <= 0 then
        return false
    end
    local indicatorName = tostring(opts.indicatorName or "")
    if indicatorName == "" then
        return false
    end
    if not (T.ScreenReminder and T.ScreenReminder.Show) then
        return false
    end

    local actualEvent = GetTime() + duration
    T.ScreenReminder:Show({
        text = tostring(opts.text or ""),
        duration = duration,
        actualEvent = actualEvent,
        targetIndicators = {
            [indicatorName] = true,
        },
        forceImmediate = true,
        spellID = tonumber(opts.spellID),
        spellIcon = opts.spellIcon,
        severity = opts.severity,
    })
    return true, actualEvent
end

end)
