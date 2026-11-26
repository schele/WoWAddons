local addonName, ns = ...

-- A gear set for each form. The player picks one of this character's
-- equipment sets (Blizzard's Equipment Manager tab, behind the arrow on the
-- character sheet) for a form, and shifting into the form puts it on.
-- Shifting out puts back what was worn before.
--
-- The gear wanted is the normal gear, remembered when a set first changes a
-- slot, with the current form's set on top. It is put on when something
-- asks for it: a shift, the end of a fight, a new choice or a change to the
-- sets. Every other gear change only finishes that work, or notices a slot
-- the player changed by hand, which is theirs until the next shift.
--
-- Items move one slot at a time with the cursor, the way Blizzard's
-- equipment pop-out does. The game answers each swap a moment later: both
-- items lock until it does, and a slot counts as done only once the item is
-- seen in it. In a fight Forever lets no addon change gear, weapons
-- included ("Interface action failed because of an AddOn", 2026-11-26), so
-- it all waits for the fight to end. Nothing moves while casting or dead.
--
-- Items are known by GUID, so two of the same ring are told apart and an
-- item is found again wherever it has moved to in the bags.

if not (C_EquipmentSet and C_EquipmentSet.GetItemLocations and GetShapeshiftFormInfo
    and C_Item and C_Item.GetItemGUID and C_Item.GetItemLocation and ItemLocation
    and EquipmentManager_GetLocationData) then
    return
end

local Forms = {}
ns.Forms = Forms

local FIRST_SLOT, LAST_SLOT = 1, 19
-- A two-hander in the main hand takes the off hand's item off, so changing
-- one weapon slot remembers the other too, and neither hand moves while the
-- other is on its way.
local WEAPON_PARTNER = { [16] = 17, [17] = 16 }
-- Swaps sent for one slot before giving up until something asks again: the
-- game can keep turning one down (bags full for a two-hander's off-hand).
local MAX_TRIES = 3

local db       -- WardrobeForeverCharDB, once the game has loaded it
local entered  -- the world is up: forms and gear can be read
local asked = true -- something asked for the form's gear, and it is not all on yet
local pending = {} -- [slot] = what was sent for (guid, or false for empty), not yet seen there
local tries = {}   -- [slot] = swaps sent since the last ask
local updating

local function clear(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

--- Something wants the form's gear on: a shift, a fight's end, the sets.
local function ask()
    asked = true
    clear(tries)
end

--- The GUID of what `slot` holds, or false when it is empty.
local function worn(slot)
    local location = ItemLocation:CreateFromEquipmentSlot(slot)
    if C_Item.DoesItemExist(location) then
        return C_Item.GetItemGUID(location)
    end
    return false
end

local function locked(slot)
    return IsInventoryItemLocked(slot) and true or false
end

local function forget(slot)
    db.normal[slot] = nil
    db.placed[slot] = nil
    pending[slot] = nil
end

--- The backpack and the bags worn in the bag slots, not the bank's.
local function isCarried(bag)
    return bag >= 0 and bag <= NUM_TOTAL_EQUIPPED_BAG_SLOTS
end

--- Casting (equipping would be refused) or dead (forms and fights end, and
-- nothing can be worn until alive again).
local function busy()
    return UnitCastingInfo("player") or UnitChannelInfo("player") or UnitIsDeadOrGhost("player")
end

--- What a set wants worn: [slot] = item GUID, or false for a slot saved
-- empty. Slots the set ignores, and items it cannot reach (gone, or in the
-- bank), are left out.
local function setItems(setID)
    local items = {}
    local locations = setID and C_EquipmentSet.GetItemLocations(setID)
    if not locations then
        return items
    end
    for slot = FIRST_SLOT, LAST_SLOT do
        local location = locations[slot]
        if location == EQUIPMENT_SET_EMPTY_SLOT then
            items[slot] = false
        elseif location and location ~= EQUIPMENT_SET_IGNORED_SLOT and location ~= EQUIPMENT_SET_ITEM_MISSING then
            local data = EquipmentManager_GetLocationData(location)
            local itemLocation
            if data.isBags and not data.isBank and isCarried(data.bag) then
                itemLocation = ItemLocation:CreateFromBagAndSlot(data.bag, data.slot)
            elseif data.isPlayer and not data.isBags and not data.isBank then
                itemLocation = ItemLocation:CreateFromEquipmentSlot(data.slot)
            end
            if itemLocation and C_Item.DoesItemExist(itemLocation) then
                items[slot] = C_Item.GetItemGUID(itemLocation)
            end
        end
    end
    return items
end

--- Send the item with `guid` to `slot`. Returns "sent", "locked" (try
-- again later), "held" (the game kept it on the cursor: counts as a try),
-- "missing" (not on the character) or "refused" (the game will not have it
-- in that slot).
local function putOn(guid, slot)
    local location = C_Item.GetItemLocation(guid)
    if not location then
        return "missing"
    end
    local from
    if location:IsEquipmentSlot() then
        from = location:GetEquipmentSlot()
    elseif not isCarried((location:GetBagAndSlot())) then
        return "missing"
    end
    if C_Item.IsLocked(location) then
        return "locked"
    end

    local leaving = worn(slot)
    ClearCursor()
    if from then
        PickupInventoryItem(from)
    else
        C_Container.PickupContainerItem(location:GetBagAndSlot())
    end
    if not C_PaperDollInfo.CursorCanGoInSlot(slot) then
        ClearCursor()
        return "refused"
    end
    PickupInventoryItem(slot)
    if CursorHasItem() then
        ClearCursor() -- held back for now; never leave it on the cursor
        return "held"
    end
    pending[slot] = guid
    -- Worn to worn swaps the two slots: what left `slot` goes to `from`.
    if from then
        pending[from] = leaving
    end
    return "sent"
end

--- Send `slot`'s item to the first free bag space this pass has not
-- handed out yet. Returns "sent", or "full" when there is none.
local function takeOff(slot, used)
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local free, bagType = C_Container.GetContainerNumFreeSlots(bag)
        if free and free > 0 and bagType == 0 then
            for _, bagSlot in ipairs(C_Container.GetContainerFreeSlots(bag)) do
                local key = bag .. ":" .. bagSlot
                if not used[key] then
                    used[key] = true
                    ClearCursor()
                    PickupInventoryItem(slot)
                    C_Container.PickupContainerItem(bag, bagSlot)
                    if CursorHasItem() then
                        ClearCursor()
                        return "full"
                    end
                    pending[slot] = false
                    return "sent"
                end
            end
        end
    end
    return "full"
end

--- Keep the choices in step with the stance bar and the sets. A choice
-- whose form left the bar moves to the form now in its place, if that one
-- has none: Dire Bear Form replaces Bear Form at level 40. With `prune`,
-- a choice whose set was deleted goes, so a new set given the same number
-- is not worn. Only once this session has seen the sets: at login the game
-- may not have them yet, and every choice would go.
local setsSeen
local function tidy(prune)
    if not db then
        return
    end
    if #(C_EquipmentSet.GetEquipmentSetIDs() or {}) > 0 then
        setsSeen = true
    end
    prune = prune and setsSeen
    local atIndex, onBar = {}, {}
    for index = 1, GetNumShapeshiftForms() do
        local spellID = select(4, GetShapeshiftFormInfo(index))
        if spellID then
            atIndex[index], onBar[spellID] = spellID, index
        end
    end
    local moves = {}
    for spellID, choice in pairs(db.forms) do
        if prune and not C_EquipmentSet.GetEquipmentSetInfo(choice.set) then
            moves[#moves + 1] = { from = spellID }
        elseif onBar[spellID] then
            choice.index = onBar[spellID]
        elseif choice.index and atIndex[choice.index] and not db.forms[atIndex[choice.index]] then
            moves[#moves + 1] = { from = spellID, to = atIndex[choice.index] }
        end
    end
    for _, move in ipairs(moves) do
        if move.to and not db.forms[move.to] then
            db.forms[move.to] = db.forms[move.from]
        end
        db.forms[move.from] = nil
    end
end

--- This character's forms and stances, in stance bar order.
function Forms.List()
    tidy()
    local forms = {}
    for index = 1, GetNumShapeshiftForms() do
        local spellID = select(4, GetShapeshiftFormInfo(index))
        if spellID then
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
            forms[#forms + 1] = { spellID = spellID, name = name or tostring(spellID), index = index }
        end
    end
    return forms
end

--- This character's equipment sets, in the game's order.
function Forms.Sets()
    local sets = {}
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then
            sets[#sets + 1] = { setID = setID, name = name }
        end
    end
    return sets
end

--- The set chosen for the form with `spellID`, or nil for "Leave gear alone".
function Forms.GetSet(spellID)
    tidy()
    local choice = db and db.forms[spellID]
    if choice and C_EquipmentSet.GetEquipmentSetInfo(choice.set) then
        return choice.set
    end
    return nil
end

--- Choose a set for a form (nil for "Leave gear alone"). In that form now,
-- the change is worn at once.
function Forms.SetSet(spellID, setID)
    if not db then
        return
    end
    if setID then
        local index
        for _, form in ipairs(Forms.List()) do
            if form.spellID == spellID then
                index = form.index
            end
        end
        db.forms[spellID] = { set = setID, index = index }
    else
        db.forms[spellID] = nil
    end
    ask()
    Forms.Update()
end

--- A slot WardrobeForever is looking after that holds none of the items it
-- expects (the normal one, the one it put there, the one on its way) was
-- changed by hand. The player's change wins: the slot is theirs until the
-- next shift.
local function noticeHandChanges()
    for slot, normal in pairs(db.normal) do
        local now = worn(slot)
        local expecting = db.placed[slot] ~= nil or pending[slot] ~= nil
        if expecting and now ~= normal and now ~= db.placed[slot] and now ~= pending[slot]
            and not locked(slot) then
            forget(slot)
            db.released[slot] = true
        end
    end
end

--- Seen in place: what was sent for has arrived.
local function arrived(slot, want, restoring)
    pending[slot] = nil
    if restoring then
        forget(slot)
    elseif db.normal[slot] ~= nil then
        db.placed[slot] = want
    end
end

--- Put on the form's gear: `set` over the normal gear. Returns true while
-- some of it is still to come (in flight, waiting for the fight to end, a
-- locked item, bags full).
local function wear(set)
    local fighting = InCombatLockdown()
    local unfinished = false

    -- Remember the normal gear of every slot the set changes, all before
    -- any move: rings change fingers mid-way.
    for slot, item in pairs(set) do
        if not db.released[slot] and db.normal[slot] == nil and not locked(slot) and worn(slot) ~= item then
            db.normal[slot] = worn(slot)
            local partner = WEAPON_PARTNER[slot]
            if partner and db.normal[partner] == nil and not db.released[partner] then
                db.normal[partner] = worn(partner)
            end
        end
    end

    -- Move, in slot order: the main hand before the off hand.
    local used = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        local partner = WEAPON_PARTNER[slot]
        local partnerInSet = partner ~= nil and set[partner] ~= nil
        local want, restoring = set[slot], false
        if db.released[slot] then
            want = nil
        elseif want == nil and db.normal[slot] ~= nil and not partnerInSet then
            want, restoring = db.normal[slot], true
        end

        if want == nil then
            -- The other hand of a set's weapon is the game's to fill until
            -- the form is left. Note what it left there, so a change by
            -- hand shows.
            if partnerInSet and db.normal[slot] ~= nil and db.placed[slot] == nil and not db.released[slot]
                and not locked(slot) and not locked(partner) and worn(partner) == set[partner] then
                db.placed[slot] = worn(slot)
            end
        elseif locked(slot) or (partner and locked(partner)) then
            unfinished = true -- on its way, or the other hand is
        elseif worn(slot) == want then
            arrived(slot, want, restoring)
        elseif fighting then
            unfinished = true -- after the fight
        elseif (tries[slot] or 0) >= MAX_TRIES then
            -- Turned down too often: left until something asks again.
        else
            local result
            if want == false then
                result = takeOff(slot, used)
            else
                result = putOn(want, slot)
            end
            if result == "sent" or result == "held" then
                tries[slot] = (tries[slot] or 0) + 1
                if worn(slot) == want then
                    arrived(slot, want, restoring) -- a client that answers at once
                else
                    unfinished = true
                end
            elseif result == "locked" or result == "full" then
                unfinished = true
            elseif restoring then
                forget(slot) -- "missing" or "refused": it cannot come back
            end
        end
    end
    return unfinished
end

--- Bring what is worn in line with the current form.
function Forms.Update()
    -- Something on the cursor is the player's: wait for the next change.
    if updating or not (db and entered) or CursorHasItem() or busy() then
        return
    end
    local index = GetShapeshiftForm() or 0
    local form
    if index > 0 then
        form = select(4, GetShapeshiftFormInfo(index))
        if not form then
            return -- at login the stance bar can be there before its spells
        end
    end
    tidy()
    if db.form ~= (form or 0) then
        db.form = form or 0
        clear(db.released)
        ask()
    end
    local choice = form and db.forms[form]
    if choice and not setsSeen and not C_EquipmentSet.GetEquipmentSetInfo(choice.set) then
        return -- at login the game may not have sent the sets yet
    end

    updating = true
    noticeHandChanges()
    if asked then
        asked = wear(setItems(form and Forms.GetSet(form)))
    end
    updating = false
end

-- Events that ask for the form's gear; every other one only lets work in
-- hand go on.
local ASKS = { PLAYER_ENTERING_WORLD = true, PLAYER_REGEN_ENABLED = true }
local FOR_THE_PLAYER = {
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
}

local events = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED",
    "PLAYER_EQUIPMENT_CHANGED", "ITEM_UNLOCKED", "BAG_UPDATE_DELAYED", "EQUIPMENT_SETS_CHANGED",
    "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_CHANNEL_STOP",
}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        if type(WardrobeForeverCharDB) ~= "table" then
            WardrobeForeverCharDB = {}
        end
        db = WardrobeForeverCharDB
        for _, key in ipairs({ "forms", "normal", "placed", "released" }) do
            if type(db[key]) ~= "table" then
                db[key] = {}
            end
        end
        return
    end
    if FOR_THE_PLAYER[event] and arg1 ~= "player" then
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        entered = true
    end
    if event == "EQUIPMENT_SETS_CHANGED" then
        tidy(true)
        ask()
    elseif ASKS[event] then
        ask()
    end
    Forms.Update()
end)
