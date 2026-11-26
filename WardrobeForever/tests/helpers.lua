local stub = require("wow_stub")

local M = {}

M.SLOT = stub.SLOT
M.worn = stub.worn
M.inBag = stub.inBag
M.inBank = stub.inBank

M.FILES = { "WardrobeForever.lua", "Forms.lua", "Settings.lua" }

--- Load the addon into a stubbed client the way WoW would: in .toc order,
-- each chunk receiving (addonName, privateTable). `prepare`, if given, sees
-- the client before any file loads.
function M.load(prepare)
    local env = stub.newEnv()
    if prepare then
        prepare(env)
    end
    local ns = {}

    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("WardrobeForever", ns)
    end

    return ns, env
end

--- Say that an item at `location` fits the slot, as GetInventoryItemsForSlot
-- would list it.
function M.fits(env, slotID, location, itemID)
    env.__items[slotID] = env.__items[slotID] or {}
    env.__items[slotID][location] = itemID or location
end

--- Move the cursor onto `frame`, or off everything when `frame` is nil:
-- OnLeave for whatever it was over, then OnEnter for the new frame.
function M.moveTo(env, frame)
    local left = {}
    for over in pairs(env.__mouseOver) do
        if over ~= frame then
            left[#left + 1] = over
        end
    end
    for _, over in ipairs(left) do
        env.__mouseOver[over] = nil
        over:Fire("OnLeave")
    end

    if frame and not env.__mouseOver[frame] then
        env.__mouseOver[frame] = true
        frame:Fire("OnEnter")
    end
end

--- Let `seconds` of game time pass, a frame at a time, running every shown
-- frame's OnUpdate.
function M.tick(env, seconds)
    local step = 1 / 60
    local elapsed = 0
    while elapsed < seconds - 1e-9 do
        local frames = {}
        for index, frame in ipairs(env.__frames) do
            frames[index] = frame
        end
        for _, frame in ipairs(frames) do
            if frame.shown and frame.scripts.OnUpdate then
                frame.scripts.OnUpdate(frame, step)
            end
        end
        elapsed = elapsed + step
    end
end

--- Fire an event on every frame registered for it.
function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do
        frames[index] = frame
    end
    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then
            frame:Fire("OnEvent", event, ...)
        end
    end
end

function M.login(env)
    M.fire(env, "PLAYER_LOGIN")
end

function M.flyoutOpenFor(env, slot)
    return env.EquipmentFlyoutFrame:IsShown() and env.EquipmentFlyoutFrame.button == slot
end

-- Gear and forms --------------------------------------------------------

-- A ring or trinket fits either of its two slots.
local PAIRED = { [11] = { 11, 12 }, [12] = { 11, 12 }, [13] = { 13, 14 }, [14] = { 13, 14 } }

--- Make an item that fits `slot` (and its twin, for rings and trinkets).
function M.item(env, guid, slot, twoHand)
    local slots = {}
    for _, each in ipairs(PAIRED[slot] or { slot }) do
        slots[each] = true
    end
    env.__itemInfo[guid] = { slots = slots, twoHand = twoHand == true }
end

--- Wear `guid` in `slot`, making the item if it is new.
function M.wear(env, slot, guid)
    if not env.__itemInfo[guid] then M.item(env, guid, slot) end
    env.__worn[slot] = guid
end

--- Put `guid`, an item for `slot`, in the first free bag space (or the
-- given one). Returns where it went.
function M.stow(env, guid, slot, bag, bagSlot)
    if not env.__itemInfo[guid] then M.item(env, guid, slot) end
    if not bag then
        for each = 0, 4 do
            for index = 1, env.__bagSize[each] do
                if not bag and not env.__bags[each][index] then
                    bag, bagSlot = each, index
                end
            end
        end
    end
    assert(bag, "no free bag space for " .. guid)
    env.__bags[bag][bagSlot] = guid
    return bag, bagSlot
end

function M.wearing(env, slot)
    return env.__worn[slot]
end

function M.inBags(env, guid)
    for _, contents in pairs(env.__bags) do
        for _, held in pairs(contents) do
            if held == guid then return true end
        end
    end
    return false
end

--- Take `guid` out of the bags, as if sold.
function M.remove(env, guid)
    for _, contents in pairs(env.__bags) do
        for slot, held in pairs(contents) do
            if held == guid then contents[slot] = nil end
        end
    end
end

--- Save a set on the equipment manager tab: { [slot] = guid | "empty" }.
function M.makeSet(env, setID, name, slots)
    env.__sets[setID] = { name = name, slots = slots }
end

M.BEAR, M.AQUATIC, M.CAT, M.TRAVEL = 5487, 1066, 768, 783

--- A level 38 druid's stance bar, as Forever lists it.
function M.druid(env)
    env.__forms = {
        { spellID = M.BEAR, name = "Bear Form" },
        { spellID = M.AQUATIC, name = "Aquatic Form" },
        { spellID = M.CAT, name = "Cat Form" },
        { spellID = M.TRAVEL, name = "Travel Form" },
    }
end

--- Shift into the form with `spellID`, or back to normal with nil.
function M.shift(env, spellID)
    env.__form = 0
    for index, form in ipairs(env.__forms) do
        if form.spellID == spellID then env.__form = index end
    end
    M.fire(env, "UPDATE_SHAPESHIFT_FORM")
end

function M.fight(env, on)
    env.__inCombat = on
    M.fire(env, on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

--- Put on a bagged item by hand, the way a right-click in the bags does.
function M.byHand(env, slot, guid)
    local at = env.C_Item.GetItemLocation(guid)
    env.C_Container.PickupContainerItem(at:GetBagAndSlot())
    env.PickupInventoryItem(slot)
    M.fire(env, "PLAYER_EQUIPMENT_CHANGED", slot, false)
end

-- The game takes its time ----------------------------------------------
--
-- The client asks the server for each swap: both items lock, and nothing
-- moves until the answer. async() makes the stub do that: a drop is queued
-- and its items locked, land() applies the queue and fires the events the
-- client fires, refuse() turns it all down. (From the final review's probes.)

local function guidAt(env, location)
    if location.equipmentSlot then return env.__worn[location.equipmentSlot] end
    return env.__bags[location.bag] and env.__bags[location.bag][location.slot]
end

function M.async(env)
    local pickInventory = env.PickupInventoryItem
    local pickContainer = env.C_Container.PickupContainerItem
    env.__queue = {}
    local function send(target, apply)
        if not env.__cursor then
            return apply()
        end
        local source = env.__cursor
        env.__cursor = nil
        env.__pickups = env.__pickups + 1
        local locked = {}
        for _, location in ipairs({ source, target }) do
            local guid = guidAt(env, location)
            if guid then
                env.__locked[guid] = true
                locked[#locked + 1] = guid
            end
        end
        table.insert(env.__queue, {
            source = source, apply = apply, locked = locked,
            slot = target.equipmentSlot or source.equipmentSlot,
        })
    end
    env.PickupInventoryItem = function(slot)
        send({ equipmentSlot = slot }, function() pickInventory(slot) end)
    end
    env.C_Container.PickupContainerItem = function(bag, slot)
        send({ bag = bag, slot = slot }, function() pickContainer(bag, slot) end)
    end
end

local function unlock(entry)
    for _, guid in ipairs(entry.locked) do entry.env.__locked[guid] = nil end
end

--- The server answers every swap sent so far. `order` "event-first" says
-- the gear changed while the items are still locked, then unlocks them;
-- otherwise they unlock first.
function M.land(env, order)
    local queue = env.__queue
    env.__queue = {}
    for _, entry in ipairs(queue) do
        entry.env = env
        unlock(entry)
        env.__cursor = entry.source
        local pickups = env.__pickups
        entry.apply()
        env.__pickups = pickups
        env.__cursor = nil
        if order == "event-first" then
            for _, guid in ipairs(entry.locked) do env.__locked[guid] = true end
            M.fire(env, "PLAYER_EQUIPMENT_CHANGED", entry.slot, false)
            unlock(entry)
            M.fire(env, "ITEM_UNLOCKED")
        else
            M.fire(env, "ITEM_UNLOCKED")
            M.fire(env, "PLAYER_EQUIPMENT_CHANGED", entry.slot, false)
        end
    end
end

--- The server turns down every swap sent so far: a red error each.
function M.refuse(env)
    local queue = env.__queue
    env.__queue = {}
    for _, entry in ipairs(queue) do
        entry.env = env
        unlock(entry)
        env.__refused = env.__refused + 1
        M.fire(env, "ITEM_UNLOCKED")
    end
end

--- Load and log in, with `saved` as this character's saved variables.
function M.start(saved, prepare)
    local ns, env = M.load(prepare)
    env.WardrobeForeverCharDB = saved
    M.fire(env, "ADDON_LOADED", "WardrobeForever")
    M.login(env)
    M.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    return ns, env
end

return M
