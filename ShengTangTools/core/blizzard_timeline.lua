local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"blizzardTimeline.enabled", "semanticTimeline.editorLoaded"}, function()

-- 暴雪时间轴集成（脚本事件注入 + 视图设置 + 恢复）
local BlizzardTimeline = {}
T.BlizzardTimeline = BlizzardTimeline

-- 指示图标掩码（EncounterEventIconmask，数值为官方枚举）
BlizzardTimeline.IndicatorIconMaskDefs = {
    { key = "tank", labelKey = "坦克", value = 128 },
    { key = "healer", labelKey = "治疗", value = 256 },
    { key = "dps", labelKey = "输出", value = 512 },
    { key = "magic", labelKey = "魔法", value = 8 },
    { key = "curse", labelKey = "诅咒", value = 32 },
    { key = "poison", labelKey = "中毒", value = 64 },
    { key = "bleed", labelKey = "流血", value = 4 },
    { key = "enrage", labelKey = "狂暴", value = 2 },
}

local injectedEventIDs = {}

local function GetConfig()
    return C.DB and C.DB.blizzardTimeline
end

local function GetRuntimeState()
    if type(STT_DB) ~= "table" then
        return nil
    end
    if type(STT_DB._blizzardTimelineState) ~= "table" then
        STT_DB._blizzardTimelineState = {}
    end
    return STT_DB._blizzardTimelineState
end

local function DebugInjection(msg)
    local cfg = GetConfig()
    if cfg and cfg.debugInjection then
        T.debug("[注入] " .. (msg or ""))
    end
end

local function DebugRecovery(msg)
    local cfg = GetConfig()
    if cfg and cfg.debugRecovery then
        T.debug("[恢复] " .. (msg or ""))
    end
end

local function SaveInjectedEventID(eventID)
    if type(eventID) ~= "number" then return end
    injectedEventIDs[eventID] = true

    local state = GetRuntimeState()
    if not state then return end
    if type(state.eventIDs) ~= "table" then
        state.eventIDs = {}
    end
    table.insert(state.eventIDs, eventID)
end

local function ClearSavedEventIDs()
    local state = GetRuntimeState()
    if not state then return end
    state.eventIDs = nil
end

local function CollectAllInjectedEventIDs()
    local ids = {}
    for eventID in pairs(injectedEventIDs) do
        ids[eventID] = true
    end
    local state = GetRuntimeState()
    if state and type(state.eventIDs) == "table" then
        for _, eventID in ipairs(state.eventIDs) do
            if type(eventID) == "number" then
                ids[eventID] = true
            end
        end
    end
    return ids
end

local function CanUseBlizzardTimeline()
    if not C_EncounterTimeline then return false end
    if not (C_EncounterTimeline.IsFeatureAvailable and C_EncounterTimeline.IsFeatureEnabled) then return false end
    if not C_EncounterTimeline.IsFeatureAvailable() then return false end
    if not C_EncounterTimeline.IsFeatureEnabled() then
        DebugInjection("[暴雪时间轴] 功能未启用，跳过注入")
        return false
    end
    if not (Enum and Enum.EncounterEventSeverity) then return false end
    return true
end

local function GetTimelineView()
    if EncounterTimeline and EncounterTimeline.GetView then
        return EncounterTimeline:GetView()
    end
    if EncounterTimeline and EncounterTimeline.View then
        return EncounterTimeline.View
    end
    return nil
end

local function GetSeverityEnum(token)
    local map = {
        Low = 0,
        Medium = 1,
        High = 2,
    }
    if Enum and Enum.EncounterEventSeverity then
        return Enum.EncounterEventSeverity[token] or Enum.EncounterEventSeverity.Medium
    end
    return map[token] or 1
end

local function NormalizeSeverityToken(token)
    if not token then return nil end
    token = tostring(token)
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    local low = token:lower()
    if low == "low" or low == "l" or token == "低" then return "Low" end
    if low == "medium" or low == "mid" or low == "m" or token == "中" then return "Medium" end
    if low == "high" or low == "h" or token == "高" then return "High" end
    return nil
end

local function ExtractSeverityTag(event)
    if not event then return nil end
    local text = event.originalText or event.content or event.text or ""
    local tag = text:match("{sev:([^}]+)}")
        or text:match("{severity:([^}]+)}")
        or text:match("{严重度:([^}]+)}")
    return NormalizeSeverityToken(tag)
end

local function ExtractSpellID(event)
    if not event then return nil end
    if event.spellID and type(event.spellID) == "number" then
        return event.spellID
    end
    local text = event.content or event.originalText or event.text or ""
    local id = text:match("{spell:(%d+):?%d*}")
    return id and tonumber(id) or nil
end

local function ResolveIcon(event, cfg)
    if not cfg then return 0, 0 end

    if cfg.iconSource == "spell" then
        local spellID = ExtractSpellID(event)
        if spellID and C_Spell and C_Spell.GetSpellInfo then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.iconID then
                return spellInfo.iconID, spellID
            end
        end
    elseif cfg.iconSource == "mapping" then
        if event and type(event.iconFileID) == "number" then
            return event.iconFileID, event.spellID or 0
        end
        if event and type(event.icon) == "number" then
            return event.icon, event.spellID or 0
        end
        local spellID = ExtractSpellID(event)
        if spellID and C_Spell and C_Spell.GetSpellInfo then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.iconID then
                return spellInfo.iconID, spellID
            end
        end
    end

    local fallbackIcon = cfg.defaultIconFileID
    if type(fallbackIcon) ~= "number" then
        fallbackIcon = 0
    end
    return fallbackIcon, 0
end

local function ResolveSeverity(event, cfg)
    if not cfg then return GetSeverityEnum("Medium") end

    if cfg.severityMode == "text-tag" then
        local tag = ExtractSeverityTag(event)
        if tag then
            return GetSeverityEnum(tag)
        end
    elseif cfg.severityMode == "mapping" then
        if event then
            if type(event.severity) == "number" then
                return event.severity
            elseif type(event.severity) == "string" then
                local tag = NormalizeSeverityToken(event.severity)
                if tag then
                    return GetSeverityEnum(tag)
                end
            end
        end
    end

    return GetSeverityEnum(cfg.defaultSeverity or "Medium")
end

local function ResolveOrientation(viewOrientation, viewDirection)
    if not (EncounterTimelineUtil and EncounterTimelineUtil.CreateOrientation) then return nil end
    if not (Enum and Enum.EncounterEventsOrientation and Enum.EncounterEventsIconDirection) then return nil end

    local orientation = Enum.EncounterEventsOrientation.Horizontal
    if viewOrientation == "Vertical" then
        orientation = Enum.EncounterEventsOrientation.Vertical
    end

    local direction
    if orientation == Enum.EncounterEventsOrientation.Vertical then
        if viewDirection == "Top" then
            direction = Enum.EncounterEventsIconDirection.Top
        else
            direction = Enum.EncounterEventsIconDirection.Bottom
        end
    else
        if viewDirection == "Left" then
            direction = Enum.EncounterEventsIconDirection.Left
        else
            direction = Enum.EncounterEventsIconDirection.Right
        end
    end

    return EncounterTimelineUtil.CreateOrientation(orientation, direction)
end

function BlizzardTimeline:GetAllIndicatorIconMask()
    if Constants and Constants.EncounterTimelineIconMasks and Constants.EncounterTimelineIconMasks.EncounterTimelineAllIcons then
        return Constants.EncounterTimelineIconMasks.EncounterTimelineAllIcons
    end
    local mask = 0
    if bit and bit.bor then
        for _, def in ipairs(self.IndicatorIconMaskDefs) do
            mask = bit.bor(mask, def.value)
        end
    else
        for _, def in ipairs(self.IndicatorIconMaskDefs) do
            mask = mask + def.value
        end
    end
    return mask
end

function BlizzardTimeline:ApplyViewSettings()
    local cfg = GetConfig()
    if not cfg then return end
    local view = GetTimelineView()
    if not view then
        DebugRecovery("[暴雪时间轴] 未找到视图对象，跳过视图设置")
        return
    end

    if view.SetEventIconScale and type(cfg.viewIconScale) == "number" then
        view:SetEventIconScale(cfg.viewIconScale)
    end
    if view.SetEventTextEnabled and type(cfg.viewTextEnabled) == "boolean" then
        view:SetEventTextEnabled(cfg.viewTextEnabled)
    end
    if view.SetEventCountdownEnabled and type(cfg.viewCountdownEnabled) == "boolean" then
        view:SetEventCountdownEnabled(cfg.viewCountdownEnabled)
    end
    if view.SetEventTooltipsEnabled and type(cfg.viewTooltipsEnabled) == "boolean" then
        view:SetEventTooltipsEnabled(cfg.viewTooltipsEnabled)
    end
    if view.SetEventIndicatorIconMask and type(cfg.viewIndicatorIconMask) == "number" then
        view:SetEventIndicatorIconMask(cfg.viewIndicatorIconMask)
    end
    if view.SetViewBackgroundAlpha and type(cfg.viewBackgroundAlpha) == "number" then
        view:SetViewBackgroundAlpha(cfg.viewBackgroundAlpha)
    end

    local orientation = ResolveOrientation(cfg.viewOrientation, cfg.viewDirection)
    if orientation and view.SetViewOrientation then
        view:SetViewOrientation(orientation)
    end

    if view.SetCrossAxisOffset and type(cfg.viewCrossAxisOffset) == "number" then
        view:SetCrossAxisOffset(cfg.viewCrossAxisOffset)
    end
    if view.SetCrossAxisExtent and type(cfg.viewCrossAxisExtent) == "number" then
        view:SetCrossAxisExtent(cfg.viewCrossAxisExtent)
    end

    if view.SetPipIconShown and type(cfg.pipIconShown) == "boolean" then
        view:SetPipIconShown(cfg.pipIconShown)
    end
    if view.SetPipTextShown and type(cfg.pipTextShown) == "boolean" then
        view:SetPipTextShown(cfg.pipTextShown)
    end
    if view.SetPipDuration and type(cfg.pipDuration) == "number" then
        view:SetPipDuration(cfg.pipDuration)
    end

    if view.UpdateView then
        view:UpdateView()
    end
end

function BlizzardTimeline:BuildEventInfo(event)
    local cfg = GetConfig()
    if not cfg then return nil end

    local duration = math.max(0, tonumber(event.time) or 0)
    local iconFileID, spellID = ResolveIcon(event, cfg)
    local severity = ResolveSeverity(event, cfg)
    local maxQueue = tonumber(cfg.maxQueueDuration) or 0

    local eventInfo = {
        duration = duration,
        spellID = spellID or 0,
        iconFileID = iconFileID or 0,
        maxQueueDuration = maxQueue,
        overrideName = event.text or "",
        severity = severity,
        paused = false,
    }

    if type(cfg.indicatorIconMask) == "number" then
        eventInfo.icons = cfg.indicatorIconMask
    end

    return eventInfo
end

function BlizzardTimeline:ClearInjected()
    if not (C_EncounterTimeline and C_EncounterTimeline.CancelScriptEvent) then
        wipe(injectedEventIDs)
        ClearSavedEventIDs()
        return
    end

    local count = 0
    local ids = CollectAllInjectedEventIDs()
    for eventID in pairs(ids) do
        local ok = pcall(C_EncounterTimeline.CancelScriptEvent, eventID)
        if ok then
            count = count + 1
        end
    end

    wipe(injectedEventIDs)
    ClearSavedEventIDs()

    if count > 0 then
        DebugInjection("[暴雪时间轴] 已清理 " .. count .. " 个事件")
    end
end

function BlizzardTimeline:InjectEvents(events, context)
    local cfg = GetConfig()
    if not cfg then return end
    if not cfg.enabled then return end
    if not CanUseBlizzardTimeline() then return end
    if not (C_EncounterTimeline and C_EncounterTimeline.AddScriptEvent) then return end

    if context and context.isTest then
        if not cfg.injectInTest and not context.force then
            return
        end
    elseif context and context.reason == "encounter_start" then
        if not cfg.injectOnEncounterStart and not context.force then
            return
        end
    end

    if not (context and context.skipClear) then
        self:ClearInjected()
    end

    self:ApplyViewSettings()

    local count = 0
    for _, event in ipairs(events or {}) do
        local eventInfo = self:BuildEventInfo(event)
        if eventInfo then
            local ok, eventID = pcall(C_EncounterTimeline.AddScriptEvent, eventInfo)
            if ok and eventID then
                SaveInjectedEventID(eventID)
                count = count + 1
                DebugInjection("[暴雪时间轴] 注入事件: " .. (event.text or "") .. " @ " .. tostring(eventInfo.duration) .. "s")
            elseif not ok then
                DebugInjection("[暴雪时间轴] 注入失败: " .. tostring(event.text or "") .. " @ " .. tostring(eventInfo.duration) .. "s")
            end
        end
    end

    if count > 0 then
        DebugInjection("[暴雪时间轴] 共注入 " .. count .. " 个事件")
    end
end

function BlizzardTimeline:InjectTestEvents()
    local cfg = GetConfig()
    if not cfg or not cfg.enabled then
        T.msg("暴雪时间轴注入未开启，无法注入测试事件")
        return
    end

    local sample = {
        { time = 3, text = L["时间轴测试事件"] .. " 1" },
        { time = 6, text = L["时间轴测试事件"] .. " 2" },
        { time = 9, text = L["时间轴测试事件"] .. " 3" },
    }
    self:InjectEvents(sample, { isTest = true, reason = "manual_test", force = true })
end

function BlizzardTimeline:RecoverIfNeeded(context)
    local cfg = GetConfig()
    if not cfg then return end
    if not cfg.enabled then return end

    if not cfg.recoveryEnabled then
        if not (context and context.manual) then
            return
        end
        DebugRecovery("[暴雪时间轴] 已关闭自动恢复，执行手动恢复")
    end

    if not CanUseBlizzardTimeline() then return end

    local hasActive = C_EncounterTimeline.HasActiveEvents and C_EncounterTimeline.HasActiveEvents() or false
    local hasAny = C_EncounterTimeline.HasAnyEvents and C_EncounterTimeline.HasAnyEvents() or false
    if not (hasActive or hasAny) then
        DebugRecovery("[暴雪时间轴] 当前无事件，跳过恢复")
        return
    end

    local currentTime = C_EncounterTimeline.GetCurrentTime and C_EncounterTimeline.GetCurrentTime() or 0
    if type(currentTime) ~= "number" then
        DebugRecovery("[暴雪时间轴] 获取当前时间失败，跳过恢复")
        return
    end

    if cfg.recoveryMode == "safe" and not (context and context.force) then
        if not cfg.recoveryAllowIfScriptExists then
            local scriptCount = 0
            if C_EncounterTimeline.GetEventCountBySource and Enum and Enum.EncounterTimelineEventSource then
                scriptCount = C_EncounterTimeline.GetEventCountBySource(Enum.EncounterTimelineEventSource.Script) or 0
            end
            if scriptCount > 0 then
                DebugRecovery("[暴雪时间轴] 检测到脚本事件，安全模式跳过恢复")
                return
            end
        end
    end

    local text = nil
    if T.GetTimelineSourceText then
        text = select(1, T.GetTimelineSourceText({ silent = true }))
    end
    if not text or text == "" then
        DebugRecovery("[暴雪时间轴] 无可用时间轴文本，跳过恢复")
        return
    end

    if not (T.NoteParser and T.NoteParser.ParseNote and T.BuildTimelineEvents) then
        DebugRecovery("[暴雪时间轴] 解析模块未就绪，跳过恢复")
        return
    end

    local parsed = T.NoteParser:ParseNote(text or "")
    if not parsed or #parsed == 0 then
        DebugRecovery("[暴雪时间轴] 解析结果为空，跳过恢复")
        return
    end

    local events = T.BuildTimelineEvents(parsed)
    local rebuilt = {}
    local maxLookahead = tonumber(cfg.recoveryMaxLookahead) or 0

    for _, event in ipairs(events) do
        local remaining = (tonumber(event.time) or 0) - currentTime
        if remaining > 0 then
            if maxLookahead <= 0 or remaining <= maxLookahead then
                table.insert(rebuilt, {
                    time = remaining,
                    text = event.text,
                    spellID = event.spellID,
                    originalText = event.originalText,
                    content = event.content,
                })
            end
        end
    end

    if #rebuilt == 0 then
        DebugRecovery("[暴雪时间轴] 无可恢复事件，跳过恢复")
        return
    end

    self:InjectEvents(rebuilt, { reason = "recovery", force = true })
    DebugRecovery("[暴雪时间轴] 恢复完成，注入事件数: " .. tostring(#rebuilt))
end

end)
