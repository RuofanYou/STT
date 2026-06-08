local T = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local KeyboardCapture = {}
T.KeyboardCapture = KeyboardCapture

KeyboardCapture.roots = {}
KeyboardCapture.focusedEditBox = nil

local function ModifierDown(fn)
    return fn and fn() or false
end

local function NormalizeKey(key)
    return tostring(key or ""):upper()
end

local function GetModifiers()
    return {
        ctrl = ModifierDown(IsControlKeyDown) or ModifierDown(IsMetaKeyDown),
        shift = ModifierDown(IsShiftKeyDown),
        alt = ModifierDown(IsAltKeyDown),
    }
end

local function HotkeyMatches(hotkey, key, mods)
    if NormalizeKey(hotkey.key) ~= NormalizeKey(key) then
        return false
    end
    return (hotkey.ctrl == true) == mods.ctrl
        and (hotkey.shift == true) == mods.shift
        and (hotkey.alt == true) == mods.alt
end

local function DebugError(message)
    if T and T.debug then
        T.debug("[STT_KEYBOARD_CAPTURE_ERROR] " .. tostring(message or "unknown"))
    end
end

function KeyboardCapture:_Dispatch(root, owner, key, fromEditBox)
    local binding = root and self.roots[root]
    if not binding then
        return false
    end
    local mods = GetModifiers()
    if fromEditBox and not (mods.ctrl or mods.alt) then
        return false
    end
    if self.focusedEditBox and not (mods.ctrl or mods.alt) then
        return false
    end
    if not fromEditBox and root and MouseIsOver and not MouseIsOver(root) then
        return false
    end

    for _, hotkey in ipairs(binding.hotkeys or {}) do
        if HotkeyMatches(hotkey, key, mods) then
            local ok, consumed = pcall(hotkey.handler, {
                key = key,
                root = root,
                owner = owner,
                fromEditBox = fromEditBox and true or false,
            })
            if not ok then
                DebugError(consumed)
                return false
            end
            return consumed == true
        end
    end
    return false
end

function KeyboardCapture.Bind(root, hotkeys)
    if not root or type(hotkeys) ~= "table" then
        return
    end

    local binding = KeyboardCapture.roots[root]
    if not binding then
        binding = { hotkeys = {} }
        KeyboardCapture.roots[root] = binding
    end
    for _, hotkey in ipairs(hotkeys) do
        if type(hotkey) == "table" and hotkey.key and type(hotkey.handler) == "function" then
            binding.hotkeys[#binding.hotkeys + 1] = hotkey
        end
    end

    if root.EnableKeyboard then
        root:EnableKeyboard(true)
    end
    if root.SetPropagateKeyboardInput then
        root:SetPropagateKeyboardInput(true)
    end
    root:SetScript("OnKeyDown", function(owner, key)
        local consumed = KeyboardCapture:_Dispatch(root, owner, key, false)
        if owner and owner.SetPropagateKeyboardInput then
            owner:SetPropagateKeyboardInput(not consumed)
        end
    end)
    root:SetScript("OnKeyUp", function(owner)
        if owner and owner.SetPropagateKeyboardInput then
            owner:SetPropagateKeyboardInput(true)
        end
    end)
end

function KeyboardCapture.AttachEditBox(editBox, root)
    if not editBox then
        return
    end
    if editBox.EnableKeyboard then
        editBox:EnableKeyboard(true)
    end
    if editBox.SetPropagateKeyboardInput then
        editBox:SetPropagateKeyboardInput(editBox.HasFocus and not editBox:HasFocus() or true)
    end
    if editBox.HookScript then
        editBox:HookScript("OnEditFocusGained", function(owner)
            KeyboardCapture.focusedEditBox = owner
            if owner and owner.SetPropagateKeyboardInput then
                owner:SetPropagateKeyboardInput(false)
            end
        end)
        editBox:HookScript("OnEditFocusLost", function(owner)
            if KeyboardCapture.focusedEditBox == owner then
                KeyboardCapture.focusedEditBox = nil
            end
            if owner and owner.SetPropagateKeyboardInput then
                owner:SetPropagateKeyboardInput(true)
            end
        end)
    end
    editBox:SetScript("OnKeyDown", function(owner, key)
        KeyboardCapture:_Dispatch(root, owner, key, true)
        if owner and owner.SetPropagateKeyboardInput then
            owner:SetPropagateKeyboardInput(false)
        end
    end)
    editBox:SetScript("OnKeyUp", function(owner)
        if owner and owner.SetPropagateKeyboardInput then
            owner:SetPropagateKeyboardInput(owner.HasFocus and not owner:HasFocus() or true)
        end
    end)
end

function KeyboardCapture.GetState()
    return {
        editBoxFocused = KeyboardCapture.focusedEditBox ~= nil,
    }
end

end)
