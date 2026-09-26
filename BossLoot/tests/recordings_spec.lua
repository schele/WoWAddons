local helpers = require("helpers")

-- The samples, with a map id and creature ids, and recordings: `own` as the
-- player's saved ones, `baked` as recorder id -> data.
local function withRecordings(own, baked)
    local ns, env = helpers.loadAddon(nil, function(e)
        e.BossLootDB = { recorded = own }
    end)
    helpers.sampleInstances(ns)
    local depths = ns.instanceByKey.Depths
    depths.mapID = 230
    depths.bosses[1].npcs = { 101, 102 }
    for recorder, data in pairs(baked or {}) do
        ns.AddRecordings(recorder, data)
    end
    helpers.login(ns, env)
    return ns, env, depths
end

local function source(fields)
    fields.map = fields.map or 230
    fields.instanceType = fields.instanceType or "party"
    fields.instance = fields.instance or "Test Depths"
    return fields
end

describe("recorded loot on the instances", function()
    it("lays a boss's recorded loot on it, most seen first, with its kills", function()
        local ns, env, depths = withRecordings({ recorder = "me", sources = {
            ["npc:101"] = source({ kind = "npc", id = 101, kills = 5, items = { [1001] = 3, [5555] = 4 } }),
        } })
        local boss = depths.bosses[1]
        assertEqual(5, boss.recordedKills)
        assertEqual(5555, boss.recorded[1][1])
        assertEqual(4, boss.recorded[1][2])
        assertEqual(1001, boss.recorded[2][1])
    end)

    it("matches a boss by its name when its creature is not known", function()
        local ns, env, depths = withRecordings({ recorder = "me", sources = {
            ["npc:999"] = source({ kind = "npc", id = 999, name = "Second Boss", kills = 1, items = { [1003] = 1 } }),
        } })
        assertEqual(1003, depths.bosses[2].recorded[1][1])
    end)

    it("counts the most kills of one creature for a boss of several", function()
        local ns, env, depths = withRecordings({ recorder = "me", sources = {
            ["npc:101"] = source({ kind = "npc", id = 101, kills = 5, items = { [1001] = 2 } }),
            ["npc:102"] = source({ kind = "npc", id = 102, kills = 5, items = { [1001] = 1 } }),
        } })
        assertEqual(5, depths.bosses[1].recordedKills)
        assertEqual(3, depths.bosses[1].recorded[1][2])
    end)

    it("puts other creatures under trash and chests under objects, notable items only", function()
        local ns, env, depths = withRecordings({ recorder = "me",
            items = { [7001] = { "Rare Find", 3 }, [7002] = { "Green Find", 2 } },
            sources = {
                ["npc:300"] = source({ kind = "npc", id = 300, name = "Trash Mob", kills = 9, items = { [7001] = 2, [7002] = 5 } }),
                ["object:50"] = source({ kind = "object", id = 50, name = "Old Chest", kills = 1, items = { [7001] = 1 } }),
            } })
        local trash = depths.recordedNotable.trash
        assertEqual(1, #trash)
        assertEqual(7001, trash[1][1])
        assertEqual(2, trash[1][2])
        assertEqual("Trash Mob", trash[1][3][1])
        assertEqual(7001, depths.recordedNotable.objects[1][1])
    end)

    it("sums baked recordings with the player's own, but not the baked copy of the player's own", function()
        local ns, env, depths = withRecordings(
            { recorder = "me", sources = { ["npc:101"] = source({ kind = "npc", id = 101, kills = 1, items = { [1001] = 1 } }) } },
            {
                friend = { sources = { ["npc:101"] = source({ kind = "npc", id = 101, kills = 2, items = { [1001] = 2 } }) } },
                me = { sources = { ["npc:101"] = source({ kind = "npc", id = 101, kills = 100, items = { [1001] = 100 } }) } },
            })
        assertEqual(3, depths.bosses[1].recordedKills)
        assertEqual(3, depths.bosses[1].recorded[1][2])
    end)

    it("lists an instance BossLoot does not know, with the bosses the game named", function()
        local ns = withRecordings({ recorder = "me", sources = {
            ["npc:8000"] = source({ kind = "npc", id = 8000, map = 9999, instance = "Hall of Thanes",
                name = "Thane", encounter = "Thane", kills = 1, items = { [8001] = 1 } }),
            ["npc:8002"] = source({ kind = "npc", id = 8002, map = 9999, instance = "Hall of Thanes",
                name = "Guard", kills = 3, items = { [8003] = 1 } }),
        } })
        local hall = ns.instanceByKey["rec:9999"]
        assertEqual("Hall of Thanes", hall.name)
        assertEqual("dungeon", hall.kind)
        assertTrue(hall.recorded)
        assertEqual(1, #hall.bosses)
        assertEqual("Thane", hall.bosses[1].name)
        assertEqual(8001, hall.bosses[1].recorded[1][1])
        local listed = false
        for _, instance in ipairs(ns.Index.Instances("dungeon")) do
            if instance == hall then listed = true end
        end
        assertTrue(listed)
    end)

    it("leaves open-world loot out of the instances", function()
        local ns = withRecordings({ recorder = "me", sources = {
            ["npc:40"] = source({ kind = "npc", id = 40, map = 0, instanceType = "none", kills = 1, items = { [900] = 1 } }),
        } })
        assertNil(ns.instanceByKey["rec:0"])
    end)

    it("names a recorded item from its recording, over the vanilla built-in copy", function()
        local ns = withRecordings({ recorder = "me", items = { [7001] = { "Forever Robe", 4, "Armor", "Cloth", "INVTYPE_CHEST" } } })
        ns.AddItems({ [7001] = { "Vanilla Robe", 2, 4, 1, 5 } })
        local info = ns.LootRow.ItemInfo(7001)
        assertEqual("Forever Robe", info.name)
        assertEqual(4, info.quality)
    end)

    it("finds recorded items in a search", function()
        local ns = withRecordings({ recorder = "me",
            items = { [5555] = { "Thane's Seal", 3 } },
            sources = { ["npc:101"] = source({ kind = "npc", id = 101, kills = 1, items = { [5555] = 1 } }) } })
        local result = ns.Index.Search("thane", function(id) local info = ns.LootRow.ItemInfo(id) return info and info.name end)
        assertEqual(5555, result.items[1].id)
    end)
end)
