local helpers = require("helpers")

local function texts(entries)
    local out = {}
    for _, entry in ipairs(entries) do table.insert(out, entry.text) end
    return table.concat(out, "|")
end

local function opened()
    local ns, env = helpers.loggedIn()
    ns.Window.Open()
    return ns, env
end

describe("the boss column", function()
    it("lists bosses under their wing headings, then the notable drops", function()
        local ns = helpers.loggedIn()
        local entries = ns.Window.BossEntries(ns.instanceByKey.Depths, 1)
        assertEqual("East|First Boss|Second Boss|West|Third Boss|Notable drops|From trash", texts(entries))
        assertTrue(entries[2].selected)
    end)

    it("leaves out a notable list with nothing in it", function()
        local ns = helpers.loggedIn()
        assertEqual("Spire Boss|Notable drops|Chests & objects", texts(ns.Window.BossEntries(ns.instanceByKey.Spire, 1)))
    end)

    it("has no notable heading when there is nothing notable", function()
        local ns = helpers.loggedIn()
        assertEqual("Raid Boss", texts(ns.Window.BossEntries(ns.instanceByKey.Core, 1)))
    end)
end)

describe("the loot column", function()
    it("lists a boss's loot", function()
        local ns = helpers.loggedIn()
        local entries = ns.Window.LootEntries(ns.instanceByKey.Depths, 1)
        assertEqual(2, #entries)
        assertEqual(1001, entries[1].id)
        assertEqual(20, entries[1].chance)
    end)

    it("lists notable drops with what drops them", function()
        local ns = helpers.loggedIn()
        local entries = ns.Window.LootEntries(ns.instanceByKey.Depths, "trash")
        assertEqual("Anvilrage Overseer", entries[1].sources[1])
    end)

    it("says so when a boss drops nothing but world drops", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.AddInstance({
            key = "Stocks", name = "The Stocks", kind = "dungeon", levels = { 24, 31 },
            bosses = { { name = "Empty Boss", loot = {} }, { name = "Full Boss", loot = { { 5001, 10 } } } },
            notable = { trash = {}, objects = {} },
        })
        helpers.login(ns, env)
        ns.Window.Open()
        ns.Window.SelectInstance("Stocks")
        local frame = ns.Window.Frame()
        assertTrue(frame.empty:IsShown())
        assertMatch("world drops", frame.empty:GetText())
        ns.Window.SelectBoss(2)
        assertFalse(frame.empty:IsShown())
    end)
end)

describe("the instance column", function()
    it("lists the current tab's instances with their level ranges", function()
        local ns = helpers.loggedIn()
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "Spire" }, "")
        assertEqual("Test Depths |cff80808052-60|r|Low Spire |cff80808055-60|r", texts(entries))
        assertTrue(entries[2].selected)
    end)

    it("shows search results instead: instances, then items", function()
        local ns, env = helpers.loggedIn()
        env.__items[1002] = { name = "Hand of Justice", quality = 3 }
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "justice")
        assertEqual("Items|" .. "|cff0070ddHand of Justice|r|" .. "    Test Depths: First Boss |cff8080801.5%|r", texts(entries))
    end)

    it("says so when a search finds nothing", function()
        local ns = helpers.loggedIn()
        assertEqual("No matches", texts(ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "zzzz")))
    end)
end)

describe("selecting", function()
    it("opens on the first dungeon and its first boss", function()
        local ns = opened()
        local instance, boss = ns.Window.Current()
        assertEqual("Depths", instance.key)
        assertEqual(1, boss)
    end)

    it("remembers the last view across a reload", function()
        local ns, env = opened()
        ns.Window.SelectInstance("Spire")
        ns.Window.SelectBoss("objects")

        local second, secondEnv = helpers.loadAddon()
        helpers.sampleInstances(second)
        secondEnv.BossLootDB = env.BossLootDB
        helpers.login(second, secondEnv)
        local instance, boss = second.Window.Current()
        assertEqual("Spire", instance.key)
        assertEqual("objects", boss)
    end)

    it("switching tabs moves to that tab's first instance", function()
        local ns = opened()
        ns.Window.SelectKind("raid")
        assertEqual("Core", ns.Window.Current().key)
    end)

    it("falls back to the first instance when the saved one has gone", function()
        local ns = opened()
        ns.db.view.instance = "NoLongerInTheData"
        ns.db.view.boss = 7
        local instance, boss = ns.Window.Current()
        assertEqual("Depths", instance.key)
        assertEqual(1, boss)
    end)

    it("falls back to the first boss when the saved boss is past the end", function()
        local ns = opened()
        ns.db.view.boss = 42
        local _, boss = ns.Window.Current()
        assertEqual(1, boss)
    end)

    it("copes with a tab whose every instance is hidden", function()
        local ns = opened()
        ns.Window.HideInstance("Core")
        ns.Window.SelectKind("raid")
        local instance = ns.Window.Current()
        assertNil(instance)
        assertEqual(0, #ns.Window.BossEntries(instance, 1))
        assertEqual(0, #ns.Window.LootEntries(instance, 1))
    end)

    it("jumps to where an item drops", function()
        local ns = opened()
        ns.Window.SelectItem(3002)
        local instance, boss = ns.Window.Current()
        assertEqual("Spire", instance.key)
        assertEqual("objects", boss)
    end)

    it("jumps across to the raid tab for a raid drop", function()
        local ns = opened()
        ns.db.hidden.Depths = true
        ns.Window.SelectItem(1001)
        assertEqual("raid", ns.db.view.kind)
        assertEqual("Core", ns.Window.Current().key)
    end)

    it("asks the client to load an instance's items when it is opened", function()
        local ns, env = opened()
        ns.Window.SelectInstance("Spire")
        assertTrue(env.__requested[3001])
        assertTrue(env.__requested[3002])
    end)
end)

describe("hiding an instance", function()
    it("takes it off the list on a right-click, and says how to bring it back", function()
        local ns, env = opened()
        local list = ns.Window.Frame().instances
        list.rows[1].scripts.OnClick(list.rows[1], "RightButton")
        assertTrue(ns.db.hidden.Depths)
        assertEqual("Low Spire |cff80808055-60|r", list.rows[1].text:GetText())
        assertMatch("/bl unhide", helpers.printed(env))
    end)

    it("brings every hidden instance back with /bl unhide", function()
        local ns, env = opened()
        ns.Window.HideInstance("Depths")
        helpers.command(env, "unhide")
        assertNil(ns.db.hidden.Depths)
    end)
end)

describe("the window", function()
    it("toggles with a bare /bl", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "")
        assertTrue(ns.Window.Frame():IsShown())
        helpers.command(env, "")
        assertFalse(ns.Window.Frame():IsShown())
    end)

    it("closes on Escape like other windows", function()
        local ns, env = opened()
        local found = false
        for _, name in ipairs(env.UISpecialFrames) do
            if name == "BossLootFrame" then found = true end
        end
        assertTrue(found)
    end)

    it("draws the three columns from the selection", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        assertEqual("East", frame.bosses.rows[1].text:GetText())
        assertEqual(1001, frame.loot.rows[1].entry.id)
        frame.bosses.rows[3].scripts.OnClick(frame.bosses.rows[3], "LeftButton")
        assertEqual(1003, frame.loot.rows[1].entry.id)
    end)

    it("redraws loot rows once their items arrive", function()
        local ns, env = opened()
        local row = ns.Window.Frame().loot.rows[1]
        assertMatch("Loading", row.name:GetText())
        env.__items[1001] = { name = "Arrived", quality = 3 }
        helpers.fire(env, "GET_ITEM_INFO_RECEIVED", 1001, true)
        env.__runTimers()
        assertEqual("|cff0070ddArrived|r", row.name:GetText())
    end)

    it("searches as you type", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        frame.search:SetText("spire")
        assertEqual("Low Spire |cff80808055-60|r", frame.instances.rows[1].text:GetText())
    end)

    it("saves where it was dragged", function()
        local ns, env = opened()
        local frame = ns.Window.Frame()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 100, -50)
        frame.scripts.OnDragStop(frame)
        assertEqual("TOPLEFT", ns.db.window.point)
        assertEqual(100, ns.db.window.x)
    end)

    it("still opens when the backdrop template is missing", function()
        local ns, env = helpers.loadAddon(nil, function(env) env.__missingTemplates.BackdropTemplate = true end)
        helpers.sampleInstances(ns)
        helpers.login(ns, env)
        ns.Window.Open()
        assertTrue(ns.Window.Frame():IsShown())
    end)
end)

describe("searching from the window", function()
    it("does not error on pattern characters typed into the box", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        frame.search:SetText("[%(-")
        assertEqual("No matches", frame.instances.rows[1].text:GetText())
    end)

    it("jumps to an item's instance and boss when a result is clicked", function()
        local ns, env = opened()
        env.__items[3002] = { name = "Chest Prize", quality = 3 }
        local frame = ns.Window.Frame()
        frame.search:SetText("prize")
        local row = frame.instances.rows[2]
        row.scripts.OnClick(row, "LeftButton")
        assertEqual("Spire", ns.db.view.instance)
        assertEqual("objects", ns.db.view.boss)
    end)

    it("goes back to the instance list when the box is cleared", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        frame.search:SetText("spire")
        frame.search:SetText("")
        assertEqual("Test Depths |cff80808052-60|r", frame.instances.rows[1].text:GetText())
    end)
end)

describe("items the server cannot load", function()
    it("are marked unknown when the answer says so", function()
        local ns, env = opened()
        local row = ns.Window.Frame().loot.rows[1]
        helpers.fire(env, "GET_ITEM_INFO_RECEIVED", 1001, false)
        env.__runTimers()
        assertMatch("Unknown item 1001", row.name:GetText())
    end)
end)

describe("the places an item drops, in search results", function()
    it("are listed under the item, each with its chance", function()
        local ns, env = helpers.loggedIn()
        env.__items[1001] = { name = "Shared Blade", quality = 3 }
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "blade")
        assertEqual("Items|" .. "|cff0070ddShared Blade|r|"
            .. "    Test Depths: First Boss |cff80808020%|r|"
            .. "    Molten Test: Raid Boss |cff80808012%|r", texts(entries))
    end)

    it("name the notable lists the way the boss column does", function()
        local ns, env = helpers.loggedIn()
        env.__items[3002] = { name = "Chest Prize", quality = 3 }
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "prize")
        assertEqual("    Low Spire: Chests & objects |cff808080100%|r", entries[3].text)
    end)

    it("each jump to their own instance and boss when clicked", function()
        local ns, env = opened()
        env.__items[1001] = { name = "Shared Blade", quality = 3 }
        local frame = ns.Window.Frame()
        frame.search:SetText("blade")
        local row = frame.instances.rows[4]
        row.scripts.OnClick(row, "LeftButton")
        assertEqual("Core", ns.db.view.instance)
        assertEqual(1, ns.db.view.boss)
    end)
end)

describe("the redesigned window", function()
    it("is opaque", function()
        local ns = opened()
        assertEqual(1, ns.Window.Frame().background.colorTexture[4])
    end)

    it("numbers each boss and gives it a portrait", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.bosses[1].display = 8807
        helpers.login(ns, env)
        ns.Window.Open()
        local row = ns.Window.Frame().bosses.rows[2]
        assertEqual("First Boss", row.text:GetText())
        assertEqual("1", row.number:GetText())
        assertEqual(8807, row.portrait.portraitDisplay)
    end)

    it("gives the notable lists a bag and a chest", function()
        local ns = opened()
        local entries = ns.Window.BossEntries(ns.instanceByKey.Depths, 1)
        assertEqual(ns.Portrait.ICONS.trash, entries[#entries].icon)
    end)

    it("heads the page with the boss's model, name and instance", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.bosses[1].display = 8807
        helpers.login(ns, env)
        ns.Window.Open()
        local header = ns.Window.Frame().header
        assertEqual("First Boss", header.title:GetText())
        assertEqual("Test Depths, East", header.subtitle:GetText())
        assertEqual(8807, header.model.display)
        assertTrue(header.model:IsShown())
        assertFalse(header.portrait:IsShown())
    end)

    it("falls back to an icon in the header for a boss without a model", function()
        local ns = opened()
        local header = ns.Window.Frame().header
        assertFalse(header.model:IsShown())
        assertTrue(header.portrait:IsShown())
    end)

    it("heads a notable list with its icon and name", function()
        local ns = opened()
        ns.Window.SelectBoss("trash")
        local header = ns.Window.Frame().header
        assertEqual("From trash", header.title:GetText())
        assertEqual(ns.Portrait.ICONS.trash, header.portrait:GetTexture())
    end)

    it("shows the instance map in the header, the selected boss's pin lit", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.map = { cols = 2, rows = 2, cells = { 0, 12 } }
        ns.instanceByKey.Depths.bosses[2].pin = { 0.5, 0.5 }
        helpers.login(ns, env)
        ns.Window.Open()
        ns.Window.SelectBoss(2)
        local inset = ns.Window.Frame().inset
        assertTrue(inset.pins[1]:IsShown())
        assertTrue(inset.pins[1].selected)
    end)

    it("opens the full map from the inset, and a pin there picks that boss", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.map = { cols = 2, rows = 2, cells = { 0, 12 } }
        ns.instanceByKey.Depths.bosses[3].pin = { 0.5, 0.5 }
        helpers.login(ns, env)
        ns.Window.Open()
        local frame = ns.Window.Frame()
        frame.inset.scripts.OnClick(frame.inset, "LeftButton")
        assertTrue(frame.fullMap:IsShown())
        local pin = frame.fullMap.view.pins[1]
        pin.scripts.OnClick(pin, "LeftButton")
        assertEqual(3, ns.db.view.boss)
        assertFalse(frame.fullMap:IsShown())
    end)

    it("closes the full map when the instance changes", function()
        local ns = opened()
        ns.Window.OpenMap()
        ns.Window.SelectInstance("Spire")
        assertFalse(ns.Window.Frame().fullMap:IsShown())
    end)

    it("lays the loot out in two columns", function()
        local ns = opened()
        assertEqual(2, ns.Window.Frame().loot.options.columns)
    end)

    it("shows placeholder text in an empty search box", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        assertTrue(frame.searchHint:IsShown())
        frame.search:SetText("sp")
        assertFalse(frame.searchHint:IsShown())
    end)

    it("shows the normal list for a single letter", function()
        local ns = helpers.loggedIn()
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "z")
        assertEqual(2, #entries)
    end)

    it("gives a plain fallback button a font, so its label shows", function()
        local ns, env = helpers.loadAddon(nil, function(env) env.__missingTemplates.UIPanelButtonTemplate = true end)
        helpers.sampleInstances(ns)
        helpers.login(ns, env)
        ns.Window.Open()
        assertEqual("GameFontNormal", ns.Window.Frame().tabs.dungeon.normalFont)
    end)
end)
