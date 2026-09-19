local helpers = require("helpers")

local FILES = { "Healclick.lua", "Anchors.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("finding Blizzard's frame for a unit", function()
    it("finds the player's own frame", function()
        local ns, env = loggedIn()
        assertEqual(env.PlayerFrame, ns.Anchors.For("player"))
    end)

    it("finds each party member's frame", function()
        local ns, env = loggedIn()
        for index = 1, 4 do
            assertEqual(
                env["PartyMemberFrame" .. index],
                ns.Anchors.For("party" .. index),
                "party" .. index
            )
        end
    end)

    it("returns nothing for a unit it has no frame for", function()
        local ns = loggedIn()
        assertNil(ns.Anchors.For("raid7"))
        assertNil(ns.Anchors.For(nil))
    end)

    it("returns nothing when the frame is simply not there", function()
        -- Not hypothetical: turning on raid-style party frames replaces
        -- PartyMemberFrame1-4 outright, and unit-frame addons remove them.
        local ns, env = loggedIn()
        env.PartyMemberFrame2 = nil

        assertNil(ns.Anchors.For("party2"))
    end)

    it("refuses a global of that name that is not a frame", function()
        -- Another addon may have taken the name for a table of its own.
        -- Anchoring to it would error somewhere far away from the cause.
        local ns, env = loggedIn()
        env.PartyMemberFrame1 = { somethingElse = true }

        assertNil(ns.Anchors.For("party1"))
    end)

    it("looks the frame up afresh rather than caching it at load", function()
        -- Blizzard's UI may not have built these when this addon loads, and
        -- an addon can swap one out later.
        local ns, env = loggedIn()
        local replacement = env.CreateFrame("Frame")
        env.PlayerFrame = replacement

        assertEqual(replacement, ns.Anchors.For("player"))
    end)
end)

describe("whether attaching is possible at all", function()
    it("is possible when the player's frame is there", function()
        local ns = loggedIn()
        assertTrue(ns.Anchors.Available())
    end)

    it("is not possible without it", function()
        local ns, env = loggedIn()
        env.PlayerFrame = nil

        assertFalse(ns.Anchors.Available())
    end)

    it("stays possible when only some party frames are missing", function()
        -- A two-person party has no PartyMemberFrame2 as a matter of course.
        -- Reading that as "this UI has no party frames" would drop everyone
        -- back to the standalone bar for the most ordinary reason there is.
        local ns, env = loggedIn()
        env.PartyMemberFrame2 = nil
        env.PartyMemberFrame3 = nil
        env.PartyMemberFrame4 = nil

        assertTrue(ns.Anchors.Available())
    end)
end)
