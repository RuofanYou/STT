local _, ns = ...
local T, C = ns[1], ns[2]

local BUTTON_NAME = "ShengTangTools"

function T.RefreshMinimapButton()
    if not (LibStub and C and C.DB and C.DB.minimap) then
        return false
    end

    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then
        return false
    end

    if icon.Refresh then
        icon:Refresh(BUTTON_NAME, C.DB.minimap)
    end

    if C.DB.minimap.hide == true then
        if icon.Hide then
            icon:Hide(BUTTON_NAME)
        end
    elseif icon.Show then
        icon:Show(BUTTON_NAME)
    end

    return true
end

T.RegisterInitCallback(function()
    if not LibStub then
        return
    end
    local broker = LibStub("LibDataBroker-1.1", true)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not (broker and icon) then
        return
    end

    local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("ShengTangTools", {
        type = "data source",
        text = "STT",
        label = T.addon_cname,
        icon = "Interface\\AddOns\\ShengTangTools\\STTicon.png",
        OnClick = function(_, button)
            if button == "LeftButton" then
                T.ToggleGUI()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(T.addon_cname)
            tooltip:AddLine("|cff888888v" .. T.Version .. "|r")
            tooltip:AddLine("|cff00ff00左键|r 打开/关闭主窗口")
        end,
    })
    icon:Register(BUTTON_NAME, ldb, C.DB.minimap)
    T.RefreshMinimapButton()
end)
