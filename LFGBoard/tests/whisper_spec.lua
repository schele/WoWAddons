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

    it("opens a whisper to them, realm and all, with the message typed", function()
        local ns, env = helpers.loggedIn()

        ns.Whisper.Open(view(ns, { whisperName = "Garrok-Aldira", roles = { tank = true, dps = true } }))

        assertEqual("/w Garrok-Aldira Hi! Level 20 feral druid, tank or dps. Room for me in Deadmines?", env.__openedChat)
    end)
end)
