local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("luraCrystal.enabled", function()

local NEW_SINCE = "260523.2"

local sampleTextCache

local function GetSampleText()
    if sampleTextCache then
        return sampleTextCache
    end
    sampleTextCache = table.concat({
        "[人员]",
        "咕咕2=咕咕玩家",
        "SS1=术士玩家",
        "增辉1=增辉玩家",
        "LR1=猎人玩家",
        "AM1=暗牧玩家",
        "增辉2=增辉玩家2",
        "DKT1=死亡骑士坦克玩家",
        "种子=咕咕2 SS1 增辉1 LR1 AM1 增辉2 DKT1",
        "",
        "[时间轴]",
        "{time:00:43.5} {种子}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:01:45.5} {种子}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:02:47.5} {种子}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:03:57.5} {ct:5}{种子}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:04:05.0} {ct:5}{种子}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:04:27.5} {ct:5}{种子}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:04:35.0} {ct:5}{种子}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:04:57.5} {ct:5}{种子}{bar:5,spell:1253031,label:<扔下种子>}",
        "{time:05:05.0} {ct:5}{种子}{bar:5,spell:1253031,label:<扔下种子>}",
    }, "\n")
    return sampleTextCache
end

local function RenderProgressSample(slot, context)
    local sampleText = GetSampleText()
    local width = math.max(280, tonumber(context and context.width) or 280)
    local innerWidth = width - 8

    local intro = T.CreateLabel(slot, {
        point = { "TOPLEFT", slot, "TOPLEFT", 4, -4 },
        text = L["LURA_CRYSTAL_PROGRESS_INTRO"] or "把下面示例复制到 STT 战术方案里，先改每个槽位对应的玩家名，再按需要调整“种子=”名单。",
        size = 12,
        width = innerWidth,
        color = { 0.72, 0.72, 0.72, 1 },
        wordWrap = true,
    })

    local sampleBox = T.CreateEditBox(slot, {
        point = { "TOPLEFT", intro, "BOTTOMLEFT", 0, -6 },
        width = innerWidth,
        height = 390,
        multiLine = true,
        autoFocus = false,
        justifyH = "LEFT",
        justifyV = "TOP",
        fontObject = "ChatFontNormal",
    })

    local restoring = false
    local function SelectSample(self)
        restoring = true
        self:SetText(sampleText)
        restoring = false
        self:SetCursorPosition(0)
        self:HighlightText()
    end

    sampleBox:SetText(sampleText)
    sampleBox:SetCursorPosition(0)
    sampleBox:SetScript("OnEditFocusGained", SelectSample)
    sampleBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        SelectSample(self)
    end)
    sampleBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetCursorPosition(0)
        self:HighlightText(0, 0)
    end)
    sampleBox:SetScript("OnTextChanged", function(self)
        if not restoring and self:GetText() ~= sampleText then
            SelectSample(self)
        end
    end)

    local help = T.CreateLabel(slot, {
        point = { "TOPLEFT", sampleBox, "BOTTOMLEFT", 0, -8 },
        text = L["LURA_CRYSTAL_PROGRESS_HELP"] or "",
        size = 12,
        width = innerWidth,
        wordWrap = true,
        color = { 0.62, 0.62, 0.62, 1 },
    })
    if help.SetJustifyH then
        help:SetJustifyH("LEFT")
    end

    return { height = 502 }
end

T.RegisterOptionModule({
    id = "luraCrystalProgress",
    category = "dungeon",
    order = 48.1,
    titleKey = "GUI_NAV_LURA_CRYSTAL_PROGRESS",
    newSince = NEW_SINCE,
    itemsFactory = function()
        return {
        {
            key = "progressSample",
            type = "custom",
            width = 1,
            height = 502,
            render = RenderProgressSample,
            newSince = NEW_SINCE,
        },
        }
    end,
})

end)
