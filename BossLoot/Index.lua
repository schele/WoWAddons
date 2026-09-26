local addonName, ns = ...

-- Lookups over the generated data, built once at login.

local Index = {}
ns.Index = Index

ns.AddDefaults({
    -- Instance keys the player has hidden from the list: WoW Forever does
    -- not have every vanilla instance.
    hidden = {},
})

-- Item searches stop here; nobody reads past a screenful.
local MAX_ITEM_RESULTS = 50

-- itemID -> { { instance = key, boss = number | "trash" | "objects" }, ... }
local sources = {}
-- Every item id, in first-seen order, for search.
local allItems = {}
-- instance key -> its item ids, once each.
local itemsByInstance = {}

local function add(itemID, instanceKey, boss)
    if not sources[itemID] then
        sources[itemID] = {}
        table.insert(allItems, itemID)
    end
    table.insert(sources[itemID], { instance = instanceKey, boss = boss })

    local list = itemsByInstance[instanceKey]
    if not list.seen[itemID] then
        list.seen[itemID] = true
        table.insert(list, itemID)
    end
end

function Index.Build()
    sources, allItems, itemsByInstance = {}, {}, {}

    for _, instance in ipairs(ns.instances) do
        itemsByInstance[instance.key] = { seen = {} }

        for bossIndex, boss in ipairs(instance.bosses) do
            for _, entry in ipairs(boss.loot) do
                add(entry[1], instance.key, bossIndex)
            end
        end

        local notable = instance.notable or {}
        for _, which in ipairs({ "trash", "objects" }) do
            for _, entry in ipairs(notable[which] or {}) do
                add(entry[1], instance.key, which)
            end
        end
    end
end

function Index.IsHidden(key)
    return ns.db ~= nil and ns.db.hidden[key] == true
end

--- The visible instances of one kind, lowest level first.
function Index.Instances(kind)
    local list = {}
    for _, instance in ipairs(ns.instances) do
        if instance.kind == kind and not Index.IsHidden(instance.key) then
            table.insert(list, instance)
        end
    end

    table.sort(list, function(a, b)
        if a.levels[1] ~= b.levels[1] then
            return a.levels[1] < b.levels[1]
        end
        return a.name < b.name
    end)

    return list
end

function Index.Sources(itemID)
    return sources[itemID] or {}
end

function Index.ItemIDs(key)
    local list = itemsByInstance[key]
    local ids = {}
    for index = 1, list and #list or 0 do
        ids[index] = list[index]
    end
    return ids
end

local function visibleSources(itemID)
    local list = {}
    for _, source in ipairs(Index.Sources(itemID)) do
        if not Index.IsHidden(source.instance) then
            table.insert(list, source)
        end
    end
    return list
end

--- Instances and items whose names contain `text`, ignoring case.
-- `nameOf(itemID)` returns an item's name, or nil when the client has not
-- loaded it: search can only find items the client has seen.
function Index.Search(text, nameOf)
    local result = { instances = {}, items = {} }
    local needle = (text or ""):lower():match("^%s*(.-)%s*$")
    if #needle < 2 then
        return result
    end

    for _, instance in ipairs(ns.instances) do
        if not Index.IsHidden(instance.key) and instance.name:lower():find(needle, 1, true) then
            table.insert(result.instances, instance)
        end
    end

    for _, itemID in ipairs(allItems) do
        local name = nameOf(itemID)
        if name and name:lower():find(needle, 1, true) then
            local where = visibleSources(itemID)
            if #where > 0 then
                table.insert(result.items, { id = itemID, name = name, sources = where })
                if #result.items >= MAX_ITEM_RESULTS then
                    break
                end
            end
        end
    end

    table.sort(result.items, function(a, b) return a.name < b.name end)
    return result
end

ns.OnLogin(Index.Build)
