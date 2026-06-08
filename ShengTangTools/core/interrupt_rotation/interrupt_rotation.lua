local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("interruptRotation.enabled", function()

local IR = T.ModuleLoader:NewModule({
    name = "InterruptRotation",
    dbKey = "interruptRotation.enabled",
    defaultEnabled = false,
    combatUnsafe = true,
})

T.InterruptRotation = IR

local SPELLCAST_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

local function Debug(fmt, ...)
    if C and C.DB and C.DB.debugMode == true and T.debug then
        T.debug(string.format("[IR] " .. fmt, ...))
    end
end

local function EnsureInterrupts(self)
    self.Interrupts = self.Interrupts or {}
    return self.Interrupts
end

local function GetUIStyle()
    local db = C and C.DB and C.DB.interruptRotation
    if db and db.uiStyle == "card" then
        return "card"
    end
    return "banner"
end

T.GetInterruptRotationUIStyle = GetUIStyle

local DisplayEdit = T.InterruptRotationDisplayEdit or {}
T.InterruptRotationDisplayEdit = DisplayEdit

local function GetDisplayController(style)
    if style == "card" then
        return T.InterruptRotationView
    end
    return T.InterruptRotationBanner
end

local function ForEachDisplayController(callback)
    if T.InterruptRotationBanner then
        callback(T.InterruptRotationBanner)
    end
    if T.InterruptRotationView then
        callback(T.InterruptRotationView)
    end
end

function DisplayEdit:IsLocked()
    local unlocked = false
    ForEachDisplayController(function(controller)
        if controller.IsLocked and not controller:IsLocked() then
            unlocked = true
        end
    end)
    return not unlocked
end

function DisplayEdit:LockAll(silent)
    ForEachDisplayController(function(controller)
        if controller.SetLocked then
            controller:SetLocked(true, silent)
        end
    end)
end

function DisplayEdit:SetLocked(locked)
    if locked then
        self:LockAll(false)
        return
    end
    self:LockAll(true)
    local controller = GetDisplayController(GetUIStyle())
    if controller and controller.SetLocked then
        controller:SetLocked(false, false)
    end
end

function DisplayEdit:ResetPosition()
    local controller = GetDisplayController(GetUIStyle())
    if controller and controller.ResetPosition then
        controller:ResetPosition()
    end
end

function DisplayEdit:OnStyleChanged(style)
    local wasUnlocked = not self:IsLocked()
    if not wasUnlocked then
        return
    end
    self:LockAll(true)
    local controller = GetDisplayController(style or GetUIStyle())
    if controller and controller.SetLocked then
        controller:SetLocked(false, false)
    end
end

local function SyncViewAssignment(interrupts)
    if not T.InterruptRotationView then
        return
    end
    if GetUIStyle() ~= "card" then
        T.InterruptRotationView:Hide()
        return
    end
    T.InterruptRotationView:Rebuild(interrupts and interrupts.myTable or {}, interrupts and interrupts.myKick or 0, interrupts and interrupts.max or 0)
    T.InterruptRotationView:OnCastChanged(interrupts and interrupts.castCount or 1)
end

local function SyncMacroAssignment(interrupts)
    if T.InterruptRotationMacro and T.InterruptRotationMacro.ApplyAssignment then
        T.InterruptRotationMacro:ApplyAssignment(interrupts)
    end
end

local function PlayCardSelfSound(interrupts)
    if GetUIStyle() ~= "card" then
        return
    end
    if tonumber(interrupts and interrupts.castCount) ~= tonumber(interrupts and interrupts.myKick) then
        return
    end
    if T.InterruptRotationBanner and T.InterruptRotationBanner.PlaySelfSound then
        T.InterruptRotationBanner:PlaySelfSound()
    end
end

local function ResetInterruptTable(self)
    local interrupts = EnsureInterrupts(self)
    interrupts.assignTable = {}
    interrupts.myID = 0
    interrupts.myKick = 0
    interrupts.myTrackedID = 0
    interrupts.castCount = 1
    interrupts.disabled = false
    interrupts.max = 0
    interrupts.myTable = {}
    return interrupts
end

local function CancelTimer(self)
    if self._resetTimer and self._resetTimer.Cancel then
        self._resetTimer:Cancel()
    end
    self._resetTimer = nil
end

local function EnsureBossEnabled(encounterID)
    if not (C and C.DB and C.DB.interruptRotation) then
        return true
    end
    local bossEnabled = C.DB.interruptRotation.bossEnabled
    if type(bossEnabled) ~= "table" then
        C.DB.interruptRotation.bossEnabled = {}
        bossEnabled = C.DB.interruptRotation.bossEnabled
    end
    local key = tostring(encounterID)
    if bossEnabled[key] == nil then
        bossEnabled[key] = true
    end
    return bossEnabled[key] ~= false
end

local function HideBossOverlay()
    if T.InterruptRotationBossOverlay and T.InterruptRotationBossOverlay.Hide then
        T.InterruptRotationBossOverlay:Hide()
    end
end

local function IsTopLevelBlock(line)
    return type(line) == "string" and line:match("^%[[^%[%]]+%]$") ~= nil
end

local function SplitAssignmentLine(line)
    local colon = line:find(":", 1, true)
    local colonLen = 1
    local cnColon = line:find("：", 1, true)
    if cnColon and (not colon or cnColon < colon) then
        colon = cnColon
        colonLen = #"："
    end
    if not colon then
        return nil
    end
    return strtrim(line:sub(colon + colonLen))
end

local function RegisterUnitEventSafe(frame, eventName, units)
    if type(units) ~= "table" or #units == 0 then
        return
    end
    frame:RegisterUnitEvent(eventName, unpack(units))
end

local function BuildSlotAliasMap(source)
    if not (T.STNTemplate and T.STNTemplate.PreprocessText) then
        return nil
    end
    local info = T.STNTemplate.PreprocessText(tostring(source or ""))
    if type(info) ~= "table" or type(info.slots) ~= "table" then
        return nil
    end
    return info.slots
end

local function ResolveInterruptName(token, slots)
    local name = strtrim(tostring(token or ""))
    if name == "" then
        return ""
    end
    local slotValue = type(slots) == "table" and slots[name] or nil
    if slotValue and slotValue ~= "" and T.STNTemplate and T.STNTemplate.ResolveSlotAtRuntime then
        local resolved = T.STNTemplate.ResolveSlotAtRuntime(slotValue)
        if type(resolved) == "table" then
            resolved = resolved[1]
        end
        if type(resolved) == "string" and resolved ~= "" then
            return resolved
        end
    end
    return name
end

local function AddInterruptNameCandidate(candidates, value)
    local text = strtrim(tostring(value or ""))
    if text == "" then
        return
    end
    candidates[#candidates + 1] = text
    for part in text:gmatch("[^,%s]+") do
        local name = strtrim(part)
        if name ~= "" and name ~= text then
            candidates[#candidates + 1] = name
        end
    end
end

local function BuildInterruptAssignmentEntry(token, slots)
    local rawName = strtrim(tostring(token or ""))
    if rawName == "" then
        return nil
    end

    local slotValue = type(slots) == "table" and slots[rawName] or nil
    local displayName = ResolveInterruptName(rawName, slots)
    local candidates = {}
    AddInterruptNameCandidate(candidates, rawName)
    AddInterruptNameCandidate(candidates, displayName)
    AddInterruptNameCandidate(candidates, slotValue)
    return {
        displayName = displayName,
        candidates = candidates,
    }
end

local function NormalizePlayerName(name)
    name = strtrim(tostring(name or ""))
    if name == "" then
        return ""
    end
    if Ambiguate then
        name = Ambiguate(name, "short") or name
    end
    return strtrim(name):gsub("%s+", "")
end

local function IsPlayerAssignmentCandidate(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    if UnitIsUnit(name, "player") then
        return true
    end

    local playerName = UnitFullName and UnitFullName("player") or UnitName("player")
    if NormalizePlayerName(name) == NormalizePlayerName(playerName) then
        return true
    end

    local nickname = C and C.DB and C.DB.mynickname or ""
    return nickname ~= "" and NormalizePlayerName(name) == NormalizePlayerName(nickname)
end

local function IsPlayerAssignmentEntry(entry)
    if type(entry) ~= "table" or type(entry.candidates) ~= "table" then
        return false
    end
    for _, name in ipairs(entry.candidates) do
        if IsPlayerAssignmentCandidate(name) then
            return true
        end
    end
    return false
end

local function ResolveEncounterDifficulty(handler, ...)
    local count = select("#", ...)
    if handler and type(handler.difficultyIDs) == "table" then
        for index = 1, count do
            local rawValue = select(index, ...)
            local value = tonumber(rawValue)
            if value and handler.difficultyIDs[value] == true then
                return value
            end
        end
    end
    local rawDifficultyID = select(2, ...)
    return tonumber(rawDifficultyID)
end

function IR:OnRegister()
    self._handlers = self._handlers or {}
    self._handlerOrder = self._handlerOrder or {}
end

function IR:EnsureFrames()
    if not self._eventFrame then
        self._eventFrame = CreateFrame("Frame")
        self._eventFrame:SetScript("OnEvent", function(_, eventName, ...)
            self:OnEvent(eventName, ...)
        end)
    end
    if not self._encounterFrame then
        self._encounterFrame = CreateFrame("Frame")
        self._encounterFrame:SetScript("OnEvent", function(_, eventName, unit, ...)
            self:OnEncounterEvent(eventName, unit, ...)
        end)
    end
end

function IR:OnEnable(reason)
    self:EnsureFrames()
    self._eventFrame:RegisterEvent("PLAYER_LOGIN")
    self._eventFrame:RegisterEvent("ENCOUNTER_START")
    self._eventFrame:RegisterEvent("ENCOUNTER_END")
    if T.InterruptRotationMacro and T.InterruptRotationMacro.SetAutoRefreshEnabled then
        T.InterruptRotationMacro:SetAutoRefreshEnabled(true)
    end
    self:RegisterPlanHooks()
    self:RefreshEncounterEventRegistration()
    self:ReadCurrentInterruptBlock("enable")
end

function IR:OnDisable(reason)
    CancelTimer(self)
    if self._eventFrame then
        self._eventFrame:UnregisterAllEvents()
    end
    if self._encounterFrame then
        self._encounterFrame:UnregisterAllEvents()
    end
    if T.InterruptRotationMacro and T.InterruptRotationMacro.SetAutoRefreshEnabled then
        T.InterruptRotationMacro:SetAutoRefreshEnabled(false)
    end
    if self.Interrupts then
        wipe(self.Interrupts)
    end
    if T.InterruptRotationView then
        T.InterruptRotationView:Hide()
    end
    HideBossOverlay()
    self._activeEncounterID = nil
    self._activeHandler = nil
end

function IR:RegisterPlanHooks()
    if not (T.Note and self.RegisterHook) then
        return
    end
    self:RegisterHook(T.Note, "UpdatePlan", "OnPlanMutation")
    self:RegisterHook(T.Note, "UpsertSemanticBossPlan", "OnPlanMutation")
    self:RegisterHook(T.Note, "SetActivePlan", "OnPlanMutation")
    if T.events and not self._bossSelectionHooked then
        self._bossSelectionHooked = true
        T.events:Register("STT_BOSS_SELECTION_CHANGED", self, function(owner)
            owner:OnBossSelectionChanged()
        end)
    end
end

function IR:RegisterEncounter(encounterID, handler)
    local normalizedID = tonumber(encounterID)
    if not normalizedID or type(handler) ~= "table" then
        return false
    end
    handler.encounterID = normalizedID
    self._handlers = self._handlers or {}
    self._handlerOrder = self._handlerOrder or {}
    if not self._handlers[normalizedID] then
        self._handlerOrder[#self._handlerOrder + 1] = normalizedID
    end
    self._handlers[normalizedID] = handler
    EnsureBossEnabled(normalizedID)
    if self.enabled and self._encounterFrame then
        self:RefreshEncounterEventRegistration()
    end
    return true
end

function IR:GetAllBossUnits()
    local seen = {}
    local units = {}
    for _, encounterID in ipairs(self._handlerOrder or {}) do
        local handler = self._handlers and self._handlers[encounterID]
        for _, unit in ipairs((handler and handler.bossUnits) or {}) do
            if type(unit) == "string" and unit ~= "" and not seen[unit] then
                seen[unit] = true
                units[#units + 1] = unit
            end
        end
    end
    return units
end

function IR:RefreshEncounterEventRegistration()
    self:EnsureFrames()
    self._encounterFrame:UnregisterAllEvents()
    local units = self:GetAllBossUnits()
    RegisterUnitEventSafe(self._encounterFrame, "UNIT_SPELLCAST_START", units)
    RegisterUnitEventSafe(self._encounterFrame, "UNIT_SPELLCAST_STOP", units)
    RegisterUnitEventSafe(self._encounterFrame, "UNIT_SPELLCAST_INTERRUPTED", units)
    self._encounterFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
end

function IR:GetCurrentStartNumber()
    if self._activeHandler and self._activeHandler.startNumber ~= nil then
        return self._activeHandler.startNumber
    end
    local semantic = T.SemanticTimeline
    local bundle = semantic and semantic.GetCurrentPlanBundle and semantic:GetCurrentPlanBundle({ allowActiveFallback = false }) or nil
    local bossKey = bundle and bundle.bossKey or nil
    local encounterID = type(bossKey) == "table" and tonumber(bossKey.encounterID) or nil
    local handler = encounterID and self._handlers and self._handlers[encounterID] or nil
    if handler and handler.startNumber ~= nil then
        return handler.startNumber
    end
    return 0
end

function IR:ReadCurrentInterruptBlock(cause)
    local startNumber = self:GetCurrentStartNumber()
    return self:ReadInterruptBlock(startNumber)
end

function IR:OnPlanMutation()
    if not self.enabled then
        return
    end
    self:ReadCurrentInterruptBlock("plan_mutation")
end

function IR:OnBossSelectionChanged()
    if not self.enabled then
        return
    end
    self:ReadCurrentInterruptBlock("boss_selection_changed")
end

function IR:OnEvent(eventName, ...)
    if eventName == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            if self.enabled then
                self:ReadCurrentInterruptBlock("player_login")
            end
        end)
    elseif eventName == "ENCOUNTER_START" then
        self:OnEncounterStart(...)
    elseif eventName == "ENCOUNTER_END" then
        self:OnEncounterEnd(...)
    end
end

function IR:OnEncounterStart(encounterID, ...)
    local normalizedID = tonumber(encounterID)
    local handler = normalizedID and self._handlers and self._handlers[normalizedID]
    local difficultyID = ResolveEncounterDifficulty(handler, ...)
    local bossEnabled = handler and EnsureBossEnabled(normalizedID) or false
    if handler and type(handler.difficultyIDs) == "table" and handler.difficultyIDs[difficultyID] ~= true then
        HideBossOverlay()
        self._activeEncounterID = nil
        self._activeHandler = nil
        return
    end
    if not handler or not bossEnabled then
        HideBossOverlay()
        self._activeEncounterID = nil
        self._activeHandler = nil
        return
    end
    self._activeEncounterID = normalizedID
    self._activeHandler = handler
    self:RefreshEncounterEventRegistration()
    self:ReadInterruptBlock(handler.startNumber or 0)
    local interrupts = self.Interrupts or {}
    if tonumber(interrupts.myID) and tonumber(interrupts.myID) > 0 then
        Debug(
            "encounter_start_active encounterID=%s difficultyID=%s startNumber=%s myID=%s myTrackedID=%s myKick=%s max=%s",
            tostring(normalizedID),
            tostring(difficultyID),
            tostring(handler.startNumber or 0),
            tostring(interrupts.myID),
            tostring(interrupts.myTrackedID),
            tostring(interrupts.myKick),
            tostring(interrupts.max)
        )
    end
    if type(handler.OnEncounterStart) == "function" then
        local ok, err = pcall(handler.OnEncounterStart, handler, self, normalizedID, ...)
        if not ok then
            Debug("handler start failed encounter=%s err=%s", tostring(normalizedID), tostring(err))
        end
    end
end

function IR:OnEncounterEnd()
    local handler = self._activeHandler
    if handler and type(handler.OnEncounterEnd) == "function" then
        local ok, err = pcall(handler.OnEncounterEnd, handler, self)
        if not ok then
            Debug("handler end failed encounter=%s err=%s", tostring(self._activeEncounterID), tostring(err))
        end
    end
    CancelTimer(self)
    self:ResetInterrupts()
    HideBossOverlay()
    self._activeEncounterID = nil
    self._activeHandler = nil
end

function IR:RefreshBossEnabledState()
    if not self._activeEncounterID or not self._activeHandler or not EnsureBossEnabled(self._activeEncounterID) then
        HideBossOverlay()
    end
end

function IR:IsTrackedUnit(unit)
    local interrupts = self.Interrupts
    if not interrupts or interrupts.disabled or not interrupts.myTrackedID or interrupts.myTrackedID == 0 then
        return false
    end
    if unit ~= ("boss" .. tostring(interrupts.myTrackedID)) then
        return false
    end
    return UnitIsEnemy(unit, "player")
end

function IR:OnEncounterEvent(eventName, unit, ...)
    if eventName == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        local handler = self._activeHandler
        if handler and type(handler.OnEngageUnit) == "function" then
            local ok, err = pcall(handler.OnEngageUnit, handler, self)
            if not ok then
                Debug("engage handler failed encounter=%s err=%s", tostring(self._activeEncounterID), tostring(err))
            end
        end
        return
    end

    if not SPELLCAST_EVENTS[eventName] then
        return
    end

    local handler = self._activeHandler
    if handler and type(handler.ShouldHandleSpellEvent) == "function" then
        local ok, allowed = pcall(handler.ShouldHandleSpellEvent, handler, self, eventName, unit, ...)
        if not ok then
            Debug("spell event gate failed encounter=%s event=%s unit=%s err=%s", tostring(self._activeEncounterID), tostring(eventName), tostring(unit), tostring(allowed))
        elseif allowed == false then
            return
        end
    end

    -- BossOverlay 走宏式顺延候选，但只能在当前启用的 Boss encounter 内响应。
    if self._activeEncounterID and self._activeHandler and EnsureBossEnabled(self._activeEncounterID)
        and T.InterruptRotationBossOverlay and T.InterruptRotationBossOverlay.OnRawSpellEvent then
        T.InterruptRotationBossOverlay:OnRawSpellEvent(eventName, unit)
    end

    local interrupts = self.Interrupts
    local trackedID = interrupts and interrupts.myTrackedID or 0
    local expectedUnit = "boss" .. tostring(trackedID or 0)
    local unitMatched = unit == expectedUnit
    local enemy = unit and UnitIsEnemy(unit, "player") or false
    if not unitMatched or not enemy then
        return
    end

    if eventName == "UNIT_SPELLCAST_START" then
        self:OnCastStart(unit)
        self:ArmResetTimer()
    elseif eventName == "UNIT_SPELLCAST_STOP" then
        self:OnCastStop(unit)
    elseif eventName == "UNIT_SPELLCAST_INTERRUPTED" then
        self:OnInterrupt(unit)
    end
end

function IR:ArmResetTimer()
    CancelTimer(self)
    local delay = tonumber(self._activeHandler and self._activeHandler.resetTimer) or 15
    self._resetTimer = C_Timer.NewTimer(delay, function()
        if self.enabled then
            self:ResetInterrupts()
        end
    end)
end

function IR:ReadInterruptBlock(startNumber)
    local interrupts = ResetInterruptTable(self)
    local source = ""
    if T.SemanticTimeline and T.SemanticTimeline.GetCurrentPlanBundle then
        local bundle = T.SemanticTimeline:GetCurrentPlanBundle({ allowActiveFallback = false })
        source = tostring(bundle and bundle.teamText or "")
    end
    local slots = BuildSlotAliasMap(source)

    local count = tonumber(startNumber) or 0
    local inBlock = false
    for line in tostring(source):gmatch("[^\r\n]+") do
        local trimmed = strtrim(line or "")
        if inBlock then
            if IsTopLevelBlock(trimmed) then
                if trimmed == "[打断]" then
                    -- 有些复制文本会出现空的重复 [打断] 标题，继续读取后面的真实内容。
                else
                    interrupts.myTrackedID = interrupts.myID
                    interrupts.myTable = interrupts.assignTable[interrupts.myID] or {}
                    if tonumber(interrupts.myID) and tonumber(interrupts.myID) > 0 then
                        Debug("block parsed myID=%s myKick=%s max=%s", tostring(interrupts.myID), tostring(interrupts.myKick), tostring(interrupts.max))
                    end
                    SyncViewAssignment(interrupts)
                    SyncMacroAssignment(interrupts)
                    return interrupts
                end
            else
                local namesText = SplitAssignmentLine(trimmed)
                if namesText and namesText ~= "" then
                    local num = 0
                    count = count + 1
                    interrupts.assignTable[count] = interrupts.assignTable[count] or {}
                    for token in namesText:gmatch("%S+") do
                        local entry = BuildInterruptAssignmentEntry(token, slots)
                        if entry and entry.displayName ~= "" then
                            num = num + 1
                            table.insert(interrupts.assignTable[count], entry.displayName)
                            if IsPlayerAssignmentEntry(entry) then
                                interrupts.myID = count
                                interrupts.myKick = num
                            end
                        end
                    end
                    if count == interrupts.myID then
                        interrupts.max = #interrupts.assignTable[count]
                    end
                end
            end
        elseif trimmed == "[打断]" then
            inBlock = true
        end
    end

    if inBlock then
        interrupts.myTrackedID = interrupts.myID
        interrupts.myTable = interrupts.assignTable[interrupts.myID] or {}
    end
    if inBlock and tonumber(interrupts.myID) and tonumber(interrupts.myID) > 0 then
        Debug("block parsed myID=%s myKick=%s max=%s", tostring(interrupts.myID), tostring(interrupts.myKick), tostring(interrupts.max))
    end
    SyncViewAssignment(interrupts)
    SyncMacroAssignment(interrupts)
    return interrupts
end

function IR:ResetInterrupts()
    local interrupts = self.Interrupts
    if not interrupts then
        return
    end
    interrupts.castCount = 1
    interrupts.myTrackedID = interrupts.myID or 0
    if T.InterruptRotationView then
        T.InterruptRotationView:Hide()
    end
end

function IR:OnCastStart(unit)
    local interrupts = self.Interrupts
    if not interrupts or interrupts.disabled or interrupts.myTrackedID == 0 then
        return
    end
    local uiStyle = GetUIStyle()
    if uiStyle == "card" and T.InterruptRotationView then
        T.InterruptRotationView:Show(unit or ("boss" .. tostring(interrupts.myTrackedID)))
        PlayCardSelfSound(interrupts)
    end
    if T.InterruptRotationBanner then
        T.InterruptRotationBanner:Show(interrupts, true)
    end
end

function IR:OnInterrupt()
    local interrupts = self.Interrupts
    if not interrupts or interrupts.disabled or interrupts.myTrackedID == 0 then
        return
    end
    if T.InterruptRotationBanner then
        T.InterruptRotationBanner:Show(interrupts, false, { suppressPrepareCue = true })
    end
end

function IR:OnCastStop()
    local interrupts = self.Interrupts
    if not interrupts or interrupts.disabled or interrupts.myTrackedID == 0 then
        return
    end
    interrupts.castCount = (tonumber(interrupts.castCount) or 1) + 1
    if interrupts.max and interrupts.max > 0 and interrupts.castCount > interrupts.max then
        interrupts.castCount = 1
    end
    if GetUIStyle() == "card" and T.InterruptRotationView then
        T.InterruptRotationView:OnCastChanged(interrupts.castCount)
    end
    if T.InterruptRotationBanner then
        T.InterruptRotationBanner:Show(interrupts, false)
    end
end

function IR:RunTest()
    local player = T.PlayerName or UnitName("player") or "Player"
    local testStepSec = 1.2
    if type(C.DB.interruptRotation) ~= "table" then
        C.DB.interruptRotation = {}
    end
    self.Interrupts = {
        assignTable = {
            [1] = { "P1", player, "P3", "P4" },
        },
        myID = 1,
        myKick = 2,
        myTrackedID = 1,
        castCount = 1,
        disabled = false,
        max = 4,
        myTable = { "P1", player, "P3", "P4" },
    }
    SyncViewAssignment(self.Interrupts)
    if GetUIStyle() == "card" and T.InterruptRotationView then
        T.InterruptRotationView:Show("boss1", testStepSec)
    end
    local db = C and C.DB and C.DB.interruptRotation
    if db and db.bossOverlayEnabled and T.InterruptRotationBossOverlay then
        T.InterruptRotationBossOverlay:Show("boss1", 4 * testStepSec)
    end

    for index = 1, 4 do
        C_Timer.After(index * testStepSec, function()
            if not self.Interrupts then
                return
            end
            self.Interrupts.castCount = index
            if GetUIStyle() == "card" and T.InterruptRotationView then
                T.InterruptRotationView:OnCastChanged(index, testStepSec)
                PlayCardSelfSound(self.Interrupts)
            end
            if T.InterruptRotationBanner then
                T.InterruptRotationBanner:Show(self.Interrupts, index == self.Interrupts.myKick)
            end
        end)
    end
    C_Timer.After(5.3, function()
        if T.InterruptRotationView then
            T.InterruptRotationView:Hide()
        end
        if T.InterruptRotationBossOverlay then
            T.InterruptRotationBossOverlay:Hide()
        end
    end)
end

end)
