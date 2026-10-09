local helpers = require("helpers")

local THANE = "Creature-0-3110-3065-47-263500-00001A2B3C"
local GUARD = "Creature-0-3110-3065-47-263470-00001A2B3D"

local LEGS = { link = "|cnIQ3:|Hitem:281400::::::::30:1484:::::::::|h[Supple Bellyskin Leggings]|h|r",
    name = "Supple Bellyskin Leggings", quality = 3 }

-- In the Hall of Thanes (map 3065), at `env.__now` seconds.
local function inHall(env)
    env.__now = env.__now or 100
    function env.GetTime() return env.__now end
    function env.GetInstanceInfo() return "The Hall of Thanes", "party", 1, "Normal", 5, 0, false, 3065 end
    function env.GetRealZoneText() return "The Hall of Thanes" end
end

-- A roll starting on `item`, as when someone opens a corpse with it.
local function roll(env, rollID, item)
    env.__rolls = env.__rolls or {}
    env.__rolls[rollID] = item
    function env.GetLootRollItemLink(id) return env.__rolls[id] and env.__rolls[id].link end
    function env.GetLootRollItemInfo(id)
        local rolled = env.__rolls[id]
        return 134400, rolled and rolled.name, 1, rolled and rolled.quality
    end
    helpers.fire(env, "START_LOOT_ROLL", rollID, 60000)
end

-- A loot window holding `item` from `guid`, with `units` (unit -> guid) for
-- whichever units the client lets the recorder see.
local function looting(env, item, guid, units, names)
    function env.GetNumLootItems() return 1 end
    function env.GetLootSlotLink() return item.link end
    function env.GetLootSlotInfo() return 134400, item.name, 1, nil, item.quality end
    function env.GetLootSourceInfo() return guid, 1 end
    function env.UnitGUID(unit) return units and units[unit] end
    function env.UnitName(unit) return names and names[unit] end
    helpers.fire(env, "LOOT_OPENED")
end

-- A boss fight: started, with the game showing `bosses` (unit -> guid, name),
-- and won.
local function fight(env, name, bosses)
    function env.UnitGUID(unit) return bosses[unit] and bosses[unit].guid end
    function env.UnitName(unit) return bosses[unit] and bosses[unit].name end
    helpers.fire(env, "ENCOUNTER_START", 1, name, 1, 5)
    helpers.fire(env, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    helpers.fire(env, "ENCOUNTER_END", 1, name, 1, 5, 1)
end

local function loggedInHall()
    local ns, env = helpers.loggedIn()
    inHall(env)
    return ns, env
end

describe("an item won on a roll", function()
    it("is recorded for the boss whose fight just ended, with the fight as a kill", function()
        local ns, env = loggedInHall()
        helpers.fire(env, "ENCOUNTER_END", 1, "Thane Grimstone", 1, 5, 1)
        env.__now = 150
        roll(env, 1, LEGS)
        env.__runTimers()
        local source = ns.db.recorded.sources["roll:Thane Grimstone@3065"]
        assertEqual(1, source.items[281400])
        assertEqual(1, source.kills)
        assertEqual("Thane Grimstone", source.encounter)
        assertEqual(3065, source.map)
        assertEqual("party", source.instanceType)
        assertEqual("Supple Bellyskin Leggings", ns.db.recorded.items[281400][1])
    end)

    it("counts one kill for a fight, however many rolls it brings", function()
        local ns, env = loggedInHall()
        helpers.fire(env, "ENCOUNTER_END", 1, "Thane Grimstone", 1, 5, 1)
        roll(env, 1, LEGS)
        roll(env, 2, { link = "|Hitem:281401::::|h[Thane's Ring]|h", name = "Thane's Ring", quality = 3 })
        env.__runTimers()
        assertEqual(1, ns.db.recorded.sources["roll:Thane Grimstone@3065"].kills)
    end)

    it("is recorded as the instance's trash when no fight ended in the last two minutes", function()
        local ns, env = loggedInHall()
        helpers.fire(env, "ENCOUNTER_END", 1, "Thane Grimstone", 1, 5, 1)
        env.__now = 100 + 121
        roll(env, 1, LEGS)
        env.__runTimers()
        assertNil(ns.db.recorded.sources["roll:Thane Grimstone@3065"])
        assertEqual(1, ns.db.recorded.sources["roll:trash@3065"].items[281400])
    end)

    it("is not credited to a fight won in another instance", function()
        local ns, env = loggedInHall()
        function env.GetInstanceInfo() return "Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
        helpers.fire(env, "ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
        inHall(env)
        roll(env, 1, LEGS)
        env.__runTimers()
        assertEqual(1, ns.db.recorded.sources["roll:trash@3065"].items[281400])
    end)

    it("is counted once when the roll is seen twice", function()
        local ns, env = loggedInHall()
        roll(env, 7, LEGS)
        roll(env, 7, LEGS)
        env.__runTimers()
        assertEqual(1, ns.db.recorded.sources["roll:trash@3065"].items[281400])
    end)

    it("is not counted again when the player opened the corpse it came from", function()
        local ns, env = loggedInHall()
        looting(env, LEGS, GUARD)
        roll(env, 1, LEGS)
        env.__runTimers()
        assertNil(ns.db.recorded.sources["roll:trash@3065"])
        assertEqual(1, ns.db.recorded.sources["npc:263470@3065"].items[281400])
    end)

    it("is not counted again when the corpse's window opens just after the roll", function()
        local ns, env = loggedInHall()
        roll(env, 1, LEGS)
        looting(env, LEGS, GUARD)
        env.__runTimers()
        assertNil(ns.db.recorded.sources["roll:trash@3065"])
    end)

    it("moves to the corpse it came from when the corpse is opened later in the roll, which becomes the fight's boss", function()
        local ns, env = loggedInHall()
        local SHADETOOTH = "Creature-0-3110-3065-47-260325-00001A2B40"
        helpers.fire(env, "ENCOUNTER_END", 1, "Shadetooth", 1, 5, 1)
        env.__now = 110
        roll(env, 1, LEGS)
        env.__runTimers()
        assertEqual(1, ns.db.recorded.sources["roll:Shadetooth@3065"].items[281400])
        env.__now = 150
        looting(env, LEGS, SHADETOOTH)
        local corpse = ns.db.recorded.sources["npc:260325@3065"]
        assertEqual(1, corpse.items[281400])
        assertEqual("Shadetooth", corpse.encounter)
        assertNil(ns.db.recorded.sources["roll:Shadetooth@3065"].items[281400], "counted once")
    end)

    it("marks the corpse it came from as the fight's boss when the corpse was opened first", function()
        local ns, env = loggedInHall()
        local GUARDIAN = "Creature-0-3110-3065-47-260326-00001A2B41"
        helpers.fire(env, "ENCOUNTER_END", 1, "Relic Guardian", 1, 5, 1)
        env.__now = 105
        looting(env, LEGS, GUARDIAN)
        roll(env, 1, LEGS)
        env.__runTimers()
        local corpse = ns.db.recorded.sources["npc:260326@3065"]
        assertEqual("Relic Guardian", corpse.encounter)
        assertEqual(1, corpse.items[281400])
        assertNil(ns.db.recorded.sources["roll:Relic Guardian@3065"])
    end)

    it("leaves a trash corpse unmarked when its roll came long after any fight", function()
        local ns, env = loggedInHall()
        helpers.fire(env, "ENCOUNTER_END", 1, "Relic Guardian", 1, 5, 1)
        env.__now = 100 + 600
        looting(env, LEGS, GUARD)
        roll(env, 1, LEGS)
        env.__runTimers()
        assertNil(ns.db.recorded.sources["npc:263470@3065"].encounter)
    end)

    it("counts a roll and a corpse over a minute apart as two drops", function()
        local ns, env = loggedInHall()
        roll(env, 1, LEGS)
        env.__runTimers()
        env.__now = 100 + 70
        looting(env, LEGS, GUARD)
        assertEqual(1, ns.db.recorded.sources["roll:trash@3065"].items[281400])
        assertEqual(1, ns.db.recorded.sources["npc:263470@3065"].items[281400])
    end)

    it("is left out in the open world", function()
        local ns, env = loggedInHall()
        function env.GetInstanceInfo() return "Eastern Kingdoms", "none", 0, "", 5, 0, false, 0 end
        roll(env, 1, LEGS)
        env.__runTimers()
        assertNil(next(ns.db.recorded.sources))
    end)

    it("is skipped, and does not fail, when the client will not give its item", function()
        local ns, env = loggedInHall()
        function env.GetLootRollItemLink() error("secret value") end
        helpers.fire(env, "START_LOOT_ROLL", 1, 60000)
        env.__runTimers()
        assertNil(next(ns.db.recorded.sources))
    end)

    it("shows under the boss in a dungeon the group finder lists", function()
        local ns, env = loggedInHall()
        env.C_LFGList = {
            GetAvailableCategories = function() return { 2 } end,
            GetLfgCategoryInfo = function() return { name = "Dungeons" } end,
            GetAvailableActivities = function() return { 1 } end,
            GetActivityInfoTable = function()
                return { fullName = "Hall of Thanes", shortName = "", minLevelSuggestion = 13, maxLevelSuggestion = 20, mapID = 3065 }
            end,
        }
        helpers.fire(env, "ENCOUNTER_END", 1, "Thane Grimstone", 1, 5, 1)
        roll(env, 1, LEGS)
        env.__runTimers() -- the roll
        env.__runTimers() -- the lists it changed
        local hall = ns.instanceByKey["lfg:3065"]
        assertEqual("Thane Grimstone", hall.bosses[1].name)
        assertEqual(281400, hall.bosses[1].recorded[1][1])
        assertEqual(1, hall.bosses[1].recordedKills)
    end)
end)

describe("a boss known by its fight", function()
    it("is the creature the game showed as the boss, named by the fight", function()
        local ns, env = loggedInHall()
        fight(env, "Thane Grimstone", { boss1 = { guid = THANE, name = "Thane Grimstone" } })
        local source = ns.db.recorded.sources["npc:263500@3065"]
        assertEqual("Thane Grimstone", source.encounter)
        assertEqual("Thane Grimstone", source.name)
        assertEqual(0, source.kills, "known, not yet looted")
    end)

    it("gets its corpse's loot, looted without a target, long after the fight", function()
        local ns, env = loggedInHall()
        fight(env, "Thane Grimstone", { boss1 = { guid = THANE, name = "Thane Grimstone" } })
        env.__now = 100 + 600
        looting(env, LEGS, THANE)
        local source = ns.db.recorded.sources["npc:263500@3065"]
        assertEqual("Thane Grimstone", source.encounter)
        assertEqual(1, source.kills)
        assertEqual(1, source.items[281400])
    end)

    it("takes every boss the game showed, for a fight of several", function()
        local ns, env = loggedInHall()
        local SECOND = "Creature-0-3110-3065-47-263501-00001A2B3F"
        fight(env, "The Twin Thanes", { boss1 = { guid = THANE, name = "Elder" }, boss2 = { guid = SECOND, name = "Younger" } })
        assertEqual("The Twin Thanes", ns.db.recorded.sources["npc:263500@3065"].encounter)
        assertEqual("The Twin Thanes", ns.db.recorded.sources["npc:263501@3065"].encounter)
    end)

    it("is not marked for a fight that was lost", function()
        local ns, env = loggedInHall()
        function env.UnitGUID(unit) return unit == "boss1" and THANE or nil end
        helpers.fire(env, "ENCOUNTER_START", 1, "Thane Grimstone", 1, 5)
        helpers.fire(env, "ENCOUNTER_END", 1, "Thane Grimstone", 1, 5, 0)
        assertNil(ns.db.recorded.sources["npc:263500@3065"])
    end)

    it("is skipped, and does not fail, when the client keeps the boss units secret", function()
        local ns, env = loggedInHall()
        function env.UnitGUID() error("secret value") end
        helpers.fire(env, "ENCOUNTER_START", 1, "Thane Grimstone", 1, 5)
        helpers.fire(env, "ENCOUNTER_END", 1, "Thane Grimstone", 1, 5, 1)
        assertNil(next(ns.db.recorded.sources))
    end)
end)

describe("a corpse's name", function()
    it("comes from the corpse under the mouse when it is not the target", function()
        local ns, env = loggedInHall()
        looting(env, LEGS, GUARD, { mouseover = GUARD }, { mouseover = "Hall Guard" })
        assertEqual("Hall Guard", ns.db.recorded.sources["npc:263470@3065"].name)
    end)

    it("comes from the interact key's corpse", function()
        local ns, env = loggedInHall()
        looting(env, LEGS, GUARD, { softinteract = GUARD }, { softinteract = "Hall Guard" })
        assertEqual("Hall Guard", ns.db.recorded.sources["npc:263470@3065"].name)
    end)
end)

describe("/bl probe on boss fights", function()
    it("says when no boss fight has been seen", function()
        local ns, env = loggedInHall()
        helpers.command(env, "probe")
        assertMatch("No boss fight seen", helpers.printed(env))
    end)

    it("names the last fight and how many of its bosses could be read", function()
        local ns, env = loggedInHall()
        fight(env, "Thane Grimstone", { boss1 = { guid = THANE, name = "Thane Grimstone" } })
        helpers.command(env, "probe")
        assertMatch("Last boss fight: Thane Grimstone, 1 boss read", helpers.printed(env))
    end)
end)
