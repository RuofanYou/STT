local T, C, L = unpack(select(2, ...))
do

local Overlay = {
    active = {},
    order = {},
}
T.VisualBoardOverlay = Overlay

local DEFAULT_POSITIONS = {
    { "TOPLEFT", "TOPLEFT", 280, -200 },
    { "TOPLEFT", "TOPLEFT", 120, -140 },
    { "TOPRIGHT", "TOPRIGHT", -120, -140 },
    { "BOTTOMLEFT", "BOTTOMLEFT", 120, 180 },
    { "BOTTOMRIGHT", "BOTTOMRIGHT", -120, 180 },
}

local function ResolveText(key, fallback)
    return (L and L[key]) or fallback or key
end

local DEFAULT_HOLD_TIME = 2.0   -- 帧无 holdTime 时的常量停留时长（§6.2）

-- 解锁态金色外框（照抄 core/editmode.lua 的 EditMode 视觉常量，单一权威同源）：
-- WHITE8X8 边 + 金黄边色 + 半透明黑底，让解锁态画布可见可抓；锁定态隐藏回纯画布。
local EDIT_BORDER_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
local EDIT_BORDER_BG_COLOR     = { 0, 0, 0, 0.25 }
local EDIT_BORDER_COLOR        = { 1, 0.82, 0, 1 }

-- HUD 缩放：右下角 resizer 直接拖 frame 宽高（照 realtime_board，真改 SetSize 而非 SetScale）。
-- canvas 锚在 frame 内框，frame 一变大 canvas 自动跟大，ComputeFitViewport 每 tick 按 canvas 框算 fit 天然自洽（契约 §6.2）。
local HUD_MIN_WIDTH = 220
local HUD_MIN_HEIGHT = 170
local HUD_FALLBACK_MAX_WIDTH = 1200
local HUD_FALLBACK_MAX_HEIGHT = 900

-- 缩放边界单一权威（照 realtime_board:ApplyBoardResizeBounds）：min 固定，max 取屏幕 0.95 与回退值的较大者。
local function ApplyResizeBounds(frame)
    if not (frame and frame.SetResizeBounds) then
        return
    end
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or HUD_FALLBACK_MAX_WIDTH
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or HUD_FALLBACK_MAX_HEIGHT
    local maxWidth = math.max(HUD_FALLBACK_MAX_WIDTH, math.floor(screenWidth * 0.95))
    local maxHeight = math.max(HUD_FALLBACK_MAX_HEIGHT, math.floor(screenHeight * 0.95))
    frame:SetResizeBounds(HUD_MIN_WIDTH, HUD_MIN_HEIGHT, maxWidth, maxHeight)
end

-- morph 数学单一权威：线性插值（位置）+ 线性 alpha 淡入淡出。
-- 全模块只此一处算 lerp/alpha，禁止散落（契约 §6.2）。
local function Lerp(a, b, p)
    return a + (b - a) * p
end

-- 帧时间线单一权威（契约 §6.2）：按 slides 与每帧 holdTime/morphFromPrev 构造 arriveAt[]。
--   arriveAt[1] = 0
--   arriveAt[i] = arriveAt[i-1] + slides[i-1].holdTime + slides[i].morphFromPrev
-- holdTime 取每帧 slide.holdTime，无则常量 DEFAULT_HOLD_TIME。
-- 返回 arriveAt 数组与播放总时长 totalTime（末帧到位时刻 + 末帧停留）。
local function BuildTimeline(slides)
    local arriveAt = {}
    local count = #slides
    if count == 0 then
        return arriveAt, 0
    end
    arriveAt[1] = 0
    for i = 2, count do
        local prevHold = tonumber(slides[i - 1].holdTime) or DEFAULT_HOLD_TIME
        local morph = math.max(0, tonumber(slides[i].morphFromPrev) or 0)
        arriveAt[i] = arriveAt[i - 1] + prevHold + morph
    end
    local lastHold = tonumber(slides[count].holdTime) or DEFAULT_HOLD_TIME
    local totalTime = arriveAt[count] + lastHold
    return arriveAt, totalTime
end

-- 运行时 info 单一权威：优先取调用方注入（编辑器预览），否则从当前激活方案 PreprocessText 解算。
-- 拿不到 info 返回 nil（降级显示 slotName + self=false，见 §10），不报错。
local function ResolvePlayInfo(opts)
    if type(opts) == "table" and type(opts.info) == "table" then
        return opts.info
    end
    local Note = T.Note
    local plan = Note and Note.GetActivePlan and Note:GetActivePlan() or nil
    local content = type(plan) == "table" and tostring(plan.content or "") or ""
    if content == "" then
        return nil
    end
    local Template = T.STNTemplate
    if not (Template and Template.PreprocessText) then
        return nil
    end
    return Template.PreprocessText(content)
end

local function GetOverlayDB()
    STT_VisualBoardsDB = type(STT_VisualBoardsDB) == "table" and STT_VisualBoardsDB or {}
    if type(STT_VisualBoardsDB._overlay) ~= "table" then
        STT_VisualBoardsDB._overlay = {}
    end
    return STT_VisualBoardsDB._overlay
end

-- 不透明度单一权威（复用 _overlay 结构，与 _locked/[boardID] 并列）：全局 _overlay._alpha，钳 0–1.0，默认 1.0（不透明）。
local OVERLAY_ALPHA_MIN = 0
local OVERLAY_ALPHA_MAX = 1.0
local function GetOverlayAlpha()
    local a = tonumber(GetOverlayDB()._alpha) or OVERLAY_ALPHA_MAX
    return math.max(OVERLAY_ALPHA_MIN, math.min(OVERLAY_ALPHA_MAX, a))
end

-- 设置不透明度：钳值 → 写回 _overlay._alpha（落 SavedVariables）→ 触发活跃 HUD 重渲一次。
-- 不透明度只作用于 canvas 背景层（经 RenderTick 的 bgAlpha 传给 canvas DrawBackground），
-- 故此处不再动 frame:SetAlpha（那会连控件一起淡），改为强制重渲让背景层即时吃到新值。
local function SetOverlayAlpha(a)
    local clamped = math.max(OVERLAY_ALPHA_MIN, math.min(OVERLAY_ALPHA_MAX, tonumber(a) or OVERLAY_ALPHA_MAX))
    GetOverlayDB()._alpha = clamped
    Overlay:RefreshActive()
    if T.debug then
        T.debug(string.format("[VisualBoard] OverlayAlpha=%.2f", clamped))
    end
end

-- 不透明度公开读写口（薄包装）：值的单一权威仍是上面的 local GetOverlayAlpha/SetOverlayAlpha（写入口唯一 _overlay._alpha）。
-- 滚轮入口不动仍走 local；editor 的可见滑块经此公开口共用同一写入口。
function Overlay:GetAlpha()
    return GetOverlayAlpha()
end

function Overlay:SetAlpha(a)
    SetOverlayAlpha(a)
end

-- 位置+尺寸持久化单一权威（照 realtime_board:SavePosition）：一次性写 point/relPoint/x/y/width/height 到共享键 _overlay._pos。
-- 所有板共享同一位置/尺寸（SSOT）：boardID 参数保留签名以兼容调用方，但不再作为存储键。
local function SaveFramePosition(frame, boardID)
    local db = GetOverlayDB()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    db._pos = {
        point = point or "CENTER",
        relPoint = relPoint or point or "CENTER",
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        width = frame:GetWidth(),
        height = frame:GetHeight(),
    }
end

-- 应用持久化位置+尺寸（照 realtime_board:LoadPosition）：有共享 _pos 用 _pos，否则用单一默认 DEFAULT_POSITIONS[1]（默认偏左上）。
-- index 参数保留签名以兼容调用方，但位置不再按 index 轮换（所有板共享同一位置 SSOT）。
local function ApplyFramePosition(frame, boardID, index)
    local saved = GetOverlayDB()._pos
    frame:ClearAllPoints()
    if type(saved) == "table" then
        frame:SetPoint(saved.point or "CENTER", UIParent, saved.relPoint or saved.point or "CENTER", tonumber(saved.x) or 0, tonumber(saved.y) or 0)
        if tonumber(saved.width) and tonumber(saved.height) then
            frame:SetSize(tonumber(saved.width), tonumber(saved.height))
        end
    else
        local pos = DEFAULT_POSITIONS[1]
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end

-- 在 boardTime 定位播放段：返回停留帧 i（过渡段则返回 i 与 i+1 及进度 p∈[0,1]）。
-- arriveAt[i] = 帧 i 到位时刻；[arriveAt[i], arriveAt[i]+hold_i] 为停留段，其后到 arriveAt[i+1] 为 i→i+1 过渡段。
local function LocateSegment(slides, arriveAt, boardTime)
    local count = #slides
    if count == 0 then
        return 1, nil, 0
    end
    if boardTime <= 0 then
        return 1, nil, 0
    end
    for i = 1, count do
        local hold = tonumber(slides[i].holdTime) or DEFAULT_HOLD_TIME
        local holdEnd = arriveAt[i] + hold
        if boardTime <= holdEnd then
            return i, nil, 0           -- 处于帧 i 停留段
        end
        if i < count then
            local nextArrive = arriveAt[i + 1]
            if boardTime < nextArrive then
                local span = nextArrive - holdEnd
                local p = span > 0 and ((boardTime - holdEnd) / span) or 1
                if p < 0 then p = 0 elseif p > 1 then p = 1 end
                return i, i + 1, p     -- 处于 i→i+1 过渡段
            end
        end
    end
    return count, nil, 0               -- 超末帧停留 → 停在末帧（MVP 不循环）
end

-- 构造 renderState.resolved（契约 §6.2/§6.3）：对每元素经 Data:ResolveElementAtSlide 取帧 i/i+1 有效值，
-- 算出 {x,y,alpha,scale,self}；person 经 PersonResolver 解析真实 id 显示文本 + 本机高亮（§10）。
-- 段定位 (i, j, p) 由调用方传入（RenderTick 已算，避免重复定位）。
local function BuildRenderState(board, info, i, j, p)
    local Data = T.VisualBoardData
    local Resolver = T.VisualBoardPersonResolver
    local resolved = {}

    for _, element in ipairs(board.elements or {}) do
        local a = Data:ResolveElementAtSlide(element, i, board)
        local x, y, alpha, scale, rotation
        if not j then
            -- 停留段：渲染帧 i 快照，隐藏元素直接跳过
            if a.hidden then
                x = nil
            else
                x, y, alpha, scale, rotation = a.x, a.y, 1, a.scale, a.rotation
            end
        else
            local b = Data:ResolveElementAtSlide(element, j, board)
            if not a.hidden and not b.hidden then
                -- 两帧都出现：位置 lerp，alpha=1
                x = Lerp(a.x, b.x, p)
                y = Lerp(a.y, b.y, p)
                alpha = 1
                scale = Lerp(a.scale, b.scale, p)
                rotation = Lerp(tonumber(a.rotation) or 0, tonumber(b.rotation) or 0, p)
            elseif not b.hidden then
                -- 仅 i+1 出现：固定 i+1 位淡入 0→1
                x, y, alpha, scale = b.x, b.y, p, b.scale
                rotation = b.rotation
            elseif not a.hidden then
                -- 仅 i 出现：固定 i 位淡出 1→0
                x, y, alpha, scale = a.x, a.y, 1 - p, a.scale
                rotation = a.rotation
            else
                x = nil  -- 两帧都不出现
            end
        end

        if x ~= nil then
            local entry = { x = x, y = y, alpha = alpha, scale = scale, rotation = tonumber(rotation) or tonumber(element.rotation) or 0, self = false }
            if element.type == "person" and Resolver then
                local params = type(element.params) == "table" and element.params or {}
                local slotName = params.slotName
                if info then
                    entry.displayText = Resolver:ResolveRealName(info, slotName)
                    if Resolver:IsSelf(info, slotName) then
                        entry.self = true
                    end
                else
                    entry.displayText = slotName
                end
            end
            resolved[element.id] = entry
        end
    end

    return resolved
end

-- fit-to-view viewport 单一权威（运行时 HUD 专用）：把整张 artboard 居中等比装进 canvas 框。
-- 运行时 HUD 不需要用户缩放/平移，每 tick 按当前框尺寸算 fit（框尺寸随 HUD 拖动/缩放可变）。
-- zoom=min(fw/artW, fh/artH)*0.96（留边）；panX/panY 居中；与 canvas.lua BoardToScreen(panX + x*zoom) 配套。
-- 帧未布局（fw/fh<=1）时返回 nil → 本 tick 跳过渲染，下一 tick 框有尺寸再算，避免除 0。
local function ComputeFitViewport(canvas, board)
    local fw = canvas:GetWidth() or 0
    local fh = canvas:GetHeight() or 0
    if fw <= 1 or fh <= 1 then
        return nil
    end
    -- fit 取景框 previewRect 那块（画板逻辑坐标），把它映射填满 HUD canvas。
    -- previewRect 由 EnsureBoardShape 规范化并钳到 artboard 内；默认=整 artboard 时退化为原 fit，行为不变。
    local artboard = type(board.artboard) == "table" and board.artboard or {}
    local artW = tonumber(artboard.w) or 1600
    local artH = tonumber(artboard.h) or 900
    local pr = type(board.previewRect) == "table" and board.previewRect or {}
    local px = tonumber(pr.x) or 0
    local py = tonumber(pr.y) or 0
    local pw = tonumber(pr.w) or artW
    local ph = tonumber(pr.h) or artH
    local zoom = math.min(fw / pw, fh / ph) * 0.96
    -- 由 screenX = panX + boardX*zoom 反解：令取景框左上角 (px,py) 居中落入框内。
    return {
        zoom = zoom,
        panX = (fw - pw * zoom) / 2 - px * zoom,
        panY = (fh - ph * zoom) / 2 - py * zoom,
    }
end

-- 单帧播放：算 boardTime → 段定位 → resolved → 调 canvas Render（renderState 形状见 §6.3）。
local function RenderTick(frame)
    local board = frame.board
    local slides = type(board.slides) == "table" and board.slides or {}
    if #slides == 0 then
        frame:Hide()
        return
    end
    local elapsed = math.max(0, GetTime() - (tonumber(frame.startedAt) or GetTime()))
    local boardTime = elapsed + (tonumber(frame.offset) or 0)
    local totalTime = math.max(0.1, tonumber(frame.totalTime) or 0.1)

    -- 时间轴触发的播放：播完（boardTime ≥ totalTime）自动消失，使「显示 N 秒后消失」成立
    -- （N = 幻灯片总时长 totalTime，由作者用每帧停留时长控制）。
    -- 仅 source=="timeline" 才自动消失；编辑器「预览」(非 timeline) 保持原样冻结末帧，让作者慢慢看。
    -- Hide() 触发 OnHide → playing=false + renderer:Clear()，OnUpdate 随之停转（无独立 ticker 需停）。
    if boardTime >= totalTime and type(frame.playOpts) == "table" and frame.playOpts.source == "timeline" then
        frame.playing = false
        frame:Hide()
        return
    end

    -- 播到末帧停留结束 → 停在末帧（非 timeline 预览不循环、不消失）。
    local clampedTime = math.min(boardTime, totalTime)

    local i, j, p = LocateSegment(slides, frame.arriveAt, clampedTime)
    if frame.renderer then
        -- fit viewport：框未布局（fw/fh<=1）时返回 nil，本 tick 跳过渲染，下一 tick 再算（避免除 0）。
        local viewport = ComputeFitViewport(frame.canvasFrame, board)
        if viewport then
            local resolved = BuildRenderState(board, frame.playInfo, i, j, p)
            -- 在 playOpts 基础上叠加 viewport（不破坏 source/info）。
            local base = type(frame.playOpts) == "table" and frame.playOpts or {}
            local renderOpts = {}
            for k, v in pairs(base) do
                renderOpts[k] = v
            end
            renderOpts.viewport = viewport
            -- 背景层透明度（单一权威 _overlay._alpha）只传给 canvas，由 DrawBackground 仅对 Boss 底图纹理应用；
            -- 画上去的控件（人员/圈/图标/十字/文字）不受影响，保持不透明。
            renderOpts.bgAlpha = GetOverlayAlpha()
            frame.renderer:Render(board, {
                mode = "play",
                resolved = resolved,
                currentSlideIndex = i,
            }, renderOpts)
        end
    end
end

function Overlay:CreateFrame(boardID, index)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(360, 270)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    -- 移动/缩放照 realtime_board：frame 本体可拖（StartMoving）+ 右下角 resizer 可缩（StartSizing），锁定态由 SetLocked 门控。
    -- EnableMouse 仅解锁态开（锁定态整帧不吃事件，避免战斗中误拖/挡 ping）；RegisterForDrag 也随锁定态切换。
    frame:SetMovable(true)
    frame:SetResizable(true)
    ApplyResizeBounds(frame)
    frame:EnableMouse(false)
    frame:EnableMouseWheel(false)
    frame:RegisterForDrag()
    -- 极简：不画 HUD 厚外框/标题，视觉边界由 canvas 自己的 backdrop 承担（去 chrome）。
    if T.MarkPingBlocker then
        T.MarkPingBlocker(frame, true)
    end

    -- 解锁态滚轮调全局不透明度（滚轮此前空闲），每格 ±0.05；锁定态滚轮关闭不吞游戏世界缩放。
    frame:SetScript("OnMouseWheel", function(_, delta)
        if Overlay:IsLocked() then
            return
        end
        SetOverlayAlpha(GetOverlayAlpha() + (tonumber(delta) or 0) * 0.05)
    end)

    -- 右下角缩放角标（照 realtime_board:1626-1644）：18×18 Button，三态 SizeGrabber 贴图，仅解锁态显示并可拖缩。
    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(18, 18)
    resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function()
        if Overlay:IsLocked() then
            return
        end
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SaveFramePosition(frame, frame.boardID)
    end)
    resizer:Hide()
    frame.resizer = resizer

    local canvas = CreateFrame("Frame", nil, frame)
    canvas:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    canvas:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    -- 裁剪：artboard(1600x900)经 fit viewport 装进 HUD 小框后仍可能有元素越界，
    -- SetClipsChildren 把超出 canvas 框的渲染裁掉，避免溢出整屏（与编辑器 canvasFrame 同处理）。
    canvas:SetClipsChildren(true)
    frame.canvasFrame = canvas
    frame.renderer = T.VisualBoardCanvas and T.VisualBoardCanvas:Create(canvas) or nil

    -- 解锁态金色外框（独立子 frame，复用 EditMode 视觉常量）：盖在 canvas 之上只做视觉提示，
    -- 与不透明度互不影响（不透明度只淡背景层）。解锁→Show 让用户看见框、能抓；锁定→Hide 回纯画布。
    local editBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    editBorder:SetAllPoints(frame)
    editBorder:SetFrameLevel(canvas:GetFrameLevel() + 5)
    editBorder:EnableMouse(false)
    if editBorder.SetBackdrop then
        editBorder:SetBackdrop(EDIT_BORDER_BACKDROP)
        editBorder:SetBackdropColor(EDIT_BORDER_BG_COLOR[1], EDIT_BORDER_BG_COLOR[2], EDIT_BORDER_BG_COLOR[3], EDIT_BORDER_BG_COLOR[4])
        editBorder:SetBackdropBorderColor(EDIT_BORDER_COLOR[1], EDIT_BORDER_COLOR[2], EDIT_BORDER_COLOR[3], EDIT_BORDER_COLOR[4])
    end
    editBorder:Hide()
    frame.editBorder = editBorder

    -- resizer 抬到 canvas 之上（照 realtime_board scrollArea+10），否则后建的 canvas 盖住右下角角标点不到。
    resizer:SetFrameLevel(canvas:GetFrameLevel() + 10)

    -- 移动：点 frame 空白拖动整 HUD（照 realtime_board OnDragStart/Stop）；锁定态直接 return，StopMovingOrSizing 后持久化位置。
    frame:SetScript("OnDragStart", function(self)
        if Overlay:IsLocked() then
            return
        end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition(self, self.boardID)
    end)
    -- 缩放实时回写宽高（照 realtime_board OnSizeChanged）：resizer 拖动每帧更新共享键 _overlay._pos.width/height。
    frame:SetScript("OnSizeChanged", function(self)
        local db = GetOverlayDB()
        local saved = type(db._pos) == "table" and db._pos or nil
        if saved then
            saved.width = self:GetWidth()
            saved.height = self:GetHeight()
        end
    end)
    frame:SetScript("OnHide", function(self)
        if self.renderer then
            self.renderer:Clear()
        end
        self.playing = false
    end)
    frame:SetScript("OnUpdate", function(self)
        if not self.playing or type(self.board) ~= "table" then
            return
        end
        self:RenderTick()
    end)

    frame.RenderTick = RenderTick

    -- EditMode 仅作暴雪原生 EditMode 联动的附加通道（group="blizz"，照 realtime_board），
    -- 插件自己的解锁拖动/缩放走 SetLocked + frame 自带 drag/size 脚本，不靠 solo 覆盖层（覆盖层会盖住右下角 resizer）。
    if T.EditMode and T.EditMode.Register then
        T.EditMode:Register({
            frame = frame,
            displayName = ResolveText("VISUAL_BOARD_OVERLAY_NAME", "视觉画板预览"),
            group = "blizz",
            saveFunc = function()
                SaveFramePosition(frame, frame.boardID)
            end,
        })
    end

    ApplyFramePosition(frame, boardID, index)
    return frame
end

function Overlay:GetFrame(boardID)
    local frame = self.active[boardID]
    if not frame then
        self.order[#self.order + 1] = boardID
        frame = self:CreateFrame(boardID, #self.order)
        self.active[boardID] = frame
        -- 新建 HUD 继承当前锁定态（解锁中再 Play 出新 HUD 也应可拖/可缩）。
        self:ApplyLockState(frame)
    end
    return frame
end

function Overlay:Play(boardID, offset, opts)
    local board = T.VisualBoardData and T.VisualBoardData:GetBoard(boardID) or nil
    if type(board) ~= "table" then
        if not self.missingWarned then
            self.missingWarned = {}
        end
        if not self.missingWarned[boardID] then
            self.missingWarned[boardID] = true
            T.msg(string.format(ResolveText("VISUAL_BOARD_MISSING", "缺少画板: %s（请让团长重新广播方案）"), tostring(boardID)))
            if T.debug then
                T.debug(string.format("[VisualBoard] BoardMissing id=%s", tostring(boardID)))
            end
        end
        return false
    end

    local slides = type(board.slides) == "table" and board.slides or {}
    if #slides == 0 then
        if T.debug then
            T.debug(string.format("[VisualBoard] BoardPlay 跳过：无 slides id=%s", tostring(board.id)))
        end
        return false
    end

    local arriveAt, totalTime = BuildTimeline(slides)
    local info = ResolvePlayInfo(opts)
    if not info and T.debug then
        T.debug(string.format("[VisualBoard] BoardPlay 无可用方案 info，person 降级显示 slotName id=%s", tostring(board.id)))
    end

    local frame = self:GetFrame(board.id)
    frame.boardID = board.id
    frame.board = board
    frame.offset = math.max(0, tonumber(offset) or 0)
    frame.startedAt = GetTime()
    frame.playing = true
    frame.arriveAt = arriveAt
    frame.totalTime = totalTime
    frame.playInfo = info
    frame.playOpts = opts
    frame:Show()
    frame:Raise()
    if T.debug then
        T.debug(string.format("[VisualBoard] BoardPlay id=%s offset=%.2f slides=%d total=%.2f source=%s", tostring(board.id), frame.offset, #slides, totalTime, tostring(opts and opts.source or "manual")))
    end
    return true
end

-- 按【画板名】播放（token/timeline 入口）：先按名解析→拿真实 id 走 Play。
-- 缺画板时复用 VISUAL_BOARD_MISSING 警告（按名去重）。
function Overlay:PlayByRef(ref, offset, opts)
    local bossKeyText = type(opts) == "table" and opts.bossKeyText or nil
    local board = T.VisualBoardData and T.VisualBoardData.ResolveBoardRefForBoss and T.VisualBoardData:ResolveBoardRefForBoss(ref, bossKeyText)
        or (T.VisualBoardData and T.VisualBoardData:ResolveBoardRef(ref) or nil)
    if type(board) ~= "table" then
        if not self.missingWarned then
            self.missingWarned = {}
        end
        if not self.missingWarned[ref] then
            self.missingWarned[ref] = true
            T.msg(string.format(ResolveText("VISUAL_BOARD_MISSING", "缺少画板: %s（请让团长重新广播方案）"), tostring(ref)))
            if T.debug then
                T.debug(string.format("[VisualBoard] BoardMissing ref=%s", tostring(ref)))
            end
        end
        return false
    end
    return self:Play(board.id, offset, opts)
end

-- 把当前锁定态应用到单个 HUD（照 realtime_board:SetLocked）：解锁开鼠标+注册拖动+显示 resizer，锁定反之。
function Overlay:ApplyLockState(frame)
    local locked = self:IsLocked()
    frame:EnableMouse(not locked)
    -- 滚轮仅解锁态开（调不透明度）；锁定态关闭，避免吞掉游戏世界滚轮缩放。
    frame:EnableMouseWheel(not locked)
    if locked then
        frame:RegisterForDrag()
        if frame.resizer then frame.resizer:Hide() end
        -- 锁定→隐藏金边，回纯画布（背景透明度由 canvas 单独处理，不受金边影响）。
        if frame.editBorder then frame.editBorder:Hide() end
    else
        frame:RegisterForDrag("LeftButton")
        if frame.resizer then frame.resizer:Show() end
        -- 解锁→显示金边，让用户看见框、能抓（独立视觉，不动背景透明度）。
        if frame.editBorder then frame.editBorder:Show() end
    end
end

-- 锁定状态查询：单一权威读 _overlay._locked（默认锁定）。
function Overlay:IsLocked()
    return GetOverlayDB()._locked ~= false
end

-- 触发活跃 HUD 重渲一次：用于不透明度（背景层）改值后即时生效（滑块/滚轮调完不必等播放）。
-- 仅对已有 board 且在显示中的 HUD 调 RenderTick（OnUpdate 同一入口），无 board/未显示的空壳跳过。
function Overlay:RefreshActive()
    for _, frame in pairs(self.active or {}) do
        if type(frame.board) == "table" and frame:IsShown() then
            frame:RenderTick()
        end
    end
end

-- 解锁后无活跃 HUD 时，为指定 board 建壳并落位（修“没 Play 过就解锁空转”根因，照 realtime_board:EnsureUI）。
-- 拿不到 boardID（编辑器未选板）则不建壳，避免空 HUD。
function Overlay:EnsureShell(boardID)
    if not boardID then
        return nil
    end
    local frame = self:GetFrame(boardID)
    frame.boardID = boardID
    if not frame:IsShown() then
        frame:Show()
    end
    return frame
end

-- 解锁/锁定入口：自管锁定态（照 realtime_board:SetLocked），不靠 T.EditMode solo 覆盖层。
-- 解锁后整 HUD 可拖动（StartMoving）+ 右下角 resizer 可缩放（StartSizing），锁定即禁鼠标并隐藏 resizer。
-- boardID 可选：解锁时若无活跃 HUD，按 boardID 先建壳（编辑器传 selectedBoardID），避免解锁空转。
function Overlay:SetLocked(locked, boardID)
    local db = GetOverlayDB()
    db._locked = locked and true or false

    if not locked then
        self:EnsureShell(boardID)
    end

    for _, frame in pairs(self.active or {}) do
        self:ApplyLockState(frame)
        -- 锁回时把“只为解锁建的空壳（从未 Play）”收起，避免战斗外残留空 HUD（照 realtime_board 锁定即隐藏 shell）。
        if db._locked and not frame.playing then
            frame:Hide()
        end
    end

    T.msg(ResolveText("VISUAL_BOARD_OVERLAY_NAME", "视觉画板预览") .. " " ..
        (db._locked and ResolveText("OPT_ANCHOR_LOCK", "锁定锚点")
                     or ResolveText("OPT_ANCHOR_UNLOCK", "解锁锚点")))
end

function Overlay:ClearAll()
    for _, frame in pairs(self.active or {}) do
        frame:Hide()
    end
    self.missingWarned = {}
end

-- 停止所有活跃预览 HUD（编辑器「停止预览」入口）：遍历 active，逐帧停转并隐藏。
-- frame:Hide() 触发 OnHide → renderer:Clear() + playing=false，故此处只需置 playing=false 再 Hide，无需重复清渲染。
function Overlay:StopAll()
    for _, frame in pairs(self.active or {}) do
        frame.playing = false
        frame:Hide()
    end
end

end
