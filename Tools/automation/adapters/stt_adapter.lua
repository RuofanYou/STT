local Common = require("mocks.wow_api_common")

local source = debug.getinfo(1, "S").source
local this_path = source:sub(1, 1) == "@" and source:sub(2) or source
local function dirname(path)
    local d = path and path:match("^(.*)/[^/]+$")
    return (d and d ~= "") and d or "."
end
local automation_dir = dirname(dirname(this_path))
local tools_dir = dirname(automation_dir)
local repo_root = dirname(tools_dir)
if repo_root == "." then
    repo_root = os.getenv("PWD") or "."
end

local FILES = {
    repo_root .. "/ShengTangTools/core/friendly_nameplate.lua",
    repo_root .. "/ShengTangTools/core/condition_filter.lua",
    repo_root .. "/ShengTangTools/core/inline_modifier.lua",
    repo_root .. "/ShengTangTools/core/timeline_syntax.lua",
    repo_root .. "/ShengTangTools/core/tactic_translator.lua",
    repo_root .. "/ShengTangTools/core/tactic_translator_mrt.lua",
    repo_root .. "/ShengTangTools/core/tactic_exporter_tr.lua",
    repo_root .. "/ShengTangTools/core/stn_template.lua",
    repo_root .. "/ShengTangTools/core/horizontal_timeline_data.lua",
    repo_root .. "/ShengTangTools/core/timeline_coords.lua",
    repo_root .. "/ShengTangTools/core/skill_picker_logic.lua",
    repo_root .. "/ShengTangTools/core/trigger_syntax.lua",
    repo_root .. "/ShengTangTools/core/encounter_event_resolver.lua",
    repo_root .. "/ShengTangTools/core/semantic_runtime.lua",
    repo_root .. "/ShengTangTools/core/note_parser.lua",
    repo_root .. "/ShengTangTools/core/tts_queue.lua",
    repo_root .. "/ShengTangTools/core/trigger_runner.lua",
    repo_root .. "/ShengTangTools/core/stn_voice_adapter.lua",
    repo_root .. "/ShengTangTools/core/screen_reminder/schema.lua",
    repo_root .. "/ShengTangTools/core/tactical_notice.lua",
    repo_root .. "/ShengTangTools/core/tactical_notice_layout.lua",
    repo_root .. "/ShengTangTools/core/countdown_player.lua",
    repo_root .. "/ShengTangTools/core/inline_sound.lua",
    repo_root .. "/ShengTangTools/core/timeline_runner.lua",
    repo_root .. "/ShengTangTools/core/lura_starsplinter_direction.lua",
    repo_root .. "/ShengTangTools/core/interrupt_rotation/interrupt_rotation_macro.lua",
}

local VISUAL_BOARD_FILES = {
    repo_root .. "/ShengTangTools/core/keyboard_capture.lua",
    repo_root .. "/ShengTangTools/visual_board/backgrounds.lua",
    repo_root .. "/ShengTangTools/visual_board/data.lua",
    repo_root .. "/ShengTangTools/visual_board/spec_icons.lua",
    repo_root .. "/ShengTangTools/visual_board/person_resolver.lua",
    repo_root .. "/ShengTangTools/visual_board/core.lua",
    repo_root .. "/ShengTangTools/visual_board/parser_hook.lua",
    repo_root .. "/ShengTangTools/visual_board/canvas.lua",
    repo_root .. "/ShengTangTools/visual_board/overlay.lua",
    repo_root .. "/ShengTangTools/visual_board/icon_picker.lua",
    repo_root .. "/ShengTangTools/visual_board/layer_panel.lua",
    repo_root .. "/ShengTangTools/visual_board/component_drawer.lua",
    repo_root .. "/ShengTangTools/visual_board/slide_bar.lua",
    repo_root .. "/ShengTangTools/visual_board/editor_gui.lua",
}

local EXPORT_IMPORT_FILES = {
    repo_root .. "/ShengTangTools/libs/LibStub/LibStub.lua",
    repo_root .. "/ShengTangTools/libs/LibSerialize/LibSerialize.lua",
    repo_root .. "/ShengTangTools/libs/LibDeflate/LibDeflate.lua",
    repo_root .. "/ShengTangTools/core/init.lua",
    repo_root .. "/ShengTangTools/core/profile.lua",
    repo_root .. "/ShengTangTools/core/note.lua",
    repo_root .. "/ShengTangTools/core/export_import.lua",
}

local SEMANTIC_TEMPLATE_FILES = {
    repo_root .. "/ShengTangTools/core/profile.lua",
    repo_root .. "/ShengTangTools/core/note.lua",
    repo_root .. "/ShengTangTools/core/semantic_timeline.lua",
    repo_root .. "/ShengTangTools/core/semantic_template_reload.lua",
}

local M = {}

local function simplify_timeline_events(events)
    local out = {}
    for _, e in ipairs(events or {}) do
        out[#out + 1] = {
            time = e.time,
            showTime = e.showTime,
            text = e.text,
            condition = e.condition,
            players = e.players,
        }
    end
    return out
end

local function simplify_screen_timeline_events(events)
    local out = {}
    for _, e in ipairs(events or {}) do
        out[#out + 1] = {
            time = e.time,
            showTime = e.showTime,
            text = e.screenText or e.text,
            timelineText = e.text,
            ttsText = e.ttsText,
            spellID = e.spellID,
            spellIcon = e.spellIcon,
            isSilent = e.isSilent,
            inlineSound = e.inlineSound,
        }
    end
    return out
end

local function simplify_board_timeline_events(events)
    local out = {}
    for _, e in ipairs(events or {}) do
        local cells = {}
        for _, cell in ipairs(e.cells or {}) do
            cells[#cells + 1] = {
                who = cell.who,
                whoType = cell.whoType,
                actionText = cell.actionText,
                spellHiddenActionText = cell.spellHiddenActionText,
                spellID = cell.spellID,
                spellIcon = cell.spellIcon,
            }
        end
        out[#out + 1] = {
            time = e.time,
            text = e.screenText or e.text,
            cells = cells,
        }
    end
    return out
end

local function simplify_tactical_notice_calls(calls)
    local out = {}
    for _, call in ipairs(calls or {}) do
        out[#out + 1] = {
            action = call.action,
            data = call.data,
        }
    end
    return out
end

local function simplify_parsed_events(events)
    local out = {}
    for _, e in ipairs(events or {}) do
        out[#out + 1] = {
            time = e.time,
            line = e.line,
            content = e.content,
            displayText = e.displayText,
            hasAudience = e.hasAudience == true,
            modifiers = e.modifiers,
            segments = e.segments,
        }
    end
    return out
end

local function simplify_parsed_event(event)
    if type(event) ~= "table" then
        return event
    end
    return {
        time = event.time,
        line = event.line,
        content = event.content,
        displayText = event.displayText,
        hasAudience = event.hasAudience == true,
        modifiers = event.modifiers,
        segments = event.segments,
    }
end

local function load_file_in_env(path, env, ns)
    local chunk, err = loadfile(path, "t", env)
    if not chunk then
        error("加载文件失败: " .. tostring(path) .. ": " .. tostring(err))
    end
    local ok, runtime_err = pcall(chunk, "ShengTangTools", ns)
    if not ok then
        error("执行文件失败: " .. tostring(path) .. ": " .. tostring(runtime_err))
    end
end

local function deep_merge(dst, src)
    if type(src) ~= "table" then
        return src
    end

    if type(dst) ~= "table" then
        dst = {}
    end

    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = deep_merge(dst[key], value)
        else
            dst[key] = value
        end
    end

    return dst
end

local function create_context(fixture)
    local init = fixture.init or {}
    local frames = {}
    local context = {
        now = tonumber(init.now or 0) or 0,
        timers = {},
        timerCallbacks = {},
        cvars = Common.deep_copy(init.cvars or {}),
        setCVarCalls = {},
        speakCalls = {},
        soundCalls = {},
        injectedCalls = {},
        clearInjectedCount = 0,
        screenReminderCalls = {},
        screenReminderLoadCount = 0,
        screenReminderClearCount = 0,
        screenReminderPlan = nil,
        screenReminderEmitted = {},
        screenReminderShowIndex = 0,
        screenReminderStartTime = nil,
        barCalls = {},
        realtimeBoardStarts = {},
        realtimeBoardStops = {},
        frames = frames,
        keyDownMap = {},
        keyModifiers = {},
        messages = {},
        debugLines = {},
        result = nil,
        hookRegistry = {},
        nameplates = {},
        unitExistsMap = Common.deep_copy(init.unitExistsMap or {}),
        difficultyID = tonumber(init.difficultyID) or 16,
    }

    local T = {
        Init_callbacks = {},
    }
    local function install_lazy_field(tbl, fieldName, assetKey)
        if type(tbl) ~= "table" or type(fieldName) ~= "string" or fieldName == "" then
            return
        end
        local mt = getmetatable(tbl) or {}
        local previousIndex = mt.__index
        local lazyFields = mt.__sttAutomationLazyFields or {}
        lazyFields[fieldName] = assetKey
        mt.__sttAutomationLazyFields = lazyFields
        if mt.__sttAutomationLazyIndexInstalled ~= true then
            mt.__index = function(target, key)
                local lazyKey = lazyFields[key]
                if lazyKey then
                    return T.Assets:Get(lazyKey)
                end
                if type(previousIndex) == "function" then
                    return previousIndex(target, key)
                end
                if type(previousIndex) == "table" then
                    return previousIndex[key]
                end
                return nil
            end
            mt.__sttAutomationLazyIndexInstalled = true
        end
        setmetatable(tbl, mt)
    end
    T.Assets = {
        defs = {},
        Define = function(self, key, def)
            if type(key) ~= "string" or key == "" or type(def) ~= "table" or type(def.factory) ~= "function" then
                return false
            end
            self.defs[key] = def
            if def.targetTable and def.targetKey then
                install_lazy_field(def.targetTable, def.targetKey, key)
            end
            return true
        end,
        Get = function(self, key)
            local def = self.defs and self.defs[key]
            if not def then
                return nil
            end
            if def.value == nil then
                def.value = def.factory()
                if def.targetTable and def.targetKey then
                    rawset(def.targetTable, def.targetKey, def.value)
                end
            end
            return def.value
        end,
    }
    local C = {
        DB = Common.merge({
            advanceTime = 3,
            ttsEnabled = true,
            ttsVolume = 100,
            ttsVoiceID = 0,
            ttsAdvanceTime = 0,
            CountdownEnabled = true,
            CountdownChannel = "Master",
            countdown = {
                activePackId = "stt_default",
            },
            Bar = {
                Enabled = true,
            },
            semanticTimeline = {
                runtimeEnabled = true,
                enabled = false,
                resolveSource = "team_plus_personal",
                personalOverridesTeam = true,
            },
            timerBarEnabled = false,
            dataSource = "MRT",
            useRaidNote = true,
            useSelfNote = false,
            filterClass = true,
            filterRole = true,
            filterPos = true,
            filterAll = true,
            filterParty = true,
            screenReminder = {
                schemaVersion = 5,
                enabled = true,
                locked = true,
                globalLeadTimeSec = 3,
                selectedIndicatorID = "text",
                indicators = {
                    {
                        id = "text",
                        kind = "text",
                        enabled = true,
                        order = 1,
                        leadTimeMode = "global",
                        leadTimeSec = 3,
                    },
                },
            },
            blizzardTimeline = {
                injectInTest = false,
            },
            friendlyNameplate = {
                enabled = false,
                removeServerName = true,
                nameOnly = true,
                useClassColor = true,
                autoInInstance = true,
                fontSize = 12,
                fontOutline = "DEFAULT",
            },
            mynickname = "",
        }, Common.deep_copy(init.db or {})),
    }
    local L = setmetatable(Common.deep_copy(init.localeMap or {}), {
        __index = function(_, key)
            return key
        end,
    })
    local ns = { T, C, L }
    local STT = { [1] = T, [2] = C, [3] = L, TestAPI = {} }

    local function attach_child(parent, child)
        if type(parent) ~= "table" or type(child) ~= "table" then
            return
        end
        parent.__children = parent.__children or {}
        parent.__children[#parent.__children + 1] = child
    end

    T.msg = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        context.messages[#context.messages + 1] = table.concat(parts, " ")
    end

    T.debug = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        context.debugLines[#context.debugLines + 1] = table.concat(parts, " ")
    end

    T.RegisterInitCallback = function(func)
        table.insert(T.Init_callbacks, func)
    end

    T.RegisterColdFile = function(_, loader)
        if type(loader) == "function" then
            loader()
        end
    end
    T.__optionModules = {}
    T.RegisterOptionModule = function(module)
        if type(module) == "table" then
            T.__optionModules[#T.__optionModules + 1] = module
        end
    end

    T.BlizzardTimeline = {
        InjectEvents = function(_, events, meta)
            local cfg = (C.DB and C.DB.blizzardTimeline) or {}
            if meta and meta.isTest and (not cfg.injectInTest) and (not meta.force) then
                return
            end
            context.injectedCalls[#context.injectedCalls + 1] = {
                count = #(events or {}),
                reason = meta and meta.reason or nil,
                isTest = meta and meta.isTest or false,
            }
        end,
        ClearInjected = function()
            context.clearInjectedCount = context.clearInjectedCount + 1
        end,
    }

    T.TimerBarManager = {
        initialized = true,
        Initialize = function() end,
        ClearAllBars = function() end,
        AddTimer = function() end,
    }

    local function make_region(kind, parent, name, layer)
        local region = {
            __kind = kind or "Region",
            __name = name,
            __parent = parent,
            __layer = layer,
            __shown = true,
            __text = "",
            __width = 0,
            __height = 0,
            __alpha = 1,
        }
        function region:GetName() return self.__name end
        function region:GetObjectType() return self.__kind end
        function region:GetParent() return self.__parent end
        function region:SetParent(parentFrame) self.__parent = parentFrame end
        function region:SetAllPoints() end
        function region:SetPoint(point, relativeTo, relPoint, x, y)
            self.__point = { point, relativeTo, relPoint, x, y }
        end
        function region:GetPoint()
            local p = self.__point or { "CENTER", nil, "CENTER", 0, 0 }
            return p[1], p[2], p[3], p[4], p[5]
        end
        function region:ClearAllPoints()
            self.__point = { "CENTER", nil, "CENTER", 0, 0 }
        end
        function region:SetSize(w, h) self.__width = w or self.__width; self.__height = h or self.__height end
        function region:SetWidth(w) self.__width = w or self.__width end
        function region:SetHeight(h) self.__height = h or self.__height end
        function region:GetWidth() return self.__width or 0 end
        function region:GetHeight() return self.__height or 0 end
        function region:SetColorTexture(r, g, b, a) self.__colorTexture = { r, g, b, a } end
        function region:SetTexture(value) self.__texture = value end
        function region:SetAtlas(value) self.__atlas = value end
        function region:AddMaskTexture(mask)
            self.__maskTextures = self.__maskTextures or {}
            self.__maskTextures[#self.__maskTextures + 1] = mask
        end
        function region:RemoveMaskTexture(mask)
            if type(self.__maskTextures) ~= "table" then return end
            for index = #self.__maskTextures, 1, -1 do
                if self.__maskTextures[index] == mask then
                    table.remove(self.__maskTextures, index)
                end
            end
        end
        function region:SetTexCoord(...) self.__texCoord = { ... } end
        function region:SetVertexColor(r, g, b, a) self.__vertexColor = { r, g, b, a } end
        function region:SetRotation(value) self.__rotation = value end
        function region:SetBlendMode(value) self.__blendMode = value end
        function region:SetMask(value) self.__mask = value end
        function region:SetStartPoint(point, parent, x, y) self.__startPoint = { point, x, y } end
        function region:SetEndPoint(point, parent, x, y) self.__endPoint = { point, x, y } end
        function region:SetThickness(value) self.__thickness = value end
        function region:SetText(text) self.__text = text or "" end
        function region:GetText() return self.__text end
        function region:SetTextColor() end
        function region:SetShadowColor() end
        function region:SetShadowOffset() end
        function region:SetJustifyH(value) self.__justifyH = value end
        function region:SetJustifyV() end
        function region:SetWordWrap() end
        function region:SetNonSpaceWrap() end
        function region:SetFontObject(fontObject)
            self.__fontObject = fontObject
            if type(fontObject) == "table" and type(fontObject.GetFont) == "function" then
                local path, size, flags = fontObject:GetFont()
                self.__font = { font = path, size = size, flags = flags }
            end
        end
        function region:GetFontObject() return self.__fontObject end
        function region:SetFont(font, size, flags) self.__font = { font = font, size = size, flags = flags } end
        function region:GetFont()
            if type(self.__fontObject) == "table" and type(self.__fontObject.GetFont) == "function" then
                return self.__fontObject:GetFont()
            end
            local font = self.__font or {}
            return font.font, font.size, font.flags
        end
        function region:GetStringHeight() return 16 end
        function region:GetStringWidth() return math.max(16, #(self.__text or "") * 8) end
        function region:SetDrawLayer() end
        function region:SetAlpha(alpha) self.__alpha = alpha end
        function region:GetAlpha() return self.__alpha or 1 end
        function region:SetShown(shown) self.__shown = shown and true or false end
        function region:Show() self.__shown = true end
        function region:Hide() self.__shown = false end
        function region:IsShown() return self.__shown end
        return region
    end

    local function get_font_triplet(target)
        if type(target) ~= "table" or type(target.GetFont) ~= "function" then
            return nil, nil, nil
        end
        local path, size, flags = target:GetFont()
        return path, tonumber(size), flags
    end

    local function make_font_object(name, path, size, flags)
        local font = make_region("FontObject", nil, name, "OVERLAY")
        font:SetFont(path, size, flags)
        return font
    end

    local augment_frame
    local systemFontNamePlate
    local systemFontNamePlateOutlined

    local function make_nameplate(spec)
        local plate = augment_frame(Common.make_frame(), "Frame", spec.name or spec.unit or nil, nil, nil)
        local unitFrame = augment_frame(Common.make_frame(), "Frame", (spec.name or spec.unit or "UnitFrame") .. "UnitFrame", plate, nil)
        local nameRegion = make_region("FontString", unitFrame, (spec.name or spec.unit or "Name") .. "Name", "OVERLAY")
        local font = spec.font or {}
        local fontPath = font.path or font.font or "Fonts/FRIZQT__.TTF"
        local fontSize = tonumber(font.size) or 9
        local fontFlags = font.flags or ""
        nameRegion:SetFont(fontPath, fontSize, fontFlags)
        nameRegion:SetFontObject(make_font_object(
            (spec.name or spec.unit or "Nameplate") .. "OriginalFont",
            fontPath,
            fontSize,
            fontFlags
        ))
        nameRegion:SetText(spec.text or spec.unit or "Nameplate")
        unitFrame.name = nameRegion
        function unitFrame:IsFriend()
            return spec.isFriend == true
        end
        function unitFrame:IsPlayer()
            return spec.isPlayer == true
        end
        unitFrame.unit = spec.unit
        attach_child(unitFrame, nameRegion)
        plate.UnitFrame = unitFrame
        attach_child(plate, unitFrame)
        return plate
    end

    local function snapshot_node(node)
        if type(node) ~= "table" then
            return nil
        end
        local out = {
            kind = node.__kind,
            name = node.__name,
            text = node.__text,
            shown = node.__shown,
            width = node.__width,
            height = node.__height,
            alpha = node.__alpha,
            strata = node.__strata,
            level = node.__level,
            value = node.__value,
        }
        if node.__point then
            out.point = { node.__point[1], node.__point[3], node.__point[4], node.__point[5] }
        end
        if node.__parent and node.__parent.__name then
            out.parent = node.__parent.__name
        end
        if node.__texture then
            out.texture = node.__texture
        end
        if node.__atlas then
            out.atlas = node.__atlas
        end
        if node.__colorTexture then
            out.colorTexture = Common.deep_copy(node.__colorTexture)
        end
        if node.__vertexColor then
            out.vertexColor = Common.deep_copy(node.__vertexColor)
        end
        if node.__thickness then
            out.thickness = node.__thickness
        end
        if node.__children and #node.__children > 0 then
            out.children = {}
            for _, child in ipairs(node.__children) do
                out.children[#out.children + 1] = snapshot_node(child)
            end
        end
        return out
    end

    augment_frame = function(frame, frameType, name, parent, template)
        frame.__width = frame.__width or 0
        frame.__height = frame.__height or 0
        frame.__alpha = 1
        frame.__value = frame.__value or 0
        frame.__scripts = frame.__scripts or {}
        frame.__point = frame.__point or { "CENTER", nil, "CENTER", 0, 0 }
        frame.__kind = frameType or frame.__kind or "Frame"
        frame.__name = name or frame.__name
        frame.__parent = parent or frame.__parent
        frame.__template = template or frame.__template
        frame.__children = frame.__children or {}
        frame.__regions = frame.__regions or {}
        frame.__events = frame.__events or {}
        if frame.__parent then
            attach_child(frame.__parent, frame)
        end
        function frame:GetName() return self.__name end
        function frame:GetObjectType() return self.__kind end
        function frame:GetParent() return self.__parent end
        function frame:SetParent(parentFrame)
            self.__parent = parentFrame
            attach_child(parentFrame, self)
        end
        function frame:GetEffectiveScale() return self.__effectiveScale or 1 end
        function frame:SetScale(scale) self.__effectiveScale = tonumber(scale) or 1 end
        function frame:GetLeft() return self.__left or 0 end
        function frame:GetTop() return self.__top or 0 end
        function frame:GetChildren()
            return table.unpack(self.__children or {})
        end
        function frame:SetClampedToScreen(value) self.__clamped = value and true or false end
        function frame:SetResizable(value) self.__resizable = value and true or false end
        function frame:IsResizable() return self.__resizable and true or false end
        function frame:SetResizeBounds(minW, minH, maxW, maxH)
            self.__minResizeWidth = minW
            self.__minResizeHeight = minH
            self.__maxResizeWidth = maxW
            self.__maxResizeHeight = maxH
        end
        function frame:SetMinResize(minW, minH)
            self.__minResizeWidth = minW
            self.__minResizeHeight = minH
        end
        function frame:SetBackdrop() end
        function frame:SetBackdropColor() end
        function frame:SetBackdropBorderColor() end
        function frame:SetAllPoints(relativeTo)
            self.__allPoints = relativeTo or true
        end
        function frame:SetPoint(point, relativeTo, relPoint, x, y)
            self.__point = { point, relativeTo, relPoint, x, y }
        end
        function frame:GetPoint()
            local p = self.__point or { "CENTER", nil, "CENTER", 0, 0 }
            return p[1], p[2], p[3], p[4], p[5]
        end
        function frame:ClearAllPoints()
            self.__point = { "CENTER", nil, "CENTER", 0, 0 }
        end
        function frame:SetSize(w, h)
            self.__width = w or self.__width
            self.__height = h or self.__height
        end
        function frame:SetWidth(w) self.__width = w or self.__width end
        function frame:SetHeight(h) self.__height = h or self.__height end
        function frame:GetWidth() return self.__width or 0 end
        function frame:GetHeight() return self.__height or 0 end
        function frame:SetAlpha(alpha) self.__alpha = alpha end
        function frame:GetAlpha() return self.__alpha or 1 end
        function frame:SetShown(shown)
            if shown then
                self:Show()
            else
                self:Hide()
            end
        end
        function frame:IsShown() return self.__shown end
        function frame:SetFrameStrata(strata) self.__strata = strata end
        function frame:GetFrameStrata() return self.__strata or "MEDIUM" end
        function frame:SetFrameLevel(level) self.__level = level end
        function frame:GetFrameLevel() return self.__level or 0 end
        function frame:SetMovable(value) self.__movable = value and true or false end
        function frame:IsMovable() return self.__movable and true or false end
        function frame:EnableMouse(value) self.__mouseEnabled = value and true or false end
        function frame:IsMouseEnabled() return self.__mouseEnabled and true or false end
        function frame:EnableKeyboard() end
        function frame:SetPropagateKeyboardInput(value) self.__propagateKeyboardInput = value and true or false end
        function frame:RegisterForClicks(...) self.__clickButtons = { ... } end
        function frame:RegisterForDrag(button) self.__dragButton = button end
        function frame:RegisterEvent(eventName) self.__events[eventName] = true end
        function frame:UnregisterEvent(eventName) self.__events[eventName] = nil end
        function frame:UnregisterAllEvents() self.__events = {} end
        function frame:StartMoving() self.__moving = true end
        function frame:StartSizing(anchor) self.__sizing = anchor or true end
        function frame:StopMovingOrSizing() self.__moving = false; self.__sizing = false end
        function frame:SetScript(scriptName, handler)
            self.__scripts[scriptName] = handler
        end
        function frame:HookScript(scriptName, handler)
            local previous = self.__scripts[scriptName]
            self.__scripts[scriptName] = function(owner, ...)
                if previous then
                    previous(owner, ...)
                end
                return handler(owner, ...)
            end
        end
        function frame:GetScript(scriptName)
            return self.__scripts[scriptName]
        end
        function frame:TriggerScript(scriptName, ...)
            local cb = self.__scripts[scriptName]
            if cb then
                return cb(self, ...)
            end
        end
        function frame:SetMinMaxValues(minValue, maxValue)
            self.__minValue = minValue
            self.__maxValue = maxValue
        end
        function frame:SetValue(value)
            self.__value = value
        end
        function frame:GetValue()
            return self.__value
        end
        function frame:SetValueStep(step)
            self.__valueStep = step
        end
        function frame:SetObeyStepOnDrag(enabled)
            self.__obeyStepOnDrag = enabled and true or false
        end
        function frame:SetStatusBarTexture(texture) self.__statusBarTexture = texture end
        function frame:SetStatusBarColor(r, g, b, a) self.__statusBarColor = { r, g, b, a } end
        function frame:SetReverseFill(value) self.__reverseFill = value and true or false end
        function frame:SetDrawBling(value) self.__drawBling = value and true or false end
        function frame:SetDrawEdge(value) self.__drawEdge = value and true or false end
        function frame:SetReverse(value) self.__reverse = value and true or false end
        function frame:SetHideCountdownNumbers(value) self.__hideCountdownNumbers = value and true or false end
        function frame:SetCooldown(startTime, duration) self.__cooldown = { startTime = startTime, duration = duration } end
        function frame:Clear() self.__cooldown = nil end
        function frame:SetAutoFocus() end
        function frame:SetMultiLine() end
        function frame:SetFontObject(fontObject)
            self.__fontObject = fontObject
            if type(fontObject) == "table" and type(fontObject.GetFont) == "function" then
                local path, size, flags = fontObject:GetFont()
                self.__font = { font = path, size = size, flags = flags }
            end
        end
        function frame:SetText(text) self.__text = text or "" end
        function frame:GetText() return self.__text or "" end
        function frame:SetMaxLetters(value) self.__maxLetters = value end
        function frame:HighlightText() end
        function frame:SetFocus() end
        function frame:SetScrollChild() end
        function frame:EnableMouseWheel() end
        function frame:SetClipsChildren() end
        function frame:SetVerticalScroll() end
        function frame:GetVerticalScroll() return 0 end
        function frame:GetVerticalScrollRange() return 0 end
        function frame:UpdateScrollChildRect() end
        function frame:SetNormalTexture(value) self.__normalTexture = value end
        function frame:SetHighlightTexture(value) self.__highlightTexture = value end
        function frame:SetPushedTexture(value) self.__pushedTexture = value end
        function frame:SetCheckedTexture(value) self.__checkedTexture = value end
        function frame:SetDisabledTexture(value) self.__disabledTexture = value end
        function frame:SetNormalFontObject() end
        function frame:SetDisabledFontObject() end
        function frame:SetTextInsets() end
        function frame:SetButtonState() end
        function frame:SetHitRectInsets() end
        function frame:SetChecked() end
        function frame:SetHighlight() end
        function frame:SetTexture(value) self.__texture = value end
        function frame:SetColorTexture(r, g, b, a) self.__colorTexture = { r, g, b, a } end
        function frame:SetVertexColor(r, g, b, a) self.__vertexColor = { r, g, b, a } end
        function frame:SetTexCoord() end
        function frame:SetDrawLayer() end
        function frame:SetWordWrap() end
        function frame:SetNonSpaceWrap() end
        function frame:SetJustifyH() end
        function frame:SetJustifyV() end
        function frame:SetTextColor(r, g, b, a) self.__textColor = { r, g, b, a } end
        function frame:SetShadowColor(r, g, b, a) self.__shadowColor = { r, g, b, a } end
        function frame:SetShadowOffset(x, y) self.__shadowOffset = { x, y } end
        function frame:SetFont(font, size, flags) self.__font = { font = font, size = size, flags = flags } end
        function frame:GetFont()
            if type(self.__fontObject) == "table" and type(self.__fontObject.GetFont) == "function" then
                return self.__fontObject:GetFont()
            end
            local font = self.__font or {}
            return font.font, font.size, font.flags
        end
        function frame:GetStringWidth()
            return math.max(16, #(self.__text or "") * 8)
        end
        function frame:CreateTexture(name, layer)
            local region = make_region("Texture", self, name, layer)
            self.__regions[#self.__regions + 1] = region
            attach_child(self, region)
            return region
        end
        function frame:CreateMaskTexture(name)
            local region = make_region("MaskTexture", self, name, "MASK")
            self.__regions[#self.__regions + 1] = region
            attach_child(self, region)
            return region
        end
        function frame:CreateFontString(name, layer, template)
            local region = make_region("FontString", self, name, layer)
            region.__template = template
            self.__regions[#self.__regions + 1] = region
            attach_child(self, region)
            return region
        end
        function frame:CreateLine(name, layer)
            local region = make_region("Line", self, name, layer)
            self.__regions[#self.__regions + 1] = region
            attach_child(self, region)
            return region
        end
        return frame
    end

    local namePlateDriverFrame = {
        __hooks = {},
    }
    function namePlateDriverFrame:OnNamePlateAdded() end
    function namePlateDriverFrame:UpdateNamePlateSize() end

    context.emit_event = function(eventName, ...)
        for _, frame in ipairs(frames) do
            if frame.__events and frame.__events[eventName] then
                frame:TriggerScript("OnEvent", eventName, ...)
            end
        end
    end

    systemFontNamePlate = make_font_object("SystemFont_NamePlate", init.systemFontNamePlatePath or "Fonts/FRIZQT__.TTF", init.systemFontNamePlateSize or 9, init.systemFontNamePlateFlags or "")
    systemFontNamePlateOutlined = make_font_object("SystemFont_NamePlate_Outlined", init.systemFontNamePlateOutlinedPath or "Fonts/FRIZQT__.TTF", init.systemFontNamePlateOutlinedSize or 9, init.systemFontNamePlateOutlinedFlags or "OUTLINE")

    for _, spec in ipairs(init.nameplates or {}) do
        context.nameplates[#context.nameplates + 1] = make_nameplate(spec)
    end

    local defaultSpecInfoByID = {
        [62] = { name = "奥术", icon = 200062, role = "DAMAGER", classFile = "MAGE" },
        [63] = { name = "火焰", icon = 200063, role = "DAMAGER", classFile = "MAGE" },
        [64] = { name = "冰霜", icon = 200064, role = "DAMAGER", classFile = "MAGE" },
        [65] = { name = "神圣", icon = 200065, role = "HEALER", classFile = "PALADIN" },
        [66] = { name = "防护", icon = 200066, role = "TANK", classFile = "PALADIN" },
        [70] = { name = "惩戒", icon = 200070, role = "DAMAGER", classFile = "PALADIN" },
        [71] = { name = "武器", icon = 200071, role = "DAMAGER", classFile = "WARRIOR" },
        [72] = { name = "狂怒", icon = 200072, role = "DAMAGER", classFile = "WARRIOR" },
        [73] = { name = "防护", icon = 200073, role = "TANK", classFile = "WARRIOR" },
        [102] = { name = "平衡", icon = 200102, role = "DAMAGER", classFile = "DRUID" },
        [103] = { name = "野性", icon = 200103, role = "DAMAGER", classFile = "DRUID" },
        [104] = { name = "守护", icon = 200104, role = "TANK", classFile = "DRUID" },
        [105] = { name = "恢复", icon = 200105, role = "HEALER", classFile = "DRUID" },
        [250] = { name = "鲜血", icon = 200250, role = "TANK", classFile = "DEATHKNIGHT" },
        [256] = { name = "戒律", icon = 200256, role = "HEALER", classFile = "PRIEST" },
        [257] = { name = "神圣", icon = 200257, role = "HEALER", classFile = "PRIEST" },
        [258] = { name = "暗影", icon = 200258, role = "DAMAGER", classFile = "PRIEST" },
        [264] = { name = "恢复", icon = 200264, role = "HEALER", classFile = "SHAMAN" },
        [268] = { name = "酒仙", icon = 200268, role = "TANK", classFile = "MONK" },
        [270] = { name = "织雾", icon = 200270, role = "HEALER", classFile = "MONK" },
        [577] = { name = "浩劫", icon = 200577, role = "DAMAGER", classFile = "DEMONHUNTER" },
        [581] = { name = "复仇", icon = 200581, role = "TANK", classFile = "DEMONHUNTER" },
        [1468] = { name = "恩护", icon = 201468, role = "HEALER", classFile = "EVOKER" },
        [1473] = { name = "增辉", icon = 201473, role = "DAMAGER", classFile = "EVOKER" },
    }

    local env = Common.new_base_env({
        CreateFrame = function(frameType, name, parent, template)
            local frame = augment_frame(Common.make_frame(), frameType, name, parent, template)
            frames[#frames + 1] = frame
            return frame
        end,
        CreateFont = function(name)
            return make_font_object(name, "Fonts/FRIZQT__.TTF", 12, "")
        end,
        C_Timer = {
            After = function(delay, fn)
                context.timers[#context.timers + 1] = delay
                if init.manualTimers and type(fn) == "function" then
                    context.timerCallbacks[#context.timerCallbacks + 1] = { delay = delay, fn = fn }
                elseif type(fn) == "function" then
                    fn()
                end
            end,
            NewTimer = function(delay, fn)
                local timer = { cancelled = false }
                function timer:Cancel() self.cancelled = true end
                context.timers[#context.timers + 1] = delay
                if init.manualTimers and type(fn) == "function" then
                    context.timerCallbacks[#context.timerCallbacks + 1] = { delay = delay, fn = fn, timer = timer }
                elseif type(fn) == "function" then
                    fn()
                end
                return timer
            end,
        },
        C_VoiceChat = {
            SpeakText = function(voiceID, text, rate, volume, overlap)
                context.speakCalls[#context.speakCalls + 1] = {
                    voiceID = voiceID,
                    text = text,
                    rate = rate,
                    volume = volume,
                    overlap = overlap,
                }
            end,
            StopSpeakingText = function() end,
            GetTtsVoices = function()
                return {}
            end,
        },
        PlaySoundFile = function(path, channel)
            context.soundCalls[#context.soundCalls + 1] = {
                path = path,
                channel = channel,
            }
            return true, #context.soundCalls
        end,
        C_Spell = {
            GetSpellTexture = function(spellID)
                local textureMap = init.spellTextureMap or {}
                return textureMap[spellID] or textureMap[tostring(spellID)]
            end,
            GetSpellName = function(spellID)
                local infoMap = init.spellInfoMap or {}
                local map = init.spellNameMap or {}
                local info = infoMap[spellID] or {}
                return info.name or map[spellID] or ("Spell" .. tostring(spellID))
            end,
            GetSpellInfo = function(spellID)
                local nameMap = init.spellNameMap or {}
                local infoMap = init.spellInfoMap or {}
                local info = infoMap[spellID] or {}
                return {
                    name = info.name or nameMap[spellID] or ("Spell" .. tostring(spellID)),
                    iconID = info.iconID or (spellID and (100000 + tonumber(spellID)) or nil),
                    spellID = spellID,
                }
            end,
        },
        C_EncounterTimeline = {
            GetEventInfo = function(eventID)
                local map = init.encounterTimelineEventInfoMap or {}
                return map[eventID]
            end,
            GetEventState = function(eventID)
                local map = init.encounterTimelineEventStateMap or {}
                return map[eventID]
            end,
        },
        C_EncounterEvents = {
            HasEventInfo = function(eventID)
                local map = init.encounterEventsInfoMap or {}
                return map[eventID] ~= nil
            end,
            GetEventInfo = function(eventID)
                local map = init.encounterEventsInfoMap or {}
                return map[eventID]
            end,
        },
        Enum = Common.deep_copy(init.enumMap or {
            EncounterTimelineEventSource = {
                Encounter = 0,
            },
            EncounterTimelineEventState = {
                Finished = 2,
                Canceled = 3,
            },
        }),
        STT = STT,
        STT_DB = C.DB,
        STANDARD_TEXT_FONT = init.standardTextFont or "STANDARD_TEXT_FONT",
        VMRT = init.VMRT,
        VExRT = init.VExRT,
        GetTime = function()
            return context.now
        end,
        geterrorhandler = function()
            return function(err)
                error(err)
            end
        end,
        UnitExists = function(unit)
            local value = context.unitExistsMap[tostring(unit or "")]
            if value == nil then
                return true
            end
            return value == true
        end,
        GetCursorPosition = function()
            return init.cursorX or 100, init.cursorY or -100
        end,
        IsKeyDown = function(key)
            return context.keyDownMap[tostring(key or "")] == true
        end,
        IsControlKeyDown = function()
            return context.keyModifiers.ctrl == true
        end,
        IsMetaKeyDown = function()
            return context.keyModifiers.meta == true
        end,
        IsShiftKeyDown = function()
            return context.keyModifiers.shift == true
        end,
        IsAltKeyDown = function()
            return context.keyModifiers.alt == true
        end,
        MouseIsOver = function()
            return true
        end,
        GetCVar = function(name)
            return context.cvars[name]
        end,
        SetCVar = function(name, value)
            local normalized = value
            if type(normalized) == "boolean" then
                normalized = normalized and "1" or "0"
            elseif normalized ~= nil then
                normalized = tostring(normalized)
            end
            context.cvars[name] = normalized
            context.setCVarCalls[#context.setCVarCalls + 1] = {
                name = name,
                value = normalized,
            }
        end,
        GetInstanceInfo = function()
            return init.instanceName or "", context.instanceType or init.instanceType or "none", context.difficultyID
        end,
        hooksecurefunc = function(target, methodName, hook)
            if type(methodName) ~= "string" or type(hook) ~= "function" then
                return
            end
            if type(target) == "table" then
                target.__hooks = target.__hooks or {}
                target.__hooks[methodName] = target.__hooks[methodName] or {}
                target.__hooks[methodName][#target.__hooks[methodName] + 1] = hook
            end
            context.hookRegistry[methodName] = context.hookRegistry[methodName] or {}
            context.hookRegistry[methodName][#context.hookRegistry[methodName] + 1] = hook
        end,
        issecurevariable = function()
            return true
        end,
        C_NamePlate = {
            GetNamePlates = function()
                return context.nameplates
            end,
            GetNamePlateForUnit = function(unit)
                for _, plate in ipairs(context.nameplates) do
                    local unitFrame = plate and plate.UnitFrame
                    if unitFrame and unitFrame.unit == unit then
                        return plate
                    end
                end
                return nil
            end,
        },
        NamePlateDriverFrame = namePlateDriverFrame,
        NamePlateFriendlyFrameOptions = Common.deep_copy(init.namePlateFriendlyFrameOptions or {
            updateNameUsesGetUnitName = true,
        }),
        SystemFont_NamePlate = systemFontNamePlate,
        SystemFont_NamePlate_Outlined = systemFontNamePlateOutlined,
        TextureLoadingGroupMixin = {
            RemoveTexture = function() end,
            AddTexture = function() end,
        },
        UnitName = function()
            return init.playerName or "Tester"
        end,
        UnitGUID = function()
            return "Player-0-TEST"
        end,
        UnitClass = function()
            return init.playerClassLocalized or "战士", init.playerClassToken or "WARRIOR"
        end,
        C_ClassColor = {
            GetClassColor = function(classFile)
                local colors = init.classColors or {
                    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
                    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
                    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
                    ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
                    PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
                    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
                    SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
                    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
                    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
                    MONK = { r = 0.00, g = 1.00, b = 0.59 },
                    DRUID = { r = 1.00, g = 0.49, b = 0.04 },
                    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
                    EVOKER = { r = 0.20, g = 0.58, b = 0.50 },
                }
                return colors[tostring(classFile or ""):upper()]
            end,
        },
        RAID_CLASS_COLORS = Common.deep_copy(init.classColors or {
            WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
            PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
            HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
            ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
            PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
            DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
            SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
            MAGE = { r = 0.25, g = 0.78, b = 0.92 },
            WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
            MONK = { r = 0.00, g = 1.00, b = 0.59 },
            DRUID = { r = 1.00, g = 0.49, b = 0.04 },
            DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
            EVOKER = { r = 0.20, g = 0.58, b = 0.50 },
        }),
        UnitGroupRolesAssigned = function()
            return init.playerRole or "DAMAGER"
        end,
        IsInRaid = function()
            return not not init.inRaid
        end,
        GetNumGroupMembers = function()
            local roster = init.raidRoster or {}
            return #roster
        end,
        GetRaidRosterInfo = function(idx)
            local roster = init.raidRoster or {}
            local row = roster[idx]
            if not row then
                return nil
            end
            return row.name, nil, row.subgroup
        end,
        GetSpecialization = function()
            return init.specIndex
        end,
        GetSpecializationInfo = function(index)
            local specID = init.specID
            local specInfoByIndex = init.specInfoByIndex or {}
            local byIndex = specInfoByIndex[index]
            if byIndex then
                specID = byIndex.specID or byIndex.id or specID
            end
            return specID
        end,
        GetSpecializationInfoByID = function(specID)
            local id = tonumber(specID)
            local custom = init.specInfoByID or {}
            local info = custom[id] or defaultSpecInfoByID[id]
            if not info then
                return id, "Spec" .. tostring(id), "", id and (200000 + id) or nil, "DAMAGER", nil
            end
            return id, info.name or ("Spec" .. tostring(id)), "", info.icon, info.role, info.classFile
        end,
        strjoin = function(sep, ...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            return table.concat(parts, sep)
        end,
        tostringall = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            return table.unpack(parts)
        end,
        wipe = function(tbl)
            if type(tbl) ~= "table" then return tbl end
            for k in pairs(tbl) do
                tbl[k] = nil
            end
            return tbl
        end,
    })

    env.L_UIDropDownMenu_CreateInfo = function()
        return {}
    end
    env.L_UIDropDownMenu_SetWidth = function(dropdown, width)
        if type(dropdown) == "table" then
            dropdown.__dropdownWidth = width
        end
    end
    env.L_UIDropDownMenu_Initialize = function(dropdown, initializer)
        if type(dropdown) == "table" then
            dropdown.__dropdownInitializer = initializer
        end
    end
    env.L_UIDropDownMenu_AddButton = function(info, level)
        context.dropdownButtons = context.dropdownButtons or {}
        context.dropdownButtons[level or 1] = context.dropdownButtons[level or 1] or {}
        context.dropdownButtons[level or 1][#context.dropdownButtons[level or 1] + 1] = Common.deep_copy(info)
    end
    env.L_UIDropDownMenu_SetText = function(dropdown, text)
        if type(dropdown) == "table" then
            dropdown.__dropdownText = text
        end
    end

    context.instanceType = init.instanceType or "none"

    local function file_exists(path)
        local fp = io.open(path, "r")
        if fp then
            fp:close()
            return true
        end
        return false
    end

    context.ensure_diagnose_module = function()
        if T.Diagnose and T.Diagnose.ScanSelfHits then
            return
        end
        local diagnosePath = repo_root .. "/ShengTangTools/options/diagnose_options.lua"
        if file_exists(diagnosePath) then
            load_file_in_env(diagnosePath, env, ns)
        end
        for _, module in ipairs(T.__optionModules or {}) do
            if module.id == "diagnose" and type(module.itemsFactory) == "function" then
                module.itemsFactory()
            end
        end
    end

    for _, file in ipairs(FILES) do
        if file_exists(file) then
            load_file_in_env(file, env, ns)
        end
    end

	    if type(T.Init_callbacks) == "table" then
	        for _, func in ipairs(T.Init_callbacks) do
	            if type(func) == "function" then
	                func()
	            end
	        end
	    end

    if not T.CountdownPacks then
        T.CountdownPacks = {
            Resolve = function(number)
                return "Interface\\AddOns\\ShengTangTools\\media\\STTaudio\\Announcer_" .. tostring(number) .. ".ogg"
            end,
            GetChannel = function()
                return C.DB.CountdownChannel or "Master"
            end,
        }
    end
    if not T.ShowBar then
        T.ShowBar = function(opts)
            context.barCalls[#context.barCalls + 1] = Common.deep_copy(opts or {})
            return true
        end
    end
    if not T.ClearAllBars then
        T.ClearAllBars = function()
            context.barCalls[#context.barCalls + 1] = { clear = true }
        end
    end
    if C.DB.realtimeBoard and C.DB.realtimeBoard.enabled == true and not T.RealtimeBoard then
        T.RealtimeBoard = {
            Start = function(_, timeline, startTime, isTest, opts)
                local rows = {}
                for _, event in ipairs(timeline or {}) do
                    rows[#rows + 1] = {
                        time = tonumber(event.time),
                        text = tostring(event.text or ""),
                        condition = event.condition,
                    }
                end
                context.realtimeBoardStarts[#context.realtimeBoardStarts + 1] = {
                    count = #rows,
                    rows = rows,
                    isTest = isTest and true or false,
                    staticPreview = type(opts) == "table" and opts.staticPreview == true or false,
                    hasStartTime = tonumber(startTime) ~= nil,
                }
                return true
            end,
            Stop = function(_, cause)
                context.realtimeBoardStops[#context.realtimeBoardStops + 1] = tostring(cause or "")
            end,
        }
    end

	    -- 兼容 timeline_syntax.lua 当前实现对全局 self 的依赖
	    -- （函数定义使用点号但函数体内部访问 self）
    env.self = T.TimelineSyntax

    local exportImportContext = nil
    local ensure_export_import_context

    local function file_exists_local(path)
        local fp = io.open(path, "r")
        if fp then
            fp:close()
            return true
        end
        return false
    end

    local function simplify_export_summary(summary)
        if type(summary) ~= "table" then
            return nil
        end
        return {
            typeCode = summary.typeCode,
            typeName = summary.typeName,
            version = summary.version,
            exportTime = summary.exportTime,
            exporterName = summary.exporterName,
            exporterVersion = summary.exporterVersion,
            planCount = summary.planCount,
            personalPlanCount = summary.personalPlanCount,
            settingsCount = summary.settingsCount,
        }
    end

    local function set_nested_path(root, path, value)
        local current = root
        local parts = {}
        for part in tostring(path or ""):gmatch("[^%.]+") do
            parts[#parts + 1] = part
        end
        if #parts == 0 then
            return
        end
        for index = 1, #parts - 1 do
            local key = parts[index]
            if type(current[key]) ~= "table" then
                current[key] = {}
            end
            current = current[key]
        end
        current[parts[#parts]] = Common.deep_copy(value)
    end

    local function get_nested_path(root, path)
        local current = root
        for part in tostring(path or ""):gmatch("[^%.]+") do
            if type(current) ~= "table" then
                return nil
            end
            current = current[part]
        end
        return Common.deep_copy(current)
    end

    local function read_text_file(path)
        local fp = io.open(path, "r")
        if not fp then
            return nil
        end
        local text = fp:read("*a")
        fp:close()
        return text
    end

    local function register_schema_path_nodes(root, prefix, out)
        if prefix and prefix ~= "" then
            out[prefix] = true
        end
        if type(root) ~= "table" then
            return
        end
        for key, value in pairs(root) do
            local child = prefix and prefix ~= "" and (prefix .. "." .. tostring(key)) or tostring(key)
            register_schema_path_nodes(value, child, out)
        end
    end

    local function eval_static_string_expr(expr, constants)
        local source = tostring(expr or ""):gsub("%s+", "")
        if source == "" then
            return nil
        end

        local out = ""
        local pos = 1
        while pos <= #source do
            local start_pos, end_pos, value = source:find('^"([^"]*)"', pos)
            if not start_pos then
                start_pos, end_pos, value = source:find("^'([^']*)'", pos)
            end
            if not start_pos then
                local name
                start_pos, end_pos, name = source:find("^([%a_][%w_]*)", pos)
                value = name and constants[name] or nil
            end
            if not start_pos or value == nil then
                return nil
            end

            out = out .. value
            pos = end_pos + 1
            if pos <= #source then
                if source:sub(pos, pos + 1) ~= ".." then
                    return nil
                end
                pos = pos + 2
            end
        end

        return out ~= "" and out or nil
    end

    local function collect_option_db_paths()
        local pipe = io.popen("find '" .. repo_root .. "/ShengTangTools/options' -type f -name '*.lua' | sort")
        if not pipe then
            return {}
        end

        local paths = {}
        for file in pipe:lines() do
            local text = read_text_file(file)
            if text then
                text = text:gsub("%-%-[^\n]*", "")
                local constants = {}
                local changed = true
                while changed do
                    changed = false
                    for name, expr in text:gmatch("local%s+([%a_][%w_]*)%s*=%s*([^\n,]+)") do
                        local value = eval_static_string_expr(expr, constants)
                        if value and constants[name] ~= value then
                            constants[name] = value
                            changed = true
                        end
                    end
                end

                for expr in text:gmatch("dbPath%s*=%s*([^,}\n]+)") do
                    local path = eval_static_string_expr(expr, constants)
                    if path then
                        paths[path] = file:gsub("^" .. repo_root:gsub("([^%w])", "%%%1") .. "/", "")
                    end
                end
            end
        end
        pipe:close()
        return paths
    end

    local function audit_settings_schema()
        local ei = ensure_export_import_context()
        local schema_paths = {}
        register_schema_path_nodes(ei.C.defaults or {}, nil, schema_paths)

        local explicit_exclude = {
            mynickname = true,
            preferredLocale = true,
            ["screenReminder.__fullConfig"] = true,
            ["screenReminder.__indicatorMerge"] = true,
            ["personalAuraAlert.__fullConfig"] = true,
            ["personalAuraAlert.__ruleMerge"] = true,
        }

        local missing = {}
        for path, file in pairs(collect_option_db_paths()) do
            if not explicit_exclude[path] and not schema_paths[path] then
                missing[#missing + 1] = path .. " <- " .. file
            end
        end
        table.sort(missing)
        return {
            ok = #missing == 0,
            missing = missing,
        }
    end

    local function get_export_import_note_db(ei)
        if ei and ei.T and ei.T.Profile and ei.T.Profile.GetActiveData then
            return ei.T.Profile:GetActiveData()
        end
        return ei and ei.env and ei.env.STT_DB and ei.env.STT_DB.Note or {}
    end

    local function build_export_import_snapshot(ei, options)
        local note = ei.T.Note
        local noteDB = get_export_import_note_db(ei)
        local snapshot = {
            semantic = {},
            personal = {},
            settings = {},
        }
        local instanceType = options and options.instanceType or nil

        for bossKey, planID in pairs(noteDB.SemanticPlanIDByBossKey or {}) do
            if not instanceType or tostring(bossKey):sub(1, #instanceType + 1) == (instanceType .. ":") then
                local plan = note:GetPlan(planID)
                if plan then
                    snapshot.semantic[bossKey] = {
                        name = plan.name,
                        content = plan.content,
                        author = plan.author,
                        createdTime = plan.created,
                        lastUpdateName = plan.lastUpdateName,
                        lastUpdateTime = plan.lastUpdateTime,
                        kind = plan.kind,
                    }
                end
            end
        end

        for bossKey, planID in pairs(noteDB.PersonalBossPlans or {}) do
            if not instanceType or tostring(bossKey):sub(1, #instanceType + 1) == (instanceType .. ":") then
                local plan = note:GetPlan(planID)
                if plan then
                    snapshot.personal[bossKey] = {
                        name = plan.name,
                        content = plan.content,
                        author = plan.author,
                        createdTime = plan.created,
                        lastUpdateName = plan.lastUpdateName,
                        lastUpdateTime = plan.lastUpdateTime,
                        kind = plan.kind,
                    }
                end
            end
        end

        for _, path in ipairs((options and options.settingsPaths) or {}) do
            snapshot.settings[path] = get_nested_path(ei.env.STT_DB, path)
        end

        return snapshot
    end

    local function reset_export_import_state(ei)
        ei.env.STT_DB = {}
        ei.C.DB = ei.env.STT_DB
        ei.T.Note:InitDB()
        ei.C.DB = ei.env.STT_DB
        ei.lastText = nil
    end

    local function seed_export_import_state(ei, seed)
        reset_export_import_state(ei)
        seed = seed or {}

        deep_merge(ei.env.STT_DB, Common.deep_copy(seed.db or {}))
        ei.C.DB = ei.env.STT_DB

        for bossKey, plan in pairs(seed.semanticPlans or {}) do
            local planID = ei.T.Note:UpsertSemanticBossPlan(
                bossKey,
                tostring(plan.name or ""),
                tostring(plan.content or ""),
                {
                    forceContent = true,
                    authorName = tostring(plan.lastUpdateName or ""),
                    timestamp = tonumber(plan.lastUpdateTime or 0) or nil,
                    planAuthor = tostring(plan.author or ""),
                }
            )
            if planID then
                local noteDB = get_export_import_note_db(ei)
                noteDB.PlanCreatedTime[planID] = tonumber(plan.createdTime or 0) or noteDB.PlanCreatedTime[planID]
            end
        end

        for bossKey, plan in pairs(seed.personalPlans or {}) do
            local planID = ei.T.Note:UpsertPersonalBossPlan(
                bossKey,
                tostring(plan.name or ""),
                tostring(plan.content or ""),
                {
                    forceContent = true,
                    authorName = tostring(plan.lastUpdateName or ""),
                    timestamp = tonumber(plan.lastUpdateTime or 0) or nil,
                    planAuthor = tostring(plan.author or ""),
                }
            )
            if planID then
                local noteDB = get_export_import_note_db(ei)
                noteDB.PlanCreatedTime[planID] = tonumber(plan.createdTime or 0) or noteDB.PlanCreatedTime[planID]
            end
        end

        for path, value in pairs(seed.settings or {}) do
            set_nested_path(ei.env.STT_DB, path, value)
        end
    end

    ensure_export_import_context = function()
        if exportImportContext then
            return exportImportContext
        end

        local ei_env = Common.new_base_env({
            CreateFrame = function(frameType, name, parent, template)
                return augment_frame(Common.make_frame(), frameType, name, parent, template)
            end,
            C_Timer = {
                After = function(_, fn)
                    if type(fn) == "function" then
                        fn()
                    end
                end,
            },
            UnitName = function()
                return init.playerName or "Tester"
            end,
            UnitGUID = function()
                return "Player-0-TEST"
            end,
            time = function()
                return context.now
            end,
            date = function(fmt, ts)
                return os.date(fmt, ts)
            end,
            ReloadUI = function()
                exportImportContext.reloadUICount = (exportImportContext.reloadUICount or 0) + 1
            end,
            C_AddOns = {
                GetAddOnInfo = function()
                    return "ShengTangTools", "ShengTang Tools"
                end,
                GetAddOnMetadata = function(_, key)
                    if key == "Version" then
                        return init.addonVersion or "260323.25"
                    end
                    return nil
                end,
            },
            GetLocale = function()
                return "zhCN"
            end,
            strmatch = string.match,
            strfind = string.find,
            strsub = string.sub,
            strgsub = string.gsub,
            strlen = string.len,
            strbyte = string.byte,
            strchar = string.char,
            strlower = string.lower,
            strupper = string.upper,
            format = string.format,
            tinsert = table.insert,
            tremove = table.remove,
            tsort = table.sort,
            STT_DB = {},
        })
        local ei_ns = { {}, {}, {} }

        for _, file in ipairs(EXPORT_IMPORT_FILES) do
            if file_exists_local(file) then
                load_file_in_env(file, ei_env, ei_ns)
                if file:match("/core/init%.lua$") then
                    ei_env.STT_DB.semanticTimeline = ei_env.STT_DB.semanticTimeline or {}
                    ei_env.STT_DB.semanticTimeline.runtimeEnabled = true
                    ei_ns[1].RuntimeColdFeatures = ei_ns[1].RuntimeColdFeatures or {}
                    ei_ns[1].RuntimeColdFeatures["semanticTimeline.editorLoaded"] = true
                end
            end
        end

        local ei_T = ei_ns[1]
        local ei_C = ei_ns[2]
        local ei_L = ei_ns[3]

        if ei_T.LoadColdFilesForDesired then
            ei_T.LoadColdFilesForDesired()
        end

        for _, func in ipairs(ei_T.Init_callbacks or {}) do
            if type(func) == "function" then
                func()
            end
        end

        exportImportContext = {
            env = ei_env,
            ns = ei_ns,
            T = ei_T,
            C = ei_C,
            L = ei_L,
            lastText = nil,
            reloadUICount = 0,
        }

        seed_export_import_state(exportImportContext, init.exportImport or {})
        return exportImportContext
    end

    context.ensure_export_import_context = ensure_export_import_context
    context.seed_export_import_state = seed_export_import_state
    context.build_export_import_snapshot = build_export_import_snapshot
    context.simplify_export_summary = simplify_export_summary
    context.audit_settings_schema = audit_settings_schema

    local function record_tactical_notice(action, data)
        local payload = Common.deep_copy(data or {})
        if action == "show" then
            context.screenReminderShowIndex = (context.screenReminderShowIndex or 0) + 1
            local plan = context.screenReminderPlan and context.screenReminderPlan[context.screenReminderShowIndex] or nil
            if plan then
                if payload.ttsText == nil and plan.ttsText ~= nil then
                    payload.ttsText = plan.ttsText
                end
                if payload.spellID == nil and plan.spellID ~= nil then
                    payload.spellID = plan.spellID
                end
                if payload.spellIcon == nil and plan.spellIcon ~= nil then
                    payload.spellIcon = plan.spellIcon
                end
                if payload.isSilent == nil and plan.isSilent ~= nil then
                    payload.isSilent = plan.isSilent
                end
            end
        end
        context.screenReminderCalls[#context.screenReminderCalls + 1] = {
            action = action,
            data = payload,
        }
    end

    local function strip_silent_markers(text)
        local value = tostring(text or "")
        value = value:gsub("<[^>]+>", "")
        value = value:gsub("~~.-~~", "")
        value = value:gsub("%s+", " ")
        return value:gsub("^%s+", ""):gsub("%s+$", "")
    end

    local RAID_MARKER_MAP = {
        ["{star}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t",
        ["{circle}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:0|t",
        ["{diamond}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:0|t",
        ["{triangle}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:0|t",
        ["{moon}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:0|t",
        ["{square}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:0|t",
        ["{cross}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:0|t",
        ["{skull}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t",
    }

    local function resolve_raid_markers(text)
        local value = tostring(text or "")
        value = value:gsub("({%a+})", RAID_MARKER_MAP)
        return value
    end

    local function resolve_spell_icon(spellID)
        if not spellID then return nil end
        if T.TimelineSyntax and T.TimelineSyntax.ResolveSpellIcon then
            return T.TimelineSyntax.ResolveSpellIcon(spellID)
        end
        local info = env.C_Spell and env.C_Spell.GetSpellInfo and env.C_Spell.GetSpellInfo(spellID)
        return info and info.iconID or nil
    end

    local function collect_frame_states()
        local out = {}
        for _, frame in ipairs(context.frames) do
            if type(frame) == "table" and frame.__name then
                out[#out + 1] = snapshot_node(frame)
            end
        end
        return out
    end

    local had_real_tactical_notice = type(T.TacticalNotice) == "table" and type(T.ScreenReminder) == "table"
    local build_tactical_notice_plan
    local emit_pending_tactical_notices

    local function get_current_tactical_notice_text()
        local text = nil
        if C.DB.dataSource == "STN" and T.Note and T.Note.GetActivePlan then
            local plan = T.Note:GetActivePlan()
            text = plan and plan.content or ""
        elseif env.VMRT and env.VMRT.Note then
            local note = env.VMRT.Note
            if C.DB.useRaidNote and note.Text1 then
                text = (text and (text .. "\n") or "") .. (note.Text1 or "")
            end
            if C.DB.useSelfNote and note.SelfText then
                text = (text and (text .. "\n") or "") .. (note.SelfText or "")
            end
        end
        return text or ""
    end

    local function ensure_tactical_notice_runtime()
        if not T.TacticalNotice then
            T.TacticalNotice = {}
        end

        if T.TacticalNotice.__automationWrapped then
            return
        end

        local runtime = T.TacticalNotice
        local origShow = runtime.ShowReminder
        local origClear = runtime.ClearAll
        local origLoad = runtime.LoadSettings
        local origSetLocked = runtime.SetLocked
        local origRunTest = runtime.RunTest

        runtime.ShowReminder = function(self, data)
            record_tactical_notice("show", data)
            if type(origShow) == "function" then
                return origShow(self, data)
            end
            return true
        end

        runtime.ClearAll = function(self)
            context.screenReminderClearCount = context.screenReminderClearCount + 1
            context.screenReminderPlan = nil
            context.screenReminderEmitted = {}
            context.screenReminderShowIndex = 0
            context.screenReminderStartTime = nil
            record_tactical_notice("clear", {})
            if type(origClear) == "function" then
                return origClear(self)
            end
        end

        runtime.LoadSettings = function(self)
            context.screenReminderLoadCount = context.screenReminderLoadCount + 1
            record_tactical_notice("load", {})
            if type(origLoad) == "function" then
                return origLoad(self)
            end
        end

        runtime.SetLocked = function(self, locked, opts)
            record_tactical_notice(locked and "lock" or "unlock", { locked = locked and true or false })
            if type(origSetLocked) == "function" then
                return origSetLocked(self, locked, opts)
            end
            if locked then
                T.msg("战术提示位置已锁定")
            else
                T.msg("战术提示位置已解锁，可以拖拽和缩放")
            end
            if self.LoadSettings then
                self:LoadSettings()
            end
        end

        runtime.RunTest = function(self, opts)
            record_tactical_notice("test", {})
            if type(origRunTest) == "function" then
                return origRunTest(self, opts)
            end
            T.msg("开始测试战术提示")
            if self.LoadSettings then
                self:LoadSettings()
            end
            if self.ClearAll then
                self:ClearAll()
            end
            local text = get_current_tactical_notice_text()
            if text == "" then
                T.msg("当前数据源没有可测试的战术提示")
                self:ShowReminder({
                    text = "当前数据源没有可测试的战术提示",
                    ttsText = "",
                    isSilent = true,
                    duration = 4,
                    spellIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
                })
            elseif build_tactical_notice_plan then
                local built = build_tactical_notice_plan(text, true)
                for _, event in ipairs(built or {}) do
                    self:ShowReminder({
                        text = event.text,
                        duration = 3,
                        spellID = event.spellID,
                        spellIcon = event.spellIcon,
                        isSilent = event.isSilent,
                        ttsText = event.ttsText or strip_silent_markers(event.text),
                    })
                end
            end
            T.msg("测试战术提示完成")
            return true
        end

        if type(T.HandleTacticalNoticeCommand) ~= "function" then
            T.HandleTacticalNoticeCommand = function(_, args)
                local sub = tostring(args or ""):match("^%s*(.-)%s*$")
                sub = sub:lower()
                if sub == "" or sub == "help" then
                    T.msg("战术提示命令: test / clear / lock / unlock / on / off")
                    return true
                elseif sub == "unlock" then
                    runtime:SetLocked(false)
                    return true
                elseif sub == "lock" then
                    runtime:SetLocked(true)
                    return true
                elseif sub == "test" then
                    runtime:RunTest()
                    return true
                elseif sub == "clear" then
                    runtime:ClearAll()
                    T.msg("战术提示已清空")
                    return true
                elseif sub == "on" then
                    tactical_notice_mock.enabled = true
                    ensure_tactical_notice_frames()
                    T.msg("战术提示已开启")
                    return true
                elseif sub == "off" then
                    tactical_notice_mock.enabled = false
                    clear_tactical_notice_samples()
                    T.msg("战术提示已关闭")
                    return true
                end
                T.msg("未知战术提示子命令: " .. tostring(args or ""))
                return false
            end
        end

        runtime.__automationWrapped = true
    end

    ensure_tactical_notice_runtime()
    if context.screenReminderLoadCount == 0 and T.TacticalNotice and T.TacticalNotice.LoadSettings then
        T.TacticalNotice:LoadSettings()
    end
    context.screenReminderHasRealModule = had_real_tactical_notice

    build_tactical_notice_plan = function(text, isTest)
        local parsed = T.NoteParser and T.NoteParser.ParseNote and T.NoteParser:ParseNote(text or "") or {}
        local built = T.BuildTimelineEvents and T.BuildTimelineEvents(parsed, {}) or {}
        for _, item in ipairs(built or {}) do
            item.ttsText = item.ttsText or strip_silent_markers(item.text)
            item.spellIcon = item.spellIcon or resolve_spell_icon(item.spellID)
            if item.isSilent == nil then
                item.isSilent = (item.ttsText ~= item.text)
            end
        end
        context.screenReminderPlan = built
        context.screenReminderEmitted = {}
        context.screenReminderShowIndex = 0
        context.screenReminderStartTime = context.now
        context.screenReminderIsTest = isTest and true or false
        return built
    end

    emit_pending_tactical_notices = function()
        if type(context.screenReminderPlan) ~= "table" or not T.TacticalNotice or not T.TacticalNotice.ShowReminder then
            return
        end

        local startTime = context.screenReminderStartTime or context.now
        local elapsed = math.max(0, context.now - startTime)
        for _, event in ipairs(context.screenReminderPlan) do
            local showTime = tonumber(event.showTime) or 0
            local key = tostring(event.time) .. "|" .. tostring(event.text or "")
            if elapsed >= showTime and not context.screenReminderEmitted[key] then
                context.screenReminderEmitted[key] = true
                local remaining = math.max(0, (tonumber(event.time) or 0) - elapsed)
                T.TacticalNotice:ShowReminder({
                    text = event.text,
                    duration = remaining,
                    spellID = event.spellID,
                    spellIcon = event.spellIcon or resolve_spell_icon(event.spellID),
                    isSilent = event.isSilent,
                    ttsText = event.ttsText or strip_silent_markers(event.text),
                })
            end
        end
    end

    local function collect_screen_state()
        return {
            screenReminderCalls = Common.deep_copy(context.screenReminderCalls),
            screenReminderLoadCount = context.screenReminderLoadCount,
            screenReminderClearCount = context.screenReminderClearCount,
            screenReminderFrames = collect_frame_states(),
        }
    end

    context.resolve_raid_markers = resolve_raid_markers
    context.strip_silent_markers = strip_silent_markers
    context.resolve_spell_icon = resolve_spell_icon
    context.build_tactical_notice_plan = build_tactical_notice_plan
    context.emit_pending_tactical_notices = emit_pending_tactical_notices
    context.collect_screen_state = collect_screen_state
    context.get_font_triplet = get_font_triplet

    if init.note then
        T.Note = {
            GetPlan = function(_, id)
                if id then
                    return init.note[id]
                end
                return init.note.default
            end,
            GetActivePlan = function()
                return init.note.default
            end,
        }
    end

    if init.semanticTimeline then
        T.SemanticTimeline = init.semanticTimeline
    elseif init.selectedEncounterID or init.encounterSpellCatalog then
        local selectedEncounterID = tonumber(init.selectedEncounterID) or 0
        local encounterSpellCatalog = Common.deep_copy(init.encounterSpellCatalog or {})
        T.SemanticTimeline = {
            GetCurrentBossSelectorKey = function()
                return { encounterID = selectedEncounterID }
            end,
            GetEncounterSpellCatalog = function()
                return Common.deep_copy(encounterSpellCatalog)
            end,
        }
    end

    context.env = env
    context.T = T
    context.C = C
    context.L = L
    context.STT = STT
    context.ns = ns

    return context
end

local function run_onupdate_frames(context, elapsed)
    for _, frame in ipairs(context.frames) do
        if frame:IsShown() then
            frame:RunOnUpdate(elapsed)
        end
    end
end

local function build_personnel_context(context, template)
    if context.T.HorizontalTimelineData and context.T.HorizontalTimelineData.ExtractPersonnelContext then
        return context.T.HorizontalTimelineData.ExtractPersonnelContext(template and template.sourceText or "")
    end
    return nil, nil
end

local function process_events(context, events)
    local function semantic_file_exists(path)
        local fp = io.open(path, "r")
        if fp then
            fp:close()
            return true
        end
        return false
    end

    local function ensure_semantic_timeline()
        if context.T.SemanticTimeline and context.T.SemanticTimeline.CompileResolvedPlanContent then
            return context.T.SemanticTimeline
        end
        context.env.time = context.env.time or function()
            return context.now
        end
        load_file_in_env(repo_root .. "/ShengTangTools/core/semantic_timeline.lua", context.env, context.ns)
        return context.T.SemanticTimeline
    end

    local function ensure_note_store()
        context.env.time = context.env.time or function()
            return math.floor(context.now or 0)
        end
        if not context.T.Profile then
            load_file_in_env(repo_root .. "/ShengTangTools/core/profile.lua", context.env, context.ns)
        end
        if not context.T.Note then
            load_file_in_env(repo_root .. "/ShengTangTools/core/note.lua", context.env, context.ns)
        end
        if not context.T.Profile:GetActiveProfileID() then
            local profileID = context.T.Profile:Create("自动化测试")
            context.T.Profile:SetActive(profileID)
        end
        return context.T.Note
    end

    local function ensure_semantic_template_runtime()
        context.env.time = context.env.time or function()
            return math.floor(context.now or 0)
        end
        context.env.GetLocale = context.env.GetLocale or function()
            return "zhCN"
        end

        for _, file in ipairs(SEMANTIC_TEMPLATE_FILES) do
            if semantic_file_exists(file) then
                local before = {
                    profile = context.T.Profile ~= nil,
                    note = context.T.Note ~= nil,
                    semantic = context.T.SemanticTimeline ~= nil and context.T.SemanticTimeline.EnsureSemanticBossPlansInitialized ~= nil,
                    reloader = context.T.SemanticTemplateReload ~= nil,
                }
                if (file:match("/core/profile%.lua$") and not before.profile)
                    or (file:match("/core/note%.lua$") and not before.note)
                    or (file:match("/core/semantic_timeline%.lua$") and not before.semantic)
                    or (file:match("/core/semantic_template_reload%.lua$") and not before.reloader) then
                    load_file_in_env(file, context.env, context.ns)
                end
            end
        end

        if not context.T.SemanticTimeline or not context.T.SemanticTemplateReload then
            error("semantic template runtime missing")
        end
        return context.T.SemanticTimeline
    end

    local function reset_semantic_template_state(seed)
        seed = seed or {}
        local db = Common.deep_copy(seed.db or {})
        db.semanticTimeline = type(db.semanticTimeline) == "table" and db.semanticTimeline or {}
        db.semanticTimeline.runtimeEnabled = true
        db.semanticTimeline.editorLoaded = true
        db.semanticTimeline.workbench = type(db.semanticTimeline.workbench) == "table" and db.semanticTimeline.workbench or {}
        db.Profiles = type(db.Profiles) == "table" and db.Profiles or {}
        db.ActiveProfileIDByChar = type(db.ActiveProfileIDByChar) == "table" and db.ActiveProfileIDByChar or {}
        db._nextProfileID = tonumber(db._nextProfileID) or 1

        context.env.STT_DB = db
        context.C.DB = db
        context.ns[2].DB = db

        local profileID = context.T.Profile:Create("自动化测试")
        context.T.Profile:SetActive(profileID)
        context.T.Note:InitDB()

        local noteDB = context.T.Profile:GetActiveData()
        local wb = db.semanticTimeline.workbench
        if type(seed.legacyPlanMap) == "table" then
            wb.bossPlanMap = {}
            for bossKey, plan in pairs(seed.legacyPlanMap) do
                local planID = context.T.Note:CreatePlan(tostring(plan.name or "旧方案"), tostring(plan.content or ""))
                wb.bossPlanMap[bossKey] = planID
            end
        end

        for bossKey, plan in pairs(seed.semanticPlans or {}) do
            context.T.Note:UpsertSemanticBossPlan(bossKey, tostring(plan.name or "已有方案"), tostring(plan.content or ""), {
                forceContent = true,
            })
        end

        for bossKey, value in pairs(seed.bossTemplateVer or {}) do
            wb.bossTemplateVer = wb.bossTemplateVer or {}
            wb.bossTemplateVer[bossKey] = value
        end
        for bossKey, value in pairs(seed.bossTemplateDigest or {}) do
            wb.bossTemplateDigest = wb.bossTemplateDigest or {}
            wb.bossTemplateDigest[bossKey] = value
        end

        return noteDB, wb
    end

    local function build_semantic_template_snapshot(caseSpec, reloadResult)
        local noteDB = context.T.Profile:GetActiveData()
        local wb = context.C.DB.semanticTimeline and context.C.DB.semanticTimeline.workbench or {}
        local semantic = {}
        local personal = {}
        local digestSet = {}

        for bossKey, planID in pairs(noteDB.SemanticPlanIDByBossKey or {}) do
            local plan = context.T.Note:GetPlan(planID)
            semantic[bossKey] = plan and tostring(plan.content or "") or nil
        end
        for bossKey, planID in pairs(noteDB.PersonalBossPlans or {}) do
            local plan = context.T.Note:GetPlan(planID)
            personal[bossKey] = plan and tostring(plan.content or "") or nil
        end
        for bossKey, value in pairs(wb.bossTemplateDigest or {}) do
            digestSet[bossKey] = value ~= nil
        end

        return {
            id = tostring(caseSpec.id or ""),
            semantic = semantic,
            personal = personal,
            bossTemplateVer = Common.deep_copy(wb.bossTemplateVer or {}),
            bossTemplateDigestSet = digestSet,
            reloadOk = reloadResult and reloadResult.ok == true or nil,
            reloadText = reloadResult and tostring(reloadResult.text or "") or nil,
        }
    end

    local function ensure_visual_board()
        if context.T.VisualBoardData and context.T.VisualBoardCanvas then
            return
        end
        context.env.time = context.env.time or function()
            return math.floor(context.now or 0)
        end
        local beforeCount = type(context.T.Init_callbacks) == "table" and #context.T.Init_callbacks or 0
        for _, file in ipairs(VISUAL_BOARD_FILES) do
            load_file_in_env(file, context.env, context.ns)
        end
        if type(context.T.Init_callbacks) == "table" then
            for index = beforeCount + 1, #context.T.Init_callbacks do
                local func = context.T.Init_callbacks[index]
                if type(func) == "function" then
                    func()
                end
            end
        end
    end

    local function cold_feature_matches(featureSpec, target)
        if featureSpec == target then
            return true
        end
        if type(featureSpec) ~= "table" then
            return false
        end
        for _, entry in ipairs(featureSpec) do
            if entry == target then
                return true
            end
            if type(entry) == "table" and entry[1] == target then
                return true
            end
        end
        return false
    end

    local function run_visual_board_cold_load_contract()
        context.env.time = context.env.time or function()
            return math.floor(context.now or 0)
        end
        context.env.STT_VisualBoardsDB = {}

        local originalRegisterColdFile = context.T.RegisterColdFile
        local coldEntries = {}
        context.T.RegisterColdFile = function(featureSpec, loader)
            if type(loader) == "function" then
                coldEntries[#coldEntries + 1] = {
                    featureSpec = featureSpec,
                    loader = loader,
                }
            end
        end

        local beforeCount = type(context.T.Init_callbacks) == "table" and #context.T.Init_callbacks or 0
        for _, file in ipairs(VISUAL_BOARD_FILES) do
            load_file_in_env(file, context.env, context.ns)
        end
        if type(context.T.Init_callbacks) == "table" then
            for index = beforeCount + 1, #context.T.Init_callbacks do
                local func = context.T.Init_callbacks[index]
                if type(func) == "function" then
                    func()
                end
            end
        end

        local data = context.T.VisualBoardData
        local stripped, invokes = nil, nil
        if context.T.VisualBoardParserHook and context.T.VisualBoardParserHook.ExtractInvokes then
            stripped, invokes = context.T.VisualBoardParserHook.ExtractInvokes("{time:00:01} {所有人}{board:P2分散@3}分散")
        end

        local merge = data and data.MergeReceivedBoards and data:MergeReceivedBoards({
            ["incoming-board"] = {
                id = "incoming-board",
                name = "P2分散",
                version = 1,
                bossKeyText = "raid:1308:3183",
                encounterID = 3183,
                artboard = { w = 1600, h = 900 },
                previewRect = { x = 0, y = 0, w = 1600, h = 900 },
                slides = { { id = "slide-1", name = "1", holdTime = 2, morphFromPrev = 0, overrides = {} } },
                elements = {},
            },
        }, "tester") or nil
        local resolved = data and data.ResolveBoardRefForBoss and data:ResolveBoardRefForBoss("P2分散", "raid:1308:3183") or nil

        local before = {
            editorGUI = context.T.VisualBoardEditorGUI ~= nil,
            componentDrawer = context.T.VisualBoardComponentDrawer ~= nil,
            layerPanel = context.T.VisualBoardLayerPanel ~= nil,
            slideBar = context.T.VisualBoardSlideBar ~= nil,
            iconPicker = context.T.VisualBoardIconPicker ~= nil,
            createBoard = data and type(data.CreateBoard) or "nil",
            applyTemplate = data and type(data.ApplyTemplate_P2toP3) or "nil",
            parser = context.T.VisualBoardParserHook and type(context.T.VisualBoardParserHook.ExtractInvokes) or "nil",
            overlay = context.T.VisualBoardOverlay and type(context.T.VisualBoardOverlay.PlayByRef) or "nil",
            mergeTotal = merge and merge.total or 0,
            resolvedBoard = resolved and resolved.name or nil,
            strippedText = stripped,
            invokeRef = type(invokes) == "table" and invokes[1] and invokes[1].boardRef or nil,
            invokeOffset = type(invokes) == "table" and invokes[1] and invokes[1].offset or nil,
        }

        for _, entry in ipairs(coldEntries) do
            if cold_feature_matches(entry.featureSpec, "visualBoard.editorLoaded") then
                entry.loader()
            end
        end
        context.T.RegisterColdFile = originalRegisterColdFile

        local after = {
            editorGUI = context.T.VisualBoardEditorGUI ~= nil,
            componentDrawer = context.T.VisualBoardComponentDrawer ~= nil,
            layerPanel = context.T.VisualBoardLayerPanel ~= nil,
            slideBar = context.T.VisualBoardSlideBar ~= nil,
            iconPicker = context.T.VisualBoardIconPicker ~= nil,
            createBoard = data and type(data.CreateBoard) or "nil",
            applyTemplate = data and type(data.ApplyTemplate_P2toP3) or "nil",
        }

        return {
            before = before,
            after = after,
        }
    end

    local function normalize_boss_key_text(text)
        local value = tostring(text or "")
        local instanceType, instanceID, encounterID = value:match("^([%a_]+):(%d+):(%d+)$")
        if not instanceType then
            return nil
        end
        return string.format("%s:%d:%d", instanceType, tonumber(instanceID) or 0, tonumber(encounterID) or 0)
    end

    local function make_test_board(id, name, bossKeyText, syncKey, text)
        return {
            id = id,
            syncKey = syncKey or id,
            name = name,
            version = 1,
            bossKeyText = bossKeyText,
            encounterID = tonumber(tostring(bossKeyText or ""):match(":(%d+)$")) or nil,
            artboard = { w = 1600, h = 900 },
            previewRect = { x = 0, y = 0, w = 1600, h = 900 },
            slides = {
                { id = "slide-1", name = "1", holdTime = 2, morphFromPrev = 0, overrides = {} },
            },
            elements = {
                { id = "elem-1", type = "text", x = 100, y = 100, z = 1, rotation = 0, scale = 1, params = { text = text or name, fontSize = 24, color = "FFFFFF" } },
            },
        }
    end

    local function build_test_boards(prefix, bossKeyText, count)
        local boards = {}
        for index = 1, count do
            local id = prefix .. tostring(index)
            boards[id] = make_test_board(id, "P" .. tostring(index) .. "画板", bossKeyText, "sync-" .. tostring(index))
        end
        return boards
    end

    local function count_boards_for_boss(data, bossKeyText)
        local count = 0
        local names = {}
        for _, board in ipairs(data:GetAllBoards()) do
            if normalize_boss_key_text(board.bossKeyText) == bossKeyText then
                count = count + 1
                names[#names + 1] = board.name
            end
        end
        table.sort(names)
        return count, names
    end

    local function run_semantic_boss_visual_board_package_sync()
        context.env.time = context.env.time or function()
            return math.floor(context.now or 0)
        end
        context.env.IsInGroup = function() return true end
        context.env.IsInRaid = function() return false end
        context.env.UnitIsGroupLeader = function() return true end
        context.env.IsInInstance = function() return "", "none" end
        context.T.NormalizeSemanticBossKeyText = normalize_boss_key_text
        context.T.LogDebugEvent = function(eventName, fields)
            context.debugLines[#context.debugLines + 1] = eventName .. ":" .. tostring(fields and fields.result or "")
        end

        local originalRegisterColdFile = context.T.RegisterColdFile
        local coldEntries = {}
        context.T.RegisterColdFile = function(featureSpec, loader)
            if type(loader) == "function" then
                coldEntries[#coldEntries + 1] = {
                    featureSpec = featureSpec,
                    loader = loader,
                }
            end
        end
        load_file_in_env(repo_root .. "/ShengTangTools/visual_board/data.lua", context.env, context.ns)
        context.T.RegisterColdFile = originalRegisterColdFile
        load_file_in_env(repo_root .. "/ShengTangTools/core/note_sync.lua", context.env, context.ns)
        context.T.TacticalNotice = nil

        local bossKey = "raid:1308:3183"
        local otherBossKey = "raid:1308:9999"
        local sends = {}
        local pendingMissingKeys = {}
        context.T.Comm = {
            ResolveGroupScope = function() return "RAID" end,
            Send = function(_, channel, command, payload, options)
                sends[#sends + 1] = {
                    channel = channel,
                    command = command,
                    payload = Common.deep_copy(payload),
                    options = Common.deep_copy(options or {}),
                }
                local proto = payload and payload.proto
                if proto == "S2" and type(options) == "table" and type(options.onAck) == "function" then
                    options.onAck({
                        status = "applied",
                        boardDeltaRequest = {
                            bossKey = bossKey,
                            manifestHash = payload.data and payload.data.visualBoardPackage and payload.data.visualBoardPackage.manifestHash or nil,
                            missingKeys = Common.deep_copy(pendingMissingKeys),
                        },
                    }, "Member-Realm", nil, true)
                end
                if type(options) == "table" and type(options.onComplete) == "function" then
                    options.onComplete({})
                end
                return true
            end,
        }

        local note = {
            SyncDeps = {
                NormalizeSemanticBossKeyText = normalize_boss_key_text,
                IsPlayableStructuredContent = function() return true, {} end,
                PlanScopeTeam = "team",
            },
            upserted = {},
        }
        function note:GetSemanticBossPlanID()
            return nil
        end
        function note:GetPlan()
            return nil
        end
        function note:UpsertBossPlan(receivedBossKey, scope, content, meta)
            self.upserted[#self.upserted + 1] = {
                bossKey = receivedBossKey,
                scope = scope,
                content = content,
                name = meta and meta.name or nil,
            }
            return 501
        end
        function note:SetActivePlan(id, options)
            self.activePlanID = id
            self.activeContextKey = options and options.contextKey or nil
        end

        context.env.STT_VisualBoardsDB = build_test_boards("local-", bossKey, 9)
        context.env.STT_VisualBoardsDB["other-boss"] = make_test_board("other-boss", "其它Boss画板", otherBossKey, "other-sync")
        pendingMissingKeys = {}
        context.T.NoteSync:SendSemanticBossToSTT(note, bossKey, "{time:00:10} {所有人}无画板引用")
        local sameManifestSend = sends[1]
        local sameDeltaSend = sends[2]
        local sameManifestPackage = sameManifestSend and sameManifestSend.payload and sameManifestSend.payload.data and sameManifestSend.payload.data.visualBoardPackage or nil

        sends = {}
        pendingMissingKeys = { "sync-5" }
        context.T.NoteSync:SendSemanticBossToSTT(note, bossKey, "{time:00:10} {所有人}无画板引用")
        local manifestSend = sends[1]
        local deltaSend = sends[2]
        local manifestPayload = manifestSend and manifestSend.payload or nil
        local manifestPackage = manifestPayload and manifestPayload.data and manifestPayload.data.visualBoardPackage or nil
        local deltaPayload = deltaSend and deltaSend.payload or nil
        local deltaPackage = deltaPayload and deltaPayload.data and deltaPayload.data.visualBoardPackage or nil
        local deltaSyncKeys = {}
        local deltaHasOtherBoss = false
        local deltaHasFullElements = false
        for _, board in ipairs((deltaPackage and deltaPackage.boards) or {}) do
            deltaSyncKeys[#deltaSyncKeys + 1] = board.syncKey
            if normalize_boss_key_text(board.bossKeyText) ~= bossKey then
                deltaHasOtherBoss = true
            end
            if type(board.elements) == "table" and #board.elements > 0 then
                deltaHasFullElements = true
            end
        end
        table.sort(deltaSyncKeys)

        local manifestHasFullElements = false
        for _, board in ipairs((manifestPackage and manifestPackage.boards) or {}) do
            if type(board.elements) == "table" then
                manifestHasFullElements = true
            end
        end

        local changedLocal = make_test_board("local-2", "P2画板", bossKey, "sync-2")
        changedLocal.elements[#changedLocal.elements + 1] = { id = "elem-2", type = "text", x = 120, y = 120, z = 2, rotation = 0, scale = 1, params = { text = "本地旧内容", fontSize = 24, color = "FFFFFF" } }
        context.env.STT_VisualBoardsDB = {
            _nextID = 1,
            ["local-1"] = make_test_board("local-1", "P1画板", bossKey, "sync-1"),
            ["local-2"] = changedLocal,
            ["old-current"] = make_test_board("old-current", "旧本地画板", bossKey, "old-current-sync"),
            ["old-other"] = make_test_board("old-other", "其它Boss保留", otherBossKey, "other-sync"),
        }
        local receivedPlanID, manifestResult = context.T.NoteSync:ReceiveSemanticBossFromSTT(note, {
            kind = "semantic_boss",
            bossKey = bossKey,
            name = "至暗之夜降临",
            content = "{time:00:10} {所有人}无画板引用",
            author = "Leader",
            ts = 100,
            visualBoardPackage = manifestPackage,
        }, "Leader-Realm")
        local data = context.T.VisualBoardData
        local manifestBossCount = select(1, count_boards_for_boss(data, bossKey))
        local otherBossCount, otherBossNames = count_boards_for_boss(data, otherBossKey)
        local db = context.env.STT_VisualBoardsDB
        local oldCurrentRemovedBeforeDelta = db["old-current"] == nil
        local deltaMergeResult = context.T.VisualBoardData:MergeBossBoardDelta(deltaPackage, "Leader-Realm")
        local deltaMergedBossCount = select(1, count_boards_for_boss(data, bossKey))
        local oldCurrentRemovedAfterDelta = db["old-current"] == nil

        context.env.STT_VisualBoardsDB = {}
        sends = {}
        pendingMissingKeys = {}
        context.T.NoteSync:SendSemanticBossToSTT(note, bossKey, "{time:00:20} {所有人}空包")
        local emptyData = sends[1] and sends[1].payload and sends[1].payload.data or nil

        return {
            coldEditorLoadedCaptured = #coldEntries > 0,
            buildBossManifestRuntime = context.T.VisualBoardData and type(context.T.VisualBoardData.BuildBossBoardManifestPackage) or "nil",
            buildBossDeltaRuntime = context.T.VisualBoardData and type(context.T.VisualBoardData.BuildBossBoardDeltaPackage) or "nil",
            applyBossManifestRuntime = context.T.VisualBoardData and type(context.T.VisualBoardData.ApplyBossBoardManifest) or "nil",
            mergeBossDeltaRuntime = context.T.VisualBoardData and type(context.T.VisualBoardData.MergeBossBoardDelta) or "nil",
            sameSendCount = sameDeltaSend and 2 or (sameManifestSend and 1 or 0),
            samePackageMode = sameManifestPackage and sameManifestPackage.mode or nil,
            sentProto = manifestPayload and manifestPayload.proto or nil,
            packageBossKey = manifestPackage and manifestPackage.bossKeyText or nil,
            packageMode = manifestPackage and manifestPackage.mode or nil,
            packageCount = manifestPackage and #(manifestPackage.boards or {}) or 0,
            packageHasFullElements = manifestHasFullElements,
            packagePrio = manifestSend and manifestSend.options and manifestSend.options.prio or nil,
            packageTimeout = manifestSend and manifestSend.options and manifestSend.options.timeout or nil,
            packageMaxRetries = manifestSend and manifestSend.options and manifestSend.options.maxRetries or nil,
            deltaSentProto = deltaPayload and deltaPayload.proto or nil,
            deltaPackageMode = deltaPackage and deltaPackage.mode or nil,
            deltaPackageCount = deltaPackage and #(deltaPackage.boards or {}) or 0,
            deltaSyncKeys = deltaSyncKeys,
            deltaHasOtherBoss = deltaHasOtherBoss,
            deltaHasFullElements = deltaHasFullElements,
            deltaPrio = deltaSend and deltaSend.options and deltaSend.options.prio or nil,
            deltaTimeout = deltaSend and deltaSend.options and deltaSend.options.timeout or nil,
            deltaMaxRetries = deltaSend and deltaSend.options and deltaSend.options.maxRetries or nil,
            receivedPlanID = receivedPlanID,
            activePlanID = note.activePlanID,
            activeContextKey = note.activeContextKey,
            manifestMatched = manifestResult and manifestResult.matched or 0,
            manifestMissingCount = manifestResult and #(manifestResult.missingKeys or {}) or 0,
            manifestRemoved = manifestResult and manifestResult.removed or 0,
            manifestPendingRemoved = manifestResult and manifestResult.pendingRemoved or 0,
            manifestBossCount = manifestBossCount,
            oldCurrentRemoved = oldCurrentRemovedBeforeDelta,
            deltaMergeRemoved = deltaMergeResult and deltaMergeResult.removed or 0,
            deltaMergedBossCount = deltaMergedBossCount,
            oldCurrentRemovedAfterDelta = oldCurrentRemovedAfterDelta,
            otherBossCount = otherBossCount,
            otherBossNames = otherBossNames,
            emptyHasPackage = emptyData and emptyData.visualBoardPackage ~= nil or false,
        }
    end

    local function collect_friendly_nameplate_ui_state()
        local mod = context.T.FriendlyNameplate
        local ui = mod and mod.ui or nil
        local out = {
            enableText = "",
            applyText = "",
            fontSizeText = "",
            fontSizeValue = nil,
            fontOutlineLabel = "",
            fontOutlineText = "",
            toggles = {},
            descriptions = {},
        }
        if not ui then
            return out
        end
        if ui.enableBtn then
            out.enableText = ui.enableBtn:GetText()
        end
        if ui.applyBtn then
            out.applyText = ui.applyBtn:GetText()
        end
        if ui.fontSizeLabel then
            out.fontSizeText = ui.fontSizeLabel:GetText()
        end
        if ui.fontSizeSlider then
            out.fontSizeValue = ui.fontSizeSlider:GetValue()
        end
        if ui.fontOutlineLabel then
            out.fontOutlineLabel = ui.fontOutlineLabel:GetText()
        end
        if ui.fontOutlineDropdown then
            if type(ui.fontOutlineDropdown.GetValueText) == "function" then
                out.fontOutlineText = ui.fontOutlineDropdown:GetValueText() or ""
            elseif ui.fontOutlineDropdown.valueText and type(ui.fontOutlineDropdown.valueText.GetText) == "function" then
                out.fontOutlineText = ui.fontOutlineDropdown.valueText:GetText() or ""
            else
                out.fontOutlineText = ui.fontOutlineDropdown.__dropdownText or ""
            end
        end
        for key, entry in pairs(ui.toggles or {}) do
            out.toggles[key] = entry.btn:GetText()
        end
        for idx, entry in ipairs(ui.descriptions or {}) do
            out.descriptions[idx] = entry.widget:GetText()
        end
        return out
    end

    local function collect_friendly_nameplate_font_state()
        local out = {}
        for _, plate in ipairs(context.nameplates or {}) do
            local unitFrame = plate and plate.UnitFrame or nil
            local nameRegion = unitFrame and unitFrame.name or nil
            local path, size, flags = context.get_font_triplet(nameRegion)
            out[#out + 1] = {
                unit = unitFrame and unitFrame.unit or nil,
                isFriend = unitFrame and unitFrame:IsFriend() or false,
                isPlayer = unitFrame and unitFrame:IsPlayer() or false,
                font = {
                    path = path,
                    size = size,
                    flags = flags,
                },
            }
        end
        return out
    end

    local function collect_friendly_nameplate_state()
        local mod = context.T.FriendlyNameplate
        local baseFonts = mod and mod.baseFontObjects or nil
        local baseNormal = type(baseFonts) == "table" and baseFonts.normal or nil
        local baseOutlined = type(baseFonts) == "table" and baseFonts.outlined or nil
        local baseNormalPath, baseNormalSize, baseNormalFlags
        local baseOutlinedPath, baseOutlinedSize, baseOutlinedFlags
        if baseNormal then
            baseNormalPath, baseNormalSize, baseNormalFlags = baseNormal.path, baseNormal.size, baseNormal.flags
        else
            baseNormalPath, baseNormalSize, baseNormalFlags = context.get_font_triplet(context.env.SystemFont_NamePlate)
        end
        if baseOutlined then
            baseOutlinedPath, baseOutlinedSize, baseOutlinedFlags = baseOutlined.path, baseOutlined.size, baseOutlined.flags
        else
            baseOutlinedPath, baseOutlinedSize, baseOutlinedFlags = context.get_font_triplet(context.env.SystemFont_NamePlate_Outlined)
        end
        return {
            enabled = context.C.DB.friendlyNameplate.enabled == true,
            runtimeApplied = mod and mod.isRuntimeApplied == true or false,
            serverNameNeedsReload = mod and mod.serverNameNeedsReload == true or false,
            fontConfig = {
                fontSize = context.C.DB.friendlyNameplate.fontSize,
                fontOutline = context.C.DB.friendlyNameplate.fontOutline,
            },
            baseFonts = {
                normal = {
                    path = baseNormalPath,
                    size = baseNormalSize,
                    flags = baseNormalFlags,
                },
                outlined = {
                    path = baseOutlinedPath,
                    size = baseOutlinedSize,
                    flags = baseOutlinedFlags,
                },
            },
            nameplates = collect_friendly_nameplate_font_state(),
            cvars = Common.deep_copy(context.cvars),
            setCVarCalls = Common.deep_copy(context.setCVarCalls),
            namePlateOptionValue = context.env.NamePlateFriendlyFrameOptions and context.env.NamePlateFriendlyFrameOptions.updateNameUsesGetUnitName or nil,
            ui = collect_friendly_nameplate_ui_state(),
            messages = Common.deep_copy(context.messages),
        }
    end

    local function ensure_friendly_nameplate_ui()
        if type(context.T.CreateButton) ~= "function" then
            context.T.CreateButton = function(parent, config)
                local button = context.env.CreateFrame("Button", nil, parent)
                local cfg = config or {}
                button:SetSize(cfg.width or 0, cfg.height or 24)
                if cfg.point then
                    button:SetPoint(table.unpack(cfg.point))
                end
                button:SetText(cfg.text or "")
                return button
            end
        end
        if type(context.T.CreateGroupTitle) ~= "function" then
            context.T.CreateGroupTitle = function(parent, config)
                local cfg = config or {}
                local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                if cfg.point then
                    title:SetPoint(table.unpack(cfg.point))
                end
                title:SetText(cfg.text or "")
                return title
            end
        end
        if type(context.T.CreateSeparator) ~= "function" then
            context.T.CreateSeparator = function(parent, config)
                local cfg = config or {}
                local line = parent:CreateTexture(nil, "OVERLAY")
                if cfg.point then
                    line:SetPoint(table.unpack(cfg.point))
                end
                line:SetSize(cfg.width or 0, cfg.height or 1)
                return line
            end
        end
        if type(context.T.CreateSelectorButton) ~= "function" then
            context.T.CreateSelectorButton = function(parent, config)
                local cfg = config or {}
                local button = context.env.CreateFrame("Button", nil, parent)
                button.__kind = "SelectorButton"
                button.items = cfg.items or {}
                button.selectedValue = cfg.selectedValue
                button.disabled = cfg.enabled == false
                button:SetSize(cfg.width or 0, cfg.height or 26)
                if cfg.point then
                    button:SetPoint(table.unpack(cfg.point))
                end
                button.labelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                button.valueText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                function button:SetItems(items)
                    self.items = items or {}
                end
                function button:SetSelectedValue(value, fallbackText)
                    self.selectedValue = value
                    local text = fallbackText
                    for _, item in ipairs(self.items or {}) do
                        if item.value == value then
                            text = item.text
                            break
                        end
                        for _, child in ipairs(item.items or {}) do
                            if child.value == value then
                                text = child.text
                                break
                            end
                        end
                        if text then
                            break
                        end
                    end
                    self:SetValueText(text or cfg.emptyText or "-")
                end
                function button:SetValueText(text)
                    self.__dropdownText = text or ""
                    if self.valueText then
                        self.valueText:SetText(self.__dropdownText)
                    end
                end
                function button:GetValueText()
                    return self.__dropdownText or ""
                end
                function button:SetLabel(text)
                    if self.labelText then
                        self.labelText:SetText(text or "")
                    end
                end
                function button:SetSelectorEnabled(enabled)
                    self.disabled = enabled == false
                    if self.disabled then
                        self:Disable()
                    else
                        self:Enable()
                    end
                end
                button:SetLabel(cfg.label or "")
                button:SetSelectedValue(cfg.selectedValue, cfg.emptyText)
                return button
            end
        end
    end

    local function run_phase_detector_case(caseSpec)
        if type(context.T.PhaseAnchorsS14) ~= "table" then
            load_file_in_env(repo_root .. "/ShengTangTools/data/phase_anchors_s14.lua", context.env, context.ns)
        end
        if not (context.T.PhaseDetector and context.T.PhaseDetector.Start and context.T.PhaseDetector.GetCurrentPhase) then
            load_file_in_env(repo_root .. "/ShengTangTools/core/phase_detector.lua", context.env, context.ns)
        end

        local detector = context.T.PhaseDetector
        if not (detector and detector.Start and detector.GetCurrentPhase) then
            error("PhaseDetector 未加载")
        end

        local encounterID = tonumber(caseSpec.encounterID) or 0
        local phaseAnchors = context.T.PhaseAnchorsS14
        if type(caseSpec.config) == "table" then
            phaseAnchors[encounterID] = Common.deep_copy(caseSpec.config)
        end

        context.now = tonumber(caseSpec.now or 0) or 0
        context.difficultyID = tonumber(caseSpec.difficultyID) or context.difficultyID
        context.unitExistsMap = Common.deep_copy(caseSpec.unitExistsMap or {})
        context.timers = {}
        context.timerCallbacks = {}

        local resolvedTargets = {}
        detector:Stop()
        detector:Start(encounterID, caseSpec.phaseRules, function() end)
        local initialPhase = detector:GetCurrentPhase()

        for _, op in ipairs(caseSpec.operations or {}) do
            if op.type == "advance_time" then
                context.now = context.now + (tonumber(op.elapsed) or 0)
            elseif op.type == "set_unit_exists" then
                context.unitExistsMap[tostring(op.unit or "")] = op.exists == true
            elseif op.type == "set_phase" then
                detector:_SetPhase(op.phase, op.source or "test", {})
            elseif op.type == "engage_unit_changed" then
                detector:OnEngageUnitChanged()
            elseif op.type == "resolve_anchor_target" then
                resolvedTargets[#resolvedTargets + 1] = detector:_ResolveAnchorTarget(op.anchor)
            elseif op.type == "run_timers" then
                local callbacks = context.timerCallbacks
                context.timerCallbacks = {}
                for _, timer in ipairs(callbacks) do
                    if not (timer.timer and timer.timer.cancelled) and type(timer.fn) == "function" then
                        timer.fn()
                    end
                end
            else
                error("未知 PhaseDetector 操作: " .. tostring(op.type))
            end
        end

        local phaseStart = {}
        for _, phaseKey in ipairs(caseSpec.queryPhases or {}) do
            phaseStart[phaseKey] = detector:GetPhaseStartTime(phaseKey) ~= nil
        end

        return {
            label = caseSpec.label,
            initialPhase = initialPhase,
            finalPhase = detector:GetCurrentPhase(),
            resolvedTargets = resolvedTargets,
            timerDelays = Common.deep_copy(context.timers),
            pendingTimerCount = #context.timerCallbacks,
            phaseStart = phaseStart,
        }
    end

    for _, event in ipairs(events or {}) do
        if event.type == "parse_line" then
            context.result = simplify_parsed_event(context.T.TimelineSyntax.ParseTimelineLine(event.line))
        elseif event.type == "phase_detector_cases" then
            local out = {}
            for _, caseSpec in ipairs(event.cases or {}) do
                out[#out + 1] = run_phase_detector_case(caseSpec)
            end
            context.result = out
        elseif event.type == "preprocess_text" then
            local info = context.T.STNTemplate.PreprocessText(event.text or "", event.opts)
            context.result = {
                isValid = info and info.isValid == true,
                hasBlocks = info and info.hasBlocks == true,
                bodyKind = info and info.bodyKind or nil,
                processedText = info and info.processedText or "",
                slotCount = info and info.slotCount or 0,
                placeholderCount = info and info.placeholderCount or 0,
                errorCount = info and info.errors and #info.errors or 0,
            }
        elseif event.type == "export_tr" then
            if not (LibStub and LibStub:GetLibrary("LibSerialize", true) and LibStub:GetLibrary("LibDeflate", true)) then
                context.env.strmatch = string.match
                context.env.strfind = string.find
                context.env.strsub = string.sub
                context.env.strgsub = string.gsub
                context.env.strlen = string.len
                context.env.strbyte = string.byte
                context.env.strchar = string.char
                context.env.strlower = string.lower
                context.env.strupper = string.upper
                context.env.format = string.format
                context.env.tinsert = table.insert
                context.env.tremove = table.remove
                context.env.tsort = table.sort
                load_file_in_env(repo_root .. "/ShengTangTools/libs/LibStub/LibStub.lua", context.env, context.ns)
                load_file_in_env(repo_root .. "/ShengTangTools/libs/LibSerialize/LibSerialize.lua", context.env, context.ns)
                load_file_in_env(repo_root .. "/ShengTangTools/libs/LibDeflate/LibDeflate.lua", context.env, context.ns)
            end
            if context.T.TacticTranslator and not context.T.TacticTranslator:GetById("tr") then
                load_file_in_env(repo_root .. "/ShengTangTools/core/tactic_translator_tr.lua", context.env, context.ns)
            end
            local exporter = context.T.TacticExporterTR
            local encoded, err
            if exporter and exporter.Export then
                encoded, err = exporter:Export(event.text or "", event.options or nil)
            else
                err = "missing_exporter"
            end
            local summary = {
                ok = encoded ~= nil,
                err = err,
                prefix = type(encoded) == "string" and encoded:sub(1, 4) or nil,
            }
            if encoded and context.T.TacticTranslator then
                local adapter = context.T.TacticTranslator:GetById("tr")
                local parsed = adapter and adapter.parse and adapter.parse(encoded) or nil
                local reminder = parsed and parsed.reminders and parsed.reminders[1] or nil
                summary.decoded = {
                    eventCount = parsed and #(parsed.reminders or {}) or 0,
                    encounterID = parsed and parsed.header and parsed.header.encounterID or nil,
                    triggerTime = reminder and reminder.trigger and reminder.trigger.time or nil,
                    loadType = reminder and reminder.load and reminder.load.type or nil,
                    loadName = reminder and reminder.load and reminder.load.name or nil,
                    displayType = reminder and reminder.display and reminder.display.type or nil,
                    spellID = reminder and reminder.display and reminder.display.spellID or nil,
                    countdownEnabled = reminder and reminder.countdown and reminder.countdown.enabled or false,
                    countdownStart = reminder and reminder.countdown and reminder.countdown.start or nil,
                    soundEnabled = reminder and reminder.sound and reminder.sound.enabled or false,
                    soundFile = reminder and reminder.sound and reminder.sound.file or nil,
                }
            end
            context.result = summary
        elseif event.type == "semantic_template_initialization_cases" then
            local sem = ensure_semantic_template_runtime()
            local output = {}
            for _, caseSpec in ipairs(event.cases or {}) do
                context.T.SemanticBuiltinPlansVersionS14 = tostring(caseSpec.version or event.version or "automation_builtin_v1")
                context.T.SemanticBuiltinPlansS14 = Common.deep_copy(caseSpec.builtinPlans or event.builtinPlans or {})
                context.T.SemanticBuiltinBossMetaS14 = Common.deep_copy(caseSpec.builtinMeta or event.builtinMeta or {})

                reset_semantic_template_state(caseSpec.seed)
                sem:RebuildTemplateIndexes(true)
                sem:EnsureSemanticBossPlansInitialized({
                    cause = "automation_semantic_template_init",
                    force = caseSpec.force == true,
                })

                local reloadResult = nil
                if caseSpec.reloadBossKey then
                    local reloadBossKey = caseSpec.reloadBossKey
                    if type(reloadBossKey) == "string" and sem.ParseBossSelectorKey then
                        reloadBossKey = sem:ParseBossSelectorKey(reloadBossKey)
                    end
                    reloadResult = context.T.SemanticTemplateReload.ReloadTeamPlan(sem, reloadBossKey)
                end
                output[#output + 1] = build_semantic_template_snapshot(caseSpec, reloadResult)
            end
            context.result = output
        elseif event.type == "personal_stt_runtime_counts" then
            local text = event.text or ""
            local info = context.T.STNTemplate.PreprocessText(text, { relaxed = true })
            local parsed = context.T.NoteParser:ParseNote(text, {
                relaxed = true,
                isPersonal = true,
                templateInfo = info,
            })
            local hits = 0
            for _, ev in ipairs(parsed or {}) do
                ev.isPersonal = true
                if context.T.NoteParser:ShouldTriggerEvent(ev) then
                    hits = hits + 1
                end
            end
            local timeline = context.T.BuildTimelineEvents(parsed, {})
            local board = context.T.BuildTimelineEvents(parsed, {}, { showAll = true })
            local detected = false
            for _, line in ipairs(context.debugLines or {}) do
                if tostring(line):find("TACTIC_TRANSLATOR_DETECTED", 1, true) then
                    detected = true
                    break
                end
            end

            local translated = nil
            if event.translateText and context.T.TacticTranslator then
                translated = context.T.TacticTranslator:Translate(event.translateFormat or "mrt", event.translateText)
            end

            context.result = {
                isValid = info and info.isValid == true,
                externalDetected = detected,
                processedHasAll = (info and (tostring(info.processedText or ""):find("{所有人}", 1, true) ~= nil)) or false,
                eventCount = #(parsed or {}),
                timelineCount = #(timeline or {}),
                boardCount = #(board or {}),
                hits = hits,
                translatorEventCount = translated and tonumber(translated.eventCount) or 0,
                translatorHasAll = (translated and (tostring(translated.stn or ""):find("{所有人}", 1, true) ~= nil)) or false,
            }
        elseif event.type == "parse_text" then
            local parsed = context.T.TimelineSyntax.ParseTimelineText(event.text or "")
            context.result = simplify_parsed_events(parsed)
        elseif event.type == "compile_workbench_rows_minimal" then
            local rows = {}
            local errors = {}
            local raw = tostring(event.text or ""):gsub("\r\n", "\n")
            local lineNo = 0

            for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
                lineNo = lineNo + 1
                local trimmed = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if trimmed ~= "" then
                    local parsed = context.T.TimelineSyntax.ParseTimelineLine(trimmed)
                    if not parsed then
                        if trimmed:find("{time:", 1, true) then
                            errors[#errors + 1] = {
                                line = lineNo,
                                reason = "时间格式无效",
                                content = trimmed,
                            }
                        else
                            rows[#rows + 1] = {
                                rowType = "comment",
                                line = lineNo,
                                label = trimmed,
                            }
                        end
                    else
                        local rowType = "text"
                        local spellID = (parsed.rawLine or ""):match("{spell:(%d+):?%d*}")
                        if spellID then
                            rowType = "spell"
                        end
                        rows[#rows + 1] = {
                            rowType = rowType,
                            line = lineNo,
                            label = parsed.displayText,
                            hasAudience = parsed.hasAudience == true,
                            spellID = spellID and tonumber(spellID) or nil,
                        }
                    end
                end
            end

            context.result = {
                rowCount = #rows,
                errorCount = #errors,
                rows = rows,
                errors = errors,
            }
        elseif event.type == "build_segments" then
            context.result = context.T.TimelineSyntax.BuildSegments(event.text or "")
        elseif event.type == "build_horizontal_per_row" then
            local template = context.T.STNTemplate.PreprocessText(event.text or "", event.opts)
            local slotVisualHints = context.T.BuildSlotVisualHints(template and template.slots, template and template.usedSlots)
            local parsed = context.T.TimelineSyntax.ParseTimelineText(template and template.processedText or event.text or "")
            local sourceRows = {}
            for _, parsedRow in ipairs(parsed or {}) do
                sourceRows[#sourceRows + 1] = {
                    rowID = "test:" .. tostring(parsedRow.line or #sourceRows + 1),
                    key = { encounterID = tonumber(event.encounterID) or 0 },
                    timeSec = parsedRow.time,
                    rowType = "spell",
                    spellID = parsedRow.primarySpellID,
                    label = parsedRow.displayText,
                    phase = parsedRow.phase,
                    sortIndex = parsedRow.line,
                    sourceLine = tonumber(template and template.bodyLineMap and template.bodyLineMap[parsedRow.line]) or parsedRow.line,
                    segments = parsedRow.segments,
                    phaseDisplaySpans = event.phaseDisplaySpans,
                    slotVisualHints = slotVisualHints,
                }
            end

            local personnelKeys, audienceDisplayByLine = build_personnel_context(context, template)

            local perRow, orderedKeys = context.T.HorizontalTimelineData.BuildPerRow(sourceRows, {
                personnelKeys = personnelKeys,
                audienceDisplayByLine = audienceDisplayByLine,
            })
            local rows = {}
            for _, key in ipairs(orderedKeys or {}) do
                local entry = perRow[key]
                local meta = entry and entry.meta or {}
                rows[#rows + 1] = {
                    key = key,
                    kind = meta.kind,
                    displayText = meta.displayText,
                    classFile = meta.classFile,
                    specID = meta.specID,
                    specIcon = meta.specIcon,
                    playerInfo = meta.playerInfo,
                }
            end
            context.result = rows
        elseif event.type == "build_horizontal_items" then
            local template = context.T.STNTemplate.PreprocessText(event.text or "", event.opts)
            local slotVisualHints = context.T.BuildSlotVisualHints(template and template.slots, template and template.usedSlots)
            local parsed = context.T.TimelineSyntax.ParseTimelineText(template and template.processedText or event.text or "")
            local sourceRows = {}
            for _, parsedRow in ipairs(parsed or {}) do
                sourceRows[#sourceRows + 1] = {
                    rowID = "test:" .. tostring(parsedRow.line or #sourceRows + 1),
                    key = { encounterID = tonumber(event.encounterID) or 0 },
                    timeSec = parsedRow.time,
                    rowType = "spell",
                    spellID = parsedRow.primarySpellID,
                    label = parsedRow.displayText,
                    phase = parsedRow.phase,
                    sortIndex = parsedRow.line,
                    sourceLine = tonumber(template and template.bodyLineMap and template.bodyLineMap[parsedRow.line]) or parsedRow.line,
                    segments = parsedRow.segments,
                    modifiers = parsedRow.modifiers,
                    phaseDisplaySpans = event.phaseDisplaySpans,
                    slotVisualHints = slotVisualHints,
                }
            end

            local personnelKeys, audienceDisplayByLine = build_personnel_context(context, template)

            local perRow, orderedKeys = context.T.HorizontalTimelineData.BuildPerRow(sourceRows, {
                personnelKeys = personnelKeys,
                audienceDisplayByLine = audienceDisplayByLine,
            })
            local rows = {}
            for _, key in ipairs(orderedKeys or {}) do
                local entry = perRow[key]
                local meta = entry and entry.meta or {}
                local outItems = {}
                for _, item in ipairs(entry and entry.items or {}) do
                    outItems[#outItems + 1] = {
                        time = item.time,
                        spellID = item.spellID,
                        duration = item.duration,
                        collisionCount = #(item.collisions or {}),
                    }
                end
                rows[#rows + 1] = {
                    key = key,
                    kind = meta.kind,
                    displayText = meta.displayText,
                    items = outItems,
                }
            end
            context.result = rows
        elseif event.type == "build_skill_picker_lines" then
            local out = {}
            for _, case in ipairs(event.cases or {}) do
                local timeline = {
                    orderedKeys = case.orderedKeys or { "boss:BOSS" },
                    phaseDisplayStats = case.phaseDisplayStats,
                    perRow = {
                        ["boss:BOSS"] = {
                            meta = { kind = "boss", displayText = "BOSS", encounterID = tonumber(event.encounterID) or 0 },
                            items = case.items or {},
                        },
                    },
                }
                local ctx = context.T.TimelineCoords.ResolveForRowTime(timeline, case.rowKey or "boss:BOSS", case.time)
                local line, reason = context.T.SkillPickerLogic.BuildLine(ctx, case.spellID, case.dur)
                out[#out + 1] = {
                    line = line,
                    reason = reason,
                    ctx = {
                        time = ctx and ctx.time or nil,
                        sourceTime = ctx and ctx.sourceTime or nil,
                        phase = ctx and ctx.phase or nil,
                        phaseDisplayOffset = ctx and ctx.phaseDisplayOffset or nil,
                        timePayload = ctx and ctx.timePayload or nil,
                    },
                }
            end
            context.result = out
        elseif event.type == "lura_starsplinter_direction_cases" then
            local mod = context.T.LuraStarsplinterDirection
            local out = {}
            for _, item in ipairs(event.cases or {}) do
                local arrow = mod and mod.ResolveArrow and mod.ResolveArrow(item)
                out[#out + 1] = {
                    label = item.label,
                    arrow = arrow,
                }
            end
            context.result = out
        elseif event.type == "compile_resolved_plan_content" then
            local sem = ensure_semantic_timeline()
            local bossKey = event.bossKey or { instanceType = "raid", instanceID = 1, encounterID = 1 }
            local teamPlan = {
                id = tonumber(event.teamPlanID) or 101,
                content = tostring(event.teamText or ""),
            }
            local personalPlan = {
                id = tonumber(event.personalPlanID) or 202,
                content = tostring(event.personalText or ""),
            }

            context.C.DB.semanticTimeline = context.C.DB.semanticTimeline or {}
            context.C.DB.semanticTimeline.resolveSource = event.resolveSource or "team_plus_personal"
            context.C.DB.semanticTimeline.personalOverridesTeam = event.personalOverridesTeam ~= false

            sem.GetCurrentBossSelectorKey = function()
                return bossKey
            end
            sem.GetResolveSource = function()
                return context.C.DB.semanticTimeline.resolveSource
            end
            sem.GetResolvedPlanTexts = function()
                return {
                    bossKey = bossKey,
                    teamText = teamPlan.content,
                    personalText = personalPlan.content,
                }
            end
            sem.GetEncounterName = function()
                return "测试"
            end
            sem.GetCurrentPlan = function()
                return teamPlan
            end
            sem.GetCurrentPersonalPlan = function()
                return personalPlan
            end
            sem.GetCurrentPlanForTab = function(_, tab)
                return tab == "personal" and personalPlan or teamPlan
            end
            sem.GetEncounterSpellCatalog = function()
                return {}
            end

            local compiled = sem:CompileResolvedPlanContent()
            local rows = {}
            for _, row in ipairs(compiled and compiled.rows or {}) do
                local editorTab = tostring(row.editorTab or "")
                rows[#rows + 1] = {
                    editorTab = editorTab,
                    spellID = tonumber(row.spellID),
                    sortIndex = tonumber(row.sortIndex),
                    line = sem.GetPlanLineByRowIDForTab and sem:GetPlanLineByRowIDForTab(editorTab, row.rowID) or nil,
                }
            end
            context.result = {
                rowCount = #rows,
                rows = rows,
            }
        elseif event.type == "resolved_runtime_plan_targets" then
            local sem = ensure_semantic_timeline()
            local bossKey = event.bossKey or { instanceType = "raid", instanceID = 1, encounterID = 1 }
            local teamPlan = {
                id = tonumber(event.teamPlanID) or 101,
                content = tostring(event.teamText or ""),
            }
            local personalPlan = {
                id = tonumber(event.personalPlanID) or 202,
                content = tostring(event.personalText or ""),
            }

            context.C.DB.semanticTimeline = context.C.DB.semanticTimeline or {}
            context.C.DB.semanticTimeline.resolveSource = event.resolveSource or "team_plus_personal"
            context.C.DB.semanticTimeline.personalOverridesTeam = event.personalOverridesTeam ~= false

            sem.GetCurrentBossSelectorKey = function()
                return bossKey
            end
            sem.GetResolveSource = function()
                return context.C.DB.semanticTimeline.resolveSource
            end
            sem.GetResolvedPlanTexts = function()
                return {
                    bossKey = bossKey,
                    teamText = teamPlan.content,
                    personalText = personalPlan.content,
                }
            end
            sem.GetEncounterName = function()
                return "测试"
            end
            sem.GetCurrentPlan = function()
                return teamPlan
            end
            sem.GetCurrentPersonalPlan = function()
                return personalPlan
            end

            local bundle = sem:GetResolvedRuntimePlan()
            local events = {}
            local templateInfo = context.T.STNTemplate and context.T.STNTemplate.PreprocessText and context.T.STNTemplate.PreprocessText(bundle and bundle.runtimeText or "") or nil
            local parsed = context.T.NoteParser and context.T.NoteParser.ParseNote and context.T.NoteParser:ParseNote(bundle and bundle.runtimeText or "", {
                templateInfo = templateInfo,
            }) or {}
            for _, parsedEvent in ipairs(parsed) do
                local targets = {}
                for name in pairs(parsedEvent.targetIndicators or {}) do
                    targets[#targets + 1] = tostring(name)
                end
                table.sort(targets)
                events[#events + 1] = {
                    time = tonumber(parsedEvent.time),
                    content = tostring(parsedEvent.content or ""),
                    targets = targets,
                }
            end
            context.result = {
                events = events,
            }
        elseif event.type == "runtime_boss_plan_ssot" then
            local note = ensure_note_store()
            local sem = ensure_semantic_timeline()
            local bossKey = event.bossKey or "raid:999:888"
            local oldBossKey = event.oldBossKey or "raid:999:777"
            local targetBoss = sem.ParseBossSelectorKey and sem:ParseBossSelectorKey(bossKey) or nil
            context.C.DB.dataSource = "STN"
            if targetBoss then
                sem.NormalizeWorkbenchSelection = function() end
                sem.ResolveBossKeyByEncounterID = function(_, encounterID)
                    if tonumber(encounterID) == tonumber(targetBoss.encounterID) then
                        return {
                            instanceType = targetBoss.instanceType,
                            instanceID = targetBoss.instanceID,
                            encounterID = targetBoss.encounterID,
                        }
                    end
                    return nil
                end
            end

            local activePlanID = note:CreatePlan("固定显示方案", tostring(event.activeText or "{time:00:08} 错误固定方案"))
            note:SetActivePlan(activePlanID, { manual = true })
            note:UpsertBossPlan(oldBossKey, "team", tostring(event.activeText or "{time:00:08} 错误固定方案"), {
                planID = activePlanID,
                name = "旧Boss固定方案",
                forceContent = true,
            })
            note:SetCurrentBossKey(oldBossKey, "test_old_context")

            local function summarize(opts)
                opts = type(opts) == "table" and opts or {}
                local text, source, bundle = context.T.GetTimelineSourceText({
                    bossKey = opts.explicitBoss and bossKey or nil,
                    silent = true,
                })
                return {
                    source = tostring(source or ""),
                    hasText = text ~= nil and text ~= "",
                    text = tostring(text or ""),
                    fallbackActive = bundle and bundle.fallbackActive == true or false,
                    teamPlanIDPresent = bundle and bundle.teamPlanID ~= nil or false,
                    personalPlanIDPresent = bundle and bundle.personalPlanID ~= nil or false,
                    activePlanIDPresent = bundle and bundle.activePlanID ~= nil or false,
                    currentBossKey = note:GetCurrentBossKey() or "",
                    bundleBossKey = bundle and bundle.bossKeyText or "",
                }
            end

            local explicitAbsent = summarize({ explicitBoss = true })
            if targetBoss and sem.SwitchWorkbenchToBossKeyText then
                sem:SwitchWorkbenchToBossKeyText(bossKey, "sync_apply", {
                    suppressCurrentBossContext = true,
                })
            end
            local afterSuppressedSyncSwitch = summarize()
            if targetBoss then
                sem:SetWorkbenchSelection(targetBoss.instanceType, targetBoss.instanceID, targetBoss.encounterID)
            end
            local afterWorkbenchSwitch = summarize()
            note:UpsertBossPlan(bossKey, "team", tostring(event.emptyBossText or ""), {
                name = "目标Boss空方案",
                forceContent = true,
            })
            if targetBoss then
                sem:SetWorkbenchSelection(targetBoss.instanceType, targetBoss.instanceID, targetBoss.encounterID)
            end
            local empty = summarize()
            note:SetCurrentBossKey(oldBossKey, "test_old_context")
            if sem.OnEncounterStart and targetBoss then
                sem:OnEncounterStart(targetBoss.encounterID, "目标Boss", 16)
            end
            local afterEncounterStart = summarize()
            context.result = {
                explicitAbsent = explicitAbsent,
                afterSuppressedSyncSwitch = afterSuppressedSyncSwitch,
                afterWorkbenchSwitch = afterWorkbenchSwitch,
                empty = empty,
                afterEncounterStart = afterEncounterStart,
            }
        elseif event.type == "resolve_screen_syntax" then
            local text = event.text or ""
            local spellID = tonumber(event.spellID or 0)
            local stripped = text
            if context.T.TimelineSyntax and context.T.TimelineSyntax.ResolveTextForCurrentPlayer then
                local _, resolved = context.T.TimelineSyntax.ResolveTextForCurrentPlayer(text, { target = "display_screen" })
                stripped = resolved or ""
            else
                stripped = context.resolve_raid_markers(stripped)
            end
            context.result = {
                text = stripped,
                spellIcon = context.resolve_spell_icon(spellID),
            }
        elseif event.type == "resolver_get_spell_name" then
            context.result = context.T.EncounterEventResolver.GetSpellName(event.spellID, event.fallbackName)
        elseif event.type == "resolver_resolve_timeline_spell_meta" then
            local meta = context.T.EncounterEventResolver.ResolveTimelineSpellMeta(event.eventInfoOrID, event.encounterID)
            context.result = Common.deep_copy(meta)
        elseif event.type == "trigger_runner_start" then
            local ok = context.T.TriggerRunner:StartFromText(event.text or "", event.isTest)
            context.result = { started = ok == true }
        elseif event.type == "trigger_runner_timeline_event_added" then
            context.T.TriggerRunner:OnTimelineEventAdded(Common.deep_copy(event.eventInfo or {}))
            context.result = true
        elseif event.type == "trigger_runner_timeline_event_state_changed" then
            context.T.TriggerRunner:OnTimelineEventStateChanged(event.eventID)
            context.result = {
                speakCalls = Common.deep_copy(context.speakCalls),
            }
        elseif event.type == "trigger_runner_collect_speak_calls" then
            context.result = {
                debugLines = Common.deep_copy(context.debugLines),
                speakCalls = Common.deep_copy(context.speakCalls),
            }
        elseif event.type == "trigger_runner_start_test" then
            local ok = context.T.TriggerRunner:StartTest()
            context.result = {
                started = ok == true,
                speakCalls = Common.deep_copy(context.speakCalls),
            }
        elseif event.type == "trigger_runner_has_display_text_api" then
            context.result = {
                present = type(context.T.TriggerRunner.BuildEncounterTimelineDisplayText) == "function",
            }
        elseif event.type == "parse_trigger_rule_line" then
            local rule, parseErr = context.T.TriggerSyntax.ParseRuleLine(event.line)
            if rule then
                local result = {
                    spellID = rule.spellID,
                    mode = rule.mode,
                    payload = rule.payload,
                    requireAudience = rule.requireAudience == true,
                    segmentCount = type(rule.segments) == "table" and #rule.segments or 0,
                }
                if rule.occurrence then
                    result.occurrence = rule.occurrence
                end
                if rule.triggerKind then
                    result.triggerKind = rule.triggerKind
                end
                if rule.eventID then
                    result.eventID = rule.eventID
                end
                context.result = result
            else
                context.result = { error = parseErr or "no_match" }
            end
        elseif event.type == "build_trigger_rule_line" then
            context.result = context.T.TriggerSyntax.BuildRuleLine(
                event.spellID, event.occurrence, event.mode, event.payload
            )
        elseif event.type == "should_trigger" then
            context.result = context.T.NoteParser:ShouldTriggerEvent(event.event)
        elseif event.type == "build_timeline_events" then
            local parsed = event.parsed and Common.deep_copy(event.parsed) or {}
            local built = context.T.BuildTimelineEvents(parsed, {})
            context.result = simplify_timeline_events(built)
        elseif event.type == "build_timeline_events_screen" then
            local parsed = event.parsed and Common.deep_copy(event.parsed) or {}
            local built = context.T.BuildTimelineEvents(parsed, {})
            for _, item in ipairs(built or {}) do
                item.ttsText = item.ttsText or context.strip_silent_markers(item.text)
                item.spellIcon = item.spellIcon or context.resolve_spell_icon(item.spellID)
                if item.isSilent == nil then
                    item.isSilent = (item.ttsText == nil or item.ttsText == "")
                end
            end
            context.result = simplify_screen_timeline_events(built)
        elseif event.type == "parse_and_build_timeline_events_screen" then
            local parsed = context.T.TimelineSyntax.ParseTimelineText(event.text or "")
            local built = context.T.BuildTimelineEvents(parsed, {})
            for _, item in ipairs(built or {}) do
                item.ttsText = item.ttsText or context.strip_silent_markers(item.text)
                item.spellIcon = item.spellIcon or context.resolve_spell_icon(item.spellID)
                if item.isSilent == nil then
                    item.isSilent = (item.ttsText == nil or item.ttsText == "")
                end
            end
            context.result = simplify_screen_timeline_events(built)
        elseif event.type == "parse_and_build_board_timeline_events" then
            local parsed = context.T.TimelineSyntax.ParseTimelineText(event.text or "")
            local built = context.T.BuildTimelineEvents(parsed, {}, { showAll = true })
            context.result = simplify_board_timeline_events(built)
        elseif event.type == "play_tts" then
            for _, text in ipairs(event.texts or {}) do
                context.T.PlayTTS(text)
            end
            context.result = Common.deep_copy(context.speakCalls)
        elseif event.type == "run_timers" then
            local remaining = {}
            local ran = 0
            for _, timer in ipairs(context.timerCallbacks) do
                local shouldRun = true
                if event.maxDelay ~= nil then
                    shouldRun = timer.delay <= event.maxDelay
                end
                if event.minDelay ~= nil then
                    shouldRun = shouldRun and timer.delay >= event.minDelay
                end
                if shouldRun then
                    ran = ran + 1
                    if not (timer.timer and timer.timer.cancelled) then
                        timer.fn()
                    end
                else
                    remaining[#remaining + 1] = timer
                end
            end
            context.timerCallbacks = remaining
            context.result = {
                ran = ran,
                speakCalls = Common.deep_copy(context.speakCalls),
            }
        elseif event.type == "tts_event" then
            local args = event.args or { event.utteranceID, event.status }
            context.emit_event(event.eventName, table.unpack(args))
            context.result = Common.deep_copy(context.speakCalls)
        elseif event.type == "clear_tts" then
            context.T.ClearTTSQueue()
            context.result = {
                queueCleared = true,
                speakCalls = Common.deep_copy(context.speakCalls),
            }
        elseif event.type == "collect_tts_trace" then
            context.result = {
                speakCalls = Common.deep_copy(context.speakCalls),
            }
        elseif event.type == "build_voice_text" then
            context.result = context.T.STNVoiceAdapter:BuildVoiceText(event.event)
        elseif event.type == "parse_st_note" then
            context.result = context.T.STNVoiceAdapter:ParseSTNote(event.noteId)
        elseif event.type == "runtime_only_parse_st_note" then
            local semantic = context.T.SemanticTimeline
            local oldGetResolvedPlanTexts = semantic and semantic.GetResolvedPlanTexts
            if semantic and (event.teamText or event.personalText) then
                semantic.GetResolvedPlanTexts = function()
                    return {
                        bossKey = event.bossKey or { instanceType = "raid", instanceID = 1, encounterID = 1 },
                        teamText = event.teamText,
                        personalText = event.personalText,
                    }
                end
            end
            local parsed = context.T.STNVoiceAdapter:ParseSTNote(event.noteId)
            if semantic and (event.teamText or event.personalText) then
                semantic.GetResolvedPlanTexts = oldGetResolvedPlanTexts
            end
            context.result = {
                hasRuntime = semantic and semantic.GetResolvedRuntimePlan ~= nil,
                fullEditorLoaded = semantic and semantic.CompileResolvedPlanContent ~= nil,
                parsed = parsed,
            }
        elseif event.type == "start_from_current" then
            local ok = context.T.TimelineRunner:StartFromCurrent(event.isTest)
            context.result = {
                started = ok,
                injectedCalls = Common.deep_copy(context.injectedCalls),
                clearInjectedCount = context.clearInjectedCount,
            }
        elseif event.type == "collect_runner_state" then
            local state = context.T.TimelineRunner:GetState()
            context.result = {
                playing = state and state.playing == true,
                currentTimePositive = state and (tonumber(state.currentTime) or 0) > 0,
                totalTimePositive = state and (tonumber(state.totalTime) or 0) > 0,
                isTest = state and state.isTest == true,
            }
        elseif event.type == "start_from_current_screen" then
            local ok = context.T.TimelineRunner:StartFromCurrent(event.isTest)
            run_onupdate_frames(context, 0.05)
            if not context.screenReminderHasRealModule then
                local text = nil
                if context.C.DB.dataSource == "STN" and context.T.Note and context.T.Note.GetActivePlan then
                    local plan = context.T.Note:GetActivePlan()
                    text = plan and plan.content or ""
                elseif context.env.VMRT and context.env.VMRT.Note then
                    local note = context.env.VMRT.Note
                    if context.C.DB.useRaidNote and note.Text1 then
                        text = (text and (text .. "\n") or "") .. (note.Text1 or "")
                    end
                    if context.C.DB.useSelfNote and note.SelfText then
                        text = (text and (text .. "\n") or "") .. (note.SelfText or "")
                    end
                end
                if text and text ~= "" then
                    context.build_tactical_notice_plan(text, event.isTest)
                    context.emit_pending_tactical_notices()
                end
            end
            context.result = {
                started = ok,
                injectedCalls = Common.deep_copy(context.injectedCalls),
                clearInjectedCount = context.clearInjectedCount,
            }
        elseif event.type == "tactical_notice_unlock" then
            if context.T.TacticalNotice and context.T.TacticalNotice.SetLocked then
                context.T.TacticalNotice:SetLocked(false)
            end
            run_onupdate_frames(context, 0.05)
            context.result = {
                messages = Common.deep_copy(context.messages),
                debugLines = Common.deep_copy(context.debugLines),
                screen = context.collect_screen_state(),
            }
        elseif event.type == "tactical_notice_lock" then
            if context.T.TacticalNotice and context.T.TacticalNotice.SetLocked then
                context.T.TacticalNotice:SetLocked(true)
            end
            run_onupdate_frames(context, 0.05)
            context.result = {
                messages = Common.deep_copy(context.messages),
                debugLines = Common.deep_copy(context.debugLines),
                screen = context.collect_screen_state(),
            }
        elseif event.type == "tactical_notice_test" then
            if context.T.TacticalNotice and context.T.TacticalNotice.RunTest then
                context.T.TacticalNotice:RunTest()
            end
            run_onupdate_frames(context, 0.05)
            context.result = {
                messages = Common.deep_copy(context.messages),
                debugLines = Common.deep_copy(context.debugLines),
                screen = context.collect_screen_state(),
            }
        elseif event.type == "tactical_notice_command" then
            local handled = false
            if context.T.HandleTacticalNoticeCommand then
                handled = context.T.HandleTacticalNoticeCommand("reminder", event.args or event.sub or "")
            end
            run_onupdate_frames(context, 0.05)
            context.result = {
                handled = handled,
                messages = Common.deep_copy(context.messages),
                debugLines = Common.deep_copy(context.debugLines),
                screen = context.collect_screen_state(),
            }
        elseif event.type == "advance_time" then
            local elapsed = tonumber(event.elapsed or 0)
            context.now = context.now + elapsed
            run_onupdate_frames(context, elapsed)
            context.emit_pending_tactical_notices()
            context.result = {
                now = context.now,
                speakCalls = Common.deep_copy(context.speakCalls),
            }
        elseif event.type == "stop_timeline_screen" then
            local clearCountBeforeStop = context.screenReminderClearCount
            context.T.TimelineRunner:Stop()
            if not context.screenReminderHasRealModule and context.screenReminderClearCount == clearCountBeforeStop and context.T.TacticalNotice and context.T.TacticalNotice.ClearAll then
                context.T.TacticalNotice:ClearAll()
            else
                context.screenReminderPlan = nil
                context.screenReminderEmitted = {}
                context.screenReminderShowIndex = 0
                context.screenReminderStartTime = nil
            end
            context.result = {
                stopped = true,
                screen = context.collect_screen_state(),
            }
        elseif event.type == "set_source_text" then
            local text = event.text or ""
            context.env.VMRT = {
                Note = {
                    Text1 = text,
                    SelfText = "",
                }
            }
            context.C.DB.dataSource = event.source or "MRT"
        elseif event.type == "set_current_plan_bundle" then
            context.C.DB.dataSource = "STN"
            context.T.Note = context.T.Note or {}
            context.T.Note.GetCurrentPlanBundle = function()
                return {
                    bossKeyText = event.bossKeyText or "raid:999:888",
                    teamText = tostring(event.teamText or ""),
                    personalText = tostring(event.personalText or ""),
                    teamName = event.teamName or "团队方案",
                    personalName = event.personalName or "个人方案",
                    teamPlanID = event.teamPlanID or 1,
                    personalPlanID = event.personalPlanID or 2,
                }
            end
        elseif event.type == "set_note" then
            context.T.Note = {
                GetPlan = function(_, id)
                    if id then return event.note[id] end
                    return event.note.default
                end,
                GetActivePlan = function()
                    return event.note.default
                end,
            }
        elseif event.type == "export_import_reseed" then
            local ei = context.ensure_export_import_context()
            local lastText = ei.lastText
            context.seed_export_import_state(ei, event.state or {})
            ei.lastText = lastText
            context.result = {
                ok = true,
            }
        elseif event.type == "export_import_export" then
            local ei = context.ensure_export_import_context()
            local text, err
            if event.channel == "raid" then
                text, err = ei.T.ExportImport:ExportRaidPlans()
            elseif event.channel == "dungeon" then
                text, err = ei.T.ExportImport:ExportDungeonPlans()
            elseif event.channel == "settings" then
                text, err = ei.T.ExportImport:ExportSettings()
            else
                error("未知导出通道: " .. tostring(event.channel))
            end
            ei.lastText = text
            local summary = text and ei.T.ExportImport:Preview(text) or nil
            context.result = {
                ok = text ~= nil,
                err = err,
                prefix = text and text:match("^(STT:%d:[RDS]:)") or nil,
                hasText = text ~= nil,
                summary = context.simplify_export_summary(summary),
            }
        elseif event.type == "export_import_preview" then
            local ei = context.ensure_export_import_context()
            local rawText = event.text
            if rawText == nil and event.source == "last" then
                rawText = ei.lastText
            end
            local summary, err = ei.T.ExportImport:Preview(rawText or "")
            context.result = {
                ok = summary ~= nil,
                err = err,
                summary = context.simplify_export_summary(summary),
            }
        elseif event.type == "export_import_import" then
            local ei = context.ensure_export_import_context()
            local rawText = event.text
            if rawText == nil and event.source == "last" then
                rawText = ei.lastText
            end
            local ok, message = ei.T.ExportImport:Import(rawText or "", event.mode or "merge")
            local output = {
                ok = ok,
                message = message,
                reloadUICount = ei.reloadUICount,
            }
            if event.collectState then
                output.snapshot = context.build_export_import_snapshot(ei, event.collectState)
            end
            context.result = output
        elseif event.type == "export_import_snapshot" then
            local ei = context.ensure_export_import_context()
            context.result = context.build_export_import_snapshot(ei, event)
        elseif event.type == "settings_schema_audit" then
            context.result = context.audit_settings_schema()
        elseif event.type == "collect" then
            context.result = {
                messages = Common.deep_copy(context.messages),
                debugLines = Common.deep_copy(context.debugLines),
                speakCalls = Common.deep_copy(context.speakCalls),
                injectedCalls = Common.deep_copy(context.injectedCalls),
                clearInjectedCount = context.clearInjectedCount,
                screen = context.collect_screen_state(),
            }
        elseif event.type == "collect_member_runtime_outputs" then
            context.result = {
                defaults = {
                    ttsEnabled = context.C.DB.ttsEnabled == true,
                    countdownEnabled = context.C.DB.CountdownEnabled == true,
                    barEnabled = type(context.C.DB.Bar) == "table" and context.C.DB.Bar.Enabled == true,
                    semanticRuntimeEnabled = type(context.C.DB.semanticTimeline) == "table" and context.C.DB.semanticTimeline.runtimeEnabled == true,
                    semanticEditorEnabled = type(context.C.DB.semanticTimeline) == "table" and context.C.DB.semanticTimeline.enabled == true,
                },
                loaded = {
                    hasRuntime = context.T.SemanticTimeline and context.T.SemanticTimeline.GetResolvedRuntimePlan ~= nil or false,
                    fullEditorLoaded = context.T.SemanticTimeline and context.T.SemanticTimeline.CompileResolvedPlanContent ~= nil or false,
                },
                speakCalls = Common.deep_copy(context.speakCalls),
                soundCallCount = #context.soundCalls,
                barCalls = Common.deep_copy(context.barCalls),
                realtimeBoardStarts = Common.deep_copy(context.realtimeBoardStarts),
            }
        elseif event.type == "collect_diagnose_hits" then
            if context.ensure_diagnose_module then
                context.ensure_diagnose_module()
            end
            local result = context.T.Diagnose and context.T.Diagnose.ScanSelfHits and context.T.Diagnose.ScanSelfHits() or {}
            context.result = {
                ttsHits = tonumber(result.ttsHits) or 0,
                displayHits = tonumber(result.displayHits) or 0,
                reason = tostring(result.reason or ""),
                source = tostring(result.source or ""),
            }
        elseif event.type == "collect_screen" then
            context.result = {
                messages = Common.deep_copy(context.messages),
                debugLines = Common.deep_copy(context.debugLines),
                speakCalls = Common.deep_copy(context.speakCalls),
                injectedCalls = Common.deep_copy(context.injectedCalls),
                clearInjectedCount = context.clearInjectedCount,
                screen = context.collect_screen_state(),
            }
        elseif event.type == "friendly_nameplate_create_ui" then
            ensure_friendly_nameplate_ui()
            local panel = context.env.CreateFrame("Frame", "FriendlyNameplatePanel", nil)
            context.friendlyNameplatePanel = panel
            context.T.FriendlyNameplate.CreateInterface(panel)
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "friendly_nameplate_toggle" then
            context.T.FriendlyNameplate:Toggle()
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "friendly_nameplate_apply" then
            context.T.FriendlyNameplate:ApplyNow()
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "friendly_nameplate_set_option" then
            context.T.FriendlyNameplate:SetOption(event.key, event.value)
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "friendly_nameplate_set_instance" then
            context.instanceType = event.instanceType or "none"
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "friendly_nameplate_event" then
            if context.T.FriendlyNameplate and context.T.FriendlyNameplate.eventFrame then
                context.T.FriendlyNameplate.eventFrame:TriggerEvent(event.name or "PLAYER_ENTERING_WORLD")
            end
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "friendly_nameplate_driver_event" then
            local hooks = context.env.NamePlateDriverFrame and context.env.NamePlateDriverFrame.__hooks or {}
            for _, hook in ipairs(hooks[event.name] or {}) do
                hook(context.env.NamePlateDriverFrame, event.plateFrame)
            end
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "friendly_nameplate_mutate_nameplate_font" then
            local plate = context.nameplates[event.index]
            local nameRegion = plate and plate.UnitFrame and plate.UnitFrame.name or nil
            if nameRegion then
                local path = event.path
                local size = event.size
                local flags = event.flags
                if path == nil or size == nil or flags == nil then
                    local currentPath, currentSize, currentFlags = nameRegion:GetFont()
                    if path == nil then
                        path = currentPath
                    end
                    if size == nil then
                        size = currentSize
                    end
                    if flags == nil then
                        flags = currentFlags
                    end
                end
                nameRegion:SetFont(path, size, flags)
            end
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "friendly_nameplate_collect" then
            context.result = collect_friendly_nameplate_state()
        elseif event.type == "visual_board_cold_load_contract" then
            context.result = run_visual_board_cold_load_contract()
        elseif event.type == "semantic_boss_visual_board_package_sync" then
            context.result = run_semantic_boss_visual_board_package_sync()
        elseif event.type == "visual_board_midnightfall_template" then
            ensure_visual_board()
            context.env.STT_VisualBoardsDB = {}
            local data = context.T.VisualBoardData
            local board = data and data:CreateBoard(event.name or "至暗之夜测试画板") or nil
            if board and data.SetBackgroundEncounter then
                data:SetBackgroundEncounter(board.id, tonumber(event.encounterID) or 3183)
            end
            if board and data.ApplyTemplate_P2toP3 then
                data:ApplyTemplate_P2toP3(board.id)
            end
            board = board and data:GetBoard(board.id) or nil
            local counts = {}
            local textureIcons, spellIcons, markerIcons, shapeCircles, shapeArrows, lowYellowCircles = 0, 0, 0, 0, 0, 0
            local titleText, doorText
            for _, element in ipairs(board and board.elements or {}) do
                local elementType = tostring(element.type or "")
                counts[elementType] = (counts[elementType] or 0) + 1
                local params = element.params or {}
                if elementType == "icon" then
                    if tostring(params.texture or "") ~= "" then
                        textureIcons = textureIcons + 1
                    end
                    if tonumber(params.spellID) then
                        spellIcons = spellIcons + 1
                    end
                elseif elementType == "marker" then
                    markerIcons = markerIcons + 1
                elseif elementType == "shape" then
                    if params.shapeKind == "circle" then
                        shapeCircles = shapeCircles + 1
                        if params.color == "FFD11A" and (tonumber(element.z) or 0) < 0 then
                            lowYellowCircles = lowYellowCircles + 1
                        end
                    elseif params.shapeKind == "arrow" then
                        shapeArrows = shapeArrows + 1
                    end
                elseif elementType == "text" then
                    if params.text == "P2第四轮分散示意图" then
                        titleText = params.text
                    elseif params.text == "门口" then
                        doorText = params.text
                    end
                end
            end

            local render = nil
            if event.render == true and board and context.T.VisualBoardCanvas then
                local parent = context.env.CreateFrame("Frame", "VisualBoardTestCanvas", nil)
                parent:SetSize(1600, 900)
                local renderer = context.T.VisualBoardCanvas:Create(parent)
                renderer:Render(board, { mode = "edit", currentSlideIndex = 1 }, { mode = "edit", viewport = { zoom = 1, panX = 0, panY = 0 } })
                render = {
                    textures = #renderer.textures,
                    fontStrings = #renderer.fontStrings,
                    lines = #renderer.lines,
                    firstTexture = renderer.textures[1] and renderer.textures[1].__texture or nil,
                }
            end

            context.result = {
                encounterID = board and board.encounterID or nil,
                background = board and board.bg and board.bg.name or nil,
                elementCount = #(board and board.elements or {}),
                counts = counts,
                textureIcons = textureIcons,
                spellIcons = spellIcons,
                markerIcons = markerIcons,
                shapeCircles = shapeCircles,
                shapeArrows = shapeArrows,
                lowYellowCircles = lowYellowCircles,
                titleText = titleText,
                doorText = doorText,
                render = render,
            }
        elseif event.type == "visual_board_clock_boss_icon" then
            ensure_visual_board()
            context.env.STT_VisualBoardsDB = {}
            local data = context.T.VisualBoardData
            local board = data and data:CreateBoard(event.name or "至暗之夜Boss图标测试画板") or nil
            if board and data.ApplyTemplate_P3ClockPositions then
                data:ApplyTemplate_P3ClockPositions(board.id)
            end
            board = board and data:GetBoard(board.id) or nil

            local iconCount, bossIconCount, textureIconCount, circleIconCount, redCircleCount = 0, 0, 0, 0, 0
            for _, element in ipairs(board and board.elements or {}) do
                if element.type == "icon" then
                    iconCount = iconCount + 1
                    local params = element.params or {}
                    if tostring(params.texture or "") ~= "" then
                        textureIconCount = textureIconCount + 1
                    end
                    if params.shape == "circle" then
                        circleIconCount = circleIconCount + 1
                    end
                    if tonumber(params.encounterID) == 3183 and tonumber(params.encounterIcon) == 7448204 then
                        bossIconCount = bossIconCount + 1
                    end
                elseif element.type == "shape" and element.params and element.params.shapeKind == "circle"
                    and tostring(element.params.color or "") == "D63315" then
                    redCircleCount = redCircleCount + 1
                end
            end

            local renderTexture, renderMaskCount = nil, 0
            if event.render == true and board and context.T.VisualBoardCanvas then
                local parent = context.env.CreateFrame("Frame", "VisualBoardBossIconCanvas", nil)
                parent:SetSize(1600, 900)
                local renderer = context.T.VisualBoardCanvas:Create(parent)
                renderer:Render(board, { mode = "edit", currentSlideIndex = 1 }, { mode = "edit", viewport = { zoom = 1, panX = 0, panY = 0 } })
                for _, texture in ipairs(renderer.textures or {}) do
                    if texture.__texture == 7448204 then
                        renderTexture = texture.__texture
                        if type(texture.__maskTextures) == "table" then
                            renderMaskCount = renderMaskCount + #texture.__maskTextures
                        end
                    end
                end
            end

            context.result = {
                encounterID = board and board.encounterID or nil,
                iconCount = iconCount,
                bossIconCount = bossIconCount,
                textureIconCount = textureIconCount,
                circleIconCount = circleIconCount,
                redCircleCount = redCircleCount,
                renderTexture = renderTexture,
                renderMaskCount = renderMaskCount,
            }
        elseif event.type == "visual_board_v2_contract" then
            ensure_visual_board()
            context.env.STT_VisualBoardsDB = {}
            local data = context.T.VisualBoardData
            local board = data and data:CreateBoard(event.name or "v2契约测试画板") or nil
            local result = {}
            if board then
                local bgCircle = data:AddElementAt(board.id, "shape", 100, 100, {
                    params = { shapeKind = "circle", color = "FFD11A", alpha = 0.85, radius = 30 },
                })
                local person = data:AddElementAt(board.id, "person", 100, 100, {
                    params = {
                        slotName = "P1",
                        icon = { spellID = 1253031, texture = "Interface\\Icons\\BadLegacyTexture" },
                        text = { position = "bottom", justifyH = "RIGHT" },
                    },
                })
                local icon = data:AddElementAt(board.id, "icon", 180, 100, {
                    params = { spellID = 1253031, texture = "Interface\\Icons\\BadLegacyTexture", atlas = "bad-atlas", size = 40 },
                })
                local text = data:AddElementAt(board.id, "text", 240, 100, {
                    params = { text = "左对齐", justifyH = "LEFT", width = 120, fontSize = 20 },
                })
                local illegalShape = data:AddElementAt(board.id, "shape", 300, 100, {
                    params = { shapeKind = "person" },
                })
                local shapeSwitch = data:AddElementAt(board.id, "shape", 360, 100, {
                    params = { shapeKind = "rect", w = 80, h = 40 },
                })
                if shapeSwitch then
                    data:UpdateElement(board.id, shapeSwitch.id, { params = { shapeKind = "circle" } })
                    shapeSwitch = data:GetElement(board.id, shapeSwitch.id)
                end
                local switchedCircle = {
                    kind = shapeSwitch and shapeSwitch.params and shapeSwitch.params.shapeKind or nil,
                    radius = shapeSwitch and shapeSwitch.params and shapeSwitch.params.radius or nil,
                    endX = shapeSwitch and shapeSwitch.end_x or nil,
                }
                if shapeSwitch then
                    data:UpdateElement(board.id, shapeSwitch.id, { params = { shapeKind = "arrow" } })
                    shapeSwitch = data:GetElement(board.id, shapeSwitch.id)
                end
                local switchedArrow = {
                    kind = shapeSwitch and shapeSwitch.params and shapeSwitch.params.shapeKind or nil,
                    endX = shapeSwitch and shapeSwitch.end_x or nil,
                    endY = shapeSwitch and shapeSwitch.end_y or nil,
                    thickness = shapeSwitch and shapeSwitch.params and shapeSwitch.params.thickness or nil,
                    arrowSize = shapeSwitch and shapeSwitch.params and shapeSwitch.params.arrowSize or nil,
                }
                board = data:GetBoard(board.id)
                local parent = context.env.CreateFrame("Frame", "VisualBoardV2Canvas", nil)
                parent:SetSize(500, 300)
                local renderer = context.T.VisualBoardCanvas:Create(parent)
                renderer:Render(board, { mode = "edit", currentSlideIndex = 1 }, { mode = "edit", viewport = { zoom = 1, panX = 0, panY = 0 } })

                local spaceSelectCount, spaceDragCount, spaceBackgroundCount = 0, 0, 0
                local normalSelectCount, normalDragCount, normalBackgroundCount = 0, 0, 0
                local editorSpaceWhileDown, editorSpaceAfterRelease = false, false
                local editor = context.T.VisualBoardEditorGUI
                if editor and editor.HandleKeyDown and editor.IsSpacePanActive then
                    context.keyDownMap.SPACE = true
                    editor:HandleKeyDown("SPACE")
                    editorSpaceWhileDown = editor:IsSpacePanActive()
                    context.keyDownMap.SPACE = false
                    editorSpaceAfterRelease = editor:IsSpacePanActive()
                end
                local spaceActive = true
                local inputParent = context.env.CreateFrame("Frame", "VisualBoardV2InputCanvas", nil)
                inputParent:SetSize(500, 300)
                local inputRenderer = context.T.VisualBoardCanvas:Create(inputParent)
                inputRenderer:Render(board, { mode = "edit", currentSlideIndex = 1 }, {
                    mode = "edit",
                    viewport = { zoom = 1, panX = 0, panY = 0 },
                    currentSlideIndex = 1,
                    isSpacePanActive = function() return spaceActive end,
                    onSelect = function()
                        if spaceActive then
                            spaceSelectCount = spaceSelectCount + 1
                        else
                            normalSelectCount = normalSelectCount + 1
                        end
                    end,
                    onDrag = function(_, _, _, transient)
                        if not transient then
                            if spaceActive then
                                spaceDragCount = spaceDragCount + 1
                            else
                                normalDragCount = normalDragCount + 1
                            end
                        end
                    end,
                    onBackgroundClick = function()
                        if spaceActive then
                            spaceBackgroundCount = spaceBackgroundCount + 1
                        else
                            normalBackgroundCount = normalBackgroundCount + 1
                        end
                    end,
                })
                local hit = inputRenderer.hitFrames and inputRenderer.hitFrames[1] or nil
                if hit then
                    hit:TriggerScript("OnClick", "LeftButton")
                    hit:TriggerScript("OnDragStart")
                    hit:TriggerScript("OnDragStop")
                end
                if inputRenderer.backgroundCatcher then
                    inputRenderer.backgroundCatcher:TriggerScript("OnClick")
                end
                spaceActive = false
                if hit then
                    hit:TriggerScript("OnClick", "LeftButton")
                    hit:TriggerScript("OnDragStart")
                    hit:TriggerScript("OnDragStop")
                end
                if inputRenderer.backgroundCatcher then
                    inputRenderer.backgroundCatcher:TriggerScript("OnClick")
                end

                local fontJustify = {}
                for _, fontString in ipairs(renderer.fontStrings or {}) do
                    if fontString.__text and fontString.__text ~= "" then
                        fontJustify[#fontJustify + 1] = {
                            text = fontString.__text,
                            justifyH = fontString.__justifyH,
                            width = fontString.__width,
                        }
                    end
                end

                local shortcutSpacePropagates, shortcutSpaceKeyUpPropagates = nil, nil
                local shortcutCommandXDeleted, shortcutCommandXPropagates = false, nil
                local shortcutCommandCopyConsumed, shortcutCommandPasteConsumed, shortcutPasteCreated = false, false, false
                if editor and editor.SetActiveBoard and editor.Select and context.T.KeyboardCapture then
                    local shortcutCopy = data:AddElementAt(board.id, "shape", 420, 100, {
                        params = { shapeKind = "rect", w = 30, h = 30 },
                    })
                    if editor:SetActiveBoard(board.id) and shortcutCopy then
                        editor:Select(shortcutCopy.id, false)
                        context.keyModifiers.meta = true
                        shortcutCommandCopyConsumed = editor:HandleKeyDown("C") == true
                        local beforePasteCount = #(data:GetBoard(board.id).elements or {})
                        shortcutCommandPasteConsumed = editor:HandleKeyDown("V") == true
                        shortcutPasteCreated = #(data:GetBoard(board.id).elements or {}) > beforePasteCount
                        context.keyModifiers.meta = false
                    end

                    local shortcutCut = data:AddElementAt(board.id, "shape", 460, 100, {
                        params = { shapeKind = "rect", w = 30, h = 30 },
                    })
                    local root = context.env.CreateFrame("Frame", "VisualBoardShortcutCapture", nil)
                    context.T.KeyboardCapture.Bind(root, {
                        {
                            key = "SPACE",
                            handler = function()
                                return editor:HandleKeyDown("SPACE")
                            end,
                        },
                        {
                            key = "X",
                            ctrl = true,
                            handler = function()
                                return editor:HandleKeyDown("X")
                            end,
                        },
                    })
                    root:TriggerScript("OnKeyDown", "SPACE")
                    shortcutSpacePropagates = root.__propagateKeyboardInput
                    root:TriggerScript("OnKeyUp", "SPACE")
                    shortcutSpaceKeyUpPropagates = root.__propagateKeyboardInput
                    editor:HandleKeyUp("SPACE")
                    if shortcutCut and editor:SetActiveBoard(board.id) then
                        editor:Select(shortcutCut.id, false)
                        context.keyModifiers.meta = true
                        root:TriggerScript("OnKeyDown", "X")
                        shortcutCommandXPropagates = root.__propagateKeyboardInput
                        context.keyModifiers.meta = false
                        shortcutCommandXDeleted = data:GetElement(board.id, shortcutCut.id) == nil
                    end
                end

                local function point_payload(frame)
                    if not (frame and frame.GetPoint) then
                        return nil
                    end
                    local point, _, relPoint, x, y = frame:GetPoint()
                    return { point = point, relPoint = relPoint, x = x, y = y }
                end

                local function find_element_frame(frames, elementID)
                    for _, frame in ipairs(frames or {}) do
                        if frame.elementID == elementID then
                            return frame
                        end
                    end
                    return nil
                end

                local function find_selection_marker(renderer)
                    for _, texture in ipairs(renderer and renderer.textures or {}) do
                        local color = texture.__colorTexture
                        if type(color) == "table"
                            and color[1] == 1.0
                            and color[2] == 0.82
                            and color[3] == 0.18
                            and color[4] == 0.24 then
                            return texture
                        end
                    end
                    return nil
                end

                local frameGeometry = nil
                local geometryBoard = data:CreateBoard("当前帧几何测试")
                if geometryBoard then
                    local tracked = data:AddElementAt(geometryBoard.id, "text", 100, 100, {
                        params = { text = "几何", fontSize = 20, width = 120 },
                    })
                    data:AddSlide(geometryBoard.id, "2")
                    if tracked then
                        data:SetSlideOverride(geometryBoard.id, 2, tracked.id, "x", 300)
                        data:SetSlideOverride(geometryBoard.id, 2, tracked.id, "y", 220)
                    end
                    geometryBoard = data:GetBoard(geometryBoard.id)
                    if tracked and geometryBoard then
                        local function render_slide(index)
                            local geomParent = context.env.CreateFrame("Frame", "VisualBoardGeometryCanvas" .. tostring(index), nil)
                            geomParent:SetSize(500, 300)
                            local geomRenderer = context.T.VisualBoardCanvas:Create(geomParent)
                            geomRenderer:Render(geometryBoard, { mode = "edit", currentSlideIndex = index }, {
                                mode = "edit",
                                viewport = { zoom = 1, panX = 0, panY = 0 },
                                currentSlideIndex = index,
                                selectedIDs = { [tracked.id] = true },
                            })
                            return geomRenderer
                        end

                        local slide1Renderer = render_slide(1)
                        local slide2Renderer = render_slide(2)
                        local slide2Geometry = data.ResolveElementGeometryAtSlide and data:ResolveElementGeometryAtSlide(tracked, 2, geometryBoard) or nil

                        frameGeometry = {
                            slide1Hit = point_payload(find_element_frame(slide1Renderer.hitFrames, tracked.id)),
                            slide2Hit = point_payload(find_element_frame(slide2Renderer.hitFrames, tracked.id)),
                            slide2Selection = point_payload(find_selection_marker(slide2Renderer)),
                            slide2Rotation = point_payload(find_element_frame(slide2Renderer.rotationFrames, tracked.id)),
                            slide2Geometry = slide2Geometry and {
                                x = slide2Geometry.x,
                                y = slide2Geometry.y,
                                scale = slide2Geometry.scale,
                            } or nil,
                        }
                    end
                end

                result = {
                    illegalShapeKind = illegalShape and illegalShape.params and illegalShape.params.shapeKind or nil,
                    shapeSwitchCircleKind = switchedCircle.kind,
                    shapeSwitchCircleRadius = switchedCircle.radius,
                    shapeSwitchCircleEndX = switchedCircle.endX,
                    shapeSwitchArrowKind = switchedArrow.kind,
                    shapeSwitchArrowEndX = switchedArrow.endX,
                    shapeSwitchArrowEndY = switchedArrow.endY,
                    shapeSwitchArrowThickness = switchedArrow.thickness,
                    shapeSwitchArrowSize = switchedArrow.arrowSize,
                    spacePanSelectCount = spaceSelectCount,
                    spacePanDragCount = spaceDragCount,
                    spacePanBackgroundCount = spaceBackgroundCount,
                    normalSelectCount = normalSelectCount,
                    normalDragCount = normalDragCount,
                    normalBackgroundCount = normalBackgroundCount,
                    editorSpaceWhileDown = editorSpaceWhileDown,
                    editorSpaceAfterRelease = editorSpaceAfterRelease,
                    shortcutSpacePropagates = shortcutSpacePropagates,
                    shortcutSpaceKeyUpPropagates = shortcutSpaceKeyUpPropagates,
                    shortcutCommandXPropagates = shortcutCommandXPropagates,
                    shortcutCommandXDeleted = shortcutCommandXDeleted,
                    shortcutCommandCopyConsumed = shortcutCommandCopyConsumed,
                    shortcutCommandPasteConsumed = shortcutCommandPasteConsumed,
                    shortcutPasteCreated = shortcutPasteCreated,
                    iconSpellID = icon and icon.params and icon.params.spellID or nil,
                    iconTexture = icon and icon.params and icon.params.texture or nil,
                    iconAtlas = icon and icon.params and icon.params.atlas or nil,
                    iconShape = icon and icon.params and icon.params.shape or nil,
                    personSpellID = person and person.params and person.params.icon and person.params.icon.spellID or nil,
                    personTexture = person and person.params and person.params.icon and person.params.icon.texture or nil,
                    personIconShape = person and person.params and person.params.icon and person.params.icon.shape or nil,
                    circleZ = bgCircle and bgCircle.z or nil,
                    personZ = person and person.z or nil,
                    fontJustify = fontJustify,
                    renderedTextures = {
                        first = renderer.textures[1] and renderer.textures[1].__texture or nil,
                        second = renderer.textures[2] and renderer.textures[2].__texture or nil,
                        third = renderer.textures[3] and renderer.textures[3].__texture or nil,
                    },
                    renderedMasks = {
                        first = renderer.textures[1] and renderer.textures[1].__maskTextures and #renderer.textures[1].__maskTextures or 0,
                        second = renderer.textures[2] and renderer.textures[2].__maskTextures and #renderer.textures[2].__maskTextures or 0,
                        third = renderer.textures[3] and renderer.textures[3].__maskTextures and #renderer.textures[3].__maskTextures or 0,
                    },
                    frameGeometry = frameGeometry,
                }
            end
            context.result = result
        elseif event.type == "interrupt_macro_preview" then
            local macro = context.T.InterruptRotationMacro
            local spellID, spellName, icon = macro:GetSpellMeta()
            context.result = {
                spellID = spellID,
                spellName = spellName,
                icon = icon,
                preview = macro:GetMacroPreview(),
            }
        else
            error("未知 STT 事件类型: " .. tostring(event.type))
        end
    end
end

function M.RunCase(caseName, fixture)
    local context = create_context(fixture)
    function context.STT.TestAPI.RunCase(_, _caseName, _fixture)
        process_events(context, _fixture.events)
        return {
            ok = true,
            output = context.result,
            case = _caseName,
        }
    end

    return context.STT.TestAPI.RunCase(context.STT.TestAPI, caseName, fixture)
end

return M
