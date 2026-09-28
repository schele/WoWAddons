local helpers = require("helpers")

describe("the index of gathered places", function()
    it("holds every saved gather, per continent, and nothing else", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        assertEqual(6, #ns.Spawns.All(0))
        assertEqual(1, #ns.Spawns.All(1))
    end)

    it("starts empty without saved gathers", function()
        local ns = helpers.loggedIn()
        assertEqual(0, #ns.Spawns.All(0))
    end)

    it("keeps the saved point on its spawn", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local spawn = ns.Spawns.ByKey(helpers.A)
        assertTrue(spawn.point == ns.db.gathered[helpers.A])
    end)

    it("puts places at one spot in one stack", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local tin = ns.Spawns.ByKey(helpers.C)
        assertEqual(2, #tin.stack)
        assertTrue(tin.stack == ns.Spawns.ByKey(helpers.S).stack)
    end)

    it("finds what is within reach, and the nearest of one entry", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local found = 0
        ns.Spawns.Near(0, -10603.8, 1154.0, 15, function() found = found + 1 end)
        assertEqual(3, found, "the copper under the player, and the tin and silver 8.6 yards off")
        assertEqual(helpers.A, ns.Spawns.Nearest(0, 1731, -10600, 1150, 15).key)
    end)

    it("adds a new place, rounded, for a saved point", function()
        local ns = helpers.loggedIn()
        local version = ns.Spawns.version
        local point = { continent = 0, entry = 1731, kind = "ore", count = 0 }
        local spawn = ns.Spawns.AddPoint(0, 1731, -10555.04, 1111.06, point)
        assertEqual("0:1731:-10555.0:1111.1", spawn.key)
        assertTrue(spawn.point == point)
        assertEqual(version + 1, ns.Spawns.version)
    end)

    it("takes a place out, and its spot with it when it was the last", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local tin, silver = ns.Spawns.ByKey(helpers.C), ns.Spawns.ByKey(helpers.S)
        ns.Spawns.Remove(tin)
        assertNil(ns.Spawns.ByKey(helpers.C))
        assertEqual(1, #silver.stack)
        assertEqual(5, #ns.Spawns.All(0))
        ns.Spawns.Remove(silver)
        local found = 0
        ns.Spawns.Near(0, -10610, 1160, 1, function() found = found + 1 end)
        assertEqual(0, found)
    end)

    it("clears everything", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        ns.Spawns.Clear()
        assertEqual(0, #ns.Spawns.All(0))
        assertNil(ns.Spawns.ByKey(helpers.A))
    end)
end)

describe("a saved point under a key its place does not give", function()
    local ODD = "0:1731:-10603.75:1154.0"

    it("moves to its place's key", function()
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = { [ODD] = helpers.point(helpers.A, { count = 2 }) } }
        end)
        assertNil(ns.db.gathered[ODD])
        assertEqual(2, ns.db.gathered[helpers.A].count)
        assertTrue(ns.Spawns.ByKey(helpers.A).point == ns.db.gathered[helpers.A])
    end)

    it("joins a point already at that key, adding its count", function()
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = {
                [ODD] = helpers.point(helpers.A, { count = 2 }),
                [helpers.A] = helpers.point(helpers.A, { count = 3 }),
            } }
        end)
        assertNil(ns.db.gathered[ODD])
        assertEqual(5, ns.db.gathered[helpers.A].count)
        assertTrue(ns.Spawns.ByKey(helpers.A).point == ns.db.gathered[helpers.A])
        assertEqual(1, #ns.Spawns.All(0))
    end)
end)

describe("what a place is", function()
    it("comes from the node list when the entry is listed", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local node = ns.Spawns.Node(ns.Spawns.ByKey(helpers.A))
        assertEqual("Copper Vein", node.name)
        assertEqual("ore", node.kind)
        assertEqual(1, node.skill)
        assertEqual(2770, node.item)
    end)

    it("comes from its loot when the entry is not listed, with no skill", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local node = ns.Spawns.Node(ns.Spawns.ByKey(helpers.E))
        assertEqual("Strange Ore", node.name)
        assertEqual("ore", node.kind)
        assertNil(node.skill)
        assertEqual(9999, node.item)
    end)

    it("is named after its kind when even the loot was not known", function()
        local key = "0:555:1.0:2.0"
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = { [key] = helpers.point(key, { kind = "herb" }) } }
        end)
        assertEqual("Herb", ns.Spawns.Node(ns.Spawns.ByKey(key)).name)
    end)
end)

describe("gathers saved by the first GatherMap", function()
    it("keep herbs and ore, drop pools, chests and the unplaceable, and lose the not-here marks", function()
        local keep = "0:1731:-10500.0:1100.0"
        local pool = "0:180582:-10620.0:1170.0"
        local chest = "0:2843:-10700.0:1300.0"
        local ns = helpers.loggedIn(function(env)
            env.GatherMapDB = {
                gathered = {
                    [keep] = helpers.point(keep, { new = true }),
                    [pool] = helpers.point(pool),
                    [chest] = helpers.point(chest),
                    broken = { continent = 0, entry = 1731 },
                },
                missing = { [keep] = 1790000000 },
            }
        end)
        assertEqual(1, #ns.Spawns.All(0))
        assertEqual("ore", ns.db.gathered[keep].kind, "the kind comes from the list")
        assertNil(ns.db.gathered[keep].new)
        assertNil(ns.db.gathered[pool])
        assertNil(ns.db.gathered[chest])
        assertNil(ns.db.gathered.broken)
        assertNil(ns.db.missing)
    end)
end)
