local helpers = require("helpers")

local FILES = { "Healclick.lua", "Spells.lua", "Slots.lua", "Row.lua", "Group.lua" }

local function loggedIn(before)
    local ns, env = helpers.loadAddon(FILES)
    if before then before(ns, env) end
    helpers.login(ns, env)
    return ns, env
end

describe("the order of the rows", function()
    it("puts you first and the party in party order", function()
        local ns = loggedIn()
        local units = ns.Group.Units()

        assertEqual(5, #units)
        assertEqual("player", units[1])
        assertEqual("party1", units[2])
        assertEqual("party4", units[5])
    end)

    it("puts you last when you ask for it", function()
        local ns = loggedIn(function(_, env)
            env.HealclickDB = { bar = { selfBottom = true } }
        end)
        local units = ns.Group.Units()

        assertEqual("party1", units[1])
        assertEqual("player", units[5])
    end)

    it("keeps the party in party order either way", function()
        local ns = loggedIn(function(_, env)
            env.HealclickDB = { bar = { selfBottom = true } }
        end)
        local units = ns.Group.Units()

        assertEqual("party1", units[1])
        assertEqual("party2", units[2])
        assertEqual("party3", units[3])
        assertEqual("party4", units[4])
    end)
end)

describe("building the group", function()
    it("builds a row for every unit", function()
        local ns = loggedIn()

        for _, unit in ipairs(ns.Group.Units()) do
            assertTrue(helpers.rowFor(ns, unit) ~= nil, unit .. " has a row")
        end
    end)

    it("hands every row to RegisterUnitWatch", function()
        -- Showing and hiding a frame holding secure buttons is blocked in
        -- combat, which is exactly when the party changes. Blizzard's own
        -- watcher runs in the secure environment, so it is allowed to.
        local ns, env = loggedIn()

        assertEqual(5, #env.__watched)
        for _, row in ipairs(env.__watched) do
            assertTrue(row.unitWatched)
        end
    end)

    it("builds once, however often it is asked", function()
        local ns, env = loggedIn()
        local before = #env.__watched

        ns.Group.Build()
        assertEqual(before, #env.__watched, "no second set of rows")
    end)

    it("seeds the spells from the player's class", function()
        local ns = loggedIn()
        assertEqual("Regrowth", ns.Slots.Spell(1), "the stub player is a druid")
    end)
end)

describe("layout", function()
    it("stacks the rows downward from the anchor", function()
        local ns = loggedIn()
        ns.Group.Layout()

        local first = helpers.rowFor(ns, "player")
        local second = helpers.rowFor(ns, "party1")

        local _, _, _, _, firstY = first:GetPoint(1)
        local _, _, _, _, secondY = second:GetPoint(1)

        assertTrue(secondY < firstY, "party1 sits below you")
    end)

    it("re-stacks in the new order when you move to the bottom", function()
        local ns = loggedIn()
        ns.db.bar.selfBottom = true
        ns.Group.Layout()

        local player = helpers.rowFor(ns, "player")
        local party1 = helpers.rowFor(ns, "party1")

        local _, _, _, _, playerY = player:GetPoint(1)
        local _, _, _, _, party1Y = party1:GetPoint(1)

        assertTrue(playerY < party1Y, "you sit below party1 now")
    end)
end)

describe("the anchor", function()
    it("starts where the database says", function()
        local ns = loggedIn()
        assertEqual("CENTER", ns.db.anchor.point)
    end)

    it("does not move while locked", function()
        local ns = loggedIn()
        ns.db.bar.locked = true

        local anchor = ns.Group.Anchor()
        anchor.scripts.OnDragStart(anchor)

        assertFalse(anchor.moving == true, "a locked frame stays put")
    end)

    it("moves while unlocked", function()
        local ns = loggedIn()
        ns.db.bar.locked = false

        local anchor = ns.Group.Anchor()
        anchor.scripts.OnDragStart(anchor)

        assertTrue(anchor.moving)
    end)

    it("remembers where it was dropped", function()
        local ns = loggedIn()
        local anchor = ns.Group.Anchor()

        -- No nils in the middle: GetPoint unpacks this table, and a hole makes
        -- the length operator unreliable.
        anchor.points = { { "TOPLEFT", "UIParent", "TOPLEFT", 120, -40 } }
        anchor.scripts.OnDragStop(anchor)

        assertEqual("TOPLEFT", ns.db.anchor.point)
        assertEqual(120, ns.db.anchor.x)
        assertEqual(-40, ns.db.anchor.y)
    end)

    it("falls back to the documented default, not a bare zero, when the drop has no point", function()
        -- GetPoint(1) returning nothing is the edge the round-trip test above
        -- cannot reach, since it always hands OnDragStop a full point. x's
        -- literal 0 fallback used to match DEFAULT_ANCHOR.x by coincidence,
        -- hiding that y's did not (DEFAULT_ANCHOR.y is -200, not 0).
        local ns = loggedIn()
        local anchor = ns.Group.Anchor()

        anchor.points = {}
        anchor.scripts.OnDragStop(anchor)

        assertEqual("CENTER", ns.db.anchor.point)
        assertEqual(0, ns.db.anchor.x)
        assertEqual(-200, ns.db.anchor.y)
    end)

    it("goes back to the middle on /hc reset", function()
        local ns, env = loggedIn()
        ns.db.anchor.point, ns.db.anchor.x, ns.db.anchor.y = "TOPLEFT", 120, -40

        helpers.command(env, "reset")

        assertEqual("CENTER", ns.db.anchor.point)
        assertEqual(0, ns.db.anchor.x)
    end)

    it("toggles the lock on /hc lock", function()
        local ns, env = loggedIn()
        assertFalse(ns.db.bar.locked)

        helpers.command(env, "lock")
        assertTrue(ns.db.bar.locked)
    end)
end)

describe("keeping the rows current", function()
    it("refreshes every row on demand", function()
        local ns, env = loggedIn()
        env.units.party1.health = 12

        ns.Group.RefreshAll()
        assertEqual(12, helpers.rowFor(ns, "party1").health:GetValue())
    end)

    it("polls for range, because the game fires no event for it", function()
        local ns, env = loggedIn()
        env.units.party1.inRange = false

        env.__tick()
        assertTrue(helpers.rowFor(ns, "party1"):GetAlpha() < 1)
    end)

    it("refreshes when the roster changes", function()
        local ns, env = loggedIn()
        env.units.party1.name = "Someone Else"

        helpers.fire(env, "GROUP_ROSTER_UPDATE")
        assertEqual("Someone Else", helpers.rowFor(ns, "party1").name:GetText())
    end)

    it("refreshes the right row when its health changes", function()
        local ns, env = loggedIn()
        env.units.party2.health = 7

        helpers.fire(env, "UNIT_HEALTH", "party2")
        assertEqual(7, helpers.rowFor(ns, "party2").health:GetValue())
    end)
end)
