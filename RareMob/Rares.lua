local addonName, ns = ...

-- The merged view: the classic database's rares, and the sightings that say
-- which of them WoW Forever really has -- the player's own and those baked
-- into the release, less the baked copy of the player's own. A rare met in
-- game that the database lacks is described by its sighting alone.

local Rares = {}
ns.Rares = Rares

ns.AddDefaults({
    -- Rares no one has seen on WoW Forever yet, from the database alone.
    showUnseen = true,
})

-- A sighting's spot gets a pin of its own when the database has no spawn of
-- that rare this near it, in yards: a rare wanders, and the spot is the
-- player's, within nameplate range of it.
Rares.NEAR_SPAWN = 150
-- Sightings this near one already pinned share its pin.
Rares.SAME_SPOT = 50

-- Bumped by every change, so anything built from the view can tell it is
-- out of date.
Rares.version = 0

local merged          -- id -> merged sighting, until the next change
local placesCache = {} -- continent -> { version, places }

function Rares.Changed()
    Rares.version = Rares.version + 1
    merged = nil
end

local function add(into, id, sighting, own)
    if type(sighting) ~= "table" or type(sighting.name) ~= "string" then
        return
    end
    local entry = into[id]
    if not entry then
        entry = { name = sighting.name, level = sighting.level, elite = sighting.elite and true or false,
            count = 0, last = 0, places = {}, own = false }
        into[id] = entry
    end
    if own then
        -- The player's own words on name and level are the freshest.
        entry.name, entry.level, entry.own = sighting.name, sighting.level, true
        entry.elite = sighting.elite and true or false
    end
    entry.count = entry.count + (tonumber(sighting.count) or 1)
    entry.last = math.max(entry.last, tonumber(sighting.last) or 0)
    for _, place in ipairs(type(sighting.places) == "table" and sighting.places or {}) do
        if type(place) == "table" and type(place.map) == "number" and type(place.x) == "number"
            and type(place.y) == "number" then
            table.insert(entry.places, place)
        end
    end
end

--- Every sighting by rare id, merged across recorders: counts summed, the
-- newest time, every place, and whether the player saw it themselves.
function Rares.Sightings()
    if merged then
        return merged
    end
    merged = {}
    local db = ns.db
    for id, sighting in pairs(db and db.sightings or {}) do
        add(merged, id, sighting, true)
    end
    local mine = db and db.recorder
    for recorder, sightings in pairs(ns.baked) do
        if recorder ~= mine then
            for id, sighting in pairs(sightings) do
                add(merged, id, sighting, false)
            end
        end
    end
    return merged
end

--- What is known of rare `id`: { id, name, minLevel, maxLevel, elite, seen,
-- own, last, inDatabase }. Nil for an id neither source knows.
function Rares.Info(id)
    local rare = ns.rares[id]
    local sighting = Rares.Sightings()[id]
    if not rare and not sighting then
        return nil
    end
    return {
        id = id,
        name = rare and rare.name or sighting.name,
        minLevel = rare and rare.minLevel or sighting.level,
        maxLevel = rare and rare.maxLevel or sighting.level,
        elite = (rare and rare.elite) or (not rare and sighting.elite) or false,
        seen = sighting ~= nil,
        own = sighting ~= nil and sighting.own,
        last = sighting and sighting.last > 0 and sighting.last or nil,
        inDatabase = rare ~= nil,
    }
end

--- Whether the settings let rare `info` show.
function Rares.Shown(info)
    return info ~= nil and (info.seen or ns.settings.showUnseen)
end

--- "26", "40-42", or "??" for a level the client would not give.
function Rares.LevelText(info)
    local low, high = tonumber(info.minLevel) or 0, tonumber(info.maxLevel) or 0
    if low <= 0 then
        return "??"
    end
    if high > low then
        return string.format("%d-%d", low, high)
    end
    return tostring(low)
end

local function plural(count, word)
    return string.format("%d %s%s ago", count, word, count == 1 and "" or "s")
end

--- How long ago `seconds` was, in words.
function Rares.Ago(seconds)
    seconds = math.max(0, seconds or 0)
    if seconds < 60 then
        return "just now"
    elseif seconds < 3600 then
        return plural(math.floor(seconds / 60), "minute")
    elseif seconds < 86400 then
        return plural(math.floor(seconds / 3600), "hour")
    end
    return plural(math.floor(seconds / 86400), "day")
end

local function near(list, id, x, y, yards)
    local limit = yards * yards
    for _, place in ipairs(list) do
        if place.id == id and (place.x - x) ^ 2 + (place.y - y) ^ 2 <= limit then
            return true
        end
    end
    return false
end

--- Every pin place on `continent`, in world yards: { id, x, y, sighting }.
-- The database's spawns, then each sighting's spot where the database has no
-- spawn of that rare near it.
function Rares.Places(continent)
    local cached = placesCache[continent]
    if cached and cached.version == Rares.version then
        return cached.places
    end

    local places = {}
    for _, spawn in ipairs(ns.spawns[continent] or {}) do
        places[#places + 1] = { id = spawn.id, x = spawn.x, y = spawn.y, sighting = false }
    end
    local spawned = #places

    local ids = {}
    for id in pairs(Rares.Sightings()) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        for _, place in ipairs(Rares.Sightings()[id].places) do
            local rect = ns.Geometry.MapRect(place.map)
            if rect and rect.continent == continent then
                local x, y = ns.Geometry.ToWorld(rect, place.x, place.y)
                local beside = false
                for index = 1, spawned do
                    local spawn = places[index]
                    if spawn.id == id and (spawn.x - x) ^ 2 + (spawn.y - y) ^ 2 <= Rares.NEAR_SPAWN ^ 2 then
                        beside = true
                        break
                    end
                end
                if not beside and not near(places, id, x, y, Rares.SAME_SPOT) then
                    places[#places + 1] = { id = id, x = x, y = y, sighting = true }
                end
            end
        end
    end

    placesCache[continent] = { version = Rares.version, places = places }
    return places
end

--- The rares of zone `uiMapID` the settings show, spawned or seen in it:
-- their infos, by level, then name.
function Rares.InZone(uiMapID)
    local rect = ns.Geometry.MapRect(uiMapID)
    if not rect then
        return {}
    end
    local ids = {}
    for _, place in ipairs(Rares.Places(rect.continent)) do
        local x, y = ns.Geometry.ToMap(rect, place.x, place.y)
        if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            ids[place.id] = true
        end
    end
    for id, sighting in pairs(Rares.Sightings()) do
        for _, place in ipairs(sighting.places) do
            if place.map == uiMapID then
                ids[id] = true
            end
        end
    end

    local infos = {}
    for id in pairs(ids) do
        local info = Rares.Info(id)
        if Rares.Shown(info) then
            infos[#infos + 1] = info
        end
    end
    table.sort(infos, function(a, b)
        local la, lb = tonumber(a.minLevel) or 0, tonumber(b.minLevel) or 0
        if la ~= lb then
            return la < lb
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.id < b.id
    end)
    return infos
end
