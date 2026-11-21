local helpers = require("helpers")

local BOOTS, BRACERS, LINEN = 9798, 6070, 2589

local function tab(env)
    return env.AuctionHouseFrame.Tabs[4]
end

local function click(button, mouse)
    button:GetScript("OnClick")(button, mouse or "LeftButton")
end

--- At the auctioneer on the Vendor deals tab.
local function onTheTab(setup)
    local ns, env, frame = helpers.atAuctionHouse(setup)
    click(tab(env))
    return ns, env, frame, ns.DealsTab
end

--- On the tab, with `auctions` up, scanned and answered.
local function scannedOnTheTab(auctions)
    local ns, env, frame, page = onTheTab(function(env)
        for _, auction in ipairs(auctions) do
            helpers.auction(env, auction[1], auction[2], auction[3])
        end
    end)
    click(page.scan)
    helpers.scanAnswered(env)
    return ns, env, frame, page
end

describe("the Vendor deals tab", function()
    it("comes after the game's Buy, Sell and Auctions tabs", function()
        local _, env, frame = helpers.atAuctionHouse()

        assertEqual(4, #frame.Tabs)
        assertEqual("Vendor deals", tab(env):GetText())
        assertEqual("AuctionHouseFrameDisplayModeTabTemplate", tab(env).template)
        local _, relativeTo = table.unpack(tab(env).points[1])
        assertEqual(frame.AuctionsTab, relativeTo, "beside the Auctions tab")
        assertEqual(4, frame.numTabs)
    end)

    it("shows its page in place of the game's when clicked", function()
        local _, env, frame, page = onTheTab()

        assertTrue(page.panel:IsShown())
        assertFalse(frame.BrowseResultsFrame:IsShown(), "the Buy tab's list is hidden")
        assertEqual(4, frame.selectedTab)
        assertEqual("Vendor deals", frame.title)
    end)

    it("gives way to another tab", function()
        local _, env, frame, page = onTheTab()

        click(frame.SellTab)

        assertFalse(page.panel:IsShown())
        assertTrue(frame.ItemSellList:IsShown())
    end)

    it("is not shown the next time the auction house opens", function()
        local _, env, frame, page = onTheTab()

        frame:Hide()
        frame:Show()

        assertFalse(page.panel:IsShown())
    end)

    it("is built when the auction house UI was already there before AutoVendor", function()
        local stub = require("wow_stub")
        local env = stub.newEnv()
        stub.buildAuctionHouse(env)
        local ns = {}
        for _, path in ipairs(helpers.FILES) do
            assert(loadfile(path, "t", env))("AutoVendor", ns)
        end
        helpers.login(env)

        assertEqual("Vendor deals", env.AuctionHouseFrame.Tabs[4]:GetText())
    end)

    it("is not added on a client that cannot scan the whole auction house", function()
        local _, env = helpers.loadAddon()
        env.C_AuctionHouse.ReplicateItems = nil
        helpers.login(env)
        local frame = helpers.openAuctionHouse(env)

        assertEqual(3, #frame.Tabs)
    end)
end)

describe("the page", function()
    it("says what a scan finds before the first one", function()
        local _, _, _, page = onTheTab()

        assertMatch("Scan the auction house", page.status:GetText())
        assertFalse(page.rows[1]:IsShown())
    end)

    it("keeps the Scan button clear of the window's portrait", function()
        -- The portrait fills the window's top-left corner, about 60 pixels
        -- each way; the game's own tabs start their top row right of it.
        local _, env, frame, page = onTheTab()

        local _, panelTo, _, panelX = table.unpack(page.panel.points[1])
        local _, scanTo, _, scanX = table.unpack(page.scan.points[1])
        assertEqual(frame, panelTo)
        assertEqual(page.panel, scanTo)
        assertTrue(panelX + scanX >= 62, "left edge at " .. (panelX + scanX) .. ", under the portrait")
    end)

    it("scans with its Scan button, and says so", function()
        local _, env, _, page = onTheTab()
        assertEqual("Scan", page.scan:GetText())

        click(page.scan)

        assertEqual(1, env.__replicates)
        assertEqual("Waiting for the auction house: 0 s...", page.status:GetText())
    end)

    it("lists each deal: the item, its buyout, what a merchant pays, the profit", function()
        local _, _, _, page = scannedOnTheTab({ { BOOTS, 1, 770 }, { LINEN, 20, 200 }, { BRACERS, 1, 100 } })

        local row = page.rows[1]
        assertEqual("Linen Cloth x20", row.name:GetText())
        assertEqual("2s", row.buyout:GetText())
        assertEqual("2s 60c", row.value:GetText())
        assertEqual("60c", row.profit:GetText())
        assertEqual("Ivycloth Boots of Arcane Protection", page.rows[2].name:GetText())
        assertEqual("53c", page.rows[2].profit:GetText())
        assertFalse(page.rows[3]:IsShown(), "the bracers are no deal")
    end)

    it("writes a name that came late, once the game has it", function()
        local ns, env, _, page = onTheTab(function(env)
            helpers.auction(env, 15251, 1, 3000, { unnamed = true, nolink = true, fullName = "Polished Zweihander of the Whale" })
        end)
        click(page.scan)
        helpers.scanAnswered(env)
        assertEqual("Polished Zweihander", page.rows[1].name:GetText(), "the plain name meanwhile")

        env.__auctions[1].unnamed, env.__auctions[1].nolink = nil, nil
        page.panel:Hide()
        page.panel:Show()

        assertEqual("Polished Zweihander of the Whale", page.rows[1].name:GetText())
    end)

    it("writes each item's name in its quality's colour", function()
        local _, env, _, page = scannedOnTheTab({ { BOOTS, 1, 700 } })

        local green = env.__qualityColors[2]
        local color = page.rows[1].name.textColor
        assertEqual(green[1], color[1])
        assertEqual(green[2], color[2])
    end)

    it("says how many auctions it read and how many are deals", function()
        local _, _, _, page = scannedOnTheTab({ { BOOTS, 1, 770 }, { LINEN, 20, 200 }, { BRACERS, 1, 100 } })

        assertEqual("3 auctions scanned just now: 2 sell to a merchant for at least 50c more than their buyout, 1s 13c in all.",
            page.status:GetText())
    end)

    it("says how long ago the scan was", function()
        local _, env, _, page = scannedOnTheTab({ { BOOTS, 1, 700 } })

        env.__clock = env.__clock + 7 * 60
        page.panel:Hide()
        page.panel:Show()

        assertMatch("scanned 7 min ago", page.status:GetText())
    end)

    it("says when a scan finds none", function()
        local _, _, _, page = scannedOnTheTab({ { BRACERS, 1, 100 } })

        assertEqual("1 auction scanned just now: none sells to a merchant for at least 50c more than its buyout.",
            page.status:GetText())
    end)

    it("says it of a single deal", function()
        local _, _, _, page = scannedOnTheTab({ { BOOTS, 1, 700 }, { BRACERS, 1, 100 } })

        assertEqual("2 auctions scanned just now: 1 sells to a merchant for at least 50c more than its buyout, 1s 23c in all.",
            page.status:GetText())
    end)

    it("says when the auction house sends nothing back", function()
        local _, env, _, page = onTheTab()
        click(page.scan)

        env.__runTimers()

        assertMatch("sent nothing back", page.status:GetText())
    end)

    it("looks a deal up in the Buy tab when it is clicked", function()
        local _, env, frame, page = scannedOnTheTab({ { BOOTS, 1, 700 } })

        click(page.rows[1])

        assertEqual("Ivycloth Boots of Arcane Protection", env.__searches[1])
        assertTrue(frame.BrowseResultsFrame:IsShown(), "on the Buy tab")
        assertFalse(page.panel:IsShown())
    end)

    it("shows a deal's tooltip on hover", function()
        local _, env, _, page = scannedOnTheTab({ { BOOTS, 1, 700 } })

        page.rows[1]:GetScript("OnEnter")(page.rows[1])

        assertEqual(env.__link(BOOTS), env.GameTooltip.link)
        assertEqual(page.rows[1], env.GameTooltip.owner)
    end)

    it("scrolls with the mouse wheel when there are more deals than rows", function()
        local auctions = {}
        for index = 1, 20 do
            auctions[index] = { LINEN, 20, 200 - index }
        end
        local _, _, _, page = scannedOnTheTab(auctions)
        assertEqual(17, page.ROWS)
        assertMatch("^1%-17 of 20", page.footer:GetText())

        page.panel:GetScript("OnMouseWheel")(page.panel, -1)

        assertEqual(3, page.offset)
        assertMatch("^4%-20 of 20", page.footer:GetText())

        page.panel:GetScript("OnMouseWheel")(page.panel, -1)
        assertEqual(3, page.offset, "no further than the last row")
        page.panel:GetScript("OnMouseWheel")(page.panel, 1)
        page.panel:GetScript("OnMouseWheel")(page.panel, 1)
        assertEqual(0, page.offset, "and no further back than the first")
    end)

    -- As the game's own Auctions tab draws its list: its panel art (the
    -- index background in an inset border), and rows striped by turns.
    it("draws its list on the auction house's own background, in its inset border", function()
        local _, _, _, page = onTheTab()

        local list = page.list
        assertEqual("auctionhouse-background-index", list.Background:GetAtlas())
        local _, _, _, _, top = table.unpack(list.Background.points[1])
        assertEqual(-19 - 3, top, "under the headings' strip")
        assertEqual("InsetFrameTemplate", list.NineSlice.layout)
    end)

    it("falls back to the classic marble where the client has no such art", function()
        local _, _, _, page = onTheTab(function(env)
            env.__atlases["auctionhouse-background-index"] = nil
        end)

        assertEqual("Interface\\FrameGeneral\\UI-Background-Marble", page.list.Background:GetTexture())
    end)

    it("stripes its rows by turns, and lights the one under the mouse as the game does", function()
        local _, _, _, page = onTheTab()

        assertEqual("auctionhouse-rowstripe-1", page.rows[1].stripe:GetAtlas())
        assertEqual("auctionhouse-rowstripe-2", page.rows[2].stripe:GetAtlas())
        assertEqual("auctionhouse-rowstripe-1", page.rows[3].stripe:GetAtlas())
        assertEqual("auctionhouse-ui-row-highlight", page.rows[1].highlight:GetAtlas())
    end)

    it("puts its rows inside the list", function()
        local _, _, _, page = onTheTab()

        local _, relativeTo = table.unpack(page.rows[1].points[1])
        assertEqual(page.list, relativeTo)
    end)

    it("counts the seconds while it waits for the auction house", function()
        local _, env, _, page = onTheTab()
        click(page.scan)

        env.__clock = env.__clock + 7
        env.__runTimersUpTo(1)

        assertEqual("Waiting for the auction house: 7 s...", page.status:GetText())
    end)

    it("shows the last list when no new one comes, and when to try again", function()
        local _, env, _, page = scannedOnTheTab({ { BOOTS, 1, 700 } })
        local next = env.date("%H:%M", env.__clock + 15 * 60)
        env.__clock = env.__clock + 6 * 60

        click(page.scan)
        env.__runAllTimers()

        assertEqual("No new list came: the auction house allows one full scan every 15 minutes, the next at "
            .. next .. ". 1 auction scanned 6 min ago: 1 sells to a merchant for at least 50c more than its "
            .. "buyout, 1s 23c in all.", page.status:GetText())
        assertTrue(page.rows[1]:IsShown())
    end)

    it("says when to try again when the game holds no list either", function()
        local _, env, _, page = onTheTab(function(env)
            env.AutoVendorDB = { dealsAnsweredAt = env.__clock - 60 }
        end)
        local next = env.date("%H:%M", env.__clock - 60 + 15 * 60)

        click(page.scan)
        env.__runTimers()

        assertEqual("The auction house sent nothing back. It allows one full scan every 15 minutes: try again at "
            .. next .. ".", page.status:GetText())
    end)

    it("keeps its lines apart: Scan, the line under it, then the list", function()
        local _, _, _, page = onTheTab()

        local scanY = select(5, table.unpack(page.scan.points[1]))
        local statusY = select(5, table.unpack(page.status.points[1]))
        local listY = select(5, table.unpack(page.list.points[1]))
        assertTrue(scanY - 22 - statusY >= 12, "a clear gap under Scan and its slider")
        assertTrue(statusY - 2 * 14 - listY >= 6, "room for two lines, then the list")
    end)

    --- On the tab with 450 auctions up, the scan answered and its first
    -- slice read.
    local function reading()
        local ns, env, frame, page = onTheTab(function(env)
            for _ = 1, 450 do helpers.auction(env, LINEN, 20, 200) end
        end)
        click(page.scan)
        helpers.fire(env, "REPLICATE_ITEM_LIST_UPDATE")
        return ns, env, frame, page
    end

    it("shows a progress bar while reading the auctions", function()
        local _, _, _, page = reading()

        local bar = page.progress
        assertTrue(bar:IsShown())
        assertEqual(0, bar.min)
        assertEqual(450, bar.max)
        assertEqual(200, bar:GetValue())
        assertEqual("Reading the auctions: 44%", page.progressText:GetText())
        assertFalse(page.status:IsShown(), "in place of the line")
    end)

    it("lists the deals found so far while it reads", function()
        local _, _, _, page = reading()

        assertTrue(page.progress:IsShown(), "still reading")
        assertEqual("Linen Cloth x20", page.rows[1].name:GetText())
        assertMatch("^1%-17 of 200", page.footer:GetText())
    end)

    it("puts the line back once the reading is done", function()
        local _, env, _, page = reading()

        env.__runAllTimers()

        assertFalse(page.progress:IsShown())
        assertTrue(page.status:IsShown())
        assertMatch("^450 auctions scanned", page.status:GetText())
    end)

    --- Time passing with the tab open: the clock on, and a frame drawn.
    local function wait(env, page, seconds)
        env.__clock = env.__clock + seconds
        page.panel:GetScript("OnUpdate")(page.panel, 1)
    end

    it("counts down on the Scan button to when the next full scan is allowed", function()
        local _, env, _, page = scannedOnTheTab({ { BOOTS, 1, 700 } })

        assertEqual("Scan in 15:00", page.scan:GetText())
        assertFalse(page.scan:IsEnabled(), "no scan the auction house would ignore")

        wait(env, page, 61)
        assertEqual("Scan in 13:59", page.scan:GetText())

        wait(env, page, 13 * 60 + 50)
        assertEqual("Scan in 0:09", page.scan:GetText())
    end)

    it("is Scan again once the 15 minutes are up", function()
        local _, env, _, page = scannedOnTheTab({ { BOOTS, 1, 700 } })

        wait(env, page, 15 * 60)

        assertEqual("Scan", page.scan:GetText())
        assertTrue(page.scan:IsEnabled())
    end)

    it("counts down from the last answer after a reload too", function()
        local _, env, _, page = onTheTab(function(env)
            env.AutoVendorDB = { dealsAnsweredAt = env.__clock - 60 }
        end)

        assertEqual("Scan in 14:00", page.scan:GetText())
        assertFalse(page.scan:IsEnabled())
    end)

    it("is plain Scan when the auction house has never answered", function()
        local _, _, _, page = onTheTab()

        assertEqual("Scan", page.scan:GetText())
        assertTrue(page.scan:IsEnabled())
    end)

    it("turns Scan into Stop while it waits and reads", function()
        local _, env, _, page = onTheTab()

        click(page.scan)
        assertEqual("Stop", page.scan:GetText())
        assertTrue(page.scan:IsEnabled())

        click(page.scan)
        assertEqual("Scan", page.scan:GetText())
        assertEqual(1, env.__replicates, "Stop asks for nothing")
    end)

    it("says where it stopped, with what it found by then", function()
        local _, env, _, page = reading()

        click(page.scan)

        assertFalse(page.progress:IsShown())
        -- 200 linen auctions at 60c each.
        assertEqual("Stopped after 200 of 450 auctions: 200 sell to a merchant for at least 50c more than "
            .. "their buyout, 1g 20s in all.", page.status:GetText())
    end)
end)

describe("the least profit slider", function()
    it("sits on the tab, at 50 copper to begin with", function()
        local ns, _, _, page = onTheTab()

        local slider = page.minProfit
        assertEqual("OptionsSliderTemplate", slider.template)
        assertEqual(1, slider.min)
        assertEqual(#ns.Deals.STEPS, slider.max)
        assertEqual(ns.Deals.StepOf(50), slider:GetValue())
        assertEqual("Least profit: 50c", page.minProfitLabel:GetText())
    end)

    it("names its two ends", function()
        local _, _, _, page = onTheTab()

        assertEqual("1c", page.minProfit.Low:GetText())
        assertEqual("1g", page.minProfit.High:GetText())
    end)

    it("keeps the Scan row clear: it sits at the right of it", function()
        local _, _, _, page = onTheTab()

        local point, relativeTo = table.unpack(page.minProfit.points[1])
        assertEqual("TOPRIGHT", point)
        assertEqual(page.panel, relativeTo)
    end)

    it("changes the list at once when dragged", function()
        local ns, env, _, page = scannedOnTheTab({ { BOOTS, 1, 700 }, { LINEN, 20, 200 } })
        assertTrue(page.rows[2]:IsShown(), "both to begin with")
        local reads = env.__replicateReads

        page.minProfit:Drag(ns.Deals.StepOf(100))

        assertEqual(100, ns.db.dealsMinProfit)
        assertEqual("Least profit: 1s", page.minProfitLabel:GetText())
        assertEqual("Ivycloth Boots of Arcane Protection", page.rows[1].name:GetText())
        assertFalse(page.rows[2]:IsShown(), "the linen makes 60c")
        assertEqual(reads, env.__replicateReads, "no new scan")
    end)

    it("follows the settings page", function()
        local ns, _, _, page = onTheTab()

        ns.Deals.SetMinProfit(500)

        assertEqual(ns.Deals.StepOf(500), page.minProfit:GetValue())
        assertEqual("Least profit: 5s", page.minProfitLabel:GetText())
    end)
end)

describe("the switch", function()
    it("is on from the start", function()
        local ns = helpers.atAuctionHouse()
        assertTrue(ns.db.deals)
    end)

    it("hides the tab when turned off with /av deals, and says so", function()
        local ns, env = helpers.atAuctionHouse()

        helpers.command(env, "deals")

        assertFalse(ns.db.deals)
        assertFalse(tab(env):IsShown())
        assertMatch("Vendor deals tab at the auction house: off%.", helpers.printed(env))
    end)

    it("leaves the page for the Buy tab when turned off on it", function()
        local _, env, frame, page = onTheTab()

        helpers.command(env, "deals")

        assertFalse(page.panel:IsShown())
        assertTrue(frame.BrowseResultsFrame:IsShown())
    end)

    it("brings the tab back when turned on", function()
        local _, env = helpers.atAuctionHouse()
        helpers.command(env, "deals")

        helpers.command(env, "deals")

        assertTrue(tab(env):IsShown())
    end)

    it("is remembered: off, the tab is hidden the next time", function()
        local _, env = helpers.loadAddon({ deals = false })
        helpers.login(env)
        helpers.openAuctionHouse(env)

        assertFalse(tab(env):IsShown())
    end)

    it("is in /av's help", function()
        local _, env = helpers.atAuctionHouse()
        helpers.command(env, "help")
        assertMatch("/av deals", helpers.printed(env))
    end)
end)
