local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("visualBoard.editorLoaded", function()
do

local Editor = {}
T.VisualBoardEditorGUI = Editor

local selectedBoardID = nil
local selectedIDs = {}
local selectedGroupID = nil
-- 当前编辑帧（§6.1）：默认 1=基线帧；切板/新建复位为 1；删帧后由 slide_bar OnChanged 链 clamp。
local currentSlideIndex = 1
-- 无边画布视口会话态（§8.2）：zoom 缩放、panX/panY 平移；持久化到 STT_VisualBoardsDB._viewport[boardID]，不进 board/hash。
local viewport = { zoom = 1, panX = 0, panY = 0 }
-- fit-to-view 待办标记：切板/新建时若无持久化视口，置 true，待 host 尺寸落定后由 RenderEdit 惰性 fit 一次。
local pendingFit = false
local MarkPendingFit
-- 空格平移态（§8.2）：空格按住时 canvasFrame 左键拖拽改走平移而非选择。
local spaceHeld = false
local elementClipboard = nil
local bossIODialog = nil
local bossIOPreviewToken = 0
local MARKER_NAMES = {
    [0] = "无",
    [1] = "星",
    [2] = "圈",
    [3] = "菱",
    [4] = "三角",
    [5] = "月",
    [6] = "方",
    [7] = "叉",
    [8] = "骷髅",
}

local function Text(key, fallback)
    local value = L and L[key]
    if value == nil or value == key then
        return fallback or key
    end
    return value
end

local function GetUILayout()
    local semantic = C and C.DB and C.DB.semanticTimeline
    if type(semantic) ~= "table" then
        return nil
    end
    if type(semantic.ui) ~= "table" then
        semantic.ui = {}
    end
    return semantic.ui
end

local function IsLeftPanelCollapsed()
    local ui = GetUILayout()
    return ui and ui.visualBoardLeftCollapsed == true
end

local function IsRightPanelCollapsed()
    local ui = GetUILayout()
    return ui and ui.visualBoardRightCollapsed == true
end

local function SetLeftPanelCollapsed(collapsed)
    local ui = GetUILayout()
    if ui then
        ui.visualBoardLeftCollapsed = collapsed == true
    end
end

local function SetRightPanelCollapsed(collapsed)
    local ui = GetUILayout()
    if ui then
        ui.visualBoardRightCollapsed = collapsed == true
    end
end

local function Trim(text)
    local value = tostring(text or "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function SetFontText(fontString, key, fallback)
    if fontString then
        fontString:SetText(Text(key, fallback))
    end
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

local function GetBoards()
    if T.VisualBoard and T.VisualBoard.GetBoards then
        return T.VisualBoard:GetBoards()
    end
    return {}
end

-- 当前激活方案 info（§6.5 单一权威）：Note:GetActivePlan → Template.PreprocessText(content)。
-- 无方案 / 无 content / 无模板引擎 → 返回 nil（canvas/person 默认图标落问号）。与 drawer/overlay 同源，不另写"当前方案"逻辑。
local function GetActiveInfo()
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

-- RGB(0–1) → 6 位 HEX：person/shape 颜色统一 6 位 hex 字符串（见 data.lua NormalizeHexColor）。
-- 与 layer_panel 同款（3 行纯转换，不值得跨模块导出契约）。
local function RGBToHex(r, g, b)
    return string.format("%02X%02X%02X",
        math.floor((tonumber(r) or 1) * 255 + 0.5),
        math.floor((tonumber(g) or 1) * 255 + 0.5),
        math.floor((tonumber(b) or 1) * 255 + 0.5))
end

-- 视口持久化（§8.2）：存 STT_VisualBoardsDB._viewport[boardID]，不进 board/hash。
local function ViewportStore()
    if not (T.VisualBoardData and T.VisualBoardData.EnsureDB) then
        return nil
    end
    local db = T.VisualBoardData:EnsureDB()
    if type(db._viewport) ~= "table" then
        db._viewport = {}
    end
    return db._viewport
end

local function LoadViewport(boardID)
    viewport = { zoom = 1, panX = 0, panY = 0 }
    local store = boardID and ViewportStore() or nil
    local saved = store and store[boardID] or nil
    if type(saved) == "table" then
        viewport.zoom = tonumber(saved.zoom) or 1
        viewport.panX = tonumber(saved.panX) or 0
        viewport.panY = tonumber(saved.panY) or 0
        if viewport.zoom <= 0 then viewport.zoom = 1 end
        pendingFit = false
    else
        -- 无持久化视口（该板从未被用户调过视口）→ 首次渲染时 fit-to-view 居中装入整张 artboard。
        pendingFit = true
    end
end

local function SaveViewport()
    local store = selectedBoardID and ViewportStore() or nil
    if not store then
        return
    end
    store[selectedBoardID] = { zoom = viewport.zoom, panX = viewport.panX, panY = viewport.panY }
end

-- fit-to-view（§8.2）：把整张 artboard 等比缩放装进画布框（host 内框）并居中。
-- 留 0.92 边距；zoom = min(hostW/artW, hostH/artH) * 0.92；artboard 居中 → pan = (host - art*zoom)/2。
-- host 尺寸需已落定（>1），由调用方在 RenderEdit 内 host 宽高可用时触发；首帧 host=0 不可用。
-- 返回 true 表示已执行 fit；false 表示尺寸未就绪，留待下次。
local function FitViewport(panel)
    if not (panel and panel.canvasHost) then
        return false
    end
    local board = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetBoard(selectedBoardID) or nil
    if not board then
        return false
    end
    local hostW = panel.canvasHost:GetWidth() or 0
    local hostH = panel.canvasHost:GetHeight() or 0
    if hostW <= 1 or hostH <= 1 then
        return false
    end
    local artboard = type(board.artboard) == "table" and board.artboard or {}
    local artW = tonumber(artboard.w) or 1600
    local artH = tonumber(artboard.h) or 900
    if artW <= 0 or artH <= 0 then
        return false
    end
    local zoom = math.min(hostW / artW, hostH / artH) * 0.92
    if zoom <= 0 then zoom = 1 end
    viewport.zoom = zoom
    viewport.panX = (hostW - artW * zoom) / 2
    viewport.panY = (hostH - artH * zoom) / 2
    -- fit 是"无持久化视口时的临时居中"，绝不落盘：一旦落盘就污染"用户视口"这一唯一权威，
    -- 叠加 LoadViewport"有存档就不 fit"，会导致 fit 只生效一次、之后旧视口永久挡道。
    -- 落盘只在用户真正缩放/平移（ZoomAtCursor/PanViewport）时发生。
    return true
end

local function SelectFirstBoardIfNeeded()
    if selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetBoard(selectedBoardID) then
        return
    end
    selectedBoardID = nil
    local boards = GetBoards()
    if boards[1] then
        selectedBoardID = boards[1].id
        -- 首次自动选板（含初次打开）：加载该板视口；无持久化视口则置 pendingFit，首帧渲染时 fit-to-view。
        LoadViewport(selectedBoardID)
    end
end

local function SelectFirstBoardForBoss(bossKeyText)
    local targetBossKey = Trim(bossKeyText)
    if targetBossKey == "" then
        return false
    end
    for _, board in ipairs(GetBoards()) do
        if type(board) == "table" and Trim(board.bossKeyText) == targetBossKey then
            selectedBoardID = board.id
            currentSlideIndex = 1
            LoadViewport(selectedBoardID)
            MarkPendingFit()
            return true
        end
    end
    return false
end

function Editor:SetActiveBoard(boardID)
    if not (boardID and T.VisualBoardData and T.VisualBoardData:GetBoard(boardID)) then
        return false
    end
    selectedBoardID = boardID
    currentSlideIndex = 1
    LoadViewport(selectedBoardID)
    self:ClearSelectionState()
    return true
end

local function SetBossIODialogSummary(line1, line2, isError)
    if not bossIODialog then
        return
    end
    bossIODialog.summaryLine1:SetText(line1 or "")
    bossIODialog.summaryLine2:SetText(line2 or "")
    local r, g, b = 0.85, 0.82, 0.62
    if isError then
        r, g, b = 1, 0.35, 0.35
    end
    bossIODialog.summaryLine1:SetTextColor(r, g, b, 1)
    bossIODialog.summaryLine2:SetTextColor(r, g, b, 1)
end

local function RefreshBossIOImportPreview()
    if not (bossIODialog and bossIODialog.mode == "import") then
        return
    end
    local text = Trim(bossIODialog.editBox and bossIODialog.editBox:GetText() or "")
    if text == "" then
        SetBossIODialogSummary(
            Text("VISUAL_BOARD_BOSS_IMPORT_EMPTY", "尚未粘贴导入字符串"),
            Text("VISUAL_BOARD_BOSS_IMPORT_PREFIX_HINT", "请粘贴 STT-VBOARD-BOSS:1: 开头的视觉画板 Boss 包"),
            false)
        bossIODialog.primaryButton:Disable()
        return
    end
    local preview, err = T.VisualBoardData and T.VisualBoardData.PreviewBossBoardsString and T.VisualBoardData:PreviewBossBoardsString(text)
    if not preview or (tonumber(preview.boardCount) or 0) <= 0 then
        SetBossIODialogSummary(Text("VISUAL_BOARD_BOSS_IMPORT_PREVIEW_FAILED", "导入预览失败"), tostring(err or ""), true)
        bossIODialog.primaryButton:Disable()
        return
    end
    SetBossIODialogSummary(
        string.format("%s: %s | %s: %d",
            Text("BOSS", "BOSS"),
            preview.bossName ~= "" and preview.bossName or preview.bossKeyText,
            Text("VISUAL_BOARD_BOSS_BOARD_COUNT", "画板数量"),
            tonumber(preview.boardCount) or 0),
        string.format("%s: %s | %s: %s",
            Text("VISUAL_BOARD_BOSS_EXPORTER", "导出者"),
            preview.exporterName ~= "" and preview.exporterName or "?",
            Text("VISUAL_BOARD_BOSS_VERSION", "版本"),
            preview.exporterVersion ~= "" and preview.exporterVersion or "?"),
        false)
    bossIODialog.primaryButton:Enable()
end

local function ScheduleBossIOPreviewRefresh()
    bossIOPreviewToken = bossIOPreviewToken + 1
    local token = bossIOPreviewToken
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if token == bossIOPreviewToken then
                RefreshBossIOImportPreview()
            end
        end)
    else
        RefreshBossIOImportPreview()
    end
end

local function ApplyBossBoardImport()
    if not (bossIODialog and bossIODialog.editBox and T.VisualBoardData and T.VisualBoardData.ImportBossBoardsString) then
        return
    end
    local ok, result = T.VisualBoardData:ImportBossBoardsString(bossIODialog.editBox:GetText())
    if not ok then
        SetBossIODialogSummary(Text("VISUAL_BOARD_BOSS_IMPORT_FAILED", "导入失败"), tostring(result or ""), true)
        return
    end
    SelectFirstBoardForBoss(result.bossKeyText)
    if T.VisualBoardData.ClearHistory then
        T.VisualBoardData:ClearHistory()
    end
    Editor:ClearSelectionState()
    Editor:RefreshAll()
    local message = string.format(
        Text("VISUAL_BOARD_BOSS_IMPORT_DONE", "视觉画板 Boss 包导入完成：已覆盖 %d 张画板。"),
        tonumber(result.added) or tonumber(result.total) or 0)
    SetBossIODialogSummary(Text("VISUAL_BOARD_BOSS_IMPORT_SUCCESS", "导入成功"), message, false)
    T.msg(message)
end

local function EnsureBossIODialog()
    if bossIODialog then
        return bossIODialog
    end
    if not (T.CreatePopupWindow and T.NoteEditor and T.NoteEditor.CreateSimpleEditor and T.CreateButton) then
        return nil
    end
    bossIODialog = T.CreatePopupWindow(nil, {
        name = (T.addon_name or "STT") .. "_VisualBoardBossIODialog",
        width = 680,
        height = 460,
        strata = "DIALOG",
        alpha = 0.92,
        title = "",
    })
    bossIODialog.title:ClearAllPoints()
    bossIODialog.title:SetPoint("TOP", 0, -10)
    bossIODialog.title:SetFontObject(GameFontNormalLarge)

    local editor = T.NoteEditor:CreateSimpleEditor(bossIODialog)
    editor:SetPoint("TOPLEFT", bossIODialog, "TOPLEFT", 12, -42)
    editor:SetPoint("BOTTOMRIGHT", bossIODialog, "BOTTOMRIGHT", -12, 92)
    bossIODialog.editor = editor
    bossIODialog.editBox = editor.editBox

    bossIODialog.summaryLine1 = bossIODialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossIODialog.summaryLine1:SetPoint("BOTTOMLEFT", bossIODialog, "BOTTOMLEFT", 16, 56)
    bossIODialog.summaryLine1:SetPoint("BOTTOMRIGHT", bossIODialog, "BOTTOMRIGHT", -16, 56)
    bossIODialog.summaryLine1:SetJustifyH("LEFT")

    bossIODialog.summaryLine2 = bossIODialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bossIODialog.summaryLine2:SetPoint("TOPLEFT", bossIODialog.summaryLine1, "BOTTOMLEFT", 0, -4)
    bossIODialog.summaryLine2:SetPoint("TOPRIGHT", bossIODialog.summaryLine1, "BOTTOMRIGHT", 0, -4)
    bossIODialog.summaryLine2:SetJustifyH("LEFT")

    bossIODialog.primaryButton = T.CreateButton(bossIODialog, {
        width = 120,
        height = 26,
        point = { "BOTTOM", bossIODialog, "BOTTOM", -68, 16 },
    })
    bossIODialog.secondaryButton = T.CreateButton(bossIODialog, {
        width = 120,
        height = 26,
        point = { "LEFT", bossIODialog.primaryButton, "RIGHT", 16, 0 },
    })

    bossIODialog.primaryButton:SetScript("OnClick", function()
        if bossIODialog.mode == "export" then
            if bossIODialog.editBox then
                bossIODialog.editBox:SetFocus()
                bossIODialog.editBox:HighlightText()
            end
            T.msg(Text("VISUAL_BOARD_BOSS_COPY_HINT", "已复制，若未生效请手动全选复制"))
            return
        end
        ApplyBossBoardImport()
    end)
    bossIODialog.secondaryButton:SetScript("OnClick", function()
        bossIODialog:Hide()
    end)
    bossIODialog.editBox:SetScript("OnTextChanged", function(_, userInput)
        if bossIODialog.mode == "import" and userInput then
            ScheduleBossIOPreviewRefresh()
        end
    end)
    bossIODialog.editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        bossIODialog:Hide()
    end)
    return bossIODialog
end

local function ShowBossBoardExport()
    local frame = EnsureBossIODialog()
    local board = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetBoard(selectedBoardID) or nil
    if not (frame and frame.editBox and type(board) == "table" and T.VisualBoardData and T.VisualBoardData.ExportBossBoardsString) then
        return
    end
    local bossKeyText = Trim(board.bossKeyText)
    local text, err = T.VisualBoardData:ExportBossBoardsString(bossKeyText)
    frame.mode = "export"
    frame.title:SetText(Text("VISUAL_BOARD_BOSS_EXPORT_TITLE", "导出当前 Boss 画板"))
    frame.primaryButton:SetText(Text("VISUAL_BOARD_BOSS_SELECT_ALL_COPY", "全选复制"))
    frame.secondaryButton:SetText(CLOSE or "关闭")
    frame.primaryButton:Enable()
    frame.secondaryButton:Enable()
    frame:Show()
    if not text then
        frame.editBox:SetText("")
        SetBossIODialogSummary(Text("VISUAL_BOARD_BOSS_EXPORT_FAILED", "导出失败"), tostring(err or ""), true)
        frame.primaryButton:Disable()
        return
    end
    frame.editBox:SetText(text)
    local boards = T.VisualBoardData:CollectBossBoards(bossKeyText) or {}
    SetBossIODialogSummary(
        board.bg and tostring(board.bg.name or bossKeyText) or bossKeyText,
        string.format("%s: %d | %s: %d",
            Text("VISUAL_BOARD_BOSS_BOARD_COUNT", "画板数量"),
            #boards,
            Text("VISUAL_BOARD_BOSS_STRING_LENGTH", "字符串长度"),
            #text),
        false)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if bossIODialog and bossIODialog:IsShown() and bossIODialog.mode == "export" then
                bossIODialog.editBox:SetFocus()
                bossIODialog.editBox:HighlightText()
            end
        end)
    end
end

local function ShowBossBoardImport()
    local frame = EnsureBossIODialog()
    if not (frame and frame.editBox) then
        return
    end
    frame.mode = "import"
    frame.title:SetText(Text("VISUAL_BOARD_BOSS_IMPORT_TITLE", "导入 Boss 画板"))
    frame.primaryButton:SetText(Text("VISUAL_BOARD_BOSS_IMPORT_REPLACE", "覆盖导入"))
    frame.secondaryButton:SetText(CANCEL or "取消")
    frame.primaryButton:Disable()
    frame.secondaryButton:Enable()
    frame:Show()
    frame.editBox:SetText("")
    frame.editBox:SetFocus()
    if frame.editor and frame.editor.placeholder then
        frame.editor.placeholder:SetText(Text("VISUAL_BOARD_BOSS_IMPORT_PREFIX_HINT", "请粘贴 STT-VBOARD-BOSS:1: 开头的视觉画板 Boss 包"))
        frame.editor.placeholder:Show()
    end
    RefreshBossIOImportPreview()
end

-- ===== 选择状态机（单一权威：selectedIDs 集合 + selectedGroupID） =====
local function CountSelected()
    local count = 0
    for _ in pairs(selectedIDs) do
        count = count + 1
    end
    return count
end

function Editor:IsSelected(id)
    return id ~= nil and selectedIDs[id] == true
end

function Editor:GetSelectedList()
    local list = {}
    for id in pairs(selectedIDs) do
        list[#list + 1] = id
    end
    return list
end

-- 返回恰好单选时的元素 ID（无组、且选中集合恰好 1 个），否则 nil。
function Editor:GetSoleSelectedID()
    if selectedGroupID ~= nil then
        return nil
    end
    if CountSelected() ~= 1 then
        return nil
    end
    return next(selectedIDs)
end

function Editor:ClearSelectionState()
    selectedIDs = {}
    selectedGroupID = nil
end

-- 普通左键点元素：属组→选整组；否则单选。Shift→累加/移除。
function Editor:Select(id, additive)
    if not id then
        return
    end
    local element = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetElement(selectedBoardID, id) or nil
    if type(element) ~= "table" then
        return
    end
    local groupID = element.groupID
    if additive then
        if selectedIDs[id] then
            selectedIDs[id] = nil
        else
            selectedIDs[id] = true
        end
        selectedGroupID = nil
    elseif groupID then
        self:SelectGroup(groupID)
        return
    else
        selectedIDs = { [id] = true }
        selectedGroupID = nil
    end
    self:OnSelectionChanged()
end

-- 选中整组：组全部成员置 true，并记录 selectedGroupID。
function Editor:SelectGroup(groupID)
    if not (selectedBoardID and T.VisualBoardData) then
        return
    end
    local members = T.VisualBoardData:GetGroupMembers(selectedBoardID, groupID)
    selectedIDs = {}
    for _, element in ipairs(members or {}) do
        selectedIDs[element.id] = true
    end
    -- 同时把组 id 置 true，供图层面板高亮组行（组 id 不会匹配任何元素 id，对画布/数据操作无副作用）。
    selectedIDs[groupID] = true
    selectedGroupID = groupID
    self:OnSelectionChanged()
end

-- 进入组：脱离整组选中，单选该子元素。
function Editor:EnterGroupChild(id)
    selectedIDs = { [id] = true }
    selectedGroupID = nil
    self:OnSelectionChanged()
end

function Editor:ClearSelection()
    self:ClearSelectionState()
    self:HideContextMenu()
    self:RefreshProperties()
    self:RefreshLayerPanel()
    self:RenderEdit()
    return true
end

function Editor:OnSelectionChanged()
    self:HideContextMenu()
    self:RefreshProperties()
    self:RefreshLayerPanel()
    self:RenderEdit()
end

-- 无边画布舞台（§8.2）：canvasFrame 直接铺满 canvasHost；缩放/平移完全由 viewport 决定（不再按宽高比缩放 frame 本体）。
-- canvasFrame 已开 SetClipsChildren，超出画布框的渲染被裁剪。artboard 边框、网格由 canvas 渲染，editor 只负责把 viewport 传给 canvas。
local function UpdateCanvasStage(panel)
    if not (panel and panel.canvasHost and panel.canvasFrame) then
        return
    end
    panel.canvasFrame:ClearAllPoints()
    panel.canvasFrame:SetAllPoints(panel.canvasHost)
end

function Editor:GetSelectedElement()
    local soleID = self:GetSoleSelectedID()
    if not (selectedBoardID and soleID and T.VisualBoardData and T.VisualBoardData.GetElement) then
        return nil
    end
    return T.VisualBoardData:GetElement(selectedBoardID, soleID)
end

function Editor:RenderEdit()
    local panel = self.panel
    if not panel then
        return
    end
    -- 预览（§6.1）走 Overlay:Play 的独立覆盖层 morph，不占用编辑画布；编辑态此处只画当前帧。
    local board = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetBoard(selectedBoardID) or nil
    if not board then
        UpdateCanvasStage(panel)
        if panel.renderer then
            panel.renderer:Clear()
        end
        if panel.canvasLabel then
            panel.canvasLabel:Show()
        end
        return
    end
    UpdateCanvasStage(panel)
    -- 惰性 fit-to-view（§8.2）：切板/新建后若该板无持久化视口，待 host 尺寸落定后居中装入整张 artboard 一次；
    -- 首帧 host=0 时 FitViewport 返回 false，保持 pendingFit，待 OnSizeChanged 再次 RenderEdit 时补算。
    if pendingFit and FitViewport(panel) then
        pendingFit = false
    end
    if panel.renderer then
        -- renderState：编辑态当前帧解算（§6.3）；opts：UI 会话态（viewport 坐标换算 + personInfo 默认图标 + 选择/拖拽/变换回调）。
        panel.renderer:Render(board, {
            mode = "edit",
            currentSlideIndex = currentSlideIndex,
        }, {
            mode = "edit",
            viewport = viewport,
            currentSlideIndex = currentSlideIndex,
            personInfo = GetActiveInfo(),
            selectedIDs = selectedIDs,
            selectedGroupID = selectedGroupID,
            isSpacePanActive = function()
                return Editor:IsSpacePanActive()
            end,
            -- 取景框：编辑态恒显青框（独立一层，不与元素选择互扰）；拖拽/缩放写入唯一经 Data:SetPreviewRect。
            showPreviewRect = true,
            onPreviewRectDrag = function(x, y, w, h, transient)
                Editor:DragPreviewRect(x, y, w, h, transient)
            end,
            onSelect = function(elementID, additive)
                Editor:Select(elementID, additive)
            end,
            onDrag = function(elementID, x, y, transient)
                Editor:DragSelection(elementID, x, y, transient)
            end,
            onSegmentEndpointDrag = function(elementID, endpoint, x, y, transient)
                Editor:DragSegmentEndpoint(elementID, endpoint, x, y, transient)
            end,
            onRotationDrag = function(elementID, angle, transient)
                Editor:DragRotation(elementID, angle, transient)
            end,
            onDoubleClick = function(elementID)
                Editor:HandleDoubleClick(elementID)
            end,
            onContext = function(elementID)
                Editor:ShowContextMenu(elementID)
            end,
            onBackgroundClick = function()
                Editor:ClearSelection()
            end,
            -- 双击画布空白处 = fit-to-view 重置：被缩放/平移卡住时一键回到装下全图（唯一 fit 入口 ResetViewport）。
            onBackgroundDoubleClick = function()
                Editor:ResetViewport()
            end,
        })
    end
    if panel.canvasLabel then
        local hasContent = #(board.elements or {}) > 0 or board.bg ~= nil
        panel.canvasLabel:SetShown(not hasContent)
    end
end

function Editor:ScheduleRenderEdit()
    local panel = self.panel
    if not panel then
        return
    end
    if panel.__renderQueued then
        return
    end
    panel.__renderQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if panel then
                panel.__renderQueued = false
            end
            Editor:RenderEdit()
        end)
    else
        panel.__renderQueued = false
        self:RenderEdit()
    end
end

-- 对齐吸附（§8.3）：屏幕像素阈值，拖动中心/edge 与目标距离 < 此值则吸附并显示参考线。
local ALIGN_THRESHOLD = 6

-- 拖动中对齐吸附（§8.3）：元素左/中/右、上/中/下与其它元素及 artboard 基准吸附。
-- 入参：被拖元素提议中心 (x,y)（board 逻辑坐标）、被拖元素 id、参与比较的元素集合（其余非选中元素 + artboard 中线）。
-- 返回：吸附后的 (snappedX, snappedY) 与参考线数组（canvasFrame 局部屏幕坐标，传 Canvas:DrawAlignGuides）。
-- 阈值按屏幕像素判定：board 距离 = 屏幕阈值 / zoom，保证缩放下吸附手感一致。
local function ComputeAlignSnap(board, draggedID, x, y)
    local renderer = Editor.panel and Editor.panel.renderer
    if not (renderer and type(board) == "table") then
        return x, y, nil
    end
    local zoom = tonumber(viewport.zoom) or 1
    if zoom <= 0 then zoom = 1 end
    local tolBoard = ALIGN_THRESHOLD / zoom
    local artboard = type(board.artboard) == "table" and board.artboard or {}
    local artW = tonumber(artboard.w) or 1600
    local artH = tonumber(artboard.h) or 900

    local dragged = T.VisualBoardData:GetElement(selectedBoardID, draggedID)
    local boxW, boxH = T.VisualBoardData:GetElementBox(dragged)
    boxW = tonumber(boxW) or 0
    boxH = tonumber(boxH) or 0
    local sourceX = { x - boxW / 2, x, x + boxW / 2 }
    local sourceY = { y - boxH / 2, y, y + boxH / 2 }

    local candX = { 0, artW / 2, artW }
    local candY = { 0, artH / 2, artH }
    -- 比较目标取“当前帧解算位”（slide≥2 时元素显示位 = 覆写位），与拖动中实际可见位置一致。
    for _, el in ipairs(board.elements or {}) do
        if type(el) == "table" and el.id ~= draggedID and not selectedIDs[el.id] then
            local resolved = T.VisualBoardData:ResolveElementAtSlide(el, currentSlideIndex, board)
            local cx = tonumber(resolved.x) or tonumber(el.x) or 0
            local cy = tonumber(resolved.y) or tonumber(el.y) or 0
            local w, h = T.VisualBoardData:GetElementBox(el)
            w = tonumber(w) or 0
            h = tonumber(h) or 0
            candX[#candX + 1] = cx - w / 2
            candX[#candX + 1] = cx
            candX[#candX + 1] = cx + w / 2
            candY[#candY + 1] = cy - h / 2
            candY[#candY + 1] = cy
            candY[#candY + 1] = cy + h / 2
        end
    end

    local snappedX, snappedY = x, y
    local bestX, bestY, bestSourceX, bestSourceY
    local bestDX, bestDY = tolBoard, tolBoard
    for _, cx in ipairs(candX) do
        for _, sx in ipairs(sourceX) do
            local d = math.abs(sx - cx)
            if d <= bestDX then bestDX = d; bestX = cx; bestSourceX = sx end
        end
    end
    for _, cy in ipairs(candY) do
        for _, sy in ipairs(sourceY) do
            local d = math.abs(sy - cy)
            if d <= bestDY then bestDY = d; bestY = cy; bestSourceY = sy end
        end
    end
    if bestX and bestSourceX then snappedX = x + (bestX - bestSourceX) end
    if bestY and bestSourceY then snappedY = y + (bestY - bestSourceY) end

    -- 参考线：竖线沿 artboard 全高、横线沿 artboard 全宽，换算到屏幕局部坐标。
    local lines = {}
    if bestX then
        local sx, syTop = renderer:BoardToScreen(board, viewport, bestX, 0)
        local _, syBot = renderer:BoardToScreen(board, viewport, bestX, artH)
        lines[#lines + 1] = { sx, syTop, sx, syBot }
    end
    if bestY then
        local sxLeft, sy = renderer:BoardToScreen(board, viewport, 0, bestY)
        local sxRight = renderer:BoardToScreen(board, viewport, artW, bestY)
        lines[#lines + 1] = { sxLeft, sy, sxRight, sy }
    end
    if #lines == 0 then
        lines = nil
    end
    return snappedX, snappedY, lines
end

-- 拖动选中元素 → 整体平移整个选中集（§6.1）。
-- 当前帧==1（基线帧）：改基线坐标（Data:MoveElements 增量平移整个选中集）。
-- 当前帧>=2：写该帧覆写（Data:SetSlideOverride x/y），不动基线；多选集合各自写各自帧坐标。
function Editor:DragSelection(elementID, x, y, transient)
    if not (selectedBoardID and T.VisualBoardData) then
        return
    end
    -- 被拖元素若不在选中集，先单选它（点住即拖场景）
    if not selectedIDs[elementID] then
        self:Select(elementID, false)
    end
    local element = T.VisualBoardData:GetElement(selectedBoardID, elementID)
    if type(element) ~= "table" then
        return
    end
    local ids = self:GetSelectedList()
    local board = T.VisualBoardData:GetBoard(selectedBoardID)

    -- 对齐吸附（§8.3）：仅拖动过程（transient）参与，吸附被拖元素中心 → 其余元素一致随动。
    -- 提交（非 transient）时清除参考线（空数组）。
    local guides
    if transient then
        x, y, guides = ComputeAlignSnap(board, elementID, tonumber(x) or element.x, tonumber(y) or element.y)
    end
    if self.panel and self.panel.renderer then
        self.panel.renderer:DrawAlignGuides(transient and guides or nil)
    end

    if currentSlideIndex >= 2 then
        -- 帧覆写：被拖元素移到 (x,y)，其余选中元素按"同一屏幕增量"写各自帧坐标。
        -- 增量 = 目标位 - 被拖元素当前帧解算位（不是基线位），保证多选集合在帧 i 整体平移一致。
        local dragged = T.VisualBoardData:ResolveElementAtSlide(element, currentSlideIndex, board)
        local dx = (tonumber(x) or dragged.x) - (tonumber(dragged.x) or 0)
        local dy = (tonumber(y) or dragged.y) - (tonumber(dragged.y) or 0)
        for _, id in ipairs(ids) do
            local member = T.VisualBoardData:GetElement(selectedBoardID, id)
            if type(member) == "table" then
                local resolved = T.VisualBoardData:ResolveElementAtSlide(member, currentSlideIndex, board)
                T.VisualBoardData:SetSlideOverride(selectedBoardID, currentSlideIndex, id, "x", (tonumber(resolved.x) or member.x) + dx, transient)
                T.VisualBoardData:SetSlideOverride(selectedBoardID, currentSlideIndex, id, "y", (tonumber(resolved.y) or member.y) + dy, transient)
            end
        end
        if not transient then
            self:RefreshProperties()
            self:RefreshLayerPanel()
        end
        if transient then self:ScheduleRenderEdit() else self:RenderEdit() end
        return
    end

    local dx = (tonumber(x) or element.x) - (tonumber(element.x) or 0)
    local dy = (tonumber(y) or element.y) - (tonumber(element.y) or 0)
    T.VisualBoardData:MoveElements(selectedBoardID, ids, dx, dy, transient)
    if not transient then
        self:RefreshProperties()
        self:RefreshLayerPanel()
    end
    if transient then self:ScheduleRenderEdit() else self:RenderEdit() end
end

function Editor:DragSegmentEndpoint(elementID, endpoint, x, y, transient)
    if not (selectedBoardID and T.VisualBoardData and T.VisualBoardData.UpdateSegmentEndpoint) then
        return
    end
    if not selectedIDs[elementID] then
        self:Select(elementID, false)
    end
    T.VisualBoardData:UpdateSegmentEndpoint(selectedBoardID, elementID, endpoint, x, y, transient)
    if not transient then
        self:RefreshProperties()
        self:RefreshLayerPanel()
    end
    if transient then self:ScheduleRenderEdit() else self:RenderEdit() end
end

function Editor:DragRotation(elementID, angle, transient)
    if not (selectedBoardID and T.VisualBoardData) then
        return
    end
    if not selectedIDs[elementID] then
        self:Select(elementID, false)
    end
    if currentSlideIndex >= 2 then
        T.VisualBoardData:SetSlideOverride(selectedBoardID, currentSlideIndex, elementID, "rotation", tonumber(angle) or 0, transient)
    else
        T.VisualBoardData:UpdateElementRotation(selectedBoardID, elementID, tonumber(angle) or 0, transient)
    end
    if not transient then
        self:RefreshProperties()
        self:RefreshLayerPanel()
    end
    if transient then self:ScheduleRenderEdit() else self:RenderEdit() end
end

-- 拖动/缩放取景框 → 写 previewRect（运行时 HUD 只 fit 该区）。
-- 写入唯一经 Data:SetPreviewRect（钳制 + transient 撤销分层在 Data 层）；canvas 只读 board.previewRect 重画。
function Editor:DragPreviewRect(x, y, w, h, transient)
    if not (selectedBoardID and T.VisualBoardData) then
        return
    end
    T.VisualBoardData:SetPreviewRect(selectedBoardID, x, y, w, h, transient)
    self:RenderEdit()
end

function Editor:HandleDoubleClick(elementID)
    local element = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetElement(selectedBoardID, elementID) or nil
    if type(element) ~= "table" then
        return
    end
    if element.type == "text" then
        self:BeginInlineEdit(elementID)
    elseif element.groupID then
        self:EnterGroupChild(elementID)
    end
end

-- slide_bar 帧条刷新（取代旧 step 概念）：守卫 panel.slideBar 后调 SlideBar:Refresh()。
function Editor:RefreshSlideBar()
    if T.VisualBoardSlideBar and T.VisualBoardSlideBar.Refresh and self.panel and self.panel.slideBar then
        T.VisualBoardSlideBar:Refresh()
    end
end

-- 顶栏画板选择器：列出所有画板，onSelect 切换并 RefreshAll。
function Editor:RefreshList()
    local panel = self.panel
    if not panel then
        return
    end
    SelectFirstBoardIfNeeded()

    local boards = GetBoards()
    local selector = panel.boardSelector
    if not selector then
        return
    end

    local items = {}
    for _, board in ipairs(boards) do
        items[#items + 1] = {
            value = board.id,
            text = tostring(board.name or board.id),
        }
    end
    selector:SetItems(items)
    selector.onSelect = function(value)
        if value == selectedBoardID then
            return
        end
        if T.VisualBoardData and T.VisualBoardData.ClearHistory then
            T.VisualBoardData:ClearHistory()
        end
        if Editor:SetActiveBoard(value) then
            Editor:RefreshAll()
        end
    end
    selector:SetLabel(Text("VISUAL_BOARD_SELECTOR_LABEL", "画板"))
    selector:SetSelectorEnabled(#boards > 0)
    if #boards > 0 then
        local current = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetBoard(selectedBoardID) or nil
        selector:SetSelectedValue(selectedBoardID, current and tostring(current.name or current.id) or Text("VISUAL_BOARD_EMPTY_LIST", "暂无画板"))
    else
        selector:SetSelectedValue(nil, Text("VISUAL_BOARD_EMPTY_LIST", "暂无画板"))
    end
end

-- 单元素字段写回单一权威：经 UpdateElement 深合并 params（含 person 子件嵌套）；禁同义字段。
-- 写后刷新画布 + 属性面板（属性面板保持当前焦点不丢，靠 inspector 行级 refresh）。
function Editor:WriteField(fields)
    local soleID = self:GetSoleSelectedID()
    if not (selectedBoardID and soleID and T.VisualBoardData and T.VisualBoardData.UpdateElement and type(fields) == "table") then
        return
    end
    T.VisualBoardData:UpdateElement(selectedBoardID, soleID, fields)
    self:RenderEdit()
end

-- ===== 动态行式 inspector（§7 person 三子件 + 其它型分区）=====
-- 单元素属性区按元素类型生成字段行：每行一个控件，竖直递推定位，放进可滚动 content。
-- 行类型：header(分区标题) / text(编辑框) / number(数字编辑框) / slider(滑条) /
--   toggle(开/关循环) / cycle(枚举循环) / segmented(枚举直选) / color(色块+取色器) / action(按钮)。
-- 行实例按"序号"复用（同一槽位换不同 row 类型时重建该槽位控件），避免每次 Refresh 重建全部 frame。

local INSPECTOR_ROW_TYPES = { header = true, text = true, number = true, slider = true, toggle = true, cycle = true, segmented = true, color = true, action = true }

-- 取/建第 index 个行容器（一行 = 一个 Frame，承载该行所有子控件）。
local function AcquireInspectorRow(panel, index)
    local rows = panel.inspectorRows
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, panel.inspectorContent)
    row.widgets = {}
    rows[index] = row
    return row
end

-- 行内控件按 (rowIndex, slotKey) 复用；类型变化时销毁旧控件重建（隐藏即可，WoW 不真销毁 frame）。
local function AcquireRowWidget(row, slotKey, ctor)
    local existing = row.widgets[slotKey]
    if existing and existing.__kind == slotKey then
        return existing
    end
    if existing then
        existing:Hide()
    end
    local widget = ctor()
    widget.__kind = slotKey
    row.widgets[slotKey] = widget
    return widget
end

-- 按字段描述 def 构建/刷新一行。返回该行高度。def 字段见各 row 类型注释。
local function BuildInspectorRow(panel, row, def, width, rowH, labelH)
    local Style = T.Style
    local GAP = Style.Scale(6)
    local labelColor = Style.Color.TEXT_INACTIVE
    -- 先隐藏所有子控件，本行用到的再 Show。
    for _, w in pairs(row.widgets) do
        w:Hide()
    end

    if def.type == "header" then
        local title = AcquireRowWidget(row, "headerText", function()
            return T.CreateFontString(row, {
                template = "GameFontHighlightSmall",
                size = Style.Scaled("LABEL_FONT_SIZE"),
                justifyH = "LEFT",
                color = Style.Color.KYRIAN_GOLD,
            })
        end)
        title:ClearAllPoints()
        title:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, Style.Scale(2))
        title:SetWidth(width)
        title:SetText(def.text)
        title:Show()
        return labelH + GAP
    end

    -- 公共：左侧 label（除 header / action / 纯色块外都有）。
    local hasLabel = def.label ~= nil
    if hasLabel then
        local label = AcquireRowWidget(row, "label", function()
            return T.CreateFontString(row, {
                template = "GameFontDisableSmall",
                size = Style.Scaled("LABEL_FONT_SIZE"),
                justifyH = "LEFT",
                color = labelColor,
            })
        end)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        label:SetWidth(width)
        label:SetText(def.label)
        label:Show()
    end
    local controlY = hasLabel and -(labelH) or 0
    local controlH = T.Style.Scaled("BUTTON_HEIGHT")

    if def.type == "text" or def.type == "number" then
        local edit = AcquireRowWidget(row, "edit", function()
            return T.CreateEditBox(row, { width = width, height = controlH, autoFocus = false })
        end)
        edit:ClearAllPoints()
        edit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, controlY)
        edit:SetWidth(width)
        if not edit:HasFocus() then
            edit:SetText(def.get and tostring(def.get()) or "")
        end
        edit:SetScript("OnEnterPressed", function(es)
            local raw = es:GetText()
            local value = def.type == "number" and tonumber(raw) or raw
            if def.set then def.set(value) end
            es:ClearFocus()
        end)
        edit:SetScript("OnEditFocusLost", function(es)
            local raw = es:GetText()
            local value = def.type == "number" and tonumber(raw) or raw
            if def.set then def.set(value) end
        end)
        edit:Show()
        panel.inspectorEdits[#panel.inspectorEdits + 1] = edit
        return (hasLabel and labelH or 0) + controlH + GAP
    elseif def.type == "slider" then
        -- 滑条行：用原生 OptionsSliderTemplate（与 CreateSliderRow 同款，但内联以适配动态 content）。
        local slider = AcquireRowWidget(row, "slider", function()
            local s = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
            s:SetHeight(T.Style.Scaled("SLIDER_HEIGHT"))
            s:SetObeyStepOnDrag(true)
            if s.Low then s.Low:SetText("") end
            if s.High then s.High:SetText("") end
            if s.Text then s.Text:SetText("") end
            return s
        end)
        slider:ClearAllPoints()
        slider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, controlY - T.Style.Scale(4))
        slider:SetWidth(width)
        -- __refreshing 守卫必须包住【整个重配过程】：SetMinMaxValues 用新范围钳旧值会
        -- 触发上一个元素遗留的 OnValueChanged 闭包，若此刻守卫未开，旧 setter 会把钳后的
        -- 值写进新选中的元素。故在 SetMinMaxValues 前置 true，挂好新闭包后才置 false。
        slider.__refreshing = true
        slider:SetMinMaxValues(def.min or 0, def.max or 1)
        slider:SetValueStep(def.step or 1)
        slider:SetValue(def.get and (tonumber(def.get()) or 0) or 0)
        slider:SetScript("OnValueChanged", function(s, value)
            if s.__refreshing then return end
            local step = def.step or 1
            local snapped = step > 0 and (math.floor(value / step + 0.5) * step) or value
            if def.set then def.set(snapped) end
            -- 即时更新 label 上的数值文本。
            if hasLabel and row.widgets.label then
                row.widgets.label:SetText(def.labelFn and def.labelFn(snapped) or def.label)
            end
        end)
        if hasLabel and row.widgets.label and def.labelFn then
            row.widgets.label:SetText(def.labelFn(def.get and (tonumber(def.get()) or 0) or 0))
        end
        slider.__refreshing = false
        slider:Show()
        return (hasLabel and labelH or 0) + T.Style.Scaled("SLIDER_HEIGHT") + GAP + T.Style.Scale(4)
    elseif def.type == "toggle" or def.type == "cycle" then
        local btn = AcquireRowWidget(row, "button", function()
            return T.CreateButton(row, { width = width, height = controlH })
        end)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, hasLabel and -labelH or 0)
        btn:SetWidth(width)
        btn:SetText(def.textFn and def.textFn() or "")
        btn:SetScript("OnClick", function()
            if def.onClick then def.onClick() end
        end)
        btn:Show()
        return (hasLabel and labelH or 0) + controlH + GAP
    elseif def.type == "segmented" then
        local options = type(def.options) == "table" and def.options or {}
        local count = #options
        local active = def.get and def.get() or nil
        if count <= 0 then
            return (hasLabel and labelH or 0) + GAP
        end
        local itemGap = Style.Scale(4)
        local buttonW = math.floor((width - itemGap * (count - 1)) / count + 0.5)
        for i, option in ipairs(options) do
            local btn = AcquireRowWidget(row, "segmented" .. i, function()
                return T.CreateButton(row, { width = buttonW, height = controlH })
            end)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (buttonW + itemGap), hasLabel and -labelH or 0)
            btn:SetWidth(buttonW)
            local selected = option.value == active
            btn:SetText(selected and ("|cffffd100" .. tostring(option.text or "") .. "|r") or tostring(option.text or ""))
            btn:SetScript("OnClick", function()
                if def.set and option.value ~= (def.get and def.get() or active) then
                    def.set(option.value)
                end
            end)
            btn:Show()
        end
        return (hasLabel and labelH or 0) + controlH + GAP
    elseif def.type == "color" then
        -- 色块行：左 label（如有），右侧色块按钮（点开 T.ShowColorPicker）。
        local swatch = AcquireRowWidget(row, "swatch", function()
            local b = CreateFrame("Button", nil, row)
            b:SetHeight(controlH)
            T.ApplyBackdrop(b, { alpha = 0.28, style = "tooltip", borderColor = { 0.55, 0.55, 0.55, 0.9 } })
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
            b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
            return b
        end)
        swatch:ClearAllPoints()
        swatch:SetPoint("TOPLEFT", row, "TOPLEFT", 0, hasLabel and -labelH or 0)
        swatch:SetWidth(width)
        local hex = def.get and tostring(def.get() or "FFFFFF") or "FFFFFF"
        local r = (tonumber(hex:sub(1, 2), 16) or 255) / 255
        local g = (tonumber(hex:sub(3, 4), 16) or 255) / 255
        local b = (tonumber(hex:sub(5, 6), 16) or 255) / 255
        swatch.tex:SetColorTexture(r, g, b, 1)
        swatch:SetScript("OnClick", function()
            T.ShowColorPicker({
                color = def.get and tostring(def.get() or "FFFFFF") or "FFFFFF",
                onChange = function(cr, cg, cb)
                    if def.set then def.set(RGBToHex(cr, cg, cb)) end
                    swatch.tex:SetColorTexture(cr, cg, cb, 1)
                end,
            })
        end)
        swatch:Show()
        return (hasLabel and labelH or 0) + controlH + GAP
    elseif def.type == "action" then
        local btn = AcquireRowWidget(row, "action", function()
            return T.CreateButton(row, { width = width, height = controlH })
        end)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        btn:SetWidth(width)
        btn:SetText(def.text or "")
        btn:SetScript("OnClick", function(b)
            if def.onClick then def.onClick(b) end
        end)
        btn:Show()
        return controlH + GAP
    end
    return 0
end

-- 渲染整个字段描述数组到 inspector content，自顶向下递推，更新 content 高度。
local function RenderInspector(panel, defs)
    local Style = T.Style
    local content = panel.inspectorContent
    if not content then
        return
    end
    local fallbackWidth = panel.inspectorInnerWidth or (Style.Scale(188) - Style.Scale(12) * 2)
    local scroll = panel.inspectorScroll and panel.inspectorScroll.scroll or nil
    local width = scroll and scroll.viewport and scroll.viewport:GetWidth() or content:GetWidth()
    if width <= 1 then
        local frameWidth = panel.inspectorFrame and panel.inspectorFrame:GetWidth() or fallbackWidth
        width = frameWidth - (scroll and scroll.scrollBarWidth or 0)
    end
    width = math.max(1, width > 1 and width or fallbackWidth)
    local rowH = Style.Scaled("BUTTON_HEIGHT")
    local labelH = math.floor(Style.Scaled("LABEL_FONT_SIZE") * 1.4 + 0.5)
    panel.inspectorEdits = {}

    local y = 0
    local index = 0
    for _, def in ipairs(defs) do
        if type(def) == "table" and INSPECTOR_ROW_TYPES[def.type] then
            index = index + 1
            local row = AcquireInspectorRow(panel, index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            local h = BuildInspectorRow(panel, row, def, width, rowH, labelH)
            row:SetHeight(math.max(1, h))
            row:Show()
            y = y + h
        end
    end
    -- 多余行隐藏。
    for i = index + 1, #panel.inspectorRows do
        panel.inspectorRows[i]:Hide()
    end
    if panel.inspectorScroll and panel.inspectorScroll.SetContentHeight then
        panel.inspectorScroll:SetContentHeight(y + Style.Scale(8))
    end
end

-- 构建当前单选元素的字段描述数组（§7 四型；person 三子件分区）。
-- 所有 set 都走 Editor:WriteField（UpdateElement 深合并），即时生效；公共旋转/缩放放末尾分区。
function Editor:BuildElementInspectorDefs(element)
    local params = element.params or {}
    local kind = element.type
    local defs = {}
    local function add(def) defs[#defs + 1] = def end

    if kind == "person" then
        local circle = type(params.circle) == "table" and params.circle or {}
        local icon = type(params.icon) == "table" and params.icon or {}
        local text = type(params.text) == "table" and params.text or {}
        local hl = type(params.highlightStyle) == "table" and params.highlightStyle or nil

        add({ type = "header", text = Text("VISUAL_BOARD_INSP_PERSON", "人员") })
        add({ type = "text", label = Text("VISUAL_BOARD_INSP_SLOTNAME", "槽位名"),
            get = function() return params.slotName or "" end,
            set = function(v) Editor:WriteField({ params = { slotName = tostring(v or "") } }); Editor:RefreshProperties() end })

        -- 文本子件分区
        add({ type = "header", text = Text("VISUAL_BOARD_INSP_TEXT_SECTION", "名签文本") })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_TEXT_ENABLED", "显示名签"),
            textFn = function() return text.enabled ~= false and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { text = { enabled = not (text.enabled ~= false) } } }); Editor:RefreshProperties() end })
        add({ type = "cycle", label = Text("VISUAL_BOARD_INSP_TEXT_POSITION", "名签位置"),
            textFn = function() return Editor:PositionText(text.position or "top") end,
            onClick = function()
                local order = { "top", "bottom", "left", "right" }
                local cur = tostring(text.position or "top")
                local nextPos = "top"
                for i, p in ipairs(order) do if p == cur then nextPos = order[i % #order + 1]; break end end
                Editor:WriteField({ params = { text = { position = nextPos } } }); Editor:RefreshProperties()
            end })
        add({ type = "cycle", label = Text("VISUAL_BOARD_TEXT_ALIGN", "文字对齐"),
            textFn = function() return tostring(text.justifyH or "CENTER") end,
            onClick = function()
                local order = { "LEFT", "CENTER", "RIGHT" }
                local cur = tostring(text.justifyH or "CENTER"):upper()
                local nextValue = "CENTER"
                for i, value in ipairs(order) do if value == cur then nextValue = order[i % #order + 1]; break end end
                Editor:WriteField({ params = { text = { justifyH = nextValue } } }); Editor:RefreshProperties()
            end })
        add({ type = "number", label = Text("VISUAL_BOARD_INSP_TEXT_DX", "横向偏移"),
            get = function() return tonumber(text.dx) or 0 end,
            set = function(v) Editor:WriteField({ params = { text = { dx = tonumber(v) or 0 } } }) end })
        add({ type = "number", label = Text("VISUAL_BOARD_INSP_TEXT_DY", "纵向偏移"),
            get = function() return tonumber(text.dy) or 0 end,
            set = function(v) Editor:WriteField({ params = { text = { dy = tonumber(v) or 0 } } }) end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_FONTSIZE", "字号"),
            min = 8, max = 60, step = 1,
            get = function() return tonumber(text.fontSize) or 19 end,
            labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_FONTSIZE", "字号"), math.floor(v + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { text = { fontSize = v } } }) end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_TEXTSCALE", "文字缩放"),
            min = 0.5, max = 3, step = 0.1,
            get = function() return tonumber(text.scale) or 1 end,
            labelFn = function(v) return string.format("%s: %.1f", Text("VISUAL_BOARD_INSP_TEXTSCALE", "文字缩放"), v) end,
            set = function(v) Editor:WriteField({ params = { text = { scale = v } } }) end })
        add({ type = "color", label = Text("VISUAL_BOARD_INSP_TEXT_COLOR", "字色"),
            get = function() return text.color or "EFFFFF" end,
            set = function(hex) Editor:WriteField({ params = { text = { color = hex } } }) end })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_BOLD", "粗体"),
            textFn = function() return text.bold == true and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { text = { bold = not (text.bold == true) } } }); Editor:RefreshProperties() end })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_OUTLINE", "描边"),
            textFn = function() return text.outline ~= false and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { text = { outline = not (text.outline ~= false) } } }); Editor:RefreshProperties() end })
        add({ type = "color", label = Text("VISUAL_BOARD_INSP_OUTLINE_COLOR", "描边色"),
            get = function() return text.outlineColor or "000000" end,
            set = function(hex) Editor:WriteField({ params = { text = { outlineColor = hex } } }) end })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_SHADOW", "阴影"),
            textFn = function() return text.shadow ~= false and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { text = { shadow = not (text.shadow ~= false) } } }); Editor:RefreshProperties() end })

        -- 图标子件分区
        add({ type = "header", text = Text("VISUAL_BOARD_INSP_ICON_SECTION", "图标") })
        add({ type = "action", text = Text("VISUAL_BOARD_ICON_PICK", "换图标"),
            onClick = function(b) Editor:OpenIconPicker(b) end })
        add({ type = "number", label = Text("VISUAL_BOARD_INSP_SPELL_ID", "法术ID"),
            get = function() return tonumber(icon.spellID) or "" end,
            set = function(v) Editor:WriteField({ params = { icon = { spellID = tonumber(v) } } }); Editor:RefreshProperties() end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_ICON_SIZE", "图标尺寸"),
            min = 12, max = 120, step = 1,
            get = function() return tonumber(icon.size) or 40 end,
            labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_ICON_SIZE", "图标尺寸"), math.floor(v + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { icon = { size = v } } }) end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_ICON_BORDER", "图标描边"),
            min = 0, max = 12, step = 1,
            get = function() return tonumber(icon.borderSize) or 0 end,
            labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_ICON_BORDER", "图标描边"), math.floor(v + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { icon = { borderSize = v } } }) end })
        add({ type = "color", label = Text("VISUAL_BOARD_INSP_ICON_BORDER_COLOR", "描边色"),
            get = function() return icon.borderColor or "000000" end,
            set = function(hex) Editor:WriteField({ params = { icon = { borderColor = hex } } }) end })

        -- 圆底子件分区
        add({ type = "header", text = Text("VISUAL_BOARD_INSP_CIRCLE_SECTION", "圆底") })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_CIRCLE_ENABLED", "显示圆底"),
            textFn = function() return circle.enabled ~= false and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { circle = { enabled = not (circle.enabled ~= false) } } }); Editor:RefreshProperties() end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_CIRCLE_RADIUS", "半径"),
            min = 10, max = 200, step = 1,
            get = function() return tonumber(circle.radius) or 58 end,
            labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_CIRCLE_RADIUS", "半径"), math.floor(v + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { circle = { radius = v } } }) end })
        add({ type = "color", label = Text("VISUAL_BOARD_INSP_CIRCLE_COLOR", "圆色"),
            get = function() return circle.color or "33CC66" end,
            set = function(hex) Editor:WriteField({ params = { circle = { color = hex } } }) end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_CIRCLE_ALPHA", "不透明度"),
            min = 0, max = 1, step = 0.05,
            get = function() return tonumber(circle.alpha) or 0.5 end,
            labelFn = function(v) return string.format("%s: %d%%", Text("VISUAL_BOARD_INSP_CIRCLE_ALPHA", "不透明度"), math.floor(v * 100 + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { circle = { alpha = v } } }) end })
        add({ type = "cycle", label = Text("VISUAL_BOARD_INSP_CIRCLE_STYLE", "样式"),
            textFn = function() return (circle.shapeStyle == "ring") and Text("VISUAL_BOARD_INSP_RING", "空心环") or Text("VISUAL_BOARD_INSP_SOLID", "实心") end,
            onClick = function()
                local nextStyle = (circle.shapeStyle == "ring") and "solid" or "ring"
                Editor:WriteField({ params = { circle = { shapeStyle = nextStyle } } }); Editor:RefreshProperties()
            end })
        if circle.shapeStyle == "ring" then
            add({ type = "slider", label = Text("VISUAL_BOARD_INSP_RING_THICKNESS", "环厚度"),
                min = 2, max = 30, step = 1,
                get = function() return tonumber(circle.ringThickness) or 6 end,
                labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_RING_THICKNESS", "环厚度"), math.floor(v + 0.5)) end,
                set = function(v) Editor:WriteField({ params = { circle = { ringThickness = v } } }) end })
        end

        -- 高亮样式分区（§10）：运行时仅"本机 person"套用，编辑期此处只配置样式参数（不联动本机判定）。
        -- highlightStyle 子表始终存在即生效（data 规范化保留 table），缺省值由首次写入 seed；无独立 enabled 开关。
        add({ type = "header", text = Text("VISUAL_BOARD_INSP_HL_SECTION", "本机高亮样式") })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_HL_SCALE", "放大倍率"),
            min = 1, max = 2.5, step = 0.05,
            get = function() return tonumber(hl and hl.scale) or 1.25 end,
            labelFn = function(v) return string.format("%s: %.2f", Text("VISUAL_BOARD_INSP_HL_SCALE", "放大倍率"), v) end,
            set = function(v) Editor:WriteField({ params = { highlightStyle = { scale = v } } }) end })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_HL_GLOW", "柔光晕"),
            textFn = function() return (not hl or hl.glow ~= false) and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { highlightStyle = { glow = not (hl and hl.glow ~= false) } } }); Editor:RefreshProperties() end })
        add({ type = "color", label = Text("VISUAL_BOARD_INSP_HL_GLOWCOLOR", "光晕色"),
            get = function() return (hl and hl.glowColor) or "FFD200" end,
            set = function(hex) Editor:WriteField({ params = { highlightStyle = { glowColor = hex } } }) end })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_HL_DESAT", "其它人灰度"),
            textFn = function() return (hl and hl.desaturateOthers == true) and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { highlightStyle = { desaturateOthers = not (hl and hl.desaturateOthers == true) } } }); Editor:RefreshProperties() end })
    elseif kind == "text" then
        add({ type = "header", text = Text("VISUAL_BOARD_TYPE_TEXT", "文字") })
        add({ type = "text", label = Text("VISUAL_BOARD_INSP_TEXT_CONTENT", "文字内容"),
            get = function() return params.text or "" end,
            set = function(v) Editor:WriteField({ params = { text = tostring(v or "") } }) end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_FONTSIZE", "字号"),
            min = 8, max = 120, step = 1,
            get = function() return tonumber(params.fontSize) or 40 end,
            labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_FONTSIZE", "字号"), math.floor(v + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { fontSize = v } }) end })
        add({ type = "color", label = Text("VISUAL_BOARD_INSP_TEXT_COLOR", "字色"),
            get = function() return params.color or "00FF8C" end,
            set = function(hex) Editor:WriteField({ params = { color = hex } }) end })
        add({ type = "cycle", label = Text("VISUAL_BOARD_TEXT_ALIGN", "文字对齐"),
            textFn = function() return tostring(params.justifyH or "CENTER") end,
            onClick = function()
                local order = { "LEFT", "CENTER", "RIGHT" }
                local cur = tostring(params.justifyH or "CENTER"):upper()
                local nextValue = "CENTER"
                for i, value in ipairs(order) do if value == cur then nextValue = order[i % #order + 1]; break end end
                Editor:WriteField({ params = { justifyH = nextValue } }); Editor:RefreshProperties()
            end })
        add({ type = "number", label = Text("VISUAL_BOARD_INSP_TEXT_WIDTH", "文本宽度"),
            get = function() return tonumber(params.width) or "" end,
            set = function(v) Editor:WriteField({ params = { width = tonumber(v) } }) end })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_BOLD", "粗体"),
            textFn = function() return params.bold == true and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { bold = not (params.bold == true) } }); Editor:RefreshProperties() end })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_OUTLINE", "描边"),
            textFn = function() return params.outline ~= false and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { outline = not (params.outline ~= false) } }); Editor:RefreshProperties() end })
        add({ type = "toggle", label = Text("VISUAL_BOARD_INSP_SHADOW", "阴影"),
            textFn = function() return params.shadow ~= false and Text("VISUAL_BOARD_ON", "开") or Text("VISUAL_BOARD_OFF", "关") end,
            onClick = function() Editor:WriteField({ params = { shadow = not (params.shadow ~= false) } }); Editor:RefreshProperties() end })
    elseif kind == "shape" then
        local shapeKind = params.shapeKind
        add({ type = "header", text = Text("VISUAL_BOARD_TYPE_SHAPE", "形状") })
        add({ type = "segmented", label = Text("VISUAL_BOARD_INSP_SHAPE_KIND", "形状类型"),
            options = {
                { value = "rect", text = Text("VISUAL_BOARD_SHAPE_RECT", "矩形") },
                { value = "circle", text = Text("VISUAL_BOARD_SHAPE_CIRCLE", "圆形") },
                { value = "line", text = Text("VISUAL_BOARD_SHAPE_LINE", "线段") },
                { value = "arrow", text = Text("VISUAL_BOARD_SHAPE_ARROW", "箭头") },
            },
            get = function() return tostring(params.shapeKind or "rect") end,
            set = function(value)
                Editor:WriteField({ params = { shapeKind = value } })
                Editor:RefreshProperties()
            end })
        add({ type = "color", label = Text("VISUAL_BOARD_INSP_SHAPE_COLOR", "颜色"),
            get = function() return params.color or "FFFFFF" end,
            set = function(hex) Editor:WriteField({ params = { color = hex } }) end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_CIRCLE_ALPHA", "不透明度"),
            min = 0, max = 1, step = 0.05,
            get = function() return tonumber(params.alpha) or 0.85 end,
            labelFn = function(v) return string.format("%s: %d%%", Text("VISUAL_BOARD_INSP_CIRCLE_ALPHA", "不透明度"), math.floor(v * 100 + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { alpha = v } }) end })
        if shapeKind == "circle" then
            add({ type = "slider", label = Text("VISUAL_BOARD_INSP_CIRCLE_RADIUS", "半径"),
                min = 10, max = 300, step = 1,
                get = function() return tonumber(params.radius) or 60 end,
                labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_CIRCLE_RADIUS", "半径"), math.floor(v + 0.5)) end,
                set = function(v) Editor:WriteField({ params = { radius = v } }) end })
            add({ type = "cycle", label = Text("VISUAL_BOARD_INSP_CIRCLE_STYLE", "样式"),
                textFn = function() return (params.shapeStyle == "ring") and Text("VISUAL_BOARD_INSP_RING", "空心环") or Text("VISUAL_BOARD_INSP_SOLID", "实心") end,
                onClick = function()
                    local nextStyle = (params.shapeStyle == "ring") and "solid" or "ring"
                    Editor:WriteField({ params = { shapeStyle = nextStyle } }); Editor:RefreshProperties()
                end })
            if params.shapeStyle == "ring" then
                add({ type = "slider", label = Text("VISUAL_BOARD_INSP_RING_THICKNESS", "环厚度"),
                    min = 2, max = 30, step = 1,
                    get = function() return tonumber(params.ringThickness) or 6 end,
                    labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_RING_THICKNESS", "环厚度"), math.floor(v + 0.5)) end,
                    set = function(v) Editor:WriteField({ params = { ringThickness = v } }) end })
            end
        elseif shapeKind == "line" or shapeKind == "arrow" then
            add({ type = "slider", label = Text("VISUAL_BOARD_INSP_THICKNESS", "线宽"),
                min = 1, max = 30, step = 1,
                get = function() return tonumber(params.thickness) or 3 end,
                labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_THICKNESS", "线宽"), math.floor(v + 0.5)) end,
                set = function(v) Editor:WriteField({ params = { thickness = v } }) end })
            if shapeKind == "arrow" then
                add({ type = "slider", label = Text("VISUAL_BOARD_INSP_ARROWSIZE", "箭头大小"),
                    min = 8, max = 60, step = 1,
                    get = function() return tonumber(params.arrowSize) or 22 end,
                    labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_ARROWSIZE", "箭头大小"), math.floor(v + 0.5)) end,
                    set = function(v) Editor:WriteField({ params = { arrowSize = v } }) end })
            end
            add({ type = "number", label = Text("VISUAL_BOARD_INSP_END_X", "终点X"),
                get = function() return math.floor((tonumber(element.end_x) or 0) + 0.5) end,
                set = function(v) Editor:WriteField({ end_x = tonumber(v) }) end })
            add({ type = "number", label = Text("VISUAL_BOARD_INSP_END_Y", "终点Y"),
                get = function() return math.floor((tonumber(element.end_y) or 0) + 0.5) end,
                set = function(v) Editor:WriteField({ end_y = tonumber(v) }) end })
        else
            add({ type = "slider", label = Text("VISUAL_BOARD_INSP_WIDTH", "宽度"),
                min = 20, max = 600, step = 1,
                get = function() return tonumber(params.w) or 200 end,
                labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_WIDTH", "宽度"), math.floor(v + 0.5)) end,
                set = function(v) Editor:WriteField({ params = { w = v } }) end })
            add({ type = "slider", label = Text("VISUAL_BOARD_INSP_HEIGHT", "高度"),
                min = 20, max = 600, step = 1,
                get = function() return tonumber(params.h) or 120 end,
                labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_HEIGHT", "高度"), math.floor(v + 0.5)) end,
                set = function(v) Editor:WriteField({ params = { h = v } }) end })
        end
    elseif kind == "icon" then
        add({ type = "header", text = Text("VISUAL_BOARD_TYPE_ICON", "图标") })
        add({ type = "action", text = Text("VISUAL_BOARD_ICON_PICK", "换图标"),
            onClick = function(b) Editor:OpenIconPicker(b) end })
        add({ type = "number", label = Text("VISUAL_BOARD_INSP_SPELL_ID", "法术ID"),
            get = function() return tonumber(params.spellID) or "" end,
            set = function(v) Editor:WriteField({ params = { spellID = tonumber(v) } }); Editor:RefreshProperties() end })
        add({ type = "cycle", label = Text("VISUAL_BOARD_INSP_ICON_SHAPE", "图标形状"),
            textFn = function() return (params.shape == "square") and Text("VISUAL_BOARD_INSP_ICON_SQUARE", "方形") or Text("VISUAL_BOARD_INSP_ICON_CIRCLE", "圆形") end,
            onClick = function()
                local nextShape = (params.shape == "square") and "circle" or "square"
                Editor:WriteField({ params = { shape = nextShape } }); Editor:RefreshProperties()
            end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_ICON_SIZE", "图标尺寸"),
            min = 12, max = 160, step = 1,
            get = function() return tonumber(params.size) or 54 end,
            labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_ICON_SIZE", "图标尺寸"), math.floor(v + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { size = v } }) end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_ICON_BORDER", "图标描边"),
            min = 0, max = 12, step = 1,
            get = function() return tonumber(params.borderSize) or 0 end,
            labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_ICON_BORDER", "图标描边"), math.floor(v + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { borderSize = v } }) end })
        add({ type = "color", label = Text("VISUAL_BOARD_INSP_ICON_BORDER_COLOR", "描边色"),
            get = function() return params.borderColor or "000000" end,
            set = function(hex) Editor:WriteField({ params = { borderColor = hex } }) end })
    elseif kind == "marker" then
        add({ type = "header", text = Text("VISUAL_BOARD_TYPE_MARKER", "团队标记") })
        add({ type = "cycle", label = Text("VISUAL_BOARD_INSP_MARKER", "标记"),
            textFn = function() return MARKER_NAMES[tonumber(params.markerIndex) or 1] or tostring(params.markerIndex) end,
            onClick = function()
                local nextIndex = (tonumber(params.markerIndex) or 1) % 8 + 1
                Editor:WriteField({ params = { markerIndex = nextIndex } }); Editor:RefreshProperties()
            end })
        add({ type = "slider", label = Text("VISUAL_BOARD_INSP_MARKER_SIZE", "尺寸"),
            min = 16, max = 120, step = 1,
            get = function() return tonumber(params.size) or 54 end,
            labelFn = function(v) return string.format("%s: %d", Text("VISUAL_BOARD_INSP_MARKER_SIZE", "尺寸"), math.floor(v + 0.5)) end,
            set = function(v) Editor:WriteField({ params = { size = v } }) end })
    end

    -- 公共变换分区（所有型）：旋转 + 缩放 + 删除。
    add({ type = "header", text = Text("VISUAL_BOARD_INSP_TRANSFORM", "变换") })
    add({ type = "number", label = Text("VISUAL_BOARD_ROTATION", "旋转"),
        get = function() return math.floor((tonumber(element.rotation) or 0) + 0.5) end,
        set = function(v) Editor:WriteField({ rotation = tonumber(v) or 0 }) end })
    add({ type = "slider", label = Text("VISUAL_BOARD_SCALE", "缩放"),
        min = 0.2, max = 4, step = 0.05,
        get = function() return tonumber(element.scale) or 1 end,
        labelFn = function(v) return string.format("%s: %.2f", Text("VISUAL_BOARD_SCALE", "缩放"), v) end,
        set = function(v) Editor:WriteField({ scale = v }) end })
    add({ type = "action", text = Text("VISUAL_BOARD_DELETE_SELECTED", "删除"),
        onClick = function() Editor:DeleteSelectedElements() end })

    return defs
end

-- 文本位置枚举 → 显示文案。
function Editor:PositionText(position)
    if position == "bottom" then return Text("VISUAL_BOARD_POS_BOTTOM", "下") end
    if position == "left" then return Text("VISUAL_BOARD_POS_LEFT", "左") end
    if position == "right" then return Text("VISUAL_BOARD_POS_RIGHT", "右") end
    return Text("VISUAL_BOARD_POS_TOP", "上")
end

function Editor:RefreshProperties()
    local panel = self.panel
    if not panel then
        return
    end

    -- 多选/组：显示组属性区，隐藏单元素属性区。
    local selectedCount = CountSelected()
    local isGroupOrMulti = selectedGroupID ~= nil or selectedCount >= 2
    if panel.groupPropertyFrame then
        panel.groupPropertyFrame:SetShown(isGroupOrMulti)
    end
    if isGroupOrMulti then
        if panel.propertyFrame then
            panel.propertyFrame:Hide()
        end
        self:RefreshGroupProperties()
        return
    end

    local element = self:GetSelectedElement()
    local hasElement = type(element) == "table"
    if panel.propertyFrame then
        panel.propertyFrame:SetShown(hasElement)
    end
    if not hasElement then
        return
    end

    -- 单元素：构建该型字段描述（§7 person 三子件）→ 渲染到 inspector 滚动区。
    local defs = self:BuildElementInspectorDefs(element)
    RenderInspector(panel, defs)
end

-- 组/多选属性面板：名称、显示/隐藏、锁定、整体位置（仅当 selectedGroupID 有组时可改名）。
function Editor:RefreshGroupProperties()
    local panel = self.panel
    if not panel then
        return
    end
    local group = selectedGroupID and T.VisualBoardData and T.VisualBoardData:GetGroup(selectedBoardID, selectedGroupID) or nil
    local hasGroup = type(group) == "table"
    if panel.groupNameEdit then
        panel.groupNameEdit:SetShown(hasGroup)
        if hasGroup and not panel.groupNameEdit:HasFocus() then
            panel.groupNameEdit:SetText(tostring(group.name or ""))
        end
    end
    if panel.groupTitle then
        if hasGroup then
            panel.groupTitle:SetText(Text("VISUAL_BOARD_GROUP_TITLE", "组属性"))
        else
            panel.groupTitle:SetText(string.format(Text("VISUAL_BOARD_MULTI_TITLE", "已选 %d 个"), CountSelected()))
        end
    end
    if panel.groupHideButton then
        local hidden = hasGroup and group.hidden == true
        panel.groupHideButton:SetText(hidden and Text("VISUAL_BOARD_SHOW", "显示") or Text("VISUAL_BOARD_HIDE", "隐藏"))
        panel.groupHideButton:SetShown(hasGroup)
    end
    if panel.groupLockButton then
        local locked = hasGroup and group.locked == true
        panel.groupLockButton:SetText(locked and Text("VISUAL_BOARD_UNLOCK", "解锁") or Text("VISUAL_BOARD_LOCK", "锁定"))
        panel.groupLockButton:SetShown(hasGroup)
    end
    if panel.ungroupButton then
        panel.ungroupButton:SetShown(hasGroup)
    end
    if panel.groupButton then
        panel.groupButton:SetShown(not hasGroup and CountSelected() >= 2)
    end
    -- 批量编辑仅对真正的组可用（§9.2）。
    if panel.groupBatchButton then
        panel.groupBatchButton:SetShown(hasGroup)
    end
    local showMultiTools = selectedCount >= 2
    for _, button in ipairs(panel.multiToolButtons or {}) do
        button:SetShown(showMultiTools)
    end
end

local function ResolveMapText(items, encounterID, fallback)
    local text = T.ResolveSelectorText and T.ResolveSelectorText(items, tonumber(encounterID), nil) or nil
    if text and text ~= "-" then
        return text
    end
    return fallback or "-"
end

function Editor:RefreshMapControls(board)
    local panel = self.panel
    if not panel then
        return
    end
    local hasBoard = type(board) == "table"
    local maps = T.VisualBoardBackgrounds and T.VisualBoardBackgrounds.GetAllMaps and T.VisualBoardBackgrounds:GetAllMaps() or {}
    local selector = panel.mapSelector
    if selector then
        selector:SetItems(maps)
        selector.onSelect = function(value)
            if selectedBoardID and T.VisualBoardData and T.VisualBoardData.SetBackgroundEncounter then
                local bossKeyText
                for _, item in ipairs(maps or {}) do
                    if tonumber(item.value or item.encounterID) == tonumber(value) then
                        bossKeyText = item.bossKeyText
                        break
                    end
                end
                T.VisualBoardData:SetBackgroundEncounter(selectedBoardID, value, bossKeyText)
                Editor:RefreshAll()
            end
        end
        selector:SetLabel(L["Boss"] or "Boss")
        selector:SetSelectorEnabled(hasBoard and #maps > 0)
    end

    if not hasBoard then
        if selector then
            selector:SetSelectedValue(nil, Text("VISUAL_BOARD_MAP_EMPTY", "未选择"))
        end
        return
    end

    local bg = type(board.bg) == "table" and board.bg or {}
    local name = tostring(bg.name or Text("VISUAL_BOARD_MAP_GRID", "深色网格"))
    if selector then
        selector:SetSelectedValue(tonumber(board.encounterID), ResolveMapText(maps, board.encounterID, name))
    end
end

function Editor:DeleteSelectedElements()
    if not (selectedBoardID and T.VisualBoardData and T.VisualBoardData.DeleteElement) then
        return false
    end
    local ids = self:GetSelectedList()
    if #ids == 0 then
        return false
    end
    for _, id in ipairs(ids) do
        T.VisualBoardData:DeleteElement(selectedBoardID, id)
    end
    self:ClearSelectionState()
    self:RefreshAll()
    return true
end

function Editor:Undo()
    if T.VisualBoardData and T.VisualBoardData.Undo and T.VisualBoardData:Undo() then
        self:ClearSelectionState()
        self:RefreshAll()
        return true
    end
    return false
end

function Editor:Redo()
    if T.VisualBoardData and T.VisualBoardData.Redo and T.VisualBoardData:Redo() then
        self:ClearSelectionState()
        self:RefreshAll()
        return true
    end
    return false
end

function Editor:CopyToClipboard()
    local ids = self:GetSelectedList()
    if #ids == 0 or not (selectedBoardID and T.VisualBoardData) then
        elementClipboard = nil
        return false
    end
    local copies = {}
    for _, id in ipairs(ids) do
        local element = T.VisualBoardData:GetElement(selectedBoardID, id)
        if type(element) == "table" then
            copies[#copies + 1] = DeepCopy(element)
        end
    end
    elementClipboard = copies
    return #copies > 0
end

function Editor:PasteFromClipboard()
    if not (selectedBoardID and type(elementClipboard) == "table" and T.VisualBoardData and T.VisualBoardData.InsertElementCopy) then
        return false
    end
    local newIDs = {}
    for _, snapshot in ipairs(elementClipboard) do
        local element = T.VisualBoardData:InsertElementCopy(selectedBoardID, snapshot, 16, 16)
        if element then
            newIDs[element.id] = true
        end
    end
    if next(newIDs) then
        selectedIDs = newIDs
        selectedGroupID = nil
        self:RefreshAll()
        return true
    end
    self:RefreshAll()
    return false
end

function Editor:CutToClipboard()
    if not self:CopyToClipboard() then
        return false
    end
    self:DeleteSelectedElements()
    return true
end

function Editor:DuplicateSelectedElements()
    if not (selectedBoardID and T.VisualBoardData and T.VisualBoardData.DuplicateElement) then
        return false
    end
    local ids = self:GetSelectedList()
    if #ids == 0 then
        return false
    end
    local newIDs = {}
    for _, id in ipairs(ids) do
        local element = T.VisualBoardData:DuplicateElement(selectedBoardID, id, 16, 16)
        if element then
            newIDs[element.id] = true
        end
    end
    if next(newIDs) then
        selectedIDs = newIDs
        selectedGroupID = nil
    end
    self:RefreshAll()
    return next(newIDs) ~= nil
end

function Editor:MoveSelectedZ(direction)
    local soleID = self:GetSoleSelectedID()
    if selectedBoardID and soleID and T.VisualBoardData and T.VisualBoardData.MoveElementZ then
        T.VisualBoardData:MoveElementZ(selectedBoardID, soleID, direction)
        self:RefreshAll()
    end
end

local function GetSelectionBoxes()
    local board = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetBoard(selectedBoardID) or nil
    if type(board) ~= "table" then
        return nil
    end
    local boxes = {}
    for _, id in ipairs(Editor:GetSelectedList()) do
        local element = T.VisualBoardData:GetElement(selectedBoardID, id)
        if type(element) == "table" then
            local resolved = T.VisualBoardData:ResolveElementAtSlide(element, currentSlideIndex, board)
            local w, h = T.VisualBoardData:GetElementBox(element)
            local x = tonumber(resolved.x) or tonumber(element.x) or 0
            local y = tonumber(resolved.y) or tonumber(element.y) or 0
            boxes[#boxes + 1] = {
                id = id, element = element, x = x, y = y,
                w = tonumber(w) or 0, h = tonumber(h) or 0,
                left = x - (tonumber(w) or 0) / 2,
                right = x + (tonumber(w) or 0) / 2,
                top = y - (tonumber(h) or 0) / 2,
                bottom = y + (tonumber(h) or 0) / 2,
            }
        end
    end
    return board, boxes
end

local function SelectionBounds(boxes)
    local bounds = nil
    for _, b in ipairs(boxes or {}) do
        if not bounds then
            bounds = { left = b.left, right = b.right, top = b.top, bottom = b.bottom }
        else
            bounds.left = math.min(bounds.left, b.left)
            bounds.right = math.max(bounds.right, b.right)
            bounds.top = math.min(bounds.top, b.top)
            bounds.bottom = math.max(bounds.bottom, b.bottom)
        end
    end
    if bounds then
        bounds.cx = (bounds.left + bounds.right) / 2
        bounds.cy = (bounds.top + bounds.bottom) / 2
    end
    return bounds
end

function Editor:MoveElementToFramePosition(id, x, y)
    local element, board = T.VisualBoardData:GetElement(selectedBoardID, id)
    if type(element) ~= "table" or type(board) ~= "table" then
        return
    end
    if currentSlideIndex >= 2 then
        T.VisualBoardData:SetSlideOverride(selectedBoardID, currentSlideIndex, id, "x", x)
        T.VisualBoardData:SetSlideOverride(selectedBoardID, currentSlideIndex, id, "y", y)
    else
        T.VisualBoardData:MoveElements(selectedBoardID, { id }, x - (tonumber(element.x) or 0), y - (tonumber(element.y) or 0), false)
    end
end

function Editor:AlignSelected(mode)
    local _, boxes = GetSelectionBoxes()
    local bounds = SelectionBounds(boxes)
    if not bounds or #(boxes or {}) < 2 then
        return
    end
    for _, b in ipairs(boxes) do
        local x, y = b.x, b.y
        if mode == "left" then x = bounds.left + b.w / 2
        elseif mode == "hcenter" then x = bounds.cx
        elseif mode == "right" then x = bounds.right - b.w / 2
        elseif mode == "top" then y = bounds.top + b.h / 2
        elseif mode == "vcenter" then y = bounds.cy
        elseif mode == "bottom" then y = bounds.bottom - b.h / 2 end
        self:MoveElementToFramePosition(b.id, x, y)
    end
    self:RefreshAll()
end

function Editor:DistributeSelected(axis)
    local _, boxes = GetSelectionBoxes()
    if not boxes or #boxes < 3 then
        return
    end
    local horizontal = axis == "h"
    table.sort(boxes, function(a, b) return horizontal and a.x < b.x or a.y < b.y end)
    local first = boxes[1]
    local last = boxes[#boxes]
    local span = (horizontal and (last.x - first.x) or (last.y - first.y)) / (#boxes - 1)
    for index, b in ipairs(boxes) do
        local value = (horizontal and first.x or first.y) + span * (index - 1)
        self:MoveElementToFramePosition(b.id, horizontal and value or b.x, horizontal and b.y or value)
    end
    self:RefreshAll()
end

function Editor:UnifySelectedSize(axis)
    local _, boxes = GetSelectionBoxes()
    if not boxes or #boxes < 2 then
        return
    end
    local ref = boxes[1]
    for index = 2, #boxes do
        local element = boxes[index].element
        local params = element.params or {}
        if element.type == "shape" then
            if params.shapeKind == "rect" then
                local patch = {}
                if axis == "w" or axis == "both" then patch.w = ref.w end
                if axis == "h" or axis == "both" then patch.h = ref.h end
                T.VisualBoardData:UpdateElement(selectedBoardID, element.id, { params = patch })
            elseif params.shapeKind == "circle" then
                local size = axis == "h" and ref.h or ref.w
                T.VisualBoardData:UpdateElement(selectedBoardID, element.id, { params = { radius = math.max(1, size / 2) } })
            end
        elseif element.type == "icon" or element.type == "marker" then
            local size = math.max(1, axis == "h" and ref.h or ref.w)
            T.VisualBoardData:UpdateElement(selectedBoardID, element.id, { params = { size = size } })
        elseif element.type == "person" then
            local size = math.max(1, axis == "h" and ref.h or ref.w)
            T.VisualBoardData:UpdateElement(selectedBoardID, element.id, { params = { icon = { size = size } } })
        elseif element.type == "text" then
            if axis == "w" or axis == "both" then
                T.VisualBoardData:UpdateElement(selectedBoardID, element.id, { params = { width = ref.w } })
            end
        end
    end
    self:RefreshAll()
end

-- ===== 组命令 =====
function Editor:GroupSelected()
    if not (selectedBoardID and T.VisualBoardData and T.VisualBoardData.CreateGroup) then
        return false
    end
    local ids = self:GetSelectedList()
    if #ids < 2 then
        return false
    end
    local groupID = T.VisualBoardData:CreateGroup(selectedBoardID, ids)
    if groupID then
        self:SelectGroup(groupID)
        self:RefreshAll()
        return true
    end
    return false
end

function Editor:UngroupSelected()
    if not (selectedBoardID and selectedGroupID and T.VisualBoardData and T.VisualBoardData.Ungroup) then
        return false
    end
    if T.VisualBoardData:Ungroup(selectedBoardID, selectedGroupID) then
        selectedGroupID = nil
        self:RefreshAll()
        return true
    end
    return false
end

function Editor:HasTextFocus()
    local panel = self.panel
    if not panel then
        return false
    end
    local edits = {
        panel.nameEdit, panel.inlineEditBox, panel.groupNameEdit,
    }
    for _, edit in ipairs(edits) do
        if edit and edit.HasFocus and edit:HasFocus() then
            return true
        end
    end
    -- inspector 动态生成的编辑框（每次 RenderInspector 收集到 panel.inspectorEdits）。
    for _, edit in ipairs(panel.inspectorEdits or {}) do
        if edit and edit.HasFocus and edit:HasFocus() then
            return true
        end
    end
    return false
end

function Editor:IsSpacePanActive()
    if self:HasTextFocus() then
        spaceHeld = false
        return false
    end
    if IsKeyDown then
        local down = IsKeyDown("SPACE") and true or false
        if not down then
            spaceHeld = false
        end
        return down
    end
    return spaceHeld
end

function Editor:HandleKeyDown(key)
    if self:HasTextFocus() then
        return false
    end
    if key == "SPACE" then
        spaceHeld = true
        return true
    end
    -- Mac 上 ⌘ 走 IsMetaKeyDown，Ctrl 走 IsControlKeyDown，二者都视为撤销/复制等的修饰键（沿用 STT selection_box 既有写法）。
    local ctrl = (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
    local shift = IsShiftKeyDown and IsShiftKeyDown()
    if key == "G" and ctrl and shift then
        self:UngroupSelected()
        return true
    elseif key == "G" and ctrl then
        self:GroupSelected()
        return true
    elseif key == "Z" and ctrl and not shift then
        self:Undo()
        return true
    elseif (key == "Z" and ctrl and shift) or (key == "Y" and ctrl) then
        self:Redo()
        return true
    elseif key == "DELETE" or key == "BACKSPACE" then
        self:DeleteSelectedElements()
        return true
    elseif key == "ESCAPE" then
        self:ClearSelection()
        return true
    elseif key == "D" and ctrl then
        self:DuplicateSelectedElements()
        return true
    elseif key == "C" and ctrl then
        self:CopyToClipboard()
        return true
    elseif key == "X" and ctrl then
        self:CutToClipboard()
        return true
    elseif key == "V" and ctrl then
        self:PasteFromClipboard()
        return true
    elseif key == "LEFT" or key == "RIGHT" or key == "UP" or key == "DOWN" then
        local ids = self:GetSelectedList()
        if #ids > 0 and selectedBoardID and T.VisualBoardData then
            local step = shift and 10 or 1
            local dx = (key == "LEFT" and -step) or (key == "RIGHT" and step) or 0
            local dy = (key == "UP" and -step) or (key == "DOWN" and step) or 0
            local element = T.VisualBoardData:GetElement(selectedBoardID, ids[1])
            local board = T.VisualBoardData:GetBoard(selectedBoardID)
            if type(element) == "table" and type(board) == "table" then
                local resolved = T.VisualBoardData:ResolveElementAtSlide(element, currentSlideIndex, board)
                self:DragSelection(ids[1], (tonumber(resolved.x) or element.x or 0) + dx, (tonumber(resolved.y) or element.y or 0) + dy, false)
            end
        end
        return true
    end
    return false
end

function Editor:HandleKeyUp(key)
    if key == "SPACE" then
        spaceHeld = false
    end
end

local function BindEditorKeyboard(panel)
    local hotkeys = {
        { key = "SPACE", handler = function() return Editor:HandleKeyDown("SPACE") end },
        { key = "C", ctrl = true, handler = function() return Editor:HandleKeyDown("C") end },
        { key = "X", ctrl = true, handler = function() return Editor:HandleKeyDown("X") end },
        { key = "V", ctrl = true, handler = function() return Editor:HandleKeyDown("V") end },
        { key = "D", ctrl = true, handler = function() return Editor:HandleKeyDown("D") end },
        { key = "G", ctrl = true, handler = function() return Editor:HandleKeyDown("G") end },
        { key = "G", ctrl = true, shift = true, handler = function() return Editor:HandleKeyDown("G") end },
        { key = "Z", ctrl = true, handler = function() return Editor:HandleKeyDown("Z") end },
        { key = "Z", ctrl = true, shift = true, handler = function() return Editor:HandleKeyDown("Z") end },
        { key = "Y", ctrl = true, handler = function() return Editor:HandleKeyDown("Y") end },
        { key = "DELETE", handler = function() return Editor:HandleKeyDown("DELETE") end },
        { key = "BACKSPACE", handler = function() return Editor:HandleKeyDown("BACKSPACE") end },
        { key = "ESCAPE", handler = function() return Editor:HandleKeyDown("ESCAPE") end },
        { key = "LEFT", handler = function() return Editor:HandleKeyDown("LEFT") end },
        { key = "RIGHT", handler = function() return Editor:HandleKeyDown("RIGHT") end },
        { key = "UP", handler = function() return Editor:HandleKeyDown("UP") end },
        { key = "DOWN", handler = function() return Editor:HandleKeyDown("DOWN") end },
        { key = "LEFT", shift = true, handler = function() return Editor:HandleKeyDown("LEFT") end },
        { key = "RIGHT", shift = true, handler = function() return Editor:HandleKeyDown("RIGHT") end },
        { key = "UP", shift = true, handler = function() return Editor:HandleKeyDown("UP") end },
        { key = "DOWN", shift = true, handler = function() return Editor:HandleKeyDown("DOWN") end },
    }
    if T.KeyboardCapture and T.KeyboardCapture.Bind then
        T.KeyboardCapture.Bind(panel, hotkeys)
    else
        panel:EnableKeyboard(true)
        if panel.SetPropagateKeyboardInput then
            panel:SetPropagateKeyboardInput(true)
        end
        panel:SetScript("OnKeyDown", function(owner, key)
            local consumed = Editor:HandleKeyDown(key)
            if owner and owner.SetPropagateKeyboardInput then
                owner:SetPropagateKeyboardInput(not consumed)
            end
        end)
        panel:SetScript("OnKeyUp", function(owner, key)
            Editor:HandleKeyUp(key)
            if owner and owner.SetPropagateKeyboardInput then
                owner:SetPropagateKeyboardInput(true)
            end
        end)
        return
    end
    local baseKeyUp = panel.GetScript and panel:GetScript("OnKeyUp")
    panel:SetScript("OnKeyUp", function(owner, key)
        Editor:HandleKeyUp(key)
        if baseKeyUp then
            baseKeyUp(owner, key)
        elseif owner and owner.SetPropagateKeyboardInput then
            owner:SetPropagateKeyboardInput(true)
        end
    end)
end

-- TODO（组缩放）：已去除组四角缩放手柄。组/多选整体缩放后续如需，应在组属性面板加一个
--   "整体缩放" 控件，经 T.VisualBoardData:ScaleElements(boardID, ids, factor, originX, originY)
--   单一权威写入；本期仅支持单元素缩放（见公共变换分区的 scale 滑条）。

function Editor:BeginInlineEdit(elementID)
    local panel = self.panel
    local element, board = T.VisualBoardData and T.VisualBoardData:GetElement(selectedBoardID, elementID) or nil
    if not (panel and type(element) == "table" and type(board) == "table" and element.type == "text") then
        return
    end
    selectedIDs = { [elementID] = true }
    selectedGroupID = nil
    local edit = panel.inlineEditBox
    if not edit then
        edit = T.CreateEditBox(panel.canvasFrame, { width = 180, height = 28, autoFocus = false })
        edit:SetFrameLevel(panel.canvasFrame:GetFrameLevel() + 40)
        panel.inlineEditBox = edit
    end
    -- 当前帧几何唯一经 Data:ResolveElementGeometryAtSlide；element.x/y 只是基线坐标。
    local geometry = T.VisualBoardData:ResolveElementGeometryAtSlide(element, currentSlideIndex, board)
    local px, py = panel.renderer:BoardToScreen(board, viewport, geometry.x, geometry.y)
    edit.elementID = elementID
    edit.cancelled = false
    edit:ClearAllPoints()
    edit:SetPoint("CENTER", panel.canvasFrame, "TOPLEFT", px, -py)
    edit:SetText(tostring((element.params or {}).text or ""))
    edit:Show()
    edit:SetFocus()
    edit:SetScript("OnEnterPressed", function(self)
        local value = self:GetText()
        self.committed = true
        self:ClearFocus()
        self:Hide()
        if T.VisualBoardData and self.elementID then
            T.VisualBoardData:UpdateElement(selectedBoardID, self.elementID, { params = { text = value } })
            Editor:RefreshAll()
        end
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self.cancelled = true
        self:ClearFocus()
        self:Hide()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if self.cancelled then
            self.cancelled = false
            return
        end
        if self.committed then
            self.committed = false
            return
        end
        local value = self:GetText()
        self:Hide()
        if T.VisualBoardData and self.elementID then
            T.VisualBoardData:UpdateElement(selectedBoardID, self.elementID, { params = { text = value } })
            Editor:RefreshAll()
        end
    end)
end

function Editor:HideContextMenu()
    if self.panel and self.panel.contextMenu then
        self.panel.contextMenu:Hide()
    end
end

function Editor:ShowContextMenu(elementID)
    local panel = self.panel
    if not panel then
        return
    end
    if not selectedIDs[elementID] then
        self:Select(elementID, false)
    end
    local menu = panel.contextMenu
    if not menu then
        menu = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        menu:SetSize(92, 116)
        menu:SetFrameLevel(panel:GetFrameLevel() + 80)
        T.ApplyBackdrop(menu, { alpha = 0.94, style = "tooltip" })
        local actions = {
            { Text("VISUAL_BOARD_CTX_COPY", "复制"), function() Editor:CopyToClipboard(); Editor:PasteFromClipboard() end },
            { Text("VISUAL_BOARD_CTX_DELETE", "删除"), function() Editor:DeleteSelectedElements() end },
            { Text("VISUAL_BOARD_CTX_TOP", "置顶"), function() Editor:MoveSelectedZ("top") end },
            { Text("VISUAL_BOARD_CTX_BOTTOM", "置底"), function() Editor:MoveSelectedZ("bottom") end },
        }
        menu.actionButtons = {}
        for index, item in ipairs(actions) do
            local button = T.CreateButton(menu, { width = 72, height = 22 })
            button:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8 - (index - 1) * 26)
            button:SetText(item[1])
            button:SetScript("OnClick", function()
                menu:Hide()
                item[2]()
            end)
            menu.actionButtons[index] = button
        end
        panel.contextMenu = menu
    end
    local x, y = GetCursorPosition()
    local scale = panel:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    menu:Show()
end

-- person/icon 属性面板"换图标"入口：打开专精图标选择器，选中后写对应 texture（不建新元素）。
-- texture/atlas 互斥由 Data:_ApplyElementFields 处理（写 texture 自动清 atlas）。
function Editor:OpenIconPicker(anchor)
    local soleID = self:GetSoleSelectedID()
    local element = self:GetSelectedElement()
    if not (selectedBoardID and soleID and T.VisualBoardData and T.VisualBoardIconPicker and type(element) == "table" and (element.type == "person" or element.type == "icon")) then
        return
    end
    T.VisualBoardIconPicker:Open(anchor, function(item)
        if type(item) ~= "table" or item.icon == nil then
            return
        end
        if element.type == "person" then
            T.VisualBoardData:UpdateElement(selectedBoardID, soleID, { params = { icon = { texture = item.icon } } })
        else
            T.VisualBoardData:UpdateElement(selectedBoardID, soleID, { params = { texture = item.icon } })
        end
        Editor:RefreshProperties()
        Editor:RenderEdit()
    end)
end

-- ===== 无边画布交互（§8.2）：滚轮缩放（光标锚点）+ 中键/空格拖拽平移 =====
-- 全局缩放/平移会话态写回 viewport，并持久化 STT_VisualBoardsDB._viewport[boardID]。

-- 光标全局缩放坐标 → canvasFrame 局部屏幕坐标（TOPLEFT 体系：右正、下正）。
-- 入参 gx/gy 为 GetScaledCursorPosition() 体系（已除 effective scale）；nil 时自取当前光标。
local function CanvasLocalFromCursor(panel, gx, gy)
    local frame = panel and panel.canvasFrame
    if not frame then
        return 0, 0
    end
    if gx == nil or gy == nil then
        local cx, cy = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        if scale <= 0 then scale = 1 end
        gx = cx / scale
        gy = cy / scale
    end
    local left = frame:GetLeft() or 0
    local top = frame:GetTop() or 0
    return gx - left, top - gy
end

-- 滚轮缩放，以光标为锚点：保持光标下 board 点在缩放前后屏幕位置不动 → 反推 panX/panY。
function Editor:ZoomAtCursor(delta)
    local panel = self.panel
    local board = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetBoard(selectedBoardID) or nil
    if not (panel and panel.renderer and board) then
        return
    end
    local localX, localY = CanvasLocalFromCursor(panel)
    -- 缩放前：光标下的 board 点。
    local bx, by = panel.renderer:ScreenToBoard(board, viewport, localX, localY)
    local oldZoom = tonumber(viewport.zoom) or 1
    local step = delta > 0 and 1.1 or (1 / 1.1)
    local newZoom = math.max(0.2, math.min(4, oldZoom * step))
    viewport.zoom = newZoom
    -- 缩放后让同一 board 点回到光标处：panX = localX - bx*zoom，panY 同理。
    viewport.panX = localX - bx * newZoom
    viewport.panY = localY - by * newZoom
    SaveViewport()
    self:RenderEdit()
end

-- 平移：直接累加屏幕位移（dx 右正、dy 下正，与 viewport 屏幕语义一致）。
function Editor:PanViewport(dx, dy)
    viewport.panX = (tonumber(viewport.panX) or 0) + (tonumber(dx) or 0)
    viewport.panY = (tonumber(viewport.panY) or 0) + (tonumber(dy) or 0)
    SaveViewport()
    self:ScheduleRenderEdit()
end

-- 标记"下次渲染强制 fit"：清掉该板可能存在的持久化视口（否则下次切回又被旧视口挡住 fit），并置 pendingFit。
-- 不自己重渲，由调用方在合适时机渲染（RefreshAll 或 RenderEdit），避免重复渲染。
MarkPendingFit = function()
    local store = selectedBoardID and ViewportStore() or nil
    if store then
        store[selectedBoardID] = nil
    end
    pendingFit = true
end

-- 适应视图（用户入口）：标记强制 fit 后重渲，让 RenderEdit 在 host 尺寸就绪时经 FitViewport 居中装入整张 artboard。
-- 用途：用户被缩放卡住时双击空白一键回到全图。fit 计算仍唯一在 FitViewport，不另造第二套。
function Editor:ResetViewport()
    MarkPendingFit()
    self:RenderEdit()
end

-- 抽屉拖拽落地（§8.2/§6.1）：drop 坐标为 GetScaledCursorPosition() 体系 → 换算 board 逻辑坐标 → 建元素。
-- person 且有 presetData.slotName → AddPersonAt；marker → AddRaidMarker；其余 → AddElementAt（默认 fields 由 data 单一权威补全）。
function Editor:OnDropComponent(kind, presetData, dropX, dropY)
    local panel = self.panel
    if not (panel and panel.renderer and selectedBoardID and T.VisualBoardData) then
        return
    end
    local board = T.VisualBoardData:GetBoard(selectedBoardID)
    if type(board) ~= "table" then
        return
    end
    local localX, localY = CanvasLocalFromCursor(panel, dropX, dropY)
    local bx, by = panel.renderer:ScreenToBoard(board, viewport, localX, localY)
    local element
    if kind == "person" then
        local slotName = type(presetData) == "table" and presetData.slotName or ""
        element = T.VisualBoardData:AddPersonAt(selectedBoardID, slotName, bx, by)
    elseif kind == "marker" then
        element = T.VisualBoardData:AddRaidMarker(selectedBoardID, 1, bx, by)
    else
        element = T.VisualBoardData:AddElementAt(selectedBoardID, kind, bx, by)
    end
    if type(element) == "table" then
        selectedIDs = { [element.id] = true }
        selectedGroupID = nil
    end
    self:RefreshAll()
end

function Editor:RefreshDetails()
    local panel = self.panel
    if not panel then
        return
    end

    local board = selectedBoardID and T.VisualBoardData and T.VisualBoardData:GetBoard(selectedBoardID) or nil
    if not board then
        if panel.deleteButton then
            panel.deleteButton:Disable()
        end
        if panel.previewButton then
            panel.previewButton:Disable()
        end
        if panel.undoButton then
            panel.undoButton:Disable()
        end
        if panel.redoButton then
            panel.redoButton:Disable()
        end
        if panel.renderer then
            panel.renderer:Clear()
        end
        self:RefreshMapControls(nil)
        self:ClearSelectionState()
        self:RefreshProperties()
        self:RefreshLayerPanel()
        self:RefreshSlideBar()
        return
    end

    if T.VisualBoardData and T.VisualBoardData.ApplyCurrentBackground then
        T.VisualBoardData:ApplyCurrentBackground(selectedBoardID)
        board = T.VisualBoardData:GetBoard(selectedBoardID) or board
    end

    -- 当前帧 clamp（删帧/重排后可能越界）：限到 [1, slideCount]，至少 1。
    local slideCount = T.VisualBoardData and T.VisualBoardData:GetSlideCount(selectedBoardID) or 1
    if slideCount < 1 then slideCount = 1 end
    if currentSlideIndex > slideCount then currentSlideIndex = slideCount end
    if currentSlideIndex < 1 then currentSlideIndex = 1 end

    if panel.nameEdit and (not panel.nameEdit:HasFocus() or (panel.nameEdit:GetText() or "") == "") then
        panel.nameEdit:SetText(tostring(board.name or ""))
    end
    if panel.deleteButton then
        if board.builtin then
            panel.deleteButton:Disable()
        else
            panel.deleteButton:Enable()
        end
    end
    if panel.previewButton then
        panel.previewButton:Enable()
    end
    if panel.saveMetaButton then
        panel.saveMetaButton:Enable()
    end
    self:RefreshMapControls(board)
    if panel.undoButton then
        if T.VisualBoardData and T.VisualBoardData.CanUndo and T.VisualBoardData:CanUndo() and not board.builtin then
            panel.undoButton:Enable()
        else
            panel.undoButton:Disable()
        end
    end
    if panel.redoButton then
        if T.VisualBoardData and T.VisualBoardData.CanRedo and T.VisualBoardData:CanRedo() and not board.builtin then
            panel.redoButton:Enable()
        else
            panel.redoButton:Disable()
        end
    end
    if panel.renderer then
        self:RenderEdit()
    end
    self:RefreshProperties()
    self:RefreshLayerPanel()
    self:RefreshSlideBar()
end

function Editor:RefreshLayerPanel()
    if T.VisualBoardLayerPanel and T.VisualBoardLayerPanel.Refresh and self.panel and self.panel.layerPanel then
        T.VisualBoardLayerPanel:Refresh()
    end
end

function Editor:RefreshAll()
    self:RefreshList()
    self:RefreshDetails()
end

function Editor.RefreshLocalization()
    local panel = Editor.panel
    if not panel then
        return
    end
    SetFontText(panel.canvasLabel, "VISUAL_BOARD_CANVAS_PLACEHOLDER", "画布区域")
    SetFontText(panel.leftTitle, "VISUAL_BOARD_SLIDE_TITLE", "幻灯片")
    SetFontText(panel.rightTitle, "VISUAL_BOARD_PROPERTY_TITLE", "属性")
    if panel.createButton then
        panel.createButton:SetText(Text("VISUAL_BOARD_CREATE", "+ 新建"))
    end
    if panel.deleteButton then
        panel.deleteButton:SetText(Text("VISUAL_BOARD_DELETE", "删除"))
    end
    if panel.previewButton then
        panel.previewButton:SetText(Text("VISUAL_BOARD_PREVIEW", "预览"))
    end
    if panel.stopPreviewButton then
        panel.stopPreviewButton:SetText(Text("VISUAL_BOARD_PREVIEW_STOP", "停止预览"))
    end
    Editor:RefreshLockButton()
    if panel.saveMetaButton then
        panel.saveMetaButton:SetText(Text("VISUAL_BOARD_SAVE_META", "保存"))
    end
    if panel.undoButton then
        panel.undoButton:SetText(Text("VISUAL_BOARD_UNDO", "撤销"))
    end
    if panel.redoButton then
        panel.redoButton:SetText(Text("VISUAL_BOARD_REDO", "重做"))
    end
    if panel.templateButton then
        panel.templateButton:SetText(Text("VISUAL_BOARD_TEMPLATE", "生成模板"))
    end
    if panel.exportBossButton then
        panel.exportBossButton:SetText(Text("VISUAL_BOARD_BOSS_EXPORT", "导出Boss"))
    end
    if panel.importBossButton then
        panel.importBossButton:SetText(Text("VISUAL_BOARD_BOSS_IMPORT", "导入Boss"))
    end
    -- 单元素属性区为动态行式 inspector：所有 label/按钮文案在 RenderInspector 时经 Text() 取本地化，
    -- RefreshAll → RefreshProperties → RenderInspector 会重建，无需在此静态刷新。
    if panel.groupButton then
        panel.groupButton:SetText(Text("VISUAL_BOARD_GROUP", "成组"))
    end
    if panel.ungroupButton then
        panel.ungroupButton:SetText(Text("VISUAL_BOARD_UNGROUP", "解组"))
    end
    if panel.alignLeftButton then panel.alignLeftButton:SetText(Text("VISUAL_BOARD_ALIGN_LEFT", "左齐")) end
    if panel.alignHCenterButton then panel.alignHCenterButton:SetText(Text("VISUAL_BOARD_ALIGN_HCENTER", "横中")) end
    if panel.alignRightButton then panel.alignRightButton:SetText(Text("VISUAL_BOARD_ALIGN_RIGHT", "右齐")) end
    if panel.alignTopButton then panel.alignTopButton:SetText(Text("VISUAL_BOARD_ALIGN_TOP", "上齐")) end
    if panel.alignVCenterButton then panel.alignVCenterButton:SetText(Text("VISUAL_BOARD_ALIGN_VCENTER", "纵中")) end
    if panel.alignBottomButton then panel.alignBottomButton:SetText(Text("VISUAL_BOARD_ALIGN_BOTTOM", "下齐")) end
    if panel.distributeHButton then panel.distributeHButton:SetText(Text("VISUAL_BOARD_DISTRIBUTE_H", "横分布")) end
    if panel.distributeVButton then panel.distributeVButton:SetText(Text("VISUAL_BOARD_DISTRIBUTE_V", "纵分布")) end
    if panel.sameWidthButton then panel.sameWidthButton:SetText(Text("VISUAL_BOARD_SAME_WIDTH", "同宽")) end
    if panel.sameHeightButton then panel.sameHeightButton:SetText(Text("VISUAL_BOARD_SAME_HEIGHT", "同高")) end
    if panel.groupBatchButton then
        panel.groupBatchButton:SetText(Text("VISUAL_BOARD_BATCH_EDIT", "批量编辑"))
    end
    if panel.RefreshDrawerTexts then
        panel.RefreshDrawerTexts()
    end
    if panel.SetLayerExpanded then
        panel.SetLayerExpanded(panel.layerExpanded)
    end
    Editor:RefreshAll()
end

-- “预览”按钮（§6.1）：调 Overlay:Play 看图1→图2 morph 过渡（morph 数学单一权威在 overlay，editor 不本地重算）。
-- 编辑器内预览传 opts.info（当前方案 PreprocessText 产物），person 默认图标解析与运行时一致；不进战斗、不解析真实 id、不判本机。
function Editor:StartPreview()
    if not (selectedBoardID and T.VisualBoardOverlay and T.VisualBoardOverlay.Play) then
        return
    end
    self:HideContextMenu()
    -- 一次只显一个：Play 当前板前先清掉所有旧预览 HUD，避免多块板叠加（如 board-28/board-29 同时悬浮）。
    if T.VisualBoardOverlay.StopAll then
        T.VisualBoardOverlay:StopAll()
    end
    T.VisualBoardOverlay:Play(selectedBoardID, 0, { info = GetActiveInfo(), source = "editorPreview" })
end

-- 「停止预览」按钮（§6.1）：隐藏所有活跃预览 HUD（编辑器预览播完冻结末帧，需手动停止入口）。
function Editor:StopPreview()
    if T.VisualBoardOverlay and T.VisualBoardOverlay.StopAll then
        T.VisualBoardOverlay:StopAll()
    end
end

-- 锁按钮文案随 Overlay:IsLocked 切换：锁定态显示“解锁锚点”（点击即解锁），反之显示“锁定锚点”。
function Editor:RefreshLockButton()
    local panel = self.panel
    if not (panel and panel.lockButton) then
        return
    end
    local locked = not (T.VisualBoardOverlay and T.VisualBoardOverlay.IsLocked) or T.VisualBoardOverlay:IsLocked()
    panel.lockButton:SetText(locked and Text("OPT_ANCHOR_UNLOCK", "解锁锚点") or Text("OPT_ANCHOR_LOCK", "锁定锚点"))
end

function Editor:ToggleOverlayLock()
    if not (T.VisualBoardOverlay and T.VisualBoardOverlay.SetLocked) then
        return
    end
    -- 传 selectedBoardID：解锁时若尚未预览过，Overlay 会按此 board 先建壳，避免解锁空转（拖不动）。
    T.VisualBoardOverlay:SetLocked(not T.VisualBoardOverlay:IsLocked(), selectedBoardID)
    self:RefreshLockButton()
end

function Editor:SaveMeta()
    local panel = self.panel
    if not (panel and selectedBoardID and T.VisualBoardData and T.VisualBoardData.UpdateBoardMeta) then
        return
    end
    -- 时长由 slide 模型（holdTime/morphFromPrev）决定，board 无 duration 字段；此处只存名称。
    T.VisualBoardData:UpdateBoardMeta(selectedBoardID, {
        name = panel.nameEdit and panel.nameEdit:GetText() or nil,
    })
    self:RefreshAll()
end

function Editor.CreateInterface(parent)
    if Editor.panel then
        Editor.panel:SetParent(parent)
        Editor.panel:SetAllPoints(parent)
        Editor.panel:Show()
        Editor:RefreshAll()
        return Editor.panel
    end

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    BindEditorKeyboard(panel)
    -- spaceHeld 生命周期兜底（#4）：松开空格的 OnKeyUp 若因切焦点/弹窗/失焦丢失，spaceHeld 会卡在 true，
    -- 导致之后左键拖背景被误判为“空格+左键”平移。面板隐藏/显示时强制复位，斩断卡死态。
    panel:HookScript("OnHide", function()
        spaceHeld = false
    end)
    panel:HookScript("OnShow", function()
        spaceHeld = false
    end)
    Editor.panel = panel

    -- 设计系统缩放量（编辑器特有布局值走 Style.Scale；标准控件量走 Style.Scaled）。
    local INSET = T.Style.Scale(12)
    local GAP = T.Style.Scale(8)
    local PAD = T.Style.Scale(12)
    local BTN_H = T.Style.Scaled("BUTTON_HEIGHT")
    local TOP_INSET = T.Style.Scale(4)
    -- chrome（顶栏/工具栏/底栏）压到最小必要高度，把竖直空间让给画布。
    local TOPBAR_H = BTN_H + T.Style.Scale(4)
    local TOPBAR_COMPACT_H = BTN_H * 2 + GAP
    local TOPBAR_COMPACT_W = T.Style.Scale(1180)
    local BOTTOMBAR_H = BTN_H + T.Style.Scale(20)
    local DRAWER_HEADER_H = BTN_H + T.Style.Scale(6)
    local DRAWER_BG = { 0.10, 0.045, 0.065, 0.97 }
    local DRAWER_BORDER = { 0.46, 0.38, 0.42, 0.82 }
    local DRAWER_ANIM_DUR = 0.16
    local DRAWER_ANIM_OFFSET = T.Style.Scale(28)
    -- 两侧栏宽度（Keynote 式三栏）：左栏=幻灯片导航（竖排每项含序号+名+停留/过渡两行时长，需较宽）；
    -- 右栏=属性 Inspector + 可折叠图层区（图层行带“批量”按钮，需较宽）。在可读前提下仍尽量窄，把竖直空间让给画布。
    local LEFT_W = T.Style.Scale(190)
    local RIGHT_W = T.Style.Scale(220)
    local HANDLE_W = T.Style.Scale(42)

    -- ===== 顶栏（§3.1）=====
    panel.topBar = CreateFrame("Frame", nil, panel)
    panel.topBar:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET, -TOP_INSET)
    panel.topBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -INSET, -TOP_INSET)
    panel.topBar:SetHeight(TOPBAR_H)

    panel.boardSelector = T.CreateSelectorButton(panel.topBar, {
        width = T.Style.Scale(170),
        height = BTN_H,
        labelWidth = T.Style.Scale(34),
        ownerFrame = panel,
    })
    panel.boardSelector:SetPoint("LEFT", panel.topBar, "LEFT", 0, 0)
    panel.boardSelector:SetFrameLevel(panel.topBar:GetFrameLevel() + 6)

    panel.createButton = T.CreateButton(panel.topBar, { width = T.Style.Scale(72), height = BTN_H })
    panel.createButton:SetPoint("LEFT", panel.boardSelector, "RIGHT", GAP, 0)
    panel.createButton:SetScript("OnClick", function()
        local board = T.VisualBoard and T.VisualBoard:CreateBoard(Text("VISUAL_BOARD_NEW_NAME", "未命名画板")) or nil
        selectedBoardID = board and board.id or selectedBoardID
        currentSlideIndex = 1
        LoadViewport(selectedBoardID)
        Editor:ClearSelectionState()
        if T.VisualBoardData and T.VisualBoardData.ClearHistory then
            T.VisualBoardData:ClearHistory()
        end
        Editor:RefreshAll()
    end)

    panel.templateButton = T.CreateButton(panel.topBar, { width = T.Style.Scale(84), height = BTN_H })
    panel.templateButton:SetPoint("LEFT", panel.createButton, "RIGHT", GAP, 0)
    panel.templateButton:SetScript("OnClick", function()
        if not (T.VisualBoard and T.VisualBoardData
            and T.VisualBoardData.ApplyTemplate_P1Flow and T.VisualBoardData.ApplyTemplate_P15Positions
            and T.VisualBoardData.ApplyTemplate_P2SoakAssign and T.VisualBoardData.ApplyTemplate_P2Front
            and T.VisualBoardData.ApplyTemplate_P2toP3 and T.VisualBoardData.ApplyTemplate_P3ClockPositions
            and T.VisualBoardData.ApplyTemplate_P31Groups and T.VisualBoardData.ApplyTemplate_P32Groups
            and T.VisualBoardData.ApplyTemplate_P33Constellation) then
            return
        end
        -- 一次生成 9 个板：P1/P1.5/P2/P3 关键站位；P2转P3、P3-1、P3-2 为双帧 morph。
        local boardP1 = T.VisualBoard:CreateBoard("P1流程图")
        if boardP1 then
            T.VisualBoardData:ApplyTemplate_P1Flow(boardP1.id)
        end
        local boardP15 = T.VisualBoard:CreateBoard("P1.5站位图")
        if boardP15 then
            T.VisualBoardData:ApplyTemplate_P15Positions(boardP15.id)
        end
        local boardP2Soak = T.VisualBoard:CreateBoard("P2分担示意图")
        if boardP2Soak then
            T.VisualBoardData:ApplyTemplate_P2SoakAssign(boardP2Soak.id)
        end
        local boardA = T.VisualBoard:CreateBoard("P2分散前三轮")
        if boardA then
            T.VisualBoardData:ApplyTemplate_P2Front(boardA.id)
        end
        local boardB = T.VisualBoard:CreateBoard("P2转P3分散圈")
        if boardB then
            T.VisualBoardData:ApplyTemplate_P2toP3(boardB.id)
        end
        local boardP3Clock = T.VisualBoard:CreateBoard("P3时钟站位法")
        if boardP3Clock then
            T.VisualBoardData:ApplyTemplate_P3ClockPositions(boardP3Clock.id)
        end
        local boardP31 = T.VisualBoard:CreateBoard("P3-1左右分组")
        if boardP31 then
            T.VisualBoardData:ApplyTemplate_P31Groups(boardP31.id)
        end
        local boardP32 = T.VisualBoard:CreateBoard("P3-2左右分组")
        if boardP32 then
            T.VisualBoardData:ApplyTemplate_P32Groups(boardP32.id)
        end
        local boardP33 = T.VisualBoard:CreateBoard("P3-3星座吸球")
        if boardP33 then
            T.VisualBoardData:ApplyTemplate_P33Constellation(boardP33.id)
        end
        selectedBoardID = (boardP1 and boardP1.id) or (boardP15 and boardP15.id) or (boardP2Soak and boardP2Soak.id) or (boardA and boardA.id) or (boardB and boardB.id) or (boardP3Clock and boardP3Clock.id) or (boardP31 and boardP31.id) or (boardP32 and boardP32.id) or (boardP33 and boardP33.id) or selectedBoardID
        currentSlideIndex = 1
        LoadViewport(selectedBoardID)
        Editor:ClearSelectionState()
        if T.VisualBoardData.ClearHistory then
            T.VisualBoardData:ClearHistory()
        end
        -- 套模板后 artboard 归一到 1600x900 → 强制 fit：回到完整图。RefreshAll 内的 RenderEdit 会消费 pendingFit。
        MarkPendingFit()
        Editor:RefreshAll()
    end)

    panel.deleteButton = T.CreateButton(panel.topBar, { width = T.Style.Scale(60), height = BTN_H })
    panel.deleteButton:SetPoint("RIGHT", panel.topBar, "RIGHT", 0, 0)
    panel.deleteButton:SetScript("OnClick", function()
        if not selectedBoardID then
            return
        end
        local ok = T.VisualBoard and T.VisualBoard:DeleteBoard(selectedBoardID)
        if ok then
            selectedBoardID = nil
            Editor:ClearSelectionState()
            Editor:RefreshAll()
        end
    end)

    panel.mapSelector = T.CreateSelectorButton(panel.topBar, {
        width = T.Style.Scale(210),
        height = BTN_H,
        labelWidth = T.Style.Scale(38),
        ownerFrame = panel,
    })
    panel.mapSelector:SetPoint("RIGHT", panel.deleteButton, "LEFT", -GAP, 0)
    panel.mapSelector:SetFrameLevel(panel.topBar:GetFrameLevel() + 6)

    panel.importBossButton = T.CreateButton(panel.topBar, { width = T.Style.Scale(78), height = BTN_H })
    panel.importBossButton:SetPoint("RIGHT", panel.mapSelector, "LEFT", -GAP, 0)
    panel.importBossButton:SetScript("OnClick", function()
        ShowBossBoardImport()
    end)

    panel.exportBossButton = T.CreateButton(panel.topBar, { width = T.Style.Scale(78), height = BTN_H })
    panel.exportBossButton:SetPoint("RIGHT", panel.importBossButton, "LEFT", -GAP, 0)
    panel.exportBossButton:SetScript("OnClick", function()
        ShowBossBoardExport()
    end)

    panel.saveMetaButton = T.CreateButton(panel.topBar, { width = T.Style.Scale(60), height = BTN_H })
    panel.saveMetaButton:SetPoint("RIGHT", panel.exportBossButton, "LEFT", -GAP, 0)
    panel.saveMetaButton:SetScript("OnClick", function()
        Editor:SaveMeta()
    end)

    panel.nameEdit = T.CreateEditBox(panel.topBar, { width = T.Style.Scale(120), height = BTN_H, autoFocus = false })
    panel.nameEdit:SetPoint("LEFT", panel.templateButton, "RIGHT", GAP, 0)
    panel.nameEdit:SetPoint("RIGHT", panel.saveMetaButton, "LEFT", -GAP, 0)
    panel.nameEdit:SetScript("OnEnterPressed", function()
        Editor:SaveMeta()
        panel.nameEdit:ClearFocus()
    end)

    function panel.LayoutTopBar()
        local compact = (panel.topBar:GetWidth() or 0) > 0 and (panel.topBar:GetWidth() or 0) < TOPBAR_COMPACT_W
        panel.topBar:SetHeight(compact and TOPBAR_COMPACT_H or TOPBAR_H)

        panel.boardSelector:ClearAllPoints()
        panel.createButton:ClearAllPoints()
        panel.templateButton:ClearAllPoints()
        panel.nameEdit:ClearAllPoints()
        panel.saveMetaButton:ClearAllPoints()
        panel.exportBossButton:ClearAllPoints()
        panel.importBossButton:ClearAllPoints()
        panel.mapSelector:ClearAllPoints()
        panel.deleteButton:ClearAllPoints()

        if compact then
            panel.boardSelector:SetPoint("TOPLEFT", panel.topBar, "TOPLEFT", 0, 0)
            panel.createButton:SetPoint("LEFT", panel.boardSelector, "RIGHT", GAP, 0)
            panel.templateButton:SetPoint("LEFT", panel.createButton, "RIGHT", GAP, 0)

            panel.deleteButton:SetPoint("TOPRIGHT", panel.topBar, "TOPRIGHT", 0, 0)
            panel.mapSelector:SetPoint("RIGHT", panel.deleteButton, "LEFT", -GAP, 0)
            panel.importBossButton:SetPoint("RIGHT", panel.mapSelector, "LEFT", -GAP, 0)
            panel.exportBossButton:SetPoint("RIGHT", panel.importBossButton, "LEFT", -GAP, 0)

            panel.saveMetaButton:SetPoint("BOTTOMRIGHT", panel.topBar, "BOTTOMRIGHT", 0, 0)
            panel.nameEdit:SetPoint("BOTTOMLEFT", panel.topBar, "BOTTOMLEFT", 0, 0)
            panel.nameEdit:SetPoint("BOTTOMRIGHT", panel.saveMetaButton, "BOTTOMLEFT", -GAP, 0)
        else
            panel.boardSelector:SetPoint("LEFT", panel.topBar, "LEFT", 0, 0)
            panel.createButton:SetPoint("LEFT", panel.boardSelector, "RIGHT", GAP, 0)
            panel.templateButton:SetPoint("LEFT", panel.createButton, "RIGHT", GAP, 0)

            panel.deleteButton:SetPoint("RIGHT", panel.topBar, "RIGHT", 0, 0)
            panel.mapSelector:SetPoint("RIGHT", panel.deleteButton, "LEFT", -GAP, 0)
            panel.importBossButton:SetPoint("RIGHT", panel.mapSelector, "LEFT", -GAP, 0)
            panel.exportBossButton:SetPoint("RIGHT", panel.importBossButton, "LEFT", -GAP, 0)
            panel.saveMetaButton:SetPoint("RIGHT", panel.exportBossButton, "LEFT", -GAP, 0)
            panel.nameEdit:SetPoint("LEFT", panel.templateButton, "RIGHT", GAP, 0)
            panel.nameEdit:SetPoint("RIGHT", panel.saveMetaButton, "LEFT", -GAP, 0)
        end
    end

    -- ===== 左栏：幻灯片导航（Keynote 式，本工具最大亮点）=====
    -- 竖排列出 board.slides（序号 + 帧名 + 停留/过渡时长），点击切当前编辑帧（高亮当前），底部“+新增幻灯片”，支持删除/拖拽重排。
    panel.leftCol = CreateFrame("Frame", nil, panel)
    panel.leftCol:SetPoint("TOPLEFT", panel.topBar, "BOTTOMLEFT", 0, -GAP)
    panel.leftCol:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", INSET, INSET)
    panel.leftCol:SetWidth(LEFT_W)
    panel.leftCol:EnableMouse(true)
    T.ApplyBackdrop(panel.leftCol, {
        bgColor = DRAWER_BG,
        borderColor = DRAWER_BORDER,
        style = "chat",
    })

    panel.leftTitle = T.CreateGroupTitle(panel.leftCol, {
        text = Text("VISUAL_BOARD_SLIDE_TITLE", "幻灯片"),
        point = { "LEFT", panel.leftCol, "TOPLEFT", PAD, -(PAD + BTN_H / 2) },
        fontSize = T.Style.Scaled("MODULE_TITLE_FONT_SIZE"),
        color = T.Style.Color.KYRIAN_GOLD,
    })

    panel.leftCollapseButton = T.CreateButton(panel.leftCol, { width = HANDLE_W, height = BTN_H })
    panel.leftCollapseButton:SetPoint("TOPRIGHT", panel.leftCol, "TOPRIGHT", -PAD, -PAD)
    panel.leftCollapseButton:SetScript("OnClick", function()
        SetLeftPanelCollapsed(not IsLeftPanelCollapsed())
        if panel.ApplyResponsiveLayout then
            panel.ApplyResponsiveLayout(true)
        end
    end)

    -- 幻灯片导航（§4.4 slide_bar 竖排版）：挂左栏标题下方铺到栏底。SetCallbacks 注入帧选择/刷新链。
    panel.slideHostFrame = CreateFrame("Frame", nil, panel.leftCol)
    panel.slideHostFrame:SetPoint("TOPLEFT", panel.leftCol, "TOPLEFT", PAD, -(PAD + DRAWER_HEADER_H))
    panel.slideHostFrame:SetPoint("BOTTOMRIGHT", panel.leftCol, "BOTTOMRIGHT", -PAD, PAD)
    if T.VisualBoardSlideBar and T.VisualBoardSlideBar.Create then
        panel.slideBar = T.VisualBoardSlideBar:Create(panel.slideHostFrame)
        panel.slideBar:ClearAllPoints()
        panel.slideBar:SetAllPoints(panel.slideHostFrame)
        T.VisualBoardSlideBar:SetCallbacks({
            GetBoardID = function() return selectedBoardID end,
            GetCurrentSlideIndex = function() return currentSlideIndex end,
            SetCurrentSlideIndex = function(index)
                currentSlideIndex = tonumber(index) or 1
                -- 纯点帧选中（绕过 OnChanged）：切当前编辑帧后必须立刻把画布渲染到新帧，
                -- 否则画布停在旧帧要等下次画布交互才补渲。复用既有刷新三件套（同 OnSelectionChanged，
                -- 不走 ClearSelectionState/OnChanged，点帧不应清掉元素选中）：
                -- 属性面板按新帧重解当前选中元素、图层面板按新帧重列元素、画布重渲到新帧。
                Editor:RefreshProperties()
                Editor:RefreshLayerPanel()
                Editor:RenderEdit()
            end,
            -- 帧增删/排序/重命名/选帧后统一刷新：clamp 当前帧 + 重渲 + 刷新各面板（经 RefreshDetails）。
            OnChanged = function()
                Editor:ClearSelectionState()
                Editor:RefreshDetails()
            end,
        })
    end

    -- ===== 右栏：属性（§3.3）=====
    panel.rightCol = CreateFrame("Frame", nil, panel)
    panel.rightCol:SetPoint("TOPRIGHT", panel.topBar, "BOTTOMRIGHT", 0, -GAP)
    panel.rightCol:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -INSET, INSET)
    panel.rightCol:SetWidth(RIGHT_W)
    panel.rightCol:EnableMouse(true)
    T.ApplyBackdrop(panel.rightCol, {
        bgColor = DRAWER_BG,
        borderColor = DRAWER_BORDER,
        style = "chat",
    })

    panel.rightTitle = T.CreateGroupTitle(panel.rightCol, {
        text = Text("VISUAL_BOARD_PROPERTY_TITLE", "属性"),
        point = { "LEFT", panel.rightCol, "TOPLEFT", PAD, -(PAD + BTN_H / 2) },
        fontSize = T.Style.Scaled("MODULE_TITLE_FONT_SIZE"),
        color = T.Style.Color.KYRIAN_GOLD,
    })

    panel.rightCollapseButton = T.CreateButton(panel.rightCol, { width = HANDLE_W, height = BTN_H })
    panel.rightCollapseButton:SetPoint("TOPRIGHT", panel.rightCol, "TOPRIGHT", -PAD, -PAD)
    panel.rightCollapseButton:SetScript("OnClick", function()
        SetRightPanelCollapsed(not IsRightPanelCollapsed())
        if panel.ApplyResponsiveLayout then
            panel.ApplyResponsiveLayout(true)
        end
    end)

    -- Inspector 顶/左/右边固定；底边由“图层折叠区”动态决定（见 panel.SetLayerExpanded）：折叠时铺到折叠头之上，展开时让出图层区高度。
    panel.inspectorFrame = CreateFrame("Frame", nil, panel.rightCol)
    panel.inspectorFrame:SetPoint("TOPLEFT", panel.rightCol, "TOPLEFT", PAD, -(PAD + DRAWER_HEADER_H))
    panel.inspectorFrame:SetPoint("RIGHT", panel.rightCol, "RIGHT", -PAD, 0)

    -- 单元素属性区（§7）：动态行式 inspector，放进可滚动 content。propertyFrame = 滚动外框（SetShown 控制显隐）。
    local INNER_W = RIGHT_W - PAD * 2
    local HALF_W = math.floor((INNER_W - GAP) / 2)
    panel.inspectorInnerWidth = INNER_W
    panel.inspectorRows = {}
    panel.inspectorEdits = {}
    panel.inspectorScroll = T.CreateScrollPanel(panel.inspectorFrame, {
        point1 = { "TOPLEFT", panel.inspectorFrame, "TOPLEFT", 0, 0 },
        point2 = { "BOTTOMRIGHT", panel.inspectorFrame, "BOTTOMRIGHT", 0, 0 },
    })
    panel.propertyFrame = panel.inspectorScroll.scroll
    panel.inspectorContent = panel.inspectorScroll.content
    panel.inspectorFrame:HookScript("OnSizeChanged", function()
        Editor:RefreshProperties()
    end)

    -- 组/多选属性区（与单元素属性区互斥显示）
    panel.groupPropertyFrame = CreateFrame("Frame", nil, panel.inspectorFrame)
    panel.groupPropertyFrame:SetAllPoints(panel.inspectorFrame)
    panel.groupPropertyFrame:Hide()

    panel.groupTitle = T.CreateFontString(panel.groupPropertyFrame, {
        template = "GameFontHighlightSmall",
        point = { "TOPLEFT", panel.groupPropertyFrame, "TOPLEFT", 0, 0 },
        size = T.Style.Scaled("LABEL_FONT_SIZE"),
        width = INNER_W,
        justifyH = "LEFT",
        color = T.Style.Color.KYRIAN_GOLD,
    })

    panel.groupNameEdit = T.CreateEditBox(panel.groupPropertyFrame, { width = INNER_W, height = BTN_H, autoFocus = false })
    panel.groupNameEdit:SetPoint("TOPLEFT", panel.groupTitle, "BOTTOMLEFT", 0, -GAP)
    panel.groupNameEdit:SetScript("OnEnterPressed", function(self)
        if selectedGroupID and T.VisualBoardData and T.VisualBoardData.RenameGroup then
            T.VisualBoardData:RenameGroup(selectedBoardID, selectedGroupID, self:GetText())
            Editor:RefreshAll()
        end
        self:ClearFocus()
    end)

    panel.groupHideButton = T.CreateButton(panel.groupPropertyFrame, { width = HALF_W, height = BTN_H })
    panel.groupHideButton:SetPoint("TOPLEFT", panel.groupNameEdit, "BOTTOMLEFT", 0, -GAP)
    panel.groupHideButton:SetScript("OnClick", function()
        if not (selectedGroupID and T.VisualBoardData) then return end
        local group = T.VisualBoardData:GetGroup(selectedBoardID, selectedGroupID)
        if type(group) == "table" then
            T.VisualBoardData:SetGroupFlag(selectedBoardID, selectedGroupID, "hidden", not (group.hidden == true))
            Editor:RefreshProperties()
            Editor:RefreshLayerPanel()
            Editor:RenderEdit()
        end
    end)

    panel.groupLockButton = T.CreateButton(panel.groupPropertyFrame, { width = HALF_W, height = BTN_H })
    panel.groupLockButton:SetPoint("LEFT", panel.groupHideButton, "RIGHT", GAP, 0)
    panel.groupLockButton:SetScript("OnClick", function()
        if not (selectedGroupID and T.VisualBoardData) then return end
        local group = T.VisualBoardData:GetGroup(selectedBoardID, selectedGroupID)
        if type(group) == "table" then
            T.VisualBoardData:SetGroupFlag(selectedBoardID, selectedGroupID, "locked", not (group.locked == true))
            Editor:RefreshProperties()
            Editor:RefreshLayerPanel()
            Editor:RenderEdit()
        end
    end)

    panel.groupButton = T.CreateButton(panel.groupPropertyFrame, { width = HALF_W, height = BTN_H })
    panel.groupButton:SetPoint("TOPLEFT", panel.groupHideButton, "BOTTOMLEFT", 0, -GAP)
    panel.groupButton:SetScript("OnClick", function()
        Editor:GroupSelected()
    end)

    panel.ungroupButton = T.CreateButton(panel.groupPropertyFrame, { width = HALF_W, height = BTN_H })
    panel.ungroupButton:SetPoint("LEFT", panel.groupButton, "RIGHT", GAP, 0)
    panel.ungroupButton:SetScript("OnClick", function()
        Editor:UngroupSelected()
    end)

    -- 组头批量编辑入口（§9.2）：复用 layer_panel 的批量小面板（唯一权威，不在右栏重造 UI）。
    -- 只对"真正的组"可用（selectedGroupID 非空）；纯多选无组时隐藏，RefreshGroupProperties 控制显隐。
    panel.groupBatchButton = T.CreateButton(panel.groupPropertyFrame, { width = INNER_W, height = BTN_H })
    panel.groupBatchButton:SetPoint("TOPLEFT", panel.groupButton, "BOTTOMLEFT", 0, -GAP)
    panel.groupBatchButton:SetScript("OnClick", function()
        if selectedGroupID and T.VisualBoardLayerPanel and T.VisualBoardLayerPanel.OpenBatchPanel then
            T.VisualBoardLayerPanel:OpenBatchPanel({ id = selectedGroupID }, selectedBoardID)
        end
    end)

    panel.multiToolButtons = {}
    local THIRD_W = math.floor((INNER_W - GAP * 2) / 3)
    local function addMultiButton(name, anchor, relPoint, x, y, width, onClick)
        local button = T.CreateButton(panel.groupPropertyFrame, { width = width or THIRD_W, height = BTN_H })
        button:SetPoint("TOPLEFT", anchor, relPoint or "BOTTOMLEFT", x or 0, y or -GAP)
        button:SetScript("OnClick", onClick)
        button:Hide()
        panel.multiToolButtons[#panel.multiToolButtons + 1] = button
        panel[name] = button
        return button
    end
    panel.alignLeftButton = addMultiButton("alignLeftButton", panel.groupBatchButton, "BOTTOMLEFT", 0, -GAP, THIRD_W, function() Editor:AlignSelected("left") end)
    panel.alignHCenterButton = addMultiButton("alignHCenterButton", panel.alignLeftButton, "TOPRIGHT", GAP, 0, THIRD_W, function() Editor:AlignSelected("hcenter") end)
    panel.alignRightButton = addMultiButton("alignRightButton", panel.alignHCenterButton, "TOPRIGHT", GAP, 0, THIRD_W, function() Editor:AlignSelected("right") end)
    panel.alignTopButton = addMultiButton("alignTopButton", panel.alignLeftButton, "BOTTOMLEFT", 0, -GAP, THIRD_W, function() Editor:AlignSelected("top") end)
    panel.alignVCenterButton = addMultiButton("alignVCenterButton", panel.alignTopButton, "TOPRIGHT", GAP, 0, THIRD_W, function() Editor:AlignSelected("vcenter") end)
    panel.alignBottomButton = addMultiButton("alignBottomButton", panel.alignVCenterButton, "TOPRIGHT", GAP, 0, THIRD_W, function() Editor:AlignSelected("bottom") end)
    local HALF_TOOL_W = math.floor((INNER_W - GAP) / 2)
    panel.distributeHButton = addMultiButton("distributeHButton", panel.alignTopButton, "BOTTOMLEFT", 0, -GAP, HALF_TOOL_W, function() Editor:DistributeSelected("h") end)
    panel.distributeVButton = addMultiButton("distributeVButton", panel.distributeHButton, "TOPRIGHT", GAP, 0, HALF_TOOL_W, function() Editor:DistributeSelected("v") end)
    panel.sameWidthButton = addMultiButton("sameWidthButton", panel.distributeHButton, "BOTTOMLEFT", 0, -GAP, HALF_TOOL_W, function() Editor:UnifySelectedSize("w") end)
    panel.sameHeightButton = addMultiButton("sameHeightButton", panel.sameWidthButton, "TOPRIGHT", GAP, 0, HALF_TOOL_W, function() Editor:UnifySelectedSize("h") end)

    -- ===== 右栏下半：可折叠“图层”区（Keynote 把图层这种次要信息收进右侧，默认折叠/按需展开）=====
    -- 折叠头固定坐右栏底部一行；图层体（layerHostFrame）坐折叠头之上一块固定高度，默认隐藏。
    -- 折叠/展开是容器布局事务（唯一所有者=editor）：toggle 时显隐图层体 + 重锚 Inspector 底边；layer_panel 只负责“展开时渲染行”。
    local LAYER_SECTION_H = T.Style.Scale(170)
    panel.layerExpanded = false

    panel.layerToggle = T.CreateButton(panel.rightCol, { width = INNER_W, height = BTN_H })
    panel.layerToggle:SetPoint("BOTTOMLEFT", panel.rightCol, "BOTTOMLEFT", PAD, PAD)
    panel.layerToggle:SetPoint("BOTTOMRIGHT", panel.rightCol, "BOTTOMRIGHT", -PAD, PAD)

    panel.layerHostFrame = CreateFrame("Frame", nil, panel.rightCol)
    panel.layerHostFrame:SetPoint("BOTTOMLEFT", panel.layerToggle, "TOPLEFT", 0, GAP)
    panel.layerHostFrame:SetPoint("BOTTOMRIGHT", panel.layerToggle, "TOPRIGHT", 0, GAP)
    panel.layerHostFrame:SetHeight(LAYER_SECTION_H)
    panel.layerHostFrame:Hide()
    if T.VisualBoardLayerPanel and T.VisualBoardLayerPanel.Create then
        panel.layerPanel = T.VisualBoardLayerPanel:Create(panel.layerHostFrame)
        panel.layerPanel:ClearAllPoints()
        panel.layerPanel:SetAllPoints(panel.layerHostFrame)
        T.VisualBoardLayerPanel:SetCallbacks({
            GetBoardID = function() return selectedBoardID end,
            GetSelectedIDs = function() return selectedIDs end,
            GetCurrentSlideIndex = function() return currentSlideIndex end,
            OnSelect = function(id, isGroup, additive)
                if isGroup then
                    Editor:SelectGroup(id)
                elseif additive then
                    -- Shift 累加：切换该行元素的精确 id（Select 累加路径不提升整组）。
                    Editor:Select(id, true)
                else
                    -- 图层面板里点哪行就精确选哪个元素（Figma 行为）；即使该元素属组也不提升为整组选中。
                    Editor:EnterGroupChild(id)
                end
            end,
            -- 组头批量编辑（§9.2）：data 已在 layer_panel 内调过 BatchUpdateGroup，这里只负责整体刷新。
            OnBatchEdit = function(_, _)
                Editor:RefreshAll()
            end,
        })
    end

    -- 折叠头文本 + Inspector 底边随展开态切换（唯一权威：panel.layerExpanded）。
    function panel.SetLayerExpanded(expanded)
        panel.layerExpanded = expanded and true or false
        local rightCollapsed = panel.rightCollapsed == true
        panel.layerToggle:SetText(T.GetDisclosureText(panel.layerExpanded, Text("VISUAL_BOARD_LAYER_TITLE", "图层")))
        panel.layerToggle:SetShown(not rightCollapsed)
        panel.layerHostFrame:SetShown(panel.layerExpanded and not rightCollapsed)
        panel.inspectorFrame:SetPoint("BOTTOM", panel.layerExpanded and panel.layerHostFrame or panel.layerToggle, "TOP", 0, GAP)
        if panel.layerExpanded and not rightCollapsed then
            Editor:RefreshLayerPanel()
        end
    end
    panel.layerToggle:SetScript("OnClick", function()
        panel.SetLayerExpanded(not panel.layerExpanded)
    end)
    panel.SetLayerExpanded(false)

    -- ===== 中栏：组件抽屉 + 画布 + 底部命令（§3.2）=====
    panel.centerCol = CreateFrame("Frame", nil, panel)
    panel.centerCol:SetPoint("TOPLEFT", panel.topBar, "BOTTOMLEFT", 0, -GAP)
    panel.centerCol:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -INSET, INSET)

    panel.leftDrawerHandle = T.CreateButton(panel, { width = HANDLE_W, height = BTN_H })
    panel.leftDrawerHandle:SetPoint("TOPLEFT", panel.centerCol, "TOPLEFT", T.Style.Scale(4), -PAD)
    panel.leftDrawerHandle:SetScript("OnClick", function()
        SetLeftPanelCollapsed(false)
        if panel.ApplyResponsiveLayout then
            panel.ApplyResponsiveLayout(true)
        end
    end)
    panel.leftDrawerHandle:Hide()

    panel.rightDrawerHandle = T.CreateButton(panel, { width = HANDLE_W, height = BTN_H })
    panel.rightDrawerHandle:SetPoint("TOPRIGHT", panel.centerCol, "TOPRIGHT", -T.Style.Scale(4), -PAD)
    panel.rightDrawerHandle:SetScript("OnClick", function()
        SetRightPanelCollapsed(false)
        if panel.ApplyResponsiveLayout then
            panel.ApplyResponsiveLayout(true)
        end
    end)
    panel.rightDrawerHandle:Hide()

    function panel.RefreshDrawerTexts()
        panel.leftCollapseButton:SetText(Text("VISUAL_BOARD_COLLAPSE_PANEL", "收起"))
        panel.rightCollapseButton:SetText(Text("VISUAL_BOARD_COLLAPSE_PANEL", "收起"))
        panel.leftDrawerHandle:SetText(Text("VISUAL_BOARD_EXPAND_PANEL", "展开"))
        panel.rightDrawerHandle:SetText(Text("VISUAL_BOARD_EXPAND_PANEL", "展开"))
    end

    local function EaseOutCubic(t)
        local v = 1 - math.max(0, math.min(1, t))
        return 1 - v * v * v
    end

    local function SetDrawerAnchors(drawer, side, offsetX)
        drawer:ClearAllPoints()
        if side == "left" then
            drawer:SetPoint("TOPLEFT", panel.centerCol, "TOPLEFT", offsetX or 0, 0)
            drawer:SetPoint("BOTTOMLEFT", panel.bottomBar, "TOPLEFT", offsetX or 0, GAP)
            drawer:SetWidth(LEFT_W)
        else
            drawer:SetPoint("TOPRIGHT", panel.centerCol, "TOPRIGHT", offsetX or 0, 0)
            drawer:SetPoint("BOTTOMRIGHT", panel.bottomBar, "TOPRIGHT", offsetX or 0, GAP)
            drawer:SetWidth(RIGHT_W)
        end
    end

    local function StopDrawerAnimation(drawer)
        local driver = drawer and drawer._drawerAnimDriver
        if driver then
            driver:SetScript("OnUpdate", nil)
            driver:Hide()
        end
    end

    local function SetDrawerImmediate(drawer, handle, side, collapsed)
        StopDrawerAnimation(drawer)
        SetDrawerAnchors(drawer, side, 0)
        drawer:SetAlpha(1)
        drawer:SetShown(not collapsed)
        handle:SetShown(collapsed)
    end

    local function AnimateDrawer(drawer, handle, side, collapsed)
        StopDrawerAnimation(drawer)
        local direction = side == "left" and -1 or 1
        local startOffset = collapsed and 0 or (direction * DRAWER_ANIM_OFFSET)
        local endOffset = collapsed and (direction * DRAWER_ANIM_OFFSET) or 0
        local startAlpha = collapsed and 1 or 0.45
        local endAlpha = collapsed and 0.18 or 1

        drawer:Show()
        handle:Hide()
        SetDrawerAnchors(drawer, side, startOffset)
        drawer:SetAlpha(startAlpha)

        local driver = drawer._drawerAnimDriver
        if not driver then
            driver = CreateFrame("Frame", nil, panel)
            drawer._drawerAnimDriver = driver
        end
        driver.elapsed = 0
        driver:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + (tonumber(elapsed) or 0)
            local t = math.min(1, self.elapsed / DRAWER_ANIM_DUR)
            local eased = EaseOutCubic(t)
            local offset = startOffset + (endOffset - startOffset) * eased
            local alpha = startAlpha + (endAlpha - startAlpha) * eased
            SetDrawerAnchors(drawer, side, offset)
            drawer:SetAlpha(alpha)
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                SetDrawerImmediate(drawer, handle, side, collapsed)
            end
        end)
        driver:Show()
    end

    function panel.ApplyResponsiveLayout(animate)
        local leftCollapsed = IsLeftPanelCollapsed()
        local rightCollapsed = IsRightPanelCollapsed()
        local animateLeft = animate == true and panel.leftCollapsed ~= nil and panel.leftCollapsed ~= leftCollapsed
        local animateRight = animate == true and panel.rightCollapsed ~= nil and panel.rightCollapsed ~= rightCollapsed
        panel.leftCollapsed = leftCollapsed
        panel.rightCollapsed = rightCollapsed

        if panel.LayoutTopBar then
            panel.LayoutTopBar()
        end

        local overlayLevel = (panel.canvasFrame and panel.canvasFrame:GetFrameLevel() or panel:GetFrameLevel()) + 40
        panel.leftCol:SetFrameLevel(overlayLevel)
        panel.rightCol:SetFrameLevel(overlayLevel)
        if panel.leftCol.sd then panel.leftCol.sd:SetFrameLevel(overlayLevel - 1) end
        if panel.rightCol.sd then panel.rightCol.sd:SetFrameLevel(overlayLevel - 1) end
        panel.leftDrawerHandle:SetFrameLevel(overlayLevel + 5)
        panel.rightDrawerHandle:SetFrameLevel(overlayLevel + 5)

        panel.centerCol:ClearAllPoints()
        panel.centerCol:SetPoint("TOPLEFT", panel.topBar, "BOTTOMLEFT", 0, -GAP)
        panel.centerCol:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -INSET, INSET)

        if animateLeft then
            AnimateDrawer(panel.leftCol, panel.leftDrawerHandle, "left", leftCollapsed)
        else
            SetDrawerImmediate(panel.leftCol, panel.leftDrawerHandle, "left", leftCollapsed)
        end
        panel.leftTitle:Show()
        panel.slideHostFrame:Show()
        panel.leftCollapseButton:ClearAllPoints()
        panel.leftCollapseButton:SetPoint("TOPRIGHT", panel.leftCol, "TOPRIGHT", -PAD, -PAD)
        panel.leftCollapseButton:SetWidth(HANDLE_W)
        panel.leftCollapseButton:SetHeight(BTN_H)

        if animateRight then
            AnimateDrawer(panel.rightCol, panel.rightDrawerHandle, "right", rightCollapsed)
        else
            SetDrawerImmediate(panel.rightCol, panel.rightDrawerHandle, "right", rightCollapsed)
        end
        panel.rightTitle:Show()
        panel.inspectorFrame:Show()
        panel.rightCollapseButton:ClearAllPoints()
        panel.rightCollapseButton:SetPoint("TOPRIGHT", panel.rightCol, "TOPRIGHT", -PAD, -PAD)
        panel.rightCollapseButton:SetWidth(HANDLE_W)
        panel.rightCollapseButton:SetHeight(BTN_H)
        panel.RefreshDrawerTexts()

        if panel.SetLayerExpanded then
            panel.SetLayerExpanded(panel.layerExpanded)
        end
        Editor:RefreshSlideBar()
        Editor:RefreshProperties()

        Editor:RenderEdit()
    end

    -- 组件抽屉（§3.2）：拖拽落到画布建元素。SetCallbacks 注入 OnDropComponent（坐标换算 + 建元素）。
    if T.VisualBoardComponentDrawer and T.VisualBoardComponentDrawer.Create then
        panel.drawer = T.VisualBoardComponentDrawer:Create(panel)
        T.VisualBoardComponentDrawer:SetCallbacks({
            OnDropComponent = function(kind, presetData, screenX, screenY)
                Editor:OnDropComponent(kind, presetData, screenX, screenY)
            end,
        })
    end

    -- 底部命令条
    panel.bottomBar = CreateFrame("Frame", nil, panel.centerCol)
    panel.bottomBar:SetPoint("BOTTOMLEFT", panel.centerCol, "BOTTOMLEFT", 0, 0)
    panel.bottomBar:SetPoint("BOTTOMRIGHT", panel.centerCol, "BOTTOMRIGHT", 0, 0)
    panel.bottomBar:SetHeight(BOTTOMBAR_H)

    panel.undoButton = T.CreateButton(panel.bottomBar, { width = T.Style.Scale(72), height = BTN_H })
    panel.undoButton:SetPoint("BOTTOMLEFT", panel.bottomBar, "BOTTOMLEFT", 0, 0)
    panel.undoButton:SetScript("OnClick", function()
        Editor:Undo()
    end)

    panel.redoButton = T.CreateButton(panel.bottomBar, { width = T.Style.Scale(72), height = BTN_H })
    panel.redoButton:SetPoint("LEFT", panel.undoButton, "RIGHT", GAP, 0)
    panel.redoButton:SetScript("OnClick", function()
        Editor:Redo()
    end)

    panel.previewButton = T.CreateButton(panel.bottomBar, { width = T.Style.Scale(72), height = BTN_H })
    panel.previewButton:SetPoint("LEFT", panel.redoButton, "RIGHT", GAP, 0)
    panel.previewButton:SetScript("OnClick", function()
        Editor:StartPreview()
    end)

    -- 「停止预览」：隐藏所有活跃预览 HUD（编辑器预览播完冻结末帧，需手动停止入口）。
    panel.stopPreviewButton = T.CreateButton(panel.bottomBar, { width = T.Style.Scale(72), height = BTN_H })
    panel.stopPreviewButton:SetPoint("LEFT", panel.previewButton, "RIGHT", GAP, 0)
    panel.stopPreviewButton:SetScript("OnClick", function()
        Editor:StopPreview()
    end)

    -- 解锁/锁定 HUD 锚点：复用 Overlay:SetLocked（内部走 T.EditMode），让用户解锁→拖动+滚轮缩放→锁定。
    panel.lockButton = T.CreateButton(panel.bottomBar, { width = T.Style.Scale(84), height = BTN_H })
    panel.lockButton:SetPoint("LEFT", panel.stopPreviewButton, "RIGHT", GAP, 0)
    panel.lockButton:SetScript("OnClick", function()
        Editor:ToggleOverlayLock()
    end)
    Editor:RefreshLockButton()

    -- 预览不透明度可见滑块（§6.1）：解锁后滚轮透明度太隐蔽，这里给一个明面入口。
    -- 值的单一权威仍是 overlay 的 _overlay._alpha；拖滑块即经 Overlay:SetAlpha 调当前所有活跃预览 HUD 并持久化。
    -- 内联 OptionsSliderTemplate（与本文件 inspector 滑块同款），横排底栏放不下 label+slider 竖排，故用滑块自带 Text 当标签。
    panel.alphaSlider = CreateFrame("Slider", nil, panel.bottomBar, "OptionsSliderTemplate")
    panel.alphaSlider:SetPoint("BOTTOMLEFT", panel.lockButton, "BOTTOMRIGHT", GAP * 2, 0)
    panel.alphaSlider:SetWidth(T.Style.Scale(120))
    panel.alphaSlider:SetHeight(T.Style.Scaled("SLIDER_HEIGHT"))
    panel.alphaSlider:SetMinMaxValues(0, 1.0)
    panel.alphaSlider:SetValueStep(0.05)
    panel.alphaSlider:SetObeyStepOnDrag(true)
    if panel.alphaSlider.Low then panel.alphaSlider.Low:SetText("") end
    if panel.alphaSlider.High then panel.alphaSlider.High:SetText("") end
    local function RefreshAlphaLabel(v)
        if panel.alphaSlider.Text then
            panel.alphaSlider.Text:SetText(string.format("%s %d%%",
                Text("VISUAL_BOARD_PREVIEW_ALPHA", "预览不透明度"), math.floor(v * 100 + 0.5)))
            panel.alphaSlider.Text:ClearAllPoints()
            panel.alphaSlider.Text:SetPoint("BOTTOM", panel.alphaSlider, "TOP", 0, T.Style.Scale(2))
        end
    end
    panel.alphaSlider.__refreshing = true
    panel.alphaSlider:SetValue(T.VisualBoardOverlay and T.VisualBoardOverlay:GetAlpha() or 1.0)
    panel.alphaSlider.__refreshing = false
    RefreshAlphaLabel(panel.alphaSlider:GetValue())
    panel.alphaSlider:SetScript("OnValueChanged", function(self, value)
        if self.__refreshing then return end
        local snapped = math.floor(value / 0.05 + 0.5) * 0.05
        if T.VisualBoardOverlay then
            T.VisualBoardOverlay:SetAlpha(snapped)
        end
        RefreshAlphaLabel(snapped)
    end)

    -- 画布主区（无工具栏：从 centerCol 顶部一直铺到底部命令条上方）。
    -- 幻灯片帧条已移到左栏（Keynote 式竖排导航），中栏不再有横向帧条压在画布下，画布因此增高。
    panel.canvasHost = CreateFrame("Frame", nil, panel.centerCol)
    panel.canvasHost:SetPoint("TOPLEFT", panel.centerCol, "TOPLEFT", 0, 0)
    panel.canvasHost:SetPoint("TOPRIGHT", panel.centerCol, "TOPRIGHT", 0, 0)
    panel.canvasHost:SetPoint("BOTTOMLEFT", panel.bottomBar, "TOPLEFT", 0, GAP)
    panel.canvasHost:SetPoint("BOTTOMRIGHT", panel.bottomBar, "TOPRIGHT", 0, GAP)
    panel.canvasHost:SetScript("OnSizeChanged", function()
        Editor:RenderEdit()
    end)
    T.ApplyBackdrop(panel.canvasHost, { alpha = 0.20, style = "chat" })

    -- 画布帧铺满 host（§8.2：缩放/平移完全由 viewport 决定，不缩放 frame 本体）。
    panel.canvasFrame = CreateFrame("Frame", nil, panel.canvasHost)
    -- 视口裁剪（§8.2）：所有元素 texture/line/fontString/命中帧均 parent 到本帧；
    -- 超出画布框（host 内框）的渲染必须裁掉，否则 artboard 1:1 像素会溢出整个游戏 UI。
    panel.canvasFrame:SetClipsChildren(true)
    panel.canvasFrame:EnableMouse(true)
    panel.canvasFrame:EnableMouseWheel(true)
    -- 滚轮缩放（光标锚点，§8.2）。
    panel.canvasFrame:SetScript("OnMouseWheel", function(_, delta)
        Editor:ZoomAtCursor(delta)
    end)
    -- 中键拖拽 / 空格+左键拖拽平移（§8.2）：用 OnUpdate 轮询按键状态，避免被画布的空白点击捕获帧（Button，盖在上层）吃掉鼠标事件。
    -- 平移条件：鼠标悬停画布 且（中键按下 或 空格按住+左键按下）。屏幕 Y 向下为正：光标全局 y 增 → 屏幕 y 减。
    panel.canvasFrame:SetScript("OnUpdate", function(self)
        local spacePan = Editor:IsSpacePanActive()
        local active = self:IsMouseOver()
            and ((IsMouseButtonDown and IsMouseButtonDown("MiddleButton"))
                or (spacePan and IsMouseButtonDown and IsMouseButtonDown("LeftButton")))
        if not active then
            self.panning = false
            return
        end
        local cx, cy = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        if scale <= 0 then scale = 1 end
        local nx, ny = cx / scale, cy / scale
        if not self.panning then
            self.panning = true
            self.panLastX = nx
            self.panLastY = ny
            return
        end
        local dx = nx - (self.panLastX or nx)
        local dy = (self.panLastY or ny) - ny
        self.panLastX = nx
        self.panLastY = ny
        if dx ~= 0 or dy ~= 0 then
            Editor:PanViewport(dx, dy)
        end
    end)

    panel.canvasLabel = T.CreateFontString(panel.canvasFrame, {
        template = "GameFontNormalLarge",
        point = { "CENTER", panel.canvasFrame, "CENTER", 0, T.Style.Scale(10) },
        size = T.Style.Scaled("MODULE_TITLE_FONT_SIZE"),
        justifyH = "CENTER",
        color = T.Style.Color.TEXT_INACTIVE,
    })
    panel.renderer = T.VisualBoardCanvas and T.VisualBoardCanvas:Create(panel.canvasFrame) or nil

    panel:HookScript("OnSizeChanged", function()
        if panel.ApplyResponsiveLayout then
            panel.ApplyResponsiveLayout()
        end
    end)
    panel.ApplyResponsiveLayout()
    Editor.RefreshLocalization()
    return panel
end

end
end)
