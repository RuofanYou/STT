local T, C, L = unpack(select(2, ...))

local Version = {}
T.VersionUtil = Version

local function Parse(version)
    if type(version) ~= "string" then
        version = tostring(version or "")
    end

    local datePart, buildPart = version:match("^(%d+)%.(%d+)$")
    if not datePart then
        datePart = version:match("^(%d+)$")
        buildPart = "0"
    end

    return tonumber(datePart) or 0, tonumber(buildPart) or 0
end

function Version.Parse(version)
    return Parse(version)
end

function Version.Compare(a, b)
    local aDate, aBuild = Parse(a)
    local bDate, bBuild = Parse(b)
    if aDate ~= bDate then
        return aDate > bDate and 1 or -1
    end
    if aBuild ~= bBuild then
        return aBuild > bBuild and 1 or -1
    end
    return 0
end

function Version.Greater(a, b)
    if not b then
        return a ~= nil
    end
    if not a then
        return false
    end
    return Version.Compare(a, b) > 0
end

function Version.GreaterOrEqual(a, b)
    return Version.Compare(a, b) >= 0
end

function Version.Max(a, b)
    if Version.Greater(b, a) then
        return b
    end
    return a
end

function Version.Diff(latest, current)
    local latestDate, latestBuild = Parse(latest)
    local currentDate, currentBuild = Parse(current)
    return latestDate - currentDate, latestBuild - currentBuild
end
