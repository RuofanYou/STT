-- screen_reminder/preview.lua
-- 顶部预览区：只渲染"当前选中"的一条 indicator。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("screenReminder.enabled", function()

local Schema = T.ScreenReminderSchema
local Preview = {}
T.ScreenReminderPreview = Preview

local function GetIndicatorModule(kind)
    return T.ScreenReminderIndicators and T.ScreenReminderIndicators[kind]
end

local TEST_CTX = {
    text = "测试文案",
    spellID = 116014,
    spellIcon = 538040,
    severity = "normal",
    phase = "p1",
}

local function GetPreviewDuration(ind)
    local duration = Schema and Schema.ResolveIndicatorLeadTime and Schema.ResolveIndicatorLeadTime(ind) or (tonumber(ind and ind.leadTimeSec) or 3)
    return math.max(0.1, duration)
end

local function GetPreviewTimingKey(ind)
    return string.format("%s/%.1f/%.1f/%s",
        tostring(ind and ind.leadTimeMode or "global"),
        GetPreviewDuration(ind),
        tonumber(ind and ind.lingerSec) or 0,
        tostring(not ind or ind.lingerFadeEnabled ~= false))
end

function Preview:Create(parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(opts.width or 516, opts.height or 140)
    if opts.point then frame:SetPoint(unpack(opts.point)) end

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
        frame:SetBackdropBorderColor(0.4, 0.35, 0.18, 0.9)
    end

    -- 标题
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -6)
    title:SetText(L["SR_PREVIEW"] or "预览")

    -- 控制按钮（用 ASCII 字母，避免 WoW 字体不识别的 Unicode 符号）
    local playBtn = T.CreateActionButton(frame, {
        width = 26, height = 20,
        point = { "TOPRIGHT", frame, "TOPRIGHT", -60, -4 },
        textFn = function() return L["SR_PLAY"] or "Play" end,
        onClick = function() Preview:Play() end,
    })
    local pauseBtn = T.CreateActionButton(frame, {
        width = 30, height = 20,
        point = { "TOPRIGHT", frame, "TOPRIGHT", -22, -4 },
        textFn = function() return L["SR_PAUSE"] or "Pause" end,
        onClick = function() Preview:Pause() end,
    })

    -- 渲染容器（indicator 实例的父）
    frame.stage = CreateFrame("Frame", nil, frame)
    frame.stage:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.stage:SetSize(opts.width or 516, (opts.height or 140) - 30)

    -- 空状态提示
    frame.emptyHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.emptyHint:SetPoint("CENTER", frame, "CENTER", 0, -8)
    frame.emptyHint:SetText(L["SR_PREVIEW_EMPTY"] or "暂无指示器，请新建一条")
    frame.emptyHint:Hide()

    self.frame = frame
    self.paused = false
    return frame
end

function Preview:DestroyCurrent()
    if self.currentRecord then
        local module = GetIndicatorModule(self.currentRecord.kind)
        if module then
            module.Release(self.currentRecord.instance)
        end
        self.currentRecord = nil
    end
    if self.frame and self.frame.cycleTicker then
        self.frame.cycleTicker:Cancel()
        self.frame.cycleTicker = nil
    end
end

function Preview:ShowIndicator(ind)
    self:DestroyCurrent()
    if not ind or not self.frame then
        if self.frame then self.frame.emptyHint:Show() end
        return
    end
    local module = GetIndicatorModule(ind.kind)
    if not module then
        self.frame.emptyHint:Show()
        return
    end
    self.frame.emptyHint:Hide()

    local instance = module.Acquire(self.frame.stage)
    instance:SetData(ind)
    -- 预览忽略 indicator.anchor，统一锚到 stage 中心
    instance.frame:ClearAllPoints()
    instance.frame:SetPoint("CENTER", self.frame.stage, "CENTER", 0, 0)

    local record = { kind = ind.kind, instance = instance, def = ind }
    self.currentRecord = record

    self:StartCycle()
end

function Preview:StartCycle()
    local record = self.currentRecord
    if not record then return end
    if self.frame and self.frame.cycleTicker then
        self.frame.cycleTicker:Cancel()
        self.frame.cycleTicker = nil
    end
    local function spawn()
        if self.paused then return end
        record.instance:Stop()
        record.instance:SetData(record.def)
        record.instance.lingerSec = math.max(0, tonumber(record.def and record.def.lingerSec) or 0)
        record.instance.lingerFadeEnabled = not record.def or record.def.lingerFadeEnabled ~= false
        record.instance.frame:ClearAllPoints()
        record.instance.frame:SetPoint("CENTER", self.frame.stage, "CENTER", 0, 0)
        record.instance:SetOnFinish(function()
            if self.frame and self.frame.cycleTicker then
                self.frame.cycleTicker:Cancel()
            end
            self.frame.cycleTicker = C_Timer.NewTimer(0.5, function()
                spawn()
            end)
        end)
        record.instance:Start(TEST_CTX, GetPreviewDuration(record.def))
    end
    spawn()
end

function Preview:Refresh()
    if self.currentRecord and self.currentRecord.def then
        -- 重新读取 def（GUI 已经写过 DB），刷新样式
        local ind = Schema and Schema.GetIndicator(self.currentRecord.def.id)
        if ind then
            local oldTiming = GetPreviewTimingKey(self.currentRecord.def)
            local newTiming = GetPreviewTimingKey(ind)
            self.currentRecord.def = ind
            self.currentRecord.instance:SetData(ind)
            self.currentRecord.instance.lingerSec = math.max(0, tonumber(ind.lingerSec) or 0)
            self.currentRecord.instance.lingerFadeEnabled = ind.lingerFadeEnabled ~= false
            self.currentRecord.instance:Refresh()
            if oldTiming ~= newTiming and not self.paused then
                self:StartCycle()
            end
        end
    end
end

function Preview:Pause()
    self.paused = true
    if self.currentRecord then
        self.currentRecord.instance:Stop()
    end
    if self.frame and self.frame.cycleTicker then
        self.frame.cycleTicker:Cancel()
        self.frame.cycleTicker = nil
    end
end

function Preview:Play()
    self.paused = false
    self:StartCycle()
end

function Preview:OnIndicatorSelected(id)
    local ind = Schema and Schema.GetIndicator(id)
    self:ShowIndicator(ind)
end

end)
