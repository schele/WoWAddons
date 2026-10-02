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
        assertEqual("1/5", party("LFM WC"), "the poster, at least")
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

describe("the minimap switch", function()
    it("sits last in the row of switches, labelled 'Minimap button'", function()
        local _, _, frame = opened()

        assertEqual("Minimap button", frame.minimap.label:GetText())
        local _, _, _, x, y = frame.minimap:GetPoint()
        assertEqual(562, x)
        assertEqual(-64, y)
    end)

    it("is ticked while the button shows, and unticked once it is hidden", function()
        local ns, _, frame = opened()
        assertTrue(frame.minimap:GetChecked())

        ns.MinimapButton.SetHidden(true)

        assertFalse(frame.minimap:GetChecked())
    end)

    it("starts unticked when the saved choice is hidden", function()
        local _, _, frame = opened({ minimap = { hide = true } })
        assertFalse(frame.minimap:GetChecked())
    end)

    it("hides the button when unticked, shows it when ticked, and remembers", function()
        local ns, _, frame = opened()

        frame.minimap:Click()
        assertFalse(ns.MinimapButton.Button():IsShown())
        assertTrue(ns.db.minimap.hide)

        frame.minimap:Click()
        assertTrue(ns.MinimapButton.Button():IsShown())
        assertFalse(ns.db.minimap.hide)
    end)

    it("follows /lfgb minimap", function()
        local _, env, frame = opened()

        helpers.command(env, "minimap")
        assertFalse(frame.minimap:GetChecked(), "unticked after hiding by command")

        helpers.command(env, "minimap")
        assertTrue(frame.minimap:GetChecked(), "ticked after showing by command")
    end)
end)

describe("the completed quests switch", function()
    local DEFIAS = "LF2M |cffffff00|Hquest:155:18|h[The Defias Brotherhood]|h|r"

    it("sits in the row of switches after Alerts, labelled 'Hide done quests', ticked to begin with", function()
        local ns, _, frame = opened()

        assertEqual("Hide done quests", frame.completed.label:GetText())
        local _, _, _, x, y = frame.completed:GetPoint()
        assertEqual(426, x)
        assertEqual(-64, y)
        assertTrue(frame.completed:GetChecked())
        assertTrue(ns.db.hideCompleted)
    end)

    it("shows a group for a completed quest when unticked, and remembers", function()
        local ns, env, frame = opened()
        env.__completedQuests[155] = true
        helpers.say(env, "Brakk", DEFIAS)
        assertFalse(frame.rows[1]:IsShown())

        frame.completed:Click()

        assertTrue(frame.rows[1]:IsShown())
        assertFalse(ns.db.hideCompleted)
    end)

    it("leaves room for each switch's label before the next, and all before Refresh", function()
        local _, _, frame = opened()
        -- Wider than the small font draws: six pixels a letter, the box 24.
        local switches = { frame.roles.tank, frame.roles.healer, frame.roles.dps,
            frame.near, frame.alerts, frame.completed, frame.minimap }
        local refreshX = select(4, frame.refresh:GetPoint())
        for index, box in ipairs(switches) do
            local x = select(4, box:GetPoint())
            local ends = x + 24 + #box.label:GetText() * 6
            local nextX = switches[index + 1] and select(4, switches[index + 1]:GetPoint()) or refreshX
            assertTrue(ends < nextX, box.label:GetText() .. " runs into what follows it")
        end
    end)
end)

describe("the classes on a row", function()
    local function view(ns, text)
        return ns.Posts.View(ns.Posts.AddChat({ name = "X", text = text, time = 1000 }))
    end

    it("are carried from what was said to the row", function()
        local ns = helpers.loggedIn()
        local got = view(ns, "LF1M DM need mage no hunters")
        assertTrue(got.wantClasses.MAGE)
        assertTrue(got.refuseClasses.HUNTER)
    end)

    it("name the classes asked for in their colours, and the ones turned away dimmed after no", function()
        local ns = helpers.loggedIn()
        assertEqual("|cff69ccf0Mage|r |cff808080no Hunter|r", ns.Window.Classes(view(ns, "LF1M DM need mage no hunters")))
        assertEqual("|cffffffffPriest|r |cffff7d0aDruid|r",
            ns.Window.Classes(view(ns, "LF1M DM need healer, priest or druid")))
        assertEqual("", ns.Window.Classes(view(ns, "LF1M DM need tank")))
    end)

    it("go on a line of their own under the count and roles", function()
        local _, env, frame = opened()
        helpers.say(env, "Garrok", "LF1M DM need mage no hunters")

        local row = frame.rows[1]
        assertEqual("4/5", row.party:GetText())
        assertTrue(row.classes:IsShown())
        assertMatch("Mage", row.classes:GetText())
        assertEqual(5, select(5, row.party:GetPoint()), "the count moved up to make room")
        assertEqual(-7, select(5, row.classes:GetPoint()))
    end)

    it("leave the count where it was when none are named", function()
        local _, env, frame = opened()
        helpers.say(env, "Garrok", "LF1M DM need heals")

        local row = frame.rows[1]
        assertEqual("4/5, needs H", row.party:GetText())
        assertFalse(row.classes:IsShown())
        assertEqual(0, select(5, row.party:GetPoint()))
    end)

    it("sit beside a listed group's squares, as its count does", function()
        local _, env, frame = opened()
        helpers.list(env, 1, "Garrok", 10, GARROK_PARTY)
        helpers.searched(env)
        helpers.say(env, "Garrok", "LF2M DM need mage")

        local row = frame.rows[1]
        assertEqual(select(4, row.party:GetPoint()), select(4, row.classes:GetPoint()))
        assertEqual(row.party.width, row.classes.width)
    end)
end)

describe("the board's frame", function()
    it("is the options window's own, with the name in its title bar, as BossLoot's and BankBags'", function()
        local _, _, frame = opened()
        assertEqual("SettingsFrameTemplate", frame.template)
        assertEqual(frame.NineSlice.Text, frame.title)
        assertEqual("LFG Board", frame.title:GetText())
        assertEqual(frame.ClosePanelButton, frame.close)
    end)

    it("heads the name with LFGBoard's own icon", function()
        local _, _, frame = opened()
        assertEqual("Interface\\AddOns\\LFGBoard\\minimap", frame.logo:GetTexture())
        local point, relativeTo, relativePoint = frame.logo:GetPoint()
        assertEqual("RIGHT", point)
        assertEqual(frame.title, relativeTo)
        assertEqual("LEFT", relativePoint)
    end)

    it("is solid, not see-through, inside the game's border", function()
        local _, _, frame = opened()
        assertEqual(frame.Bg, frame.background:GetParent(), "drawn with the game's background, under all else")
        assertEqual(1, frame.background.color[4])
    end)

    it("closes with its X", function()
        local _, _, frame = opened()
        frame.close.scripts.OnClick(frame.close, "LeftButton")
        assertFalse(frame:IsShown())
    end)

    it("falls back to the dialog border, still solid, on a client without that frame", function()
        local ns, env = helpers.loadAddon(nil, function(e) e.__missingTemplates.SettingsFrameTemplate = true end)
        helpers.login(env)
        helpers.command(env, "")
        local frame = ns.Window.Frame()
        assertTrue(frame:IsShown())
        assertTrue(frame.backdrop ~= nil, "the dialog border")
        assertNil(frame.backdrop.bgFile, "no see-through dialog background")
        assertEqual(1, frame.background.color[4])
        assertEqual("LFG Board", frame.title:GetText())
        frame.close.scripts.OnClick(frame.close, "LeftButton")
        assertFalse(frame:IsShown())
    end)

    it("keeps the tabs, the switches and the rows clear of the title bar", function()
        local _, _, frame = opened()
        assertTrue(select(5, frame.tabs.all:GetPoint()) <= -30, "the tabs")
        assertTrue(select(5, frame.near:GetPoint()) <= -30, "the switches")
    end)
end)

describe("links in what was said", function()
    local DEFIAS = "|cffffff00|Hquest:155:18|h[The Defias Brotherhood]|h|r"

    local function boardWithLink()
        local ns, env, frame = opened()
        helpers.say(env, "Garrok", "LF2M " .. DEFIAS)
        return ns, env, frame.rows[1]
    end

    it("are live on every row", function()
        local _, _, row = boardWithLink()
        assertTrue(row.hyperlinks)
    end)

    it("show the quest's tooltip on hover, and hide it after", function()
        local _, env, row = boardWithLink()
        row.scripts.OnHyperlinkEnter(row, "quest:155:18", DEFIAS)
        assertEqual("quest:155:18", env.GameTooltip.hyperlink)
        assertEqual(row, env.GameTooltip.owner)
        assertTrue(env.GameTooltip:IsShown())

        row.scripts.OnHyperlinkLeave(row)
        assertFalse(env.GameTooltip:IsShown())
    end)

    it("do not raise for a link the tooltip cannot show", function()
        local _, env, row = boardWithLink()
        env.GameTooltip.SetHyperlink = function() error("unknown link") end
        row.scripts.OnHyperlinkEnter(row, "garbage:1", "[x]")
    end)

    it("do what chat does on a click", function()
        local _, env, row = boardWithLink()
        row.scripts.OnHyperlinkClick(row, "quest:155:18", DEFIAS, "LeftButton")
        local call = env.__itemRefCalls[#env.__itemRefCalls]
        assertEqual("quest:155:18", call[1])
        assertEqual(DEFIAS, call[2])
        assertEqual("LeftButton", call[3])
        assertEqual(row, call[4])
    end)

    it("go into an open chat box on a Shift-click", function()
        local _, env, row = boardWithLink()
        env.__modifiedClick.CHATLINK = true
        env.__chatBoxOpen = true
        row.scripts.OnHyperlinkClick(row, "quest:155:18", DEFIAS, "LeftButton")
        assertEqual(DEFIAS, env.__inserted[1])
        assertEqual(0, #env.__itemRefCalls, "not opened as well")
    end)

    it("open as a click does on a Shift-click with no chat box open", function()
        local _, env, row = boardWithLink()
        env.__modifiedClick.CHATLINK = true
        row.scripts.OnHyperlinkClick(row, "quest:155:18", DEFIAS, "LeftButton")
        assertEqual(1, #env.__itemRefCalls)
    end)

    it("leave the window moving when a row is dragged, and remember where", function()
        local ns, _, row = boardWithLink()
        local frame = ns.Window.Frame()
        row.scripts.OnDragStart(row)
        assertTrue(frame.moving)
        row.scripts.OnDragStop(row)
        assertFalse(frame.moving)
        assertEqual(frame:GetPoint(1), ns.db.window.point)
    end)

    it("leave the Whisper button working", function()
        local _, env, row = boardWithLink()
        row.whisper:Click()
        assertMatch("Garrok", env.__openedChat or "")
    end)
end)
