local helpers = require("helpers")

local function ready()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    return ns, env
end

describe("/av keep", function()
    it("keeps an item from its Shift-clicked link", function()
        local ns, env = ready()

        helpers.command(env, "keep " .. env.__link(7073))

        assertTrue(ns.Keep.Has(7073))
        assertMatch("Keeping %[Broken Fang%]: it will not be sold%.", helpers.printed(env))
    end)

    it("keeps an item from its number", function()
        local ns, env = ready()

        helpers.command(env, "keep 3300")

        assertTrue(ns.Keep.Has(3300))
        assertMatch("Keeping %[Rabbit's Foot%]", helpers.printed(env))
    end)

    it("names an item the client has not described by its number", function()
        local ns, env = ready()
        env.__uncached[3300] = true

        helpers.command(env, "keep 3300")

        assertTrue(ns.Keep.Has(3300))
        assertMatch("Keeping %[item 3300%]", helpers.printed(env))
    end)

    it("says so when the item is kept already", function()
        local _, env = ready()
        helpers.command(env, "keep 7073")

        helpers.command(env, "keep " .. env.__link(7073))

        assertMatch("%[Broken Fang%] is already on the keep list%.", helpers.printed(env))
    end)

    it("gives the help for anything that is not an item", function()
        local ns, env = ready()

        helpers.command(env, "keep fang")

        assertMatch("Commands:", helpers.printed(env))
        assertEqual(nil, next(ns.Keep.All()))
    end)
end)

describe("/av unkeep", function()
    it("takes an item off the list", function()
        local ns, env = ready()
        helpers.command(env, "keep 7073")

        helpers.command(env, "unkeep " .. env.__link(7073))

        assertFalse(ns.Keep.Has(7073))
        assertMatch("No longer keeping %[Broken Fang%]%.", helpers.printed(env))
    end)

    it("says so when the item is not on the list", function()
        local _, env = ready()

        helpers.command(env, "unkeep 7073")

        assertMatch("%[Broken Fang%] is not on the keep list%.", helpers.printed(env))
    end)
end)

describe("/av list", function()
    it("says when the list is empty", function()
        local _, env = ready()

        helpers.command(env, "list")

        assertMatch("Nothing is on the keep list%.", helpers.printed(env))
    end)

    it("names every kept item, in name order", function()
        local _, env = ready()
        helpers.command(env, "keep 3300")
        helpers.command(env, "keep 7073")
        env.__printed = {}

        helpers.command(env, "list")

        local printed = helpers.printed(env)
        local fang = printed:find("[Broken Fang]", 1, true)
        local foot = printed:find("[Rabbit's Foot]", 1, true)
        assertTrue(fang and foot and fang < foot)
    end)
end)

describe("the keep list", function()
    it("is still there after a reload", function()
        local _, env = ready()
        helpers.command(env, "keep 7073")

        local ns = helpers.reload(env)

        assertTrue(ns.Keep.Has(7073))
    end)

    it("is in /av's help", function()
        local _, env = ready()

        helpers.command(env, "help")

        local printed = helpers.printed(env)
        assertMatch("/av keep", printed)
        assertMatch("/av unkeep", printed)
        assertMatch("/av list", printed)
    end)
end)
