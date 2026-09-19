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
        assertEqual(env.PlayerFrameHealthBar, ns.Anchors.For("player"))
    end)

    it("finds each party member's frame", function()
        local ns, env = loggedIn()
        for index = 1, 4 do
            assertEqual(
                env["PartyMemberFrame" .. index .. "HealthBar"],
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
        -- The old frame's health bar goes with it, the way a real
        -- replacement takes its children along.
        env.PlayerFrameHealthBar = nil

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

describe("what exactly a row hangs off", function()
    it("prefers the health bar to the frame around it", function()
        -- A unit frame's rect runs past the art it draws, and the player
        -- frame and the party frames do not overhang by the same amount.
        -- Anchored to the frames, one offset put the player's icons snug
        -- against the portrait and a party member's a frame-width out into
        -- empty screen.
        local ns, env = loggedIn()
        assertEqual(env.PartyMemberFrame1HealthBar, ns.Anchors.For("party1"))
    end)

    it("falls back to the frame when there is no health bar on it", function()
        local ns, env = loggedIn()
        env.PartyMemberFrame1HealthBar = nil

        assertEqual(env.PartyMemberFrame1, ns.Anchors.For("party1"))
    end)

    it("is absent when the frame is, whatever shares its name prefix", function()
        -- The frame decides whether the unit has a usable anchor; the health
        -- bar only refines where on it.
        local ns, env = loggedIn()
        env.PartyMemberFrame1 = nil

        assertNil(ns.Anchors.For("party1"))
    end)
end)
