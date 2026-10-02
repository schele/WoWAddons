local helpers = require("helpers")

local function chat(ns, name, text, time)
    return ns.Posts.AddChat({ name = name, text = text, time = time or 1000 })
end

local function listing(ns, id, leader, members, key, extra)
    local activity = ns.Activities.ByKey(key)
    local made = {
        resultID = id, leader = leader, members = members, activity = activity,
        kind = activity.kind, max = activity.kind == "raid" and 40 or 5, comment = "",
        full = false, delisted = false,
    }
    for field, value in pairs(extra or {}) do
        made[field] = value
    end
    return made
end

local function visible(ns, filter)
    return ns.Posts.Visible(filter or helpers.ALL)
end

describe("a row from chat", function()
    it("is made from a recruiting message", function()
        local ns = helpers.loadAddon()

        chat(ns, "Garrok", "LF2M DM need heals")

        local rows = visible(ns)
        assertEqual(1, #rows)
        assertEqual("Garrok", rows[1].name)
        assertEqual("dungeon", rows[1].kind)
        assertEqual("dm", rows[1].activity.key)
        assertEqual("chat", rows[1].source)
        assertEqual(3, rows[1].size.have)
        assertTrue(rows[1].roles.healer)
    end)

    it("is not made from chatter", function()
        local ns = helpers.loadAddon()

        assertNil(chat(ns, "Garrok", "selling linen"))
        assertEqual(0, #visible(ns))
    end)

    it("is one per person, the newest message's", function()
        local ns = helpers.loadAddon()

        chat(ns, "Garrok", "LFM WC", 1000)
        chat(ns, "Garrok", "LFM SFK", 1060)

        local rows = visible(ns)
        assertEqual(1, #rows)
        assertEqual("sfk", rows[1].activity.key)
        assertEqual(1060, rows[1].time)
    end)

    it("leaves a row alone when the person says something else", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LFM WC", 1000)

        chat(ns, "Garrok", "thanks all", 1030)

        local rows = visible(ns)
        assertEqual(1, #rows)
        assertEqual("wc", rows[1].activity.key)
        assertEqual(1000, rows[1].time)
    end)

    it("goes when the person says full", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LFM DM")

        chat(ns, "Garrok", "full")

        assertEqual(0, #visible(ns))
    end)

    it("drops off 10 minutes after its message", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LFM DM", 1000)

        ns.Posts.Expire(1599)
        assertEqual(1, #visible(ns))

        ns.Posts.Expire(1600)
        assertEqual(0, #visible(ns))
    end)

    it("comes newest first", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LFM DM", 1000)
        chat(ns, "Brakk", "LFM WC", 1100)

        assertEqual("Brakk", visible(ns)[1].name)
    end)

    it("keeps the whisper name with its realm, and shows the name without", function()
        local ns = helpers.loadAddon()

        chat(ns, "Garrok-Aldira", "LFM DM")

        local row = visible(ns)[1]
        assertEqual("Garrok", row.name)
        assertEqual("Garrok-Aldira", row.whisperName)
    end)
end)

describe("a row from the group finder", function()
    it("shows the group's members and the roles it has room for", function()
        local ns = helpers.loadAddon()

        ns.Posts.SetListings({ listing(ns, 1, "Elandra", {
            { role = "dps", class = "MAGE" }, { role = "tank", class = "WARRIOR" },
        }, "wc") }, 1000)

        local row = visible(ns)[1]
        assertEqual("finder", row.source)
        assertEqual(2, #row.members)
        assertEqual(2, row.size.have)
        assertEqual(5, row.size.of)
        assertTrue(row.roles.healer)
        assertTrue(row.roles.dps)
        assertNil(row.roles.tank)
    end)

    it("is merged with the leader's chat message", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LF2M DM need heals", 1000)

        ns.Posts.SetListings({ listing(ns, 1, "Garrok", {
            { role = "tank", class = "WARRIOR" }, { role = "dps", class = "ROGUE" }, { role = "dps", class = "MAGE" },
        }, "dm") }, 1010)

        local rows = visible(ns)
        assertEqual(1, #rows)
        assertEqual("both", rows[1].source)
        assertEqual("LF2M DM need heals", rows[1].text)
        assertTrue(rows[1].roles.healer)
        assertNil(rows[1].roles.dps, "the message's words, not the guess from the members")
    end)

    it("takes a full listing's leader off the board, chat message and all", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LF1M DM need heals")

        ns.Posts.PutListing(listing(ns, 1, "Garrok", {}, "dm", { full = true }), 1010)

        assertEqual(0, #visible(ns))
    end)

    it("goes when it delists", function()
        local ns = helpers.loadAddon()
        ns.Posts.SetListings({ listing(ns, 1, "Elandra", {}, "wc") }, 1000)

        ns.Posts.DropListing(1)

        assertEqual(0, #visible(ns))
    end)

    it("is replaced by the next search's, and chat rows stay", function()
        local ns = helpers.loadAddon()
        ns.Posts.SetListings({ listing(ns, 1, "Elandra", {}, "wc") }, 1000)
        chat(ns, "Brakk", "LFM SFK", 1010)

        ns.Posts.SetListings({ listing(ns, 2, "Vexxa", {}, "sfk") }, 1100)

        local names = {}
        for _, row in ipairs(visible(ns)) do
            names[row.name] = true
        end
        assertTrue(names.Brakk)
        assertTrue(names.Vexxa)
        assertNil(names.Elandra)
    end)

    it("an empty search clears the finder rows and keeps chat", function()
        local ns = helpers.loadAddon()
        ns.Posts.SetListings({ listing(ns, 1, "Elandra", {}, "wc") }, 1000)
        chat(ns, "Brakk", "LFM SFK", 1010)

        ns.Posts.SetListings({}, 1100)

        local rows = visible(ns)
        assertEqual(1, #rows)
        assertEqual("Brakk", rows[1].name)
    end)

    it("keeps the time it was first seen across searches", function()
        local ns = helpers.loadAddon()
        ns.Posts.SetListings({ listing(ns, 1, "Elandra", {}, "wc") }, 1000)

        ns.Posts.SetListings({ listing(ns, 1, "Elandra", {}, "wc") }, 1200)

        assertEqual(1000, visible(ns)[1].time)
    end)

    it("drops off 10 minutes after the search that last saw it", function()
        local ns = helpers.loadAddon()
        ns.Posts.SetListings({ listing(ns, 1, "Elandra", {}, "wc") }, 1000)

        ns.Posts.Expire(1600)

        assertEqual(0, #visible(ns))
    end)
end)

describe("the filters", function()
    local function board(ns)
        chat(ns, "Garrok", "LFM DM need tank", 1000)
        chat(ns, "Aurelius", "LFM MC need heals", 1001)
        chat(ns, "Brakk", "LF2M quest Hogger", 1002)
        chat(ns, "Vexxa", "LFM new dungeon Blackroot", 1003)
    end

    it("show only the tab's kind, with Other under All alone", function()
        local ns = helpers.loadAddon()
        board(ns)

        local function count(tab)
            return #visible(ns, { tab = tab, roles = helpers.ALL.roles })
        end
        assertEqual(4, count("all"))
        assertEqual(1, count("dungeon"))
        assertEqual(1, count("raid"))
        assertEqual(1, count("quest"))
    end)

    it("count each tab under the other filters", function()
        local ns = helpers.loadAddon()
        board(ns)

        local counts = ns.Posts.Counts(helpers.ALL)

        assertEqual(4, counts.all)
        assertEqual(1, counts.dungeon)
        assertEqual(1, counts.quest)
        assertEqual(1, counts.raid)
    end)

    it("show a group that wants one of your roles or does not say, and hide one wanting only others", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LFM DM need heals", 1000)
        chat(ns, "Elandra", "LFM WC need tank", 1001)
        chat(ns, "Vexxa", "LFM SFK", 1002)

        local rows = visible(ns, { tab = "all", roles = { tank = true, dps = true } })

        assertEqual(2, #rows)
        assertEqual("Vexxa", rows[1].name)
        assertEqual("Elandra", rows[2].name)
    end)

    it("hide dungeons and raids far from your level when asked, but not quests or Other", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LFM DM", 1000)
        chat(ns, "Elandra", "LFM BFD", 1001)
        chat(ns, "Aurelius", "LFM MC", 1002)
        chat(ns, "Brakk", "LF2M quest Hogger", 1003)

        local rows = visible(ns, { tab = "all", roles = helpers.ALL.roles, nearLevel = true, level = 20 })

        assertEqual(2, #rows)
        assertEqual("Brakk", rows[1].name)
        assertEqual("Garrok", rows[2].name)
    end)

    it("show one activity when one is picked", function()
        local ns = helpers.loadAddon()
        board(ns)

        local rows = visible(ns, { tab = "all", roles = helpers.ALL.roles, activity = ns.Activities.ByKey("dm") })

        assertEqual(1, #rows)
        assertEqual("Garrok", rows[1].name)
    end)

    it("list the activities on the board by name, for the picker", function()
        local ns = helpers.loadAddon()
        chat(ns, "Garrok", "LFM DM", 1000)
        chat(ns, "Vexxa", "LFM SFK", 1001)
        chat(ns, "Brakk", "LF2M quest Hogger", 1002)

        local activities = ns.Posts.Activities()

        assertEqual(2, #activities)
        assertEqual("sfk", activities[1].key)
        assertEqual("dm", activities[2].key)
    end)
end)

describe("a group wanting you", function()
    it("is one that asks for a role you play", function()
        local ns = helpers.loadAddon()
        local mine = { tank = true, dps = true }

        assertFalse(ns.Posts.WantsMe({ roles = { healer = true } }, mine))
        assertTrue(ns.Posts.WantsMe({ roles = { dps = true } }, mine))
        assertFalse(ns.Posts.WantsMe({ roles = nil }, mine))
    end)
end)

describe("completed quests", function()
    local DEFIAS = "LF2M |cffffff00|Hquest:155:18|h[The Defias Brotherhood]|h|r"
    local HIDING = { tab = "all", roles = helpers.ALL.roles, hideCompleted = true }

    it("hide a quest group whose linked quest you have completed, when asked", function()
        local ns, env = helpers.loadAddon()
        env.__completedQuests[155] = true
        chat(ns, "Brakk", DEFIAS)

        assertEqual(0, #visible(ns, HIDING))
        assertEqual(0, ns.Posts.Counts(HIDING).quest)
        assertEqual(1, #visible(ns), "shown when not asked")
    end)

    it("keep a quest group whose quest you have not completed", function()
        local ns = helpers.loadAddon()
        chat(ns, "Brakk", DEFIAS)

        assertEqual(1, #visible(ns, HIDING))
    end)

    it("keep a quest group with one of its linked quests still to do", function()
        local ns, env = helpers.loadAddon()
        env.__completedQuests[155] = true
        chat(ns, "Brakk", DEFIAS .. " |cffffff00|Hquest:166:22|h[The Defias Brotherhood]|h|r")

        assertEqual(1, #visible(ns, HIDING))
    end)

    it("keep a quest group that names its quest only in words", function()
        local ns = helpers.loadAddon()
        chat(ns, "Brakk", "LF2M quest Hogger")

        assertEqual(1, #visible(ns, HIDING))
    end)

    it("keep a dungeon group, though it links a quest you have done", function()
        local ns, env = helpers.loadAddon()
        env.__completedQuests[155] = true
        chat(ns, "Garrok", "LFM DM |cffffff00|Hquest:155:18|h[The Defias Brotherhood]|h|r")

        assertEqual(1, #visible(ns, HIDING))
    end)

    it("are read through the older calls on a client without C_QuestLog's", function()
        local ns, env = helpers.loadAddon()
        env.C_QuestLog = nil
        function env.IsQuestFlaggedCompleted(id) return id == 155 end
        chat(ns, "Brakk", DEFIAS)

        assertEqual(0, #visible(ns, HIDING))
    end)

    it("are read from the completed list when that is all the client has", function()
        local ns, env = helpers.loadAddon()
        env.C_QuestLog = nil
        function env.GetQuestsCompleted() return { [155] = true } end
        chat(ns, "Brakk", DEFIAS)

        assertEqual(0, #visible(ns, HIDING))
    end)

    it("count as not completed when the client will not say", function()
        local ns, env = helpers.loadAddon()
        env.C_QuestLog.IsQuestFlaggedCompleted = function() error("secret") end
        chat(ns, "Brakk", DEFIAS)

        assertEqual(1, #visible(ns, HIDING))
    end)
end)
