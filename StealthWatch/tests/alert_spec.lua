local helpers = require("helpers")

local VANISH = 1856

--- Logged in, then an enemy rogue on nameplate1 who goes into stealth:
-- with the spell named, or (hidden = true) by the cast-then-gone sign.
local function stealthed(setup, hidden)
    local ns, env = helpers.loggedIn(setup)
    helpers.plateAdded(env, "nameplate1", env.__enemy("Sneaky", "ROGUE", 58, "Undead"))
    if hidden then
        helpers.cast(env, "nameplate1", env.__secret())
        helpers.plateRemoved(env, "nameplate1")
    else
        helpers.cast(env, "nameplate1", VANISH)
    end
    return ns, env
end

describe("an alert", function()
    it("sounds the boss emote warning, on the master channel", function()
        local _, env = stealthed()
        assertEqual(1, #env.__sounds)
        assertEqual(12197, env.__sounds[1].kit)
        assertEqual("Master", env.__sounds[1].channel)
    end)

    it("puts the spell and who cast it in red in the middle of the screen", function()
        local _, env = stealthed()
        assertEqual(1, #env.__warnings)
        local warning = env.__warnings[1]
        assertEqual("Vanish: |cfffff569Sneaky|r, Rogue", warning.text)
        assertEqual(1, warning.color.r)
        assertTrue(warning.color.g < 0.5 and warning.color.b < 0.5, "red")
    end)

    it("says Stealth on screen when the client hid the spell", function()
        local _, env = stealthed(nil, true)
        assertEqual("Stealth: |cfffff569Sneaky|r, Rogue", env.__warnings[1] and env.__warnings[1].text)
    end)

    it("prints who, and the spell, in chat", function()
        local _, env = stealthed()
        assertMatch("Sneaky, level 58 Undead Rogue, cast Vanish%.", helpers.printed(env))
    end)

    it("says in chat when stealth was inferred rather than seen", function()
        local _, env = stealthed(nil, true)
        assertMatch("Sneaky, level 58 Undead Rogue, went out of sight right after an instant cast: likely stealth%.",
            helpers.printed(env))
    end)

    it("gives a level too high to see as ??", function()
        local ns, env = helpers.loggedIn()
        helpers.plateAdded(env, "nameplate1", env.__enemy("Boss", "ROGUE", -1, "Orc"))
        helpers.cast(env, "nameplate1", VANISH)
        assertMatch("Boss, level %?%? Orc Rogue, cast Vanish%.", helpers.printed(env))
    end)

    it("leaves the name uncoloured for a class the client has no colour for", function()
        local ns, env = helpers.loggedIn(function(env) env.RAID_CLASS_COLORS = nil end)
        helpers.plateAdded(env, "nameplate1", env.__enemy("Sneaky"))
        helpers.cast(env, "nameplate1", VANISH)
        assertEqual("Vanish: Sneaky, Rogue", env.__warnings[1] and env.__warnings[1].text)
    end)
end)

describe("the alert's switches", function()
    it("are all on at first", function()
        local ns = helpers.loggedIn()
        assertTrue(ns.settings.sound)
        assertTrue(ns.settings.screen)
        assertTrue(ns.settings.chat)
    end)

    it("silence the sound", function()
        local _, env = stealthed(function(env) env.StealthWatchDB = { settings = { sound = false } } end)
        assertEqual(0, #env.__sounds)
        assertEqual(1, #env.__warnings)
    end)

    it("keep the screen clear", function()
        local _, env = stealthed(function(env) env.StealthWatchDB = { settings = { screen = false } } end)
        assertEqual(0, #env.__warnings)
        assertEqual(1, #env.__sounds)
    end)

    it("keep chat quiet", function()
        local _, env = stealthed(function(env) env.StealthWatchDB = { settings = { chat = false } } end)
        assertFalse(helpers.printed(env):find("Sneaky"), "nothing about Sneaky in chat")
        assertEqual(1, #env.__warnings)
    end)
end)

describe("on a client without Forever's raid warning call", function()
    it("shows the text through Classic Era's RaidNotice_AddMessage", function()
        local notices = {}
        local _, env = stealthed(function(env)
            env.RaidWarningUtil = nil
            env.RaidNotice_AddMessage = function(frame, text, color)
                table.insert(notices, { frame = frame, text = text, color = color })
            end
        end)
        assertEqual(1, #notices)
        assertEqual(env.RaidWarningFrame, notices[1].frame)
        assertEqual("Vanish: |cfffff569Sneaky|r, Rogue", notices[1].text)
    end)

    it("shows the text in the error frame when there is no raid warning at all", function()
        local errors = {}
        local _, env = stealthed(function(env)
            env.RaidWarningUtil = nil
            env.UIErrorsFrame = { AddMessage = function(_, text) table.insert(errors, text) end }
        end)
        assertEqual("Vanish: |cfffff569Sneaky|r, Rogue", errors[1])
    end)

    it("still sounds without SOUNDKIT", function()
        local _, env = stealthed(function(env) env.SOUNDKIT = nil end)
        assertEqual(12197, env.__sounds[1] and env.__sounds[1].kit)
    end)
end)

describe("/sw test", function()
    it("shows what an alert looks like", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "test")
        assertEqual(1, #env.__sounds)
        assertEqual("Vanish: |cfffff569Example|r, Rogue", env.__warnings[1] and env.__warnings[1].text)
        assertMatch("Example, level 60 Night Elf Rogue, cast Vanish%.", helpers.printed(env))
    end)

    it("can be run again straight away", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "test")
        helpers.command(env, "test")
        assertEqual(2, #env.__warnings)
    end)

    it("says so when all three alerts are off", function()
        local ns, env = helpers.loggedIn(function(env)
            env.StealthWatchDB = { settings = { sound = false, screen = false, chat = false } }
        end)
        helpers.command(env, "test")
        assertMatch("All three alerts are off", helpers.printed(env))
    end)
end)
