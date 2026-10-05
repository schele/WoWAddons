local helpers = require("helpers")

local NOW = 1790000000

--- Logged in, with a listener counting what was spotted and what is gone.
local function watching(setup)
    local ns, env = helpers.loggedIn(setup)
    local log = { spotted = {}, gone = {} }
    ns.OnSpotted(function(id, info) table.insert(log.spotted, { id = id, info = info }) end)
    ns.OnGone(function(id) table.insert(log.gone, id) end)
    return ns, env, log
end

local function target(env, unit)
    env.__units.target = unit
    helpers.fire(env, "PLAYER_TARGET_CHANGED")
end

describe("reading a GUID", function()
    it("gives a creature's id, and nothing for anything else", function()
        local ns = helpers.loggedIn()
        assertEqual(462, ns.Spotter.ParseGUID("Creature-0-5250-0-1436-462-00001A2B3C"))
        assertNil(ns.Spotter.ParseGUID("Player-5250-0A1B2C3D"))
        assertNil(ns.Spotter.ParseGUID("Pet-0-5250-0-1436-462-00001A2B3C"))
        assertNil(ns.Spotter.ParseGUID(nil))
    end)
end)

describe("spotting a rare", function()
    it("records a living rare targeted: name, level, where and when", function()
        local ns, env, log = watching()
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        local sighting = ns.db.sightings[462]
        assertEqual("Vultros", sighting.name)
        assertEqual(26, sighting.level)
        assertFalse(sighting.elite)
        assertEqual(1, sighting.count)
        assertEqual(NOW, sighting.last)
        assertEqual(1, #sighting.places)
        local place = sighting.places[1]
        assertEqual(1436, place.map)
        assertNear(0.846, place.x)
        assertNear(0.6038, place.y)
        assertEqual(NOW, place.time)
        assertEqual(1, #log.spotted)
        assertEqual(462, log.spotted[1].id)
        assertTrue(ns.Spotter.IsSpotted(462))
    end)

    it("records a rare elite, from a nameplate", function()
        local ns, env, log = watching()
        env.__units.nameplate3 = env.__creature(1, "Elite Rare", 41, "rareelite")
        helpers.fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate3")
        assertTrue(ns.db.sightings[1].elite)
        assertEqual(1, #log.spotted)
    end)

    it("records one under the mouse", function()
        local ns, env = watching()
        env.__units.mouseover = env.__creature(520, "Brack", 19, "rare")
        helpers.fire(env, "UPDATE_MOUSEOVER_UNIT")
        assertEqual("Brack", ns.db.sightings[520].name)
    end)

    it("ignores a dead rare", function()
        local ns, env, log = watching()
        target(env, env.__creature(462, "Vultros", 26, "rare", true))
        assertNil(ns.db.sightings[462])
        assertEqual(0, #log.spotted)
    end)

    it("ignores a mob that is not rare", function()
        local ns, env, log = watching()
        target(env, env.__creature(500, "Defias Bandit", 15, "normal"))
        target(env, env.__creature(501, "Elite", 15, "elite"))
        assertNil(next(ns.db.sightings))
        assertEqual(0, #log.spotted)
    end)

    it("skips a unit whose classification or GUID cannot be read", function()
        local ns, env, log = watching()
        local unit = env.__creature(462, "Vultros", 26, "rare")
        unit.classificationError = true
        target(env, unit)
        unit = env.__creature(462, "Vultros", 26, "rare")
        unit.guidError = true
        target(env, unit)
        unit = env.__creature(462, "Vultros", 26, "rare")
        unit.guid = "garbage"
        target(env, unit)
        assertNil(ns.db.sightings[462])
        assertEqual(0, #log.spotted)
    end)

    it("skips a rare while the client gives no map position", function()
        local ns, env, log = watching()
        env.__playerMap = nil
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        assertNil(ns.db.sightings[462])
        assertEqual(0, #log.spotted)
    end)

    it("counts a rare once while it stays near", function()
        local ns, env, log = watching()
        local vultros = env.__creature(462, "Vultros", 26, "rare")
        env.__units.nameplate1 = vultros
        helpers.fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate1")
        target(env, vultros)
        env.__units.mouseover = vultros
        helpers.fire(env, "UPDATE_MOUSEOVER_UNIT")
        assertEqual(1, ns.db.sightings[462].count)
        assertEqual(1, #ns.db.sightings[462].places)
        assertEqual(1, #log.spotted)
    end)

    it("counts it again once it has been gone", function()
        local ns, env, log = watching()
        local vultros = env.__creature(462, "Vultros", 26, "rare")
        target(env, vultros)
        target(env, nil)
        env.__now = env.__now + 31
        env.__time = env.__time + 31
        ns.Spotter.Tick()
        target(env, vultros)
        assertEqual(2, ns.db.sightings[462].count)
        assertEqual(2, #ns.db.sightings[462].places)
        assertEqual(NOW + 31, ns.db.sightings[462].last)
        assertEqual(2, #log.spotted)
    end)

    it("keeps the newest 20 places", function()
        local ns, env = watching(helpers.withSightings({}))
        local places = {}
        for index = 1, 20 do places[index] = helpers.place(0.1, 0.1, index) end
        ns.db.sightings[462] = helpers.sighting("Vultros", 26, 20, places, { count = 20 })
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        local kept = ns.db.sightings[462].places
        assertEqual(20, #kept)
        assertEqual(2, kept[1].time, "the oldest went")
        assertEqual(NOW, kept[20].time)
        assertEqual(21, ns.db.sightings[462].count)
    end)

    it("tells the merged view", function()
        local ns, env = watching()
        assertFalse(ns.Rares.Info(462).seen)
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        assertTrue(ns.Rares.Info(462).seen)
        assertTrue(ns.Rares.Info(462).own)
    end)
end)

describe("a rare going", function()
    it("is gone 30 seconds after the last look at it", function()
        local ns, env, log = watching()
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        target(env, nil)
        env.__now = env.__now + 29
        ns.Spotter.Tick()
        assertTrue(ns.Spotter.IsSpotted(462))
        env.__now = env.__now + 2
        ns.Spotter.Tick()
        assertFalse(ns.Spotter.IsSpotted(462))
        assertEqual(462, log.gone[1])
    end)

    it("stays while its nameplate shows, its target or under the mouse", function()
        local ns, env, log = watching()
        local vultros = env.__creature(462, "Vultros", 26, "rare")
        env.__units.nameplate2 = vultros
        helpers.fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate2")
        for _ = 1, 5 do
            env.__now = env.__now + 20
            ns.Spotter.Tick()
        end
        assertTrue(ns.Spotter.IsSpotted(462))
        env.__units.nameplate2 = nil
        helpers.fire(env, "NAME_PLATE_UNIT_REMOVED", "nameplate2")
        env.__units.target = vultros
        env.__now = env.__now + 20
        ns.Spotter.Tick()
        assertTrue(ns.Spotter.IsSpotted(462), "still the target")
        env.__units.target = nil
        env.__now = env.__now + 31
        ns.Spotter.Tick()
        assertFalse(ns.Spotter.IsSpotted(462))
    end)

    it("is gone at once when it dies", function()
        local ns, env, log = watching()
        local vultros = env.__creature(462, "Vultros", 26, "rare")
        target(env, vultros)
        vultros.dead = true
        ns.Spotter.Tick()
        assertFalse(ns.Spotter.IsSpotted(462))
        assertEqual(1, #log.gone)
    end)

    it("is gone at once when a dead one is targeted", function()
        local ns, env, log = watching()
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        target(env, env.__creature(462, "Vultros", 26, "rare", true))
        assertFalse(ns.Spotter.IsSpotted(462))
    end)

    it("ticks once a second from its own frame", function()
        local ns, env = watching()
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        target(env, nil)
        env.__now = env.__now + 31
        ns.Spotter.ticker.scripts.OnUpdate(ns.Spotter.ticker, 0.5)
        assertTrue(ns.Spotter.IsSpotted(462))
        ns.Spotter.ticker.scripts.OnUpdate(ns.Spotter.ticker, 0.5)
        assertFalse(ns.Spotter.IsSpotted(462))
    end)
end)
