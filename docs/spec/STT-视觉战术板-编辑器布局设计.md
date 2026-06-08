# STT 视觉战术板 — 编辑器布局重做设计契约（Figma 三栏）

> 状态：冻结 v1（2026-05-29）。本文件是**编辑器布局重做轮**的单一权威。第一轮的数据层(data.lua)/渲染层(canvas.lua)已验收正确，**本轮不改它们**；面板公共 API 保持稳定。本轮只重做**布局与视觉**，让编辑器对齐 STT 设计系统并达到 Figma 级易用。

---

## 0. 为什么要重做（上一轮的失败）

上一轮 editor 用裸 `CreateFrame`+裸 `GameFontXxx`+硬编码偏移堆布局，**完全没用 STT 设计系统**，导致：
- 右侧 `layerHostFrame`(锚 -242) 与 220px 高的 `propertyFrame`+缩放控件**竖直碰撞**（"图层"叠"1.00"、按钮糊一团）。
- `rotationLabel`/`scaleLabel` 同行仅隔 82px、无宽度 → 文字相撞。
- 工具栏 `选/站/形/图/字/标` 裸单字、无 tooltip → 没人懂"图"是专精图标入口。

**本轮目标**：Figma 经典三栏布局 + 全程走 STT 设计系统 + 图标工具栏带 tooltip + 彻底消除碰撞 + 专精图标入口一目了然。

---

## 1. STT 设计系统（强制，铁律）

权威定义：`core/style.lua`（token/颜色/缩放）、`core/widget_api.lua`（组件工厂）。

**必须遵守：**
- **所有控件经 `T.Create*` 工厂生成**：`T.CreateButton / CreateToggleButton / CreateCycleButton / CreateLabel / CreateEditBox / CreateSelectorButton / CreateScrollPanel / CreateTabGroup / CreateCollapsibleSection / CreateSeparator / CreateGroupTitle / CreateFontString`。**禁止**手写 `CreateFrame`+`SetFont`+硬编码字号（容器 Frame 可以 CreateFrame，但文字/按钮/输入框/分割线/标题必须走工厂）。
- **所有尺寸/间距经缩放**：标准量用 `T.Style.Scaled("TOKEN")`（token 见 `Style.BASE`：`BUTTON_HEIGHT=26 / DROPDOWN_HEIGHT=26 / ITEM_HEIGHT=26 / ITEM_GAP=2 / LABEL_FONT_SIZE=12 / CHECKBOX_SIZE=24` 等）；编辑器特有的布局数值用 `T.Style.Scale(字面量)`（= floor(字面量×fontScale)，仿 widget_api 的 ScaleForSettings 模式）。**禁止裸写像素常量**做尺寸/偏移。
- **栅格**：2px 水平栅格；分区留白参考主面板（inset 24、侧栏内 pad ~12、控件段距 ≈ fontSize×1.6）。
- **颜色**：从 `T.Style.Color` 取（`KYRIAN_GOLD` 金=强调/标题/激活；`TEXT_INACTIVE` 灰=非激活；`SECTION_LINE`=分割线；`TEXT_HOVER`=悬停白）。**禁止硬编码 RGBA**做文字/强调色（画布内图元颜色不在此列，那是数据）。
- **backdrop**：分区容器用 `T.ApplyBackdrop(frame, {style="tooltip"|"chat", alpha=…})`。
- **字号响应**：工厂创建的文字会自动随 fontScale 重排，无需额外处理；若手动需要刷新，参考 `realtime_board_gui.lua` 的 `refreshList` 注册模式。
- **本轮不改 `core/style.lua`**：复用现有 token + `Style.Scale(字面量)` 即可，不新增 `Style.BASE` 条目（避免触碰共享文件）。

**范例标杆**（实现前务必读）：`core/gui.lua`(主面板三区布局)、`options/nav_tree.lua`(列表/缩进/对齐)、`core/realtime_board_gui.lua`(分区+控件递推布局)。

---

## 2. 文件归属（本轮，铁律：不同 agent 改不同文件）

| 归属 | 文件 | 角色 |
|---|---|---|
| **editor-owner** | `visual_board/editor_gui.lua`（重写布局部分） | Figma 三栏骨架、顶栏、横向图标工具栏、右侧上下文属性面板、挂载左侧图层面板、所有定位走设计系统 |
| **iconpicker-owner** | `visual_board/icon_picker.lua`（重做样式） | 选择器弹窗按设计系统重做：搜索框、职业分组网格、配色、间距、悬停、tooltip；**公共 API `:Open(anchor,onPick)` / `:Close()` 签名不变** |
| **layerpanel-owner** | `visual_board/layer_panel.lua`（重做样式） | 图层面板按设计系统重做：适配左栏常驻、行高/缩进/图标/金色高亮/分割；**公共 API `:Create(parent)` / `:SetCallbacks(cb)` / `:Refresh()` 签名不变** |

**不准碰**：`data.lua`、`canvas.lua`、`spec_icons.lua`（上一轮已对、本轮零改动）；`core/style.lua`、`core/gui.lua`、`load.xml`、`locale/*`（本轮无需求；若 editor 确需补极少量 locale 键，仅 editor-owner 可动 locale，并保持三语种一致）。播放链路(overlay/map_overlay/parser_hook)不准碰。

---

## 3. 三栏布局结构（editor-owner，冻结）

在视觉画板 tab 根 `panel` 内重排为：**顶栏 + 三栏 body**。所有锚点用相对 `SetPoint`，所有尺寸/偏移用 `Style.Scaled`/`Style.Scale`。

```
┌─ panel (tab 根) ────────────────────────────────────────────────┐
│ topBar  (高=Scaled(BUTTON_HEIGHT)+上下pad，满宽)                  │
│  画板选择器▾ │ 名称EditBox │ 时长EditBox │ 保存 │ Boss选择器▾ │ 删除│
├──────────────┬───────────────────────────────────┬──────────────┤
│ leftCol      │ centerCol                          │ rightCol     │
│ 宽=Scale(180)│ flex(填充中间)                      │ 宽=Scale(220)│
│              │ ┌ toolbar 行(高=Scaled(BUTTON_H)+pad)┐│              │
│ 图层(标题)   │ │[选][站][形▾][图][字][标▾] 图标按钮 ││ 属性(标题)   │
│ ┌图层列表──┐ │ └────────────────────────────────────┘│ ┌属性区────┐ │
│ │LayerPanel│ │ ┌ canvasHost/canvasFrame(填充)──────┐ ││ │上下文控件│ │
│ │ :Create  │ │ │     画布(MidnightFall 背景)        │ ││ │(元素/组) │ │
│ │          │ │ └────────────────────────────────────┘ ││ └──────────┘ │
│ └──────────┘ │ ┌ bottomBar [撤销][重做][预览] ───────┐ ││              │
└──────────────┴───────────────────────────────────┴──────────────┘
```

锚点要点（相对、token 化）：
- `topBar`：`TOPLEFT/TOPRIGHT` 贴 panel，留 inset；高 = `Scaled("BUTTON_HEIGHT") + Scale(12)`。内部控件横向排布，用 `Style.Scale(8~12)` 作间距，金色分隔可选。
- `leftCol`：`TOPLEFT` 贴 topBar 底，`BOTTOMLEFT` 贴 panel 底；宽 `Style.Scale(180)`。顶部金色标题"图层"(`T.CreateGroupTitle`)，下方 `layerHostFrame` 充满，调 `T.VisualBoardLayerPanel:Create(layerHostFrame)` + `SetAllPoints`。
- `rightCol`：`TOPRIGHT` 贴 topBar 底，`BOTTOMRIGHT` 贴 panel 底；宽 `Style.Scale(220)`。顶部金色标题"属性"，下方上下文属性区。
- `centerCol`：夹在 left/right 之间填充。内含 `toolbar`(顶) + `canvasHost`(中，充满) + `bottomBar`(底)。`canvasHost:OnSizeChanged` 仍触发 `RenderEdit`（保留现有等比 UpdateCanvasStage 逻辑）。
- **碰撞根除**：图层在左栏独占整列、属性在右栏独占整列，二者物理隔离，不再竖直叠压。属性区内各控件用 `Style.Scale` 递推 Y、每个 label 显式 `SetWidth` 并 `SetJustifyH("LEFT")`，杜绝同行文字相撞。

### 3.1 顶栏（替代旧 listFrame 画板列表）

- **画板选择器**：用 `T.CreateSelectorButton` 列出所有画板（item=各 board，`onSelect` 切换 selectedBoardID 并 `RefreshAll`），label="画板"。**取代**原左侧 `listFrame` 整列（画板列表收进下拉，给三栏腾出横向空间）。旁边一个 `T.CreateButton` "新建"。
- 名称 `EditBox`、时长 `EditBox`、"保存"按钮：沿用现有 SaveMeta 逻辑，只换工厂与定位。
- Boss `mapSelector`（`T.CreateSelectorButton`）：沿用现有 `RefreshMapControls`/`SetBackgroundEncounter`。
- "删除"按钮：右端，沿用现有删除逻辑（builtin 禁用）。

### 3.2 横向图标工具栏（centerCol 顶部，冻结交互）

- 工具：`选择 / 站位 / 形状 / 图标 / 文字 / 标记`，横向排列的**图标按钮**(`T.CreateButton` 或 `CreateToggleButton`，每个 `Scaled("BUTTON_HEIGHT")` 见方左右)。
- **每个按钮**：① 设 atlas 图标（见下）；② **必须**有 `GameTooltip`（`OnEnter` 显示中文工具名 + 一句说明，`OnLeave` 隐藏）；③ 激活态用金色描边/高亮（沿用 `RefreshToolState` 思路，但改金色）。
- **图标 atlas（实现前须核验存在性，可只读查 /Applications/World of Warcraft/_retail_/Interface/AddOns/ 或 wow-ui-source；若某图缺失则降级显示该工具中文首字 + tooltip，保证不空白——这是素材降级，非逻辑兜底）**。候选（自行核验/替换为确实存在的 12.0 atlas）：
  - 选择：箭头/光标类（如 `UI-Cursor-Point` 或通用箭头 atlas）
  - 站位：人物/圈类（如 `groupfinder-icon-class` 或圆形 atlas）
  - 形状：方块（`UI-Frame-Bg` 不合适→用简单几何 atlas 或矩形 glyph）
  - 图标：专精/职业感（如 `talents-button-` 或一个明确的"图标"感 atlas）
  - 文字：字母 T 感 atlas，或直接金色"T"字 fontstring
  - 标记：**直接用 `Interface\\TargetingFrame\\UI-RaidTargetingIcon_1`**（确定存在，骷髅/星等）
- **形状 / 标记** 仍走下拉 popover（沿用现有 `shapePopover`/`markerPopover`，但用设计系统重排：圆/方/箭/线；八标记）。
- **图标工具**：点击 → `Editor:OpenIconPicker(anchorButton)` → `T.VisualBoardIconPicker:Open`（链路已有，保留）。这是专精图标的**唯一明确入口**，tooltip 写明"选择全职业专精图标"。

### 3.3 右栏上下文属性面板（rightCol，冻结）

- **单选**（恰好 1 个元素、无组）：显示该元素属性——名称/大小(半径或字号)/标记(站位/图标可切)/旋转/缩放/换色/删除。沿用现有 `SaveSelectedElement`/`UpdateElement` 逻辑，只换工厂与竖直递推定位（每控件一行，label 在上或左、宽度显式、用 `Style.Scale` 间距）。
- **多选/组**：显示组属性——组名(改名)/显示隐藏(`SetGroupFlag`)/锁定/成组/解组。与单选区**互斥显示**（沿用现有 propertyFrame/groupPropertyFrame 互斥思路，但二者都在右栏、且不再与图层面板争用空间）。
- 旋转/缩放/换色等沿用现有数据接口，**不改 data.lua**。

### 3.4 左栏图层面板（leftCol）

- 调 `T.VisualBoardLayerPanel:Create(layerHostFrame)` + `:SetCallbacks({GetBoardID,GetSelectedIDs,OnSelect})` + 每次选择/数据变化 `:Refresh()`（链路已有，保留；只是挂到左栏并给足整列高度）。

---

## 4. icon_picker.lua 重做样式（iconpicker-owner）

公共 API 不变（`:Open(anchor,onPick)`/`:Close()`）。内部按设计系统重做，达到"像 Figma/PPT 选素材一样直观"：
- 弹窗容器 `T.ApplyBackdrop(style="tooltip")`；标题用 `T.CreateGroupTitle` 金色"选择专精图标"。
- 顶部搜索 `T.CreateEditBox`（占位文案走 L[] 或中文字面量），`OnTextChanged` 调 `T.VisualBoardSpecIcons:Search`。
- 网格用 `T.CreateScrollPanel`；无搜索词时按职业分组，**职业标题用该职业 class color**，组内专精图标网格；图标格统一尺寸(`Style.Scale`)、悬停金色描边 + tooltip(专精名)、点击 `onPick({icon,label})` 并 `Close`。
- Esc / 右上关闭。所有文字走工厂、尺寸走 Style。无裸 print。

## 5. layer_panel.lua 重做样式（layerpanel-owner）

公共 API 不变（`:Create`/`:SetCallbacks`/`:Refresh`）。适配**左栏常驻**：
- 行用工厂构件；行高 `Scaled("ITEM_HEIGHT")`、间距 `Scaled("ITEM_GAP")`、缩进 `Scaled("ITEM_INDENT")`（组成员缩进）。
- 自顶到底列"组+顶层元素"（z 最大在最上）；组可折叠（`T.GetDisclosureText` 箭头）；每行：折叠箭头(组)、显示名、眼睛(hidden)、锁(locked)；当前选中行用 `KYRIAN_GOLD` 高亮、非选中 `TEXT_INACTIVE`。
- 双击改名(内联 EditBox)、点击 `OnSelect(id,isGroup,additive)`(Shift 累加)、顶层拖拽重排 `Data:SetElementOrder`（沿用，不改 data）。
- 所有文字走工厂、尺寸/颜色走 Style。无裸 print。

---

## 6. 通用约束（所有 agent）

- 文件头朴素：`local T, C, L = unpack(select(2, ...))` 直接跟代码，**无 `T.RegisterColdFile`**（本分支无此函数）、无 `end)`。逐字对照同目录现有文件。
- 玩家可见输出 `T.msg`，调试 `T.debug`，**禁止裸 print**。
- 单一权威/DRY，禁止兜底/同义字段映射。
- 每改一个 `.lua` 跑 `luac -p` 通过。
- Bash cwd 每次重置，用绝对路径或 cd 到仓库根 `/Users/rofan/Cursor/魔兽插件-vboard`。
- **不改** data.lua/canvas.lua/spec_icons.lua/style.lua/overlay/map_overlay/parser_hook；面板公共 API 签名不变（editor 现有调用必须继续可用）。

---

## 7. 验收标准

1. `luac -p`：editor_gui.lua / icon_picker.lua / layer_panel.lua 全过；改到的任何文件全过。
2. **设计系统合规**（静态可查）：editor_gui 重写的布局区**无裸 `GameFont`/`SetFont(数字)`/硬编码像素尺寸**；文字/按钮/输入框/分割线/标题均走 `T.Create*`；尺寸走 `Style.Scaled/Scale`；强调色走 `Style.Color`。icon_picker/layer_panel 同标准。
3. 三栏物理隔离：图层在左栏、属性在右栏，**无竖直叠压**；属性区每个 label 显式宽度，无同行文字相撞（读码核对锚点/宽度）。
4. 工具栏每个按钮有 atlas 图标(或降级首字)+ `GameTooltip`；图标工具点击确实打开 `IconPicker:Open`。
5. 面板公共 API 未变、data/canvas/style/播放链路零改动（`git diff` 核对）。
6. 无 `selectedElementID` 回潮、无 `RegisterColdFile`、无裸 print。

---

## 8. 红线

- 不改 data/canvas/spec_icons/style/播放链路；不改面板公共 API。
- 不用裸 CreateFrame+GameFont+硬编码尺寸做可见控件（容器 Frame 除外）。
- 不嵌套组、不碰时间轴/广播语义。
- 工具按钮不得无 tooltip。
