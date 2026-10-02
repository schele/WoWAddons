local helpers = require("helpers")

local function holds(env, slot)
    local action = env.__actions[slot]
    return action and action.id
end

describe("upgrading", function()
    it("puts the highest rank on every outdated button", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.place(env, 14, 5186)
        helpers.place(env, 20, 1058)

        assertTrue(ns.Swap.Run())

        assertEqual(5189, holds(env, 3))
        assertEqual(5189, holds(env, 14))
        assertEqual(1430, holds(env, 20))
    end)

    it("leaves nothing on the cursor", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)

        ns.Swap.Run()

        assertNil(env.__cursor)
    end)

    it("leaves every other button as it was", function()
        local ns, env = helpers.loadAddon()
        env.__actions[1] = { kind = "item", id = 6948 }
        helpers.place(env, 2, 5189)
        helpers.place(env, 3, 5487)
        helpers.place(env, 4, 5188)

        ns.Swap.Run()

        assertEqual("item", env.__actions[1].kind)
        assertEqual(6948, holds(env, 1))
        assertEqual(5189, holds(env, 2))
        assertEqual(5487, holds(env, 3))
        assertEqual(1, #env.__placements, "only slot 4 is touched")
        assertEqual(4, env.__placements[1])
    end)

    it("says what it upgraded, spell by spell", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.place(env, 14, 5186)

        ns.Swap.Run()

        assertMatch("Healing Touch %-> Rank 5 %(2 buttons%)", helpers.printed(env))
    end)

    it("names a button that did not change, instead of counting it done", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.place(env, 14, 5186)
        env.__stuckSlots[14] = true

        ns.Swap.Run()

        local printed = helpers.printed(env)
        assertMatch("could not upgrade Healing Touch on action slot 14", printed)
        assertMatch("Healing Touch %-> Rank 5 %(1 button%)", printed)
    end)

    it("works from the bars as they are now, not as a popup listed them", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        ns.Ranks.Outdated() -- what a popup would have shown
        env.__actions[3] = { kind = "item", id = 6948 }

        ns.Swap.Run()

        assertEqual("item", env.__actions[3].kind)
        assertEqual(0, #env.__placements)
    end)
end)

describe("upgrading and combat", function()
    it("does nothing in combat", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        env.__inCombat = true

        assertFalse(ns.Swap.Run())

        assertEqual(5188, holds(env, 3))
        assertEqual(0, #env.__placements)
    end)

    it("stops when a fight starts partway, without an error", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.place(env, 14, 5186)
        env.__onPlace = function()
            env.__inCombat = true
        end

        assertFalse(ns.Swap.Run())

        assertEqual(5189, holds(env, 3))
        assertEqual(5186, holds(env, 14))
    end)
end)

describe("upgrading on the older client", function()
    it("picks the rank up through the old global", function()
        local ns, env = helpers.loadAddon()
        helpers.legacy(env)
        helpers.place(env, 3, 5188)

        assertTrue(ns.Swap.Run())

        assertEqual(5189, holds(env, 3))
    end)
end)
