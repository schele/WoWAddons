local helpers = require("helpers")

describe("saved settings", function()
    it("starts with the window on, shown only in combat, and the warning on", function()
        local ns = helpers.loggedIn()

        assertTrue(ns.settings.shown, "window on")
        assertTrue(ns.settings.combatOnly, "only in combat")
        assertTrue(ns.settings.warn, "warning on")
    end)

    it("keeps what was saved", function()
        local ns = helpers.loggedIn(function(env)
            env.ThreatForeverDB = { settings = { warn = false } }
        end)

        assertFalse(ns.settings.warn)
        assertTrue(ns.settings.shown, "and fills in the rest")
    end)
end)

describe("slash commands", function()
    it("answers to /threat and /threatforever", function()
        local _, env = helpers.loggedIn()

        assertEqual("/threat", env.SLASH_THREATFOREVER1)
        assertEqual("/threatforever", env.SLASH_THREATFOREVER2)
    end)

    it("lists every command in the help", function()
        local _, env = helpers.loggedIn()

        helpers.command(env, "help")

        local text = helpers.printed(env)
        assertMatch("/threat %- ", text)
        assertMatch("/threat settings %- ", text)
        assertMatch("/threat check %- ", text)
    end)

    it("says so for a command it does not know", function()
        local _, env = helpers.loggedIn()

        helpers.command(env, "dance")

        assertMatch("Unknown command: dance", helpers.printed(env))
    end)
end)
