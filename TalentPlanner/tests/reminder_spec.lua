local helpers = require("helpers")

-- Saved with a Feral plan: Feral Instinct x2, then Ferocity.
local function savedPlan(extra)
    local saved = { chars = { ["Skyler-Aldira"] = {
        active = "Feral", plans = { Feral = { class = "DRUID", points = { { 2, 2 }, { 2, 2 }, { 2, 1 } } } },
    } } }
    for key, value in pairs(extra or {}) do saved[key] = value end
    return saved
end

local function count(env, pattern)
    local found = 0
    for _, line in ipairs(env.__printed) do
        if line:find(pattern) then found = found + 1 end
    end
    return found
end

describe("the reminder", function()
    it("names the next talent at login when a point is free", function()
        local _, env = helpers.loggedIn(savedPlan(), function(env) env.__unspent = 1 end)
        assertMatch("Talent point ready: Feral Instinct %(1/5%)", helpers.printed(env))
    end)

    it("says nothing at login with no point free", function()
        local _, env = helpers.loggedIn(savedPlan())
        assertEqual(0, count(env, "Talent point ready"))
    end)

    it("is not repeated for the same point", function()
        local _, env = helpers.loggedIn(savedPlan(), function(env) env.__unspent = 1 end)
        helpers.fire(env, "PLAYER_LEVEL_UP", 31)
        helpers.fire(env, "CHARACTER_POINTS_CHANGED", 1)
        assertEqual(1, count(env, "Talent point ready"))
    end)

    it("names the next point once the last is spent", function()
        local _, env = helpers.loggedIn(savedPlan(), function(env) env.__unspent = 2 end)
        env.__ranks[2][2] = 1
        env.__unspent = 1
        helpers.fire(env, "CHARACTER_POINTS_CHANGED", -1)
        assertMatch("Talent point ready: Feral Instinct %(2/5%)", helpers.printed(env))
        assertEqual(2, count(env, "Talent point ready"))
    end)

    it("comes on a level up", function()
        local _, env = helpers.loggedIn(savedPlan())
        env.__unspent = 1
        helpers.fire(env, "PLAYER_LEVEL_UP", 31)
        assertEqual(1, count(env, "Talent point ready"))
    end)

    it("is silent with the setting off", function()
        local _, env = helpers.loggedIn(savedPlan({ remind = false }), function(env) env.__unspent = 1 end)
        assertEqual(0, count(env, "Talent point ready"))
    end)

    it("is silent when the plan is done or empty", function()
        local _, env = helpers.loggedIn(nil, function(env) env.__unspent = 1 end)
        assertEqual(0, count(env, "Talent point ready"))
    end)

    it("is silent when the next point names a talent the client does not have", function()
        local saved = { chars = { ["Skyler-Aldira"] = {
            active = "Old", plans = { Old = { class = "DRUID", points = { { 2, 12 }, { 2, 2 } } } },
        } } }
        local _, env = helpers.loggedIn(saved, function(env) env.__unspent = 1 end)
        assertEqual(0, count(env, "Talent point ready"))
    end)

    it("reads the free points from GetUnspentTalentPoints on a client without UnitCharacterPoints", function()
        local _, env = helpers.loggedIn(savedPlan(), function(env)
            env.UnitCharacterPoints = nil
            env.GetUnspentTalentPoints = function() return 1 end
        end)
        assertEqual(1, count(env, "Talent point ready"))
    end)

    it("does not raise on a client missing the level-up event", function()
        local _, env = helpers.loggedIn(savedPlan(), function(env)
            env.__unknownEvents.PLAYER_LEVEL_UP = true
            env.__unspent = 1
        end)
        assertEqual(1, count(env, "Talent point ready"))
    end)
end)

describe("Learn next", function()
    local function ready(extra, prepare)
        local ns, env = helpers.loggedIn(savedPlan(extra or { learn = true }), function(env)
            env.__unspent = 1
            if prepare then prepare(env) end
        end)
        return ns, env
    end

    it("learns the planned talent out of combat", function()
        local ns, env = ready()
        assertTrue(ns.Reminder.LearnNext())
        assertEqual(1, #env.__learned)
        assertEqual(2, env.__learned[1][1])
        assertEqual(2, env.__learned[1][2])
        assertEqual(1, env.__ranks[2][2])
    end)

    it("never learns in combat", function()
        local ns, env = ready()
        env.__inCombat = true
        local ok, why = ns.Reminder.LearnNext()
        assertFalse(ok)
        assertEqual("Not in combat.", why)
        assertEqual(0, #env.__learned)
    end)

    it("does nothing with the setting off", function()
        local ns, env = ready({ learn = false })
        assertFalse(ns.Reminder.LearnNext())
        assertEqual(0, #env.__learned)
    end)

    it("does nothing on a client without LearnTalent", function()
        local ns, env = ready(nil, function(env) env.LearnTalent = nil end)
        local ok, why = ns.Reminder.LearnNext()
        assertFalse(ok)
        assertEqual("This client has no LearnTalent.", why)
    end)

    it("does nothing with no point free", function()
        local ns, env = ready()
        env.__unspent = 0
        local ok, why = ns.Reminder.LearnNext()
        assertFalse(ok)
        assertEqual("No talent point to spend.", why)
        assertEqual(0, #env.__learned)
    end)

    it("notes that the client learned it", function()
        local ns, env = ready()
        ns.Reminder.LearnNext()
        env.__runTimers()
        assertEqual("worked", ns.Reminder.LastLearn().result)
    end)

    it("notes a refusal by the client, and the probe says so", function()
        local ns, env = ready(nil, function(env) env.__refuseLearn = true end)
        ns.Reminder.LearnNext()
        env.__runTimers()
        assertEqual("refused", ns.Reminder.LastLearn().result)
        helpers.command(env, "probe")
        assertMatch("Learn next: the client refused Feral Instinct", helpers.printed(env))
    end)
end)

describe("/tp probe", function()
    it("lists every talent call, LearnTalent among them", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "probe")
        local printed = helpers.printed(env)
        for _, name in ipairs({ "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetTalentInfo",
            "GetTalentPrereqs", "UnitCharacterPoints", "LearnTalent" }) do
            assertMatch(name .. ": yes", printed)
        end
        assertMatch("GetUnspentTalentPoints: no", printed)
        assertMatch("Tab info: name first", printed)
        assertMatch("Trees: Balance 8, Feral Combat 10, Restoration 4", printed)
        assertMatch("Talent window: not loaded yet", printed)
        assertMatch("Learn next: not tried", printed)
    end)

    it("says when LearnTalent is missing", function()
        local _, env = helpers.loggedIn(nil, function(env) env.LearnTalent = nil end)
        helpers.command(env, "probe")
        assertMatch("LearnTalent: no", helpers.printed(env))
    end)

    it("names the talent window once it is loaded", function()
        local _, env = helpers.loggedIn()
        env.__makeTalentUI(true)
        helpers.fire(env, "ADDON_LOADED", "Blizzard_TalentUI")
        helpers.command(env, "probe")
        assertMatch("Talent window: PlayerTalentFrame, 20 buttons", helpers.printed(env))
    end)
end)
