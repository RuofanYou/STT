local T, _, L = unpack(select(2, ...))

local SyncButton = {
    busy = false,
}

T.SemanticTimelineSyncButton = SyncButton

function SyncButton:GetDefaultText()
    if self.deps and type(self.deps.getDefaultText) == "function" then
        return self.deps.getDefaultText()
    end
    return L["同步方案"] or "同步方案"
end

function SyncButton:Bind(button, deps)
    self.button = button
    self.deps = deps or {}
    self.busy = false
    self:ResetText()
end

function SyncButton:IsBusy()
    return self.busy == true
end

function SyncButton:CancelResetTimer()
    local timer = self.resetTimer
    if timer and timer.Cancel then
        timer:Cancel()
    end
    self.resetTimer = nil
end

function SyncButton:ResetText()
    if self.button then
        self.button:SetText(self:GetDefaultText())
    end
end

function SyncButton:RefreshOwner()
    if self.deps and type(self.deps.refresh) == "function" then
        self.deps.refresh()
    end
end

function SyncButton:ScheduleReset()
    self:CancelResetTimer()
    if C_Timer and C_Timer.NewTimer then
        self.resetTimer = C_Timer.NewTimer(1.2, function()
            self.resetTimer = nil
            self:ResetText()
            self:RefreshOwner()
        end)
    else
        self:ResetText()
        self:RefreshOwner()
    end
end

function SyncButton:SetStatus(status, sent, total)
    if not self.button then
        return
    end
    self:CancelResetTimer()
    if status == "sending" or status == "in_progress" then
        self.busy = true
        if type(sent) == "number" and type(total) == "number" and total > 0 then
            self.button:SetText(string.format("同步中 %d/%d", sent, total))
        else
            self.button:SetText("同步中...")
        end
        self:RefreshOwner()
    elseif status == "complete" then
        self.busy = false
        self.button:SetText("同步完成")
        self:RefreshOwner()
        self:ScheduleReset()
    elseif status == "timeout" then
        self.busy = false
        self.button:SetText("同步超时")
        self:RefreshOwner()
        self:ScheduleReset()
    elseif status == "failed" then
        self.busy = false
        self.button:SetText("同步失败")
        self:RefreshOwner()
        self:ScheduleReset()
    else
        self.busy = false
        self:ResetText()
        self:RefreshOwner()
    end
end

function SyncButton:RefreshEnabled(isPersonalTab)
    if not self.button then
        return
    end
    self.button:SetEnabled(not isPersonalTab and not self.busy)
    local tooltip = nil
    if isPersonalTab then
        if self.deps and type(self.deps.getPersonalTooltip) == "function" then
            tooltip = self.deps.getPersonalTooltip()
        else
            tooltip = L["个人方案不支持同步"] or "个人方案不支持同步"
        end
    elseif self.busy then
        if self.deps and type(self.deps.getBusyTooltip) == "function" then
            tooltip = self.deps.getBusyTooltip()
        else
            tooltip = "当前方案正在同步"
        end
    end
    if self.deps and type(self.deps.setTooltip) == "function" then
        self.deps.setTooltip(self.button, tooltip)
    end
end
