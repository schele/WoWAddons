local helpers = require("helpers")

local function names(list)
    local out = {}
    for index, row in ipairs(list.rows) do
        out[index] = row.name
    end
    return table.concat(out, ", ")
end

local PARTY = {
    { "party1", "Brann", "ROGUE" },
    { "party2", "Celia", "MAGE" },
    { "party3", "Dorn", "PRIEST" },
}

describe("which mob", function()
    it("is your target when you can attack it", function()
        local ns, env = helpers.loggedIn()
        helpers.mob(env, "mob", "Defias Pillager")
        helpers.target(env, "mob")

        assertEqual("target", ns.Threat.Mob())
    end)

    it("is none with nothing targeted", function()
        local ns = helpers.loggedIn()

        assertNil(ns.Threat.Mob())
    end)

    it("is none when the target is dead", function()
        local ns, env = helpers.loggedIn()
        helpers.mob(env, "mob", "Defias Pillager").dead = true
        helpers.target(env, "mob")

        assertNil(ns.Threat.Mob())
    end)

    it("is a friendly target's target, so a healer on the tank sees the tank's mob", function()
        local ns, env = helpers.loggedIn(function(env) helpers.member(env, "party1", "Brann", "WARRIOR") end)
        helpers.mob(env, "mob", "Defias Pillager")
        env.__units.targettarget = env.__units.mob
        helpers.target(env, "party1")

        assertEqual("targettarget", ns.Threat.Mob())
    end)

    it("is none for a friendly target with no enemy targeted", function()
        local ns, env = helpers.loggedIn(function(env) helpers.member(env, "party1", "Brann", "WARRIOR") end)
        helpers.target(env, "party1")

        assertNil(ns.Threat.Mob())
    end)
end)

describe("whose threat", function()
    it("is yours alone when you are alone", function()
        local ns = helpers.loggedIn()

        assertEqual("player", table.concat(ns.Threat.Units(), ","))
    end)

    it("takes in your pet", function()
        local ns = helpers.loggedIn(function(env) helpers.member(env, "pet", "Wolf") end)

        assertEqual("player,pet", table.concat(ns.Threat.Units(), ","))
    end)

    it("takes in the party and their pets", function()
        local ns = helpers.loggedIn(function(env)
            helpers.member(env, "party1", "Brann", "HUNTER")
            helpers.member(env, "partypet1", "Cat")
            helpers.member(env, "party2", "Celia", "MAGE")
        end)

        assertEqual("player,party1,partypet1,party2", table.concat(ns.Threat.Units(), ","))
    end)

    it("takes in the raid, without you twice", function()
        local ns = helpers.loggedIn(function(env)
            env.__units.raid1 = { name = "Brann", classFile = "ROGUE" }
            env.__units.raid2 = env.__units.player
            env.__units.raid3 = { name = "Celia", classFile = "MAGE" }
            env.__raid = { "raid1", "raid2", "raid3" }
        end)

        assertEqual("player,raid1,raid3", table.concat(ns.Threat.Units(), ","))
    end)
end)

describe("reading the threat list", function()
    it("lists everyone on it, the most threat first", function()
        local ns = helpers.fighting({ player = 100, party1 = 72, party2 = 91 }, PARTY)

        local list = ns.Threat.Read()
        assertEqual("Skyler, Celia, Brann", names(list), "Dorn has no threat and is left out")
        assertEqual(91, list.rows[2].scaled)
        assertEqual("MAGE", list.rows[2].classFile)
        assertFalse(list.secret)
    end)

    it("marks who is tanking and which row is you", function()
        local ns = helpers.fighting({ player = 64, party1 = 100 }, PARTY)

        local list = ns.Threat.Read()
        assertEqual("Brann", list.rows[1].name)
        assertTrue(list.rows[1].tanking, "Brann tanks")
        assertTrue(list.rows[2].isPlayer, "the second row is you")
        assertFalse(list.rows[2].tanking)
    end)

    it("has nothing to read without a mob", function()
        local ns = helpers.loggedIn()

        local list = ns.Threat.Read()
        assertNil(list.mob)
        assertEqual(0, #list.rows)
    end)

    it("names the mob", function()
        local ns = helpers.fighting({ player = 100 })

        assertEqual("Defias Pillager", ns.Threat.Read().name)
    end)
end)

describe("on a boss", function()
    -- The game hides the numbers, but not who is tanking or over the tank.
    local function bossFight()
        local ns, env = helpers.loggedIn(function(env)
            for _, member in ipairs(PARTY) do helpers.member(env, member[1], member[2], member[3]) end
        end)
        helpers.mob(env, "mob", "Edwin VanCleef", { boss = true })
        helpers.target(env, "mob")
        helpers.combat(env, true)
        helpers.threat(env, "party2", 60, 0)
        helpers.threat(env, "player", 80, 0)
        helpers.threat(env, "party1", 100, 3)
        helpers.threat(env, "party3", 95, 1)
        return ns, env
    end

    it("says the numbers are hidden and hands them on as they came", function()
        local ns, env = bossFight()

        local list = ns.Threat.Read()
        assertTrue(list.secret)
        assertTrue(env.issecretvalue(list.rows[1].scaled))
    end)

    it("orders by what the game still says: the tank, anyone over the tank, you, then the group", function()
        local ns = bossFight()

        assertEqual("Brann, Dorn, Skyler, Celia", names(ns.Threat.Read()))
    end)

    it("still knows who is tanking", function()
        local ns = bossFight()

        local list = ns.Threat.Read()
        assertTrue(list.rows[1].tanking)
        assertEqual(1, list.rows[2].status)
    end)
end)

describe("keeping up", function()
    it("tells listeners when the threat list changes", function()
        local ns, env = helpers.fighting({ player = 100 })
        local heard
        ns.Threat.OnUpdate(function(list) heard = list end)

        helpers.threat(env, "player", 100)

        assertTrue(heard ~= nil, "heard")
        assertEqual("Skyler", heard.rows[1].name)
    end)

    it("knows when you are in combat", function()
        local ns, env = helpers.fighting({ player = 100 })
        assertTrue(ns.Threat.InCombat())

        helpers.combat(env, false)
        assertFalse(ns.Threat.InCombat())
    end)
end)

describe("/threat check", function()
    it("says what it reads on your target", function()
        local ns, env = helpers.fighting({ player = 64, party1 = 100 }, PARTY)

        helpers.command(env, "check")

        local text = helpers.printed(env)
        assertMatch("Defias Pillager: the game shows the numbers%.", text)
        assertMatch("Brann 100%% %(tanking%)", text)
        assertMatch("Skyler 64%%", text)
    end)

    it("says when the game hides the numbers", function()
        local ns, env = helpers.loggedIn()
        helpers.mob(env, "mob", "Edwin VanCleef", { boss = true })
        helpers.target(env, "mob")
        helpers.threat(env, "player", 100, 3)

        helpers.command(env, "check")

        local text = helpers.printed(env)
        assertMatch("Edwin VanCleef: the game hides the numbers%.", text)
        assertMatch("Skyler hidden %(tanking%)", text)
    end)

    it("calls the mob your target when the game hides its name", function()
        local _, env = helpers.fighting({ player = 100 })
        env.__units.mob.name = env.__secret()

        helpers.command(env, "check")

        assertMatch("Your target: the game shows the numbers%.", helpers.printed(env))
    end)

    it("says when there is nothing to read", function()
        local _, env = helpers.loggedIn()

        helpers.command(env, "check")

        assertMatch("No enemy targeted%.", helpers.printed(env))
    end)
end)
