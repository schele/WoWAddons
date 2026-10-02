local helpers = require("helpers")

describe("looking at login", function()
    it("shows the popup when a button is outdated", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)

        helpers.login(env)

        assertTrue(ns.Popup.IsShown())
    end)

    it("shows and says nothing when every button is current", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5189)

        helpers.login(env)

        assertFalse(ns.Popup.IsShown())
        assertEqual("", helpers.printed(env))
    end)

    it("looks only once, not after every loading screen", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.login(env)
        ns.Popup.frame.notNow:Click()

        helpers.fire(env, "PLAYER_ENTERING_WORLD", false, false)
        env.__runTimers()

        assertFalse(ns.Popup.IsShown())
    end)
end)

describe("looking when a spell is learned", function()
    local function trainedRankFive()
        local ns, env = helpers.loadAddon()
        env.__known[5189] = nil -- Rank 5 not trained yet
        helpers.place(env, 3, 5188)
        helpers.login(env)
        env.__known[5189] = true
        return ns, env
    end

    it("looks a moment after the trainer teaches a rank", function()
        local ns, env = trainedRankFive()
        assertFalse(ns.Popup.IsShown(), "Rank 4 was the highest at login")

        helpers.fire(env, "LEARNED_SPELL_IN_TAB", 5189, 1)
        assertFalse(ns.Popup.IsShown(), "before the spellbook has caught up")

        env.__runTimers()
        assertTrue(ns.Popup.IsShown())
    end)

    it("looks once for several ranks taught together", function()
        local _, env = trainedRankFive()

        helpers.fire(env, "LEARNED_SPELL_IN_TAB", 5189, 1)
        helpers.fire(env, "LEARNED_SPELL_IN_TAB", 1430, 1)
        helpers.fire(env, "LEARNED_SPELL_IN_TAB", 6808, 1)

        assertEqual(1, #env.__timers)
    end)

    it("hears the newer client's name for the event", function()
        local ns, env = trainedRankFive()

        helpers.fire(env, "LEARNED_SPELL_IN_SKILL_LINE", 5189, 1)
        env.__runTimers()

        assertTrue(ns.Popup.IsShown())
    end)

    it("loads on a client that lacks one of the names", function()
        local ns, env = helpers.loadAddon(function(e)
            e.__unknownEvents.LEARNED_SPELL_IN_TAB = true
        end)
        helpers.login(env)
        helpers.place(env, 3, 5188)

        helpers.fire(env, "LEARNED_SPELL_IN_SKILL_LINE", 5189, 1)
        env.__runTimers()

        assertTrue(ns.Popup.IsShown())
    end)

    it("does not look when a button changes", function()
        local ns, env = helpers.loadAddon()
        helpers.login(env)
        helpers.place(env, 3, 5188)

        helpers.fire(env, "ACTIONBAR_SLOT_CHANGED", 3)
        env.__runTimers()

        assertFalse(ns.Popup.IsShown())
    end)
end)

describe("/rankup", function()
    it("shows the popup when a button is outdated", function()
        local ns, env = helpers.loadAddon()
        helpers.login(env)
        helpers.place(env, 3, 5188)

        helpers.command(env)

        assertTrue(ns.Popup.IsShown())
    end)

    it("says so when every button is current", function()
        local _, env = helpers.loadAddon()
        helpers.login(env)

        helpers.command(env)

        assertMatch("Every button already holds your highest rank%.", helpers.printed(env))
    end)

    it("brings the popup back after Not now", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.login(env)
        ns.Popup.frame.notNow:Click()

        helpers.command(env)

        assertTrue(ns.Popup.IsShown())
    end)
end)

describe("looking and combat", function()
    it("holds a look until the fight ends", function()
        local ns, env = helpers.loadAddon()
        helpers.login(env)
        helpers.place(env, 3, 5188)
        helpers.enterCombat(env)

        helpers.command(env)
        assertFalse(ns.Popup.IsShown(), "in combat")

        helpers.leaveCombat(env)
        assertTrue(ns.Popup.IsShown())
    end)

    it("holds /rankup's answer too", function()
        local _, env = helpers.loadAddon()
        helpers.login(env)
        helpers.enterCombat(env)

        helpers.command(env)
        assertEqual("", helpers.printed(env), "in combat")

        helpers.leaveCombat(env)
        assertMatch("Every button already holds your highest rank%.", helpers.printed(env))
    end)

    it("never opens during a fight, even when a look comes due", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.fire(env, "PLAYER_ENTERING_WORLD", true, false)
        helpers.enterCombat(env)

        env.__runTimers()
        assertFalse(ns.Popup.IsShown(), "in combat")

        helpers.leaveCombat(env)
        assertTrue(ns.Popup.IsShown())
    end)

    it("greys out Upgrade while a fight is on", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.login(env)

        helpers.enterCombat(env)
        assertFalse(ns.Popup.frame.upgrade:IsEnabled())

        helpers.leaveCombat(env)
        assertTrue(ns.Popup.frame.upgrade:IsEnabled())
    end)

    it("shows what is left after a fight stopped an upgrade", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.place(env, 14, 5186)
        helpers.login(env)
        env.__onPlace = function()
            env.__inCombat = true
        end

        ns.Popup.frame.upgrade:Click()
        env.__onPlace = nil
        helpers.leaveCombat(env)

        assertTrue(ns.Popup.IsShown())
        assertEqual("Healing Touch: Rank 2 -> Rank 5 (1 button)", ns.Popup.frame.lines[1]:GetText())
    end)
end)
