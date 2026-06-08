local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("CountdownEnabled", function()

function T.PlayCountdownMp3(number)
    local value = tonumber(number)
    if not value or value < 1 or value > 10 or value ~= math.floor(value) then
        return false
    end
    if C.DB and C.DB.CountdownEnabled == false then
        return false
    end

    local path = T.CountdownPacks and T.CountdownPacks.Resolve and T.CountdownPacks.Resolve(value) or nil
    if not path then
        return false
    end
    local channel = T.CountdownPacks.GetChannel()
    local willPlay = PlaySoundFile(path, channel)
    return willPlay == true
end

end)
