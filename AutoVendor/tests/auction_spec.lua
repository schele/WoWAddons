local helpers = require("helpers")

local function atAuctioneer()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    local ah = helpers.openAuctionHouse(env)
    return ns, env, ah
end

describe("UndercutPrice", function()
    it("asks one copper under the competitor", function()
        local ns = helpers.loadAddon()
        assertEqual(4499, ns.Auction.UndercutPrice(4500))
    end)

    it("stays at the floor of one copper instead of asking zero", function()
        local ns = helpers.loadAddon()
        assertEqual(1, ns.Auction.UndercutPrice(1))
    end)

    it("leaves a missing price alone", function()
        local ns = helpers.loadAddon()
        assertNil(ns.Auction.UndercutPrice(nil))
    end)
end)

describe("posting stackable goods", function()
    it("fills the price one copper under the listing the game picked", function()
        local _, _, ah = atAuctioneer()
        helpers.selectRow(ah.CommoditiesSellFrame, { unitPrice = 4500 })
        assertEqual(4499, ah.CommoditiesSellFrame.PriceInput:GetAmount())
    end)

    it("matches a listing already at one copper", function()
        local _, _, ah = atAuctioneer()
        helpers.selectRow(ah.CommoditiesSellFrame, { unitPrice = 1 })
        assertEqual(1, ah.CommoditiesSellFrame.PriceInput:GetAmount())
    end)

    it("leaves the price be when the selection goes away", function()
        local _, _, ah = atAuctioneer()
        helpers.selectRow(ah.CommoditiesSellFrame, { unitPrice = 4500 })
        helpers.selectRow(ah.CommoditiesSellFrame, nil)
        assertEqual(4499, ah.CommoditiesSellFrame.PriceInput:GetAmount())
    end)

    it("copies the price untouched when turned off", function()
        local _, env, ah = atAuctioneer()
        helpers.command(env, "undercut")
        helpers.selectRow(ah.CommoditiesSellFrame, { unitPrice = 4500 })
        assertEqual(4500, ah.CommoditiesSellFrame.PriceInput:GetAmount())
    end)
end)

describe("posting single items", function()
    it("fills the buyout one copper under the listing the game picked", function()
        local _, _, ah = atAuctioneer()
        helpers.selectRow(ah.ItemSellFrame, { buyoutAmount = 100000 })
        assertEqual(99999, ah.ItemSellFrame.PriceInput:GetAmount())
    end)

    it("leaves a bid-only listing alone", function()
        local _, _, ah = atAuctioneer()
        helpers.selectRow(ah.ItemSellFrame, { bidAmount = 5000 })
        assertEqual(0, ah.ItemSellFrame.PriceInput:GetAmount())
    end)

    it("pulls the bid under the new buyout when they would collide", function()
        local _, _, ah = atAuctioneer()
        ah.ItemSellFrame.SecondaryPriceInput.shown = true
        helpers.selectRow(ah.ItemSellFrame, { bidAmount = 100000, buyoutAmount = 100000 })
        assertEqual(99999, ah.ItemSellFrame.PriceInput:GetAmount())
        assertEqual(99998, ah.ItemSellFrame.SecondaryPriceInput:GetAmount())
    end)

    it("leaves a lower bid where the listing had it", function()
        local _, _, ah = atAuctioneer()
        ah.ItemSellFrame.SecondaryPriceInput.shown = true
        helpers.selectRow(ah.ItemSellFrame, { bidAmount = 90000, buyoutAmount = 100000 })
        assertEqual(99999, ah.ItemSellFrame.PriceInput:GetAmount())
        assertEqual(90000, ah.ItemSellFrame.SecondaryPriceInput:GetAmount())
    end)
end)

describe("the undercut switch", function()
    it("is on from the start", function()
        local ns, env = helpers.loadAddon()
        helpers.login(env)
        assertTrue(ns.db.undercut)
    end)

    it("flips with /av undercut, and says so", function()
        local ns, env = helpers.loadAddon()
        helpers.login(env)
        helpers.command(env, "undercut")
        assertFalse(ns.db.undercut)
        assertMatch("off", helpers.printed(env))
        helpers.command(env, "undercut")
        assertTrue(ns.db.undercut)
    end)

    it("is in /av's help", function()
        local _, env = helpers.loadAddon()
        helpers.login(env)
        helpers.command(env, "help")
        assertMatch("/av undercut", helpers.printed(env))
    end)

    it("keeps its state over a reload", function()
        local _, env = helpers.loadAddon()
        helpers.login(env)
        helpers.command(env, "undercut")
        local ns = helpers.reload(env)
        assertFalse(ns.db.undercut)
    end)
end)

describe("hooking the auction house", function()
    -- After a /reload at the auctioneer, Blizzard_AuctionHouseUI is back
    -- before this addon runs, so its load event has already come and gone.
    it("still undercuts when the auction house UI loaded first", function()
        local stub = require("wow_stub")
        local env = stub.newEnv()
        local ah = stub.buildAuctionHouse(env)

        local ns = {}
        for _, path in ipairs(helpers.FILES) do
            local chunk = assert(loadfile(path, "t", env))
            chunk("AutoVendor", ns)
        end
        helpers.login(env)

        ah.CommoditiesSellFrame:Show()
        helpers.selectRow(ah.CommoditiesSellFrame, { unitPrice = 4500 })
        assertEqual(4499, ah.CommoditiesSellFrame.PriceInput:GetAmount())
    end)

    it("does nothing on a client without the auction house UI", function()
        local _, env = helpers.loadAddon()
        helpers.login(env)
        helpers.fire(env, "ADDON_LOADED", "Blizzard_AuctionHouseUI")
        -- No AuctionHouseFrame was built: loading must not have raised.
        assertNil(env.AuctionHouseFrame)
    end)
end)
