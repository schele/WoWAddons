local helpers = require("helpers")

local A = "0:1731:-10603.8:1154.0"

describe("the spawn index", function()
    it("takes every data spawn the catalog knows, per continent", function()
        local ns = helpers.loggedIn()
        assertEqual(7, #ns.Spawns.All(0), "the unknown object is left out")
        assertEqual(1, #ns.Spawns.All(1))
        assertEqual(0, #ns.Spawns.All(36))
    end)

    it("keys a spawn by continent, entry and position to a tenth of a yard", function()
        local ns = helpers.loggedIn()
        assertEqual(A, ns.Spawns.Key(0, 1731, -10603.8, 1154))
        local spawn = ns.Spawns.ByKey(A)
        assertEqual(1731, spawn.entry)
        assertEqual(0, spawn.continent)
    end)

    it("finds what is within reach, and nothing further", function()
        local ns = helpers.loggedIn()
        local found = {}
        ns.Spawns.Near(0, -10603.8, 1154.0, 15, function(spawn) found[#found + 1] = spawn.entry end)
        table.sort(found)
        assertEqual(3, #found)
        assertEqual(1731, found[1])
        assertEqual(1733, found[2])
        assertEqual(3764, found[3])
    end)

    it("looks across a cell border", function()
        local ns = helpers.loggedIn()
        local found = 0
        ns.Spawns.Near(0, -10001, 999, 5, function() found = found + 1 end)
        assertEqual(1, found, "B sits on the corner of four cells")
    end)

    it("finds the nearest spawn of one entry", function()
        local ns = helpers.loggedIn()
        assertEqual(A, ns.Spawns.Nearest(0, 1731, -10600, 1150, 15).key)
        assertEqual(3764, ns.Spawns.Nearest(0, 3764, -10603.8, 1154.0, 15).entry)
        assertNil(ns.Spawns.Nearest(0, 180582, -10603.8, 1154.0, 15), "the pool is 22.8 yards off")
        assertEqual(180582, ns.Spawns.Nearest(0, 180582, -10603.8, 1154.0, 30).entry)
        assertNil(ns.Spawns.Nearest(1, 1731, -10603.8, 1154.0, 30), "another continent")
    end)

    it("adds a new point, rounded, and counts the change", function()
        local ns = helpers.loggedIn()
        local version = ns.Spawns.version
        local spawn = ns.Spawns.AddPoint(0, 1731, -10555.04, 1111.06)
        assertEqual("0:1731:-10555.0:1111.1", spawn.key)
        assertTrue(ns.Spawns.ByKey(spawn.key) == spawn)
        assertEqual(version + 1, ns.Spawns.version)
        assertTrue(ns.Spawns.AddPoint(0, 1731, -10555.04, 1111.06) == spawn, "the same place twice is one point")
    end)

    it("loads the new points the player found before", function()
        local key = "0:1731:-10500.0:1100.0"
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = {
                [key] = { continent = 0, entry = 1731, x = -10500.0, y = 1100.0, count = 1, new = true },
                ["0:1731:-10603.8:1154.0"] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0, count = 4 },
            } }
        end)
        assertEqual(key, ns.Spawns.ByKey(key).key)
        assertEqual(8, #ns.Spawns.All(0), "a gathered data spawn is not added twice")
    end)

    it("skips a saved point it cannot place", function()
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = {
                bad1 = { continent = 0, entry = 1731, new = true },
                bad2 = { continent = 0, x = 1, y = 2, new = true },
                bad3 = { continent = 0, entry = 424242, x = 1, y = 2, new = true },
            } }
        end)
        assertEqual(7, #ns.Spawns.All(0))
    end)
end)

describe("a spot", function()
    local C = "0:3764:-10610.0:1160.0"
    local C2 = "0:1733:-10610.0:1160.0"

    it("stacks the spawns at one place, in the order they came", function()
        local ns = helpers.loggedIn()
        local tin, silver = ns.Spawns.ByKey(C), ns.Spawns.ByKey(C2)
        assertTrue(tin.stack == silver.stack, "one table for both")
        assertEqual(2, #tin.stack)
        assertTrue(tin.stack[1] == tin)
        assertTrue(tin.stack[2] == silver)
    end)

    it("holds just the spawn where it is alone", function()
        local ns = helpers.loggedIn()
        local spawn = ns.Spawns.ByKey(A)
        assertEqual(1, #spawn.stack)
        assertTrue(spawn.stack[1] == spawn)
    end)

    it("takes a new point at a place that has spawns, or starts one", function()
        local ns = helpers.loggedIn()
        local copper = ns.Spawns.AddPoint(0, 1731, -10610.02, 1159.98)
        local tin = ns.Spawns.ByKey(C)
        assertTrue(copper.stack == tin.stack)
        assertEqual(3, #tin.stack)
        assertTrue(tin.stack[3] == copper)
        ns.Spawns.AddPoint(0, 1731, -10610.0, 1160.0)
        assertEqual(3, #tin.stack, "the same point again is not stacked twice")
        local alone = ns.Spawns.AddPoint(0, 1731, -10555.0, 1111.0)
        assertEqual(1, #alone.stack)
        assertTrue(alone.stack[1] == alone)
    end)

    it("is per continent", function()
        local ns = helpers.loggedIn()
        local other = ns.Spawns.AddPoint(1, 3764, -10610.0, 1160.0)
        assertEqual(1, #other.stack)
        assertEqual(2, #ns.Spawns.ByKey(C).stack)
    end)
end)
