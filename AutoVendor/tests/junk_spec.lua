local helpers = require("helpers")

local function ready()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    return ns, env
end

describe("/av junk", function()
    it("lists an item from its Shift-clicked link", function()
        local ns, env = ready()

        helpers.command(env, "junk " .. env.__link(2589))

        assertTrue(ns.Junk.Has(2589))
        assertEqual("Linen Cloth", ns.db.junk[2589])
        assertMatch("Selling %[Linen Cloth%] at every merchant%.", helpers.printed(env))
    end)

    it("lists an item from its number", function()
        local ns, env = ready()

        helpers.command(env, "junk 2589")

        assertTrue(ns.Junk.Has(2589))
        assertEqual("Linen Cloth", ns.db.junk[2589])
    end)

    it("says so when the item is listed already", function()
        local _, env = ready()
        helpers.command(env, "junk 2589")
        env.__printed = {}

        helpers.command(env, "junk 2589")

        assertMatch("%[Linen Cloth%] is already on the junk list%.", helpers.printed(env))
    end)

    it("gives the help for anything that is not an item", function()
        local ns, env = ready()

        helpers.command(env, "junk hello")

        assertMatch("/av junk", helpers.printed(env))
        assertNil(next(ns.db.junk))
    end)

    it("takes a kept item off the keep list, and says so", function()
        local ns, env = ready()
        helpers.command(env, "keep 3300")

        helpers.command(env, "junk 3300")

        assertFalse(ns.Keep.Has(3300))
        assertTrue(ns.Junk.Has(3300))
        assertMatch("Selling %[Rabbit's Foot%] at every merchant%. It is off the keep list%.", helpers.printed(env))
    end)
end)

describe("/av unjunk", function()
    it("takes an item off the list", function()
        local ns, env = ready()
        helpers.command(env, "junk 2589")

        helpers.command(env, "unjunk 2589")

        assertFalse(ns.Junk.Has(2589))
        assertMatch("No longer selling %[Linen Cloth%]%.", helpers.printed(env))
    end)

    it("says so when the item is not on the list", function()
        local _, env = ready()

        helpers.command(env, "unjunk 2589")

        assertMatch("%[Linen Cloth%] is not on the junk list%.", helpers.printed(env))
    end)
end)

describe("the junk list", function()
    it("is still there after a reload", function()
        local _, env = ready()
        helpers.command(env, "junk 2589")

        local ns = helpers.reload(env)

        assertTrue(ns.Junk.Has(2589))
    end)

    it("is in /av's help", function()
        local _, env = ready()

        helpers.command(env, "help")

        local printed = helpers.printed(env)
        assertMatch("/av junk", printed)
        assertMatch("/av unjunk", printed)
    end)
end)
