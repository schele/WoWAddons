local helpers = require("helpers")

local REVELOSH = "Creature-0-3110-70-47-6910-00001A2B3C"
local OTHER = "Creature-0-3110-70-47-7000-00001A2B3D"

-- A loot window: each slot an item (link, name, quality) or money, from its
-- sources (guid, count, guid, count, ...); in Uldaman, with `target` targeted.
local function looting(env, slots, target)
    function env.GetNumLootItems() return #slots end
    function env.GetLootSlotLink(slot) return slots[slot].link end
    function env.GetLootSlotInfo(slot) return 134400, slots[slot].name, 1, nil, slots[slot].quality end
    function env.GetLootSourceInfo(slot) return table.unpack(slots[slot].sources) end
    function env.GetInstanceInfo() return "Uldaman", "party", 1, "Normal", 5, 0, false, 70 end
    function env.GetRealZoneText() return "Uldaman" end
    function env.UnitGUID(unit) return unit == "target" and target and target.guid or nil end
    function env.UnitName(unit) return unit == "target" and target and target.name or nil end
end

local BOOTS = { link = "|cff1eff00|Hitem:9387::::|h[Revelosh's Boots]|h|r", name = "Revelosh's Boots", quality = 2 }
local GLOVES = { link = "|cff1eff00|Hitem:9388::::|h[Revelosh's Gloves]|h|r", name = "Revelosh's Gloves", quality = 2 }

local function withSources(item, ...)
    return { link = item.link, name = item.name, quality = item.quality, sources = { ... } }
end

describe("a GUID", function()
    it("names a creature or an object, and nothing else", function()
        local ns = helpers.loggedIn()
        local kind, id = ns.Recorder.ParseGUID(REVELOSH)
        assertEqual("npc", kind)
        assertEqual(6910, id)
        kind, id = ns.Recorder.ParseGUID("GameObject-0-3110-70-47-5678-0000ABCD")
        assertEqual("object", kind)
        assertEqual(5678, id)
        assertNil(ns.Recorder.ParseGUID("Item-0-0-0-0-1234-0000"))
        assertNil(ns.Recorder.ParseGUID("Player-3110-00ABCDEF"))
        assertNil(ns.Recorder.ParseGUID(nil))
    end)
end)

describe("recording loot", function()
    it("records a boss's loot, with the kill, where it was, and its name", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1), withSources(GLOVES, REVELOSH, 1) },
            { guid = REVELOSH, name = "Revelosh" })
        helpers.fire(env, "LOOT_OPENED")
        local source = ns.db.recorded.sources["npc:6910@70"]
        assertEqual(1, source.kills)
        assertEqual(1, source.items[9387])
        assertEqual(1, source.items[9388])
        assertEqual("Revelosh", source.name)
        assertEqual(70, source.map)
        assertEqual("party", source.instanceType)
        assertEqual("Uldaman", source.instance)
    end)

    it("counts a corpse once, however often its loot is opened", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(env, "LOOT_OPENED")
        helpers.fire(env, "LOOT_OPENED")
        local source = ns.db.recorded.sources["npc:6910@70"]
        assertEqual(1, source.kills)
        assertEqual(1, source.items[9387])
    end)

    it("counts a kill for a corpse with only money", function()
        local ns, env = helpers.loggedIn()
        looting(env, { { sources = { REVELOSH, 1 } } })
        helpers.fire(env, "LOOT_OPENED")
        local source = ns.db.recorded.sources["npc:6910@70"]
        assertEqual(1, source.kills)
        assertNil(next(source.items))
    end)

    it("keeps each corpse apart when several are looted at once", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1, OTHER, 1) })
        helpers.fire(env, "LOOT_OPENED")
        assertEqual(1, ns.db.recorded.sources["npc:6910@70"].kills)
        assertEqual(1, ns.db.recorded.sources["npc:7000@70"].kills)
        assertEqual(1, ns.db.recorded.sources["npc:7000@70"].items[9387])
    end)

    it("remembers corpses looted before a reload", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(env, "LOOT_OPENED")
        local later, laterEnv = helpers.loadAddon(nil, function(e) e.BossLootDB = env.BossLootDB end)
        helpers.sampleInstances(later)
        helpers.login(later, laterEnv)
        looting(laterEnv, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(laterEnv, "LOOT_OPENED")
        assertEqual(1, later.db.recorded.sources["npc:6910@70"].kills)
    end)

    it("marks the boss the game named when the fight ended, for a minute", function()
        local ns, env = helpers.loggedIn()
        env.__now = 100
        function env.GetTime() return env.__now end
        helpers.fire(env, "ENCOUNTER_END", 1, "Revelosh", 1, 5, 1)
        looting(env, { withSources(BOOTS, REVELOSH, 1) }, { guid = REVELOSH, name = "Revelosh" })
        helpers.fire(env, "LOOT_OPENED")
        assertEqual("Revelosh", ns.db.recorded.sources["npc:6910@70"].encounter)

        helpers.fire(env, "ENCOUNTER_END", 2, "Ironaya", 1, 5, 1)
        env.__now = 200
        local IRONAYA = "Creature-0-3110-70-47-7228-00001A2B3E"
        looting(env, { withSources(GLOVES, IRONAYA, 1) }, { guid = IRONAYA, name = "Ironaya" })
        helpers.fire(env, "LOOT_OPENED")
        assertNil(ns.db.recorded.sources["npc:7228@70"].encounter, "too long after")
    end)

    it("saves each item's name and quality from the loot window when the game has no more", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(env, "LOOT_OPENED")
        assertEqual("Revelosh's Boots", ns.db.recorded.items[9387][1])
        assertEqual(2, ns.db.recorded.items[9387][2])
    end)

    it("saves the game's full description of an item when it has one", function()
        local ns, env = helpers.loggedIn()
        env.__items[9387] = { name = "Forever Boots", quality = 3, type = "Armor", subType = "Leather", equipLoc = "INVTYPE_FEET" }
        looting(env, { withSources(BOOTS, REVELOSH, 1) })
        helpers.fire(env, "LOOT_OPENED")
        local item = ns.db.recorded.items[9387]
        assertEqual("Forever Boots", item[1])
        assertEqual(3, item[2])
        assertEqual("Leather", item[4])
    end)

    it("keeps a chest found in two places apart", function()
        -- Scarab Coffers stand in both Ahn'Qiraj instances, under one id.
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, "GameObject-0-3110-509-47-180691-0000A", 1) })
        function env.GetInstanceInfo() return "Ruins of Ahn'Qiraj", "raid", 1, "Normal", 20, 0, false, 509 end
        helpers.fire(env, "LOOT_OPENED")
        looting(env, { withSources(GLOVES, "GameObject-0-3110-531-47-180691-0000B", 1) })
        function env.GetInstanceInfo() return "Temple of Ahn'Qiraj", "raid", 1, "Normal", 40, 0, false, 531 end
        helpers.fire(env, "LOOT_OPENED")
        local ruins = ns.db.recorded.sources["object:180691@509"]
        local temple = ns.db.recorded.sources["object:180691@531"]
        assertEqual(1, ruins.kills)
        assertEqual(1, ruins.items[9387])
        assertEqual(1, temple.kills)
        assertEqual(1, temple.items[9388])
        assertNil(temple.items[9387])
    end)

    it("does nothing, and does not fail, on a client without the loot calls", function()
        local ns, env = helpers.loggedIn()
        helpers.fire(env, "LOOT_OPENED")
        assertNil(next(ns.db.recorded.sources))
    end)

    it("gets a recorder id at login, and keeps it", function()
        local ns, env = helpers.loggedIn()
        local id = ns.db.recorded.recorder
        assertTrue(type(id) == "string" and #id >= 8)
        local later, laterEnv = helpers.loadAddon(nil, function(e) e.BossLootDB = env.BossLootDB end)
        helpers.login(later, laterEnv)
        assertEqual(id, later.db.recorded.recorder)
    end)
end)

describe("recording quests, merchants and crafts", function()
    it("records a quest's rewards and choices, with its title and the faction", function()
        local ns, env = helpers.loggedIn()
        function env.GetQuestID() return 2279 end
        function env.GetTitleText() return "Passing Word of a Threat" end
        function env.UnitFactionGroup() return "Alliance" end
        function env.GetNumQuestRewards() return 1 end
        function env.GetNumQuestChoices() return 2 end
        function env.GetQuestItemLink(kind, index)
            if kind == "reward" then return "|Hitem:9587::|h[A]|h" end
            return index == 1 and "|Hitem:9588::|h[B]|h" or "|Hitem:9589::|h[C]|h"
        end
        helpers.fire(env, "QUEST_DETAIL")
        local quest = ns.db.recorded.quests[2279]
        assertEqual("Passing Word of a Threat", quest.title)
        assertEqual("Alliance", quest.faction)
        assertEqual("9587", table.concat(quest.rewards, ","))
        assertEqual("9588,9589", table.concat(quest.choices, ","))
    end)

    it("records what a merchant sells, and for how much", function()
        local ns, env = helpers.loggedIn()
        function env.UnitGUID(unit) return unit == "npc" and "Creature-0-3110-0-47-1234-0000AA" or nil end
        function env.UnitName(unit) return unit == "npc" and "Brave Sword" or nil end
        function env.GetRealZoneText() return "Ironforge" end
        function env.GetMerchantNumItems() return 2 end
        function env.GetMerchantItemLink(i) return i == 1 and "|Hitem:2901::|h[Mining Pick]|h" or nil end
        function env.GetMerchantItemInfo(i) return "Mining Pick", 134400, 81 end
        helpers.fire(env, "MERCHANT_SHOW")
        local merchant = ns.db.recorded.merchants["npc:1234"]
        assertEqual("Brave Sword", merchant.name)
        assertEqual("Ironforge", merchant.zone)
        assertEqual(81, merchant.items[2901].price)
    end)

    it("records what a profession's recipes make, leaving out the headings", function()
        local ns, env = helpers.loggedIn()
        function env.GetTradeSkillLine() return "Blacksmithing", 120, 150 end
        function env.GetNumTradeSkills() return 2 end
        function env.GetTradeSkillInfo(i) return i == 1 and "Armor" or "Copper Chain Belt", i == 1 and "header" or "easy" end
        function env.GetTradeSkillItemLink(i) return i == 2 and "|Hitem:2851::|h[Copper Chain Belt]|h" or nil end
        helpers.fire(env, "TRADE_SKILL_SHOW")
        assertTrue(ns.db.recorded.crafts["Blacksmithing"][2851])
    end)

    it("records nothing, and does not fail, without the quest, merchant or profession calls", function()
        local ns, env = helpers.loggedIn()
        helpers.fire(env, "QUEST_DETAIL")
        helpers.fire(env, "QUEST_COMPLETE")
        helpers.fire(env, "MERCHANT_SHOW")
        helpers.fire(env, "TRADE_SKILL_SHOW")
        assertNil(next(ns.db.recorded.quests))
        assertNil(next(ns.db.recorded.merchants))
        assertNil(next(ns.db.recorded.crafts))
    end)
end)

describe("the recorder's commands", function()
    it("say which calls this client is missing", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "probe")
        assertMatch("GetLootSourceInfo", helpers.printed(env))
        function env.GetNumLootItems() end
        function env.GetLootSlotLink() end
        function env.GetLootSlotInfo() end
        function env.GetLootSourceInfo() end
        function env.GetInstanceInfo() end
        function env.UnitGUID() end
        function env.GetQuestID() end
        function env.GetQuestItemLink() end
        function env.GetMerchantItemLink() end
        function env.GetMerchantItemInfo() end
        function env.GetTradeSkillLine() end
        function env.GetTradeSkillItemLink() end
        function env.GetItemStats() end
        env.__printed = {}
        helpers.command(env, "probe")
        assertMatch("Everything the recorder needs", helpers.printed(env))
    end)

    it("count what has been recorded", function()
        local ns, env = helpers.loggedIn()
        looting(env, { withSources(BOOTS, REVELOSH, 1) }, { guid = REVELOSH, name = "Revelosh" })
        helpers.fire(env, "LOOT_OPENED")
        helpers.command(env, "recorded")
        assertMatch("1 creatures and objects", helpers.printed(env))
        assertMatch("1 items", helpers.printed(env))
    end)
end)
