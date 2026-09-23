local helpers = require("helpers")

local FILES = { "ClickHeal.lua", "Anchors.lua", "Spells.lua", "Slots.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("the slot count", function()
    it("defaults to the shipped count", function()
        local ns = loggedIn()
        assertEqual(ns.Slots.DEFAULT_COUNT, ns.Slots.Count())
    end)

    it("ships as six", function()
        -- Named separately from the test above so that changing the number
        -- is a deliberate edit here rather than something that quietly
        -- follows a constant.
        local ns = loggedIn()
        assertEqual(6, ns.Slots.DEFAULT_COUNT)
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

        assertEqual("Rejuvenation", ns.Slots.Spell(1))
        assertEqual("Healing Touch", ns.Slots.Spell(2))
        assertEqual("Mark of the Wild", ns.Slots.Spell(3))
        assertEqual("Thorns", ns.Slots.Spell(4))
        assertNil(ns.Slots.Spell(5), "the seed is four long; the rest stay empty")
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
        -- ClickHealDB is account-wide (## SavedVariables): a first login on
        -- a Warrior must not permanently deny a Druid alt its own seed the
        -- first time it logs in.
        local ns = loggedIn()
        ns.Slots.Seed("WARRIOR")
        ns.Slots.Seed("DRUID")

        assertEqual("Rejuvenation", ns.Slots.Spell(1))
        assertEqual("Healing Touch", ns.Slots.Spell(2))
        assertEqual("Mark of the Wild", ns.Slots.Spell(3))
    end)
end)

describe("slot defaults", function()
    it("starts unlocked, with the player's own row on top", function()
        local ns = loggedIn()
        assertFalse(ns.db.bar.locked)
        assertFalse(ns.db.bar.selfBottom)
    end)
end)

describe("moving a spell to another slot", function()
    local function filled(ns, names)
        for index = 1, ns.Slots.MAX do
            ns.Slots.Set(index, names[index] or "")
        end
    end

    it("slides the ones between along rather than swapping", function()
        -- Dragging row 3 onto row 1 means "put this first". A swap would
        -- send whatever was first down to row 3, which nobody dragging
        -- asked for.
        local ns = loggedIn()
        filled(ns, { "Rejuvenation", "Healing Touch", "Regrowth" })

        assertTrue(ns.Slots.Move(3, 1))

        assertEqual("Regrowth", ns.Slots.Spell(1))
        assertEqual("Rejuvenation", ns.Slots.Spell(2))
        assertEqual("Healing Touch", ns.Slots.Spell(3))
    end)

    it("slides the other way just as well", function()
        local ns = loggedIn()
        filled(ns, { "Rejuvenation", "Healing Touch", "Regrowth" })

        ns.Slots.Move(1, 3)

        assertEqual("Healing Touch", ns.Slots.Spell(1))
        assertEqual("Regrowth", ns.Slots.Spell(2))
        assertEqual("Rejuvenation", ns.Slots.Spell(3))
    end)

    it("carries empty slots along like any other", function()
        -- A slot holds nothing as a hole in the table, not an empty string,
        -- so shifting in place would have to special-case every gap.
        local ns = loggedIn()
        filled(ns, { "Rejuvenation", nil, "Regrowth" })

        ns.Slots.Move(3, 1)

        assertEqual("Regrowth", ns.Slots.Spell(1))
        assertEqual("Rejuvenation", ns.Slots.Spell(2))
        assertNil(ns.Slots.Spell(3))
    end)

    it("reports nothing moved when it lands where it started", function()
        local ns = loggedIn()
        filled(ns, { "Rejuvenation" })

        assertFalse(ns.Slots.Move(1, 1))
        assertEqual("Rejuvenation", ns.Slots.Spell(1))
    end)

    it("refuses a slot outside the range, and changes nothing", function()
        local ns = loggedIn()
        filled(ns, { "Rejuvenation", "Healing Touch" })

        assertFalse(ns.Slots.Move(0, 1))
        assertFalse(ns.Slots.Move(1, ns.Slots.MAX + 1))
        assertFalse(ns.Slots.Move(nil, 1))

        assertEqual("Rejuvenation", ns.Slots.Spell(1), "left alone")
    end)

    it("leaves every slot accounted for, none lost or duplicated", function()
        local ns = loggedIn()
        filled(ns, { "Rejuvenation", "Healing Touch", "Regrowth", "Thorns" })

        ns.Slots.Move(2, 4)

        local seen = {}
        for index = 1, ns.Slots.MAX do
            local spell = ns.Slots.Spell(index)
            if spell then
                assertNil(seen[spell], spell .. " appears once")
                seen[spell] = true
            end
        end
        assertEqual("Healing Touch", ns.Slots.Spell(4))
    end)
end)
