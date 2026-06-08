-- S1 大秘境 Boss 内置 eventID 触发方案
-- 基于 encounterEvent 的 {event:xx} 规则，与 spell 规则共存

local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

T.SemanticBuiltinEventPlansVersionS14 = "builtin_event_plans_s14_v2"

T.Assets:Define("SemanticBuiltinEventPlansS14", {
    targetTable = T,
    targetKey = "SemanticBuiltinEventPlansS14",
    factory = function()
        return {
    -- =============================================
    -- 通天峰 (Skyreach, instanceID=1209)
    -- =============================================

    -- Ranjit (1698)
    ["dungeon:1209:1698"] = [[
{event:5} {BOSS}{spell:156793}
{event:11} {治疗}治疗预铺
{event:13} {BOSS}{spell:153315}
{event:19} {BOSS}{spell:1258152}
{event:29} {BOSS}{spell:156793}
{event:32} {BOSS}{spell:1252690}
    ]],

    -- Araknath (1699)
    ["dungeon:1209:1699"] = [[
{event:28} {BOSS}{spell:154135}
{event:49} {BOSS}{spell:154135}
    ]],

    -- Rukhran (1700)
    ["dungeon:1209:1700"] = [[
{event:5} {坦克}{BOSS}{spell:1253519}
{event:6} {治疗}注意刷坦
{event:12} {BOSS}{spell:153810}
{event:15} {坦克,输出}转火小怪
{event:17} {BOSS}{spell:1253510}
{event:33} {坦克,输出}转火小怪
{event:35} {所有人}快找掩体
{event:46} {所有人}安全安全
    ]],

    -- High Sage Viryx (1701)
    ["dungeon:1209:1701"] = [[
{event:6} {治疗}单刷点名
{event:8} {坦克,输出}打断读条
{event:15} {坦克,输出}转火小怪
{event:16} {治疗}单刷点名
{event:20} {坦克,输出}打断读条
{event:26} {治疗}单刷点名
{event:29} {BOSS}{spell:1253538}
    ]],

    -- =============================================
    -- 执政团之座 (Seat of the Triumvirate, instanceID=1753)
    -- =============================================

    -- Zuraal the Ascended (2065)
    ["dungeon:1753:2065"] = [[
{event:24} {坦克,输出}转火小怪
    ]],

    -- Saprish (2066)
    ["dungeon:1753:2066"] = [[
{event:20} {所有人}全注小球
{event:32} {所有人}快开减伤
    ]],

    -- Viceroy Nezhar (2067)
    ["dungeon:1753:2067"] = [[
{event:4} {坦克,输出}打断读条
{event:6} {所有人}准备躲球
{event:8} {坦克,输出}打断读条
{event:10} {所有人}注意躲球
{event:12} {治疗}准备AOE
{event:20} {坦克,输出}打断读条
{event:24} {所有人}准备躲球
{event:26} {治疗}准备AOE
{event:28} {所有人}注意躲球
{event:30} {坦克,输出}控杀小怪
{event:36} {坦克,输出}打断读条
{event:42} {坦克,输出}打断读条
{event:45} {所有人}小心击飞
{event:48} {所有人}靠近中场
{event:52} {治疗}治疗预铺
{event:56} {治疗,输出}快开减伤
{event:57} {治疗}大招抬血
    ]],

    -- L'ura (2068)
    ["dungeon:1753:2068"] = [[
{event:15} {所有人}注意自爆
{event:20} {所有人}安全安全
{event:53} {所有人}安全安全
    ]],

    -- =============================================
    -- 萨隆矿坑 (Pit of Saron, instanceID=658)
    -- =============================================

    -- Forgemaster Garfrost (1999)
    ["dungeon:658:1999"] = [[
{event:4} {BOSS}{spell:1261299}
{event:24} {所有人}注意躲圈
{event:40} {所有人}快开减伤
{event:43} {所有人}注意躲圈
{event:44} {治疗}驱散队友
    ]],

    -- Scourgelord Tyrannus (2000)
    ["dungeon:658:2000"] = [[
{event:4} {BOSS}{spell:1262745}
{event:14} {坦克}小心击退
{event:17} {所有人}躲开大圈
{event:24} {所有人}注意躲圈
{event:33} {BOSS}{spell:1262745}
{event:41} {坦克}小心击退
{event:44} {所有人}躲开大圈
{event:52} {所有人}{BOSS}{spell:1263406}
{event:56} {坦克,输出}激活大怪
{event:58} {坦克,输出}打断读条
{event:60} {治疗,输出}快开减伤
{event:67} {坦克,输出}打断读条
{event:69} {所有人}注意躲圈
    ]],

    -- Ick & Krick (2001)
    ["dungeon:658:2001"] = [[
{event:1} {所有人}快开减伤
{event:5} {所有人}准备诅咒
{event:7} {坦克,输出}转火小怪
{event:8} {坦克,输出}打断读条
{event:11} {坦克,治疗}坦克减伤
{event:21} {所有人}准备AOE
{event:24} {所有人}注意躲圈
{event:25} {坦克,输出}打断读条
{event:30} {坦克,治疗}坦克减伤
{event:40} {所有人}准备AOE
{event:43} {所有人}注意躲圈
{event:50} {所有人}准备追人
    ]],

    -- =============================================
    -- 艾杰斯亚学院 (Algeth'ar Academy, instanceID=2526)
    -- =============================================

    -- Vexamus (2562)
    ["dungeon:2526:2562"] = [[
{event:2} {所有人}准备吃球
{event:5} {坦克}坦克拉前
{event:15} {所有人}准备放水
{event:20} {所有人}准备吃球
{event:23} {坦克}坦克拉前
{event:33} {所有人}准备放水
{event:40} {所有人}准备击退
{event:43} {所有人}注意躲圈
    ]],

    -- Overgrown Ancient (2563)
    ["dungeon:2526:2563"] = [[
{event:9} {坦克,治疗}坦克减伤
{event:18} {所有人}注意躲圈
{event:30} {坦克,输出}准备大怪
{event:32} {坦克,输出}转火大怪
{event:37} {坦克,治疗}坦克减伤
{event:38} {坦克,输出}打断大怪
{event:51} {所有人}注意躲圈
{event:55} {所有人}准备AOE
    ]],

    -- Crawth (2564)
    ["dungeon:2526:2564"] = [[
{event:5} {坦克}注意减伤
{event:6} {治疗}注意刷坦
{event:14} {所有人}停止施法
{event:20} {所有人}躲开正面
    ]],

    -- Echo of Doragosa (2565)
    ["dungeon:2526:2565"] = [[
{event:9} {坦克,治疗}坦克减伤
{event:14} {所有人}准备点名
{event:17} {治疗}注意驱散
{event:21} {坦克,治疗}坦克减伤
{event:24} {所有人}准备拉人
{event:30} {所有人}躲开大圈
    ]],

    -- =============================================
    -- 风行者之塔 (Windrunner Spire, instanceID=2805)
    -- =============================================

    -- Emberdawn (3056)
    ["dungeon:2805:3056"] = [[
{event:5} {所有人}准备点名
{event:11} {坦克}注意减伤
{event:12} {治疗}注意刷坦
{event:16} {所有人}准备吹风
{event:19} {所有人}你是阵头前
{event:22} {输出}快开减伤
{event:37} {所有人}吹风结束
    ]],

    -- Derelict Duo (3057)
    ["dungeon:2805:3057"] = [[
{event:2} {坦克,输出}打断毒镖
{event:16} {坦克}注意减伤
{event:17} {治疗}注意刷坦
{event:23} {所有人}准备诅咒
{event:37} {输出}快开减伤
{event:46} {所有人}准备点名
{event:48} {治疗}治疗预铺
    ]],

    -- Commander Kroluk (3058)
    ["dungeon:2805:3058"] = [[
{event:3} {坦克}注意减伤
{event:5} {治疗}注意刷坦
{event:14} {所有人}注意躲圈
{event:18} {所有人}靠近队友
{event:30} {坦克}注意减伤
{event:31} {治疗}注意刷坦
{event:45} {所有人}靠近队友
{event:54} {坦克}注意减伤
{event:55} {治疗}注意刷坦
{event:69} {所有人}靠近队友
{event:75} {所有人}准备AOE
{event:83} {坦克,输出}打断毒镖
    ]],

    -- The Restless Heart (3059)
    ["dungeon:2805:3059"] = [[
{event:9} {所有人}注意躲圈
{event:15} {治疗,输出}踩圈下层
{event:21} {所有人}准备AOE
{event:25} {所有人}准备踩圈
{event:32} {所有人}踩圈上天
{event:47} {所有人}注意躲圈
{event:53} {治疗,输出}踩圈下层
{event:57} {坦克}小心击退
{event:73} {所有人}准备监禁
{event:87} {所有人}准备AOE
{event:91} {所有人}准备踩圈
{event:98} {所有人}踩圈上天
{event:112} {所有人}注意躲圈
{event:118} {治疗,输出}踩圈下层
{event:122} {坦克}小心击退
{event:138} {所有人}准备监禁
{event:151} {所有人}准备AOE
{event:155} {所有人}准备踩圈
{event:162} {所有人}踩圈上天
{event:177} {所有人}注意躲圈
{event:183} {治疗,输出}踩圈下层
{event:187} {坦克}小心击退
    ]],

    -- =============================================
    -- 魔导师平台 (Magisters' Terrace, instanceID=2811)
    -- =============================================

    -- Arcanotron Custos (3071)
    ["dungeon:2811:3071"] = [[
{event:5} {坦克,治疗}坦克击退
{event:16} {所有人}小心击退
{event:20} {所有人}准备点名
{event:24} {治疗}驱散魔法
{event:28} {坦克,治疗}坦克击退
{event:39} {所有人}小心击退
{event:46} {所有人}准备吃球
{event:49} {所有人}以上阶段
{event:68} {所有人}以上结束
    ]],

    -- Seranel Sunlash (3072)
    ["dungeon:2811:3072"] = [[
{event:7} {所有人}准备点名
{event:17} {所有人}躲开大圈
{event:20} {治疗}治疗预铺
{event:22} {所有人}注意躲圈
{event:26} {所有人}注意躲圈
{event:27} {坦克}注意减伤
{event:30} {所有人}进攻驱散魔法
{event:36} {所有人}准备点名
{event:38} {治疗}治疗预铺
{event:40} {所有人}注意躲圈
{event:44} {所有人}注意躲圈
    ]],

    -- Gemellus (3073)
    ["dungeon:2811:3073"] = [[
{event:5} {所有人}首领复制
{event:14} {所有人}准备点名
{event:25} {所有人}准备点名
{event:38} {所有人}准备拉人
{event:50} {所有人}安全安全
    ]],

    -- Degentrius (3074)
    ["dungeon:2811:3074"] = [[
{event:2} {坦克}注意减伤
{event:3} {治疗}注意刷坦
{event:6} {治疗}驱散魔法
{event:16} {所有人}准备接圈
{event:18} {所有人}接圈
{event:20} {所有人}准备躲球
{event:26} {坦克}注意减伤
{event:27} {治疗}注意刷坦
{event:30} {治疗}驱散魔法
    ]],

    -- =============================================
    -- 迈萨拉洞窟 (Maisara Caverns, instanceID=2874)
    -- =============================================

    -- Murojin and Nekraxx (3212)
    ["dungeon:2874:3212"] = [[
{event:5} {坦克}小心击飞
{event:6} {治疗}坦克流血
{event:12} {所有人}准备疾病
{event:20} {所有人}躲开陷阱
{event:28} {所有人}注意躲圈
{event:32} {所有人}准备监禁
{event:40} {治疗}驱散魔法
    ]],

    -- Vordaza (3213)
    ["dungeon:2874:3213"] = [[
{event:2} {坦克}注意减伤
{event:3} {治疗}注意刷坦
{event:14} {所有人}准备点名
{event:25} {所有人}躲开头前
{event:35} {坦克}注意减伤
{event:36} {治疗}注意刷坦
{event:48} {所有人}准备点名
{event:59} {所有人}躲开头前
{event:68} {所有人}准备破盾
{event:71} {所有人}快开减伤
{event:80} {所有人}注意躲球
    ]],

    -- Raktul (3214)
    ["dungeon:2874:3214"] = [[
{event:2} {坦克}注意减伤
{event:4} {坦克}贴边放水
{event:5} {治疗}注意刷坦
{event:6} {所有人}注意躲圈
{event:12} {所有人}注意躲圈
{event:18} {所有人}注意躲圈
{event:24} {坦克,输出}转火小怪
{event:29} {坦克}注意减伤
{event:31} {坦克}贴边放水
{event:36} {所有人}注意躲圈
{event:42} {所有人}注意躲圈
{event:49} {所有人}注意躲圈
{event:52} {坦克,输出}转火小怪
{event:55} {坦克}注意减伤
{event:57} {坦克}贴边放水
{event:66} {所有人}注意躲圈
{event:70} {所有人}阶段转换
{event:80} {所有人}控断大怪
{event:86} {所有人}快开减伤
{event:119} {所有人}以上结束
    ]],

    -- =============================================
    -- 节点希纳纳斯 (Nexus-Point Xenas, instanceID=2915)
    -- =============================================

    -- Chief Corewright Kasreth (3328)
    ["dungeon:2915:3328"] = [[
{event:2} {所有人}注意射线
{event:6} {所有人}准备点名
{event:12} {所有人}注意躲圈
{event:14} {所有人}注意射线
{event:18} {所有人}准备点名
{event:24} {所有人}注意躲圈
{event:26} {所有人}注意射线
{event:30} {所有人}准备点名
{event:36} {所有人}注意射线
{event:38} {所有人}集合引球
{event:42} {治疗}治疗预铺
{event:46} {所有人}小心击退
{event:48} {所有人}快开减伤
    ]],

    -- Corewarden Nysarra (3332)
    ["dungeon:2915:3332"] = [[
{event:2} {坦克}注意减伤
{event:3} {治疗}注意刷坦
{event:5} {所有人}准备点名
{event:19} {坦克}注意减伤
{event:20} {治疗}注意刷坦
{event:22} {所有人}小怪激活
{event:24} {所有人}准备点名
{event:26} {坦克,输出}打断大怪
{event:32} {所有人}准备以上
{event:37} {所有人}快进圣光
{event:39} {治疗,输出}快开减伤
{event:55} {所有人}以上结束
    ]],

    -- Lothraxion (3333)
    ["dungeon:2915:3333"] = [[
{event:2} {坦克}注意减伤
{event:3} {治疗}注意刷坦
{event:12} {所有人}八码分散
{event:16} {所有人}注意躲圈
{event:24} {所有人}躲开射线
{event:29} {坦克}注意减伤
{event:30} {治疗}注意刷坦
{event:34} {所有人}躲开射线
{event:37} {所有人}八码分散
{event:45} {所有人}躲开射线
{event:53} {所有人}准备击飞
{event:60} {所有人}打断光头
    ]],
        }
    end,
})

return true

end)
