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

    -- Gathered into a table before it leaves the guard, because ns.Guarded is
    -- a pcall and a pcall returns one value.
    local reading = ns.Guarded(function()
        local start, duration, enabled

        if C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(spellName)
            if type(info) ~= "table" then
                return nil
            end
            start, duration = info.startTime, info.duration
            enabled = info.isEnabled ~= false
        elseif GetSpellCooldown then
            start, duration, enabled = GetSpellCooldown(spellName)
            enabled = enabled ~= 0 and enabled ~= false
        else
            return nil
        end

        -- Both numbers are compared in here rather than handed out for the
        -- caller to test, and that placement is the whole point. A number
        -- this client will not disclose is truthy and survives `or 0`, so
        -- having fetched one proves nothing about it; comparing it is what
        -- raises. Comparing both here turns "the client will not say" into a
        -- missing sweep, where doing it upstairs took the refresh down for
        -- every remaining button on every remaining row.
        if not start or not duration or start < 0 or duration <= 0 then
            return nil
        end

        return { start = start, duration = duration, enabled = enabled }
    end, nil)

    if not reading then
        return nil
    end

    return reading.start, reading.duration, reading.enabled
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

-- Every helpful aura on a unit, whoever cast it. Narrowed to this player's
-- own once, and no longer: a Mark of the Wild somebody else put on someone is
-- one you do not need to re-cast, so a blank where one is running told a
-- healer to spend a global cooldown on nothing. Who cast it is still read --
-- see castByPlayer below -- because it decides how the number is drawn, not
-- whether there is one.
--
-- The PLAYER half of this filter went with that change, and would have had to
-- go anyway: /ch auras on 1.60.1, 2026-09-22 found HELPFUL|PLAYER returning 0
-- auras for "player" while plain HELPFUL returned the Mark of the Wild that
-- character had cast on themselves a minute earlier, name and expiry both
-- readable -- with the same filtered walk answering correctly for party1 in
-- the same report. The row beside your own frame was the only one in the
-- group with no numbers on it.
local AURA_FILTER = "HELPFUL"

--- Whether the client says this player cast the aura, given something that
-- fetches the caster.
--
-- A function rather than the value, because on 1.60.1 fetching it is itself
-- a thing the client refuses: `data.sourceUnit` raises where `data.name` and
-- `data.expirationTime` beside it do not. Read in the same statement as
-- those two -- which is how this shipped for one build -- it took down the
-- whole walk, for every unit and both filters, and the bar lost every number
-- it had. So the fetch and the comparison sit in one guard, and the guard is
-- per aura: an unreadable caster costs its own answer and nothing else.
--
-- Unknown is yours, whether the client stayed silent or refused outright.
-- Silence is not "somebody else cast it", and on your own unit this client is
-- silent about every aura, including the one you cast a second ago -- the
-- other reading greys the row you look at most.
local function castByPlayer(fetchSource)
    return ns.Guarded(function()
        local source = fetchSource()
        return source == nil or source == "player"
    end, true)
end

--- Every helpful aura on `unit`, by spell name: when it expires, and whether
-- this player is the one who cast it. Empty when there are none, or when the
-- client will not say.
--
-- Gathered per unit rather than asked per button: with eight buttons on each
-- of five rows, refreshed five times a second, asking per button would be
-- thousands of calls into the client every second for the same answers.
--
-- Guarded, like every other read here that the client might hand back as a
-- secret value -- an expiry time is exactly the sort of combat-relevant
-- number this client family has started withholding.
function Spells.HelpfulAuras(unit)
    if not unit then
        return {}
    end

    return ns.Guarded(function()
        local auras = {}

        for index = 1, AURA_LIMIT do
            local name, expires, source

            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local data = C_UnitAuras.GetAuraDataByIndex(unit, index, AURA_FILTER)
                if type(data) ~= "table" then
                    break
                end
                name, expires = data.name, data.expirationTime
                -- Not fetched here, and not on this line: see castByPlayer.
                source = function() return data.sourceUnit end
            elseif UnitAura then
                -- name, icon, count, dispelType, duration, expirationTime, caster
                local found, _, _, _, _, expirationTime, caster =
                    UnitAura(unit, index, AURA_FILTER)
                if not found then
                    break
                end
                name, expires = found, expirationTime
                source = function() return caster end
            else
                break
            end

            -- First wins: a spell appearing twice is the same spell, and the
            -- one the client lists first is the one it considers current.
            if type(name) == "string" and auras[name] == nil then
                auras[name] = {
                    expires = expires or 0,
                    -- Judged here, where the source is still in reach: a
                    -- caller holding the gathered table has no way back to
                    -- it.
                    mine = castByPlayer(source),
                }
            end
        end

        return auras
    end, {})
end

--- Seconds left on `spellName` on `unit`, and whether this player is the one
-- who cast it. Nil when it is not there, never expires, or cannot be read.
--
-- nil rather than 0 throughout: a slot with nothing on it and a slot whose
-- buff has just run out both mean "no number to show", and neither is worth
-- distinguishing under a 22 pixel icon.
--
-- The second return is only ever read alongside a number -- there is nothing
-- to draw in whose colour otherwise -- so every path with no aura to report
-- leaves it nil.
function Spells.AuraRemaining(unit, spellName, auras)
    if type(spellName) ~= "string" or spellName == "" then
        return nil
    end

    auras = auras or Spells.HelpfulAuras(unit)

    local aura = auras[spellName]
    if not aura then
        return nil
    end

    -- HelpfulAuras guards the reading, not the reading's result: an expiry the
    -- client will not disclose is truthy, so it rides out of that guard in the
    -- table and arrives here untouched. Subtracting from it and comparing the
    -- result are both things it raises on, so they belong inside a guard of
    -- their own -- which costs one icon its timer instead of the refresh.
    local remaining = ns.Guarded(function()
        if aura.expires == 0 then
            return nil
        end

        local left = aura.expires - (GetTime and GetTime() or 0)
        return left > 0 and left or nil
    end, nil)

    if not remaining then
        return nil
    end

    return remaining, aura.mine
end

-- How many of a unit's auras the report below prints one by one. A report is
-- read in the chat frame, where a line per aura past the first handful is a
-- wall nobody scrolls back through; the count that follows them still covers
-- the whole walk.
local REPORT_LIMIT = 8

--- Render a value the client handed back, without assuming it can be
-- inspected at all.
--
-- Even tostring is an inspection as far as a secret value is concerned, so
-- the whole description happens inside a guard. A value that cannot be
-- described is itself the finding, and must not take the report down on its
-- way to being reported.
local function describe(value)
    return ns.Guarded(function()
        if value == nil then
            return "nil"
        end

        if type(value) == "string" then
            return string.format("%q", value)
        end

        return string.format("%s %s", type(value), tostring(value))
    end, "WITHHELD")
end

--- What an expiry says when you try to use it: how long is left, that it
-- never runs out, or that this client will not let tainted code do the
-- arithmetic. The third is the whole reason the report exists, and is what
-- an icon with no number under it looks like from in game.
local function describeRemaining(expires)
    return ns.Guarded(function()
        if expires == nil then
            return "-"
        end

        if expires == 0 then
            return "never"
        end

        return string.format("%.0fs", expires - (GetTime and GetTime() or 0))
    end, "WITHHELD")
end

--- One pass over `unit`'s auras under `filter`, reporting each index rather
-- than gathering them. Returns how many the client answered for.
--
-- Per index, and each read on its own guard: which index the walk stopped at,
-- and whether it stopped because the client ran out of auras or because it
-- raised, are distinctions HelpfulAuras is entitled to flatten into one empty
-- table and a report is not.
local function walkAuras(unit, filter, add)
    local found = 0

    for index = 1, AURA_LIMIT do
        -- "raised" as the unknown value rather than nil, because nil is what
        -- an honest end of the list looks like and the two must not read the
        -- same here.
        local entry = ns.Guarded(function()
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local data = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
                if type(data) ~= "table" then
                    return nil
                end
                return {
                    name = data.name,
                    expires = data.expirationTime,
                    -- Described in its own guard, inside this one: the read
                    -- raises on 1.60.1, and a report that goes down on the
                    -- field it was added to investigate reports nothing at
                    -- all. See castByPlayer.
                    source = ns.Guarded(function()
                        return describe(data.sourceUnit)
                    end, "RAISED ON READ"),
                }
            end

            if UnitAura then
                local name, _, _, _, _, expires, caster = UnitAura(unit, index, filter)
                if name == nil then
                    return nil
                end
                return {
                    name = name,
                    expires = expires,
                    source = ns.Guarded(function()
                        return describe(caster)
                    end, "RAISED ON READ"),
                }
            end

            return nil
        end, "raised")

        if entry == "raised" then
            add("  %s #%d: the client raised on the read", filter, index)
            return found
        end

        if entry == nil then
            break
        end

        found = found + 1
        if found <= REPORT_LIMIT then
            -- The caster among them, because who the client says cast an
            -- aura is what decides the colour of its number: a walk
            -- whose every source reads nil is the client declining to
            -- attribute anything, which is a different world from one that
            -- names a party member.
            add("  %s #%d: name=%s source=%s expires=%s remaining=%s", filter,
                index, describe(entry.name), entry.source,
                describe(entry.expires), describeRemaining(entry.expires))
        end
    end

    return found
end

--- What the timers can actually read on `unit`, layer by layer, as lines of
-- plain text.
--
-- Deliberately not HelpfulAuras with its answer printed. Flattening every way
-- a client can decline into one empty table is exactly right under a 22 pixel
-- icon and useless here: a blank timer looks the same whether the client
-- returned no auras at all, returned the buff under a name the slot does not
-- hold, or returned an expiry it will not let us subtract from. Those want
-- three different fixes, so the report walks the same ground keeping them
-- apart.
--
-- `spells` is what that unit's buttons are holding, so the last lines answer
-- the question actually being asked: this icon, on this person, why no
-- number.
function Spells.Report(unit, spells)
    local lines = {}
    local function add(format, ...)
        lines[#lines + 1] = string.format(format, ...)
    end

    local api = "NONE"
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        api = "C_UnitAuras"
    elseif UnitAura then
        api = "UnitAura"
    end

    add("%s: api=%s exists=%s", unit, api, tostring(
        ns.Guarded(function() return not not UnitExists(unit) end, "WITHHELD")
    ))

    add("  %s: %d aura(s)", AURA_FILTER, walkAuras(unit, AURA_FILTER, add))

    -- Asked the narrow way as well, because that is the answer this client
    -- gets wrong: on your own unit it comes back empty however many auras the
    -- walk above found. A day when it does not is a day this file can go back
    -- to letting the client do the filtering.
    add("  HELPFUL|PLAYER: %d aura(s)", walkAuras(unit, "HELPFUL|PLAYER", add))

    local auras = Spells.HelpfulAuras(unit)
    local names = {}
    for name, aura in pairs(auras) do
        names[#names + 1] = aura.mine and name or (name .. " (not yours)")
    end
    table.sort(names)
    add("  HelpfulAuras: %d (%s)", #names, table.concat(names, ", "))

    for _, spell in ipairs(spells or {}) do
        local remaining, mine = Spells.AuraRemaining(unit, spell, auras)
        add("  %s: %s", spell, remaining
            and string.format("%.0fs%s", remaining, mine and "" or " (not yours)")
            or "no number")
    end

    return lines
end
