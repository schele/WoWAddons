local addonName, ns = ...

-- Recording what WoW Forever really has. WoW Forever reworked dungeon loot and
-- item stats, so the vanilla lists BossLoot ships with are only a guide; this
-- records, as the player plays, what each creature and chest drops, which
-- boss the game named when a fight ended, and (see below) quest rewards,
-- merchant goods and crafts. Every client call is checked for first: a client
-- without one records the rest.

local Recorder = {}
ns.Recorder = Recorder

ns.AddDefaults({
    recorded = { sources = {}, quests = {}, merchants = {}, crafts = {}, items = {}, seen = {} },
})

local SEEN_LIMIT = 500        -- corpses remembered, so a reopened one does not count again
local ENCOUNTER_WINDOW = 60   -- seconds after a fight that a looted creature can be its boss
local KINDS = { Creature = "npc", Vehicle = "npc", GameObject = "object" }

local function recorded()
    return ns.db and ns.db.recorded
end

local function now()
    return GetTime and GetTime() or 0
end

--- A GUID's kind and id: "npc", 6910 for a creature; "object", 5678 for a
-- game object; nil for anything else.
function Recorder.ParseGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local kind, id = guid:match("^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-")
    kind = KINDS[kind]
    if not kind then
        return nil
    end
    return kind, tonumber(id)
end

local function itemIDOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- An item's name, quality and kind, as the game describes it; failing that,
-- the name and quality the loot window gave. Never a vanilla built-in copy:
-- those are what WoW Forever changed.
local function remember(itemID, name, quality)
    local items = recorded().items
    local info = ns.LootRow.ItemInfo(itemID)
    if info and not info.builtIn then
        items[itemID] = { info.name, info.quality, info.itemType, info.itemSubType, info.equipLoc }
    elseif not items[itemID] and name then
        items[itemID] = { name, quality }
    end
end

local function whereNow()
    local where = { zone = GetRealZoneText and GetRealZoneText() or nil }
    if GetInstanceInfo then
        local name, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
        where.instance, where.instanceType, where.map = name, instanceType, mapID
    end
    return where
end

local function sourceFor(kind, id, where)
    local sources = recorded().sources
    local key = kind .. ":" .. id
    local source = sources[key]
    if not source then
        source = { kind = kind, id = id, kills = 0, items = {} }
        sources[key] = source
    end
    source.map, source.instance, source.instanceType, source.zone =
        where.map, where.instance, where.instanceType, where.zone
    return source
end

-- Whether a corpse was looted before; remembers it if not.
local seenSet
local function alreadySeen(guid)
    local list = recorded().seen
    if not seenSet then
        seenSet = {}
        for _, seen in ipairs(list) do
            seenSet[seen] = true
        end
    end
    if seenSet[guid] then
        return true
    end
    seenSet[guid] = true
    table.insert(list, guid)
    if #list > SEEN_LIMIT then
        seenSet[table.remove(list, 1)] = nil
    end
    return false
end

local lastEncounter

--- A boss fight ended (ENCOUNTER_END): a won one's boss, looted within a
-- minute, is marked as that encounter's boss.
function Recorder.EncounterEnded(name, success)
    if success == 1 or success == true then
        lastEncounter = { name = name, at = now() }
    end
end

local function encounterFor(name)
    if lastEncounter and name == lastEncounter.name and now() - lastEncounter.at <= ENCOUNTER_WINDOW then
        return lastEncounter.name
    end
    return nil
end

local function targetName(guid)
    if UnitGUID and UnitName and UnitGUID("target") == guid then
        return UnitName("target")
    end
    return nil
end

--- A loot window opened (LOOT_OPENED): each corpse or chest it holds loot
-- from counts one kill or opening, the first time only, and its items once.
function Recorder.LootOpened()
    if not (recorded() and GetNumLootItems and GetLootSlotLink and GetLootSourceInfo) then
        return
    end
    local where = whereNow()
    local counted, skipped = {}, {}
    local changed = false
    for slot = 1, GetNumLootItems() do
        local itemID = itemIDOf(GetLootSlotLink(slot))
        local from = { GetLootSourceInfo(slot) }
        for k = 1, #from, 2 do
            local guid = from[k]
            local source = counted[guid]
            if not source and not skipped[guid] then
                local kind, id = Recorder.ParseGUID(guid)
                if kind and not alreadySeen(guid) then
                    source = sourceFor(kind, id, where)
                    source.kills = source.kills + 1
                    local name = targetName(guid)
                    if name then
                        source.name = name
                        source.encounter = encounterFor(name) or source.encounter
                    end
                    counted[guid] = source
                    changed = true
                else
                    skipped[guid] = true
                end
            end
            if source and itemID then
                source.items[itemID] = (source.items[itemID] or 0) + 1
                local name, quality
                if GetLootSlotInfo then
                    local _
                    _, name, _, _, quality = GetLootSlotInfo(slot)
                end
                remember(itemID, name, quality)
            end
        end
    end
    if changed then
        ns.Recordings.Changed()
    end
end

ns.OnLogin(function()
    local data = recorded()
    if not data.recorder then
        local stamp = time and time() or 0
        data.recorder = string.format("%08x%04x", math.random(0, 0x7fffffff), stamp % 0x10000)
    end
end)

local handlers = {
    LOOT_OPENED = function() Recorder.LootOpened() end,
    ENCOUNTER_END = function(_, name, _, _, success) Recorder.EncounterEnded(name, success) end,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        handler(...)
    end
end)

Recorder.handlers = handlers
Recorder.events = events
