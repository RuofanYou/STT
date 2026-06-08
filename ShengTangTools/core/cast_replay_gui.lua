-- 施法回放对照窗口（Cast Replay GUI）
-- 把一场录像的实际施法与录制时的 STN 战术方案时间轴上下对照展示。
-- 纯本地数据呈现：读取 STT_CDB.castRecords，不订阅战斗事件、不做任何通信。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("castRecorder.backendEnabled", function()

local GUI = {}
T.CastReplayGUI = GUI

local function Loc(key, fallback)
    local v = L and L[key]
    if type(v) == "string" and v ~= "" then
        return v
    end
    return fallback
end

--=== 布局常量 ===--
local WINDOW_W, WINDOW_H = 920, 320
local LIST_W = 208
local TRACK_LEFT = 10
local TRACK_RIGHT_PAD = 12
local PLAN_TRACK_TOP = -24
local PLAN_TRACK_H = 38
local ACTUAL_TRACK_TOP = -86
local ACTUAL_TRACK_H = 64
local CAST_ICON_SIZE = 14
local PLAN_ICON_SIZE = 18

local COLORS = {
    title       = { 1, 0.82, 0, 1 },
    panelBG     = { 0.06, 0.06, 0.08, 0.85 },
    trackBG     = { 0.12, 0.12, 0.15, 0.9 },
    planMine    = { 1, 0.82, 0.1, 1 },
    planOther   = { 0.5, 0.5, 0.55, 0.55 },
    actual      = { 0.4, 0.78, 1, 1 },
    playhead    = { 1, 0.95, 0.35, 1 },
    phaseLine   = { 0.45, 0.78, 0.85, 0.6 },
    text        = { 0.88, 0.88, 0.9, 1 },
    dim         = { 0.6, 0.6, 0.64, 1 },
    rowHover    = { 0.25, 0.4, 0.6, 0.5 },
    rowActive   = { 0.3, 0.5, 0.75, 0.7 },
    success     = { 0.34, 1, 0.55, 1 },
    wipe        = { 1, 0.36, 0.32, 1 },
}

local SPEED_CYCLE = { 1, 2, 4, 0.5 }

--=== 运行态 ===--
local win = nil          -- 主窗口
local filterWin = nil    -- 技能筛选子窗口
local replaySubID = nil

local state = {
    record = nil,
    recordIndex = nil,
    planEvents = nil,    -- 解析后的方案事件（nil = 方案丢失，降级）
    spellSummary = nil,  -- 当前录像的 unique 技能统计
    filter = {},         -- [spellID] = false 表示隐藏；缺省视为显示
    speedIndex = 1,
    pxPerSec = 1,
    dragging = false,
}

-- 渲染对象池
local pool = { planMarkers = {}, actualIcons = {}, phaseLines = {}, timeTicks = {}, listRows = {}, filterRows = {} }

--=== 工具函数 ===--

local function FormatTime(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function ShowSpellTooltip(owner, payload)
    if T.UITooltip and T.UITooltip.ShowSpellItem then
        T.UITooltip.ShowSpellItem(owner, payload, { anchor = "ANCHOR_RIGHT" })
    end
end

local function HideTooltip()
    if T.UITooltip then
        T.UITooltip.ScheduleHide()
    end
end

local function FormatDate(epoch)
    if not epoch or epoch == 0 then
        return ""
    end
    return date("%m-%d %H:%M", epoch)
end

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    return tostring(spellID)
end

local function SpellIcon(spellID)
    if T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
        local icon = T.TimelineSyntax.ResolveSpellIcon(spellID)
        if icon then
            return icon
        end
    end
    return 134400 -- 默认问号图标
end

-- 全员受众词识别（"所有人/全团/all/everyone"）
local function IsAllAudience(text)
    local v = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return v == "all" or v == "everyone" or v == "所有人" or v == "全团"
end

-- 判断方案事件是否与当前玩家相关（仅决定高亮/弱化，不决定显隐，避免受众解析误差丢信息）
local function IsEventForPlayer(event)
    if not event.hasAudience then
        return true
    end
    local segs = event.segments
    if type(segs) ~= "table" then
        return true
    end
    for _, seg in ipairs(segs) do
        local cond = seg.condition or ""
        local condOK = IsAllAudience(cond) or T.ShouldBroadcastToPlayer(cond)
        local nameOK = T.ShouldBroadcastForNames(seg.players or {})
        if condOK and nameOK then
            return true
        end
    end
    return false
end

-- 解析录制时方案，得到对照用事件列表；方案丢失返回 nil
local function BuildPlanEvents(record)
    if not record or not record.planId or not T.Note or not T.Note.GetPlan then
        return nil
    end
    local plan = T.Note:GetPlan(record.planId)
    if not plan or type(plan.content) ~= "string" or plan.content == "" then
        return nil
    end
    local parsed = T.TimelineSyntax.ParseTimelineText(plan.content)
    local events = {}
    for _, ev in ipairs(parsed) do
        events[#events + 1] = {
            time = tonumber(ev.time) or 0,
            label = ev.displayText or ev.content or "",
            spellID = ev.primarySpellID,
            mine = IsEventForPlayer(ev),
        }
    end
    return events
end

-- 统计当前录像的 unique 技能（用于筛选面板）
local function BuildSpellSummary(record)
    local seen, list = {}, {}
    for _, cast in ipairs(record.casts or {}) do
        local s = cast.s
        if s then
            local entry = seen[s]
            if not entry then
                entry = { spellID = s, count = 0, name = SpellName(s), icon = SpellIcon(s) }
                seen[s] = entry
                list[#list + 1] = entry
            end
            entry.count = entry.count + 1
        end
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

--=== 时间轴渲染 ===--

local function HidePool(name)
    for _, obj in ipairs(pool[name]) do
        obj:Hide()
    end
end

local function CanvasInnerWidth()
    local canvas = win.canvas
    return math.max(50, canvas:GetWidth() - TRACK_LEFT - TRACK_RIGHT_PAD)
end

local function TimeToX(t)
    return TRACK_LEFT + (tonumber(t) or 0) * state.pxPerSec
end

-- 阶段竖虚线
local function RenderPhaseLines()
    HidePool("phaseLines")
    local record = state.record
    if not record or type(record.phases) ~= "table" then
        return
    end
    local canvas = win.canvas
    for i, ph in ipairs(record.phases) do
        if i > 1 then -- 第一条（t=0）不画线
            local line = pool.phaseLines[i]
            if not line then
                line = canvas:CreateTexture(nil, "ARTWORK")
                line:SetWidth(1)
                pool.phaseLines[i] = line
            end
            line:SetColorTexture(unpack(COLORS.phaseLine))
            line:ClearAllPoints()
            line:SetPoint("TOP", canvas, "TOPLEFT", TimeToX(ph.t), -4)
            line:SetPoint("BOTTOM", canvas, "BOTTOMLEFT", TimeToX(ph.t), 18)
            line:Show()
        end
    end
end

-- 时间刻度
local function RenderTimeTicks()
    HidePool("timeTicks")
    local record = state.record
    if not record then
        return
    end
    local duration = record.duration or 0
    local stepSec = 30
    if duration > 600 then
        stepSec = 120
    elseif duration > 240 then
        stepSec = 60
    end
    local canvas = win.canvas
    local idx, t = 0, 0
    while t <= duration do
        idx = idx + 1
        local tick = pool.timeTicks[idx]
        if not tick then
            tick = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            pool.timeTicks[idx] = tick
        end
        tick:ClearAllPoints()
        tick:SetPoint("BOTTOM", canvas, "BOTTOMLEFT", TimeToX(t), 2)
        tick:SetText(FormatTime(t))
        tick:Show()
        t = t + stepSec
    end
end

-- 上轨：方案计划事件（仅画落在录像时长 [0,duration] 内的事件，避免画到画布外）
local function RenderPlanTrack()
    HidePool("planMarkers")
    local events = state.planEvents
    if not events then
        return
    end
    local canvas = win.canvas
    local duration = state.record and state.record.duration or 0
    local shown = 0
    for _, ev in ipairs(events) do
        if ev.time >= 0 and ev.time <= duration then
            shown = shown + 1
            local marker = pool.planMarkers[shown]
            if not marker then
                marker = CreateFrame("Frame", nil, canvas)
                marker.bar = marker:CreateTexture(nil, "ARTWORK")
                marker.bar:SetAllPoints(marker)
                marker.icon = marker:CreateTexture(nil, "OVERLAY")
                marker.icon:SetSize(PLAN_ICON_SIZE, PLAN_ICON_SIZE)
                marker.icon:SetPoint("BOTTOM", marker, "TOP", 0, 1)
                marker:SetScript("OnEnter", function(self)
                    ShowSpellTooltip(self, {
                        spellID = self._spellID,
                        spellIcon = self._spellIcon,
                        text = self._label,
                        time = self._time,
                        source = Loc("CAST_REPLAY_TRACK_PLAN", "方案计划"),
                    })
                end)
                marker:SetScript("OnLeave", HideTooltip)
                pool.planMarkers[shown] = marker
            end
            local col = ev.mine and COLORS.planMine or COLORS.planOther
            marker:SetSize(3, PLAN_TRACK_H)
            marker:ClearAllPoints()
            marker:SetPoint("TOPLEFT", canvas, "TOPLEFT", TimeToX(ev.time) - 1, PLAN_TRACK_TOP)
            marker.bar:SetColorTexture(unpack(col))
            marker._label = ev.label
            marker._time = ev.time
            marker._spellID = ev.spellID
            if ev.spellID then
                local texture = SpellIcon(ev.spellID)
                marker._spellIcon = texture
                marker.icon:SetTexture(texture)
                marker.icon:SetDesaturated(not ev.mine)
                marker.icon:SetAlpha(ev.mine and 1 or 0.5)
                marker.icon:Show()
            else
                marker._spellIcon = nil
                marker.icon:Hide()
            end
            marker:Show()
        end
    end
end

-- 下轨：实际施法
local function RenderActualTrack()
    HidePool("actualIcons")
    local record = state.record
    if not record then
        return
    end
    local canvas = win.canvas
    local centerY = ACTUAL_TRACK_TOP - ACTUAL_TRACK_H / 2 + CAST_ICON_SIZE / 2
    local shown = 0
    for i, cast in ipairs(record.casts or {}) do
        if state.filter[cast.s] ~= false then
            shown = shown + 1
            local icon = pool.actualIcons[shown]
            if not icon then
                icon = CreateFrame("Frame", nil, canvas)
                icon:SetSize(CAST_ICON_SIZE, CAST_ICON_SIZE)
                icon.tex = icon:CreateTexture(nil, "ARTWORK")
                icon.tex:SetAllPoints(icon)
                icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:SetScript("OnEnter", function(self)
                    ShowSpellTooltip(self, {
                        spellID = self._spellID,
                        spellIcon = self._spellIcon,
                        time = self._time,
                        source = Loc("CAST_REPLAY_TRACK_ACTUAL", "实际施法"),
                    })
                end)
                icon:SetScript("OnLeave", HideTooltip)
                pool.actualIcons[shown] = icon
            end
            local texture = SpellIcon(cast.s)
            icon.tex:SetTexture(texture)
            icon._spellID = cast.s
            icon._spellIcon = texture
            icon._time = cast.t
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", canvas, "TOPLEFT", TimeToX(cast.t), centerY)
            icon:Show()
        end
    end
end

local function UpdatePlayhead()
    if not win or not state.record then
        return
    end
    local session = T.CastReplay:GetSession()
    local t = session and session.currentTime or 0
    win.playhead:ClearAllPoints()
    win.playhead:SetPoint("TOP", win.canvas, "TOPLEFT", TimeToX(t), -4)
    win.playhead:SetPoint("BOTTOM", win.canvas, "BOTTOMLEFT", TimeToX(t), 18)
    win.timeLabel:SetText(FormatTime(t) .. " / " .. FormatTime(state.record.duration or 0))
    win.playBtn:SetText(session and session.playing and Loc("CAST_REPLAY_PAUSE", "暂停") or Loc("CAST_REPLAY_PLAY", "播放"))
end

local function RenderTimeline()
    if not win or not state.record then
        return
    end
    state.pxPerSec = CanvasInnerWidth() / math.max(state.record.duration or 1, 1)
    if T.debug then
        T.debug(string.format("[CastReplay] 渲染时间轴 duration=%.1f canvasW=%.0f pxPerSec=%.3f",
            state.record.duration or 0, win.canvas:GetWidth() or 0, state.pxPerSec))
    end
    RenderPhaseLines()
    RenderTimeTicks()
    RenderPlanTrack()
    RenderActualTrack()
    UpdatePlayhead()
end

--=== 录像列表 ===--

local function SelectRecord(index)
    local records = T.CastRecorder and T.CastRecorder:GetRecords() or {}
    local record = records[index]
    if not record then
        return
    end
    state.record = record
    state.recordIndex = index
    state.planEvents = BuildPlanEvents(record)
    state.spellSummary = BuildSpellSummary(record)
    state.filter = {}
    T.CastReplay:Load(record)

    if T.debug then
        T.debug(string.format("[CastReplay] 加载录像 #%d name=%s casts=%d planId=%s planEvents=%s spells=%d",
            index, tostring(record.encounterName), #(record.casts or {}),
            tostring(record.planId),
            state.planEvents and tostring(#state.planEvents) or "nil(方案丢失或未解析)",
            #(state.spellSummary or {})))
    end

    -- 标题信息
    local diffName = ""
    if record.difficulty and GetDifficultyInfo then
        diffName = GetDifficultyInfo(record.difficulty) or ""
    end
    local resultText = record.success and Loc("CAST_REPLAY_KILL", "击杀") or Loc("CAST_REPLAY_WIPE", "灭团")
    win.infoLabel:SetText(string.format("%s  |  %s  |  %s  |  %s",
        record.encounterName or "?", diffName, resultText, FormatDate(record.date)))
    win.infoLabel:SetTextColor(unpack(record.success and COLORS.success or COLORS.wipe))

    win.noPlanLabel:SetShown(state.planEvents == nil)
    if win.canvas then
        win.canvas:Show()
    end
    RenderTimeline()
    GUI.RenderList()
    if filterWin and filterWin:IsShown() then
        GUI.RenderFilter()
    end
end

function GUI.RenderList()
    if not win then
        return
    end
    HidePool("listRows")
    local records = T.CastRecorder and T.CastRecorder:GetRecords() or {}
    win.listEmpty:SetShown(#records == 0)

    local y = -4
    for i, record in ipairs(records) do
        local row = pool.listRows[i]
        if not row then
            row = CreateFrame("Button", nil, win.listPanel.content)
            row:SetHeight(40)
            row.hl = row:CreateTexture(nil, "BACKGROUND")
            row.hl:SetAllPoints(row)
            row.hl:SetColorTexture(unpack(COLORS.rowHover))
            row.hl:Hide()
            row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -5)
            row.title:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.title:SetJustifyH("LEFT")
            row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
            row:SetScript("OnEnter", function(self) if state.recordIndex ~= self._index then self.hl:Show() end end)
            row:SetScript("OnLeave", function(self) if state.recordIndex ~= self._index then self.hl:Hide() end end)
            row:SetScript("OnClick", function(self) SelectRecord(self._index) end)
            pool.listRows[i] = row
        end
        row._index = i
        row:SetWidth(LIST_W - 24)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.listPanel.content, "TOPLEFT", 4, y)
        row.title:SetText(record.encounterName or "?")
        local resultText = record.success and Loc("CAST_REPLAY_KILL", "击杀") or Loc("CAST_REPLAY_WIPE", "灭团")
        row.sub:SetText(string.format("%s  %s  %s", resultText, FormatTime(record.duration or 0), FormatDate(record.date)))
        if state.recordIndex == i then
            row.hl:SetColorTexture(unpack(COLORS.rowActive))
            row.hl:Show()
        else
            row.hl:SetColorTexture(unpack(COLORS.rowHover))
            row.hl:Hide()
        end
        row:Show()
        y = y - 44
    end
    win.listPanel:SetContentHeight(math.max(10, -y))
end

--=== 技能筛选子窗口 ===--

function GUI.RenderFilter()
    if not filterWin then
        return
    end
    HidePool("filterRows")
    local summary = state.spellSummary or {}
    local y = -4
    for i, entry in ipairs(summary) do
        local row = pool.filterRows[i]
        if not row then
            row = CreateFrame("Button", nil, filterWin.panel.content)
            row:SetHeight(24)
            row.hl = row:CreateTexture(nil, "BACKGROUND")
            row.hl:SetAllPoints(row)
            row.hl:SetColorTexture(unpack(COLORS.rowHover))
            row.hl:Hide()
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetJustifyH("LEFT")
            row.name:SetWidth(150)
            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row:SetScript("OnEnter", function(self) self.hl:Show() end)
            row:SetScript("OnLeave", function(self) self.hl:Hide() end)
            row:SetScript("OnClick", function(self)
                local sid = self._spellID
                state.filter[sid] = (state.filter[sid] == false) and true or false
                GUI.RenderFilter()
                RenderActualTrack()
            end)
            pool.filterRows[i] = row
        end
        row._spellID = entry.spellID
        row:SetWidth(232)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", filterWin.panel.content, "TOPLEFT", 4, y)
        row.icon:SetTexture(entry.icon)
        row.name:SetText(entry.name)
        row.count:SetText(tostring(entry.count))
        local visible = state.filter[entry.spellID] ~= false
        row.icon:SetDesaturated(not visible)
        row.name:SetTextColor(unpack(visible and COLORS.text or COLORS.dim))
        row.count:SetTextColor(unpack(visible and COLORS.text or COLORS.dim))
        row:Show()
        y = y - 26
    end
    filterWin.panel:SetContentHeight(math.max(10, -y))
end

local function SetAllFilter(visible)
    for _, entry in ipairs(state.spellSummary or {}) do
        state.filter[entry.spellID] = visible and true or false
    end
    GUI.RenderFilter()
    RenderActualTrack()
end

local function EnsureFilterWindow()
    if filterWin then
        return filterWin
    end
    filterWin = T.CreatePopupWindow(UIParent, {
        name = "STT_CastReplayFilterWindow",
        width = 280,
        height = 420,
        title = Loc("CAST_REPLAY_FILTER", "技能筛选"),
        point = { "LEFT", win, "RIGHT", 8, 0 },
    })
    local allBtn = T.CreateButton(filterWin, { width = 118, height = 22 })
    allBtn:SetText(Loc("CAST_REPLAY_FILTER_ALL", "全选"))
    allBtn:SetPoint("TOPLEFT", filterWin, "TOPLEFT", 12, -34)
    allBtn:SetScript("OnClick", function() SetAllFilter(true) end)

    local noneBtn = T.CreateButton(filterWin, { width = 118, height = 22 })
    noneBtn:SetText(Loc("CAST_REPLAY_FILTER_NONE", "全不选"))
    noneBtn:SetPoint("TOPRIGHT", filterWin, "TOPRIGHT", -12, -34)
    noneBtn:SetScript("OnClick", function() SetAllFilter(false) end)

    filterWin.panel = T.CreateScrollPanel(filterWin, {
        point1 = { "TOPLEFT", filterWin, "TOPLEFT", 10, -64 },
        point2 = { "BOTTOMRIGHT", filterWin, "BOTTOMRIGHT", -10, 12 },
        backdrop = true,
        backdropAlpha = 0.12,
    })
    return filterWin
end

--=== 画布交互（点击 / 拖动 seek）===--

local function SeekToCursor()
    local canvas = win.canvas
    local scale = canvas:GetEffectiveScale()
    local cx = GetCursorPosition() / scale
    local relX = cx - canvas:GetLeft() - TRACK_LEFT
    T.CastReplay:Seek(relX / math.max(state.pxPerSec, 0.0001))
end

--=== 主窗口构建 ===--

local function BuildWindow()
    win = T.CreatePopupWindow(UIParent, {
        name = "STT_CastReplayWindow",
        width = WINDOW_W,
        height = WINDOW_H,
        title = Loc("CAST_REPLAY_TITLE", "施法记录回放"),
    })

    -- 左侧录像列表
    local listBG = CreateFrame("Frame", nil, win, "BackdropTemplate")
    listBG:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -34)
    listBG:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 10, 12)
    listBG:SetWidth(LIST_W)
    T.ApplyBackdrop(listBG, { alpha = 0.2, style = "chat" })

    win.listPanel = T.CreateScrollPanel(listBG, {
        point1 = { "TOPLEFT", listBG, "TOPLEFT", 4, -4 },
        point2 = { "BOTTOMRIGHT", listBG, "BOTTOMRIGHT", -4, 4 },
    })
    win.listEmpty = listBG:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.listEmpty:SetPoint("TOPLEFT", listBG, "TOPLEFT", 10, -10)
    win.listEmpty:SetPoint("TOPRIGHT", listBG, "TOPRIGHT", -10, -10)
    win.listEmpty:SetJustifyH("LEFT")
    win.listEmpty:SetText(Loc("CAST_REPLAY_EMPTY", "暂无录像。完成一场 Boss 战后会自动生成。"))
    win.listEmpty:Hide()

    -- 右侧区域
    local right = CreateFrame("Frame", nil, win)
    right:SetPoint("TOPLEFT", listBG, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 12)

    win.infoLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.infoLabel:SetPoint("TOPLEFT", right, "TOPLEFT", 4, -2)
    win.infoLabel:SetText("")

    -- 时间轴画布
    local canvas = CreateFrame("Frame", nil, right, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -24)
    canvas:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    canvas:SetHeight(190)
    T.ApplyBackdrop(canvas, { alpha = 0.85, style = "tooltip" })
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function()
        if state.record then
            state.dragging = true
            SeekToCursor()
        end
    end)
    canvas:SetScript("OnMouseUp", function() state.dragging = false end)
    canvas:SetScript("OnUpdate", function()
        if state.dragging then
            SeekToCursor()
        end
    end)
    canvas:Hide()
    win.canvas = canvas

    -- 轨道标题
    local planTitle = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    planTitle:SetPoint("TOPLEFT", canvas, "TOPLEFT", TRACK_LEFT, -6)
    planTitle:SetText(Loc("CAST_REPLAY_TRACK_PLAN", "方案计划"))
    local actualTitle = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    actualTitle:SetPoint("TOPLEFT", canvas, "TOPLEFT", TRACK_LEFT, ACTUAL_TRACK_TOP + 14)
    actualTitle:SetText(Loc("CAST_REPLAY_TRACK_ACTUAL", "实际施法"))

    -- 轨道背景
    local planBG = canvas:CreateTexture(nil, "BACKGROUND")
    planBG:SetColorTexture(unpack(COLORS.trackBG))
    planBG:SetPoint("TOPLEFT", canvas, "TOPLEFT", TRACK_LEFT, PLAN_TRACK_TOP)
    planBG:SetPoint("BOTTOMRIGHT", canvas, "TOPRIGHT", -TRACK_RIGHT_PAD, PLAN_TRACK_TOP - PLAN_TRACK_H)
    local actualBG = canvas:CreateTexture(nil, "BACKGROUND")
    actualBG:SetColorTexture(unpack(COLORS.trackBG))
    actualBG:SetPoint("TOPLEFT", canvas, "TOPLEFT", TRACK_LEFT, ACTUAL_TRACK_TOP)
    actualBG:SetPoint("BOTTOMRIGHT", canvas, "TOPRIGHT", -TRACK_RIGHT_PAD, ACTUAL_TRACK_TOP - ACTUAL_TRACK_H)

    -- 播放头
    win.playhead = canvas:CreateTexture(nil, "OVERLAY")
    win.playhead:SetWidth(2)
    win.playhead:SetColorTexture(unpack(COLORS.playhead))

    win.noPlanLabel = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.noPlanLabel:SetPoint("TOPLEFT", canvas, "TOPLEFT", TRACK_LEFT + 80, PLAN_TRACK_TOP - 12)
    win.noPlanLabel:SetText(Loc("CAST_REPLAY_NO_PLAN", "录制时的方案已不存在，仅显示实际施法"))
    win.noPlanLabel:Hide()

    -- 底部控制条
    win.playBtn = T.CreateButton(right, { width = 80, height = 26 })
    win.playBtn:SetText(Loc("CAST_REPLAY_PLAY", "播放"))
    win.playBtn:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -10)
    win.playBtn:SetScript("OnClick", function()
        if state.record then
            T.CastReplay:TogglePlay()
        end
    end)

    win.speedBtn = T.CreateButton(right, { width = 70, height = 26 })
    win.speedBtn:SetText(Loc("CAST_REPLAY_SPEED", "速度") .. " 1x")
    win.speedBtn:SetPoint("LEFT", win.playBtn, "RIGHT", 8, 0)
    win.speedBtn:SetScript("OnClick", function()
        state.speedIndex = state.speedIndex % #SPEED_CYCLE + 1
        local sp = SPEED_CYCLE[state.speedIndex]
        T.CastReplay:SetSpeed(sp)
        win.speedBtn:SetText(Loc("CAST_REPLAY_SPEED", "速度") .. " " .. tostring(sp) .. "x")
    end)

    win.timeLabel = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.timeLabel:SetPoint("LEFT", win.speedBtn, "RIGHT", 14, 0)
    win.timeLabel:SetText("0:00 / 0:00")

    win.filterBtn = T.CreateButton(right, { width = 100, height = 26 })
    win.filterBtn:SetText(Loc("CAST_REPLAY_FILTER", "技能筛选"))
    win.filterBtn:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -10)
    win.filterBtn:SetScript("OnClick", function()
        if not state.record then
            return
        end
        EnsureFilterWindow()
        if filterWin:IsShown() then
            filterWin:Hide()
        else
            filterWin:Show()
            GUI.RenderFilter()
        end
    end)

    win:HookScript("OnHide", function()
        if filterWin then
            filterWin:Hide()
        end
    end)

    -- 订阅回放引擎刷新播放头
    replaySubID = T.CastReplay:Subscribe(function()
        UpdatePlayhead()
    end)
end

--=== 公开接口 ===--

function GUI:Open()
    if not win then
        BuildWindow()
    end
    win:Show()
    GUI.RenderList()
    -- 默认选中最近一场
    local records = T.CastRecorder and T.CastRecorder:GetRecords() or {}
    if records[1] and not state.record then
        SelectRecord(1)
    elseif state.recordIndex then
        RenderTimeline()
    end
end

function GUI:Close()
    if win then
        win:Hide()
    end
end

function GUI:Toggle()
    if win and win:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

end)
