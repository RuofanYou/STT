local T, C, L = unpack(select(2, ...))

-- 视觉战术板 person 解析桥接层（契约 §5，单一权威转调 stn_template）。
-- 本文件只做转调与查表：specID 来自 PreprocessText 产物 info.slotVisualSpecs；
-- 真实名/本机判定转调 Template.ResolveSlotAtRuntime / Template.NormalizePlayerName。
-- 禁止复制 ResolveSlotAtRuntime / IsPlayerInCurrentGroup / 名字规范化的函数体。
local PersonResolver = {}
T.VisualBoardPersonResolver = PersonResolver

-- 编辑期：slotName → specID。优先级：
--   1) 作者在方案 [人员图标] 段手填的 info.slotVisualSpecs[slotName]（最高，显式覆盖）；
--   2) 槽位名黑话推断 T.ResolveSlotVisualHint(slotName).specID（如 AM1→暗牧 258），复用与水平视角同一份黑话表，
--      不在本文件重造黑话→specID 映射。
-- 黑话只解析出职业（classFile，无 specID，如“小德”“FS”）时本函数返回 nil；职业图标兜底由 data:ResolvePersonDefaultIcon 负责。
-- 两条都不命中返回 nil。
function PersonResolver:ResolveSpecID(info, slotName)
    if type(slotName) ~= "string" or slotName == "" then
        return nil
    end
    if type(info) == "table" and type(info.slotVisualSpecs) == "table" then
        local manual = info.slotVisualSpecs[slotName]
        if manual then
            return manual
        end
    end
    if T.ResolveSlotVisualHint then
        local hint = T.ResolveSlotVisualHint(slotName)
        if type(hint) == "table" and hint.specID then
            return hint.specID
        end
    end
    return nil
end

-- 运行时：slotName → 真实角色名。
-- Template.ResolveSlotAtRuntime 吃的是 info.slots[slotName] 的 value（非 slotName 本身）。
-- person.slotName 契约保证单人槽位；若返回 table（含内部空格的并集组）视为非法 slotName：
-- T.debug 告警并降级显示原 slotName，不静默取首个。
-- 最终经 Template.NormalizePlayerName 规范化。
function PersonResolver:ResolveRealName(info, slotName)
    if type(slotName) ~= "string" or slotName == "" then
        return slotName
    end

    local Template = T.STNTemplate
    if not (Template and Template.ResolveSlotAtRuntime and Template.NormalizePlayerName) then
        return slotName
    end

    local slotValue = type(info) == "table" and type(info.slots) == "table" and info.slots[slotName] or nil
    if type(slotValue) ~= "string" or slotValue == "" then
        return slotName
    end

    local resolved = Template.ResolveSlotAtRuntime(slotValue)
    if type(resolved) == "table" then
        if T.debug then
            T.debug("[VisualBoardPersonResolver] slotName='" .. slotName .. "' 解析为并集组（非单人槽位），降级显示原槽位名")
        end
        return slotName
    end

    return Template.NormalizePlayerName(resolved)
end

-- 运行时：该 person 是否本机玩家。
-- = NormalizePlayerName(ResolveRealName) == NormalizePlayerName(本机名)；
-- 复用 Template.NormalizePlayerName + ResolveSlotAtRuntime（经 ResolveRealName），不复制规范化逻辑。
function PersonResolver:IsSelf(info, slotName)
    local Template = T.STNTemplate
    if not (Template and Template.NormalizePlayerName) then
        return false
    end

    local realName = self:ResolveRealName(info, slotName)
    if type(realName) ~= "string" or realName == "" then
        return false
    end

    local myName = Template.NormalizePlayerName(UnitName and UnitName("player") or "")
    if myName == "" then
        return false
    end

    return Template.NormalizePlayerName(realName) == myName
end
