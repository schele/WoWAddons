local addonName, ns = ...

-- Turns a gather into a place: a loot window from a GameObject that is a
-- listed herb or vein, or that opens just after the player's Mining or
-- Herbalism cast. The object's entry is the sixth field of the loot's source
-- GUID; the place is where the player stands.

local Recorder = {}
ns.Recorder = Recorder

-- The gather spells, by the ID whose name the game gives them: mining a vein
-- casts 2576, named "Mining" like 2575 (probed 2026-09-28). The herb cast is
-- expected to be named "Herbalism" like 2366; listed herbs count regardless.
Recorder.SPELLS = { [2575] = "ore", [2366] = "herb" }
-- How long after a gather cast its loot window can open, in seconds.
Recorder.SPELL_WINDOW = 3
-- A place gathered again within this many seconds is the same visit: a vein
-- is mined several times, each with its own loot window.
Recorder.VISIT = 60
-- How far from an earlier place of the same entry a gather joins it, in yards.
Recorder.REACH = 15

function Recorder.EntryFromGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local entry = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return entry and tonumber(entry)
end

local function spellName(id)
    return ns.Guarded(function()
        if C_Spell and C_Spell.GetSpellName then
            return C_Spell.GetSpellName(id)
        end
        return (GetSpellInfo(id))
    end)
end

-- Spell name -> kind, read from the game the first time it has them.
local kindByName

local function kindOfSpell(spellID)
    if Recorder.SPELLS[spellID] then
        return Recorder.SPELLS[spellID]
    end
    if not kindByName then
        local names, any = {}, false
        for id, kind in pairs(Recorder.SPELLS) do
            local name = spellName(id)
            if name then
                names[name] = kind
                any = true
            end
        end
        kindByName = any and names or nil
    end
    local name = kindByName and spellName(spellID)
    return name and kindByName[name]
end

local lastKind, lastCast

function Recorder.SpellSucceeded(unit, spellID)
    if unit ~= "player" then
        return
    end
    local kind = kindOfSpell(spellID)
    if kind then
        lastKind, lastCast = kind, GetTime()
    end
end

--- The first loot slot's item: its ID and name, or nil if the client will not say.
local function lootItem()
    return ns.Guarded(function()
        local link = GetLootSlotLink(1)
        if type(link) ~= "string" then
            return nil
        end
        return { item = tonumber(link:match("item:(%d+)")), name = link:match("%[(.-)%]") }
    end)
end

-- Place key -> GetTime() of its last counted gather.
local lastSeen = {}

function Recorder.LootOpened()
    local entry = Recorder.EntryFromGUID(ns.Guarded(function()
        return (GetLootSourceInfo(1))
    end))
    if not entry then
        return
    end

    local now = GetTime()
    local listed = ns.Nodes[entry]
    local kind = listed and ns.Spawns.KINDS[listed.kind] and listed.kind or nil
    if not kind and lastCast and now - lastCast <= Recorder.SPELL_WINDOW then
        kind = lastKind
    end
    if not kind then
        return
    end

    local x, y, _, continent = UnitPosition("player")
    if type(x) ~= "number" or (continent ~= 0 and continent ~= 1) then
        return
    end

    local spawn = ns.Spawns.Nearest(continent, entry, x, y, Recorder.REACH)
    if spawn then
        if lastSeen[spawn.key] and now - lastSeen[spawn.key] < Recorder.VISIT then
            return
        end
    else
        local point = { continent = continent, entry = entry, kind = kind, count = 0 }
        if not listed then
            local loot = lootItem()
            if loot then
                point.item, point.itemName = loot.item, loot.name
            end
        end
        spawn = ns.Spawns.AddPoint(continent, entry, x, y, point)
        point.x, point.y = spawn.x, spawn.y
        ns.db.gathered[spawn.key] = point
    end

    lastSeen[spawn.key] = now
    spawn.point.count = (spawn.point.count or 0) + 1
    spawn.point.last = time()
    ns.Refresh()
end

--- Forget the places in `members` (a spot's, as a pin shows them): out of
-- the saved gathers and off both maps.
function Recorder.Forget(members)
    for _, spawn in ipairs(members) do
        ns.db.gathered[spawn.key] = nil
        lastSeen[spawn.key] = nil
        ns.Spawns.Remove(spawn)
    end
    ns.Refresh()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        ns.Guarded(function() Recorder.SpellSucceeded(unit, spellID) end)
    else
        ns.Guarded(Recorder.LootOpened)
    end
end)

local resetAsked

ns.RegisterCommand("reset", "Forget every place you have gathered: /gmap reset gathered", function(rest)
    if rest ~= "gathered" then
        ns.Print("To forget every place you have gathered: /gmap reset gathered")
        return
    end

    local now = GetTime()
    if resetAsked and now - resetAsked <= 10 then
        resetAsked = nil
        for key in pairs(ns.db.gathered) do
            ns.db.gathered[key] = nil
        end
        lastSeen = {}
        ns.Spawns.Clear()
        ns.Print("Forgot every place you have gathered.")
        ns.Refresh()
        return
    end

    resetAsked = now
    ns.Print("This forgets every place you have gathered, on every character. "
        .. "Type /gmap reset gathered again within 10 seconds to do it.")
end)
