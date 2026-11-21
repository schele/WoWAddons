local helpers = require("helpers")

local PARTY = { { "party1", "Brann", "WARRIOR" } }

--- Brann tanking, you under him at `scaled`.
local function underTheTank(scaled)
    return helpers.fighting({ party1 = 100, player = scaled or 50 }, PARTY)
end

describe("the warning", function()
    it("sounds and shows when you go over the tank", function()
        local _, env = underTheTank()

        helpers.threat(env, "player", 85, 1)

        assertEqual(1, #env.__sounds, "one sound")
        assertEqual(env.SOUNDKIT.RAID_WARNING, env.__sounds[1].kit)
        assertEqual(1, #env.__warnings, "one warning on screen")
        assertEqual("You are about to pull aggro!", env.__warnings[1].text)
        assertEqual(1, env.__warnings[1].color.r, "in red")
    end)

    it("comes at 90% while you are still under the tank", function()
        local _, env = underTheTank()

        helpers.threat(env, "player", 92, 0)

        assertEqual(1, #env.__warnings)
    end)

    it("stays quiet below 90%", function()
        local _, env = underTheTank()

        helpers.threat(env, "player", 89, 0)

        assertEqual(0, #env.__warnings)
    end)

    it("comes once, not on every change", function()
        local _, env = underTheTank()

        helpers.threat(env, "player", 92, 0)
        helpers.threat(env, "player", 95, 1)
        helpers.threat(env, "player", 93, 1)

        assertEqual(1, #env.__warnings)
    end)

    it("comes again once you have dropped back under 80%", function()
        local _, env = underTheTank()

        helpers.threat(env, "player", 92, 0)
        helpers.threat(env, "player", 85, 0)
        helpers.threat(env, "player", 93, 0)
        assertEqual(1, #env.__warnings, "85% is not far enough back")

        helpers.threat(env, "player", 70, 0)
        helpers.threat(env, "player", 93, 0)
        assertEqual(2, #env.__warnings)
    end)

    it("comes again on a new target", function()
        local _, env = underTheTank()
        helpers.threat(env, "player", 92, 0)

        helpers.mob(env, "other", "Defias Thug")
        helpers.target(env, "other")
        helpers.threat(env, "party1", 100)
        helpers.threat(env, "player", 92, 0)

        assertEqual(2, #env.__warnings)
    end)

    it("comes again in the next fight", function()
        local _, env = underTheTank()
        helpers.threat(env, "player", 92, 0)

        helpers.combat(env, false)
        helpers.combat(env, true)
        helpers.threat(env, "player", 92, 0)

        assertEqual(2, #env.__warnings)
    end)

    it("stays quiet while you are the one tanking", function()
        local _, env = helpers.fighting({ player = 100 })

        helpers.threat(env, "player", 100, 3)
        helpers.threat(env, "player", 100, 2)

        assertEqual(0, #env.__warnings)
        assertEqual(0, #env.__sounds)
    end)

    it("stays quiet when turned off", function()
        local ns, env = underTheTank()
        ns.settings.warn = false

        helpers.threat(env, "player", 95, 1)

        assertEqual(0, #env.__warnings)
        assertEqual(0, #env.__sounds)
    end)
end)

describe("the warning on a boss", function()
    local function bossFight()
        local ns, env = helpers.loggedIn(function(env) helpers.member(env, "party1", "Brann", "WARRIOR") end)
        helpers.mob(env, "mob", "Edwin VanCleef", { boss = true })
        helpers.target(env, "mob")
        helpers.combat(env, true)
        helpers.threat(env, "party1", 100, 3)
        return ns, env
    end

    it("comes when the game says you are over the tank, numbers or not", function()
        local _, env = bossFight()

        helpers.threat(env, "player", 95, 1)

        assertEqual(1, #env.__warnings)
    end)

    it("cannot come at 90%, since the number is hidden", function()
        local _, env = bossFight()

        helpers.threat(env, "player", 95, 0)

        assertEqual(0, #env.__warnings)
    end)
end)

describe("/threat test", function()
    it("shows what the warning is like", function()
        local _, env = helpers.loggedIn()

        helpers.command(env, "test")

        assertEqual(1, #env.__warnings)
        assertEqual(1, #env.__sounds)
    end)

    it("says when the warning is off", function()
        local ns, env = helpers.loggedIn()
        ns.settings.warn = false

        helpers.command(env, "test")

        assertMatch("The warning is off%.", helpers.printed(env))
        assertEqual(0, #env.__sounds)
    end)
end)
