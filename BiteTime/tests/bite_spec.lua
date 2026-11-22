local helpers = require("helpers")
local stub = require("wow_stub")

describe("reading Ferocious Bite's tooltip", function()
    it("finds the damage for each number of combo points", function()
        local ns = helpers.loggedIn()
        local parsed = ns.Bite.Parse(stub.BITE_TEXT)
        assertEqual(5, #parsed.ranges)
        assertEqual(40, parsed.ranges[1][1])
        assertEqual(54, parsed.ranges[1][2])
        assertEqual(160, parsed.ranges[5][1])
        assertEqual(174, parsed.ranges[5][2])
    end)

    it("finds what each extra point of energy adds", function()
        local ns = helpers.loggedIn()
        assertNear(0.7, ns.Bite.Parse(stub.BITE_TEXT).perEnergy, 1e-9)
    end)

    it("reads a decimal comma, as a German client writes it", function()
        local ns = helpers.loggedIn()
        local text = stub.BITE_TEXT:gsub("0%.7", "0,7")
        assertNear(0.7, ns.Bite.Parse(text).perEnergy, 1e-9)
    end)

    it("reads damage past a thousand, with or without a separator", function()
        local ns = helpers.loggedIn()
        local parsed = ns.Bite.Parse("into 2.5 additional damage. 1 point: 1,040-1,120 damage 2 points: 1200-1290 damage")
        assertEqual(1040, parsed.ranges[1][1])
        assertEqual(1200, parsed.ranges[2][1])
        assertNear(2.5, parsed.perEnergy, 1e-9)
    end)

    it("takes the last five ranges when the text has another one first", function()
        local ns = helpers.loggedIn()
        local parsed = ns.Bite.Parse("Uses 1-5 combo points. " .. stub.BITE_TEXT)
        assertEqual(5, #parsed.ranges)
        assertEqual(40, parsed.ranges[1][1])
    end)

    it("counts no energy bonus when the text names none", function()
        local ns = helpers.loggedIn()
        assertEqual(0, ns.Bite.Parse("1 point: 10-12 damage").perEnergy)
    end)

    it("gives up on text with no damage in it", function()
        local ns = helpers.loggedIn()
        assertNil(ns.Bite.Parse("Finishing move."))
        assertNil(ns.Bite.Parse(""))
        assertNil(ns.Bite.Parse(nil))
    end)
end)

describe("a rank of Ferocious Bite", function()
    it("is read from the client: its tooltip, its energy cost and its icon", function()
        local ns = helpers.loggedIn()
        local rank = ns.Bite.Read(22568)
        assertEqual(22568, rank.id)
        assertEqual(40, rank.ranges[1][1])
        assertEqual(35, rank.cost)
        assertEqual(132127, rank.icon)
    end)

    it("costs 35 energy when the client will not say", function()
        local ns, env = helpers.loggedIn()
        env.C_Spell.GetSpellPowerCost = function() return nil end
        assertEqual(35, ns.Bite.Read(22568).cost)
    end)

    it("is read again later when the client had no tooltip for it yet", function()
        local ns = helpers.loggedIn()
        local spell = stub.SPELLS[22568]
        local saved = spell.description
        spell.description = ""
        ns.Bite.Forget() -- as at a login before the tooltip has loaded
        local early = ns.Bite.Read(22568)
        spell.description = saved
        assertNil(early)
        assertEqual(22568, ns.Bite.Read(22568).id)
    end)

    it("is told apart from other spells by the client's name for it", function()
        local ns, env = helpers.loggedIn()
        assertTrue(ns.Bite.Is(22568))
        assertTrue(ns.Bite.Is(22827))
        assertFalse(ns.Bite.Is(5221))
        assertFalse(ns.Bite.Is(nil))
        assertFalse(ns.Bite.Is(env.__secret(22568)))
    end)

    it("is the highest the character knows, when asked for the best", function()
        local ns, env = helpers.loggedIn()
        assertEqual(22568, ns.Bite.TopRank())
        env.__known[22827] = true
        assertEqual(22827, ns.Bite.TopRank())
    end)

    it("is none for a character who has not learned it", function()
        local ns, env = helpers.loggedIn()
        env.__known = {}
        assertNil(ns.Bite.TopRank())
    end)
end)

describe("the least a Bite does", function()
    local function rank()
        local ns = helpers.loggedIn()
        return ns, ns.Bite.Read(22568)
    end

    it("is the low end for the combo points, with just enough energy", function()
        local ns, r = rank()
        assertEqual(40, ns.Bite.Damage(r, 1, 35))
        assertEqual(100, ns.Bite.Damage(r, 3, 35))
    end)

    it("grows with the energy over its cost", function()
        local ns, r = rank()
        assertNear(160 + 25 * 0.7, ns.Bite.Damage(r, 5, 60), 1e-9)
    end)

    it("counts no extra when there is less energy than it costs", function()
        local ns, r = rank()
        assertEqual(70, ns.Bite.Damage(r, 2, 10))
    end)

    it("counts more combo points than the tooltip lists as the most it lists", function()
        local ns, r = rank()
        assertEqual(160, ns.Bite.Damage(r, 7, 35))
    end)

    it("is nothing without combo points", function()
        local ns, r = rank()
        assertNil(ns.Bite.Damage(r, 0, 100))
        assertNil(ns.Bite.Damage(nil, 3, 100))
    end)
end)
