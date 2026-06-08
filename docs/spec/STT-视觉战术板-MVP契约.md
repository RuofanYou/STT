# STT 视觉战术板 — MidnightFall MVP 冻结契约

> 状态：冻结 v1（2026-05-29）。本文件是本次 MVP 的**单一权威**。所有实现 agent 必须严格按本契约的接口签名、字段名、文件归属落地。**禁止偏离签名、禁止兜底/兼容映射、禁止保留双版本（旧单选 + 新多选）。**

---

## 0. 背景与现状真相（先纠正过时认知）

视觉战术板模块**早已存在**于 `ShengTangTools/visual_board/`，不是从零做。读代码确认的真实现状（spec 草案里"右键选中"等描述已过时，以本节为准）：

- `canvas.lua` 的 `RegisterEditHit` **已经是左键单击选中**（`OnClick` 左键 → `onSelect`；右键 → `onContext`）。
- `canvas.lua` 的 `DrawTransformerHandles` **已经画出八向缩放手柄 + 旋转手柄**（NW/N/NE/E/SE/S/SW/W/rotate），拖拽移动（`RegisterEditHit` 的 OnDragStart/Stop）也已实现。
- 文字（建/拖/双击改字/手柄缩放）、矩形（square）、八团队标记、MidnightFall 背景（encounterID `3183`，`backgrounds.lua` + `data.lua:ApplyMidnightfallTemplate`）**都已存在**。

**真正的缺口（本次 MVP 要补的）：**
1. **多选模型**：当前是单选 `selectedElementID`。组、图层、PPT 缩放三者都依赖多选。这是地基。
2. **组系统**：完全没有。
3. **图层面板**：只有 z 序 + 右键置顶/置底，没有 Figma 式图层列表。
4. **专精图标选择器**：当前只能在 `textureEdit` 手填贴图路径，没有任何图标选择器。
5. **PPT 式矩形缩放**：当前 `editor_gui:UpdateTransform` 对矩形是"中心对称 ×2"（W/E 同算、N/S 同算），不是 PowerPoint 的"锚定对边"。这是真 bug。

**用户拍板的范围约束（务必遵守）：**
- 只攻**静态绘图编辑器**。**时间轴 / 战斗内播放 / 全团广播链路保留但不优化、不破坏**：`overlay.lua`、`map_overlay.lua`、`parser_hook.lua` 以及 `data.lua` 中的 `step/start_t/end_t/hash/Export/Import/Merge/CollectReferencedBoards` 等播放与同步逻辑**不得改动语义**。
- 组、图层为本次重点，**严格对标 Figma 交互**，但 MVP 采用**单层组**（组内不嵌套组），覆盖"专精图标 + 文字成组"等 95% 场景。嵌套组留作后续。
- MidnightFall（`3183`）作为 MVP 主场景打磨样板。

---

## 1. 文件归属矩阵（铁律：不同 agent 改不同文件，零交叉）

| 归属 | 文件 | 角色 |
|---|---|---|
| **data-owner** | `visual_board/data.lua`（改）、`visual_board/spec_icons.lua`（新） | 数据层：schema 扩展、组 CRUD、图层 flag、多元素操作、几何单一权威、专精图标数据源 |
| **canvas-owner** | `visual_board/canvas.lua`（改） | 渲染层：多选渲染、隐藏/锁定处理、组包围盒与手柄、PPT 缩放手柄语义 |
| **panels-owner** | `visual_board/icon_picker.lua`（新）、`visual_board/layer_panel.lua`（新） | 两个自包含 UI 组件，暴露 API 供 editor 调用 |
| **editor-owner** | `visual_board/editor_gui.lua`（改）、`load.xml`（改）、`locale/enUS.lua`/`zhCN.lua`/`zhTW.lua`（改）、`core/gui.lua`（仅必要的挂载/帮助文本，改） | 集成中枢：多选状态机、组命令、工具栏、属性面板、挂载 picker/layer、键位、本地化、加载注册 |
| **docs-owner** | `docs/战术方案编写指南.md`（改）、`简介_STT.html` 中英文（改） | 文档同步 |

> **除归属人外，任何 agent 不得写其归属外的文件。** 跨文件只能通过本契约定义的 `T.*` 全局接口调用。`load.xml`、`locale/*`、`core/gui.lua` 只有 editor-owner 能改。

---

## 2. 通用工程约束（所有 agent）

- 每个 `.lua` 文件头：`local T, C, L = unpack(select(2, ...))`，**之后直接写代码，不加任何包裹**。⚠️ 本分支（main 派生 `feature/visual-board-mvp`）**没有 `T.RegisterColdFile` 这个函数**（那是 perf 实验分支专属）。现有 visual_board 文件全是朴素模式（见 `visual_board/core.lua`：首行 `local T, C, L = ...` 直接跟 `local VisualBoard = {}`，文件尾无 `end)`）。新文件**严禁**写 `T.RegisterColdFile(...)`，否则会调用不存在的函数→整文件加载失败。新文件必须逐字对照同目录现有文件的头尾模式。
- 玩家可见输出只走 `T.msg(...)`；调试只走 `T.debug(...)`；**禁止裸 `print(...)`**。
- **单一权威 + DRY**：`selectedElementID` 单选状态**整体替换**为多选集合，**不得保留两套**。任何"同义字段兜底"（如 `a or b`）非法。
- 改动后**必须** `luac -p <文件>` 通过（防智能引号静默失败）。
- 12.0 合规：纯 UI；用游戏内建材质/API，不新增 .tga。
- 不出现第三方竞品插件名。

---

## 3. 数据 schema 扩展（data-owner，权威）

### 3.1 元素（element）新增字段

在现有 element schema（`id/type/z/start_t/end_t/x/y/end_x/end_y/color/rotation/scale/fade_in/fade_out/step/params`）基础上**新增**：

```lua
element.name    = nil          -- string|nil：图层面板显示名；nil 时由 type+label/text 推导
element.hidden  = false        -- boolean：隐藏（渲染处处跳过）
element.locked  = false        -- boolean：锁定（编辑态不可命中：不可选/不可拖/无手柄；但照常渲染）
element.groupID = nil          -- string|nil：所属组 id（单层组）
```

`EnsureElementShape` 必须规范化这 4 个字段（`name` Trim 后空串归 nil；`hidden/locked` 布尔化；`groupID` 校验存在于 `board.groups`，悬空则清 nil）。

### 3.2 画板（board）新增字段

```lua
board.groups = {
    [groupID] = { id = groupID, name = "组1", hidden = false, locked = false },
    ...
}
```

`EnsureBoard`（或现有等价初始化）必须确保 `board.groups` 为 table，并剔除无成员的悬空组。

### 3.3 渲染/命中可见性规则（canvas-owner 与 data 共同遵守）

- **跳过渲染**：`element.hidden == true` **或** 其所属组 `board.groups[element.groupID].hidden == true`。
- **跳过命中（编辑态不注册 hitFrame，不画手柄）**：`element.locked == true` **或** 所属组 `.locked == true`。

---

## 4. data.lua 新增 API（data-owner 实现，签名冻结）

> 数据层与"选择"解耦：editor 传入 ID 列表，data 不持有选择状态。所有改动数据的函数都要走现有撤销栈（`DoCommand`/`CommitElementSnapshot` 同款），保证 Ctrl+Z 可回退。

### 4.1 几何单一权威（消除重复的尺寸逻辑）

```lua
-- 返回元素在【画板逻辑坐标】下的包围盒尺寸与形状语义，单一权威。
-- canvas 计算屏幕命中/手柄、editor 计算 PPT 缩放锚点，都必须调用本函数，禁止各自再算一遍。
-- 返回: w, h, shape  其中 shape ∈ "rect"|"radial"|"text"|"segment"
--   rect   : 矩形类(square)，w/h 独立
--   radial : 圆/图标/站位(circle/icon/slot)，w==h，按半径/尺寸
--   text   : 文字，按 fontSize 估算
--   segment: 线/箭头(line/arrow)，按两端点
function Data:GetElementBox(element)  --> w, h, shape
```

### 4.2 图层 flag 与命名

```lua
function Data:SetElementFlag(boardID, elementID, flag, value)  -- flag ∈ "hidden"|"locked"；撤销可回退
function Data:SetElementName(boardID, elementID, name)         -- name 空串→nil；撤销可回退
function Data:SetElementOrder(boardID, orderedIDs)             -- 按给定顺序重写 z（图层面板拖拽排序用）。orderedIDs 为自顶到底或自底到顶——【约定：数组首元素 z 最大（最上层）】；撤销可回退
```

> 现有 `MoveElementZ(boardID, elementID, "top"|"bottom"|"up"|"down")` 保留不动。

### 4.3 多元素操作

```lua
-- 将一组元素整体平移 dx,dy（画板逻辑坐标增量）。transient=true 仅预览不进撤销栈；
-- transient=false 时把整次拖拽合并为【一条】撤销记录。
function Data:MoveElements(boardID, elementIDs, dx, dy, transient)

-- 以 (originX,originY) 为锚点，将一组元素按 factor 等比缩放（位置与尺寸同步缩放）。
-- 缩放作用于每个元素的逻辑尺寸(w/h/radius/size/fontSize)与其相对锚点的位置。
-- transient 语义同上；factor 下限 0.1。
function Data:ScaleElements(boardID, elementIDs, factor, originX, originY, transient)
```

### 4.4 组 CRUD（单层组）

```lua
function Data:CreateGroup(boardID, elementIDs, name)  --> groupID    -- 给成员写 groupID，建 board.groups 条目；name 可空(自动"组N")；撤销可回退
function Data:Ungroup(boardID, groupID)                              -- 清成员 groupID，删 board.groups 条目；撤销可回退
function Data:GetGroup(boardID, groupID)              --> group|nil
function Data:GetGroupMembers(boardID, groupID)       --> { element, ... }（按 z 升序）
function Data:SetGroupFlag(boardID, groupID, flag, value)           -- flag ∈ "hidden"|"locked"；撤销可回退
function Data:RenameGroup(boardID, groupID, name)                   -- 撤销可回退
```

### 4.5 图标字段可写性（确保专精图标可落地）

`AddElementAt(boardID, "icon", x, y, fields)` 与 `UpdateElement` 必须支持 `fields.texture`（fileID 数字或路径字符串）、`fields.atlas`（字符串）、`fields.size`（数字）。`_ApplyElementFields` 中补齐这三者的写入（若已支持则确认无误）。`texture` 允许数字 fileID（`SetTexture(fileID)` 合法）。

---

## 5. spec_icons.lua 新增模块（data-owner，新文件）

运行时基于游戏 API 动态构建全职业全专精图标数据，**不硬编码 fileID**（版本无关、DRY）。

```lua
T.VisualBoardSpecIcons = {}

-- 返回有序职业列表（含每职业的专精）。结果应缓存（首次构建后复用）。
-- 数据来自：GetNumClasses / GetClassInfo / C_CreatureInfo 或 GetClassInfoByID,
--   每职业用 GetSpecializationInfoForClassID(classID, i) 取 specID/name/icon/role。
function T.VisualBoardSpecIcons:GetClasses()
--> {
--     { classID=1, classFile="WARRIOR", className="战士", color={r,g,b},
--       icon=<职业图标 fileID/atlas>,
--       specs = { { specID=71, name="武器", icon=<fileID>, role="DAMAGER" }, ... } },
--     ...
--   }

-- 扁平搜索：按名称（职业名/专精名，支持子串）返回匹配项，供搜索框用。
-- 返回项形如 { kind="spec"|"class", classFile, className, specName(可空), icon, label }
function T.VisualBoardSpecIcons:Search(query)  --> { item, ... }
```

> 取图标用 `GetSpecializationInfoForClassID` 返回的 icon（fileID）。职业图标可用 `C_Texture.GetAtlasInfo("classicon-"..classFile:lower())` 之类的内建 atlas，或 `GetClassInfo`/职业图标坐标。具体取法由 data-owner 联网核对 12.0 API 后选定，但**输出结构必须如上**。

---

## 6. canvas.lua 渲染契约（canvas-owner，签名冻结）

### 6.1 `renderer:Render(board, timeValue, opts)` opts 字段变更

**移除** `opts.selectedElementID`（单选），**替换为**：

```lua
opts = {
    mode = "edit",
    selectedIDs = { [elementID]=true, ... },   -- 选中集合（单选即单条目集合）
    selectedGroupID = groupID 或 nil,          -- 当"整组"被选中时给出（用于画组包围盒）
    onSelect = function(elementID, additive) end,      -- additive=true 表示 Shift 累加（canvas 在 OnClick 时读 IsShiftKeyDown() 传入）
    onDrag = function(elementID, x, y, transient) end, -- 不变；editor 内部决定移动整个选中集
    onTransformStart = function(elementID, kind) end,  -- 不变
    onTransform = function(elementID, kind, x, y, transient) end,  -- 不变
    onGroupTransformStart = function(groupID, kind) end,           -- 新增：组手柄按下
    onGroupTransform = function(groupID, kind, x, y, transient) end,-- 新增：组等比缩放(kind∈"NW"/"NE"/"SE"/"SW")或拖动
    onDoubleClick = function(elementID) end,           -- 不变
    onContext = function(elementID) end,               -- 不变
    onBackgroundClick = function() end,                -- 新增：点击画布空白处（editor 用于清空选择）
}
```

> 播放/预览调用（overlay、editor 预览）**不传** `selectedIDs`/`mode`，渲染逻辑必须对"无选择/非编辑态"完全等价于改动前（不画任何选择 UI）。

### 6.2 渲染行为

- **可见性**：按 §3.3，`hidden`（元素或其组）跳过渲染。
- **命中**：按 §3.3，`locked`（元素或其组）不注册 hitFrame、不画手柄。
- **选择高亮**：对 `selectedIDs` 中**每个**元素画选择框（沿用 `DrawSelectionBox` 样式）。
- **单选手柄**：当 `selectedIDs` 恰好 1 个且无 `selectedGroupID` 时，画现有八向 + 旋转手柄（保留）。
- **组/多选包围盒**：当 `selectedGroupID` 非空，或 `selectedIDs` ≥ 2 时：用 `Data:GetElementBox` 求各成员屏幕盒的并集，画一个组包围盒边框 + **四角**等比缩放手柄（角点拖拽触发 `onGroupTransform(groupID,"NW"/.."SE")`；包围盒内拖动整体移动走现有 `onDrag`/editor 多选移动）。MVP 组只做四角等比，不做边手柄。
- **空白点击**：画布父 frame 空白区域点击（未命中任何 hitFrame）触发 `opts.onBackgroundClick()`。可在现有 `canvasFrame:OnMouseDown` 协作（editor 侧已有 `PlaceActiveTool`，二者需协调：有激活工具→放置；无激活工具且未命中元素→清空选择）。

### 6.3 几何 DRY

`GetHitBox` 内部的"逻辑尺寸"计算必须改为调用 `Data:GetElementBox(element)` 得到逻辑 w/h，再用现有 `ScalePoint` 换算屏幕，**不得在 canvas 里重复硬编码** radius*2 / w / h / size 这套尺寸推导。

---

## 7. editor_gui.lua 集成（editor-owner，签名冻结）

### 7.1 选择状态机（替换单选）

- 把 `selectedElementID`（单条）**整体替换**为 `selectedIDs`（集合/有序表）+ `selectedGroupID`（当前激活的整组）。提供内部 helper：`IsSelected(id)`、`Select(id, additive)`、`SelectGroup(groupID)`、`ClearSelection()`、`GetSelectedList()`。
- **Figma 选择语义**：
  - 普通左键点击元素：单选该元素。若该元素属于某组 → 选中**整组**（`selectedGroupID`=该组，`selectedIDs`=组全部成员）。
  - Shift+左键：累加/移除（`additive`）。
  - 双击属于组的元素：进入组，选中**该单个子元素**（脱离"整组选中"，可单独编辑该子元素）。
  - 双击 text 元素：维持现有内联改字（`BeginInlineEdit`）。二者按元素类型分流。
  - 点击画布空白（`onBackgroundClick`）：清空选择。
- 拖动任一选中元素 → 调 `Data:MoveElements(boardID, selectedIDs, dx, dy, transient)` 整体移动。

### 7.2 PPT 式单元素缩放（修 `UpdateTransform`）

重写 `UpdateTransform` 的尺寸分支，按形状（用 `Data:GetElementBox` + `transformState.before` 的盒）实现"锚定对边/对角"：

- **rect（square）**：拖某手柄时，固定其**对边/对角**，按光标计算新 w/h 并相应移动中心 x/y。
  - 例：拖 `E` → 固定西边，`newW = max(12, cursorX − westX)`，`newCenterX = (westX + cursorX)/2`，`h` 不变。`SE` → 固定 NW 角，w、h 同时按光标。`W`/`N`/`S`/`NW`/`NE`/`SW` 同理。
- **radial（circle/icon/slot）**：以中心为锚，`radius/size = 光标到中心距离`（半径类天然径向，保持中心不动）。
- **text**：按光标到中心的竖直距离调 `fontSize`（中心不动）。
- **segment（line/arrow）**：拖端点改 `end_x/end_y`（沿用现有）。
- `rotate` 手柄：沿用现有旋转逻辑。
- 提交（transient=false）走 `CommitElementSnapshot` 一条撤销记录（沿用现有）。

### 7.3 组命令与键位

- `Ctrl+G`：对 `selectedIDs`（≥2）调 `Data:CreateGroup`，之后选中该组。
- `Ctrl+Shift+G`：对 `selectedGroupID` 调 `Data:Ungroup`。
- 组手柄回调 `onGroupTransform` → `Data:ScaleElements(boardID, 组成员, factor, originX, originY, transient)`（factor 由拖拽角点相对对角的距离比得出；origin=对角点）。
- `Delete/Backspace`：删除整个选中集（多选/组）。`Esc`：清空选择。`Ctrl+C/V/D`：对选中集复制/粘贴/重复（多元素）。

### 7.4 工具栏与属性面板

- **图标工具改造**：把现有"icon → 直接放占位 + 手填 textureEdit"改为：点"图"工具 → 打开 `T.VisualBoardIconPicker:Open(anchor, onPick)`；`onPick(item)` 回调里 `Data:AddElementAt(boardID,"icon",x,y,{ texture=item.icon, size=44 })`（item.icon 为 fileID）。**移除手填贴图路径的主交互**（textureEdit 可保留为高级编辑，但不再是主入口）。
- 团队标记（marker）popover 维持现状不动（已可用）。
- **属性面板**：单选→沿用现有元素属性；多选/组选中→显示组属性（名称、显示/隐藏、锁定、整体位置）。`name/hidden/locked` 走 §4.2/§4.4 接口。

### 7.5 挂载图层面板

- 在编辑器布局内挂载 `T.VisualBoardLayerPanel`（见 §9）。布局位置由 editor-owner 定（建议放在右侧 inspector 区，与属性面板分区/分页共存），不挤占画布主区。
- 选择联动双向：画布选中 → 图层面板高亮当前项并滚动定位；图层面板点击项 → editor 选中对应元素/组（"找不到时点图层快速定位"）。

### 7.6 加载注册 / 本地化 / 帮助文本

- `load.xml`：在 `data.lua` 之后加 `spec_icons.lua`；在 `editor_gui.lua` 之前加 `icon_picker.lua`、`layer_panel.lua`。
- `locale/enUS.lua`（键集合权威）+ `zhCN.lua` + `zhTW.lua`：新增本契约涉及的所有可见文案键（图标选择器标题/搜索占位、成组/解组、图层/显示/隐藏/锁定/重命名、组属性等）。enUS 为权威，三语种键集合一致。完成后须能过 `Tools/check_locale.sh`。
- `core/gui.lua` 的帮助文本键 `GUI_HELP_VISUAL_BOARD_LINE`：更新为包含"专精图标选择器、成组(Ctrl+G)、图层面板"。仅改文案，不动 tab 注册结构。
- **NEW 角标**：本次改动在视觉画板 tab 内部，不涉及 `options/*_options.lua` 的 module/item，**默认无 NEW 角标义务**；除非 editor-owner 额外在 options 里加了开关项（不建议），那才需 `newSince`。

---

## 8. icon_picker.lua（panels-owner，新文件）

```lua
T.VisualBoardIconPicker = {}

-- 打开图标选择器（弹出层），锚定到 anchor。选中某图标后调 onPick(item) 并关闭。
-- item 形如 { icon=<fileID>, label="武器战" }（取自 SpecIcons）。
function T.VisualBoardIconPicker:Open(anchor, onPick)
function T.VisualBoardIconPicker:Close()
```

UI 要求：顶部搜索框（接 `T.VisualBoardSpecIcons:Search`）；下方按职业分组的图标网格（接 `:GetClasses()`），职业用 class color 分隔；点击图标 → `onPick` + 关闭。**像 Figma/PPT 选素材一样直观**：网格、悬停高亮、键盘可关闭(Esc)。文案走 L[] 键（键名报告给 editor-owner 加入 locale；或 editor-owner 已按 §7.6 预置，panels-owner 用约定键名）。

> **本地化协作约定**：panels-owner 使用键名前缀 `VISUAL_BOARD_ICONPICKER_*` 与 `VISUAL_BOARD_LAYER_*`，并用 `L["KEY"] or "中文兜底字面量"` 的现有 `Text()` 模式取值（editor-owner 负责把这些键补进 locale/*）。

---

## 9. layer_panel.lua（panels-owner，新文件）

```lua
T.VisualBoardLayerPanel = {}

-- 创建图层面板 frame（挂到 parent）。返回 frame。
function T.VisualBoardLayerPanel:Create(parent)  --> frame

-- 用回调把面板接到 editor（解耦：面板不直接 import editor 内部状态）。
function T.VisualBoardLayerPanel:SetCallbacks(callbacks)
-- callbacks = {
--   GetBoardID = function() --> boardID end,
--   GetSelectedIDs = function() --> { [id]=true } end,
--   OnSelect = function(idOrGroupID, isGroup, additive) end,  -- 点击图层项
--   -- flag/排序/改名 直接走 T.VisualBoardData 接口即可，但选中态变更要回调 editor
-- }

-- 刷新列表（editor 在选择/数据变化后调用）。
function T.VisualBoardLayerPanel:Refresh()
```

UI 要求（抄 Figma 图层交互）：
- 自**顶到底**列出"组 + 顶层元素"，z 最大者在最上（与 `Data:SetElementOrder` 数组首=最上层一致）。组可折叠/展开显示成员。
- 每行：显示名（双击改名，走 `Data:SetElementName`/`RenameGroup`）、眼睛图标（切 hidden，走 `Data:SetElementFlag`/`SetGroupFlag`）、锁图标（切 locked）。
- 点击行 → `OnSelect`（支持 Shift 累加 additive）→ editor 选中并在画布定位。
- 拖拽行重排 → `Data:SetElementOrder`（MVP 可先只支持顶层元素/组之间重排，组内成员重排可留后续，但需保证不报错）。
- 当前选中项高亮。

---

## 10. 验收标准（验收 agent + 主控）

1. `luac -p` 通过：所有改动/新增 `.lua`（data/canvas/editor_gui/spec_icons/icon_picker/layer_panel）。
2. `rg -n "print\(" ShengTangTools -g '!ShengTangTools/libs/**'` 无新增裸 print。
3. `bash Tools/check_locale.sh` 通过（或无新缺键/多键）。
4. 接口对齐：canvas/editor/panels 调用的 `Data:*`、`SpecIcons:*`、`IconPicker:*`、`LayerPanel:*` 签名与本契约一致；无 `selectedElementID` 残留（已全替换为 `selectedIDs`）。
5. 播放链路未被破坏：`overlay.lua`/`map_overlay.lua`/`parser_hook.lua` 未改语义；canvas 在不传 `selectedIDs/mode` 时渲染等价于改前。
6. 功能可达（人工/读码核对）：MidnightFall 画板下可创建文字/矩形/专精图标(选择器)/团队标记；可多选、成组(Ctrl+G)/解组、整组移动与等比缩放；图层面板可点击定位、显隐、锁定、重排；矩形手柄缩放为 PPT 式锚定对边。
7. `bash Tools/deploySTT.sh retail` 一次成功（主控在验收后执行）。
8. 文档同步：`战术方案编写指南.md`、`简介_STT.html`(中英)、`GUI_HELP_VISUAL_BOARD_LINE` 均提及专精图标选择器/组/图层。

---

## 11. 红线（永不做）

- 不改时间轴/广播/播放语义（保留不优化）。
- 不保留旧单选与新多选两套（单一权威）。
- 不写兜底/同义字段映射。
- 不硬编码专精图标 fileID（走 API 动态构建）。
- 不在源码出现第三方竞品插件名。
- 不嵌套组（MVP 单层组）。
