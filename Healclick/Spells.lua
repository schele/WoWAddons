local addonName, ns = ...

-- What this client knows about a spell: its icon, whether it is learned, and
-- what a spellbook drag or a cursor pickup actually names. Everything here is
-- a pure lookup against the client's spell APIs -- no frame, no row, no
-- layout -- which is what lets this file answer "what spell is that" without
-- Row.lua or Slots.lua needing their own, separate guess at the same thing.

local Spells = {}
ns.Spells = Spells

--- The spell's own icon, defensively: the namespaced call if this client has
-- it, the old global if it does not, nil if neither does. A spike against
-- this addon's 1.60 Classic beta target found GetSpellInfo and
-- GetSpellBookItemName gone, moved into C_Spell and C_SpellBook, while
-- C_SpellBook's namespaced call still worked -- so the namespaced route is
-- the likely one, but trying both means we do not have to be right about it.
function Spells.Texture(spellName)
    if type(spellName) ~= "string" or spellName == "" then
        return nil
    end

    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellName)
    end

    if GetSpellTexture then
        return GetSpellTexture(spellName)
    end

    return nil
end

--- A spell's name from whatever identifies it -- a spellID or the name
-- itself -- tried through whichever API this client has. Both
-- C_Spell.GetSpellInfo and the old GetSpellInfo accept either kind of
-- argument, which is what lets this one helper serve both CursorSpell's
-- spellID route below and IsKnown's by-name check.
local function nameFromSpellInfo(identifier)
    if not identifier then
        return nil
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(identifier)
        if type(info) == "table" and type(info.name) == "string" then
            return info.name
        end
    end

    if GetSpellInfo then
        local name = GetSpellInfo(identifier)
        if type(name) == "string" then
            return name
        end
    end

    return nil
end

--- A spell name from a spellbook (index, bookType) pair, tried the same way.
local function nameFromBook(index, bookType)
    if not index then
        return nil
    end

    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        local name = C_SpellBook.GetSpellBookItemName(index, bookType)
        if type(name) == "string" then
            return name
        end
    end

    if GetSpellBookItemName then
        local name = GetSpellBookItemName(index, bookType)
        if type(name) == "string" then
            return name
        end
    end

    return nil
end

--- Whether this client knows the spell by name, through whichever API it
-- has -- the same defensive chain as everything else here, so there is one
-- answer to "what spell APIs does this client have" rather than a caller
-- keeping its own, separate guess. A client with neither API cannot be asked
-- at all, so this reports the spell as known rather than warn about
-- something it has no way to confirm either way.
function Spells.IsKnown(spellName)
    if type(spellName) ~= "string" or spellName == "" then
        return false
    end

    if (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo then
        return nameFromSpellInfo(spellName) ~= nil
    end

    return true
end

--- What spell, if any, is on the cursor -- nil for anything else (an item, a
-- macro, an empty cursor), so a player dropping or clicking one of those can
-- carry on carrying it. GetCursorInfo's extra returns for a spell differ by
-- client: some hand back a spellID, others only a spellbook index and which
-- book it came from, so the ID route is tried first and the book route
-- second, rather than assuming which this client gives.
function Spells.CursorSpell()
    local cursorType, index, bookType, spellID = GetCursorInfo()
    if cursorType ~= "spell" then
        return nil
    end

    return nameFromSpellInfo(spellID) or nameFromBook(index, bookType)
end

--- When a spell's cooldown started and how long it runs: start, duration and
-- whether the client wants a sweep drawn at all. Nil when this client has
-- nothing to say about the spell, which a caller reads as "draw nothing"
-- rather than "ready".
--
-- The two APIs disagree about shape, not just about name: C_Spell hands back
-- a table, while the old global returned four loose values with `enabled` as
-- 1 or 0. Normalising here is the point of the function -- 0 is truthy in
-- Lua, so a caller testing the raw return would draw a sweep over exactly
-- the spell the client asked it not to.
function Spells.Cooldown(spellName)
    if type(spellName) ~= "string" or spellName == "" then
        return nil
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellName)
        if type(info) ~= "table" then
            return nil
        end
        return info.startTime, info.duration, info.isEnabled ~= false
    end

    if GetSpellCooldown then
        local start, duration, enabled = GetSpellCooldown(spellName)
        if start then
            return start, duration, enabled ~= 0 and enabled ~= false
        end
    end

    return nil
end

--- Whether `spellName` can currently reach `unit`: true, false, or nil when
-- this client will not say.
--
-- Per spell rather than per unit. UnitInRange answers for the unit as a
-- whole, which is both less useful -- a 40 yard heal and a melee-range
-- debuff do not have the same reach -- and, on this client, unavailable:
-- its answer comes back as a secret value that tainted code may not inspect.
-- The same may well be true here, so the call and the branch on its result
-- both sit inside ns.Guarded.
--
-- nil means "cannot tell" and is deliberately distinct from false. Telling a
-- healer a spell is out of reach when it is not costs them a cast they had.
function Spells.InRange(spellName, unit)
    if type(spellName) ~= "string" or spellName == "" or not unit then
        return nil
    end

    return ns.Guarded(function()
        if C_Spell and C_Spell.IsSpellInRange then
            local result = C_Spell.IsSpellInRange(spellName, unit)
            if result == nil then
                return nil
            end
            return result and true or false
        end

        if IsSpellInRange then
            -- 1 or 0, never a boolean. 0 is truthy in Lua, so it has to be
            -- compared rather than tested.
            local result = IsSpellInRange(spellName, unit)
            if result == nil then
                return nil
            end
            return result == 1 or result == true
        end

        return nil
    end, nil)
end

-- Where the player's own spells live in the spellbook. Modern clients name
-- the bank through Enum; older ones used the string "spell". Asked rather
-- than assumed, like every other client difference in this file.
local function playerSpellBank()
    if Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player then
        return Enum.SpellBookSpellBank.Player
    end

    return BOOKTYPE_SPELL or "spell"
end

-- A spellbook has no published length on every client, but it does end: the
-- name lookup returns nothing past the last entry. Walking until it does
-- needs no API beyond the one the drag-and-drop path already relies on,
-- which is the point -- this client has already moved two spell APIs out
-- from under this addon, and enumerating is not worth a third dependency.
--
-- The cap is a guard against a client that answers for every index it is
-- ever asked about, which would otherwise be an infinite loop in the
-- settings panel.
local SPELLBOOK_LIMIT = 1000

--- Every distinct spell the player knows, by name, in alphabetical order.
--
-- Distinct matters: Classic gives each rank its own spellbook entry, so a
-- druid with three ranks of Healing Touch has three entries all named
-- "Healing Touch". A slot holds a name, and a name casts the best rank the
-- player has, so the list has no use for the other two.
function Spells.Known()
    local names, seen = {}, {}
    local bank = playerSpellBank()

    for index = 1, SPELLBOOK_LIMIT do
        local name = nameFromBook(index, bank)
        if not name or name == "" then
            break
        end

        if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end

    table.sort(names)
    return names
end
