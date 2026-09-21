local helpers = require("helpers")

local FILES = { "TrinketBar.lua", "Items.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("finding the trinkets in the bags", function()
    it("returns the ones that go in a trinket slot", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Kiss of the Spider")
        env.__carry(0, 2, "Hand of Justice")

        local carried = ns.Items.Carried()

        assertEqual(2, #carried)
    end)

    it("leaves out everything that is not a trinket", function()
        -- A bag is mostly not trinkets. Reagents, food and the bags
        -- themselves share it.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Kiss of the Spider")
        env.__carry(0, 2, "Runecloth Bag", "INVTYPE_BAG")
        env.__carry(0, 3, "Mageroyal", "")

        local carried = ns.Items.Carried()

        assertEqual(1, #carried)
        assertEqual("Kiss of the Spider", carried[1].name)
    end)

    it("sorts by name, so the bar only reshuffles when the set changes", function()
        -- Bag order changes every time the bags are tidied. A bar that
        -- reshuffles then is one no muscle memory can form on.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Zandalarian Hero Charm")
        env.__carry(0, 2, "Hand of Justice")
        env.__carry(1, 1, "Mark of the Chosen")

        local carried = ns.Items.Carried()

        assertEqual("Hand of Justice", carried[1].name)
        assertEqual("Mark of the Chosen", carried[2].name)
        assertEqual("Zandalarian Hero Charm", carried[3].name)
    end)

    it("walks every bag, not just the backpack", function()
        local ns, env = loggedIn()
        env.__carry(4, 7, "Kiss of the Spider")

        assertEqual(1, #ns.Items.Carried())
    end)

    it("carries the icon and where it was found", function()
        local ns, env = loggedIn()
        env.__carry(2, 5, "Hand of Justice")

        local first = ns.Items.Carried()[1]

        assertEqual(133308, first.texture)
        assertEqual(2, first.bag)
        assertEqual(5, first.slot)
        assertTrue(first.link ~= nil)
    end)

    it("lists two of the same trinket once", function()
        -- /equipslot takes the first match by name, and two identical icons
        -- side by side say nothing that can be acted on.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.__carry(0, 2, "Hand of Justice")

        assertEqual(1, #ns.Items.Carried())
    end)

    it("falls back to the old globals on a client that has them", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")

        local container = env.C_Container
        local item = env.C_Item
        env.C_Container = nil
        env.C_Item = nil
        env.GetContainerNumSlots = container.GetContainerNumSlots
        env.GetContainerItemLink = container.GetContainerItemLink
        env.GetItemInfo = item.GetItemInfo

        assertEqual(1, #ns.Items.Carried())
    end)

    it("is empty, not broken, when the bags cannot be walked at all", function()
        local ns, env = loggedIn()
        env.C_Container = nil

        assertEqual(0, #ns.Items.Carried())
    end)

    it("says so when it cannot walk the bags", function()
        local ns, env = loggedIn()
        env.C_Container = nil

        ns.Items.Carried()

        assertMatch("bags", helpers.printed(env))
    end)

    it("says so exactly once, however often it is asked", function()
        -- Carried() runs on every bag change. A message that repeats then
        -- is worse than the fault it reports.
        local ns, env = loggedIn()
        env.C_Container = nil

        ns.Items.Carried()
        ns.Items.Carried()
        ns.Items.Carried()

        local _, count = helpers.printed(env):gsub("bags", "bags")
        assertEqual(1, count)
    end)

    it("is empty when a bag read raises", function()
        -- Every client read here goes through ns.Guarded, because a read
        -- this client refuses to let tainted code inspect raises rather
        -- than returning nothing.
        --
        -- Something has to be in a bag first. With every bag empty the walk
        -- runs `for slot = 1, 0`, never calls the read at all, and returns
        -- an empty list by falling through -- which looks exactly like the
        -- guard working and would pass with the guard deleted.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.C_Container.GetContainerItemLink = function() error("secret value") end

        local ok, carried = pcall(ns.Items.Carried)
        assertTrue(ok, "a refused read must not take the bar down")
        assertEqual(0, #carried)
    end)

    it("says so when an item read raises, not only when the bag API is missing", function()
        -- warnOnce() used to be reachable only from the "no bag API at all"
        -- gate. A raising read (the secret-value case) fell into the whole
        -- walk's guard and said nothing -- silently emptying the bar with no
        -- explanation, which is worse than the fault it reports.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.C_Container.GetContainerItemLink = function() error("secret value") end

        ns.Items.Carried()

        assertMatch("bags", helpers.printed(env))
    end)

    it("skips only the item whose read raises, not the rest of the walk", function()
        -- The guard used to wrap the whole walk, so one unreadable item cost
        -- every item. Now it is pushed down to per-item, so a bad read costs
        -- only that item.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.__carry(0, 2, "Kiss of the Spider")

        local original = env.C_Container.GetContainerItemLink
        env.C_Container.GetContainerItemLink = function(bag, slot)
            if slot == 1 then
                error("secret value")
            end
            return original(bag, slot)
        end

        local carried = ns.Items.Carried()

        assertEqual(1, #carried)
        assertEqual("Kiss of the Spider", carried[1].name)
    end)

    it("warns once even when several items in the same walk fail", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.__carry(0, 2, "Kiss of the Spider")
        env.C_Container.GetContainerItemLink = function() error("secret value") end

        ns.Items.Carried()

        local _, count = helpers.printed(env):gsub("bags", "bags")
        assertEqual(1, count)
    end)

    it("does not claim the bar shows only what is worn when some trinkets read fine", function()
        -- warnOnce() was broadened to fire on any failing read, but kept
        -- describing total failure. Three trinkets carried, one of them
        -- unreadable: the other two are visibly on the bar, so "the bar
        -- shows only what you are wearing" is false the moment it prints.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.__carry(0, 2, "Kiss of the Spider")
        env.__carry(0, 3, "Zandalarian Hero Charm")

        local original = env.C_Container.GetContainerItemLink
        env.C_Container.GetContainerItemLink = function(bag, slot)
            if slot == 2 then
                error("secret value")
            end
            return original(bag, slot)
        end

        local carried = ns.Items.Carried()

        assertEqual(2, #carried, "the two readable trinkets still show")
        assertFalse(helpers.printed(env):find("shows only what you are wearing") ~= nil,
            "false and misleading when trinkets are visibly on the bar")
    end)

    it("says something for a partial failure too, just not the total-failure claim", function()
        -- Silence would be its own bug: a player missing a trinket they
        -- know they are carrying needs a reason, even a partial one.
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.__carry(0, 2, "Kiss of the Spider")

        local original = env.C_Container.GetContainerItemLink
        env.C_Container.GetContainerItemLink = function(bag, slot)
            if slot == 1 then
                error("secret value")
            end
            return original(bag, slot)
        end

        ns.Items.Carried()

        assertMatch("carrying", helpers.printed(env))
    end)

    it("warns about a partial failure at most once too", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.__carry(0, 2, "Kiss of the Spider")

        local original = env.C_Container.GetContainerItemLink
        env.C_Container.GetContainerItemLink = function(bag, slot)
            if slot == 1 then
                error("secret value")
            end
            return original(bag, slot)
        end

        ns.Items.Carried()
        ns.Items.Carried()
        ns.Items.Carried()

        local _, count = helpers.printed(env):gsub("carrying", "carrying")
        assertEqual(1, count)
    end)

    it("does not pass through a texture value that is not a number or a string", function()
        -- Bar.Apply branches on entry.texture ("if entry.texture then")
        -- outside any guard, from an event handler. Lua cannot construct a
        -- value that raises on a truthiness test, so this proves the
        -- coercion directly: an unreasonable shape (a table) comes back as
        -- nil, same as no icon at all.
        local ns, env = loggedIn()
        local link = env.__carry(0, 1, "Hand of Justice")
        env.__items[link].texture = {}

        local carried = ns.Items.Carried()

        assertNil(carried[1].texture)
    end)
end)

describe("what is worn", function()
    it("reads both trinket slots", function()
        local ns, env = loggedIn()
        env.__wear(13, "Hand of Justice")
        env.__wear(14, "Kiss of the Spider")

        local worn = ns.Items.Worn()

        assertEqual("Hand of Justice", worn[13].name)
        assertEqual("Kiss of the Spider", worn[14].name)
    end)

    it("says nothing for an empty slot", function()
        local ns, env = loggedIn()
        env.__wear(13, "Hand of Justice")

        assertNil(ns.Items.Worn()[14])
    end)

    it("is empty, not broken, when the read raises", function()
        local ns, env = loggedIn()
        env.GetInventoryItemLink = function() error("secret value") end

        local ok, worn = pcall(ns.Items.Worn)
        assertTrue(ok)
        assertNil(worn[13])
    end)
end)

describe("everything the bar shows", function()
    it("puts the worn and the carried in one list, sorted by name", function()
        local ns, env = loggedIn()
        env.__wear(13, "Mark of the Chosen")
        env.__carry(0, 1, "Zandalarian Hero Charm")
        env.__carry(0, 2, "Hand of Justice")

        local all = ns.Items.All()

        assertEqual(3, #all)
        assertEqual("Hand of Justice", all[1].name)
        assertEqual("Mark of the Chosen", all[2].name)
        assertEqual("Zandalarian Hero Charm", all[3].name)
    end)

    it("marks which slot a worn one is in", function()
        -- Without this the bar says what could go on but not what is on,
        -- and the swap is blind.
        local ns, env = loggedIn()
        env.__wear(14, "Mark of the Chosen")
        env.__carry(0, 1, "Hand of Justice")

        local all = ns.Items.All()

        assertNil(all[1].wornSlot, "the carried one is not worn")
        assertEqual(14, all[2].wornSlot)
    end)

    it("lists a trinket once even if a second copy is in the bags", function()
        local ns, env = loggedIn()
        env.__wear(13, "Hand of Justice")
        env.__carry(0, 1, "Hand of Justice")

        local all = ns.Items.All()

        assertEqual(1, #all)
        assertEqual(13, all[1].wornSlot, "the worn one wins, since it says more")
    end)
end)

describe("a trinket's cooldown", function()
    it("reads a worn one from its inventory slot", function()
        local ns, env = loggedIn()
        env.__wear(13, "Hand of Justice")
        env.__cooldowns["worn:13"] = { start = 100, duration = 120 }

        local start, duration = ns.Items.Cooldown(ns.Items.All()[1])

        assertEqual(100, start)
        assertEqual(120, duration)
    end)

    it("reads a carried one from its bag slot", function()
        local ns, env = loggedIn()
        env.__carry(2, 5, "Hand of Justice")
        env.__cooldowns["bag:2:5"] = { start = 100, duration = 90 }

        local start, duration = ns.Items.Cooldown(ns.Items.All()[1])

        assertEqual(100, start)
        assertEqual(90, duration)
    end)

    it("says nothing when there is no cooldown running", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")

        assertNil(ns.Items.Cooldown(ns.Items.All()[1]))
    end)

    it("says nothing when the read raises", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        env.C_Container.GetContainerItemCooldown = function() error("secret") end

        local ok, start = pcall(ns.Items.Cooldown, ns.Items.All()[1])
        assertTrue(ok)
        assertNil(start)
    end)
end)
