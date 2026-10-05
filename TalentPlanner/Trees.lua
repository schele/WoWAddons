local addonName, ns = ...

-- The class's talent trees, read from the game every time they are wanted,
-- never from a table of our own: whatever WoW Forever has changed about a
-- talent, the planner shows what the client says. The result is the plain
-- table Plan.lua works on.

local Trees = {}
ns.Trees = Trees

-- The calls the planner cannot draw without.
Trees.CALLS = { "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo", "GetTalentPrereqs" }

function Trees.Missing()
    local missing = {}
    for _, name in ipairs(Trees.CALLS) do
        if type(_G[name]) ~= "function" then
            missing[#missing + 1] = name
        end
    end
    return missing
end

--- What the planner says instead of drawing.
function Trees.Unreadable(missing)
    if missing and #missing > 0 then
        return "This client has no " .. table.concat(missing, ", ") .. ", so the talent trees cannot be read."
    end
    return "The talent trees could not be read from this client."
end

--- A tab's name, icon and points spent. Classic gives the name first;
-- newer clients put an ID before it and a description after.
local function tabInfo(tab)
    local first, second, third, fourth, fifth = GetTalentTabInfo(tab)
    if type(first) == "string" then
        return first, second, third
    end
    return second, fourth, fifth
end

local function readTree(tab)
    local name, icon = tabInfo(tab)
    local tree = { name = name or ("Tree " .. tab), icon = icon, spent = 0, talents = {} }
    local at = {}

    for index = 1, GetNumTalents(tab) or 0 do
        local talentName, talentIcon, tier, column, rank, maxRank = GetTalentInfo(tab, index)
        if type(talentName) == "string" and type(tier) == "number" and type(column) == "number" then
            local talent = {
                name = talentName, icon = talentIcon, tier = tier, column = column,
                rank = type(rank) == "number" and rank or 0,
                maxRank = type(maxRank) == "number" and maxRank or 1,
            }
            tree.talents[index] = talent
            tree.spent = tree.spent + talent.rank
            at[tier .. ":" .. column] = index
        end
    end

    -- Prerequisites come as a tier and column; the plan wants the talent.
    for index, talent in pairs(tree.talents) do
        local tier, column = GetTalentPrereqs(tab, index)
        if type(tier) == "number" and type(column) == "number" then
            talent.prereq = at[tier .. ":" .. column]
        end
    end
    return tree
end

--- The trees, or nil and the calls this client lacks (empty when a call
-- raised or the class has none).
function Trees.Read()
    local missing = Trees.Missing()
    if #missing > 0 then
        return nil, missing
    end
    local trees = ns.Guarded(function()
        local read = {}
        for tab = 1, GetNumTalentTabs() or 0 do
            read[tab] = readTree(tab)
        end
        return read
    end)
    if not trees or #trees == 0 then
        return nil, {}
    end
    return trees
end

--- Talent points waiting to be spent, or nil when the client will not say.
function Trees.Unspent()
    return ns.Guarded(function()
        local points
        if type(UnitCharacterPoints) == "function" then
            points = UnitCharacterPoints("player")
        elseif type(GetUnspentTalentPoints) == "function" then
            points = GetUnspentTalentPoints()
        end
        return type(points) == "number" and points or nil
    end)
end
