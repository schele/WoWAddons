local addonName, ns = ...

-- What is in the bags, slot by slot: enough to see where the items a take
-- from a mail went, and to find an empty slot. Reading only.

local Bags = {}
ns.Bags = Bags

-- Every bag an item from the mail can land in, and the ones that take any
-- item: the backpack and the four bags beside it.
local function lastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

local function lastGeneralBag()
    return NUM_BAG_SLOTS or 4
end

local function numSlots(bag)
    return ns.Guarded(function()
        local count = C_Container.GetContainerNumSlots(bag)
        return type(count) == "number" and count or 0
    end, 0)
end

--- The item in a slot, { id, count, locked, bound }, or nil for none.
function Bags.Item(bag, slot)
    return ns.Guarded(function()
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) ~= "table" or type(info.itemID) ~= "number" then
            return nil
        end
        return {
            id = info.itemID,
            count = type(info.stackCount) == "number" and info.stackCount or 1,
            locked = info.isLocked == true,
            bound = info.isBound == true,
        }
    end, nil)
end

local function each(fn)
    for bag = 0, lastBag() do
        for slot = 1, numSlots(bag) do
            fn(bag, slot, Bags.Item(bag, slot))
        end
    end
end

--- Every item in the bags, by "bag:slot".
function Bags.Snapshot()
    local items = {}
    each(function(bag, slot, item)
        items[bag .. ":" .. slot] = item
    end)
    return items
end

--- What has come into the bags since `before`, a Snapshot: { bag, slot,
-- id, count } for each slot that now holds more of its item than it did,
-- or an item it did not hold. A take tops up the player's own stacks
-- before it fills an empty slot, so one take can land in several.
function Bags.Arrivals(before)
    local list = {}
    each(function(bag, slot, item)
        if not item then
            return
        end
        local was = before[bag .. ":" .. slot]
        local added = item.count
        if was and was.id == item.id then
            added = item.count - was.count
        end
        if added > 0 then
            list[#list + 1] = { bag = bag, slot = slot, id = item.id, count = added }
        end
    end)
    return list
end

--- An empty slot that takes any item, in the backpack or a plain bag, not
-- a quiver or a soul bag. Nil when there is none.
function Bags.EmptySlot()
    for bag = 0, lastGeneralBag() do
        local general = ns.Guarded(function()
            local _, bagType = C_Container.GetContainerNumFreeSlots(bag)
            return bagType == nil or bagType == 0
        end, false)
        if general then
            for slot = 1, numSlots(bag) do
                if not Bags.Item(bag, slot) then
                    return bag, slot
                end
            end
        end
    end
    return nil
end
