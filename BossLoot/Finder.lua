local addonName, ns = ...

-- What WoW Forever offers: the dungeons and raids in the game's group
-- finder, each with its name, level range and map. Laid onto the instances,
-- it lists those and no others, in the finder's names: an instance the
-- finder lists by wing (Scarlet Monastery's four) as one row per wing, and
-- one BossLoot does not know as a row of its own, filled in by recordings.
-- A client whose finder lists nothing keeps the whole vanilla list.

local Finder = {}
ns.Finder = Finder

local FINDER_KEY = "lfg:"

-- The word in a finder category's name for each kind of instance. The
-- finder's other categories (quests and zones, PvP) are not instances.
local KIND_WORDS = { dungeon = "dungeon", raid = "raid" }

local function positive(value)
    return type(value) == "number" and value > 0 and value or nil
end

local function categoryName(id)
    if C_LFGList.GetLfgCategoryInfo then
        local info = C_LFGList.GetLfgCategoryInfo(id)
        return type(info) == "table" and info.name or nil
    end
    if C_LFGList.GetCategoryInfo then
        return (C_LFGList.GetCategoryInfo(id))
    end
    return nil
end

local function kindOf(categoryID)
    local name = categoryName(categoryID)
    if type(name) ~= "string" then
        return nil
    end
    name = name:lower()
    for kind, word in pairs(KIND_WORDS) do
        if name:find(word, 1, true) then
            return kind
        end
    end
    return nil
end

local function activityOf(activityID, kind)
    local info = C_LFGList.GetActivityInfoTable(activityID)
    if type(info) ~= "table" then
        return nil
    end
    -- The short name where there is one, as the finder's own list shows it.
    local name = (type(info.shortName) == "string" and info.shortName ~= "") and info.shortName or info.fullName
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local low = positive(info.minLevelSuggestion) or positive(info.minLevel)
    local high = positive(info.maxLevelSuggestion)
    return {
        name = name,
        kind = kind,
        mapID = positive(info.mapID),
        levels = (low and high) and { low, high } or nil,
    }
end

--- The finder's dungeons and raids, each { name, kind, mapID, levels }
-- (mapID and levels nil where the finder has none). Empty on a client with
-- no group finder, or while it lists nothing.
function Finder.Read()
    if not (C_LFGList and C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableActivities
        and C_LFGList.GetActivityInfoTable) then
        return {}
    end
    return ns.Guarded(function()
        local list = {}
        for _, categoryID in ipairs(C_LFGList.GetAvailableCategories() or {}) do
            local kind = kindOf(categoryID)
            if kind then
                for _, activityID in ipairs(C_LFGList.GetAvailableActivities(categoryID) or {}) do
                    local activity = activityOf(activityID, kind)
                    if activity then
                        table.insert(list, activity)
                    end
                end
            end
        end
        return list
    end, {})
end

--- A name as words to compare: lower case, a leading "The" dropped,
-- anything but letters and digits a single space.
local function words(name)
    local text = (" " .. name:lower():gsub("[^%w]+", " ") .. " "):gsub("^ the ", " ")
    return text
end

-- The wing of `instance` an activity's name names, or nil.
local function wingNamed(instance, activity)
    local name = words(activity.name)
    for _, boss in ipairs(instance.bosses) do
        if boss.wing and name:find(words(boss.wing), 1, true) then
            return boss.wing
        end
    end
    return nil
end

-- Widen `levels` to take in `more`.
local function widen(levels, more)
    if not more then
        return levels
    end
    if not levels then
        return { more[1], more[2] }
    end
    return { math.min(levels[1], more[1]), math.max(levels[2], more[2]) }
end

local function add(instance)
    table.insert(ns.instances, instance)
    ns.instanceByKey[instance.key] = instance
end

-- Take away what the last Apply did: the rows it made gone, and the
-- instances back to their own names, levels and kinds.
local function clear()
    for position = #ns.instances, 1, -1 do
        local instance = ns.instances[position]
        if instance.fromFinder or instance.wingOf then
            table.remove(ns.instances, position)
            ns.instanceByKey[instance.key] = nil
        else
            if instance.own then
                instance.name, instance.levels, instance.kind = instance.own.name, instance.own.levels, instance.own.kind
                instance.own = nil
            end
            instance.notInFinder, instance.byWing = nil, nil
        end
    end
end

-- The row for one wing of `instance`: that wing's bosses, and the whole
-- instance's map and notable drops. Recordings.Apply hands it the instance's
-- recorded notable drops.
local function wingRow(instance, wing, activity)
    local bosses = {}
    for _, boss in ipairs(instance.bosses) do
        if boss.wing == wing then
            table.insert(bosses, boss)
        end
    end
    return {
        key = instance.key .. ":" .. wing,
        name = activity.name,
        kind = activity.kind,
        levels = activity.levels or instance.levels,
        wing = wing,
        wingOf = instance,
        bosses = bosses,
        map = instance.map,
        entrance = instance.entrance,
        notable = instance.notable,
    }
end

-- What each of the finder's activities was laid on, for /bl finder.
local matched = {}

--- Lay the finder's list onto the instances. Run before Recordings.Apply,
-- which fills in the instances the finder made.
function Finder.Apply()
    clear()
    matched = {}
    local activities = Finder.Read()
    Finder.activities = activities
    if #activities == 0 then
        return
    end

    local byMap, byName = {}, {}
    for _, instance in ipairs(ns.instances) do
        -- Instances made from recordings come and go with them; they are
        -- matched to the finder's rows when the recordings are laid on.
        if not instance.recorded then
            instance.notInFinder = true
            if instance.mapID then
                byMap[instance.mapID] = instance
            end
            byName[words(instance.name)] = instance
        end
    end

    local made = {}
    for index, activity in ipairs(activities) do
        local instance = (activity.mapID and byMap[activity.mapID]) or byName[words(activity.name)]
        local wing = instance and wingNamed(instance, activity)
        if wing then
            local key = instance.key .. ":" .. wing
            if not ns.instanceByKey[key] then
                add(wingRow(instance, wing, activity))
            end
            instance.byWing = true
            instance.notInFinder = nil
            matched[index] = string.format("%s, %s", instance.own and instance.own.name or instance.name, wing)
        elseif instance then
            matched[index] = instance.own and instance.own.name or instance.name
            if not instance.own then
                -- The finder's name, levels and kind, its own remembered.
                instance.own = { name = instance.name, levels = instance.levels, kind = instance.kind }
                instance.name, instance.kind = activity.name, activity.kind
                instance.levels = activity.levels or instance.levels
            else
                -- Listed twice: one row, wide enough for both.
                instance.levels = widen(instance.levels, activity.levels)
            end
            instance.notInFinder = nil
        else
            local key = FINDER_KEY .. (activity.mapID or words(activity.name):match("^ (.-) $"))
            local row = made[key]
            if row then
                row.levels = widen(row.levels, activity.levels)
            else
                row = {
                    key = key,
                    name = activity.name,
                    kind = activity.kind,
                    levels = activity.levels,
                    mapID = activity.mapID,
                    fromFinder = true,
                    bosses = {},
                    notable = { trash = {}, objects = {} },
                }
                made[key] = row
                add(row)
            end
        end
    end
end

--- Whether the finder leaves an instance off the list: it lists other
-- instances but not this one, or this one only by its wings. One the
-- finder leaves out is still listed once something was recorded there.
function Finder.LeavesOut(instance)
    if instance.byWing then
        return true
    end
    if not instance.notInFinder then
        return false
    end
    if instance.recordedNotable then
        return false
    end
    for _, boss in ipairs(instance.bosses) do
        if boss.recorded then
            return false
        end
    end
    return true
end

local function describe(activity)
    local text = activity.name
    if activity.levels then
        text = string.format("%s %d-%d", text, activity.levels[1], activity.levels[2])
    end
    if activity.mapID then
        text = string.format("%s, map %d", text, activity.mapID)
    end
    return text
end

ns.RegisterCommand("finder", "List the dungeons and raids the game's group finder offers", function()
    local activities = Finder.activities or {}
    if #activities == 0 then
        ns.Print("The group finder lists no dungeons or raids, so BossLoot lists every instance it knows.")
        return
    end
    local counts = { dungeon = 0, raid = 0 }
    for _, activity in ipairs(activities) do
        counts[activity.kind] = counts[activity.kind] + 1
    end
    ns.Print(string.format("The group finder lists %d dungeons and %d raids:", counts.dungeon, counts.raid))
    for index, activity in ipairs(activities) do
        ns.Print(string.format("  %s: %s", describe(activity), matched[index] or "new to BossLoot"))
    end
end)

-- The list as one string, to tell whether it changed.
local function signature(activities)
    local parts = {}
    for _, activity in ipairs(activities) do
        table.insert(parts, describe(activity) .. "/" .. activity.kind)
    end
    return table.concat(parts, "|")
end

local loggedIn = false
ns.OnLogin(function()
    loggedIn = true
end)

-- The finder may fill its lists in after login, and change them later.
-- The event comes often; the instances are laid out again only when the
-- list really changed.
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "LFG_LIST_AVAILABILITY_UPDATE")
events:SetScript("OnEvent", function()
    if loggedIn and signature(Finder.Read()) ~= signature(Finder.activities or {}) then
        ns.Recordings.Changed()
    end
end)
