local addonName, ns = ...

-- What has been recorded in WoW Forever: the player's own recordings and any
-- baked into the release, merged, and laid onto BossLoot's instances.

local Recordings = {}
ns.Recordings = Recordings

local RECORDED_KEY = "rec:"

-- Every recorder's recordings: the player's own, and those baked into the
-- release but the baked copy of the player's own. Remembered until the next
-- change.
local recorders

local function all()
    if not recorders then
        recorders = {}
        local own = ns.db and ns.db.recorded
        if own then
            table.insert(recorders, own)
        end
        for recorder, data in pairs(ns.bakedRecordings or {}) do
            if not (own and recorder == own.recorder) then
                table.insert(recorders, data)
            end
        end
    end
    return recorders
end

--- Every recorder's loot sources, merged by kind and id: kills and item
-- counts summed, names and places from whichever recorder has them.
function Recordings.Sources()
    local merged = {}
    for _, data in ipairs(all()) do
        for key, source in pairs(data.sources or {}) do
            local into = merged[key]
            if not into then
                into = { kind = source.kind, id = source.id, kills = 0, items = {} }
                merged[key] = into
            end
            into.name = into.name or source.name
            into.encounter = into.encounter or source.encounter
            into.map = into.map or source.map
            into.instance = into.instance or source.instance
            into.instanceType = into.instanceType or source.instanceType
            into.zone = into.zone or source.zone
            into.kills = into.kills + (source.kills or 0)
            for itemID, count in pairs(source.items or {}) do
                into.items[itemID] = (into.items[itemID] or 0) + count
            end
        end
    end
    return merged
end

--- A recorded item's name, quality and kind, from any recorder, or nil.
function Recordings.Item(itemID)
    for _, data in ipairs(all()) do
        local item = data.items and data.items[itemID]
        if item then
            return item
        end
    end
    return nil
end

local function contains(list, value)
    for _, each in ipairs(list or {}) do
        if each == value then
            return true
        end
    end
    return false
end

local function bossFor(instance, source)
    for _, boss in ipairs(instance.bosses) do
        if (source.kind == "npc" and contains(boss.npcs, source.id))
            or (source.kind == "object" and contains(boss.objects, source.id))
            or (source.name ~= nil and source.name == boss.name)
            or (source.encounter ~= nil and source.encounter == boss.name) then
            return boss
        end
    end
    return nil
end

-- Notable, as the vanilla trash and chest lists count it: rare or better, a
-- recipe or a key. An item not described yet counts, rather than hiding.
local function notable(itemID)
    local info = ns.LootRow.ItemInfo(itemID)
    if not info then
        return true
    end
    return (info.quality or 0) >= 3
        or info.itemType == ns.ItemData.ClassName(9)
        or info.itemType == ns.ItemData.ClassName(13)
end

-- Grey junk, which the vanilla boss lists leave out too. An item not
-- described yet stays.
local function junk(itemID)
    local info = ns.LootRow.ItemInfo(itemID)
    return info ~= nil and info.quality == 0
end

local function byCount(a, b)
    if a[2] ~= b[2] then
        return a[2] > b[2]
    end
    return a[1] < b[1]
end

-- Add `count` of an item to a list, once per item, noting where it came from.
local function addTo(list, index, itemID, count, sourceName)
    local entry = index[itemID]
    if not entry then
        entry = { itemID, 0, {} }
        index[itemID] = entry
        table.insert(list, entry)
    end
    entry[2] = entry[2] + count
    if sourceName and not contains(entry[3], sourceName) then
        table.insert(entry[3], sourceName)
    end
end

-- Take away what the last Apply laid on, and the recorded instances.
local function clear()
    for position = #ns.instances, 1, -1 do
        local instance = ns.instances[position]
        if instance.recorded then
            table.remove(ns.instances, position)
            ns.instanceByKey[instance.key] = nil
        else
            instance.recordedNotable = nil
            for _, boss in ipairs(instance.bosses) do
                boss.recorded, boss.recordedKills = nil, nil
            end
        end
    end
end

local function recordedInstance(source)
    return {
        key = RECORDED_KEY .. source.map,
        name = source.instance or ("Instance " .. source.map),
        kind = source.instanceType == "raid" and "raid" or "dungeon",
        recorded = true,
        bosses = {},
        notable = { trash = {}, objects = {} },
    }
end

--- Lay the recordings onto the instances: each boss's loot and kills, the
-- notable trash and chest finds, and instances BossLoot does not know.
function Recordings.Apply()
    clear()
    local byMap = {}
    for _, instance in ipairs(ns.instances) do
        if instance.mapID then
            byMap[instance.mapID] = instance
        end
    end

    local sources = Recordings.Sources()
    local keys = {}
    for key in pairs(sources) do
        table.insert(keys, key)
    end
    table.sort(keys)

    local indexes = {}
    local function list(owner)
        indexes[owner] = indexes[owner] or {}
        return owner, indexes[owner]
    end

    for _, key in ipairs(keys) do
        local source = sources[key]
        local inInstance = source.instanceType == "party" or source.instanceType == "raid"
        if source.map and inInstance then
            local instance = byMap[source.map]
            if not instance then
                instance = recordedInstance(source)
                table.insert(ns.instances, instance)
                ns.instanceByKey[instance.key] = instance
                byMap[source.map] = instance
            end
            local boss = bossFor(instance, source)
            if not boss and instance.recorded and source.encounter then
                boss = { name = source.encounter, loot = {} }
                table.insert(instance.bosses, boss)
            end
            if boss then
                boss.recorded = boss.recorded or {}
                boss.recordedKills = math.max(boss.recordedKills or 0, source.kills)
                local entries, index = list(boss.recorded)
                for itemID, count in pairs(source.items) do
                    if not junk(itemID) then
                        addTo(entries, index, itemID, count)
                    end
                end
            else
                instance.recordedNotable = instance.recordedNotable or { trash = {}, objects = {} }
                local which = source.kind == "object" and "objects" or "trash"
                local entries, index = list(instance.recordedNotable[which])
                for itemID, count in pairs(source.items) do
                    if notable(itemID) then
                        addTo(entries, index, itemID, count, source.name)
                    end
                end
            end
        end
    end

    for entries in pairs(indexes) do
        table.sort(entries, byCount)
    end

    -- A recorded instance with no named boss and nothing notable yet (only
    -- money, or common finds) has nothing to show: it is listed once it does.
    for position = #ns.instances, 1, -1 do
        local instance = ns.instances[position]
        local notable = instance.recordedNotable
        local empty = #instance.bosses == 0
            and (not notable or (#notable.trash == 0 and #notable.objects == 0))
        if instance.recorded and empty then
            table.remove(ns.instances, position)
            ns.instanceByKey[instance.key] = nil
        end
    end
end

--- Something was recorded, or the saved recordings are in: bring the
-- instances, the index and an open window up to date.
function Recordings.Changed()
    recorders = nil
    Recordings.Apply()
    if ns.Index and ns.Index.Build then
        ns.Index.Build()
    end
    local frame = ns.Window and ns.Window.Frame and ns.Window.Frame()
    if frame and frame:IsShown() then
        ns.Window.Refresh()
    end
end

ns.OnLogin(Recordings.Changed)
