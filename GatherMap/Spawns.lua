local addonName, ns = ...

-- Every spawn GatherMap knows: the data files' and the new points the
-- player found. Each is { continent, entry, x, y, key }, filed in a grid of
-- 200-yard cells per continent, so the minimap and the recorder look only at
-- the few cells around the player.

local Spawns = {}
ns.Spawns = Spawns

local CELL = 200
Spawns.CELL = CELL
-- Bumped by every spawn added after login, so a cache built from the index
-- can tell it is out of date.
Spawns.version = 0

local lists = {}
local grids = {}
local byKey = {}

function Spawns.Key(continent, entry, x, y)
    return string.format("%d:%d:%.1f:%.1f", continent, entry, x, y)
end

local function cellKey(cx, cy)
    return cx .. ":" .. cy
end

local function add(continent, entry, x, y)
    local key = Spawns.Key(continent, entry, x, y)
    if byKey[key] then
        return byKey[key]
    end

    local spawn = { continent = continent, entry = entry, x = x, y = y, key = key }
    byKey[key] = spawn

    lists[continent] = lists[continent] or {}
    table.insert(lists[continent], spawn)

    grids[continent] = grids[continent] or {}
    local cell = cellKey(math.floor(x / CELL), math.floor(y / CELL))
    local bucket = grids[continent][cell]
    if not bucket then
        bucket = {}
        grids[continent][cell] = bucket
    end
    table.insert(bucket, spawn)

    Spawns.version = Spawns.version + 1
    return spawn
end

local function round(value)
    return math.floor(value * 10 + 0.5) / 10
end

--- Take the data files' spawns and the saved new points. Once, at login.
function Spawns.Load()
    for continent, flat in pairs(ns.rawSpawns) do
        for index = 1, #flat - 2, 3 do
            if ns.Nodes[flat[index]] then
                add(continent, flat[index], flat[index + 1], flat[index + 2])
            end
        end
    end
    ns.rawSpawns = {}

    for _, point in pairs(ns.db.gathered) do
        if type(point) == "table" and point.new and type(point.continent) == "number"
            and type(point.x) == "number" and type(point.y) == "number" and ns.Nodes[point.entry] then
            add(point.continent, point.entry, round(point.x), round(point.y))
        end
    end
end

--- A place the data does not have, rounded to a tenth of a yard.
function Spawns.AddPoint(continent, entry, x, y)
    return add(continent, entry, round(x), round(y))
end

function Spawns.All(continent)
    return lists[continent] or {}
end

function Spawns.ByKey(key)
    return byKey[key]
end

--- Call fn(spawn) for every spawn within `radius` yards of (x, y).
function Spawns.Near(continent, x, y, radius, fn)
    local grid = grids[continent]
    if not grid then
        return
    end
    local limit = radius * radius
    for cx = math.floor((x - radius) / CELL), math.floor((x + radius) / CELL) do
        for cy = math.floor((y - radius) / CELL), math.floor((y + radius) / CELL) do
            local bucket = grid[cellKey(cx, cy)]
            if bucket then
                for _, spawn in ipairs(bucket) do
                    local dx, dy = spawn.x - x, spawn.y - y
                    if dx * dx + dy * dy <= limit then
                        fn(spawn)
                    end
                end
            end
        end
    end
end

--- The nearest spawn of `entry` within `radius` yards of (x, y), or nil.
function Spawns.Nearest(continent, entry, x, y, radius)
    local best, bestDistance
    Spawns.Near(continent, x, y, radius, function(spawn)
        if spawn.entry == entry then
            local distance = (spawn.x - x) ^ 2 + (spawn.y - y) ^ 2
            if not bestDistance or distance < bestDistance then
                best, bestDistance = spawn, distance
            end
        end
    end)
    return best
end

ns.OnLogin(Spawns.Load)
