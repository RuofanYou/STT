local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

-- 方案文本扫描器：在玩家输入文本中找出"可替换为 {spell:ID}<原文> 的位置"，
-- 过滤已经位于 token/注释/静默标记/颜色块内的命中，避免对已转换内容误报。
-- 输出按起点升序、重叠时取最长词的命中列表。

local Scanner = {}
T.SpellAliasScanner = Scanner

local function CollectProtectedRanges(text)
    local ranges = {}
    local patterns = {
        "{[^{}]*}",                  -- 任何 token（{spell:...} / {time:...} / {所有人} 等）
        "<[^<>]->",                  -- `<xxx>` 绝对注释
        "~~.-~~",                    -- `~~xxx~~` 静默标记
        "|c%x%x%x%x%x%x%x%x.-|r",    -- `|cAARRGGBB...|r` 颜色块
    }
    for _, pattern in ipairs(patterns) do
        local init = 1
        while init <= #text do
            local s, e = text:find(pattern, init)
            if not s then
                break
            end
            ranges[#ranges + 1] = { s, e }
            init = e + 1
        end
    end
    return ranges
end

local function OverlapsAny(ranges, s, e)
    for i = 1, #ranges do
        local r = ranges[i]
        if s <= r[2] and e >= r[1] then
            return true
        end
    end
    return false
end

function Scanner.Scan(text)
    if type(text) ~= "string" or text == "" then
        return {}
    end
    local Index = T.SpellAliasIndex
    if not Index or not Index.IsReady or not Index.IsReady() then
        return {}
    end

    local protected = CollectProtectedRanges(text)
    local hits = {}
    local names = Index.GetNames()

    for i = 1, #names do
        local entry = names[i]
        local name = entry.name
        if type(name) == "string" and #name >= 2 then
            local init = 1
            while init <= #text do
                local s, e = text:find(name, init, true)
                if not s then
                    break
                end
                if not OverlapsAny(protected, s, e) then
                    hits[#hits + 1] = {
                        start = s,
                        finish = e,
                        word = name,
                        spellID = entry.id,
                    }
                end
                init = e + 1
            end
        end
    end

    -- 同起点取长词优先；起点升序输出
    table.sort(hits, function(a, b)
        if a.start ~= b.start then
            return a.start < b.start
        end
        if a.finish ~= b.finish then
            return a.finish > b.finish
        end
        return a.spellID < b.spellID
    end)

    local accepted = {}
    local lastEnd = 0
    for i = 1, #hits do
        local hit = hits[i]
        if hit.start > lastEnd then
            accepted[#accepted + 1] = hit
            lastEnd = hit.finish
        end
    end

    return accepted
end

-- 按 scanner 的命中列表批量替换文本，从后往前以避免位置偏移。
function Scanner.ApplyReplacements(text, hits)
    if type(text) ~= "string" or type(hits) ~= "table" or #hits == 0 then
        return text or "", 0
    end
    local ordered = {}
    for i = 1, #hits do
        ordered[i] = hits[i]
    end
    table.sort(ordered, function(a, b) return a.start > b.start end)
    local out = text
    local count = 0
    for i = 1, #ordered do
        local hit = ordered[i]
        if hit.spellID and hit.word and hit.start and hit.finish then
            local replacement = string.format("{spell:%d}<%s>", hit.spellID, hit.word)
            out = out:sub(1, hit.start - 1) .. replacement .. out:sub(hit.finish + 1)
            count = count + 1
        end
    end
    return out, count
end

end)
