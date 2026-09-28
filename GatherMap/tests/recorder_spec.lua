local helpers = require("helpers")

local function guid(entry)
    return string.format("GameObject-0-6782-0-79720-%d-00003A1A8E", entry)
end

local function cast(env, spellID)
    helpers.fire(env, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", spellID)
end

local function loot(env, entry, link)
    env.__lootSource = guid(entry)
    env.__lootLink = link
    helpers.fire(env, "LOOT_OPENED")
end

local HERE = "0:1731:-10603.8:1154.0"

describe("reading a loot window's source", function()
    it("takes the object's entry from its GUID", function()
        local ns = helpers.loggedIn()
        assertEqual(1731, ns.Recorder.EntryFromGUID("GameObject-0-6782-0-79720-1731-00003A1A8E"))
        assertNil(ns.Recorder.EntryFromGUID("Creature-0-6782-0-79720-1731-00003A1A8E"))
        assertNil(ns.Recorder.EntryFromGUID(nil))
    end)
end)

describe("a gather", function()
    it("of a listed vein makes a new place where the player stands", function()
        local ns, env = helpers.loggedIn()
        cast(env, 2576)
        loot(env, 1731)
        local point = ns.db.gathered[HERE]
        assertEqual(1, point.count)
        assertEqual("ore", point.kind)
        assertEqual(env.__time, point.last)
        assertEqual(HERE, ns.Spawns.ByKey(HERE).key, "and the maps can draw it")
    end)

    it("of a listed herb counts with no Herbalism cast seen", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1617)
        assertEqual("herb", ns.db.gathered["0:1617:-10603.8:1154.0"].kind)
    end)

    it("of an unlisted object counts after Mining, named after its loot", function()
        local ns, env = helpers.loggedIn()
        cast(env, 2576)
        env.__now = env.__now + 2
        loot(env, 424242, "|cffffffff|Hitem:9999::::::::20:::::::|h[Strange Ore]|h|r")
        local point = ns.db.gathered["0:424242:-10603.8:1154.0"]
        assertEqual("ore", point.kind)
        assertEqual(9999, point.item)
        assertEqual("Strange Ore", point.itemName)
    end)

    it("of an unlisted object counts after Herbalism as a herb", function()
        local ns, env = helpers.loggedIn()
        cast(env, 2369)
        loot(env, 424243)
        assertEqual("herb", ns.db.gathered["0:424243:-10603.8:1154.0"].kind)
    end)

    it("of an unlisted object is recorded even when the client hides the loot link", function()
        local ns, env = helpers.loggedIn()
        env.GetLootSlotLink = function() error("secret") end
        cast(env, 2576)
        loot(env, 424242)
        local point = ns.db.gathered["0:424242:-10603.8:1154.0"]
        assertEqual("ore", point.kind)
        assertNil(point.itemName)
    end)

    it("is not an unlisted object with no gather cast, or one more than 3 seconds old", function()
        local ns, env = helpers.loggedIn()
        loot(env, 424242)
        cast(env, 133) -- Fireball
        loot(env, 424242)
        cast(env, 2576)
        env.__now = env.__now + 4
        loot(env, 424242)
        assertNil(next(ns.db.gathered))
    end)

    it("ignores another unit's cast", function()
        local ns, env = helpers.loggedIn()
        helpers.fire(env, "UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast", 2576)
        loot(env, 424242)
        assertNil(next(ns.db.gathered))
    end)

    it("counts one vein mined three times once", function()
        local ns, env = helpers.loggedIn()
        for _ = 1, 3 do
            cast(env, 2576)
            loot(env, 1731)
            env.__now = env.__now + 8
        end
        assertEqual(1, ns.db.gathered[HERE].count)
        env.__now = env.__now + 60
        cast(env, 2576)
        loot(env, 1731)
        assertEqual(2, ns.db.gathered[HERE].count, "the next visit counts")
    end)

    it("joins an earlier place of the same entry within 15 yards", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        env.__position = { -10610.0, 1150.0, 0, 0 }
        loot(env, 1731)
        assertEqual(2, ns.db.gathered[helpers.A].count)
        assertEqual(7, #ns.Spawns.All(0) + #ns.Spawns.All(1), "no new place")
    end)

    it("ignores corpses, instances and a hidden position", function()
        local ns, env = helpers.loggedIn()
        env.__lootSource = "Creature-0-6782-0-79720-1731-00003A1A8E"
        helpers.fire(env, "LOOT_OPENED")
        env.__position = { -10603.8, 1154.0, 0, 36 }
        loot(env, 1731)
        env.__position = nil
        loot(env, 1731)
        env.GetLootSourceInfo = function() error("secret") end
        helpers.fire(env, "LOOT_OPENED")
        assertNil(next(ns.db.gathered))
    end)

    it("redraws the pins", function()
        local ns, env = helpers.loggedIn()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        loot(env, 1731)
        assertEqual(1, count)
    end)
end)

describe("forgetting a spot", function()
    it("takes its places out of the saved gathers and the index, and redraws", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        local tin = ns.Spawns.ByKey(helpers.C)
        ns.Recorder.Forget({ tin, ns.Spawns.ByKey(helpers.S) })
        assertNil(ns.db.gathered[helpers.C])
        assertNil(ns.db.gathered[helpers.S])
        assertNil(ns.Spawns.ByKey(helpers.C))
        assertEqual(1, count)
    end)

    it("lets the next gather there count straight away", function()
        local ns, env = helpers.loggedIn()
        loot(env, 1731)
        ns.Recorder.Forget({ ns.Spawns.ByKey(HERE) })
        loot(env, 1731)
        assertEqual(1, ns.db.gathered[HERE].count)
    end)
end)

describe("/gmap reset gathered", function()
    it("asks first, then forgets everything on a second go within 10 seconds", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        helpers.command(env, "reset gathered")
        assertTrue(ns.db.gathered[helpers.A] ~= nil, "not yet")
        assertMatch("again within 10 seconds", helpers.printed(env))
        env.__now = env.__now + 3
        helpers.command(env, "reset gathered")
        assertNil(next(ns.db.gathered))
        assertEqual(0, #ns.Spawns.All(0))
        assertMatch("Forgot every place", helpers.printed(env))
    end)

    it("asks again when the second go comes too late", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        helpers.command(env, "reset gathered")
        env.__now = env.__now + 11
        helpers.command(env, "reset gathered")
        assertTrue(ns.db.gathered[helpers.A] ~= nil)
    end)

    it("says how to use it without 'gathered'", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "reset")
        assertMatch("/gmap reset gathered", helpers.printed(env))
    end)
end)
