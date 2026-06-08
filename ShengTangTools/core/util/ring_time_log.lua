local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded", "raidCommandPanel.enabled", "realtimeBoard.enabled"}, function()

local RingTimeLog = {}
RingTimeLog.__index = RingTimeLog

function RingTimeLog.new(maxPos, entryShape)
    local size = math.max(1, tonumber(maxPos) or 1)
    local log = {
        pos = 0,
        count = 0,
        maxPos = size,
    }

    for i = 1, size do
        local entry = {}
        if type(entryShape) == "table" then
            for k, v in pairs(entryShape) do
                entry[k] = v
            end
        end
        log[i] = entry
    end

    return setmetatable(log, RingTimeLog)
end

function RingTimeLog:Reset()
    self.pos = 0
    self.count = 0
    for i = 1, self.maxPos do
        local entry = self[i]
        for k in pairs(entry) do
            entry[k] = nil
        end
    end
end

function RingTimeLog:Advance()
    self.pos = (self.pos % self.maxPos) + 1
    if self.count < self.maxPos then
        self.count = self.count + 1
    end

    local entry = self[self.pos]
    for k in pairs(entry) do
        entry[k] = nil
    end
    return entry
end

local function PhysicalIndex(log, relativeIndex)
    return ((log.pos - log.count + relativeIndex - 1) % log.maxPos) + 1
end

local function EntryAt(log, relativeIndex)
    if relativeIndex < 1 or relativeIndex > log.count then
        return nil
    end
    return log[PhysicalIndex(log, relativeIndex)]
end

local function LowerBound(log, tBegin)
    local lo, hi = 1, log.count + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local entry = EntryAt(log, mid)
        if entry and entry.time and entry.time < tBegin then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
end

local function UpperBound(log, tEnd)
    local lo, hi = 1, log.count + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local entry = EntryAt(log, mid)
        if entry and entry.time and entry.time <= tEnd then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo - 1
end

function RingTimeLog:IterateWindow(tBegin, tEnd)
    if self.count <= 0 or not tBegin or not tEnd or tBegin > tEnd then
        return function() return nil end
    end

    local beginRelPos = LowerBound(self, tBegin)
    local endRelPos = UpperBound(self, tEnd)
    if beginRelPos > endRelPos then
        return function() return nil end
    end

    assert(beginRelPos <= endRelPos)
    local cursor = beginRelPos - 1
    return function()
        cursor = cursor + 1
        if cursor > endRelPos then
            return nil
        end
        return EntryAt(self, cursor)
    end
end

T.RingTimeLog = RingTimeLog

end)
