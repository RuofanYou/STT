local T = unpack(select(2, ...))
T.RegisterColdFile("yakEscape.enabled", function()

local MODULE = "YakEscapeMVP"
local MOUNT_ID = 460

local frame
local button
local stage = "summon"
local movedOnCurrentClick = false

local function Debug(message)
    if T and T.debug then
        T.debug("[" .. MODULE .. "] " .. tostring(message))
    end
end

local function SetButtonText(text)
    if button and button.SetText then
        button:SetText(text)
    end
end

local function SetMacroEnabled(enabled)
    if not button then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        Debug("战斗中跳过安全按钮属性切换")
        return
    end
    if enabled then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/run if C_MountJournal then C_MountJournal.SummonByID(" .. MOUNT_ID .. ") end")
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("macrotext", nil)
    end
end

local function SetStage(nextStage)
    stage = nextStage or "summon"
    if stage == "summon" then
        SetButtonText("牦牛撤离测试")
        SetMacroEnabled(true)
    elseif stage == "merchant" then
        SetButtonText("等待商人窗口")
        SetMacroEnabled(false)
    elseif stage == "move" then
        SetButtonText("按住前进")
        SetMacroEnabled(false)
    elseif stage == "failed" then
        SetButtonText("修理失败")
        SetMacroEnabled(false)
    else
        SetButtonText("完成")
        SetMacroEnabled(false)
    end
    Debug("阶段切换: " .. tostring(stage))
end

local function TryRepair()
    Debug("检测到 MERCHANT_SHOW")

    local canRepair = false
    if CanMerchantRepair then
        local ok, value = pcall(CanMerchantRepair)
        canRepair = ok and value == true
        Debug("CanMerchantRepair=" .. tostring(canRepair))
    end
    if not canRepair then
        SetStage("failed")
        return
    end

    local cost, canAfford = 0, true
    if GetRepairAllCost then
        local ok, repairCost, repairPossible = pcall(GetRepairAllCost)
        if ok then
            cost = tonumber(repairCost) or 0
            canAfford = repairPossible ~= false
        else
            Debug("GetRepairAllCost 失败: " .. tostring(repairCost))
        end
    end
    Debug("修理费用=" .. tostring(cost) .. " canAfford=" .. tostring(canAfford))

    if RepairAllItems and canAfford then
        local ok, err = pcall(RepairAllItems)
        Debug("RepairAllItems 调用结果=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
        SetStage("move")
    else
        SetStage("failed")
    end
end

local function TryMoveStart()
    if stage ~= "move" then
        return
    end
    movedOnCurrentClick = true
    if MoveForwardStart then
        local ok, err = pcall(MoveForwardStart)
        Debug("MoveForwardStart 调用结果=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
    else
        Debug("MoveForwardStart 不可用")
    end
end

local function TryMoveStop()
    if stage ~= "move" then
        return
    end
    if MoveForwardStop then
        local ok, err = pcall(MoveForwardStop)
        Debug("MoveForwardStop 调用结果=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
    else
        Debug("MoveForwardStop 不可用")
    end
    SetStage("done")
end

local function CreateButton()
    button = CreateFrame("Button", "STT_YakEscapeMVPButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    button:SetSize(132, 28)
    button:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            TryMoveStart()
        end
    end)
    button:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            TryMoveStop()
        end
    end)
    button:HookScript("PostClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then
            return
        end
        if movedOnCurrentClick then
            movedOnCurrentClick = false
            return
        end
        if stage == "summon" then
            Debug("召唤牦牛宏已由安全按钮触发 mountID=" .. tostring(MOUNT_ID))
            SetStage("merchant")
        elseif stage == "failed" or stage == "done" then
            SetStage("summon")
        end
    end)
    SetStage("summon")
end

local function Init()
    if frame then
        return
    end
    frame = CreateFrame("Frame")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" and (stage == "merchant" or stage == "summon") then
            TryRepair()
        end
    end)
    CreateButton()
end

T.RegisterInitCallback(Init)

end)
