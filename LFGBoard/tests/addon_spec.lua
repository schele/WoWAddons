local helpers = require("helpers")

describe("the addon's chat lines", function()
    it("start with its name", function()
        local ns, env = helpers.loadAddon()

        ns.Print("hello")

        assertMatch("^|cff66ccffLFG Board|r hello$", helpers.printed(env))
    end)
end)

describe("the saved variables", function()
    it("are made on the first login", function()
        local ns, env = helpers.loggedIn()

        assertEqual("table", type(env.LFGBoardDB))
        assertTrue(ns.db == env.LFGBoardDB)
    end)

    it("keep what an earlier session saved", function()
        local ns = helpers.loggedIn({ version = 1, custom = "kept" })

        assertEqual("kept", ns.db.custom)
    end)
end)

describe("the player", function()
    it("is known by name and realm", function()
        local ns = helpers.loggedIn()

        assertEqual("Skyler-Aldira", ns.Me())
    end)

    it("is told from others whether chat gives a realm or not", function()
        local ns = helpers.loggedIn()

        assertTrue(ns.IsMe("Skyler"))
        assertTrue(ns.IsMe("Skyler-Aldira"))
        assertFalse(ns.IsMe("Skyler-Other"))
        assertFalse(ns.IsMe("Garrok"))
        assertFalse(ns.IsMe(nil))
    end)
end)

describe("roles", function()
    it("start as a druid's: tank, healer and damage", function()
        local ns = helpers.loggedIn()

        local roles = ns.Roles()

        assertTrue(roles.tank)
        assertTrue(roles.healer)
        assertTrue(roles.dps)
    end)

    it("start as a warrior's: tank and damage", function()
        local ns, env = helpers.loadAddon()
        env.__player.class, env.__player.classFile = "Warrior", "WARRIOR"
        helpers.login(env)

        local roles = ns.Roles()

        assertTrue(roles.tank)
        assertFalse(roles.healer)
        assertTrue(roles.dps)
    end)

    it("start as a mage's: damage only", function()
        local ns, env = helpers.loadAddon()
        env.__player.class, env.__player.classFile = "Mage", "MAGE"
        helpers.login(env)

        local roles = ns.Roles()

        assertFalse(roles.tank)
        assertFalse(roles.healer)
        assertTrue(roles.dps)
    end)

    it("are kept per character, across a reload", function()
        local ns, env = helpers.loggedIn()
        ns.Roles().healer = false

        local again = helpers.loggedIn(env.LFGBoardDB)
        assertFalse(again.Roles().healer)

        local other, otherEnv = helpers.loadAddon(env.LFGBoardDB)
        otherEnv.__player.name = "Brakk"
        helpers.login(otherEnv)
        assertTrue(other.Roles().healer)
    end)
end)

describe("/lfgb", function()
    it("lists the registered commands on help", function()
        local ns, env = helpers.loadAddon()
        ns.RegisterCommand("test", "a test command", function() end)

        helpers.command(env, "help")

        assertMatch("/lfgb test %- a test command", helpers.printed(env))
    end)

    it("gives the help for a command it does not know", function()
        local _, env = helpers.loadAddon()

        helpers.command(env, "dance")

        assertMatch("Unknown command: dance", helpers.printed(env))
        assertMatch("Commands:", helpers.printed(env))
    end)

    it("answers to /lfgboard too", function()
        local _, env = helpers.loadAddon()

        assertEqual("/lfgb", env.SLASH_LFGBOARD1)
        assertEqual("/lfgboard", env.SLASH_LFGBOARD2)
    end)
end)

describe("a change to the board", function()
    it("does nothing while there is no window", function()
        local ns = helpers.loggedIn()

        ns.Changed()
    end)
end)

describe("the player on a realm with a space in its name", function()
    it("is known in chat, where the space is left out", function()
        local ns, env = helpers.loggedIn()
        env.__player.realm = "Living Flame"

        assertTrue(ns.IsMe("Skyler-LivingFlame"))

        env.GetNormalizedRealmName = function() return "LivingFlame" end
        assertTrue(ns.IsMe("Skyler-LivingFlame"))
        assertEqual("Skyler-LivingFlame", ns.Me())
    end)
end)
