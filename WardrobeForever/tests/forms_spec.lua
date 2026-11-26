local helpers = require("helpers")

local SLOT = helpers.SLOT
local CAT, BEAR, TRAVEL = helpers.CAT, helpers.BEAR, helpers.TRAVEL

--- A druid in caster gear (head and legs), with the Cat set's legs in the
-- backpack. `extra` sees the client before login, to add to it.
local function druid(extra)
    return helpers.start(nil, function(env)
        helpers.druid(env)
        helpers.wear(env, SLOT.HEAD, "head-caster")
        helpers.wear(env, SLOT.LEGS, "legs-caster")
        helpers.stow(env, "legs-cat", SLOT.LEGS)
        helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat" })
        if extra then extra(env) end
    end)
end

--- The same druid with set 1 chosen for Cat Form.
local function catDruid(extra)
    local ns, env = druid(extra)
    ns.Forms.SetSet(CAT, 1)
    return ns, env
end

describe("shifting into a form with a set", function()
    it("puts on the Cat set when you shift into Cat Form", function()
        local _, env = catDruid()
        helpers.shift(env, CAT)
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
    end)

    it("leaves the slots the set ignores alone", function()
        local _, env = catDruid(function(env)
            helpers.stow(env, "head-cat", SLOT.HEAD)
        end)
        helpers.shift(env, CAT)
        assertEqual("head-caster", helpers.wearing(env, SLOT.HEAD))
    end)

    it("changes nothing for a form with no set", function()
        local _, env = catDruid()
        helpers.shift(env, TRAVEL)
        assertEqual(0, env.__pickups)
        assertNil(next(env.WardrobeForeverCharDB.normal))
    end)

    it("skips a set item that is missing", function()
        local _, env = catDruid(function(env)
            helpers.wear(env, SLOT.FEET, "feet-caster")
            helpers.item(env, "feet-sold", SLOT.FEET)
            helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat", [SLOT.FEET] = "feet-sold" })
        end)
        helpers.shift(env, CAT)
        assertEqual("feet-caster", helpers.wearing(env, SLOT.FEET))
        assertNil(env.WardrobeForeverCharDB.normal[SLOT.FEET])
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
    end)

    it("waits while you hold an item on the cursor", function()
        local _, env = catDruid(function(env)
            helpers.stow(env, "gloves-spare", SLOT.HANDS)
        end)
        env.C_Container.PickupContainerItem(env.C_Item.GetItemLocation("gloves-spare"):GetBagAndSlot())

        helpers.shift(env, CAT)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
        assertTrue(env.CursorHasItem(), "the item you hold stays on the cursor")

        env.ClearCursor() -- the item goes back to its bag, which unlocks it
        helpers.fire(env, "ITEM_UNLOCKED", 0, 1)
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
    end)
end)

describe("shifting out", function()
    it("puts back what you wore when you shift out", function()
        local _, env = catDruid()
        helpers.shift(env, CAT)
        helpers.shift(env, nil)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
        assertTrue(helpers.inBags(env, "legs-cat"))
    end)

    it("forgets what you wore once it is all back", function()
        local _, env = catDruid()
        helpers.shift(env, CAT)
        helpers.shift(env, nil)
        assertNil(next(env.WardrobeForeverCharDB.normal))
        assertNil(next(env.WardrobeForeverCharDB.placed))
    end)

    it("goes from Cat's set straight to Bear's, and back from either", function()
        local ns, env = catDruid(function(env)
            helpers.wear(env, SLOT.FEET, "feet-caster")
            helpers.stow(env, "legs-bear", SLOT.LEGS)
            helpers.stow(env, "feet-bear", SLOT.FEET)
            helpers.makeSet(env, 2, "Bear", { [SLOT.LEGS] = "legs-bear", [SLOT.FEET] = "feet-bear" })
        end)
        ns.Forms.SetSet(BEAR, 2)

        helpers.shift(env, CAT)
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
        assertEqual("feet-caster", helpers.wearing(env, SLOT.FEET))

        helpers.shift(env, BEAR)
        assertEqual("legs-bear", helpers.wearing(env, SLOT.LEGS))
        assertEqual("feet-bear", helpers.wearing(env, SLOT.FEET))

        helpers.shift(env, CAT)
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
        assertEqual("feet-caster", helpers.wearing(env, SLOT.FEET), "Bear's feet go when Cat's set has none")

        helpers.shift(env, nil)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
        assertEqual("feet-caster", helpers.wearing(env, SLOT.FEET))
    end)

    it("brings your normal gear back in a form left on Leave gear alone", function()
        local _, env = catDruid()
        helpers.shift(env, CAT)
        helpers.shift(env, TRAVEL)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
    end)
end)

describe("slots that need care", function()
    --- Cat's set saved with the off hand empty, worn with a book in it.
    local function emptyOffHand(extra)
        return catDruid(function(env)
            helpers.wear(env, SLOT.OFFHAND, "book")
            helpers.makeSet(env, 1, "Cat", { [SLOT.OFFHAND] = "empty" })
            if extra then extra(env) end
        end)
    end

    it("empties a slot the set saved as empty, and refills it on the way out", function()
        local _, env = emptyOffHand()
        helpers.shift(env, CAT)
        assertNil(helpers.wearing(env, SLOT.OFFHAND))
        assertTrue(helpers.inBags(env, "book"))

        helpers.shift(env, nil)
        assertEqual("book", helpers.wearing(env, SLOT.OFFHAND))
    end)

    it("keeps a slot it cannot empty when the bags are full", function()
        local _, env = emptyOffHand(function(env)
            env.__bagSize[0] = 1 -- legs-cat fills it
        end)
        helpers.shift(env, CAT)
        assertEqual("book", helpers.wearing(env, SLOT.OFFHAND))
        assertFalse(env.CursorHasItem(), "nothing left on the cursor")
    end)

    it("swaps rings between fingers and back", function()
        local _, env = catDruid(function(env)
            helpers.wear(env, SLOT.FINGER0, "ring-c")
            helpers.wear(env, SLOT.FINGER1, "ring-a")
            helpers.stow(env, "ring-b", SLOT.FINGER0)
            helpers.makeSet(env, 1, "Cat", { [SLOT.FINGER0] = "ring-a", [SLOT.FINGER1] = "ring-b" })
        end)
        helpers.shift(env, CAT)
        assertEqual("ring-a", helpers.wearing(env, SLOT.FINGER0))
        assertEqual("ring-b", helpers.wearing(env, SLOT.FINGER1))

        helpers.shift(env, nil)
        assertEqual("ring-c", helpers.wearing(env, SLOT.FINGER0))
        assertEqual("ring-a", helpers.wearing(env, SLOT.FINGER1))
    end)

    it("brings back the off-hand a two-hander pushed off", function()
        local _, env = catDruid(function(env)
            helpers.wear(env, SLOT.MAINHAND, "mace")
            helpers.wear(env, SLOT.OFFHAND, "book")
            helpers.item(env, "staff", SLOT.MAINHAND, true)
            helpers.stow(env, "staff", SLOT.MAINHAND)
            helpers.makeSet(env, 1, "Cat", { [SLOT.MAINHAND] = "staff" })
        end)
        helpers.shift(env, CAT)
        assertEqual("staff", helpers.wearing(env, SLOT.MAINHAND))
        assertNil(helpers.wearing(env, SLOT.OFFHAND))

        helpers.shift(env, nil)
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual("book", helpers.wearing(env, SLOT.OFFHAND))
    end)
end)

describe("in a fight", function()
    --- Cat's set with a weapon: a staff in place of the mace.
    local function armed(extra)
        return catDruid(function(env)
            helpers.wear(env, SLOT.MAINHAND, "mace")
            helpers.stow(env, "staff-cat", SLOT.MAINHAND)
            helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat", [SLOT.MAINHAND] = "staff-cat" })
            if extra then extra(env) end
        end)
    end

    -- Forever blocks addons from equipping in a fight, weapons too
    -- ("Interface action failed because of an AddOn", 2026-11-26): it all
    -- waits for the fight to end.
    it("changes nothing in a fight, and all of it when the fight ends", function()
        local _, env = armed()
        helpers.fight(env, true)
        helpers.shift(env, CAT)
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
        assertEqual(0, env.__blocked, "never asks for what the game blocks")

        helpers.fight(env, false)
        assertEqual("staff-cat", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
    end)

    it("counts only the form you end the fight in", function()
        local _, env = armed()
        helpers.fight(env, true)
        helpers.shift(env, CAT)
        helpers.shift(env, BEAR)
        helpers.shift(env, nil)
        helpers.fight(env, false)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual(0, env.__blocked)
    end)

    it("puts it all back when a fight you left the form in ends", function()
        local _, env = armed()
        helpers.shift(env, CAT)
        helpers.fight(env, true)
        helpers.shift(env, nil)
        assertEqual("staff-cat", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
        assertEqual(0, env.__blocked)

        helpers.fight(env, false)
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
    end)
end)

describe("your own changes", function()
    it("leaves a slot you changed by hand while shifted", function()
        local _, env = catDruid(function(env)
            helpers.wear(env, SLOT.FEET, "feet-caster")
            helpers.stow(env, "feet-cat", SLOT.FEET)
            helpers.stow(env, "legs-pvp", SLOT.LEGS)
            helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat", [SLOT.FEET] = "feet-cat" })
        end)
        helpers.shift(env, CAT)
        helpers.byHand(env, SLOT.LEGS, "legs-pvp")

        helpers.shift(env, nil)
        assertEqual("legs-pvp", helpers.wearing(env, SLOT.LEGS))
        assertEqual("feet-caster", helpers.wearing(env, SLOT.FEET), "the rest still comes back")
    end)

    it("lets go of a normal item you no longer have", function()
        local _, env = catDruid()
        helpers.shift(env, CAT)
        helpers.remove(env, "legs-caster")

        helpers.shift(env, nil)
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
        assertNil(env.WardrobeForeverCharDB.normal[SLOT.LEGS])
    end)
end)

describe("swaps that cannot happen yet", function()
    it("tries a locked item again on the next equipment change", function()
        local _, env = catDruid(function(env)
            env.__locked["legs-cat"] = true
        end)
        helpers.shift(env, CAT)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))

        env.__locked["legs-cat"] = nil
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", SLOT.LEGS, false)
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
    end)

    it("does not mistake a swap still in flight for a change by hand", function()
        -- Cat to Bear: the Bear legs were sent for, and the slot still shows
        -- the Cat legs, locked, until the game answers.
        local saved = {
            forms = { [CAT] = { set = 1, index = 3 }, [BEAR] = { set = 2, index = 1 } },
            normal = { [SLOT.LEGS] = "legs-caster" },
            placed = { [SLOT.LEGS] = "legs-bear" },
        }
        local _, env = helpers.start(saved, function(env)
            helpers.druid(env)
            helpers.wear(env, SLOT.LEGS, "legs-cat")
            helpers.stow(env, "legs-caster", SLOT.LEGS)
            helpers.stow(env, "legs-bear", SLOT.LEGS)
            helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat" })
            helpers.makeSet(env, 2, "Bear", { [SLOT.LEGS] = "legs-bear" })
            env.__locked["legs-cat"] = true
            env.__form = 1
        end)
        assertEqual("legs-caster", env.WardrobeForeverCharDB.normal[SLOT.LEGS])
    end)
end)

describe("a reload in a form", function()
    --- Shifted into Cat in one session; the saved record and the gear as
    -- that session left them, for the next.
    local function reloadedInCat()
        local _, first = catDruid()
        helpers.shift(first, CAT)
        local saved = first.WardrobeForeverCharDB
        return helpers.start(saved, function(env)
            helpers.druid(env)
            helpers.wear(env, SLOT.HEAD, "head-caster")
            helpers.wear(env, SLOT.LEGS, "legs-cat")
            helpers.stow(env, "legs-caster", SLOT.LEGS)
            helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat" })
            env.__form = 3
        end)
    end

    it("swaps nothing on a reload in Cat Form", function()
        local _, env = reloadedInCat()
        assertEqual(0, env.__pickups)
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
    end)

    it("puts your normal gear back after a reload", function()
        local _, env = reloadedInCat()
        helpers.shift(env, nil)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
    end)
end)

describe("choices that last", function()
    local DIRE_BEAR, MOONKIN = 9634, 24858

    --- A second session for a druid whose first saved `saved`; `extra`
    -- changes the client before login (a new stance bar, say).
    local function nextSession(saved, extra)
        return helpers.start(saved, function(env)
            helpers.druid(env)
            helpers.wear(env, SLOT.LEGS, "legs-caster")
            helpers.stow(env, "legs-cat", SLOT.LEGS)
            helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat" })
            helpers.makeSet(env, 2, "Bear", {})
            if extra then extra(env) end
        end)
    end

    it("lists the stance bar's forms in order, by name", function()
        local ns = druid()
        local cat = ns.Forms.List()[3]
        assertEqual(CAT, cat.spellID)
        assertEqual("Cat Form", cat.name)
        assertEqual(3, cat.index)
    end)

    it("lists the character's sets in the game's order", function()
        local ns = druid(function(env)
            helpers.makeSet(env, 2, "Bear", {})
        end)
        local sets = ns.Forms.Sets()
        assertEqual(2, #sets)
        assertEqual(1, sets[1].setID)
        assertEqual("Cat", sets[1].name)
        assertEqual("Bear", sets[2].name)
    end)

    it("keeps Bear's set when Dire Bear Form takes its place", function()
        local ns, env = nextSession(nil)
        ns.Forms.SetSet(BEAR, 2)

        local later = nextSession(env.WardrobeForeverCharDB, function(env)
            env.__forms[1] = { spellID = DIRE_BEAR, name = "Dire Bear Form" }
        end)
        assertEqual(2, later.Forms.GetSet(DIRE_BEAR))
        assertNil(later.Forms.GetSet(BEAR))
    end)

    it("keeps every choice when a new form is learned", function()
        local ns, env = nextSession(nil)
        ns.Forms.SetSet(CAT, 1)
        ns.Forms.SetSet(BEAR, 2)

        local later = nextSession(env.WardrobeForeverCharDB, function(env)
            table.insert(env.__forms, { spellID = MOONKIN, name = "Moonkin Form" })
        end)
        assertEqual(1, later.Forms.GetSet(CAT))
        assertEqual(2, later.Forms.GetSet(BEAR))
        assertNil(later.Forms.GetSet(MOONKIN))
    end)

    it("treats a deleted set as Leave gear alone", function()
        local ns, env = catDruid()
        env.__sets[1] = nil
        helpers.fire(env, "EQUIPMENT_SETS_CHANGED")

        assertNil(ns.Forms.GetSet(CAT))
        helpers.shift(env, CAT)
        assertEqual(0, env.__pickups)
    end)

    it("does not wear a new set that took a deleted set's number", function()
        local ns, env = catDruid()
        env.__sets[1] = nil
        helpers.fire(env, "EQUIPMENT_SETS_CHANGED")
        helpers.makeSet(env, 1, "Fishing", { [SLOT.LEGS] = "legs-cat" })
        helpers.fire(env, "EQUIPMENT_SETS_CHANGED")

        assertNil(ns.Forms.GetSet(CAT))
        helpers.shift(env, CAT)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
    end)

    it("keeps the choices while the game has not sent the sets yet", function()
        local ns, env = nextSession(nil)
        ns.Forms.SetSet(CAT, 1)

        local later, laterEnv = nextSession(env.WardrobeForeverCharDB, function(env)
            env.__sets = {}
        end)
        helpers.fire(laterEnv, "EQUIPMENT_SETS_CHANGED")
        helpers.makeSet(laterEnv, 1, "Cat", { [SLOT.LEGS] = "legs-cat" })
        helpers.fire(laterEnv, "EQUIPMENT_SETS_CHANGED")
        assertEqual(1, later.Forms.GetSet(CAT))
    end)

    it("follows a set renamed on the Equipment Manager tab", function()
        local ns, env = catDruid()
        env.__sets[1].name = "Feral"
        helpers.fire(env, "EQUIPMENT_SETS_CHANGED")

        assertEqual(1, ns.Forms.GetSet(CAT))
        assertEqual("Feral", ns.Forms.Sets()[1].name)
    end)
end)

describe("changes by hand, there and then", function()
    it("keeps legs you put on by hand while shifted", function()
        local _, env = catDruid(function(env)
            helpers.stow(env, "legs-pvp", SLOT.LEGS)
        end)
        helpers.shift(env, CAT)
        helpers.byHand(env, SLOT.LEGS, "legs-pvp")
        assertEqual("legs-pvp", helpers.wearing(env, SLOT.LEGS))
        assertNil(env.WardrobeForeverCharDB.normal[SLOT.LEGS], "your pick is not taken for your normal gear")
    end)

    it("leaves a set item off that you took off by hand", function()
        local _, env = catDruid()
        helpers.shift(env, CAT)
        env.PickupInventoryItem(SLOT.LEGS)
        env.C_Container.PickupContainerItem(0, 10)
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", SLOT.LEGS, true)
        assertNil(helpers.wearing(env, SLOT.LEGS))
    end)

    it("does not put the set back over a change made after it went on", function()
        -- Already in the Cat legs before shifting: nothing to remember.
        local _, env = catDruid(function(env)
            helpers.remove(env, "legs-cat")
            helpers.wear(env, SLOT.LEGS, "legs-cat")
            helpers.stow(env, "legs-pvp", SLOT.LEGS)
        end)
        helpers.shift(env, CAT)
        helpers.byHand(env, SLOT.LEGS, "legs-pvp")
        assertEqual("legs-pvp", helpers.wearing(env, SLOT.LEGS))
    end)

    it("keeps an off-hand you changed by hand while shifted", function()
        local _, env = catDruid(function(env)
            helpers.wear(env, SLOT.MAINHAND, "mace")
            helpers.wear(env, SLOT.OFFHAND, "book")
            helpers.stow(env, "mace-cat", SLOT.MAINHAND)
            helpers.stow(env, "shield", SLOT.OFFHAND)
            helpers.makeSet(env, 1, "Cat", { [SLOT.MAINHAND] = "mace-cat" })
        end)
        helpers.shift(env, CAT)
        helpers.byHand(env, SLOT.OFFHAND, "shield")
        helpers.shift(env, nil)
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual("shield", helpers.wearing(env, SLOT.OFFHAND))
    end)
end)

describe("when the game takes its time", function()
    it("puts your normal gear back when you leave before the set has gone on", function()
        local _, env = catDruid()
        helpers.async(env)
        helpers.shift(env, CAT)
        helpers.shift(env, nil)
        helpers.land(env)
        helpers.land(env)
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
    end)

    it("puts mace and book back after a staff, one hand at a time", function()
        local _, env = catDruid(function(env)
            helpers.wear(env, SLOT.MAINHAND, "mace")
            helpers.wear(env, SLOT.OFFHAND, "book")
            helpers.item(env, "staff", SLOT.MAINHAND, true)
            helpers.stow(env, "staff", SLOT.MAINHAND)
            helpers.makeSet(env, 1, "Cat", { [SLOT.MAINHAND] = "staff" })
        end)
        helpers.async(env)
        helpers.shift(env, CAT)
        helpers.land(env)
        assertEqual("staff", helpers.wearing(env, SLOT.MAINHAND))

        helpers.shift(env, nil)
        for _ = 1, 3 do helpers.land(env) end
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
        assertEqual("book", helpers.wearing(env, SLOT.OFFHAND))
        assertEqual(0, env.__refused)
    end)

    it("finishes swapping rings when the game unlocks them after saying the gear changed", function()
        local _, env = catDruid(function(env)
            helpers.wear(env, SLOT.FINGER0, "ring-c")
            helpers.wear(env, SLOT.FINGER1, "ring-a")
            helpers.stow(env, "ring-b", SLOT.FINGER0)
            helpers.makeSet(env, 1, "Cat", { [SLOT.FINGER0] = "ring-a", [SLOT.FINGER1] = "ring-b" })
        end)
        helpers.async(env)
        helpers.shift(env, CAT)
        for _ = 1, 3 do helpers.land(env, "event-first") end
        assertEqual("ring-a", helpers.wearing(env, SLOT.FINGER0))
        assertEqual("ring-b", helpers.wearing(env, SLOT.FINGER1))

        helpers.shift(env, nil)
        for _ = 1, 3 do helpers.land(env, "event-first") end
        assertEqual("ring-c", helpers.wearing(env, SLOT.FINGER0))
        assertEqual("ring-a", helpers.wearing(env, SLOT.FINGER1))
    end)
end)

describe("when the game says no", function()
    it("keeps your normal gear on record when a swap is turned down", function()
        local ns, env = catDruid(function(env)
            helpers.stow(env, "legs-bear", SLOT.LEGS)
            helpers.makeSet(env, 2, "Bear", { [SLOT.LEGS] = "legs-bear" })
        end)
        ns.Forms.SetSet(BEAR, 2)
        helpers.async(env)
        helpers.shift(env, CAT)
        helpers.land(env)
        helpers.shift(env, BEAR)
        helpers.refuse(env)
        helpers.fire(env, "PLAYER_EQUIPMENT_CHANGED", SLOT.HEAD, false) -- any later gear change
        assertEqual("legs-caster", env.WardrobeForeverCharDB.normal[SLOT.LEGS])
    end)

    it("gives up on a swap turned down three times, until the next shift", function()
        local _, env = catDruid()
        helpers.async(env)
        helpers.shift(env, CAT)
        for _ = 1, 3 do helpers.refuse(env) end
        assertEqual(0, #env.__queue, "no fourth try")
        assertEqual(3, env.__refused)

        helpers.shift(env, nil)
        helpers.shift(env, CAT)
        assertEqual(1, #env.__queue, "a new shift tries again")
    end)

    it("waits for a cast to end", function()
        local _, env = catDruid()
        helpers.shift(env, CAT)
        env.__casting = true
        local pickups = env.__pickups
        helpers.shift(env, nil)
        assertEqual(pickups, env.__pickups, "nothing while casting")

        env.__casting = false
        helpers.fire(env, "UNIT_SPELLCAST_STOP", "player")
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
    end)

    it("waits until you are alive again", function()
        local _, env = catDruid()
        helpers.shift(env, CAT)
        env.__dead = true
        local pickups = env.__pickups
        helpers.shift(env, nil)
        assertEqual(pickups, env.__pickups, "nothing on a corpse")

        env.__dead = false
        helpers.fire(env, "PLAYER_ALIVE")
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
    end)
end)

describe("logging in shifted", function()
    --- The gear and record a Cat session left; `extra` sets up the login.
    local function loginInCat(extra)
        local _, first = catDruid()
        helpers.shift(first, CAT)
        return helpers.start(first.WardrobeForeverCharDB, function(env)
            helpers.druid(env)
            helpers.wear(env, SLOT.HEAD, "head-caster")
            helpers.wear(env, SLOT.LEGS, "legs-cat")
            helpers.stow(env, "legs-caster", SLOT.LEGS)
            env.__form = 3
            extra(env)
        end)
    end

    it("swaps nothing before the game has sent the sets", function()
        local _, env = loginInCat(function() end)
        assertEqual(0, env.__pickups)

        helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat" })
        helpers.fire(env, "EQUIPMENT_SETS_CHANGED")
        assertEqual(0, env.__pickups)
        assertEqual("legs-cat", helpers.wearing(env, SLOT.LEGS))
    end)

    it("swaps nothing before the stance bar knows its spells", function()
        local _, env = loginInCat(function(env)
            helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat" })
            env.__formsLoading = true
        end)
        assertEqual(0, env.__pickups)

        env.__formsLoading = false
        helpers.fire(env, "UPDATE_SHAPESHIFT_FORM")
        assertEqual(0, env.__pickups)
    end)
end)

describe("a set deleted while worn", function()
    it("brings your normal gear back", function()
        local _, env = catDruid(function(env)
            helpers.makeSet(env, 2, "Bear", {})
        end)
        helpers.shift(env, CAT)
        env.__sets[1] = nil
        helpers.fire(env, "EQUIPMENT_SETS_CHANGED")
        assertEqual("legs-caster", helpers.wearing(env, SLOT.LEGS))
    end)
end)

describe("weapons swapped by a stance button's click", function()
    --- Normal: mace and idol. Cat's set: a staff; Bear's: another staff.
    local function clicker(extra)
        local ns, env = catDruid(function(env)
            helpers.wear(env, SLOT.MAINHAND, "mace")
            helpers.wear(env, SLOT.RANGED, "idol")
            helpers.stow(env, "staff-cat", SLOT.MAINHAND)
            helpers.stow(env, "staff-bear", SLOT.MAINHAND)
            helpers.makeSet(env, 1, "Cat", { [SLOT.LEGS] = "legs-cat", [SLOT.MAINHAND] = "staff-cat" })
            helpers.makeSet(env, 2, "Bear", { [SLOT.MAINHAND] = "staff-bear" })
            if extra then extra(env) end
        end)
        ns.Forms.SetSet(BEAR, 2)
        return ns, env
    end

    it("remembers the weapons you wear in normal form", function()
        local _, env = clicker()
        assertEqual("mace", env.WardrobeForeverCharDB.home[SLOT.MAINHAND])
        assertEqual("idol", env.WardrobeForeverCharDB.home[SLOT.RANGED])

        helpers.shift(env, CAT)
        assertEqual("mace", env.WardrobeForeverCharDB.home[SLOT.MAINHAND], "not while shifted")
    end)

    it("knows your normal weapon when the click's swap lands before the shift", function()
        local ns, env = clicker()
        ns.Forms.ExpectClick({ [SLOT.MAINHAND] = "staff-cat" })
        helpers.byHand(env, SLOT.MAINHAND, "staff-cat")
        assertEqual("mace", env.WardrobeForeverCharDB.home[SLOT.MAINHAND], "the click's staff is not home")

        helpers.shift(env, CAT)
        assertEqual("mace", env.WardrobeForeverCharDB.normal[SLOT.MAINHAND])
        helpers.shift(env, nil)
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
    end)

    it("does not take the form's own set weapon, put on by the click, for a change by hand", function()
        local ns, env = clicker()
        helpers.shift(env, CAT)
        helpers.fight(env, true)
        helpers.shift(env, BEAR)
        helpers.byHand(env, SLOT.MAINHAND, "staff-bear") -- the click's swap, after the shift
        helpers.fight(env, false)
        helpers.shift(env, nil)
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
    end)

    it("does not take it for a change by hand when it lands before the shift either", function()
        local ns, env = clicker()
        helpers.shift(env, CAT)
        helpers.fight(env, true)
        ns.Forms.ExpectClick({ [SLOT.MAINHAND] = "staff-bear" })
        helpers.byHand(env, SLOT.MAINHAND, "staff-bear")
        helpers.shift(env, BEAR)
        helpers.fight(env, false)
        helpers.shift(env, nil)
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
    end)

    -- The game can refuse the shift (no mana, cooldown) while the click's
    -- /equipslot still goes through.
    it("still learns a new normal weapon after a shift the game refused", function()
        local ns, env = clicker(function(env)
            helpers.stow(env, "mace-new", SLOT.MAINHAND)
        end)
        ns.Forms.ExpectClick({ [SLOT.MAINHAND] = "mace" }) -- Travel Form: no set, refused
        helpers.byHand(env, SLOT.MAINHAND, "mace-new")
        assertEqual("mace-new", env.WardrobeForeverCharDB.home[SLOT.MAINHAND])
    end)

    it("puts the form's weapon back after a fight when a refused click swapped it", function()
        local ns, env = clicker()
        helpers.shift(env, CAT)
        helpers.fight(env, true)
        ns.Forms.ExpectClick({ [SLOT.MAINHAND] = "staff-bear" }) -- Bear refused, staff on
        helpers.byHand(env, SLOT.MAINHAND, "staff-bear")
        helpers.fight(env, false)
        assertEqual("staff-cat", helpers.wearing(env, SLOT.MAINHAND), "still in Cat")
        helpers.shift(env, nil)
        assertEqual("mace", helpers.wearing(env, SLOT.MAINHAND))
    end)

    it("tells the stance buttons what the normal and set weapons are", function()
        local ns = clicker()
        assertEqual("mace", ns.Forms.Normal(SLOT.MAINHAND))
        assertEqual("staff-cat", ns.Forms.SetItems(1)[SLOT.MAINHAND])
    end)
end)
