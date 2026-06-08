local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({ { "semanticTimeline.runtimeEnabled", true }, "semanticTimeline.editorLoaded", "dreadElegy.enabled", "privateAuraHijack.enabled" }, function()

function T.PlayInlineSound(path, label)
    if type(path) ~= "string" or path == "" or not PlaySoundFile then
        return false
    end

    local ok, willPlay = pcall(PlaySoundFile, path, "Master")
    if not ok or not willPlay then
        if T and T.debug then
            T.debug("[InlineSound] play_failed path=" .. tostring(path) .. " label=" .. tostring(label or "") .. " channel=Master")
        end
        return false
    end
    return true
end

end)
