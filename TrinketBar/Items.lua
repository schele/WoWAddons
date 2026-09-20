local addonName, ns = ...

-- What this client knows about items: what is in the bags, what is worn, and
-- which of it goes in a trinket slot. Everything here is a lookup against the
-- client's own APIs -- no frame, no layout -- which is what lets the answers
-- be tested without a client.

local Items = {}
ns.Items = Items

-- The two trinket slots. Named constants where the client has them, the
-- numbers otherwise: they have been 13 and 14 since the game shipped, but a
-- constant that exists is one fewer thing to be wrong about.
Items.TRINKET_SLOTS = {
    INVSLOT_TRINKET1 or 13,
    INVSLOT_TRINKET2 or 14,
}

-- What a trinket's equip location reads as. Every other slot in the game
-- answers with something else, which is the whole filter.
local TRINKET_LOCATION = "INVTYPE_TRINKET"

-- Said once per session, not once per bag change. Carried() runs on every
-- BAG_UPDATE_DELAYED, and a message repeating that often is worse than the
-- fault it reports.
local warnedAboutBags = false

local function warnOnce()
    if warnedAboutBags then
        return
    end
    warnedAboutBags = true
    ns.Print("This client will not let me read your bags, so the bar shows only what you are wearing.")
end

--- How many slots a bag has, through whichever API this client has.
local function bagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end

    if GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end

    return 0
end

--- The item link in a bag slot, or nil for an empty one.
local function bagLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end

    if GetContainerItemLink then
        return GetContainerItemLink(bag, slot)
    end

    return nil
end

--- An item's name, equip location and icon, by link.
--
-- Read positionally because that is how the call answers: name, link,
-- quality, level, minLevel, type, subType, stackCount, equipLoc, texture.
-- The two that matter are ninth and tenth.
local function itemFacts(link)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not info then
        return nil
    end

    local name, _, _, _, _, _, _, _, equipLoc, texture = info(link)
    if type(name) ~= "string" then
        return nil
    end

    return name, equipLoc, texture
end

--- Every trinket in the bags, by name, in alphabetical order.
--
-- Sorted rather than left in bag order: bag order changes every time the bags
-- are tidied, and a bar that reshuffles then is one no muscle memory can form
-- on. The set changing is the only thing that should move a button.
--
-- Guarded whole rather than per call: a client that refuses one of these
-- reads refuses them all, and a half-walked bag is not a better answer than
-- an empty one.
function Items.Carried()
    local canWalk = (C_Container and C_Container.GetContainerNumSlots)
        or GetContainerNumSlots
    if not canWalk then
        warnOnce()
        return {}
    end

    return ns.Guarded(function()
        local found, seen = {}, {}

        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, bagSlots(bag) do
                local link = bagLink(bag, slot)

                if link then
                    local name, equipLoc, texture = itemFacts(link)

                    -- Two of the same trinket collapse to one: /equipslot
                    -- takes the first match by name, so a second button for
                    -- the second copy would do exactly what the first does.
                    if name and equipLoc == TRINKET_LOCATION and not seen[name] then
                        seen[name] = true
                        found[#found + 1] = {
                            name = name,
                            link = link,
                            texture = texture,
                            bag = bag,
                            slot = slot,
                        }
                    end
                end
            end
        end

        table.sort(found, function(left, right)
            return left.name < right.name
        end)

        return found
    end, {})
end
