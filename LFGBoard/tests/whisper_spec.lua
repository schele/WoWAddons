local helpers = require("helpers")

local function view(ns, extra)
    local made = { name = "Garrok", whisperName = "Garrok", kind = "dungeon", activity = ns.Activities.ByKey("dm") }
    for field, value in pairs(extra or {}) do
        made[field] = value
    end
    return made
end

describe("the whisper", function()
    it("is your level, talents and class, the roles wanted, and the dungeon", function()
        local ns = helpers.loggedIn()

        local text = ns.Whisper.Message(view(ns, { roles = { tank = true, dps = true } }))

        assertEqual("Hi! Level 20 feral druid, tank or dps. Room for me in Deadmines?", text)
    end)

    it("offers every role you play when the group does not say", function()
        local ns = helpers.loggedIn()
        ns.Roles().healer = false

        local text = ns.Whisper.Message(view(ns))

        assertMatch("druid, tank or dps%.", text)
    end)

    it("offers every role you play when the group wants none of them", function()
        local ns = helpers.loggedIn()
        ns.Roles().healer = false

        local text = ns.Whisper.Message(view(ns, { roles = { healer = true } }))

        assertMatch("druid, tank or dps%.", text)
    end)

    it("uses the short words for talent trees", function()
        local ns = helpers.loadAddon()

        assertEqual("resto", ns.Whisper.SpecWord("Restoration"))
        assertEqual("prot", ns.Whisper.SpecWord("Protection"))
        assertEqual("bm", ns.Whisper.SpecWord("Beast Mastery"))
        assertEqual("feral", ns.Whisper.SpecWord("Feral Combat"))
        assertEqual("arms", ns.Whisper.SpecWord("Arms"))
        assertNil(ns.Whisper.SpecWord(nil))
    end)

    it("leaves the tree out with no points spent", function()
        local ns, env = helpers.loggedIn()
        for _, tree in ipairs(env.__talents) do
            for index in ipairs(tree.ranks) do
                tree.ranks[index] = 0
            end
        end

        assertMatch("^Hi! Level 20 druid, ", ns.Whisper.Message(view(ns)))
    end)

    it("reads talent trees that give their name first", function()
        local ns, env = helpers.loggedIn()
        env.__talentNameFirst = true

        assertMatch("^Hi! Level 20 feral druid", ns.Whisper.Message(view(ns)))
    end)

    it("names a quest group and an unknown one", function()
        local ns = helpers.loggedIn()

        assertMatch("Room for me in your quest group%?$", ns.Whisper.Message(view(ns, { kind = "quest", activity = false })))
        assertMatch("Room for me in your group%?$", ns.Whisper.Message(view(ns, { kind = "other", activity = false })))
    end)

end)

describe("writing the whisper", function()
    local MESSAGE = "Hi! Level 20 feral druid, tank or dps. Room for me in Deadmines?"

    local function opened(extra)
        local ns, env = helpers.loggedIn()
        ns.Whisper.Open(view(ns, extra or { whisperName = "Garrok-Aldira", roles = { tank = true, dps = true } }))
        return ns, env, ns.Whisper.Composer()
    end

    it("opens at the foot of the board, to them, realm and all, with the message typed", function()
        local ns, env, composer = opened()

        assertTrue(ns.Window.Frame():IsShown(), "the board")
        assertTrue(composer:IsShown())
        assertEqual("To Garrok-Aldira:", composer.label:GetText())
        assertEqual(MESSAGE, composer.box:GetText())
        assertTrue(composer.box:HasFocus(), "ready for Enter")
        assertFalse(ns.Window.Frame().footer:IsShown(), "in the footer's place")
    end)

    it("never opens the game's chat box", function()
        local _, env = opened()
        assertNil(env.__openedChat)
    end)

    it("sends it as a whisper on Enter, and closes", function()
        local ns, env, composer = opened()

        composer.box.scripts.OnEnterPressed(composer.box)

        assertEqual(1, #env.__sent)
        assertEqual(MESSAGE, env.__sent[1].text)
        assertEqual("WHISPER", env.__sent[1].chatType)
        assertEqual("Garrok-Aldira", env.__sent[1].target)
        assertFalse(composer:IsShown())
        assertTrue(ns.Window.Frame().footer:IsShown(), "the footer back")
    end)

    it("sends what was written over it, with Send", function()
        local _, env, composer = opened()
        composer.box:SetText("Hi, healer here")

        composer.send:Click()

        assertEqual("Hi, healer here", env.__sent[1].text)
    end)

    it("sends nothing when emptied", function()
        local _, env, composer = opened()
        composer.box:SetText("   ")

        composer.box.scripts.OnEnterPressed(composer.box)

        assertEqual(0, #env.__sent)
        assertFalse(composer:IsShown())
    end)

    it("is dropped by Escape, by Cancel, and by closing the board", function()
        local ns, env, composer = opened()
        composer.box.scripts.OnEscapePressed(composer.box)
        assertFalse(composer:IsShown(), "Escape")
        assertFalse(composer.box:HasFocus())

        ns.Whisper.Open(view(ns))
        composer.cancel:Click()
        assertFalse(composer:IsShown(), "Cancel")

        ns.Whisper.Open(view(ns))
        ns.Window.Frame():Hide()
        assertFalse(composer:IsShown(), "the board closed")

        assertEqual(0, #env.__sent)
    end)

    it("keeps what was written while the game holds chat back in a fight", function()
        local _, env, composer = opened()
        env.__chatLockdown = true

        composer.box.scripts.OnEnterPressed(composer.box)

        assertEqual(0, #env.__sent)
        assertTrue(composer:IsShown())
        assertEqual(MESSAGE, composer.box:GetText())
        assertMatch("fight", helpers.printed(env))
    end)

    it("is replaced by the next one", function()
        local ns, env, composer = opened()

        ns.Whisper.Open(view(ns, { name = "Elandra", whisperName = "Elandra" }))
        composer.box.scripts.OnEnterPressed(composer.box)

        assertEqual("Elandra", env.__sent[1].target)
    end)

    it("takes a link put in it", function()
        local ns, _, composer = opened()

        assertTrue(ns.Whisper.Insert(" [Linen Cloth]"))

        assertEqual(MESSAGE .. " [Linen Cloth]", composer.box:GetText())
    end)

    it("takes no link when none is being written", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.Whisper.Insert("[Linen Cloth]"))
    end)
end)
