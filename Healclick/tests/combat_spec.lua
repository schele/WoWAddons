local helpers = require("helpers")

local FILES = { "Healclick.lua", "Slots.lua", "Row.lua", "Group.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("applying out of combat", function()
    it("writes the spells", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")

        assertTrue(ns.Group.ApplyAll())
        assertEqual("Regrowth", helpers.attrs(helpers.rowFor(ns, "party1").buttons[1]).spell)
    end)

    it("leaves nothing pending", function()
        local ns = loggedIn()
        ns.Group.ApplyAll()

        assertFalse(ns.Group.Pending())
    end)
end)

describe("applying in combat", function()
    it("refuses, and says so by returning false", function()
        local ns, env = loggedIn()
        env.__setCombat(true)

        assertFalse(ns.Group.ApplyAll())
    end)

    it("writes nothing at all", function()
        -- The client blocks this, not us. Attempting it and being refused is
        -- an error in the player's face, so we do not attempt it.
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        ns.Group.ApplyAll()

        env.__setCombat(true)
        ns.Slots.Set(1, "Rejuvenation")
        ns.Group.ApplyAll()

        assertEqual(
            "Regrowth",
            helpers.attrs(helpers.rowFor(ns, "party1").buttons[1]).spell,
            "still the old spell"
        )
    end)

    it("holds the change", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        ns.Group.ApplyAll()

        assertTrue(ns.Group.Pending())
    end)

    it("applies it the moment combat ends", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        ns.Slots.Set(1, "Rejuvenation")
        ns.Group.ApplyAll()

        env.__setCombat(false)

        assertEqual(
            "Rejuvenation",
            helpers.attrs(helpers.rowFor(ns, "party1").buttons[1]).spell
        )
        assertFalse(ns.Group.Pending())
    end)

    it("does nothing when combat ends with nothing waiting", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        ns.Group.ApplyAll()

        env.__setCombat(true)
        env.__setCombat(false)

        assertFalse(ns.Group.Pending())
    end)
end)

describe("what stays safe in combat", function()
    it("still refreshes health, which touches nothing secure", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        env.units.party1.health = 9

        ns.Group.RefreshAll()
        assertEqual(9, helpers.rowFor(ns, "party1").health:GetValue())
    end)

    it("still dims a unit that goes out of range mid-fight", function()
        local ns, env = loggedIn()
        env.__setCombat(true)
        env.units.party1.inRange = false

        env.__tick()
        assertTrue(helpers.rowFor(ns, "party1"):GetAlpha() < 1)
    end)
end)

describe("re-ordering, which moves secure buttons", function()
    it("waits for combat to end like everything else secure", function()
        local ns, env = loggedIn()
        ns.Group.ApplyAll()

        env.__setCombat(true)
        ns.db.bar.selfBottom = true
        ns.Group.ApplyAll()

        env.__setCombat(false)

        local player = helpers.rowFor(ns, "player")
        local party1 = helpers.rowFor(ns, "party1")
        local _, _, _, _, playerY = player:GetPoint(1)
        local _, _, _, _, party1Y = party1:GetPoint(1)

        assertTrue(playerY < party1Y, "you moved to the bottom once the fight ended")
    end)
end)

-- EXTRA REQUIREMENT: Group.Build() itself writes secure attributes
-- (Row.Create calls SetAttribute), and PLAYER_LOGIN can fire mid-fight -- a
-- /reload during a pull, or reconnecting after a disconnect mid-fight. If
-- Build does not hold off the same way ApplyAll does, the addon is left
-- half-built for the rest of the session: the anchor exists (satisfying
-- Build's own idempotence guard) but no rows do, and nothing tells the
-- player why their buttons never showed up.
describe("logging in during combat", function()
    it("holds the whole build, not just the spells", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__setCombat(true)
        helpers.login(ns, env)

        assertNil(
            helpers.rowFor(ns, "party1"),
            "Row.Create's SetAttribute is blocked exactly like ApplyAll's writes"
        )
    end)

    it("does not leave the guard falsely satisfied while still in combat", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__setCombat(true)
        helpers.login(ns, env)

        -- If Build had already created the anchor before checking combat,
        -- this second call would see the anchor and report "built" even
        -- though no row exists yet and the fight is still on.
        assertFalse(ns.Group.Build(), "asking again mid-fight must still be held")
    end)

    it("builds the rows and applies the spells the moment combat ends", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__setCombat(true)
        helpers.login(ns, env)

        env.__setCombat(false)

        assertTrue(helpers.rowFor(ns, "party1") ~= nil, "rows built")
        assertEqual(
            "Regrowth",
            helpers.attrs(helpers.rowFor(ns, "party1").buttons[1]).spell,
            "spells applied (the stub player is a druid)"
        )
        assertFalse(ns.Group.Pending())
    end)
end)
