local T, _, L = unpack(select(2, ...))

local Controls = {}
T.RuntimeTestControls = Controls

local function Text(key, fallback)
    return (L and L[key]) or fallback or key
end

function Controls:Start()
    if not (T.TimelineRunner and T.TimelineRunner.StartTest) then
        T.msg(Text("RUNTIME_TEST_UNAVAILABLE", "测试模块尚未加载"))
        return false
    end

    local ok, result = pcall(function()
        return T.TimelineRunner:StartTest()
    end)
    if not ok then
        if T.debug then
            T.debug("[RuntimeTestControls] Start failed: %s", tostring(result))
        end
        T.msg(Text("RUNTIME_TEST_START_FAILED", "运行测试启动失败，请打开调试日志查看原因"))
        return false
    end
    if result == false then
        T.msg(Text("RUNTIME_TEST_NO_PLAN", "当前没有可测试的战术方案"))
        return false
    end
    return true
end

function Controls:Stop()
    local stopped = false
    if T.TimelineRunner and T.TimelineRunner.Stop then
        T.TimelineRunner:Stop()
        stopped = true
    end
    if T.TriggerRunner and T.TriggerRunner.Stop then
        T.TriggerRunner:Stop()
        stopped = true
    end
    if T.ClearTTSQueue then
        T.ClearTTSQueue()
    end
    if not stopped and T.RealtimeBoard and T.RealtimeBoard.Stop then
        T.RealtimeBoard:Stop("manual_stop")
    end
    T.msg(Text("RUNTIME_TEST_STOPPED", "已停止测试播报"))
    return true
end
