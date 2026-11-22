local helpers = require("helpers")

local link = helpers.link

local FRENCH = link("quest", "2945:28", "La fiancée de l'Embaumeur")
local ENGLISH = link("quest", "2945:28", "Bride of the Embalmer")

local function english(env)
    env.__names.quest[2945] = "Bride of the Embalmer"
end

describe("a link in chat", function()
    it("shows by this client's name", function()
        local _, env = helpers.loggedIn(english)
        local shown = helpers.say(env, "Someoe for : " .. FRENCH .. " ?")
        assertEqual("Someoe for : " .. ENGLISH .. " ?", shown)
    end)

    it("still opens the same thing: only the text between the brackets changes", function()
        local _, env = helpers.loggedIn(english)
        local shown = helpers.say(env, FRENCH)
        assertMatch("|Hquest:2945:28|h%[", shown)
        assertMatch("^|cffffff00", shown)
    end)

    it("changes every link in the line", function()
        local _, env = helpers.loggedIn(function(env)
            english(env)
            env.__names.item[19019] = "Thunderfury, Blessed Blade of the Windseeker"
        end)
        local shown = helpers.say(env, FRENCH .. " et " .. link("item", "19019:0:0:0", "Lame-tonnerre"))
        assertEqual(ENGLISH .. " et " .. link("item", "19019:0:0:0", "Thunderfury, Blessed Blade of the Windseeker"),
            shown)
    end)

    it("leaves a line alone when the names already match", function()
        local _, env = helpers.loggedIn(english)
        assertEqual("lf " .. ENGLISH, helpers.say(env, "lf " .. ENGLISH))
    end)

    it("leaves player and channel links alone", function()
        local _, env = helpers.loggedIn()
        local line = "|Hplayer:Tranzalorr:12|h[Tranzalorr]|h |Hchannel:CHANNEL:1|h[1. General]|h"
        assertEqual(line, helpers.say(env, line))
    end)

    it("leaves a link alone when its text holds more than a name", function()
        local _, env = helpers.loggedIn(english)
        local fancy = "|Hquest:2945:28|h[La fiancée |cffff0000rouge|r]|h"
        assertEqual(fancy, helpers.say(env, fancy))
    end)

    it("is translated in whispers, party and guild too", function()
        local _, env = helpers.loggedIn(english)
        for _, event in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_GUILD", "CHAT_MSG_SAY" }) do
            assertEqual(ENGLISH, helpers.say(env, FRENCH, event), event)
        end
    end)

    it("is left as it came in system lines, which the player's own client writes", function()
        local _, env = helpers.loggedIn(english)
        assertNil(env.__filters.CHAT_MSG_SYSTEM)
    end)

    it("is left as it came with the switch off", function()
        local ns, env = helpers.loggedIn(english)
        ns.settings.translate = false
        assertEqual(FRENCH, helpers.say(env, FRENCH))
    end)

    it("hands the sender and the rest of the line on untouched", function()
        local ns, env = helpers.loggedIn(english)
        local filter = env.__filters.CHAT_MSG_CHANNEL[1]
        local results = table.pack(filter(env.ChatFrame1, "CHAT_MSG_CHANNEL", FRENCH, "Tranzalorr", "", "General"))
        assertFalse(results[1], "never thrown away")
        assertEqual(ENGLISH, results[2])
        assertEqual("Tranzalorr", results[3])
        assertEqual("General", results[5])
        assertEqual(5, results.n)
    end)

    it("is hooked into chat once, at login", function()
        local ns, env = helpers.loadAddon()
        assertNil(env.__filters.CHAT_MSG_CHANNEL)
        helpers.login(env)
        ns.Chat.Install()
        assertEqual(1, #env.__filters.CHAT_MSG_CHANNEL)
    end)

    it("uses the old global on a client without ChatFrameUtil", function()
        local _, env = helpers.loggedIn(function(env)
            english(env)
            env.ChatFrameUtil = nil
        end)
        assertEqual(ENGLISH, helpers.say(env, FRENCH))
    end)
end)

describe("a link whose name the client loads after the line arrives", function()
    local function arriving()
        local ns, env = helpers.loggedIn(function(env)
            env.__loadable.quest[2945] = "Bride of the Embalmer"
        end)
        return ns, env
    end

    it("shows as it came at first, and the name is asked for", function()
        local _, env = arriving()
        assertEqual(FRENCH, helpers.say(env, FRENCH))
        assertEqual("quest:2945", env.__requests[1])
    end)

    it("is rewritten in chat once the name arrives", function()
        local _, env = arriving()
        helpers.say(env, "Someoe for : " .. FRENCH .. " ?")
        helpers.finishLoad(env, "quest", 2945)
        assertEqual("Someoe for : " .. ENGLISH .. " ?", env.ChatFrame1:LineText(1))
    end)

    it("keeps the line's colour and position", function()
        local _, env = arriving()
        env.ChatFrame1:AddMessage("before", 1, 1, 1)
        helpers.say(env, FRENCH)
        env.ChatFrame1:AddMessage("after", 1, 1, 1)
        helpers.finishLoad(env, "quest", 2945)
        assertEqual("before", env.ChatFrame1:LineText(1))
        assertEqual(ENGLISH, env.ChatFrame1:LineText(2))
        assertEqual(0.75, env.ChatFrame1.lines[2][3])
        assertEqual("after", env.ChatFrame1:LineText(3))
    end)

    it("is rewritten in every chat window that shows it", function()
        local _, env = arriving()
        helpers.say(env, FRENCH, nil, env.ChatFrame1)
        helpers.say(env, FRENCH, nil, env.ChatFrame2)
        helpers.finishLoad(env, "quest", 2945)
        assertEqual(ENGLISH, env.ChatFrame1:LineText(1))
        assertEqual(ENGLISH, env.ChatFrame2:LineText(1))
    end)

    it("leaves lines about another quest alone, even one whose id starts the same", function()
        local _, env = arriving()
        local other = link("quest", "29450:30", "Autre")
        env.ChatFrame1:AddMessage(other, 1, 1, 1)
        helpers.say(env, FRENCH)
        helpers.finishLoad(env, "quest", 2945)
        assertEqual(other, env.ChatFrame1:LineText(1))
    end)

    it("steps over a secret line it cannot read", function()
        local _, env = arriving()
        local secret = env.__secret()
        env.ChatFrame1:AddMessage(secret, 1, 1, 1)
        helpers.say(env, FRENCH)
        helpers.finishLoad(env, "quest", 2945)
        assertEqual(secret, env.ChatFrame1:LineText(1))
        assertEqual(ENGLISH, env.ChatFrame1:LineText(2))
    end)

    it("stays as it came if the switch is turned off meanwhile", function()
        local ns, env = arriving()
        helpers.say(env, FRENCH)
        ns.settings.translate = false
        helpers.finishLoad(env, "quest", 2945)
        assertEqual(FRENCH, env.ChatFrame1:LineText(1))
    end)

    it("stays as it came on a client whose chat windows cannot be rewritten", function()
        local _, env = arriving()
        env.ChatFrame1.TransformMessages = nil
        helpers.say(env, FRENCH)
        helpers.finishLoad(env, "quest", 2945)
        assertEqual(FRENCH, env.ChatFrame1:LineText(1))
    end)
end)

describe("/lt on and off", function()
    it("switches translating off and on", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "off")
        assertFalse(ns.settings.translate)
        assertMatch("left as they are sent", helpers.printed(env))
        helpers.command(env, "on")
        assertTrue(ns.settings.translate)
        assertMatch("in your game's language", helpers.printed(env))
    end)
end)
