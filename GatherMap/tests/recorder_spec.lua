local helpers = require("helpers")

local A = "0:1731:-10603.8:1154.0"
local E = "0:180582:-10620.0:1170.0"

local function guid(entry)
    return string.format("GameObject-0-6782-0-79720-%d-00003A1A8E", entry)
end

local function loot(env, entry)
    env.__lootSource = guid(entry)
    helpers.fire(env, "LOOT_OPENED")
end

describe("reading a loot window's source", function()
    it("takes the object's entry from its GUID", function()
        local ns = helpers.loggedIn()
        assertEqual(1731, ns.Recorder.EntryFromGUID("GameObject-0-6782-0-79720-1731-00003A1A8E"))
        assertNil(ns.Recorder.EntryFromGUID("Creature-0-6782-0-79720-1731-00003A1A8E"))
        assertNil(ns.Recorder.EntryFromGUID(nil))
    end)
end)

describe("a gather", function()
    it("counts the spawn it was taken from", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        local point = ns.db.gathered[A]
        assertEqual(1, point.count)
        assertEqual(env.__time, point.last)
        assertFalse(point.new)
        assertEqual(1731, point.entry)
    end)

    it("counts again next time, but not twice for one window", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        env.__now = env.__now + 2
        loot(env, 1731)
        assertEqual(1, ns.db.gathered[A].count, "reopened within 5 seconds")
        env.__now = env.__now + 6
        loot(env, 1731)
        assertEqual(2, ns.db.gathered[A].count)
    end)

    it("makes a new point where the data has no spawn", function()
        local ns, env = helpers.loggedIn(function(env) env.__position = { -10300.04, 900.06, 0, 0 } end)
        loot(env, 1731)
        local key = "0:1731:-10300.0:900.1"
        assertEqual(1, ns.db.gathered[key].count)
        assertTrue(ns.db.gathered[key].new)
        assertEqual(key, ns.Spawns.ByKey(key).key, "and the maps can draw it")
    end)

    it("counts a pool from the shore, up to 30 yards off", function()
        local ns, env = helpers.loggedIn()
        loot(env, 180582)
        assertEqual(1, ns.db.gathered[E].count)
    end)

    it("never makes a new point for a pool", function()
        local ns, env = helpers.loggedIn(function(env) env.__position = { -10300, 900, 0, 0 } end)
        loot(env, 180582)
        assertNil(next(ns.db.gathered))
    end)

    it("works on Kalimdor too", function()
        local ns, env = helpers.loggedIn(function(env) env.__position = { 100.0, 200.0, 0, 1 } end)
        loot(env, 1618)
        assertEqual(1, ns.db.gathered["1:1618:100.0:200.0"].count)
    end)

    it("ignores corpses, unknown objects, instances and a hidden position", function()
        local ns, env = helpers.loggedIn()
        env.__lootSource = "Creature-0-6782-0-79720-1731-00003A1A8E"
        helpers.fire(env, "LOOT_OPENED")
        loot(env, 424242)
        env.__position = { -10603.8, 1154.0, 0, 36 }
        loot(env, 1731)
        env.__position = nil
        loot(env, 1731)
        env.GetLootSourceInfo = function() error("secret") end
        helpers.fire(env, "LOOT_OPENED")
        assertNil(next(ns.db.gathered))
    end)

    it("repairs a saved point with no count", function()
        local ns, env = helpers.loggedIn(function(env)
            env.GatherMapDB = { gathered = { [A] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0 } } }
        end)
        loot(env, 1731)
        assertEqual(1, ns.db.gathered[A].count)
    end)

    it("redraws the pins", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        loot(env, 1731)
        assertEqual(1, count)
    end)

    it("clears a not-here mark on the spawn it was taken from", function()
        local ns, env = helpers.loggedIn()
        ns.db.missing[A] = 1
        loot(env, 1731)
        assertNil(ns.db.missing[A])
    end)
end)

describe("marking a spawn not here", function()
    it("toggles, stamped with the time, and redraws", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        local spawn = ns.Spawns.ByKey(A)
        assertTrue(ns.Recorder.ToggleMissing(spawn))
        assertEqual(env.__time, ns.db.missing[A])
        assertFalse(ns.Recorder.ToggleMissing(spawn))
        assertNil(ns.db.missing[A])
        assertEqual(2, count)
    end)

    it("marks a whole spot if any of it is unmarked, else clears it, with one redraw each", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        local C, C2 = "0:3764:-10610.0:1160.0", "0:1733:-10610.0:1160.0"
        local members = ns.Spawns.ByKey(C).stack
        ns.db.missing[C] = 5
        assertTrue(ns.Recorder.ToggleMissingAll(members))
        assertEqual(env.__time, ns.db.missing[C])
        assertEqual(env.__time, ns.db.missing[C2])
        assertEqual(1, count)
        assertFalse(ns.Recorder.ToggleMissingAll(members))
        assertNil(ns.db.missing[C])
        assertNil(ns.db.missing[C2])
        assertEqual(2, count)
    end)

    it("matches a gather to its own entry at a shared spot", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1733)
        assertEqual(1, ns.db.gathered["0:1733:-10610.0:1160.0"].count)
        assertNil(ns.db.gathered["0:3764:-10610.0:1160.0"])
    end)
end)

describe("/gmap reset gathered", function()
    it("asks first, then forgets on a second go within 10 seconds", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        helpers.command(env, "reset gathered")
        assertEqual(1, ns.db.gathered[A].count, "not yet")
        assertMatch("again within 10 seconds", helpers.printed(env))
        env.__now = env.__now + 3
        ns.db.missing["0:2843:-10700.0:1300.0"] = 1
        helpers.command(env, "reset gathered")
        assertNil(next(ns.db.gathered))
        assertNil(next(ns.db.missing), "the not-here marks go too")
        assertMatch("Forgot every place", helpers.printed(env))
    end)

    it("asks again when the second go comes too late", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        helpers.command(env, "reset gathered")
        env.__now = env.__now + 11
        helpers.command(env, "reset gathered")
        assertEqual(1, ns.db.gathered[A].count)
    end)

    it("says how to use it without 'gathered'", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "reset")
        assertMatch("/gmap reset gathered", helpers.printed(env))
    end)
end)
