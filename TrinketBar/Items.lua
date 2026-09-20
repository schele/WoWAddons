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

-- Said once per session each, not once per bag change: Carried() runs on
-- every BAG_UPDATE_DELAYED, and a message repeating that often is worse than
-- the fault it reports.
--
-- Two flags, not one, because the two failures are not the same claim.
-- "The bar shows only what you are wearing" is true when nothing could be
-- read at all; it is false, and actively misleading, when some trinkets
-- read fine and are sitting right there on the bar next to the two worn
-- ones. Which one applies is decided by the caller, by whether anything
-- ended up on the list.
local warnedBagsUnreadable = false
local warnedSomeItemsUnreadable = false

local function warnBagsUnreadable()
    if warnedBagsUnreadable then
        return
    end
    warnedBagsUnreadable = true
    ns.Print("This client will not let me read your bags, so the bar shows only what you are wearing.")
end

local function warnSomeItemsUnreadable()
    if warnedSomeItemsUnreadable then
        return
    end
    warnedSomeItemsUnreadable = true
    ns.Print("This client would not read some of what you are carrying, so the bar may be missing a trinket.")
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

    -- Coerced the same as name is rejected above: Bar.Apply branches on this
    -- one ("if entry.texture then") outside any guard, so whatever the
    -- client hands back here has to be a shape that branch can test safely.
    if type(texture) ~= "number" and type(texture) ~= "string" then
        texture = nil
    end

    return name, equipLoc, texture
end

--- Every trinket in the bags, by name, in alphabetical order.
--
-- Sorted rather than left in bag order: bag order changes every time the bags
-- are tidied, and a bar that reshuffles then is one no muscle memory can form
-- on. The set changing is the only thing that should move a button.
--
-- Guarded per bag and per slot rather than around the whole walk: a client
-- that refuses one of these reads still answers for the rest of them, and a
-- single unreadable item should cost that item, not every trinket on the
-- bar. Every failure along the way -- missing API, a raise counting a bag's
-- slots, a raise reading one of them -- sets the same flag, but which
-- warning that flag triggers below depends on whether the walk still found
-- anything: total failure and partial failure are different claims to the
-- player and must not share a message.
function Items.Carried()
    local canWalk = (C_Container and C_Container.GetContainerNumSlots)
        or GetContainerNumSlots
    if not canWalk then
        warnBagsUnreadable()
        return {}
    end

    local found, seen = {}, {}
    local anyUnreadable = false

    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = ns.Guarded(function() return bagSlots(bag) end, nil)

        if slots == nil then
            anyUnreadable = true
        else
            for slot = 1, slots do
                local ok = ns.Guarded(function()
                    local link = bagLink(bag, slot)

                    if link then
                        local name, equipLoc, texture = itemFacts(link)

                        -- Two of the same trinket collapse to one: /equipslot
                        -- takes the first match by name, so a second button
                        -- for the second copy would do exactly what the
                        -- first does.
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

                    return true
                end, false)

                if not ok then
                    anyUnreadable = true
                end
            end
        end
    end

    if anyUnreadable then
        -- Nothing on the list is the only case where "the bar shows only
        -- what you are wearing" is actually true. Anything else and the
        -- bar contradicts that claim the moment it is on screen.
        if #found == 0 then
            warnBagsUnreadable()
        else
            warnSomeItemsUnreadable()
        end
    end

    table.sort(found, function(left, right)
        return left.name < right.name
    end)

    return found
end

--- What is in each trinket slot: { [13] = entry, [14] = entry }, with a slot
-- missing where nothing is worn.
function Items.Worn()
    return ns.Guarded(function()
        local worn = {}

        for _, slot in ipairs(Items.TRINKET_SLOTS) do
            local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)

            if link then
                local name, _, texture = itemFacts(link)
                if name then
                    worn[slot] = {
                        name = name,
                        link = link,
                        texture = texture,
                        wornSlot = slot,
                    }
                end
            end
        end

        return worn
    end, {})
end

--- Everything the bar shows: the worn and the carried, as one list sorted by
-- name.
--
-- A trinket that is both worn and carried -- a second copy in the bags --
-- appears once, as the worn one. The worn entry says strictly more: it
-- carries which slot it is in, which is what the marker on the button needs.
function Items.All()
    local all, seen = {}, {}

    for _, entry in pairs(Items.Worn()) do
        if not seen[entry.name] then
            seen[entry.name] = true
            all[#all + 1] = entry
        end
    end

    for _, entry in ipairs(Items.Carried()) do
        if not seen[entry.name] then
            seen[entry.name] = true
            all[#all + 1] = entry
        end
    end

    table.sort(all, function(left, right)
        return left.name < right.name
    end)

    return all
end

--- When a trinket's cooldown started and how long it runs, or nil when there
-- is none to draw.
--
-- Which call answers depends on where the trinket is, which is why the entry
-- is passed rather than a name: a worn trinket is asked about by inventory
-- slot, a carried one by bag and slot, and nothing can turn one into the
-- other.
function Items.Cooldown(entry)
    if type(entry) ~= "table" then
        return nil
    end

    -- Gathered into a table before it leaves the guard, because ns.Guarded
    -- returns one value -- it is a pcall, and the second return of a pcall
    -- is the first return of what it called. Two loose values cannot come
    -- back through it, and asking the client twice to get them would be two
    -- reads where the answer must not disagree with itself.
    local reading = ns.Guarded(function()
        local start, duration

        if entry.wornSlot then
            if not GetInventoryItemCooldown then
                return nil
            end
            start, duration = GetInventoryItemCooldown("player", entry.wornSlot)
        else
            local read = (C_Container and C_Container.GetContainerItemCooldown)
                or GetContainerItemCooldown
            if not read then
                return nil
            end
            start, duration = read(entry.bag, entry.slot)
        end

        -- Zero duration is how the client says "not on cooldown", and it is
        -- the common answer. Returning it as a cooldown would draw a sweep
        -- of no length over every button.
        if not start or not duration or duration <= 0 then
            return nil
        end

        return { start = start, duration = duration }
    end, nil)

    if not reading then
        return nil
    end

    return reading.start, reading.duration
end
