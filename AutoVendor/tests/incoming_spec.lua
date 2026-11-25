local helpers = require("helpers")

local SOLD, ACTIVE = 1, 0

local function assertContains(text, part)
    assertTrue(type(text) == "string" and text:find(part, 1, true) ~= nil,
        string.format("%q in %q", part, tostring(text)))
end

local function click(button)
    button:GetScript("OnClick")(button, "LeftButton")
end

--- At the auctioneer with `owned` auctions of your own, on the Auctions tab.
local function onAuctionsTab(owned)
    local ns, env, frame = helpers.atAuctionHouse(function(env)
        for _, auction in ipairs(owned or {}) do
            helpers.ownAuction(env, auction)
        end
    end)
    click(frame.AuctionsTab)
    return ns, env, frame, ns.Incoming.line
end

local function hover(line, env)
    line:GetScript("OnEnter")(line)
    return table.concat(env.GameTooltip.lines, "\n")
end

describe("the incoming total on the Auctions tab", function()
    it("adds up the Incoming Amount of every sold auction", function()
        local ns, _, _, line = onAuctionsTab({
            { status = SOLD, buyoutAmount = 1460, timeLeftSeconds = 1800 },
            { status = SOLD, buyoutAmount = 93, timeLeftSeconds = 1620 },
        })

        assertTrue(line:IsShown())
        assertContains(line.text:GetText(), "Incoming:")
        assertContains(line.text:GetText(), ns.Money(1553))
        assertContains(line.text:GetText(), "from 2 sold")
    end)

    it("leaves the auctions still listed out of it", function()
        local ns, _, _, line = onAuctionsTab({
            { status = SOLD, buyoutAmount = 1460 },
            { status = ACTIVE, buyoutAmount = 50000 },
        })

        assertContains(line.text:GetText(), ns.Money(1460))
        assertContains(line.text:GetText(), "from 1 sold")
    end)

    it("takes a sale's bid when it came with no buyout", function()
        local ns, _, _, line = onAuctionsTab({
            { status = SOLD, bidAmount = 700 },
        })

        assertContains(line.text:GetText(), ns.Money(700))
    end)

    it("says so when nothing has sold", function()
        local _, _, _, line = onAuctionsTab({
            { status = ACTIVE, buyoutAmount = 50000 },
        })

        assertEqual("Incoming: none", line.text:GetText())
    end)

    it("follows your auctions as the game updates them", function()
        local ns, env, _, line = onAuctionsTab({
            { status = SOLD, buyoutAmount = 1460 },
        })

        helpers.ownAuction(env, { status = SOLD, buyoutAmount = 540 })
        helpers.fire(env, "OWNED_AUCTIONS_UPDATED")

        assertContains(line.text:GetText(), ns.Money(2000))
        assertContains(line.text:GetText(), "from 2 sold")
    end)

    it("sits on the Auctions tab, in the strip right of your gold", function()
        local _, _, frame, line = onAuctionsTab()

        assertEqual(frame.AuctionsFrame, line:GetParent(), "goes with the Auctions tab")
        local point, relativeTo, relativePoint = table.unpack(line.points[1])
        assertEqual("LEFT", point)
        assertEqual(frame.MoneyFrameBorder, relativeTo)
        assertEqual("RIGHT", relativePoint)
    end)

    it("makes way for the Bids sub-tab, and comes back with Auctions", function()
        local _, _, frame, line = onAuctionsTab({
            { status = SOLD, buyoutAmount = 1460 },
        })

        frame.AuctionsFrame:SetTab(2)
        assertFalse(line:IsShown(), "hidden on Bids")

        frame.AuctionsFrame:SetTab(1)
        assertTrue(line:IsShown(), "back on Auctions")
    end)

    it("tells in its tooltip when the last sale reaches the mailbox", function()
        local _, env, _, line = onAuctionsTab({
            { status = SOLD, buyoutAmount = 1460, timeLeftSeconds = 1800 },
            { status = SOLD, buyoutAmount = 93, timeLeftSeconds = 1990 },
        })

        local text = hover(line, env)

        assertContains(text, "2 sold auctions")
        assertContains(text, "33 min")
        assertTrue(env.GameTooltip:IsShown())
    end)

    it("adds up what is still listed in its tooltip", function()
        local ns, env, _, line = onAuctionsTab({
            { status = SOLD, buyoutAmount = 1460 },
            { status = ACTIVE, buyoutAmount = 20000 },
            { status = ACTIVE, buyoutAmount = 30000 },
        })

        local text = hover(line, env)

        assertContains(text, "Still listed: 2 auctions")
        assertContains(text, ns.Money(50000))
    end)

    it("is built when the auction house UI was there before AutoVendor", function()
        local stub = require("wow_stub")
        local env = stub.newEnv()
        local frame = stub.buildAuctionHouse(env)
        helpers.ownAuction(env, { status = SOLD, buyoutAmount = 1460 })
        local ns = {}
        for _, path in ipairs(helpers.FILES) do
            assert(loadfile(path, "t", env))("AutoVendor", ns)
        end
        helpers.login(env)
        frame:Show()

        click(frame.AuctionsTab)

        assertContains(ns.Incoming.line.text:GetText(), ns.Money(1460))
    end)
end)
