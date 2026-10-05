local helpers = require("helpers")

describe("reading the trees", function()
    it("reads each tree's name and talents from the game", function()
        local ns = helpers.loggedIn()
        local trees = ns.Trees.Read()
        assertEqual(3, #trees)
        assertEqual("Feral Combat", trees[2].name)
        assertEqual("icon-tab2", trees[2].icon)
        local instinct = trees[2].talents[2]
        assertEqual("Feral Instinct", instinct.name)
        assertEqual("icon-2-2", instinct.icon)
        assertEqual(1, instinct.tier)
        assertEqual(3, instinct.column)
        assertEqual(5, instinct.maxRank)
        assertEqual(0, instinct.rank)
    end)

    it("reads the player's ranks and points spent", function()
        local ns, env = helpers.loggedIn()
        env.__ranks[2][1] = 3
        local trees = ns.Trees.Read()
        assertEqual(3, trees[2].talents[1].rank)
        assertEqual(3, trees[2].spent)
    end)

    it("finds each prerequisite by its tier and column", function()
        local ns = helpers.loggedIn()
        local trees = ns.Trees.Read()
        assertEqual(5, trees[2].talents[9].prereq)
        assertEqual(9, trees[2].talents[10].prereq)
        assertEqual(2, trees[1].talents[3].prereq)
        assertNil(trees[2].talents[1].prereq)
    end)

    it("reads a tab's info with an ID before the name, as newer clients give it", function()
        local ns, env = helpers.loggedIn()
        env.__tabInfoIdFirst = true
        env.__ranks[1][1] = 2
        local trees = ns.Trees.Read()
        assertEqual("Balance", trees[1].name)
        assertEqual("icon-tab1", trees[1].icon)
        assertEqual(2, trees[1].spent)
    end)

    it("says which calls the client lacks, and reads nothing", function()
        local ns, env = helpers.loggedIn()
        env.GetTalentPrereqs = nil
        local trees, missing = ns.Trees.Read()
        assertNil(trees)
        assertEqual("GetTalentPrereqs", table.concat(missing, ", "))
    end)

    it("reads nothing from a call that raises", function()
        local ns, env = helpers.loggedIn()
        env.GetTalentInfo = function() error("secret") end
        assertNil(ns.Trees.Read())
    end)

    it("reads nothing for a class with no trees", function()
        local ns, env = helpers.loggedIn()
        env.GetNumTalentTabs = function() return 0 end
        assertNil(ns.Trees.Read())
    end)
end)

describe("unspent points", function()
    it("come from UnitCharacterPoints", function()
        local ns, env = helpers.loggedIn()
        env.__unspent = 2
        assertEqual(2, ns.Trees.Unspent())
    end)

    it("come from GetUnspentTalentPoints on a client without it", function()
        local ns, env = helpers.loggedIn()
        env.UnitCharacterPoints = nil
        env.GetUnspentTalentPoints = function() return 4 end
        assertEqual(4, ns.Trees.Unspent())
    end)

    it("are unknown on a client with neither", function()
        local ns, env = helpers.loggedIn()
        env.UnitCharacterPoints = nil
        assertNil(ns.Trees.Unspent())
    end)
end)

describe("import and export", function()
    it("exports the active plan", function()
        local ns = helpers.loggedIn()
        local plan = ns.Plans.Active()
        plan.points = helpers.points("2.2", "2.10")
        assertEqual("TP1:DRUID:222a", ns.Export())
    end)

    it("imports a good plan as a new active plan", function()
        local ns = helpers.loggedIn()
        ns.Plans.Active()
        local ok, name = ns.Import("TP1:DRUID:21212121212223")
        assertTrue(ok)
        assertEqual("Imported", name)
        local plan, active = ns.Plans.Active()
        assertEqual("Imported", active)
        assertEqual(7, #plan.points)
        local _, second = ns.Import("TP1:DRUID:22")
        assertEqual("Imported 2", second)
    end)

    it("refuses another class's plan", function()
        local ns = helpers.loggedIn()
        local ok, why = ns.Import("TP1:MAGE:11")
        assertFalse(ok)
        assertEqual("This plan is for a MAGE; you are a DRUID.", why)
    end)

    it("names the first point that breaks a rule", function()
        local ns = helpers.loggedIn()
        local ok, why = ns.Import("TP1:DRUID:222223")
        assertFalse(ok)
        assertEqual("Point 3 (level 12), Thick Hide: Thick Hide needs 5 points in Feral Combat first.", why)
        assertEqual("Plan 1", select(2, ns.Plans.Active()), "nothing stored")
    end)

    it("refuses a talent the tree does not have", function()
        local ns = helpers.loggedIn()
        local ok, why = ns.Import("TP1:DRUID:2c")
        assertFalse(ok)
        assertEqual("Point 1 (level 10), tree 2 talent 12: Tree 2 has no talent 12.", why)
    end)

    it("passes on the codec's reason for a broken string", function()
        local ns = helpers.loggedIn()
        local ok, why = ns.Import("hello")
        assertFalse(ok)
        assertEqual("Not a TalentPlanner string.", why)
    end)

    it("says so when the client cannot read the trees", function()
        local ns, env = helpers.loggedIn()
        env.GetNumTalents = nil
        local ok, why = ns.Import("TP1:DRUID:22")
        assertFalse(ok)
        assertMatch("GetNumTalents", why)
    end)
end)
