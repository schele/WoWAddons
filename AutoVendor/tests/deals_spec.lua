local helpers = require("helpers")

local BOOTS, BRACERS, LINEN, HEARTHSTONE, JERKY = 9798, 6070, 2589, 6948, 117

--- At the auctioneer, the auctions in `auctions` up, scanned and answered.
local function scanned(auctions, setup)
    local ns, env = helpers.atAuctionHouse(function(env)
        for _, auction in ipairs(auctions) do
            helpers.auction(env, auction[1], auction[2], auction[3], auction[4])
        end
        if setup then setup(env) end
    end)
    ns.Deals.Scan()
    helpers.scanAnswered(env)
    return ns, env
end

local function names(deals)
    local out = {}
    for index, deal in ipairs(deals) do
        out[index] = deal.name
    end
    return table.concat(out, ", ")
end

describe("finding deals", function()
    it("finds an auction a merchant would pay more for than its buyout", function()
        -- A merchant pays 8s 23c for the boots.
        local ns = scanned({ { BOOTS, 1, 700 }, { BRACERS, 1, 100 } })

        local deals = ns.Deals.Current().deals
        assertEqual(1, #deals, "the bracers cost more than a merchant pays")
        local deal = deals[1]
        assertEqual("Ivycloth Boots of Arcane Protection", deal.name)
        assertEqual(700, deal.buyout)
        assertEqual(823, deal.value)
        assertEqual(123, deal.profit)
    end)

    it("passes over one that makes less than 50 copper", function()
        -- The boots in the picture: 8s 19c up, a merchant pays 8s 23c.
        local ns = scanned({ { BOOTS, 1, 819 }, { BOOTS, 1, 774 } })

        assertEqual(0, #ns.Deals.Current().deals, "4c and 49c are not worth the trip")
    end)

    it("keeps one that makes 50 copper exactly", function()
        local ns = scanned({ { BOOTS, 1, 773 } })

        assertEqual(1, #ns.Deals.Current().deals)
        assertEqual(50, ns.Deals.Current().deals[1].profit)
    end)

    it("prices the whole stack", function()
        local ns = scanned({ { LINEN, 20, 200 } })

        local deal = ns.Deals.Current().deals[1]
        assertEqual(20, deal.count)
        assertEqual(260, deal.value)
        assertEqual(60, deal.profit)
    end)

    it("passes over one that only costs what a merchant pays", function()
        local ns = scanned({ { BOOTS, 1, 823 } })

        assertEqual(0, #ns.Deals.Current().deals)
    end)

    it("passes over an auction with no buyout", function()
        local ns = scanned({ { BOOTS, 1, 0, { bid = 100 } } })

        assertEqual(0, #ns.Deals.Current().deals)
    end)

    it("passes over your own auctions", function()
        local ns = scanned({ { BOOTS, 1, 500, { owner = "Skyler" } } })

        assertEqual(0, #ns.Deals.Current().deals)
    end)

    it("passes over one already sold", function()
        local ns = scanned({ { BOOTS, 1, 500, { saleStatus = 1 } } })

        assertEqual(0, #ns.Deals.Current().deals)
    end)

    it("passes over items no merchant buys", function()
        local ns = scanned({ { HEARTHSTONE, 1, 0 }, { HEARTHSTONE, 1, 1 } })

        assertEqual(0, #ns.Deals.Current().deals)
    end)

    it("puts the biggest profit first", function()
        -- 57c, 3s 23c and 60c.
        local ns = scanned({ { BRACERS, 1, 20 }, { BOOTS, 1, 500 }, { LINEN, 20, 200 } })

        assertEqual("Ivycloth Boots of Arcane Protection, Linen Cloth, Wolfskin Bracers",
            names(ns.Deals.Current().deals))
    end)

    it("counts every auction it read", function()
        local ns = scanned({ { BOOTS, 1, 500 }, { BRACERS, 1, 100 }, { LINEN, 20, 900 } })

        assertEqual(3, ns.Deals.Current().auctions)
    end)

    it("keeps each deal's link for its tooltip", function()
        local ns, env = scanned({ { BOOTS, 1, 500 } })

        assertEqual(env.__link(BOOTS), ns.Deals.Current().deals[1].link)
    end)
end)

describe("reading the scan", function()
    --- At the auctioneer with `count` auctions of linen up, asked to scan.
    local function manyUp(count)
        return helpers.atAuctionHouse(function(env)
            for _ = 1, count do
                helpers.auction(env, LINEN, 20, 200)
            end
        end)
    end

    it("reads a slice of auctions at a time, so the game keeps drawing", function()
        local ns, env = manyUp(450)
        ns.Deals.Scan()

        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")
        local current = ns.Deals.Current()
        assertEqual("reading", current.state)
        assertEqual(ns.Deals.BATCH, current.read, "one slice in the frame the answer came")
        assertEqual(450, current.auctions)

        env.__runTimers()
        assertEqual(2 * ns.Deals.BATCH, current.read, "and one more each frame after")

        env.__runAllTimers()
        assertEqual("done", current.state)
        assertEqual(450, current.read)
        assertEqual(450, #current.deals)
    end)

    it("shows the deals found so far while it reads, the biggest profit first", function()
        local ns, env = helpers.atAuctionHouse(function(env)
            for _ = 1, 300 do helpers.auction(env, LINEN, 20, 200) end -- 60c each
            helpers.auction(env, BOOTS, 1, 100) -- 7s 23c, the 301st
            for _ = 1, 149 do helpers.auction(env, LINEN, 20, 200) end
        end)
        ns.Deals.SHOW_EVERY = 2
        ns.Deals.Scan()

        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")
        local current = ns.Deals.Current()
        assertEqual("reading", current.state)
        assertEqual(ns.Deals.BATCH, #current.deals, "the first slice's at once")

        env.__runTimers() -- the second slice, with the boots in it
        assertEqual("reading", current.state)
        assertEqual("Ivycloth Boots of Arcane Protection", current.deals[1].name, "sorted in as found")
        assertEqual(2 * ns.Deals.BATCH, #current.deals)

        env.__runAllTimers()
        assertEqual(450, #current.deals)
    end)

    it("does not sort the list again every frame while it reads", function()
        local ns, env = helpers.atAuctionHouse(function(env)
            for _ = 1, 450 do helpers.auction(env, LINEN, 20, 200) end
        end)
        ns.Deals.SHOW_EVERY = 3
        ns.Deals.Scan()
        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")

        env.__runTimers() -- the second slice: not shown yet

        assertEqual(ns.Deals.BATCH, #ns.Deals.Current().deals)
    end)

    -- With the game's millisecond clock (debugprofilestop), a frame reads
    -- as many as fit in its share of time, not a fixed number: an auction
    -- house can hold hundreds of thousands.
    it("reads as many a frame as fit in its time, by the game's clock", function()
        local ns, env = manyUp(450)
        local now = 0
        env.debugprofilestop = function() return now end
        ns.Deals.Scan()

        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")

        assertEqual("done", ns.Deals.Current().state, "a fast machine reads them all at once")
    end)

    it("leaves the rest for the next frame once its time is up", function()
        local ns, env = manyUp(450)
        local now = 0
        env.debugprofilestop = function()
            now = now + 1
            return now
        end
        ns.Deals.Scan()

        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")

        local read = ns.Deals.Current().read
        assertTrue(read > 0 and read < 450, "partway: " .. read)
        env.__runAllTimers()
        assertEqual(450, ns.Deals.Current().read)
    end)

    it("looks each item's price up once a scan, however many auctions it has", function()
        local ns, env = manyUp(300)
        ns.Deals.Scan()

        helpers.scanAnswered(env)

        assertEqual(1, env.__itemInfoCalls[LINEN])
    end)

    it("adds an item's auctions once the game describes it, without reading the rest again", function()
        local ns, env = helpers.atAuctionHouse(function(env)
            env.__uncached[BOOTS] = true
            for _ = 1, 100 do helpers.auction(env, BRACERS, 1, 100) end
            helpers.auction(env, BOOTS, 1, 500)
            helpers.auction(env, BOOTS, 1, 600)
        end)
        ns.Deals.Scan()
        helpers.scanAnswered(env)
        assertEqual(0, #ns.Deals.Current().deals, "no price for the boots yet")
        local readBefore = env.__replicateReads

        env.__uncached[BOOTS] = nil
        helpers.fire(env, "GET_ITEM_INFO_RECEIVED", BOOTS, true)
        env.__runAllTimers()

        assertEqual(2, #ns.Deals.Current().deals)
        assertEqual(2, env.__replicateReads - readBefore, "the two boots, not all 102")
    end)

    -- The game says the list is ready more than once for one scan. The whole
    -- list is there the first time, so going back to the start on each
    -- (reading up to thousands, then from nothing again) only costs time.
    it("reads the list once a scan, however often the game says it is ready", function()
        local ns, env = manyUp(450)
        ns.Deals.Scan()
        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")
        assertEqual(ns.Deals.BATCH, ns.Deals.Current().read)

        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")
        assertEqual(ns.Deals.BATCH, ns.Deals.Current().read, "not back to the start")
        env.__runAllTimers()
        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")

        assertEqual("done", ns.Deals.Current().state)
        assertEqual(450, #ns.Deals.Current().deals, "each counted once")
        assertEqual(450, env.__replicateReads, "each read once")
    end)
end)

describe("stopping", function()
    local function manyUp(count)
        return helpers.atAuctionHouse(function(env)
            for _ = 1, count do
                helpers.auction(env, LINEN, 20, 200)
            end
        end)
    end

    it("stops reading, and keeps the deals found so far", function()
        local ns, env = manyUp(450)
        ns.Deals.Scan()
        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")

        ns.Deals.Stop()
        env.__runAllTimers()

        local current = ns.Deals.Current()
        assertEqual("stopped", current.state)
        assertEqual(ns.Deals.BATCH, current.read, "read no further")
        assertEqual(ns.Deals.BATCH, #current.deals)
    end)

    it("stops waiting, and takes no answer that comes after", function()
        local ns, env = manyUp(10)
        ns.Deals.Scan()

        ns.Deals.Stop()
        helpers.scanAnswered(env)

        assertEqual("idle", ns.Deals.Current().state)
        assertEqual(0, env.__replicateReads)
    end)

    it("stops waiting, and goes back to the deals from before", function()
        local ns, env = scanned({ { BOOTS, 1, 700 } })
        local scannedAt = ns.Deals.Current().scannedAt
        env.__clock = env.__clock + 60
        ns.Deals.Scan()

        ns.Deals.Stop()

        local current = ns.Deals.Current()
        assertEqual("done", current.state)
        assertEqual(1, #current.deals)
        assertEqual(scannedAt, current.scannedAt)
    end)

    it("knows when there is something to stop", function()
        local ns, env = manyUp(450)
        assertFalse(ns.Deals.Busy())

        ns.Deals.Scan()
        assertTrue(ns.Deals.Busy(), "waiting")
        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")
        assertTrue(ns.Deals.Busy(), "reading")
        env.__runAllTimers()
        assertFalse(ns.Deals.Busy(), "done")
    end)
end)

describe("when no new list comes", function()
    -- Retail's auction house allows one full scan every 15 minutes and
    -- sends nothing when asked sooner. The game keeps the last list it sent.

    it("tells whoever shows the deals each second while it waits", function()
        local ns, env = helpers.atAuctionHouse()
        local heard = 0
        ns.Deals.Scan()
        ns.Deals.OnChange(function() heard = heard + 1 end)

        env.__runTimersUpTo(1)
        env.__runTimersUpTo(1)

        assertEqual("scanning", ns.Deals.Current().state)
        assertEqual(2, heard)
    end)

    it("remembers when the auction house last answered", function()
        local ns, env = scanned({ { BOOTS, 1, 700 } })

        assertEqual(env.__clock, ns.db.dealsAnsweredAt)
    end)

    it("reads the list the game still holds from the last scan", function()
        local ns, env = scanned({ { BOOTS, 1, 700 } })
        local answeredAt = env.__clock
        env.__clock = env.__clock + 6 * 60

        ns.Deals.Scan()
        env.__runAllTimers() -- no answer comes

        local current = ns.Deals.Current()
        assertEqual("done", current.state)
        assertTrue(current.stale, "an earlier list")
        assertEqual(answeredAt, current.scannedAt, "dated when it came")
        assertEqual(1, #current.deals)
    end)

    it("says when the next full scan should be allowed", function()
        local ns, env = scanned({ { BOOTS, 1, 700 } })

        assertEqual(env.__clock + 15 * 60, ns.Deals.NextScanAt())
    end)

    it("takes a new list after all, should one come late", function()
        local ns, env = scanned({ { BOOTS, 1, 700 } })
        ns.Deals.Scan()
        env.__runAllTimers()
        env.__clock = env.__clock + 30

        helpers.scanAnswered(env)

        assertFalse(ns.Deals.Current().stale)
        assertEqual(env.__clock, ns.Deals.Current().scannedAt)
    end)
end)

describe("the least profit", function()
    it("is 50 copper to begin with", function()
        local ns = helpers.atAuctionHouse()

        assertEqual(50, ns.Deals.MinProfit())
    end)

    it("keeps only deals making at least what you set, at once", function()
        -- The boots make 1s 23c, the linen 60c.
        local ns, env = scanned({ { BOOTS, 1, 700 }, { LINEN, 20, 200 } })
        local reads = env.__replicateReads

        ns.Deals.SetMinProfit(100)
        assertEqual("Ivycloth Boots of Arcane Protection", names(ns.Deals.Current().deals))

        ns.Deals.SetMinProfit(1)
        assertEqual("Ivycloth Boots of Arcane Protection, Linen Cloth", names(ns.Deals.Current().deals))
        assertEqual(reads, env.__replicateReads, "without scanning or reading again")
    end)

    it("brings back small deals when lowered below 50 copper", function()
        local ns = scanned({ { BOOTS, 1, 819 } })
        assertEqual(0, #ns.Deals.Current().deals)

        ns.Deals.SetMinProfit(1)

        assertEqual(4, ns.Deals.Current().deals[1].profit)
    end)

    it("is remembered", function()
        local ns, env = helpers.atAuctionHouse()
        ns.Deals.SetMinProfit(500)

        local reloaded = helpers.reload(env)

        assertEqual(500, reloaded.Deals.MinProfit())
    end)

    it("comes in steps, from any profit up to a gold", function()
        local ns = helpers.loadAddon()

        local steps = ns.Deals.STEPS
        assertEqual(1, steps[1])
        assertEqual(10000, steps[#steps])
        assertEqual(4, ns.Deals.StepOf(50), "50c is a step of its own")
        assertEqual(4, ns.Deals.StepOf(60), "a value between steps takes the nearest")
    end)
end)

describe("a deal's name", function()
    local ZWEIHANDER = 15251

    it("is the auction's own, suffix and all", function()
        local ns = scanned({ { ZWEIHANDER, 1, 3000, { fullName = "Polished Zweihander of the Whale" } } })

        assertEqual("Polished Zweihander of the Whale", ns.Deals.Current().deals[1].name)
    end)

    -- The scan can hand over an auction before the game has described it in
    -- full: a blank name, though its item and sell price are known.
    it("comes from its link when the scan leaves the name blank", function()
        local ns = scanned({ { ZWEIHANDER, 1, 3000, { unnamed = true, fullName = "Polished Zweihander of the Whale" } } })

        assertEqual("Polished Zweihander of the Whale", ns.Deals.Current().deals[1].name)
    end)

    it("is the item's own name when the auction has no link yet either", function()
        local ns = scanned({ { ZWEIHANDER, 1, 3000, { unnamed = true, nolink = true } } })

        assertEqual("Polished Zweihander", ns.Deals.Current().deals[1].name)
    end)

    it("becomes the full one once the game has it", function()
        local ns, env = scanned({ { ZWEIHANDER, 1, 3000, { unnamed = true, nolink = true, fullName = "Polished Zweihander of the Whale" } } })
        local deal = ns.Deals.Current().deals[1]

        env.__auctions[1].unnamed, env.__auctions[1].nolink = nil, nil

        assertEqual("Polished Zweihander of the Whale", ns.Deals.NameOf(deal))
        assertEqual(env.__link(ZWEIHANDER, "Polished Zweihander of the Whale"), deal.link, "and its link")
    end)
end)

describe("an item the game has not described yet", function()
    it("is asked for, and counted once the game describes it", function()
        local ns, env = scanned({ { BOOTS, 1, 500 } }, function(env) env.__uncached[BOOTS] = true end)
        assertEqual(0, #ns.Deals.Current().deals, "no price yet")
        assertTrue(env.__requested[BOOTS], "asked for")

        env.__uncached[BOOTS] = nil
        helpers.fire(env, "GET_ITEM_INFO_RECEIVED", BOOTS, true)
        env.__runTimers()

        assertEqual(1, #ns.Deals.Current().deals)
        assertEqual("Ivycloth Boots of Arcane Protection", ns.Deals.Current().deals[1].name)
    end)
end)

describe("scanning", function()
    it("asks the auction house for every auction", function()
        local ns, env = helpers.atAuctionHouse()

        assertTrue(ns.Deals.Scan())

        assertEqual(1, env.__replicates)
        assertEqual("scanning", ns.Deals.Current().state)
    end)

    it("is done when the answer comes, and says when", function()
        local ns, env = scanned({ { BOOTS, 1, 500 } })

        local current = ns.Deals.Current()
        assertEqual("done", current.state)
        assertEqual(env.__clock, current.scannedAt)
    end)

    it("says when the auction house sends nothing back", function()
        local ns, env = helpers.atAuctionHouse()
        ns.Deals.Scan()

        env.__runTimers() -- the wait runs out with no answer

        assertEqual("nothing", ns.Deals.Current().state)
    end)

    it("ignores an answer it did not ask for", function()
        local ns, env = helpers.atAuctionHouse(function(env) helpers.auction(env, BOOTS, 1, 500) end)

        helpers.scanAnswered(env)

        assertNil(ns.Deals.Current().scannedAt)
        assertEqual(0, #ns.Deals.Current().deals)
    end)

    it("needs the auction house open", function()
        local ns, env = helpers.atAuctionHouse()
        env.AuctionHouseFrame:Hide()

        local ok, why = ns.Deals.Scan()

        assertFalse(ok)
        assertEqual("Open the auction house first.", why)
        assertEqual(0, env.__replicates)
    end)

    it("tells whoever shows the deals", function()
        local ns, env = helpers.atAuctionHouse(function(env) helpers.auction(env, BOOTS, 1, 500) end)
        local heard = 0
        ns.Deals.OnChange(function() heard = heard + 1 end)

        ns.Deals.Scan()
        helpers.scanAnswered(env)

        assertTrue(heard >= 2, "on starting and on the answer")
    end)
end)
