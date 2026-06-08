-- 施法回放引擎（Cast Replay）
-- 轻量时间轴 scheduler：把一场录像（cast_recorder 产出）按时间推进，
-- 供 cast_replay_gui 渲染对照视图。纯本地数据回放，不订阅任何战斗事件。

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("castRecorder.backendEnabled", function()

local Replay = {}
T.CastReplay = Replay

-- 推进用的 OnUpdate 帧：仅在播放中创建，暂停即停
local ticker

-- 当前回放会话：{ record, currentTime, playing, speed }
local session = nil

local subscribers = {}
local nextSubID = 0

local function Notify()
    for _, cb in pairs(subscribers) do
        pcall(cb, session)
    end
end

local function GetDuration()
    return session and session.record and tonumber(session.record.duration) or 0
end

local function OnTickerUpdate(_, elapsed)
    if not session or not session.playing then
        return
    end
    session.currentTime = session.currentTime + elapsed * (session.speed or 1)
    local duration = GetDuration()
    if session.currentTime >= duration then
        session.currentTime = duration
        session.playing = false
        ticker:Hide()
    end
    Notify()
end

local function EnsureTicker()
    if not ticker then
        ticker = CreateFrame("Frame")
        ticker:SetScript("OnUpdate", OnTickerUpdate)
        ticker:Hide()
    end
    return ticker
end

-- 载入一场录像，重置到起点（不自动播放）
function Replay:Load(record)
    if type(record) ~= "table" then
        return false
    end
    session = {
        record = record,
        currentTime = 0,
        playing = false,
        speed = 1,
    }
    if ticker then
        ticker:Hide()
    end
    if T.debug then
        T.debug(string.format("[CastReplay] 引擎载入录像 duration=%.1f casts=%d",
            tonumber(record.duration) or 0, #(record.casts or {})))
    end
    Notify()
    return true
end

function Replay:Play()
    if not session then
        return
    end
    -- 已播到结尾再点播放：从头开始
    if session.currentTime >= GetDuration() then
        session.currentTime = 0
    end
    session.playing = true
    EnsureTicker():Show()
    Notify()
end

function Replay:Pause()
    if not session then
        return
    end
    session.playing = false
    if ticker then
        ticker:Hide()
    end
    Notify()
end

function Replay:TogglePlay()
    if not session then
        return
    end
    if session.playing then
        self:Pause()
    else
        self:Play()
    end
end

function Replay:Seek(targetTime)
    if not session then
        return
    end
    local duration = GetDuration()
    local t = tonumber(targetTime) or 0
    if t < 0 then
        t = 0
    elseif t > duration then
        t = duration
    end
    session.currentTime = t
    Notify()
end

function Replay:SetSpeed(speed)
    if not session then
        return
    end
    session.speed = tonumber(speed) or 1
    Notify()
end

function Replay:GetSession()
    return session
end

function Replay:Clear()
    session = nil
    if ticker then
        ticker:Hide()
    end
    Notify()
end

-- 订阅会话变更，返回订阅 ID 供取消
function Replay:Subscribe(callback)
    if type(callback) ~= "function" then
        return nil
    end
    nextSubID = nextSubID + 1
    subscribers[nextSubID] = callback
    return nextSubID
end

function Replay:Unsubscribe(id)
    if id then
        subscribers[id] = nil
    end
end

end)
