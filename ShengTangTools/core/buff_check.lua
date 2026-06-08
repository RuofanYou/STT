local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("buffCheck.enabled", function()

local BuffCheck = T.ModuleLoader:NewModule({
    name = "BuffCheck",
    dbKey = "buffCheck.enabled",
    defaultEnabled = false,
})
T.BuffCheck = BuffCheck

BuffCheck.state = BuffCheck.state or {
    results = {},
    units = {},
    durabilityReports = {
        byFull = {},
        byShort = {},
    },
    pendingAuraUnits = {},
    panelVisible = false,
    autoHideTimer = nil,
    refreshTimer = nil,
    lastBroadcastAt = 0,
    lastDurabilityBroadcastAt = 0,
    lastDurabilityBroadcastPct = nil,
    repairReminder = {
        active = false,
        pendingCombat = false,
        lastToastAt = 0,
        lastPercent = nil,
    },
    readyCheck = {
        active = false,
        shown = false,
        initialScanDone = false,
        source = nil,
        startedAt = 0,
        confirmCount = 0,
        liveUpdatesSuppressed = false,
    },
}

local DURABILITY_EVENT_DELAY = 0.6
local DURABILITY_BROADCAST_COOLDOWN = 5
local DURABILITY_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17 }
local DURABILITY_SLOT_SET = {}
for _, slotID in ipairs(DURABILITY_SLOTS) do
    DURABILITY_SLOT_SET[slotID] = true
end
local DIMENSION_ORDER = {
    "food",
    "flask",
    "rune",
    "vantus",
    "weaponEnchantMain",
    "weaponEnchantOff",
    "durability",
    "ap",
    "stamina",
    "intellect",
    "versatility",
    "mastery",
    "movement",
}
local DIMENSION_TO_LABEL = {
    food = "BUFF_MISSING_FOOD",
    flask = "BUFF_MISSING_FLASK",
    rune = "BUFF_MISSING_RUNE",
    vantus = "BUFF_MISSING_VANTUS",
    weaponEnchantMain = "BUFF_MISSING_OIL_MH",
    weaponEnchantOff = "BUFF_MISSING_OIL_OH",
    durability = "BUFF_MISSING_DURABILITY",
    durabilityUnknown = "BUFF_UNKNOWN_DURABILITY",
    ap = "BUFF_MISSING_RAIDBUFF_AP",
    stamina = "BUFF_MISSING_RAIDBUFF_STAMINA",
    intellect = "BUFF_MISSING_RAIDBUFF_INTELLECT",
    versatility = "BUFF_MISSING_RAIDBUFF_VERSATILITY",
    mastery = "BUFF_MISSING_RAIDBUFF_MASTERY",
    movement = "BUFF_MISSING_RAIDBUFF_MOVEMENT",
}

local function Debug(message)
    if T.debug then
        T.debug("[BuffCheck] " .. tostring(message))
    end
end

local DEBUG_FIELD_ORDER = {
    "scenario",
    "event",
    "panel",
    "mode",
    "unit",
    "total",
    "ready",
    "missing",
    "summary",
    "channel",
    "lineCount",
    "reason",
    "action",
    "enabled",
    "autoShow",
    "leader",
    "raid",
    "source",
    "skippedSecret",
    "force",
    "error",
    "shown",
    "strata",
    "level",
    "pct",
    "slot",
    "critical",
    "merchant",
}

function BuffCheck:DebugEvent(eventName, fields)
    if not (T.debug and C.DB and C.DB.debugMode) then
        return
    end
    local parts = { "[BuffCheck]", tostring(eventName or "Event") }
    local payload = type(fields) == "table" and fields or {}
    for _, key in ipairs(DEBUG_FIELD_ORDER) do
        if payload[key] ~= nil then
            parts[#parts + 1] = string.format("%s=%s", key, tostring(payload[key]))
        end
    end
    T.debug(table.concat(parts, " "))
end

local function CaptureError(err)
    if geterrorhandler then
        local handler = geterrorhandler()
        if type(handler) == "function" then
            pcall(handler, err)
        end
    end
    return tostring(err)
end

local function GetNow()
    return GetTime and GetTime() or 0
end

local function DB()
    C.DB.buffCheck = C.DB.buffCheck or {}
    if STT_DB then
        STT_DB.buffCheck = C.DB.buffCheck
    end
    return C.DB.buffCheck
end

local function Checks()
    local db = DB()
    db.checks = db.checks or {}
    return db.checks
end

local function IsCheckEnabled(checkKey)
    local defaults = C.defaults and C.defaults.buffCheck and C.defaults.buffCheck.checks or {}
    local value = Checks()[checkKey]
    if value == nil then
        return defaults[checkKey] ~= false
    end
    return value == true
end

local function GetCommChannel()
    local home = LE_PARTY_CATEGORY_HOME or 1
    local instance = LE_PARTY_CATEGORY_INSTANCE or 2
    if IsInRaid and IsInRaid(home) then
        return "RAID"
    end
    if IsInRaid and IsInRaid(instance) then
        return "INSTANCE_CHAT"
    end
    if IsInGroup and IsInGroup(home) then
        return "PARTY"
    end
    if IsInGroup and IsInGroup(instance) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function GetUnitFullName(unit)
    local name, realm = UnitFullName(unit)
    if not name or name == "" then
        name = UnitName(unit)
    end
    if not name or name == "" then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function GetShortName(name)
    if not name then
        return ""
    end
    if Ambiguate then
        return Ambiguate(name, "short")
    end
    return tostring(name):gsub("%-.+$", "")
end

local function IsAuraScanBlocked()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, blocked = pcall(C_Secrets.ShouldAurasBeSecret)
        return ok and blocked == true
    end
    return false
end

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value)
end

local function ReadUnitBool(unit, reader, defaultValue)
    if type(reader) ~= "function" then
        return defaultValue
    end
    local ok, value = pcall(reader, unit)
    if not ok or IsSecretValue(value) then
        return defaultValue
    end
    return value
end

local function ReadAura(unit, handler)
    if IsAuraScanBlocked() then
        return false, "secret", 0
    end
    if not (unit and UnitExists(unit) and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return false, "api_unavailable", 0
    end
    local index = 1
    local skippedSecret = 0
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
        if not auraData then
            break
        end
        if IsSecretValue(auraData.spellId) then
            skippedSecret = skippedSecret + 1
        else
            handler(auraData)
        end
        index = index + 1
    end
    return true, nil, skippedSecret
end

local function GetRuneStock()
    local data = BuffCheck.Data or {}
    local stock = 0
    local hasInfinite = false
    if GetItemCount then
        for _, itemID in ipairs(data.RuneItems or {}) do
            stock = stock + (tonumber(GetItemCount(itemID, false, true)) or 0)
        end
        for _, itemID in ipairs(data.InfiniteRuneItems or {}) do
            local count = tonumber(GetItemCount(itemID, false, true)) or 0
            if count > 0 then
                hasInfinite = true
            end
        end
    end
    return stock, hasInfinite
end

local function ClampPercent(value)
    local pct = math.floor((tonumber(value) or 0) + 0.5)
    if pct < 0 then
        pct = 0
    elseif pct > 100 then
        pct = 100
    end
    return pct
end

local function BuildDurabilityData(percent, source, reportedAt, detail)
    local pct = ClampPercent(percent)
    local data = {
        available = true,
        percent = pct,
        ok = pct >= 100,
        source = source or "unknown",
        reportedAt = tonumber(reportedAt) or GetNow(),
    }
    if type(detail) == "table" then
        data.minSlot = detail.minSlot
        data.minCurrent = detail.minCurrent
        data.minMaximum = detail.minMaximum
        data.brokenCount = detail.brokenCount
        data.checkedSlots = detail.checkedSlots
    end
    return data
end

function BuffCheck:GetPlayerDurabilityData()
    if type(GetInventoryItemDurability) ~= "function" then
        return { available = false, source = "player" }
    end
    local minPercent
    local minSlot
    local minCurrent
    local minMaximum
    local checked = 0
    local brokenCount = 0
    for _, slotID in ipairs(DURABILITY_SLOTS) do
        local current, maximum = GetInventoryItemDurability(slotID)
        current = tonumber(current)
        maximum = tonumber(maximum)
        if current and maximum and maximum > 0 then
            checked = checked + 1
            local pct = (current / maximum) * 100
            if not minPercent or pct < minPercent then
                minPercent = pct
                minSlot = slotID
                minCurrent = current
                minMaximum = maximum
            end
            if current <= 0 then
                brokenCount = brokenCount + 1
            end
        end
    end
    if checked == 0 or not minPercent then
        return { available = false, source = "player" }
    end
    return BuildDurabilityData(minPercent, "player", GetNow(), {
        minSlot = minSlot,
        minCurrent = minCurrent,
        minMaximum = minMaximum,
        brokenCount = brokenCount,
        checkedSlots = checked,
    })
end

local function GetWeaponEnchantState(unit)
    if unit ~= "player" or not GetWeaponEnchantInfo then
        return {
            mainHand = { ok = false, expires = 0 },
            offHand = { ok = false, expires = 0 },
            unavailable = unit ~= "player",
        }
    end
    local hasMainHandEnchant, mainHandExpiration, _, mainHandEnchantID, hasOffHandEnchant, offHandExpiration, _, offHandEnchantID = GetWeaponEnchantInfo()
    return {
        mainHand = { ok = hasMainHandEnchant == true, expires = tonumber(mainHandExpiration) or 0, enchantID = mainHandEnchantID },
        offHand = { ok = hasOffHandEnchant == true, expires = tonumber(offHandExpiration) or 0, enchantID = offHandEnchantID },
    }
end

local function EnsureAuraBucket(result)
    result.food = result.food or { ok = false, tier = 0, expires = 0 }
    result.flask = result.flask or { ok = false, tier = 0, expires = 0 }
    result.rune = result.rune or { ok = false, stock = 0, hasInfinite = false }
    result.vantus = result.vantus or { ok = false }
    result.raidBuffs = result.raidBuffs or {}
    result.durability = result.durability or { available = false }
end

function BuffCheck:IsEnabled()
    return DB().enabled == true and C.DB and C.DB.debugMode == true
end

function BuffCheck:GetDurabilityThreshold()
    local pct = tonumber(DB().minDurabilityPct) or 50
    if pct < 0 then
        pct = 0
    elseif pct > 100 then
        pct = 100
    end
    return pct
end

function BuffCheck:GetRepairReminderDB()
    local db = DB()
    db.repairReminder = db.repairReminder or {}
    if db.repairReminder.enabled == nil then
        db.repairReminder.enabled = false
    end
    if db.repairReminder.thresholdPct == nil then
        db.repairReminder.thresholdPct = 25
    end
    if db.repairReminder.criticalPct == nil then
        db.repairReminder.criticalPct = 10
    end
    if db.repairReminder.durationSec == nil then
        db.repairReminder.durationSec = 5
    end
    if db.repairReminder.repeatMinutes == nil then
        db.repairReminder.repeatMinutes = 10
    end
    if db.repairReminder.combatEndReminder == nil then
        db.repairReminder.combatEndReminder = true
    end
    if db.repairReminder.autoRepair == nil then
        db.repairReminder.autoRepair = false
    end
    if db.repairReminder.autoRepairGuildFunds == nil then
        db.repairReminder.autoRepairGuildFunds = true
    end
    if db.repairReminder.autoRepairShowSummary == nil then
        db.repairReminder.autoRepairShowSummary = true
    end
    if db.repairReminder.tts == nil then
        db.repairReminder.tts = false
    end
    return db.repairReminder
end

function BuffCheck:IsRepairReminderEnabled()
    local db = self:GetRepairReminderDB()
    return db.enabled == true
end

function BuffCheck:IsAutoRepairEnabled()
    return self:GetRepairReminderDB().autoRepair == true
end

function BuffCheck:ShouldKeepEventsEnabled()
    return self:IsEnabled() or self:IsRepairReminderEnabled()
end

function BuffCheck:GetRepairReminderThreshold()
    local pct = tonumber(self:GetRepairReminderDB().thresholdPct) or 25
    if pct < 1 then
        pct = 1
    elseif pct > 100 then
        pct = 100
    end
    return pct
end

function BuffCheck:GetRepairReminderCriticalThreshold()
    local pct = tonumber(self:GetRepairReminderDB().criticalPct) or 10
    if pct < 1 then
        pct = 1
    elseif pct > 100 then
        pct = 100
    end
    return pct
end

function BuffCheck:GetRepairReminderDuration()
    local sec = tonumber(self:GetRepairReminderDB().durationSec) or 5
    if sec < 2 then
        sec = 2
    elseif sec > 30 then
        sec = 30
    end
    return sec
end

function BuffCheck:GetRepairReminderRepeatSec()
    local minutes = tonumber(self:GetRepairReminderDB().repeatMinutes) or 10
    if minutes < 1 then
        minutes = 1
    elseif minutes > 60 then
        minutes = 60
    end
    return minutes * 60
end

function BuffCheck:EnsureCommReady()
    if self.state.commReady ~= nil then
        return self.state.commReady == true
    end
    if not T.Comm then
        self.state.commReady = false
        return false
    end
    local ok, err = T.Comm:Register("buffDurability", "durability", function(payload, sender, meta)
        if self:IsEnabled() then
            self:HandleCommPayload(payload, meta and meta.channel, sender)
        end
    end)
    self.state.commReady = ok == true
    if not self.state.commReady then
        self:DebugEvent("CommRegisterFailed", {
            source = "durability",
            summary = tostring(err),
        })
    end
    return self.state.commReady
end

function BuffCheck:StoreDurabilityReport(sender, percent, reportedAt, source)
    if not sender or sender == "" then
        return nil
    end
    local fullName = tostring(sender)
    local shortName = GetShortName(fullName)
    local report = BuildDurabilityData(percent, source or "addon", reportedAt)
    report.unitName = fullName
    report.shortName = shortName
    self.state.durabilityReports = self.state.durabilityReports or { byFull = {}, byShort = {} }
    self.state.durabilityReports.byFull[fullName] = report
    if shortName and shortName ~= "" then
        self.state.durabilityReports.byShort[shortName] = report
    end
    for unitName, result in pairs(self.state.results or {}) do
        if unitName == fullName or GetShortName(unitName) == shortName then
            result.durability = BuildDurabilityData(report.percent, report.source, report.reportedAt)
        end
    end
    return report
end

function BuffCheck:GetDurabilityReport(unitName)
    if not unitName then
        return nil
    end
    local reports = self.state.durabilityReports or {}
    if reports.byFull and reports.byFull[unitName] then
        return reports.byFull[unitName]
    end
    local shortName = GetShortName(unitName)
    if reports.byShort and shortName and reports.byShort[shortName] then
        return reports.byShort[shortName]
    end
    return nil
end

function BuffCheck:GetUnitDurability(unit, unitName)
    if unit == "player" then
        local selfData = self:GetPlayerDurabilityData()
        if selfData.available then
            self:StoreDurabilityReport(unitName or GetUnitFullName("player") or UnitName("player"), selfData.percent, selfData.reportedAt, "player")
        end
        return selfData
    end
    local report = self:GetDurabilityReport(unitName)
    if report then
        return BuildDurabilityData(report.percent, report.source or "addon", report.reportedAt)
    end
    return { available = false, source = "addon" }
end

function BuffCheck:GetDurabilityState(result)
    if not IsCheckEnabled("durability") then
        return "disabled", nil
    end
    local data = result and result.durability
    if not (data and data.available) then
        return "unknown", nil
    end
    local pct = ClampPercent(data.percent)
    if pct < self:GetDurabilityThreshold() then
        return "low", pct
    end
    return "ok", pct
end

function BuffCheck:HasUnknownDurability(result)
    local state = self:GetDurabilityState(result)
    return state == "unknown"
end

function BuffCheck:BroadcastOwnDurability(source, force)
    local localData = self:GetPlayerDurabilityData()
    if localData.available then
        self:StoreDurabilityReport(GetUnitFullName("player") or UnitName("player") or "player", localData.percent, localData.reportedAt, "player")
        if self.UI and self.UI.Refresh then
            self:RequestRefresh(0.05)
        end
    end
    if not localData.available then
        return
    end
    local channel = GetCommChannel()
    if not channel or not self:EnsureCommReady() then
        return
    end
    local now = GetNow()
    if force ~= true then
        local lastPct = self.state.lastDurabilityBroadcastPct
        local lastAt = tonumber(self.state.lastDurabilityBroadcastAt) or 0
        if lastPct == localData.percent and (now - lastAt) < DURABILITY_BROADCAST_COOLDOWN then
            return
        end
    end
    self.state.lastDurabilityBroadcastPct = localData.percent
    self.state.lastDurabilityBroadcastAt = now
    local ok, err = T.Comm:Send("buffDurability", "durability", {
        type = "durability",
        percent = localData.percent,
        reportedAt = math.floor(now),
    }, { target = "group", prio = "NORMAL" })
    if not ok then
        self:DebugEvent("DurabilityBroadcastFailed", {
            source = source or "unknown",
            channel = channel,
            summary = tostring(err),
        })
        return
    end
    self:DebugEvent("DurabilityBroadcast", {
        source = source or "unknown",
        channel = channel,
        summary = tostring(localData.percent) .. "%",
    })
end

function BuffCheck:ShowRepairReminder(data, reason)
    if not (self.UI and self.UI.ShowRepairReminder) then
        return false
    end
    local threshold = self:GetRepairReminderThreshold()
    local pct = data and data.percent
    if not pct then
        return false
    end
    local critical = (tonumber(pct) or 100) <= self:GetRepairReminderCriticalThreshold() or (tonumber(data.brokenCount) or 0) > 0
    self.UI:ShowRepairReminder({
        percent = pct,
        threshold = threshold,
        criticalThreshold = self:GetRepairReminderCriticalThreshold(),
        minSlot = data.minSlot,
        minCurrent = data.minCurrent,
        minMaximum = data.minMaximum,
        brokenCount = data.brokenCount,
        critical = critical,
        durationSec = self:GetRepairReminderDuration(),
    })
    local db = self:GetRepairReminderDB()
    if db.tts == true and T.PlayTTS then
        local text = string.format(L["BUFF_REPAIR_REMINDER_TTS_LOW"] or "装备耐久偏低，当前%d%%", pct)
        pcall(T.PlayTTS, text)
    end
    self:DebugEvent("RepairReminderShown", {
        source = reason or "unknown",
        pct = tostring(pct),
        slot = tostring(data.minSlot or "none"),
        critical = critical and "true" or "false",
    })
    return true
end

function BuffCheck:EvaluateRepairReminder(reason, force)
    local state = self.state.repairReminder
    if not state then
        return
    end
    if not self:IsRepairReminderEnabled() then
        state.active = false
        state.pendingCombat = false
        state.lastPercent = nil
        if self.UI and self.UI.HideRepairReminder then
            self.UI:HideRepairReminder()
        end
        return
    end

    local data = self:GetPlayerDurabilityData()
    if not (data and data.available) then
        return
    end
    local threshold = self:GetRepairReminderThreshold()
    local pct = data.percent
    if pct >= threshold then
        state.active = false
        state.pendingCombat = false
        state.lastPercent = pct
        if self.UI and self.UI.HideRepairReminder then
            self.UI:HideRepairReminder()
        end
        return
    end

    local inCombat = InCombatLockdown and InCombatLockdown()
    if inCombat then
        state.active = true
        state.pendingCombat = true
        state.lastPercent = pct
        self:DebugEvent("RepairReminderDeferred", {
            source = reason or "unknown",
            pct = tostring(pct),
        })
        return
    end

    local now = GetNow()
    local crossed = state.active ~= true
    local shouldShow = force == true or crossed or state.pendingCombat == true or (now - (tonumber(state.lastToastAt) or 0)) >= self:GetRepairReminderRepeatSec()
    state.active = true
    state.pendingCombat = false
    state.lastPercent = pct
    if shouldShow and self:ShowRepairReminder(data, reason) then
        state.lastToastAt = now
    end
end

function BuffCheck:GetAutoRepairCostText(cost)
    cost = tonumber(cost) or 0
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinText then
        return C_CurrencyInfo.GetCoinText(cost)
    end
    if GetMoneyString then
        return GetMoneyString(cost, true)
    end
    return tostring(cost)
end

function BuffCheck:TryAutoRepair(reason)
    local db = self:GetRepairReminderDB()
    if db.autoRepair ~= true then
        return false
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        self:DebugEvent("AutoRepairSkipped", { source = reason or "unknown", reason = "shift" })
        return false
    end
    if not (CanMerchantRepair and GetRepairAllCost and RepairAllItems) then
        return false
    end
    local okMerchant, canRepairMerchant = pcall(CanMerchantRepair)
    if not okMerchant or canRepairMerchant ~= true then
        return false
    end
    local okCost, repairCost, canRepair = pcall(GetRepairAllCost)
    repairCost = tonumber(repairCost) or 0
    if not okCost or canRepair ~= true or repairCost <= 0 then
        return false
    end

    local useGuildFunds = false
    if db.autoRepairGuildFunds == true and IsInGuild and IsInGuild() and CanGuildBankRepair then
        local okGuild, canGuildRepair = pcall(CanGuildBankRepair)
        useGuildFunds = okGuild and canGuildRepair == true
    end

    local repaired = false
    if useGuildFunds then
        local okGuildRepair = pcall(RepairAllItems, 1)
        local okFallbackRepair = pcall(RepairAllItems)
        repaired = okGuildRepair or okFallbackRepair
    else
        repaired = pcall(RepairAllItems)
    end

    if repaired and db.autoRepairShowSummary == true and T.msg then
        T.msg(string.format(L["DURABILITY_AUTO_REPAIR_SUMMARY"] or "已自动修理：%s", self:GetAutoRepairCostText(repairCost)))
    end
    self:DebugEvent("AutoRepair", {
        source = reason or "unknown",
        cost = tostring(repairCost),
        guild = useGuildFunds and "true" or "false",
        repaired = repaired and "true" or "false",
    })
    return repaired
end

function BuffCheck:HandleCommPayload(payload, channel, sender)
    if type(payload) ~= "table" or payload.type ~= "durability" then
        return
    end
    local percent = tonumber(payload.percent)
    local reportedAt = tonumber(payload.reportedAt)
    if not percent then
        return
    end
    local report = self:StoreDurabilityReport(sender, percent, reportedAt, "addon")
    if not report then
        return
    end
    self:DebugEvent("DurabilityReportReceived", {
        source = channel or "unknown",
        unit = report.shortName or report.unitName,
        summary = tostring(report.percent) .. "%",
    })
    if self.UI and self.UI.IsRaidShown and self.UI:IsRaidShown() then
        self:RequestRefresh(0.05)
    end
end

function BuffCheck:ScanUnit(unit)
    unit = unit or "player"
    if not UnitExists(unit) then
        return nil
    end

    local unitName = GetUnitFullName(unit)
    if not unitName then
        return nil
    end

    local _, className = UnitClass(unit)
    local connected = ReadUnitBool(unit, UnitIsConnected, true)
    local dead = ReadUnitBool(unit, UnitIsDeadOrGhost, false)
    local inRange = ReadUnitBool(unit, UnitInRange, nil)
    local result = {
        unit = unit,
        unitName = unitName,
        shortName = GetShortName(unitName),
        class = className,
        connected = connected ~= false,
        dead = dead == true,
        inRange = inRange,
        lastUpdate = GetTime and GetTime() or 0,
    }
    EnsureAuraBucket(result)

    local data = BuffCheck.Data or {}
    local minFoodTier = tonumber(DB().minFoodTier) or 0
    local minFlaskTier = tonumber(DB().minFlaskTier) or 0
    local ok, reason, skippedSecret = ReadAura(unit, function(auraData)
        local spellID = auraData and auraData.spellId
        if not spellID then
            return
        end
        local expires = tonumber(auraData.expirationTime) or 0
        local foodTier = data.Food and data.Food[spellID]
        if foodTier and foodTier >= minFoodTier and foodTier >= (result.food.tier or 0) then
            result.food = { ok = true, tier = foodTier, expires = expires, spellID = spellID, icon = auraData.icon, name = auraData.name }
        end
        local flaskTier = data.Flask and data.Flask[spellID]
        if flaskTier and flaskTier >= minFlaskTier and flaskTier >= (result.flask.tier or 0) then
            result.flask = { ok = true, tier = flaskTier, expires = expires, spellID = spellID, icon = auraData.icon, name = auraData.name }
        end
        local runeTier = data.Rune and data.Rune[spellID]
        if runeTier then
            result.rune.ok = true
            result.rune.tier = runeTier
            result.rune.expires = expires
            result.rune.spellID = spellID
            result.rune.icon = auraData.icon
            result.rune.name = auraData.name
        end
        if data.Vantus and data.Vantus[spellID] then
            result.vantus = { ok = true, expires = expires, spellID = spellID, icon = auraData.icon, name = auraData.name }
        end
        for _, buff in ipairs(data.RaidBuffs or {}) do
            if buff.spells and buff.spells[spellID] then
                result.raidBuffs[buff.id] = true
            end
        end
    end)
    if not ok then
        result.unavailableReason = reason
    end
    result.skippedSecretAuraCount = skippedSecret or 0

    if unit == "player" then
        local stock, hasInfinite = GetRuneStock()
        result.rune.stock = stock
        result.rune.hasInfinite = hasInfinite
        if hasInfinite or stock > 0 then
            result.rune.ok = true
        end
    end
    result.weaponEnchant = GetWeaponEnchantState(unit)
    result.durability = self:GetUnitDurability(unit, unitName)

    self.state.results[unitName] = result
    self.state.units[unit] = unitName
    return result
end

function BuffCheck:ScanSafely(scanName, callback, source)
    local ok, result = xpcall(callback, CaptureError)
    if not ok then
        self:DebugEvent("ScanError", {
            action = scanName or "scan",
            source = source or "unknown",
            error = result,
        })
        return nil, result
    end
    return result
end

function BuffCheck:ScanSelf()
    return self:ScanUnit("player")
end

function BuffCheck:ScanGroup()
    if IsInRaid() then
        for index = 1, 40 do
            local unit = "raid" .. index
            if UnitExists(unit) then
                self:ScanUnit(unit)
            end
        end
    elseif IsInGroup() then
        self:ScanSelf()
        for index = 1, 4 do
            local unit = "party" .. index
            if UnitExists(unit) then
                self:ScanUnit(unit)
            end
        end
    else
        self:ScanSelf()
    end
    self:PruneResults()
    self:DebugEvent("GroupScanComplete", {
        total = #self:GetSortedResults(),
        raid = IsInRaid() and "true" or "false",
        leader = UnitIsGroupLeader("player") and "true" or "false",
    })
    Debug("GroupScanComplete count=" .. tostring(#self:GetSortedResults()))
end

function BuffCheck:ScanRaidIfLead()
    self:ScanGroup()
end

function BuffCheck:PruneResults()
    local active = {}
    local activeShort = {}
    if IsInRaid() then
        for index = 1, 40 do
            local unit = "raid" .. index
            local name = UnitExists(unit) and GetUnitFullName(unit)
            if name then
                active[name] = true
                activeShort[GetShortName(name)] = true
            end
        end
    elseif IsInGroup() then
        local playerName = GetUnitFullName("player")
        if playerName then
            active[playerName] = true
            activeShort[GetShortName(playerName)] = true
        end
        for index = 1, 4 do
            local unit = "party" .. index
            local name = UnitExists(unit) and GetUnitFullName(unit)
            if name then
                active[name] = true
                activeShort[GetShortName(name)] = true
            end
        end
    else
        local playerName = GetUnitFullName("player")
        if playerName then
            active[playerName] = true
            activeShort[GetShortName(playerName)] = true
        end
    end
    for name in pairs(self.state.results or {}) do
        if not active[name] then
            self.state.results[name] = nil
        end
    end
    local reports = self.state.durabilityReports or {}
    for name in pairs(reports.byFull or {}) do
        if not active[name] then
            reports.byFull[name] = nil
        end
    end
    for shortName in pairs(reports.byShort or {}) do
        if not activeShort[shortName] then
            reports.byShort[shortName] = nil
        end
    end
end

function BuffCheck:EvaluateMissing(result)
    local missing = {}
    if type(result) ~= "table" then
        return missing
    end
    if not result.connected or result.dead then
        missing.unavailable = true
        return missing
    end
    if result.unavailableReason then
        missing.unavailable = true
        return missing
    end
    if IsCheckEnabled("food") and not (result.food and result.food.ok) then missing.food = true end
    if IsCheckEnabled("flask") and not (result.flask and result.flask.ok) then missing.flask = true end
    if IsCheckEnabled("rune") and not (result.rune and result.rune.ok) then missing.rune = true end
    if IsCheckEnabled("vantus") and not (result.vantus and result.vantus.ok) then missing.vantus = true end
    local weaponUnavailable = result.weaponEnchant and result.weaponEnchant.unavailable
    if not weaponUnavailable and IsCheckEnabled("weaponEnchantMain") and not (result.weaponEnchant and result.weaponEnchant.mainHand and result.weaponEnchant.mainHand.ok) then missing.weaponEnchantMain = true end
    if not weaponUnavailable and IsCheckEnabled("weaponEnchantOff") and not (result.weaponEnchant and result.weaponEnchant.offHand and result.weaponEnchant.offHand.ok) then missing.weaponEnchantOff = true end
    local durabilityState = self:GetDurabilityState(result)
    if durabilityState == "low" then
        missing.durability = true
    elseif durabilityState == "unknown" then
        missing.durabilityUnknown = true
    end
    for _, buff in ipairs((BuffCheck.Data and BuffCheck.Data.RaidBuffs) or {}) do
        if IsCheckEnabled(buff.checkKey) and not (result.raidBuffs and result.raidBuffs[buff.id]) then
            missing[buff.id] = true
        end
    end
    return missing
end

function BuffCheck:HasMissing(result)
    for key, value in pairs(self:EvaluateMissing(result) or {}) do
        if key ~= "unavailable" and key ~= "durabilityUnknown" and value == true then
            return true
        end
    end
    return false
end

function BuffCheck:GetMissingLabels(result)
    local labels = {}
    local missing = self:EvaluateMissing(result)
    for _, key in ipairs(DIMENSION_ORDER) do
        if missing[key] then
            labels[#labels + 1] = L[DIMENSION_TO_LABEL[key]] or DIMENSION_TO_LABEL[key] or key
        end
    end
    return labels
end

function BuffCheck:GetMissingKeyString(result)
    local missing = self:EvaluateMissing(result)
    local keys = {}
    for _, key in ipairs(DIMENSION_ORDER) do
        if missing[key] then
            keys[#keys + 1] = key
        end
    end
    if #keys == 0 then
        return "none"
    end
    return table.concat(keys, ",")
end

function BuffCheck:GetSortedResults()
    local list = {}
    for _, result in pairs(self.state.results or {}) do
        list[#list + 1] = result
    end
    table.sort(list, function(a, b)
        local aMissing = self:HasMissing(a)
        local bMissing = self:HasMissing(b)
        if aMissing ~= bMissing then
            return aMissing
        end
        local aUnknown = self:HasUnknownDurability(a)
        local bUnknown = self:HasUnknownDurability(b)
        if aUnknown ~= bUnknown then
            return aUnknown
        end
        if (a.class or "") ~= (b.class or "") then
            return (a.class or "") < (b.class or "")
        end
        return (a.shortName or a.unitName or "") < (b.shortName or b.unitName or "")
    end)
    return list
end

function BuffCheck:GetSummary(results)
    results = results or self:GetSortedResults()
    local summary = {
        total = 0,
        ready = 0,
        counts = {},
    }
    for _, result in ipairs(results) do
        summary.total = summary.total + 1
        local missing = self:EvaluateMissing(result)
        local hasMissing = false
        for key, value in pairs(missing) do
            if key ~= "unavailable" and value == true then
                summary.counts[key] = (summary.counts[key] or 0) + 1
                if key ~= "durabilityUnknown" then
                    hasMissing = true
                end
            end
        end
        if not hasMissing and missing.unavailable ~= true and missing.durabilityUnknown ~= true then
            summary.ready = summary.ready + 1
        end
    end
    return summary
end

function BuffCheck:BuildSummaryText(results, personal)
    local summary = self:GetSummary(results)
    if summary.total == 0 then
        return personal and (L["BUFF_NO_PERSONAL_DATA"] or "暂无个人数据") or (L["BUFF_NO_RAID_DATA"] or "暂无团队数据")
    end
    local parts = {}
    local order = DIMENSION_ORDER
    if not personal then
        order = {
            "food",
            "flask",
            "rune",
            "vantus",
            "weaponEnchantMain",
            "durability",
            "durabilityUnknown",
            "ap",
            "stamina",
            "intellect",
            "versatility",
            "mastery",
            "movement",
        }
    end
    for _, key in ipairs(order) do
        local count = summary.counts[key] or 0
        if count > 0 then
            parts[#parts + 1] = string.format("%s %d", L[DIMENSION_TO_LABEL[key]] or key, count)
        end
    end
    if #parts == 0 then
        return personal and (L["BUFF_PERSONAL_ALL_OK_SHORT"] or "你已准备就绪") or (L["BUFF_RAID_ALL_OK_SHORT"] or "全团准备就绪")
    end
    if #parts > 4 then
        local short = { parts[1], parts[2], parts[3] }
        short[#short + 1] = string.format(L["BUFF_SUMMARY_MORE"] or "还有 %d 项", #parts - 3)
        parts = short
    end
    if not personal and summary.total > 0 then
        parts[#parts + 1] = string.format("%d/%d", summary.ready, summary.total)
    end
    return table.concat(parts, " · ")
end

function BuffCheck:Refresh()
    if self.UI and self.UI.Refresh then
        self.UI:Refresh()
    end
end

function BuffCheck:RequestRefresh(delay)
    if not (self.UI and self.UI.Refresh) then
        return
    end
    if self.state.refreshTimer then
        return
    end
    self.state.refreshTimer = C_Timer.NewTimer(math.max(0, tonumber(delay) or 0), function()
        self.state.refreshTimer = nil
        self:Refresh()
    end)
end

function BuffCheck:GetReadyCheckState()
    self.state.readyCheck = self.state.readyCheck or {
        active = false,
        shown = false,
        initialScanDone = false,
        source = nil,
        startedAt = 0,
        confirmCount = 0,
        liveUpdatesSuppressed = false,
    }
    return self.state.readyCheck
end

function BuffCheck:ResetReadyCheckSession()
    local session = self:GetReadyCheckState()
    session.active = false
    session.shown = false
    session.initialScanDone = false
    session.source = nil
    session.startedAt = 0
    session.confirmCount = 0
    session.liveUpdatesSuppressed = false
end

function BuffCheck:StartReadyCheckSession(source)
    local session = self:GetReadyCheckState()
    session.active = true
    session.shown = false
    session.initialScanDone = false
    session.source = source or "ready_check"
    session.startedAt = GetNow()
    session.confirmCount = 0
    session.liveUpdatesSuppressed = false
    self:DebugEvent("ReadyCheckSessionStarted", {
        source = session.source,
        raid = IsInRaid() and "true" or "false",
        leader = UnitIsGroupLeader("player") and "true" or "false",
    })
    return session
end

function BuffCheck:IsReadyCheckSessionActive()
    local session = self:GetReadyCheckState()
    return session.active == true
end

function BuffCheck:FinishReadyCheckSession(reason)
    local session = self:GetReadyCheckState()
    if not session.active then
        return
    end
    local summary = self:GetSummary()
    self:DebugEvent("ReadyCheckSessionFinished", {
        source = session.source or "ready_check",
        reason = reason or "finished",
        total = summary.total,
        ready = summary.ready,
    })
    self:ResetReadyCheckSession()
end

function BuffCheck:ShowPersonal(options)
    local opts = type(options) == "table" and options or {}
    if not (opts.force == true) and not self:IsEnabled() and not self.testMode then
        self:DebugEvent("PersonalPanelBlocked", {
            reason = "disabled",
            source = opts.source or "unknown",
            enabled = "false",
        })
        T.msg(L["BUFF_CHECK_DISABLED"] or "团队检查未启用")
        return
    end
    if not self.testMode and opts.skipScan ~= true then
        self:ScanSafely("scan_self", function()
            return self:ScanSelf()
        end, opts.source or "personal")
    end
    if not self.testMode then
        self:BroadcastOwnDurability(opts.source or "personal", false)
    end
    local frame
    if self.UI and self.UI.ShowPersonal then
        local ok, err = xpcall(function()
            frame = self.UI:ShowPersonal()
        end, CaptureError)
        if not ok then
            self:DebugEvent("PersonalPanelError", {
                source = opts.source or "direct",
                error = err,
            })
            T.msg(L["BUFF_PANEL_OPEN_FAILED"] or "团队检查面板打开失败，请查看调试日志")
            return
        end
    end
    self:DebugEvent("PersonalPanelShown", {
        panel = "personal",
        mode = self.testMode and "test" or "live",
        source = opts.source or "direct",
        force = opts.force == true and "true" or "false",
        shown = frame and frame:IsShown() and "true" or "false",
        strata = frame and frame:GetFrameStrata() or "none",
        level = frame and frame:GetFrameLevel() or "none",
    })
    Debug("PersonalPanelShown")
end

function BuffCheck:ShowRaid(options)
    local opts = type(options) == "table" and options or {}
    if not (opts.force == true) and not self:IsEnabled() and not self.testMode then
        self:DebugEvent("RaidPanelBlocked", {
            reason = "disabled",
            source = opts.source or "unknown",
            enabled = "false",
        })
        T.msg(L["BUFF_CHECK_DISABLED"] or "团队检查未启用")
        return
    end
    local frame
    if self.UI and self.UI.ShowRaid then
        local ok, err = xpcall(function()
            frame = self.UI:ShowRaid()
        end, CaptureError)
        if not ok then
            self:DebugEvent("RaidPanelError", {
                source = opts.source or "direct",
                error = err,
            })
            T.msg(L["BUFF_PANEL_OPEN_FAILED"] or "团队检查面板打开失败，请查看调试日志")
            return
        end
    end
    self:DebugEvent("RaidPanelShown", {
        panel = "raid",
        mode = self.testMode and "test" or "live",
        total = #self:GetSortedResults(),
        source = opts.source or "direct",
        force = opts.force == true and "true" or "false",
        shown = frame and frame:IsShown() and "true" or "false",
        strata = frame and frame:GetFrameStrata() or "none",
        level = frame and frame:GetFrameLevel() or "none",
    })
    Debug("RaidPanelShown")
end

function BuffCheck:HideAll()
    if self.UI and self.UI.HideAll then
        self.UI:HideAll()
    end
    if self.state.autoHideTimer and self.state.autoHideTimer.Cancel then
        self.state.autoHideTimer:Cancel()
    end
    self.state.autoHideTimer = nil
end

function BuffCheck:ChatBroadcast()
    local now = GetTime and GetTime() or 0
    if now - (self.state.lastBroadcastAt or 0) < 5 then
        T.msg(L["BUFF_BROADCAST_COOLDOWN"] or "团队检查汇总冷却中")
        return
    end
    self.state.lastBroadcastAt = now
    if next(self.state.results or {}) == nil then
        self:ScanGroup()
    end

    local buckets = {}
    for _, result in ipairs(self:GetSortedResults()) do
        local missing = self:GetMissingLabels(result)
        for _, label in ipairs(missing) do
            buckets[label] = buckets[label] or {}
            buckets[label][#buckets[label] + 1] = result.shortName or result.unitName
        end
    end

    local lines = {}
    for label, names in pairs(buckets) do
        table.sort(names)
        lines[#lines + 1] = string.format("【%s (%d)】%s", label, #names, table.concat(names, ", "))
    end
    table.sort(lines)
    if #lines == 0 then
        lines[1] = L["BUFF_RAID_ALL_OK_SHORT"] or "全团准备就绪"
    end

    local channel = DB().chatBroadcastChannel or "NONE"
    if channel == "RAID_WARNING" and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        T.msg(L["BUFF_RW_NEED_ASSIST"] or "团队警告需要团长或助理权限")
        return
    end
    if channel == "RAID" and not IsInRaid() then
        channel = IsInGroup() and "PARTY" or "NONE"
    end
    if channel == "PARTY" and not IsInGroup() then
        channel = "NONE"
    end

    for _, line in ipairs(lines) do
        if channel == "NONE" then
            T.msg(line)
        else
            SendChatMessage(line, channel)
        end
    end
    self:DebugEvent("BroadcastSummary", {
        channel = channel,
        lineCount = #lines,
        summary = table.concat(lines, " || "),
    })
end

function BuffCheck:RunTest(options)
    local opts = type(options) == "table" and options or {}
    self.testMode = true
    local _, className = UnitClass("player")
    local unitName = GetUnitFullName("player") or T.PlayerName or "player"
    self.state.results = {
        [unitName] = {
            unit = "player",
            unitName = unitName,
            shortName = GetShortName(unitName),
            class = className,
            connected = true,
            dead = false,
            food = { ok = false },
            flask = { ok = false },
            rune = { ok = true, stock = 1 },
            vantus = { ok = false },
            weaponEnchant = { mainHand = { ok = true }, offHand = { ok = false } },
            durability = { available = true, percent = 41, source = "test" },
            raidBuffs = { ap = true, stamina = true, intellect = false, versatility = true, mastery = true, movement = true },
            lastUpdate = GetTime and GetTime() or 0,
        },
    }
    local result = self.state.results[unitName]
    self.state.testRenderLogged = false
    self:DebugEvent("TestDataReady", {
        scenario = "personal",
        unit = result.shortName or result.unitName,
        total = 1,
        source = opts.source or "direct",
        missing = self:GetMissingKeyString(result),
        summary = self:BuildSummaryText({ result }, true),
    })
    self:ShowPersonal({ force = true, source = opts.source or "test" })
    T.msg(L["BUFF_TEST_READY"] or "团队检查测试数据已生成")
end

function BuffCheck:QueueUnitScan(unit)
    if not unit or self.state.pendingAuraUnits[unit] then
        return
    end
    if self:IsReadyCheckSessionActive() and self.UI and self.UI.IsRaidShown and self.UI:IsRaidShown() then
        local session = self:GetReadyCheckState()
        if not session.liveUpdatesSuppressed then
            session.liveUpdatesSuppressed = true
            self:DebugEvent("ReadyCheckLiveUpdatesSuppressed", {
                source = session.source or "ready_check",
                reason = "raid_panel_snapshot_mode",
            })
        end
        return
    end
    self.state.pendingAuraUnits[unit] = true
    C_Timer.After(0.2, function()
        self.state.pendingAuraUnits[unit] = nil
        self:ScanUnit(unit)
        self:RequestRefresh(0.05)
    end)
end

function BuffCheck:StartAutoHide()
    if self.state.autoHideTimer and self.state.autoHideTimer.Cancel then
        self.state.autoHideTimer:Cancel()
    end
    local delay = tonumber(DB().autoHideDelaySec) or 15
    self.state.autoHideTimer = C_Timer.NewTimer(math.max(5, delay), function()
        self:HideAll()
        Debug("AutoHide")
    end)
end

function BuffCheck:CanAutoShowReadyCheck(source)
    local enabled = self:IsEnabled()
    local autoShow = DB().autoShowOnReadyCheck ~= false
    if enabled and autoShow then
        return true
    end
    self:DebugEvent("ReadyCheckAutoShowSkipped", {
        source = source or "ready_check",
        reason = enabled and "auto_show_disabled" or "module_disabled",
        enabled = enabled and "true" or "false",
        autoShow = autoShow and "true" or "false",
    })
    return false
end

function BuffCheck:ShowReadyCheckPanel(source)
    if not self:CanAutoShowReadyCheck(source) then
        return
    end
    local session = self:GetReadyCheckState()
    if session.shown then
        self:DebugEvent("ReadyCheckAutoShowSkipped", {
            source = source or "ready_check",
            reason = "already_shown",
            enabled = "true",
            autoShow = "true",
        })
        return
    end
    local isLeader = UnitIsGroupLeader("player") == true
    local inRaid = IsInRaid() == true
    local inGroup = IsInGroup() == true
    if inGroup then
        self:ShowRaid({ force = true, source = source or "ready_check", skipScan = true })
    else
        self:ShowPersonal({ force = true, source = source or "ready_check", skipScan = true })
    end
    session.shown = true
    self:StartAutoHide()
    self:DebugEvent("ReadyCheckAutoShow", {
        source = source or "ready_check",
        leader = isLeader and "true" or "false",
        raid = inRaid and "true" or "false",
    })
end

function BuffCheck:HandleReadyCheck(event, unit, isReady)
    local source = event == "READY_CHECK_CONFIRM" and "ready_check_confirm" or "ready_check"
    if event == "READY_CHECK" then
        local session = self:GetReadyCheckState()
        if session.active and (GetNow() - (session.startedAt or 0)) > 45 then
            self:FinishReadyCheckSession("stale")
        end
        session = self:GetReadyCheckState()
        if session.active then
            self:DebugEvent("ReadyCheckAutoShowSkipped", {
                source = source,
                reason = "session_active",
                enabled = self:IsEnabled() and "true" or "false",
                autoShow = DB().autoShowOnReadyCheck ~= false and "true" or "false",
            })
            return
        end
        session = self:StartReadyCheckSession(source)
        if IsInGroup() then
            self:ScanSafely("scan_ready_check_initial", function()
                return self:ScanGroup()
            end, source)
            self:BroadcastOwnDurability("ready_check_initial", true)
        else
            self:ScanSafely("scan_ready_check_self", function()
                return self:ScanSelf()
            end, source)
        end
        session.initialScanDone = true
        self:DebugEvent("ReadyCheckInitialScanComplete", {
            source = source,
            total = #self:GetSortedResults(),
        })
        self:ShowReadyCheckPanel(source)
        return
    end
    if event == "READY_CHECK_CONFIRM" then
        local session = self:GetReadyCheckState()
        if not session.active then
            return
        end
        session.confirmCount = (session.confirmCount or 0) + 1
        -- 避免用 UnitIsUnit 判断是否为自己：当 unit 为 remote token（如 targettarget）时返回 secret boolean 会污染执行栈
        if isReady == false then
            self:DebugEvent("ReadyCheckConfirmNotReady", {
                source = source,
                unit = unit or "none",
                ready = "false",
            })
        end
    end
end

function BuffCheck:Enable()
    self:Init()
    if self.eventsEnabled or not self.eventFrame then
        return
    end
    self.eventFrame:RegisterEvent("READY_CHECK")
    self.eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
    self.eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    self.eventFrame:RegisterEvent("UNIT_AURA")
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self.eventFrame:RegisterEvent("MERCHANT_SHOW")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:EnsureCommReady()
    self.eventsEnabled = true
    C_Timer.After(2, function()
        if self:IsEnabled() then
            self:ScanSelf()
            self:BroadcastOwnDurability("enable", true)
        end
        if self:IsRepairReminderEnabled() then
            self:EvaluateRepairReminder("enable", false)
        end
    end)
end

function BuffCheck:Disable()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    self.eventsEnabled = false
    self.state.results = {}
    self.state.units = {}
    self.state.durabilityReports = { byFull = {}, byShort = {} }
    self.state.repairReminder = {
        active = false,
        pendingCombat = false,
        lastToastAt = 0,
        lastPercent = nil,
    }
    self:ResetReadyCheckSession()
    self:HideAll()
    if self.UI and self.UI.HideRepairReminder then
        self.UI:HideRepairReminder()
    end
end

function BuffCheck:Init()
    if self.initialized then
        return
    end
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "READY_CHECK" then
            if self:IsEnabled() then
                self:HandleReadyCheck(event, ...)
            end
        elseif event == "READY_CHECK_CONFIRM" then
            if self:IsEnabled() then
                self:HandleReadyCheck(event, ...)
            end
        elseif event == "READY_CHECK_FINISHED" then
            if self:IsEnabled() then
                self:FinishReadyCheckSession("finished")
                self:StartAutoHide()
            end
        elseif event == "UNIT_AURA" then
            if not self:IsEnabled() then
                return
            end
            local unit = ...
            if unit == "player" then
                self:QueueUnitScan(unit)
            elseif self.UI and self.UI.IsRaidShown and self.UI:IsRaidShown() and unit and (unit:match("^raid%d+$") or unit:match("^party%d+$") or unit == "player") then
                self:QueueUnitScan(unit)
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            if not self:IsEnabled() then
                return
            end
            self:PruneResults()
            if self:IsReadyCheckSessionActive() and self.UI and self.UI.IsRaidShown and self.UI:IsRaidShown() then
                return
            end
            if self.UI and self.UI.IsRaidShown and self.UI:IsRaidShown() then
                C_Timer.After(0.5, function()
                    self:ScanGroup()
                    self:RequestRefresh(0)
                end)
            else
                self:RequestRefresh(0)
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(2, function()
                if self:IsEnabled() then
                    self:ScanSelf()
                    self:BroadcastOwnDurability("enter_world", true)
                    self:RequestRefresh(0)
                end
                if self:IsRepairReminderEnabled() then
                    self:EvaluateRepairReminder("enter_world", false)
                end
            end)
        elseif event == "UPDATE_INVENTORY_DURABILITY" then
            C_Timer.After(DURABILITY_EVENT_DELAY, function()
                if self:IsEnabled() then
                    self:BroadcastOwnDurability("durability_update", false)
                    self:QueueUnitScan("player")
                end
                if self:IsRepairReminderEnabled() then
                    self:EvaluateRepairReminder("durability_update", false)
                end
            end)
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            local slotID = tonumber((...))
            if slotID and DURABILITY_SLOT_SET[slotID] then
                C_Timer.After(DURABILITY_EVENT_DELAY, function()
                    if self:IsEnabled() then
                        self:BroadcastOwnDurability("equipment_changed", false)
                        self:QueueUnitScan("player")
                    end
                    if self:IsRepairReminderEnabled() then
                        self:EvaluateRepairReminder("equipment_changed", false)
                    end
                end)
            end
        elseif event == "MERCHANT_SHOW" then
            self:TryAutoRepair("merchant_show")
        elseif event == "PLAYER_REGEN_ENABLED" then
            if self:IsRepairReminderEnabled() and self.state.repairReminder and self.state.repairReminder.pendingCombat then
                self:EvaluateRepairReminder("regen_enabled", true)
            elseif self:IsRepairReminderEnabled() and self:GetRepairReminderDB().combatEndReminder ~= false then
                self:EvaluateRepairReminder("combat_end", true)
            end
        end
    end)
    self.initialized = true
end

function BuffCheck:ApplyEnabledState()
    if self:ShouldKeepEventsEnabled() then
        self:Enable()
        if not self:IsEnabled() then
            self:HideAll()
        end
    else
        self:Disable()
    end
end

function BuffCheck:OnRegister()
    T.BuffCheck = self
end

function BuffCheck:OnEnable()
    self:ApplyEnabledState()
end

function BuffCheck:OnDisable()
    self:Disable()
end

function T.HandleBuffCheckCommand(args)
    args = tostring(args or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if args == "" or args == "me" or args == "self" then
        BuffCheck.testMode = false
        BuffCheck:ScanSelf()
        BuffCheck:BroadcastOwnDurability("command_personal", false)
        BuffCheck:ShowPersonal()
    elseif args == "raid" then
        BuffCheck.testMode = false
        BuffCheck:ScanRaidIfLead()
        BuffCheck:BroadcastOwnDurability("command_raid", true)
        BuffCheck:ShowRaid()
    elseif args == "broadcast" then
        BuffCheck:ChatBroadcast()
    elseif args == "test" then
        BuffCheck:RunTest()
    elseif args == "hide" then
        BuffCheck:HideAll()
    elseif args == "refresh" then
        if BuffCheck.UI and BuffCheck.UI.IsRaidShown and BuffCheck.UI:IsRaidShown() then
            BuffCheck:ScanRaidIfLead()
            BuffCheck:BroadcastOwnDurability("command_refresh", true)
        else
            BuffCheck:ScanSelf()
            BuffCheck:BroadcastOwnDurability("command_refresh", true)
        end
        BuffCheck:Refresh()
        T.msg(L["BUFF_REFRESHED"] or "团队检查已刷新")
    else
        T.msg(L["BUFF_COMMAND_HELP"] or "用法: /st bc me|raid|broadcast|test|hide|refresh")
    end
end

end)
