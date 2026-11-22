local helpers = require("helpers")

local RANK1, RANK2, SHRED = 22568, 22827, 5221

--- Logged in with Ferocious Bite rank 1 on the first button, a Bite counted
-- at its full tooltip damage unless `share` says otherwise, and `setup` run
-- before login.
local function ready(setup, share, options)
    return helpers.loggedIn(function(env, ns)
        env.BiteTimeDB = { settings = { share = share or 100 } }
        env.__place(1, RANK1)
        if setup then setup(env, ns) end
    end, options)
end

local function buttonGlow(ns, env, button)
    local overlay = ns.Glow.buttons[button or env.ActionButton1]
    return overlay and helpers.seen(env, overlay) or 0
end

local function centerGlow(ns, env)
    return helpers.seen(env, ns.Glow.center)
end

describe("the glow on a Bite button", function()
    it("lights when a Bite with your combo points would kill the target", function()
        local ns, env = ready(nil, 80)
        helpers.target(env, env.__mob("Defias Thug", 100, 1000))
        helpers.power(env, 3, 35)
        assertEqual(0, buttonGlow(ns, env), "100 health is more than 80% of 100")
        helpers.health(env, 80)
        assertEqual(1, buttonGlow(ns, env))
    end)

    it("lights at exactly the most a Bite takes, and not one point above", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Defias Thug", 40, 1000))
        helpers.power(env, 1, 35)
        assertEqual(1, buttonGlow(ns, env))
        helpers.health(env, 41)
        assertEqual(0, buttonGlow(ns, env))
    end)

    it("counts the energy over a Bite's cost", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Defias Thug", 177, 1000))
        helpers.power(env, 5, 60) -- 160 + 25 x 0.7 = 177.5
        assertEqual(1, buttonGlow(ns, env))
        helpers.health(env, 178)
        assertEqual(0, buttonGlow(ns, env))
    end)

    it("counts a Bite at the share set on the options page", function()
        local ns, env = ready(nil, 50)
        helpers.target(env, env.__mob("Defias Thug", 20, 1000))
        helpers.power(env, 1, 35)
        assertEqual(1, buttonGlow(ns, env))
        helpers.health(env, 21)
        assertEqual(0, buttonGlow(ns, env))
    end)

    it("lights from full health when a Bite takes more than the target has", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        assertEqual(1, buttonGlow(ns, env))
    end)

    it("lights though the game hides both the mob's health and its max health from addons", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Defias Thug", 40, 1000))
        assertTrue(env.issecretvalue(env.UnitHealth("target")), "health hidden")
        assertTrue(env.issecretvalue(env.UnitHealthMax("target")), "max health hidden")
        helpers.power(env, 1, 35)
        assertEqual(1, buttonGlow(ns, env))
        helpers.health(env, 41)
        assertEqual(0, buttonGlow(ns, env))
    end)

    it("goes dark when you change to a target with more health", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        helpers.target(env, env.__mob("Defias Thug", 500, 1000))
        assertEqual(0, buttonGlow(ns, env))
    end)

    it("turns off with its box", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        ns.settings.buttons = false
        ns.Refresh()
        assertEqual(0, buttonGlow(ns, env))
    end)
end)

describe("the glow staying dark", function()
    local function darkWhen(change)
        local ns, env = ready()
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        assertEqual(1, buttonGlow(ns, env), "lit before the change")
        change(env)
        helpers.fire(env, "UPDATE_SHAPESHIFT_FORM")
        return buttonGlow(ns, env)
    end

    it("with no combo points", function()
        assertEqual(0, darkWhen(function(env) env.__points = 0 end))
    end)

    it("out of Cat Form", function()
        assertEqual(0, darkWhen(function(env) env.__form = 5 end))
    end)

    it("with no target", function()
        assertEqual(0, darkWhen(function(env) env.__units.target = nil end))
    end)

    it("with a target you cannot attack", function()
        assertEqual(0, darkWhen(function(env) env.__units.target.hostile = false end))
    end)

    it("with a dead target", function()
        assertEqual(0, darkWhen(function(env) env.__units.target.dead = true end))
    end)

    it("with an enemy player, whose health it cannot weigh", function()
        assertEqual(0, darkWhen(function(env) env.__units.target.player = true end))
    end)

    it("when the game hides your combo points", function()
        assertEqual(0, darkWhen(function(env) env.__points = env.__secret(3) end))
    end)
end)

describe("which buttons glow", function()
    local function lit(setup)
        local ns, env = ready(setup)
        helpers.target(env, env.__mob("Defias Thug", 50, 1000))
        helpers.power(env, 1, 35)
        return ns, env
    end

    it("not one that holds another spell", function()
        local ns, env = lit(function(env) env.__place(2, SHRED) end)
        assertEqual(0, buttonGlow(ns, env, env.ActionButton2))
    end)

    it("every one that holds a Bite, on any bar", function()
        local ns, env = lit(function(env) env.__place(61, RANK1) end)
        helpers.health(env, 40)
        assertEqual(1, buttonGlow(ns, env, env.ActionButton1))
        assertEqual(1, buttonGlow(ns, env, env.MultiBarBottomLeftButton1))
    end)

    it("each by its own rank's damage", function()
        local ns, env = lit(function(env)
            env.__known[RANK2] = true
            env.__place(2, RANK2)
        end)
        assertEqual(0, buttonGlow(ns, env, env.ActionButton1), "rank 1 takes 40")
        assertEqual(1, buttonGlow(ns, env, env.ActionButton2), "rank 2 takes 64")
    end)

    it("one a Bite is dragged onto, and not once it is dragged off", function()
        local ns, env = lit()
        helpers.health(env, 40)
        helpers.place(env, 3, RANK1)
        assertEqual(1, buttonGlow(ns, env, env.ActionButton3))
        env.__actions[3] = nil
        helpers.fire(env, "ACTIONBAR_SLOT_CHANGED", 3)
        assertEqual(0, buttonGlow(ns, env, env.ActionButton3))
    end)

    it("the main bar's, as it pages to Cat Form's bar", function()
        local ns, env = ready(function(env) env.__actions[1] = nil end)
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        assertEqual(0, buttonGlow(ns, env))
        env.__place(73, RANK1)
        env.ActionButton1.action = 73
        helpers.fire(env, "UPDATE_BONUS_ACTIONBAR")
        helpers.wait(env, 0)
        assertEqual(1, buttonGlow(ns, env))
    end)

    it("pulses while lit", function()
        local ns, env = lit()
        local overlay = ns.Glow.buttons[env.ActionButton1]
        assertTrue(overlay.pulse:IsPlaying())
    end)
end)

describe("the icon in the middle of the screen", function()
    it("lights with the Bite on your bars", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Defias Thug", 41, 1000))
        helpers.power(env, 1, 35)
        assertEqual(0, centerGlow(ns, env))
        helpers.health(env, 40)
        assertEqual(1, centerGlow(ns, env))
    end)

    it("shows Ferocious Bite's icon", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        assertEqual(132127, ns.Glow.center.icon:GetStatusBarTexture():GetTexture())
    end)

    it("goes by the weakest rank on your bars, the one a press might cast", function()
        local ns, env = ready(function(env)
            env.__known[RANK2] = true
            env.__place(2, RANK2)
        end)
        helpers.target(env, env.__mob("Defias Thug", 50, 1000))
        helpers.power(env, 1, 35)
        assertEqual(0, centerGlow(ns, env))
    end)

    it("goes by the highest rank known when no Bite is on the bars", function()
        local ns, env = ready(function(env)
            env.__actions[1] = nil
            env.__known[RANK2] = true
        end)
        helpers.target(env, env.__mob("Defias Thug", 50, 1000))
        helpers.power(env, 1, 35)
        assertEqual(1, centerGlow(ns, env))
    end)

    it("turns off with its box", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        ns.settings.center = false
        ns.Refresh()
        assertEqual(0, centerGlow(ns, env))
    end)

    it("stays dark for a character who has not learned Ferocious Bite", function()
        local ns, env = ready(function(env)
            env.__actions[1] = nil
            env.__known = {}
        end)
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        assertEqual(0, centerGlow(ns, env))
    end)
end)

describe("when something goes wrong", function()
    it("says so once, rather than going dark without a word", function()
        local ns, env = ready()
        ns.Kill.Weigh = function() error("kaboom") end
        helpers.target(env, env.__mob("Rat", 30, 30))
        helpers.power(env, 1, 35)
        helpers.wait(env, 0.5)
        local text = helpers.printed(env)
        assertMatch("Something went wrong, so BiteTime may not light: .*kaboom", text)
        local _, times = text:gsub("Something went wrong", "")
        assertEqual(1, times)
    end)
end)

describe("keeping up", function()
    it("looks again a few times a second, for anything the events missed", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Rat", 30, 30))
        env.__points = 1 -- no event
        helpers.wait(env, 0.5)
        assertEqual(1, buttonGlow(ns, env))
    end)

    it("reads the tooltip again when your attack power changes", function()
        local ns, env = ready()
        helpers.target(env, env.__mob("Defias Thug", 50, 1000))
        helpers.power(env, 1, 35)
        assertEqual(0, buttonGlow(ns, env))
        local spell = require("wow_stub").SPELLS[RANK1]
        local saved = spell.description
        spell.description = saved:gsub("40%-54", "50-64")
        helpers.fire(env, "UNIT_ATTACK_POWER", "player")
        spell.description = saved
        assertEqual(1, buttonGlow(ns, env))
    end)
end)

describe("on Classic Era", function()
    it("compares the health itself, the game giving it as a plain number there", function()
        local ns, env = ready(nil, nil, { era = true })
        helpers.target(env, env.__mob("Defias Thug", 40, 1000))
        helpers.power(env, 1, 35)
        assertEqual(1, buttonGlow(ns, env))
        helpers.health(env, 41)
        assertEqual(0, buttonGlow(ns, env))
    end)

    it("stays dark when the game gives the health only as a percentage", function()
        local ns, env = ready(nil, nil, { era = true })
        helpers.target(env, env.__mob("Defias Thug", 30, 100))
        helpers.power(env, 1, 35)
        assertEqual(0, buttonGlow(ns, env))
    end)
end)
