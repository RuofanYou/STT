local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("privateAuraList.enabled", function()

local DB_KEY = "privateAuraList"

-- Beta 模块本地化：内联 TEXT 表，沿用 interrupt_alert_options.lua 的写法。
-- 转正时再迁到独立的 locale 键。
local TEXT = {
    zhCN = {
        title = "个人光环列表 (Beta)",
        subtitle_beta = "实验：仅在 ENCOUNTER 期间挂载私密光环 anchor",
        desc_warning = "本模块用于验证私密光环 anchor 的 DOM 探针。开启后会在团本 boss 战开始时给每位团员挂上私密光环 anchor，并用 OnUpdate 检测客户端是否真把图标渲染到了 anchor 的 frame 上。所有事件写入 /st 调试日志（/st log 查看）。战斗结束自动释放。",
        max_icons = "每位团员预留槽位数",
        icon_size = "图标尺寸",
        row_height = "行高",
        growth = "列表生长方向",
        growth_down = "向下",
        growth_up = "向上",
        verbose_log = "详细探针日志（每个子 frame 类型）",
        subtitle_testing = "调试工具",
        btn_force_rebuild = "强制重挂 anchor",
        btn_dump_snapshot = "导出当前 DOM 快照到日志",
        btn_toggle_test_mode = "测试模式（忽略 ENCOUNTER，所有行强制显示）",
        log_hint = "日志查看：/st log",
    },
    zhTW = {
        title = "個人光環列表 (Beta)",
        subtitle_beta = "實驗：僅在 ENCOUNTER 期間掛載私密光環 anchor",
        desc_warning = "本模組用於驗證私密光環 anchor 的 DOM 探針。開啟後會在團本 boss 戰開始時給每位團員掛上私密光環 anchor，並用 OnUpdate 檢測用戶端是否真把圖示渲染到了 anchor 的 frame 上。所有事件寫入 /st 除錯日誌（/st log 查看）。戰鬥結束自動釋放。",
        max_icons = "每位團員預留槽位數",
        icon_size = "圖示尺寸",
        row_height = "行高",
        growth = "列表生長方向",
        growth_down = "向下",
        growth_up = "向上",
        verbose_log = "詳細探針日誌（每個子 frame 類型）",
        subtitle_testing = "除錯工具",
        btn_force_rebuild = "強制重掛 anchor",
        btn_dump_snapshot = "匯出目前 DOM 快照到日誌",
        btn_toggle_test_mode = "測試模式（忽略 ENCOUNTER，所有行強制顯示）",
        log_hint = "日誌查看：/st log",
    },
    enUS = {
        title = "Private Aura List (Beta)",
        subtitle_beta = "Experiment: mount private-aura anchors only during ENCOUNTER",
        desc_warning = "Verifies whether the client renders private-aura icons as children of the anchor parent. Mounts anchors for every group member on ENCOUNTER_START and probes child/region counts via OnUpdate. All events go to /st debug log (open with /st log). Anchors are released on ENCOUNTER_END.",
        max_icons = "Anchor slots per member",
        icon_size = "Icon size",
        row_height = "Row height",
        growth = "List grow direction",
        growth_down = "Down",
        growth_up = "Up",
        verbose_log = "Verbose probe log (dump child frame types)",
        subtitle_testing = "Debug tools",
        btn_force_rebuild = "Force rebuild anchors",
        btn_dump_snapshot = "Dump current DOM snapshot to log",
        btn_toggle_test_mode = "Test mode (ignore ENCOUNTER, force show all rows)",
        log_hint = "Log viewer: /st log",
    },
}
local TXT = TEXT[T.Client] or TEXT.enUS
L[TXT.title] = TXT.title

local function ApplyMaster()
    if T.PrivateAuraList then
        T.PrivateAuraList:ApplySettings()
    end
end

local function ApplyRebuild()
    if T.PrivateAuraList and T.PrivateAuraList.RebuildAnchors then
        -- 仅当模块正在 active 时重建有意义；非 active 直接打 log
        T.PrivateAuraList:ApplySettings()
    end
end

T.RegisterOptionModule({
    id = "privateAuraList",
    category = "utility",
    order = 90,
    beta = true,
    titleKey = TXT.title,
    masterToggle = {
        dbPath = DB_KEY .. ".enabled",
        default = false,
        apply = ApplyMaster,
    },
    itemsFactory = function()
        return {
        {
            type = "subtitle",
            text = TXT.subtitle_beta,
        },
        {
            key = "desc",
            type = "custom",
            width = 1,
            height = 80,
            render = function(slot, ctx)
                local fs = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetPoint("TOPLEFT", slot, "TOPLEFT", 4, -4)
                fs:SetPoint("RIGHT", slot, "RIGHT", -8, 0)
                fs:SetJustifyH("LEFT")
                fs:SetJustifyV("TOP")
                fs:SetWordWrap(true)
                fs:SetTextColor(1, 0.82, 0)
                fs:SetText(TXT.desc_warning)
                return { height = math.max(60, (fs:GetStringHeight() or 60) + 12) }
            end,
        },
        {
            type = "slider",
            text = TXT.max_icons,
            dbPath = DB_KEY .. ".maxIconsPerUnit",
            default = 2,
            min = 1,
            max = 3,
            step = 1,
            apply = ApplyRebuild,
        },
        {
            type = "slider",
            text = TXT.icon_size,
            dbPath = DB_KEY .. ".iconSize",
            default = 36,
            min = 24,
            max = 64,
            step = 4,
            apply = ApplyRebuild,
        },
        {
            type = "slider",
            text = TXT.row_height,
            dbPath = DB_KEY .. ".rowHeight",
            default = 40,
            min = 28,
            max = 64,
            step = 4,
            apply = ApplyRebuild,
        },
        {
            type = "dropdown",
            text = TXT.growth,
            dbPath = DB_KEY .. ".growthDirection",
            default = "DOWN",
            options = {
                { text = TXT.growth_down, value = "DOWN" },
                { text = TXT.growth_up, value = "UP" },
            },
            apply = ApplyRebuild,
        },
        {
            type = "check",
            text = TXT.verbose_log,
            dbPath = DB_KEY .. ".verboseProbeLog",
            default = true,
        },
        {
            type = "subtitle",
            text = TXT.subtitle_testing,
        },
        {
            key = "btnRebuild",
            type = "button",
            width = 0.5,
            text = TXT.btn_force_rebuild,
            onClick = function()
                if T.PrivateAuraList then
                    T.PrivateAuraList:RebuildAnchors()
                end
            end,
        },
        {
            key = "btnSnapshot",
            type = "button",
            width = 0.5,
            text = TXT.btn_dump_snapshot,
            onClick = function()
                if T.PrivateAuraList then
                    T.PrivateAuraList:DumpSnapshot()
                end
            end,
        },
        {
            key = "btnTest",
            type = "button",
            width = 0.5,
            text = TXT.btn_toggle_test_mode,
            onClick = function()
                if T.PrivateAuraList then
                    T.PrivateAuraList:ToggleTestMode()
                end
            end,
        },
        {
            type = "subtitle",
            text = TXT.log_hint,
        },
        }
    end,
})

end)
