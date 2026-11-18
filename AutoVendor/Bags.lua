local addonName, ns = ...

-- Which bag slots hold junk: grey or on the junk list, worth something to a
-- merchant, not kept and not locked. And which items could go on the junk
-- list. Reading only, so it can be tested without a merchant.

local Bags = {}
ns.Bags = Bags

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

local function lastBag()
    return NUM_BAG_SLOTS or 4
end

local function slotCount(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

--- What a slot holds: { itemID, count, quality, locked, noValue, icon }, or
-- nil.
local function slotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) ~= "table" or type(info.itemID) ~= "number" then
            return nil
        end
        return {
            itemID = info.itemID,
            count = info.stackCount or 1,
            quality = info.quality,
            locked = info.isLocked,
            noValue = info.hasNoValue,
            icon = info.iconFileID,
        }
    end

    if GetContainerItemInfo then
        local icon, count, locked, quality, _, _, _, _, noValue, itemID = GetContainerItemInfo(bag, slot)
        if type(itemID) ~= "number" then
            return nil
        end
        return {
            itemID = itemID,
            count = count or 1,
            quality = quality,
            locked = locked,
            noValue = noValue,
            icon = icon,
        }
    end

    return nil
end

--- What a merchant pays for one, or nil when the client has not described
-- the item yet.
local function sellPrice(itemID)
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getItemInfo then
        return nil
    end
    local price = select(11, getItemInfo(itemID))
    return type(price) == "number" and price or nil
end

--- A slot's junk, { bag, slot, itemID, count, price }, or nil. Junk is grey
-- or on the junk list (`chosen`), and never kept. One guarded read, so a slot
-- the client will not describe costs that slot and no other.
local function readSlot(bag, slot, keep, chosen)
    return ns.Guarded(function()
        local item = slotItem(bag, slot)
        if not item or item.locked or item.noValue or keep[item.itemID] then
            return nil
        end
        if item.quality ~= POOR and not chosen[item.itemID] then
            return nil
        end

        local price = sellPrice(item.itemID)
        if not price or price <= 0 then
            return nil
        end
        return { bag = bag, slot = slot, itemID = item.itemID, count = item.count, price = price }
    end, nil)
end

--- Call `visit(bag, slot)` for every bag slot, in bag order.
local function eachSlot(visit)
    for bag = 0, lastBag() do
        local slots = ns.Guarded(function()
            return slotCount(bag)
        end, 0)
        for slot = 1, slots do
            visit(bag, slot)
        end
    end
end

--- The slots to sell: greys, and whatever is on the junk list (`chosen`),
-- unless kept.
function Bags.Junk(keep, chosen)
    keep, chosen = keep or {}, chosen or {}
    local junk = {}

    eachSlot(function(bag, slot)
        local found = readSlot(bag, slot, keep, chosen)
        if found then
            junk[#junk + 1] = found
        end
    end)

    return junk
end

--- A slot's item if it could go on the junk list, { itemID, name, icon }, or
-- nil: not grey, since greys are sold anyway, a merchant pays for it, the
-- client has described it, and it is on neither list.
local function readCandidate(bag, slot, keep, chosen)
    return ns.Guarded(function()
        local item = slotItem(bag, slot)
        if not item or item.quality == POOR or item.noValue then
            return nil
        end
        if keep[item.itemID] or chosen[item.itemID] then
            return nil
        end

        local price = sellPrice(item.itemID)
        local name = ns.ItemName(item.itemID)
        if not price or price <= 0 or not name then
            return nil
        end
        return { itemID = item.itemID, name = name, icon = item.icon }
    end, nil)
end

--- The items in the bags that could go on the junk list, each once, by
-- name. For the settings page's grid of bag items.
function Bags.Sellable(keep, chosen)
    keep, chosen = keep or {}, chosen or {}
    local items, seen = {}, {}

    eachSlot(function(bag, slot)
        local found = readCandidate(bag, slot, keep, chosen)
        if found and not seen[found.itemID] then
            seen[found.itemID] = true
            items[#items + 1] = found
        end
    end)

    table.sort(items, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.itemID < b.itemID
    end)
    return items
end

--- Where a sale of `itemID` from a slot stands: "gone" once the slot no
-- longer holds it, "busy" while it is locked on its way to the merchant,
-- "there" when it is back in hand because the merchant refused it. The
-- comparison happens inside the guard, and a slot that will not answer
-- reads "there", so a sale is never counted on a guess.
function Bags.SlotState(bag, slot, itemID)
    return ns.Guarded(function()
        local item = slotItem(bag, slot)
        if not item or item.itemID ~= itemID then
            return "gone"
        end
        if item.locked then
            return "busy"
        end
        return "there"
    end, "there")
end
