local T, C = unpack(select(2, ...))
T.RegisterColdFile("interruptRotation.enabled", function()

local DEBUG_INTERRUPT_WINDOW_SEC = 185

T.Assets:Define("MidnightFallsInterruptHandler", {
    factory = function()
        local handler = {
            encounterID = 3183,
            bossUnits = { "boss2", "boss3", "boss4" },
            difficultyIDs = { [16] = true },
            startNumber = 1,
            resetTimer = 15,
        }

        local function DebugWindowEnabled()
            return C and C.DB and C.DB.debugMode == true
        end

        local function LogDebug(fmt, ...)
            if DebugWindowEnabled() and T.debug then
                T.debug(string.format("[IR:MidnightFalls] " .. fmt, ...))
            end
        end

        function handler:OnEncounterStart()
            self._debugWindowStartTime = nil
            self._debugWindowEndTime = nil
            if not DebugWindowEnabled() then
                return
            end

            local now = GetTime()
            self._debugWindowStartTime = now
            self._debugWindowEndTime = now + DEBUG_INTERRUPT_WINDOW_SEC
            LogDebug("debug window armed %.1fs", DEBUG_INTERRUPT_WINDOW_SEC)
        end

        function handler:OnEncounterEnd()
            self._debugWindowStartTime = nil
            self._debugWindowEndTime = nil
        end

        function handler:ShouldHandleSpellEvent(IR, eventName, unit)
            if not DebugWindowEnabled() then
                return true
            end

            local endTime = tonumber(self._debugWindowEndTime)
            if not endTime then
                return true
            end

            local now = GetTime()
            if now <= endTime then
                return true
            end

            local startTime = tonumber(self._debugWindowStartTime) or now
            LogDebug(
                "blocked spell event event=%s unit=%s elapsed=%.1fs window=%.1fs",
                tostring(eventName),
                tostring(unit),
                now - startTime,
                DEBUG_INTERRUPT_WINDOW_SEC
            )
            return false
        end

        function handler:OnEngageUnit(IR)
            local interrupts = IR and IR.Interrupts
            if not interrupts then
                return
            end

            if UnitExists("boss2") and UnitIsEnemy("boss2", "player") then
                if interrupts.myTrackedID == 4 then
                    if not UnitExists("boss4") then
                        if UnitExists("boss3") then
                            interrupts.myTrackedID = 3
                        else
                            interrupts.myTrackedID = 2
                        end
                    end
                elseif interrupts.myTrackedID == 3 then
                    if not UnitExists("boss3") then
                        interrupts.myTrackedID = 2
                    end
                end
                return
            end

            if not UnitExists("boss2") or not UnitIsEnemy("boss2", "player") then
                IR:ResetInterrupts()
            end
        end

        return handler
    end,
})

T.RegisterInitCallback(function()
    if T.InterruptRotation and T.InterruptRotation.RegisterEncounter then
        local handler = T.Assets:Get("MidnightFallsInterruptHandler", "InterruptRotation")
        T.InterruptRotation:RegisterEncounter(3183, handler)
    end
end)

end)
