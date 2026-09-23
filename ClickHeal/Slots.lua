local addonName, ns = ...

-- The spell slots: how many buttons a row has, and what is in each. Nothing
-- here builds a frame or casts anything, which is what lets the decisions be
-- tested without a client.

local Slots = {}
ns.Slots = Slots

-- Every row builds this many buttons whatever the count says. Growing the bar
-- later must never need a frame created at a moment the client forbids one.
Slots.MAX = 8

-- How many buttons a row shows before anyone changes it. Named rather than
-- written in twice, because the default and the fallback Count uses when the
-- database has not loaded have to be the same number.
Slots.DEFAULT_COUNT = 6

-- A starting set per class, so a configuration that was never saved is still
-- usable. ForeverPanel seeds its chat keys for the same reason.
local SEED = {
    DRUID   = { "Rejuvenation", "Healing Touch", "Mark of the Wild", "Thorns", "Revive" },
    PRIEST = { "Flash Heal", "Renew", "Dispel Magic", "Power Word: Fortitude" },
    PALADIN = { "Holy Light", "Flash of Light", "Cleanse", "Blessing of Might" },
    SHAMAN  = { "Healing Wave", "Lesser Healing Wave", "Cure Poison", "Lightning Shield" },
}

ns.AddDefaults({
    bar = {
        slots = Slots.DEFAULT_COUNT,
        locked = false,
        -- Your own row: top by default, bottom if you prefer it there.
        selfBottom = false,
        spells = {},
    },
    seeded = false,
    -- Spells from SEED_LATER already handed out, by name, so each goes out once.
    seedAdded = {},
})

-- Spells added to a seed after it first shipped. A configuration seeded before
-- they existed gets each one once, in its first empty slot; seeding still
-- happens once, so these are the only thing that reaches it afterwards.
local SEED_LATER = {
    DRUID = { "Revive" },
}

function Slots.Count()
    local count = tonumber(ns.db and ns.db.bar.slots) or Slots.DEFAULT_COUNT
    count = math.floor(count)

    if count < 1 then
        return 1
    elseif count > Slots.MAX then
        return Slots.MAX
    end

    return count
end

function Slots.Spell(index)
    local spells = ns.db and ns.db.bar.spells
    local spell = spells and spells[index]

    return spell
end

--- Put a spell in a slot. Returns ok, and a warning when the client does not
-- recognise the name.
--
-- The name is stored either way. ns.Spells.IsKnown only knows spells this
-- character has learned, so refusing an unknown one would reject a level 5
-- Druid setting up the Remove Curse they get at 24 -- and would reject our
-- own seeds. Asking Spells rather than a global here directly means there is
-- one answer to "what spell APIs does this client have", not a second guess
-- that can disagree with the one Row.lua uses for icons and drag-and-drop.
function Slots.Set(index, spellName)
    if type(index) ~= "number" or index < 1 or index > Slots.MAX then
        return false, "no such slot"
    end

    spellName = type(spellName) == "string" and spellName:match("^%s*(.-)%s*$") or ""

    if spellName == "" then
        ns.db.bar.spells[index] = nil
        return true
    end

    ns.db.bar.spells[index] = spellName

    if not ns.Spells.IsKnown(spellName) then
        return true, string.format(
            "%s is not a spell you know yet. Kept anyway.", spellName
        )
    end

    return true
end

--- Fill empty slots with a starting set, once ever.
-- Once is the whole point: a slot the player deliberately empties must stay
-- empty at the next login rather than being helpfully refilled.
local function slotted(spell)
    for index = 1, Slots.MAX do
        if ns.db.bar.spells[index] == spell then
            return true
        end
    end
    return false
end

--- Hand out any SEED_LATER spells this configuration has not had yet.
-- Marked as given even when there is no room or it is already slotted, so
-- emptying the slot afterwards sticks, the same as it does for the seed.
local function seedLater(class)
    local added = ns.db.seedAdded

    for _, spell in ipairs(SEED_LATER[class or ""] or {}) do
        if not added[spell] then
            added[spell] = true

            if not slotted(spell) then
                for index = 1, Slots.Count() do
                    if ns.db.bar.spells[index] == nil then
                        ns.db.bar.spells[index] = spell
                        break
                    end
                end
            end
        end
    end
end

function Slots.Seed(class)
    if ns.db.seeded then
        seedLater(class)
        return
    end

    local seed = SEED[class or ""]
    if not seed then
        -- Not burnt here: ClickHealDB is account-wide, so a first login on a
        -- class with no seed set (Warrior, Rogue, Mage) must not permanently
        -- deny every other character on the account -- a Druid main included
        -- -- its own seed the first time it logs in.
        return
    end
    ns.db.seeded = true

    for index, spell in ipairs(seed) do
        if ns.db.bar.spells[index] == nil then
            ns.db.bar.spells[index] = spell
        end
    end

    -- The fresh seed already carries them; mark them so they are not handed
    -- out a second time.
    seedLater(class)
end

-- Declared next to the code that reads them. Settings.lua renders whatever has
-- been declared, so adding one here needs no edit there.
--
-- Every onChange routes through Group.ApplyAll rather than writing attributes
-- directly, because that is the one place that knows to wait for combat.
ns.RegisterColumn("right", "Raid settings")

ns.RegisterSetting({
    store = "bar",
    key = "slots",
    type = "slider",
    name = "Buttons per player",
    min = 1,
    max = Slots.MAX,
    step = 1,
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
        -- The count decides how many slot rows the panel shows, so the panel
        -- has to redraw itself as the slider moves. Panel.Refresh guards
        -- against the loop this would otherwise make with the slider's own
        -- Refresh.
        if ns.SettingsPanel then ns.SettingsPanel.Refresh() end
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "selfBottom",
    type = "checkbox",
    column = "right",
    name = "Put my row at the bottom",
    tooltip = "Whether you sit above the party or below it.",
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "spells",
    type = "spelltable",
    name = "Spells",
    rows = Slots.MAX,
    onChange = function()
        if ns.Group then ns.Group.ApplyAll() end
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "locked",
    type = "checkbox",
    column = "right",
    name = "Lock the frame",
    tooltip = "Stops the bar being dragged around by accident.",
})

--- Move the spell in `from` to `to`, sliding everything between along.
--
-- A move rather than a swap: dragging row 5 onto row 1 means "put this
-- first", and swapping would send whatever was first down to row 5, which
-- nobody dragging asked for. Sliding is what a list does.
--
-- Returns true when something actually moved, so a caller can skip the
-- reapply that follows -- a drag that ends where it started is not a change.
function Slots.Move(from, to)
    if type(from) ~= "number" or type(to) ~= "number" then
        return false
    end

    if from < 1 or from > Slots.MAX or to < 1 or to > Slots.MAX or from == to then
        return false
    end

    local spells = ns.db and ns.db.bar.spells
    if not spells then
        return false
    end

    -- Read the whole strip out first. Slots are a sparse table -- an empty
    -- slot is a hole, not an empty string -- so shifting in place would have
    -- to special-case every gap.
    local order = {}
    for index = 1, Slots.MAX do
        order[index] = spells[index]
    end

    -- Shifted by hand rather than with table.remove and table.insert. Those
    -- want a sequence, and this is not one: an empty slot is a hole, so the
    -- length operator stops at the first gap and a move across one is
    -- refused outright.
    local moving = order[from]

    if from < to then
        for index = from, to - 1 do
            order[index] = order[index + 1]
        end
    else
        for index = from, to + 1, -1 do
            order[index] = order[index - 1]
        end
    end

    order[to] = moving

    for index = 1, Slots.MAX do
        spells[index] = order[index]
    end

    return true
end
