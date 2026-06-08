local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded", "raidCommandPanel.enabled", "realtimeBoard.enabled"}, function()

local InstanceGate = {}
T.InstanceGate = InstanceGate

local RAID_DIFFICULTY = {
    [14] = true, -- 普通
    [15] = true, -- 英雄
    [16] = true, -- 史诗
    [17] = true, -- 随机团队
}

function InstanceGate.GetCurrent()
    local inInstance, instanceType = IsInInstance()
    local name, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    return {
        inInstance = inInstance == true,
        instanceType = instanceType,
        difficultyID = difficultyID,
        instanceID = instanceID,
        name = name,
    }
end

function InstanceGate.IsRaidActive()
    local info = InstanceGate.GetCurrent()
    return info.inInstance and info.instanceType == "raid" and RAID_DIFFICULTY[info.difficultyID] == true
end

function InstanceGate.GetRaidRejectReason()
    local info = InstanceGate.GetCurrent()
    if not info.inInstance or info.instanceType ~= "raid" then
        return L["EARLY_PULL_ONLY_RAID"] or "/stt pull 仅在团本中可用"
    end
    if RAID_DIFFICULTY[info.difficultyID] ~= true then
        return L["EARLY_PULL_RAID_DIFFICULTY_UNSUPPORTED"] or "当前团本难度暂不支持提前开怪检测"
    end
    return nil
end

end)
