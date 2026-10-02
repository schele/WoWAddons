local helpers = require("helpers")

local function keyOf(ns, text)
    local activity = ns.Activities.Find(text)
    return activity and activity.key
end

describe("finding a dungeon in words", function()
    it("finds one by its abbreviation", function()
        local ns = helpers.loadAddon()
        local cases = {
            dm = "dm", vc = "dm", wc = "wc", sfk = "sfk", rfc = "rfc", bfd = "bfd",
            stocks = "stocks", gnomer = "gnomer", rfk = "rfk", sm = "sm", zf = "zf",
            brd = "brd", ubrs = "brs", strat = "strat", mc = "mc", bwl = "bwl", aq40 = "aq40",
        }
        for word, key in pairs(cases) do
            assertEqual(key, keyOf(ns, "LFM " .. word .. " need tank"), word)
        end
    end)

    it("finds one by the words of its name", function()
        local ns = helpers.loadAddon()

        assertEqual("dm", keyOf(ns, "anyone for deadmines"))
        assertEqual("sfk", keyOf(ns, "Shadowfang Keep run"))
        assertEqual("zf", keyOf(ns, "LF2M Zul'Farrak"))
        assertEqual("sm", keyOf(ns, "Scarlet Monastery - Library"))
        assertEqual("st", keyOf(ns, "The Temple of Atal'Hakkar"))
    end)

    it("tells the Deadmines from Dire Maul", function()
        local ns = helpers.loadAddon()

        assertEqual("dm", keyOf(ns, "LFM DM"))
        assertEqual("diremaul", keyOf(ns, "LFM DM east"))
        assertEqual("diremaul", keyOf(ns, "LFM DME"))
        assertEqual("diremaul", keyOf(ns, "dire maul tribute"))
    end)

    it("ignores case and punctuation", function()
        local ns = helpers.loadAddon()

        assertEqual("dm", keyOf(ns, "LF2M DM!!"))
        assertEqual("wc", keyOf(ns, "(WC)"))
    end)

    it("finds nothing in a message about something else", function()
        local ns = helpers.loadAddon()

        assertNil(ns.Activities.Find("selling linen cloth"))
        assertNil(ns.Activities.Find("LFM new dungeon"))
    end)

    it("does not find an abbreviation inside another word", function()
        local ns = helpers.loadAddon()

        assertNil(ns.Activities.Find("big dmg numbers"))
        assertNil(ns.Activities.Find("what a match"))
        assertNil(ns.Activities.Find("1st place"))
    end)
end)

describe("an activity", function()
    it("shows its name without a leading The", function()
        local ns = helpers.loadAddon()

        assertEqual("Deadmines", ns.Activities.Display(ns.Activities.ByKey("dm")))
        assertEqual("Wailing Caverns", ns.Activities.Display(ns.Activities.ByKey("wc")))
    end)

    it("counts a dungeon near the player's level within 3 levels of its range", function()
        local ns = helpers.loadAddon()
        local A = ns.Activities

        assertTrue(A.Near(A.ByKey("dm"), 20))
        assertTrue(A.Near(A.ByKey("rfc"), 20), "13-18, so up to 21")
        assertFalse(A.Near(A.ByKey("bfd"), 20), "24-32, so from 21")
        assertFalse(A.Near(A.ByKey("mc"), 20))
        assertTrue(A.Near(A.ByKey("mc"), nil), "a level that cannot be read hides nothing")
    end)

    it("is one of 26, each complete", function()
        local ns = helpers.loadAddon()

        assertEqual(26, #ns.Activities.LIST)
        for _, activity in ipairs(ns.Activities.LIST) do
            assertEqual("string", type(activity.key))
            assertEqual("string", type(activity.name))
            assertTrue(activity.kind == "dungeon" or activity.kind == "raid", activity.name)
            assertEqual(2, #activity.levels, activity.name)
            assertTrue(#activity.words > 0, activity.name)
        end
    end)
end)

describe("a message naming more than one thing", function()
    it("is for the dungeon it names first", function()
        local ns = helpers.loadAddon()

        assertEqual("sm", keyOf(ns, "LFM SM need heals, DM me"))
        assertEqual("zf", keyOf(ns, "LFM ZF need tank, dm me"))
        assertEqual("wc", keyOf(ns, "LFM WC then DM"))
        assertEqual("dm", keyOf(ns, "LFM DM need tank, then WC"))
    end)
end)
