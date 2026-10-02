local addonName, ns = ...

-- Which bag slots hold junk: grey, worth something to a merchant, not kept
-- and not locked. Reading only, so it can be tested without a merchant.

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

--- What a slot holds: { itemID, count, quality, locked, noValue }, or nil.
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
        }
    end

    if GetContainerItemInfo then
        local _, count, locked, quality, _, _, _, _, noValue, itemID = GetContainerItemInfo(bag, slot)
        if type(itemID) ~= "number" then
            return nil
        end
        return { itemID = itemID, count = count or 1, quality = quality, locked = locked, noValue = noValue }
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

--- A slot's junk, { bag, slot, itemID, count, price }, or nil. One guarded
-- read, so a slot the client will not describe costs that slot and no other.
local function readSlot(bag, slot, keep)
    return ns.Guarded(function()
        local item = slotItem(bag, slot)
        if not item or item.quality ~= POOR or item.locked or item.noValue or keep[item.itemID] then
            return nil
        end

        local price = sellPrice(item.itemID)
        if not price or price <= 0 then
            return nil
        end
        return { bag = bag, slot = slot, itemID = item.itemID, count = item.count, price = price }
    end, nil)
end

function Bags.Junk(keep)
    keep = keep or {}
    local junk = {}

    for bag = 0, lastBag() do
        local slots = ns.Guarded(function()
            return slotCount(bag)
        end, 0)
        for slot = 1, slots do
            local found = readSlot(bag, slot, keep)
            if found then
                junk[#junk + 1] = found
            end
        end
    end

    return junk
end

--- The item ID in a slot, or nil when it is empty: how a sale is seen to
-- have gone through.
function Bags.ItemAt(bag, slot)
    return ns.Guarded(function()
        local item = slotItem(bag, slot)
        return item and item.itemID or nil
    end, nil)
end
