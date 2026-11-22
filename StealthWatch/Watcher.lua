local addonName, ns = ...

-- Noticing an enemy player going into stealth. The combat log is closed to
-- addons on WoW Forever, so this watches the units the client does show:
-- every nameplate as it appears, and the target. For each enemy player among
-- them a frame hears their casts.
--
-- A cast the client names is easy: Stealth, Vanish, Prowl, Shadowmeld or an
-- invisibility potion is reported at once, and anything else is not stealth.
-- But on Forever the client hides which spell anyone but the player cast. So
-- a hidden spell that was instant (no cast bar before it), followed within
-- WINDOW seconds by the caster going out of sight while alive, is reported
-- as stealth too: that is what stealthing looks like from outside. Walking
-- out of range comes with no cast, and a hearthstone has a cast time.

local Watcher = {}
ns.Watcher = Watcher

Watcher.WINDOW = 1.5     -- seconds from an instant cast to going out of sight
Watcher.QUIET = 10       -- seconds before the same player is reported again
Watcher.CAST_LIMIT = 30  -- a cast bar older than this is forgotten

-- The stealth spells, every rank, by their classic ids, with the English
-- name for a client that cannot say. The client's own name for each is what
-- counts: a cast with an id not here but one of these names is stealth too,
-- since WoW Forever has its own versions of some spells.
Watcher.SPELLS = {
    { 1784, "Stealth" }, { 1785, "Stealth" }, { 1786, "Stealth" }, { 1787, "Stealth" },
    { 1856, "Vanish" }, { 1857, "Vanish" },
    { 5215, "Prowl" }, { 6783, "Prowl" }, { 9913, "Prowl" },
    { 20580, "Shadowmeld" },
    { 3680, "Lesser Invisibility" },
    { 11392, "Invisibility" },
}

-- Casts heard this session: those whose spell the client named, and those
-- it hid. /sw probe tells them, to show which way this client goes.
Watcher.seen = { named = 0, hidden = 0 }

local byId = {}
for _, spell in ipairs(Watcher.SPELLS) do
    byId[spell[1]] = spell[2]
end

local tracked = {}      -- unit token -> who it shows: { guid, name, class, ..., castAt, startedAt }
local casters = {}      -- unit token -> the frame that hears its casts
local lastReported = {} -- guid -> GetTime() of its last report
local listeners = {}

--- Call fn(info) when an enemy player near goes into stealth. info is
-- { guid, name, class, classFile, level, race, spell, confirmed }: spell is
-- the client's name for it, or nil when the client hid it; confirmed is
-- true when the spell was named, false when it was inferred.
function ns.OnStealth(fn)
    table.insert(listeners, fn)
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id)
    end
    if GetSpellInfo then
        return (GetSpellInfo(id))
    end
end

local names -- the client's names for the stealth spells, as a set
local ordered -- and in the order of SPELLS, each once

local function learnNames()
    if names then
        return
    end
    names, ordered = {}, {}
    for _, spell in ipairs(Watcher.SPELLS) do
        local name = ns.Guarded(function() return spellName(spell[1]) end)
        if type(name) == "string" and name ~= "" and not names[name] then
            names[name] = true
            ordered[#ordered + 1] = name
        end
    end
end

--- The stealth spells this client knows, by its own names. Only names the
-- client gave are here: a spell it does not know is left out.
function Watcher.KnownNames()
    learnNames()
    local copy = {}
    for index, name in ipairs(ordered) do
        copy[index] = name
    end
    return copy
end

--- What a cast's spell id says: the spell's name if it is stealth, false
-- if it is something else, nil if the client hid it.
function Watcher.Classify(spellID)
    return ns.Guarded(function()
        if issecretvalue and issecretvalue(spellID) then
            return nil
        end
        if type(spellID) ~= "number" then
            return nil
        end
        local name = spellName(spellID)
        if byId[spellID] then
            return type(name) == "string" and name or byId[spellID]
        end
        learnNames()
        if type(name) == "string" and names[name] then
            return name
        end
        return false
    end, nil)
end

--- Who `unit` is, if an enemy player; nil for anyone else, or a unit the
-- client will not describe. The tests on the client's answers happen in
-- here: they may be secrets outside.
local function read(unit)
    return ns.Guarded(function()
        if not UnitExists(unit) or not UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then
            return nil
        end
        local class, classFile = UnitClass(unit)
        return {
            guid = UnitGUID(unit),
            name = (UnitName(unit)),
            class = class,
            classFile = classFile,
            level = tonumber(UnitLevel(unit)) or 0,
            race = (UnitRace(unit)),
        }
    end)
end

local function report(who, spell)
    local now = GetTime()
    local key = who.guid or who.name
    if key then
        if lastReported[key] and now - lastReported[key] < Watcher.QUIET then
            return
        end
        lastReported[key] = now
    end
    local info = {
        guid = who.guid, name = who.name, class = who.class, classFile = who.classFile,
        level = who.level, race = who.race, spell = spell, confirmed = spell ~= nil,
    }
    -- One listener that raises must not stop the rest.
    for _, fn in ipairs(listeners) do
        ns.Guarded(function() fn(info) end)
    end
end

--- A cast event heard for `unit`.
function Watcher.OnCast(unit, event, spellID)
    local who = tracked[unit]
    if not who then
        return
    end
    local now = GetTime()
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        who.startedAt = now
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        who.startedAt = nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local instant = not (who.startedAt and now - who.startedAt <= Watcher.CAST_LIMIT)
        who.startedAt, who.castAt = nil, nil
        local spell = Watcher.Classify(spellID)
        if spell == nil then
            Watcher.seen.hidden = Watcher.seen.hidden + 1
            if instant then
                who.castAt = now
            end
        else
            Watcher.seen.named = Watcher.seen.named + 1
            if spell then
                report(who, spell)
            end
        end
    end
end

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_SUCCEEDED",
}

local function casterFor(unit)
    local frame = casters[unit]
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event, _, _, spellID)
            Watcher.OnCast(unit, event, spellID)
        end)
        casters[unit] = frame
    end
    return frame
end

local function untrack(unit)
    tracked[unit] = nil
    if casters[unit] then
        casters[unit]:UnregisterAllEvents()
    end
end

--- Start watching whoever `unit` shows now, if an enemy player.
function Watcher.Track(unit)
    untrack(unit)
    local who = read(unit)
    if not who then
        return
    end
    tracked[unit] = who
    local frame = casterFor(unit)
    for _, event in ipairs(CAST_EVENTS) do
        ns.Guarded(function() frame:RegisterUnitEvent(event, unit) end)
    end
end

--- `unit` no longer shows who it did: report them if they went straight
-- after an instant hidden cast, and alive.
local function lost(unit)
    local who = tracked[unit]
    if not who then
        return
    end
    local dead = ns.Guarded(function() return UnitIsDeadOrGhost(unit) and true or false end, false)
    untrack(unit)
    if who.castAt and GetTime() - who.castAt <= Watcher.WINDOW and not dead then
        report(who, nil)
    end
end

--- The target changed. One that is simply gone went out of sight; one
-- swapped for someone else was let go by the player.
local function targetChanged()
    if tracked.target then
        local cleared = ns.Guarded(function() return not UnitExists("target") end, false)
        if cleared then
            lost("target")
        else
            untrack("target")
        end
    end
    Watcher.Track("target")
end

Watcher.MAX_PLATES = 40

--- Whether the client shows enemy nameplates: without them only the target
-- is watched.
function Watcher.EnemyPlatesShown()
    return ns.Guarded(function() return GetCVarBool("nameplateShowEnemies") and true or false end, true)
end

-- What C_Secrets.GetSpellCastSecrecy answers, in words.
local SECRECY = { [0] = "never hidden", [1] = "always hidden", [2] = "hidden at times" }

ns.RegisterCommand("probe", "Say what this client lets StealthWatch see", function()
    if Watcher.EnemyPlatesShown() then
        local range = ns.Guarded(function() return tonumber(GetCVar("nameplateMaxDistance")) end)
        ns.Print(string.format("Enemy nameplates: on, out to %s yards.", range and tostring(range) or "?"))
    else
        ns.Print("Enemy nameplates: off. Press V to show them.")
    end

    local known = Watcher.KnownNames()
    ns.Print(string.format("Stealth spells this client knows: %s.",
        #known > 0 and table.concat(known, ", ") or "none"))

    if not (C_Secrets and C_Secrets.GetSpellCastSecrecy) then
        ns.Print("This client hides no casts.")
    else
        -- One line for every name, by its first id.
        local parts, done = {}, {}
        for _, spell in ipairs(Watcher.SPELLS) do
            local name = Watcher.Classify(spell[1])
            if type(name) == "string" and not done[name] then
                done[name] = true
                local secrecy = ns.Guarded(function() return C_Secrets.GetSpellCastSecrecy(spell[1]) end)
                parts[#parts + 1] = string.format("%s %s", name, SECRECY[secrecy] or "unknown")
            end
        end
        ns.Print(string.format("Other players' casts: %s.", table.concat(parts, ", ")))
    end

    ns.Print(string.format("Casts heard since login: %d named, %d hidden.", Watcher.seen.named, Watcher.seen.hidden))
end)

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        Watcher.Track(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        lost(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        targetChanged()
    end
end)

ns.OnLogin(function()
    for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED" }) do
        ns.Guarded(function() frame:RegisterEvent(event) end)
    end
    -- Whoever is showing already: after a /reload the plates are up before
    -- this file hears of them.
    for index = 1, Watcher.MAX_PLATES do
        local unit = "nameplate" .. index
        if ns.Guarded(function() return UnitExists(unit) and true or false end, false) then
            Watcher.Track(unit)
        end
    end
    Watcher.Track("target")

    if not Watcher.EnemyPlatesShown() then
        ns.Print("Enemy nameplates are off, so StealthWatch only sees your target. Press V to show them.")
    end
end)
