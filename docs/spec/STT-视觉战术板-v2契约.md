# STT 视觉战术板 — v2 契约（PPT 帧 morph + person 复合 + 4 元素）

> 状态：**v2 契约（冻结候选）**（2026-05-29）。本文**取代 v1**（`STT-视觉战术板-MVP契约.md`，建议归档 v1 到 `docs/spec/归档/`，本次不移动文件）。一旦冻结，成为本模块单一权威：所有实现 agent 必须严格按本契约的字段名、接口签名、文件归属落地。**禁止偏离签名、禁止兜底/同义字段映射（如 `a or b`）、禁止保留双版本（旧 element/step + 新 slide/morph）。**

---

## 0. v2 与 v1 的取代关系（先讲清继承与推翻）

v1 只攻"静态绘图编辑器 + 多选/组/图层 + 专精图标选择器"，并**明确保留不动**时间轴/播放/广播（`start_t/end_t/step` 模型、`overlay.lua` 静态渲染）。v2 用户已**授权拆除**旧时间模型与画布模型，本契约据此重做。

### 0.1 从 v1 继承（仍是单一权威，原样保留或微调）

| 继承项 | 来源 | v2 处置 |
|---|---|---|
| 多选 `selectedIDs` 集合 + `selectedGroupID` | v1 §7.1，已实现于 `editor_gui.lua` | **保留**，不回退单选 |
| 单层组（不嵌套） | v1 §0/§4.4 | **保留**，组 CRUD 接口签名不变 |
| 几何单一权威 `Data:GetElementBox` | v1 §4.1，已实现 | **保留为唯一几何源**，v2 扩展 person/shape 分支 |
| PPT 锚定缩放（锚定对边/对角，非中心×2） | v1 §7.2 | **保留**，作用于新元素形状 |
| `spec_icons` API 驱动、不硬编码 fileID | v1 §5，已实现 `SpecIcons:GetClasses/Search` | **保留原文件不动**，person 默认图标与图标选择器都复用 |
| 图标选择器（Figma 式网格 + 搜索） | v1 §8 `IconPicker` | **保留接口**，person 换图标也走它 |
| 文件归属矩阵零交叉 | v1 §1 | **保留铁律**，见本文件 §3 |
| 无裸 `print`，只走 `T.msg`/`T.debug` | v1 §2 | **保留** |
| `luac -p` 必过（防智能引号） | v1 §2 | **保留** |
| 源码不出现第三方竞品名 | v1 §2 | **保留** |
| 本分支无 `T.RegisterColdFile`（朴素模块模式） | v1 §2 | **保留**，新/改文件头尾逐字对照同目录现有文件 |
| `enUS` 本地化键集合权威，三语种一致 | v1 §7.6 | **保留**，过 `Tools/check_locale.sh` |
| 几何 DRY（canvas 不重复算尺寸） | v1 §6.3 | **保留并强化**：person 子件也只从 box 取尺寸 |

### 0.2 被 v2 推翻（彻底重做，破坏旧数据格式不迁移）

| 被推翻项 | v1 形态 | v2 形态 |
|---|---|---|
| **时间模型** | 每元素 `start_t/end_t/fade_in/fade_out` + `board.steps` + `element.step` | **删除**。改 `board.slides[]`（PPT 帧/关键帧），相邻帧自动补间。元素只存"几何 + 每帧覆写"，不再持有时间字段 |
| **元素模型** | 11 种：`slot/circle/square/line/arrow/text/icon/path/...` | **收敛为 5 种**：`person`/`icon`/`text`/`shape`/`marker`。`slot`、独立几何、`background` 元素、`path` 全废弃；`icon` 保留为纯图标控件，用于 Boss/职责/技能等非人员图标 |
| **画布模型** | 固定 1600×900 逻辑画布，渲染整画布 | **有界 artboard 框 + 框外无边草稿区 + 滚轮缩放 + 平移**；运行时只渲染框内 |
| **person 构成** | "圆 + 图标 + 文字"是 3 个**独立** element 拼出来（`ApplyMidnightfallTemplate` 里 `addUnit` 各加 3 个） | person 是**单个复合 element**，圆/图标/文字是它的内部子件，整体一个 ID、一次选中、一次移动 |
| **添加方式** | 顶部工具栏按钮逐个 add | **组件抽屉**（拖到画布），移除顶部添加按钮；person 预设按 `[人员]` 自动生成 |
| **图层面板行池** | `AcquireRow(self, index)` 按动态数字 index 复用（组折叠后 rows 长度变 → 行与数据错位） | **按稳定 ID（element.id / group.id）复用行**，修 SSOT bug |
| **运行时渲染** | `overlay.lua` `OnUpdate` 调 `renderer:Render(board, boardTime)`，`ResolvePosition` 忽略动画恒在基准位 | **按帧序播放 + 相邻帧补间平移**；新增 person 淡入。改 `overlay.lua` 的播放循环与 `canvas.lua` 的位置解析 |
| 旧模板入口 | `ApplyMidnightfallTemplate`（拼 3 件式 unit）、`ApplySlotTemplate` | **删除重写**为双帧 person 模板（图 1/图 2，见 §11） |
| 旧静态导出 hash | hash payload 含 `elements`，无 slides | 重写 hash payload 含 `slides`（见 §4.6） |

---

## 1. 名词与坐标约定（全局单一权威）

- **artboard（画板框）**：有界矩形，逻辑坐标系原点在框左上 `(0,0)`，宽高 `board.artboard.w/h`（默认 1600×900）。所有元素 `x/y` 都是 artboard 逻辑坐标。运行时只渲染框内（框外为编辑期草稿区，不播放）。
- **视口（viewport）**：编辑器画布 frame。`viewport.zoom`（缩放）+ `viewport.panX/panY`（平移）把 artboard 逻辑坐标映射到屏幕。**坐标换算是单一权威函数**（见 §8.1 `Canvas:BoardToScreen` / `Canvas:ScreenToBoard`），canvas/editor 一律调它，禁止各自再算。
- **slide（帧）**：离散关键帧，作者编排"图 1、图 2…"。`board.slides[]` 有序数组。
- **morph（补间）**：相邻 slide 之间，对**两帧都存在**的 person 做位置补间平滑平移；只在后一帧出现的 person 做淡入。
- **person 子件**：`text`（名签）/`icon`（专精图标）/`circle`（散圈），三者属于同一个 person element，不是独立 element。

---

## 2. 数据 schema（data-owner 权威，字段名冻结）

> 设计原则（本视角核心）：
> 1. **几何唯一锚点**：person 的 `x/y` 是图标中心，也是 circle 圆心；circle 不可独立偏移（`circle` 无 dx/dy）。text 用 `position`（上/下/左/右）+ `dx/dy` 相对锚点。整个 person 只有一个权威坐标。
> 2. **DRY 复用仅限 text**：person.text 的样式字段**逐字复用** `indicator_text` 的 style 字段集（`fontSize/fontFace/color/bold/outline/outlineColor/shadow/scale`，已核实存在）。person.circle **不复用** `indicator_circle`——后者是冷却扫描环 widget（`fillMode="drain"|"fill"`、四象限顶点遮罩），语义与"实心散圈"不符；person.circle 用自有干净字段集，渲染为简单填充圆/环。禁止造新的同义字段。
> 3. **零兜底**：升级即全局替换；`EnsureElementShape` 对每种 type 只规范化该 type 的字段，不写 `a or b` 同义合并。
> 4. **slide 覆写最小化**：元素的"基线几何"存在 element 上；slide 只存**每帧差异覆写**（per-slide overrides），避免每帧整份拷贝元素。

### 2.1 board（画板）

```lua
board = {
    id = "board-1",            -- string：稳定 ID
    name = "至暗之夜 P2 分散",  -- string：显示名
    version = 1,               -- number
    builtin = false,           -- boolean：内置模板只读
    received = false,          -- boolean：他人广播收到的
    created = <ts>, modified = <ts>,
    encounterID = 3183,        -- number|nil：绑定 boss（背景/触发用）
    bossKeyText = "...",       -- string：语义 boss key（广播/触发对接）
    bg = { type="texture", texture="...tga", name="...", encounterID=3183, instanceType="raid", instanceID=1308 } | nil,

    artboard = { w = 1600, h = 900 },   -- 有界画板框逻辑尺寸（取代旧 canvas）

    elements = { <element>, ... },      -- 基线元素数组（见 §2.2）；顺序无关，z 决定层叠
    groups   = { [groupID] = { id, name, hidden=false, locked=false }, ... },  -- 单层组（继承 v1）

    slides = {                          -- PPT 帧有序数组（取代旧 steps）
        { id = "slide-1", name = "图1 前三轮",  holdTime = 2.0, morphFromPrev = 1.2,  overrides = { [elementID] = <override>, ... } },
        { id = "slide-2", name = "图2 第四轮",  holdTime = 2.0, morphFromPrev = 1.2,  overrides = { ... } },
    },

    _nextElementID = 1,        -- number：自增 ID 游标
    _nextGroupID   = 1,
    _nextSlideID   = 1,
    hash = "...",              -- 内容指纹（去重广播）；payload 见 §4.6
}
```

> **`viewport` 不进 board**：缩放/平移是**编辑器会话态**，存在 `editor_gui` 本地或 `STT_VisualBoardsDB._viewport[boardID]`（与 overlay 的 `_overlay` 同级，UI 偏好不是方案数据），不污染可广播的 board 内容、不进 hash。

### 2.2 element（5 种，公共字段 + 分型 params）

公共字段（所有 type 共有）：

```lua
element = {
    id = "elem-1",     -- string：稳定 ID（"elem-N"）
    type = "person",   -- "person" | "icon" | "text" | "shape" | "marker"
    z = 10,            -- number：层叠序，越大越上
    x = 800, y = 450,  -- number：artboard 逻辑坐标（person=图标中心锚点；text=文字中心；marker=图标中心；shape=见下）
    scale = 1,         -- number：整体缩放（>0）
    rotation = 0,      -- number：度（person/marker/text/部分 shape 适用）
    name = nil,        -- string|nil：图层面板显示名；nil 时按 type 推导（person→slotName；text→文本；shape→shapeKind；marker→标记名）
    hidden = false,    -- boolean：编辑期隐藏（渲染跳过）
    locked = false,    -- boolean：编辑期锁定（不可命中，仍渲染）
    groupID = nil,     -- string|nil：所属单层组
    params = { ... },  -- 分型字段，见下
}
```

**(a) type = "person"** —— 复合控件，唯一中央锚点 = `element.x/y`（图标中心 = circle 圆心）：

```lua
params = {
    slotName = "咕咕2",    -- string：对接 [人员] 块的槽位名/昵称；编辑器显示它，运行时解析成真实 id
    highlightStyle = {     -- "这是我"高亮样式（运行时本机==解析 id 时套用），可自定义；nil=用内置默认
        scale = 1.25, glow = true, glowColor = "FFD200", desaturateOthers = false,
    } | nil,

    -- 子件 1：专精图标（默认自动渲染 [人员] 映射职业专精；可换其他图标）
    icon = {
        size = 40,                  -- number：图标边长（逻辑像素，未乘 element.scale）
        -- 图标来源单一权威：默认 nil → 运行时按 slotName 经 [人员图标] 映射出 specID → spec icon fileID。
        -- 作者用图标选择器、Boss 图标或 spellID 换图后，写下面其一（互斥，禁止同时存在）：
        encounterID = nil,          -- number|nil；Boss 图标来源，配合 encounterIcon 或内置 encounter override
        encounterIcon = nil,        -- number|nil；Boss 图标 fileID，优先于 encounterID 动态解析
        spellID = nil,              -- number|nil；优先经 C_Spell.GetSpellTexture / GetSpellTexture 解析贴图
        texture = nil,              -- number(fileID) | string(路径) | nil
        atlas   = nil,              -- string(atlas 名) | nil
        borderSize = 0, borderColor = { 0,0,0,0.95 },
    },

    -- 子件 2：圆底（默认浅绿 50% 不透明；圆心恒 = 图标中心，无 dx/dy）。person 自有字段，渲染为简单填充圆/环（不走 indicator_circle 冷却扫描环）。
    circle = {
        radius = 58,                -- number：半径（逻辑像素）
        color = "33CC66",           -- string hex：填充色
        alpha = 0.5,                -- number：不透明度（0-1）
        shapeStyle = "solid",       -- "solid"(实心填充圆) | "ring"(空心环)
        ringThickness = nil,        -- number|nil：ring 时的环厚
        enabled = true,             -- boolean：是否显示圆底
    },

    -- 子件 3：名签文本（内容=槽位名/解析结果；位置上下左右；复用 indicator_text 字段）
    text = {
        position = "top",           -- "top"|"bottom"|"left"|"right"（left/right 竖向生长）
        dx = 0, dy = 0,             -- number：相对锚点的额外偏移
        fontSize = 19,              -- number：复用 indicator_text.style.fontSize
        fontFace = "default",       -- 复用 indicator_text.style.fontFace（"default"|"FRIZQT"）
        color = "EFFFFF",           -- hex：复用 indicator_text.style.color
        bold = false,               -- 复用 indicator_text.style.bold
        outline = true,             -- 复用 indicator_text.style.outline
        outlineColor = "000000",    -- 复用 indicator_text.style.outlineColor
        shadow = true,              -- 复用 indicator_text.style.shadow
        textScale = 1,              -- 复用 indicator_text.style.scale
        justifyH = "CENTER",        -- "LEFT"|"CENTER"|"RIGHT"
        width = nil,                -- number|nil；多行/左对齐时可设逻辑宽度
        enabled = true,             -- boolean：是否显示名签
    },
}
```

> **person 的 DRY 红线**：`person.text.*` 的字段名与取值语义必须与 `indicator_text` 的 `style` 一一对应（已核实字段集存在）。新增 person 文本样式能力时，**先看 `indicator_text` 有没有该字段**，有就复用同名，没有才扩展（并同步两边）。`person.circle.*` 是 person 自有字段（不与 indicator_circle 对齐）。**严禁**出现 `fontSize` 与 `size` 这种同义双字段。

**(b) type = "text"** —— 独立文本：

```lua
params = {
    text = "门口",
    -- 直接复用 indicator_text.style 字段（与 person.text 同集合，去掉 position/dx/dy/enabled）
    fontSize = 40, fontFace = "default", color = "00FF8C",
    bold = false, outline = true, outlineColor = "000000", shadow = true, textScale = 1,
    justifyH = "CENTER", width = nil,
}
```

**(c) type = "icon"** —— 纯图标（Boss/职责/技能等非人员图标）：

```lua
params = {
    encounterID = nil, -- number|nil；Boss 图标来源，配合 encounterIcon 或内置 encounter override
    encounterIcon = nil, -- number|nil；Boss 图标 fileID，优先于 encounterID 动态解析
    spellID = nil, -- number|nil；优先经 C_Spell.GetSpellTexture / GetSpellTexture 解析贴图
    texture = 12345 | "Interface\\Icons\\..." | nil,
    atlas = "atlas-name" | nil,
    size = 54,
    shape = "circle", -- "circle"|"square"；纯 icon 默认圆形遮罩，用户可切方形
    borderSize = 0,
    borderColor = "000000",
}
```

`encounterID/encounterIcon`、`spellID`、`texture` 与 `atlas` 互斥；写 Boss 图标来源时清 `spellID/texture/atlas`，写 `spellID` 时清 `texture/atlas/encounterID/encounterIcon`，写 `texture/atlas` 时清 `spellID/encounterID/encounterIcon`。换图标走 `icon_picker.lua` 写入同一个 `params.texture`；模板中的种子图标直接存 `spellID=1253031`；鲁拉 Boss 纯图标直接存 `encounterID=3183, encounterIcon=7448204`，复用主干 Boss 图标口径，不使用本地 TGA 占位，也不额外叠红色背景圆。纯 `icon` 默认 `shape="circle"` 并用圆形遮罩裁切；`shape="square"` 时按方形显示。`person.params.icon` 默认仍为方形，不受纯图标默认圆形影响。

文本控件：未设置 `width` 时，文本框按内容自适应；设置 `width` 后按该逻辑宽度自动换行，不允许因为复用旧宽度显示省略号。`Data:GetElementBox(text)` 应按文本内容/width 返回可命中的文本框尺寸。

**(d) type = "shape"** —— 形状（合并旧 square/circle/line/arrow）：

```lua
params = {
    shapeKind = "rect",        -- "rect" | "circle" | "line" | "arrow"
    color = "FFFFFF", alpha = 0.85,
    -- rect：以 x/y 为中心，w/h
    w = 1240, h = 14,
    -- circle：以 x/y 为圆心，radius；shapeStyle="solid"|"ring"，ringThickness（ring）；与 person.circle 同套自绘字段
    radius = 60, shapeStyle = "solid", ringThickness = nil,
    -- line/arrow：x/y=起点，end_x/end_y=终点（存在 element 顶层 end_x/end_y）
    thickness = 3, arrowSize = 22,
}
-- line/arrow 专用：element.end_x / element.end_y（number），其余 type 无此字段
```

属性面板必须将 `shapeKind` 暴露为直接选择控件（矩形 / 圆形 / 线段 / 箭头），不能只靠顺序轮换。切换后统一走 `Data:UpdateElement` 与数据规范化入口：`rect/circle` 清 `end_x/end_y`，`circle` 补 `radius`，`line/arrow` 补 `end_x/end_y/thickness/arrowSize`。`shapeKind` 只允许 `rect/circle/line/arrow`；历史或外部导入写入非法值（如 `person`）时必须规范化为 `rect`，UI 不得出现 `shapeKind=person` 选项。

**(e) type = "marker"** —— 暴雪 8 大团队标记：

```lua
params = {
    markerIndex = 3,   -- 1-8（1星 2圆 3钻 4三角 5月 6方 7叉 8骷髅）
    size = 54,         -- number：边长
}
```

> **废弃确认**：`slot` 并入 person（slot 的"圆+名签+标记"语义由 person 覆盖，标记单独用 marker 元素）；`square/circle/line/arrow` 并入 shape；`path` 直接删；`background` 不再是 element（背景是 `board.bg`）。`EnsureElementShape` 遇到这些旧 type 一律剔除（破坏旧数据，不迁移）。`icon` 是正式纯图标元素，不再作为旧 type 剔除。

### 2.3 slide override（每帧差异覆写，最小化存储）

slide 不整份拷贝元素，只存"该帧相对基线的差异"。override 的合法字段（**白名单**，超出的忽略）：

```lua
override = {
    x = 700, y = 200,     -- number|nil：该帧位置（缺省=用元素基线 x/y）
    hidden = true,        -- boolean|nil：该帧是否不出现（用于"图1没有、图2才有"的人员）
    scale = 1.1,          -- number|nil：该帧整体缩放
    -- 仅此白名单。颜色/文本/半径等"样式"不做逐帧覆写（MVP 不需要；要改样式改基线）。
}
```

> **设计取舍（重要）**：morph 只补间**位置**（`x/y`）与淡入淡出（由 `hidden` 派生）。不补间颜色/字号/半径——这些是元素恒定属性。这样 morph 数学只有一种（线性插值 x/y + alpha），单一权威，零特例。若未来要补间更多维度，扩 override 白名单 + 在 §6 插值函数加维度，但**当前冻结只补位置**。
>
> **"图1有、图2新增"的人员**：该 person 的 element 一直在 `board.elements`；在它"还没出现"的 slide 里，override `hidden=true`；在它"出现"的 slide 里不 hidden。播放跨过它首次出现的帧时做淡入（见 §6.3）。

### 2.4 EnsureElementShape / EnsureBoardShape 规范化义务

- `EnsureBoardShape`：保证 `artboard.w/h`、`elements[]`、`groups{}`、`slides[]`（至少 1 帧；无则建 `slide-1`）、`_nextElementID/_nextGroupID/_nextSlideID`。剔除悬空组（无成员）、剔除引用了不存在 elementID 的 slide override。
- `EnsureElementShape`：按 type 分发，每 type 只规范化该 type 字段；person 三子件各自规范化（缺子件补默认、`enabled` 布尔化、互斥的 `icon.texture`/`icon.atlas` 若同时存在则**报 debug 并清空 atlas 保留 texture**——这是规范化不是兜底，违反互斥即数据非法）。`name` Trim 空串归 nil。

---

## 3. 文件归属矩阵（铁律：零交叉）

| 归属 | 文件 | 角色 | 改/新/删 |
|---|---|---|---|
| **data-owner** | `visual_board/data.lua` | 重写 schema（4 元素+slide+artboard）、slide CRUD、morph 数据接口、person 复合 CRUD、组、几何权威 | 改（大改） |
| **data-owner** | `visual_board/spec_icons.lua` | 专精图标数据源 | 不改（保留） |
| **data-owner** | `visual_board/person_resolver.lua` | 新文件：person.slotName → specID（编辑期，经 `info.slotVisualSpecs`）→ 默认图标；slotName → 真实 id + 本机判定（运行时，经 `Template.ResolveSlotAtRuntime`/`NormalizePlayerName`）。**单一权威桥接 stn_template**，禁止重造解析 | 新 |
| **canvas-owner** | `visual_board/canvas.lua` | 重写渲染：4 元素 + person 复合渲染、坐标换算权威（zoom/pan）、morph 插值位置消费、选择/手柄、对齐吸附线 | 改（大改） |
| **runtime-owner** | `visual_board/overlay.lua` | 重写播放循环：按 slide 帧序播放 + 相邻帧补间 + 淡入；运行时 person 高亮 | 改 |
| **panels-owner** | `visual_board/component_drawer.lua` | 新文件：组件抽屉（复用 skill_drawer 交互），自动 person 预设（按 [人员]），拖到画布 | 新 |
| **panels-owner** | `visual_board/icon_picker.lua` | 图标选择器（person 换图标 + shape 不用） | 改（接 person） |
| **panels-owner** | `visual_board/layer_panel.lua` | 重写行池：按稳定 ID 复用（修 SSOT）；分组 + 组头批量编辑 | 改 |
| **editor-owner** | `visual_board/editor_gui.lua` | 集成中枢：slide 时间条/帧编辑、person 属性面板、无边画布交互（滚轮/中键/空格拖拽）、挂载抽屉/图标选择器/图层、键位、移除顶部添加按钮 | 改（大改） |
| **editor-owner** | `visual_board/slide_bar.lua` | 新文件：底部 slide 帧条（增/删/排序/重命名/选中当前帧/morph 时长/holdTime 停留时长） | 新 |
| **editor-owner** | `load.xml`、`locale/enUS.lua`/`zhCN.lua`/`zhTW.lua`、`core/gui.lua`（仅帮助文本） | 加载注册顺序、本地化、帮助文本 | 改 |
| **runtime-owner** | `core/timeline_runner.lua`（仅 §10 集成点） | 时间轴 `{board:...}` 调用 `VisualBoardOverlay:PlayByRef(ref, offset, { bossKeyText = scheduler.bossKeyText })`，按当前 Boss 优先解析同名画板 | 微调 |
| **docs-owner** | `docs/战术方案编写指南.md`、`简介_STT.html`（中英）、`core/gui.lua` 帮助文本 | 文档同步 | 改 |

> `map_overlay.lua` 已删（不在矩阵）。`parser_hook.lua`：仅当 board 引用/合并语义不变则不动；若 slide 影响序列化已在 data.lua 内处理，则 parser_hook 不改。
> **除归属人外不得写其归属外文件**；跨文件只经本契约 `T.*` 接口。`load.xml`/`locale/*`/`core/gui.lua` 仅 editor-owner 改（docs-owner 只改帮助文本字面量，需与 editor-owner 协调键名）。

---

## 4. data.lua 冻结接口（data-owner）

> 所有改数据的函数走现有撤销栈（`DoCommand`/`CommitBatch`），Ctrl+Z 可回退。data 不持有选择态。

### 4.1 几何单一权威（扩展 v1）

```lua
-- 返回元素在 artboard 逻辑坐标下的包围盒尺寸与形状语义。canvas 命中/手柄、editor 缩放锚点唯一来源。
-- 返回: w, h, shape  其中 shape ∈ "rect"|"radial"|"text"|"segment"|"person"
--   person : 取 person 整体外接盒（含 circle 半径、icon、名签 position 偏移的并集），shape="person"
function Data:GetElementBox(element)  --> w, h, shape

-- person 专用：返回各子件在 artboard 逻辑坐标下相对锚点 (element.x,element.y) 的局部布局。
-- canvas 渲染 person 三子件、命中 person 都只调它，禁止 canvas 自己算名签该放哪。
-- 返回: { icon={size}, circle={radius,enabled}, text={ox,oy,vertical,enabled} }
--   text.ox/oy = 名签中心相对锚点的偏移（已综合 position + dx/dy + icon/circle 尺寸）
--   text.vertical = (position=="left" or "right")
function Data:GetPersonLayout(element)  --> layout
```

### 4.2 元素 CRUD（5 种）

```lua
function Data:AddElementAt(boardID, type, x, y, fields)   --> element|nil  -- type∈4种；person 默认三子件
function Data:AddPersonAt(boardID, slotName, x, y)        --> element|nil  -- 便捷：建 person 并写 slotName（图标默认自动）
function Data:UpdateElement(boardID, elementID, fields)                    -- 深层覆写 params（含 person 子件）
function Data:DeleteElement(boardID, elementID)
function Data:DuplicateElement(boardID, elementID, dx, dy) --> element|nil
function Data:GetElement(boardID, elementID)              --> element, board
```

> `UpdateElement` 的 `fields` 支持嵌套 person 子件覆写，例如 `{ person = { circle = { radius = 70 } } }`（仅覆写给出的叶子字段，未给的不动；这是"部分更新"不是"兜底合并"）。具体嵌套写法由 data-owner 定，但**禁止**用同义字段。

### 4.3 多元素 / 组（继承 v1，签名不变）

```lua
function Data:MoveElements(boardID, elementIDs, dx, dy, transient)
function Data:ScaleElements(boardID, elementIDs, factor, originX, originY, transient)
function Data:SetElementFlag(boardID, elementID, flag, value)   -- "hidden"|"locked"
function Data:SetElementName(boardID, elementID, name)
function Data:SetElementOrder(boardID, orderedIDs)              -- 数组首=最上层
function Data:CreateGroup(boardID, elementIDs, name) --> groupID
function Data:Ungroup(boardID, groupID)
function Data:GetGroup / GetGroupMembers / SetGroupFlag / RenameGroup ...   -- 同 v1
-- 组头批量编辑（§9.2）：
function Data:BatchUpdateGroup(boardID, groupID, fields)   -- 对组内全部 person 套用同一 fields（如统一 circle.radius）；一条撤销
```

### 4.4 slide CRUD（取代 step）

```lua
function Data:AddSlide(boardID, name)            --> slide, index   -- 新帧默认 morphFromPrev=1.0，overrides 空
function Data:DeleteSlide(boardID, slideIndex)                      -- 至少保留 1 帧
function Data:RenameSlide(boardID, slideIndex, name)
function Data:ReorderSlides(boardID, orderedIDs)                    -- 帧条拖拽排序
function Data:SetSlideMorph(boardID, slideIndex, seconds)          -- morphFromPrev（与上一帧的补间时长）
function Data:GetSlide(boardID, slideIndex)      --> slide, index
function Data:GetSlideCount(boardID)             --> n

-- 写当前帧的覆写（编辑器"在帧 i 下拖动 person/改隐藏"时调用）。key ∈ override 白名单(§2.3)。
-- value=nil 表示清除该覆写（回落到元素基线）。撤销可回退。
function Data:SetSlideOverride(boardID, slideIndex, elementID, key, value)

-- 取"元素在帧 i 的有效值"（基线 + 该帧 override 合并后的结果），供编辑器渲染当前帧用。
-- 这是 override 合并的单一权威；编辑器/canvas 不得自己合并。
function Data:ResolveElementAtSlide(element, slideIndex, board)  --> { x, y, hidden, scale }
```

### 4.5 person 默认图标桥接（编辑期）

```lua
-- person 没写 icon.texture/atlas 时，按 slotName 推默认专精图标 fileID（经 person_resolver:ResolveSpecID(info, slotName) + spec_icons）。
-- info = 当前方案的 PreprocessText 结果（含 slotVisualSpecs），由调用方注入（见 §5）。
-- 返回 fileID 或 nil（无映射则 nil，canvas 落到问号图）。编辑期与运行时渲染都调它。
function Data:ResolvePersonDefaultIcon(element, info)  --> fileID|nil
```

### 4.6 导出 / hash（重写 payload）

- `ComputeBoardHash` 的 payload 改为 `{ artboard, bg, elements, groups, slides }`（移除旧 `duration/elements-only`）。
- `ExportBoardString`/`ImportBoardString`/`MergeReceivedBoards`：序列化整 board（含 slides）。导出版本号升到 **`STT-VBOARD:2:`**（破坏旧串不兼容、不迁移）。`ImportBoardString` 见到 `version==1`（或解析出已废弃 type `slot/square/path`、缺 `slides`）时**直接返回 `false, "legacy_unsupported"` 并 `T.msg` 明确提示"旧版视觉方案串不再支持"**——禁止静默规范化吞掉旧串产出残废 board。
- Boss 整包格式为 **`STT-VBOARD-BOSS:1:`**，由 `BuildBossBoardPackage(bossKeyText)` / `ExportBossBoardsString(bossKeyText)` 生成。包内包含同一 `bossKeyText` 下全部 board，每张 board 保留 `artboard/bg/elements/groups/slides/hash`，不包含 `_viewport` 等编辑器会话态。
- `ImportBossBoardsString(text, sender)` / `ReplaceBossBoards(package, sender)` 只覆盖 `package.bossKeyText` 对应的本地画板集合：先删除本地同 Boss 画板，再为包内每张画板分配新的本地 `boardID`。其它 Boss 不受影响；播放引用仍按 `{board:画板名}` 匹配。

---

## 5. person_resolver.lua（data-owner，新文件，桥接单一权威）

```lua
T.VisualBoardPersonResolver = {}

-- 编辑期：slotName → specID → 交给 spec_icons 取 fileID。
-- specID 来源是 stn_template.PreprocessText 解析出的 info.slotVisualSpecs[slotName]（来自方案 [图标] 段，作者手填 key=specID）；
-- 该表是 PreprocessText 的局部产物，须由调用方传入当前方案 info，resolver 不重造解析、不自行推导职业→specID。
-- 无映射则返回 nil（canvas 落问号图）。
function T.VisualBoardPersonResolver:ResolveSpecID(info, slotName)  --> specID|nil

-- 运行时：slotName → 真实角色 id（咕咕2→咕咕玩家）。
-- 转调已导出的 Template.ResolveSlotAtRuntime(slotValue)——注意它吃的是 info.slots[slotName] 的 value（非 slotName 本身），
-- 返回 string 或 table（空格并集组返回数组）。person.slotName 契约保证单人槽位；
-- 若返回 table（并集组），视为非法 slotName：T.debug 告警并降级显示原 slotName，不当正常行为静默取第一个。
function T.VisualBoardPersonResolver:ResolveRealName(info, slotName)  --> realName

-- 运行时：该 person 是否本机玩家。= NormalizePlayerName(ResolveRealName) == NormalizePlayerName(本机名)。
-- 复用已导出的 Template.NormalizePlayerName + Template.ResolveSlotAtRuntime；不复制规范化逻辑。
function T.VisualBoardPersonResolver:IsSelf(info, slotName)  --> boolean
```

> **红线**：本文件**只做转调与查表**，`ResolveSlotAtRuntime`/`NormalizePlayerName` 的真实逻辑留在 `stn_template.lua`（均已导出为 `Template.*`，直接调）。`slotVisualSpecs` 是 `Template.PreprocessText` 的局部产物，resolver 不自行解析方案文本、不推导职业→specID。
> **导出口待办**：若后续需要单独的"在场"判定（`IsPlayerInCurrentGroup`，stn_template 内 local 未导出），须由 runtime-owner 协调 stn_template-owner 增加导出口 `Template.IsPlayerInCurrentGroup = IsPlayerInCurrentGroup`，**禁止复制函数体**；但本机判定（IsSelf）只用 `NormalizePlayerName` 比对，不依赖该导出口。

---

## 6. slide 关键帧 morph 模型（编辑 + 运行时 + 集成）

### 6.1 编辑期（editor + slide_bar）

- 底部 `slide_bar` 列出所有帧（图1、图2…），点击选中"当前编辑帧" `editor.currentSlideIndex`。
- 画布渲染"当前帧的有效快照"：对每个元素调 `Data:ResolveElementAtSlide(element, currentSlideIndex, board)` 得到该帧 `x/y/hidden/scale`，再渲染。
- 在帧 i 拖动一个 person → `Data:SetSlideOverride(boardID, i, elementID, "x"/"y", newVal)`（写**当前帧**的覆写，不动其它帧、不动基线）。
- "某 person 这帧不出现" → 在该帧 `SetSlideOverride(..., "hidden", true)`。
- `morphFromPrev`（秒）：该帧相对上一帧的补间时长，可在帧条调。
- **编辑器内预览整段 morph**：编辑器提供"预览播放"按钮，不进战斗即可看图1→图2 过渡。其驱动一个本地计时器走与 overlay 同一套时间线/插值逻辑（morph 数学单一权威，editor 与 overlay 共用，不各自重算），仅播放、不触发任何运行时副作用（不解析真实 id、不判本机）。

> **基线 vs 覆写的取舍**：元素**首次创建**写在基线（`element.x/y`）。编辑器策略：**第一帧（slide-1）的拖动直接改基线**（因为 slide-1 无"上一帧"，其覆写等价于基线）；**第二帧起的拖动写该帧 override**。这样常见"图1摆好位 → 加图2只挪动几个人"流程下，图2 override 只含被挪动的人，存储最小。此策略由 editor-owner 实现，data 层两条路径都支持（基线写 `UpdateElement`，覆写写 `SetSlideOverride`）。

### 6.2 运行时播放时间线（overlay 重写）

播放参数：`slides[]` + 每帧 `morphFromPrev`。时间线构造（单一权威，在 overlay 内）：

```
帧 i 的“到位时刻” arriveAt[i]：
  arriveAt[1] = 0
  arriveAt[i] = arriveAt[i-1] + slides[i-1].holdTime + slides[i].morphFromPrev
（slides[i].holdTime = 该帧停留时长；morphFromPrev = 补间段时长）
```

播放循环（`OnUpdate`，boardTime = 已播秒数）：

1. 定位当前处于"第 i 帧停留段"还是"i→i+1 补间段"。
2. **停留段**：渲染帧 i 快照（`ResolveElementAtSlide(*, i)`）。
3. **补间段（i→i+1，进度 p∈[0,1]）**：对每个元素：
   - 两帧都"出现"（均非 hidden）：位置 `lerp(posAt_i, posAt_{i+1}, p)`，alpha=1。
   - 仅 i+1 出现（i 帧 hidden）：固定在 i+1 位置，alpha 从 0→1 淡入（新增 person 淡入）。
   - 仅 i 出现（i+1 帧 hidden）：固定在 i 位置，alpha 从 1→0 淡出。
4. 播到最后一帧停留结束 → 停在末帧（或按 `Play` 的 offset/loop 策略；MVP 停末帧，不循环）。

> **morph 数学唯一**：只有"位置 lerp + alpha 线淡"。`lerp`/`alpha` 计算封装为单一 helper，editor 预览与 overlay 播放共用，禁止散落。位置插值用的"帧 i 有效位置"必须经 `Data:ResolveElementAtSlide`，不在 overlay 重算覆写合并。
>
> **holdTime 可配性结论**：`holdTime` 提升为 **per-slide 字段**（`slide.holdTime`，与 `morphFromPrev` 并列，默认 2.0s），**不做 board 级全局常量**。理由：(a)时间参数全在 slide 上，单一权威，overlay 不持有任何时长常量；(b)作者能给"需盯久的帧"单独调停留；(c)slides 已在 §4.6 hash payload 内，holdTime 自然进指纹，无遗漏。slide_bar 在帧条上提供 holdTime 输入（与 morphFromPrev 同处）。MVP 不暴露"每帧停留再细分到每元素"的可配性（无需求）。

### 6.3 canvas 对运行时的支持

`Canvas:Render(board, renderState, opts)` 的 `renderState` 取代旧 `timeValue`：

```lua
renderState = {
    mode = "play",                  -- "play" | "edit"
    -- play 模式：每元素的"已解算位置/alpha/scale"由 overlay 算好传入，canvas 不碰 slide：
    resolved = { [elementID] = { x, y, alpha, scale, self=bool }, ... },
    -- edit 模式：canvas 调 Data:ResolveElementAtSlide(*, opts.currentSlideIndex) 自己解算当前帧，
    --   并叠加选择/手柄/吸附线（见 §8）。
    currentSlideIndex = 1,
}
```

> 这样**morph 计算只在 overlay（play）**，**当前帧解算只在 data（ResolveElementAtSlide）**，canvas 永远只做"给我位置我画"，三者职责单一。`self=true` 时 canvas 对该 person 套用 highlightStyle（§10）。

### 6.4 timeline 集成点

`timeline_runner.lua:1845` 的 `T.VisualBoardOverlay:PlayByRef(invoke.boardRef, invoke.offset, { source = "timeline", bossKeyText = scheduler.bossKeyText })` 按画板名播放。`Data:ResolveBoardRefForBoss(ref, bossKeyText)` 优先匹配当前方案 Boss 下的同名画板；找不到时才退回旧的全局同名匹配并写 debug。`Overlay:Play(boardID, offset, opts)` 内部按帧序+补间播放，`offset` 含义=从 boardTime=offset 处开始播（落到对应帧/补间段）。

### 6.5 组件抽屉的人员预设（无激活方案时的行为）

- 人员预设区按当前激活方案的 `[人员]` 段自动生成（数据源经 `Note:GetActivePlan()` → `Template.PreprocessText` 拿 `info.slots`，**复用此单一权威入口**，不另写"当前方案"读取逻辑）。
- **无激活方案 / 方案无 `[人员]` 段时**：人员预设区显示空状态提示（走 locale 键，如"请先选择战术方案"），不报错、不留空白歧义。
- 用户仍可从抽屉拖通用 person 预设入画布：落点经 `Canvas:ScreenToBoard` 换算后调 `Data:AddPersonAt`，`slotName` 留空由作者手填，图标落问号图。预设拖出后的 `slotName` 绑定方式 = 预设携带的槽位名直接写入新 person 的 `params.slotName`（通用预设则为空串）。

---

## 7. person 复合控件模型（canvas 渲染 + 单一锚点）

- person 一个 element、一个 hitFrame、一次选中、一次拖动（拖 person → 改 `element.x/y` 或当前帧 override，三子件随动）。
- canvas 渲染 person：
  1. 调 `Data:GetPersonLayout(element)` 拿三子件局部布局。
  2. circle（若 enabled）：圆心 = person 屏幕锚点，半径来自 layout；`shapeStyle="solid"` 画简单填充圆纹理，`"ring"` 画空心环（`ringThickness`）；颜色/alpha 来自 `params.circle`。**不走 indicator_circle 冷却扫描环**。
  3. icon：中心 = person 屏幕锚点；贴图 = `params.icon.texture/atlas` 互斥取一，否则 `Data:ResolvePersonDefaultIcon`。
  4. text（若 enabled）：中心 = 锚点 + `layout.text.ox/oy`；left/right 时按 utf8 单字竖排。竖排切字的 `SplitUTF8Chars` 当前是 `indicator_circle.lua` 内 local——**拍板：提取到 `core/widget_api.lua` 作 `T.SplitUTF8Chars(s)`（归 widget_api owner）**，`indicator_circle` 与 canvas 都改调 `T.SplitUTF8Chars`，禁止两份实现、禁止"各自实现"退路。
- person 子件**不注册独立 hitFrame**；选 person 选整体。"换图标"在属性面板点按钮 → `IconPicker:Open`。

> 复用边界（已查证）：仅 `indicator_text` 的 **style 字段集**被 person.text 复用（不复用其 Acquire/Release 实例池，避免拖进倒计时/glow 耦合，在 canvas 现有 fontString 池里画）。`indicator_circle` 是冷却扫描环 widget（`fillMode="drain"|"fill"`、四象限遮罩），与 person 散圈语义不符，**person.circle 字段与渲染都自成一套，不复用 indicator_circle**。这是"复用 text 数据契约、circle 自绘"，避免耦合，仍 DRY。

---

## 8. 无边画布（artboard 框 + 缩放 + 平移 + 对齐吸附）

### 8.1 坐标换算单一权威（canvas）

```lua
-- viewport: { zoom, panX, panY }（editor 持有会话态，渲染前传给 canvas）
function Canvas:BoardToScreen(board, viewport, x, y)  --> screenX, screenY
function Canvas:ScreenToBoard(board, viewport, screenX, screenY)  --> boardX, boardY
```

所有命中/手柄/拖拽/吸附的坐标换算唯一经这两个函数（取代 v1 的 `ScalePoint`/`CursorToBoardPoint` 散算）。

### 8.2 交互（editor）

- **滚轮缩放**：以光标为锚点缩放（`zoom` 变化时调整 `panX/panY` 使光标下的 board 点不动）。zoom 范围限幅（如 0.2–4）。
- **平移**：中键拖拽 或 空格+左键拖拽 → 改 `panX/panY`。
- **artboard 框**：画一个边框表示有界画板（框外是草稿区，半透明遮罩区分）。运行时只渲染框内（框外元素 play 时裁掉/不渲染）。
- **viewport 持久化**：存 `STT_VisualBoardsDB._viewport[boardID]`，不进 board 内容/hash。

### 8.3 对齐线 / 吸附（Figma 级）

- 拖动元素时，与"其它元素的中心/边、artboard 中线"比较，距离 < 阈值（屏幕像素，如 6px）时显示对齐参考线并吸附。
- 吸附计算在 editor 拖拽回调内，用 `Data:GetElementBox` 取盒、`Canvas:BoardToScreen` 取屏幕坐标，画参考线走 canvas 的一个轻量接口 `Canvas:DrawAlignGuides(lines)`（lines=屏幕坐标线段数组；空数组=清除）。
- `shapeKind="line"|"arrow"` 选中后显示起点/终点两个端点手柄；拖起点只写 `x/y`，拖终点只写 `end_x/end_y`，不走普通整体移动，交互对齐 Keynote/PPT 线段端点编辑。
- 吸附维度：artboard 左/中/右、上/中/下；其它元素左/中/右、上/中/下。边/中心尺寸只从 `Data:GetElementBox` 取。
- Shift 拖拽约束：普通拖拽与线/箭头端点拖拽均按水平、垂直、45 度方向约束。

### 8.4 编辑生产力控件

- 方向键微调选中元素：普通 1 逻辑单位，Shift 10 逻辑单位；slide1 走 `Data:MoveElements`，slide2+ 写当前帧 `SetSlideOverride`。
- 旋转手柄：非线段元素选中时显示旋转手柄；slide1 写基线 rotation，slide2+ 写当前帧 `rotation` override；Shift 旋转吸附到 15 度。
- 多选右栏提供对齐/分布/统一尺寸：左/中/右、上/中/下、横/纵分布、同宽/同高；位置仍复用 `MoveElements` / `SetSlideOverride`，尺寸只写现有 params 字段。

---

## 9. 图层面板 SSOT 修复 + 分组批量编辑（panels-owner，重写 layer_panel）

### 9.1 SSOT 根因与修复

- **根因**（现状 `layer_panel.lua`）：`AcquireRow(self, index)` 用**运行序号 index** 作行池 key（line 196/307）。组折叠/展开会改变 `rows` 数组长度与顺序，同一个物理 row frame 在不同 Refresh 里被绑到不同 model，残留的 OnClick/rename editbox/眼睛锁状态可能错位 → 行与数据对不上。
- **修复**：行池**按稳定 ID 复用**——`rowPool[stableKey]`，`stableKey = "g:"..groupID` 或 `"e:"..elementID`。每次 Refresh：算出可见行模型列表（含稳定 key），为每个 model 取/建对应 stableKey 的 row，重写其全部绑定，按顺序 `ClearAllPoints` 重新锚定；本轮未用到的 row `Hide()`。`collapsed` 折叠态按 groupID 存（已有）。这样"行 ↔ 数据"恒由 ID 绑定，长度变化不再错位。

### 9.2 分组 + 组头批量编辑

- 图层面板按"组（可折叠）+ 顶层元素"自顶向下列出（z 大在上）。
- **组头**：显示组名（双击改名）、眼睛、锁，外加**批量编辑入口**：点组头的"批量"按钮 → 弹出小面板，对组内全部 person 批量改同一属性（如统一 `circle.radius`、统一 `circle.color`、统一 `text.fontSize`）→ 调 `Data:BatchUpdateGroup`（一条撤销）。
- 行的"显名"双击改名走 `Data:SetElementName`/`RenameGroup`；眼睛走 `SetElementFlag`/`SetGroupFlag` hidden；锁走 locked；拖拽重排走 `SetElementOrder`/`ReorderSlides`（组与元素层级内重排）。

```lua
T.VisualBoardLayerPanel:Create(parent) --> frame
T.VisualBoardLayerPanel:SetCallbacks(callbacks)   -- GetBoardID/GetSelectedIDs/GetCurrentSlideIndex/OnSelect/OnBatchEdit
T.VisualBoardLayerPanel:Refresh()
```

---

## 10. 运行时 slotName 解析 + 本机高亮（runtime-owner）

- overlay 播放前，对每个 person 调 `PersonResolver:ResolveRealName(slotName)` 得真实 id 作显示文本（**运行时显真实 id**，编辑器显 slotName）。
- 调 `PersonResolver:IsSelf(slotName)` 判本机；为真则该 person 在 `renderState.resolved[id].self=true`，canvas 套用 `params.highlightStyle`（缺省=内置默认：放大 + 描边/glow）。
- 解析全部经 person_resolver 转调 stn_template，**禁止 overlay/canvas 自己解析名字**。
- **highlightStyle 配置位置**：在 person 属性面板（§7 提到的属性面板）提供"本机高亮样式"编辑入口（`scale`/`glow`/`glowColor` 用 widget_api 控件改，`desaturateOthers` 开关）；`params.highlightStyle = nil` 时走内置默认（放大 + 描边/glow）。运行时 `self=true` 才套用，编辑期可在属性面板预览样式但不联动本机判定。

---

## 11. 验收：内置模板还原（验收 agent + 主控）

“生成模板”按钮一次生成 9 个画板，均使用 encounterID=3183 背景与 `visual_board/data.lua` 的模板 helper；P1/P1.5/P2分担/P3时钟站位法/P3-3星座吸球为独立单帧板，P2转P3、P3-1左右分组、P3-2左右分组为双帧 morph。

**单帧「P1流程图」**：
- 背景：紫色至暗竞技场（`bg` 3183）。
- text：顶部白色标题"P1流程图"；底部绿色"门口"和"这一侧是门口"；逐字还原 1-7 的流程批注。
- icon：鲁拉 Boss 图标与坦克盾牌图标。
- shape：三处"大团"圆、白/绿箭头。
- marker：紫钻(3)、绿三角(4)、红叉(7)、骷髅(8)、钱币/圆(2)、黄星(1)。

**单帧「P1.5站位图」**：
- 背景：紫色至暗竞技场（`bg` 3183）；本图不放白色十字矩形。
- text：顶部白色标题"P1.5站位图"；底部绿色"门口"。
- marker：紫钻、绿三角、红叉、骷髅、钱币、黄星、月亮。
- icon：玩家身上的种子图标，使用 spellID `1253031` 解析贴图。
- person（20，专精图标 + 名签；本图关闭浅绿散圈）：增辉1、噬灭1、咕咕2、LR1、SS1、DK1、DK2、奶德2、JLM1、LR2、ZST1、AM1、CJQ1、奶德1、冰法1、SS2、增辉2、元素1、DKT1、奶萨1。

**单帧「P2分担示意图」**：
- 背景/十字/门口同上。
- text：左上白色标题"P2分担示意图"；局部组合标注"SS1咕咕2"。
- marker：紫钻、绿三角、红叉、骷髅、钱币、黄星、月亮。
- icon：玩家身上的种子图标，使用 spellID `1253031` 解析贴图。
- person（20，专精图标 + 名签；本图关闭浅绿散圈）：JLM1、元素1、奶德2、增辉1、奶德1、LR1、SS2、冰法1、增辉2、噬灭1、SS1、咕咕2、LR2、DK1、DK2、DKT1、CJQ1、ZST1、AM1、奶萨1。

**slide-1「P2前三轮分散示意图」（20人，前三轮紧密团簇）**：
- 背景：紫色至暗竞技场（`bg` 3183）。
- text：顶部白色标题"P2前三轮分散示意图"；底部绿色"门口"。
- shape：中央白色十字（rect 横 + rect 竖）。
- marker：中心附近 紫钻(3)/绿三角(?)/红叉(7)/骷髅(8)/黄三角 等（按图位摆）。
- person（20，circle 浅绿 + 专精图标 + 名签）：奶德2、奶德1、冰法1、增辉1、LR1、噬灭1、SS1、SS2、DK1、DK2、增辉2、元素1、咕咕2、DKT1、ZST1、AM1、奶萨1、LR2、JLM1、CJQ1。

**slide-2「P2第四轮分散示意图」（20人，第四轮铺成网格）**：
- 同背景/十字/门口。
- marker：紫钻/绿三角/红叉/骷髅/金币ZST(用 person 还是 marker 由实现定，金币=钱标可用文本)/月亮。
- person（20）：与 slide-1 同一批，仅位置散开成网格（噬灭1、SS2、冰法1、DK1、增辉1、LR1、奶德1、奶德2、SS1、AM1、DK2、LR2、咕咕2、DKT1、元素1、ZST1、增辉2、JLM1、奶萨1、CJQ1）。

**双帧 morph 验收**：
- slide-1 与 slide-2 均为同一批 20 人，slide-1→slide-2 播放时全员**平滑平移**（前三轮团簇 → 第四轮网格的位置 morph）。
- person 两帧都显示、不再隐藏淡入；仅 title/moon 仍用 `hidden` 覆写区分帧。

**单帧「P3时钟站位法」**：
- 背景：紫色至暗竞技场（`bg` 3183）；本图不放白色十字矩形。
- text：顶部白色标题“时钟站位法”；底部绿色“门口”；底部说明“BOSS的位置即为12点钟方向”等 5 行文案。
- shape/icon：左右两个白色大时钟圈；每圈顶部放鲁拉 Boss 图标；绿色时钟数字 12/10/9/8/6/4/3/2。
- person（左右各 10）：左圈 DK1、ZST1、LR2、噬灭1、咕咕1、元素1、SS1、JLM1、增辉1、奶德2；右圈 DK2、DKT1、CJQ1、冰法1、增辉2、LR1、SS2、奶德1、AM1、奶萨1。

**双帧「P3-1左右分组」**：
- slide-1 帧名 `05:48/05:50`，顶部文案“P3-1”“05:48左吸球”“05:50右星座”；左侧标注“左/中/右”和“左吸球时找对自己的球即可”；右侧四行星座说明。
- slide-2 帧名 `06:08/06:10`，顶部文案“06:08左星座”“06:10右吸球”；两侧保留同一批人员，按 slide override 平移；新增“06:31 左增辉1开种子 / 右LR1开种子”等提示。
- 形状：黄色星座/吸球圈、紫色小圈、鲁拉 Boss 图标、绿色 3/6/9/12 数字按帧显示；非当前帧元素用 `hidden` 覆写。

**双帧「P3-2左右分组」**：
- slide-1 帧名 `06:43/06:45`，顶部文案“P3-2”“06:45左星座”“06:43右吸球”；右侧标注“右/中/左”；左侧说明含“其中冰法1必定是第一个被点符文的”。
- slide-2 帧名 `07:03/07:05`，顶部文案“07:03左吸球”“07:05右星座”；新增门图标、07:26 两侧开种子/放门提示；左右说明含 SS1/SS2 转场门位置提醒。
- 同一批人员跨帧复用，第二帧只写 x/y override；帧专属圈、门、Boss 图标、批注层用 hidden 覆写。

**单帧「P3-3星座吸球」**：
- 背景：紫色至暗竞技场（`bg` 3183）；本图不放白色十字矩形。
- text：左上“07:38左吸球”、右上“07:40右星座”、底部“P3-3”和绿色“门口”。
- shape/icon：左侧吸球黄色/紫色圈 + 鲁拉 Boss 图标；右侧星座大黄圈 + 鲁拉 Boss 图标；绿色 3/6/9/12 数字。
- person：左侧奶德2、奶德1；右侧 LR1、AM1、增辉2、LR2、增辉1、SS2、DKT1、DK1、噬灭1；说明文案逐字落入模板。

验收门槛：
1. `luac -p` 全过（data/canvas/overlay/editor_gui/person_resolver/component_drawer/slide_bar/icon_picker/layer_panel）。
2. `rg -n "print\(" ShengTangTools -g '!ShengTangTools/libs/**'` 无新增裸 print。
3. `bash Tools/check_locale.sh` 通过（无缺/多键）。
4. 接口对齐：canvas/overlay/editor/panels 调的 `Data:*`/`PersonResolver:*`/`IconPicker:*`/`LayerPanel:*` 签名与本契约一致；无旧 `start_t/end_t/step/slot/square` 残留。
5. 编辑器：组件抽屉拖 person/icon/text/shape/marker 入画布；slide_bar 增/删/切帧；当前帧拖 person 写覆写；箭头/线段可拖起点与终点；滚轮缩放 + 中键/空格平移；方向键微调、Shift 约束拖拽、旋转手柄、对齐/分布/统一尺寸可用；图层面板按 ID 复用不错位、组头批量改半径生效。
6. 运行时：`Overlay:Play` 双帧播放，共有 person 补间、新增 person 淡入；本机对应 person 高亮；编辑器显 slotName、运行时显真实 id。
7. `bash Tools/deploySTT.sh retail` 一次成功。
8. 文档同步：指南/简介(中英)/帮助文本 描述 slide 帧编排 + person + 组件抽屉。

---

## 12. 红线（永不做）

- 不保留旧 element/step/slot/square 与新 slide/person/shape 两套（单一权威；破坏旧数据不迁移）。
- 不写兜底/同义字段映射（如 `targetCount or count`、person `fontSize or size`）。
- person 的 text 字段必须复用 indicator_text 的同名 schema，不造新同义字段；person.circle 是自有字段集（不复用 indicator_circle，后者是冷却扫描环、语义不符）。
- morph 当前只补间位置 + alpha 淡入淡出；不私自加颜色/字号补间（要加先扩 override 白名单 + §6 插值维度）。
- person.slotName 解析/本机判定只经 person_resolver 转调 stn_template（`ResolveSlotAtRuntime`/`NormalizePlayerName`/`slotVisualSpecs`），不复制解析逻辑。
- 几何只从 `Data:GetElementBox`/`GetPersonLayout`/坐标换算函数取；canvas/editor 不重复硬编码尺寸/换算。
- 不硬编码专精图标 fileID（走 spec_icons API）。
- 12.0 纯 UI：运行时只做视觉呈现，不驱动游戏内行为；播放主开关默认安全。
- 可选模块禁用即等同空文件、顶层零构造；新/改文件头尾逐字对照同目录现有朴素模块（无 `T.RegisterColdFile`）。
- 不在源码出现第三方竞品名；只走 `T.msg`/`T.debug`；`luac -p` 必过。
- 不嵌套组（单层组）。

---

## 13. 分阶段实现计划（建议）

1. **data 层地基**（data-owner）：schema 4 元素 + slide + artboard + override；`EnsureBoardShape/EnsureElementShape` 重写；`GetElementBox/GetPersonLayout`；slide CRUD + `ResolveElementAtSlide`/`SetSlideOverride`；person CRUD + `ResolvePersonDefaultIcon`；hash/export 重写。**同时提供一个最小验证夹具** `Data:BuildTestFixture(boardID)`（纯代码 `AddPersonAt`+`SetSlideOverride` 拼 3-4 person + 2 slide，不依赖真实 boss 数据），供阶段 3/4 渲染验收用。→ 验证：`luac -p`，单元自测 person/slide 数据可建可解算。
2. **person_resolver**（data-owner）：编辑期 specID 桥接 + 运行时真实名/本机判定（转调 stn_template）。→ 验证：解析咕咕2→真实 id 正确，本机判定正确。
3. **canvas 渲染**（canvas-owner）：坐标换算权威（zoom/pan）；5 元素 + person 复合渲染；`renderState` 消费 resolved/currentSlideIndex；选择/手柄沿用；`DrawAlignGuides`。→ 验证：用阶段 1 的 `BuildTestFixture` 单帧渲染 person/icon/text/shape/marker 正确（**不依赖阶段 8 模板**）；`BoardToScreen`/`ScreenToBoard` 往返一致性单测。完整图1 20 人还原归阶段 8。
4. **overlay 运行时**（runtime-owner）：帧时间线 + morph 补间 + 淡入；本机高亮；Play 签名不变。→ 验证：用阶段 1 `BuildTestFixture` 的 2 帧验补间/淡入肉眼正确（**不依赖阶段 8 模板**）。完整图1→图2 morph 还原归阶段 8。
5. **slide_bar + 编辑器集成**（editor-owner）：帧条、当前帧编辑、无边画布交互、移除顶部添加按钮、挂载抽屉/图标选择器/图层、键位、本地化、帮助文本。
6. **component_drawer**（panels-owner）：抽屉交互（复用 skill_drawer）+ 自动 person 预设（按 [人员]）+ 拖入画布。
7. **layer_panel 重写**（panels-owner）：稳定 ID 行池修 SSOT + 组头批量编辑。
8. **模板 + 验收**（data-owner 写模板，主控验收）：`ApplyMidnightfallTemplate` 双帧；跑 §11 全部门槛 + 部署。
9. **文档同步**（docs-owner）：指南/简介/帮助文本。

> 阶段 1-2（data + resolver）是所有人的依赖，必须先冻结落地；阶段 1 的 `BuildTestFixture` 是阶段 3/4 的渲染验收数据源（让 3/4 可独立验收，不反向依赖排在最后的阶段 8 模板）。3/4（canvas/overlay）可并行；5/6/7（editor/drawer/layer）依赖 3；8（完整图1/图2 还原 + §11 验收）/9 收尾。每阶段验收只依赖其声明的前置阶段产物。
