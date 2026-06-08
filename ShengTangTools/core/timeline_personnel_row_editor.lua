local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local Editor = {}
T.TimelinePersonnelRowEditor = Editor

local WIDTH = 420
local HEIGHT = 320
local FIELD_W = 260
local DEFAULT_ICON = 134400
local NONE_SPEC = "__none"

local SPEC_OPTIONS = {
    { 250, "死亡骑士 / 鲜血" }, { 251, "死亡骑士 / 冰霜" }, { 252, "死亡骑士 / 邪恶" },
    { 577, "恶魔猎手 / 浩劫" }, { 581, "恶魔猎手 / 复仇" }, { 1480, "恶魔猎手 / 噬灭" },
    { 102, "德鲁伊 / 平衡" }, { 103, "德鲁伊 / 野性" }, { 104, "德鲁伊 / 守护" }, { 105, "德鲁伊 / 恢复" },
    { 1473, "唤魔师 / 增辉" }, { 1467, "唤魔师 / 湮灭" }, { 1468, "唤魔师 / 恩护" },
    { 253, "猎人 / 野兽控制" }, { 254, "猎人 / 射击" }, { 255, "猎人 / 生存" },
    { 62, "法师 / 奥术" }, { 63, "法师 / 火焰" }, { 64, "法师 / 冰霜" },
    { 268, "武僧 / 酒仙" }, { 269, "武僧 / 踏风" }, { 270, "武僧 / 织雾" },
    { 65, "圣骑士 / 神圣" }, { 66, "圣骑士 / 防护" }, { 70, "圣骑士 / 惩戒" },
    { 256, "牧师 / 戒律" }, { 257, "牧师 / 神圣" }, { 258, "牧师 / 暗影" },
    { 259, "潜行者 / 奇袭" }, { 260, "潜行者 / 狂徒" }, { 261, "潜行者 / 敏锐" },
    { 262, "萨满祭司 / 元素" }, { 263, "萨满祭司 / 增强" }, { 264, "萨满祭司 / 恢复" },
    { 265, "术士 / 痛苦" }, { 266, "术士 / 恶魔学识" }, { 267, "术士 / 毁灭" },
    { 71, "战士 / 武器" }, { 72, "战士 / 狂怒" }, { 73, "战士 / 防护" },
}

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function Text(key, fallback)
    return (L and L[key]) or fallback
end

local function Msg(text)
    if T.msg then
        T.msg(text)
    end
end

local function ResolveSpecInfo(specID)
    local id = tonumber(specID)
    if not id then
        return nil
    end
    if GetSpecializationInfoByID then
        local ok, _, name, _, icon = pcall(GetSpecializationInfoByID, id)
        if ok then
            return {
                id = id,
                name = name,
                icon = icon,
            }
        end
    end
    return {
        id = id,
        icon = DEFAULT_ICON,
    }
end

local function BuildSpecItems()
    local items = {
        { text = Text("PERSONNEL_ROW_EDITOR_SPEC_NONE", "不指定（问号）"), value = NONE_SPEC },
    }
    for _, pair in ipairs(SPEC_OPTIONS) do
        local specID, fallback = pair[1], pair[2]
        items[#items + 1] = {
            text = fallback,
            value = tostring(specID),
        }
    end
    return items
end

local function SetEditEnabled(edit, enabled)
    if not edit then
        return
    end
    if enabled then
        edit:Enable()
        edit:SetAlpha(1)
    else
        edit:Disable()
        edit:SetAlpha(0.45)
    end
end

local function SetSelectorEnabled(selector, enabled)
    if not selector then
        return
    end
    if selector.SetSelectorEnabled then
        selector:SetSelectorEnabled(enabled == true)
    elseif enabled and selector.Enable then
        selector:Enable()
    elseif selector.Disable then
        selector:Disable()
    end
    selector:SetAlpha(enabled and 1 or 0.45)
end

local function ValidateName(text)
    local value = Trim(text)
    if value == "" then
        return false, "empty"
    end
    if value:find("[=\r\n%[%]{}]") then
        return false, "invalid"
    end
    return true
end

function Editor:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "STT_TimelinePersonnelRowEditor", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(90)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    T.ApplyBackdrop(frame, { alpha = 0.90, style = "tooltip" })

    frame.title = T.CreateFontString(frame, {
        template = "GameFontNormalLarge",
        point = { "TOPLEFT", frame, "TOPLEFT", 18, -18 },
        size = 16,
        flags = "OUTLINE",
        color = { 1, 0.86, 0.25, 1 },
        text = Text("PERSONNEL_ROW_EDITOR_TITLE", "新增人员行"),
    })

    frame.close = T.CreateButton(frame, { width = 26, height = 24, point = { "TOPRIGHT", frame, "TOPRIGHT", -12, -12 } })
    frame.close:SetText("×")
    frame.close:SetScript("OnClick", function()
        Editor.Close()
    end)

    T.CreateLabel(frame, { text = Text("PERSONNEL_ROW_EDITOR_ROW_NAME", "行名称"), point = { "TOPLEFT", frame, "TOPLEFT", 24, -64 }, width = 90 })
    frame.rowName = T.CreateEditBox(frame, {
        width = FIELD_W,
        height = 26,
        point = { "TOPLEFT", frame, "TOPLEFT", 120, -60 },
        placeholder = Text("PERSONNEL_ROW_EDITOR_ROW_PLACEHOLDER", "例如：增辉1"),
    })

    frame.mappingEnabled = T.CreateCheckbox(frame, {
        point = { "TOPLEFT", frame, "TOPLEFT", 24, -104 },
        label = Text("PERSONNEL_ROW_EDITOR_MAPPING", "人员映射"),
        clickLabel = true,
    })
    frame.mappingEdit = T.CreateEditBox(frame, {
        width = FIELD_W,
        height = 26,
        point = { "TOPLEFT", frame, "TOPLEFT", 120, -100 },
        placeholder = Text("PERSONNEL_ROW_EDITOR_MAPPING_PLACEHOLDER", "不填则只创建占位行"),
    })

    T.CreateLabel(frame, { text = Text("PERSONNEL_ROW_EDITOR_SPEC_ICON", "专精图标"), point = { "TOPLEFT", frame, "TOPLEFT", 24, -146 }, width = 90 })
    frame.iconBack = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.iconBack:SetSize(32, 32)
    frame.iconBack:SetPoint("TOPLEFT", frame, "TOPLEFT", 120, -140)
    T.ApplyBackdrop(frame.iconBack, { alpha = 0.35, style = "tooltip" })
    frame.icon = frame.iconBack:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", frame.iconBack, "TOPLEFT", 3, -3)
    frame.icon:SetPoint("BOTTOMRIGHT", frame.iconBack, "BOTTOMRIGHT", -3, 3)
    frame.icon:SetTexture(DEFAULT_ICON)

    frame.specSelector = T.CreateSelectorButton(frame, {
        width = 218,
        height = 26,
        point = { "TOPLEFT", frame, "TOPLEFT", 162, -143 },
        label = "",
        labelWidth = 0,
        items = BuildSpecItems(),
        ownerFrame = frame,
    })

    frame.hint = T.CreateFontString(frame, {
        template = "GameFontDisableSmall",
        point = { "TOPLEFT", frame, "TOPLEFT", 24, -184 },
        width = WIDTH - 48,
        size = 12,
        color = { 0.72, 0.72, 0.72, 1 },
        text = "",
    })
    if frame.hint.SetWordWrap then
        frame.hint:SetWordWrap(true)
    end

    frame.preview = T.CreateFontString(frame, {
        template = "GameFontHighlightSmall",
        point = { "TOPLEFT", frame, "TOPLEFT", 24, -222 },
        width = WIDTH - 48,
        size = 12,
        color = { 0.90, 0.90, 0.90, 1 },
        text = "",
    })

    frame.save = T.CreateButton(frame, { width = 82, height = 26, point = { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -110, 18 } })
    frame.save:SetText(Text("PERSONNEL_ROW_EDITOR_SAVE", "保存"))
    frame.cancel = T.CreateButton(frame, { width = 82, height = 26, point = { "LEFT", frame.save, "RIGHT", 8, 0 } })
    frame.cancel:SetText(Text("PERSONNEL_ROW_EDITOR_CANCEL", "取消"))
    frame.cancel:SetScript("OnClick", function()
        Editor.Close()
    end)
    frame.save:SetScript("OnClick", function()
        Editor:Save()
    end)

    local function changed()
        Editor:Refresh()
    end
    frame.rowName:HookScript("OnTextChanged", changed)
    frame.mappingEdit:HookScript("OnTextChanged", changed)
    frame.mappingEnabled:HookScript("OnClick", changed)
    frame.specSelector.onSelect = changed

    self.frame = frame
    return frame
end

function Editor:GetDefaultHint(rowName)
    local hint = T.ResolveSlotVisualHint and T.ResolveSlotVisualHint(rowName) or nil
    if hint and tonumber(hint.specID) then
        return hint
    end
    return nil
end

function Editor:Refresh()
    local frame = self.frame
    if not frame then
        return
    end
    local rowName = Trim(frame.rowName:GetText())
    local mappingEnabled = frame.mappingEnabled:GetChecked()
    SetEditEnabled(frame.mappingEdit, mappingEnabled)

    local defaultHint = self:GetDefaultHint(rowName)
    local selectedValue = frame.specSelector:GetSelectedValue()
    if defaultHint then
        local specID = tostring(defaultHint.specID)
        frame.specSelector:SetSelectedValue(specID)
        SetSelectorEnabled(frame.specSelector, false)
        local info = ResolveSpecInfo(defaultHint.specID)
        frame.icon:SetTexture((info and info.icon) or DEFAULT_ICON)
        frame.hint:SetText(Text("PERSONNEL_ROW_EDITOR_LOCKED_HINT", "行名已匹配默认专精黑话，图标锁定为默认专精。"))
    else
        SetSelectorEnabled(frame.specSelector, true)
        if selectedValue == nil or selectedValue == "" then
            frame.specSelector:SetSelectedValue(NONE_SPEC)
            selectedValue = NONE_SPEC
        end
        local specInfo = selectedValue ~= NONE_SPEC and ResolveSpecInfo(selectedValue) or nil
        frame.icon:SetTexture((specInfo and specInfo.icon) or DEFAULT_ICON)
        frame.hint:SetText(Text("PERSONNEL_ROW_EDITOR_CUSTOM_HINT", "未匹配默认专精黑话时，可以手选专精图标；它只影响水平视图显示。"))
    end

    local mapping = mappingEnabled and Trim(frame.mappingEdit:GetText()) or ""
    local iconLine = ""
    if not defaultHint and selectedValue and selectedValue ~= NONE_SPEC then
        iconLine = "\n[人员图标]\n" .. rowName .. "=" .. tostring(selectedValue)
    end
    local rowLine = mapping ~= "" and (rowName .. "=" .. mapping) or rowName
    frame.preview:SetText(rowName ~= "" and ("[人员]\n" .. rowLine .. iconLine) or "")
end

function Editor:Save()
    local frame = self.frame
    if not frame then
        return
    end
    local rowName = Trim(frame.rowName:GetText())
    local ok, reason = ValidateName(rowName)
    if not ok then
        Msg(Text(reason == "empty" and "PERSONNEL_ROW_EDITOR_ERR_EMPTY_ROW" or "PERSONNEL_ROW_EDITOR_ERR_INVALID_ROW", reason == "empty" and "行名称不能为空" or "行名称不能包含 =、括号或换行"))
        return
    end
    local mapping = frame.mappingEnabled:GetChecked() and Trim(frame.mappingEdit:GetText()) or ""
    if mapping ~= "" then
        ok, reason = ValidateName(mapping)
        if not ok then
            Msg(Text(reason == "empty" and "PERSONNEL_ROW_EDITOR_ERR_EMPTY_MAPPING" or "PERSONNEL_ROW_EDITOR_ERR_INVALID_MAPPING", reason == "empty" and "人员映射不能为空" or "人员映射不能包含 =、括号或换行"))
            return
        end
    end
    local specValue = frame.specSelector:GetSelectedValue()
    local defaultHint = self:GetDefaultHint(rowName)
    local specID = (not defaultHint and specValue ~= NONE_SPEC) and tonumber(specValue) or nil
    local saved, saveReason = T.SemanticTimelineGUI and T.SemanticTimelineGUI.UpsertPersonnelRow and T.SemanticTimelineGUI.UpsertPersonnelRow({
        oldRowName = self.originalRowName,
        allowCreateIfMissing = self.allowCreateIfMissing == true,
        rowName = rowName,
        mappingName = mapping,
        specID = specID,
    })
    if saved then
        Editor.Close()
        return
    end
    local messages = {
        empty_row_name = Text("PERSONNEL_ROW_EDITOR_ERR_EMPTY_ROW", "行名称不能为空"),
        invalid_row_name = Text("PERSONNEL_ROW_EDITOR_ERR_INVALID_ROW", "行名称不能包含 =、括号或换行"),
        invalid_mapping_name = Text("PERSONNEL_ROW_EDITOR_ERR_INVALID_MAPPING", "人员映射不能包含 =、括号或换行"),
        duplicate_row_name = Text("PERSONNEL_ROW_EDITOR_ERR_DUPLICATE", "人员行已存在，未覆盖原有映射"),
        personnel_row_not_found = Text("PERSONNEL_ROW_EDITOR_ERR_NOT_FOUND", "人员行不存在，无法编辑"),
        editor_not_ready = Text("PERSONNEL_ROW_EDITOR_ERR_NOT_READY", "战术方案编辑器未就绪"),
    }
    Msg(messages[saveReason] or string.format(Text("PERSONNEL_ROW_EDITOR_ERR_FAILED", "新增人员行失败：%s"), tostring(saveReason or "unknown")))
end

function Editor:LoadExistingRow(rowName)
    if not (T.SemanticTimelineGUI and T.SemanticTimelineGUI.GetPersonnelRow) then
        return nil
    end
    return T.SemanticTimelineGUI.GetPersonnelRow(rowName)
end

function Editor.Open(ctx)
    ctx = type(ctx) == "table" and ctx or {}
    local frame = Editor:EnsureFrame()
    local existing = ctx.mode == "edit" and Editor:LoadExistingRow(ctx.rowName) or nil
    if not existing and ctx.mode == "edit" and ctx.allowCreateFromTarget and Trim(ctx.rowName) ~= "" then
        existing = {
            rowName = Trim(ctx.rowName),
            mappingName = "",
            specID = tonumber(ctx.specID),
            createFromTarget = true,
        }
    end
    Editor.originalRowName = existing and existing.rowName or nil
    Editor.allowCreateIfMissing = existing and existing.createFromTarget == true or false
    frame.title:SetText(existing and Text("PERSONNEL_ROW_EDITOR_EDIT_TITLE", "编辑人员行") or Text("PERSONNEL_ROW_EDITOR_TITLE", "新增人员行"))
    frame.rowName:SetText(existing and existing.rowName or "")
    SetEditEnabled(frame.rowName, true)
    local mapping = existing and Trim(existing.mappingName) or ""
    local useMapping = existing and mapping ~= "" and mapping ~= existing.rowName
    frame.mappingEnabled:SetChecked(useMapping == true)
    frame.mappingEdit:SetText(useMapping and mapping or "")
    frame.specSelector:SetItems(BuildSpecItems())
    frame.specSelector:SetSelectedValue(existing and existing.specID and tostring(existing.specID) or NONE_SPEC)
    Editor:Refresh()
    frame:Show()
    frame.rowName:SetFocus()
end

function Editor.Close()
    if Editor.frame then
        Editor.frame:Hide()
    end
end

end)
