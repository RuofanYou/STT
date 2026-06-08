local T, C, L = unpack(select(2, ...))

local selector

local function Tr(key, fallback)
    return L[key] or fallback or key
end

local function GetClassColorString(classFile)
    if classFile and classFile ~= "" and GetClassColor then
        local colorString = select(4, GetClassColor(classFile))
        if colorString and colorString ~= "" then
            return colorString
        end
    end
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color and color.colorStr then
        return color.colorStr
    end
    return "ffffffff"
end

local function ColorProfileName(name, classFile)
    return "|c" .. GetClassColorString(classFile) .. tostring(name or Tr("CONFIG_PROFILE_DEFAULT_NAME", "默认配置")) .. "|r"
end

local function BuildProfileItems()
    local items = {}
    local list = {}
    local activeID
    local defaultID
    if T.Profile then
        list = T.Profile:GetList()
        activeID = T.Profile:GetActiveProfileID()
        defaultID = T.Profile:GetDefaultProfileID()
        for _, profile in ipairs(list) do
            local profileID = profile.id
            local isActive = profileID == activeID
            local label = ColorProfileName(profile.name, profile.ownerClass)
            if profileID == defaultID then
                label = label .. "  " .. Tr("CONFIG_PROFILE_BADGE_DEFAULT", "★默认")
            end
            items[#items + 1] = {
                text = label,
                radio = true,
                radioChecked = isActive,
                onClick = function()
                    if not isActive then
                        T.Profile:SetActive(profileID)
                    end
                    if T.RefreshProfileSelector then
                        T.RefreshProfileSelector()
                    end
                end,
            }
        end
    end

    local isCurrentDefault = activeID and activeID == defaultID
    items[#items + 1] = { isDivider = true, text = "" }
    items[#items + 1] = {
        text = Tr("CONFIG_PROFILE_MENU_NEW", "+ 新建配置..."),
        onClick = function()
            if T.ShowProfileNewDialog then
                T.ShowProfileNewDialog()
            end
        end,
    }
    if #list > 1 then
        items[#items + 1] = {
            text = Tr("CONFIG_PROFILE_MENU_COPY_FROM", "从其它配置复制内容..."),
            onClick = function()
                if T.ShowProfileCopyContentDialog then
                    T.ShowProfileCopyContentDialog()
                end
            end,
        }
    end
    items[#items + 1] = {
        text = Tr("CONFIG_PROFILE_MENU_EDIT", "编辑当前配置..."),
        disabled = not (T.Profile and T.Profile:GetActiveProfileID()),
        onClick = function()
            if T.ShowProfileEditDialog and T.Profile then
                T.ShowProfileEditDialog(T.Profile:GetActiveProfileID())
            end
        end,
    }
    items[#items + 1] = {
        text = isCurrentDefault
            and Tr("CONFIG_PROFILE_MENU_UNSET_DEFAULT", "✓ 已设为新角色默认（点击取消）")
            or Tr("CONFIG_PROFILE_MENU_SET_DEFAULT", "★ 设为新角色默认（账号共享）"),
        disabled = not activeID,
        onClick = function()
            if T.Profile then
                if isCurrentDefault then
                    T.Profile:SetDefaultProfileID(nil)
                else
                    T.Profile:SetDefaultProfileID(activeID)
                end
            end
            if T.RefreshProfileSelector then
                T.RefreshProfileSelector()
            end
        end,
    }
    return items
end

local function GetActiveProfileText()
    local profile = T.Profile and T.Profile:GetActive()
    local meta = profile and profile._meta or {}
    return ColorProfileName(meta.name, meta.ownerClass)
end

function T.RefreshProfileSelector()
    if not selector then
        return
    end
    local activeID = T.Profile and T.Profile:GetActiveProfileID() or nil
    selector:SetSelectedValue(activeID, GetActiveProfileText())
    selector:SetValueText(GetActiveProfileText())
end

function T.CreateProfileSelector(parent, ownerFrame)
    selector = T.CreateSelectorButton(parent, {
        width = 240,
        height = 26,
        labelWidth = 42,
        ownerFrame = ownerFrame,
        menuBuilder = BuildProfileItems,
    })
    selector:SetLabel(Tr("CONFIG_PROFILE_LABEL", "配置"))
    T.RefreshProfileSelector()
    if T.events then
        T.events:Register("STT_PROFILE_CHANGED", selector, function()
            T.RefreshProfileSelector()
        end)
        T.events:Register("STT_PROFILE_CREATED", selector, function()
            T.RefreshProfileSelector()
        end)
        T.events:Register("STT_PROFILE_DELETED", selector, function()
            T.RefreshProfileSelector()
        end)
        T.events:Register("STT_PROFILE_RENAMED", selector, function()
            T.RefreshProfileSelector()
        end)
        T.events:Register("STT_PROFILE_CONTENT_COPIED", selector, function()
            T.RefreshProfileSelector()
        end)
        T.events:Register("STT_PROFILE_DEFAULT_CHANGED", selector, function()
            T.RefreshProfileSelector()
        end)
    end
    return selector
end
