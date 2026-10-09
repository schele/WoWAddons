local helpers = require("helpers")

-- A group finder listing `activities`, each { name, kind, map, levels, short }:
-- dungeons and raids in their own categories, anything else under quests.
local function finderListing(env, activities)
    local names = { [2] = "Dungeons", [114] = "Raids", [116] = "Quests & Zones" }
    local byCategory = { [2] = {}, [114] = {}, [116] = {} }
    local infos = {}
    for index, activity in ipairs(activities) do
        local category = (activity.kind == "raid" and 114) or (activity.kind == "quest" and 116) or 2
        local id = 1000 + index
        table.insert(byCategory[category], id)
        infos[id] = {
            fullName = activity.name, shortName = activity.short or "", categoryID = category,
            minLevelSuggestion = activity.levels and activity.levels[1] or 0,
            maxLevelSuggestion = activity.levels and activity.levels[2] or 0,
            minLevel = 0, mapID = activity.map or 0, maxNumPlayers = activity.kind == "raid" and 40 or 5,
        }
    end
    env.C_LFGList = {
        GetAvailableCategories = function() return { 2, 114, 116 } end,
        GetLfgCategoryInfo = function(id) return { name = names[id] } end,
        GetAvailableActivities = function(id) return byCategory[id] or {} end,
        GetActivityInfoTable = function(id) return infos[id] end,
    }
end

-- The samples, with map ids, logged in with the finder listing `activities`
-- (none: a client without a finder) and the player's recordings `sources`.
local function withFinder(activities, sources)
    local ns, env = helpers.loadAddon(nil, function(e)
        if activities then
            finderListing(e, activities)
        end
        e.BossLootDB = { recorded = { recorder = "me", sources = sources or {} } }
    end)
    helpers.sampleInstances(ns)
    ns.instanceByKey.Depths.mapID = 230
    ns.instanceByKey.Depths.bosses[1].npcs = { 101 }
    ns.instanceByKey.Depths.bosses[3].npcs = { 103 }
    ns.instanceByKey.Spire.mapID = 229
    ns.instanceByKey.Core.mapID = 409
    helpers.login(ns, env)
    return ns, env
end

local function listed(ns, kind)
    local out = {}
    for _, instance in ipairs(ns.Index.Instances(kind)) do
        table.insert(out, instance.name)
    end
    return table.concat(out, ",")
end

local function source(fields)
    fields.map = fields.map or 230
    fields.instanceType = fields.instanceType or "party"
    fields.instance = fields.instance or "Test Depths"
    return fields
end

describe("the instances the game's group finder offers", function()
    it("are the only ones listed", function()
        local ns = withFinder({ { name = "Test Depths", map = 230 } })
        assertEqual("Test Depths", listed(ns, "dungeon"))
        assertEqual("", listed(ns, "raid"), "the finder lists no raid")
        assertTrue(ns.Index.IsHidden("Spire"))
    end)

    it("take the finder's names and level ranges", function()
        local ns = withFinder({ { name = "Lower Spire", map = 229, levels = { 14, 20 } } })
        local spire = ns.instanceByKey.Spire
        assertEqual("Lower Spire", spire.name)
        assertEqual(14, spire.levels[1])
        assertEqual(20, spire.levels[2])
    end)

    it("keep their own level range where the finder suggests none", function()
        local ns = withFinder({ { name = "Low Spire", map = 229 } })
        assertEqual(55, ns.instanceByKey.Spire.levels[1])
    end)

    it("go by the finder's short name, as its own list does", function()
        local ns = withFinder({ { name = "Low Spire: Lower City", short = "Lower City", map = 229 } })
        assertEqual("Lower City", ns.instanceByKey.Spire.name)
    end)

    it("are matched by name, ignoring a leading The, when the finder gives no map", function()
        local ns = withFinder({ { name = "The Low Spire" } })
        assertEqual("The Low Spire", listed(ns, "dungeon"))
    end)

    it("include a raid from the finder's raid list", function()
        local ns = withFinder({ { name = "Molten Test", kind = "raid", map = 409 } })
        assertEqual("Molten Test", listed(ns, "raid"))
        assertEqual("", listed(ns, "dungeon"))
    end)

    it("leave a tab empty, and the window whole, when the finder lists none of its kind", function()
        local ns = withFinder({ { name = "Test Depths", map = 230 } })
        ns.Window.Open()
        ns.Window.SelectKind("raid")
        assertNil(ns.Window.Current())
        local entries = ns.Window.InstanceEntries({ kind = "raid", instance = "" }, "")
        assertEqual(1, #entries)
        assertEqual("heading", entries[1].kind)
        assertMatch("no raids", entries[1].text)
        ns.Window.SelectKind("dungeon")
        assertEqual("Depths", ns.Window.Current().key)
    end)

    it("leave out what the finder lists under quests and zones", function()
        local ns = withFinder({ { name = "Low Spire", map = 229 }, { name = "Elwynn Forest", kind = "quest", map = 0 } })
        assertEqual("Low Spire", listed(ns, "dungeon"))
    end)

    it("go back to their own names and levels when the finder stops listing them", function()
        local ns, env = withFinder({ { name = "Lower Spire", map = 229, levels = { 14, 20 } } })
        finderListing(env, { { name = "Test Depths", map = 230 } })
        helpers.fire(env, "LFG_LIST_AVAILABILITY_UPDATE")
        assertEqual("Low Spire", ns.instanceByKey.Spire.name)
        assertEqual(55, ns.instanceByKey.Spire.levels[1])
        assertEqual("Test Depths", listed(ns, "dungeon"))
    end)
end)

describe("an instance BossLoot does not know", function()
    it("is listed from the finder before anything was recorded there", function()
        local ns = withFinder({ { name = "Hall of Thanes", map = 3065, levels = { 20, 25 } } })
        local hall = ns.instanceByKey["lfg:3065"]
        assertEqual("Hall of Thanes", hall.name)
        assertEqual("dungeon", hall.kind)
        assertEqual(20, hall.levels[1])
        assertEqual(0, #hall.bosses)
        assertEqual("Hall of Thanes", listed(ns, "dungeon"))
    end)

    it("gets what was recorded there, with the bosses the game named", function()
        local ns = withFinder({ { name = "Hall of Thanes", map = 3065 } }, {
            ["npc:8000"] = source({ kind = "npc", id = 8000, map = 3065, instance = "The Hall of Thanes",
                name = "Thane", encounter = "Thane", kills = 1, items = { [8001] = 1 } }),
        })
        local hall = ns.instanceByKey["lfg:3065"]
        assertEqual("Thane", hall.bosses[1].name)
        assertEqual(8001, hall.bosses[1].recorded[1][1])
        assertNil(ns.instanceByKey["rec:3065"], "not listed twice")
        assertEqual("Hall of Thanes", listed(ns, "dungeon"))
    end)

    it("names its bosses once however often the recordings change", function()
        local ns = withFinder({ { name = "Hall of Thanes", map = 3065 } }, {
            ["npc:8000"] = source({ kind = "npc", id = 8000, map = 3065, name = "Thane", encounter = "Thane",
                kills = 1, items = { [8001] = 1 } }),
        })
        ns.Recordings.Changed()
        ns.Recordings.Changed()
        assertEqual(1, #ns.instanceByKey["lfg:3065"].bosses)
    end)

    it("says nothing has been recorded there yet, not that its bosses drop nothing", function()
        local ns = withFinder({ { name = "Hall of Thanes", map = 3065 } })
        ns.Window.Open()
        ns.Window.SelectInstance("lfg:3065")
        local frame = ns.Window.Frame()
        assertTrue(frame.empty:IsShown())
        assertMatch("recorded", frame.empty:GetText())
    end)
end)

describe("an instance the finder lists by wing", function()
    local WINGS = {
        { name = "Test Depths East", map = 230, levels = { 50, 55 } },
        { name = "Test Depths West", map = 230, levels = { 55, 60 } },
    }

    it("is listed once per wing, with the finder's names and levels", function()
        local ns = withFinder(WINGS)
        assertEqual("Test Depths East,Test Depths West", listed(ns, "dungeon"))
        local east = ns.instanceByKey["Depths:East"]
        assertEqual(50, east.levels[1])
        assertTrue(ns.Index.IsHidden("Depths"), "not as a whole as well")
    end)

    it("lists only that wing's bosses, with no wing heading", function()
        local ns = withFinder(WINGS)
        local entries = ns.Window.BossEntries(ns.instanceByKey["Depths:East"], 1)
        local names = {}
        for _, entry in ipairs(entries) do table.insert(names, entry.text) end
        assertEqual("First Boss|Second Boss|Notable drops|From trash", table.concat(names, "|"))
        assertEqual(1, #ns.instanceByKey["Depths:West"].bosses)
    end)

    it("keeps the instance's map and notable drops", function()
        local ns = withFinder(WINGS)
        local west = ns.instanceByKey["Depths:West"]
        assertEqual(ns.instanceByKey.Depths.notable, west.notable)
        assertEqual(ns.instanceByKey.Depths.map, west.map)
    end)

    it("finds an item in the wing that drops it", function()
        local ns = withFinder(WINGS)
        local result = ns.Index.Search("third", function(id) return id == 1004 and "Third Boss Sword" or nil end)
        assertEqual("Depths:West", result.items[1].sources[1].instance)
        assertEqual(1, result.items[1].sources[1].boss)
    end)

    it("shows what was recorded in that wing", function()
        local ns = withFinder(WINGS, {
            ["npc:103"] = source({ kind = "npc", id = 103, kills = 2, items = { [6001] = 1 } }),
            ["npc:300"] = source({ kind = "npc", id = 300, name = "Trash Mob", kills = 4, items = { [6002] = 1 } }),
        })
        local west = ns.instanceByKey["Depths:West"]
        assertEqual(6001, west.bosses[1].recorded[1][1])
        assertEqual(6002, west.recordedNotable.trash[1][1])
        assertNil(ns.instanceByKey["Depths:East"].bosses[1].recorded)
    end)

    it("is shown whole when the finder's names do not say which wing", function()
        local ns = withFinder({ { name = "Test Depths", map = 230 } })
        assertEqual("Test Depths", listed(ns, "dungeon"))
        assertNil(ns.instanceByKey["Depths:East"])
    end)
end)

describe("an instance the finder leaves out", function()
    it("is listed once something was recorded there", function()
        local ns = withFinder({ { name = "Low Spire", map = 229 } }, {
            ["npc:101"] = source({ kind = "npc", id = 101, kills = 1, items = { [1001] = 1 } }),
        })
        assertEqual("Test Depths,Low Spire", listed(ns, "dungeon"))
    end)
end)

describe("without the finder's list", function()
    it("lists every instance on a client with no group finder", function()
        local ns = withFinder(nil)
        assertEqual("Test Depths,Low Spire", listed(ns, "dungeon"))
        assertEqual("Molten Test", listed(ns, "raid"))
    end)

    it("lists every instance while the finder lists nothing, and follows it once it does", function()
        local ns, env = withFinder({})
        assertEqual("Test Depths,Low Spire", listed(ns, "dungeon"))
        finderListing(env, { { name = "Low Spire", map = 229 } })
        helpers.fire(env, "LFG_LIST_AVAILABILITY_UPDATE")
        assertEqual("Low Spire", listed(ns, "dungeon"))
    end)
end)

describe("/bl finder", function()
    it("prints what the finder lists and what each one is in BossLoot", function()
        local ns, env = withFinder({
            { name = "Test Depths East", map = 230, levels = { 50, 55 } },
            { name = "Hall of Thanes", map = 3065 },
        })
        helpers.command(env, "finder")
        local printed = helpers.printed(env)
        assertMatch("2 dungeons and 0 raids", printed)
        assertMatch("Test Depths East 50%-55, map 230: Test Depths, East", printed)
        assertMatch("Hall of Thanes, map 3065: new to BossLoot", printed)
    end)

    it("says when the client has no list", function()
        local ns, env = withFinder(nil)
        helpers.command(env, "finder")
        assertMatch("lists no dungeons or raids", helpers.printed(env))
    end)
end)
