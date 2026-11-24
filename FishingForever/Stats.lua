local addonName, ns = ...

-- A log of every cast that ended: a fish caught (and which), a fish that got
-- away, or a cast the game refused for too little skill. Each with when, who
-- and at what level, the Fishing skill, its cap and what a lure or gear
-- added, the zone and its level range, the subzone and where in it, and the
-- point a catch brought.
--
-- What WoW Forever does with fishing is not the old game's rule, and the log
-- is how to find out what it is: the stats under the skill bar add it up,
-- and players can send their saved-variables file in. Account-wide, so every
-- character's fishing counts; the newest LIMIT entries are kept.

local Stats = {}
ns.Stats = Stats

ns.AddDefaults({
    stats = {
        log = {},
        -- Names as the game gave them, for the log's item and map IDs.
        items = {},
        zones = {},
    },
})

-- Enough for a character's whole climb to 300 and then some.
Stats.LIMIT = 10000

local function stats()
    return ns.db.stats
end

local function rounded(value)
    return math.floor(value * 1000 + 0.5) / 1000
end

--- Where the player is fishing, and as whom, at what skill: the part of an
-- entry known when the cast goes out. `skill` is { rank, maxRank, bonus }.
function Stats.Context(skill)
    if not (ns.db and skill and skill.rank) then
        return nil
    end
    local context = {
        t = time and time() or 0,
        skill = skill.rank,
        max = skill.maxRank,
    }
    if skill.bonus and skill.bonus ~= 0 then
        context.bonus = skill.bonus
    end
    ns.Guarded(function()
        context.who = (UnitName("player"))
        context.lvl = UnitLevel("player")
    end)
    ns.Guarded(function()
        local id = C_Map.GetBestMapForUnit("player")
        if type(id) ~= "number" then
            return
        end
        context.zone = id
        local info = C_Map.GetMapInfo(id)
        if info and info.name then
            stats().zones[id] = info.name
        end
        local low, high = C_Map.GetMapLevels(id)
        if type(low) == "number" and low > 0 then
            context.zlo, context.zhi = low, high
        end
        local position = C_Map.GetPlayerMapPosition(id, "player")
        if position then
            local x, y = position:GetXY()
            if x and y then
                context.x, context.y = rounded(x), rounded(y)
            end
        end
    end)
    ns.Guarded(function()
        local sub = GetSubZoneText and GetSubZoneText()
        if type(sub) == "string" and sub ~= "" then
            context.sub = sub
        end
    end)
    return context
end

--- The fish in the loot window open now: item ID -> how many. Names are
-- kept in the log's item list.
function Stats.ReadLoot()
    local fish = {}
    ns.Guarded(function()
        for slot = 1, GetNumLootItems() do
            local link = GetLootSlotLink(slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                local _, name, count = GetLootSlotInfo(slot)
                fish[id] = (fish[id] or 0) + (tonumber(count) or 1)
                if name then
                    stats().items[id] = name
                end
            end
        end
    end)
    return fish
end

--- Log how a cast ended: `out` is "caught", "away" or "refused"; `fish`
-- what a catch brought. Returns the entry, to mark a point on.
function Stats.Note(context, out, fish)
    if not context then
        return nil
    end
    local entry = {}
    for key, value in pairs(context) do
        entry[key] = value
    end
    entry.out = out
    if fish and next(fish) then
        entry.fish = fish
    end
    local log = stats().log
    log[#log + 1] = entry
    while #log > Stats.LIMIT do
        table.remove(log, 1)
    end
    if ns.StatsPanel and ns.StatsPanel.Refresh then
        ns.StatsPanel.Refresh()
    end
    return entry
end

--- Mark the catch `entry` as the one that raised the skill to `rank`.
function Stats.Point(entry, rank)
    if entry and entry.out == "caught" and not entry.point then
        entry.point = rank
        if ns.StatsPanel and ns.StatsPanel.Refresh then
            ns.StatsPanel.Refresh()
        end
    end
end

local function add(counts, key, amount)
    counts[key] = (counts[key] or 0) + amount
end

--- The zones fished, by map ID, the latest first.
function Stats.Zones()
    local latest = {}
    for _, entry in ipairs(stats().log) do
        if entry.zone then
            latest[entry.zone] = math.max(latest[entry.zone] or 0, entry.t or 0)
        end
    end
    local zones = {}
    for id in pairs(latest) do
        zones[#zones + 1] = id
    end
    table.sort(zones, function(a, b)
        if latest[a] ~= latest[b] then
            return latest[a] > latest[b]
        end
        return a < b
    end)
    return zones
end

--- A zone's log added up: its name and level range, the totals, the fish,
-- and a row for each skill, highest first. A row: { skill, caught, away,
-- refused, points, fish = { id -> n }, subs = { subzone -> casts },
-- bonus = { bonus -> casts }, levels = { character level -> casts } }.
function Stats.Zone(id)
    local zone = {
        id = id, name = stats().zones[id],
        caught = 0, away = 0, refused = 0, points = 0, fish = {}, rows = {},
    }
    local bySkill = {}
    for _, entry in ipairs(stats().log) do
        if entry.zone == id and entry.skill then
            local row = bySkill[entry.skill]
            if not row then
                row = {
                    skill = entry.skill, caught = 0, away = 0, refused = 0, points = 0,
                    fish = {}, subs = {}, bonus = {}, levels = {},
                }
                bySkill[entry.skill] = row
                zone.rows[#zone.rows + 1] = row
            end
            local key = entry.out == "caught" and "caught" or entry.out == "away" and "away" or "refused"
            row[key] = row[key] + 1
            zone[key] = zone[key] + 1
            if entry.point then
                row.points = row.points + 1
                zone.points = zone.points + 1
            end
            for fish, count in pairs(entry.fish or {}) do
                add(row.fish, fish, count)
                add(zone.fish, fish, count)
            end
            add(row.subs, entry.sub or "", 1)
            add(row.bonus, entry.bonus or 0, 1)
            if entry.lvl then
                add(row.levels, entry.lvl, 1)
            end
            if entry.zlo then
                zone.zlo, zone.zhi = entry.zlo, entry.zhi
            end
        end
    end
    table.sort(zone.rows, function(a, b) return a.skill > b.skill end)
    return zone
end

--- The casts in zone `id` that got as far as a bite, made at `skill` or
-- more (with the lure's bonus they had), and how many of them landed a fish.
function Stats.LandedFrom(id, skill)
    local casts, caught = 0, 0
    for _, entry in ipairs(stats().log) do
        if entry.zone == id and entry.skill and (entry.out == "caught" or entry.out == "away")
            and entry.skill + (entry.bonus or 0) >= skill then
            casts = casts + 1
            if entry.out == "caught" then
                caught = caught + 1
            end
        end
    end
    return casts, caught
end

-- Skills put together in a row of the stats: tens, on round numbers, so a
-- row does not move each time the skill does.
Stats.BAND = 10

--- A zone's rows (Stats.Zone) put together in tens of skill, highest first.
-- A band is a row's counts added up, plus `from` and `to`, the lowest and
-- highest skill fished in it; `perPoint`, the catches each point took there
-- (counting the skills a point came from); and `rule`, what the old game's
-- rule says a point takes at those skills. Both nil without a point.
function Stats.Bands(rows, size)
    size = size or Stats.BAND
    local bands, byKey = {}, {}
    local pointCatches, ruleCatches = {}, {}
    for _, row in ipairs(rows) do
        local key = math.floor(row.skill / size) * size
        local band = byKey[key]
        if not band then
            band = {
                key = key, from = row.skill, to = row.skill,
                caught = 0, away = 0, refused = 0, points = 0,
                fish = {}, subs = {}, bonus = {}, levels = {},
            }
            byKey[key] = band
            bands[#bands + 1] = band
            pointCatches[band], ruleCatches[band] = 0, 0
        end
        band.from = math.min(band.from, row.skill)
        band.to = math.max(band.to, row.skill)
        for _, field in ipairs({ "caught", "away", "refused", "points" }) do
            band[field] = band[field] + row[field]
        end
        for _, field in ipairs({ "fish", "subs", "bonus", "levels" }) do
            for key2, value in pairs(row[field] or {}) do
                add(band[field], key2, value)
            end
        end
        if row.points > 0 then
            pointCatches[band] = pointCatches[band] + row.caught
            ruleCatches[band] = ruleCatches[band] + ns.Skill.Guess(row.skill) * row.points
        end
    end
    for _, band in ipairs(bands) do
        if band.points > 0 then
            band.perPoint = pointCatches[band] / band.points
            band.rule = ruleCatches[band] / band.points
        end
    end
    table.sort(bands, function(a, b) return a.key > b.key end)
    return bands
end

--- An item's name, as the loot window gave it, or as the game knows it.
function Stats.ItemName(id)
    return stats().items[id]
        or ns.Guarded(function() return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) end)
        or ("item " .. id)
end

--- `counts` (key -> n) as "name n, name n", the most first. `name` names a key.
function Stats.List(counts, name)
    local keys = {}
    for key in pairs(counts) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = string.format("%s %d", name and name(key) or tostring(key), counts[key])
    end
    return table.concat(parts, ", ")
end
