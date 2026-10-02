local helpers = require("helpers")

describe("junk", function()
    it("is a grey item worth something, with where it is and what it fetches", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 3, 7073, 5)

        local junk = ns.Bags.Junk()

        assertEqual(1, #junk)
        assertEqual(0, junk[1].bag)
        assertEqual(3, junk[1].slot)
        assertEqual(7073, junk[1].itemID)
        assertEqual(5, junk[1].count)
        assertEqual(6, junk[1].price)
    end)

    it("is found in every bag, in bag order", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 4, 6, 3300)
        helpers.put(env, 0, 1, 7073)

        local junk = ns.Bags.Junk()

        assertEqual(2, #junk)
        assertEqual(0, junk[1].bag)
        assertEqual(4, junk[2].bag)
    end)
end)

describe("not junk", function()
    it("is a white item", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 2589) -- Linen Cloth

        assertEqual(0, #ns.Bags.Junk())
    end)

    it("is a grey item no merchant will pay for", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 9999) -- Worthless Rock

        assertEqual(0, #ns.Bags.Junk())
    end)

    it("is a grey item on the keep list", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 7073)

        assertEqual(0, #ns.Bags.Junk({ [7073] = "Broken Fang" }))
    end)

    it("is a locked item", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 7073, 1, true)

        assertEqual(0, #ns.Bags.Junk())
    end)

    it("is an item the client has not described yet", function()
        local ns, env = helpers.loadAddon()
        env.__uncached[7073] = true
        helpers.put(env, 0, 1, 7073)

        assertEqual(0, #ns.Bags.Junk())
    end)
end)

describe("a slot the client will not read", function()
    it("is skipped, and the slots after it are still read", function()
        local ns, env = helpers.loadAddon()
        env.__raisingSlots["0:1"] = true
        helpers.put(env, 0, 1, 7073)
        helpers.put(env, 0, 2, 3300)

        local junk = ns.Bags.Junk()

        assertEqual(1, #junk)
        assertEqual(2, junk[1].slot)
    end)
end)

describe("what a slot holds", function()
    it("is its item's ID", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 1, 2, 3300)

        assertEqual(3300, ns.Bags.ItemAt(1, 2))
    end)

    it("is nil when it is empty", function()
        local ns = helpers.loadAddon()

        assertNil(ns.Bags.ItemAt(1, 2))
    end)
end)

describe("the older client's calls", function()
    it("find the same junk", function()
        local ns, env = helpers.loadAddon()
        helpers.legacy(env)
        helpers.put(env, 0, 3, 7073, 5)
        helpers.put(env, 0, 4, 2589)

        local junk = ns.Bags.Junk()

        assertEqual(1, #junk)
        assertEqual(7073, junk[1].itemID)
        assertEqual(5, junk[1].count)
        assertEqual(6, junk[1].price)
    end)
end)
