local helpers = require("helpers")

local FILES = { "Healclick.lua", "Anchors.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

--- Stage the pre-10.x layout on top of the stub's modern one: party frames at
-- globals of their own, health bars at globals named after them.
local function legacyFrames(env)
    env.PartyFrame = nil
    env.PlayerFrame.healthBar = nil

    for index = 1, 4 do
        local frame = env.CreateFrame("Frame")
        env["PartyMemberFrame" .. index] = frame
        env["PartyMemberFrame" .. index .. "HealthBar"] = env.CreateFrame("Frame")
    end

    env.PlayerFrameHealthBar = env.CreateFrame("Frame")
end

describe("finding Blizzard's frame for a unit", function()
    it("finds the player's own frame, which no client has moved", function()
        local ns, env = loggedIn()
        assertEqual(env.PlayerFrame, (ns.Anchors.Frame("player")))
    end)

    it("finds each party member's frame inside the modern container", function()
        -- PartyMemberFrame1 was the global through Classic and Wrath. The
        -- 10.x rework moved it to PartyFrame.MemberFrame1, and this client
        -- is a 1.60 beta on that base -- /hc anchors reported the old global
        -- missing while PlayerFrame was still there.
        local ns, env = loggedIn()
        for index = 1, 4 do
            assertEqual(
                env.PartyFrame["MemberFrame" .. index],
                (ns.Anchors.Frame("party" .. index)),
                "party" .. index
            )
        end
    end)

    it("still finds the old globals on a client that has them", function()
        local ns, env = loggedIn()
        legacyFrames(env)

        assertEqual(env.PartyMemberFrame1, (ns.Anchors.Frame("party1")))
    end)

    it("reports which path answered, so the report can say", function()
        local ns = loggedIn()
        local _, path = ns.Anchors.Frame("party1")

        assertEqual("PartyFrame.MemberFrame1", path)
    end)

    it("returns nothing for a unit it has no frame for", function()
        local ns = loggedIn()
        assertNil(ns.Anchors.Frame("raid7"))
        assertNil(ns.Anchors.Frame(nil))
    end)

    it("returns nothing when no candidate is there", function()
        -- Raid-style party frames replace these outright, and unit-frame
        -- addons remove them.
        local ns, env = loggedIn()
        env.PartyFrame.MemberFrame2 = nil

        assertNil(ns.Anchors.Frame("party2"))
    end)

    it("refuses something of that name that is not a frame", function()
        -- Another addon may have taken the name for a table of its own.
        -- Anchoring to it would error a long way from the cause.
        local ns, env = loggedIn()
        env.PartyFrame.MemberFrame1 = { somethingElse = true }

        assertNil(ns.Anchors.Frame("party1"))
    end)

    it("walks a dotted path without tripping over a missing container", function()
        local ns, env = loggedIn()
        env.PartyFrame = nil

        assertNil(ns.Anchors.Frame("party1"))
    end)

    it("looks the frame up afresh rather than caching it at load", function()
        -- Blizzard's UI may not have built these when this addon loads, and
        -- an addon can swap one out later.
        local ns, env = loggedIn()
        local replacement = env.CreateFrame("Frame")
        env.PlayerFrame = replacement

        assertEqual(replacement, (ns.Anchors.Frame("player")))
    end)
end)

describe("what exactly a row hangs off", function()
    it("prefers the health bar the modern frames keep as a field", function()
        -- A unit frame's rect can run past the art it draws; the health
        -- bar's right edge is where the frame visibly ends.
        local ns, env = loggedIn()
        assertEqual(
            env.PartyFrame.MemberFrame1.healthBar,
            ns.Anchors.For("party1")
        )
    end)

    it("prefers the health bar the old clients published as a global", function()
        local ns, env = loggedIn()
        legacyFrames(env)

        assertEqual(env.PartyMemberFrame1HealthBar, ns.Anchors.For("party1"))
    end)

    it("settles for the frame when neither health bar is there", function()
        -- Which is what this client does for the player frame, and the icons
        -- sit correctly against it.
        local ns, env = loggedIn()
        env.PlayerFrame.healthBar = nil

        assertEqual(env.PlayerFrame, ns.Anchors.For("player"))
    end)

    it("is absent when the frame is, whatever else shares its name", function()
        local ns, env = loggedIn()
        env.PartyFrame.MemberFrame1 = nil

        assertNil(ns.Anchors.For("party1"))
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
        -- A two-person party has no third member frame as a matter of
        -- course. Reading that as "this UI has no party frames" would drop
        -- everyone back to the bar for the most ordinary reason there is.
        local ns, env = loggedIn()
        env.PartyFrame.MemberFrame2 = nil
        env.PartyFrame.MemberFrame3 = nil
        env.PartyFrame.MemberFrame4 = nil

        assertTrue(ns.Anchors.Available())
    end)
end)
