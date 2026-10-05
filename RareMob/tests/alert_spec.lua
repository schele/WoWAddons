local helpers = require("helpers")

local function target(env, unit)
    env.__units.target = unit
    helpers.fire(env, "PLAYER_TARGET_CHANGED")
end

--- Spot Vultros, let it go, and come back `seconds` later.
local function againAfter(ns, env, seconds)
    target(env, nil)
    env.__now = env.__now + seconds
    ns.Spotter.Tick()
    target(env, env.__creature(462, "Vultros", 26, "rare"))
end

describe("the alert", function()
    it("sounds the raid warning when a living rare is spotted", function()
        local ns, env = helpers.loggedIn()
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        assertEqual(1, #env.__sounds)
        assertEqual(env.SOUNDKIT.RAID_WARNING, env.__sounds[1])
    end)

    it("sounds once per rare in five minutes", function()
        local ns, env = helpers.loggedIn()
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        againAfter(ns, env, 60)
        assertEqual(1, #env.__sounds, "a minute later: quiet")
        againAfter(ns, env, 241)
        assertEqual(2, #env.__sounds, "five minutes after the first: again")
    end)

    it("sounds for another rare inside the five minutes", function()
        local ns, env = helpers.loggedIn()
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        target(env, env.__creature(520, "Brack", 19, "rare"))
        assertEqual(2, #env.__sounds)
    end)

    it("never sounds while resting", function()
        local ns, env = helpers.loggedIn()
        env.__resting = true
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        assertEqual(0, #env.__sounds)
        assertTrue(ns.db.sightings[462] ~= nil, "still recorded")
    end)

    it("is silent with the setting off", function()
        local ns, env = helpers.loggedIn()
        ns.settings.alert = false
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        assertEqual(0, #env.__sounds)
    end)

    it("falls back to sound 8959 on a client without SOUNDKIT", function()
        local ns, env = helpers.loggedIn()
        env.SOUNDKIT = nil
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        assertEqual(8959, env.__sounds[1])
    end)

    it("does nothing on a client without PlaySound", function()
        local ns, env = helpers.loggedIn()
        env.PlaySound = nil
        target(env, env.__creature(462, "Vultros", 26, "rare"))
        assertTrue(ns.db.sightings[462] ~= nil)
    end)
end)
