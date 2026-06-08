local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("castRecorder.backendEnabled", function()

local function ApplyGanttToggle()
    if T.CastLogRow then
        T.CastLogRow.Refresh()
    end
end

local function OpenReplay()
    if T.CastReplayGUI then
        T.CastReplayGUI:Open()
    end
end

local function ConfirmClearRecords()
    if not StaticPopupDialogs["STT_CAST_RECORDER_CLEAR"] then
        StaticPopupDialogs["STT_CAST_RECORDER_CLEAR"] = {
            text = L["OPT_CAST_RECORDER_CLEAR_CONFIRM"] or "确定要清空所有施法录像吗？此操作不可撤销。",
            button1 = ACCEPT,
            button2 = CANCEL,
            OnAccept = function()
                if T.CastRecorder then
                    T.CastRecorder:ClearAllRecords()
                end
                if T.CastLogComm and T.CastLogComm.ClearTeamRecords then
                    T.CastLogComm.ClearTeamRecords()
                end
                if T.CastLogRow then
                    T.CastLogRow.Refresh()
                end
                if T.CastReplayGUI and T.CastReplayGUI.RenderList then
                    T.CastReplayGUI.RenderList()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show("STT_CAST_RECORDER_CLEAR")
end

local function RequestTeamRecords()
    if T.CastLogComm and T.CastLogComm.RequestTeamRecords then
        T.CastLogComm.RequestTeamRecords()
    end
end

local function RenderHint(slot, ctx)
    local fs = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", slot, "TOPLEFT", 4, -4)
    fs:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -8, 4)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(1, 0.82, 0)
    fs:SetText(L["OPT_CAST_RECORDER_HINT"]
        or "点击“收集团队施法记录”后，可在战术方案甘特图里查看团队施法记录。")
    return { height = 78 }
end

T.RegisterOptionModule({
    id = "cast_recorder",
    category = "tactic",
    order = 55,
    titleKey = "OPT_CAST_RECORDER_TITLE",
    newSince = "260522.7",
    masterToggle = {
        dbPath = "castRecorder.backendEnabled",
        default = false,
    },
    itemsFactory = function()
        return {
        {
            key = "hint",
            type = "custom",
            width = 1,
            height = 78,
            render = RenderHint,
        },
        {
            key = "maxRecords",
            type = "slider",
            textKey = "OPT_CAST_RECORDER_MAX",
            dbPath = "castRecorder.maxRecords",
            default = 1,
            min = 1,
            max = 5,
            step = 1,
        },
        {
            key = "showInGantt",
            type = "check",
            textKey = "OPT_CAST_RECORDER_SHOW_IN_GANTT",
            dbPath = "castRecorder.showInGantt",
            default = true,
            apply = ApplyGanttToggle,
            newSince = "260522.11",
        },
        {
            key = "requestTeamRecords",
            type = "button",
            textKey = "OPT_CAST_RECORDER_REQUEST_TEAM",
            width = 1,
            onClick = RequestTeamRecords,
            newSince = "260523.50",
        },
        {
            key = "clearRecords",
            type = "button",
            textKey = "OPT_CAST_RECORDER_CLEAR",
            width = 0.5,
            onClick = ConfirmClearRecords,
        },
        {
            key = "openReplay",
            type = "button",
            textKey = "OPT_CAST_RECORDER_OPEN",
            width = 0.5,
            onClick = OpenReplay,
            newSince = "260522.11",
        },
        }
    end,
})

end)
