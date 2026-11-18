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

    it("is a white item on the junk list", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 2589, 5) -- Linen Cloth

        local junk = ns.Bags.Junk({}, { [2589] = "Linen Cloth" })

        assertEqual(1, #junk)
        assertEqual(2589, junk[1].itemID)
        assertEqual(5, junk[1].count)
        assertEqual(13, junk[1].price)
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

    it("is an item on the junk list no merchant will pay for", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 6948) -- Hearthstone

        assertEqual(0, #ns.Bags.Junk({}, { [6948] = "Hearthstone" }))
    end)

    it("is an item on both lists: kept wins", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 2589)

        assertEqual(0, #ns.Bags.Junk({ [2589] = "Linen Cloth" }, { [2589] = "Linen Cloth" }))
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

describe("where a sale stands", function()
    it("is gone once the slot is empty", function()
        local ns = helpers.loadAddon()

        assertEqual("gone", ns.Bags.SlotState(1, 2, 3300))
    end)

    it("is gone once the slot holds something else", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 1, 2, 7073)

        assertEqual("gone", ns.Bags.SlotState(1, 2, 3300))
    end)

    it("is busy while the item is locked on its way", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 1, 2, 3300, 1, true)

        assertEqual("busy", ns.Bags.SlotState(1, 2, 3300))
    end)

    it("is there when the item is back in hand", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 1, 2, 3300)

        assertEqual("there", ns.Bags.SlotState(1, 2, 3300))
    end)

    it("is there when the slot will not answer, so nothing is counted on a guess", function()
        local ns, env = helpers.loadAddon()
        env.__raisingSlots["1:2"] = true

        assertEqual("there", ns.Bags.SlotState(1, 2, 3300))
    end)
end)

describe("what could be put on the junk list", function()
    it("is each white item in the bags once, with its name and icon", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 2589)
        helpers.put(env, 0, 2, 2589)

        local items = ns.Bags.Sellable({}, {})

        assertEqual(1, #items)
        assertEqual(2589, items[1].itemID)
        assertEqual("Linen Cloth", items[1].name)
        assertEqual(1, items[1].icon)
    end)

    it("is in name order", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 117) -- Tough Jerky
        helpers.put(env, 1, 1, 2589) -- Linen Cloth

        local items = ns.Bags.Sellable({}, {})

        assertEqual("Linen Cloth", items[1].name)
        assertEqual("Tough Jerky", items[2].name)
    end)

    it("leaves out greys, items with no sell price, and items on either list", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 3300) -- grey, sold anyway
        helpers.put(env, 0, 2, 6948) -- Hearthstone, no sell price
        helpers.put(env, 0, 3, 2589) -- on the junk list
        helpers.put(env, 0, 4, 7073) -- grey on the keep list
        helpers.put(env, 0, 5, 117) -- Tough Jerky

        local items = ns.Bags.Sellable({ [7073] = "Broken Fang" }, { [2589] = "Linen Cloth" })

        assertEqual(1, #items)
        assertEqual(117, items[1].itemID)
    end)

    it("leaves out a kept white item", function()
        local ns, env = helpers.loadAddon()
        helpers.put(env, 0, 1, 2589)

        assertEqual(0, #ns.Bags.Sellable({ [2589] = "Linen Cloth" }, {}))
    end)

    it("leaves out an item the client has not described yet, until it has", function()
        local ns, env = helpers.loadAddon()
        env.__uncached[2589] = true
        helpers.put(env, 0, 1, 2589)

        assertEqual(0, #ns.Bags.Sellable({}, {}))

        env.__uncached[2589] = nil
        assertEqual(1, #ns.Bags.Sellable({}, {}))
    end)

    it("skips a slot that will not read, and reads the rest", function()
        local ns, env = helpers.loadAddon()
        env.__raisingSlots["0:1"] = true
        helpers.put(env, 0, 1, 117)
        helpers.put(env, 0, 2, 2589)

        local items = ns.Bags.Sellable({}, {})

        assertEqual(1, #items)
        assertEqual(2589, items[1].itemID)
    end)

    it("is found with the older client's calls too", function()
        local ns, env = helpers.loadAddon()
        helpers.legacy(env)
        helpers.put(env, 0, 1, 2589)

        local items = ns.Bags.Sellable({}, {})

        assertEqual(1, #items)
        assertEqual("Linen Cloth", items[1].name)
        assertEqual(1, items[1].icon)
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
