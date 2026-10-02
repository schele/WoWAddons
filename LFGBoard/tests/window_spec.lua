local helpers = require("helpers")

local function opened(saved)
    local ns, env = helpers.loggedIn(saved)
    helpers.command(env, "")
    return ns, env, ns.Window.Frame()
end

local GARROK_PARTY = {
    { role = "TANK", class = "WARRIOR" }, { role = "DAMAGER", class = "ROGUE" }, { role = "DAMAGER", class = "MAGE" },
}

describe("the board", function()
    it("opens and closes with /lfgb", function()
        local ns, env = helpers.loggedIn()

        helpers.command(env, "")
        assertTrue(ns.Window.Frame():IsShown())

        helpers.command(env, "")
        assertFalse(ns.Window.Frame():IsShown())
    end)

    it("closes on Escape", function()
        local _, env = opened()

        local found = false
        for _, name in ipairs(env.UISpecialFrames) do
            found = found or name == "LFGBoardFrame"
        end
        assertTrue(found)
    end)

    it("lists the rows newest first, with when, who, what for and what was said", function()
        local _, env, frame = opened()
        helpers.say(env, "Garrok", "LF2M DM need heals")
        helpers.later(env, 12)
        helpers.say(env, "Elandra", "LFM WC need dps")
        helpers.later(env, 30)

        frame:Hide()
        frame:Show()

        assertEqual("0:30", frame.rows[1].age:GetText())
        assertMatch("Elandra", frame.rows[1].who:GetText())
        assertEqual("Wailing Caverns", frame.rows[1].what:GetText())
        assertEqual("LFM WC need dps", frame.rows[1].said:GetText())
        assertEqual("0:42", frame.rows[2].age:GetText())
        assertFalse(frame.rows[3]:IsShown())
    end)

    it("redraws when a message arrives while it is open", function()
        local _, env, frame = opened()

        helpers.say(env, "Garrok", "LF2M DM need heals")

        assertTrue(frame.rows[1]:IsShown())
        assertMatch("Garrok", frame.rows[1].who:GetText())
    end)

    it("colours a name by class", function()
        local _, env, frame = opened()
        env.__guids["Player-1"] = "WARRIOR"

        helpers.say(env, "Garrok", "LF2M DM need heals", { guid = "Player-1" })

        assertEqual("|cffc79c6eGarrok|r", frame.rows[1].who:GetText())
    end)

    it("says where each row came from", function()
        local _, env, frame = opened()
        helpers.say(env, "Brakk", "LFM SFK need tank")
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)
        helpers.say(env, "Garrok", "LF2M DM need heals")
        helpers.list(env, 2, "Elandra", 11, { { role = "TANK", class = "WARRIOR" } })
        helpers.searched(env)

        local sources = {}
        for _, row in ipairs(frame.rows) do
            if row:IsShown() then
                sources[row.view.name] = row.source:GetText()
            end
        end
        assertEqual("chat only", sources.Brakk)
        assertEqual("group finder + chat", sources.Garrok)
        assertEqual("group finder", sources.Elandra)
    end)

    it("says how many rows did not fit", function()
        local _, env, frame = opened()
        for index = 1, 14 do
            helpers.say(env, "Player" .. index, "LFM DM need tank")
        end

        assertMatch("2 more not shown", frame.footer:GetText())
    end)
end)

describe("the party column", function()
    it("gives the size and the roles asked for from chat", function()
        local ns = helpers.loggedIn()
        local function party(text)
            return ns.Window.Party(ns.Posts.View(ns.Posts.AddChat({ name = "X", text = text, time = 1000 })))
        end

        assertEqual("3/5, needs H D", party("LF2M DM need heals dps"))
        assertEqual("?/5", party("LFM WC"))
        assertEqual("31/40, needs H", party("LFM MC 31/40 need heals"))
    end)

    it("shows a listed group's members as squares with their roles, and its room", function()
        local _, env, frame = opened()
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)

        helpers.searched(env)

        local row = frame.rows[1]
        assertEqual("T", row.slots[1].letter:GetText())
        assertEqual("D", row.slots[2].letter:GetText())
        assertEqual("+", row.slots[4].letter:GetText())
        assertNear(0xc7 / 255, row.slots[1].texture.color[1], 0.01)
        assertEqual("room for H D", row.party:GetText())
    end)

    it("marks a row that asks for one of your roles with the green edge", function()
        local _, env, frame = opened()
        helpers.say(env, "Garrok", "LFM DM need tank")
        helpers.later(env, 1)
        helpers.say(env, "Vexxa", "LFM SFK")

        assertFalse(frame.rows[1].edge:IsShown(), "Vexxa's does not say")
        assertTrue(frame.rows[2].edge:IsShown(), "Garrok's asks for a tank")
    end)
end)

describe("the board's filters", function()
    local function board(env)
        helpers.say(env, "Garrok", "LFM DM need tank")
        helpers.say(env, "Aurelius", "LFM MC need heals")
        helpers.say(env, "Brakk", "LF2M quest Hogger")
    end

    it("count each tab, and show only the tab clicked", function()
        local ns, env, frame = opened()
        ns.db.nearLevel = false
        board(env)

        assertEqual("All (3)", frame.tabs.all:GetText())
        assertEqual("Dungeons (1)", frame.tabs.dungeon:GetText())
        assertEqual("Quests (1)", frame.tabs.quest:GetText())
        assertEqual("Raids (1)", frame.tabs.raid:GetText())

        frame.tabs.dungeon:Click()

        assertMatch("Garrok", frame.rows[1].who:GetText())
        assertFalse(frame.rows[2]:IsShown())
    end)

    it("hide far-away dungeons with Near my level, and remember the switch", function()
        local ns, env, frame = opened()
        board(env)
        assertEqual("All (2)", frame.tabs.all:GetText(), "Molten Core is hidden at level 20")

        frame.near:Click()

        assertEqual("All (3)", frame.tabs.all:GetText())
        assertFalse(ns.db.nearLevel)
    end)

    it("hide groups that want only roles you switched off, per character", function()
        local ns, env, frame = opened()
        helpers.say(env, "Garrok", "LFM DM need heals")
        assertTrue(frame.rows[1]:IsShown())

        frame.roles.healer:Click()

        assertFalse(frame.rows[1]:IsShown())
        assertFalse(ns.Roles().healer)
    end)

    it("step the dungeon picker through the dungeons on the board, and back to Any", function()
        local _, env, frame = opened()
        helpers.say(env, "Garrok", "LFM DM need tank")
        helpers.say(env, "Vexxa", "LFM SFK need tank")

        frame.picker:Click()
        assertEqual("Dungeon: Shadowfang Keep", frame.picker:GetText())
        assertMatch("Vexxa", frame.rows[1].who:GetText())
        assertFalse(frame.rows[2]:IsShown())

        frame.picker:Click()
        assertEqual("Dungeon: Deadmines", frame.picker:GetText())

        frame.picker:Click()
        assertEqual("Dungeon: Any", frame.picker:GetText())

        frame.picker:Click("RightButton")
        assertEqual("Dungeon: Deadmines", frame.picker:GetText())
    end)
end)

describe("the board's buttons", function()
    it("Refresh searches the group finder for the tab shown", function()
        local _, env, frame = opened()

        frame.tabs.raid:Click()
        frame.refresh:Click()

        assertEqual(114, env.__searches[1])
    end)

    it("Refresh says why when the finder cannot be searched", function()
        local _, env, frame = opened()
        env.__categories = {}

        frame.refresh:Click()

        assertMatch("The group finder could not be searched: the group finder has no list for that tab%.", helpers.printed(env))
    end)

    it("Whisper opens chat with the message typed", function()
        local _, env, frame = opened()
        helpers.say(env, "Garrok", "LFM DM need tank")

        frame.rows[1].whisper:Click()

        assertMatch("^/w Garrok Hi! Level 20 feral druid, tank%.", env.__openedChat)
    end)
end)

describe("the board's place", function()
    it("is remembered where it was moved", function()
        local ns, env, frame = opened()
        frame.points = { { "TOPLEFT", env.UIParent, "TOPLEFT", 100, -50 } }

        frame.scripts.OnDragStop(frame)

        assertEqual("TOPLEFT", ns.db.window.point)
        assertEqual(100, ns.db.window.x)
        assertEqual(-50, ns.db.window.y)
    end)
end)

describe("the party column", function()
    local function clear(row)
        local right = row.party.points[1][4] + row.party.width
        local whisperLeft = row.width + row.whisper.points[1][4] - row.whisper.width
        return right <= whisperLeft
    end

    it("stays clear of the Whisper button, beside squares or not", function()
        local _, env, frame = opened()
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)
        helpers.searched(env)
        helpers.later(env, 1)
        helpers.say(env, "Vexxa", "LF2M SFK need heals dps")

        assertTrue(clear(frame.rows[1]), "a row from chat")
        assertTrue(clear(frame.rows[2]), "a row with squares")
    end)
end)
