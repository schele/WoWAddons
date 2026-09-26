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
    return source
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
    if not (UnitGUID and UnitName) then
        return nil
    end
    local isTarget = ns.Guarded(function() return UnitGUID("target") == guid end, false)
    if isTarget then
        return ns.Guarded(function() return UnitName("target") end, nil)
    end
    return nil
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
    local where = whereNow()

    local found, order, described = {}, {}, {}
    for slot = 1, GetNumLootItems() do
        local itemID = itemIDOf(GetLootSlotLink(slot))
        if itemID and not described[itemID] then
            local name, quality
            if GetLootSlotInfo then
                local _
                _, name, _, _, quality = GetLootSlotInfo(slot)
            end
            described[itemID] = { name = name, quality = quality, info = ns.LootRow.ItemInfo(itemID) or false }
        end
        local from = { GetLootSourceInfo(slot) }
        for k = 1, #from, 2 do
            local guid = from[k]
            local entry = found[guid]
            if entry == nil then
                local kind, id = Recorder.ParseGUID(guid)
                if kind and not seenBefore(guid) then
                    entry = { kind = kind, id = id, name = targetName(guid), items = {} }
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
    for itemID, item in pairs(described) do
        remember(itemID, item.name, item.quality, item.info)
    end

    if #order > 0 then
        ns.Recordings.Changed()
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
            local price = GetMerchantItemInfo and select(3, GetMerchantItemInfo(index)) or nil
            merchant.items[itemID] = { price = price }
            remember(itemID)
        end
    end
    merchants[key] = merchant
end

--- A profession window (TRADE_SKILL_SHOW, TRADE_SKILL_UPDATE): what each of
-- its recipes makes.
function Recorder.TradeSkillShown()
    if not (recorded() and GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillItemLink) then
        return
    end
    local profession = GetTradeSkillLine()
    if not profession or profession == "UNKNOWN" then
        return
    end
    local crafts = recorded().crafts
    local made = crafts[profession] or {}
    for index = 1, GetNumTradeSkills() do
        local _, skillType = GetTradeSkillInfo(index)
        if skillType ~= "header" then
            local itemID = itemIDOf(GetTradeSkillItemLink(index))
            if itemID then
                made[itemID] = true
                remember(itemID)
            end
        end
    end
    crafts[profession] = made
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

-- The calls the recorder (and the gear finder after it) uses.
local PROBED = {
    "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo", "GetInstanceInfo",
    "UnitGUID", "GetQuestID", "GetQuestItemLink", "GetMerchantItemLink", "GetMerchantItemInfo",
    "GetTradeSkillLine", "GetTradeSkillItemLink", "GetItemStats",
}

ns.RegisterCommand("probe", "Check this client has what the recorder needs", function()
    local missing = {}
    for _, name in ipairs(PROBED) do
        if not (_G[name] or (C_Item and C_Item[name])) then
            table.insert(missing, name)
        end
    end
    if #missing == 0 then
        ns.Print("Everything the recorder needs is here.")
    else
        ns.Print("This client is missing: " .. table.concat(missing, ", "))
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
    ENCOUNTER_END = function(_, name, _, _, success) Recorder.EncounterEnded(name, success) end,
    QUEST_DETAIL = function() Recorder.QuestShown() end,
    QUEST_COMPLETE = function() Recorder.QuestShown() end,
    MERCHANT_SHOW = function() Recorder.MerchantShown() end,
    TRADE_SKILL_SHOW = function() Recorder.TradeSkillShown() end,
    TRADE_SKILL_UPDATE = function() Recorder.TradeSkillShown() end,
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
