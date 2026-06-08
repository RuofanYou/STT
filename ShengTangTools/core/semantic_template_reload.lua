local T, C, L = unpack(select(2, ...))
T.RegisterColdFile("semanticTimeline.editorLoaded", function()

local TemplateReload = {}
T.SemanticTemplateReload = TemplateReload

local TEAM_TAB = "team"

local function GetWorkbenchDB()
    local db = STT_DB and STT_DB.semanticTimeline
    local wb = db and db.workbench
    if type(wb) ~= "table" then
        return nil
    end
    if type(wb.bossTemplateVer) ~= "table" then
        wb.bossTemplateVer = {}
    end
    if type(wb.bossTemplateDigest) ~= "table" then
        wb.bossTemplateDigest = {}
    end
    return wb
end

local function UpdateBuiltinMetadata(sem, bossKeyText, digest)
    if not bossKeyText or bossKeyText == "" then
        return
    end

    local wb = GetWorkbenchDB()
    if not wb then
        return
    end

    wb.bossTemplateVer[bossKeyText] = T.SemanticBuiltinPlansVersionS14 or ""
    wb.bossTemplateDigest[bossKeyText] = digest
end

function TemplateReload.ReloadTeamPlan(sem, bossKey)
    if not (sem and bossKey and sem.GetBuiltinPlanText and sem.EnsurePlanDocumentForBossTab and sem.SavePlanDocument and sem.SerializeBossSelectorKey and sem.ComputeContentDigest) then
        return { ok = false, reason = "missing_dependency", text = "" }
    end

    local bossKeyText = sem:SerializeBossSelectorKey(bossKey)
    if not bossKeyText or bossKeyText == "" then
        return { ok = false, reason = "invalid_boss", text = "" }
    end

    local builtinText = sem:GetBuiltinPlanText(bossKey)
    local document = sem:EnsurePlanDocumentForBossTab(bossKey, TEAM_TAB)
    if not document then
        return { ok = false, reason = "missing_document", text = builtinText }
    end

    local ok = sem:SavePlanDocument(document, builtinText, "reload_template") == true
    if not ok then
        return { ok = false, reason = "save_failed", text = builtinText }
    end

    local digest = sem.ComputeContentDigest(builtinText)
    UpdateBuiltinMetadata(sem, bossKeyText, digest)

    if T.debug then
        T.debug(string.format(
            "[SemanticTemplate] ReloadBuiltinTeamPlan: boss=%s",
            tostring(bossKeyText)
        ))
    end

    return {
        ok = true,
        text = builtinText,
        bossKeyText = bossKeyText,
        digest = digest,
    }
end

end)
