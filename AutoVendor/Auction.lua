local addonName, ns = ...

-- Posting at the auction house: when you pick an item or click a listing,
-- the game copies that listing's price into the price boxes. This nudges the
-- copy one copper down, so the new auction sorts ahead of the one it was
-- copied from instead of tying with it.

local Auction = {}
ns.Auction = Auction

ns.AddDefaults({
    undercut = true,
})

--- One copper under a competitor's price. A price already at the floor of
-- one copper is matched instead: the game refuses an auction at zero.
function Auction.UndercutPrice(price)
    if type(price) ~= "number" or price <= 1 then
        return price
    end
    return price - 1
end

local function undercutting()
    return ns.db and ns.db.undercut
end

-- Both sell frames fill the price from the sell list's row-selected
-- callback, and that callback captures the handler when the frame first
-- shows. So the handlers are hooked as Blizzard_AuctionHouseUI loads, before
-- the frames can have shown, and the callback captures hook and all.
local function hookSellFrames()
    -- Stackable goods: the row's unit price, into the one price box.
    hooksecurefunc(AuctionHouseFrame.CommoditiesSellFrame, "OnAuctionSelected", function(sellFrame, result)
        if not (undercutting() and result and result.unitPrice) then
            return
        end
        local price = Auction.UndercutPrice(result.unitPrice)
        if price ~= result.unitPrice then
            sellFrame.PriceInput:SetAmount(price)
        end
    end)

    -- Single items: the row's buyout. A row without one changes nothing, so
    -- there is nothing to undercut. The bid box only shows outside the
    -- default buyout-only mode; the game refuses a bid at or over the
    -- buyout, so a colliding bid follows the buyout down.
    hooksecurefunc(AuctionHouseFrame.ItemSellFrame, "OnSearchResultSelected", function(sellFrame, result)
        if not (undercutting() and result and result.buyoutAmount) then
            return
        end
        local price = Auction.UndercutPrice(result.buyoutAmount)
        if price == result.buyoutAmount then
            return
        end
        sellFrame.PriceInput:SetAmount(price)

        local bid = sellFrame.SecondaryPriceInput
        if bid and bid:IsShown() and bid:GetAmount() >= price then
            bid:SetAmount(Auction.UndercutPrice(price))
        end
    end)
end

local hooked = false
local function onAuctionHouseLoaded()
    if hooked or not AuctionHouseFrame then
        return
    end
    hooked = true
    hookSellFrames()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_AuctionHouseUI" then
        onAuctionHouseLoaded()
    end
end)

-- After a /reload at the auctioneer, the client brings the auction house UI
-- back before this file runs, so its load event has already come and gone.
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    onAuctionHouseLoaded()
end

-- The settings page, told of every change however it was made, so a box it
-- shows never disagrees with what a command has just set.
local function changed()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

--- Undercut the listing a price is copied from, or copy it as the game does.
function Auction.SetUndercut(value)
    ns.db.undercut = value and true or false
    changed()
end

ns.RegisterCommand("undercut", "post auctions one copper under the cheapest, on or off", function()
    Auction.SetUndercut(not ns.db.undercut)
    ns.Print("Undercut the cheapest auction: " .. (ns.db.undercut and "on" or "off") .. ".")
end)
