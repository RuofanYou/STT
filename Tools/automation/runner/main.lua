local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source

local function dirname(path)
    return path:match("^(.*)/[^/]+$")
end

local function shell_quote(path)
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local runner_dir = dirname(script_path)
local automation_dir = dirname(runner_dir)
local tools_dir = dirname(automation_dir)
local repo_root = dirname(tools_dir)

package.path = table.concat({
    automation_dir .. "/?.lua",
    automation_dir .. "/?/?.lua",
    package.path,
}, ";")

local Assert = require("runner.assert")
local Report = require("runner.report")

local function parse_args(argv)
    local out = {
        plugin = "all",
    }

    local i = 1
    while i <= #argv do
        if argv[i] == "--plugin" then
            out.plugin = argv[i + 1] or out.plugin
            i = i + 2
        else
            i = i + 1
        end
    end

    return out
end

local function list_case_files(plugin, case_type)
    local dir = automation_dir .. "/cases/" .. plugin .. "/" .. case_type
    local cmd = "find " .. shell_quote(dir) .. " -type f -name '*.lua' | sort"
    local pipe = io.popen(cmd)
    if not pipe then
        return {}
    end

    local files = {}
    for line in pipe:lines() do
        files[#files + 1] = line
    end
    pipe:close()
    return files
end

local function load_table_file(path)
    local chunk, err = loadfile(path)
    if not chunk then
        return nil, err
    end
    local ok, ret = pcall(chunk)
    if not ok then
        return nil, ret
    end
    return ret, nil
end

local function run_one_case(plugin, adapter, case_file)
    local fixture, err = load_table_file(case_file)
    local case_id = fixture and fixture.meta and fixture.meta.id or case_file
    if not fixture then
        return {
            ok = false,
            case_id = case_id,
            message = "加载用例失败: " .. tostring(err),
        }
    end

    local ok, actual = pcall(adapter.RunCase, case_id, fixture)
    if not ok then
        return {
            ok = false,
            case_id = case_id,
            message = "执行异常: " .. tostring(actual),
        }
    end

    local expected = fixture.expect or {}
    local output = actual
    if type(actual) == "table" and actual.output ~= nil then
        output = actual.output
    end

    if expected.equals ~= nil then
        if not Assert.deep_equal(output, expected.equals) then
            return {
                ok = false,
                case_id = case_id,
                message = "断言失败（equals）\n" .. Assert.diff_message(output, expected.equals),
            }
        end
    end

    if expected.baseline then
        local baseline_path = automation_dir .. "/baselines/" .. plugin .. "/" .. expected.baseline
        local baseline, load_err = load_table_file(baseline_path)
        if not baseline then
            return {
                ok = false,
                case_id = case_id,
                message = "读取 baseline 失败: " .. tostring(load_err),
            }
        end
        if not Assert.deep_equal(output, baseline) then
            return {
                ok = false,
                case_id = case_id,
                message = "断言失败（baseline）\n" .. Assert.diff_message(output, baseline),
            }
        end
    end

    if expected.ok ~= nil and not Assert.deep_equal(actual.ok, expected.ok) then
        return {
            ok = false,
            case_id = case_id,
            message = "断言失败（ok）\n" .. Assert.diff_message(actual.ok, expected.ok),
        }
    end

    return {
        ok = true,
        case_id = case_id,
        message = "",
    }
end

local function load_adapter(plugin)
    if plugin == "adt" then
        return require("adapters.adt_adapter")
    elseif plugin == "stt" then
        return require("adapters.stt_adapter")
    end
    error("未知插件: " .. tostring(plugin))
end

local function run_plugin(plugin, reporter)
    local adapter = load_adapter(plugin)
    local unit_files = list_case_files(plugin, "unit")
    local replay_files = list_case_files(plugin, "replay")

    local files = {}
    for _, f in ipairs(unit_files) do files[#files + 1] = f end
    for _, f in ipairs(replay_files) do files[#files + 1] = f end

    for _, case_file in ipairs(files) do
        reporter:add(run_one_case(plugin, adapter, case_file))
    end
end

local opts = parse_args(arg)
local reporter = Report.new_reporter()

if opts.plugin == "all" then
    run_plugin("adt", reporter)
    run_plugin("stt", reporter)
else
    run_plugin(opts.plugin, reporter)
end

reporter:print_summary()

local log_path = automation_dir .. "/logs/latest_report.txt"
local fp = io.open(log_path, "w")
if fp then
    fp:write(string.format("total=%d\npassed=%d\nfailed=%d\n", reporter.total, reporter.passed, reporter.failed))
    for _, item in ipairs(reporter.details) do
        fp:write(string.format("%s|%s|%s\n", item.ok and "PASS" or "FAIL", item.case_id, (item.message or ""):gsub("\n", " ")))
    end
    fp:close()
end

if reporter.failed > 0 then
    os.exit(1)
end

os.exit(0)
