local addonName, ns = ...

-- Every place the player has gathered, from GatherMapDB.gathered. Each is
-- { continent, entry, x, y, key, point, stack }: `point` is its saved
-- record, and `stack` every place at that same spot, this one included (one
-- table, shared by all of them). Filed in a grid of 200-yard cells per
-- continent, so the minimap and the recorder look only at the few cells
-- around the player.

local Spawns = {}
ns.Spawns = Spawns

local CELL = 200
Spawns.CELL = CELL
-- Bumped by every change, so a cache built from the index can tell it is
-- out of date.
Spawns.version = 0

Spawns.KINDS = { herb = true, ore = true }
-- The name of a place whose entry is not listed and whose loot was unknown.
Spawns.LABEL = { herb = "Herb", ore = "Ore" }

local lists, grids, byKey, stacks = {}, {}, {}, {}

function Spawns.Key(continent, entry, x, y)
    return string.format("%d:%d:%.1f:%.1f", continent, entry, x, y)
end

local function cellKey(x, y)
    return math.floor(x / CELL) .. ":" .. math.floor(y / CELL)
end

local function spotKey(continent, x, y)
    return string.format("%d:%.1f:%.1f", continent, x, y)
end

local function add(continent, entry, x, y, point)
    local key = Spawns.Key(continent, entry, x, y)
    if byKey[key] then
        return byKey[key]
    end

    local spawn = { continent = continent, entry = entry, x = x, y = y, key = key, point = point }
    byKey[key] = spawn

    -- Places at one spot (Tin, then Silver, where they alternate) are one
    -- stack, drawn as one pin.
    local spot = spotKey(continent, x, y)
    local stack = stacks[spot]
    if not stack then
        stack = {}
        stacks[spot] = stack
    end
    table.insert(stack, spawn)
    spawn.stack = stack

    lists[continent] = lists[continent] or {}
    table.insert(lists[continent], spawn)

    grids[continent] = grids[continent] or {}
    local cell = cellKey(x, y)
    grids[continent][cell] = grids[continent][cell] or {}
    table.insert(grids[continent][cell], spawn)

    Spawns.version = Spawns.version + 1
    return spawn
end

local function removeFrom(list, item)
    for index = #(list or {}), 1, -1 do
        if list[index] == item then
            table.remove(list, index)
        end
    end
end

local function round(value)
    return math.floor(value * 10 + 0.5) / 10
end

--- A saved point's kind: the list's for a listed entry, else what was
-- saved. Nil for anything neither herb nor ore (the first GatherMap's pools
-- and chests).
local function kindOf(point)
    local node = ns.Nodes[point.entry]
    local kind = node and node.kind or point.kind
    return Spawns.KINDS[kind] and kind or nil
end

--- Index the saved gathers, in key order. Once, at login. A point that
-- cannot be placed, or is no herb or ore, is dropped from the saved
-- variables.
function Spawns.Load()
    local keys = {}
    for key in pairs(ns.db.gathered) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    for _, key in ipairs(keys) do
        local point = ns.db.gathered[key]
        local kind = type(point) == "table" and type(point.entry) == "number" and kindOf(point)
        if kind and type(point.continent) == "number" and type(point.x) == "number" and type(point.y) == "number" then
            point.kind = kind
            point.new = nil
            add(point.continent, point.entry, round(point.x), round(point.y), point)
        else
            ns.db.gathered[key] = nil
        end
    end
end

--- A new place for the saved `point`, rounded to a tenth of a yard.
function Spawns.AddPoint(continent, entry, x, y, point)
    return add(continent, entry, round(x), round(y), point)
end

--- Take `spawn` out of the index. Its saved point is the caller's to delete.
function Spawns.Remove(spawn)
    if byKey[spawn.key] ~= spawn then
        return
    end
    byKey[spawn.key] = nil
    removeFrom(spawn.stack, spawn)
    if #spawn.stack == 0 then
        stacks[spotKey(spawn.continent, spawn.x, spawn.y)] = nil
    end
    removeFrom(lists[spawn.continent], spawn)
    removeFrom((grids[spawn.continent] or {})[cellKey(spawn.x, spawn.y)], spawn)
    Spawns.version = Spawns.version + 1
end

function Spawns.Clear()
    lists, grids, byKey, stacks = {}, {}, {}, {}
    Spawns.version = Spawns.version + 1
end

--- What a place is: the list's { kind, name, skill, item } for a listed
-- entry; else, from what was saved, its loot's name and item and no skill.
function Spawns.Node(spawn)
    local node = ns.Nodes[spawn.entry]
    if node then
        return node
    end
    local point = spawn.point or {}
    return { kind = point.kind, name = point.itemName or Spawns.LABEL[point.kind] or "?", item = point.item }
end

function Spawns.All(continent)
    return lists[continent] or {}
end

function Spawns.ByKey(key)
    return byKey[key]
end

--- Call fn(spawn) for every place within `radius` yards of (x, y).
function Spawns.Near(continent, x, y, radius, fn)
    local grid = grids[continent]
    if not grid then
        return
    end
    local limit = radius * radius
    for cx = math.floor((x - radius) / CELL), math.floor((x + radius) / CELL) do
        for cy = math.floor((y - radius) / CELL), math.floor((y + radius) / CELL) do
            for _, spawn in ipairs(grid[cx .. ":" .. cy] or {}) do
                local dx, dy = spawn.x - x, spawn.y - y
                if dx * dx + dy * dy <= limit then
                    fn(spawn)
                end
            end
        end
    end
end

--- The nearest place of `entry` within `radius` yards of (x, y), or nil.
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
