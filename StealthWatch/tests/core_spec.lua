local helpers = require("helpers")

describe("/sw help", function()
    it("lists the commands", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "help")
        local text = helpers.printed(env)
        assertMatch("/sw test %- ", text)
        assertMatch("/sw probe %- ", text)
    end)

    it("is what an unknown command gets", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "dance")
        local text = helpers.printed(env)
        assertMatch("Unknown command: dance", text)
        assertMatch("/sw test %- ", text)
    end)
end)

describe("logging in", function()
    it("is quiet with enemy nameplates on", function()
        local ns, env = helpers.loggedIn()
        assertEqual("", helpers.printed(env))
    end)

    it("warns that only the target is watched while enemy nameplates are off", function()
        local ns, env = helpers.loggedIn(function(env) env.__cvars.nameplateShowEnemies = "0" end)
        assertMatch("Enemy nameplates are off, so StealthWatch only sees your target%. Press V to show them%.",
            helpers.printed(env))
    end)
end)

describe("/sw probe", function()
    local function probe(setup)
        local ns, env = helpers.loggedIn(setup)
        helpers.command(env, "probe")
        return helpers.printed(env), ns, env
    end

    it("says enemy nameplates are on, and how far they reach", function()
        assertMatch("Enemy nameplates: on, out to 41 yards%.", (probe()))
    end)

    it("says enemy nameplates are off", function()
        local text = probe(function(env) env.__cvars.nameplateShowEnemies = "0" end)
        assertMatch("Enemy nameplates: off%. Press V to show them%.", text)
    end)

    it("names the stealth spells the client knows, each once", function()
        assertMatch("Stealth spells this client knows: Stealth, Vanish, Prowl, Shadowmeld, Lesser Invisibility, Invisibility%.",
            (probe()))
    end)

    it("leaves out a stealth spell the client does not know", function()
        local text = probe(function(env)
            local known = env.C_Spell.GetSpellName
            env.C_Spell.GetSpellName = function(id) if id ~= 20580 then return known(id) end end
        end)
        assertMatch("knows: Stealth, Vanish, Prowl, Lesser Invisibility, Invisibility%.", text)
    end)

    it("says how the client shows other players' casts of each", function()
        local text = probe(function(env)
            env.__castSecrecy = { [1784] = 2, [1856] = 0, [5215] = 1 }
        end)
        assertMatch("Stealth hidden at times", text)
        assertMatch("Vanish never hidden", text)
        assertMatch("Prowl always hidden", text)
        assertMatch("Shadowmeld unknown", text)
    end)

    it("says when the client hides no casts at all", function()
        local text = probe(function(env) env.C_Secrets = nil end)
        assertMatch("This client hides no casts%.", text)
    end)

    it("counts the casts heard since login, named and hidden", function()
        local ns, env = helpers.loggedIn()
        helpers.plateAdded(env, "nameplate1", env.__enemy("Sneaky"))
        helpers.cast(env, "nameplate1", 2983)
        helpers.cast(env, "nameplate1", env.__secret())
        helpers.command(env, "probe")
        assertMatch("Casts heard since login: 1 named, 1 hidden%.", helpers.printed(env))
    end)
end)
