local helpers = require("helpers")

local A = "0:1731:-10603.8:1154.0"     -- Copper Vein, skill 1
local C = "0:3764:-10610.0:1160.0"     -- Tin Vein, skill 65
local E = "0:180582:-10620.0:1170.0"   -- a pool
local F = "0:2843:-10700.0:1300.0"     -- a chest

local function shows(ns, where, key)
    return ns.Filter.Shows(where, ns.Spawns.ByKey(key))
end

describe("the filter", function()
    it("shows every kind on both maps by default", function()
        local ns = helpers.loggedIn()
        for _, key in ipairs({ A, C, E, F }) do
            assertTrue(shows(ns, "worldmap", key), key)
            assertTrue(shows(ns, "minimap", key), key)
        end
    end)

    it("hides everything while pins are off", function()
        local ns = helpers.loggedIn()
        ns.SetEnabled(false)
        assertFalse(shows(ns, "worldmap", A))
        assertFalse(shows(ns, "minimap", E))
    end)

    it("hides a kind on one map and not the other", function()
        local ns = helpers.loggedIn()
        ns.settings.minimap.kinds.chest = false
        assertFalse(shows(ns, "minimap", F))
        assertTrue(shows(ns, "worldmap", F))
    end)

    it("hides a node by name", function()
        local ns = helpers.loggedIn()
        ns.settings.worldmap.hidden["Copper Vein"] = true
        assertFalse(shows(ns, "worldmap", A))
        assertTrue(shows(ns, "worldmap", C))
    end)

    it("hides what the skill cannot gather yet, unless asked not to", function()
        local ns, env = helpers.loggedIn(function(env) env.__skills[3] = { "Mining", false, 50 } end)
        assertFalse(shows(ns, "worldmap", C), "Tin needs 65")
        assertTrue(shows(ns, "worldmap", A))
        ns.settings.worldmap.hideUngatherable = false
        assertTrue(shows(ns, "worldmap", C))
    end)

    it("hides grey nodes when asked", function()
        local ns = helpers.loggedIn(function(env) env.__skills[3] = { "Mining", false, 150 } end)
        assertTrue(shows(ns, "minimap", A))
        ns.settings.minimap.hideGrey = true
        assertFalse(shows(ns, "minimap", A), "Copper is grey at 150")
        assertTrue(shows(ns, "minimap", C), "Tin is green at 150")
    end)

    it("never hides pools or chests for skill", function()
        local ns = helpers.loggedIn(function(env) env.__skills = { { "Professions", true } } end)
        ns.settings.worldmap.hideGrey = true
        assertTrue(shows(ns, "worldmap", E))
        assertTrue(shows(ns, "worldmap", F))
        assertFalse(shows(ns, "worldmap", A), "no Mining: the vein is out of reach")
    end)

    it("shows only spawns confirmed in game when asked: yours, or the release's", function()
        local ns = helpers.loggedIn()
        ns.settings.worldmap.onlyConfirmed = true
        assertFalse(shows(ns, "worldmap", A), "only the database has it")
        assertTrue(shows(ns, "worldmap", C), "a baked recording confirmed it")
        ns.db.gathered[A] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0, count = 1 }
        assertTrue(shows(ns, "worldmap", A))
        assertTrue(shows(ns, "minimap", E), "the minimap's own setting is still off")
    end)

    it("tells confirmed spawns apart", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Filter.Confirmed(ns.Spawns.ByKey(A)))
        assertTrue(ns.Filter.Confirmed(ns.Spawns.ByKey(C)))
        ns.db.gathered[A] = { count = 1 }
        assertTrue(ns.Filter.Confirmed(ns.Spawns.ByKey(A)))
    end)

    it("hides a spawn marked not here, unless asked to show those", function()
        local ns = helpers.loggedIn()
        ns.db.missing[A] = 1790000000
        assertFalse(shows(ns, "worldmap", A))
        assertFalse(shows(ns, "minimap", A))
        ns.settings.minimap.showMissing = true
        assertTrue(shows(ns, "minimap", A))
        assertFalse(shows(ns, "worldmap", A))
    end)

    it("shows nothing for an object the catalog does not know", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Filter.Shows("worldmap", { entry = 424242, key = "x" }))
    end)
end)

describe("the filter on a spot", function()
    local function names(list)
        local out = {}
        for index, spawn in ipairs(list) do out[index] = spawn.entry end
        return table.concat(out, ",")
    end

    it("keeps the members it shows, in the spot's order", function()
        local ns = helpers.loggedIn(function(env) env.__skills[3] = { "Mining", false, 100 } end)
        local stack = ns.Spawns.ByKey(C).stack
        assertEqual("3764,1733", names(ns.Filter.Shown("worldmap", stack)))
        ns.settings.worldmap.hidden["Tin Vein"] = true
        assertEqual("1733", names(ns.Filter.Shown("worldmap", stack)))
        assertEqual("3764,1733", names(ns.Filter.Shown("minimap", stack)))
        ns.settings.worldmap.kinds.ore = false
        assertEqual("", names(ns.Filter.Shown("worldmap", stack)))
    end)

    it("leaves out a member the skill cannot gather yet", function()
        local ns = helpers.loggedIn()
        assertEqual("3764", names(ns.Filter.Shown("worldmap", ns.Spawns.ByKey(C).stack)), "Silver needs 75, Mining is 70")
    end)
end)
