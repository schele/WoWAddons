local addonName, ns = ...

-- Vendor deals: auctions whose buyout is less than a merchant pays for the
-- same items, by at least the profit the player sets. Found with the
-- auction house's full scan (C_AuctionHouse.ReplicateItems), which hands
-- over every auction up at once; DealsTab.lua shows them.
--
-- WoW Forever's auction house is the current game's, so the full scan is
-- there. Retail allows it once every 15 minutes and sends nothing back when
-- asked sooner; whether Forever does the same is not confirmed, so instead of
-- a countdown the scan says so when no answer comes.
--
-- The scan can hand over thousands of auctions, so they are read a slice a
-- frame, each item's price is looked up once a scan, and an item the game
-- describes late has only its own auctions read again. Every auction that
-- makes any profit is kept; the least profit is a filter over those, so
-- moving it needs no new scan.

local Deals = {}
ns.Deals = Deals

-- How long to wait for the auction house's answer before saying none came.
Deals.WAIT = 20
-- How often the auction house allows a full scan: once every 15 minutes, as
-- retail's. Asked sooner it sends nothing, and the game keeps the last list.
Deals.LIMIT = 15 * 60
-- Auctions read a frame on a client without the game's millisecond clock.
Deals.BATCH = 200
-- With the clock (debugprofilestop), a frame reads as many as fit in this
-- many milliseconds instead: an auction house can hold hundreds of
-- thousands, and a frame is about 16 milliseconds at 60 a second.
Deals.BUDGET_MS = 8
-- How many to read between looks at the clock.
local CLOCK_EVERY = 50
-- While reading, the deals found so far are shown after the first slice
-- and every this many slices after it: a few times a second, rather than
-- sorting a growing list every frame.
Deals.SHOW_EVERY = 10
-- The least profit the player can pick, in copper: any profit at all, up to
-- a gold.
Deals.STEPS = { 1, 10, 25, 50, 75, 100, 200, 500, 1000, 2500, 5000, 10000 }
local DEFAULT_MIN_PROFIT = 50
-- Items the game describes come in runs; the list is redrawn once a run.
local SETTLE = 0.5

ns.AddDefaults({
    dealsMinProfit = DEFAULT_MIN_PROFIT,
})

local current = { state = "idle", deals = {}, all = {}, auctions = 0, read = 0 }
local listeners = {}
local asked = nil -- the scan last asked for; nil until there has been one
local pass = nil -- the reading of the list the auction house last sent
local settleQueued = false

function Deals.Current()
    return current
end

function Deals.OnChange(fn)
    table.insert(listeners, fn)
end

local function changed()
    for _, fn in ipairs(listeners) do
        ns.Guarded(fn)
    end
end

--- Whether this client has the full scan at all.
function Deals.Available()
    return C_AuctionHouse ~= nil and C_AuctionHouse.ReplicateItems ~= nil
        and C_AuctionHouse.GetReplicateItemInfo ~= nil
end

--- The least a deal must make, in copper.
function Deals.MinProfit()
    local value = ns.db and ns.db.dealsMinProfit
    return type(value) == "number" and value or DEFAULT_MIN_PROFIT
end

--- The step nearest `copper`, as an index into STEPS.
function Deals.StepOf(copper)
    local best, bestGap = 1, math.huge
    for index, step in ipairs(Deals.STEPS) do
        local gap = math.abs(step - copper)
        if gap < bestGap then
            best, bestGap = index, gap
        end
    end
    return best
end

local function byProfit(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    if a.name ~= b.name then return a.name < b.name end
    return a.index < b.index
end

--- The deals to show: every profitable auction found that makes at least
-- the least profit, the biggest first.
local function refilter()
    local least = Deals.MinProfit()
    local deals = {}
    for _, deal in ipairs(current.all) do
        if deal.profit >= least then
            deals[#deals + 1] = deal
        end
    end
    table.sort(deals, byProfit)
    current.deals = deals
end

--- Keep deals making at least `copper`; remembered, and applied at once.
function Deals.SetMinProfit(copper)
    ns.db.dealsMinProfit = math.max(1, math.floor(tonumber(copper) or DEFAULT_MIN_PROFIT))
    refilter()
    changed()
    if ns.SettingsPanel and ns.SettingsPanel.Refresh then
        ns.SettingsPanel.Refresh()
    end
end

local function mine(owner)
    return owner ~= nil and owner == UnitName("player")
end

local function requestItem(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        ns.Guarded(function() C_Item.RequestLoadItemDataByID(itemID) end)
    end
end

--- What a merchant pays for one of `itemID`: looked up once a scan. False
-- while the game has yet to describe the item, which it is then asked to.
local function priceOf(itemID)
    local known = pass.prices[itemID]
    if known ~= nil then
        return known
    end
    local price = ns.Bags.SellPrice(itemID)
    if price == nil then
        pass.prices[itemID] = false
        requestItem(itemID)
    else
        pass.prices[itemID] = price
    end
    return pass.prices[itemID]
end

local function filled(text)
    return type(text) == "string" and text ~= "" and text or nil
end

--- The name an item link shows: "[Polished Zweihander of the Whale]".
local function linkName(link)
    return type(link) == "string" and filled(link:match("|h%[(.-)%]|h")) or nil
end

--- An auction's full name, suffix and all, and its link, as the scan has
-- them now. The scan hands some auctions over before the game has
-- described them in full: a blank name, and maybe no link yet.
local function auctionName(index, name)
    local link = C_AuctionHouse.GetReplicateItemLink and C_AuctionHouse.GetReplicateItemLink(index)
    return filled(name) or linkName(link), link
end

--- A deal's name, for showing it: the full one once the game has it,
-- asked again until then. Meanwhile the item's own (plain) name.
function Deals.NameOf(deal)
    if deal.named then
        return deal.name
    end
    -- Both values: Guarded hands back the first alone.
    local full, link
    pcall(function()
        full, link = auctionName(deal.index, (C_AuctionHouse.GetReplicateItemInfo(deal.index)))
    end)
    if full then
        deal.name, deal.named = full, true
    end
    if link then
        deal.link = link
    end
    return deal.name
end

--- One auction as a deal making any profit, or nil. `index` counts from 0,
-- as the game does. An auction of an item without a price yet waits for it.
local function readAuction(index)
    local name, texture, count, quality, _, _, _, _, _, buyout, _, _, _, owner, _, saleStatus, itemID =
        C_AuctionHouse.GetReplicateItemInfo(index)
    if type(itemID) ~= "number" or type(buyout) ~= "number" or buyout <= 0 then
        return nil
    end
    if (saleStatus or 0) ~= 0 or mine(owner) then
        return nil
    end

    local price = priceOf(itemID)
    if price == false then
        local waiting = pass.waiting[itemID] or {}
        waiting[#waiting + 1] = index
        pass.waiting[itemID] = waiting
        return nil
    end

    count = count or 1
    local value = price * count
    if price <= 0 or value <= buyout then
        return nil
    end
    local full, link = auctionName(index, name)
    return {
        index = index,
        itemID = itemID,
        name = full or filled(ns.ItemName(itemID)) or ("item " .. itemID),
        named = full ~= nil,
        icon = texture or ns.ItemIcon(itemID),
        quality = quality,
        count = count,
        buyout = buyout,
        value = value,
        profit = value - buyout,
        link = link,
    }
end

local function add(index)
    -- One auction the client will not describe costs that auction only.
    local deal = ns.Guarded(function() return readAuction(index) end)
    if deal then
        pass.found[#pass.found + 1] = deal
    end
end

--- Read the next slice of `reading`, and queue the one after for the next
-- frame; done after the last. A newer list sent meanwhile stops this one.
local function readSlice(reading)
    if pass ~= reading then
        return
    end
    local index = reading.next
    if debugprofilestop then
        local started = debugprofilestop()
        while index < reading.total do
            add(index)
            index = index + 1
            if index % CLOCK_EVERY == 0 and debugprofilestop() - started >= Deals.BUDGET_MS then
                break
            end
        end
    else
        local last = math.min(reading.total, index + Deals.BATCH)
        while index < last do
            add(index)
            index = index + 1
        end
    end
    reading.next = index
    current.read = reading.next
    reading.slices = (reading.slices or 0) + 1

    if reading.next < reading.total then
        if reading.slices == 1 or reading.slices % Deals.SHOW_EVERY == 0 then
            -- What has been found so far, sorted in: the list fills as it reads.
            current.all = reading.found
            refilter()
        end
        changed()
        C_Timer.After(0, function() readSlice(reading) end)
        return
    end
    reading.done = true
    current.all = reading.found
    current.state = "done"
    current.stale = reading.stale
    -- A held list is as old as the answer it came in.
    current.scannedAt = reading.stale and ns.db.dealsAnsweredAt or time()
    refilter()
    changed()
end

--- Read `total` auctions from the start, a slice now. `stale` when it is
-- the list the game kept from an earlier scan.
local function startReading(total, stale)
    pass = { total = total, next = 0, found = {}, prices = {}, waiting = {}, stale = stale }
    current.state = "reading"
    current.auctions = total
    current.read = 0
    readSlice(pass)
end

local function heldCount()
    return ns.Guarded(function() return C_AuctionHouse.GetNumReplicateItems() end, 0) or 0
end

--- When the next full scan should be allowed, from when the auction house
-- last answered one; nil when it never has.
function Deals.NextScanAt()
    local answeredAt = ns.db and ns.db.dealsAnsweredAt
    if type(answeredAt) ~= "number" then
        return nil
    end
    return answeredAt + Deals.LIMIT
end

--- No answer in time: read the list the game kept from the last scan, if
-- it kept one; else say none came.
local function noAnswer()
    local held = heldCount()
    if held > 0 then
        startReading(held, true)
        return
    end
    current.state = "nothing"
    changed()
end

--- Ask the auction house for every auction up. False and why when it
-- cannot be asked: the client has no full scan, or the window is closed.
function Deals.Scan()
    if not Deals.Available() then
        return false, "This client cannot scan the whole auction house."
    end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        return false, "Open the auction house first."
    end
    if Deals.Busy() then
        return false, "A scan is already going: Stop it first."
    end

    -- What was shown before, for Stop to go back to while still waiting.
    local scan = {
        before = {
            state = current.state, scannedAt = current.scannedAt, stale = current.stale,
            all = current.all, auctions = current.auctions, read = current.read,
        },
    }
    asked = scan
    current.state = "scanning"
    current.askedAt = time()
    C_AuctionHouse.ReplicateItems()
    changed()

    -- A word each second while it waits, so the wait shows.
    local function tick()
        if asked == scan and current.state == "scanning" then
            changed()
            C_Timer.After(1, tick)
        end
    end
    C_Timer.After(1, tick)

    C_Timer.After(Deals.WAIT, function()
        if asked == scan and current.state == "scanning" then
            noAnswer()
        end
    end)
    return true
end

--- The auction house sent its list: read it from the start, a slice now.
-- Once a scan: the game says the list is ready more than once, and the
-- whole of it is there the first time.
local function answered()
    if not asked or asked.answered then
        return
    end
    asked.answered = true
    ns.db.dealsAnsweredAt = time()
    startReading(heldCount(), false)
end

--- Whether a scan is waiting for the auction house or being read.
function Deals.Busy()
    return current.state == "scanning" or current.state == "reading"
end

--- Stop the scan. While waiting, back to what was shown before, and an
-- answer that comes after is let go. While reading, keep the deals found
-- so far and read no further.
function Deals.Stop()
    if current.state == "scanning" then
        local before = asked and asked.before or {}
        asked = nil
        current.state = before.state or "idle"
        current.scannedAt, current.stale = before.scannedAt, before.stale
        current.all = before.all or {}
        current.auctions, current.read = before.auctions or 0, before.read or 0
        refilter()
        changed()
    elseif current.state == "reading" and pass then
        local reading = pass
        asked, pass = nil, nil
        current.all = reading.found
        current.state = "stopped"
        current.stale = reading.stale
        current.scannedAt = reading.stale and ns.db.dealsAnsweredAt or time()
        refilter()
        changed()
    end
end

--- The game described an item: read just its auctions that were waiting.
local function described(itemID, success)
    local waiting = pass and pass.waiting[itemID]
    if not waiting then
        return
    end
    pass.waiting[itemID] = nil
    if success == false then
        return
    end
    pass.prices[itemID] = nil
    for _, index in ipairs(waiting) do
        add(index)
    end

    if not pass.done or settleQueued then
        return
    end
    settleQueued = true
    C_Timer.After(SETTLE, function()
        settleQueued = false
        refilter()
        changed()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, itemID, success)
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        answered()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        described(itemID, success)
    end
end)
