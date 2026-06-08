local T, C, L = unpack(select(2, ...))

local editDialog
local newDialog
local copyDialog
local editingProfileID
local pendingDeleteID
local pendingDeleteToken = 0

local function Tr(key, fallback)
    return L[key] or fallback or key
end

local function RefreshProfileUI()
    if T.RefreshProfileSelector then
        T.RefreshProfileSelector()
    end
    if T.SemanticTimelineGUI and T.SemanticTimelineGUI.RefreshData then
        T.SemanticTimelineGUI.RefreshData("profile_dialog")
    end
end

local function GetProfileName(profileID)
    local profile = T.Profile and T.Profile:Get(profileID) or nil
    local meta = profile and profile._meta or {}
    return meta.name or Tr("CONFIG_PROFILE_DEFAULT_NAME", "默认配置")
end

local function BuildSourceItems(excludeID, onSelect)
    local items = {}
    local list = T.Profile and T.Profile:GetList() or {}
    for _, profile in ipairs(list) do
        if tonumber(profile.id) ~= tonumber(excludeID) then
            local profileID = profile.id
            items[#items + 1] = {
                value = profileID,
                text = profile.name or Tr("CONFIG_PROFILE_DEFAULT_NAME", "默认配置"),
                onClick = function(item)
                    if onSelect then
                        onSelect(item.value, item.text)
                    end
                end,
            }
        end
    end
    return items
end

local function FirstSourceID(excludeID)
    local items = BuildSourceItems(excludeID)
    return items[1] and items[1].value or nil
end

local function SetRadio(dialog, mode)
    dialog.initialMode = mode
    dialog.currentCheck:SetChecked(mode == "current")
    dialog.blankCheck:SetChecked(mode == "blank")
    dialog.otherCheck:SetChecked(mode == "other")
    dialog.sourceSelector:SetSelectorEnabled(mode == "other" and dialog.selectedSourceID ~= nil)
end

local function EnsureEditDialog()
    if editDialog then
        return editDialog
    end

    editDialog = T.CreatePopupWindow(UIParent, {
        name = "STT_ProfileEditDialog",
        title = Tr("CONFIG_PROFILE_EDIT_TITLE", "配置设定"),
        width = 360,
        height = 170,
    })

    editDialog.nameLabel = T.CreateLabel(editDialog, {
        text = Tr("CONFIG_PROFILE_NAME_LABEL", "名字"),
        point = { "TOPLEFT", editDialog, "TOPLEFT", 24, -42 },
        color = { 1, 0.82, 0, 1 },
    })
    editDialog.nameEdit = T.CreateEditBox(editDialog, {
        width = 300,
        height = 28,
        point = { "TOPLEFT", editDialog, "TOPLEFT", 24, -64 },
        autoFocus = true,
    })

    editDialog.acceptButton = T.CreateButton(editDialog, { width = 82, height = 24 })
    editDialog.acceptButton:SetPoint("BOTTOMLEFT", editDialog, "BOTTOMLEFT", 24, 18)
    editDialog.acceptButton:SetText(Tr("CONFIG_PROFILE_BTN_ACCEPT", "接受"))

    editDialog.deleteButton = T.CreateButton(editDialog, { width = 140, height = 24 })
    editDialog.deleteButton:SetPoint("LEFT", editDialog.acceptButton, "RIGHT", 12, 0)
    editDialog.deleteButton:SetText(Tr("CONFIG_PROFILE_BTN_DELETE", "删除"))

    editDialog.cancelButton = T.CreateButton(editDialog, { width = 82, height = 24 })
    editDialog.cancelButton:SetPoint("LEFT", editDialog.deleteButton, "RIGHT", 12, 0)
    editDialog.cancelButton:SetText(Tr("CONFIG_PROFILE_BTN_CANCEL", "取消"))
    editDialog.cancelButton:SetScript("OnClick", function()
        editDialog:Hide()
    end)

    editDialog.acceptButton:SetScript("OnClick", function()
        if not (editingProfileID and T.Profile) then
            return
        end
        T.Profile:Rename(editingProfileID, editDialog.nameEdit:GetText())
        editDialog:Hide()
        RefreshProfileUI()
    end)

    editDialog.deleteButton:SetScript("OnClick", function()
        if not (editingProfileID and T.Profile) then
            return
        end
        if pendingDeleteID ~= editingProfileID then
            pendingDeleteID = editingProfileID
            pendingDeleteToken = pendingDeleteToken + 1
            local token = pendingDeleteToken
            editDialog.deleteButton:SetText(Tr("CONFIG_PROFILE_BTN_DELETE_CONFIRM", "确认删除？再点一次"))
            if C_Timer and C_Timer.After then
                C_Timer.After(5, function()
                    if pendingDeleteToken == token then
                        pendingDeleteID = nil
                        if editDialog and editDialog:IsShown() then
                            editDialog.deleteButton:SetText(Tr("CONFIG_PROFILE_BTN_DELETE", "删除"))
                        end
                    end
                end)
            end
            return
        end
        local ok, err = pcall(T.Profile.Delete, T.Profile, editingProfileID)
        if not ok then
            T.msg(tostring(err))
            return
        end
        pendingDeleteID = nil
        editDialog:Hide()
        RefreshProfileUI()
    end)

    return editDialog
end

local function EnsureNewDialog()
    if newDialog then
        return newDialog
    end

    newDialog = T.CreatePopupWindow(UIParent, {
        name = "STT_ProfileNewDialog",
        title = Tr("CONFIG_PROFILE_NEW_TITLE", "新建配置"),
        width = 390,
        height = 245,
    })

    newDialog.nameLabel = T.CreateLabel(newDialog, {
        text = Tr("CONFIG_PROFILE_NAME_LABEL", "名字"),
        point = { "TOPLEFT", newDialog, "TOPLEFT", 24, -42 },
        color = { 1, 0.82, 0, 1 },
    })
    newDialog.nameEdit = T.CreateEditBox(newDialog, {
        width = 320,
        height = 28,
        point = { "TOPLEFT", newDialog, "TOPLEFT", 24, -64 },
        autoFocus = true,
    })
    newDialog.initialLabel = T.CreateLabel(newDialog, {
        text = Tr("CONFIG_PROFILE_NEW_INITIAL_LABEL", "初始内容："),
        point = { "TOPLEFT", newDialog, "TOPLEFT", 24, -104 },
        color = { 1, 0.82, 0, 1 },
    })
    newDialog.currentCheck = T.CreateCheckbox(newDialog, {
        label = Tr("CONFIG_PROFILE_NEW_INITIAL_CURRENT", "复制当前配置（推荐）"),
        point = { "TOPLEFT", newDialog, "TOPLEFT", 24, -126 },
    })
    newDialog.blankCheck = T.CreateCheckbox(newDialog, {
        label = Tr("CONFIG_PROFILE_NEW_INITIAL_BLANK", "空白"),
        point = { "TOPLEFT", newDialog, "TOPLEFT", 24, -150 },
    })
    newDialog.otherCheck = T.CreateCheckbox(newDialog, {
        label = Tr("CONFIG_PROFILE_NEW_INITIAL_OTHER", "复制其它："),
        point = { "TOPLEFT", newDialog, "TOPLEFT", 24, -174 },
    })
    newDialog.sourceSelector = T.CreateSelectorButton(newDialog, {
        width = 180,
        height = 20,
        labelWidth = 0,
        ownerFrame = newDialog,
        menuBuilder = function()
            return BuildSourceItems(T.Profile and T.Profile:GetActiveProfileID(), function(value, text)
                newDialog.selectedSourceID = value
                newDialog.sourceSelector:SetSelectedValue(value, text)
            end)
        end,
    })
    newDialog.sourceSelector:SetPoint("LEFT", newDialog.otherCheck.label, "RIGHT", 8, 0)
    newDialog.sourceSelector:SetLabel("")

    newDialog.currentCheck:SetScript("OnClick", function() SetRadio(newDialog, "current") end)
    newDialog.blankCheck:SetScript("OnClick", function() SetRadio(newDialog, "blank") end)
    newDialog.otherCheck:SetScript("OnClick", function() SetRadio(newDialog, "other") end)

    newDialog.acceptButton = T.CreateButton(newDialog, { width = 82, height = 24 })
    newDialog.acceptButton:SetPoint("BOTTOMLEFT", newDialog, "BOTTOMLEFT", 24, 18)
    newDialog.acceptButton:SetText(Tr("CONFIG_PROFILE_BTN_ACCEPT", "接受"))
    newDialog.cancelButton = T.CreateButton(newDialog, { width = 82, height = 24 })
    newDialog.cancelButton:SetPoint("LEFT", newDialog.acceptButton, "RIGHT", 12, 0)
    newDialog.cancelButton:SetText(Tr("CONFIG_PROFILE_BTN_CANCEL", "取消"))
    newDialog.cancelButton:SetScript("OnClick", function()
        newDialog:Hide()
    end)

    newDialog.acceptButton:SetScript("OnClick", function()
        if not T.Profile then
            return
        end
        local name = tostring(newDialog.nameEdit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            T.msg(Tr("CONFIG_PROFILE_NAME_REQUIRED", "请输入配置名字"))
            return
        end
        local activeID = T.Profile:GetActiveProfileID()
        local newID = T.Profile:Create(name)
        if newDialog.initialMode == "current" and activeID then
            T.Profile:CopyContentTo(activeID, newID)
        elseif newDialog.initialMode == "other" and newDialog.selectedSourceID then
            T.Profile:CopyContentTo(newDialog.selectedSourceID, newID)
        end
        T.Profile:SetActive(newID)
        T.msg((Tr("CONFIG_PROFILE_NEW_CREATED", "已新建配置「%s」并切换")):format(name))
        newDialog:Hide()
        RefreshProfileUI()
    end)

    return newDialog
end

local function EnsureCopyDialog()
    if copyDialog then
        return copyDialog
    end

    copyDialog = T.CreatePopupWindow(UIParent, {
        name = "STT_ProfileCopyContentDialog",
        title = Tr("CONFIG_PROFILE_COPY_TITLE", "从其它配置复制内容"),
        width = 390,
        height = 190,
    })

    copyDialog.srcLabel = T.CreateLabel(copyDialog, {
        text = Tr("CONFIG_PROFILE_COPY_SRC_LABEL", "复制源："),
        point = { "TOPLEFT", copyDialog, "TOPLEFT", 24, -48 },
        color = { 1, 0.82, 0, 1 },
    })
    copyDialog.sourceSelector = T.CreateSelectorButton(copyDialog, {
        width = 245,
        height = 22,
        labelWidth = 0,
        ownerFrame = copyDialog,
        menuBuilder = function()
            return BuildSourceItems(T.Profile and T.Profile:GetActiveProfileID(), function(value, text)
                copyDialog.selectedSourceID = value
                copyDialog.sourceSelector:SetSelectedValue(value, text)
                copyDialog.warning:SetText((Tr("CONFIG_PROFILE_COPY_WARN", "当前配置「%s」的全部内容会被覆盖，不可恢复")):format(GetProfileName(T.Profile:GetActiveProfileID())))
            end)
        end,
    })
    copyDialog.sourceSelector:SetPoint("LEFT", copyDialog.srcLabel, "RIGHT", 8, 0)
    copyDialog.sourceSelector:SetLabel("")
    copyDialog.warning = T.CreateLabel(copyDialog, {
        text = "",
        point = { "TOPLEFT", copyDialog, "TOPLEFT", 24, -88 },
        width = 330,
        color = { 1, 0.55, 0.2, 1 },
        wordWrap = true,
    })

    copyDialog.acceptButton = T.CreateButton(copyDialog, { width = 82, height = 24 })
    copyDialog.acceptButton:SetPoint("BOTTOMLEFT", copyDialog, "BOTTOMLEFT", 24, 18)
    copyDialog.acceptButton:SetText(Tr("CONFIG_PROFILE_BTN_ACCEPT", "接受"))
    copyDialog.cancelButton = T.CreateButton(copyDialog, { width = 82, height = 24 })
    copyDialog.cancelButton:SetPoint("LEFT", copyDialog.acceptButton, "RIGHT", 12, 0)
    copyDialog.cancelButton:SetText(Tr("CONFIG_PROFILE_BTN_CANCEL", "取消"))
    copyDialog.cancelButton:SetScript("OnClick", function()
        copyDialog:Hide()
    end)

    copyDialog.acceptButton:SetScript("OnClick", function()
        if not (T.Profile and copyDialog.selectedSourceID) then
            return
        end
        local activeID = T.Profile:GetActiveProfileID()
        StaticPopup_Show("STT_PROFILE_OVERWRITE_CONFIRM", GetProfileName(copyDialog.selectedSourceID), GetProfileName(activeID), {
            srcID = copyDialog.selectedSourceID,
            dstID = activeID,
            srcName = GetProfileName(copyDialog.selectedSourceID),
            dstName = GetProfileName(activeID),
        })
    end)

    return copyDialog
end

StaticPopupDialogs["STT_PROFILE_OVERWRITE_CONFIRM"] = {
    text = Tr("CONFIG_PROFILE_OVERWRITE_CONFIRM", "即将把「%s」的所有方案覆盖到「%s」上，原内容会丢失。\n\n确认?"),
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, data)
        if not (data and T.Profile) then
            return
        end
        T.Profile:CopyContentTo(data.srcID, data.dstID)
        T.msg((Tr("CONFIG_PROFILE_OVERWRITTEN", "已将「%s」的内容复制到「%s」")):format(data.srcName, data.dstName))
        if copyDialog then
            copyDialog:Hide()
        end
        RefreshProfileUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function T.ShowProfileEditDialog(profileID)
    local frame = EnsureEditDialog()
    editingProfileID = tonumber(profileID)
    pendingDeleteID = nil
    local profile = editingProfileID and T.Profile and T.Profile:Get(editingProfileID) or nil
    local meta = profile and profile._meta or {}

    frame.title:SetText(Tr("CONFIG_PROFILE_EDIT_TITLE", "配置设定"))
    frame.nameEdit:SetText(meta.name or Tr("CONFIG_PROFILE_DEFAULT_NAME", "默认配置"))
    frame.nameEdit:HighlightText()
    frame.deleteButton:SetText(Tr("CONFIG_PROFILE_BTN_DELETE", "删除"))
    frame.deleteButton:SetEnabled(editingProfileID ~= nil)
    frame:Show()
    frame.nameEdit:SetFocus()
end

function T.ShowProfileNewDialog()
    local frame = EnsureNewDialog()
    local activeName = GetProfileName(T.Profile and T.Profile:GetActiveProfileID())
    frame.nameEdit:SetText(activeName)
    frame.nameEdit:HighlightText()
    frame.selectedSourceID = FirstSourceID(T.Profile and T.Profile:GetActiveProfileID())
    frame.sourceSelector:SetSelectedValue(frame.selectedSourceID, frame.selectedSourceID and GetProfileName(frame.selectedSourceID) or "-")
    SetRadio(frame, "current")
    frame:Show()
    frame.nameEdit:SetFocus()
end

function T.ShowProfileCopyContentDialog()
    local frame = EnsureCopyDialog()
    local activeID = T.Profile and T.Profile:GetActiveProfileID()
    frame.selectedSourceID = FirstSourceID(activeID)
    frame.sourceSelector:SetSelectedValue(frame.selectedSourceID, frame.selectedSourceID and GetProfileName(frame.selectedSourceID) or "-")
    frame.acceptButton:SetEnabled(frame.selectedSourceID ~= nil)
    frame.warning:SetText((Tr("CONFIG_PROFILE_COPY_WARN", "当前配置「%s」的全部内容会被覆盖，不可恢复")):format(GetProfileName(activeID)))
    frame:Show()
end

T.UI = T.UI or {}
T.UI.ShowProfileNewDialog = function()
    T.ShowProfileNewDialog()
end
T.UI.ShowProfileCopyContentDialog = function()
    T.ShowProfileCopyContentDialog()
end
T.UI.ShowProfileEditDialog = function(_, profileID)
    T.ShowProfileEditDialog(profileID)
end
