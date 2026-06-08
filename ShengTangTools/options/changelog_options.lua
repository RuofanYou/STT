local T, C, L = unpack(select(2, ...))

-- 更新日志面板（设置 → 系统 → 更新日志）
-- 纯展示：把 T.Changelog（data/changelog.lua，单一权威）渲染成只读富文本。
-- 完全静默：不弹窗、不提示，玩家想看自己点开。无运行体/事件，零常驻开销。

local PANEL_HEIGHT = 460

-- 配色（ARGB 十六进制，含 alpha）
local C_DATE_HEAD = "ffffd100" -- 日期标题：盟约金
local C_NEW     = "ff40c057" -- 新增：绿
local C_IMPROVE = "ff4dabf7" -- 改进：蓝
local C_FIXED   = "ffff922b" -- 修复：橙
local C_REMOVED = "ff909296" -- 移除：灰
local C_BULLET  = "ffced4da" -- 条目正文：浅灰

local function Tr(key, fallback)
    local v = key and rawget(L, key)
    if v ~= nil and v ~= "" then
        return v
    end
    return fallback or key or ""
end

local function AppendSection(lines, items, colorHex, label)
    if not items or #items == 0 then
        return
    end
    lines[#lines + 1] = string.format("  |c%s%s|r", colorHex, label)
    for _, key in ipairs(items) do
        local text = Tr(key)
        lines[#lines + 1] = string.format("    |c%s\226\128\162|r |c%s%s|r", colorHex, C_BULLET, text)
    end
end

-- 把结构化数据拼成带色富文本（按天写日记，标题就是日期）
local function BuildChangelogText()
    local data = T.Changelog or {}
    local lines = {}
    for _, block in ipairs(data) do
        local date = block.date
        if date and date ~= "" then
            lines[#lines + 1] = string.format("|c%s%s|r", C_DATE_HEAD, date)
            AppendSection(lines, block.new, C_NEW, Tr("CHANGELOG_SECTION_NEW"))
            AppendSection(lines, block.improved, C_IMPROVE, Tr("CHANGELOG_SECTION_IMPROVED"))
            AppendSection(lines, block.fixed, C_FIXED, Tr("CHANGELOG_SECTION_FIXED"))
            AppendSection(lines, block.removed, C_REMOVED, Tr("CHANGELOG_SECTION_REMOVED"))
            lines[#lines + 1] = ""
        end
    end
    if #lines == 0 then
        return Tr("CHANGELOG_EMPTY")
    end
    return table.concat(lines, "\n")
end

local function RenderChangelogPanel(slot, ctx)
    local width = (ctx and ctx.width) or slot:GetWidth()

    local container = CreateFrame("Frame", nil, slot)
    container:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
    container:SetWidth(width)
    container:SetHeight(PANEL_HEIGHT)
    T.ApplyBackdrop(container, { alpha = 0.15 })

    -- 复用 STT 平滑滚动组件（带渐隐细滚动条），内容是只读 FontString，不用 EditBox。
    local scroll = T.CreateSimpleScroll(container)
    scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)

    local text = scroll.content:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
    text:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 4, -2)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(2)
    text:SetText(BuildChangelogText())

    -- 宽度随视口同步；高度按文字实际换行高度回填给滚动组件
    local function refresh()
        local vw = scroll.viewport and scroll.viewport:GetWidth() or 0
        if vw <= 1 then
            if not scroll._clPending then
                scroll._clPending = true
                C_Timer.After(0, function()
                    scroll._clPending = nil
                    if scroll:IsShown() then
                        refresh()
                    end
                end)
            end
            return
        end
        text:SetWidth(vw - 8)
        scroll:SetContentHeight((text:GetStringHeight() or 0) + 8)
    end
    refresh()
    scroll:HookScript("OnSizeChanged", refresh)

    return { height = PANEL_HEIGHT }
end

T.RegisterOptionModule({
    id = "changelog",
    category = "system",
    order = 90,
    titleKey = "GUI_NAV_CHANGELOG",
    newSince = "260531.21",
    itemsFactory = function()
        return {
            { type = "custom", render = RenderChangelogPanel, searchText = Tr("CHANGELOG_SEARCH_TEXT") },
        }
    end,
})
