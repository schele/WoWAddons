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

describe("bank tabs", function()
    -- What a client with bank tabs hands over: each tab a container like a
    -- bag, its "bag" a placeholder item no player is meant to see.
    local TAB_BAG = { link = "|cffffffff|Hitem:999999::|h[Character Bank Tab Bag (DNT)]|h|r", icon = 4549254 }
    local TAB_ICON = "Interface\\AddOns\\BankBags\\tab"

    -- The old 28-slot bank, empty unless told otherwise, and two tabs (6 and
    -- 7) of 4 slots, Linen in the first.
    local function withTabs(mainItem, setup)
        return function(env)
            env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS = 4, 5, 6
            local main = {}
            for slot = 1, 28 do main[slot] = false end
            main[1] = mainItem or false
            helpers.bank(env,
                { [-1] = main, [6] = { LINEN, false, false, false }, [7] = { false, false, false, false } },
                { [6] = TAB_BAG, [7] = TAB_BAG })
            if setup then setup(env) end
        end
    end

    local function saved(setup)
        local ns, env = helpers.loggedIn(setup)
        helpers.fire(env, "BANKFRAME_OPENED")
        return ns.db.characters["Stormwind-Carl"].containers
    end

    it("names each tab as the game's bank does, not by its placeholder item", function()
        local containers = saved(withTabs())
        assertEqual("Tab 1", containers[1].name)
        assertEqual("Tab 2", containers[2].name)
        assertEqual(LINEN.link, containers[1].slots[1].link)
    end)

    it("gives a tab BankBags' own tab icon, not the placeholder item's", function()
        local containers = saved(withTabs())
        assertEqual(TAB_ICON, containers[1].icon)
        assertEqual(TAB_ICON, containers[2].icon)
    end)

    it("leaves out the old bank when it is empty and the tabs hold the bank", function()
        local containers = saved(withTabs())
        assertEqual(2, #containers)
        assertEqual(6, containers[1].id)
    end)

    it("keeps the old bank when something is in it", function()
        local containers = saved(withTabs(BOOTS))
        assertEqual(-1, containers[1].id)
        assertEqual("Bank", containers[1].name)
        assertEqual(3, #containers)
    end)

    it("keeps an empty bank on a client without tabs", function()
        local containers = saved(function(env)
            local main = {}
            for slot = 1, 24 do main[slot] = false end
            helpers.bank(env, { [-1] = main, [5] = { false, false, false, false } }, { [5] = BAG })
        end)
        assertEqual(-1, containers[1].id)
        assertEqual(2, #containers)
    end)

    it("takes a tab's name and icon from the client, when it says", function()
        local asked
        local containers = saved(withTabs(nil, function(env)
            env.Enum = { BankType = { Character = 0 } }
            env.C_Bank = {
                FetchPurchasedBankTabData = function(bankType)
                    asked = bankType
                    return { { ID = 6, name = "Mats", icon = 133784 }, { ID = 7, name = "" } }
                end,
            }
        end))
        assertEqual(0, asked, "the character's own tabs")
        assertEqual("Mats", containers[1].name)
        assertEqual(133784, containers[1].icon)
        assertEqual("Tab 2", containers[2].name, "a tab never named is numbered")
    end)

    -- A tab bought and never given an icon wears the game's question mark,
    -- 134400, which reads as a broken texture beside a heading.
    it("gives a tab still wearing the game's question mark BankBags' own icon", function()
        local containers = saved(withTabs(nil, function(env)
            env.C_Bank = {
                FetchPurchasedBankTabData = function()
                    return {
                        { ID = 6, name = "Mats", icon = 134400 },
                        { ID = 7, name = "Ore", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
                    }
                end,
            }
        end))
        assertEqual(TAB_ICON, containers[1].icon)
        assertEqual(TAB_ICON, containers[2].icon)
    end)

    it("still saves the bank when the client's tab data raises", function()
        local containers = saved(withTabs(nil, function(env)
            env.C_Bank = { FetchPurchasedBankTabData = function() error("secret") end }
        end))
        assertEqual("Tab 1", containers[1].name)
        assertEqual(2, #containers)
    end)
end)

describe("which containers are the bank bags", function()
    -- The ids saved, with every container from -1 to 13 holding one slot.
    local function savedIds(setup)
        local ns, env = helpers.loggedIn(function(e)
            setup(e)
            local containers = { [-1] = { false } }
            for id = 0, 13 do containers[id] = { false } end
            helpers.bank(e, containers, {})
        end)
        helpers.fire(env, "BANKFRAME_OPENED")
        local ids = {}
        for _, container in ipairs(ns.db.characters["Stormwind-Carl"].containers) do
            table.insert(ids, container.id)
        end
        return table.concat(ids, ",")
    end

    it("follows the game's own bag count: bags 5 to 10 on Classic", function()
        assertEqual("-1,5,6,7,8,9,10", savedIds(function(e)
            e.NUM_BAG_SLOTS, e.NUM_BANKBAGSLOTS = 4, 6
        end))
    end)

    it("counts a reagent bag when the client has one: bags 6 to 12", function()
        assertEqual("-1,6,7,8,9,10,11,12", savedIds(function(e)
            e.NUM_BAG_SLOTS, e.NUM_TOTAL_EQUIPPED_BAG_SLOTS, e.NUM_BANKBAGSLOTS = 4, 5, 7
        end))
    end)

    it("is not thrown off by a bag enum laid out for another client", function()
        assertEqual("-1,5,6,7,8,9,10", savedIds(function(e)
            e.NUM_BAG_SLOTS, e.NUM_BANKBAGSLOTS = 4, 6
            e.Enum = { BagIndex = { Bank = -1, BankBag_1 = 6 } }
        end))
    end)
end)
