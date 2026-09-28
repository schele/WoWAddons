local helpers = require("helpers")

local function shows(ns, where, key)
    return ns.Filter.Shows(where, ns.Spawns.ByKey(key))
end

describe("the filter", function()
    it("shows herbs and ore on both maps by default", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        for _, key in ipairs({ helpers.A, helpers.C, helpers.D, helpers.E }) do
            assertTrue(shows(ns, "worldmap", key), key)
            assertTrue(shows(ns, "minimap", key), key)
        end
    end)

    it("hides everything while pins are off", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        ns.SetEnabled(false)
        assertFalse(shows(ns, "worldmap", helpers.A))
    end)

    it("hides a kind on one map and not the other", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        ns.settings.minimap.kinds.herb = false
        assertFalse(shows(ns, "minimap", helpers.D))
        assertTrue(shows(ns, "worldmap", helpers.D))
    end)

    it("hides a node by name, listed or not", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        ns.settings.worldmap.hidden["Copper Vein"] = true
        ns.settings.worldmap.hidden["Strange Ore"] = true
        assertFalse(shows(ns, "worldmap", helpers.A))
        assertFalse(shows(ns, "worldmap", helpers.E))
        assertTrue(shows(ns, "worldmap", helpers.C))
    end)

    it("hides what the skill cannot gather yet, unless asked not to", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        assertFalse(shows(ns, "worldmap", helpers.S), "Silver needs 75, Mining is 70")
        ns.settings.worldmap.hideUngatherable = false
        assertTrue(shows(ns, "worldmap", helpers.S))
    end)

    it("hides grey nodes when asked", function()
        local ns = helpers.loggedIn(function(env)
            helpers.withGathers(env)
            env.__skills[3] = { "Mining", false, 150 }
        end)
        ns.settings.minimap.hideGrey = true
        assertFalse(shows(ns, "minimap", helpers.A), "Copper is grey at 150")
        assertTrue(shows(ns, "minimap", helpers.C), "Tin is green at 150")
    end)

    it("never hides an unlisted node for skill, having none", function()
        local ns = helpers.loggedIn(function(env)
            helpers.withGathers(env)
            env.__skills = { { "Professions", true } }
        end)
        ns.settings.worldmap.hideGrey = true
        assertTrue(shows(ns, "worldmap", helpers.E))
        assertFalse(shows(ns, "worldmap", helpers.A))
    end)

    it("gives the members of a spot it shows, in order", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        local shown = ns.Filter.Shown("worldmap", ns.Spawns.ByKey(helpers.C).stack)
        assertEqual(1, #shown, "Silver is out of reach at Mining 70")
        assertEqual(helpers.C, shown[1].key)
    end)
end)
