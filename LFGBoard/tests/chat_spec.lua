local helpers = require("helpers")

local function rows(ns)
    return ns.Posts.Visible(helpers.ALL)
end

describe("chat", function()
    it("puts a recruiting channel message on the board", function()
        local ns, env = helpers.loggedIn()

        helpers.say(env, "Garrok", "LF2M DM need heals")

        assertEqual(1, #rows(ns))
    end)

    it("takes guild chat too, the word guild and all", function()
        local ns, env = helpers.loggedIn()

        helpers.guild(env, "Brakk", "LFM DM guild run")

        assertEqual(1, #rows(ns))
    end)

    it("skips the defence channels", function()
        local ns, env = helpers.loggedIn()

        helpers.say(env, "Garrok", "LFM DM need tank", { channel = "LocalDefense" })

        assertEqual(0, #rows(ns))
    end)

    it("skips your own messages", function()
        local ns, env = helpers.loggedIn()

        helpers.say(env, "Skyler", "LFM DM need tank")
        helpers.say(env, "Skyler-Aldira", "LFM WC need tank")

        assertEqual(0, #rows(ns))
    end)

    it("knows a sender's class from their GUID", function()
        local ns, env = helpers.loggedIn()
        env.__guids["Player-1"] = "WARRIOR"

        helpers.say(env, "Garrok", "LF2M DM need heals", { guid = "Player-1" })

        assertEqual("WARRIOR", rows(ns)[1].class)
    end)

    it("alerts for a message that wants you", function()
        local _, env = helpers.loggedIn()

        helpers.say(env, "Garrok", "LF1M DM need tank")

        assertEqual(1, #env.__sounds)
        assertMatch("wants a tank", helpers.printed(env))
    end)

    it("sweeps out messages older than ten minutes", function()
        local ns, env = helpers.loggedIn()
        helpers.say(env, "Garrok", "LFM DM")

        helpers.later(env, 601)
        env.__runTimers()

        assertEqual(0, #rows(ns))
    end)

    it("keeps going after a message it cannot read", function()
        local ns, env = helpers.loggedIn()

        helpers.say(env, nil, "LFM DM")
        helpers.say(env, "Garrok", nil)
        helpers.say(env, "Garrok", "LFM DM")

        assertEqual(1, #rows(ns))
    end)
end)
