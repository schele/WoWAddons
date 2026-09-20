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

--- Whether a spell is one you cast on a friendly target: true, false, or nil
-- when this client will not say.
--
-- This is the rule that keeps a spellbook walk from offering Attack, Dodge,
-- Armor Proficiency, Mining and every other passive and profession sitting
-- in the same book. It is asked as a general question rather than matched
-- against a list of a class's heals, because a list would have to be right
-- for every class the seed already covers and wrong the day anyone respecs.
--
-- Note which way the unknown case falls, below: a client that cannot answer
-- shows everything rather than nothing. A filter that silently empties the
-- picker is worse than one that lets a few passives through.
function Spells.IsHelpful(spellName)
    if type(spellName) ~= "string" or spellName == "" then
        return nil
    end

    return ns.Guarded(function()
        if C_Spell and C_Spell.IsSpellHelpful then
            local helpful = C_Spell.IsSpellHelpful(spellName)
            if helpful ~= nil then
                return helpful and true or false
            end
        end

        if IsHelpfulSpell then
            return IsHelpfulSpell(spellName) and true or false
        end

        return nil
    end, nil)
end

-- What each class can usefully put in a slot.
--
-- Curated, which is a reversal: IsHelpful above was meant to answer this in
-- general, and on this client it does not. Shadowmeld, Wisp Spirit, Find
-- Minerals, Quickness and Elune's Light all came back as things you could
-- cast on a party member, and a picker full of racials and tracking
-- abilities is no better than the raw spellbook it was meant to tidy.
--
-- A list is wrong the day Blizzard adds a spell; the filter was wrong today,
-- on every character. So: a list where there is one, and IsHelpful for any
-- class nobody has curated -- a long picker beats an empty one, and an
-- omission here should cost tidiness rather than the feature.
local CLASS_SPELLS = {
    DRUID = {
        "Rejuvenation", "Regrowth", "Healing Touch", "Tranquility",
        "Mark of the Wild", "Gift of the Wild", "Thorns",
        "Remove Curse", "Abolish Poison", "Cure Poison",
        "Rebirth", "Innervate",
    },
    PRIEST = {
        "Lesser Heal", "Heal", "Greater Heal", "Flash Heal", "Renew",
        "Prayer of Healing", "Power Word: Shield",
        "Power Word: Fortitude", "Prayer of Fortitude",
        "Divine Spirit", "Prayer of Spirit",
        "Shadow Protection", "Prayer of Shadow Protection",
        "Dispel Magic", "Abolish Disease", "Cure Disease",
        "Resurrection", "Fear Ward",
    },
    PALADIN = {
        "Holy Light", "Flash of Light", "Lay on Hands", "Redemption",
        "Cleanse", "Purify", "Divine Intervention",
        "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings",
        "Blessing of Salvation", "Blessing of Light",
        "Blessing of Sanctuary", "Blessing of Freedom",
        "Blessing of Protection", "Blessing of Sacrifice",
        "Greater Blessing of Might", "Greater Blessing of Wisdom",
        "Greater Blessing of Kings", "Greater Blessing of Salvation",
        "Greater Blessing of Light", "Greater Blessing of Sanctuary",
    },
    SHAMAN = {
        "Healing Wave", "Lesser Healing Wave", "Chain Heal",
        "Cure Poison", "Cure Disease", "Ancestral Spirit",
        "Water Breathing", "Water Walking", "Lightning Shield",
    },
    MAGE = {
        "Arcane Intellect", "Arcane Brilliance", "Dampen Magic",
        "Amplify Magic", "Remove Lesser Curse", "Slow Fall",
    },
    WARLOCK = {
        "Unending Breath", "Detect Invisibility", "Soulstone Resurrection",
    },
}

-- Turned into sets once, at load, so the walk below is a lookup per spell
-- rather than a scan of the whole list.
local CLASS_SPELL_SET = {}
for class, names in pairs(CLASS_SPELLS) do
    local set = {}
    for _, name in ipairs(names) do
        set[name] = true
    end
    CLASS_SPELL_SET[class] = set
end

--- The list for the player's class, or nil for a class nobody has curated.
local function allowedForPlayer()
    local _, class = UnitClass("player")
    return class and CLASS_SPELL_SET[class] or nil
end

--- Every distinct spell the player can cast on a friendly target, by name,
-- in alphabetical order.
--
-- Distinct matters: Classic gives each rank its own spellbook entry, so a
-- druid with three ranks of Healing Touch has three entries all named
-- "Healing Touch". A slot holds a name, and a name casts the best rank the
-- player has, so the list has no use for the other two.
function Spells.Pickable()
    local names, seen = {}, {}
    local allowed = allowedForPlayer()
    local bank = playerSpellBank()

    for index = 1, SPELLBOOK_LIMIT do
        local name = nameFromBook(index, bank)
        if not name or name == "" then
            break
        end

        -- The class list decides where there is one. Where there is not,
        -- only a definite "not helpful" excludes, so a missing API costs a
        -- tidy list rather than the whole picker.
        local wanted
        if allowed then
            wanted = allowed[name] == true
        else
            wanted = Spells.IsHelpful(name) ~= false
        end

        if wanted and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end

    table.sort(names)
    return names
end

-- How deep to look through a unit's auras. Forty is past anything a party
-- member carries, and the walk stops at the first gap anyway; the cap only
-- matters on a client that answers for every index it is asked about.
local AURA_LIMIT = 40

-- Helpful auras this player cast, which is the only kind a ClickHeal button
-- can be responsible for. Someone else's Rejuvenation on the same target is
-- not this button's business.
local AURA_FILTER = "HELPFUL|PLAYER"

--- When each of the player's own helpful auras on `unit` expires, by spell
-- name. Empty when there are none, or when the client will not say.
--
-- Gathered per unit rather than asked per button: with eight buttons on each
-- of five rows, refreshed five times a second, asking per button would be
-- thousands of calls into the client every second for the same answers.
--
-- Guarded, like every other read here that the client might hand back as a
-- secret value -- an expiry time is exactly the sort of combat-relevant
-- number this client family has started withholding.
function Spells.PlayerAuras(unit)
    if not unit then
        return {}
    end

    return ns.Guarded(function()
        local expiries = {}

        for index = 1, AURA_LIMIT do
            local name, expires

            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local data = C_UnitAuras.GetAuraDataByIndex(unit, index, AURA_FILTER)
                if type(data) ~= "table" then
                    break
                end
                name, expires = data.name, data.expirationTime
            elseif UnitAura then
                -- name, icon, count, dispelType, duration, expirationTime
                local found, _, _, _, _, expirationTime = UnitAura(unit, index, AURA_FILTER)
                if not found then
                    break
                end
                name, expires = found, expirationTime
            else
                break
            end

            -- First wins: a spell appearing twice is the same spell, and the
            -- one the client lists first is the one it considers current.
            if type(name) == "string" and expiries[name] == nil then
                expiries[name] = expires or 0
            end
        end

        return expiries
    end, {})
end

--- Seconds left on the player's own `spellName` aura on `unit`, or nil when
-- it is not there, never expires, or cannot be read.
--
-- nil rather than 0 throughout: a slot with nothing on it and a slot whose
-- buff has just run out both mean "no number to show", and neither is worth
-- distinguishing under a 22 pixel icon.
function Spells.AuraRemaining(unit, spellName, auras)
    if type(spellName) ~= "string" or spellName == "" then
        return nil
    end

    auras = auras or Spells.PlayerAuras(unit)

    local expires = auras[spellName]
    if not expires or expires == 0 then
        return nil
    end

    local remaining = expires - (GetTime and GetTime() or 0)
    return remaining > 0 and remaining or nil
end
