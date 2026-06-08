local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("privateAuraHijack.enabled", function()

local AuraAPI = _G["C_" .. "Unit" .. "Auras"]
if not AuraAPI or not AuraAPI.AddPrivateAuraAnchor then
    return
end

local DB_KEY = "privateAuraHijack"
local AddPrivateAuraAnchor = AuraAPI.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = AuraAPI.RemovePrivateAuraAnchor

local M = T.ModuleLoader:NewModule({
    name = "PrivateAuraHijack",
    dbKey = DB_KEY .. ".enabled",
    defaultEnabled = false,
})
T.PrivateAuraHijack = M

local frameAnchors = {}
local containerAnchorFrames = {}
local hookedChildren = {}
local activeSources = {}
local activeFrames = {}
local scanChildFailures = {}
local initialized = false
local enabled = false
local eventFrame
local pendingReanchor = false
local privateContainerHooked = false
local privateContainerHookLoadTried = false

local function GetDB()
    if type(C.DB) ~= "table" then
        return nil
    end
    if type(C.DB[DB_KEY]) ~= "table" then
        C.DB[DB_KEY] = {}
    end
    return C.DB[DB_KEY]
end

local function Debug(fmt, ...)
    if T and T.debug then
        T.debug(string.format("[PAH] " .. fmt, ...))
    end
end

local function FrameLabel(frame)
    if not frame then
        return "-"
    end
    if type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tostring(frame)
end

local function SafeFrameName(frame)
    if frame and type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

local function SafeFrameLevel(frame)
    if frame and type(frame.GetFrameLevel) == "function" then
        local ok, level = pcall(frame.GetFrameLevel, frame)
        if ok and type(level) == "number" then
            return level
        end
    end
    return 1
end

local function SafeGetChildren(frame)
    if not frame or type(frame.GetChildren) ~= "function" then
        return {}
    end
    local children = { pcall(frame.GetChildren, frame) }
    local ok = table.remove(children, 1)
    if not ok then
        if not scanChildFailures[frame] then
            scanChildFailures[frame] = true
            Debug("scan_children_failed frame=%s err=%s", FrameLabel(frame), tostring(children[1]))
        end
        return {}
    end
    return children
end

local function SafeUnit(frame)
    local unit = frame and frame.unit
    if (type(unit) ~= "string" or unit == "") and frame and type(frame.GetAttribute) == "function" then
        local ok, attr = pcall(frame.GetAttribute, frame, "unit")
        if ok then
            unit = attr
        end
    end
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    if unit == "player" then
        return IsInGroup() and unit or nil
    end
    if unit:find("^party%d+$") or unit:find("^raid%d+$") then
        return unit
    end
    return nil
end

local function IsCandidateFrame(frame)
    if not frame then
        return false
    end
    local unit = SafeUnit(frame)
    if not unit or not UnitExists(unit) then
        return false
    end

    local name = SafeFrameName(frame)
    if not name then
        return false
    end
    if name:find("Arena") then
        return false
    end
    if name:find("^CompactRaidFrame%d+$") then
        return true
    end
    if name:find("^CompactPartyFrameMember%d+$") then
        return not IsInRaid()
    end
    if unit:find("^raid%d+$") and name:find("Party") then
        return false
    end
    if unit:find("^party%d+$") and name:find("Raid") then
        return false
    end
    if name:find("^RaidFrameMember%d+$") then
        return true
    end
    if name:find("UnitButton%d+$") and (name:find("Raid") or name:find("Party") or name:find("Group") or name:find("Header")) then
        return true
    end
    return false
end

local function AddCandidate(result, seen, frame)
    if IsCandidateFrame(frame) and not seen[frame] then
        seen[frame] = true
        result[#result + 1] = frame
    end
end

local function ScanChildren(result, seen, frame, depth)
    if not frame or depth > 8 or type(frame.GetChildren) ~= "function" then
        return
    end
    AddCandidate(result, seen, frame)
    for _, child in ipairs(SafeGetChildren(frame)) do
        ScanChildren(result, seen, child, depth + 1)
    end
end

local function CollectFrames()
    local result = {}
    local seen = {}

    for index = 1, 40 do
        AddCandidate(result, seen, _G["CompactRaidFrame" .. index])
    end
    for index = 1, 5 do
        AddCandidate(result, seen, _G["CompactPartyFrameMember" .. index])
    end
    ScanChildren(result, seen, _G.CompactRaidFrameContainer, 0)
    ScanChildren(result, seen, _G.CompactPartyFrame, 0)
    ScanChildren(result, seen, UIParent, 0)

    return result
end

local function ApplyWrapperAlpha(frame)
    local db = GetDB() or {}
    local wrapper = frame and frame.sttPAHWrapper
    if wrapper then
        wrapper:SetAlpha(db.hideBlizzardOverlay == false and 1 or 0)
    end
end

local function ApplyOverlaySettings(frame)
    local db = GetDB() or {}
    local overlay = frame and frame.sttPAHOverlay
    if not overlay then
        return
    end

    overlay:ClearAllPoints()
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(SafeFrameLevel(frame) + 10)

    if overlay.text then
        overlay.text:ClearAllPoints()
        overlay.text:SetPoint(db.anchor or "CENTER", frame, db.anchor or "CENTER", db.offsetX or 0, db.offsetY or 0)
        overlay.text:SetFont(STANDARD_TEXT_FONT, db.fontSize or 28, db.outline ~= "NONE" and db.outline or nil)
        local color = db.fontColor or { 1, 0.2, 0.2, 1 }
        overlay.text:SetTextColor(color[1] or 1, color[2] or 0.2, color[3] or 0.2, color[4] or 1)
        overlay.text:SetText(db.dispelText or "驱散!")
        overlay.text:SetShown(db.dispelTextEnabled ~= false)
    end

    local color = db.fontColor or { 1, 0.2, 0.2, 1 }
    for _, tex in pairs(overlay.border or {}) do
        tex:SetColorTexture(color[1] or 1, color[2] or 0.2, color[3] or 0.2, 0.75)
    end
end

local function CreateBorderTexture(parent)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetColorTexture(1, 0.2, 0.2, 0.75)
    return tex
end

local function AttachHijackOverlay(frame)
    if frame.sttPAHOverlay then
        ApplyOverlaySettings(frame)
        return frame.sttPAHOverlay
    end

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(SafeFrameLevel(frame) + 10)
    overlay:EnableMouse(false)
    if overlay.SetMouseClickEnabled then
        overlay:SetMouseClickEnabled(false)
    end

    overlay.border = {
        top = CreateBorderTexture(overlay),
        bottom = CreateBorderTexture(overlay),
        left = CreateBorderTexture(overlay),
        right = CreateBorderTexture(overlay),
    }
    overlay.border.top:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    overlay.border.top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    overlay.border.top:SetHeight(3)
    overlay.border.bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    overlay.border.bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    overlay.border.bottom:SetHeight(3)
    overlay.border.left:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    overlay.border.left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    overlay.border.left:SetWidth(3)
    overlay.border.right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    overlay.border.right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    overlay.border.right:SetWidth(3)

    overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.pulse = overlay:CreateAnimationGroup()
    overlay.pulse:SetLooping("REPEAT")
    local fadeOut = overlay.pulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.35)
    fadeOut:SetOrder(1)
    local fadeIn = overlay.pulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.35)
    fadeIn:SetToAlpha(1)
    fadeIn:SetOrder(2)

    frame.sttPAHOverlay = overlay
    ApplyOverlaySettings(frame)
    overlay:Hide()
    return overlay
end

local function PlayOverlayPulse(overlay)
    local db = GetDB() or {}
    if not overlay or not overlay.pulse then
        return
    end
    overlay.pulse:Stop()
    overlay:SetAlpha(1)
    if db.flashEnabled == true then
        local duration = math.max(0.1, tonumber(db.flashInterval) or 0.5)
        for _, anim in ipairs({ overlay.pulse:GetAnimations() }) do
            anim:SetDuration(duration)
        end
        overlay.pulse:Play()
    end
end

local function HasActiveSource(frame)
    local sources = activeSources[frame]
    if not sources then
        return false
    end
    for _, active in pairs(sources) do
        if active then
            return true
        end
    end
    return false
end

local function OnDispelOverlayShow(frame, source)
    local db = GetDB() or {}
    source = source or "unknown"
    activeSources[frame] = activeSources[frame] or {}
    activeSources[frame][source] = true
    local overlay = AttachHijackOverlay(frame)
    overlay:Show()
    PlayOverlayPulse(overlay)
    Debug("overlay_show frame=%s unit=%s source=%s text=%s textEnabled=%s", FrameLabel(frame), tostring(SafeUnit(frame)), tostring(source), tostring(db.dispelText or "驱散!"), tostring(db.dispelTextEnabled ~= false))
    if db.soundEnabled == true and type(db.soundPath) == "string" and db.soundPath ~= "" and T.PlayInlineSound then
        T.PlayInlineSound(db.soundPath, "private_aura_hijack")
    end
end

local function OnDispelOverlayHide(frame, source)
    source = source or "unknown"
    if activeSources[frame] then
        activeSources[frame][source] = nil
    end
    if HasActiveSource(frame) then
        Debug("overlay_hide frame=%s unit=%s source=%s remaining=true", FrameLabel(frame), tostring(SafeUnit(frame)), tostring(source))
        return
    end
    local overlay = frame and frame.sttPAHOverlay
    if overlay then
        if overlay.pulse then
            overlay.pulse:Stop()
        end
        overlay:SetAlpha(1)
        overlay:Hide()
    end
    Debug("overlay_hide frame=%s unit=%s source=%s", FrameLabel(frame), tostring(SafeUnit(frame)), tostring(source))
end

local function HookOverlaySource(frame, source, overlay)
    if not frame or not overlay or type(overlay.HookScript) ~= "function" then
        return false
    end

    hookedChildren[frame] = hookedChildren[frame] or {}
    if hookedChildren[frame][source] == overlay then
        return true
    end

    local ok, err = pcall(function()
        overlay:HookScript("OnShow", function()
            OnDispelOverlayShow(frame, source)
        end)
        overlay:HookScript("OnHide", function()
            OnDispelOverlayHide(frame, source)
        end)
    end)
    if not ok then
        Debug("hook_failed frame=%s unit=%s source=%s err=%s", FrameLabel(frame), tostring(SafeUnit(frame)), tostring(source), tostring(err))
        return false
    end

    hookedChildren[frame][source] = overlay
    local shownOk, shown = pcall(overlay.IsShown, overlay)
    if shownOk and shown then
        OnDispelOverlayShow(frame, source)
    end
    Debug("hooked frame=%s unit=%s source=%s", FrameLabel(frame), tostring(SafeUnit(frame)), tostring(source))
    return true
end

local function HookFrameSources(frame)
    HookOverlaySource(frame, "dfDispelOverlay", frame and frame.dfDispelOverlay)
end

local function TryHookPrivateContainerBridge()
    if privateContainerHooked then
        return true
    end

    if not privateContainerHookLoadTried then
        privateContainerHookLoadTried = true
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_PrivateAurasUI")
        end
    end

    local mixin = _G.PrivateAuraAnchorContainerMixin
    if type(mixin) ~= "table" or type(mixin.SetDispelOverlayAura) ~= "function" or type(hooksecurefunc) ~= "function" then
        return false
    end

    hooksecurefunc(mixin, "SetDispelOverlayAura", function(container, aura)
        local anchorID = container and container.anchorID
        local frame = anchorID and containerAnchorFrames[anchorID]
        if not frame then
            return
        end
        if aura ~= nil then
            OnDispelOverlayShow(frame, "privateContainer")
        else
            OnDispelOverlayHide(frame, "privateContainer")
        end
    end)
    privateContainerHooked = true
    Debug("private_container_hooked")
    return true
end

local function SchedulePrivateContainerHook()
    if TryHookPrivateContainerBridge() then
        return
    end
    C_Timer.After(0.2, function()
        if not TryHookPrivateContainerBridge() then
            C_Timer.After(1, function()
                TryHookPrivateContainerBridge()
            end)
        end
    end)
end

local function EnsureWrapper(frame)
    local wrapper = frame.sttPAHWrapper
    if not wrapper then
        wrapper = CreateFrame("Frame", nil, frame)
        wrapper:EnableMouse(false)
        if wrapper.SetMouseClickEnabled then
            wrapper:SetMouseClickEnabled(false)
        end
        frame.sttPAHWrapper = wrapper
    end

    wrapper:SetParent(frame)
    wrapper:ClearAllPoints()
    wrapper:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    wrapper:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    wrapper:SetFrameStrata("MEDIUM")
    wrapper:SetFrameLevel(SafeFrameLevel(frame) + 6)
    wrapper:Show()

    return wrapper
end

local function ApplyContainerAttributes(wrapper, unit)
    wrapper:SetAttribute("max-buffs", 0)
    wrapper:SetAttribute("max-debuffs", 0)
    wrapper:SetAttribute("max-dispel-debuffs", 1)
    wrapper:SetAttribute("ignore-buffs", true)
    wrapper:SetAttribute("ignore-debuffs", true)
    wrapper:SetAttribute("ignore-dispel-debuffs", true)
    wrapper:SetAttribute("show-dispel-indicator-overlay", true)
    wrapper:SetAttribute("suppress-dispel-border-icons", true)
    wrapper:SetAttribute("dispel-indicator-option", 2)
    wrapper:SetAttribute("aura-organization-type", 0)
    wrapper:SetAttribute("group-type", unit and unit:find("^party") and 4 or 5)
    wrapper:SetAttribute("power-bar-used-height", 0)
    wrapper:SetAttribute("icon-size", 10)
    wrapper:SetAttribute("set-aura-size-to-icon-size", false)
    wrapper:SetAttribute("update-settings", true)
end

local function UnregisterAnchor(frame)
    local anchorID = frameAnchors[frame]
    if anchorID and RemovePrivateAuraAnchor then
        pcall(RemovePrivateAuraAnchor, anchorID)
    end
    if anchorID then
        containerAnchorFrames[anchorID] = nil
    end
    frameAnchors[frame] = nil
    activeFrames[frame] = nil
    hookedChildren[frame] = nil
    activeSources[frame] = nil
    if frame then
        frame.sttPAHUnit = nil
        OnDispelOverlayHide(frame, "unregister")
        if frame.sttPAHWrapper then
            frame.sttPAHWrapper:Hide()
        end
    end
end

local function ScheduleFrameSourceHook(frame, delay)
    if not frame then
        return
    end
    C_Timer.After(delay or 0, function()
        if frameAnchors[frame] then
            local ok, err = pcall(HookFrameSources, frame)
            if not ok then
                Debug("hook_callback_failed frame=%s unit=%s err=%s", FrameLabel(frame), tostring(SafeUnit(frame)), tostring(err))
            end
        end
    end)
end

local function RegisterAnchor(frame, unit)
    if not frame or not unit then
        return
    end
    if frameAnchors[frame] and frame.sttPAHUnit == unit then
        ApplyWrapperAlpha(frame)
        ApplyOverlaySettings(frame)
        ScheduleFrameSourceHook(frame, 0)
        return
    end
    if frameAnchors[frame] then
        UnregisterAnchor(frame)
    end

    local wrapper = EnsureWrapper(frame)
    ApplyContainerAttributes(wrapper, unit)
    ApplyWrapperAlpha(frame)

    local ok, anchorID = pcall(AddPrivateAuraAnchor, {
        unitToken = unit,
        parent = wrapper,
        isContainer = true,
        auraIndex = 1,
        showCountdownFrame = false,
        showCountdownNumbers = false,
    })
    if not ok or not anchorID then
        Debug("anchor_failed frame=%s unit=%s err=%s", FrameLabel(frame), tostring(unit), tostring(anchorID))
        return
    end

    frameAnchors[frame] = anchorID
    containerAnchorFrames[anchorID] = frame
    activeFrames[frame] = true
    frame.sttPAHUnit = unit
    AttachHijackOverlay(frame)
    SchedulePrivateContainerHook()
    ScheduleFrameSourceHook(frame, 0)
    Debug("anchor_ok frame=%s unit=%s anchor=%s", FrameLabel(frame), tostring(unit), tostring(anchorID))
end

function M:Disable()
    pendingReanchor = false
    enabled = false
    for frame in pairs(activeFrames) do
        UnregisterAnchor(frame)
    end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    Debug("disabled")
end

function M:Reanchor()
    if not enabled then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        pendingReanchor = true
        Debug("reanchor_deferred combat")
        return
    end

    local frames = CollectFrames()
    local alive = {}
    for _, frame in ipairs(frames) do
        local unit = SafeUnit(frame)
        alive[frame] = true
        RegisterAnchor(frame, unit)
    end
    for frame in pairs(activeFrames) do
        if not alive[frame] then
            UnregisterAnchor(frame)
        end
    end
    pendingReanchor = false
    Debug("reanchor frames=%d", #frames)
end

function M:ApplySettings()
    local db = GetDB() or {}
    Debug("apply_settings enabled=%s", tostring(db.enabled == true))
    if db.enabled == true then
        self:Enable()
    else
        self:Disable()
    end
end

function M:OnRegister()
    T.PrivateAuraHijack = self
end

function M:OnEnable()
    self:Enable()
end

function M:OnDisable()
    self:Disable()
end

function M:Enable()
    local db = GetDB() or {}
    if db.enabled ~= true then
        Debug("enable_skip db_disabled")
        return
    end
    enabled = true
    Debug("enabled")
    self:Initialize()
    self:Reanchor()
end

function M:Initialize()
    if initialized then
        if eventFrame then
            eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:RegisterEvent("UNIT_AURA")
        end
        return
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" and pendingReanchor then
            M:Reanchor()
            return
        end
        if event == "UNIT_AURA" then
            if type(unit) ~= "string" then
                return
            end
            for frame in pairs(activeFrames) do
                if SafeUnit(frame) == unit then
                    ScheduleFrameSourceHook(frame, 0)
                end
            end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
            C_Timer.After(0.2, function()
                M:Reanchor()
            end)
        end
    end)
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("UNIT_AURA")
    initialized = true
end

end)
