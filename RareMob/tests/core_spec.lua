local helpers = require("helpers")

describe("the saved variables", function()
    it("start with every switch on, pins of 14, and no sightings", function()
        local ns, env = helpers.loggedIn()
        assertEqual(env.RareMobDB, ns.db)
        assertEqual(ns.db.settings, ns.settings)
        assertTrue(ns.settings.worldPins)
        assertTrue(ns.settings.minimapPins)
        assertTrue(ns.settings.showUnseen)
        assertTrue(ns.settings.alert)
        assertEqual(14, ns.settings.pinSize)
        assertEqual("table", type(ns.db.sightings))
    end)

    it("keep what was saved", function()
        local ns = helpers.loggedIn(function(env)
            env.RareMobDB = { settings = { alert = false, pinSize = 20 }, sightings = { [462] = helpers.sighting("Vultros", 26, 1) } }
        end)
        assertFalse(ns.settings.alert)
        assertEqual(20, ns.settings.pinSize)
        assertEqual("Vultros", ns.db.sightings[462].name)
    end)

    it("replace a saved value that is not a table", function()
        local ns = helpers.loggedIn(function(env) env.RareMobDB = "broken" end)
        assertEqual("table", type(ns.db.sightings))
    end)

    it("make a recorder id once, and keep it", function()
        local ns, env = helpers.loggedIn()
        local id = ns.db.recorder
        assertEqual("string", type(id))
        assertEqual(8, #id)
        local again = helpers.loggedIn(function(fresh) fresh.RareMobDB = env.RareMobDB end)
        assertEqual(id, again.db.recorder)
    end)
end)

describe("the data files", function()
    it("hand over the rares, by id", function()
        local ns = helpers.loadAddon()
        local rare = ns.rares[1]
        assertEqual("Elite Rare", rare.name)
        assertEqual(40, rare.minLevel)
        assertEqual(42, rare.maxLevel)
        assertTrue(rare.elite)
        assertFalse(ns.rares[462].elite)
    end)

    it("hand over each continent's spawns", function()
        local ns = helpers.loadAddon()
        assertEqual(4, #ns.spawns[0])
        local first = ns.spawns[0][1]
        assertEqual(462, first.id)
        assertEqual(-10500, first.x)
        assertEqual(1500, first.y)
        assertEqual(5, ns.spawns[1][1].id)
    end)

    it("hand over each recorder's sightings", function()
        local ns = helpers.loadAddon()
        ns.AddRecordings("abc", { [462] = helpers.sighting("Vultros", 26, 1) })
        assertEqual("Vultros", ns.baked.abc[462].name)
    end)
end)

describe("logging in", function()
    it("runs every login handler, even after one that raises", function()
        local ns, env = helpers.loadAddon()
        local ran = false
        ns.OnLogin(function() error("broken") end)
        ns.OnLogin(function() ran = true end)
        helpers.login(ns, env)
        assertTrue(ran)
        assertMatch("Loaded%.", helpers.printed(env))
    end)
end)

describe("the commands", function()
    it("list themselves on /rm help", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "help")
        assertMatch("/rm probe", helpers.printed(env))
    end)

    it("answer /raremob too", function()
        local ns, env = helpers.loggedIn()
        assertEqual("/rm", env.SLASH_RAREMOB1)
        assertEqual("/raremob", env.SLASH_RAREMOB2)
    end)
end)

describe("/rm probe", function()
    local CALLS = {
        "UnitClassification", "UnitGUID", "UnitIsDead", "C_NamePlate.GetNamePlateForUnit",
        "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetWorldPosFromMapPos",
        "WorldMapFrame.AddDataProvider", "PlaySound",
    }

    it("names every call RareMob uses, and says this client has it", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "probe")
        local said = helpers.printed(env)
        for _, call in ipairs(CALLS) do
            assertMatch(call:gsub("%.", "%%.") .. ": yes", said)
        end
    end)

    it("says which are missing", function()
        local ns, env = helpers.loggedIn()
        env.UnitClassification = nil
        env.C_NamePlate = nil
        helpers.command(env, "probe")
        local said = helpers.printed(env)
        assertMatch("UnitClassification: missing", said)
        assertMatch("C_NamePlate%.GetNamePlateForUnit: missing", said)
        assertMatch("UnitGUID: yes", said)
    end)

    it("says where the client puts the player, or that it will not", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "probe")
        assertMatch("map 1436", helpers.printed(env))
        env.__playerMap = nil
        helpers.command(env, "probe")
        assertMatch("no map position", helpers.printed(env))
    end)
end)
