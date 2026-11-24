local helpers = require("helpers")

local POLE = 6256
local HILLSBRAD = 1424

--- Logged in holding a pole, at skill 106 of 150 in Hillsbrad Foothills.
-- `setup` runs before login, on the env.
local function loggedIn(setup)
    local ns, env = helpers.loadAddon()
    env.__mainHand = POLE
    env.__fishing = { rank = 106, maxRank = 150 }
    if setup then setup(env) end
    helpers.login(ns, env)
    return ns, env
end

local function castStart(env)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
end

local function caught(env)
    castStart(env)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    env.__fishingLoot = true
    helpers.fire(env, "LOOT_OPENED")
    helpers.fire(env, "LOOT_CLOSED")
    env.__fishingLoot = false
end

local function gotAway(env)
    castStart(env)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    helpers.fire(env, "UI_ERROR_MESSAGE", 400, "Your fish got away!")
end

--- How the casts logged so far ended, in order.
local function outs(ns)
    local list = {}
    for _, entry in ipairs(ns.db.stats.log) do
        list[#list + 1] = entry.out
    end
    return table.concat(list, ",")
end

describe("hearing a fish get away", function()
    it("logs each cast's end", function()
        local ns, env = loggedIn()
        gotAway(env)
        caught(env)
        assertEqual("away,caught", outs(ns))
    end)

    it("counts a cast once, however often the game says the fish got away", function()
        local ns, env = loggedIn()
        gotAway(env)
        helpers.fire(env, "UI_ERROR_MESSAGE", 400, "Your fish got away!")
        assertEqual("away", outs(ns))
    end)

    it("hears it as a yellow message too", function()
        local ns, env = loggedIn()
        castStart(env)
        helpers.fire(env, "UI_INFO_MESSAGE", 400, "Your fish got away!")
        assertEqual("away", outs(ns))
    end)

    it("leaves out other errors, and a fish getting away without a cast", function()
        local ns, env = loggedIn()
        castStart(env)
        helpers.fire(env, "UI_ERROR_MESSAGE", 50, "You are too far away!")
        assertEqual("", outs(ns))
        local again, againEnv = loggedIn()
        helpers.fire(againEnv, "UI_ERROR_MESSAGE", 400, "Your fish got away!")
        assertEqual("", outs(again))
    end)

    it("puts the cast against the zone it was cast in, though the fish bites elsewhere", function()
        local ns, env = loggedIn()
        castStart(env)
        env.__map = { id = 1425, name = "Arathi Highlands" }
        helpers.fire(env, "UI_ERROR_MESSAGE", 400, "Your fish got away!")
        assertEqual(HILLSBRAD, ns.db.stats.log[1].zone)
    end)

    it("does not count a fish that got away toward the next point", function()
        local ns, env = loggedIn()
        gotAway(env)
        gotAway(env)
        caught(env)
        assertEqual(1, ns.Skill.Catches())
    end)
end)

describe("water the game will not let you fish", function()
    local function refused(env, spellID)
        helpers.fire(env, "UNIT_SPELLCAST_SENT", "player", "", "guid", spellID or 7620)
        helpers.fire(env, "UNIT_SPELLCAST_FAILED", "player", "guid", spellID or 7620)
        helpers.fire(env, "UI_ERROR_MESSAGE", 300, "Skill not high enough")
    end

    it("notes the skill a fishing cast was refused at, in the zone it was cast in", function()
        local ns, env = loggedIn()
        refused(env)
        local water = ns.Water.Read(HILLSBRAD)
        assertEqual(106, water.refused)
        assertEqual("Hillsbrad Foothills", water.name)
    end)

    it("hears the refusal whichever comes first, the message or the failed cast", function()
        local ns, env = loggedIn()
        helpers.fire(env, "UI_ERROR_MESSAGE", 300, "Skill not high enough")
        helpers.fire(env, "UNIT_SPELLCAST_FAILED", "player", "guid", 7620)
        assertEqual(106, ns.Water.Read(HILLSBRAD).refused)
    end)

    it("leaves out the same words said about anything but fishing", function()
        local ns, env = loggedIn()
        refused(env, 774)
        helpers.fire(env, "UI_ERROR_MESSAGE", 300, "Skill not high enough")
        assertNil(ns.Water.Read(HILLSBRAD).refused)
        helpers.fire(env, "UNIT_SPELLCAST_SENT", "player", "", "guid", 7620)
        env.__now = env.__now + 5
        helpers.fire(env, "UI_ERROR_MESSAGE", 300, "Skill not high enough")
        assertNil(ns.Water.Read(HILLSBRAD).refused, "too long after the cast to be its answer")
    end)

    it("keeps the highest skill refused", function()
        local ns, env = loggedIn()
        refused(env)
        env.__fishing.rank = 104
        helpers.fire(env, "SKILL_LINES_CHANGED")
        refused(env)
        assertEqual(106, ns.Water.Read(HILLSBRAD).refused)
    end)

    it("counts refusals players sent in, baked into a release, with the player's own", function()
        local ns, env = loggedIn()
        ns.Water.BAKED[HILLSBRAD] = { refused = 120 }
        refused(env)
        assertEqual(120, ns.Water.Read(HILLSBRAD).refused)
    end)

    it("calls the water too low to land a fish once every fish of five casts got away", function()
        local ns, env = loggedIn()
        for _ = 1, 4 do gotAway(env) end
        assertNil(ns.Water.TooLowFor(HILLSBRAD, 106), "four could be bad luck")
        gotAway(env)
        local reason, casts = ns.Water.TooLowFor(HILLSBRAD, 106)
        assertEqual("away", reason)
        assertEqual(5, casts)
        caught(env)
        assertNil(ns.Water.TooLowFor(HILLSBRAD, 106), "a fish landed: it is not")
    end)

    it("counts only the casts made at the skill or above", function()
        local ns, env = loggedIn()
        for _ = 1, 5 do gotAway(env) end
        assertNil(ns.Water.TooLowFor(HILLSBRAD, 107), "a point up, those casts say nothing")
    end)

    it("counts a lure's bonus in the skill a cast was made at", function()
        local ns, env = loggedIn(function(e) e.__fishing.modifier = 5 end)
        for _ = 1, 5 do gotAway(env) end
        assertEqual("away", (ns.Water.TooLowFor(HILLSBRAD, 111)))
        assertNil(ns.Water.TooLowFor(HILLSBRAD, 112))
    end)

    it("names a refusal first", function()
        local ns, env = loggedIn()
        refused(env)
        local reason, skill = ns.Water.TooLowFor(HILLSBRAD, 106)
        assertEqual("refused", reason)
        assertEqual(106, skill)
    end)

    it("says the skill is too low here while it is no higher than the skill refused", function()
        local ns, env = loggedIn()
        assertFalse(ns.Water.TooLow(ns.Water.Read(HILLSBRAD), 106))
        refused(env)
        assertTrue(ns.Water.TooLow(ns.Water.Read(HILLSBRAD), 106))
        assertFalse(ns.Water.TooLow(ns.Water.Read(HILLSBRAD), 107))
    end)
end)
