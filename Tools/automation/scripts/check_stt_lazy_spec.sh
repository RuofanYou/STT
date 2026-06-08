#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

failures=0

fail() {
  echo "[FAIL] $*"
  failures=$((failures + 1))
}

pass() {
  echo "[PASS] $*"
}

check_no_match() {
  local label="$1"
  local pattern="$2"
  shift 2
  local output
  if output="$(rg -n "$pattern" "$@" 2>/dev/null)"; then
    echo "$output"
    fail "$label"
  else
    pass "$label"
  fi
}

echo "[STT Lazy Spec] Lua 语法"
find ShengTangTools -path '*/libs/*' -prune -o -name '*.lua' -print0 | xargs -0 luac -p
pass "luac -p 全量通过"

echo "[STT Lazy Spec] 静态规则"
check_no_match "禁止 require(" 'require\(' ShengTangTools -g '*.lua' -g '!ShengTangTools/libs/**'
check_no_match "禁止业务模块 defaultEnabled=true" 'defaultEnabled\s*=\s*true' ShengTangTools/core ShengTangTools/options -g '*.lua'
check_no_match "数据文件禁止顶层 T.X = {" 'T\.[A-Za-z0-9_]+\s*=\s*\{' ShengTangTools/data -g '*.lua'
check_no_match "数据文件禁止 return T.X 触发 LazyAsset" 'return\s+T\.[A-Za-z0-9_]+' ShengTangTools/data -g '*.lua'
check_no_match "团员默认运行时禁止加载编辑/内置方案大表" 'semanticTimeline\.runtimeEnabled' \
  ShengTangTools/data/semantic_builtin_plans_s14.lua \
  ShengTangTools/data/semantic_templates_s14.lua \
  ShengTangTools/data/semantic_builtin_event_plans_s14.lua \
  ShengTangTools/data/semantic_embedded_trigger_templates_s14.lua \
  ShengTangTools/data/semantic_spell_texts_s14.lua \
  ShengTangTools/data/class_spells.lua \
  ShengTangTools/data/boss_spells.lua \
  ShengTangTools/data/spell_pinyin.lua
if rg -n 'T\.RegisterColdFile\("semanticTimeline\.editorLoaded"' ShengTangTools/core/semantic_timeline.lua >/dev/null \
  && rg -n 'core\\semantic_runtime\.lua' ShengTangTools/load.xml >/dev/null; then
  pass "团员默认运行时使用 semantic_runtime，完整工作台仅编辑器加载"
else
  fail "团员默认运行时使用 semantic_runtime，完整工作台仅编辑器加载"
fi
check_no_match "选项模块禁止顶层 items = {" 'T\.RegisterOptionModule\(\{[\s\S]*?\n\s*items\s*=\s*\{' ShengTangTools/options ShengTangTools/core -g '*.lua' -U
check_no_match "locale 必须注册加载函数，禁止客户端语言顶层 return" 'if\s+(?:T\s+and\s+)?T\.Client\s*~=' ShengTangTools/locale -g '*.lua'

echo "[STT Lazy Spec] 运行时状态机与探针"
node <<'NODE'
const fs = require('fs');

const checks = [
  {
    name: 'ModuleLoader disable calls OnSoftDisable',
    file: 'ShengTangTools/core/module_loader.lua',
    pattern: /SafeCall\(module,\s*["']OnSoftDisable["']/,
  },
  {
    name: 'ModuleLoader disable calls OnRelease',
    file: 'ShengTangTools/core/module_loader.lua',
    pattern: /SafeCall\(module,\s*["']OnRelease["']/,
  },
  {
    name: 'ModuleLoader disable releases LazyAsset owner',
    file: 'ShengTangTools/core/module_loader.lua',
    pattern: /Assets:ReleaseOwner\(module\.name\)/,
  },
  {
    name: 'ModuleLoader gates user enable behind reload',
    file: 'ShengTangTools/core/module_loader.lua',
    pattern: /module\.state\s*=\s*["']PendingLoad["'][\s\S]*?return\s+true,\s*["']reload_required["']/,
  },
  {
    name: 'PerfProbe prints loadDelta',
    file: 'ShengTangTools/core/perf_probe.lua',
    pattern: /loadDelta=%sKB/,
  },
  {
    name: 'PerfProbe prints softDisableDelta',
    file: 'ShengTangTools/core/perf_probe.lua',
    pattern: /softDisableDelta=%sKB/,
  },
  {
    name: 'PerfProbe prints memory target',
    file: 'ShengTangTools/core/perf_probe.lua',
    pattern: /冷壳≤%dKB/,
  },
  {
    name: 'PerfProbe has single-module audit command',
    file: 'ShengTangTools/core/perf_probe.lua',
    pattern: /BeginModuleAudit[\s\S]*?baseline[\s\S]*?loaded[\s\S]*?returned[\s\S]*?restore/,
  },
  {
    name: 'PerfProbe has all-module audit command',
    file: 'ShengTangTools/core/perf_probe.lua',
    pattern: /BeginAllModuleAudit[\s\S]*?全模块验收完成[\s\S]*?maxGC[\s\S]*?audit report/,
  },
  {
    name: 'PerfProbe persists module audit report',
    file: 'ShengTangTools/core/perf_probe.lua',
    pattern: /lastModuleAudit[\s\S]*?PrintModuleAuditReport/,
  },
  {
    name: 'ModuleLoader requires dbKey',
    file: 'ShengTangTools/core/module_loader.lua',
    pattern: /requires desc\.dbKey/,
  },
  {
    name: 'ModuleLoader rejects defaultEnabled true',
    file: 'ShengTangTools/core/module_loader.lua',
    pattern: /defaultEnabled\s*==\s*true[\s\S]*?requires defaultEnabled=false/,
  },
  {
    name: 'OptionEngine releases full render tree after idle',
    file: 'ShengTangTools/options/option_engine.lua',
    pattern: /ScheduleRenderRelease[\s\S]*?ReleaseRenderTree/,
  },
  {
    name: 'NewBadge does not inspect cold module item factories',
    file: 'ShengTangTools/core/new_badge.lua',
    pattern: /ShouldInspectItems[\s\S]*?runtimeModule\.enabled\s*==\s*true\s+and\s+runtimeModule\.pendingReload\s*~=\s*true[\s\S]*?GetOptionItems[\s\S]*?return\s+\{\}/,
  },
  {
    name: 'GUI releases option render tree on hide',
    file: 'ShengTangTools/core/gui.lua',
    pattern: /SetScript\(["']OnHide["'][\s\S]*?ReleaseSettingsRenderTree\("gui_hide"\)/,
  },
  {
    name: 'Cold files are finalized after all load.xml registrations',
    file: 'ShengTangTools/load.xml',
    pattern: /core\\minimap_button\.lua[\s\S]*core\\cold_file_finalizer\.lua/,
  },
  {
    name: 'Cold file finalizer loads desired late registrations',
    file: 'ShengTangTools/core/cold_file_finalizer.lua',
    pattern: /LoadColdFilesForDesired/,
  },
  {
    name: 'Member runtime defaults on',
    file: 'ShengTangTools/core/init.lua',
    pattern: /ttsEnabled\s*=\s*true[\s\S]*?CountdownEnabled\s*=\s*true[\s\S]*?Bar\s*=\s*\{[\s\S]*?Enabled\s*=\s*true[\s\S]*?semanticTimeline\s*=\s*\{[\s\S]*?runtimeEnabled\s*=\s*true[\s\S]*?enabled\s*=\s*false/,
  },
  {
    name: 'Voice depends on member tactic runtime',
    file: 'ShengTangTools/core/runtime_modules.lua',
    pattern: /RegisterShellModule\("Voice"[\s\S]*?dependencies\s*=\s*\{\s*"TacticRuntime"\s*\}/,
  },
  {
    name: 'Countdown depends on member tactic runtime',
    file: 'ShengTangTools/core/runtime_modules.lua',
    pattern: /RegisterShellModule\("Countdown"[\s\S]*?dependencies\s*=\s*\{\s*"TacticRuntime"\s*\}/,
  },
  {
    name: 'Segmented bar depends on member tactic runtime',
    file: 'ShengTangTools/core/runtime_modules.lua',
    pattern: /RegisterShellModule\("SegmentedBar"[\s\S]*?dependencies\s*=\s*\{\s*"TacticRuntime"\s*\}/,
  },
  {
    name: 'Countdown runtime files load from countdown switch',
    file: 'ShengTangTools/core/countdown_player.lua',
    pattern: /RegisterColdFile\("CountdownEnabled"/,
  },
  {
    name: 'Countdown packs load from countdown switch',
    file: 'ShengTangTools/core/countdown_packs.lua',
    pattern: /RegisterColdFile\("CountdownEnabled"/,
  },
  {
    name: 'Tactics editor loads on plan tab without a user-facing module switch',
    file: 'ShengTangTools/core/gui.lua',
    pattern: /ActivateColdFeature\("semanticTimeline\.editorLoaded"\)/,
  },
  {
    name: 'Raid member import loads with tactics editor',
    file: 'ShengTangTools/core/sync_raid.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.editorLoaded[\s\S]*?rosterPlanner\.enabled[\s\S]*?\}/,
  },
  {
    name: 'Raid spec reader loads with tactics editor',
    file: 'ShengTangTools/core/raid_spec_reader.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.editorLoaded[\s\S]*?rosterPlanner\.enabled[\s\S]*?\}/,
  },
  {
    name: 'Spec aliases load with tactics editor',
    file: 'ShengTangTools/core/spec_aliases.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.editorLoaded[\s\S]*?rosterPlanner\.enabled[\s\S]*?\}/,
  },
  {
    name: 'Raid member import click reports missing module',
    file: 'ShengTangTools/core/semantic_timeline_gui.lua',
    pattern: /HandleSyncRaidMembers[\s\S]*?T\.SyncRaid[\s\S]*?T\.msg[\s\S]*?MSG_SYNC_RAID_NOT_READY/,
  },
  {
    name: 'Member runtime loads comm receive path',
    file: 'ShengTangTools/core/comm.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.runtimeEnabled[\s\S]*?\}/,
  },
  {
    name: 'Member runtime loads received tactic storage',
    file: 'ShengTangTools/core/note_sync.lua',
    pattern: /T\.Comm:Register\("note",\s*"sync"/,
  },
  {
    name: 'Member runtime loads STN parser chain',
    file: 'ShengTangTools/core/stn_template.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.runtimeEnabled[\s\S]*?\}/,
  },
  {
    name: 'Member runtime loads timeline syntax',
    file: 'ShengTangTools/core/timeline_syntax.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.runtimeEnabled[\s\S]*?\}/,
  },
  {
    name: 'Member runtime loads note parser',
    file: 'ShengTangTools/core/note_parser.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.runtimeEnabled[\s\S]*?\}/,
  },
  {
    name: 'Member runtime loads voice adapter',
    file: 'ShengTangTools/core/stn_voice_adapter.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.runtimeEnabled[\s\S]*?\}[\s\S]*?GetCurrentPlanBundle/,
  },
  {
    name: 'Member runtime loads timeline runner',
    file: 'ShengTangTools/core/timeline_runner.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.runtimeEnabled[\s\S]*?\}[\s\S]*?GetCurrentPlanBundle/,
  },
  {
    name: 'Member runtime loads TTS queue',
    file: 'ShengTangTools/core/tts_queue.lua',
    pattern: /RegisterColdFile\(\{[\s\S]*?semanticTimeline\.runtimeEnabled[\s\S]*?\}[\s\S]*?C_VoiceChat/,
  },
];

const bad = [];
for (const check of checks) {
  const text = fs.readFileSync(check.file, 'utf8');
  if (!check.pattern.test(text)) {
    bad.push(`${check.name}: ${check.file}`);
  }
}
if (bad.length) {
  console.log(bad.join('\n'));
  process.exit(1);
}
NODE
pass "状态机、softDisable/release 与 /st mem 关键证据存在"

echo "[STT Lazy Spec] Module Manifest 与设置绑定"
node <<'NODE'
const fs = require('fs');
const cp = require('child_process');

function list(cmd) {
  const out = cp.execSync(cmd, { encoding: 'utf8' }).trim();
  return out ? out.split(/\n/) : [];
}

const files = list("find ShengTangTools -name '*.lua' -not -path '*/libs/*'");
const moduleDbKeys = new Set();
const problems = [];

for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  const newModuleRe = /T\.ModuleLoader:NewModule\(\{([\s\S]*?)\n\s*\}\)/g;
  for (const match of text.matchAll(newModuleRe)) {
    const block = match[1];
    if (!/dbKey\s*=/.test(block)) {
      problems.push(`${file}: NewModule missing dbKey`);
    }
    if (!/defaultEnabled\s*=\s*false/.test(block)) {
      problems.push(`${file}: NewModule missing defaultEnabled=false`);
    }
    const literalDb = block.match(/dbKey\s*=\s*"([^"]+)"/);
    if (literalDb) {
      moduleDbKeys.add(literalDb[1]);
    }
  }

  const shellRe = /RegisterShell(?:WhenCold|Module)\(\s*"[^"]+"\s*,\s*"([^"]+)"/g;
  for (const match of text.matchAll(shellRe)) {
    moduleDbKeys.add(match[1]);
  }
}

const optionDbKeys = new Map();
for (const file of list("find ShengTangTools/options -name '*.lua'")) {
  const text = fs.readFileSync(file, 'utf8');
  for (const match of text.matchAll(/masterToggle\s*=\s*\{[\s\S]*?dbPath\s*=\s*"([^"]+)"/g)) {
    optionDbKeys.set(match[1], file);
  }
}

const optionEngine = fs.readFileSync('ShengTangTools/options/option_engine.lua', 'utf8');
for (const match of optionEngine.matchAll(/\{\s*id\s*=\s*"[^"]+"[\s\S]*?dbPath\s*=\s*"([^"]+)"/g)) {
  optionDbKeys.set(match[1], 'ShengTangTools/options/option_engine.lua');
}
const versionOptions = fs.readFileSync('ShengTangTools/options/version_check_options.lua', 'utf8');
if (/masterToggle\s*=/.test(versionOptions)) {
  problems.push('ShengTangTools/options/version_check_options.lua: version check must not expose masterToggle');
}
if (/\{\s*id\s*=\s*"versionCheck"[\s\S]*?dbPath\s*=\s*"versionCheck\.enabled"/.test(optionEngine)) {
  problems.push('ShengTangTools/options/option_engine.lua: version check must not be an option stub toggle');
}
const initText = fs.readFileSync('ShengTangTools/core/init.lua', 'utf8');
const systemOptions = fs.readFileSync('ShengTangTools/options/system_options.lua', 'utf8');
const commText = fs.readFileSync('ShengTangTools/core/comm.lua', 'utf8');
if (!/raidLead\s*=\s*\{[\s\S]*?optionPushAccept\s*=\s*true/.test(initText)) {
  problems.push('ShengTangTools/core/init.lua: raid lead setting push acceptance must default to true');
}
const defaultOnPaths = [
  ['ShengTangTools/core/init.lua', initText, /screenReminder\s*=\s*\{[\s\S]*?enabled\s*=\s*true/, 'screen reminder must default on'],
  ['ShengTangTools/core/init.lua', initText, /earlyPull\s*=\s*\{[\s\S]*?enabled\s*=\s*true/, 'early pull must default on'],
  ['ShengTangTools/core/init.lua', initText, /interruptRotation\s*=\s*\{[\s\S]*?enabled\s*=\s*true/, 'interrupt rotation must default on'],
  ['ShengTangTools/core/init.lua', initText, /suppressForbiddenPopup\s*=\s*true/, 'forbidden popup suppression must default on'],
  ['ShengTangTools/core/init.lua', initText, /repairReminder\s*=\s*\{[\s\S]*?autoRepair\s*=\s*true/, 'durability auto repair sub-default must stay on'],
];
for (const [file, text, pattern, label] of defaultOnPaths) {
  if (!pattern.test(text)) {
    problems.push(`${file}: ${label}`);
  }
}
if (!/dbPath\s*=\s*"raidLead\.optionPushAccept"[\s\S]*?default\s*=\s*true/.test(systemOptions)) {
  problems.push('ShengTangTools/options/system_options.lua: option push UI default must be true');
}
if (!/RegisterColdFile\(\{[\s\S]*?"raidLead\.optionPushAccept"[\s\S]*?\}/.test(commText)) {
  problems.push('ShengTangTools/core/comm.lua: option push acceptance must load communication runtime');
}
const screenOptions = fs.readFileSync('ShengTangTools/options/screen_reminder_options.lua', 'utf8');
const earlyPullOptions = fs.readFileSync('ShengTangTools/options/early_pull_options.lua', 'utf8');
const interruptOptions = fs.readFileSync('ShengTangTools/options/interrupt_rotation_options.lua', 'utf8');
const durabilityOptions = fs.readFileSync('ShengTangTools/options/durability_check_options.lua', 'utf8');
if (!/dbPath\s*=\s*"screenReminder\.enabled"[\s\S]*?default\s*=\s*true/.test(screenOptions)) {
  problems.push('ShengTangTools/options/screen_reminder_options.lua: screen reminder UI default must be true');
}
if (!/dbPath\s*=\s*"earlyPull\.enabled"[\s\S]*?default\s*=\s*true/.test(earlyPullOptions)) {
  problems.push('ShengTangTools/options/early_pull_options.lua: early pull UI default must be true');
}
if (!/dbPath\s*=\s*"interruptRotation\.enabled"[\s\S]*?default\s*=\s*true/.test(interruptOptions)) {
  problems.push('ShengTangTools/options/interrupt_rotation_options.lua: interrupt rotation UI default must be true');
}
if (!/dbPath\s*=\s*DB_KEY\s*\.\.\s*"\.autoRepair"[\s\S]*?default\s*=\s*true/.test(durabilityOptions)) {
  problems.push('ShengTangTools/options/durability_check_options.lua: durability auto repair UI default must be true');
}
for (const [moduleId, dbPath] of [
  ['screen_remind', 'screenReminder.enabled'],
  ['earlyPull', 'earlyPull.enabled'],
  ['interruptRotation', 'interruptRotation.enabled'],
]) {
  const pattern = new RegExp(`\\{\\s*id\\s*=\\s*"${moduleId}"[\\s\\S]*?dbPath\\s*=\\s*"${dbPath.replace('.', '\\.')}"[\\s\\S]*?default\\s*=\\s*true`);
  if (!pattern.test(optionEngine)) {
    problems.push(`ShengTangTools/options/option_engine.lua: ${moduleId} stub default must be true`);
  }
}

for (const [dbPath, file] of optionDbKeys.entries()) {
  if (!moduleDbKeys.has(dbPath)) {
    problems.push(`${file}: option dbPath has no ModuleLoader module: ${dbPath}`);
  }
}

if (problems.length) {
  console.log(problems.join('\n'));
  process.exit(1);
}
NODE
pass "所有 ModuleLoader 模块 default=false 且设置 dbPath 绑定到运行时模块"

echo "[STT Lazy Spec] 库 Desired 依赖"
node <<'NODE'
const fs = require('fs');
const text = fs.readFileSync('ShengTangTools/core/init.lua', 'utf8');

function listValues(name) {
  const match = text.match(new RegExp(`local\\s+${name}\\s*=\\s*\\{([\\s\\S]*?)\\n\\}`));
  if (!match) {
    throw new Error(`${name}: missing list`);
  }
  return new Set(Array.from(match[1].matchAll(/"([^"]+)"/g), (m) => m[1]));
}

function assertList(name, expected, forbidden = []) {
  const values = listValues(name);
  const bad = [];
  for (const item of expected) {
    if (!values.has(item)) {
      bad.push(`${name}: missing ${item}`);
    }
  }
  for (const item of forbidden) {
    if (values.has(item)) {
      bad.push(`${name}: should not include ${item}`);
    }
  }
  return bad;
}

const serializeFeatures = [
  'semanticTimeline.runtimeEnabled',
  'semanticTimeline.editorLoaded',
  'raidCommandPanel.enabled',
  'rosterPlanner.enabled',
  'earlyPull.enabled',
  'dreadElegy.enabled',
  'buffCheck.enabled',
  'castRecorder.backendEnabled',
  'raidLead.optionPushAccept',
  'versionCheck.enabled',
  'tacticTranslator.enabled',
  'screenReminder.enabled',
  'debugMode',
];
const commFeatures = [
  'semanticTimeline.runtimeEnabled',
  'semanticTimeline.editorLoaded',
  'raidCommandPanel.enabled',
  'rosterPlanner.enabled',
  'earlyPull.enabled',
  'dreadElegy.enabled',
  'buffCheck.enabled',
  'castRecorder.backendEnabled',
  'raidLead.optionPushAccept',
  'versionCheck.enabled',
  'tacticTranslator.enabled',
];

let bad = [];
bad = bad.concat(assertList('LIB_CUSTOM_GLOW_FEATURES', [
  'screenReminder.enabled',
], [
  'auraColorAlert.enabled',
  'personalAuraAlert.enabled',
  'dreadElegy.enabled',
]));
bad = bad.concat(assertList('LIB_SERIALIZE_FEATURES', serializeFeatures));
bad = bad.concat(assertList('LIB_COMM_FEATURES', commFeatures, [
  'screenReminder.enabled',
  'debugMode',
]));
bad = bad.concat(assertList('LIB_STUB_FEATURES', [
  'screenReminder.enabled',
  ...serializeFeatures.filter((item) => item !== 'screenReminder.enabled'),
]));
bad = bad.concat(assertList('LIB_CALLBACK_FEATURES', [
  ...commFeatures,
], [
  'screenReminder.enabled',
  'debugMode',
]));
if (text.includes('"minimap.enabled"')) {
  bad.push('minimap button must use minimap.hide core-shell gate, not minimap.enabled feature gate');
}

const branchChecks = {
  'LibCustomGlow-1.0': 'LIB_CUSTOM_GLOW_FEATURES',
  LibSerialize: 'LIB_SERIALIZE_FEATURES',
  LibDeflate: 'LIB_SERIALIZE_FEATURES',
  'AceComm-3.0': 'LIB_COMM_FEATURES',
  ChatThrottleLib: 'LIB_COMM_FEATURES',
  'CallbackHandler-1.0': 'LIB_CALLBACK_FEATURES',
  LibStub: 'LIB_STUB_FEATURES',
};

for (const [lib, listName] of Object.entries(branchChecks)) {
  if (!text.includes(`libraryName == "${lib}"`)) {
    bad.push(`${lib}: missing branch`);
  }
  if (!text.includes(`T.ShouldLoadAnyFeature(${listName})`)) {
    bad.push(`${lib}: branch does not use ${listName}`);
  }
}
for (const lib of ['LibDataBroker-1.1', 'LibDBIcon-1.0']) {
  if (!text.includes(`libraryName == "${lib}"`)) {
    bad.push(`${lib}: missing branch`);
  }
}
if (!/libraryName == "LibDataBroker-1\.1"[\s\S]*T\.ShouldLoadMinimapButton\(\)/.test(text)) {
  bad.push('minimap libraries must be gated by T.ShouldLoadMinimapButton()');
}
if (!/libraryName == "CallbackHandler-1\.0"[\s\S]*T\.ShouldLoadMinimapButton\(\)\s+or\s+T\.ShouldLoadAnyFeature\(LIB_CALLBACK_FEATURES\)/.test(text)) {
  bad.push('CallbackHandler must load for minimap button or callback-dependent modules');
}
if (!/libraryName == "LibStub"[\s\S]*T\.ShouldLoadMinimapButton\(\)\s+or\s+T\.ShouldLoadAnyFeature\(LIB_STUB_FEATURES\)/.test(text)) {
  bad.push('LibStub must load for minimap button or LibStub-dependent modules');
}

if (bad.length) {
  console.log(bad.join('\n'));
  process.exit(1);
}
NODE
pass "库文件按 Desired 加载且依赖链完整"

echo "[STT Lazy Spec] Core Shell 本地化"
lua <<'LUA'
unpack = table.unpack
local T, C, L = { Client = "enUS" }, { DB = { preferredLocale = "zhCN" } }, {}
local ns = { T, C, L }
local function load_stt_file(path)
    local chunk = assert(loadfile(path))
    local ok, err = pcall(chunk, "ShengTangTools", ns)
    if not ok then
        error(err)
    end
end

load_stt_file("ShengTangTools/locale/zhCN.lua")
load_stt_file("ShengTangTools/locale/zhTW.lua")
load_stt_file("ShengTangTools/locale/enUS.lua")
load_stt_file("ShengTangTools/locale/auto_zhCN.lua")

assert(type(T.LoadLocale_zhCN) == "function", "zhCN loader missing")
assert(type(T.LoadLocale_zhTW) == "function", "zhTW loader missing")
assert(type(T.LoadLocale_enUS) == "function", "enUS loader missing")
T.LoadLocale_zhCN()
assert(L.GUI_NAV_DIAGNOSE == "一键诊断", "zhCN diagnose label missing")
assert(L.GUI_SEARCH_PLACEHOLDER == "搜索设置...", "zhCN search placeholder missing")

for key in pairs(L) do
    L[key] = nil
end
T.LoadLocale_enUS()
assert(L.GUI_NAV_DIAGNOSE == "Quick Diagnose", "enUS diagnose label missing")
print("[PASS] locale loaders register unconditionally")
LUA
pass "Core Shell 保留本地化并支持语言切换"

echo "[STT Lazy Spec] ModuleLoader 运行时语义"
lua <<'LUA'
local function load_stt_file(path, env, ns)
    local chunk, err = loadfile(path, "t", env)
    if not chunk then
        error(err)
    end
    local ok, runtimeErr = pcall(chunk, "ShengTangTools", ns)
    if not ok then
        error(runtimeErr)
    end
end

local T, C, L = {}, { DB = { demo = { enabled = false } } }, {}
local ns = { T, C, L }
STT_DB = C.DB

local messages = {}
T.msg = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    messages[#messages + 1] = table.concat(parts, " ")
end
T.debug = function() end

local env = {
    STT_DB = STT_DB,
    table = table,
    string = string,
    math = math,
    pairs = pairs,
    ipairs = ipairs,
    next = next,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    select = select,
    unpack = table.unpack,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    rawget = rawget,
    rawset = rawset,
    error = error,
    pcall = pcall,
    collectgarbage = collectgarbage,
    print = print,
}

load_stt_file("ShengTangTools/core/lazy_assets.lua", env, ns)
load_stt_file("ShengTangTools/core/module_loader.lua", env, ns)

local okMissingDb = pcall(function()
    T.ModuleLoader:NewModule({ name = "MissingDb", defaultEnabled = false })
end)
assert(okMissingDb == false, "NewModule must reject missing dbKey")

local okDefaultEnabled = pcall(function()
    T.ModuleLoader:NewModule({ name = "DefaultOn", dbKey = "defaultOn.enabled", defaultEnabled = true })
end)
assert(okDefaultEnabled == false, "NewModule must reject defaultEnabled=true")

local duplicateBase = T.ModuleLoader:NewModule({
    name = "DuplicateSafe",
    dbKey = "duplicateSafe.enabled",
    defaultEnabled = false,
})
local duplicateSame = T.ModuleLoader:NewModule({
    name = "DuplicateSafe",
    dbKey = "duplicateSafe.enabled",
    defaultEnabled = false,
})
assert(duplicateSame == duplicateBase, "same module/dbKey duplicate must be idempotent")
local duplicateDifferentOk = pcall(function()
    T.ModuleLoader:NewModule({
        name = "DuplicateSafe",
        dbKey = "duplicateOther.enabled",
        defaultEnabled = false,
    })
end)
assert(duplicateDifferentOk == false, "same module with different dbKey must still fail")

local calls = {}
T.Assets:Define("DemoAsset", {
    factory = function()
        return { value = 1 }
    end,
})

local module = T.ModuleLoader:NewModule({
    name = "Demo",
    dbKey = "demo.enabled",
    defaultEnabled = false,
    OnFirstLoad = function()
        calls[#calls + 1] = "first"
    end,
    OnEnable = function(self)
        calls[#calls + 1] = "enable"
        self.asset = T.Assets:Get("DemoAsset", self.name)
    end,
    OnSoftDisable = function()
        calls[#calls + 1] = "soft"
    end,
    OnDisable = function()
        calls[#calls + 1] = "disable"
    end,
    OnRelease = function()
        calls[#calls + 1] = "release"
    end,
})

local ok, reason = T.ModuleLoader:SetDesired("Demo", true, "slash")
assert(ok == true and reason == "reload_required", "enable must be reload gated")
assert(module.enabled == false, "enable before reload must not hot-load")
assert(module.firstLoaded ~= true, "enable before reload must not first-load")
assert(module.pendingReload == true, "enable before reload must mark pending")
assert(#calls == 0, "enable before reload must not call module body")

local hotShell = T.ModuleLoader:NewModule({
    name = "HotOption",
    dbKey = "hotOption.enabled",
    defaultEnabled = false,
    _isColdShell = true,
})
local loadColdCalls = 0
T.LoadColdFilesForDesired = function()
    loadColdCalls = loadColdCalls + 1
    T.ModuleLoader:NewModule({
        name = "HotOption",
        dbKey = "hotOption.enabled",
        defaultEnabled = false,
        OnEnable = function(self)
            self.applied = true
        end,
    })
    return 1
end
ok, reason = T.ModuleLoader:SetDesired("HotOption", true, "option")
local hotOption = T.ModuleLoader:Get("HotOption")
assert(ok == true, "option enable should succeed")
assert(hotOption ~= hotShell and hotOption._isColdShell ~= true, "option enable must replace cold shell")
assert(hotOption.enabled == true and hotOption.applied == true, "option enable must hot-load active runtime")
assert(hotOption.pendingReload ~= true, "option enable must not require reload after hot-load")
assert(loadColdCalls == 1, "option enable must load desired cold files once")
T.LoadColdFilesForDesired = nil

T.ModuleLoader:Reconcile("initialize")
assert(module.enabled == true, "reconcile with desired=true must load")
assert(module.firstLoaded == true, "reconcile must mark firstLoaded")
assert(calls[1] == "first" and calls[2] == "enable", "reconcile must call first+enable")
assert(T.Assets:IsLoaded("DemoAsset") == true, "enabled module must own loaded asset")

ok, reason = T.ModuleLoader:SetDesired("Demo", false, "slash")
assert(ok == true or ok == false, "disable must return a boolean")
assert(module.enabled == false, "disable must stop active module")
assert(module.pendingReload == true, "disable after load must mark pending unload")
assert(calls[3] == "soft" and calls[4] == "disable" and calls[5] == "release", "disable must call soft+disable+release")
assert(T.Assets:IsLoaded("DemoAsset") == false, "disable must release owned assets")

local failing = T.ModuleLoader:NewModule({
    name = "Failing",
    dbKey = "failing.enabled",
    defaultEnabled = false,
    OnEnable = function()
        error("boom")
    end,
})
C.DB.failing = { enabled = true }
T.ModuleLoader:Reconcile("initialize")
assert(failing.enabled == false, "failed module must not stay enabled")
assert(failing.pendingReload == true, "failed module must keep pending reload after reconcile")
assert(C.DB.failing.enabled == false, "failed module must write desired=false")

print("[PASS] ModuleLoader runtime semantics")
LUA
pass "ModuleLoader 启用/禁用/release 运行时语义正确"

echo "[STT Lazy Spec] 屏幕提醒 schema 自愈"
lua <<'LUA'
local function load_stt_file(path, ns)
    local chunk = assert(loadfile(path))
    local ok, err = pcall(chunk, "ShengTangTools", ns)
    if not ok then
        error(err)
    end
end

unpack = table.unpack
local now = 1000
GetTime = function()
    now = now + 1
    return now
end

STT_DB = {
    screenReminder = {
        enabled = true,
        indicators = nil,
    },
}
local T, C, L = {}, { DB = STT_DB }, {}
local ns = { T, C, L }
T.debug = function() end
T.RegisterColdFile = function(_, loader)
    loader()
end

load_stt_file("ShengTangTools/core/screen_reminder/schema.lua", ns)

local Schema = T.ScreenReminderSchema
assert(type(Schema) == "table", "screen reminder schema missing")
Schema.Migrate()
local root = Schema.GetRoot()
assert(root.enabled == true, "schema migrate must preserve enabled=true")
assert(type(root.indicators) == "table" and #root.indicators >= 1, "schema migrate must recreate missing indicators")

local before = #root.indicators
local created = Schema.CreateIndicator("text")
assert(type(created) == "table" and created.kind == "text", "CreateIndicator must return text indicator")
assert(#root.indicators == before + 1, "CreateIndicator must append after schema self-heal")
assert(root.selectedIndicatorID == created.id, "CreateIndicator must select created indicator")

root.indicators = {}
local selected = Schema.GetSelectedIndicator()
assert(type(selected) == "table", "empty indicator list must self-heal selected indicator")
assert(#root.indicators >= 1, "empty indicator list must recreate defaults")

print("[PASS] screen reminder schema self-heals missing indicator list")
LUA
pass "屏幕提醒 indicators=nil/空列表不会导致新建崩溃"

echo "[STT Lazy Spec] 冷态文件入口 registry"
node <<'NODE'
const fs = require('fs');
const cp = require('child_process');

const files = cp.execSync("find ShengTangTools -name '*.lua' -not -path '*/libs/*/tests/*' -not -path '*/libs/*/examples/*'", { encoding: 'utf8' })
  .trim()
  .split(/\n/)
  .filter(Boolean);

const shellAllow = new Set([
  'ShengTangTools/core/init.lua',
  'ShengTangTools/core/version.lua',
  'ShengTangTools/core/new_badge.lua',
  'ShengTangTools/core/module_loader.lua',
  'ShengTangTools/core/event_bus.lua',
  'ShengTangTools/core/message_bus.lua',
  'ShengTangTools/core/hook_manager.lua',
  'ShengTangTools/core/lazy_assets.lua',
  'ShengTangTools/core/runtime_modules.lua',
  'ShengTangTools/core/perf_probe.lua',
  'ShengTangTools/core/perf_log.lua',
  'ShengTangTools/core/core.lua',
  'ShengTangTools/core/runtime_test_controls.lua',
  'ShengTangTools/core/widget_api.lua',
  'ShengTangTools/core/frame_skin.lua',
  'ShengTangTools/core/minimap_button.lua',
  'ShengTangTools/core/cold_file_finalizer.lua',
  'ShengTangTools/core/profile.lua',
  'ShengTangTools/core/smooth_scroll.lua',
  'ShengTangTools/core/debug_log_gui.lua',
  'ShengTangTools/core/style.lua',
  'ShengTangTools/core/gui.lua',
  'ShengTangTools/core/note_sync.lua',
  'ShengTangTools/core/semantic_timeline_sync_button.lua',
  'ShengTangTools/options/option_engine.lua',
  'ShengTangTools/options/nav_tree.lua',
  'ShengTangTools/options/search.lua',
  'ShengTangTools/options/diagnose_options.lua',
  'ShengTangTools/options/frame_skin_options.lua',
  'ShengTangTools/options/system_options.lua',
  'ShengTangTools/options/about_options.lua',
  'ShengTangTools/options/profile_dialogs.lua',
  'ShengTangTools/options/profile_selector.lua',
  'ShengTangTools/locale/zhCN.lua',
  'ShengTangTools/locale/zhTW.lua',
  'ShengTangTools/locale/enUS.lua',
  'ShengTangTools/locale/auto_zhCN.lua',
  'ShengTangTools/locale/auto_zhTW.lua',
  'ShengTangTools/locale/auto_enUS.lua',
]);

const libraryEntries = new Set([
  'ShengTangTools/libs/LibStub/LibStub.lua',
  'ShengTangTools/libs/CallbackHandler-1.0/CallbackHandler-1.0.lua',
  'ShengTangTools/libs/ChatThrottleLib/ChatThrottleLib.lua',
  'ShengTangTools/libs/AceComm-3.0/AceComm-3.0.lua',
  'ShengTangTools/libs/LibDataBroker-1.1/LibDataBroker-1.1.lua',
  'ShengTangTools/libs/LibDBIcon-1.0/LibDBIcon-1.0.lua',
  'ShengTangTools/libs/LibCustomGlow-1.0/LibCustomGlow-1.0.lua',
  'ShengTangTools/libs/LibSerialize/LibSerialize.lua',
  'ShengTangTools/libs/LibDeflate/LibDeflate.lua',
]);

function entryLine(lines) {
  for (let i = 0; i < Math.min(lines.length, 35); i++) {
    const line = lines[i];
    if (/T\.RegisterColdFile\s*\(/.test(line)) return i;
    if (/ShouldLoadLibrary/.test(line)) return i;
    if (/T\.Client\s*~=\s*["']/.test(line)) return i;
    if (/GetLocale\(\)\s*~=\s*["']/.test(line)) return i;
  }
  return -1;
}

const missing = [];
const earlyWork = [];
const forbiddenBeforeGuard = /\b(CreateFrame|RegisterEvent|SetScript|hooksecurefunc|HookScript)\b|C_Timer\.New(?:Ticker|Timer)|T\.EventBus:Register|T\.MessageBus:Register/;

for (const file of files) {
  if (shellAllow.has(file)) continue;
  if (file.startsWith('ShengTangTools/libs/') && !libraryEntries.has(file)) continue;
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split(/\n/);
  const g = entryLine(lines);
  if (g < 0) {
    missing.push(file);
    continue;
  }
  const prelude = lines.slice(0, g).join('\n');
  if (forbiddenBeforeGuard.test(prelude)) {
    earlyWork.push(`${file}:${g + 1}`);
  }
}

if (missing.length || earlyWork.length) {
  if (missing.length) {
    console.log('缺少冷态入口注册:');
    console.log(missing.join('\n'));
  }
  if (earlyWork.length) {
    console.log('冷态入口注册前存在运行时构造/注册:');
    console.log(earlyWork.join('\n'));
  }
  process.exit(1);
}
NODE
pass "非 Core Shell 文件均有冷态入口注册，且注册前无运行时构造"

echo "[STT Lazy Spec] 数据 LazyAsset"
node <<'NODE'
const fs = require('fs');
const cp = require('child_process');
const files = cp.execSync("find ShengTangTools/data -name '*.lua'", { encoding: 'utf8' })
  .trim()
  .split(/\n/)
  .filter(Boolean);
const bad = [];
for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  if (!/T\.Assets:Define\(/.test(text)) {
    bad.push(`${file}\tmissing T.Assets:Define`);
    continue;
  }
  const firstFactory = text.search(/factory\s*=\s*function/);
  const head = firstFactory >= 0 ? text.slice(0, firstFactory) : text;
  const directTable = head.match(/(?:^|\n)\s*(?:T\.[\w.]+|local\s+\w+)\s*=\s*\{/);
  if (directTable) {
    bad.push(`${file}\tdirect table before factory`);
  }
}
if (bad.length) {
  console.log(bad.join('\n'));
  process.exit(1);
}
NODE
pass "data 目录大表均通过 LazyAsset factory 定义"

echo "[STT Lazy Spec] masterToggle 与 ModuleLoader 绑定"
node <<'NODE'
const fs = require('fs');
const cp = require('child_process');

function files(cmd) {
  const out = cp.execSync(cmd, { encoding: 'utf8' }).trim();
  return out ? out.split(/\n/) : [];
}

const optionFiles = files("rg --files ShengTangTools/options -g '*_options.lua'");
const coreFiles = files("rg --files ShengTangTools/core -g '*.lua'");
const coreText = coreFiles.map((file) => fs.readFileSync(file, 'utf8')).join('\n');
const missing = [];

for (const file of optionFiles) {
  const text = fs.readFileSync(file, 'utf8');
  const id = (text.match(/id\s*=\s*"([^"]+)"/) || [])[1] || file;
  const matches = text.matchAll(/masterToggle\s*=\s*\{[\s\S]*?dbPath\s*=\s*"([^"]+)"/g);
  for (const match of matches) {
    const dbPath = match[1];
    if (!coreText.includes(`dbKey = "${dbPath}"`) && !coreText.includes(`RegisterShellModule("${dbPath}`) && !coreText.includes(`"${dbPath}"`)) {
      missing.push(`${dbPath}\t${id}\t${file}`);
    }
  }
}

if (missing.length > 0) {
  console.log(missing.join('\n'));
  process.exit(1);
}
NODE
pass "所有 masterToggle dbPath 均可在运行时模块中找到"

if (( failures > 0 )); then
  echo "[STT Lazy Spec] 失败: ${failures}"
  exit 1
fi

echo "[STT Lazy Spec] 通过"
