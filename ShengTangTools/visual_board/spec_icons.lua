local T, C, L = unpack(select(2, ...))

-- 视觉战术板专精图标数据源：运行时基于 12.0 API 动态构建全职业全专精图标，不硬编码 fileID。
local SpecIcons = {}
T.VisualBoardSpecIcons = SpecIcons

local cachedClasses

local function BuildColor(classFile)
    if C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(classFile)
        if color then
            return { r = color.r, g = color.g, b = color.b }
        end
    end
    return { r = 1, g = 1, b = 1 }
end

local function BuildClasses()
    local classes = {}
    local numClasses = GetNumClasses and GetNumClasses() or 0
    for classID = 1, numClasses do
        local classInfo = C_CreatureInfo and C_CreatureInfo.GetClassInfo(classID)
        if type(classInfo) == "table" and classInfo.classFile then
            local classFile = classInfo.classFile
            local className = classInfo.className or classFile
            local entry = {
                classID = classID,
                classFile = classFile,
                className = className,
                color = BuildColor(classFile),
                icon = "classicon-" .. string.lower(classFile),
                specs = {},
            }
            local numSpecs = GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(classID) or 0
            for specIndex = 1, numSpecs do
                local specID, name, _, icon, role = GetSpecializationInfoForClassID(classID, specIndex)
                if specID then
                    entry.specs[#entry.specs + 1] = {
                        specID = specID,
                        name = name,
                        icon = icon,
                        role = role,
                    }
                end
            end
            classes[#classes + 1] = entry
        end
    end
    return classes
end

function SpecIcons:GetClasses()
    if not cachedClasses then
        cachedClasses = BuildClasses()
    end
    return cachedClasses
end

function SpecIcons:GetSpecIcon(specID)
    for _, class in ipairs(self:GetClasses()) do
        for _, spec in ipairs(class.specs) do
            if spec.specID == specID then
                return spec.icon
            end
        end
    end
    return nil
end

-- classFile（如 "PRIEST"）→ 职业图标 atlas（classicon-priest）。
-- 用于只解析出职业、解析不出具体专精时的中性兜底。无匹配返回 nil。
function SpecIcons:GetClassIcon(classFile)
    if type(classFile) ~= "string" or classFile == "" then
        return nil
    end
    for _, class in ipairs(self:GetClasses()) do
        if class.classFile == classFile then
            return class.icon
        end
    end
    return nil
end

local function Contains(haystack, needle)
    if needle == "" then
        return true
    end
    return string.find(string.lower(tostring(haystack or "")), needle, 1, true) ~= nil
end

function SpecIcons:Search(query)
    local needle = string.lower(tostring(query or ""))
    needle = needle:gsub("^%s+", ""):gsub("%s+$", "")
    local results = {}
    for _, class in ipairs(self:GetClasses()) do
        local classMatched = Contains(class.className, needle) or Contains(class.classFile, needle)
        if classMatched then
            results[#results + 1] = {
                kind = "class",
                classFile = class.classFile,
                className = class.className,
                specName = nil,
                icon = class.icon,
                label = class.className,
            }
        end
        for _, spec in ipairs(class.specs) do
            if classMatched or Contains(spec.name, needle) then
                results[#results + 1] = {
                    kind = "spec",
                    classFile = class.classFile,
                    className = class.className,
                    specName = spec.name,
                    icon = spec.icon,
                    label = spec.name .. " " .. class.className,
                }
            end
        end
    end
    return results
end
