local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("buffCheck.enabled", function()

T.BuffCheck = T.BuffCheck or {}
T.Assets:Define("BuffCheckData", {
    targetTable = T.BuffCheck,
    targetKey = "Data",
    factory = function()
        return {
    Food = {
        [308488] = 30, [308506] = 30, [308434] = 30, [308514] = 30, [327708] = 20,
        [327706] = 20, [327709] = 20, [308525] = 18, [327707] = 30, [308637] = 30,
        [308474] = 18, [308504] = 18, [308430] = 18, [308509] = 18, [327704] = 18,
        [327701] = 18, [327705] = 18, [327702] = 18,
        [382145] = 70, [382150] = 70, [382146] = 70, [382149] = 70, [396092] = 90,
        [382246] = 70, [382247] = 90, [382152] = 90, [382153] = 90, [382157] = 90,
        [382230] = 70, [382231] = 70, [382232] = 70, [382154] = 90, [382155] = 90,
        [382156] = 90, [382234] = 90, [382235] = 90, [382236] = 90,
    },
    FoodHeaders = { 0, 70, 90 },
    Flask = {
        [1236763] = 165, [1239355] = 165, [1235057] = 165, [1239755] = 165,
        [1236767] = 165, [1235111] = 165, [1235110] = 165, [1235108] = 165,
    },
    FlaskHeaders = { 0, 152, 165 },
    Rune = {
        [224001] = 5, [270058] = 6, [317065] = 6, [347901] = 18, [367405] = 18,
        [393438] = 87, [453250] = 87, [1234969] = 733, [1242347] = 733, [1264426] = 25,
    },
    RuneItems = { 259085, 246492, 224572, 201325, 181468 },
    InfiniteRuneItems = { 243191, 211495, 190384 },
    Vantus = {
        [269276] = true, [269405] = true, [269408] = true, [269407] = true, [269409] = true,
        [269411] = true, [269412] = true, [269413] = true, [298622] = true, [298640] = true,
        [298642] = true, [298643] = true, [298644] = true, [298645] = true, [298646] = true,
        [302914] = true, [306475] = true, [306480] = true, [306476] = true, [306477] = true,
        [306478] = true, [306484] = true, [306485] = true, [306479] = true, [313550] = true,
        [313551] = true, [313554] = true, [313556] = true, [311445] = true, [334132] = true,
        [311448] = true, [311446] = true, [311447] = true, [311449] = true, [311450] = true,
        [311451] = true, [311452] = true, [334131] = true, [354384] = true, [354385] = true,
        [354386] = true, [354387] = true, [354388] = true, [354389] = true, [354390] = true,
        [354391] = true, [354392] = true, [354393] = true, [384233] = true, [384234] = true,
        [384235] = true, [384229] = true, [384228] = true, [384227] = true, [384192] = true,
        [384203] = true, [384201] = true, [384239] = true, [384240] = true, [384241] = true,
        [384245] = true, [384246] = true, [384247] = true, [384220] = true, [384221] = true,
        [384222] = true, [384210] = true, [384209] = true, [384208] = true, [384214] = true,
        [384215] = true, [384216] = true, [384154] = true, [384248] = true, [384306] = true,
    },
    RaidBuffs = {
        { id = "ap", checkKey = "raidBuffAP", class = "WARRIOR", spellID = 6673, labelKey = "GUI_BUFF_RAIDBUFF_AP", spells = { [6673] = true, [264761] = true } },
        { id = "stamina", checkKey = "raidBuffStamina", class = "PRIEST", spellID = 21562, labelKey = "GUI_BUFF_RAIDBUFF_STAMINA", spells = { [21562] = true, [264764] = true } },
        { id = "intellect", checkKey = "raidBuffIntellect", class = "MAGE", spellID = 1459, labelKey = "GUI_BUFF_RAIDBUFF_INTELLECT", spells = { [1459] = true, [264760] = true } },
        { id = "versatility", checkKey = "raidBuffVersatility", class = "DRUID", spellID = 1126, labelKey = "GUI_BUFF_RAIDBUFF_VERSATILITY", spells = { [1126] = true } },
        { id = "mastery", checkKey = "raidBuffMastery", class = "SHAMAN", spellID = 462854, labelKey = "GUI_BUFF_RAIDBUFF_MASTERY", spells = { [462854] = true } },
        { id = "movement", checkKey = "raidBuffMovement", class = "EVOKER", spellID = 381748, labelKey = "GUI_BUFF_RAIDBUFF_MOVEMENT", spells = {
            [381758] = true, [381732] = true, [381741] = true, [381746] = true, [381748] = true,
            [381750] = true, [381749] = true, [381751] = true, [381752] = true, [381753] = true,
            [381754] = true, [381756] = true, [381757] = true,
        } },
    },
    PersonalChecks = {
        { id = "food", checkKey = "food", spellID = 396092, labelKey = "GUI_BUFF_CHECK_FOOD", missingKey = "BUFF_MISSING_FOOD" },
        { id = "flask", checkKey = "flask", spellID = 1236763, labelKey = "GUI_BUFF_CHECK_FLASK", missingKey = "BUFF_MISSING_FLASK" },
        { id = "rune", checkKey = "rune", spellID = 1264426, labelKey = "GUI_BUFF_CHECK_RUNE", missingKey = "BUFF_MISSING_RUNE" },
        { id = "vantus", checkKey = "vantus", spellID = 384233, labelKey = "GUI_BUFF_CHECK_VANTUS", missingKey = "BUFF_MISSING_VANTUS" },
        { id = "weaponEnchantMain", checkKey = "weaponEnchantMain", spellID = 33757, labelKey = "GUI_BUFF_CHECK_WEAPON_ENCHANT", missingKey = "BUFF_MISSING_OIL_MH" },
        { id = "weaponEnchantOff", checkKey = "weaponEnchantOff", spellID = 33757, labelKey = "GUI_BUFF_CHECK_WEAPON_ENCHANT_OH", missingKey = "BUFF_MISSING_OIL_OH" },
        { id = "durability", checkKey = "durability", icon = "Interface\\MINIMAP\\TRACKING\\Repair", labelKey = "GUI_BUFF_CHECK_DURABILITY", missingKey = "BUFF_MISSING_DURABILITY" },
    },
        }
    end,
})

end)
