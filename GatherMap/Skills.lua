local addonName, ns = ...

-- The player's Herbalism and Mining, read from the skill list, and how a
-- node's required skill looks against them.

local Skills = {}
ns.Skills = Skills

-- The skill list gives names, not IDs, so each profession is looked for
-- under its name in every client language.
local NAMES = {
    herb = { "Herbalism", "Kräuterkunde", "Herboristerie", "Herboristería", "Erbalismo", "Herborismo",
        "Травничество", "약초채집", "草药学", "草藥學" },
    ore = { "Mining", "Bergbau", "Minage", "Minería", "Estrazione", "Mineração",
        "Горное дело", "채광", "采矿", "採礦" },
}

local kindOf = {}
for kind, names in pairs(NAMES) do
    for _, name in ipairs(names) do
        kindOf[name] = kind
    end
end

Skills.LABEL = { herb = "Herbalism", ore = "Mining" }

Skills.RGB = {
    red = { 1, 0.1, 0.1 },
    orange = { 1, 0.5, 0.25 },
    yellow = { 1, 1, 0 },
    green = { 0.25, 0.75, 0.25 },
    grey = { 0.5, 0.5, 0.5 },
}

local ranks = { herb = 0, ore = 0 }
-- Whether each profession's line was listed by the last read that worked.
-- Until one has, neither is known, and the skill filters leave its nodes be.
local known = { herb = false, ore = false }

--- Read both skills again. A refusal leaves them as they were, and so does
-- a collapsed header: the lines under it are not listed, and reading that as
-- "no profession" would hide every herb and vein.
function Skills.Read()
    ns.Guarded(function()
        local found = { herb = 0, ore = 0 }
        local listed = { herb = false, ore = false }
        local collapsed = false
        for index = 1, GetNumSkillLines() do
            local name, isHeader, isExpanded, rank = GetSkillLineInfo(index)
            if isHeader then
                if not isExpanded then
                    collapsed = true
                end
            elseif kindOf[name] then
                found[kindOf[name]] = rank or 0
                listed[kindOf[name]] = true
            end
        end
        if collapsed then
            for kind in pairs(found) do
                if not listed[kind] then
                    found[kind] = ranks[kind]
                    listed[kind] = known[kind]
                end
            end
        end
        ranks, known = found, listed
    end)
end

function Skills.Get(kind)
    return ranks[kind] or 0
end

--- Whether the player's `kind` skill was found: its line listed by the last
-- read that worked.
function Skills.Known(kind)
    return known[kind] == true
end

--- How a node needing `required` looks at `skill`: "red" cannot be
-- gathered; then the skill-up colours, "orange" to "grey".
function Skills.Color(required, skill)
    if skill < required then
        return "red"
    elseif skill < required + 25 then
        return "orange"
    elseif skill < required + 50 then
        return "yellow"
    elseif skill < required + 100 then
        return "green"
    end
    return "grey"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:SetScript("OnEvent", function()
    Skills.Read()
    ns.Refresh()
end)

ns.OnLogin(Skills.Read)
