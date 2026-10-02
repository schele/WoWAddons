local helpers = require("helpers")

local function ready()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    return ns, env
end

describe("opening a merchant", function()
    it("sells the first junk item at once, and the next after a pause", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)

        helpers.openMerchant(env)
        assertEqual(1, #env.__sales, "at once")
        assertEqual("0:1", env.__sales[1])

        env.__runTimers()
        assertEqual(2, #env.__sales, "after one pause")
        assertEqual("0:2", env.__sales[2])
    end)

    it("waits 0.2 seconds between sales", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)

        helpers.openMerchant(env)

        assertEqual(0.2, env.__timerDelays[1])
    end)

    it("sells every junk item and says what it earned", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300) -- 15c
        helpers.put(env, 0, 2, 7073, 5) -- 5 x 6c
        helpers.put(env, 1, 3, 1411) -- 1g 23s 45c

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertNil(env.__slots["0:1"])
        assertNil(env.__slots["0:2"])
        assertNil(env.__slots["1:3"])
        assertMatch("Sold 7 items for 1g 23s 90c%.", helpers.printed(env))
    end)

    it("says item for a single one", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertMatch("Sold 1 item for 15c%.", helpers.printed(env))
    end)

    it("leaves white, worthless and kept items alone", function()
        local ns, env = ready()
        helpers.put(env, 0, 1, 2589)
        helpers.put(env, 0, 2, 9999)
        helpers.put(env, 0, 3, 7073)
        ns.Keep.All()[7073] = "Broken Fang"

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(0, #env.__sales)
        assertEqual("", helpers.printed(env))
    end)

    it("sells loot that arrives during the visit", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)

        helpers.openMerchant(env)
        helpers.put(env, 0, 5, 7073)
        env.__runAllTimers()

        assertNil(env.__slots["0:5"])
        assertMatch("Sold 2 items for 21c%.", helpers.printed(env))
    end)

    it("does not count a sale the merchant refused, and tries it once", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        env.__refused[3300] = true

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(2, #env.__sales)
        assertMatch("Sold 1 item for 6c%.", helpers.printed(env))
    end)
end)

describe("closing the merchant", function()
    it("stops the selling and says what had sold", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        helpers.put(env, 0, 3, 1411)

        helpers.openMerchant(env)
        helpers.closeMerchant(env)
        env.__runAllTimers()

        assertEqual(1, #env.__sales)
        assertMatch("Sold 1 item for 15c%.", helpers.printed(env))
    end)

    it("does not repair", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        env.__money, env.__repairCost = 10000, 500

        helpers.openMerchant(env)
        helpers.closeMerchant(env)
        env.__runAllTimers()

        assertEqual(0, env.__repairs)
    end)

    it("says nothing when it closes without a visit", function()
        local _, env = ready()

        helpers.closeMerchant(env)
        helpers.closeMerchant(env)

        assertEqual("", helpers.printed(env))
    end)
end)

describe("opening again", function()
    it("ignores a second open signal during a visit", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)

        helpers.openMerchant(env)
        helpers.fire(env, "MERCHANT_SHOW")

        assertEqual(1, #env.__sales)
    end)

    it("starts a fresh visit after a close, without the old one's steps", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        helpers.put(env, 0, 3, 1411)
        helpers.put(env, 0, 4, 3300)

        helpers.openMerchant(env) -- sells 0:1
        helpers.closeMerchant(env)
        helpers.openMerchant(env) -- sells 0:2
        env.__runTimers()

        assertEqual(3, #env.__sales, "one sale per pause, not two")
    end)
end)

describe("repairing", function()
    it("comes after the selling", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        env.__money, env.__repairCost = 100, 50

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(1, env.__repairs)
        assertEqual("repair", env.__log[#env.__log])
        assertEqual("sell 0:2", env.__log[#env.__log - 1])
    end)

    it("is paid for with the junk's gold when your own falls short", function()
        local _, env = ready()
        helpers.put(env, 1, 1, 1411) -- 1g 23s 45c
        env.__money, env.__repairCost = 0, 10000

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(1, env.__repairs)
        assertMatch("Sold 1 item for 1g 23s 45c%. Repaired for 1g%.", helpers.printed(env))
    end)

    it("says what it cost", function()
        local _, env = ready()
        env.__money, env.__repairCost = 10000, 4500

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertMatch("^|cff66ccffAutoVendor|r Repaired for 45s%.$", helpers.printed(env))
    end)

    it("does not happen at a merchant that cannot repair", function()
        local _, env = ready()
        env.__money, env.__repairCost = 10000, 500
        env.__canRepair = false

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(0, env.__repairs)
        assertEqual("", helpers.printed(env))
    end)

    it("does not happen when nothing needs it", function()
        local _, env = ready()
        env.__money = 10000

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(0, env.__repairs)
        assertEqual("", helpers.printed(env))
    end)

    it("names the cost when the gold falls short, and repairs nothing", function()
        local _, env = ready()
        env.__money, env.__repairCost = 50, 10200

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(0, env.__repairs)
        assertMatch("Not enough gold to repair %(costs 1g 2s%)%.", helpers.printed(env))
    end)
end)

describe("the line", function()
    it("says nothing when there was nothing to do", function()
        local _, env = ready()

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual("", helpers.printed(env))
    end)

    it("puts the sale and the repair in one line", function()
        local _, env = ready()
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)
        env.__money, env.__repairCost = 10000, 4500

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertMatch("^|cff66ccffAutoVendor|r Sold 2 items for 21c%. Repaired for 45s%.$", helpers.printed(env))
    end)
end)

describe("the older client's calls", function()
    it("sell the junk the same way", function()
        local _, env = ready()
        helpers.legacy(env)
        helpers.put(env, 0, 1, 3300)

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertNil(env.__slots["0:1"])
        assertMatch("Sold 1 item for 15c%.", helpers.printed(env))
    end)
end)

describe("a server that answers a sale late", function()
    it("still counts the sale once the answer comes", function()
        local _, env = ready()
        env.__slowSales = true
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertNil(env.__slots["0:1"])
        assertNil(env.__slots["0:2"])
        assertMatch("Sold 2 items for 21c%.", helpers.printed(env))
    end)

    it("repairs with the gold of a sale answered late", function()
        local _, env = ready()
        env.__slowSales = true
        helpers.put(env, 1, 1, 1411) -- 1g 23s 45c
        env.__money, env.__repairCost = 0, 10000

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(1, env.__repairs)
        assertMatch("Sold 1 item for 1g 23s 45c%. Repaired for 1g%.", helpers.printed(env))
    end)

    it("gives up on a sale the server never answers, and sells the rest", function()
        local _, env = ready()
        env.__slowSales = true
        env.__lostSales[3300] = true
        helpers.put(env, 0, 1, 3300)
        helpers.put(env, 0, 2, 7073)

        helpers.openMerchant(env)
        env.__runAllTimers()

        assertEqual(2, #env.__sales)
        assertMatch("Sold 1 item for 6c%.", helpers.printed(env))
    end)
end)
