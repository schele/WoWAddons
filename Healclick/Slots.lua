local addonName, ns = ...

-- The spell slots: how many buttons a row has, and what is in each. Nothing
-- here builds a frame or casts anything, which is what lets the decisions be
-- tested without a client.

local Slots = {}
ns.Slots = Slots

-- Every row builds this many buttons whatever the count says. Growing the bar
-- later must never need a frame created at a moment the client forbids one.
Slots.MAX = 8

-- A starting set per class, so a configuration that was never saved is still
-- usable. ForeverPanel seeds its chat keys for the same reason.
local SEED = {
    DRUID   = { "Regrowth", "Rejuvenation", "Remove Curse", "Mark of the Wild" },
    PRIEST  = { "Flash Heal", "Renew", "Dispel Magic", "Power Word: Fortitude" },
    PALADIN = { "Holy Light", "Flash of Light", "Cleanse", "Blessing of Might" },
    SHAMAN  = { "Healing Wave", "Lesser Healing Wave", "Cure Poison", "Lightning Shield" },
}

ns.AddDefaults({
    bar = {
        slots = 4,
        locked = false,
        -- Your own row: top by default, bottom if you prefer it there.
        selfBottom = false,
        spells = {},
    },
    seeded = false,
})

function Slots.Count()
    local count = tonumber(ns.db and ns.db.bar.slots) or 4
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
-- The name is stored either way. GetSpellInfo only knows spells this character
-- has learned, so refusing an unknown one would reject a level 5 Druid setting
-- up the Remove Curse they get at 24 -- and would reject our own seeds.
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

    if GetSpellInfo and not GetSpellInfo(spellName) then
        return true, string.format(
            "%s is not a spell you know yet. Kept anyway.", spellName
        )
    end

    return true
end

--- Fill empty slots with a starting set, once ever.
-- Once is the whole point: a slot the player deliberately empties must stay
-- empty at the next login rather than being helpfully refilled.
function Slots.Seed(class)
    if ns.db.seeded then
        return
    end
    ns.db.seeded = true

    local seed = SEED[class or ""]
    if not seed then
        return
    end

    for index, spell in ipairs(seed) do
        if ns.db.bar.spells[index] == nil then
            ns.db.bar.spells[index] = spell
        end
    end
end

-- Declared next to the code that reads them. Settings.lua renders whatever has
-- been declared, so adding one here needs no edit there.
--
-- Every onChange routes through Group.ApplyAll rather than writing attributes
-- directly, because that is the one place that knows to wait for combat.
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
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "selfBottom",
    type = "checkbox",
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
    name = "Lock the frame",
    tooltip = "Stops the bar being dragged around by accident.",
})
