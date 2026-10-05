local addonName, ns = ...

-- The rules of a plan, and nothing else: no game calls, no frames. A plan is
-- an ordered list of points, each { tab, index }; point n is taken at level
-- n + 9. The trees come in as a plain table (see Trees.lua), so every rule
-- here can be tested without a client.

local Plan = {}
ns.Plan = Plan

-- Level 60's points: one a level from 10.
Plan.MAX = 51
-- Points a tree needs before each tier below the first.
local PER_TIER = 5

function Plan.LevelOf(n)
    return n + 9
end

local function talentOf(trees, tab, index)
    local tree = trees[tab]
    return tree and tree.talents and tree.talents[index]
end

--- Points on one talent among the first `upto` points (all by default).
function Plan.Count(points, tab, index, upto)
    local count = 0
    for n = 1, math.min(upto or #points, #points) do
        local point = points[n]
        if point[1] == tab and point[2] == index then
            count = count + 1
        end
    end
    return count
end

--- Points in one tree among the first `upto` points (all by default).
function Plan.TreeCount(points, tab, upto)
    local count = 0
    for n = 1, math.min(upto or #points, #points) do
        if points[n][1] == tab then
            count = count + 1
        end
    end
    return count
end

-- Whether the talent can be the point after the first `before` points.
local function checkAt(trees, points, before, tab, index)
    local talent = talentOf(trees, tab, index)
    if not talent then
        return false, string.format("Tree %s has no talent %s.", tostring(tab), tostring(index))
    end
    if before >= Plan.MAX then
        return false, string.format("The plan is full: %d points.", Plan.MAX)
    end
    if Plan.Count(points, tab, index, before) >= talent.maxRank then
        return false, string.format("%s is already at %d/%d.", talent.name, talent.maxRank, talent.maxRank)
    end
    local needed = PER_TIER * (talent.tier - 1)
    if Plan.TreeCount(points, tab, before) < needed then
        return false, string.format("%s needs %d points in %s first.", talent.name, needed, trees[tab].name)
    end
    local prereq = talent.prereq and talentOf(trees, tab, talent.prereq)
    if prereq and Plan.Count(points, tab, talent.prereq, before) < prereq.maxRank then
        return false, string.format("%s needs %s at %d/%d first.", talent.name, prereq.name, prereq.maxRank, prereq.maxRank)
    end
    return true
end

--- Whether the talent could be added after the plan as it stands.
function Plan.Check(trees, points, tab, index)
    return checkAt(trees, points, #points, tab, index)
end

function Plan.Add(trees, points, tab, index)
    local ok, why = Plan.Check(trees, points, tab, index)
    if ok then
        points[#points + 1] = { tab, index }
    end
    return ok, why
end

--- Every point checked in order: true, or false with the first bad point's
-- number and why.
function Plan.Validate(trees, points)
    for n = 1, #points do
        local ok, why = checkAt(trees, points, n - 1, points[n][1], points[n][2])
        if not ok then
            return false, n, why
        end
    end
    return true
end

--- "Point 7 (level 16), Feral Instinct": how the planner names a point.
function Plan.Describe(trees, n, point)
    local talent = talentOf(trees, point[1], point[2])
    local name = talent and talent.name or string.format("tree %s talent %s", tostring(point[1]), tostring(point[2]))
    return string.format("Point %d (level %d), %s", n, Plan.LevelOf(n), name)
end

--- Take out the talent's last planned point, if the plan stays valid
-- without it. True with the removed point's number, or false and why: the
-- later point that depends on it.
function Plan.Remove(trees, points, tab, index)
    local last
    for n = #points, 1, -1 do
        if points[n][1] == tab and points[n][2] == index then
            last = n
            break
        end
    end
    if not last then
        local talent = talentOf(trees, tab, index)
        return false, string.format("%s is not in the plan.", talent and talent.name or "That talent")
    end

    local rest = {}
    for n, point in ipairs(points) do
        if n ~= last then
            rest[#rest + 1] = point
        end
    end
    local ok, bad = Plan.Validate(trees, rest)
    if not ok then
        -- Numbered as the player sees the plan now, with the point still in.
        local original = bad >= last and bad + 1 or bad
        return false, Plan.Describe(trees, original, points[original]) .. ", depends on it."
    end

    table.remove(points, last)
    return true, last
end

function Plan.Undo(points)
    if #points == 0 then
        return nil
    end
    return table.remove(points)
end

--- The levels a talent's points are taken at, in order.
function Plan.Levels(points, tab, index)
    local levels = {}
    for n, point in ipairs(points) do
        if point[1] == tab and point[2] == index then
            levels[#levels + 1] = Plan.LevelOf(n)
        end
    end
    return levels
end

--- The player's rank in every talent, from the trees: ranks[tab][index].
function Plan.RanksOf(trees)
    local ranks = {}
    for tab, tree in pairs(trees) do
        ranks[tab] = {}
        for index, talent in pairs(tree.talents) do
            ranks[tab][index] = talent.rank or 0
        end
    end
    return ranks
end

local function rankIn(ranks, tab, index)
    return ranks[tab] and ranks[tab][index] or 0
end

--- The first point the player has not taken: its number, its talent, and
-- the rank it brings that talent to. Points already learned are passed
-- over, wherever in the plan's order they were learned.
function Plan.Next(points, ranks)
    local counted = {}
    for n, point in ipairs(points) do
        local key = point[1] .. ":" .. point[2]
        counted[key] = (counted[key] or 0) + 1
        if rankIn(ranks, point[1], point[2]) < counted[key] then
            return n, point[1], point[2], counted[key]
        end
    end
    return nil
end

--- Talents holding more points than the plan had by the time as many points
-- were spent: over[tab][index] = true.
function Plan.Over(points, ranks)
    local spent = 0
    for _, tree in pairs(ranks) do
        for _, rank in pairs(tree) do
            spent = spent + rank
        end
    end

    local over = {}
    for tab, tree in pairs(ranks) do
        for index, rank in pairs(tree) do
            if rank > Plan.Count(points, tab, index, spent) then
                over[tab] = over[tab] or {}
                over[tab][index] = true
            end
        end
    end
    return over
end
