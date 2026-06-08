# Tools/automation

本目录是 WoW 插件本地自动化测试的单一入口，覆盖 ADT 与 STT。

## 目录说明

- `scripts/`: 测试入口脚本（`test.sh adt|stt|all`）
- `runner/`: 用例发现、执行、断言、报告
- `vendor/`: 第三方或兼容层（轻量 luaunit）
- `mocks/`: WoW API mock（公共+插件专用）
- `adapters/`: 插件测试适配层（统一暴露 `RunCase`）
- `cases/`: 用例文件（unit + replay + fixtures）
- `baselines/`: replay 用例 golden 基线
- `smoke/`: 自动化后剩余的最小手工冒烟清单
- `logs/`: 最近一次汇总结果

## 统一执行命令

```bash
bash Tools/automation/scripts/test.sh adt
bash Tools/automation/scripts/test.sh stt
bash Tools/automation/scripts/test.sh all
```

执行顺序固定：

1. locale 检查（ADT/STT 各自脚本）
2. unit + replay
3. 汇总报告 + 非 0 退出码

## fixture 统一格式

每个用例文件返回 Lua table，必须包含：

- `meta`: `id/plugin/type/title`
- `init`: 初始状态（DB、mock 数据、玩家信息等）
- `events`: 事件序列（输入动作）
- `expect`: 断言（`equals` 或 `baseline`）

示例：

```lua
return {
  meta = {
    id = "adt_unit_xxx",
    plugin = "adt",
    type = "unit",
    title = "示例",
  },
  init = {
    db = { EnableBatchPlace = true },
  },
  events = {
    { type = "set_ctrl", value = true },
  },
  expect = {
    equals = { ok = true },
  },
}
```
