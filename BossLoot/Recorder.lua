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
local REFRESH_DELAY = 0.5     -- seconds of loot gathered into one update of the lists
local CRAFTS_DELAY = 1        -- seconds of profession list updates gathered into one reading
local ROLL_WINDOW = 120       -- seconds after a fight that a roll is taken to be its boss's loot
local ROLL_DELAY = 2          -- seconds a roll waits, so the loot window it came from is seen first
local ROLL_MATCH = 65         -- seconds apart that a roll and a loot window holding its item are one drop:
                              -- a roll runs a minute, and the item is in its corpse until it ends
local BOSS_UNITS = 5          -- boss1 to boss5, the units the game gives a fight's bosses

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

-- An item's name, quality and kind, as the game describes it (`info`, looked
-- up here unless given; false for none); failing that, the name and quality
-- the loot window gave. Never a vanilla built-in copy: those are what WoW
-- Forever changed.
local function remember(itemID, name, quality, info)
    local items = recorded().items
    if info == nil then
        info = ns.LootRow.ItemInfo(itemID)
    end
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

-- A source is a creature or object in one place, "<kind>:<id>@<map>": one
-- chest or herb id can stand in several instances, and each keeps its own.
local function sourceFor(kind, id, where)
    local sources = recorded().sources
    local key = kind .. ":" .. id .. "@" .. (where.map or 0)
    local source = sources[key]
    if not source then
        source = { kind = kind, id = id, kills = 0, items = {} }
        sources[key] = source
    end
    source.map, source.instance, source.instanceType, source.zone =
        where.map, where.instance, where.instanceType, where.zone
    return source, key
end

-- The corpses looted before, and marking one that now has been.
local seenSet
local function seenIndex()
    if not seenSet then
        seenSet = {}
        for _, seen in ipairs(recorded().seen) do
            seenSet[seen] = true
        end
    end
    return seenSet
end

local function seenBefore(guid)
    return seenIndex()[guid] == true
end

local function markSeen(guid)
    local set, list = seenIndex(), recorded().seen
    if set[guid] then
        return
    end
    set[guid] = true
    table.insert(list, guid)
    if #list > SEEN_LIMIT then
        set[table.remove(list, 1)] = nil
    end
end

-- Bring the lists up to date after instance loot, once for a burst of it.
local refreshPending = false
local function listsChanged()
    if refreshPending then
        return
    end
    if not (C_Timer and C_Timer.After) then
        ns.Recordings.Changed()
        return
    end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshPending = false
        ns.Recordings.Changed()
    end)
end


-- A roll and a loot window holding its item are one drop. Each remembers
-- its side, itemID -> { at, key }: when, and the source it was recorded
-- under (the corpse or chest; the roll's own). A roll also keeps the boss
-- fight it followed, if any.
local recentLoot = {}
local recentRolls = {}

-- A corpse whose item a boss's roll was on is that boss, for good: its
-- loot, then and after, is the boss's.
local function markBoss(key, encounter)
    local source = key and encounter and recorded().sources[key]
    if source then
        source.encounter = encounter
        source.name = source.name or encounter
    end
end

-- The last boss fight won: its name, when, where, and whether a roll has
-- counted it as a kill yet.
local lastEncounter
-- The fight going on: the creature ids of the bosses the game has shown,
-- each with its name where the client gives it.
local fight

-- A unit's creature id, or nil: not a creature, or a GUID kept secret.
local function creatureOf(unit)
    return ns.Guarded(function()
        local kind, id = Recorder.ParseGUID(UnitGUID(unit))
        return kind == "npc" and id or nil
    end, nil)
end

-- A unit's name, or nil where the client keeps it secret: comparing a
-- secret raises, so one never gets saved.
local function nameOf(unit)
    return ns.Guarded(function()
        local name = UnitName(unit)
        if type(name) == "string" and name ~= "" then
            return name
        end
        return nil
    end, nil)
end

-- Note the bosses the game shows for the fight going on.
local function readBossUnits()
    if not (UnitGUID and fight) then
        return
    end
    for index = 1, BOSS_UNITS do
        local unit = "boss" .. index
        local id = creatureOf(unit)
        if id then
            fight.bosses[id] = fight.bosses[id] or (UnitName and nameOf(unit)) or false
        end
    end
end

--- A boss fight started (ENCOUNTER_START), or its bosses changed
-- (INSTANCE_ENCOUNTER_ENGAGE_UNIT): note the bosses the game shows.
function Recorder.EncounterStarted()
    fight = { bosses = {} }
    readBossUnits()
end

function Recorder.BossesChanged()
    readBossUnits()
end

-- What /bl probe says of boss fights: the last one ended, and how many of
-- its bosses could be read.
local lastFight

--- A boss fight ended (ENCOUNTER_END). A won one marks the bosses the game
-- showed as that fight's, for good: their corpses' loot is the boss's
-- however long after it is looted. A boss looted within a minute, by a name
-- that matches, is marked too, and a roll within two minutes is its loot.
function Recorder.EncounterEnded(name, success)
    fight = fight or { bosses = {} }
    readBossUnits()
    local won = success == 1 or success == true
    local count = 0
    for _ in pairs(fight.bosses) do
        count = count + 1
    end
    lastFight = { name = name, read = count }

    if won and recorded() then
        local where = whereNow()
        lastEncounter = { name = name, at = now(), map = where.map }
        for id, bossName in pairs(fight.bosses) do
            local source = sourceFor("npc", id, where)
            source.encounter = name
            source.name = source.name or bossName or nil
        end
        if count > 0 and (where.instanceType == "party" or where.instanceType == "raid") then
            listsChanged()
        end
    end
    fight = nil
end

local function encounterFor(name)
    if lastEncounter and name == lastEncounter.name and now() - lastEncounter.at <= ENCOUNTER_WINDOW then
        return lastEncounter.name
    end
    return nil
end

-- The units a looted corpse can be: the target, the corpse under the mouse,
-- and the one the interact key picked.
local CORPSE_UNITS = { "target", "mouseover", "softinteract" }

local function corpseName(guid)
    if not (UnitGUID and UnitName) then
        return nil
    end
    for _, unit in ipairs(CORPSE_UNITS) do
        local isCorpse = ns.Guarded(function() return UnitGUID(unit) == guid end, false)
        if isCorpse then
            return nameOf(unit)
        end
    end
    return nil
end

-- A live creature's loot window is its pocket (Pick Pocket), not its loot.
local function livingTarget(guid)
    if not (UnitGUID and UnitIsDead) then
        return false
    end
    return ns.Guarded(function() return UnitGUID("target") == guid and not UnitIsDead("target") end, false)
end

--- A loot window opened (LOOT_OPENED): each corpse or chest it holds loot
-- from counts one kill or opening, the first time only, and its items once.
-- Everything is asked of the client first and recorded after, so a call that
-- fails partway leaves nothing half recorded: the loot is recorded when the
-- corpse is next opened.
function Recorder.LootOpened()
    if not (recorded() and GetNumLootItems and GetLootSlotLink and GetLootSourceInfo) then
        return
    end
    -- What was fished up is the water's, not a creature's or a chest's.
    if IsFishingLoot and ns.Guarded(IsFishingLoot, false) then
        return
    end
    local where = whereNow()

    local found, order, described = {}, {}, {}
    for slot = 1, GetNumLootItems() do
        local itemID = itemIDOf(GetLootSlotLink(slot))
        local from = { GetLootSourceInfo(slot) }
        if itemID and not described[itemID] then
            local name, quality
            if GetLootSlotInfo then
                local _
                _, name, _, _, quality = GetLootSlotInfo(slot)
            end
            -- The source the item is recorded under: its first corpse or chest.
            local kind, id = Recorder.ParseGUID(from[1])
            local key = kind and (kind .. ":" .. id .. "@" .. (where.map or 0)) or nil
            described[itemID] = { name = name, quality = quality, info = ns.LootRow.ItemInfo(itemID) or false, key = key }
        end
        for k = 1, #from, 2 do
            local guid = from[k]
            local entry = found[guid]
            if entry == nil then
                local kind, id = Recorder.ParseGUID(guid)
                if kind and not seenBefore(guid) and not livingTarget(guid) then
                    entry = { kind = kind, id = id, name = corpseName(guid), items = {} }
                    table.insert(order, guid)
                else
                    entry = false
                end
                found[guid] = entry
            end
            if entry and itemID then
                table.insert(entry.items, itemID)
            end
        end
    end

    for _, guid in ipairs(order) do
        local entry = found[guid]
        local source = sourceFor(entry.kind, entry.id, where)
        source.kills = source.kills + 1
        if entry.name then
            source.name = entry.name
            source.encounter = encounterFor(entry.name) or source.encounter
        end
        for _, itemID in ipairs(entry.items) do
            source.items[itemID] = (source.items[itemID] or 0) + 1
        end
        markSeen(guid)
    end
    local at = now()
    local sources = recorded().sources
    for itemID, item in pairs(described) do
        remember(itemID, item.name, item.quality, item.info)
        recentLoot[itemID] = { at = at, key = item.key }
        -- Rolled on already, and recorded under the roll: the corpse has it
        -- now, so the roll gives it back, and says whose corpse this is.
        local rolled = recentRolls[itemID]
        if rolled and at - rolled.at <= ROLL_MATCH and item.key then
            local rollSource = sources[rolled.key]
            local count = rollSource and rollSource.items[itemID]
            if count then
                rollSource.items[itemID] = count > 1 and count - 1 or nil
            end
            markBoss(item.key, rolled.encounter)
            recentRolls[itemID] = nil
        end
    end

    -- Loot in the open world changes no list.
    local inInstance = where.instanceType == "party" or where.instanceType == "raid"
    if #order > 0 and inInstance then
        listsChanged()
    end
end

-- Roll ids already taken, this session.
local rollsSeen = {}

-- A roll waits ROLL_DELAY first: if the player opened the corpse it came
-- from, the loot window has recorded the item, with its corpse, and the roll
-- only says whose corpse that is.
local function recordRoll(roll)
    local encounter = roll.encounter
    local looted = recentLoot[roll.itemID]
    if looted and math.abs(looted.at - roll.at) <= ROLL_MATCH then
        markBoss(looted.key, encounter and encounter.name)
        listsChanged()
        return
    end
    local source, key = sourceFor("roll", encounter and encounter.name or "trash", roll.where)
    recentRolls[roll.itemID] = { at = roll.at, key = key, encounter = encounter and encounter.name }
    if encounter then
        source.encounter, source.name = encounter.name, encounter.name
        -- The fight is the kill: once, however many rolls it brings.
        if not encounter.rolled then
            encounter.rolled = true
            source.kills = source.kills + 1
        end
    end
    source.items[roll.itemID] = (source.items[roll.itemID] or 0) + 1
    remember(roll.itemID, roll.name, roll.quality)
    listsChanged()
end

--- A roll started (START_LOOT_ROLL), as it does for everyone in the group
-- when one of them opens a corpse with something worth rolling on. The
-- client does not say which corpse: a roll within two minutes of a won boss
-- fight in this instance is that boss's loot, any other the instance's trash.
function Recorder.RollStarted(rollID)
    if not (recorded() and GetLootRollItemLink) or rollID == nil or rollsSeen[rollID] then
        return
    end
    local where = whereNow()
    if not (where.instanceType == "party" or where.instanceType == "raid") then
        return
    end
    local itemID = ns.Guarded(function() return itemIDOf(GetLootRollItemLink(rollID)) end, nil)
    if not itemID then
        return
    end
    rollsSeen[rollID] = true

    -- The roll's own name and quality, for an item the game has not
    -- described yet; a secret one raises on the checks and is left out.
    local name, quality
    if GetLootRollItemInfo then
        ns.Guarded(function()
            local _, rolledName, _, rolledQuality = GetLootRollItemInfo(rollID)
            if type(rolledName) == "string" and rolledName ~= "" and type(rolledQuality) == "number" and rolledQuality >= 0 then
                name, quality = rolledName, rolledQuality
            end
        end)
    end
    local at = now()
    local encounter = lastEncounter
    if not (encounter and encounter.map == where.map and at - encounter.at <= ROLL_WINDOW) then
        encounter = nil
    end
    local roll = { itemID = itemID, name = name, quality = quality, at = at, where = where, encounter = encounter }
    if C_Timer and C_Timer.After then
        C_Timer.After(ROLL_DELAY, function() recordRoll(roll) end)
    else
        recordRoll(roll)
    end
end

--- A quest window (QUEST_DETAIL, QUEST_COMPLETE): its fixed and choice
-- reward items, its title, and the faction of the one who saw it.
function Recorder.QuestShown()
    if not (recorded() and GetQuestID and GetQuestItemLink) then
        return
    end
    local questID = GetQuestID()
    if not questID or questID == 0 then
        return
    end
    local quests = recorded().quests
    local quest = quests[questID] or {}
    quest.title = GetTitleText and GetTitleText() or quest.title
    quest.faction = UnitFactionGroup and UnitFactionGroup("player") or quest.faction
    local function collect(kind, count)
        local ids = {}
        for index = 1, count do
            local itemID = itemIDOf(GetQuestItemLink(kind, index))
            if itemID then
                table.insert(ids, itemID)
                remember(itemID)
            end
        end
        return ids
    end
    local rewards = collect("reward", GetNumQuestRewards and GetNumQuestRewards() or 0)
    local choices = collect("choice", GetNumQuestChoices and GetNumQuestChoices() or 0)
    if #rewards > 0 then quest.rewards = rewards end
    if #choices > 0 then quest.choices = choices end
    quests[questID] = quest
end

-- A merchant item's price and how many the price buys: the newer call
-- (C_MerchantFrame), or the old one.
local function merchantPrice(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            return info.price, info.stackCount
        end
    end
    if GetMerchantItemInfo then
        local _, _, price, count = GetMerchantItemInfo(index)
        return price, count
    end
    return nil
end

--- A merchant window (MERCHANT_SHOW): what it sells, and for how much.
function Recorder.MerchantShown()
    if not (recorded() and GetMerchantNumItems and GetMerchantItemLink and UnitGUID) then
        return
    end
    local kind, id = Recorder.ParseGUID(UnitGUID("npc"))
    if kind ~= "npc" then
        return
    end
    local merchants = recorded().merchants
    local key = "npc:" .. id
    local merchant = merchants[key] or { items = {} }
    merchant.name = UnitName and UnitName("npc") or merchant.name
    merchant.zone = GetRealZoneText and GetRealZoneText() or merchant.zone
    for index = 1, GetMerchantNumItems() do
        local itemID = itemIDOf(GetMerchantItemLink(index))
        if itemID then
            local price, count = merchantPrice(index)
            merchant.items[itemID] = { price = price, count = count }
            remember(itemID)
        end
    end
    merchants[key] = merchant
end

-- The open profession's name and what its recipes make: the newer
-- profession calls (C_TradeSkillUI, a recipe's schematic or item link), or
-- the old ones. A recipe that makes no item (an enchant) gives none.
local function craftsNow()
    local ui = C_TradeSkillUI
    if ui and ui.GetAllRecipeIDs then
        local profession
        if ui.GetBaseProfessionInfo then
            local info = ui.GetBaseProfessionInfo()
            profession = info and info.professionName
        end
        if (not profession or profession == "") and ui.GetTradeSkillLine then
            local _, name = ui.GetTradeSkillLine()
            profession = name
        end
        local items = {}
        for _, recipeID in ipairs(ui.GetAllRecipeIDs() or {}) do
            local itemID
            if ui.GetRecipeSchematic then
                local schematic = ui.GetRecipeSchematic(recipeID, false)
                itemID = schematic and schematic.outputItemID
            end
            if not itemID and ui.GetRecipeItemLink then
                itemID = itemIDOf(ui.GetRecipeItemLink(recipeID))
            end
            if itemID then
                table.insert(items, itemID)
            end
        end
        return profession, items
    end
    if GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillItemLink then
        local items = {}
        for index = 1, GetNumTradeSkills() do
            local _, skillType = GetTradeSkillInfo(index)
            if skillType ~= "header" then
                local itemID = itemIDOf(GetTradeSkillItemLink(index))
                if itemID then
                    table.insert(items, itemID)
                end
            end
        end
        return GetTradeSkillLine(), items
    end
    return nil
end

--- A profession window (TRADE_SKILL_SHOW, and its list updates): what each
-- of its recipes makes.
function Recorder.TradeSkillShown()
    if not recorded() then
        return
    end
    local profession, items = craftsNow()
    if not profession or profession == "" or profession == "UNKNOWN" then
        return
    end
    local crafts = recorded().crafts
    local made = crafts[profession] or {}
    for _, itemID in ipairs(items) do
        made[itemID] = true
        remember(itemID)
    end
    crafts[profession] = made
end

-- A profession's list can come in after its window opens, and updates with
-- every search: read it once, a moment after the last update.
local craftsPending = false
local function craftsLater()
    if craftsPending or not (C_Timer and C_Timer.After) then
        return
    end
    craftsPending = true
    C_Timer.After(CRAFTS_DELAY, function()
        craftsPending = false
        Recorder.TradeSkillShown()
    end)
end

--- How much the player has recorded.
function Recorder.Counts()
    local data = recorded()
    local counts = { sources = 0, bosses = 0, items = 0, quests = 0, merchants = 0, professions = 0 }
    for _, source in pairs(data.sources) do
        counts.sources = counts.sources + 1
        if source.encounter then counts.bosses = counts.bosses + 1 end
    end
    for _ in pairs(data.items) do counts.items = counts.items + 1 end
    for _ in pairs(data.quests) do counts.quests = counts.quests + 1 end
    for _ in pairs(data.merchants) do counts.merchants = counts.merchants + 1 end
    for _ in pairs(data.crafts) do counts.professions = counts.professions + 1 end
    return counts
end

-- The calls the recorder (and the gear finder after it) uses. "A|B": either
-- will do -- newer clients have some under C_ namespaces instead.
local PROBED = {
    "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo", "GetInstanceInfo",
    "GetRealZoneText", "UnitGUID", "UnitName", "UnitIsDead", "IsFishingLoot",
    "GetQuestID", "GetTitleText", "GetNumQuestRewards", "GetNumQuestChoices", "GetQuestItemLink",
    "UnitFactionGroup", "GetMerchantNumItems", "GetMerchantItemLink",
    "GetMerchantItemInfo|C_MerchantFrame.GetItemInfo",
    "GetTradeSkillLine|C_TradeSkillUI.GetBaseProfessionInfo|C_TradeSkillUI.GetTradeSkillLine",
    "GetNumTradeSkills|C_TradeSkillUI.GetAllRecipeIDs",
    "GetTradeSkillInfo|C_TradeSkillUI.GetAllRecipeIDs",
    "GetTradeSkillItemLink|C_TradeSkillUI.GetRecipeSchematic|C_TradeSkillUI.GetRecipeItemLink",
    "GetItemStats|C_Item.GetItemStats",
    "GetLootRollItemLink",
}

local function present(name)
    local namespace, field = name:match("^([%w_]+)%.([%w_]+)$")
    if namespace then
        local space = _G[namespace]
        return type(space) == "table" and space[field] ~= nil
    end
    return _G[name] ~= nil
end

ns.RegisterCommand("probe", "Check this client has what the recorder needs", function()
    local missing = {}
    for _, entry in ipairs(PROBED) do
        local found = false
        for name in entry:gmatch("[^|]+") do
            found = found or present(name)
        end
        if not found then
            table.insert(missing, (entry:match("^[^|]+")))
        end
    end
    if #missing == 0 then
        ns.Print("Everything the recorder needs is here.")
    else
        ns.Print("This client is missing: " .. table.concat(missing, ", "))
    end
    -- Whether this client says when a boss fight ends, and shows its bosses.
    if lastFight then
        ns.Print(string.format("Last boss fight: %s, %d boss%s read.", tostring(lastFight.name),
            lastFight.read, lastFight.read == 1 and "" or "es"))
    else
        ns.Print("No boss fight seen since you logged in.")
    end
end)

ns.RegisterCommand("recorded", "Show how much you have recorded", function()
    local c = Recorder.Counts()
    ns.Print(string.format(
        "Recorded: %d creatures and objects (%d named bosses), %d items; %d quests, %d merchants, %d professions.",
        c.sources, c.bosses, c.items, c.quests, c.merchants, c.professions))
end)

ns.OnLogin(function()
    local data = recorded()
    if not data.recorder then
        local stamp = time and time() or 0
        data.recorder = string.format("%08x%04x", math.random(0, 0x7fffffff), stamp % 0x10000)
    end
end)

local handlers = {
    LOOT_OPENED = function() Recorder.LootOpened() end,
    ENCOUNTER_START = function() Recorder.EncounterStarted() end,
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = function() Recorder.BossesChanged() end,
    ENCOUNTER_END = function(_, name, _, _, success) Recorder.EncounterEnded(name, success) end,
    START_LOOT_ROLL = function(rollID) Recorder.RollStarted(rollID) end,
    QUEST_DETAIL = function() Recorder.QuestShown() end,
    QUEST_COMPLETE = function() Recorder.QuestShown() end,
    MERCHANT_SHOW = function() Recorder.MerchantShown() end,
    TRADE_SKILL_SHOW = function() Recorder.TradeSkillShown() end,
    TRADE_SKILL_UPDATE = function() craftsLater() end,
    TRADE_SKILL_LIST_UPDATE = function() craftsLater() end,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end
local reported = false
events:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if not handler then
        return
    end
    local ok, problem = pcall(handler, ...)
    if not ok and not reported then
        reported = true
        ns.Print("The loot recorder skipped something it could not read: " .. tostring(problem))
    end
end)

Recorder.handlers = handlers
Recorder.events = events
