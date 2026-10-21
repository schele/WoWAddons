local stub = require("wow_stub")

local M = {}

M.FILES = {
    "AutoVendor.lua",
    "Bags.lua",
    "Keep.lua",
    "Vendor.lua",
    "Auction.lua",
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
