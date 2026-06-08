local T, C, L = unpack(select(2, ...))

local CATEGORY_ID = "ShengTangTools"
local category

local function OpenSTTSettings()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
    if T.OpenSettingsModule then
        T.OpenSettingsModule("system")
    elseif T.ToggleGUI then
        T.ToggleGUI()
    end
end

function T.RegisterBlizzardOptionsPanel()
    if category then
        return true
    end
    if C and C.DB and C.DB.system and C.DB.system.showInBlizzardOptions == false then
        return false
    end
    if not (Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function") then
        if T.debug then
            T.debug("[BlizzardOptions] Settings API unavailable")
        end
        return false
    end

    local panel = CreateFrame("Frame", "STTBlizzardOptionsPanel")
    panel.name = "STT"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(T.addon_cname or "STT")

    local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    intro:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(L["STT_BLIZZ_OPTIONS_INTRO"] or "STT uses its own settings window. Click the button below or type /st to open it.")

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(220, 28)
    button:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)
    button:SetText(L["STT_BLIZZ_OPTIONS_OPEN"] or "Open STT Settings")
    button:SetScript("OnClick", OpenSTTSettings)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -16)
    hint:SetText(L["STT_BLIZZ_OPTIONS_HINT"] or "You can also use /st.")

    category = Settings.RegisterCanvasLayoutCategory(panel, "STT")
    category.ID = CATEGORY_ID
    Settings.RegisterAddOnCategory(category)
    T.BlizzardOptionsCategoryID = category:GetID()
    return true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    T.RegisterBlizzardOptionsPanel()
end)
