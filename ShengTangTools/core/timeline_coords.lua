local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local TimelineCoords = {}
T.TimelineCoords = TimelineCoords

local function GetCursorXInFrame(frame)
    if not frame or not frame.GetLeft then
        return nil
    end
    local cursorX = GetCursorPosition()
    local scale = frame:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
    return (cursorX / scale) - (frame:GetLeft() or 0)
end

local function FindNearestSourceLine(entry, targetTime)
    local bestLine
    local bestDistance
    for _, item in ipairs(entry and entry.items or {}) do
        local lineNum = tonumber(item.lineNum)
        if lineNum and lineNum > 0 then
            local distance = math.abs((tonumber(item.time) or 0) - (tonumber(targetTime) or 0))
            if not bestDistance or distance < bestDistance then
                bestDistance = distance
                bestLine = lineNum
            end
        end
    end
    return bestLine
end

local function FindItemAtTime(entry, targetTime)
    local bestItem
    local bestDistance
    for _, item in ipairs(entry and entry.items or {}) do
        local distance = math.abs((tonumber(item.time) or 0) - (tonumber(targetTime) or 0))
        if not bestDistance or distance < bestDistance then
            bestDistance = distance
            bestItem = item
        end
    end
    return bestItem
end

local function FindRowIndex(timeline, rowKey)
    for index, key in ipairs(timeline and timeline.orderedKeys or {}) do
        if key == rowKey then
            return index
        end
    end
    return nil
end

local function NormalizeTimeValue(value)
    return tonumber(string.format("%.3f", math.max(0, tonumber(value) or 0))) or 0
end

local function ParsePhaseKey(phase)
    return T.HorizontalTimelineData and T.HorizontalTimelineData.ParsePhaseKey
        and T.HorizontalTimelineData.ParsePhaseKey(tostring(phase or ""):lower())
        or nil
end

local function ExtractPhaseFromPayload(payload)
    local phase = T.HorizontalTimelineData and T.HorizontalTimelineData.ExtractPhaseFromTimePayload
        and T.HorizontalTimelineData.ExtractPhaseFromTimePayload(payload)
        or nil
    return phase
end

local function ResolveMarkerPhase(marker)
    local phase = marker and (marker.key or marker.displayKey or marker.baseKey)
    local parsed = ParsePhaseKey(phase)
    return parsed and parsed.key or nil
end

local function ResolvePhaseAtTime(timeline, targetTime)
    local markers = timeline and timeline.phaseDisplayStats and timeline.phaseDisplayStats.markers or nil
    if type(markers) ~= "table" then
        return nil
    end

    local timeValue = tonumber(targetTime) or 0
    local bestMarker
    for _, marker in ipairs(markers) do
        local markerTime = tonumber(marker and marker.time)
        if markerTime and markerTime <= timeValue then
            if not bestMarker or markerTime >= (tonumber(bestMarker.time) or 0) then
                bestMarker = marker
            end
        end
    end

    local phase = ResolveMarkerPhase(bestMarker)
    if not phase then
        return nil
    end
    return phase, math.max(0, tonumber(bestMarker.time) or 0)
end

local function ResolveSourceTiming(timeline, targetTime, item)
    local phase, offset = ResolvePhaseAtTime(timeline, targetTime)
    local itemPhase = ExtractPhaseFromPayload(item and item.timePayload)
    if phase then
        local phaseOffset = tonumber(offset) or 0
        local sourceTime = NormalizeTimeValue((tonumber(targetTime) or 0) - phaseOffset)
        local timePayload = itemPhase == phase and item and item.timePayload or nil
        return sourceTime, phase, phaseOffset, timePayload
    end

    phase = itemPhase
    if not phase then
        return nil, nil, nil, item and item.timePayload or nil
    end
    offset = tonumber(item and item.phaseDisplayOffset)
    local sourceTime = tonumber(item and item.sourceTime)
    local phaseOffset = tonumber(offset) or tonumber(item and item.phaseDisplayOffset) or 0
    if sourceTime == nil then
        sourceTime = NormalizeTimeValue((tonumber(targetTime) or 0) - phaseOffset)
    end
    return sourceTime, phase, phaseOffset, item and item.timePayload or nil
end

local function BuildContext(timeline, rowKey, entry, targetTime, rawTime, item)
    local meta = entry and entry.meta or nil
    if not entry or not meta then
        return nil
    end
    local explicitItem = item
    item = item or FindItemAtTime(entry, targetTime)
    local sourceTime, phase, phaseDisplayOffset, timePayload = ResolveSourceTiming(timeline, targetTime, item)
    return {
        rowIndex = FindRowIndex(timeline, rowKey),
        rowKey = rowKey,
        time = targetTime,
        rawTime = rawTime or targetTime,
        sourceTime = sourceTime,
        phase = phase,
        phaseDisplayOffset = phaseDisplayOffset,
        timePayload = timePayload,
        entry = entry,
        meta = meta,
        who = meta.displayText or rowKey,
        item = item,
        hitToken = explicitItem ~= nil,
        rowID = item and item.rowID or nil,
        spellID = item and item.spellID or nil,
        dur = item and item.duration or nil,
        sourceLineNum = item and item.lineNum or FindNearestSourceLine(entry, targetTime),
        editorTab = item and item.editorTab or (entry.items and entry.items[1] and entry.items[1].editorTab or nil),
    }
end

function TimelineCoords.ResolveAt(timeline, row, item)
    if type(timeline) ~= "table" or type(row) ~= "table" or not row.trackClip then
        return nil
    end
    if not row.trackClip:IsShown() then
        return nil
    end

    local cursorX = GetCursorXInFrame(row.trackClip)
    local width = row.trackClip:GetWidth() or 0
    if not cursorX or cursorX < 0 or cursorX > width then
        return nil
    end

    local pxPerSecond = math.max(0.0001, tonumber(timeline.pxPerSecond) or 1)
    local rawTime = math.max(0, ((tonumber(timeline.scrollX) or 0) + cursorX) / pxPerSecond)
    local targetTime = rawTime
    if T.HorizontalTimelineData and T.HorizontalTimelineData.GetDragTargetTime then
        targetTime = T.HorizontalTimelineData.GetDragTargetTime(
            rawTime,
            IsShiftKeyDown and IsShiftKeyDown(),
            timeline.GetTimeGrid and timeline:GetTimeGrid() or nil
        )
    end

    return BuildContext(timeline, row.rowKey, row.entry, targetTime, rawTime, item)
end

function TimelineCoords.ResolveForRowTime(timeline, rowKey, targetTime)
    local key = tostring(rowKey or "")
    if key == "" then
        return nil
    end
    local entry = timeline and timeline.perRow and timeline.perRow[key] or nil
    local timeValue = math.max(0, tonumber(targetTime) or 0)
    return BuildContext(timeline, key, entry, timeValue, timeValue, nil)
end

end)
