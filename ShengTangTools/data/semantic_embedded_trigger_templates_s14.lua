local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

T.SemanticEmbeddedTriggerTemplatesVersionS14 = "embedded_trigger_templates_s14_v1"

T.Assets:Define("SemanticEmbeddedTriggerTemplatesS14", {
    targetTable = T,
    targetKey = "SemanticEmbeddedTriggerTemplatesS14",
    factory = function()
        return {
    textByEncounterID = {
        [3056] = {
            [466064] = "躲正面",
            [466556] = "进罩子",
        },
    },
    textBySpellID = {
    },
    retimeByEncounterID = {
    },
        }
    end,
})

return true

end)
