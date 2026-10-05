local helpers = require("helpers")

local NOW = 1790000000
local DAY = 86400

local function ids(infos)
    local list = {}
    for _, info in ipairs(infos) do list[#list + 1] = info.id end
    return table.concat(list, ",")
end

describe("a rare, merged", function()
    it("from the database only: not seen", function()
        local ns = helpers.loggedIn()
        local info = ns.Rares.Info(1)
        assertEqual("Elite Rare", info.name)
        assertEqual(40, info.minLevel)
        assertEqual(42, info.maxLevel)
        assertTrue(info.elite)
        assertTrue(info.inDatabase)
        assertFalse(info.seen)
        assertFalse(info.own)
        assertNil(info.last)
    end)

    it("from a sighting only: seen, described by the sighting", function()
        local ns = helpers.loggedIn(helpers.withSightings({
            [777] = helpers.sighting("New Rare", 33, NOW, { helpers.place(0.2, 0.3) }, { elite = true }),
        }))
        local info = ns.Rares.Info(777)
        assertEqual("New Rare", info.name)
        assertEqual(33, info.minLevel)
        assertEqual(33, info.maxLevel)
        assertTrue(info.elite)
        assertFalse(info.inDatabase)
        assertTrue(info.seen)
        assertTrue(info.own)
        assertEqual(NOW, info.last)
    end)

    it("from both: the database's levels, seen by the player", function()
        local ns = helpers.loggedIn(helpers.withSightings({ [462] = helpers.sighting("Vultros", 26, NOW - DAY) }))
        local info = ns.Rares.Info(462)
        assertTrue(info.inDatabase)
        assertTrue(info.seen)
        assertTrue(info.own)
        assertEqual(NOW - DAY, info.last)
    end)

    it("baked: seen on WoW Forever, but not by this player", function()
        local ns = helpers.loggedIn(function(env, ns)
            ns.AddRecordings("other", { [1] = helpers.sighting("Elite Rare", 41, NOW - 2 * DAY) })
        end)
        local info = ns.Rares.Info(1)
        assertTrue(info.seen)
        assertFalse(info.own)
        assertEqual(NOW - 2 * DAY, info.last)
    end)

    it("leaves out the baked copy of the player's own recorder", function()
        local ns = helpers.loggedIn(function(env, ns)
            env.RareMobDB = { recorder = helpers.ME, sightings = { [462] = helpers.sighting("Vultros", 26, NOW, {}, { count = 1 }) } }
            ns.AddRecordings(helpers.ME, { [462] = helpers.sighting("Vultros", 26, NOW - DAY, {}, { count = 5 }) })
            ns.AddRecordings("other", { [462] = helpers.sighting("Vultros", 26, NOW - 3 * DAY, {}, { count = 2 }) })
        end)
        local merged = ns.Rares.Sightings()[462]
        assertEqual(3, merged.count, "the player's own, once, and the other recorder's")
        assertEqual(NOW, merged.last, "the newest")
        assertTrue(merged.own)
    end)

    it("is nil for an id neither the database nor a sighting knows", function()
        local ns = helpers.loggedIn()
        assertNil(ns.Rares.Info(424242))
    end)

    it("sees a new sighting once told", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Rares.Info(462).seen)
        ns.db.sightings[462] = helpers.sighting("Vultros", 26, NOW)
        ns.Rares.Changed()
        assertTrue(ns.Rares.Info(462).seen)
    end)
end)

describe("the words", function()
    it("say a level, or a range", function()
        local ns = helpers.loggedIn()
        assertEqual("26", ns.Rares.LevelText(ns.Rares.Info(462)))
        assertEqual("40-42", ns.Rares.LevelText(ns.Rares.Info(1)))
    end)

    it("say how long ago", function()
        local ns = helpers.loggedIn()
        assertEqual("just now", ns.Rares.Ago(30))
        assertEqual("1 minute ago", ns.Rares.Ago(60))
        assertEqual("5 minutes ago", ns.Rares.Ago(5 * 60 + 20))
        assertEqual("1 hour ago", ns.Rares.Ago(3600))
        assertEqual("3 hours ago", ns.Rares.Ago(3 * 3600 + 5))
        assertEqual("1 day ago", ns.Rares.Ago(DAY))
        assertEqual("3 days ago", ns.Rares.Ago(3 * DAY))
        assertEqual("just now", ns.Rares.Ago(-5), "a clock set back is not the future")
    end)
end)

describe("the pin places on a continent", function()
    local function places(ns, continent, id)
        local found = {}
        for _, place in ipairs(ns.Rares.Places(continent)) do
            if place.id == id then found[#found + 1] = place end
        end
        return found
    end

    it("are every database spawn, in world yards", function()
        local ns = helpers.loggedIn()
        local vultros = places(ns, 0, 462)
        assertEqual(1, #vultros)
        assertEqual(-10500, vultros[1].x)
        assertEqual(1500, vultros[1].y)
        assertFalse(vultros[1].sighting)
        assertEqual(1, #places(ns, 1, 5))
    end)

    it("add a sighting's spot where the database has no spawn of that rare", function()
        local ns = helpers.loggedIn(helpers.withSightings({
            [777] = helpers.sighting("New Rare", 33, NOW, { helpers.place(0.2, 0.3) }),
        }))
        local found = places(ns, 0, 777)
        assertEqual(1, #found)
        assertTrue(found[1].sighting)
        assertNear(-10300, found[1].x)
        assertNear(1800, found[1].y)
    end)

    it("add no spot for a sighting beside a database spawn, and one for a sighting far from it", function()
        local ns = helpers.loggedIn(helpers.withSightings({
            [462] = helpers.sighting("Vultros", 26, NOW, { helpers.place(0.5, 0.52), helpers.place(0.9, 0.9) }),
        }))
        local found = places(ns, 0, 462)
        assertEqual(2, #found, "the spawn, and the far sighting")
        assertTrue(found[2].sighting)
        assertNear(-10900, found[2].x)
    end)

    it("add one spot for several sightings at much the same place", function()
        local ns = helpers.loggedIn(helpers.withSightings({
            [777] = helpers.sighting("New Rare", 33, NOW, { helpers.place(0.2, 0.3), helpers.place(0.201, 0.301), helpers.place(0.7, 0.7) }),
        }))
        assertEqual(2, #places(ns, 0, 777))
    end)

    it("skip a sighting on a map the client cannot place", function()
        local ns = helpers.loggedIn(helpers.withSightings({
            [777] = helpers.sighting("New Rare", 33, NOW, { { map = 947, x = 0.5, y = 0.5, time = NOW } }),
        }))
        assertEqual(0, #places(ns, 0, 777))
    end)
end)

describe("a zone's rares", function()
    it("are those spawned or seen in it, by level", function()
        local ns = helpers.loggedIn(helpers.withSightings({
            [777] = helpers.sighting("New Rare", 33, NOW, { helpers.place(0.2, 0.3) }),
        }))
        assertEqual("520,462,777,1", ids(ns.Rares.InZone(1436)))
    end)

    it("are none on a map the client cannot place", function()
        local ns = helpers.loggedIn()
        assertEqual("", ids(ns.Rares.InZone(947)))
        assertEqual("", ids(ns.Rares.InZone(nil)))
    end)

    it("leave out the database-only ones when the setting says so", function()
        local ns = helpers.loggedIn(helpers.withSightings({ [462] = helpers.sighting("Vultros", 26, NOW) }))
        ns.settings.showUnseen = false
        assertEqual("462", ids(ns.Rares.InZone(1436)))
        assertTrue(ns.Rares.Shown(ns.Rares.Info(462)))
        assertFalse(ns.Rares.Shown(ns.Rares.Info(1)))
    end)
end)
