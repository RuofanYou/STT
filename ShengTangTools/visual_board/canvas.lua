local T, C, L = unpack(select(2, ...))
do

local Canvas = {}
T.VisualBoardCanvas = Canvas

local unpackFunc = unpack or table.unpack
local SLOT_CIRCLE_TEXTURE = "Interface\\AddOns\\ShengTangTools\\media\\visual_board\\slot_circle.tga"
-- 内圆遮罩：复用 indicator_circle 的环厚度权威纹理；mask size = 外径 - 2*厚度，挖空内部留外缘亮环。
local CIRCLE_INNER_MASK = "Interface\\AddOns\\ShengTangTools\\media\\textures\\circle_inner_mask.png"
local RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local DEFAULT_ICON_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"
local ENCOUNTER_ICON_OVERRIDES = {
    [3183] = 7448204,
}
-- 暴雪内置纯白可着色纹理：自带内禀尺寸，配 SetVertexColor 直接上色，首帧即定（与 icon/marker 同路径）。
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- 可见性/命中权威（§3.3）：跳过渲染 = 元素或其组 hidden；跳过命中 = 元素或其组 locked。
local function ElementGroup(board, element)
    local groupID = element.groupID
    if groupID == nil then
        return nil
    end
    local groups = type(board.groups) == "table" and board.groups or nil
    if not groups then
        return nil
    end
    return groups[groupID]
end

local function IsRenderHidden(board, element)
    if element.hidden == true then
        return true
    end
    local group = ElementGroup(board, element)
    return group ~= nil and group.hidden == true
end

local function IsHitLocked(board, element)
    if element.locked == true then
        return true
    end
    local group = ElementGroup(board, element)
    return group ~= nil and group.locked == true
end

local function IsSpacePanActive(opts)
    return opts and opts.isSpacePanActive and opts.isSpacePanActive() == true
end

-- 元素当前帧解算单一权威（契约 §6.3）：返回 { x, y, alpha, scale, self, displayText } 或 nil（本帧不渲染）。
-- play 模式：直接取 overlay 算好的 renderState.resolved[id]（canvas 不碰 slide）。
-- edit 模式：调 Data:ResolveElementAtSlide(element, currentSlideIndex, board) 解算当前帧（hidden 返回 nil）。
local function ResolveRenderEntry(board, element, renderState)
    if type(renderState) ~= "table" then
        return nil
    end
    if renderState.mode == "play" then
        local resolved = type(renderState.resolved) == "table" and renderState.resolved or nil
        return resolved and resolved[element.id] or nil
    end
    -- edit：当前帧解算（隐藏由 ResolveElementAtSlide 判定，hidden 直接不渲染）。
    local frame = T.VisualBoardData:ResolveElementAtSlide(element, renderState.currentSlideIndex, board)
    if frame.hidden == true then
        return nil
    end
    return {
        x = frame.x,
        y = frame.y,
        alpha = 1,
        scale = frame.scale,
        rotation = frame.rotation,
        self = false,
    }
end

-- hex 颜色解析（与 indicator_text 的 HexToRGB 同算法；v2 shape/person 颜色统一为 6 位 hex 字符串）。
local function HexToRGB(hex)
    if type(hex) ~= "string" or #hex < 6 then
        return 1, 1, 1
    end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end

local function GetParamColor(color, fallback, alphaScale)
    local src = type(color) == "table" and color or fallback or {}
    return tonumber(src[1]) or 1,
        tonumber(src[2]) or 1,
        tonumber(src[3]) or 1,
        (tonumber(src[4]) or 1) * (alphaScale or 1)
end

-- 坐标换算单一权威（契约 §8.1）：artboard 逻辑坐标 ⇄ 屏幕局部坐标（CENTER 锚 TOPLEFT 体系）。
-- viewport = { zoom, panX, panY }，由 editor 持有会话态、渲染前传入；缺省为恒等映射（zoom=1,pan=0）。
-- 返回的屏幕坐标语义：screenX 向右为正，screenY 向下为正（SetPoint 时取 -screenY）。
local function ReadViewport(viewport)
    local vp = type(viewport) == "table" and viewport or {}
    local zoom = tonumber(vp.zoom) or 1
    if zoom <= 0 then zoom = 1 end
    return zoom, tonumber(vp.panX) or 0, tonumber(vp.panY) or 0
end

function Canvas:BoardToScreen(board, viewport, x, y)
    local zoom, panX, panY = ReadViewport(viewport)
    return panX + (tonumber(x) or 0) * zoom, panY + (tonumber(y) or 0) * zoom
end

function Canvas:ScreenToBoard(board, viewport, screenX, screenY)
    local zoom, panX, panY = ReadViewport(viewport)
    return ((tonumber(screenX) or 0) - panX) / zoom, ((tonumber(screenY) or 0) - panY) / zoom
end

local function ResolveEncounterIcon(params)
    local staticIcon = tonumber(params and params.encounterIcon)
    if staticIcon and staticIcon > 0 then
        return staticIcon
    end

    local encounterID = tonumber(params and params.encounterID)
    if not (encounterID and encounterID > 0) then
        return nil
    end

    local overrideIcon = ENCOUNTER_ICON_OVERRIDES[encounterID]
    if overrideIcon then
        return overrideIcon
    end

    local meta = T.SemanticBuiltinBossMetaS14
    if type(meta) == "table" then
        for _, item in pairs(meta) do
            if type(item) == "table"
                and tonumber(item.encounterID) == encounterID
                and tonumber(item.encounterIcon)
                and tonumber(item.encounterIcon) > 0 then
                return tonumber(item.encounterIcon)
            end
        end
    end

    return nil
end

-- 图标贴图解析（单一权威）：稳健区分 团队标记 / Boss 图标 / spellID / atlas 字符串 / 数字 fileID / 贴图路径。
-- spec_icons 的 icon 可能是 ① 数字 fileID ② atlas 名（无反斜杠、非 Interface 开头）③ 贴图路径。
-- 旧实现把 atlas 字符串错误地走 SetTexture 导致空白，这里按优先级正确分流。
local function ApplyIconTexture(texture, markerIndex, params)
    if markerIndex and markerIndex > 0 then
        texture:SetTexture(string.format(RAID_MARKER_TEXTURE, markerIndex))
        return
    end
    local encounterIcon = ResolveEncounterIcon(params)
    if encounterIcon then
        texture:SetTexture(encounterIcon)
        return
    end
    local spellID = tonumber(params.spellID)
    if spellID then
        local spellTexture = nil
        if C_Spell and C_Spell.GetSpellTexture then
            spellTexture = C_Spell.GetSpellTexture(spellID)
        end
        if not spellTexture and type(GetSpellTexture) == "function" then
            spellTexture = GetSpellTexture(spellID)
        end
        if spellTexture then
            texture:SetTexture(spellTexture)
            return
        end
    end
    if params.atlas and params.atlas ~= "" and texture.SetAtlas then
        texture:SetAtlas(params.atlas, false)
        return
    end
    local tex = params.texture
    if type(tex) == "number" then
        texture:SetTexture(tex)
        return
    end
    local pathStr = tostring(tex or "")
    if pathStr ~= ""
        and not pathStr:find("\\", 1, true)
        and pathStr:sub(1, 9) ~= "Interface"
        and texture.SetAtlas
        and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(pathStr) then
        texture:SetAtlas(pathStr, false)
        return
    end
    texture:SetTexture(pathStr ~= "" and pathStr or DEFAULT_ICON_TEXTURE)
end

-- 池取用单一权威：池项跨帧复用，但 DrawLayer 仅在 CreateTexture 时设过一次，复用时不会变。
-- self.textures 是被 person/shape/marker/selection 共用的【单一纹理池】：同一池 index 这帧可能是
-- person 的 ARTWORK 圈、下帧被 shape rect（应 OVERLAY）复用，层级却停留在 ARTWORK → 被同层 OVERLAY 子件遮挡。
-- 故 texture 取用点必须传入本子件应在的 drawLayer，这里每帧重设，保证复用项层级正确（唯一处理层级处）。
local function Acquire(pool, index, factory, drawLayer, parent)
    local item = pool[index]
    if not item then
        item = factory()
        pool[index] = item
    end
    -- re-parent 进当前元素容器 Frame：只改 region 的 draw 归属（由容器 FrameLevel 决定全局 z 名次），
    -- region 的 SetPoint 锚点仍锚 self.parent（容器 SetAllPoints(self.parent)，坐标系一致），不影响定位。
    if parent and item.SetParent then
        item:SetParent(parent)
    end
    if drawLayer and item.SetDrawLayer then
        item:SetDrawLayer(drawLayer)
    end
    item:Show()
    -- 复用复位顶点色（单一权威）：HideUnused 对 unused 项 SetVertexColor(...,0) 消残影，会污染池项 alpha=0。
    -- line/arrow（SetColorTexture）不会自带顶点色，复用到被污染项即全透明不显示。取出时统一复位为不透明白，
    -- 调用方随后的 SetColorTexture/SetTexture/SetVertexColor 设真实外观即可覆盖此复位。
    if item.SetVertexColor then item:SetVertexColor(1, 1, 1, 1) end
    return item
end

-- 每元素容器 Frame 单一权威（全局 z-order）：WoW 唯一能跨 draw layer 表达任意数量元素全局层级的机制是 FrameLevel。
-- 同一池 region 分类型固定 DrawLayer（ARTWORK/OVERLAY），单凭 DrawLayer 无法让 shape 十字 与 person 圆 按 z 名次互压；
-- 故每个【实际渲染】的元素分一个容器 Frame，FrameLevel = z 排序名次，元素所有 region 每帧 re-parent 进它 → 名次落到层级。
-- 按 index（排序名次）稳定复用；SetAllPoints(self.parent) 保证容器与画布同坐标系；不 EnableMouse → 鼠标穿透给命中帧。
function Canvas:AcquireElementFrame(index, level)
    local frame = self.elementFrames[index]
    if not frame then
        frame = CreateFrame("Frame", nil, self.parent)
        self.elementFrames[index] = frame
    end
    frame:SetAllPoints(self.parent)
    frame:SetFrameLevel(level)
    frame:Show()
    return frame
end

function Canvas:Create(parent)
    local renderer = {
        parent = parent,
        backgrounds = {},
        gridLines = {},
        artboardLines = {},
        textures = {},
        iconMasks = {},
        shapeTextures = {},
        ringTextures = {},
        fontStrings = {},
        lines = {},
        alignLines = {},
        previewLines = {},
        hitFrames = {},
        endpointFrames = {},
        rotationFrames = {},
        elementFrames = {},
    }
    setmetatable(renderer, { __index = self })

    -- 空白点击捕获帧（§6.2 onBackgroundClick）：铺满画布、坐落于所有元素命中帧之下（元素帧 +20，本帧 +5），
    -- 元素命中帧吃掉落在元素上的点击，落在空白处的点击由本帧接住 → 编辑器取消选择。
    -- 仅 edit 模式启用（Render 时按 opts 挂/卸脚本），play/preview 不挂脚本 → 不拦截、不画任何选择 UI。
    local catcher = CreateFrame("Button", nil, parent)
    catcher:SetFrameLevel(parent:GetFrameLevel() + 5)
    catcher:SetAllPoints(parent)
    catcher:RegisterForClicks("LeftButtonUp")
    catcher:Hide()
    renderer.backgroundCatcher = catcher

    return renderer
end

-- 回收池项时彻底清除残留视觉状态：仅 Hide() 不够——slot 圆贴图保留了绿色 vertexcolor 与
-- 旧坐标，编辑态拖动/组移动的高频 transient 重绘会让旧位置的圆/线残影留在画布上。
-- 这里对 texture/line 额外 ClearAllPoints + 中性化（透明 vertexcolor / 线宽归零）。
function Canvas:HideUnused(pool, used)
    for index = used + 1, #pool do
        local item = pool[index]
        item:Hide()
        if item.ClearAllPoints then
            item:ClearAllPoints()
        end
        if item.SetThickness then
            item:SetThickness(0)
        end
        if item.SetVertexColor then
            item:SetVertexColor(1, 1, 1, 0)
        end
    end
end

local function HideHitFrame(frame)
    frame.dragging = false
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
end

function Canvas:HideUnusedHitFrames(used)
    for index = used + 1, #self.hitFrames do
        HideHitFrame(self.hitFrames[index])
    end
end

function Canvas:HideUnusedEndpointFrames(used)
    for index = used + 1, #self.endpointFrames do
        local frame = self.endpointFrames[index]
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
end

function Canvas:HideUnusedRotationFrames(used)
    for index = used + 1, #self.rotationFrames do
        local frame = self.rotationFrames[index]
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
end

function Canvas:HideUnusedIconMasks(used)
    for index = used + 1, #self.iconMasks do
        local mask = self.iconMasks[index]
        if mask then
            mask:ClearAllPoints()
            mask:Hide()
        end
    end
end

-- 回收多余元素容器 Frame：rank 用尽后 hide index>used 的容器（被 hide 的容器内 region 已各自 HideUnused 回收）。
function Canvas:HideUnusedElementFrames(used)
    for index = used + 1, #self.elementFrames do
        self.elementFrames[index]:Hide()
    end
end

-- 背景属于 artboard 内容（§8.2）：Boss 背景纹理与网格都定位到 artboard 屏幕矩形
-- （经 BoardToScreen 换算 (0,0)-(artW,artH)），随 viewport 缩放/平移，与元素同一坐标体系。
-- artboard 框外是中性暗色画布空间（由 canvasHost backdrop 体现），不在此铺色。
-- SetClipsChildren 已开，背景超出画布框部分被裁。
function Canvas:DrawBackground(board, viewport, opts)
    local bg = type(board.bg) == "table" and board.bg or nil
    local artboard = type(board.artboard) == "table" and board.artboard or {}
    local artW = tonumber(artboard.w) or 1600
    local artH = tonumber(artboard.h) or 900
    local tlx, tly = self:BoardToScreen(board, viewport, 0, 0)
    local brx, bry = self:BoardToScreen(board, viewport, artW, artH)

    -- 背景层单独不透明度：仅 Boss 底图纹理吃 opts.bgAlpha（overlay 运行时传入，编辑器/缺省 = 1 不透明）。
    -- 控件层（person/shape/marker/text）走各自渲染路径、各自 alpha，完全不受 bgAlpha 影响 → 运行时背景淡、控件清晰。
    local bgAlpha = tonumber(opts and opts.bgAlpha)
    if bgAlpha == nil then bgAlpha = 1 end

    local texture = Acquire(self.backgrounds, 1, function()
        return self.parent:CreateTexture(nil, "BACKGROUND")
    end)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", self.parent, "TOPLEFT", tlx, -tly)
    texture:SetPoint("BOTTOMRIGHT", self.parent, "TOPLEFT", brx, -bry)
    texture:SetVertexColor(1, 1, 1, bgAlpha)
    if bg and type(bg.texture) == "string" and bg.texture ~= "" then
        texture:SetTexture(bg.texture)
    else
        texture:SetColorTexture(0.035, 0.045, 0.055, bgAlpha)
    end
    self:HideUnused(self.backgrounds, 1)

    local gridUsed = 0
    if not bg then
        local artScreenW = brx - tlx
        local artScreenH = bry - tly
        local step = math.max(24, math.min(artScreenW, artScreenH) / 8)
        local function drawGrid(x1, y1, x2, y2)
            local line = Acquire(self.gridLines, gridUsed + 1, function()
                return self.parent:CreateLine(nil, "BACKGROUND")
            end)
            gridUsed = gridUsed + 1
            line:ClearAllPoints()
            line:SetStartPoint("TOPLEFT", self.parent, x1, -y1)
            line:SetEndPoint("TOPLEFT", self.parent, x2, -y2)
            line:SetThickness(1)
            line:SetColorTexture(0.16, 0.22, 0.28, 0.55)
        end
        local x = tlx + step
        while x < brx do
            drawGrid(x, tly, x, bry)
            x = x + step
        end
        local y = tly + step
        while y < bry do
            drawGrid(tlx, y, brx, y)
            y = y + step
        end
    end
    self:HideUnused(self.gridLines, gridUsed)
end

-- artboard 边框（§8.2）：把 artboard 逻辑矩形 (0,0)-(artW,artH) 经 BoardToScreen 换算为屏幕四角，
-- 画 4 条边线让用户看到有界画板（无边画布 + fit-to-view 后，artboard 居中显示，框外为画布背景）。
-- 用独立 artboardLines 池，不与元素 line 池混用；颜色用浅青描边区分。
function Canvas:DrawArtboardBorder(board, viewport)
    local artboard = type(board.artboard) == "table" and board.artboard or {}
    local artW = tonumber(artboard.w) or 1600
    local artH = tonumber(artboard.h) or 900
    local lx, ty = self:BoardToScreen(board, viewport, 0, 0)
    local rx, by = self:BoardToScreen(board, viewport, artW, artH)
    local used = 0
    local function drawSegment(x1, y1, x2, y2)
        local line = Acquire(self.artboardLines, used + 1, function()
            return self.parent:CreateLine(nil, "BORDER")
        end)
        used = used + 1
        line:ClearAllPoints()
        line:SetStartPoint("TOPLEFT", self.parent, x1, -y1)
        line:SetEndPoint("TOPLEFT", self.parent, x2, -y2)
        line:SetThickness(2)
        line:SetColorTexture(0.45, 0.65, 0.78, 0.85)
    end
    drawSegment(lx, ty, rx, ty) -- 上
    drawSegment(rx, ty, rx, by) -- 右
    drawSegment(rx, by, lx, by) -- 下
    drawSegment(lx, by, lx, ty) -- 左
    self:HideUnused(self.artboardLines, used)
end

-- 画圆单一权威（person.circle 与 shape circle 共用）：以屏幕坐标 (sx,sy) 为圆心画填充圆。
-- diameter 已是屏幕像素（调用方乘好 zoom）。返回新的 textureIndex。
-- shapeStyle="solid" → 复用 slot_circle 贴图整圆填充。
-- shapeStyle="ring"（空心环）：slot_circle.tga 为实心圆纹理，无环态，且 WoW texture 叠加不支持 alpha 擦除；
--   真环需独立环纹理或顶点遮罩 → 留第二批（widget/素材 owner）。本批 ring 暂按 solid 渲染，
--   不引入"偷背景色挖空"这类脆弱 hack（会硬编码背景色、压在图上露馅）。
function Canvas:DrawCircle(sx, sy, diameter, r, g, b, a, shapeStyle, textureIndex, pool, drawLayer)
    -- ring 暂按 solid 渲染（见上方说明，环纹理待第二批）；不在此高频渲染路径打 debug，避免刷屏。
    -- pool/drawLayer 缺省 = person 圈走共享 self.textures/ARTWORK；shape 圈传入独立 self.shapeTextures/OVERLAY。
    pool = pool or self.textures
    drawLayer = drawLayer or "ARTWORK"
    local outer = Acquire(pool, textureIndex + 1, function()
        return self.parent:CreateTexture(nil, drawLayer)
    end, drawLayer, self._elemParent)
    textureIndex = textureIndex + 1
    outer:ClearAllPoints()
    outer:SetPoint("CENTER", self.parent, "TOPLEFT", sx, -sy)
    outer:SetTexture(SLOT_CIRCLE_TEXTURE)
    if outer.SetBlendMode then outer:SetBlendMode("BLEND") end
    outer:SetVertexColor(r, g, b, a)
    outer:SetSize(diameter, diameter)
    return textureIndex
end

-- 边缘亮环单一权威（本机高亮 §10）：在 (sx,sy) 处画一道恰好贴外缘的亮环，外径 = diameter（不超出分散圈），
-- 厚度由内圆遮罩控制（mask size = diameter - 2*thickness 挖空内部，只留外缘环带）。复用 indicator_circle 的
-- CIRCLE_INNER_MASK 厚度纹理，不偷背景色挖空、不引环纹理。ringTextures 为本环专用池：mask 仅随环纹理复用，
-- 永不污染 person/shape/marker 共用的 self.textures 池。返回新的 ringIndex。
function Canvas:DrawEdgeRing(sx, sy, diameter, thickness, r, g, b, a, ringIndex)
    local pool = self.ringTextures
    local item = pool[ringIndex + 1]
    if not item then
        local tex = self.parent:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(SLOT_CIRCLE_TEXTURE)
        local mask = self.parent:CreateMaskTexture()
        mask:SetTexture(CIRCLE_INNER_MASK, "CLAMPTOWHITE", "CLAMPTOWHITE", "NEAREST")
        tex:AddMaskTexture(mask)
        item = { tex = tex, mask = mask }
        pool[ringIndex + 1] = item
    end
    ringIndex = ringIndex + 1
    local tex, mask = item.tex, item.mask
    -- re-parent 亮环纹理进当前元素容器（与该 person 同 z 名次层级）；mask 锚 tex CENTER 随之，无需单独 re-parent。
    if self._elemParent and tex.SetParent then
        tex:SetParent(self._elemParent)
    end
    tex:Show()
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", self.parent, "TOPLEFT", sx, -sy)
    if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
    tex:SetVertexColor(r, g, b, a)
    tex:SetSize(diameter, diameter)
    -- 遮罩挖空内部：内径 = 外径 - 2*厚度，留下厚度为 thickness 的外缘环带；下限 0 避免负尺寸。
    local inner = math.max(0, diameter - thickness * 2)
    mask:ClearAllPoints()
    mask:SetPoint("CENTER", tex, "CENTER")
    mask:SetSize(inner, inner)
    return ringIndex
end

-- 回收边缘环池未用项：隐藏并中性化，避免旧位置/旧色残影（与 HideUnused 同义，但本池项是 { tex, mask } 复合）。
function Canvas:HideUnusedRings(used)
    local pool = self.ringTextures
    for index = used + 1, #pool do
        local item = pool[index]
        item.tex:Hide()
        item.tex:ClearAllPoints()
        item.tex:SetVertexColor(1, 1, 1, 0)
    end
end

-- 字体面解析（与 indicator_text 同一字段集语义）：default → STANDARD_TEXT_FONT；FRIZQT → 暴雪默认西文字。
local TEXT_FONT_FACES = {
    default = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
    FRIZQT = "Fonts\\FRIZQT__.TTF",
}

-- 样式文本绘制单一权威（text 元素与 person 名签共用，借鉴 indicator_text 的 ApplyStyle 算法）。
-- style 字段集逐字复用 indicator_text.style：fontSize/fontFace/color/bold/outline/outlineColor/shadow/scale(textScale)。
-- 在 canvas 现有 fontStrings 池里画（不复用 indicator_text 的 Acquire/Release 实例池，避免拖进倒计时/glow 耦合）。
-- screenX/screenY = 名签锚点屏幕坐标；anchorH ∈ "CENTER"|"TOP"|"BOTTOM"|"LEFT"|"RIGHT"（决定文字相对锚点的贴边方向）。
-- zoom 把逻辑字号换算到屏幕字号；renderAlpha = 元素当前帧整体淡入淡出系数。
-- 注：自定义 outlineColor（非黑）的 8 向描边复刻待第二批；本批用原生 OUTLINE/THICKOUTLINE（黑描边），与默认 outlineColor=000000 视觉一致。
function Canvas:DrawStyledText(screenX, screenY, zoom, text, style, anchorH, renderAlpha, textIndex)
    style = type(style) == "table" and style or {}
    local fontString = Acquire(self.fontStrings, textIndex + 1, function()
        return self.parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    end, nil, self._elemParent)
    textIndex = textIndex + 1

    -- 复用前先给足宽度，避免上一帧窄文本框把本帧内容截成省略号。
    if fontString.SetWidth then fontString:SetWidth(10000) end
    if fontString.SetMaxLines then fontString:SetMaxLines(0) end
    if fontString.SetWordWrap then fontString:SetWordWrap(false) end

    -- 锚点：名签贴锚点的内边（top 名签的底边贴锚点上方，bottom 名签的顶边贴锚点下方）。
    local point, relAnchor = "CENTER", "TOPLEFT"
    if anchorH == "TOP" then
        point = "BOTTOM"
    elseif anchorH == "BOTTOM" then
        point = "TOP"
    elseif anchorH == "LEFT" then
        point = "RIGHT"
    elseif anchorH == "RIGHT" then
        point = "LEFT"
    end
    local justifyH = tostring(style.justifyH or "CENTER"):upper()
    if justifyH ~= "LEFT" and justifyH ~= "CENTER" and justifyH ~= "RIGHT" then
        justifyH = "CENTER"
    end

    local alpha = tonumber(renderAlpha) or 1
    local r, g, b = HexToRGB(style.color or "FFFFFF")
    local font = TEXT_FONT_FACES[style.fontFace or "default"] or TEXT_FONT_FACES.default
    local logicalSize = tonumber(style.fontSize) or 24
    local textScale = tonumber(style.scale) or 1
    local screenSize = math.max(6, logicalSize * textScale * (tonumber(zoom) or 1))
    local outlineFlag = ""
    if style.outline ~= false then
        outlineFlag = style.bold and "THICKOUTLINE" or "OUTLINE"
    elseif style.bold then
        outlineFlag = "THICKOUTLINE"
    end
    if fontString.SetFont then
        fontString:SetFont(font, screenSize, outlineFlag)
    end
    fontString:SetJustifyH(justifyH)
    fontString:SetText(tostring(text or ""))

    local textWidth = tonumber(style.width)
    if textWidth and textWidth > 0 then
        fontString:SetWidth(textWidth * (tonumber(zoom) or 1))
        if fontString.SetWordWrap then fontString:SetWordWrap(true) end
    elseif fontString.SetWidth and fontString.GetStringWidth then
        fontString:SetWidth(math.max(1, fontString:GetStringWidth()))
        if fontString.SetWordWrap then fontString:SetWordWrap(false) end
    end

    fontString:ClearAllPoints()
    fontString:SetPoint(point, self.parent, relAnchor, screenX, -screenY)
    fontString:SetTextColor(r, g, b, alpha)

    if style.shadow ~= false then
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 0.8 * alpha) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(1, -1) end
    elseif fontString.SetShadowOffset then
        fontString:SetShadowOffset(0, 0)
    end
    return textIndex
end

-- shape line/arrow 绘制（契约 §2.2(c)）：x/y=起点（屏幕坐标已由调用方换算），end_x/end_y=终点（逻辑坐标，本函数换算）。
-- color 为 hex 字符串、alpha 为 params.alpha；arrow 额外画两条翼线。
function Canvas:DrawShapeLine(board, viewport, element, screenX, screenY, zoom, renderAlpha, lineIndex)
    local params = element.params or {}
    local r, g, b = HexToRGB(params.color or "FFFFFF")
    local a = (tonumber(params.alpha) or 1) * (tonumber(renderAlpha) or 1)
    local thickness = (tonumber(params.thickness) or 3) * (tonumber(zoom) or 1)

    -- 终点换算：end_x/end_y 在 element 顶层（逻辑坐标）。
    local startX = tonumber(entry and entry.x) or tonumber(element.x) or 0
    local startY = tonumber(entry and entry.y) or tonumber(element.y) or 0
    local endX = tonumber(element.end_x) or (startX + 120)
    local endY = tonumber(element.end_y) or startY
    local ex, ey = self:BoardToScreen(board, viewport, endX, endY)

    local function drawSegment(x1, y1, x2, y2)
        local line = Acquire(self.lines, lineIndex + 1, function()
            return self.parent:CreateLine(nil, "OVERLAY")
        end, nil, self._elemParent)
        lineIndex = lineIndex + 1
        line:ClearAllPoints()
        line:SetStartPoint("TOPLEFT", self.parent, x1, -y1)
        line:SetEndPoint("TOPLEFT", self.parent, x2, -y2)
        line:SetThickness(thickness)
        line:SetColorTexture(r, g, b, a)
    end

    drawSegment(screenX, screenY, ex, ey)
    if params.shapeKind == "arrow" then
        local dx, dy = ex - screenX, ey - screenY
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.01 then
            local ux, uy = dx / len, dy / len
            local nx, ny = -uy, ux
            local arrowSize = (tonumber(params.arrowSize) or 22) * (tonumber(zoom) or 1)
            local wing = arrowSize * 0.58
            drawSegment(ex, ey, ex - ux * arrowSize + nx * wing, ey - uy * arrowSize + ny * wing)
            drawSegment(ex, ey, ex - ux * arrowSize - nx * wing, ey - uy * arrowSize - ny * wing)
        end
    end
    return lineIndex
end

-- 对齐参考线轻量接口（契约 §8.3）：editor 拖拽吸附时调用。
-- lines = 屏幕坐标线段数组，每项 { x1, y1, x2, y2 }（屏幕局部坐标，TOPLEFT 体系：向右/向下为正）；
-- editor 拖拽回调内用 Data:GetElementBox 取盒、Canvas:BoardToScreen 换算后传入。空数组/nil = 清除。
-- 独立 alignLines 池，与元素 line 池隔离（避免被元素重绘回收），用紫青色细线区分对齐线。
function Canvas:DrawAlignGuides(lines)
    local used = 0
    if type(lines) == "table" then
        for _, seg in ipairs(lines) do
            if type(seg) == "table" then
                local line = Acquire(self.alignLines, used + 1, function()
                    return self.parent:CreateLine(nil, "OVERLAY")
                end)
                used = used + 1
                line:ClearAllPoints()
                line:SetStartPoint("TOPLEFT", self.parent, tonumber(seg[1]) or 0, -(tonumber(seg[2]) or 0))
                line:SetEndPoint("TOPLEFT", self.parent, tonumber(seg[3]) or 0, -(tonumber(seg[4]) or 0))
                line:SetThickness(1)
                line:SetColorTexture(0.35, 0.95, 1.0, 0.9)
            end
        end
    end
    self:HideUnused(self.alignLines, used)
end

local GetHitBox

-- 选择高亮：当元素在 selectedIDs 集合内时画选择框（沿用原黄色高亮样式）。
function Canvas:DrawSelectionBox(board, element, textureIndex, opts)
    if not (opts and opts.selectedIDs and opts.selectedIDs[element.id]) then
        return textureIndex
    end
    local px, py, width, height = GetHitBox(self.parent, board, element, opts)
    local marker = Acquire(self.textures, textureIndex + 1, function()
        return self.parent:CreateTexture(nil, "ARTWORK")
    end, "ARTWORK", self._elemParent)
    textureIndex = textureIndex + 1
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", self.parent, "TOPLEFT", px, -py)
    if marker.SetBlendMode then marker:SetBlendMode("BLEND") end
    marker:SetColorTexture(1.0, 0.82, 0.18, 0.24)
    marker:SetSize(math.max(18, width + 10), math.max(18, height + 10))
    return textureIndex
end

-- 图标贴图绘制（person.icon 子件 + marker 元素共用底层）：以屏幕坐标为中心，边长 screenSize。
-- iconParams 走 ApplyIconTexture（markerIndex>0 团队标记 / atlas / fileID / 路径 四态分流）；带可选描边。
function Canvas:DrawIcon(screenX, screenY, screenSize, rotationDeg, alpha, iconParams, markerIndex, textureIndex)
    iconParams = type(iconParams) == "table" and iconParams or {}
    local mIndex = tonumber(markerIndex) or 0
    local shape = tostring(iconParams.shape or "square"):lower()
    if mIndex > 0 then
        shape = "square"
    elseif shape ~= "circle" and shape ~= "square" then
        shape = "square"
    end
    local borderSize = (tonumber(iconParams.borderSize) or 0) * 1
    if borderSize > 0 then
        local br, bg, bb, ba
        if type(iconParams.borderColor) == "string" then
            br, bg, bb = HexToRGB(iconParams.borderColor)
            ba = 0.95 * alpha
        else
            br, bg, bb, ba = GetParamColor(iconParams.borderColor, { 0, 0, 0, 0.95 }, alpha)
        end
        local border = Acquire(self.textures, textureIndex + 1, function()
            return self.parent:CreateTexture(nil, "ARTWORK")
        end, "ARTWORK", self._elemParent)
        textureIndex = textureIndex + 1
        border:ClearAllPoints()
        border:SetPoint("CENTER", self.parent, "TOPLEFT", screenX, -screenY)
        border:SetTexture(shape == "circle" and SLOT_CIRCLE_TEXTURE or WHITE_TEXTURE)
        if border.SetBlendMode then border:SetBlendMode("BLEND") end
        border:SetVertexColor(br, bg, bb, ba)
        border:SetSize(screenSize + borderSize * 2, screenSize + borderSize * 2)
    end

    local texture = Acquire(self.textures, textureIndex + 1, function()
        return self.parent:CreateTexture(nil, "OVERLAY")
    end, "OVERLAY", self._elemParent)
    textureIndex = textureIndex + 1
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", self.parent, "TOPLEFT", screenX, -screenY)
    texture:SetRotation(math.rad(tonumber(rotationDeg) or 0))
    if texture.SetBlendMode then texture:SetBlendMode("BLEND") end
    texture:SetVertexColor(1, 1, 1, alpha)
    ApplyIconTexture(texture, mIndex, iconParams)
    texture:SetSize(screenSize, screenSize)
    if texture._visualBoardMask and texture.RemoveMaskTexture then
        texture:RemoveMaskTexture(texture._visualBoardMask)
        texture._visualBoardMask = nil
    end
    if shape == "circle" and self.parent.CreateMaskTexture and texture.AddMaskTexture then
        local mask = self.iconMasks[textureIndex]
        if not mask then
            mask = self.parent:CreateMaskTexture()
            self.iconMasks[textureIndex] = mask
        end
        mask:ClearAllPoints()
        mask:SetTexture(SLOT_CIRCLE_TEXTURE, "CLAMPTOWHITE", "CLAMPTOWHITE", "NEAREST")
        mask:SetPoint("CENTER", texture, "CENTER")
        mask:SetSize(screenSize, screenSize)
        mask:Show()
        texture:AddMaskTexture(mask)
        texture._visualBoardMask = mask
    end
    return textureIndex
end

-- person 复合渲染（契约 §7）：单锚点 = 屏幕坐标 (screenX,screenY)；circle/icon/text 三子件随动。
-- entry = 当前帧解算结果（含 alpha/scale/self/displayText）；info = 当前方案 PreprocessText（默认图标解析用，缺失落问号图）。
-- self=true 时套 highlightStyle（§10）：缺省不放大；圈色提亮 + 外缘亮环（同半径不超出分散圈，glowColor 可自定义，缺省金色）。
function Canvas:DrawPerson(board, element, screenX, screenY, zoom, entry, info, textureIndex, textIndex, ringIndex)
    local params = element.params or {}
    local layout = T.VisualBoardData:GetPersonLayout(element)
    local alpha = tonumber(entry and entry.alpha) or 1
    local elementScale = tonumber(entry and entry.scale) or 1

    -- 本机高亮（§10）：self=true 时套 highlightStyle 视觉强调。highlightScale 缺省 1 = 不放大，
    -- 避免撑大分散圈误导真实半径；circle/icon/text 尺寸与非高亮完全一致。可自定义 scale 放大。
    -- 字段集逐字按 §7：{ scale, glow, glowColor, desaturateOthers }。desaturateOthers 影响"其它 person"，
    -- 属跨元素决策（需 overlay 在 resolved 标记别人），非本函数单元素职责范围 → canvas 侧不处理，避免越权造机制。
    local isSelf = entry and entry.self == true
    local highlightScale = 1
    local ringEnabled, ringR, ringG, ringB = false, 1, 0.82, 0
    if isSelf then
        local hs = type(params.highlightStyle) == "table" and params.highlightStyle or nil
        highlightScale = tonumber(hs and hs.scale) or 1
        -- glow 语义 = 圆边缘亮环开关；缺省开，显式 glow=false 才关。
        ringEnabled = not (hs and hs.glow == false)
        if hs and type(hs.glowColor) == "string" then
            ringR, ringG, ringB = HexToRGB(hs.glowColor)
        end
    end
    local s = zoom * elementScale * highlightScale

    -- circle 子件（enabled）：圆心 = 锚点。
    if layout.circle.enabled then
        local circle = type(params.circle) == "table" and params.circle or {}
        local cr, cg, cb = HexToRGB(circle.color or "33CC66")
        local ca = (tonumber(circle.alpha) or 0.5) * alpha
        if entry and entry.self == true then
            -- 高亮：圈色提亮（在原色基础上向白偏移），区分本机。
            cr, cg, cb = cr * 0.5 + 0.5, cg * 0.5 + 0.5, cb * 0.5 + 0.5
        end
        textureIndex = self:DrawCircle(screenX, screenY, layout.circle.radius * 2 * s, cr, cg, cb, ca, circle.shapeStyle, textureIndex)
    end

    -- 本机外缘亮环（§10）：贴圆外缘画一道明亮描边环，外径 = 圈外径（不超出分散圈，不改变其视觉大小）。
    -- 环厚 2.5px（不随 zoom 放大以保持稳定可见的细环），明亮金色或自定义 glowColor。OVERLAY 在圈之上，只描边不撑大。
    if isSelf and ringEnabled then
        local ringDiameter = (layout.circle.enabled and layout.circle.radius * 2 or layout.icon.size) * s
        ringIndex = self:DrawEdgeRing(screenX, screenY, ringDiameter, 2.5, ringR, ringG, ringB, alpha, ringIndex)
    end

    -- icon 子件：中心 = 锚点。贴图 = params.icon.texture/atlas 互斥取一，否则 ResolvePersonDefaultIcon（nil 落问号图）。
    local iconParams = type(params.icon) == "table" and params.icon or {}
    local iconSize = layout.icon.size * s
    local resolvedIcon = iconParams
    if iconParams.spellID == nil and (iconParams.texture == nil or iconParams.texture == "") and (iconParams.atlas == nil or iconParams.atlas == "") then
        -- 默认图标：按 slotName 解析专精图标 fileID；解析不到则 ApplyIconTexture 落问号图。
        local defaultIcon = T.VisualBoardData:ResolvePersonDefaultIcon(element, info)
        resolvedIcon = {
            texture = defaultIcon,
            borderSize = iconParams.borderSize,
            borderColor = iconParams.borderColor,
        }
    end
    textureIndex = self:DrawIcon(screenX, screenY, iconSize, entry and entry.rotation or element.rotation, alpha, resolvedIcon, 0, textureIndex)

    -- text 子件（名签，enabled）：内容 = 解析名(play) / slotName(edit)；位置 = 锚点 + layout.text.ox/oy。
    if layout.text.enabled then
        local textParams = type(params.text) == "table" and params.text or {}
        local content
        if entry and entry.displayText ~= nil then
            content = entry.displayText           -- play：已解析真实名
        else
            content = params.slotName             -- edit：直接显示槽位名
        end
        local position = tostring(textParams.position or "top")
        local tx = screenX + layout.text.ox * s
        local ty = screenY - layout.text.oy * s   -- layout.oy 正=向上；屏幕 y 向下为正，故减。
        if layout.text.vertical then
            -- left/right 竖排名签：按 utf8 单字竖排。SplitUTF8Chars 尚未提取到 widget_api（§7 拍板归 widget_api owner，
            -- 现仅 indicator_circle.lua 内 local，canvas 不得自造第二份）→ 本批留桩，横排回退 + 一次性 debug。
            self._verticalNameWarned = self._verticalNameWarned or {}
            if not self._verticalNameWarned[element.id] then
                T.debug("[VisualBoard][canvas] person 竖排名签(position=", position, ")待 T.SplitUTF8Chars 提取，暂横排回退 id=", tostring(element.id))
                self._verticalNameWarned[element.id] = true
            end
            local anchorH = position == "left" and "RIGHT" or "LEFT"
            textIndex = self:DrawStyledText(tx, ty, s, content, textParams, anchorH, alpha, textIndex)
        else
            local anchorH = position == "bottom" and "BOTTOM" or "TOP"
            textIndex = self:DrawStyledText(tx, ty, s, content, textParams, anchorH, alpha, textIndex)
        end
    end

    return textureIndex, textIndex, ringIndex
end

-- shape 渲染（契约 §2.2(c)）：rect(中心 w/h) / circle(圆心 radius，solid|ring) / line|arrow 走 DrawShapeLine。
-- rect/circle 走【独立专用池】self.shapeTextures（固定 OVERLAY），shapeIndex 独立计数，永不与 person/marker 共享槽位 →
-- 槽位不随 person 数量漂移，十字/形状跨帧复用同一物理纹理，可见性稳定。line/arrow 仍走 self.lines 独立池。
function Canvas:DrawShape(board, viewport, element, screenX, screenY, zoom, entry, shapeIndex, lineIndex)
    local params = element.params or {}
    local alpha = tonumber(entry and entry.alpha) or 1
    local elementScale = tonumber(entry and entry.scale) or 1
    local s = zoom * elementScale
    local shapeKind = params.shapeKind
    local r, g, b = HexToRGB(params.color or "FFFFFF")
    local a = (tonumber(params.alpha) or 1) * alpha

    if shapeKind == "circle" then
        local diameter = (tonumber(params.radius) or 60) * 2 * s
        shapeIndex = self:DrawCircle(screenX, screenY, diameter, r, g, b, a, params.shapeStyle, shapeIndex, self.shapeTextures, "OVERLAY")
    elseif shapeKind == "line" or shapeKind == "arrow" then
        lineIndex = self:DrawShapeLine(board, viewport, element, screenX, screenY, zoom, alpha, lineIndex)
    else
        -- rect：以 x/y 为中心，w/h。与 icon/marker/circle 同一上色路径（内置纯白纹理 + SetVertexColor），
        -- 自带内禀尺寸，首帧即定尺、即可见；不用 SetColorTexture（纯色虚拟纹理无内禀尺寸，叠 SetRotation 时首渲不显示）。
        local rect = Acquire(self.shapeTextures, shapeIndex + 1, function()
            return self.parent:CreateTexture(nil, "OVERLAY")
        end, "OVERLAY", self._elemParent)
        shapeIndex = shapeIndex + 1
        rect:ClearAllPoints()
        rect:SetPoint("CENTER", self.parent, "TOPLEFT", screenX, -screenY)
        if rect.SetBlendMode then rect:SetBlendMode("BLEND") end
        rect:SetTexture(WHITE_TEXTURE)
        rect:SetVertexColor(r, g, b, a)
        rect:SetSize((tonumber(params.w) or 200) * s, (tonumber(params.h) or 120) * s)
        rect:SetRotation(math.rad(tonumber(entry and entry.rotation or element.rotation) or 0))
    end
    return shapeIndex, lineIndex
end

-- marker 渲染（契约 §2.2(d)）：暴雪 8 大团队标记，中心 = 锚点，边长 size。
function Canvas:DrawMarker(element, screenX, screenY, zoom, entry, textureIndex)
    local params = element.params or {}
    local alpha = tonumber(entry and entry.alpha) or 1
    local elementScale = tonumber(entry and entry.scale) or 1
    local markerIndex = tonumber(params.markerIndex) or 0
    local size = (tonumber(params.size) or 54) * zoom * elementScale
    return self:DrawIcon(screenX, screenY, size, entry and entry.rotation or element.rotation, alpha, params, markerIndex, textureIndex)
end

function Canvas:DrawIconElement(element, screenX, screenY, zoom, entry, textureIndex)
    local params = element.params or {}
    local alpha = tonumber(entry and entry.alpha) or 1
    local elementScale = tonumber(entry and entry.scale) or 1
    local size = (tonumber(params.size) or 54) * zoom * elementScale
    return self:DrawIcon(screenX, screenY, size, entry and entry.rotation or element.rotation, alpha, params, 0, textureIndex)
end

-- 光标 → artboard 逻辑坐标（拖拽回调用）。换算唯一经 Canvas:ScreenToBoard（§8.1），不再散算。
-- viewport 由调用方（手柄/命中帧的拖拽回调）持有并传入。
local function CursorToBoardPoint(parent, board, viewport)
    local cx, cy = GetCursorPosition()
    local scale = parent:GetEffectiveScale()
    if scale <= 0 then scale = 1 end
    local left = parent:GetLeft() or 0
    local top = parent:GetTop() or 0
    -- 光标全局坐标 → parent 局部屏幕坐标（TOPLEFT 体系：向右为正、向下为正）。
    local localX = (cx / scale) - left
    local localY = top - (cy / scale)
    return Canvas:ScreenToBoard(board, viewport, localX, localY)
end

local function ConstrainDelta45(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    if ax < 0.001 and ay < 0.001 then
        return dx, dy
    end
    if ay <= ax * 0.4142 then
        return dx, 0
    end
    if ax <= ay * 0.4142 then
        return 0, dy
    end
    local len = math.max(ax, ay)
    return dx >= 0 and len or -len, dy >= 0 and len or -len
end

local function Atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    return math.atan(y, x)
end

-- 几何单一权威（§6.3）：逻辑尺寸来自 Data:GetElementBox（已含 element.scale），canvas 只换算屏幕坐标 + 乘 zoom。
-- 修正 v1 双重缩放：GetElementBox 内部已乘 element.scale，这里不再二次乘，只乘 viewport.zoom。
GetHitBox = function(parent, board, element, opts)
    local viewport = opts and opts.viewport
    local zoom = ReadViewport(viewport)
    local geometry = T.VisualBoardData:ResolveElementGeometryAtSlide(element, opts and opts.currentSlideIndex, board)
    local px, py = Canvas:BoardToScreen(board, viewport, geometry.x, geometry.y)
    local boxW = (tonumber(geometry.boxW) or 0) * zoom
    local boxH = (tonumber(geometry.boxH) or 0) * zoom

    if geometry.shape == "segment" then
        local p2x, p2y = Canvas:BoardToScreen(board, viewport, geometry.endX, geometry.endY)
        return (px + p2x) / 2, (py + p2y) / 2, math.max(28, math.abs(p2x - px) + 28), math.max(28, math.abs(p2y - py) + 28)
    end
    -- radial（圆/图标/marker/person）与 rect/text/person：box 已是含 scale 的逻辑尺寸，乘 zoom 即屏幕尺寸。
    return px, py, boxW, boxH
end

function Canvas:RegisterEditHit(board, element, hitIndex, opts, rank)
    if not (opts and opts.mode == "edit" and element) then
        return hitIndex
    end
    if IsHitLocked(board, element) then
        return hitIndex
    end

    local px, py, width, height = GetHitBox(self.parent, board, element, opts)
    local frame = Acquire(self.hitFrames, hitIndex + 1, function()
        local hit = CreateFrame("Button", nil, self.parent)
        hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        hit:RegisterForDrag("LeftButton")
        return hit
    end)
    hitIndex = hitIndex + 1

    -- 命中帧 z 跟随 rank：层级 = parent +1000+rank，居于所有元素容器（+21..+21+N）之上、预览手柄（+2000 区）之下。
    -- 元素容器不 EnableMouse 不拦截 → 命中帧永远收到鼠标；+rank 让视觉最上层元素的命中帧 frame level 最高 → 点击优先选中它。
    -- 每帧按 rank 重设（hitIndex 复用槽位 ≠ rank，必须每帧落 level），不能只在 lazy-create 时设一次。
    frame:SetFrameLevel(self.parent:GetFrameLevel() + 1000 + (tonumber(rank) or 0))
    frame.elementID = element.id
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", self.parent, "TOPLEFT", px, -py)
    frame:SetSize(math.max(18, width), math.max(18, height))
    frame:SetScript("OnClick", function(self, button)
        if IsSpacePanActive(opts) then
            return
        end
        if button == "RightButton" and opts.onContext then
            opts.onContext(self.elementID)
        elseif opts.onSelect then
            opts.onSelect(self.elementID, IsShiftKeyDown and IsShiftKeyDown())
        end
    end)
    frame:SetScript("OnDoubleClick", function(self, button)
        if IsSpacePanActive(opts) then
            return
        end
        if button == "LeftButton" and opts.onDoubleClick then
            opts.onDoubleClick(self.elementID)
        end
    end)
    frame:SetScript("OnDragStart", function(self)
        if IsSpacePanActive(opts) then
            self.dragging = false
            self:SetScript("OnUpdate", nil)
            return
        end
        self.dragging = true
        local boardX, boardY = CursorToBoardPoint(self:GetParent(), board, opts.viewport)
        self.dragStartCursorX = boardX
        self.dragStartCursorY = boardY
        local resolved = T.VisualBoardData:ResolveElementAtSlide(element, opts.currentSlideIndex, board)
        self.dragStartElementX = tonumber(resolved.x) or tonumber(element.x) or 0
        self.dragStartElementY = tonumber(resolved.y) or tonumber(element.y) or 0
        if opts.onSelect then
            opts.onSelect(self.elementID, IsShiftKeyDown and IsShiftKeyDown())
        end
        self:SetScript("OnUpdate", function()
            local nextX, nextY = CursorToBoardPoint(self:GetParent(), board, opts.viewport)
            if IsShiftKeyDown and IsShiftKeyDown() then
                local dx, dy = ConstrainDelta45(nextX - (self.dragStartCursorX or nextX), nextY - (self.dragStartCursorY or nextY))
                nextX = (self.dragStartElementX or nextX) + dx
                nextY = (self.dragStartElementY or nextY) + dy
            end
            if opts.onDrag then
                opts.onDrag(self.elementID, nextX, nextY, true)
            end
        end)
    end)
    frame:SetScript("OnDragStop", function(self)
        if IsSpacePanActive(opts) or not self.dragging then
            self.dragging = false
            self:SetScript("OnUpdate", nil)
            return
        end
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        local nextX, nextY = CursorToBoardPoint(self:GetParent(), board, opts.viewport)
        if IsShiftKeyDown and IsShiftKeyDown() then
            local dx, dy = ConstrainDelta45(nextX - (self.dragStartCursorX or nextX), nextY - (self.dragStartCursorY or nextY))
            nextX = (self.dragStartElementX or nextX) + dx
            nextY = (self.dragStartElementY or nextY) + dy
        end
        if opts.onDrag then
            opts.onDrag(self.elementID, nextX, nextY, false)
        end
    end)
    return hitIndex
end

function Canvas:RegisterSegmentEndpointHandles(board, element, handleIndex, opts, rank)
    if not (opts and opts.mode == "edit" and opts.selectedIDs and opts.selectedIDs[element.id]) then
        return handleIndex
    end
    if IsHitLocked(board, element) then
        return handleIndex
    end
    local params = element.params or {}
    if element.type ~= "shape" or (params.shapeKind ~= "line" and params.shapeKind ~= "arrow") then
        return handleIndex
    end

    local geometry = T.VisualBoardData:ResolveElementGeometryAtSlide(element, opts.currentSlideIndex, board)
    local points = {
        { endpoint = "start", x = geometry.startX, y = geometry.startY, color = { 0.2, 0.85, 0.95, 1 } },
        -- end_x/end_y 尚无逐帧 override，端点手柄明确停留在基线端点。
        { endpoint = "end", x = geometry.endX, y = geometry.endY, color = { 1.0, 0.72, 0.16, 1 } },
    }
    for _, point in ipairs(points) do
        local sx, sy = self:BoardToScreen(board, opts.viewport, point.x, point.y)
        local frame = Acquire(self.endpointFrames, handleIndex + 1, function()
            local hit = CreateFrame("Button", nil, self.parent)
            hit:RegisterForClicks("LeftButtonUp")
            hit:RegisterForDrag("LeftButton")
            local tex = hit:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(hit)
            tex:SetTexture(WHITE_TEXTURE)
            hit.tex = tex
            return hit
        end)
        handleIndex = handleIndex + 1
        frame:SetFrameLevel(self.parent:GetFrameLevel() + 2100 + (tonumber(rank) or 0))
        frame.elementID = element.id
        frame.endpoint = point.endpoint
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", self.parent, "TOPLEFT", sx, -sy)
        frame:SetSize(18, 18)
        if frame.tex then
            frame.tex:SetVertexColor(point.color[1], point.color[2], point.color[3], point.color[4])
        end
        frame:SetScript("OnClick", function(self)
            if IsSpacePanActive(opts) then
                return
            end
            if opts.onSelect then
                opts.onSelect(self.elementID, false)
            end
        end)
        frame:SetScript("OnDragStart", function(self)
            if IsSpacePanActive(opts) then
                self.endpointDragging = false
                self:SetScript("OnUpdate", nil)
                return
            end
            self.endpointDragging = true
            if opts.onSelect then
                opts.onSelect(self.elementID, false)
            end
            self.dragStartCursorX, self.dragStartCursorY = CursorToBoardPoint(self:GetParent(), board, opts.viewport)
            self.dragStartPointX = point.x
            self.dragStartPointY = point.y
            self:SetScript("OnUpdate", function()
                local nextX, nextY = CursorToBoardPoint(self:GetParent(), board, opts.viewport)
                if IsShiftKeyDown and IsShiftKeyDown() then
                    local dx, dy = ConstrainDelta45(nextX - (self.dragStartCursorX or nextX), nextY - (self.dragStartCursorY or nextY))
                    nextX = (self.dragStartPointX or nextX) + dx
                    nextY = (self.dragStartPointY or nextY) + dy
                end
                if opts.onSegmentEndpointDrag then
                    opts.onSegmentEndpointDrag(self.elementID, self.endpoint, nextX, nextY, true)
                end
            end)
        end)
        frame:SetScript("OnDragStop", function(self)
            if IsSpacePanActive(opts) or not self.endpointDragging then
                self.endpointDragging = false
                self:SetScript("OnUpdate", nil)
                return
            end
            self.endpointDragging = false
            self:SetScript("OnUpdate", nil)
            local nextX, nextY = CursorToBoardPoint(self:GetParent(), board, opts.viewport)
            if IsShiftKeyDown and IsShiftKeyDown() then
                local dx, dy = ConstrainDelta45(nextX - (self.dragStartCursorX or nextX), nextY - (self.dragStartCursorY or nextY))
                nextX = (self.dragStartPointX or nextX) + dx
                nextY = (self.dragStartPointY or nextY) + dy
            end
            if opts.onSegmentEndpointDrag then
                opts.onSegmentEndpointDrag(self.elementID, self.endpoint, nextX, nextY, false)
            end
        end)
        frame:Show()
    end
    return handleIndex
end

function Canvas:RegisterRotationHandle(board, element, handleIndex, opts, rank)
    if not (opts and opts.mode == "edit" and opts.selectedIDs and opts.selectedIDs[element.id]) then
        return handleIndex
    end
    if IsHitLocked(board, element) then
        return handleIndex
    end
    local params = element.params or {}
    if element.type == "shape" and (params.shapeKind == "line" or params.shapeKind == "arrow") then
        return handleIndex
    end
    local px, py, width, height = GetHitBox(self.parent, board, element, opts)
    local geometry = T.VisualBoardData:ResolveElementGeometryAtSlide(element, opts.currentSlideIndex, board)
    local frame = Acquire(self.rotationFrames, handleIndex + 1, function()
        local hit = CreateFrame("Button", nil, self.parent)
        hit:RegisterForClicks("LeftButtonUp")
        hit:RegisterForDrag("LeftButton")
        local tex = hit:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(hit)
        tex:SetTexture(WHITE_TEXTURE)
        hit.tex = tex
        return hit
    end)
    handleIndex = handleIndex + 1
    frame:SetFrameLevel(self.parent:GetFrameLevel() + 2200 + (tonumber(rank) or 0))
    frame.elementID = element.id
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", self.parent, "TOPLEFT", px, -(py - height / 2 - 26))
    frame:SetSize(16, 16)
    if frame.tex then
        frame.tex:SetVertexColor(1.0, 0.82, 0.18, 1)
    end
    local function angleAtCursor(self)
        local bx, by = CursorToBoardPoint(self:GetParent(), board, opts.viewport)
        local dx = bx - (tonumber(geometry.x) or 0)
        local dy = by - (tonumber(geometry.y) or 0)
        local angle = math.deg(Atan2(dy, dx)) + 90
        if IsShiftKeyDown and IsShiftKeyDown() then
            angle = math.floor(angle / 15 + 0.5) * 15
        end
        return angle % 360
    end
    frame:SetScript("OnClick", function(self)
        if IsSpacePanActive(opts) then
            return
        end
        if opts.onSelect then opts.onSelect(self.elementID, false) end
    end)
    frame:SetScript("OnDragStart", function(self)
        if IsSpacePanActive(opts) then
            self.rotating = false
            self:SetScript("OnUpdate", nil)
            return
        end
        self.rotating = true
        if opts.onSelect then opts.onSelect(self.elementID, false) end
        self:SetScript("OnUpdate", function()
            if opts.onRotationDrag then
                opts.onRotationDrag(self.elementID, angleAtCursor(self), true)
            end
        end)
    end)
    frame:SetScript("OnDragStop", function(self)
        if IsSpacePanActive(opts) or not self.rotating then
            self.rotating = false
            self:SetScript("OnUpdate", nil)
            return
        end
        self.rotating = false
        self:SetScript("OnUpdate", nil)
        if opts.onRotationDrag then
            opts.onRotationDrag(self.elementID, angleAtCursor(self), false)
        end
    end)
    frame:Show()
    return handleIndex
end

-- 取景框两个常驻拖拽手柄（lazy 建一次）：body=左上角"预览区"标签那一小条（移动手柄）、corner=右下角缩放。
-- body 不再盖满整框 → 框内部留空，鼠标点内部穿透去选画布元素（不误触平移取景框）。
-- 独立一层，frame level 居于背景 catcher(+5) 之上、元素命中帧(+20)之下 → 点元素时元素帧优先、不误移取景框；
-- body 只 RegisterForDrag 不接管单击 → 标签上单击仍穿到 catcher（不误选/不异常取消选择）。
function Canvas:EnsurePreviewHandles()
    if not self.previewBodyHit then
        -- 预览手柄抬到 +2000 区：高于所有元素命中帧（+1000+rank），避免被高 rank 元素容器/命中帧盖住，标签可抓取平移。
        local body = CreateFrame("Frame", nil, self.parent)
        body:SetFrameLevel(self.parent:GetFrameLevel() + 2000)
        body:EnableMouse(true)
        body:RegisterForDrag("LeftButton")
        body:Hide()
        self.previewBodyHit = body
    end
    if not self.previewCornerHit then
        -- 右下角缩放手柄：与 body 同 +2000 区（再 +1 略高），高于所有元素命中帧，保证小角标可抓取。
        local corner = CreateFrame("Frame", nil, self.parent)
        corner:SetFrameLevel(self.parent:GetFrameLevel() + 2001)
        corner:SetSize(14, 14)
        corner:EnableMouse(true)
        corner:RegisterForDrag("LeftButton")
        -- 角标可见性：青色实心小方块（与取景框同色），让用户一眼看出右下角能拖动缩放。
        -- 不用半透明 grabber 贴图（用户反映看不见），改纯色 WHITE8X8 + 顶点上色为不透明青。
        local grab = corner:CreateTexture(nil, "OVERLAY")
        grab:SetAllPoints(corner)
        grab:SetTexture(WHITE_TEXTURE)
        grab:SetVertexColor(0.2, 0.85, 0.95, 1)
        corner.grab = grab
        corner:Hide()
        self.previewCornerHit = corner
    end
    if not self.previewLabel then
        -- 取景框左上角"预览区"标签：提升可发现性，让用户知道这是可框选的预览范围。
        local label = self.parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetTextColor(0.2, 0.85, 0.95, 1)
        label:Hide()
        self.previewLabel = label
    end
    return self.previewBodyHit, self.previewCornerHit
end

-- 编辑态取景框（previewRect）：仿 DrawArtboardBorder，经 BoardToScreen 把 previewRect 逻辑矩形换算为屏幕四角，
-- 画 4 条青线（独立 previewLines 池）+ 左上角"预览区"标签做移动手柄 + 右下角缩放手柄。仅 opts.showPreviewRect 为真时绘制（play/preview 不画）。
-- 写入唯一经回调 opts.onPreviewRectDrag(x,y,w,h,transient) → editor → Data:SetPreviewRect（canvas 只读 previewRect、不写）。
function Canvas:DrawPreviewRect(board, viewport, opts)
    if not (opts and opts.showPreviewRect and opts.mode == "edit") then
        self:HideUnused(self.previewLines, 0)
        if self.previewBodyHit then self.previewBodyHit:Hide() end
        if self.previewCornerHit then self.previewCornerHit:Hide() end
        if self.previewLabel then self.previewLabel:Hide() end
        return
    end
    local pr = type(board.previewRect) == "table" and board.previewRect or {}
    local px0 = tonumber(pr.x) or 0
    local py0 = tonumber(pr.y) or 0
    local pw = tonumber(pr.w) or 0
    local ph = tonumber(pr.h) or 0
    local lx, ty = self:BoardToScreen(board, viewport, px0, py0)
    local rx, by = self:BoardToScreen(board, viewport, px0 + pw, py0 + ph)

    -- 可视框屏幕空间内缩 3px：逻辑 previewRect 不变，仅把 4 条青线画在逻辑框内 3px，
    -- 让取景框与 DrawArtboardBorder 的 artboard 边框明显错开（不再逐像素重合），且永远落在 artboard 边框之内，
    -- 不被 FitViewport 缩放 + canvasFrame:SetClipsChildren 的边缘裁切吃掉。
    local ilx, ity = lx + 3, ty + 3
    local irx, iby = rx - 3, by - 3

    local used = 0
    local function drawSegment(x1, y1, x2, y2)
        local line = Acquire(self.previewLines, used + 1, function()
            return self.parent:CreateLine(nil, "OVERLAY")
        end)
        used = used + 1
        line:ClearAllPoints()
        line:SetStartPoint("TOPLEFT", self.parent, x1, -y1)
        line:SetEndPoint("TOPLEFT", self.parent, x2, -y2)
        line:SetThickness(3)
        -- 复位顶点色为不透明白：防 HideUnused 残留的 alpha=0 顶点色把线弄透明（belt-and-suspenders）。
        line:SetVertexColor(1, 1, 1, 1)
        line:SetColorTexture(0.2, 0.85, 0.95, 0.95)
    end
    drawSegment(ilx, ity, irx, ity) -- 上
    drawSegment(irx, ity, irx, iby) -- 右
    drawSegment(irx, iby, ilx, iby) -- 下
    drawSegment(ilx, iby, ilx, ity) -- 左
    self:HideUnused(self.previewLines, used)

    local body, corner = self:EnsurePreviewHandles()
    local parent = self.parent
    local onDrag = opts.onPreviewRectDrag

    -- 左上角"预览区"标签：贴框内左上，既是可发现性提示、又是唯一移动手柄（拖它平移取景框）。
    -- 先建标签并定位，body 命中区随后贴合标签尺寸（不再盖满整框）。
    local label = self.previewLabel
    if label then
        label:SetText(L["VISUAL_BOARD_PREVIEW_REGION"] or "预览区")
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", lx + 3, -(ty + 3))
        label:Show()
    end

    -- body：移动手柄=仅覆盖左上角"预览区"标签那一小条，不再整框捕获拖拽。
    -- 框内部留空 → 鼠标点内部穿透去选画布元素/取消选择，只有抓标签才平移取景框（不误触）。
    -- 拖拽中保持 w/h 不变，按"光标 - 框左上角"初始偏移平移。
    local labelW = label and math.max(1, label:GetStringWidth() + 6) or 48
    local labelH = label and math.max(1, label:GetStringHeight() + 6) or 16
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", parent, "TOPLEFT", lx, -ty)
    body:SetSize(labelW, labelH)
    body:Show()
    body:SetScript("OnDragStart", function(self)
        if IsSpacePanActive(opts) then
            self.previewDragging = false
            self:SetScript("OnUpdate", nil)
            return
        end
        self.previewDragging = true
        local cbx, cby = CursorToBoardPoint(parent, board, viewport)
        self.grabDX = cbx - px0
        self.grabDY = cby - py0
        self:SetScript("OnUpdate", function(self)
            local bx, byy = CursorToBoardPoint(parent, board, viewport)
            if onDrag then onDrag(bx - (self.grabDX or 0), byy - (self.grabDY or 0), pw, ph, true) end
        end)
    end)
    body:SetScript("OnDragStop", function(self)
        if IsSpacePanActive(opts) or not self.previewDragging then
            self.previewDragging = false
            self:SetScript("OnUpdate", nil)
            return
        end
        self.previewDragging = false
        self:SetScript("OnUpdate", nil)
        local bx, byy = CursorToBoardPoint(parent, board, viewport)
        if onDrag then onDrag(bx - (self.grabDX or 0), byy - (self.grabDY or 0), pw, ph, false) end
    end)

    -- corner：右下角缩放。框左上角 (px0,py0) 固定，w/h = 光标 board 坐标 - 左上角。
    corner:ClearAllPoints()
    corner:SetPoint("CENTER", parent, "TOPLEFT", rx, -by)
    corner:Show()
    local function cornerApply(transient)
        local bx, byy = CursorToBoardPoint(parent, board, viewport)
        if onDrag then onDrag(px0, py0, bx - px0, byy - py0, transient) end
    end
    corner:SetScript("OnDragStart", function(self)
        if IsSpacePanActive(opts) then
            self.previewResizing = false
            self:SetScript("OnUpdate", nil)
            return
        end
        self.previewResizing = true
        self:SetScript("OnUpdate", function() cornerApply(true) end)
    end)
    corner:SetScript("OnDragStop", function(self)
        if IsSpacePanActive(opts) or not self.previewResizing then
            self.previewResizing = false
            self:SetScript("OnUpdate", nil)
            return
        end
        self.previewResizing = false
        self:SetScript("OnUpdate", nil)
        cornerApply(false)
    end)
end

-- 渲染入口（契约 §6.3）：renderState 取代旧 timeValue（play=overlay 算好 resolved；edit=canvas 解算当前帧）。
-- opts 携带 UI 会话态：viewport（坐标换算，§8.1）、personInfo（person 默认图标/名签解析）、mode、selectedIDs、edit 回调。
-- canvas 只做"给我位置我画"：位置/alpha/scale 全从 ResolveRenderEntry 取，坐标换算唯一经 BoardToScreen。
function Canvas:Render(board, renderState, opts)
    if type(board) ~= "table" then
        self:Clear()
        return
    end
    opts = opts or {}
    local viewport = opts.viewport
    local zoom = ReadViewport(viewport)
    local info = opts.personInfo

    local elements = {}
    for index, element in ipairs(board.elements or {}) do
        elements[#elements + 1] = { element = element, index = index }
    end
    table.sort(elements, function(a, b)
        local az = tonumber(a.element and a.element.z) or 0
        local bz = tonumber(b.element and b.element.z) or 0
        if az == bz then
            return a.index < b.index
        end
        return az < bz
    end)

    self:DrawBackground(board, viewport, opts)
    -- artboard 蓝灰外框仅编辑态画；预览/运行时(play=overlay)纯画布无外框。
    if renderState and renderState.mode == "edit" then
        self:DrawArtboardBorder(board, viewport)
    end

    local textureIndex, textIndex, lineIndex, hitIndex, shapeIndex, ringIndex, endpointIndex, rotationIndex = 0, 0, 0, 0, 0, 0, 0, 0
    -- rank：仅对【实际渲染】的元素从 1 递增，作为全局 z 名次（elements 已按 z 升序排好，rank 越大越靠上）。
    -- 每个渲染元素分一个容器 Frame，FrameLevel = parent +20+rank（容器带 +21..+21+N），region re-parent 进它 → z 名次落到层级。
    local baseLevel = self.parent:GetFrameLevel()
    local rank = 0
    for _, item in ipairs(elements) do
        local element = item.element
        local entry = nil
        if not IsRenderHidden(board, element) then
            entry = ResolveRenderEntry(board, element, renderState)
        end
        if entry == nil then
            -- 元素或其组 hidden，或本帧 morph 不出现：跳过渲染。
        else
            rank = rank + 1
            self._elemParent = self:AcquireElementFrame(rank, baseLevel + 20 + rank)
            local screenX, screenY = self:BoardToScreen(board, viewport, entry.x, entry.y)
            textureIndex = self:DrawSelectionBox(board, element, textureIndex, opts)
            local kind = element.type
            if kind == "person" then
                textureIndex, textIndex, ringIndex = self:DrawPerson(board, element, screenX, screenY, zoom, entry, info, textureIndex, textIndex, ringIndex)
            elseif kind == "text" then
                local p = element.params or {}
                textIndex = self:DrawStyledText(screenX, screenY, zoom, p.text, p, "CENTER", entry.alpha, textIndex)
            elseif kind == "shape" then
                shapeIndex, lineIndex = self:DrawShape(board, viewport, element, screenX, screenY, zoom, entry, shapeIndex, lineIndex)
            elseif kind == "marker" then
                textureIndex = self:DrawMarker(element, screenX, screenY, zoom, entry, textureIndex)
            elseif kind == "icon" then
                textureIndex = self:DrawIconElement(element, screenX, screenY, zoom, entry, textureIndex)
            end
            hitIndex = self:RegisterEditHit(board, element, hitIndex, opts, rank)
            endpointIndex = self:RegisterSegmentEndpointHandles(board, element, endpointIndex, opts, rank)
            rotationIndex = self:RegisterRotationHandle(board, element, rotationIndex, opts, rank)
        end
    end
    self._elemParent = nil
    self:HideUnused(self.textures, textureIndex)
    self:HideUnusedIconMasks(textureIndex)
    self:HideUnused(self.shapeTextures, shapeIndex)
    self:HideUnusedRings(ringIndex)
    self:HideUnused(self.fontStrings, textIndex)
    self:HideUnused(self.lines, lineIndex)
    self:HideUnusedHitFrames(hitIndex)
    self:HideUnusedEndpointFrames(endpointIndex)
    self:HideUnusedRotationFrames(rotationIndex)
    self:HideUnusedElementFrames(rank)

    -- 取景框叠在元素之上画，仅 edit + showPreviewRect 时显示（DrawPreviewRect 内部自判）。
    self:DrawPreviewRect(board, viewport, opts)

    self:UpdateBackgroundCatcher(opts)
end

-- 空白点击捕获（§6.2 onBackgroundClick）：仅 edit 模式启用；点空白处（未命中任何元素帧）→ 取消选择。
function Canvas:UpdateBackgroundCatcher(opts)
    local catcher = self.backgroundCatcher
    if not catcher then
        return
    end
    if opts.mode == "edit" and opts.onBackgroundClick then
        catcher:SetScript("OnClick", function()
            if IsSpacePanActive(opts) then
                return
            end
            opts.onBackgroundClick()
        end)
        -- 双击空白处 = fit-to-view 重置（§8.2）：catcher 已 RegisterForClicks("LeftButtonUp")，OnDoubleClick 即可生效。
        catcher:SetScript("OnDoubleClick", function(_, button)
            if IsSpacePanActive(opts) then
                return
            end
            if button == "LeftButton" and opts.onBackgroundDoubleClick then
                opts.onBackgroundDoubleClick()
            end
        end)
        catcher:Show()
    else
        catcher:SetScript("OnClick", nil)
        catcher:SetScript("OnDoubleClick", nil)
        catcher:Hide()
    end
end

function Canvas:Clear()
    self:HideUnused(self.backgrounds, 0)
    self:HideUnused(self.gridLines, 0)
    self:HideUnused(self.artboardLines, 0)
    self:HideUnused(self.textures, 0)
    self:HideUnusedIconMasks(0)
    self:HideUnused(self.shapeTextures, 0)
    self:HideUnusedRings(0)
    self:HideUnused(self.fontStrings, 0)
    self:HideUnused(self.lines, 0)
    self:HideUnused(self.alignLines, 0)
    self:HideUnused(self.previewLines, 0)
    self:HideUnusedHitFrames(0)
    self:HideUnusedEndpointFrames(0)
    self:HideUnusedRotationFrames(0)
    self:HideUnusedElementFrames(0)
    if self.previewBodyHit then
        self.previewBodyHit:SetScript("OnUpdate", nil)
        self.previewBodyHit:SetScript("OnDragStart", nil)
        self.previewBodyHit:SetScript("OnDragStop", nil)
        self.previewBodyHit:Hide()
    end
    if self.previewCornerHit then
        self.previewCornerHit:SetScript("OnUpdate", nil)
        self.previewCornerHit:SetScript("OnDragStart", nil)
        self.previewCornerHit:SetScript("OnDragStop", nil)
        self.previewCornerHit:Hide()
    end
    if self.backgroundCatcher then
        self.backgroundCatcher:SetScript("OnClick", nil)
        self.backgroundCatcher:SetScript("OnDoubleClick", nil)
        self.backgroundCatcher:Hide()
    end
end

end
