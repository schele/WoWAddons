local addonName, ns = ...

-- A merchant visit: the junk sold one item at a time, then the repair, then
-- one line saying what happened.

local Vendor = {}
ns.Vendor = Vendor

-- Between sales. A server sent them faster refuses some ("That object is
-- busy") and leaves greys behind.
Vendor.PAUSE = 0.2

-- A sale is only asked for; the slot empties when the server answers. It may
-- wait this many pauses (about a second) before it is given up uncounted.
Vendor.MAX_WAITS = 5

-- Both halves of a visit, each with its own switch. Both on is how
-- AutoVendor has always behaved.
ns.AddDefaults({
    sell = true,
    repair = true,
})

-- The visit under way, or nil. Each step is handed the visit it belongs to,
-- so one queued before a close does nothing in the visit after it.
local visit

local function sell(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
    elseif UseContainerItem then
        UseContainerItem(bag, slot)
    end
end

-- A slot and what was in it: tried once per visit, so a sale the merchant
-- refused is not retried forever, while loot landing in a sold slot is new.
local function tried(entry)
    return entry.bag .. ":" .. entry.slot .. ":" .. entry.itemID
end

--- Settle the sale in flight: count it once its slot has emptied, drop it
-- if the merchant handed it back or the server never answered. False while
-- it is still on its way, so nothing new is sold and the repair waits for
-- its gold.
local function settle(current)
    local last = current.pending
    if not last then
        return true
    end

    local state = ns.Bags.SlotState(last.bag, last.slot, last.itemID)
    if state == "busy" and last.waits < Vendor.MAX_WAITS then
        last.waits = last.waits + 1
        return false
    end

    current.pending = nil
    if state == "gone" then
        current.items = current.items + last.count
        current.copper = current.copper + last.price * last.count
    end
    return true
end

local function nextJunk(current)
    if not ns.db.sell then
        return nil
    end
    for _, entry in ipairs(ns.Bags.Junk(ns.Keep.All())) do
        if not current.tried[tried(entry)] then
            return entry
        end
    end
    return nil
end

--- Repair if this merchant can and something needs it. The words for what
-- happened, or nil when nothing did. Turned off, it does not even look, so
-- the line never mentions a repair the player asked not to have.
local function repair()
    if not ns.db.repair then
        return nil
    end

    local canRepair = ns.Guarded(function()
        return CanMerchantRepair() and true or false
    end, false)
    if not canRepair then
        return nil
    end

    local cost = ns.Guarded(function()
        local amount, needed = GetRepairAllCost()
        if needed and type(amount) == "number" and amount > 0 then
            return amount
        end
        return 0
    end, 0)
    if cost == 0 then
        return nil
    end

    if GetMoney() < cost then
        return string.format("Not enough gold to repair (costs %s).", ns.Money(cost))
    end

    RepairAllItems()
    return string.format("Repaired for %s.", ns.Money(cost))
end

local function report(current, repaired)
    local parts = {}
    if current.items > 0 then
        parts[#parts + 1] = string.format("Sold %d %s for %s.",
            current.items, current.items == 1 and "item" or "items", ns.Money(current.copper))
    end
    if repaired then
        parts[#parts + 1] = repaired
    end
    if #parts > 0 then
        ns.Print(table.concat(parts, " "))
    end
end

--- End the visit. At the merchant it repairs first; after a close there is
-- nobody to repair at.
local function finish(current, atMerchant)
    settle(current)
    local repaired = atMerchant and repair() or nil
    report(current, repaired)
    visit = nil
end

local function step(current)
    if visit ~= current then
        return
    end

    local function again()
        C_Timer.After(Vendor.PAUSE, function()
            step(current)
        end)
    end

    if not settle(current) then
        again()
        return
    end

    local entry = nextJunk(current)
    if not entry then
        finish(current, true)
        return
    end

    current.tried[tried(entry)] = true
    entry.waits = 0
    current.pending = entry
    sell(entry.bag, entry.slot)
    again()
end

function Vendor.Open()
    -- Some clients say a merchant opened more than once per visit.
    if visit then
        return
    end
    visit = { items = 0, copper = 0, tried = {} }
    step(visit)
end

function Vendor.Close()
    if visit then
        finish(visit, false)
    end
end

-- The settings page, told of every change however it was made, so a box it
-- shows never disagrees with what a command has just set.
local function changed()
    if ns.SettingsPanel then
        ns.SettingsPanel.Refresh()
    end
end

--- Sell grey items at a merchant, or leave them be. A visit under way
-- notices at its next step.
function Vendor.SetSell(value)
    ns.db.sell = value and true or false
    changed()
end

--- Repair at a merchant that can, or leave the gear as it is.
function Vendor.SetRepair(value)
    ns.db.repair = value and true or false
    changed()
end

local function onOff(value)
    return value and "on" or "off"
end

ns.RegisterCommand("sell", "turn selling grey items on or off", function()
    Vendor.SetSell(not ns.db.sell)
    ns.Print("Sell grey items: " .. onOff(ns.db.sell) .. ".")
end)

ns.RegisterCommand("repair", "turn repairing at merchants on or off", function()
    Vendor.SetRepair(not ns.db.repair)
    ns.Print("Repair at merchants: " .. onOff(ns.db.repair) .. ".")
end)

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        Vendor.Open()
    else
        Vendor.Close()
    end
end)
