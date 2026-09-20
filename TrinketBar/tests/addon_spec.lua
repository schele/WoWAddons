local helpers = require("helpers")

local ONLY_CORE = { "TrinketBar.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(ONLY_CORE)
    helpers.login(ns, env)
    return ns, env
end

describe("the database", function()
    it("exists once the player is logged in", function()
        local ns = loggedIn()
        assertTrue(ns.db ~= nil)
    end)

    it("keeps a value that was already saved", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        env.TrinketBarDB = { bar = { locked = true } }
        helpers.login(ns, env)

        assertTrue(ns.db.bar.locked)
    end)
end)

describe("the slash command", function()
    it("lists the commands for a bare /tb", function()
        -- The same as /fp, /url and /ch. Four addons whose login lines sit
        -- together must not disagree about what a bare command does.
        local ns, env = loggedIn()
        helpers.command(env, "")

        assertMatch("Commands:", helpers.printed(env))
    end)

    it("says so for a command it does not have", function()
        local ns, env = loggedIn()
        helpers.command(env, "nonsense")

        assertMatch("Unknown command: nonsense", helpers.printed(env))
    end)

    it("runs a registered command", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        local ran = false
        ns.RegisterCommand("poke", "pokes", function() ran = true end)
        helpers.login(ns, env)

        helpers.command(env, "poke")
        assertTrue(ran)
    end)
end)

describe("guarding a client read", function()
    it("returns what the call returned when nothing raises", function()
        local ns = loggedIn()
        assertEqual(7, ns.Guarded(function() return 7 end, 0))
    end)

    it("returns the fallback when the call raises", function()
        -- A secret value raises when it is inspected, not when it is
        -- fetched, so the branch has to be inside the guard too.
        local ns = loggedIn()
        assertEqual(0, ns.Guarded(function() error("secret value") end, 0))
    end)
end)
