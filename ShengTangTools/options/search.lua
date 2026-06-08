local T, C, L = unpack(select(2, ...))

local OptionSearch = {}
T.OptionSearch = OptionSearch

local function Text(key, fallback)
    local value = key and rawget(L, key)
    if value ~= nil then
        return value
    end
    return fallback or key or ""
end

function OptionSearch.Create(parent, width)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 32)

    local editBox = T.CreateEditBox(frame, {
        width = width,
        height = 26,
        point = { "TOPLEFT", frame, "TOPLEFT", 0, 0 },
        placeholder = Text("GUI_SEARCH_PLACEHOLDER", "搜索设置..."),
    })
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    frame.editBox = editBox
    frame.searchSerial = 0

    function frame:SetOnQueryChanged(callback)
        self.onQueryChanged = callback
    end

    function frame:GetQuery()
        return self.editBox:GetText() or ""
    end

    function frame:SetQuery(value)
        self.editBox:SetText(value or "")
    end

    function frame:RefreshTexts()
        if self.editBox.placeholder then
            self.editBox.placeholder:SetText(Text("GUI_SEARCH_PLACEHOLDER", "搜索设置..."))
        end
    end

    function frame:SetSearchWidth(nextWidth)
        local w = math.max(1, tonumber(nextWidth) or width)
        self:SetWidth(w)
        if self.editBox then
            self.editBox:SetWidth(w)
        end
    end

    editBox:SetScript("OnTextChanged", function(selfBox)
        frame.searchSerial = frame.searchSerial + 1
        local serial = frame.searchSerial
        C_Timer.After(0.3, function()
            if serial ~= frame.searchSerial then
                return
            end
            if type(frame.onQueryChanged) == "function" then
                frame.onQueryChanged(selfBox:GetText() or "")
            end
        end)
        if selfBox.placeholder then
            selfBox.placeholder:SetShown((selfBox:GetText() or "") == "" and not selfBox:HasFocus())
        end
    end)

    return frame
end
