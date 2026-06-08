local T, C, L = unpack(select(2, ...))
T.RegisterColdFile({"semanticTimeline.runtimeEnabled", "semanticTimeline.editorLoaded"}, function()

-- STN语音适配器模块
-- 负责将STN战术方案转换为语音播报格式
local Adapter = {}
T.STNVoiceAdapter = Adapter

-- 解析STN方案并转换为语音播报格式
function Adapter:ParseSTNote(noteId)
    local out = {}

    -- 定位方案
    local note
    local content = ""
    if noteId then
        if not T.Note then
            T.msg("STN方案模块未加载")
            return out
        end
        note = T.Note:GetPlan(noteId)
        content = tostring(note and note.content or "")
    else
        local semantic = T.SemanticTimeline
        local bundle = semantic and semantic.GetCurrentPlanBundle and semantic:GetCurrentPlanBundle() or nil
        content = tostring(bundle and bundle.runtimeText or "")
        if content == "" and T.Note and T.Note.GetActivePlan then
            note = T.Note:GetActivePlan()
            content = tostring(note and note.content or "")
        end
    end

    if content == "" and not note then
        T.msg("没有找到任何可用方案")
        return out
    end

    local template = T.STNTemplate and T.STNTemplate.PreprocessText and T.STNTemplate.PreprocessText(content) or nil
    local isUsableTimeline = T.STNTemplate and T.STNTemplate.IsBodyUsable and T.STNTemplate.IsBodyUsable(template, "timeline") or false
    if not template or (template.bodyKind == "timeline" and not isUsableTimeline) or (template.bodyKind ~= "timeline" and template.isValid ~= true) then
        if template and template.errors and #template.errors > 0 then
            T.msg(string.format("%s %d", L["模板解析错误"] or "模板解析错误", #template.errors))
        end
        return out
    end

    if template.bodyKind == "trigger" and T.TriggerSyntax and T.TriggerSyntax.ParseTriggerText then
        local parsed = T.TriggerSyntax.ParseTriggerText(content)
        local seq = 0
        for _, rule in ipairs(parsed.rules or {}) do
            if not rule.occurrence then
                seq = seq + 1
                local spellName = nil
                if T.SemanticTimeline and T.SemanticTimeline.GetSpellName then
                    spellName = T.SemanticTimeline:GetSpellName(rule.spellID)
                elseif C_Spell and C_Spell.GetSpellName then
                    spellName = C_Spell.GetSpellName(rule.spellID)
                end
                local text = T.TriggerSyntax.BuildSpeakText(rule, spellName)
                if text ~= "" then
                    out[#out + 1] = { time = seq, text = text }
                end
            end
        end
        return out
    end

    if template.bodyKind ~= "timeline" then
        return out
    end

    if not T.NoteParser or not T.NoteParser.ParseNote then
        T.msg("NoteParser 未加载")
        return out
    end

    local parsed = T.NoteParser:ParseNote(content)
    for _, ev in ipairs(parsed or {}) do
        local text = self:BuildVoiceText(ev)
        if text ~= "" then
            table.insert(out, { time = tonumber(ev.time) or 0, text = text })
        end
    end
    table.sort(out, function(a,b) return a.time < b.time end)
    return out
end

-- 构建语音播报文本
function Adapter:BuildVoiceText(event)
    if type(event) ~= "table" then return "" end

    local source = event.content or event.displayText or event.originalText or event.rawLine or ""
    if T.NoteParser and (event.hasAudience ~= nil or source ~= "") then
        if T.NoteParser.ShouldTriggerEvent and not T.NoteParser:ShouldTriggerEvent(event) then
            return ""
        end
        if T.NoteParser.GetResolvedEventTTSText then
            local text = T.NoteParser:GetResolvedEventTTSText(event)
            if text ~= "" then
                return text
            end
        end
    end

    if source ~= "" then
        if T.TimelineSyntax and T.TimelineSyntax.ResolveTextForCurrentPlayer then
            local matched, text = T.TimelineSyntax.ResolveTextForCurrentPlayer(source, {
                target = "tts",
            })
            if matched then
                return text or ""
            end
            return ""
        end

        local fallback = source
        if T.TimelineSyntax and T.TimelineSyntax.ResolveSpellTokens then
            fallback = T.TimelineSyntax.ResolveSpellTokens(fallback, { target = "tts" })
        end
        fallback = fallback:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return T.TimelineSyntax.NormalizeASCIIWhitespace(fallback)
    end

    local segments = event.segments
    if type(segments) == "table" and #segments > 0 and T.TimelineSyntax and T.TimelineSyntax.ResolveSegmentsForCurrentPlayer then
        local matched, text = T.TimelineSyntax.ResolveSegmentsForCurrentPlayer(segments)
        if matched then
            return text or ""
        end
        return ""
    end

    return ""
end

-- 测试STN语音播报
function Adapter:TestSTNVoice()
    T.msg("测试STN语音播报...")

    local timeline = self:ParseSTNote()

    if #timeline == 0 then
        T.msg("STN方案解析失败或无事件")
        return
    end

    T.msg("解析成功，共 " .. #timeline .. " 个播报事件")

    -- 显示前几个事件
    for i = 1, math.min(3, #timeline) do
        local event = timeline[i]
        T.msg(string.format("[%d秒] %s", event.time, event.text))
    end

    -- 如果有StartVoiceTest函数，调用它
    if T.TimelineRunner and T.TimelineRunner.StartTest then
        T.TimelineRunner:StartTest()
    elseif T.StartVoiceTest then
        T.StartVoiceTest(timeline)
    else
        T.msg("语音测试功能未加载")
    end
end

end)
