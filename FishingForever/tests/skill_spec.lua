local helpers = require("helpers")

local POLE = 6256

--- Logged in holding a pole. `setup` runs before login, on the env.
local function loggedIn(setup)
    local ns, env = helpers.loadAddon()
    env.__mainHand = POLE
    if setup then setup(env) end
    helpers.login(ns, env)
    return ns, env
end

local function castStart(env)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
end

local function castStop(env)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
end

local function skillUp(env)
    env.__fishing.rank = env.__fishing.rank + 1
    helpers.fire(env, "SKILL_LINES_CHANGED")
end

--- One cast and a fish on the line: the loot window opens on the catch and
-- closes. `pointFirst` has the skill point arrive before the loot does,
-- `point` after it.
local function catch(env, point, pointFirst)
    castStart(env)
    castStop(env)
    if point and pointFirst then skillUp(env) end
    env.__fishingLoot = true
    helpers.fire(env, "LOOT_OPENED")
    if point and not pointFirst then skillUp(env) end
    helpers.fire(env, "LOOT_CLOSED")
    env.__fishingLoot = false
end

describe("reading the fishing skill", function()
    it("reads it by its ID on a client with C_SkillInfo, as Forever has", function()
        local ns = loggedIn()
        local rank, maxRank = ns.Skill.Rank()
        assertEqual(231, rank)
        assertEqual(300, maxRank)
    end)

    it("reads it from the skill list on Classic, under the spell's own name", function()
        local ns = loggedIn(function(env)
            env.C_SkillInfo = nil
            local lines = {
                { "Professions", true },
                { "Herbalism", false, 120, 150 },
                { "Secondary Skills", true },
                { "Fishing", false, 88, 150 },
            }
            function env.GetNumSkillLines() return #lines end
            function env.GetSkillLineInfo(index)
                local line = lines[index]
                return line[1], line[2], true, line[3] or 0, 0, 0, line[4] or 0
            end
        end)
        local rank, maxRank = ns.Skill.Rank()
        assertEqual(88, rank)
        assertEqual(150, maxRank)
    end)

    it("finds it by name in C_SkillInfo's list when its ID gives nothing", function()
        local ns = loggedIn(function(env)
            local lines = {
                { name = "Secondary Skills", isHeader = true, isCollapsed = false, rank = 0, maxRank = 0 },
                { name = "Fishing", isHeader = false, isCollapsed = false, rank = 140, maxRank = 225 },
            }
            env.C_SkillInfo = {
                GetSkillLineInfoByID = function() return nil end,
                GetNumSkillLines = function() return #lines end,
                GetSkillLineInfo = function(index) return lines[index] end,
            }
        end)
        local rank, maxRank = ns.Skill.Rank()
        assertEqual(140, rank)
        assertEqual(225, maxRank)
    end)

    it("is nothing for a character who has not learned Fishing", function()
        local ns = loggedIn(function(env) env.__fishing = nil end)
        assertNil(ns.Skill.Rank())
    end)
end)

describe("counting catches", function()
    it("counts each catch", function()
        local ns, env = loggedIn()
        catch(env)
        catch(env)
        assertEqual(2, ns.Skill.Catches())
    end)

    it("leaves out loot that is not a catch", function()
        local ns, env = loggedIn()
        helpers.fire(env, "LOOT_OPENED")
        helpers.fire(env, "LOOT_CLOSED")
        assertEqual(0, ns.Skill.Catches())
    end)

    it("counts a catch once, however often its loot window opens", function()
        local ns, env = loggedIn()
        castStart(env)
        castStop(env)
        env.__fishingLoot = true
        helpers.fire(env, "LOOT_OPENED")
        helpers.fire(env, "LOOT_OPENED")
        assertEqual(1, ns.Skill.Catches())
    end)

    it("starts again from nothing at a skill point", function()
        local ns, env = loggedIn()
        catch(env)
        catch(env, true)
        assertEqual(0, ns.Skill.Catches())
        assertEqual(232, (ns.Skill.Rank()))
        catch(env)
        assertEqual(1, ns.Skill.Catches())
    end)

    it("gives the catch to the point it brought, when the point arrives before the loot", function()
        local ns, env = loggedIn()
        catch(env)
        catch(env, true, true)
        assertEqual(0, ns.Skill.Catches(), "the catch that brought the point is not the next point's")
    end)

    it("counts nothing at the cap, where a catch cannot raise the skill", function()
        local ns, env = loggedIn(function(e) e.__fishing = { rank = 150, maxRank = 150 } end)
        catch(env)
        assertEqual(0, ns.Skill.Catches())
    end)

    it("keeps the count for this character over a logout", function()
        local ns, env = loggedIn()
        catch(env)
        catch(env)
        local saved = env.FishingForeverCharDB
        local again = loggedIn(function(e) e.FishingForeverCharDB = saved end)
        assertEqual(2, again.Skill.Catches())
    end)

    it("starts over when the skill changed while FishingForever was not watching", function()
        local ns, env = loggedIn()
        catch(env)
        local saved = env.FishingForeverCharDB
        local again = loggedIn(function(e)
            e.FishingForeverCharDB = saved
            e.__fishing.rank = 233
        end)
        assertEqual(0, again.Skill.Catches())
    end)
end)

describe("what a point takes", function()
    it("guesses from the old game's rule until points are measured: one catch a point below 75", function()
        local ns = loggedIn()
        local catches, source = ns.Skill.Expected(50)
        assertEqual(1, catches)
        assertEqual("guess", source)
    end)

    it("guesses fewer than one in seven catches at 231, and one in four at 150", function()
        local ns = loggedIn()
        assertEqual(7, math.floor(ns.Skill.Expected(231) + 0.5))
        assertEqual(4, math.floor(ns.Skill.Expected(150) + 0.5))
    end)

    it("notes how many catches each point took, once it has watched from the point before", function()
        local ns, env = loggedIn()
        catch(env)
        catch(env, true) -- counting began mid-way: this point is not measured
        assertNil(ns.db.skillUps[231])
        catch(env)
        catch(env)
        catch(env, true)
        assertEqual(1, ns.db.skillUps[232].points)
        assertEqual(3, ns.db.skillUps[232].catches)
    end)

    it("uses what it measured once five points near this skill are noted", function()
        local ns = loggedIn(function(env)
            env.FishingForeverDB = { skillUps = {
                [226] = { points = 2, catches = 10 },
                [230] = { points = 2, catches = 8 },
                [245] = { points = 1, catches = 12 },
            } }
        end)
        local catches, source, points = ns.Skill.Expected(231)
        assertEqual("measured", source)
        assertEqual(5, points)
        assertEqual(6, catches)
    end)

    it("keeps guessing with fewer than five", function()
        local ns = loggedIn(function(env)
            env.FishingForeverDB = { skillUps = { [230] = { points = 4, catches = 40 } } }
        end)
        local _, source = ns.Skill.Expected(231)
        assertEqual("guess", source)
    end)
end)
