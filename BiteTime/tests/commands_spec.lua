local helpers = require("helpers")

local RANK1 = 22568

local function ready(setup)
    return helpers.loggedIn(function(env, ns)
        env.__place(1, RANK1)
        if setup then setup(env, ns) end
    end)
end

describe("/bt test", function()
    it("lights the buttons and the icon for three seconds, with no target", function()
        local ns, env = ready()
        helpers.command(env, "test")
        assertEqual(1, helpers.seen(env, ns.Glow.buttons[env.ActionButton1]))
        assertEqual(1, helpers.seen(env, ns.Glow.center))
        helpers.wait(env, 3)
        assertEqual(0, helpers.seen(env, ns.Glow.buttons[env.ActionButton1]))
        assertEqual(0, helpers.seen(env, ns.Glow.center))
    end)

    it("lights only what is switched on", function()
        local ns, env = ready(function(env) env.BiteTimeDB = { settings = { center = false } } end)
        helpers.command(env, "test")
        assertEqual(1, helpers.seen(env, ns.Glow.buttons[env.ActionButton1]))
        assertEqual(0, helpers.seen(env, ns.Glow.center))
    end)

    it("says when both are switched off", function()
        local _, env = ready(function(env)
            env.BiteTimeDB = { settings = { buttons = false, center = false } }
        end)
        helpers.command(env, "test")
        assertMatch("Both are off%. Turn one on in the settings page %(/bt%)%.", helpers.printed(env))
    end)

    it("says when the character has not learned Ferocious Bite", function()
        local _, env = helpers.loggedIn(function(env) env.__known = {} end)
        helpers.command(env, "test")
        assertMatch("You have not learned Ferocious Bite, so there is nothing to light%.", helpers.printed(env))
    end)
end)

describe("/bt probe", function()
    local function probe(setup, options)
        local ns, env = helpers.loggedIn(function(env, ns)
            env.__place(1, RANK1)
            if setup then setup(env, ns) end
        end, options)
        env.__printed = {}
        helpers.command(env, "probe")
        return helpers.printed(env), ns, env
    end

    it("says what each combo point's Bite does, and what energy adds", function()
        local text = probe()
        assertMatch("Ferocious Bite %(Rank 1%): 40%-54, 70%-84, 100%-114, 130%-144, 160%-174 damage for 1 to 5 combo "
            .. "points%. Each energy over 35 adds 0%.7%.", text)
    end)

    it("says how many buttons hold it", function()
        local text = probe(function(env) env.__place(61, RANK1) end)
        assertMatch("It is on 2 of your action buttons%.", text)
    end)

    it("says when no button holds it", function()
        local text = probe(function(env) env.__actions[1] = nil end)
        assertMatch("It is on none of your action buttons, so only the icon in the middle can light%.", text)
    end)

    it("says the game hides the target's health, and does the comparing", function()
        local text = probe(function(env) env.__units.target = env.__mob("Defias Thug", 300, 1234) end)
        assertMatch("Target: Defias Thug%. The game hides its health from addons, so the game itself does the "
            .. "comparing%.", text)
    end)

    it("says the target's health where the game shows it", function()
        local text = probe(function(env) env.__units.target = env.__mob("Defias Thug", 300, 1234) end, { era = true })
        assertMatch("Target: Defias Thug, 300 of 1234 health%.", text)
    end)

    it("says when the game hides your combo points", function()
        local text = probe(function(env)
            env.__units.target = env.__mob("Defias Thug", 300, 1234)
            env.__points = env.__secret(3)
        end)
        assertMatch("The game hides your combo points from addons, so BiteTime cannot tell what a Bite does%.", text)
    end)

    it("says when the game hides your energy, and counts none over the cost", function()
        local text = probe(function(env)
            env.__units.target = env.__mob("Defias Thug", 300, 1234)
            env.__points, env.__energy = 5, env.__secret(60)
        end)
        assertMatch("Now: 5 combo points and energy the game hides, so a Bite does at least 160%. Counted at 80%%, "
            .. "that takes 128 health%.", text)
    end)

    it("checks that the game keeps a bar's value inside its range, as the comparing needs", function()
        assertMatch("Bar check: the game keeps a bar's value inside its range, as BiteTime needs%.", (probe()))
    end)

    it("says when the bar check fails", function()
        local text = probe(function(env) env.__barsKeepAnyValue = true end)
        assertMatch("Bar check failed: the game lets a bar's value leave its range, so BiteTime cannot light on WoW "
            .. "Forever%.", text)
    end)

    it("checks no bars where the game shows health and does not need them", function()
        local text = probe(nil, { era = true })
        assertTrue(not text:find("Bar check"), text)
    end)

    it("says what a Bite does now, and what it is counted at", function()
        local text = probe(function(env)
            env.__units.target = env.__mob("Defias Thug", 300, 1234)
            env.__points, env.__energy = 5, 60
        end)
        assertMatch("Now: 5 combo points and 60 energy, so a Bite does at least 177%.5%. Counted at 80%%, that "
            .. "takes 142 health%.", text)
    end)

    it("says why nothing can light: no target", function()
        assertMatch("No target you can attack%.", (probe()))
    end)

    it("says why nothing can light: an enemy player", function()
        local text = probe(function(env) env.__units.target = env.__enemyPlayer("Sneaky", 300, 1234) end)
        assertMatch("Your target is a player%. BiteTime weighs only mobs%.", text)
    end)

    it("says why nothing can light: no combo points", function()
        local text = probe(function(env) env.__units.target = env.__mob("Defias Thug", 300, 1234) end)
        assertMatch("No combo points on your target%.", text)
    end)

    it("says why nothing can light: not in Cat Form", function()
        local text = probe(function(env)
            env.__units.target = env.__mob("Defias Thug", 300, 1234)
            env.__form = 0
        end)
        assertMatch("You are not in Cat Form%.", text)
    end)

    it("says when the character has not learned Ferocious Bite", function()
        local text = probe(function(env)
            env.__actions[1] = nil
            env.__known = {}
        end)
        assertMatch("You have not learned Ferocious Bite, so BiteTime has nothing to light%.", text)
    end)

    it("says when the tooltip has no damage it can read", function()
        local stub = require("wow_stub")
        local saved = stub.SPELLS[RANK1].description
        stub.SPELLS[RANK1].description = "Finishing move."
        local text = probe()
        stub.SPELLS[RANK1].description = saved
        assertMatch("Ferocious Bite's tooltip has no damage BiteTime can read%.", text)
    end)
end)
