local helpers = require("helpers")

describe("the addon's chat lines", function()
    it("start with its name", function()
        local ns, env = helpers.loadAddon()

        ns.Print("hello")

        assertMatch("^|cff66ccffAutoVendor|r hello$", helpers.printed(env))
    end)
end)

describe("money words", function()
    it("spell out gold, silver and copper", function()
        local ns = helpers.loadAddon()

        assertEqual("1g 23s 45c", ns.Money(12345))
    end)

    it("leave out the parts that are zero", function()
        local ns = helpers.loadAddon()

        assertEqual("5s", ns.Money(500))
        assertEqual("1g", ns.Money(10000))
        assertEqual("1g 2s", ns.Money(10200))
    end)

    it("say 0c for nothing", function()
        local ns = helpers.loadAddon()

        assertEqual("0c", ns.Money(0))
    end)

    it("are the client's own, coin icons and all, where it has them", function()
        local ns, env = helpers.loadAddon()
        env.GetMoneyString = function(copper) return "MONEY:" .. copper end

        assertEqual("MONEY:5", ns.Money(5))
    end)
end)

describe("the saved variables", function()
    it("are made on the first login", function()
        local ns, env = helpers.loadAddon()

        helpers.login(env)

        assertEqual("table", type(env.AutoVendorDB))
        assertTrue(ns.db == env.AutoVendorDB)
    end)

    it("keep what an earlier session saved", function()
        local ns, env = helpers.loadAddon({ version = 1, custom = "kept" })

        helpers.login(env)

        assertEqual("kept", ns.db.custom)
    end)

    it("are filled in with the defaults a file registers", function()
        local ns, env = helpers.loadAddon()
        ns.AddDefaults({ things = { size = 3 } })

        helpers.login(env)

        assertEqual(3, ns.db.things.size)
    end)
end)

describe("/av", function()
    it("lists the registered commands", function()
        local ns, env = helpers.loadAddon()
        ns.RegisterCommand("test", "a test command", function() end)

        helpers.command(env, "")

        assertMatch("/av test %- a test command", helpers.printed(env))
    end)

    it("runs a command with what follows its name", function()
        local ns, env = helpers.loadAddon()
        local got
        ns.RegisterCommand("echo", "repeat", function(rest) got = rest end)

        helpers.command(env, "  ECHO Broken Fang  ")

        assertEqual("Broken Fang", got)
    end)

    it("gives the help for a command it does not know", function()
        local _, env = helpers.loadAddon()

        helpers.command(env, "dance")

        assertMatch("Unknown command: dance", helpers.printed(env))
        assertMatch("Commands:", helpers.printed(env))
    end)

    it("answers to /autovendor too", function()
        local _, env = helpers.loadAddon()

        assertEqual("/autovendor", env.SLASH_AUTOVENDOR1)
        assertEqual("/av", env.SLASH_AUTOVENDOR2)
    end)
end)
