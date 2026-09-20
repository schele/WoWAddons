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
        local ns, env = loggedIn()
        env.C_Container.GetContainerItemLink = function() error("secret value") end

        local ok, carried = pcall(ns.Items.Carried)
        assertTrue(ok, "a refused read must not take the bar down")
        assertEqual(0, #carried)
    end)
end)
