local helpers = require("helpers")

describe("an outdated button", function()
    it("is listed with its old rank and the highest one", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188) -- Healing Touch Rank 4; Rank 5 is known

        local groups = ns.Ranks.Outdated()

        assertEqual(1, #groups)
        assertEqual("Healing Touch", groups[1].name)
        assertEqual("Rank 4", groups[1].fromRank)
        assertEqual("Rank 5", groups[1].toRank)
        assertEqual(5189, groups[1].toID)
        assertEqual(1, #groups[1].slots)
        assertEqual(3, groups[1].slots[1])
    end)

    it("shares one group with every other button of the same spell", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.place(env, 14, 5186)

        local groups = ns.Ranks.Outdated()

        assertEqual(1, #groups)
        assertEqual(2, #groups[1].slots)
        assertEqual(3, groups[1].slots[1])
        assertEqual(14, groups[1].slots[2])
    end)

    it("shows the lowest of the old ranks its group holds", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188) -- Rank 4, seen first
        helpers.place(env, 14, 5186) -- Rank 2

        assertEqual("Rank 2", ns.Ranks.Outdated()[1].fromRank)
    end)

    it("is found on a form's page and on the newer bars", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 100, 6807) -- Maul Rank 1, on Bear Form's page
        helpers.place(env, 180, 774) -- Rejuvenation Rank 1, bar 8's last button

        local groups = ns.Ranks.Outdated()

        assertEqual(2, #groups)
        assertEqual(100, groups[1].slots[1])
        assertEqual(180, groups[2].slots[1])
    end)

    it("comes in the order of the spells' names", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 1, 774) -- Rejuvenation
        helpers.place(env, 2, 5188) -- Healing Touch

        local groups = ns.Ranks.Outdated()

        assertEqual("Healing Touch", groups[1].name)
        assertEqual("Rejuvenation", groups[2].name)
    end)
end)

describe("a button that is not listed", function()
    it("holds the highest rank already", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5189)

        assertEqual(0, #ns.Ranks.Outdated())
    end)

    it("holds an item or a macro", function()
        local ns, env = helpers.loadAddon()
        -- IDs that are also old ranks' spell IDs: the kind is what counts.
        env.__actions[3] = { kind = "item", id = 5188 }
        env.__actions[4] = { kind = "macro", id = 5186 }

        assertEqual(0, #ns.Ranks.Outdated())
    end)

    it("holds a spell with only one rank", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5487) -- Bear Form

        assertEqual(0, #ns.Ranks.Outdated())
    end)

    it("holds a spell the character no longer knows", function()
        local ns, env = helpers.loadAddon()
        for id = 5185, 5189 do
            env.__known[id] = nil
        end
        helpers.place(env, 3, 5188)

        assertEqual(0, #ns.Ranks.Outdated())
    end)

    it("is empty", function()
        local ns = helpers.loadAddon()

        assertEqual(0, #ns.Ranks.Outdated())
    end)
end)

describe("a slot the client will not read", function()
    it("is skipped, and the slots after it are still read", function()
        local ns, env = helpers.loadAddon()
        env.__raisingSlots[2] = true
        helpers.place(env, 2, 5188)
        helpers.place(env, 3, 5186)

        local groups = ns.Ranks.Outdated()

        assertEqual(1, #groups)
        assertEqual(1, #groups[1].slots)
        assertEqual(3, groups[1].slots[1])
    end)
end)

describe("a rank's words", function()
    it("are the client's own", function()
        local ns = helpers.loadAddon()

        assertEqual("Rank 5", ns.Ranks.RankText(5189))
    end)

    it("are nil for a spell without a rank", function()
        local ns = helpers.loadAddon()

        assertNil(ns.Ranks.RankText(5487))
    end)
end)

describe("the older client's spell calls", function()
    it("find the same outdated button", function()
        local ns, env = helpers.loadAddon()
        helpers.legacy(env)
        helpers.place(env, 3, 5188)

        local groups = ns.Ranks.Outdated()

        assertEqual(1, #groups)
        assertEqual(5189, groups[1].toID)
        assertEqual("Rank 4", groups[1].fromRank)
        assertEqual("Rank 5", groups[1].toRank)
    end)
end)
