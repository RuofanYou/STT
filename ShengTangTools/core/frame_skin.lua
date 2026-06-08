local T, C, L = unpack(select(2, ...))

local DEFAULT_SKIN_ID = "kyrian"

local PIECE_NAMES = {
    "TopLeftCorner",
    "TopRightCorner",
    "BottomLeftCorner",
    "BottomRightCorner",
    "TopEdge",
    "BottomEdge",
    "LeftEdge",
    "RightEdge",
    "Center",
}

local PIECE_KEYS = {
    TopLeftCorner = "cornerTopLeft",
    TopRightCorner = "cornerTopRight",
    BottomLeftCorner = "cornerBottomLeft",
    BottomRightCorner = "cornerBottomRight",
    TopEdge = "edgeTop",
    BottomEdge = "edgeBottom",
    LeftEdge = "edgeLeft",
    RightEdge = "edgeRight",
    Center = "center",
}

local PRESET_ORDER = {
    "kyrian",
    "venthyr",
    "necrolord",
    "nightfae",
}

local PRESETS = {
    kyrian = {
        id = "kyrian",
        displayName = "FRAMESKIN_NAME_KYRIAN",
        layoutMode = "unique",
        pieces = {
            cornerTopLeft = "Kyrian-NineSlice-CornerTopLeft",
            cornerTopRight = "Kyrian-NineSlice-CornerTopRight",
            cornerBottomLeft = "Kyrian-NineSlice-CornerBottomLeft",
            cornerBottomRight = "Kyrian-NineSlice-CornerBottomRight",
            edgeTop = "_Kyrian-NineSlice-EdgeTop",
            edgeBottom = "_Kyrian-NineSlice-EdgeBottom",
            edgeLeft = nil,
            edgeRight = nil,
            center = "Kyrian-NineSlice-Center",
        },
        titleBarAtlas = "CovenantSanctum-Level-Border-Kyrian",
        colors = {
            title = { 0.9, 0.85, 0.7, 1 },
            leftPanelBorder = { 0.45, 0.4, 0.22, 0.75 },
            backdrop = { 0, 0, 0, 0.85 },
        },
        availability = "verified",
    },
    venthyr = {
        id = "venthyr",
        displayName = "FRAMESKIN_NAME_VENTHYR",
        layoutMode = "unique",
        pieces = {
            cornerTopLeft = "Venthyr-NineSlice-CornerTopLeft",
            cornerTopRight = "Venthyr-NineSlice-CornerTopRight",
            cornerBottomLeft = "Venthyr-NineSlice-CornerBottomLeft",
            cornerBottomRight = "Venthyr-NineSlice-CornerBottomRight",
            edgeTop = "_Venthyr-NineSlice-EdgeTop",
            edgeBottom = "_Venthyr-NineSlice-EdgeBottom",
            edgeLeft = "!Venthyr-NineSlice-EdgeLeft",
            edgeRight = "!Venthyr-NineSlice-EdgeRight",
            center = "Venthyr-NineSlice-Center",
        },
        titleBarAtlas = "CovenantSanctum-Level-Border-Venthyr",
        colors = {
            title = { 0.95, 0.5, 0.45, 1 },
            leftPanelBorder = { 0.5, 0.2, 0.2, 0.75 },
            backdrop = { 0.15, 0.05, 0.08, 0.85 },
        },
        availability = "verified",
    },
    necrolord = {
        id = "necrolord",
        displayName = "FRAMESKIN_NAME_NECROLORD",
        layoutMode = "unique",
        pieces = {
            cornerTopLeft = "necrolord-nineslice-cornertopleft",
            cornerTopRight = "necrolord-nineslice-cornertopright",
            cornerBottomLeft = "necrolord-nineslice-cornerbottomleft",
            cornerBottomRight = "necrolord-nineslice-cornerbottomright",
            edgeTop = "_necrolord-nineslice-edgetop",
            edgeBottom = "_necrolord-nineslice-edgebottom",
            edgeLeft = "!Necrolord-NineSlice-EdgeLeft",
            edgeRight = "!Necrolord-NineSlice-EdgeRight",
            center = "Necrolord-NineSlice-Center",
        },
        titleBarAtlas = "covenantsanctum-level-border-necrolord",
        colors = {
            title = { 0.6, 0.85, 0.55, 1 },
            leftPanelBorder = { 0.3, 0.45, 0.25, 0.75 },
            backdrop = { 0.08, 0.12, 0.07, 0.85 },
        },
        availability = "verified",
    },
    nightfae = {
        id = "nightfae",
        displayName = "FRAMESKIN_NAME_NIGHTFAE",
        layoutMode = "unique",
        pieces = {
            cornerTopLeft = "NightFae-NineSlice-CornerTopLeft",
            cornerTopRight = "NightFae-NineSlice-CornerTopRight",
            cornerBottomLeft = "NightFae-NineSlice-CornerBottomLeft",
            cornerBottomRight = "NightFae-NineSlice-CornerBottomRight",
            edgeTop = "_NightFae-NineSlice-EdgeTop",
            edgeBottom = "_NightFae-NineSlice-EdgeBottom",
            edgeLeft = "!NightFae-NineSlice-EdgeLeft",
            edgeRight = "!NightFae-NineSlice-EdgeRight",
            center = "NightFae-NineSlice-Center",
        },
        titleBarAtlas = "covenantsanctum-level-border-nightfae",
        colors = {
            title = { 0.7, 0.9, 0.95, 1 },
            leftPanelBorder = { 0.35, 0.4, 0.6, 0.75 },
            backdrop = { 0.08, 0.06, 0.15, 0.85 },
        },
        availability = "verified",
    },
}

local KYRIAN_LEGACY = {
    background = "UI-Frame-Kyrian-BackgroundTile",
    titleBar = "CovenantSanctum-Level-Border-Kyrian",
    pieces = {
        cornerTopLeft = "Kyrian-NineSlice-CornerTopLeft",
        cornerTopRight = "Kyrian-NineSlice-CornerTopRight",
        cornerBottomLeft = "Kyrian-NineSlice-CornerBottomLeft",
        cornerBottomRight = "Kyrian-NineSlice-CornerBottomRight",
        edgeTop = "_Kyrian-NineSlice-EdgeTop",
        edgeBottom = "_Kyrian-NineSlice-EdgeBottom",
        edgeLeft = "!Kyrian-NineSlice-EdgeLeft",
        edgeRight = "!Kyrian-NineSlice-EdgeRight",
    },
}

local FrameSkin = {
    PRESETS = PRESETS,
    PRESET_ORDER = PRESET_ORDER,
    _registry = setmetatable({}, { __mode = "k" }),
}
T.FrameSkin = FrameSkin

local function ResolveText(textKey, fallback)
    if textKey and L[textKey] then
        return L[textKey]
    end
    return fallback or textKey or ""
end

local function ColorWithAlpha(color, alphaMul)
    color = type(color) == "table" and color or { 0, 0, 0, 0.85 }
    alphaMul = tonumber(alphaMul) or 1
    return {
        color[1] or 0,
        color[2] or 0,
        color[3] or 0,
        (color[4] == nil and 1 or color[4]) * alphaMul,
    }
end

local function BuildPiece(pieceName, atlas, skin)
    if not atlas then
        return nil
    end

    local piece = { atlas = atlas }
    if pieceName == "TopLeftCorner" then
        piece.x, piece.y = -12, 12
    elseif pieceName == "TopRightCorner" then
        piece.x, piece.y = 12, 12
    elseif pieceName == "BottomLeftCorner" then
        piece.x, piece.y = -12, -12
    elseif pieceName == "BottomRightCorner" then
        piece.x, piece.y = 12, -12
    end

    if pieceName == "Center" and skin.colors and skin.colors.backdrop then
        piece.vertexColor = skin.colors.backdrop
    end

    return piece
end

local function BuildLayout(skin)
    local layout = {
        mirrorLayout = skin.layoutMode == "identical" or nil,
        setupPieceVisualsFunction = function(_, piece, setupInfo, pieceLayout)
            local left, right, top, bottom = 0, 1, 0, 1
            local pieceMirrored = pieceLayout.mirrorLayout
            if pieceMirrored == nil then
                pieceMirrored = skin.layoutMode == "identical"
            end
            if pieceMirrored then
                if setupInfo.mirrorVertical then
                    top, bottom = bottom, top
                end
                if setupInfo.mirrorHorizontal then
                    left, right = right, left
                end
            end
            piece:SetTexCoord(left, right, top, bottom)

            local atlasName = pieceLayout.atlas
            local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlasName)
            if not info then
                piece._frameSkinAtlasValid = false
                piece:Hide()
                return
            end

            piece:SetHorizTile(info.tilesHorizontally or setupInfo.tileHorizontal or false)
            piece:SetVertTile(info.tilesVertically or setupInfo.tileVertical or false)
            piece:SetAtlas(atlasName, true)
            piece._frameSkinAtlasValid = true
            piece:Show()
        end,
    }
    local pieces = skin.pieces or {}
    for _, pieceName in ipairs(PIECE_NAMES) do
        local atlas = pieces[PIECE_KEYS[pieceName]]
        local piece = BuildPiece(pieceName, atlas, skin)
        if piece then
            layout[pieceName] = piece
        end
    end
    return layout
end

local function SetPieceVisibility(frame, layout)
    for _, pieceName in ipairs(PIECE_NAMES) do
        local piece = frame and frame[pieceName]
        if piece and piece.SetShown then
            piece:SetShown(layout[pieceName] ~= nil and piece._frameSkinAtlasValid ~= false)
        end
        if piece and layout[pieceName] and layout[pieceName].vertexColor and piece.SetVertexColor then
            piece:SetVertexColor(unpack(layout[pieceName].vertexColor))
        elseif piece and layout[pieceName] and piece.SetVertexColor then
            piece:SetVertexColor(1, 1, 1, 1)
        end
    end
end

local function HideNineSlicePieces(frame)
    for _, pieceName in ipairs(PIECE_NAMES) do
        local piece = frame and frame[pieceName]
        if piece and piece.Hide then
            piece:Hide()
        end
    end
end

local function HideLegacyKyrian(frame)
    local legacy = frame and frame._frameSkinLegacyKyrian
    if not legacy then
        return
    end
    for _, texture in pairs(legacy) do
        if texture and texture.Hide then
            texture:Hide()
        end
    end
end

local function ApplyBackground(frame, skin)
    if not frame._frameSkinBackground then
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints(frame)
        frame._frameSkinBackground = bg
    end
    frame._frameSkinBackground:SetColorTexture(unpack(ColorWithAlpha(skin.colors and skin.colors.backdrop, 1)))
    frame._frameSkinBackground:Show()
end

local function HideBackground(frame)
    if frame and frame._frameSkinBackground then
        frame._frameSkinBackground:Hide()
    end
end

local function ApplyTitleBar(frame, skin)
    if not frame._frameSkinTitleBar then
        local titleBar = frame:CreateTexture(nil, "ARTWORK")
        titleBar:SetPoint("TOP", frame, "TOP", 0, 35)
        frame._frameSkinTitleBar = titleBar
    end

    local titleBar = frame._frameSkinTitleBar
    if skin.titleBarAtlas then
        local ok, err = pcall(titleBar.SetAtlas, titleBar, skin.titleBarAtlas, true)
        if ok then
            titleBar:Show()
        else
            titleBar:Hide()
            T.debug("[FrameSkin] titlebar_failed skin=%s atlas=%s err=%s", tostring(skin.id), tostring(skin.titleBarAtlas), tostring(err))
        end
    else
        titleBar:Hide()
    end

    if frame.TitleText and frame.TitleText.SetTextColor and skin.colors and skin.colors.title then
        frame.TitleText:SetTextColor(unpack(skin.colors.title))
    end
end

local function HideTitleBar(frame)
    if frame and frame._frameSkinTitleBar then
        frame._frameSkinTitleBar:Hide()
    end
end

local function HideBaseBackdrop(frame)
    local backdrop = frame and frame._frameSkinBaseBackdrop
    if backdrop and backdrop.Hide then
        backdrop:Hide()
    end
end

local function ApplyBaseBackdrop(frame, role)
    if not T.ApplyBackdrop then
        return
    end
    if role ~= "main" and role ~= "panel" and role ~= "subPanel" then
        return
    end

    local alpha = 0.85
    if role == "subPanel" then
        alpha = 0.35
    elseif role == "panel" then
        alpha = 0.55
    end

    frame._frameSkinBaseBackdrop = T.ApplyBackdrop(frame, {
        style = role == "main" and "tooltip" or "chat",
        alpha = alpha,
        borderColor = { 0.45, 0.4, 0.22, 0.75 },
        offsets = role == "main" and { -8, 8, 8, -8 } or nil,
    })
end

local function ClearSkin(frame)
    HideNineSlicePieces(frame)
    HideLegacyKyrian(frame)
    HideBackground(frame)
    HideTitleBar(frame)
end

local function EnsureLegacyTexture(frame, key, layer)
    frame._frameSkinLegacyKyrian = frame._frameSkinLegacyKyrian or {}
    if not frame._frameSkinLegacyKyrian[key] then
        frame._frameSkinLegacyKyrian[key] = frame:CreateTexture(nil, layer or "BORDER")
    end
    local texture = frame._frameSkinLegacyKyrian[key]
    texture:ClearAllPoints()
    return texture
end

local function ApplyLegacyKyrian(frame)
    HideNineSlicePieces(frame)
    HideBackground(frame)
    HideTitleBar(frame)

    local offset = 12
    local bg = EnsureLegacyTexture(frame, "background", "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetAtlas(KYRIAN_LEGACY.background, true)
    bg:SetAlpha(0.85)
    bg:Show()

    local topLeft = EnsureLegacyTexture(frame, "topLeft", "BORDER")
    topLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    topLeft:SetAtlas(KYRIAN_LEGACY.pieces.cornerTopLeft, true)
    topLeft:Show()

    local topRight = EnsureLegacyTexture(frame, "topRight", "BORDER")
    topRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", offset, offset)
    topRight:SetAtlas(KYRIAN_LEGACY.pieces.cornerTopRight, true)
    topRight:Show()

    local bottomLeft = EnsureLegacyTexture(frame, "bottomLeft", "BORDER")
    bottomLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -offset, -offset)
    bottomLeft:SetAtlas(KYRIAN_LEGACY.pieces.cornerBottomLeft, true)
    bottomLeft:Show()

    local bottomRight = EnsureLegacyTexture(frame, "bottomRight", "BORDER")
    bottomRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    bottomRight:SetAtlas(KYRIAN_LEGACY.pieces.cornerBottomRight, true)
    bottomRight:Show()

    local top = EnsureLegacyTexture(frame, "top", "BORDER")
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT", 0, 0)
    top:SetAtlas(KYRIAN_LEGACY.pieces.edgeTop, true)
    top:Show()

    local bottom = EnsureLegacyTexture(frame, "bottom", "BORDER")
    bottom:SetPoint("BOTTOMLEFT", bottomLeft, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bottomRight, "BOTTOMLEFT", 0, 0)
    bottom:SetAtlas(KYRIAN_LEGACY.pieces.edgeBottom, true)
    bottom:Show()

    local left = EnsureLegacyTexture(frame, "left", "BORDER")
    left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottomLeft, "TOPLEFT", 0, 0)
    left:SetAtlas(KYRIAN_LEGACY.pieces.edgeLeft, true)
    left:Show()

    local right = EnsureLegacyTexture(frame, "right", "BORDER")
    right:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottomRight, "TOPRIGHT", 0, 0)
    right:SetAtlas(KYRIAN_LEGACY.pieces.edgeRight, true)
    right:Show()

    local titleBar = EnsureLegacyTexture(frame, "titleBar", "ARTWORK")
    titleBar:SetPoint("TOP", frame, "TOP", 0, 35)
    titleBar:SetAtlas(KYRIAN_LEGACY.titleBar, true)
    titleBar:Show()

    if frame.TitleText and frame.TitleText.SetTextColor then
        frame.TitleText:SetTextColor(0.9, 0.85, 0.7, 1)
    end
end

local function ApplyNineSlice(frame, skin)
    if not (NineSliceUtil and NineSliceUtil.ApplyLayout) then
        T.debug("[FrameSkin] nineslice_unavailable skin=%s", tostring(skin and skin.id))
        return
    end

    local layout = BuildLayout(skin)
    local ok, err = pcall(NineSliceUtil.ApplyLayout, frame, layout)
    if not ok then
        T.debug("[FrameSkin] ApplyLayout failed skin=%s err=%s", tostring(skin.id), tostring(err))
        return
    end
    SetPieceVisibility(frame, layout)
end

function FrameSkin:NormalizeSavedValue()
    if type(STT_DB) ~= "table" then
        return DEFAULT_SKIN_ID
    end
    if not self.PRESETS[STT_DB.frameSkin] then
        if STT_DB.frameSkin ~= nil then
            T.debug("[FrameSkin] unknown skinId=%s reset=%s", tostring(STT_DB.frameSkin), DEFAULT_SKIN_ID)
        end
        STT_DB.frameSkin = DEFAULT_SKIN_ID
    end
    if type(C.DB) == "table" then
        C.DB.frameSkin = STT_DB.frameSkin
    end
    return STT_DB.frameSkin
end

function FrameSkin:GetActive()
    if type(STT_DB) == "table" and not self.PRESETS[STT_DB.frameSkin] then
        self:NormalizeSavedValue()
    end
    if type(C.DB) == "table" and self.PRESETS[C.DB.frameSkin] then
        return C.DB.frameSkin
    end
    if type(STT_DB) == "table" and self.PRESETS[STT_DB.frameSkin] then
        return STT_DB.frameSkin
    end
    return DEFAULT_SKIN_ID
end

function FrameSkin:GetActivePreset()
    return self.PRESETS[self:GetActive()] or self.PRESETS[DEFAULT_SKIN_ID]
end

function FrameSkin:GetPresetName(skinId)
    local skin = self.PRESETS[skinId or self:GetActive()] or self.PRESETS[DEFAULT_SKIN_ID]
    return ResolveText(skin.displayName, skin.id)
end

function FrameSkin:GetPresetList()
    local list = {}
    local experimentalSuffix = ResolveText("FRAMESKIN_AVAILABILITY_EXPERIMENTAL", " (Experimental)")
    for _, skinId in ipairs(self.PRESET_ORDER) do
        local skin = self.PRESETS[skinId]
        if skin then
            local text = ResolveText(skin.displayName, skin.id)
            if skin.availability == "experimental" then
                text = text .. experimentalSuffix
            end
            list[#list + 1] = {
                id = skin.id,
                value = skin.id,
                text = text,
                displayName = text,
                availability = skin.availability,
            }
        end
    end
    return list
end

function FrameSkin:IsEnabled()
    return true
end

function FrameSkin:Register(frame, role)
    if not frame then
        return
    end
    self._registry[frame] = role or "panel"
end

function FrameSkin:Apply(frame, role)
    if not frame then
        return
    end
    local targetRole = role or self._registry[frame] or "panel"
    if not self:IsEnabled() then
        ClearSkin(frame)
        ApplyBaseBackdrop(frame, targetRole)
        return
    end

    local skin = self:GetActivePreset()
    if targetRole == "main" then
        HideBaseBackdrop(frame)
        if skin.id == "kyrian" then
            ApplyLegacyKyrian(frame)
        else
            HideLegacyKyrian(frame)
            ApplyBackground(frame, skin)
            ApplyNineSlice(frame, skin)
            ApplyTitleBar(frame, skin)
        end
    elseif targetRole == "title" then
        ApplyTitleBar(frame, skin)
    elseif targetRole == "panel" or targetRole == "subPanel" then
        local alphaMul = tonumber(frame._frameSkinAlpha)
        if not alphaMul then
            alphaMul = targetRole == "subPanel" and 0.5 or 1
        end
        T.ApplyBackdrop(frame, {
            style = "chat",
            bgColor = ColorWithAlpha(skin.colors and skin.colors.backdrop, alphaMul),
            borderColor = ColorWithAlpha(skin.colors and skin.colors.leftPanelBorder, 1),
        })
    end
end

function FrameSkin:SetActive(skinId, opts)
    local skin = self.PRESETS[skinId]
    if not skin then
        T.debug("[FrameSkin] unknown skinId=%s", tostring(skinId))
        return false, "unknown"
    end

    local options = type(opts) == "table" and opts or {}
    if options.persist ~= false then
        if type(STT_DB) == "table" then
            STT_DB.frameSkin = skin.id
        end
        if type(C.DB) == "table" then
            C.DB.frameSkin = skin.id
        end
    end

    for frame, role in pairs(self._registry) do
        self:Apply(frame, role)
    end

    if options.silent ~= true then
        T.msg(string.format(
            ResolveText("FRAMESKIN_SWITCH_TIP", "Frame Appearance switched to %s. Some panels update next time they open or after /reload."),
            self:GetPresetName(skin.id)
        ))
    end
    return true
end

function FrameSkin:RefreshAll()
    for frame, role in pairs(self._registry) do
        self:Apply(frame, role)
    end
end

function FrameSkin:OnDisable()
    for frame in pairs(self._registry) do
        ClearSkin(frame)
    end
end

function FrameSkin:GetRegistryCount()
    local count = 0
    for _ in pairs(self._registry) do
        count = count + 1
    end
    return count
end
