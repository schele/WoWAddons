local stub = require("wow_stub")

local M = {}

M.FILES = {
    "AutoVendor.lua",
    "Bags.lua",
    "Keep.lua",
    "Junk.lua",
    "Vendor.lua",
    "Auction.lua",
    "Deals.lua",
    "DealsTab.lua",
    "Incoming.lua",
    "Picker.lua",
    "Settings.lua",
}

--- Load the addon's files into a stubbed client, in .toc order, each chunk
-- receiving (addonName, privateTable). `saved` is AutoVendorDB as the
-- client would load it.
function M.loadAddon(saved)
    local env = stub.newEnv(saved)
    local ns = {}
    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("AutoVendor", ns)
    end
    return ns, env
end

M.legacy = stub.useLegacyAPI

--- Fire an event on every frame registered for it.
function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do
        frames[index] = frame
    end
    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then
            frame:Fire(event, ...)
        end
    end
end

function M.login(env)
    M.fire(env, "ADDON_LOADED", "AutoVendor")
    M.fire(env, "PLAYER_LOGIN")
end

--- A /reload: the same saved variables, a fresh addon, logged in.
function M.reload(env)
    local ns, fresh = M.loadAddon(env.AutoVendorDB)
    M.login(fresh)
    return ns, fresh
end

function M.put(env, bag, slot, itemID, count, locked)
    env.__slots[bag .. ":" .. slot] = { itemID = itemID, count = count or 1, locked = locked }
end

--- Visit the auctioneer: the client loads Blizzard_AuctionHouseUI on demand,
-- and the sell frames capture their callbacks as they first show.
function M.openAuctionHouse(env)
    local frame = stub.buildAuctionHouse(env)
    M.fire(env, "ADDON_LOADED", "Blizzard_AuctionHouseUI")
    frame.CommoditiesSellFrame:Show()
    frame.ItemSellFrame:Show()
    return frame
end

--- An auction up at the auction house: `count` of `itemID` for a buyout of
-- `buyout` copper. `extra` can set bid, owner or saleStatus.
function M.auction(env, itemID, count, buyout, extra)
    local auction = { itemID = itemID, count = count, buyout = buyout }
    for key, value in pairs(extra or {}) do
        auction[key] = value
    end
    table.insert(env.__auctions, auction)
    return auction
end

--- An auction of your own, as the Auctions tab lists it: `fields` of the
-- game's OwnedAuctionInfo (status 1 for sold, buyoutAmount, timeLeftSeconds).
function M.ownAuction(env, fields)
    table.insert(env.__owned, fields)
    return fields
end

--- Logged in and standing at the auctioneer with the window open on the
-- Buy tab. `setup(env)` runs first.
function M.atAuctionHouse(setup)
    local ns, env = M.loadAddon()
    if setup then setup(env) end
    M.login(env)
    local frame = M.openAuctionHouse(env)
    frame:Show()
    return ns, env, frame
end

--- The auction house answers a full scan, and every slice of it is read.
function M.scanAnswered(env)
    M.fire(env, "REPLICATE_ITEM_LIST_UPDATE")
    env.__runAllTimers()
end

--- Click a row in a sell frame's list, as the game's selection callback
-- delivers it.
function M.selectRow(sellFrame, rowData)
    sellFrame.selectionCallback(rowData)
end

function M.openMerchant(env)
    env.__merchantOpen = true
    M.fire(env, "MERCHANT_SHOW")
end

function M.closeMerchant(env)
    env.__merchantOpen = false
    M.fire(env, "MERCHANT_CLOSED")
end

function M.command(env, text)
    env.SlashCmdList.AUTOVENDOR(text or "")
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
