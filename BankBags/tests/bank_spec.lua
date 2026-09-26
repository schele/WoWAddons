local helpers = require("helpers")

local LINEN = { link = "|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r", count = 20, icon = 132889, quality = 1 }
local BOOTS = { link = "|cff1eff00|Hitem:9387::|h[Revelosh's Boots]|h|r", count = 1, icon = 132541, quality = 2 }
local BAG = { link = "|cffffffff|Hitem:14155::|h[Mooncloth Bag]|h|r", icon = 133652 }

-- The main bank (-1) with Linen in slot 1 and Boots in slot 3 of 24, and one
-- bank bag (5), a Mooncloth Bag of 4 slots holding Linen in slot 2.
local function withBank(env)
    local main = {}
    for slot = 1, 24 do main[slot] = false end
    main[1], main[3] = LINEN, BOOTS
    helpers.bank(env, { [-1] = main, [5] = { false, LINEN, false, false } }, { [5] = BAG })
end

describe("saving the bank", function()
    it("saves the bank and its bags when it opens, with when", function()
        local ns, env = helpers.loggedIn(withBank)
        helpers.fire(env, "BANKFRAME_OPENED")
        local carl = ns.db.characters["Stormwind-Carl"]
        assertEqual("Carl", carl.name)
        assertEqual("Stormwind", carl.realm)
        assertEqual("DRUID", carl.class)
        assertEqual(env.__now, carl.saved)
        assertEqual(2, #carl.containers)
        local main, bag = carl.containers[1], carl.containers[2]
        assertEqual(-1, main.id)
        assertEqual("Bank", main.name)
        assertEqual(24, main.size)
        assertEqual(LINEN.link, main.slots[1].link)
        assertEqual(20, main.slots[1].count)
        assertEqual(132889, main.slots[1].icon)
        assertNil(main.slots[2], "an empty slot")
        assertEqual(2, main.slots[3].quality)
        assertEqual(5, bag.id)
        assertEqual("Mooncloth Bag", bag.name)
        assertEqual(133652, bag.icon)
        assertEqual(4, bag.size)
        assertEqual(LINEN.link, bag.slots[2].link)
    end)

    it("leaves out bag slots with no bag", function()
        local ns, env = helpers.loggedIn(withBank)
        helpers.fire(env, "BANKFRAME_OPENED")
        for _, container in ipairs(ns.db.characters["Stormwind-Carl"].containers) do
            assertTrue(container.id == -1 or container.id == 5, "only the bank and the one bag")
        end
    end)

    it("saves nothing away from the bank", function()
        local ns, env = helpers.loggedIn(withBank)
        helpers.fire(env, "BAG_UPDATE", 5)
        env.__runTimers()
        assertNil(ns.db.characters["Stormwind-Carl"])
        helpers.fire(env, "BANKFRAME_OPENED")
        helpers.fire(env, "BANKFRAME_CLOSED")
        helpers.bank(env, {}, {})
        helpers.fire(env, "BAG_UPDATE", 5)
        helpers.fire(env, "PLAYERBANKSLOTS_CHANGED", 1)
        env.__runTimers()
        assertEqual(2, #ns.db.characters["Stormwind-Carl"].containers, "the copy is kept")
    end)

    it("saves again after a change at the bank, once for a burst", function()
        local ns, env = helpers.loggedIn(withBank)
        helpers.fire(env, "BANKFRAME_OPENED")
        local main = {}
        for slot = 1, 24 do main[slot] = false end
        main[2] = BOOTS
        helpers.bank(env, { [-1] = main }, {})
        env.__now = env.__now + 60
        helpers.fire(env, "PLAYERBANKSLOTS_CHANGED", 2)
        helpers.fire(env, "BAG_UPDATE", -1)
        env.__runTimers()
        local carl = ns.db.characters["Stormwind-Carl"]
        assertEqual(BOOTS.link, carl.containers[1].slots[2].link)
        assertEqual(1, #carl.containers, "the bag was taken out")
        assertEqual(env.__now, carl.saved)
    end)

    it("saves a change made just before the bank closes", function()
        local ns, env = helpers.loggedIn(withBank)
        helpers.fire(env, "BANKFRAME_OPENED")
        helpers.bank(env, { [-1] = { BOOTS } }, {})
        helpers.fire(env, "PLAYERBANKSLOTS_CHANGED", 1)
        helpers.fire(env, "BANKFRAME_CLOSED")
        env.__runTimers()
        assertEqual(BOOTS.link, ns.db.characters["Stormwind-Carl"].containers[1].slots[1].link)
    end)

    it("reads the old container calls too", function()
        local ns, env = helpers.loggedIn()
        function env.GetContainerNumSlots(id) return id == -1 and 2 or 0 end
        function env.GetContainerItemInfo(id, slot)
            if id == -1 and slot == 2 then return 132889, 20, false, 1, false, false, LINEN.link end
        end
        helpers.fire(env, "BANKFRAME_OPENED")
        local main = ns.db.characters["Stormwind-Carl"].containers[1]
        assertEqual(2, main.size)
        assertEqual(LINEN.link, main.slots[2].link)
        assertEqual(20, main.slots[2].count)
    end)

    it("keeps each character apart, the one played listed first", function()
        local ns, env = helpers.loggedIn(withBank)
        ns.db.characters["Stormwind-Alt"] = { name = "Alt", realm = "Stormwind", containers = {} }
        ns.db.characters["Argent-Zed"] = { name = "Zed", realm = "Argent", containers = {} }
        helpers.fire(env, "BANKFRAME_OPENED")
        assertEqual("Stormwind-Carl,Argent-Zed,Stormwind-Alt", table.concat(ns.Bank.Characters(), ","))
        assertEqual("Alt", ns.Bank.Get("Stormwind-Alt").name)
    end)

    it("forgets a character with /bb forget", function()
        local ns, env = helpers.loggedIn()
        ns.db.characters["Stormwind-Alt"] = { name = "Alt", realm = "Stormwind", containers = {} }
        helpers.command(env, "forget alt")
        assertNil(ns.db.characters["Stormwind-Alt"])
        assertMatch("Forgot alt", helpers.printed(env))
        helpers.command(env, "forget nobody")
        assertMatch("No saved bank for nobody", helpers.printed(env))
    end)
end)
