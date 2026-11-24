local helpers = require("helpers")

local POLE = 6256
local HILLSBRAD = 1424
local BLACKMOUTH = { id = 6358, name = "Oily Blackmouth" }
local ALBACORE = { id = 13754, name = "Raw Rainbow Fin Albacore" }

--- Logged in holding a pole, at skill 106 of 150 in Southshore, Hillsbrad
-- Foothills (level 20 to 30). `setup` runs before login, on the env.
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

local function skillUp(env)
    env.__fishing.rank = env.__fishing.rank + 1
    helpers.fire(env, "SKILL_LINES_CHANGED")
end

--- A cast, and `fish` on the line ({ id, name }, Oily Blackmouth by default).
-- `point` brings a skill point: "before" the loot or "after" it.
local function caught(env, fish, point)
    castStart(env)
    helpers.fire(env, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    if point == "before" then skillUp(env) end
    env.__fishingLoot = true
    env.__loot = { fish or BLACKMOUTH }
    helpers.fire(env, "LOOT_OPENED")
    if point == "after" then skillUp(env) end
    helpers.fire(env, "LOOT_CLOSED")
    env.__fishingLoot = false
    env.__loot = {}
end

local function gotAway(env)
    castStart(env)
    helpers.fire(env, "UI_ERROR_MESSAGE", 400, "Your fish got away!")
end

local function refused(env)
    helpers.fire(env, "UNIT_SPELLCAST_SENT", "player", "", "guid", 7620)
    helpers.fire(env, "UI_ERROR_MESSAGE", 300, "Skill not high enough")
end

local function last(ns)
    local log = ns.db.stats.log
    return log[#log]
end

describe("the fishing log", function()
    it("notes a catch with its fish, the skill, the zone and its level, where, and who", function()
        local ns, env = loggedIn()
        caught(env)
        local entry = last(ns)
        assertEqual("caught", entry.out)
        assertEqual(1, entry.fish[6358])
        assertEqual(106, entry.skill)
        assertEqual(150, entry.max)
        assertEqual(HILLSBRAD, entry.zone)
        assertEqual("Southshore", entry.sub)
        assertEqual(20, entry.zlo)
        assertEqual(30, entry.zhi)
        assertEqual(0.5, entry.x)
        assertEqual(0.6, entry.y)
        assertEqual("Aldira", entry.who)
        assertEqual(34, entry.lvl)
        assertEqual(1764000000, entry.t)
        assertEqual("Oily Blackmouth", ns.db.stats.items[6358])
        assertEqual("Hillsbrad Foothills", ns.db.stats.zones[HILLSBRAD])
    end)

    it("notes a fish that got away", function()
        local ns, env = loggedIn()
        gotAway(env)
        assertEqual("away", last(ns).out)
        assertNil(last(ns).fish)
    end)

    it("notes a cast the game refused for too little skill", function()
        local ns, env = loggedIn()
        refused(env)
        assertEqual("refused", last(ns).out)
        assertEqual(106, last(ns).skill)
    end)

    it("marks the catch that brought a point, the point coming after its loot", function()
        local ns, env = loggedIn()
        caught(env, nil, "after")
        assertEqual(107, last(ns).point)
        assertEqual(106, last(ns).skill, "the skill it was caught at")
    end)

    it("marks the catch that brought a point, the point coming before its loot", function()
        local ns, env = loggedIn()
        caught(env)
        caught(env, nil, "before")
        assertNil(ns.db.stats.log[1].point)
        assertEqual(107, ns.db.stats.log[2].point)
        assertEqual(106, ns.db.stats.log[2].skill)
    end)

    it("notes what a lure or gear adds, and counts it in the skill a refusal was at", function()
        local ns, env = loggedIn(function(e) e.__fishing.modifier = 25 end)
        gotAway(env)
        assertEqual(25, last(ns).bonus)
        assertEqual(106, last(ns).skill, "the skill itself, with the bonus beside it")
        refused(env)
        assertEqual(131, ns.Water.Read(HILLSBRAD).refused)
    end)

    it("keeps only the newest entries", function()
        local ns, env = loggedIn()
        ns.Stats.LIMIT = 3
        for index = 1, 5 do
            env.__clock = 1764000000 + index
            caught(env)
        end
        assertEqual(3, #ns.db.stats.log)
        assertEqual(1764000003, ns.db.stats.log[1].t)
    end)
end)

describe("the stats put together", function()
    it("counts each zone by skill, highest skill first, with the fish and the points", function()
        local ns, env = loggedIn()
        caught(env, BLACKMOUTH)
        gotAway(env)
        caught(env, ALBACORE, "after")
        caught(env, ALBACORE)
        refused(env)

        local zone = ns.Stats.Zone(HILLSBRAD)
        assertEqual("Hillsbrad Foothills", zone.name)
        assertEqual(20, zone.zlo)
        assertEqual(30, zone.zhi)
        assertEqual(3, zone.caught)
        assertEqual(1, zone.away)
        assertEqual(1, zone.refused)
        assertEqual(1, zone.points)
        assertEqual(1, zone.fish[6358])
        assertEqual(2, zone.fish[13754])

        assertEqual(107, zone.rows[1].skill)
        assertEqual(1, zone.rows[1].caught)
        assertEqual(1, zone.rows[1].refused)
        assertEqual(106, zone.rows[2].skill)
        assertEqual(2, zone.rows[2].caught)
        assertEqual(1, zone.rows[2].away)
        assertEqual(1, zone.rows[2].points)
        assertEqual(3, zone.rows[2].subs.Southshore)
    end)

    it("puts skills together in tens, each from the lowest to the highest skill fished in it", function()
        local ns = loggedIn()
        local function row(skill, caught, away, refused, points, fish, subs)
            return {
                skill = skill, caught = caught, away = away, refused = refused, points = points,
                fish = fish, subs = subs, bonus = { [0] = caught + away + refused }, levels = { [34] = 1 },
            }
        end
        local bands = ns.Stats.Bands({
            row(112, 1, 0, 0, 0, { [6358] = 1 }, { Southshore = 1 }),
            row(107, 2, 1, 0, 1, { [6358] = 2 }, { Southshore = 3 }),
            row(106, 1, 0, 1, 1, { [13754] = 1 }, { ["Lordamere Lake"] = 2 }),
        })
        assertEqual(2, #bands)
        assertEqual(112, bands[1].from)
        assertEqual(112, bands[1].to)
        local band = bands[2]
        assertEqual(106, band.from)
        assertEqual(107, band.to)
        assertEqual(3, band.caught)
        assertEqual(1, band.away)
        assertEqual(1, band.refused)
        assertEqual(2, band.points)
        assertEqual(2, band.fish[6358], "112's fish is in the band above")
        assertEqual(1, band.fish[13754])
        assertEqual(3, band.subs.Southshore)
        assertEqual(2, band.levels[34])
        assertEqual(1.5, band.perPoint, "the catches at the skills that gave a point, over the points")
        assertTrue(math.abs(band.rule - 2.26) < 1e-9, "the old rule's catches a point at those skills")
    end)

    it("lists the zones fished, the latest first", function()
        local ns, env = loggedIn()
        caught(env)
        env.__map = { id = 1436, name = "Westfall", levels = { 10, 20 } }
        env.__clock = env.__clock + 60
        caught(env)
        local zones = ns.Stats.Zones()
        assertEqual(1436, zones[1])
        assertEqual(HILLSBRAD, zones[2])
    end)
end)
