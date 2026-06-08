local T, C, L = unpack(select(2, ...))
do

local Data = {}
T.VisualBoardData = Data

local SCHEMA_VERSION = 2
local DEFAULT_ARTBOARD_W = 1600
local DEFAULT_ARTBOARD_H = 900
local DEFAULT_HOLD_TIME = 2.0
local DEFAULT_MORPH_TIME = 1.0
local PREVIEW_RECT_MIN = 40
local EXPORT_PREFIX = "STT-VBOARD"
local EXPORT_VERSION = 2
local BOSS_EXPORT_PREFIX = "STT-VBOARD-BOSS"
local BOSS_EXPORT_VERSION = 1
local COORD_VERSION = 2
local EnsureElementShape

Data.History = {
    past = {},
    future = {},
    limit = 100,
}
Data._transientSnapshots = {}

local function Trim(text)
    local value = tostring(text or "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function NormalizeBossKeyText(text)
    local value = Trim(text)
    if value == "" then
        return nil
    end
    if T and T.NormalizeSemanticBossKeyText then
        return T.NormalizeSemanticBossKeyText(value)
    end
    return value
end

local function CountBoards(db)
    local count = 0
    for key, value in pairs(db or {}) do
        if type(key) == "string" and key:sub(1, 1) ~= "_" and type(value) == "table" then
            count = count + 1
        end
    end
    return count
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, child in pairs(value) do
        out[DeepCopy(key)] = DeepCopy(child)
    end
    return out
end

-- 部分深合并：把 src 的键写入 dst（table 对 table 递归一层，叶子直接覆写）。
-- 只覆写 src 给出的键，dst 中 src 未给的键保留。用于元素 params 的部分更新（含 person 子件）。
local function DeepMergeInto(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            DeepMergeInto(dst[key], value)
        else
            dst[key] = value
        end
    end
    return dst
end

local function Clamp(value, minValue, maxValue)
    local numberValue = tonumber(value) or minValue
    if numberValue < minValue then return minValue end
    if numberValue > maxValue then return maxValue end
    return numberValue
end

local function RecomputeBoard(DataRef, board)
    if type(board) ~= "table" then
        return
    end
    board.hash = DataRef:ComputeBoardHash(board)
    DataRef:TouchBoard(board)
end

local function FindElementIndex(board, elementID)
    local targetID = Trim(elementID)
    if targetID == "" then
        return nil
    end
    for index, element in ipairs(board.elements or {}) do
        if type(element) == "table" and element.id == targetID then
            return index, element
        end
    end
    return nil
end

local function ReplaceElement(board, elementID, snapshot)
    local index = FindElementIndex(board, elementID)
    if not index then
        return false
    end
    board.elements[index] = EnsureElementShape(DeepCopy(snapshot), index, board)
    return true
end

local function InsertElement(board, snapshot, index)
    if type(board.elements) ~= "table" then
        board.elements = {}
    end
    local insertIndex = math.max(1, math.min(#board.elements + 1, tonumber(index) or (#board.elements + 1)))
    table.insert(board.elements, insertIndex, EnsureElementShape(DeepCopy(snapshot), insertIndex, board))
    return true
end

local function RemoveElement(board, elementID)
    local index = FindElementIndex(board, elementID)
    if not index then
        return nil
    end
    return table.remove(board.elements, index), index
end

local function NormalizePositiveNumber(value, fallback)
    local numberValue = tonumber(value)
    if not numberValue or numberValue <= 0 then
        return fallback
    end
    return numberValue
end

-- v2 颜色单一权威：hex 字符串（"RRGGBB"，6 位大写）。
-- 非法/缺省回落到 fallback（同为 hex）。禁止 RGBA 数组与 hex 并存。
local function NormalizeHexColor(value, fallback)
    local hex = tostring(value or ""):gsub("^#", ""):upper()
    if hex:match("^%x%x%x%x%x%x$") then
        return hex
    end
    return fallback
end

-- 0-1 不透明度规范化。
local function NormalizeAlpha(value, fallback)
    local alpha = tonumber(value)
    if not alpha then
        return fallback
    end
    if alpha < 0 then return 0 end
    if alpha > 1 then return 1 end
    return alpha
end

local function NormalizeSpellID(value)
    local spellID = tonumber(value)
    if spellID and spellID > 0 then
        return math.floor(spellID + 0.5)
    end
    return nil
end

local function NormalizeJustifyH(value)
    local justify = tostring(value or "CENTER"):upper()
    if justify == "LEFT" or justify == "CENTER" or justify == "RIGHT" then
        return justify
    end
    return "CENTER"
end

local function NormalizeIconParams(icon, fallbackSize, element)
    if type(icon) ~= "table" then
        return
    end
    icon.size = NormalizePositiveNumber(icon.size, fallbackSize or 54)
    local defaultShape = element and element.type == "icon" and "circle" or "square"
    icon.shape = tostring(icon.shape or defaultShape):lower()
    if icon.shape ~= "circle" and icon.shape ~= "square" then
        icon.shape = defaultShape
    end
    icon.encounterID = NormalizePositiveNumber(icon.encounterID, nil)
    icon.encounterIcon = NormalizePositiveNumber(icon.encounterIcon, nil)
    icon.spellID = NormalizeSpellID(icon.spellID)
    if icon.encounterID or icon.encounterIcon then
        icon.spellID = nil
        icon.texture = nil
        icon.atlas = nil
    elseif icon.spellID then
        icon.texture = nil
        icon.atlas = nil
    else
        if type(icon.texture) == "number" then
            -- fileID 直接保留
        else
            local tex = Trim(icon.texture)
            icon.texture = tex ~= "" and tex or nil
        end
        local atlas = Trim(icon.atlas)
        icon.atlas = atlas ~= "" and atlas or nil
        if icon.texture ~= nil and icon.atlas ~= nil then
            if T and T.debug then
                T.debug(string.format("[VisualBoard] IconConflict element=%s 同时存在 texture 与 atlas，清空 atlas", tostring(element and element.id)))
            end
            icon.atlas = nil
        end
    end
    icon.borderSize = math.max(0, tonumber(icon.borderSize) or 0)
    icon.borderColor = NormalizeHexColor(icon.borderColor, "000000")
end

-- v2：person.text / type=text 复用 indicator_text.style 字段集（fontSize/fontFace/color/bold/outline/outlineColor/shadow/scale）。
-- 规范化一份 indicator_text 风格的文本样式表（就地修改 t）。
local function NormalizeTextStyle(t)
    if type(t) ~= "table" then
        return
    end
    t.fontSize = NormalizePositiveNumber(t.fontSize, 19)
    t.fontFace = tostring(t.fontFace or "default")
    if t.fontFace == "" then
        t.fontFace = "default"
    end
    t.color = NormalizeHexColor(t.color, "EFFFFF")
    t.bold = t.bold == true
    t.outline = t.outline ~= false
    t.outlineColor = NormalizeHexColor(t.outlineColor, "000000")
    t.shadow = t.shadow ~= false
    t.scale = NormalizePositiveNumber(t.scale, 1)
    t.justifyH = NormalizeJustifyH(t.justifyH)
    t.width = NormalizePositiveNumber(t.width, nil)
end

-- person 三子件规范化（缺子件补默认，enabled 布尔化）。
local function NormalizePersonParams(params, element)
    if type(params.icon) ~= "table" then params.icon = {} end
    local icon = params.icon
    NormalizeIconParams(icon, 40, element)

    if type(params.circle) ~= "table" then params.circle = {} end
    local circle = params.circle
    circle.radius = NormalizePositiveNumber(circle.radius, 58)
    circle.color = NormalizeHexColor(circle.color, "33CC66")
    circle.alpha = NormalizeAlpha(circle.alpha, 0.5)
    circle.shapeStyle = circle.shapeStyle == "ring" and "ring" or "solid"
    circle.ringThickness = circle.shapeStyle == "ring" and NormalizePositiveNumber(circle.ringThickness, 6) or nil
    circle.enabled = circle.enabled ~= false

    if type(params.text) ~= "table" then params.text = {} end
    local text = params.text
    local pos = tostring(text.position or "top")
    if pos ~= "top" and pos ~= "bottom" and pos ~= "left" and pos ~= "right" then
        pos = "top"
    end
    text.position = pos
    text.dx = tonumber(text.dx) or 0
    text.dy = tonumber(text.dy) or 0
    text.enabled = text.enabled ~= false
    NormalizeTextStyle(text)

    params.slotName = Trim(params.slotName)
    if type(params.highlightStyle) == "table" then
        local hl = params.highlightStyle
        -- scale 默认 1：本机高亮不放大，避免撑大分散圈误导真实半径。可自定义放大。
        hl.scale = NormalizePositiveNumber(hl.scale, 1)
        -- glow 语义 = 圆边缘亮环开关（不再是比圆还大的大光晕）；glowColor = 亮环色，缺省金。
        hl.glow = hl.glow ~= false
        hl.glowColor = NormalizeHexColor(hl.glowColor, "FFD200")
        hl.desaturateOthers = hl.desaturateOthers == true
    else
        params.highlightStyle = nil
    end
end

function EnsureElementShape(element, index, board)
    if type(element) ~= "table" then
        return nil
    end
    local kind = tostring(element.type or "")
    if kind ~= "person" and kind ~= "text" and kind ~= "shape" and kind ~= "marker" and kind ~= "icon" then
        return nil
    end

    element.id = Trim(element.id)
    if element.id == "" then
        element.id = "elem-" .. tostring(index or 1)
    end
    element.type = kind
    element.z = tonumber(element.z) or index or 0
    element.x = tonumber(element.x) or DEFAULT_ARTBOARD_W / 2
    element.y = tonumber(element.y) or DEFAULT_ARTBOARD_H / 2
    element.rotation = tonumber(element.rotation) or 0
    element.scale = NormalizePositiveNumber(element.scale, 1)
    element.name = Trim(element.name)
    if element.name == "" then
        element.name = nil
    end
    element.hidden = element.hidden == true
    element.locked = element.locked == true
    local groupID = Trim(element.groupID)
    if groupID ~= "" and type(board) == "table" and type(board.groups) == "table" and type(board.groups[groupID]) == "table" then
        element.groupID = groupID
    else
        element.groupID = nil
    end
    if type(element.params) ~= "table" then
        element.params = {}
    end
    local params = element.params

    if kind == "person" then
        element.end_x = nil
        element.end_y = nil
        NormalizePersonParams(params, element)
    elseif kind == "text" then
        element.end_x = nil
        element.end_y = nil
        params.text = Trim(params.text)
        if params.text == "" then
            params.text = "文字"
        end
        NormalizeTextStyle(params)
    elseif kind == "shape" then
        local shapeKind = tostring(params.shapeKind or "rect")
        if shapeKind ~= "rect" and shapeKind ~= "circle" and shapeKind ~= "line" and shapeKind ~= "arrow" then
            shapeKind = "rect"
        end
        params.shapeKind = shapeKind
        params.color = NormalizeHexColor(params.color, "FFFFFF")
        params.alpha = NormalizeAlpha(params.alpha, 0.85)
        if shapeKind == "rect" then
            element.end_x = nil
            element.end_y = nil
            params.w = NormalizePositiveNumber(params.w, 200)
            params.h = NormalizePositiveNumber(params.h, 120)
        elseif shapeKind == "circle" then
            element.end_x = nil
            element.end_y = nil
            params.radius = NormalizePositiveNumber(params.radius, 60)
            params.shapeStyle = params.shapeStyle == "ring" and "ring" or "solid"
            params.ringThickness = params.shapeStyle == "ring" and NormalizePositiveNumber(params.ringThickness, 6) or nil
        else -- line / arrow
            element.end_x = tonumber(element.end_x) or (element.x + 160)
            element.end_y = tonumber(element.end_y) or element.y
            params.thickness = NormalizePositiveNumber(params.thickness, 3)
            params.arrowSize = NormalizePositiveNumber(params.arrowSize, 22)
        end
    elseif kind == "marker" then
        element.end_x = nil
        element.end_y = nil
        local markerIndex = tonumber(params.markerIndex) or 1
        params.markerIndex = math.max(1, math.min(8, markerIndex))
        params.size = NormalizePositiveNumber(params.size, 54)
    elseif kind == "icon" then
        element.end_x = nil
        element.end_y = nil
        NormalizeIconParams(params, 54, element)
    end
    return element
end

local function EnsureBoardShape(board, id)
    if type(board) ~= "table" then
        return nil
    end

    board.id = Trim(board.id or id)
    if board.id == "" then
        return nil
    end

    board.syncKey = Trim(board.syncKey)
    if board.syncKey == "" then
        board.syncKey = board.id
    end

    board.name = Trim(board.name)
    if board.name == "" then
        board.name = board.id
    end

    board.version = NormalizePositiveNumber(board.version, 1)
    board.created = tonumber(board.created) or time()
    board.modified = tonumber(board.modified) or board.created
    board.builtin = board.builtin == true
    board.received = board.received == true
    if type(board.bg) == "table" and type(board.bg.texture) == "string" and board.bg.texture ~= "" then
        board.bg.type = tostring(board.bg.type or "texture")
        board.bg.name = Trim(board.bg.name)
        board.bg.bossKeyText = Trim(board.bg.bossKeyText)
        board.bg.encounterID = tonumber(board.bg.encounterID)
    else
        board.bg = nil
    end
    board.bossKeyText = Trim(board.bossKeyText)
    board.encounterID = tonumber(board.encounterID)

    if type(board.artboard) ~= "table" then
        board.artboard = {}
    end
    board.artboard.w = NormalizePositiveNumber(board.artboard.w, DEFAULT_ARTBOARD_W)
    board.artboard.h = NormalizePositiveNumber(board.artboard.h, DEFAULT_ARTBOARD_H)

    -- previewRect：运行时 HUD 取景框（画板逻辑坐标）。默认=整 artboard（行为不变）。
    -- 钳到 artboard 内：x/y ∈ [0, artboard]，w/h 至少 PREVIEW_RECT_MIN 且不越出右/下边界。
    if type(board.previewRect) ~= "table" then
        board.previewRect = {}
    end
    local pr = board.previewRect
    local aw, ah = board.artboard.w, board.artboard.h
    pr.x = math.max(0, math.min(aw, tonumber(pr.x) or 0))
    pr.y = math.max(0, math.min(ah, tonumber(pr.y) or 0))
    pr.w = NormalizePositiveNumber(pr.w, aw)
    pr.h = NormalizePositiveNumber(pr.h, ah)
    pr.w = math.max(PREVIEW_RECT_MIN, math.min(pr.w, aw - pr.x))
    pr.h = math.max(PREVIEW_RECT_MIN, math.min(pr.h, ah - pr.y))

    if type(board.groups) ~= "table" then
        board.groups = {}
    end
    for groupID, group in pairs(board.groups) do
        if type(group) ~= "table" then
            board.groups[groupID] = nil
        else
            group.id = Trim(group.id or groupID)
            if group.id == "" or group.id ~= groupID then
                board.groups[groupID] = nil
            else
                group.name = Trim(group.name)
                if group.name == "" then
                    group.name = group.id
                end
                group.hidden = group.hidden == true
                group.locked = group.locked == true
            end
        end
    end

    if type(board.elements) ~= "table" then
        board.elements = {}
    end
    -- v2：只保留 person/text/shape/marker/icon；废弃 type（slot/circle/square/line/arrow/path/background）由 EnsureElementShape 返回 nil 而被剔除。
    for index = #board.elements, 1, -1 do
        local element = EnsureElementShape(board.elements[index], index, board)
        if not element then
            table.remove(board.elements, index)
        else
            board.elements[index] = element
        end
    end

    local groupHasMember = {}
    for _, element in ipairs(board.elements) do
        if element.groupID then
            groupHasMember[element.groupID] = true
        end
    end
    for groupID in pairs(board.groups) do
        if not groupHasMember[groupID] then
            board.groups[groupID] = nil
        end
    end
    -- 建立 elementID 存在性索引，供 slide override 剔除悬空引用用。
    local elementExists = {}
    for _, element in ipairs(board.elements) do
        elementExists[element.id] = true
    end

    board._coordVersion = COORD_VERSION
    board._nextElementID = NormalizePositiveNumber(board._nextElementID, #board.elements + 1)
    board._nextGroupID = NormalizePositiveNumber(board._nextGroupID, 1)

    -- slides：PPT 帧有序数组，至少 1 帧；override 白名单裁剪 + 悬空 elementID 剔除（§2.3/§2.4）。
    if type(board.slides) ~= "table" then
        board.slides = {}
    end
    if #board.slides == 0 then
        board.slides[1] = { id = "slide-1", name = "1", holdTime = DEFAULT_HOLD_TIME, morphFromPrev = DEFAULT_MORPH_TIME, overrides = {} }
    end
    for index, slide in ipairs(board.slides) do
        if type(slide) ~= "table" then
            slide = {}
            board.slides[index] = slide
        end
        slide.id = Trim(slide.id)
        if slide.id == "" then
            slide.id = "slide-" .. tostring(index)
        end
        slide.name = Trim(slide.name)
        if slide.name == "" then
            slide.name = tostring(index)
        end
        slide.holdTime = NormalizePositiveNumber(slide.holdTime, DEFAULT_HOLD_TIME)
        slide.morphFromPrev = NormalizePositiveNumber(slide.morphFromPrev, DEFAULT_MORPH_TIME)
        if type(slide.overrides) ~= "table" then
            slide.overrides = {}
        end
        for elementID, override in pairs(slide.overrides) do
            if type(override) ~= "table" or not elementExists[elementID] then
                slide.overrides[elementID] = nil
            else
                local clean = {}
                if override.x ~= nil then clean.x = tonumber(override.x) end
                if override.y ~= nil then clean.y = tonumber(override.y) end
                if override.hidden ~= nil then clean.hidden = override.hidden == true end
                if override.scale ~= nil then clean.scale = NormalizePositiveNumber(override.scale, nil) end
                if override.rotation ~= nil then clean.rotation = tonumber(override.rotation) end
                if next(clean) == nil then
                    slide.overrides[elementID] = nil
                else
                    slide.overrides[elementID] = clean
                end
            end
        end
    end
    board._nextSlideID = NormalizePositiveNumber(board._nextSlideID, #board.slides + 1)

    return board
end

function Data:EnsureDB()
    if type(STT_VisualBoardsDB) ~= "table" then
        STT_VisualBoardsDB = {}
    end

    STT_VisualBoardsDB._schemaVersion = SCHEMA_VERSION
    STT_VisualBoardsDB._nextID = NormalizePositiveNumber(STT_VisualBoardsDB._nextID, 1)

    for key, board in pairs(STT_VisualBoardsDB) do
        if type(key) == "string" and key:sub(1, 1) ~= "_" then
            local normalized = EnsureBoardShape(board, key)
            if normalized then
                STT_VisualBoardsDB[normalized.id] = normalized
                if normalized.id ~= key then
                    STT_VisualBoardsDB[key] = nil
                end
            else
                STT_VisualBoardsDB[key] = nil
            end
        end
    end

    return STT_VisualBoardsDB
end

function Data:GetAllBoards()
    local db = self:EnsureDB()
    local boards = {}
    for key, board in pairs(db) do
        if type(key) == "string" and key:sub(1, 1) ~= "_" and type(board) == "table" then
            boards[#boards + 1] = board
        end
    end
    table.sort(boards, function(a, b)
        if (a.builtin == true) ~= (b.builtin == true) then
            return a.builtin ~= true
        end
        return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
    end)
    return boards
end

function Data:GetBoard(id)
    local boardID = Trim(id)
    if boardID == "" then
        return nil
    end
    return self:EnsureDB()[boardID]
end

-- 按【画板名】解析 token 引用：返回首个同名画板，无则 nil。
-- 复用 GetAllBoards 作为遍历权威（已过滤 _nextID/_viewport 等 meta 键）。
function Data:ResolveBoardRef(ref)
    return self:ResolveBoardRefForBoss(ref, nil)
end

function Data:ResolveBoardRefForBoss(ref, bossKeyText)
    local name = Trim(ref)
    if name == "" then
        return nil
    end
    local targetBossKey = NormalizeBossKeyText(bossKeyText)
    if targetBossKey then
        local matchedForBoss = nil
        for _, board in ipairs(self:GetAllBoards()) do
            if Trim(board.name) == name and NormalizeBossKeyText(board.bossKeyText) == targetBossKey then
                if matchedForBoss == nil then
                    matchedForBoss = board
                elseif T and T.debug then
                    T.debug(string.format("[VisualBoard] BoardRefDuplicate boss=%s name=%s 取首个 id=%s", tostring(targetBossKey), tostring(name), tostring(matchedForBoss.id)))
                end
            end
        end
        if matchedForBoss then
            return matchedForBoss
        end
    end
    local matched = nil
    for _, board in ipairs(self:GetAllBoards()) do
        if Trim(board.name) == name then
            if matched == nil then
                matched = board
            elseif T and T.debug then
                T.debug(string.format("[VisualBoard] BoardRefDuplicate name=%s 取首个 id=%s", tostring(name), tostring(matched.id)))
            end
        end
    end
    return matched
end

T.RegisterColdFile("visualBoard.editorLoaded", function()

function Data:CreateBoard(name)
    local db = self:EnsureDB()
    local seq = NormalizePositiveNumber(db._nextID, 1)
    local id
    repeat
        id = "board-" .. tostring(seq)
        seq = seq + 1
    until db[id] == nil
    db._nextID = seq

    local now = time()
    local defaultBg, bossKey, bossKeyText = nil, nil, nil
    if T.VisualBoardBackgrounds and T.VisualBoardBackgrounds.ResolveDefaultForCurrentBoss then
        defaultBg, bossKey, bossKeyText = T.VisualBoardBackgrounds:ResolveDefaultForCurrentBoss()
    end
    local board = EnsureBoardShape({
        id = id,
        name = Trim(name) ~= "" and Trim(name) or (L["VISUAL_BOARD_NEW_NAME"] or "未命名画板"),
        version = 1,
        builtin = false,
        created = now,
        modified = now,
        artboard = { w = DEFAULT_ARTBOARD_W, h = DEFAULT_ARTBOARD_H },
        bg = defaultBg,
        bossKeyText = bossKeyText,
        encounterID = type(bossKey) == "table" and tonumber(bossKey.encounterID) or nil,
        slides = { { id = "slide-1", name = "1", holdTime = DEFAULT_HOLD_TIME, morphFromPrev = DEFAULT_MORPH_TIME, overrides = {} } },
        elements = {},
    }, id)

    db[id] = board
    if T and T.debug then
        T.debug(string.format("[VisualBoard] BoardCreated id=%s name=%s", tostring(id), tostring(board.name)))
    end
    return board
end

function Data:TouchBoard(board)
    if type(board) ~= "table" then
        return
    end
    board.modified = time()
    board.version = NormalizePositiveNumber(board.version, 1)
end

function Data:ClearHistory()
    self.History.past = {}
    self.History.future = {}
    self._transientSnapshots = {}
end

function Data:CanUndo()
    return #(self.History and self.History.past or {}) > 0
end

function Data:CanRedo()
    return #(self.History and self.History.future or {}) > 0
end

function Data:DoCommand(cmd)
    if type(cmd) ~= "table" or type(cmd.do_) ~= "function" or type(cmd.undo) ~= "function" then
        return false
    end
    cmd.do_()
    table.insert(self.History.past, cmd)
    if #self.History.past > self.History.limit then
        table.remove(self.History.past, 1)
    end
    self.History.future = {}
    if T and T.debug then
        T.debug(string.format("[VisualBoard] HistoryDo label=%s past=%d", tostring(cmd.label or ""), #self.History.past))
    end
    return true
end

function Data:Undo()
    local cmd = table.remove(self.History.past)
    if type(cmd) ~= "table" or type(cmd.undo) ~= "function" then
        return false
    end
    cmd.undo()
    table.insert(self.History.future, cmd)
    if T and T.debug then
        T.debug(string.format("[VisualBoard] HistoryUndo label=%s future=%d", tostring(cmd.label or ""), #self.History.future))
    end
    return true
end

function Data:Redo()
    local cmd = table.remove(self.History.future)
    if type(cmd) ~= "table" or type(cmd.do_) ~= "function" then
        return false
    end
    cmd.do_()
    table.insert(self.History.past, cmd)
    if T and T.debug then
        T.debug(string.format("[VisualBoard] HistoryRedo label=%s past=%d", tostring(cmd.label or ""), #self.History.past))
    end
    return true
end

local function ScaleElementPosition(element, scaleX, scaleY)
    if type(element) ~= "table" then
        return
    end
    element.x = (tonumber(element.x) or 0) * scaleX
    element.y = (tonumber(element.y) or 0) * scaleY
    if element.end_x then
        element.end_x = (tonumber(element.end_x) or 0) * scaleX
    end
    if element.end_y then
        element.end_y = (tonumber(element.end_y) or 0) * scaleY
    end
end

function Data:ApplyCurrentBackground(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local currentTexture = type(board.bg) == "table" and tostring(board.bg.texture or "") or ""
    if currentTexture ~= "" and not currentTexture:find("default_arena", 1, true) then
        return false
    end
    if not (T.VisualBoardBackgrounds and T.VisualBoardBackgrounds.ResolveDefaultForCurrentBoss) then
        return false
    end
    local bg, bossKey, bossKeyText = T.VisualBoardBackgrounds:ResolveDefaultForCurrentBoss()
    if type(bg) ~= "table" then
        return false
    end

    local artboard = type(board.artboard) == "table" and board.artboard or {}
    local oldW = tonumber(artboard.w) or DEFAULT_ARTBOARD_W
    local oldH = tonumber(artboard.h) or DEFAULT_ARTBOARD_H
    if oldW ~= DEFAULT_ARTBOARD_W or oldH ~= DEFAULT_ARTBOARD_H then
        local scaleX = DEFAULT_ARTBOARD_W / math.max(1, oldW)
        local scaleY = DEFAULT_ARTBOARD_H / math.max(1, oldH)
        for _, element in ipairs(board.elements or {}) do
            ScaleElementPosition(element, scaleX, scaleY)
        end
    end

    board.artboard = { w = DEFAULT_ARTBOARD_W, h = DEFAULT_ARTBOARD_H }
    board.bg = bg
    board.bossKeyText = bossKeyText
    board.encounterID = type(bossKey) == "table" and tonumber(bossKey.encounterID) or bg.encounterID
    board.hash = self:ComputeBoardHash(board)
    self:TouchBoard(board)
    if T and T.debug then
        T.debug(string.format("[VisualBoard] BackgroundApplied board=%s encounterID=%s", tostring(board.id), tostring(board.encounterID)))
    end
    return true
end

function Data:SetBackgroundEncounter(boardID, encounterID, bossKeyText)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    if not (T.VisualBoardBackgrounds and T.VisualBoardBackgrounds.ResolveForEncounter) then
        return false
    end
    local bg = T.VisualBoardBackgrounds:ResolveForEncounter(encounterID)
    if type(bg) ~= "table" then
        return false
    end

    local artboard = type(board.artboard) == "table" and board.artboard or {}
    local oldW = tonumber(artboard.w) or DEFAULT_ARTBOARD_W
    local oldH = tonumber(artboard.h) or DEFAULT_ARTBOARD_H
    if oldW ~= DEFAULT_ARTBOARD_W or oldH ~= DEFAULT_ARTBOARD_H then
        local scaleX = DEFAULT_ARTBOARD_W / math.max(1, oldW)
        local scaleY = DEFAULT_ARTBOARD_H / math.max(1, oldH)
        for _, element in ipairs(board.elements or {}) do
            ScaleElementPosition(element, scaleX, scaleY)
        end
    end

    board.artboard = { w = DEFAULT_ARTBOARD_W, h = DEFAULT_ARTBOARD_H }
    board.bg = bg
    board.encounterID = tonumber(encounterID)
    local bgInstanceType = tostring(bg.instanceType or "raid")
    local bgInstanceID = tonumber(bg.instanceID) or 0
    board.bossKeyText = Trim(bossKeyText) ~= "" and Trim(bossKeyText) or (T.BuildSemanticBossKeyText and T.BuildSemanticBossKeyText(bgInstanceType, bgInstanceID, encounterID) or tostring(bg.name or ""))
    board.hash = self:ComputeBoardHash(board)
    self:TouchBoard(board)
    if T and T.debug then
        T.debug(string.format("[VisualBoard] BackgroundSelected board=%s encounterID=%s name=%s", tostring(board.id), tostring(board.encounterID), tostring(bg.name)))
    end
    return true
end

function Data:SetBackgroundToCurrentBoss(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    if not (T.VisualBoardBackgrounds and T.VisualBoardBackgrounds.ResolveDefaultForCurrentBoss) then
        return false
    end
    local bg, bossKey, bossKeyText = T.VisualBoardBackgrounds:ResolveDefaultForCurrentBoss()
    if type(bg) ~= "table" then
        return false
    end
    local artboard = type(board.artboard) == "table" and board.artboard or {}
    local oldW = tonumber(artboard.w) or DEFAULT_ARTBOARD_W
    local oldH = tonumber(artboard.h) or DEFAULT_ARTBOARD_H
    if oldW ~= DEFAULT_ARTBOARD_W or oldH ~= DEFAULT_ARTBOARD_H then
        local scaleX = DEFAULT_ARTBOARD_W / math.max(1, oldW)
        local scaleY = DEFAULT_ARTBOARD_H / math.max(1, oldH)
        for _, element in ipairs(board.elements or {}) do
            ScaleElementPosition(element, scaleX, scaleY)
        end
    end
    board.artboard = { w = DEFAULT_ARTBOARD_W, h = DEFAULT_ARTBOARD_H }
    board.bg = bg
    board.bossKeyText = bossKeyText
    board.encounterID = type(bossKey) == "table" and tonumber(bossKey.encounterID) or bg.encounterID
    board.hash = self:ComputeBoardHash(board)
    self:TouchBoard(board)
    if T and T.debug then
        T.debug(string.format("[VisualBoard] BackgroundCurrentBoss board=%s encounterID=%s", tostring(board.id), tostring(board.encounterID)))
    end
    return true
end

end)

function Data:ComputeBoardHash(board)
    if type(board) ~= "table" then
        return "0"
    end
    local serializer = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local hashPayload = {
        artboard = board.artboard,
        previewRect = board.previewRect,
        bg = board.bg,
        elements = board.elements or {},
        groups = board.groups or {},
        slides = board.slides or {},
    }
    local payload = serializer and serializer:Serialize(hashPayload) or tostring(#(board.elements or {}))
    local deflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if deflate and deflate.Adler32 then
        return tostring(deflate:Adler32(payload))
    end
    return tostring(#payload)
end

-- 检测反序列化出的 board 是否为旧 schema（缺 slides 或含已废弃 element type）。
local function IsLegacyBoard(board)
    if type(board) ~= "table" then
        return false
    end
    if type(board.slides) ~= "table" then
        return true
    end
    for _, element in ipairs(board.elements or {}) do
        local t = type(element) == "table" and element.type or nil
        if t == "slot" or t == "square" or t == "path" or t == "circle" or t == "line" or t == "arrow" then
            return true
        end
    end
    return false
end

local function CopyBoardForExport(self, board)
    local copy = DeepCopy(board)
    copy.received = nil
    copy.receivedFrom = nil
    copy.hash = copy.hash or self:ComputeBoardHash(copy)
    return copy
end

function Data:CollectBossBoards(bossKeyText)
    local targetBossKey = NormalizeBossKeyText(bossKeyText)
    if not targetBossKey then
        return nil
    end
    local boards = {}
    for _, board in ipairs(self:GetAllBoards()) do
        if type(board) == "table" and NormalizeBossKeyText(board.bossKeyText) == targetBossKey then
            boards[#boards + 1] = CopyBoardForExport(self, board)
        end
    end
    table.sort(boards, function(a, b)
        return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
    end)
    return #boards > 0 and boards or nil
end

function Data:BuildBossBoardPackage(bossKeyText)
    local targetBossKey = NormalizeBossKeyText(bossKeyText)
    if not targetBossKey then
        return nil, "missing_boss"
    end
    local boards = self:CollectBossBoards(targetBossKey)
    if not boards then
        return nil, "empty"
    end
    local encounterID
    local bossName = ""
    for _, board in ipairs(boards) do
        encounterID = encounterID or tonumber(board.encounterID)
        if bossName == "" and type(board.bg) == "table" then
            bossName = tostring(board.bg.name or "")
        end
    end
    return {
        format = BOSS_EXPORT_PREFIX,
        version = BOSS_EXPORT_VERSION,
        bossKeyText = targetBossKey,
        encounterID = encounterID,
        bossName = bossName,
        exporterName = tostring(UnitName and (UnitName("player") or "") or ""),
        exporterVersion = tostring(T and T.Version or ""),
        exportTime = time and time() or 0,
        boards = boards,
    }
end

local function ComputeManifestHash(boards)
    local serializer = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local payload
    if serializer then
        payload = serializer:Serialize(boards or {})
    else
        local parts = {}
        for _, board in ipairs(boards or {}) do
            parts[#parts + 1] = tostring(board.syncKey or "") .. ":" .. tostring(board.hash or "")
        end
        payload = table.concat(parts, "|")
    end
    local deflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if deflate and deflate.Adler32 then
        return tostring(deflate:Adler32(payload))
    end
    return tostring(#payload)
end

local function BuildManifestEntry(self, board)
    local hash = board.hash or self:ComputeBoardHash(board)
    board.hash = hash
    return {
        syncKey = Trim(board.syncKey or board.id),
        name = tostring(board.name or ""),
        hash = hash,
    }
end

function Data:BuildBossBoardManifestPackage(bossKeyText)
    local targetBossKey = NormalizeBossKeyText(bossKeyText)
    if not targetBossKey then
        return nil, "missing_boss"
    end
    local boards = {}
    local manifestKeys = {}
    for _, board in ipairs(self:GetAllBoards()) do
        if type(board) == "table" and NormalizeBossKeyText(board.bossKeyText) == targetBossKey then
            local entry = BuildManifestEntry(self, board)
            boards[#boards + 1] = entry
            manifestKeys[#manifestKeys + 1] = entry.syncKey
        end
    end
    table.sort(boards, function(a, b)
        return tostring(a.syncKey or "") < tostring(b.syncKey or "")
    end)
    if #boards <= 0 then
        return nil, "empty"
    end
    return {
        format = BOSS_EXPORT_PREFIX,
        version = BOSS_EXPORT_VERSION,
        mode = "manifest",
        bossKeyText = targetBossKey,
        exporterName = tostring(UnitName and (UnitName("player") or "") or ""),
        exporterVersion = tostring(T and T.Version or ""),
        exportTime = time and time() or 0,
        manifestHash = ComputeManifestHash(boards),
        manifestKeys = manifestKeys,
        boards = boards,
    }
end

local function BuildKeySet(keys)
    local set = {}
    for _, key in ipairs(keys or {}) do
        local value = Trim(key)
        if value ~= "" then
            set[value] = true
        end
    end
    return set
end

function Data:BuildBossBoardDeltaPackage(bossKeyText, keys, manifestHash)
    local targetBossKey = NormalizeBossKeyText(bossKeyText)
    if not targetBossKey then
        return nil, "missing_boss"
    end
    local keySet = BuildKeySet(keys)
    if next(keySet) == nil then
        return nil, "empty"
    end
    local boards = {}
    for _, board in ipairs(self:GetAllBoards()) do
        local syncKey = Trim(board and (board.syncKey or board.id))
        if type(board) == "table" and keySet[syncKey] and NormalizeBossKeyText(board.bossKeyText) == targetBossKey then
            boards[#boards + 1] = CopyBoardForExport(self, board)
        end
    end
    table.sort(boards, function(a, b)
        return tostring(a.syncKey or a.id or "") < tostring(b.syncKey or b.id or "")
    end)
    if #boards <= 0 then
        return nil, "empty"
    end
    local manifestKeys = {}
    local manifestPackage = self:BuildBossBoardManifestPackage(targetBossKey)
    for _, entry in ipairs((manifestPackage and manifestPackage.boards) or {}) do
        manifestKeys[#manifestKeys + 1] = entry.syncKey
    end
    return {
        format = BOSS_EXPORT_PREFIX,
        version = BOSS_EXPORT_VERSION,
        mode = "delta",
        bossKeyText = targetBossKey,
        manifestHash = tostring(manifestHash or ""),
        manifestKeys = manifestKeys,
        exporterName = tostring(UnitName and (UnitName("player") or "") or ""),
        exporterVersion = tostring(T and T.Version or ""),
        exportTime = time and time() or 0,
        boards = boards,
    }
end

local function FindBoardBySyncKey(db, bossKeyText, syncKey)
    local targetKey = Trim(syncKey)
    if targetKey == "" then
        return nil
    end
    for id, board in pairs(db or {}) do
        if type(id) == "string" and id:sub(1, 1) ~= "_" and type(board) == "table"
            and NormalizeBossKeyText(board.bossKeyText) == bossKeyText
            and Trim(board.syncKey or board.id) == targetKey then
            return id, board
        end
    end
    return nil
end

local function RemoveBoardsOutsideManifest(db, bossKeyText, manifestKeys)
    local keep = BuildKeySet(manifestKeys)
    local removed = 0
    for id, board in pairs(db or {}) do
        if type(id) == "string" and id:sub(1, 1) ~= "_" and type(board) == "table" and NormalizeBossKeyText(board.bossKeyText) == bossKeyText then
            local syncKey = Trim(board.syncKey or board.id)
            if syncKey == "" or not keep[syncKey] then
                db[id] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

function Data:ApplyBossBoardManifest(package, sender)
    local result = { total = 0, matched = 0, missing = 0, removed = 0, pendingRemoved = 0, missingKeys = {}, bossKeyText = "", manifestHash = "" }
    if type(package) ~= "table" or package.mode ~= "manifest" then
        return result, "invalid_package"
    end
    local bossKeyText = NormalizeBossKeyText(package.bossKeyText)
    if not bossKeyText or type(package.boards) ~= "table" then
        return result, "invalid_package"
    end
    result.bossKeyText = bossKeyText
    result.manifestHash = tostring(package.manifestHash or "")

    local db = self:EnsureDB()
    local manifestKeys = {}
    local entries = {}
    for _, entry in ipairs(package.boards) do
        if type(entry) == "table" then
            local syncKey = Trim(entry.syncKey)
            if syncKey ~= "" then
                manifestKeys[syncKey] = true
                entries[#entries + 1] = {
                    syncKey = syncKey,
                    hash = tostring(entry.hash or ""),
                }
            end
        end
    end
    result.total = #entries

    for _, entry in ipairs(entries) do
        local _, existing = FindBoardBySyncKey(db, bossKeyText, entry.syncKey)
        local existingHash = existing and (existing.hash or self:ComputeBoardHash(existing)) or nil
        if existing then
            existing.hash = existingHash
        end
        if existing and existingHash == entry.hash then
            result.matched = result.matched + 1
        else
            result.missing = result.missing + 1
            result.missingKeys[#result.missingKeys + 1] = entry.syncKey
        end
    end

    for id, board in pairs(db) do
        if type(id) == "string" and id:sub(1, 1) ~= "_" and type(board) == "table" and NormalizeBossKeyText(board.bossKeyText) == bossKeyText then
            local syncKey = Trim(board.syncKey or board.id)
            if syncKey == "" or not manifestKeys[syncKey] then
                result.pendingRemoved = result.pendingRemoved + 1
            end
        end
    end
    if result.missing <= 0 then
        result.removed = RemoveBoardsOutsideManifest(db, bossKeyText, package.manifestKeys or {})
        result.pendingRemoved = 0
    end

    if T and T.debug then
        T.debug(string.format(
            "[VisualBoard] BossBoardManifestApplied boss=%s total=%d matched=%d missing=%d removed=%d pendingRemoved=%d sender=%s manifest=%s",
            tostring(bossKeyText),
            result.total,
            result.matched,
            result.missing,
            result.removed,
            result.pendingRemoved,
            tostring(sender or ""),
            result.manifestHash
        ))
    end
    return result
end

local function AllocateBoardID(db)
    local seq = NormalizePositiveNumber(db._nextID, 1)
    local id
    repeat
        id = "board-" .. tostring(seq)
        seq = seq + 1
    until db[id] == nil
    db._nextID = seq
    return id
end

function Data:ReplaceBossBoards(package, sender)
    local result = { total = 0, added = 0, updated = 0, skipped = 0, removed = 0, bossKeyText = "" }
    if type(package) ~= "table" then
        return result, "invalid_package"
    end
    local bossKeyText = NormalizeBossKeyText(package.bossKeyText)
    if not bossKeyText or type(package.boards) ~= "table" then
        return result, "invalid_package"
    end
    result.bossKeyText = bossKeyText

    local incoming = {}
    for _, board in ipairs(package.boards) do
        if type(board) == "table" and not IsLegacyBoard(board) then
            local id = Trim(board.id)
            if id == "" then
                id = "incoming-" .. tostring(#incoming + 1)
            end
            local normalized = EnsureBoardShape(DeepCopy(board), id)
            if normalized then
                normalized.bossKeyText = bossKeyText
                normalized.encounterID = tonumber(normalized.encounterID) or tonumber(package.encounterID)
                normalized.received = sender ~= nil
                normalized.receivedFrom = tostring(sender or "")
                normalized.hash = normalized.hash or self:ComputeBoardHash(normalized)
                incoming[#incoming + 1] = normalized
            end
        end
    end
    result.total = #incoming
    if result.total <= 0 then
        return result, "empty"
    end

    local db = self:EnsureDB()
    for id, board in pairs(db) do
        if type(id) == "string" and id:sub(1, 1) ~= "_" and type(board) == "table" and NormalizeBossKeyText(board.bossKeyText) == bossKeyText then
            db[id] = nil
            result.removed = result.removed + 1
        end
    end

    for _, board in ipairs(incoming) do
        local newID = AllocateBoardID(db)
        board.id = newID
        board.builtin = false
        board.hash = self:ComputeBoardHash(board)
        db[newID] = board
        result.added = result.added + 1
    end

    if T and T.debug then
        T.debug(string.format(
            "[VisualBoard] BossBoardsReplaced boss=%s total=%d added=%d removed=%d sender=%s",
            tostring(bossKeyText),
            result.total,
            result.added,
            result.removed,
            tostring(sender or "")
        ))
    end
    return result
end

function Data:MergeBossBoardDelta(package, sender)
    local result = { total = 0, added = 0, updated = 0, skipped = 0, removed = 0, bossKeyText = "", manifestHash = "" }
    if type(package) ~= "table" or package.mode ~= "delta" then
        return result, "invalid_package"
    end
    local bossKeyText = NormalizeBossKeyText(package.bossKeyText)
    if not bossKeyText or type(package.boards) ~= "table" then
        return result, "invalid_package"
    end
    result.bossKeyText = bossKeyText
    result.manifestHash = tostring(package.manifestHash or "")

    local db = self:EnsureDB()
    for _, board in ipairs(package.boards) do
        if type(board) == "table" and not IsLegacyBoard(board) then
            local syncKey = Trim(board.syncKey or board.id)
            if syncKey ~= "" then
                local normalized = EnsureBoardShape(DeepCopy(board), board.id)
                if normalized then
                    result.total = result.total + 1
                    normalized.bossKeyText = bossKeyText
                    normalized.received = sender ~= nil
                    normalized.receivedFrom = tostring(sender or "")
                    normalized.hash = self:ComputeBoardHash(normalized)
                    local existingID, existing = FindBoardBySyncKey(db, bossKeyText, syncKey)
                    local existingHash = existing and (existing.hash or self:ComputeBoardHash(existing)) or nil
                    if existing and existingHash == normalized.hash then
                        existing.hash = existingHash
                        result.skipped = result.skipped + 1
                    elseif existingID then
                        normalized.id = existingID
                        normalized.created = existing.created or normalized.created
                        db[existingID] = normalized
                        result.updated = result.updated + 1
                    else
                        local newID = AllocateBoardID(db)
                        normalized.id = newID
                        db[newID] = normalized
                        result.added = result.added + 1
                    end
                end
            end
        end
    end
    if type(package.manifestKeys) == "table" then
        result.removed = RemoveBoardsOutsideManifest(db, bossKeyText, package.manifestKeys)
    end

    if T and T.debug then
        T.debug(string.format(
            "[VisualBoard] BossBoardDeltaMerged boss=%s total=%d added=%d updated=%d skipped=%d removed=%d sender=%s manifest=%s",
            tostring(bossKeyText),
            result.total,
            result.added,
            result.updated,
            result.skipped,
            result.removed,
            tostring(sender or ""),
            result.manifestHash
        ))
    end
    return result
end

T.RegisterColdFile("visualBoard.editorLoaded", function()

-- v2：创建 person/text/shape/marker/icon 默认元素。颜色统一 hex。
-- 非法 kind 返回 nil。
function Data:CreateDefaultElement(kind, board)
    local kindStr = tostring(kind or "")
    if kindStr ~= "person" and kindStr ~= "text" and kindStr ~= "shape" and kindStr ~= "marker" and kindStr ~= "icon" then
        return nil
    end
    local element = {
        type = kindStr,
        z = #(board and board.elements or {}) + 1,
        x = DEFAULT_ARTBOARD_W / 2,
        y = DEFAULT_ARTBOARD_H / 2,
        rotation = 0,
        scale = 1,
        params = {},
    }

    if kindStr == "person" then
        element.params = {
            slotName = "",
            icon = { size = 40, borderSize = 0, borderColor = "000000" },
            circle = { radius = 58, color = "33CC66", alpha = 0.5, shapeStyle = "solid", enabled = true },
            text = {
                position = "top", dx = 0, dy = 0,
                fontSize = 19, fontFace = "default", color = "EFFFFF",
                bold = false, outline = true, outlineColor = "000000", shadow = true, scale = 1,
                justifyH = "CENTER",
                enabled = true,
            },
        }
    elseif kindStr == "text" then
        element.params = {
            text = L["VISUAL_BOARD_SAMPLE_TEXT"] or "文字",
            fontSize = 40, fontFace = "default", color = "00FF8C",
            bold = false, outline = true, outlineColor = "000000", shadow = true, scale = 1,
            justifyH = "CENTER",
        }
    elseif kindStr == "shape" then
        element.params = { shapeKind = "rect", color = "FFFFFF", alpha = 0.85, w = 200, h = 120 }
    elseif kindStr == "marker" then
        element.params = { markerIndex = 1, size = 54 }
    elseif kindStr == "icon" then
        element.params = {
            texture = "Interface\\Icons\\INV_Misc_QuestionMark",
            size = 54,
            shape = "circle",
            borderSize = 0,
            borderColor = "000000",
        }
    end

    return element
end

function Data:_ApplyElementFields(element, fields)
    if type(element) ~= "table" or type(fields) ~= "table" then
        return false
    end
    if type(element.params) ~= "table" then
        element.params = {}
    end

    -- 公共几何字段（顶层）。
    if fields.x ~= nil then
        element.x = tonumber(fields.x) or element.x
    end
    if fields.y ~= nil then
        element.y = tonumber(fields.y) or element.y
    end
    if fields.end_x ~= nil then
        element.end_x = tonumber(fields.end_x)
    end
    if fields.end_y ~= nil then
        element.end_y = tonumber(fields.end_y)
    end
    if fields.rotation ~= nil then
        element.rotation = (tonumber(fields.rotation) or 0) % 360
    end
    if fields.z ~= nil then
        element.z = tonumber(fields.z) or element.z
    end
    if fields.scale ~= nil then
        element.scale = NormalizePositiveNumber(fields.scale, element.scale or 1)
    end

    -- params 深层部分覆写：只覆写 fields.params 给出的叶子，未给的保留；
    -- person 子件（icon/circle/text）按表递归一层覆写。规范化交给调用链的 EnsureElementShape。
    if type(fields.params) == "table" then
        DeepMergeInto(element.params, fields.params)
        -- 图标来源互斥：本次明确写哪个就清掉其它入口（换图标语义，非兜底）。
        if element.type == "person" and type(fields.params.icon) == "table" and type(element.params.icon) == "table" then
            if fields.params.icon.encounterID ~= nil or fields.params.icon.encounterIcon ~= nil then
                element.params.icon.texture = nil
                element.params.icon.atlas = nil
                element.params.icon.spellID = nil
            elseif fields.params.icon.spellID ~= nil then
                element.params.icon.texture = nil
                element.params.icon.atlas = nil
                element.params.icon.encounterID = nil
                element.params.icon.encounterIcon = nil
            elseif fields.params.icon.texture ~= nil then
                element.params.icon.atlas = nil
                element.params.icon.spellID = nil
                element.params.icon.encounterID = nil
                element.params.icon.encounterIcon = nil
            elseif fields.params.icon.atlas ~= nil then
                element.params.icon.texture = nil
                element.params.icon.spellID = nil
                element.params.icon.encounterID = nil
                element.params.icon.encounterIcon = nil
            end
        elseif element.type == "icon" then
            if fields.params.encounterID ~= nil or fields.params.encounterIcon ~= nil then
                element.params.texture = nil
                element.params.atlas = nil
                element.params.spellID = nil
            elseif fields.params.spellID ~= nil then
                element.params.texture = nil
                element.params.atlas = nil
                element.params.encounterID = nil
                element.params.encounterIcon = nil
            elseif fields.params.texture ~= nil then
                element.params.atlas = nil
                element.params.spellID = nil
                element.params.encounterID = nil
                element.params.encounterIcon = nil
            elseif fields.params.atlas ~= nil then
                element.params.texture = nil
                element.params.spellID = nil
                element.params.encounterID = nil
                element.params.encounterIcon = nil
            end
        end
    end
    return true
end

-- v2 无边画布：元素允许落在 artboard 框外（草稿区），不再 clamp 到画板内。
-- line/arrow 端点随锚点平移。
function Data:_SetElementPosition(element, board, x, y)
    if type(element) ~= "table" then
        return false
    end
    local oldX = tonumber(element.x) or 0
    local oldY = tonumber(element.y) or 0
    local nextX = tonumber(x) or oldX
    local nextY = tonumber(y) or oldY
    local dx = nextX - oldX
    local dy = nextY - oldY
    element.x = nextX
    element.y = nextY
    if element.end_x and element.end_y then
        element.end_x = (tonumber(element.end_x) or oldX) + dx
        element.end_y = (tonumber(element.end_y) or oldY) + dy
    end
    return true
end

function Data:_AllocateElement(board, kind, x, y, fields)
    local element = self:CreateDefaultElement(kind, board)
    if type(element) ~= "table" then
        return nil
    end
    local nextID = NormalizePositiveNumber(board._nextElementID, #board.elements + 1)
    element.id = "elem-" .. tostring(nextID)
    board._nextElementID = nextID + 1
    self:_SetElementPosition(element, board, x or element.x, y or element.y)
    self:_ApplyElementFields(element, fields)
    return EnsureElementShape(element, #board.elements + 1, board)
end

function Data:GetElement(boardID, elementID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" then
        return nil
    end
    local targetID = Trim(elementID)
    if targetID == "" then
        return nil
    end
    for _, element in ipairs(board.elements or {}) do
        if type(element) == "table" and element.id == targetID then
            return element, board
        end
    end
    return nil
end

function Data:AddElement(boardID, kind)
    return self:AddElementAt(boardID, kind, DEFAULT_ARTBOARD_W / 2, DEFAULT_ARTBOARD_H / 2)
end

function Data:AddElementAt(boardID, kind, x, y, fields)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return nil
    end
    local element = self:_AllocateElement(board, kind, x, y, fields)
    if type(element) ~= "table" then
        return nil
    end
    local snapshot = DeepCopy(element)
    local insertIndex = #board.elements + 1
    self:DoCommand({
        label = "addElement:" .. tostring(kind),
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" then
                if not FindElementIndex(target, snapshot.id) then
                    InsertElement(target, snapshot, insertIndex)
                end
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" then
                RemoveElement(target, snapshot.id)
                RecomputeBoard(self, target)
            end
        end,
    })
    if T and T.debug then
        T.debug(string.format("[VisualBoard] ElementPlaced board=%s element=%s type=%s x=%.1f y=%.1f", tostring(boardID), tostring(snapshot.id), tostring(kind), tonumber(snapshot.x) or 0, tonumber(snapshot.y) or 0))
    end
    return self:GetElement(boardID, snapshot.id)
end

-- 便捷：新建 person 并写 slotName（图标默认自动）。落点不 clamp（无边画布）。
function Data:AddPersonAt(boardID, slotName, x, y)
    return self:AddElementAt(boardID, "person", x, y, { params = { slotName = Trim(slotName) } })
end

-- 便捷：新建团队标记（marker type）。
function Data:AddRaidMarker(boardID, markerIndex, x, y)
    local element = self:AddElementAt(boardID, "marker", x or DEFAULT_ARTBOARD_W / 2, y or DEFAULT_ARTBOARD_H / 2, {
        params = { markerIndex = math.max(1, math.min(8, tonumber(markerIndex) or 1)) },
    })
    if type(element) ~= "table" then
        return nil
    end
    if T and T.debug then
        T.debug(string.format("[VisualBoard] RaidMarkerAdded board=%s element=%s marker=%s", tostring(boardID), tostring(element.id), tostring(element.params.markerIndex)))
    end
    return element
end

function Data:DeleteElement(boardID, elementID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local targetID = Trim(elementID)
    if targetID == "" then
        return false
    end
    local index, element = FindElementIndex(board, targetID)
    if not index then
        return false
    end
    local snapshot = DeepCopy(element)
    self:DoCommand({
        label = "deleteElement",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" then
                RemoveElement(target, targetID)
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and not FindElementIndex(target, targetID) then
                InsertElement(target, snapshot, index)
                RecomputeBoard(self, target)
            end
        end,
    })
    if T and T.debug then
        T.debug(string.format("[VisualBoard] ElementDeleted board=%s element=%s", tostring(board.id), tostring(targetID)))
    end
    return true
end

function Data:UpdateElement(boardID, elementID, fields)
    local element, board = self:GetElement(boardID, elementID)
    if type(element) ~= "table" or type(board) ~= "table" or board.builtin == true or type(fields) ~= "table" then
        return false
    end

    local before = DeepCopy(element)
    local after = DeepCopy(element)
    self:_ApplyElementFields(after, fields)
    self:DoCommand({
        label = "updateElement",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, elementID, after) then
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, elementID, before) then
                RecomputeBoard(self, target)
            end
        end,
    })
    if T and T.debug then
        T.debug(string.format("[VisualBoard] ElementUpdated board=%s element=%s type=%s", tostring(board.id), tostring(element.id), tostring(element.type)))
    end
    return true
end

function Data:UpdateElementPosition(boardID, elementID, x, y, transient)
    local element, board = self:GetElement(boardID, elementID)
    if type(element) ~= "table" or type(board) ~= "table" or board.builtin == true then
        return false
    end
    local key = tostring(boardID) .. ":" .. tostring(elementID)
    if transient then
        if not self._transientSnapshots[key] then
            self._transientSnapshots[key] = DeepCopy(element)
        end
        self:_SetElementPosition(element, board, x, y)
        return true
    end

    local before = self._transientSnapshots[key] or DeepCopy(element)
    self._transientSnapshots[key] = nil
    self:_SetElementPosition(element, board, x, y)
    local after = DeepCopy(element)
    local unchanged = tonumber(before.x) == tonumber(after.x) and tonumber(before.y) == tonumber(after.y) and tonumber(before.end_x) == tonumber(after.end_x) and tonumber(before.end_y) == tonumber(after.end_y)
    if unchanged then
        RecomputeBoard(self, board)
        return true
    end
    self:DoCommand({
        label = "moveElement",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, elementID, after) then
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, elementID, before) then
                RecomputeBoard(self, target)
            end
        end,
    })
    if T and T.debug then
        T.debug(string.format("[VisualBoard] ElementMoved board=%s element=%s x=%.1f y=%.1f", tostring(board.id), tostring(element.id), after.x, after.y))
    end
    return true
end

function Data:UpdateSegmentEndpoint(boardID, elementID, endpoint, x, y, transient)
    local element, board = self:GetElement(boardID, elementID)
    if type(element) ~= "table" or type(board) ~= "table" or board.builtin == true then
        return false
    end
    local params = type(element.params) == "table" and element.params or {}
    if element.type ~= "shape" or (params.shapeKind ~= "line" and params.shapeKind ~= "arrow") then
        return false
    end
    local point = endpoint == "end" and "end" or "start"
    local key = tostring(boardID) .. ":" .. tostring(elementID) .. ":segment"
    local function apply(target)
        if point == "end" then
            target.end_x = tonumber(x) or target.end_x
            target.end_y = tonumber(y) or target.end_y
        else
            target.x = tonumber(x) or target.x
            target.y = tonumber(y) or target.y
        end
    end
    if transient then
        if not self._transientSnapshots[key] then
            self._transientSnapshots[key] = DeepCopy(element)
        end
        apply(element)
        return true
    end

    local before = self._transientSnapshots[key] or DeepCopy(element)
    self._transientSnapshots[key] = nil
    apply(element)
    local after = DeepCopy(element)
    local unchanged = tonumber(before.x) == tonumber(after.x) and tonumber(before.y) == tonumber(after.y) and tonumber(before.end_x) == tonumber(after.end_x) and tonumber(before.end_y) == tonumber(after.end_y)
    if unchanged then
        RecomputeBoard(self, board)
        return true
    end
    self:DoCommand({
        label = "moveSegmentEndpoint",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, elementID, after) then
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, elementID, before) then
                RecomputeBoard(self, target)
            end
        end,
    })
    return true
end

function Data:UpdateElementRotation(boardID, elementID, rotation, transient)
    local element, board = self:GetElement(boardID, elementID)
    if type(element) ~= "table" or type(board) ~= "table" or board.builtin == true then
        return false
    end
    local key = tostring(boardID) .. ":" .. tostring(elementID) .. ":rotation"
    local value = (tonumber(rotation) or 0) % 360
    if transient then
        if not self._transientSnapshots[key] then
            self._transientSnapshots[key] = DeepCopy(element)
        end
        element.rotation = value
        RecomputeBoard(self, board)
        return true
    end

    local before = self._transientSnapshots[key] or DeepCopy(element)
    self._transientSnapshots[key] = nil
    element.rotation = value
    local after = DeepCopy(element)
    if tonumber(before.rotation) == tonumber(after.rotation) then
        RecomputeBoard(self, board)
        return true
    end
    self:DoCommand({
        label = "rotateElement",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, elementID, after) then
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, elementID, before) then
                RecomputeBoard(self, target)
            end
        end,
    })
    return true
end

function Data:DuplicateElement(boardID, elementID, dx, dy)
    local element, board = self:GetElement(boardID, elementID)
    if type(element) ~= "table" or type(board) ~= "table" or board.builtin == true then
        return nil
    end
    local copy = DeepCopy(element)
    local nextID = NormalizePositiveNumber(board._nextElementID, #board.elements + 1)
    copy.id = "elem-" .. tostring(nextID)
    board._nextElementID = nextID + 1
    copy.z = #(board.elements or {}) + 1
    self:_SetElementPosition(copy, board, (tonumber(copy.x) or 0) + (tonumber(dx) or 16), (tonumber(copy.y) or 0) + (tonumber(dy) or 16))
    local snapshot = EnsureElementShape(copy, #board.elements + 1, board)
    local insertIndex = #board.elements + 1
    self:DoCommand({
        label = "duplicateElement",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and not FindElementIndex(target, snapshot.id) then
                InsertElement(target, snapshot, insertIndex)
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" then
                RemoveElement(target, snapshot.id)
                RecomputeBoard(self, target)
            end
        end,
    })
    return self:GetElement(boardID, snapshot.id)
end

function Data:InsertElementCopy(boardID, snapshot, dx, dy)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true or type(snapshot) ~= "table" then
        return nil
    end
    local copy = DeepCopy(snapshot)
    local nextID = NormalizePositiveNumber(board._nextElementID, #board.elements + 1)
    copy.id = "elem-" .. tostring(nextID)
    board._nextElementID = nextID + 1
    copy.z = #(board.elements or {}) + 1
    self:_SetElementPosition(copy, board, (tonumber(copy.x) or 0) + (tonumber(dx) or 16), (tonumber(copy.y) or 0) + (tonumber(dy) or 16))
    local element = EnsureElementShape(copy, #board.elements + 1, board)
    local insertIndex = #board.elements + 1
    self:DoCommand({
        label = "pasteElement",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and not FindElementIndex(target, element.id) then
                InsertElement(target, element, insertIndex)
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" then
                RemoveElement(target, element.id)
                RecomputeBoard(self, target)
            end
        end,
    })
    return self:GetElement(boardID, element.id)
end

function Data:MoveElementZ(boardID, elementID, direction)
    local element, board = self:GetElement(boardID, elementID)
    if type(element) ~= "table" or type(board) ~= "table" or board.builtin == true then
        return false
    end
    local before = {}
    for _, item in ipairs(board.elements or {}) do
        before[item.id] = tonumber(item.z) or 0
    end
    local targetZ = direction == "bottom" and 1 or #(board.elements or {})
    local after = {}
    for _, item in ipairs(board.elements or {}) do
        after[item.id] = tonumber(item.z) or 0
        if item.id == elementID then
            after[item.id] = targetZ
        elseif direction == "bottom" then
            after[item.id] = after[item.id] + 1
        else
            after[item.id] = math.max(1, after[item.id] - 1)
        end
    end
    local function applyZ(values)
        local target = self:GetBoard(boardID)
        if type(target) ~= "table" then
            return
        end
        for _, item in ipairs(target.elements or {}) do
            if values[item.id] then
                item.z = values[item.id]
            end
        end
        RecomputeBoard(self, target)
    end
    self:DoCommand({
        label = "moveElementZ",
        do_ = function() applyZ(after) end,
        undo = function() applyZ(before) end,
    })
    return true
end

function Data:CommitElementSnapshot(boardID, elementID, before, after, label)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true or type(before) ~= "table" or type(after) ~= "table" then
        return false
    end
    local targetID = Trim(elementID)
    if targetID == "" or not FindElementIndex(board, targetID) then
        return false
    end
    self:DoCommand({
        label = label or "transformElement",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, targetID, after) then
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" and ReplaceElement(target, targetID, before) then
                RecomputeBoard(self, target)
            end
        end,
    })
    return true
end

end)

-- 几何单一权威：返回元素在【画板逻辑坐标】下的包围盒尺寸与形状语义。
-- canvas 命中/手柄、editor PPT 缩放锚点都必须调用本函数。
-- 返回: w, h, shape  其中 shape ∈ "rect"|"radial"|"text"|"segment"|"person"
local function EstimateTextBox(params, fallbackFontSize)
    params = type(params) == "table" and params or {}
    local fontSize = tonumber(params.fontSize) or fallbackFontSize or 40
    local scale = tonumber(params.scale) or 1
    local text = tostring(params.text or "")
    local explicitWidth = tonumber(params.width)
    local lines = 1
    local maxBytes = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines = math.max(lines, 1)
        maxBytes = math.max(maxBytes, #line)
    end
    lines = select(2, text:gsub("\n", "")) + 1
    local autoWidth = math.max(fontSize * 1.5, maxBytes * fontSize * 0.34)
    local width = explicitWidth and explicitWidth > 0 and explicitWidth or autoWidth
    if explicitWidth and explicitWidth > 0 and autoWidth > explicitWidth then
        lines = math.max(lines, math.ceil(autoWidth / explicitWidth))
    end
    return width * scale, math.max(fontSize * 1.25, lines * fontSize * 1.25) * scale
end

function Data:GetElementBox(element)
    if type(element) ~= "table" then
        return 0, 0, "rect"
    end
    local params = type(element.params) == "table" and element.params or {}
    local elementScale = tonumber(element.scale) or 1
    local kind = element.type
    if kind == "person" then
        -- person 包围盒只框住可点中的核心（圆半径 / 图标半边 取大）；名签是装饰，不计入。
        local layout = self:GetPersonLayout(element)
        local coreR = math.max(
            layout.circle.enabled and layout.circle.radius or 0,
            layout.icon.size / 2
        )
        return coreR * 2 * elementScale, coreR * 2 * elementScale, "person"
    elseif kind == "marker" then
        local size = (tonumber(params.size) or 54) * elementScale
        return size, size, "radial"
    elseif kind == "icon" then
        local size = (tonumber(params.size) or 54) * elementScale
        return size, size, "radial"
    elseif kind == "text" then
        local w, h = EstimateTextBox(params, 40)
        return w * elementScale, h * elementScale, "text"
    elseif kind == "shape" then
        local shapeKind = params.shapeKind
        if shapeKind == "circle" then
            local radius = (tonumber(params.radius) or 60) * elementScale
            return radius * 2, radius * 2, "radial"
        elseif shapeKind == "line" or shapeKind == "arrow" then
            local x = tonumber(element.x) or 0
            local y = tonumber(element.y) or 0
            local endX = tonumber(element.end_x) or (x + 120)
            local endY = tonumber(element.end_y) or y
            return math.abs(endX - x), math.abs(endY - y), "segment"
        end
        -- rect
        local w = (tonumber(params.w) or 200) * elementScale
        local h = (tonumber(params.h) or 120) * elementScale
        return w, h, "rect"
    end
    return 0, 0, "rect"
end

-- person 专用：返回各子件在 artboard 逻辑坐标下相对锚点 (element.x,element.y) 的局部布局。
-- 尺寸均为逻辑像素（未乘 element.scale；canvas 统一施加整体缩放）。
-- 返回: { icon={size}, circle={radius,enabled}, text={ox,oy,vertical,enabled} }
function Data:GetPersonLayout(element)
    local params = type(element) == "table" and type(element.params) == "table" and element.params or {}
    local icon = type(params.icon) == "table" and params.icon or {}
    local circle = type(params.circle) == "table" and params.circle or {}
    local text = type(params.text) == "table" and params.text or {}

    local iconSize = tonumber(icon.size) or 40
    local circleRadius = tonumber(circle.radius) or 58
    local circleEnabled = circle.enabled ~= false
    local textEnabled = text.enabled ~= false
    local position = tostring(text.position or "top")
    local vertical = (position == "left" or position == "right")
    local dx = tonumber(text.dx) or 0
    local dy = tonumber(text.dy) or 0
    local fontSize = tonumber(text.fontSize) or 19
    local textScale = tonumber(text.scale) or 1

    -- 名签紧贴专精图标下沿：基础间距 = 半个图标尺寸 + 半个文字盒高度（不以圆半径为基准，避免名签离图标过远）。
    local gap = fontSize * textScale * 0.5
    local offset = iconSize / 2 + gap
    local ox, oy = 0, 0
    if position == "top" then
        oy = offset + dy
        ox = dx
    elseif position == "bottom" then
        oy = -(offset) + dy
        ox = dx
    elseif position == "left" then
        ox = -(offset) + dx
        oy = dy
    else -- right
        ox = offset + dx
        oy = dy
    end

    return {
        icon = { size = iconSize },
        circle = { radius = circleRadius, enabled = circleEnabled },
        text = { ox = ox, oy = oy, vertical = vertical, enabled = textEnabled },
    }
end

-- 批量撤销提交：保存一组元素 before/after 快照与 board.groups 整表，作为一条撤销记录。
local function CommitBatch(self, boardID, beforeElements, afterElements, beforeGroups, afterGroups, label)
    self:DoCommand({
        label = label or "batch",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) ~= "table" then return end
            target.groups = DeepCopy(afterGroups)
            for id, snapshot in pairs(afterElements) do
                ReplaceElement(target, id, snapshot)
            end
            RecomputeBoard(self, target)
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) ~= "table" then return end
            target.groups = DeepCopy(beforeGroups)
            for id, snapshot in pairs(beforeElements) do
                ReplaceElement(target, id, snapshot)
            end
            RecomputeBoard(self, target)
        end,
    })
end

local function CollectElementSnapshots(board, elementIDs)
    local snapshots = {}
    local order = {}
    for _, id in ipairs(elementIDs or {}) do
        local targetID = Trim(id)
        if targetID ~= "" and not snapshots[targetID] then
            local _, element = FindElementIndex(board, targetID)
            if type(element) == "table" then
                snapshots[targetID] = DeepCopy(element)
                order[#order + 1] = targetID
            end
        end
    end
    return snapshots, order
end

function Data:SetElementFlag(boardID, elementID, flag, value)
    if flag ~= "hidden" and flag ~= "locked" then
        return false
    end
    local element, board = self:GetElement(boardID, elementID)
    if type(element) ~= "table" or type(board) ~= "table" or board.builtin == true then
        return false
    end
    local targetID = element.id
    local before = DeepCopy(element)
    local after = DeepCopy(element)
    after[flag] = value == true
    CommitBatch(self, boardID, { [targetID] = before }, { [targetID] = after }, board.groups, board.groups, "setElementFlag")
    return true
end

function Data:SetElementName(boardID, elementID, name)
    local element, board = self:GetElement(boardID, elementID)
    if type(element) ~= "table" or type(board) ~= "table" or board.builtin == true then
        return false
    end
    local targetID = element.id
    local trimmed = Trim(name)
    local before = DeepCopy(element)
    local after = DeepCopy(element)
    after.name = trimmed ~= "" and trimmed or nil
    CommitBatch(self, boardID, { [targetID] = before }, { [targetID] = after }, board.groups, board.groups, "setElementName")
    return true
end

-- 按给定顺序重写 z。约定：orderedIDs 数组首元素 z 最大（最上层）。
function Data:SetElementOrder(boardID, orderedIDs)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true or type(orderedIDs) ~= "table" then
        return false
    end
    local count = #orderedIDs
    local beforeElements, order = CollectElementSnapshots(board, orderedIDs)
    if #order == 0 then
        return false
    end
    local afterElements = {}
    for index, id in ipairs(orderedIDs) do
        local targetID = Trim(id)
        if beforeElements[targetID] then
            local after = DeepCopy(beforeElements[targetID])
            after.z = count - index + 1
            afterElements[targetID] = after
        end
    end
    CommitBatch(self, boardID, beforeElements, afterElements, board.groups, board.groups, "setElementOrder")
    return true
end

function Data:MoveElements(boardID, elementIDs, dx, dy, transient)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local deltaX = tonumber(dx) or 0
    local deltaY = tonumber(dy) or 0
    local _, order = CollectElementSnapshots(board, elementIDs)
    if #order == 0 then
        return false
    end

    local key = tostring(boardID) .. ":move:" .. table.concat(order, ",")
    if transient then
        if not self._transientSnapshots[key] then
            self._transientSnapshots[key] = CollectElementSnapshots(board, order)
        end
        for _, id in ipairs(order) do
            local _, element = FindElementIndex(board, id)
            if type(element) == "table" then
                self:_SetElementPosition(element, board, (tonumber(element.x) or 0) + deltaX, (tonumber(element.y) or 0) + deltaY)
            end
        end
        return true
    end

    local beforeElements = self._transientSnapshots[key] or CollectElementSnapshots(board, order)
    self._transientSnapshots[key] = nil
    for _, id in ipairs(order) do
        local _, element = FindElementIndex(board, id)
        if type(element) == "table" then
            self:_SetElementPosition(element, board, (tonumber(element.x) or 0) + deltaX, (tonumber(element.y) or 0) + deltaY)
        end
    end
    local afterElements = CollectElementSnapshots(board, order)
    CommitBatch(self, boardID, beforeElements, afterElements, board.groups, board.groups, "moveElements")
    return true
end

-- v2：缩放 = 位置锚定缩放 + element.scale 整体放大（单一权威，不逐 param 改尺寸）。
-- line/arrow 端点同样按 origin 锚定缩放。
local function ScaleOneElement(self, board, element, factor, originX, originY)
    if type(element) ~= "table" then
        return
    end
    local x = tonumber(element.x) or 0
    local y = tonumber(element.y) or 0
    self:_SetElementPosition(element, board, originX + (x - originX) * factor, originY + (y - originY) * factor)
    if element.end_x and element.end_y then
        element.end_x = originX + ((tonumber(element.end_x) or 0) - originX) * factor
        element.end_y = originY + ((tonumber(element.end_y) or 0) - originY) * factor
    end
    element.scale = NormalizePositiveNumber((tonumber(element.scale) or 1) * factor, element.scale or 1)
end

function Data:ScaleElements(boardID, elementIDs, factor, originX, originY, transient)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local scaleFactor = math.max(0.1, tonumber(factor) or 1)
    local ax = tonumber(originX) or 0
    local ay = tonumber(originY) or 0
    local _, order = CollectElementSnapshots(board, elementIDs)
    if #order == 0 then
        return false
    end

    local key = tostring(boardID) .. ":scale:" .. table.concat(order, ",")
    if transient then
        if not self._transientSnapshots[key] then
            self._transientSnapshots[key] = CollectElementSnapshots(board, order)
        end
        local baseline = self._transientSnapshots[key]
        for _, id in ipairs(order) do
            if baseline[id] then
                ReplaceElement(board, id, baseline[id])
                local _, element = FindElementIndex(board, id)
                ScaleOneElement(self, board, element, scaleFactor, ax, ay)
            end
        end
        return true
    end

    local beforeElements = self._transientSnapshots[key] or CollectElementSnapshots(board, order)
    self._transientSnapshots[key] = nil
    for _, id in ipairs(order) do
        ReplaceElement(board, id, beforeElements[id])
        local _, element = FindElementIndex(board, id)
        ScaleOneElement(self, board, element, scaleFactor, ax, ay)
    end
    local afterElements = CollectElementSnapshots(board, order)
    CommitBatch(self, boardID, beforeElements, afterElements, board.groups, board.groups, "scaleElements")
    return true
end

function Data:CreateGroup(boardID, elementIDs, name)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return nil
    end
    local beforeElements, order = CollectElementSnapshots(board, elementIDs)
    if #order < 1 then
        return nil
    end

    local seq = NormalizePositiveNumber(board._nextGroupID, 1)
    local groupID
    repeat
        groupID = "group-" .. tostring(seq)
        seq = seq + 1
    until type(board.groups) ~= "table" or board.groups[groupID] == nil
    board._nextGroupID = seq

    local groupCount = 0
    for _ in pairs(board.groups or {}) do
        groupCount = groupCount + 1
    end
    local groupName = Trim(name)
    if groupName == "" then
        groupName = string.format(L["VISUAL_BOARD_GROUP_AUTONAME"] or "组%d", groupCount + 1)
    end

    local beforeGroups = board.groups
    local afterGroups = DeepCopy(board.groups)
    afterGroups[groupID] = { id = groupID, name = groupName, hidden = false, locked = false }
    local afterElements = {}
    for _, id in ipairs(order) do
        local after = DeepCopy(beforeElements[id])
        after.groupID = groupID
        afterElements[id] = after
    end
    CommitBatch(self, boardID, beforeElements, afterElements, beforeGroups, afterGroups, "createGroup")
    if T and T.debug then
        T.debug(string.format("[VisualBoard] GroupCreated board=%s group=%s members=%d", tostring(boardID), tostring(groupID), #order))
    end
    return groupID
end

function Data:Ungroup(boardID, groupID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local targetID = Trim(groupID)
    if targetID == "" or type(board.groups) ~= "table" or type(board.groups[targetID]) ~= "table" then
        return false
    end
    local memberIDs = {}
    for _, element in ipairs(board.elements or {}) do
        if element.groupID == targetID then
            memberIDs[#memberIDs + 1] = element.id
        end
    end
    local beforeElements = CollectElementSnapshots(board, memberIDs)
    local beforeGroups = board.groups
    local afterGroups = DeepCopy(board.groups)
    afterGroups[targetID] = nil
    local afterElements = {}
    for _, id in ipairs(memberIDs) do
        local after = DeepCopy(beforeElements[id])
        after.groupID = nil
        afterElements[id] = after
    end
    CommitBatch(self, boardID, beforeElements, afterElements, beforeGroups, afterGroups, "ungroup")
    return true
end

function Data:GetGroup(boardID, groupID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" then
        return nil
    end
    local targetID = Trim(groupID)
    if targetID == "" or type(board.groups) ~= "table" then
        return nil
    end
    return board.groups[targetID]
end

function Data:GetGroupMembers(boardID, groupID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" then
        return {}
    end
    local targetID = Trim(groupID)
    if targetID == "" then
        return {}
    end
    local members = {}
    for _, element in ipairs(board.elements or {}) do
        if element.groupID == targetID then
            members[#members + 1] = element
        end
    end
    table.sort(members, function(a, b)
        return (tonumber(a.z) or 0) < (tonumber(b.z) or 0)
    end)
    return members
end

function Data:SetGroupFlag(boardID, groupID, flag, value)
    if flag ~= "hidden" and flag ~= "locked" then
        return false
    end
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local targetID = Trim(groupID)
    if targetID == "" or type(board.groups) ~= "table" or type(board.groups[targetID]) ~= "table" then
        return false
    end
    local beforeGroups = board.groups
    local afterGroups = DeepCopy(board.groups)
    afterGroups[targetID][flag] = value == true
    CommitBatch(self, boardID, {}, {}, beforeGroups, afterGroups, "setGroupFlag")
    return true
end

function Data:RenameGroup(boardID, groupID, name)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local targetID = Trim(groupID)
    if targetID == "" or type(board.groups) ~= "table" or type(board.groups[targetID]) ~= "table" then
        return false
    end
    local groupName = Trim(name)
    if groupName == "" then
        groupName = targetID
    end
    local beforeGroups = board.groups
    local afterGroups = DeepCopy(board.groups)
    afterGroups[targetID].name = groupName
    CommitBatch(self, boardID, {}, {}, beforeGroups, afterGroups, "renameGroup")
    return true
end

T.RegisterColdFile("visualBoard.editorLoaded", function()

-- 至暗之夜分散模板：拆为两个独立画板（板A=P2前三轮单帧；板B=P2第四轮→P3接圈双帧）。
-- 取真实专精图标 fileID（走 12.0 API GetSpecializationInfoForClassID，不硬编码路径）。
-- 第 4 个返回值即图标 fileID/路径，直接烘焙进 person.icon.texture。无映射返回 nil。
local function TemplateSpecIcon(classID, specIndex)
    if type(GetSpecializationInfoForClassID) ~= "function" then
        return nil
    end
    local _, _, _, icon = GetSpecializationInfoForClassID(classID, specIndex)
    return icon
end

local function TemplateSpellIcon(spellID, fallback)
    local id = tonumber(spellID)
    if id and C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(id)
        if icon then
            return icon
        end
    end
    if id and type(GetSpellTexture) == "function" then
        local icon = GetSpellTexture(id)
        if icon then
            return icon
        end
    end
    return fallback
end

local function TemplateAddIcon(self, boardID, x, y, texture, size, borderSize)
    return self:AddElementAt(boardID, "icon", x, y, {
        params = {
            texture = texture,
            size = size or 42,
            shape = "circle",
            borderSize = borderSize or 0,
            borderColor = "000000",
        },
    })
end

-- 建一个 person 并烘焙：专精图标 texture + 浅绿圆底 + 名签默认下方。
-- classID/specIndex 取真实 spec 图标；circle 沿用 CreateDefaultElement 默认（浅绿 33CC66 alpha0.5 radius58）。
-- 返回 element（失败 nil）。
local function TemplateAddPerson(self, boardID, slotName, x, y, classID, specIndex)
    local element = self:AddPersonAt(boardID, slotName, x, y)
    if type(element) ~= "table" then
        return nil
    end
    local icon = TemplateSpecIcon(classID, specIndex)
    self:UpdateElement(boardID, element.id, {
        params = {
            icon = { texture = icon },
            text = { position = "bottom" },
        },
    })
    return self:GetElement(boardID, element.id)
end

-- 共用基线：encounterID=3183 背景 + 中心十字（横竖 2 rect）+ 底部"门口"。
-- 标记不再共用：两板布局不同、标记落在不同人身上，由各 Apply 函数自带（见 TemplatePlaceMarkers）。
-- 返回 created（本 helper 新增的元素数 = 2 十字 + 1 门口 = 3）。
local function TemplateBaseline(self, boardID)
    self:SetBackgroundEncounter(boardID, 3183)
    local CX, CY = 800, 450  -- 中心十字交点
    -- 十字：横 rect + 竖 rect（白色）。
    self:AddElementAt(boardID, "shape", CX, CY, {
        params = { shapeKind = "rect", color = "FFFFFF", alpha = 0.85, w = 1200, h = 10 },
    })
    self:AddElementAt(boardID, "shape", CX, CY, {
        params = { shapeKind = "rect", color = "FFFFFF", alpha = 0.85, w = 10, h = 640 },
    })
    -- 底部"门口"（绿色 00FF8C）。
    self:AddElementAt(boardID, "text", CX, 820, {
        params = { text = "门口", color = "00FF8C", fontSize = 30 },
    })
    return 3
end

-- 共用：按 { markerIndex, x, y } 表批量落团队标记（size40），返回新增数。
local function TemplatePlaceMarkers(self, boardID, markers)
    local count = 0
    for _, m in ipairs(markers) do
        self:AddElementAt(boardID, "marker", m[2], m[3], { params = { markerIndex = m[1], size = 40 } })
        count = count + 1
    end
    return count
end

-- 共用职业/专精映射：人员名→(classID, specIndex)。模板人员都用这套图标映射。
-- 奶德=德鲁伊(11)恢复(4)；冰法=法师(8)冰(3)；增辉=唤魔师(13)增辉(3)；LR=猎人(3)野兽(1)；
-- 噬灭=术士(9)痛苦(1)；SS=术士(9)毁灭(3)；DK=死亡骑士(6)邪恶(3)；元素=萨满(7)元素(1)；
-- 咕咕=德鲁伊(11)平衡(1)；DKT=死亡骑士(6)鲜血(1)；ZST=战士(1)防护(3)；AM=牧师(5)暗影(3)；
-- 奶萨=萨满(7)恢复(3)；JLM=牧师(5)戒律(1)；CJQ=圣骑士(2)惩戒(3)。
local TEMPLATE_SPEC = {
    ["奶德1"] = { 11, 4 }, ["奶德2"] = { 11, 4 },
    ["冰法1"] = { 8, 3 },
    ["增辉1"] = { 13, 3 }, ["增辉2"] = { 13, 3 },
    ["LR1"] = { 3, 1 }, ["LR2"] = { 3, 1 },
    ["噬灭1"] = { 9, 1 },
    ["SS1"] = { 9, 3 }, ["SS2"] = { 9, 3 },
    ["DK1"] = { 6, 3 }, ["DK2"] = { 6, 3 },
    ["元素1"] = { 7, 1 },
    ["咕咕1"] = { 11, 1 }, ["咕咕2"] = { 11, 1 },
    ["DKT1"] = { 6, 1 },
    ["ZST1"] = { 1, 3 },
    ["AM1"] = { 5, 3 },
    ["奶萨1"] = { 7, 3 },
    ["JLM1"] = { 5, 1 },
    ["CJQ1"] = { 2, 3 },
}

-- 共用：按 { slot, x, y } 表批量落 person（图标查 TEMPLATE_SPEC），返回 slot→element 映射 + 新增数。
local function TemplatePlacePersons(self, boardID, persons)
    local elemBySlot = {}
    local count = 0
    for _, def in ipairs(persons) do
        local spec = TEMPLATE_SPEC[def[1]]
        local element = TemplateAddPerson(self, boardID, def[1], def[2], def[3], spec and spec[1], spec and spec[2])
        if type(element) == "table" then
            elemBySlot[def[1]] = element
            count = count + 1
        end
    end
    return elemBySlot, count
end

local function TemplateSetPersonCircles(self, boardID, elemBySlot, enabled)
    for _, element in pairs(elemBySlot or {}) do
        if type(element) == "table" then
            self:UpdateElement(boardID, element.id, {
                params = {
                    circle = { enabled = enabled == true },
                },
            })
        end
    end
end

local function TemplateFinalizeSingleSlide(self, boardID, slideName)
    self:RenameSlide(boardID, 1, slideName)
    self:SetSlideMorph(boardID, 1, 1.2)
    self:SetSlideHold(boardID, 1, 10.0)
end

local function TemplateAddText(self, boardID, x, y, text, color, fontSize)
    return self:AddElementAt(boardID, "text", x, y, {
        params = { text = text, color = color or "FFFFFF", fontSize = fontSize or 24 },
    })
end

local function TemplateAddCircle(self, boardID, x, y, radius, color, alpha)
    return self:AddElementAt(boardID, "shape", x, y, {
        params = { shapeKind = "circle", shapeStyle = "solid", color = color or "FFFF66", alpha = alpha or 0.75, radius = radius or 60 },
    })
end

local function TemplateHideElementsOnSlide(self, boardID, elements, slideIndex)
    for _, element in ipairs(elements or {}) do
        if type(element) == "table" and element.id then
            self:SetSlideOverride(boardID, slideIndex, element.id, "hidden", true)
        end
    end
end

local function TemplateOverrideElementPosition(self, boardID, slideIndex, element, x, y)
    if type(element) == "table" and element.id then
        self:SetSlideOverride(boardID, slideIndex, element.id, "x", x)
        self:SetSlideOverride(boardID, slideIndex, element.id, "y", y)
    end
end

local function TemplateAddClockBossIcon(self, boardID, x, y)
    local icon = self:AddElementAt(boardID, "icon", x, y, {
        params = { encounterID = 3183, encounterIcon = 7448204, size = 76, shape = "circle", borderSize = 3, borderColor = "000000" },
    })
    return icon
end

local function TemplateAddSeedIcon(self, boardID, x, y)
    return self:AddElementAt(boardID, "icon", x, y, {
        params = { spellID = 1253031, size = 32, shape = "circle", borderSize = 0, borderColor = "000000" },
    })
end

local function TemplateAddDoorIcon(self, boardID, x, y)
    return TemplateAddIcon(self, boardID, x, y, "Interface\\Icons\\INV_Misc_Rune_11", 44, 0)
end

local function TemplateAddClockNumber(self, boardID, x, y, text, fontSize)
    return TemplateAddText(self, boardID, x, y, text, "55FF88", fontSize or 30)
end

-- 板「P1流程图」：单帧流程批注（大团/编号/箭头/阶段说明）。
function Data:ApplyTemplate_P1Flow(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    self:SetBackgroundEncounter(boardID, 3183)
    local created = 0

    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 720, 255 }, { 4, 865, 255 }, { 7, 800, 380 }, { 8, 890, 465 }, { 2, 805, 535 },
        { 1, 705, 455 },
    })

    self:AddElementAt(boardID, "text", 285, 175, {
        params = { text = "P1流程图", color = "FFFFFF", fontSize = 42 },
    })
    created = created + 1

    local tankIcon = "Interface\\Icons\\Ability_Warrior_DefensiveStance"
    local icons = {
        { 390, 465, tankIcon, 34, false }, { 435, 465, nil, 44, true },
        { 550, 690, tankIcon, 34, false }, { 595, 690, nil, 44, true },
        { 705, 810, nil, 44, true }, { 690, 860, tankIcon, 34, false },
    }
    for _, icon in ipairs(icons) do
        if icon[5] then
            self:AddElementAt(boardID, "icon", icon[1], icon[2], {
                params = { encounterID = 3183, encounterIcon = 7448204, size = icon[4], shape = "circle" },
            })
        else
            TemplateAddIcon(self, boardID, icon[1], icon[2], icon[3], icon[4])
        end
        created = created + 1
    end

    local groups = {
        { 520, 470, "大团", "7", 450, 535 },
        { 610, 650, "大团", "456", 505, 650 },
        { 720, 760, "大团", "123", 675, 765 },
    }
    for _, g in ipairs(groups) do
        self:AddElementAt(boardID, "shape", g[1], g[2], {
            params = { shapeKind = "circle", shapeStyle = "solid", color = "E8E8F0", alpha = 0.85, radius = 45 },
        })
        self:AddElementAt(boardID, "text", g[1], g[2], {
            params = { text = g[3], color = "FFFFFF", fontSize = 20 },
        })
        self:AddElementAt(boardID, "text", g[5], g[6], {
            params = { text = g[4], color = "FFFFFF", fontSize = 38 },
        })
        created = created + 3
    end

    local flowArrows = {
        { 650, 575, 595, 490, "00FF8C" },
        { 680, 620, 620, 565, "00FF8C" },
        { 735, 710, 625, 615, "FFFFFF" },
        { 820, 660, 650, 590, "FFFFFF" },
        { 835, 620, 675, 560, "FFFFFF" },
    }
    for _, a in ipairs(flowArrows) do
        self:AddElementAt(boardID, "shape", a[1], a[2], {
            end_x = a[3], end_y = a[4],
            params = { shapeKind = "arrow", color = a[5], alpha = 0.95, arrowSize = 24, thickness = 5 },
        })
        created = created + 1
    end

    local notes = {
        { 520, 405, "7.处理打断3和符文3,\n符文3结束进入P1.5", "FFFFFF", 18 },
        { 680, 450, "6.处理第二轮射线", "FFFFFF", 17 },
        { 760, 505, "5.处理第二轮符文站位", "FFFFFF", 17 },
        { 760, 585, "4.处理第二轮打断,\nJLM1吃增辉2的时间螺旋\n三拉种子", "FFFFFF", 17 },
        { 930, 645, "3.处理射线，有可能逆时针也可能顺时针\n先反向跨过第一道1秒不生效的线，然后\n正向移动20码", "FFFFFF", 17 },
        { 900, 760, "2.符文站位，其中外场坦克点\n红场、蓝场都是只有一个治疗,\n由治疗点STT符文。但是是永远1,\n治疗会被随机分到蓝场或者红场,\n蓝场固定3，红场固定25", "FFFFFF", 16 },
        { 820, 870, "1.BOSS带到月亮，处理4次打断,\n然后转火水晶，JLM1双拉种子,\n增辉2抢1个种子到JLM1的位置", "FFFFFF", 16 },
        { 1120, 850, "这一侧是门口", "FFFFFF", 30 },
    }
    for _, note in ipairs(notes) do
        self:AddElementAt(boardID, "text", note[1], note[2], {
            params = { text = note[3], color = note[4], fontSize = note[5] },
        })
        created = created + 1
    end

    TemplateFinalizeSingleSlide(self, boardID, "P1流程图")
    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP1FlowApplied board=%s elements=%d slides=1", tostring(boardID), created))
    end
    return created
end

-- 板「P1.5站位图」：单帧 20 人外围站位 + 主要团队标记。
function Data:ApplyTemplate_P15Positions(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    self:SetBackgroundEncounter(boardID, 3183)
    local created = 0

    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 735, 300 }, { 4, 865, 300 }, { 7, 800, 390 }, { 8, 885, 455 }, { 2, 805, 535 },
        { 1, 705, 455 }, { 5, 710, 780 },
    })

    self:AddElementAt(boardID, "text", 800, 110, {
        params = { text = "P1.5站位图", color = "FFFFFF", fontSize = 42 },
    })
    created = created + 1
    self:AddElementAt(boardID, "text", 800, 850, {
        params = { text = "门口", color = "00FF8C", fontSize = 30 },
    })
    created = created + 1

    local persons = {
        { "增辉1", 550, 210 }, { "噬灭1", 430, 340 }, { "咕咕2", 430, 560 }, { "LR1", 550, 705 },
        { "SS1", 690, 825 },   { "DK1", 660, 385 },   { "DK2", 620, 475 },   { "奶德2", 660, 565 },
        { "JLM1", 710, 620 },  { "LR2", 800, 650 },   { "ZST1", 870, 620 },  { "AM1", 950, 585 },
        { "CJQ1", 970, 485 },  { "奶德1", 970, 560 }, { "冰法1", 1190, 340 }, { "SS2", 1185, 510 },
        { "增辉2", 1065, 210 }, { "元素1", 1155, 620 }, { "DKT1", 980, 820 }, { "奶萨1", 805, 250 },
    }
    local elemBySlot, n = TemplatePlacePersons(self, boardID, persons)
    created = created + n
    TemplateSetPersonCircles(self, boardID, elemBySlot, false)

    local seedOverlays = {
        { 550, 235 }, { 735, 250 }, { 865, 250 }, { 430, 585 },
        { 550, 730 }, { 690, 850 }, { 980, 845 },
    }
    for _, icon in ipairs(seedOverlays) do
        TemplateAddSeedIcon(self, boardID, icon[1], icon[2])
        created = created + 1
    end

    TemplateFinalizeSingleSlide(self, boardID, "P1.5站位图")
    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP15PositionsApplied board=%s elements=%d slides=1", tostring(boardID), created))
    end
    return created
end

-- 板「P2分担示意图」：单帧分担站位，保留十字锚点与 5 个团队标记。
function Data:ApplyTemplate_P2SoakAssign(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    local created = TemplateBaseline(self, boardID)

    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 720, 255 }, { 4, 865, 255 }, { 7, 800, 380 }, { 8, 895, 455 }, { 2, 795, 535 },
        { 1, 705, 455 }, { 5, 705, 780 },
    })

    self:AddElementAt(boardID, "text", 385, 185, {
        params = { text = "P2分担示意图", color = "FFFFFF", fontSize = 42 },
    })
    created = created + 1

    local persons = {
        { "JLM1", 795, 250 },  { "元素1", 795, 305 }, { "奶德2", 795, 360 }, { "增辉1", 850, 360 },
        { "奶德1", 795, 425 }, { "咕咕2", 620, 470 }, { "LR2", 675, 470 },   { "DK1", 730, 470 },
        { "SS1", 780, 470 },   { "LR1", 840, 455 },   { "SS2", 900, 455 },   { "冰法1", 960, 455 },
        { "增辉2", 1020, 455 }, { "噬灭1", 1080, 455 }, { "AM1", 745, 585 },   { "奶萨1", 850, 585 },
        { "DK2", 795, 595 },   { "DKT1", 795, 655 },  { "CJQ1", 795, 715 },  { "ZST1", 795, 775 },
    }
    local elemBySlot, n = TemplatePlacePersons(self, boardID, persons)
    created = created + n
    TemplateSetPersonCircles(self, boardID, elemBySlot, false)

    local seedOverlays = {
        { 795, 275 }, { 850, 385 }, { 620, 495 }, { 675, 495 },
        { 730, 495 }, { 745, 610 }, { 1020, 480 },
    }
    for _, icon in ipairs(seedOverlays) do
        TemplateAddSeedIcon(self, boardID, icon[1], icon[2])
        created = created + 1
    end

    self:AddElementAt(boardID, "text", 650, 535, {
        params = { text = "SS1咕咕2", color = "FFFFFF", fontSize = 16 },
    })
    created = created + 1

    TemplateFinalizeSingleSlide(self, boardID, "P2分担示意图")
    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP2SoakAssignApplied board=%s elements=%d slides=1", tostring(boardID), created))
    end
    return created
end

-- 板A「P2分散前三轮」：单帧团簇示意图（基线十字/门口/5 marker + 标题 + 20 人前三轮团簇）。
-- 返回新增元素数量；builtin 板不可改返回 0。
function Data:ApplyTemplate_P2Front(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    local created = TemplateBaseline(self, boardID)

    -- 板A 自带 5 标记：紫钻(3)/绿三角(4)/红叉(7)/骷髅(8)/黄三角(用 1 星)。位置不变。
    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 720, 255 }, { 4, 870, 255 }, { 7, 800, 380 }, { 8, 895, 455 }, { 1, 660, 460 },
    })

    -- 标题（前三轮）。
    self:AddElementAt(boardID, "text", 800, 90, {
        params = { text = "P2前三轮分散示意图", color = "FFFFFF", fontSize = 40 },
    })
    created = created + 1

    -- 20 人前三轮紧密团簇（图标中心 x,y；名签下方）。
    local persons = {
        { "奶德2", 720, 300 }, { "奶德1", 865, 315 }, { "冰法1", 925, 380 }, { "增辉1", 720, 400 },
        { "LR1", 845, 385 },   { "噬灭1", 625, 425 }, { "SS1", 685, 465 },   { "SS2", 905, 455 },
        { "DK1", 685, 585 },   { "DK2", 795, 645 },   { "增辉2", 905, 585 },  { "元素1", 758, 352 },
        { "咕咕2", 832, 350 },  { "DKT1", 800, 425 },  { "ZST1", 882, 418 },  { "AM1", 742, 508 },
        { "奶萨1", 805, 512 },  { "LR2", 868, 508 },   { "JLM1", 722, 548 },  { "CJQ1", 852, 562 },
    }
    local _, n = TemplatePlacePersons(self, boardID, persons)
    created = created + n

    -- 单帧：命名 + hold≈10 + morph 1.2。
    self:RenameSlide(boardID, 1, "P2前三轮分散示意图")
    self:SetSlideMorph(boardID, 1, 1.2)
    self:SetSlideHold(boardID, 1, 10.0)

    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP2FrontApplied board=%s elements=%d slides=1", tostring(boardID), created))
    end
    return created
end

-- 板B「P2转P3分散圈」：双帧 morph（slide1=P2第四轮网格 → slide2=P3接圈批注层淡入）。
-- 模型：20 人/十字/5 marker 两帧位置相同不动（基线，无 override）；只有标题与 P3 批注层用 hidden 覆写区分帧。
-- 返回新增元素数量；builtin 板不可改返回 0。
function Data:ApplyTemplate_P2toP3(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    local created = TemplateBaseline(self, boardID)

    -- 板B 自带 5 标记（#49 落点）：紫钻(3)/绿三角(4)/红叉(7)/骷髅(8)/黄三角(用 1 星)。
    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 700, 218 }, { 4, 885, 205 }, { 7, 800, 400 }, { 8, 875, 478 }, { 1, 795, 550 },
    })

    -- 标题：title2(P2第四轮)仅 slide-1、title3(P3接圈)仅 slide-2，均基线建 + 另一帧 hidden 覆写。
    local title2 = self:AddElementAt(boardID, "text", 800, 90, {
        params = { text = "P2第四轮分散示意图", color = "FFFFFF", fontSize = 40 },
    })
    local title3 = self:AddElementAt(boardID, "text", 800, 85, {
        params = { text = "P3接圈和拿种子安排", color = "FFFFFF", fontSize = 40 },
    })
    created = created + 2

    -- 20 人网格基线（=图2第四轮紧密菱形；两帧都显示、位置不变，故不写 person override）。
    local persons = {
        { "噬灭1", 700, 285 }, { "SS2", 885, 270 },  { "DK1", 640, 385 },   { "增辉1", 775, 400 },
        { "LR1", 860, 400 },   { "冰法1", 950, 375 }, { "奶德2", 600, 450 }, { "SS1", 715, 480 },
        { "奶德1", 1000, 440 }, { "AM1", 895, 480 },  { "LR2", 650, 545 },   { "咕咕2", 775, 520 },
        { "DKT1", 860, 530 },  { "DK2", 965, 540 },   { "元素1", 670, 605 }, { "ZST1", 790, 590 },
        { "增辉2", 905, 610 },  { "JLM1", 745, 660 },  { "奶萨1", 815, 685 }, { "CJQ1", 880, 660 },
    }
    local elemBySlot, n = TemplatePlacePersons(self, boardID, persons)
    created = created + n

    -- P3 批注层（全部基线建；下面统一对 slide-1 打 hidden 覆写，只在 slide-2 淡入）。
    -- (a) 12 黄圈 = solid circle(FFD11A r30) + 紧贴下方标签 text(左圈/右圈)。
    local circles = {
        { 620, 250, "左圈" },  { 545, 335, "右圈" },  { 1020, 335, "左圈" }, { 950, 248, "右圈" },
        { 505, 458, "左圈" },  { 505, 560, "右圈" },  { 1090, 560, "左圈" }, { 1090, 445, "右圈" },
        { 640, 700, "左圈" },  { 748, 780, "右圈" },  { 870, 780, "左圈" },  { 968, 700, "右圈" },
    }
    local p3 = {}  -- P3 批注层元素，统一打 slide-1 hidden
    for index, c in ipairs(circles) do
        local circ = self:AddElementAt(boardID, "shape", c[1], c[2], {
            z = -900 + index,
            params = { shapeKind = "circle", shapeStyle = "solid", color = "FFD11A", alpha = 0.85, radius = 30 },
        })
        p3[#p3 + 1] = circ
        local label = self:AddElementAt(boardID, "text", c[1], c[2] + 42, {
            params = { text = c[3], color = "FFD11A", fontSize = 16 },
        })
        p3[#p3 + 1] = label
        created = created + 2
    end

    -- (b) 12 绿箭头：接圈人 grid 位 → 对应黄圈（与上面 12 行一一对应）。
    local arrows = {
        { "噬灭1", 620, 250 }, { "DK1", 545, 335 },   { "冰法1", 1020, 335 }, { "SS2", 950, 248 },
        { "SS1", 505, 458 },   { "LR2", 505, 560 },   { "DK2", 1090, 560 },   { "AM1", 1090, 445 },
        { "元素1", 640, 700 }, { "ZST1", 748, 780 },  { "CJQ1", 870, 780 },   { "DKT1", 968, 700 },
    }
    for _, a in ipairs(arrows) do
        local from = elemBySlot[a[1]]
        if type(from) == "table" then
            local arrow = self:AddElementAt(boardID, "shape", from.x, from.y, {
                end_x = a[2], end_y = a[3],
                params = { shapeKind = "arrow", color = "33FF66", alpha = 0.95, arrowSize = 22 },
            })
            p3[#p3 + 1] = arrow
            created = created + 1
        end
    end

    -- (c) 6 段批注 text（多行 \n；canvas 居中渲染，左对齐需改 canvas 故此处用多行居中）。
    local notes = {
        { 240, 180,  "增辉1加速第一时间拿种子\n噬灭1接左圈\nDK1接右圈" },
        { 1360, 180, "LR1加速第一时间拿种子\n冰法1接左圈\nSS2接右圈" },
        { 170, 455,  "奶德2加速第一时间拿种子\nSS1接左圈\nLR2接右圈" },
        { 1430, 455, "奶德1加速第一时间拿种子\nDK2接左圈\nAM1接右圈" },
        { 265, 820,  "咕咕2加速第一时间拿种子\n元素1接左圈\nZST1大跳接右圈\nJLM1站桩刷血" },
        { 1340, 820, "增辉2加速第一时间拿种子\nCJQ1接左圈\nDKT1接右圈\n奶萨1站桩刷血" },
    }
    for _, note in ipairs(notes) do
        local txt = self:AddElementAt(boardID, "text", note[1], note[2], {
            params = { text = note[3], color = "FFFFFF", fontSize = 17 },
        })
        p3[#p3 + 1] = txt
        created = created + 1
    end

    -- 双帧：slide-1「P2第四轮」hold≈10、slide-2「P3接圈和拿种子安排」hold≈12。
    self:RenameSlide(boardID, 1, "P2第四轮分散示意图")
    self:SetSlideMorph(boardID, 1, 1.2)
    self:SetSlideHold(boardID, 1, 10.0)
    local _, slide2 = self:AddSlide(boardID, "P3接圈和拿种子安排")
    if not slide2 then
        return created
    end
    self:SetSlideMorph(boardID, slide2, 2.0)
    self:SetSlideHold(boardID, slide2, 12.0)

    -- 标题帧区分：title2 仅 slide-1、title3 仅 slide-2。
    if type(title2) == "table" then
        self:SetSlideOverride(boardID, slide2, title2.id, "hidden", true)
    end
    if type(title3) == "table" then
        self:SetSlideOverride(boardID, 1, title3.id, "hidden", true)
    end
    -- P3 批注层：全部 slide-1 hidden=true，只在 slide-2 淡入。
    for _, el in ipairs(p3) do
        if type(el) == "table" then
            self:SetSlideOverride(boardID, 1, el.id, "hidden", true)
        end
    end

    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP2toP3Applied board=%s elements=%d slides=2", tostring(boardID), created))
    end
    return created
end

-- 板「P3时钟站位法」：单帧左右两组时钟站位，白圈内按 12/10/9/8/6/4/3/2 标注。
function Data:ApplyTemplate_P3ClockPositions(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    self:SetBackgroundEncounter(boardID, 3183)
    local created = 0

    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 735, 285 }, { 4, 865, 285 }, { 7, 800, 410 }, { 8, 880, 475 }, { 2, 805, 555 }, { 1, 720, 475 },
    })

    TemplateAddText(self, boardID, 800, 100, "时钟站位法", "FFFFFF", 44); created = created + 1
    TemplateAddText(self, boardID, 800, 835, "门口", "00FF8C", 32); created = created + 1
    TemplateAddText(self, boardID, 800, 660, "BOSS的位置即为12点钟方向\n坦克永远是12点钟位置\n当圈里没有10个人时\n可以根据自己的位置发生偏移\n但是不应偏移太多", "FFFFFF", 18); created = created + 1

    TemplateAddCircle(self, boardID, 485, 480, 185, "F2F0F8", 0.82); created = created + 1
    TemplateAddCircle(self, boardID, 1120, 485, 185, "F2F0F8", 0.82); created = created + 1
    TemplateAddClockBossIcon(self, boardID, 485, 280); created = created + 1
    TemplateAddClockBossIcon(self, boardID, 1120, 290); created = created + 1

    local numbers = {
        { 485, 350, "12" }, { 370, 410, "10" }, { 325, 520, "9" }, { 375, 645, "8" },
        { 485, 725, "6" }, { 600, 650, "4" }, { 650, 535, "3" }, { 605, 405, "2" },
        { 1120, 360, "12" }, { 1005, 430, "10" }, { 970, 535, "9" }, { 1010, 660, "8" },
        { 1120, 720, "6" }, { 1245, 660, "4" }, { 1290, 535, "3" }, { 1250, 420, "2" },
    }
    for _, n in ipairs(numbers) do
        TemplateAddClockNumber(self, boardID, n[1], n[2], n[3], 32)
        created = created + 1
    end

    local persons = {
        { "DK1", 410, 435 }, { "ZST1", 495, 380 }, { "LR2", 585, 435 }, { "噬灭1", 365, 510 },
        { "咕咕1", 485, 515 }, { "元素1", 640, 525 }, { "SS1", 410, 605 }, { "JLM1", 500, 675 },
        { "增辉1", 590, 635 }, { "奶德2", 500, 520 },
        { "DK2", 1035, 450 }, { "DKT1", 1125, 405 }, { "CJQ1", 1210, 455 }, { "冰法1", 990, 540 },
        { "增辉2", 1130, 525 }, { "LR1", 1260, 565 }, { "SS2", 1045, 625 }, { "奶德1", 1130, 635 },
        { "AM1", 1215, 655 }, { "奶萨1", 1120, 720 },
    }
    local elemBySlot, n = TemplatePlacePersons(self, boardID, persons)
    created = created + n
    TemplateSetPersonCircles(self, boardID, elemBySlot, false)

    self:RenameSlide(boardID, 1, "P3时钟站位法")
    self:SetSlideMorph(boardID, 1, 1.0)
    self:SetSlideHold(boardID, 1, 6.0)
    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP3ClockPositionsApplied board=%s elements=%d slides=1", tostring(boardID), created))
    end
    return created
end

local function TemplateAddAbsorbConstellationFrame(self, boardID, opts)
    local created = 0
    local elements = {}
    local backgroundIndex = 0
    local function add(element, count)
        if type(element) == "table" then
            elements[#elements + 1] = element
        end
        created = created + (tonumber(count) or 1)
    end
    local function addBackgroundCircle(element)
        if type(element) == "table" then
            backgroundIndex = backgroundIndex + 1
            element.z = -1000 + backgroundIndex
        end
        add(element)
    end
    for _, c in ipairs(opts.yellowCircles or {}) do
        addBackgroundCircle(TemplateAddCircle(self, boardID, c[1], c[2], c[3] or 78, "E6DF55", 0.72))
    end
    for _, c in ipairs(opts.purpleCircles or {}) do
        addBackgroundCircle(TemplateAddCircle(self, boardID, c[1], c[2], c[3] or 52, "A020D0", 0.72))
    end
    for _, b in ipairs(opts.bossIcons or {}) do
        local icon = TemplateAddClockBossIcon(self, boardID, b[1], b[2])
        if type(icon) == "table" then
            elements[#elements + 1] = icon
        end
        created = created + 1
    end
    for _, t in ipairs(opts.texts or {}) do
        add(TemplateAddText(self, boardID, t[1], t[2], t[3], t[4] or "FFFFFF", t[5] or 28))
    end
    for _, n in ipairs(opts.numbers or {}) do
        add(TemplateAddClockNumber(self, boardID, n[1], n[2], n[3], n[4] or 20))
    end
    for _, icon in ipairs(opts.seedIcons or {}) do
        add(TemplateAddSeedIcon(self, boardID, icon[1], icon[2]))
    end
    for _, icon in ipairs(opts.doorIcons or {}) do
        add(TemplateAddDoorIcon(self, boardID, icon[1], icon[2]))
    end
    return elements, created
end

-- 板「P3-1左右分组」：双帧 morph（05:48/05:50 → 06:08/06:10）。
function Data:ApplyTemplate_P31Groups(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    self:SetBackgroundEncounter(boardID, 3183)
    local created = 0
    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 735, 300 }, { 4, 865, 300 }, { 7, 800, 425 }, { 8, 890, 500 }, { 2, 805, 595 }, { 1, 710, 500 }, { 5, 710, 780 },
    })
    TemplateAddText(self, boardID, 800, 845, "门口", "00FF8C", 32); created = created + 1

    local slide1Persons = {
        { "增辉1", 600, 545 }, { "噬灭1", 660, 545 }, { "ZST1", 700, 585 }, { "DK1", 620, 625 },
        { "奶德2", 620, 700 }, { "SS1", 675, 670 }, { "LR2", 715, 715 }, { "元素1", 740, 755 },
        { "JLM1", 775, 720 }, { "咕咕2", 820, 760 },
        { "DKT1", 1035, 540 }, { "LR1", 1085, 540 }, { "SS2", 1125, 615 }, { "冰法1", 1085, 670 },
        { "AM1", 1155, 700 }, { "CJQ1", 1005, 735 }, { "奶萨1", 1045, 760 }, { "DK2", 1090, 755 },
        { "奶德1", 1120, 795 }, { "增辉2", 965, 770 },
    }
    local elemBySlot, n = TemplatePlacePersons(self, boardID, slide1Persons)
    created = created + n
    TemplateSetPersonCircles(self, boardID, elemBySlot, false)

    local slide2Persons = {
        { "增辉1", 610, 500 }, { "噬灭1", 650, 500 }, { "ZST1", 690, 555 }, { "DK1", 640, 590 },
        { "奶德2", 615, 690 }, { "SS1", 620, 735 }, { "LR2", 680, 730 }, { "元素1", 725, 760 },
        { "JLM1", 770, 735 }, { "咕咕2", 800, 780 },
        { "DKT1", 1035, 500 }, { "LR1", 1085, 500 }, { "SS2", 1130, 560 }, { "冰法1", 1095, 630 },
        { "AM1", 1145, 675 }, { "CJQ1", 1010, 705 }, { "奶萨1", 1040, 725 }, { "DK2", 1090, 720 },
        { "奶德1", 1115, 760 }, { "增辉2", 965, 735 },
    }
    local layer1, c1 = TemplateAddAbsorbConstellationFrame(self, boardID, {
        yellowCircles = { { 590, 560, 82 }, { 570, 690, 78 }, { 710, 735, 78 }, { 1040, 585, 82 }, { 1070, 735, 78 }, { 1150, 655, 78 } },
        purpleCircles = { { 610, 555, 48 }, { 610, 700, 48 }, { 735, 735, 48 }, { 1080, 600, 48 }, { 1040, 720, 48 }, { 1160, 655, 48 } },
        bossIcons = { { 710, 630 }, { 980, 640 } },
        seedIcons = { { 600, 545 }, { 620, 700 }, { 1040, 585 }, { 1070, 735 } },
        numbers = { { 1130, 510, "6" }, { 1000, 545, "3" }, { 1000, 640, "12" }, { 1035, 700, "12" }, { 1130, 720, "3" }, { 1180, 625, "9" } },
        texts = {
            { 800, 150, "P3-1", "FFFFFF", 46 },
            { 530, 310, "05:48左吸球", "FFFFFF", 42 },
            { 1080, 310, "05:50右星座", "FFFFFF", 42 },
            { 500, 520, "左", "FFFFFF", 42 }, { 500, 720, "中", "FFFFFF", 42 }, { 665, 805, "右", "FFFFFF", 42 },
            { 560, 825, "左吸球时找对自己的球即可", "FFFFFF", 18 },
            { 1120, 830, "右星座大家都是站在靠近BOSS或者靠近中间的一侧,\n这样能第一时间合星座，八奔的处理成1+2，而非2+1,\n2+1会出现超过15秒仍然没有合完最终炸团的问题\n左星座时同理", "FFFFFF", 18 },
        },
    })
    created = created + c1

    local layer2, c2 = TemplateAddAbsorbConstellationFrame(self, boardID, {
        yellowCircles = { { 600, 545, 78 }, { 610, 700, 80 }, { 745, 740, 78 }, { 1040, 545, 78 }, { 1030, 710, 78 }, { 1160, 680, 76 } },
        purpleCircles = { { 615, 520, 48 }, { 600, 700, 48 }, { 735, 740, 48 }, { 1080, 520, 48 }, { 1010, 705, 48 }, { 1160, 680, 48 } },
        bossIcons = { { 700, 630 }, { 980, 630 } },
        seedIcons = { { 610, 500 }, { 1085, 500 } },
        numbers = { { 620, 500, "6" }, { 720, 470, "9" }, { 640, 585, "12" }, { 570, 650, "3" }, { 680, 735, "3" }, { 710, 785, "9" }, { 760, 650, "12" },
                    { 990, 690, "9" }, { 1000, 615, "12" }, { 1010, 765, "6" }, { 1110, 610, "12" }, { 1160, 690, "3" }, { 1165, 520, "6" } },
        texts = {
            { 800, 120, "P3-1", "FFFFFF", 46 },
            { 560, 290, "06:08左星座", "FFFFFF", 42 },
            { 1070, 290, "06:10右吸球", "FFFFFF", 42 },
            { 315, 560, "06:31\n左增辉1开种子", "FFFFFF", 42 },
            { 1285, 585, "06:31\n右LR1开种子", "FFFFFF", 42 },
            { 1225, 495, "右", "FFFFFF", 42 }, { 1225, 675, "中", "FFFFFF", 42 }, { 915, 795, "左", "FFFFFF", 42 },
            { 570, 835, "左星座大差不差即可只要不互炸就行\n但是如果互炸，未按照时钟站位的\n玩家则判定为站位错误", "FFFFFF", 18 },
            { 1100, 795, "右吸球时找对自己的球即可", "FFFFFF", 18 },
        },
    })
    created = created + c2

    self:RenameSlide(boardID, 1, "05:48/05:50")
    self:SetSlideMorph(boardID, 1, 1.0)
    self:SetSlideHold(boardID, 1, 5.0)
    local _, slide2 = self:AddSlide(boardID, "06:08/06:10")
    if slide2 then
        self:SetSlideMorph(boardID, slide2, 1.0)
        self:SetSlideHold(boardID, slide2, 5.0)
        for _, p in ipairs(slide2Persons) do
            TemplateOverrideElementPosition(self, boardID, slide2, elemBySlot[p[1]], p[2], p[3])
        end
        TemplateHideElementsOnSlide(self, boardID, layer2, 1)
        TemplateHideElementsOnSlide(self, boardID, layer1, slide2)
    end
    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP31GroupsApplied board=%s elements=%d slides=2", tostring(boardID), created))
    end
    return created
end

-- 板「P3-2左右分组」：双帧 morph（06:43/06:45 → 07:03/07:05）。
function Data:ApplyTemplate_P32Groups(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    self:SetBackgroundEncounter(boardID, 3183)
    local created = 0
    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 730, 285 }, { 4, 865, 285 }, { 7, 800, 450 }, { 8, 890, 535 }, { 2, 805, 610 }, { 1, 705, 535 }, { 5, 700, 785 },
    })
    TemplateAddText(self, boardID, 800, 845, "门口", "00FF8C", 32); created = created + 1

    local slide1Persons = {
        { "增辉1", 590, 340 }, { "奶德2", 640, 340 }, { "噬灭1", 680, 340 }, { "ZST1", 640, 395 },
        { "SS1", 560, 485 }, { "咕咕2", 620, 485 }, { "LR2", 670, 485 }, { "JLM1", 585, 555 },
        { "元素1", 650, 555 }, { "奶德1", 710, 555 },
        { "LR1", 985, 335 }, { "SS2", 1035, 335 }, { "冰法1", 1070, 380 }, { "DKT1", 1010, 445 },
        { "CJQ1", 980, 540 }, { "DK1", 1020, 540 }, { "DK2", 1070, 540 }, { "AM1", 1130, 540 },
        { "增辉2", 990, 605 }, { "奶萨1", 1070, 620 },
    }
    local elemBySlot, n = TemplatePlacePersons(self, boardID, slide1Persons)
    created = created + n
    TemplateSetPersonCircles(self, boardID, elemBySlot, false)

    local slide2Persons = {
        { "增辉1", 555, 310 }, { "奶德2", 610, 310 }, { "噬灭1", 655, 310 }, { "ZST1", 600, 370 },
        { "SS1", 535, 455 }, { "咕咕2", 590, 455 }, { "LR2", 640, 455 }, { "JLM1", 555, 535 },
        { "元素1", 610, 535 }, { "奶德1", 660, 535 },
        { "LR1", 1010, 325 }, { "SS2", 1060, 325 }, { "冰法1", 1090, 375 }, { "DKT1", 1040, 435 },
        { "CJQ1", 1000, 535 }, { "DK1", 1040, 535 }, { "DK2", 1080, 535 }, { "AM1", 1130, 535 },
        { "增辉2", 1005, 610 }, { "奶萨1", 1075, 610 },
    }
    local layer1, c1 = TemplateAddAbsorbConstellationFrame(self, boardID, {
        yellowCircles = { { 575, 360, 78 }, { 555, 510, 78 }, { 670, 520, 72 }, { 1010, 350, 78 }, { 1040, 545, 78 } },
        purpleCircles = { { 640, 350, 48 }, { 560, 500, 48 }, { 1030, 350, 48 }, { 1170, 445, 48 } },
        bossIcons = { { 650, 430 }, { 985, 470 } },
        seedIcons = { { 590, 340 }, { 640, 340 }, { 1060, 325 } },
        numbers = { { 535, 315, "6" }, { 650, 300, "9" }, { 615, 420, "12" }, { 530, 475, "3" }, { 520, 575, "6" }, { 635, 555, "3" },
                    { 1045, 245, "6" }, { 985, 405, "12" }, { 995, 540, "12" }, { 1080, 610, "9" }, { 1130, 535, "3" } },
        texts = {
            { 800, 110, "P3-2", "FFFFFF", 46 },
            { 570, 95, "06:45左星座", "FFFFFF", 42 },
            { 1095, 95, "06:43右吸球", "FFFFFF", 42 },
            { 1040, 240, "右", "FFFFFF", 42 }, { 1160, 370, "中", "FFFFFF", 42 }, { 1165, 520, "左", "FFFFFF", 42 },
            { 520, 640, "左星座大差不差即可只要不互炸就行\n但是如果互炸，未按照时钟站位的\n玩家则判定为站位错误\n其中冰法1必定是第一个被点符文的", "FFFFFF", 18 },
            { 1070, 655, "右吸球时找对自己的球即可\n先吸左右然后中间", "FFFFFF", 18 },
        },
    })
    created = created + c1

    local layer2, c2 = TemplateAddAbsorbConstellationFrame(self, boardID, {
        yellowCircles = { { 560, 330, 78 }, { 545, 485, 78 }, { 1015, 340, 78 }, { 1055, 520, 78 } },
        purpleCircles = { { 640, 300, 50 }, { 545, 460, 48 }, { 1080, 345, 48 }, { 1140, 480, 48 } },
        bossIcons = { { 640, 410 }, { 1005, 430 } },
        seedIcons = { { 590, 455 }, { 1040, 535 } },
        doorIcons = { { 675, 270 }, { 940, 285 }, { 590, 385 }, { 1100, 420 } },
        numbers = { { 520, 285, "6" }, { 610, 265, "9" }, { 500, 405, "3" }, { 515, 560, "6" }, { 620, 570, "3" },
                    { 1030, 245, "6" }, { 970, 350, "3" }, { 1075, 440, "12" }, { 1010, 570, "9" }, { 1130, 495, "3" } },
        texts = {
            { 800, 110, "P3-2", "FFFFFF", 46 },
            { 520, 105, "07:03左吸球", "FFFFFF", 42 },
            { 1110, 105, "07:05右星座", "FFFFFF", 42 },
            { 430, 260, "中", "FFFFFF", 42 }, { 650, 230, "左", "FFFFFF", 42 }, { 420, 500, "右", "FFFFFF", 42 },
            { 420, 745, "07:26\n左咕咕2开种子\nSS1放门", "FFFFFF", 42 },
            { 1000, 765, "07:26\n右增辉2开种子\nSS2放门", "FFFFFF", 42 },
            { 555, 610, "左吸球时找对自己的球即可\n先吸右和中\n因为合星座时都站在右和中\nSS1注意转场时门的位置", "FFFFFF", 18 },
            { 1060, 610, "右星座大差不差即可只要不互炸就行\n但是如果互炸，未按照时钟站位的\n玩家则判定为站位错误\n其中LR1必定是第一个被点符文的\nSS2注意转场时门的位置", "FFFFFF", 18 },
        },
    })
    created = created + c2

    self:RenameSlide(boardID, 1, "06:43/06:45")
    self:SetSlideMorph(boardID, 1, 1.0)
    self:SetSlideHold(boardID, 1, 5.0)
    local _, slide2 = self:AddSlide(boardID, "07:03/07:05")
    if slide2 then
        self:SetSlideMorph(boardID, slide2, 1.0)
        self:SetSlideHold(boardID, slide2, 5.0)
        for _, p in ipairs(slide2Persons) do
            TemplateOverrideElementPosition(self, boardID, slide2, elemBySlot[p[1]], p[2], p[3])
        end
        TemplateHideElementsOnSlide(self, boardID, layer2, 1)
        TemplateHideElementsOnSlide(self, boardID, layer1, slide2)
    end
    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP32GroupsApplied board=%s elements=%d slides=2", tostring(boardID), created))
    end
    return created
end

-- 板「P3-3星座吸球」：单帧 P3-3 左吸球/右星座说明。
function Data:ApplyTemplate_P33Constellation(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return 0
    end
    self:SetBackgroundEncounter(boardID, 3183)
    local created = 0
    created = created + TemplatePlaceMarkers(self, boardID, {
        { 3, 735, 325 }, { 4, 865, 355 }, { 7, 800, 490 }, { 8, 880, 590 }, { 2, 805, 640 }, { 1, 720, 590 }, { 5, 710, 780 },
    })
    TemplateAddText(self, boardID, 800, 820, "门口", "00FF8C", 32); created = created + 1
    TemplateAddText(self, boardID, 800, 690, "P3-3", "FFFFFF", 42); created = created + 1
    TemplateAddText(self, boardID, 410, 250, "07:38左吸球", "FFFFFF", 42); created = created + 1
    TemplateAddText(self, boardID, 1200, 250, "07:40右星座", "FFFFFF", 42); created = created + 1

    local persons = {
        { "奶德2", 660, 165 }, { "奶德1", 660, 220 },
        { "LR1", 905, 150 }, { "AM1", 955, 145 }, { "增辉2", 1005, 145 }, { "LR2", 920, 210 }, { "增辉1", 970, 210 },
        { "SS2", 1030, 210 }, { "DKT1", 940, 270 }, { "DK1", 990, 270 }, { "噬灭1", 1015, 330 },
    }
    local elemBySlot, n = TemplatePlacePersons(self, boardID, persons)
    created = created + n
    TemplateSetPersonCircles(self, boardID, elemBySlot, false)

    local _, c = TemplateAddAbsorbConstellationFrame(self, boardID, {
        yellowCircles = { { 685, 145, 78 }, { 960, 205, 90 } },
        purpleCircles = { { 625, 145, 48 }, { 715, 220, 48 }, { 725, 320, 48 } },
        bossIcons = { { 625, 260 }, { 890, 275 } },
        seedIcons = { { 665, 165 } },
        numbers = { { 875, 135, "3", 22 }, { 1015, 110, "6", 22 }, { 910, 335, "12", 22 }, { 1010, 330, "9", 22 } },
        texts = {
            { 630, 160, "右", "FFFFFF", 42 }, { 710, 235, "中", "FFFFFF", 42 }, { 720, 330, "左", "FFFFFF", 42 },
            { 535, 410, "右吸球时找对自己的球即可\n先吸最右，然后中，最后左\n奶德2不吸球，但是要站在右和中\n先罩住右形成通道", "FFFFFF", 18 },
            { 1065, 380, "左星座迎来最强一波，10个人\n需要严格按照时钟站位处理星座\n其中增辉2会被先点", "FFFFFF", 18 },
        },
    })
    created = created + c

    self:RenameSlide(boardID, 1, "P3-3星座吸球")
    self:SetSlideMorph(boardID, 1, 1.0)
    self:SetSlideHold(boardID, 1, 6.0)
    if T and T.debug then
        T.debug(string.format("[VisualBoard] TemplateP33ConstellationApplied board=%s elements=%d slides=1", tostring(boardID), created))
    end
    return created
end

function Data:UpdateBoardMeta(boardID, fields)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true or type(fields) ~= "table" then
        return false
    end
    local name = Trim(fields.name)
    if name ~= "" then
        board.name = name
    end
    self:TouchBoard(board)
    return true
end

function Data:ExportBoardString(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" then
        return nil, "missing"
    end
    local serializer = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local deflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not (serializer and deflate) then
        return nil, "library_missing"
    end
    local payload = DeepCopy(board)
    payload.hash = payload.hash or self:ComputeBoardHash(payload)
    local serialized = serializer:Serialize({
        format = EXPORT_PREFIX,
        version = EXPORT_VERSION,
        board = payload,
    })
    local compressed = deflate:CompressDeflate(serialized, { level = 9 })
    local encoded = deflate:EncodeForWoWAddonChannel(compressed)
    return table.concat({ EXPORT_PREFIX, tostring(EXPORT_VERSION), encoded }, ":")
end

-- 旧版（v1）视觉方案串不再支持：破坏旧数据，不静默规范化吞掉残废 board。
local function RejectLegacyImport()
    if T and T.msg then
        T.msg(L["VISUAL_BOARD_IMPORT_LEGACY"] or "旧版视觉方案串不再支持，请让发送者升级插件后重新导出。")
    end
    return false, "legacy_unsupported"
end

-- 解析失败（格式错误/解压解序列化失败/缺库）：明确报错，不静默吞掉。
local function RejectImportFailure(reason)
    if T and T.msg then
        T.msg(L["VISUAL_BOARD_IMPORT_FAILED"] or "视觉方案串导入失败：内容已损坏或格式无法识别。")
    end
    return false, reason
end

function Data:ImportBoardString(text, sender)
    local value = Trim(text)
    local prefix, versionText, encoded = value:match("^([^:]+):([^:]+):(.+)$")
    if prefix ~= EXPORT_PREFIX or not encoded then
        return RejectImportFailure("invalid_format")
    end
    if tonumber(versionText) == 1 then
        return RejectLegacyImport()
    end
    if tonumber(versionText) ~= EXPORT_VERSION then
        return RejectImportFailure("invalid_format")
    end
    local serializer = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local deflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not (serializer and deflate) then
        return RejectImportFailure("library_missing")
    end
    local decoded = deflate:DecodeForWoWAddonChannel(encoded)
    local decompressed = decoded and deflate:DecompressDeflate(decoded) or nil
    if not decompressed then
        return RejectImportFailure("decode_failed")
    end
    local ok, payload = serializer:Deserialize(decompressed)
    if not ok or type(payload) ~= "table" or payload.format ~= EXPORT_PREFIX then
        return RejectImportFailure("deserialize_failed")
    end
    if tonumber(payload.version) == 1 or IsLegacyBoard(payload.board) then
        return RejectLegacyImport()
    end
    local result = self:MergeReceivedBoards({ [payload.board and payload.board.id or ""] = payload.board }, sender)
    return result.total > 0, result
end

local function EncodePayload(prefix, version, payload, forPrint)
    local serializer = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local deflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not (serializer and deflate) then
        return nil, "library_missing"
    end
    local serialized = serializer:Serialize(payload)
    if not serialized then
        return nil, "serialize_failed"
    end
    local compressed = deflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then
        return nil, "compress_failed"
    end
    local encoded = forPrint and deflate:EncodeForPrint(compressed) or deflate:EncodeForWoWAddonChannel(compressed)
    if not encoded then
        return nil, "encode_failed"
    end
    return table.concat({ prefix, tostring(version), encoded }, ":")
end

function Data:ExportBossBoardsString(bossKeyText)
    local package, reason = self:BuildBossBoardPackage(bossKeyText)
    if not package then
        return nil, reason
    end
    return EncodePayload(BOSS_EXPORT_PREFIX, BOSS_EXPORT_VERSION, package, true)
end

local function DecodePayloadString(text, expectedPrefix, expectedVersion, forPrint)
    local value = Trim(text)
    local prefix, versionText, encoded = value:match("^([^:]+):([^:]+):(.+)$")
    if prefix ~= expectedPrefix or not encoded or tonumber(versionText) ~= expectedVersion then
        return nil, "invalid_format"
    end
    local serializer = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local deflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not (serializer and deflate) then
        return nil, "library_missing"
    end
    local decoded = forPrint and deflate:DecodeForPrint(encoded) or deflate:DecodeForWoWAddonChannel(encoded)
    local decompressed = decoded and deflate:DecompressDeflate(decoded) or nil
    if not decompressed then
        return nil, "decode_failed"
    end
    local ok, payload = serializer:Deserialize(decompressed)
    if not ok or type(payload) ~= "table" then
        return nil, "deserialize_failed"
    end
    return payload
end

function Data:PreviewBossBoardsString(text)
    local payload, reason = DecodePayloadString(text, BOSS_EXPORT_PREFIX, BOSS_EXPORT_VERSION, true)
    if not payload then
        return nil, reason
    end
    if payload.format ~= BOSS_EXPORT_PREFIX or tonumber(payload.version) ~= BOSS_EXPORT_VERSION then
        return nil, "invalid_format"
    end
    local bossKeyText = NormalizeBossKeyText(payload.bossKeyText)
    if not bossKeyText or type(payload.boards) ~= "table" then
        return nil, "invalid_package"
    end
    local count = 0
    for _, board in ipairs(payload.boards) do
        if type(board) == "table" and not IsLegacyBoard(board) then
            count = count + 1
        end
    end
    return {
        bossKeyText = bossKeyText,
        bossName = tostring(payload.bossName or ""),
        encounterID = tonumber(payload.encounterID),
        exporterName = tostring(payload.exporterName or ""),
        exporterVersion = tostring(payload.exporterVersion or ""),
        exportTime = tonumber(payload.exportTime) or 0,
        boardCount = count,
    }
end

function Data:ImportBossBoardsString(text, sender)
    local payload, reason = DecodePayloadString(text, BOSS_EXPORT_PREFIX, BOSS_EXPORT_VERSION, true)
    if not payload then
        return RejectImportFailure(reason)
    end
    if payload.format ~= BOSS_EXPORT_PREFIX or tonumber(payload.version) ~= BOSS_EXPORT_VERSION then
        return RejectImportFailure("invalid_format")
    end
    local result, replaceReason = self:ReplaceBossBoards(payload, sender)
    if not result or result.total <= 0 then
        return false, replaceReason or "empty"
    end
    local semantic = T.SemanticTimeline
    if semantic and semantic.SwitchWorkbenchToBossKeyText and result.bossKeyText ~= "" then
        semantic:SwitchWorkbenchToBossKeyText(result.bossKeyText, "visual_board_import")
    end
    return true, result
end

function Data:DeleteBoard(id)
    local boardID = Trim(id)
    if boardID == "" then
        return false, "empty_id"
    end
    local db = self:EnsureDB()
    local board = db[boardID]
    if type(board) ~= "table" then
        return false, "missing"
    end
    if board.builtin == true then
        return false, "builtin"
    end
    db[boardID] = nil
    if T and T.debug then
        T.debug(string.format("[VisualBoard] BoardDeleted id=%s", tostring(boardID)))
    end
    return true
end

end)

function Data:ExtractBoardReferences(content)
    local refs = {}
    local seen = {}
    for payload in tostring(content or ""):gmatch("{board:([^}]+)}") do
        local id = tostring(payload or ""):match("^([^@]+)") or ""
        id = Trim(id)
        if id ~= "" and not seen[id] then
            seen[id] = true
            refs[#refs + 1] = id
        end
    end
    return refs
end

function Data:CollectReferencedBoards(content, bossKeyText)
    local boards = {}
    for _, ref in ipairs(self:ExtractBoardReferences(content)) do
        local board = self:ResolveBoardRefForBoss(ref, bossKeyText)
        if type(board) == "table" then
            local copy = DeepCopy(board)
            copy.hash = copy.hash or self:ComputeBoardHash(copy)
            copy.received = nil
            boards[board.id] = copy
        end
    end
    return next(boards) and boards or nil
end

function Data:MergeReceivedBoards(boards, sender)
    local result = { total = 0, added = 0, updated = 0, skipped = 0 }
    if type(boards) ~= "table" then
        return result
    end

    local db = self:EnsureDB()
    for id, board in pairs(boards) do
        if type(board) == "table" then
            local normalized = EnsureBoardShape(DeepCopy(board), id)
            if normalized then
                result.total = result.total + 1
                normalized.received = true
                normalized.receivedFrom = tostring(sender or "")
                normalized.hash = normalized.hash or self:ComputeBoardHash(normalized)
                local existing = db[normalized.id]
                local existingHash = existing and (existing.hash or self:ComputeBoardHash(existing)) or nil
                if not existing then
                    db[normalized.id] = normalized
                    result.added = result.added + 1
                elseif existingHash ~= normalized.hash then
                    db[normalized.id] = normalized
                    result.updated = result.updated + 1
                else
                    result.skipped = result.skipped + 1
                end
            end
        end
    end
    if T and T.debug and result.total > 0 then
        T.debug(string.format(
            "[VisualBoard] BoardsMerged total=%d added=%d updated=%d skipped=%d sender=%s",
            result.total,
            result.added,
            result.updated,
            result.skipped,
            tostring(sender or "")
        ))
    end
    return result
end

-- ===== slide CRUD（取代 step；§4.4）=====

-- slides 整表撤销提交（结构性增删改、override 写入共用单一权威）。
local function CommitSlides(self, boardID, beforeSlides, afterSlides, label)
    self:DoCommand({
        label = label or "slides",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) ~= "table" then return end
            target.slides = DeepCopy(afterSlides)
            RecomputeBoard(self, target)
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) ~= "table" then return end
            target.slides = DeepCopy(beforeSlides)
            RecomputeBoard(self, target)
        end,
    })
end

local function ClampSlideIndex(board, slideIndex)
    local count = #(board.slides or {})
    if count == 0 then
        return nil
    end
    local index = tonumber(slideIndex) or 1
    if index < 1 then index = 1 end
    if index > count then index = count end
    return index
end

function Data:GetSlideCount(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" then
        return 0
    end
    return #(board.slides or {})
end

function Data:GetSlide(boardID, slideIndex)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" then
        return nil
    end
    local index = ClampSlideIndex(board, slideIndex)
    if not index then
        return nil
    end
    return board.slides[index], index
end

function Data:AddSlide(boardID, name)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return nil
    end
    local beforeSlides = DeepCopy(board.slides)
    local afterSlides = DeepCopy(board.slides)
    local seq = NormalizePositiveNumber(board._nextSlideID, #afterSlides + 1)
    local slideName = Trim(name)
    if slideName == "" then
        slideName = tostring(#afterSlides + 1)
    end
    local slide = {
        id = "slide-" .. tostring(seq),
        name = slideName,
        holdTime = DEFAULT_HOLD_TIME,
        morphFromPrev = DEFAULT_MORPH_TIME,
        overrides = {},
    }
    afterSlides[#afterSlides + 1] = slide
    board._nextSlideID = seq + 1
    local index = #afterSlides
    CommitSlides(self, boardID, beforeSlides, afterSlides, "addSlide")
    if T and T.debug then
        T.debug(string.format("[VisualBoard] SlideAdded board=%s slide=%s index=%d", tostring(boardID), tostring(slide.id), index))
    end
    return slide, index
end

function Data:DeleteSlide(boardID, slideIndex)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    if #(board.slides or {}) <= 1 then
        return false  -- 至少保留 1 帧
    end
    local index = ClampSlideIndex(board, slideIndex)
    if not index then
        return false
    end
    local beforeSlides = DeepCopy(board.slides)
    local afterSlides = DeepCopy(board.slides)
    table.remove(afterSlides, index)
    CommitSlides(self, boardID, beforeSlides, afterSlides, "deleteSlide")
    return true
end

function Data:RenameSlide(boardID, slideIndex, name)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local index = ClampSlideIndex(board, slideIndex)
    if not index then
        return false
    end
    local slideName = Trim(name)
    if slideName == "" then
        slideName = tostring(index)
    end
    local beforeSlides = DeepCopy(board.slides)
    local afterSlides = DeepCopy(board.slides)
    afterSlides[index].name = slideName
    CommitSlides(self, boardID, beforeSlides, afterSlides, "renameSlide")
    return true
end

-- 帧条拖拽排序：orderedIDs 为新顺序的 slide.id 数组。仅当覆盖全部现有帧才生效。
function Data:ReorderSlides(boardID, orderedIDs)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true or type(orderedIDs) ~= "table" then
        return false
    end
    local byID = {}
    for _, slide in ipairs(board.slides or {}) do
        byID[slide.id] = slide
    end
    local afterSlides = {}
    local seen = {}
    for _, id in ipairs(orderedIDs) do
        local sid = Trim(id)
        if byID[sid] and not seen[sid] then
            seen[sid] = true
            afterSlides[#afterSlides + 1] = DeepCopy(byID[sid])
        end
    end
    if #afterSlides ~= #(board.slides or {}) then
        return false  -- 必须是现有帧的完整重排
    end
    local beforeSlides = DeepCopy(board.slides)
    CommitSlides(self, boardID, beforeSlides, afterSlides, "reorderSlides")
    return true
end

function Data:SetSlideMorph(boardID, slideIndex, seconds)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local index = ClampSlideIndex(board, slideIndex)
    if not index then
        return false
    end
    local beforeSlides = DeepCopy(board.slides)
    local afterSlides = DeepCopy(board.slides)
    afterSlides[index].morphFromPrev = NormalizePositiveNumber(seconds, DEFAULT_MORPH_TIME)
    CommitSlides(self, boardID, beforeSlides, afterSlides, "setSlideMorph")
    return true
end

-- 设置该帧停留时长（holdTime）。契约 §6.3 holdTime 为 per-slide 可配字段，slide_bar 在帧条提供输入。
function Data:SetSlideHold(boardID, slideIndex, seconds)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local index = ClampSlideIndex(board, slideIndex)
    if not index then
        return false
    end
    local beforeSlides = DeepCopy(board.slides)
    local afterSlides = DeepCopy(board.slides)
    afterSlides[index].holdTime = NormalizePositiveNumber(seconds, DEFAULT_HOLD_TIME)
    CommitSlides(self, boardID, beforeSlides, afterSlides, "setSlideHold")
    return true
end

local function ApplySlideOverrideValue(slide, targetID, key, value)
    local overrides = slide.overrides
    if type(overrides) ~= "table" then
        overrides = {}
        slide.overrides = overrides
    end
    local entry = type(overrides[targetID]) == "table" and overrides[targetID] or {}
    if value == nil then
        entry[key] = nil
    elseif key == "hidden" then
        entry[key] = value == true
    elseif key == "scale" then
        entry[key] = NormalizePositiveNumber(value, nil)
    elseif key == "rotation" then
        entry[key] = (tonumber(value) or 0) % 360
    else
        entry[key] = tonumber(value)
    end
    if next(entry) == nil then
        overrides[targetID] = nil
    else
        overrides[targetID] = entry
    end
end

-- 写当前帧覆写。key ∈ override 白名单(§2.3：x/y/hidden/scale/rotation)。value=nil 清除该覆写。
function Data:SetSlideOverride(boardID, slideIndex, elementID, key, value, transient)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    if key ~= "x" and key ~= "y" and key ~= "hidden" and key ~= "scale" and key ~= "rotation" then
        return false
    end
    local index = ClampSlideIndex(board, slideIndex)
    if not index then
        return false
    end
    local targetID = Trim(elementID)
    if targetID == "" or not FindElementIndex(board, targetID) then
        return false
    end
    local transientKey = tostring(boardID) .. ":slideOverride:" .. tostring(index) .. ":" .. targetID .. ":" .. key
    if transient then
        if not self._transientSnapshots[transientKey] then
            self._transientSnapshots[transientKey] = DeepCopy(board.slides)
        end
        ApplySlideOverrideValue(board.slides[index], targetID, key, value)
        RecomputeBoard(self, board)
        return true
    end

    local beforeSlides = self._transientSnapshots[transientKey] or DeepCopy(board.slides)
    self._transientSnapshots[transientKey] = nil
    local afterSlides = DeepCopy(board.slides)
    ApplySlideOverrideValue(afterSlides[index], targetID, key, value)
    local beforePayload = { elements = {}, slides = beforeSlides, artboard = board.artboard }
    local afterPayload = { elements = {}, slides = afterSlides, artboard = board.artboard }
    if self:ComputeBoardHash(beforePayload) == self:ComputeBoardHash(afterPayload) then
        board.slides = afterSlides
        RecomputeBoard(self, board)
        return true
    end
    CommitSlides(self, boardID, beforeSlides, afterSlides, "setSlideOverride")
    return true
end

-- previewRect 钳制单一权威：钳到 artboard 内（同 EnsureBoardShape 规则），w/h 不小于 PREVIEW_RECT_MIN。
local function ClampPreviewRect(board, x, y, w, h)
    local aw, ah = board.artboard.w, board.artboard.h
    local nx = math.max(0, math.min(aw, tonumber(x) or 0))
    local ny = math.max(0, math.min(ah, tonumber(y) or 0))
    local nw = NormalizePositiveNumber(w, aw)
    local nh = NormalizePositiveNumber(h, ah)
    nw = math.max(PREVIEW_RECT_MIN, math.min(nw, aw - nx))
    nh = math.max(PREVIEW_RECT_MIN, math.min(nh, ah - ny))
    return { x = nx, y = ny, w = nw, h = nh }
end

-- previewRect 写入单一权威：编辑态取景框拖拽/缩放只调本函数。
-- transient 复用 _transientSnapshots（同 UpdateElementPosition）：拖拽中就地写、不堆撤销；松手提交一条撤销。
function Data:SetPreviewRect(boardID, x, y, w, h, transient)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    local after = ClampPreviewRect(board, x, y, w, h)
    local key = tostring(boardID) .. ":previewRect"
    if transient then
        if not self._transientSnapshots[key] then
            self._transientSnapshots[key] = DeepCopy(board.previewRect)
        end
        board.previewRect = after
        return true
    end

    local before = self._transientSnapshots[key] or DeepCopy(board.previewRect)
    self._transientSnapshots[key] = nil
    board.previewRect = after
    local unchanged = before.x == after.x and before.y == after.y and before.w == after.w and before.h == after.h
    if unchanged then
        RecomputeBoard(self, board)
        return true
    end
    self:DoCommand({
        label = "setPreviewRect",
        do_ = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" then
                target.previewRect = DeepCopy(after)
                RecomputeBoard(self, target)
            end
        end,
        undo = function()
            local target = self:GetBoard(boardID)
            if type(target) == "table" then
                target.previewRect = DeepCopy(before)
                RecomputeBoard(self, target)
            end
        end,
    })
    return true
end

-- override 合并单一权威：返回元素在帧 i 的有效值（基线 + 该帧 override）。
-- editor/canvas 不得自行合并。返回 { x, y, hidden, scale, rotation }。
function Data:ResolveElementAtSlide(element, slideIndex, board)
    if type(element) ~= "table" then
        return { x = 0, y = 0, hidden = false, scale = 1, rotation = 0 }
    end
    local resolved = {
        x = tonumber(element.x) or 0,
        y = tonumber(element.y) or 0,
        hidden = element.hidden == true,
        scale = NormalizePositiveNumber(element.scale, 1),
        rotation = tonumber(element.rotation) or 0,
    }
    if type(board) ~= "table" or type(board.slides) ~= "table" then
        return resolved
    end
    local index = ClampSlideIndex(board, slideIndex)
    if not index then
        return resolved
    end
    local slide = board.slides[index]
    local override = type(slide) == "table" and type(slide.overrides) == "table" and slide.overrides[element.id] or nil
    if type(override) == "table" then
        if override.x ~= nil then resolved.x = tonumber(override.x) or resolved.x end
        if override.y ~= nil then resolved.y = tonumber(override.y) or resolved.y end
        if override.hidden ~= nil then resolved.hidden = override.hidden == true end
        if override.scale ~= nil then resolved.scale = NormalizePositiveNumber(override.scale, resolved.scale) end
        if override.rotation ~= nil then resolved.rotation = (tonumber(override.rotation) or resolved.rotation) % 360 end
    end
    return resolved
end

-- 当前帧几何单一权威：编辑态所有可见位置/命中/手柄定位都从这里取。
-- element.x/y 只代表基线；第 2 帧以后可能被 slide override 覆写，canvas/editor 禁止各自再拼坐标。
function Data:ResolveElementGeometryAtSlide(element, slideIndex, board)
    local resolved = self:ResolveElementAtSlide(element, slideIndex, board)
    local proxy = DeepCopy(element or {})
    proxy.x = resolved.x
    proxy.y = resolved.y
    proxy.scale = resolved.scale
    proxy.rotation = resolved.rotation
    local boxW, boxH, shape = self:GetElementBox(proxy)
    local startX = tonumber(resolved.x) or 0
    local startY = tonumber(resolved.y) or 0
    local endX = tonumber(element and element.end_x)
    local endY = tonumber(element and element.end_y)
    if endX == nil then
        endX = startX + 120
    end
    if endY == nil then
        endY = startY
    end
    return {
        x = startX,
        y = startY,
        hidden = resolved.hidden == true,
        scale = NormalizePositiveNumber(resolved.scale, 1),
        rotation = tonumber(resolved.rotation) or 0,
        boxW = tonumber(boxW) or 0,
        boxH = tonumber(boxH) or 0,
        shape = shape or "rect",
        startX = startX,
        startY = startY,
        -- 线段端点暂不做 slide override：显式 end_x/end_y 仍是基线几何，不能在 canvas/editor 私自伪造逐帧端点。
        endX = endX,
        endY = endY,
    }
end

-- ===== 组头批量编辑（§4.3 / §9.2）=====
-- 对组内全部 person 套用同一 fields（深层覆写，如统一 circle.radius）；一条撤销。
function Data:BatchUpdateGroup(boardID, groupID, fields)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true or type(fields) ~= "table" then
        return false
    end
    local targetID = Trim(groupID)
    if targetID == "" or type(board.groups) ~= "table" or type(board.groups[targetID]) ~= "table" then
        return false
    end
    local memberIDs = {}
    for _, element in ipairs(board.elements or {}) do
        if element.groupID == targetID and element.type == "person" then
            memberIDs[#memberIDs + 1] = element.id
        end
    end
    if #memberIDs == 0 then
        return false
    end
    local beforeElements = CollectElementSnapshots(board, memberIDs)
    local afterElements = {}
    for _, id in ipairs(memberIDs) do
        local after = DeepCopy(beforeElements[id])
        self:_ApplyElementFields(after, fields)
        afterElements[id] = after
    end
    CommitBatch(self, boardID, beforeElements, afterElements, board.groups, board.groups, "batchUpdateGroup")
    return true
end

-- ===== person 默认图标桥接（§4.5）=====
-- person 未写 icon.texture/atlas 时，按 slotName 推默认图标，优先级：
--   1) 专精图标：ResolveSpecID（手填 [人员图标] 或槽位名黑话，如 AM1→暗牧）命中 specID → spec 图标；
--   2) 职业图标（中性兜底）：黑话只解析出职业（如“小德”“FS”，无具体专精）→ classicon-<classFile>；
--   3) 都不命中返回 nil（drawer 落中性人员图标，不再落问号）。
-- 复用 person_resolver + condition_filter 黑话表 + spec_icons，本文件不重造任何映射。
function Data:ResolvePersonDefaultIcon(element, info)
    if type(element) ~= "table" or element.type ~= "person" then
        return nil
    end
    local resolver = T.VisualBoardPersonResolver
    local specIcons = T.VisualBoardSpecIcons
    if type(resolver) ~= "table" or type(resolver.ResolveSpecID) ~= "function" or type(specIcons) ~= "table" then
        return nil
    end
    local params = type(element.params) == "table" and element.params or {}
    local specID = resolver:ResolveSpecID(info, params.slotName)
    if specID and type(specIcons.GetSpecIcon) == "function" then
        local icon = specIcons:GetSpecIcon(specID)
        if icon then
            return icon
        end
    end
    -- 职业级中性兜底：黑话只认出职业（无专精）时显职业图标。
    if T.ResolveSlotVisualHint and type(specIcons.GetClassIcon) == "function" then
        local hint = T.ResolveSlotVisualHint(params.slotName)
        if type(hint) == "table" and hint.classFile then
            return specIcons:GetClassIcon(hint.classFile)
        end
    end
    return nil
end

-- ===== 最小验证夹具（§13 阶段 1）=====
-- 纯代码拼 person + slide，不依赖真实 boss 数据，供阶段 3/4 渲染验收。
-- 共有 person 两帧都在；新增 person 在 slide-1 override hidden=true。
function Data:BuildTestFixture(boardID)
    local board = self:GetBoard(boardID)
    if type(board) ~= "table" or board.builtin == true then
        return false
    end
    -- slide-1（基线）：3 个共有 person 摆位。
    local p1 = self:AddPersonAt(boardID, "测试A", 400, 300)
    local p2 = self:AddPersonAt(boardID, "测试B", 800, 300)
    local p3 = self:AddPersonAt(boardID, "测试C", 1200, 300)
    -- 新增 person：仅 slide-2 出现。
    local p4 = self:AddPersonAt(boardID, "测试D", 800, 600)
    if not (p1 and p2 and p3 and p4) then
        return false
    end
    -- 第 2 帧。
    local _, slide2 = self:AddSlide(boardID, "图2")
    if not slide2 then
        return false
    end
    -- 共有 person 在 slide-2 平移到新位（写覆写）。
    self:SetSlideOverride(boardID, slide2, p1.id, "x", 600)
    self:SetSlideOverride(boardID, slide2, p1.id, "y", 500)
    self:SetSlideOverride(boardID, slide2, p2.id, "x", 1000)
    self:SetSlideOverride(boardID, slide2, p2.id, "y", 500)
    -- 新增 person 在 slide-1 隐藏（图1没有、图2才有），slide-2 显示。
    self:SetSlideOverride(boardID, 1, p4.id, "hidden", true)
    if T and T.debug then
        T.debug(string.format("[VisualBoard] TestFixtureBuilt board=%s persons=4 slides=2", tostring(boardID)))
    end
    return true
end

function Data:GetSummary()
    local db = self:EnsureDB()
    return {
        schemaVersion = db._schemaVersion,
        count = CountBoards(db),
        nextID = db._nextID,
    }
end

end
