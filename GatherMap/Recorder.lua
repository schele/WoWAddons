local addonName, ns = ...

-- Turns a loot window from a herb, vein, chest or pool into "gathered here":
-- the loot's source is the object's GUID, whose sixth field is its entry,
-- and the spawn is the nearest of that entry to the player.

local Recorder = {}
ns.Recorder = Recorder

-- How far off a gathered node's spawn can be. A player stands at a herb,
-- vein or chest; they fish a pool from 10 to 20 yards away.
Recorder.REACH = 15
Recorder.POOL_REACH = 30
-- A loot window on the same spawn again within this many seconds is the
-- same gather, reopened.
Recorder.REPEAT = 5

function Recorder.EntryFromGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local entry = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return entry and tonumber(entry)
end

local lastKey, lastTime

local function record(spawn, isNew)
    local now = GetTime()
    if spawn.key == lastKey and now - lastTime < Recorder.REPEAT then
        return
    end
    lastKey, lastTime = spawn.key, now

    local point = ns.db.gathered[spawn.key]
    if type(point) ~= "table" then
        point = { continent = spawn.continent, entry = spawn.entry, x = spawn.x, y = spawn.y, new = isNew }
        ns.db.gathered[spawn.key] = point
    end
    point.count = (point.count or 0) + 1
    point.last = time()
    -- Something grew here after all.
    ns.db.missing[spawn.key] = nil
    ns.Refresh()
end

--- Mark `spawn` "not here", or take the mark off. True when now marked.
function Recorder.ToggleMissing(spawn)
    local marked = not ns.db.missing[spawn.key]
    ns.db.missing[spawn.key] = marked and time() or nil
    ns.Refresh()
    return marked
end

--- The same for a spot's spawns together: all marked if any was not, else
-- all cleared. True when now marked.
function Recorder.ToggleMissingAll(members)
    local marked = false
    for _, spawn in ipairs(members) do
        if not ns.db.missing[spawn.key] then
            marked = true
        end
    end
    for _, spawn in ipairs(members) do
        ns.db.missing[spawn.key] = marked and time() or nil
    end
    ns.Refresh()
    return marked
end

--- A loot window opened. Counted when it came from a node GatherMap knows,
-- on one of the two continents, and the client says where the player is.
function Recorder.LootOpened()
    local entry = Recorder.EntryFromGUID(ns.Guarded(function()
        return (GetLootSourceInfo(1))
    end))
    local node = entry and ns.Nodes[entry]
    if not node then
        return
    end

    local x, y, _, continent = UnitPosition("player")
    if type(x) ~= "number" or (continent ~= 0 and continent ~= 1) then
        return
    end

    if node.kind == "pool" then
        local spawn = ns.Spawns.Nearest(continent, entry, x, y, Recorder.POOL_REACH)
        if spawn then
            record(spawn, false)
        end
        return
    end

    local spawn = ns.Spawns.Nearest(continent, entry, x, y, Recorder.REACH)
    if spawn then
        record(spawn, false)
    else
        record(ns.Spawns.AddPoint(continent, entry, x, y), true)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED")
frame:SetScript("OnEvent", function()
    ns.Guarded(Recorder.LootOpened)
end)

local resetAsked

ns.RegisterCommand("reset", "Forget every place you have gathered: /gmap reset gathered", function(rest)
    if rest ~= "gathered" then
        ns.Print("To forget every place you have gathered: /gmap reset gathered")
        return
    end

    local now = GetTime()
    if resetAsked and now - resetAsked <= 10 then
        resetAsked = nil
        for key in pairs(ns.db.gathered) do
            ns.db.gathered[key] = nil
        end
        for key in pairs(ns.db.missing) do
            ns.db.missing[key] = nil
        end
        ns.Print("Forgot every place you have gathered, and every spawn marked not here.")
        ns.Refresh()
        return
    end

    resetAsked = now
    ns.Print("This forgets every place you have gathered and every spawn marked not here, on every character. "
        .. "Type /gmap reset gathered again within 10 seconds to do it.")
end)
