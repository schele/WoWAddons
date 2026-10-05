local addonName, ns = ...

-- Noticing rares. Every unit the player could be looking at -- each
-- nameplate as it appears, the target, the mouseover -- is asked whether it
-- is a living rare. One newly near is a sighting: saved with where the
-- player stands (within nameplate range of it) and told to the alert and the
-- pins. It stays near until it dies or nothing has shown it for 30 seconds.

local Spotter = {}
ns.Spotter = Spotter

Spotter.GONE_AFTER = 30 -- seconds with no nameplate, target or mouseover
Spotter.INTERVAL = 1    -- seconds between looks at who is still near
Spotter.PLACES = 20     -- places kept per rare, the newest

local RARE = { rare = true, rareelite = true }

local spotted = {} -- id -> { seenAt }: the rares near now
local plates = {}  -- nameplate unit tokens showing now
local spottedListeners, goneListeners = {}, {}

--- Call fn(id, info) when a living rare comes near; info is { id, name,
-- level, elite }.
function ns.OnSpotted(fn)
    table.insert(spottedListeners, fn)
end

--- Call fn(id) when a rare near is gone or dead.
function ns.OnGone(fn)
    table.insert(goneListeners, fn)
end

-- Lua 5.1 has unpack; later versions keep it in table.
local unpackArgs = unpack or table.unpack

local function tell(listeners, ...)
    local args = { ... }
    for _, fn in ipairs(listeners) do
        ns.Guarded(function() fn(unpackArgs(args)) end)
    end
end

--- A GUID's creature id, or nil for anything not a creature.
function Spotter.ParseGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local id = guid:match("^Creature%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-")
    return tonumber(id)
end

--- What `unit` is, if it is a rare: { id, name, level, elite, dead }. Nil
-- for anything else, or a unit the client will not describe. The tests on
-- the client's answers happen in here: they may be secrets outside.
local function read(unit)
    return ns.Guarded(function()
        local classification = UnitClassification(unit)
        if not RARE[classification] then
            return nil
        end
        local id = Spotter.ParseGUID(UnitGUID(unit))
        if not id then
            return nil
        end
        return {
            id = id,
            name = UnitName(unit),
            level = tonumber(UnitLevel(unit)) or 0,
            elite = classification == "rareelite",
            dead = UnitIsDead(unit) and true or false,
        }
    end)
end

--- Where the player stands, as a map and a position on it; nil when the
-- client will not say.
local function playerPlace()
    return ns.Guarded(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local at = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not at or type(at.x) ~= "number" or type(at.y) ~= "number" then
            return nil
        end
        return { map = mapID, x = math.floor(at.x * 10000 + 0.5) / 10000, y = math.floor(at.y * 10000 + 0.5) / 10000 }
    end)
end

local function record(rare, place)
    local sightings = ns.db.sightings
    local sighting = sightings[rare.id]
    if type(sighting) ~= "table" then
        sighting = { count = 0, places = {} }
        sightings[rare.id] = sighting
    end
    if type(sighting.places) ~= "table" then
        sighting.places = {}
    end
    local now = time()
    sighting.name = type(rare.name) == "string" and rare.name or sighting.name or "?"
    sighting.level = rare.level
    sighting.elite = rare.elite
    sighting.count = (tonumber(sighting.count) or 0) + 1
    sighting.last = now
    place.time = now
    table.insert(sighting.places, place)
    while #sighting.places > Spotter.PLACES do
        table.remove(sighting.places, 1)
    end
    ns.Rares.Changed()
end

local function gone(id)
    if not spotted[id] then
        return
    end
    spotted[id] = nil
    tell(goneListeners, id)
    ns.Refresh()
end

--- Look at `unit`: a living rare not near already is a sighting.
function Spotter.Look(unit)
    local rare = read(unit)
    if not rare then
        return
    end
    if rare.dead then
        gone(rare.id)
        return
    end
    if spotted[rare.id] then
        spotted[rare.id].seenAt = GetTime()
        return
    end
    local place = playerPlace()
    if not place then
        return
    end
    record(rare, place)
    spotted[rare.id] = { seenAt = GetTime() }
    tell(spottedListeners, rare.id, { id = rare.id, name = rare.name, level = rare.level, elite = rare.elite })
    ns.Refresh()
end

local function hasPlate(unit)
    return ns.Guarded(function()
        if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
            return true -- no way to ask: the plate's removal event still says
        end
        return C_NamePlate.GetNamePlateForUnit(unit) ~= nil
    end, false)
end

--- Who is still near: every unit shown now refreshes its rare; a dead one
-- is gone at once; one nothing has shown for GONE_AFTER seconds is gone.
function Spotter.Tick()
    if not next(spotted) then
        return
    end
    local now = GetTime()
    local units = { "target", "mouseover" }
    for unit in pairs(plates) do
        if hasPlate(unit) then
            units[#units + 1] = unit
        else
            plates[unit] = nil
        end
    end
    for _, unit in ipairs(units) do
        local rare = read(unit)
        if rare and spotted[rare.id] then
            if rare.dead then
                gone(rare.id)
            else
                spotted[rare.id].seenAt = now
            end
        end
    end
    for id, state in pairs(spotted) do
        if now - state.seenAt >= Spotter.GONE_AFTER then
            gone(id)
        end
    end
end

function Spotter.IsSpotted(id)
    return spotted[id] ~= nil
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit)
    if not ns.db then
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        plates[unit] = true
        Spotter.Look(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plates[unit] = nil
    elseif event == "PLAYER_TARGET_CHANGED" then
        Spotter.Look("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Spotter.Look("mouseover")
    end
end)

ns.OnLogin(function()
    for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
        ns.Guarded(function() frame:RegisterEvent(event) end)
    end

    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= Spotter.INTERVAL - 1e-9 then
            elapsed = 0
            ns.Guarded(Spotter.Tick)
        end
    end)
    Spotter.ticker = ticker
end)
