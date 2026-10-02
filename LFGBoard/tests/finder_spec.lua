local helpers = require("helpers")

local GARROK_PARTY = {
    { role = "TANK", class = "WARRIOR" }, { role = "DAMAGER", class = "ROGUE" }, { role = "DAMAGER", class = "MAGE" },
}

describe("the group finder", function()
    it("is there when the client can search it", function()
        local ns, env = helpers.loadAddon()
        assertTrue(ns.Finder.Available())

        env.C_LFGList = nil
        assertFalse(ns.Finder.Available())
    end)

    it("has a category for each tab, All searching dungeons", function()
        local ns = helpers.loadAddon()

        assertEqual(2, ns.Finder.CategoryFor("dungeon"))
        assertEqual(114, ns.Finder.CategoryFor("raid"))
        assertEqual(116, ns.Finder.CategoryFor("quest"))
        assertEqual(2, ns.Finder.CategoryFor("all"))
    end)

    it("searches the tab's category", function()
        local ns, env = helpers.loadAddon()

        assertTrue(ns.Finder.Search("raid"))

        assertEqual(114, env.__searches[1])
    end)

    it("says why it cannot search", function()
        local ns, env = helpers.loadAddon()

        env.C_LFGList.Search = function() error("blocked") end
        local ok, why = ns.Finder.Search("dungeon")
        assertFalse(ok)
        assertEqual("the game refused the search", why)

        env.__categories = {}
        ok, why = ns.Finder.Search("dungeon")
        assertEqual("the group finder has no list for that tab", why)

        env.C_LFGList = nil
        ok, why = ns.Finder.Search("dungeon")
        assertEqual("this client has no group finder", why)
    end)
end)

describe("a listing", function()
    it("is read with its leader, activity, members and roles", function()
        local ns, env = helpers.loadAddon()
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY, "LF2M heals")

        local listing = ns.Finder.Read(1)

        assertEqual("Garrok", listing.leader)
        assertEqual("dm", listing.activity.key)
        assertEqual("dungeon", listing.kind)
        assertEqual(5, listing.max)
        assertEqual(3, #listing.members)
        assertEqual("tank", listing.members[1].role)
        assertEqual("WARRIOR", listing.members[1].class)
        assertEqual("dps", listing.members[2].role)
        assertEqual("WARRIOR", listing.class)
        assertEqual("LF2M heals", listing.comment)
        assertFalse(listing.full)
    end)

    it("is full with five of five", function()
        local ns, env = helpers.loadAddon()
        helpers.list(env, 1, "Garrok", 10, {
            { role = "TANK" }, { role = "HEALER" }, { role = "DAMAGER" }, { role = "DAMAGER" }, { role = "DAMAGER" },
        })

        assertTrue(ns.Finder.Read(1).full)
    end)

    it("is a quest group when its activity says quests", function()
        local ns, env = helpers.loadAddon()
        helpers.list(env, 1, "Brakk", 30, {})

        local listing = ns.Finder.Read(1)

        assertEqual("quest", listing.kind)
        assertNil(listing.activity)
    end)

    it("is read through the older finder's calls too", function()
        local ns, env = helpers.loadAddon()
        helpers.olderFinder(env)
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)

        assertEqual(114, ns.Finder.CategoryFor("raid"))
        assertEqual("dm", ns.Finder.Read(1).activity.key)
        assertEqual(5, ns.Finder.Read(1).max)
    end)
end)

describe("the finder's results", function()
    it("go on the board after any search, the game's own included", function()
        local ns, env = helpers.loadAddon()
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)

        helpers.searched(env)

        local rows = ns.Posts.Visible(helpers.ALL)
        assertEqual(1, #rows)
        assertEqual("Garrok", rows[1].name)
        assertEqual("finder", rows[1].source)
    end)

    it("take a group off when the game says it filled", function()
        local ns, env = helpers.loadAddon()
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)
        helpers.searched(env)

        table.insert(env.__results[1].members, { role = "HEALER", class = "PRIEST" })
        table.insert(env.__results[1].members, { role = "DAMAGER", class = "HUNTER" })
        helpers.fire(env, "LFG_LIST_SEARCH_RESULT_UPDATED", 1)

        assertEqual(0, #ns.Posts.Visible(helpers.ALL))
    end)

    it("take a group off when it delists", function()
        local ns, env = helpers.loadAddon()
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)
        helpers.searched(env)

        env.__results[1].delisted = true
        helpers.fire(env, "LFG_LIST_SEARCH_RESULT_UPDATED", 1)

        assertEqual(0, #ns.Posts.Visible(helpers.ALL))
    end)

    it("take a group off when the finder no longer has it", function()
        local ns, env = helpers.loadAddon()
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)
        helpers.searched(env)

        env.__results[1] = nil
        helpers.fire(env, "LFG_LIST_SEARCH_RESULT_UPDATED", 1)

        assertEqual(0, #ns.Posts.Visible(helpers.ALL))
    end)

    it("keep a group the finder updated with room left", function()
        local ns, env = helpers.loadAddon()
        helpers.list(env, 1, "Garrok", 10, { { role = "TANK", class = "WARRIOR" } })
        helpers.searched(env)

        table.insert(env.__results[1].members, { role = "DAMAGER", class = "MAGE" })
        helpers.fire(env, "LFG_LIST_SEARCH_RESULT_UPDATED", 1)

        local rows = ns.Posts.Visible(helpers.ALL)
        assertEqual(1, #rows)
        assertEqual(2, #rows[1].members)
    end)

    it("are not needed for the addon to load on a client without the finder's events", function()
        local ns = helpers.loadAddon(nil, function(env)
            env.__unknownEvents.LFG_LIST_SEARCH_RESULTS_RECEIVED = true
            env.__unknownEvents.LFG_LIST_SEARCH_RESULT_UPDATED = true
        end)

        assertTrue(ns.Finder.Available())
    end)
end)
