local helpers = require("helpers")

local FILES = { "Healclick.lua", "Spells.lua", "Slots.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("the slot count", function()
    it("defaults to four", function()
        local ns = loggedIn()
        assertEqual(4, ns.Slots.Count())
    end)

    it("clamps above the maximum", function()
        local ns = loggedIn()
        ns.db.bar.slots = 99
        assertEqual(ns.Slots.MAX, ns.Slots.Count())
    end)

    it("clamps below one", function()
        local ns = loggedIn()
        ns.db.bar.slots = 0
        assertEqual(1, ns.Slots.Count())
    end)

    it("builds more buttons than it uses, so growing needs no new frame", function()
        -- A frame created at the wrong moment is a frame the client refuses.
        local ns = loggedIn()
        assertTrue(ns.Slots.MAX > ns.Slots.Count())
    end)
end)

describe("setting a spell", function()
    it("stores a spell the client knows", function()
        local ns = loggedIn()
        local ok = ns.Slots.Set(1, "Regrowth")

        assertTrue(ok)
        assertEqual("Regrowth", ns.Slots.Spell(1))
    end)

    it("stores a spell the client does not know, and warns", function()
        -- ns.Spells.IsKnown only knows spells this character has learned. A
        -- level 5 Druid setting up Remove Curse for level 24 is being
        -- sensible, not making a typo, and refusing them would reject our own
        -- seeds.
        local ns = loggedIn()
        local ok, message = ns.Slots.Set(1, "Tranquility")

        assertTrue(ok, "stored anyway")
        assertEqual("Tranquility", ns.Slots.Spell(1))
        assertMatch("Tranquility", message, "but said so")
    end)

    it("trims surrounding space", function()
        local ns = loggedIn()
        ns.Slots.Set(1, "  Regrowth  ")

        assertEqual("Regrowth", ns.Slots.Spell(1))
    end)

    it("clears a slot given an empty string", function()
        local ns = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(1, "")

        assertNil(ns.Slots.Spell(1))
    end)

    it("refuses a slot number outside the range", function()
        local ns = loggedIn()

        assertFalse((ns.Slots.Set(0, "Regrowth")))
        assertFalse((ns.Slots.Set(ns.Slots.MAX + 1, "Regrowth")))
    end)
end)

describe("seeding", function()
    it("fills empty slots for the class", function()
        local ns = loggedIn()
        ns.Slots.Seed("DRUID")

        assertEqual("Regrowth", ns.Slots.Spell(1))
        assertEqual("Rejuvenation", ns.Slots.Spell(2))
        assertEqual("Remove Curse", ns.Slots.Spell(3))
        assertEqual("Mark of the Wild", ns.Slots.Spell(4))
    end)

    it("leaves a slot the player already chose", function()
        local ns = loggedIn()
        ns.Slots.Set(1, "Healing Touch")
        ns.Slots.Seed("DRUID")

        assertEqual("Healing Touch", ns.Slots.Spell(1))
    end)

    it("does not refill a slot the player deliberately emptied", function()
        -- Seeding is a starting point, not a policy. Emptying slot 2 and
        -- logging in again must not put Rejuvenation back.
        local ns = loggedIn()
        ns.Slots.Seed("DRUID")
        ns.Slots.Set(2, "")
        ns.Slots.Seed("DRUID")

        assertNil(ns.Slots.Spell(2))
    end)

    it("does nothing for a class it has no set for", function()
        local ns = loggedIn()
        ns.Slots.Seed("WARLOCK")

        assertNil(ns.Slots.Spell(1))
    end)

    it("survives being asked with no class at all", function()
        local ns = loggedIn()
        ns.Slots.Seed(nil)

        assertNil(ns.Slots.Spell(1))
    end)

    it("does not burn the account-wide flag on a class with no seed, so a later class still gets one", function()
        -- HealclickDB is account-wide (## SavedVariables): a first login on
        -- a Warrior must not permanently deny a Druid alt its own seed the
        -- first time it logs in.
        local ns = loggedIn()
        ns.Slots.Seed("WARRIOR")
        ns.Slots.Seed("DRUID")

        assertEqual("Regrowth", ns.Slots.Spell(1))
        assertEqual("Rejuvenation", ns.Slots.Spell(2))
        assertEqual("Remove Curse", ns.Slots.Spell(3))
        assertEqual("Mark of the Wild", ns.Slots.Spell(4))
    end)
end)

describe("slot defaults", function()
    it("starts unlocked, with the player's own row on top", function()
        local ns = loggedIn()
        assertFalse(ns.db.bar.locked)
        assertFalse(ns.db.bar.selfBottom)
    end)
end)
