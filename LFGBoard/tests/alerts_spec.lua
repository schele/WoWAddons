local helpers = require("helpers")

local function posted(ns, name, text)
    return ns.Posts.View(ns.Posts.AddChat({ name = name, text = text, time = 1000 }))
end

describe("an alert", function()
    it("sounds and says so for a group that wants one of your roles near your level", function()
        local ns, env = helpers.loggedIn()

        assertTrue(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank")))

        assertEqual(3081, env.__sounds[1])
        local printed = helpers.printed(env)
        assertMatch("Garrok wants a tank for Deadmines%.", printed)
        assertMatch("|Hlfgboard:whisper:garrok|h", printed)
    end)

    it("comes once per person and activity", function()
        local ns, env = helpers.loggedIn()
        local first = posted(ns, "Garrok", "LF1M DM need tank")

        ns.Alerts.Consider(first)
        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank, still")))

        assertEqual(1, #env.__sounds)
    end)

    it("comes again when the same person posts for another dungeon", function()
        local ns = helpers.loggedIn()

        ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank"))

        assertTrue(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M SFK need tank")))
    end)

    it("does not come for a group that does not ask for your roles", function()
        local ns = helpers.loggedIn()
        ns.Roles().healer = false

        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need heals")))
    end)

    it("does not come for a group that does not say what it wants", function()
        local ns = helpers.loggedIn()

        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LFM DM")))
    end)

    it("does not come for a dungeon far from your level", function()
        local ns = helpers.loggedIn()

        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LFM BFD need tank")))
    end)

    it("does not come while you are in a group", function()
        local ns, env = helpers.loggedIn()
        env.__inGroup = true

        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank")))
    end)

    it("does not come with the switch off", function()
        local ns = helpers.loggedIn()
        ns.db.alerts = false

        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank")))
    end)
end)

describe("an alert's link", function()
    it("opens the whisper", function()
        local ns, env = helpers.loggedIn()
        ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank"))

        env.SetItemRef("lfgboard:whisper:garrok")

        assertEqual("/w Garrok Hi! Level 20 feral druid, tank. Room for me in Deadmines?", env.__openedChat)
    end)

    it("still opens the whisper after the row has gone", function()
        local ns, env = helpers.loggedIn()
        ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank"))
        ns.Posts.Expire(99999)

        env.SetItemRef("lfgboard:whisper:garrok")

        assertMatch("^/w Garrok Hi!", env.__openedChat)
    end)

    it("leaves every other link to the game", function()
        local ns, env = helpers.loggedIn()

        env.SetItemRef("item:1234")

        assertNil(env.__openedChat)
        assertEqual("item:1234", env.__itemRefs[1])
    end)
end)

describe("an alert for something the board does not know", function()
    it("does not come, however it asks", function()
        local ns = helpers.loggedIn()

        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LFM new dungeon Blackroot need tank")))
    end)
end)

describe("an alert for a quest you have completed", function()
    local DEFIAS = "LF1M need tank |cffffff00|Hquest:155:18|h[The Defias Brotherhood]|h|r"

    it("does not come while completed quests are hidden", function()
        local ns, env = helpers.loggedIn()
        env.__completedQuests[155] = true

        assertFalse(ns.Alerts.Consider(posted(ns, "Brakk", DEFIAS)))
        assertEqual(0, #env.__sounds)
    end)

    it("comes when they are shown", function()
        local ns, env = helpers.loggedIn()
        env.__completedQuests[155] = true
        ns.db.hideCompleted = false

        assertTrue(ns.Alerts.Consider(posted(ns, "Brakk", DEFIAS)))
    end)
end)

describe("an alert and the classes a group asks for", function()
    -- The player is a druid.
    it("does not come when the group turns your class away", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank no druids")))
    end)

    it("does not come when the group asks only for classes that are not yours", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need tank, warrior or paladin")))
    end)

    it("comes when the group asks for your class, though it names no role", function()
        local ns, env = helpers.loggedIn()
        assertTrue(ns.Alerts.Consider(posted(ns, "Garrok", "LF1M DM need druid")))
        assertMatch("Garrok wants a Druid for Deadmines%.", helpers.printed(env))
    end)

    it("does not come for a group that says it is full", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Alerts.Consider(posted(ns, "Garrok", "LFM DM 5/5 need tank")))
    end)
end)
