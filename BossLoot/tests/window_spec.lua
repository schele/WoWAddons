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
        assertEqual("Items|" .. "|cff0070ddHand of Justice|r|" .. "    Test Depths: First Boss", texts(entries))
        assertEqual("1.5%", entries[3].right)
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
        assertMatch("not loaded", row.name:GetText())
    end)
end)

describe("the places an item drops, in search results", function()
    it("are listed under the item, each with its chance", function()
        local ns, env = helpers.loggedIn()
        env.__items[1001] = { name = "Shared Blade", quality = 3 }
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "blade")
        assertEqual("Items|" .. "|cff0070ddShared Blade|r|"
            .. "    Test Depths: First Boss|"
            .. "    Molten Test: Raid Boss", texts(entries))
        assertEqual("20%", entries[3].right)
        assertEqual("12%", entries[4].right)
    end)

    it("name the notable lists the way the boss column does", function()
        local ns, env = helpers.loggedIn()
        env.__items[3002] = { name = "Chest Prize", quality = 3 }
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "prize")
        assertEqual("    Low Spire: Chests & objects", entries[3].text)
        assertEqual("100%", entries[3].right)
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
        ns.instanceByKey.Depths.map = { cols = 2, rows = 2, runs = { 0, 0, 1, 1, 1, 1 } }
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
        ns.instanceByKey.Depths.map = { cols = 2, rows = 2, runs = { 0, 0, 1, 1, 1, 1 } }
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

describe("the window, after review", function()
    local function withLongInstance()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        local bosses = {}
        for i = 1, 20 do bosses[i] = { name = "Boss " .. i, loot = { { 7000 + i, 10 } } } end
        ns.AddInstance({ key = "Long", name = "Long Halls", kind = "dungeon", levels = { 50, 60 }, bosses = bosses, notable = { trash = {}, objects = {} } })
        helpers.login(ns, env)
        ns.Window.Open()
        return ns, env
    end

    it("shows a chest, not a skull, for a boss with no model", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        assertEqual(ns.Portrait.ICONS.objects, frame.header.portrait:GetTexture())
        assertEqual(ns.Portrait.ICONS.objects, frame.bosses.rows[2].portrait:GetTexture())
    end)

    it("draws the search placeholder on the box, above the box's art", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        assertEqual(frame.search, frame.searchHint:GetParent())
    end)

    it("does not reload the boss's model when it has not changed", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.bosses[1].display = 8807
        helpers.login(ns, env)
        ns.Window.Open()
        ns.Window.Refresh()
        ns.Window.Refresh()
        assertEqual(1, ns.Window.Frame().header.model.displaySets)
    end)

    it("does not redraw portraits that have not changed", function()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.bosses[1].display = 8807
        helpers.login(ns, env)
        ns.Window.Open()
        local before = env.__portraitCalls
        ns.Window.Refresh()
        assertEqual(before, env.__portraitCalls)
    end)

    it("keeps the selected boss in view in a long list", function()
        local ns = withLongInstance()
        ns.Window.SelectInstance("Long")
        ns.Window.SelectBoss(20)
        local seen = false
        for _, row in ipairs(ns.Window.Frame().bosses.rows) do
            if row:IsShown() and row.entry and row.entry.value == 20 then seen = true end
        end
        assertTrue(seen)
    end)

    it("opens another instance at the top of its boss list", function()
        local ns = withLongInstance()
        ns.Window.SelectInstance("Long")
        ns.Window.SelectBoss(20)
        ns.Window.SelectInstance("Depths")
        assertEqual(0, ns.Window.Frame().bosses.offset)
    end)

    it("keeps every list, and the line under it, inside the window", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        for name, list in pairs({ rail = frame.instances, bosses = frame.bosses, loot = frame.loot, mapLoot = frame.mapLoot }) do
            local _, _, _, _, y = list:GetPoint(1)
            assertTrue(-y + list:GetHeight() + 16 <= 520 - 12, name .. " runs past the bottom")
        end
    end)

    it("keeps the full map's close button above its pins", function()
        local ns = opened()
        local full = ns.Window.Frame().fullMap
        assertTrue(full.close:GetFrameLevel() > full.view:GetFrameLevel() + 2)
    end)
end)

describe("the loot while the big map is open", function()
    it("moves under the bosses, and back when the map closes", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        local fullRows = frame.bosses.options.rows

        ns.Window.OpenMap()
        assertFalse(frame.loot:IsShown(), "gone from the page, under the map")
        assertTrue(frame.mapLoot:IsShown(), "under the bosses instead")
        assertEqual(1001, frame.mapLoot.rows[1].entry.id)
        assertTrue(frame.bosses.options.rows < fullRows, "the boss list makes room")

        ns.Window.CloseMap()
        assertTrue(frame.loot:IsShown())
        assertFalse(frame.mapLoot:IsShown())
        assertEqual(fullRows, frame.bosses.options.rows)
        assertEqual(1001, frame.loot.rows[1].entry.id)
    end)

    it("follows a boss picked on the map", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        ns.Window.OpenMap()
        ns.Window.SelectBoss(2)
        assertEqual(1003, frame.mapLoot.rows[1].entry.id)
    end)
end)

describe("the loot under the bosses", function()
    it("starts right under the last boss, not at a fixed place", function()
        local ns = opened()
        ns.Window.SelectInstance("Spire")
        ns.Window.OpenMap()
        local _, _, _, _, y = ns.Window.Frame().mapLoot:GetPoint(1)
        assertEqual(-(40 + 3 * 34 + 6), y, "three rows: the boss, the heading, the chest list")
    end)

    it("leaves room for the more line when the bosses do not all fit", function()
        local ns = opened()
        ns.Window.OpenMap()
        local _, _, _, _, y = ns.Window.Frame().mapLoot:GetPoint(1)
        assertEqual(-(40 + 6 * 34 + 16 + 6), y)
    end)
end)

describe("an item picked from the search", function()
    local function searched()
        local ns, env = opened()
        env.__items[1002] = { name = "Hand of Justice", quality = 3 }
        local frame = ns.Window.Frame()
        frame.search:SetText("justice")
        return ns, env, frame
    end

    local function lootRowFor(frame, id)
        for _, row in ipairs(frame.loot.rows) do
            if row:IsShown() and row.entry and row.entry.id == id then return row end
        end
    end

    it("is highlighted in the results and in the loot", function()
        local ns, env, frame = searched()
        local itemRow = frame.instances.rows[2]
        itemRow.scripts.OnClick(itemRow, "LeftButton")
        assertTrue(frame.instances.rows[2].selectedTexture:IsShown(), "the item in the results")
        assertTrue(frame.instances.rows[3].selectedTexture:IsShown(), "the place it was found")
        assertTrue(lootRowFor(frame, 1002).selectedTexture:IsShown(), "the item in the loot")
        assertFalse(lootRowFor(frame, 1001).selectedTexture:IsShown(), "and nothing else")
    end)

    it("is highlighted when picked by its place, too", function()
        local ns, env, frame = searched()
        local placeRow = frame.instances.rows[3]
        placeRow.scripts.OnClick(placeRow, "LeftButton")
        assertTrue(lootRowFor(frame, 1002).selectedTexture:IsShown())
        assertTrue(frame.instances.rows[3].selectedTexture:IsShown())
    end)

    it("stops being highlighted when the search is cleared", function()
        local ns, env, frame = searched()
        frame.instances.rows[2].scripts.OnClick(frame.instances.rows[2], "LeftButton")
        frame.search:SetText("")
        assertFalse(lootRowFor(frame, 1002).selectedTexture:IsShown())
    end)
end)

describe("the big map's title", function()
    it("names the instance", function()
        local ns = opened()
        ns.Window.OpenMap()
        assertEqual("Test Depths", ns.Window.Frame().fullMap.title:GetText())
    end)
end)

describe("turning the boss's model by hand", function()
    local function withModels()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.bosses[1].display = 8807
        ns.instanceByKey.Depths.bosses[2].display = 8808
        helpers.login(ns, env)
        ns.Window.Open()
        return ns, env, ns.Window.Frame().header.model
    end

    it("turns the boss as the cursor drags across it", function()
        local ns, env, model = withModels()
        local start = model.facing
        env.__cursorX = 100
        model.scripts.OnMouseDown(model, "LeftButton")
        env.__cursorX = 150
        model.scripts.OnUpdate(model, 0)
        assertTrue(math.abs(model.facing - (start + 1)) < 1e-9, "50 pixels, a little under a third of a turn")
        model.scripts.OnMouseUp(model, "LeftButton")
        env.__cursorX = 300
        model.scripts.OnUpdate(model, 0)
        assertTrue(math.abs(model.facing - (start + 1)) < 1e-9, "not once let go")
    end)

    it("stays where it was turned to, until another boss is picked", function()
        local ns, env, model = withModels()
        env.__cursorX = 100
        model.scripts.OnMouseDown(model, "LeftButton")
        env.__cursorX = 130
        model.scripts.OnUpdate(model, 0)
        model.scripts.OnMouseUp(model, "LeftButton")
        local facing = model.facing
        model.scripts.OnUpdate(model, 1)
        assertEqual(facing, model.facing, "no longer turning by itself")
        ns.Window.SelectBoss(2)
        model.scripts.OnUpdate(model, 1)
        assertTrue(model.facing ~= facing, "the next boss turns by itself again")
    end)
end)

describe("the item loading bar", function()
    -- The sample Test Depths has five items: four from bosses, one from trash.
    local function opened(loaded)
        local ns, env = helpers.loggedIn()
        for _, id in ipairs(loaded or {}) do env.__items[id] = { name = "Item " .. id, quality = 2 } end
        ns.Window.Open()
        return ns, env, ns.Window.Frame().progress
    end

    -- Ask for every item until the server is given up on.
    local function giveUpOnAll(env)
        env.__now = 100
        function env.GetTime() return env.__now end
        for _ = 1, 10 do
            env.__now = env.__now + 11
            env.__runTimers()
            env.__runTimers()
        end
    end

    it("shows how many of the instance's items have loaded", function()
        local ns, env, bar = opened({ 1001, 1002 })
        assertTrue(bar:IsShown())
        assertEqual("Loading items 2 / 5", bar.text:GetText())
        assertEqual(bar:GetWidth() * 2 / 5, bar.fill:GetWidth())
    end)

    it("is gone once every item has loaded", function()
        local ns, env, bar = opened({ 1001, 1002, 1003, 1004, 2001 })
        assertFalse(bar:IsShown())
    end)

    it("fills in as items arrive, with nothing else redrawn", function()
        local ns, env, bar = opened()
        assertEqual("Loading items 0 / 5", bar.text:GetText())
        env.__items[1001] = { name = "Late", quality = 2 }
        bar.scripts.OnUpdate(bar, 1)
        assertEqual("Loading items 1 / 5", bar.text:GetText())
    end)

    it("says how many could not be loaded, and asks for them again on a click", function()
        local ns, env, bar = opened({ 1001 })
        giveUpOnAll(env)
        bar.scripts.OnUpdate(bar, 1)
        assertEqual("1 / 5 items, 4 failed: click to retry", bar.text:GetText())
        assertEqual(bar:GetWidth() * 4 / 5, bar.failedFill:GetWidth())

        local asked = env.__requestCount[1002]
        bar.scripts.OnClick(bar, "LeftButton")
        assertEqual(asked + 1, env.__requestCount[1002])
        assertEqual("Loading items 1 / 5", bar.text:GetText())
    end)

    it("breaks the count down on hover", function()
        local ns, env, bar = opened({ 1001 })
        bar.scripts.OnEnter(bar)
        assertMatch("1 loaded", table.concat(env.GameTooltip.lines, "\n"))
        assertMatch("4 loading", table.concat(env.GameTooltip.lines, "\n"))
    end)
end)

describe("the big model", function()
    local function withModels()
        local ns, env = helpers.loadAddon()
        helpers.sampleInstances(ns)
        ns.instanceByKey.Depths.bosses[1].display = 8807
        ns.instanceByKey.Depths.bosses[2].display = 8808
        helpers.login(ns, env)
        ns.Window.Open()
        local frame = ns.Window.Frame()
        return ns, env, frame.header.model, frame.modelView
    end

    local function click(env, model)
        env.__cursorX = 100
        model.scripts.OnMouseDown(model, "LeftButton")
        model.scripts.OnMouseUp(model, "LeftButton")
    end

    it("opens on a click on the boss's model, with the boss in it", function()
        local ns, env, model, view = withModels()
        assertFalse(view:IsShown())
        click(env, model)
        assertTrue(view:IsShown())
        assertEqual(8807, view.model.display)
        assertEqual("First Boss", view.title:GetText())
    end)

    it("does not open when the small model is dragged round", function()
        local ns, env, model, view = withModels()
        env.__cursorX = 100
        model.scripts.OnMouseDown(model, "LeftButton")
        env.__cursorX = 150
        model.scripts.OnUpdate(model, 0)
        model.scripts.OnMouseUp(model, "LeftButton")
        assertFalse(view:IsShown())
    end)

    it("turns when dragged, and zooms with the mouse wheel", function()
        local ns, env, model, view = withModels()
        click(env, model)
        local big = view.model
        local start = big.facing
        env.__cursorX = 100
        big.scripts.OnMouseDown(big, "LeftButton")
        env.__cursorX = 150
        big.scripts.OnUpdate(big, 0)
        big.scripts.OnMouseUp(big, "LeftButton")
        assertTrue(math.abs(big.facing - (start + 1)) < 1e-9)

        big.scripts.OnMouseWheel(big, 1)
        assertTrue(big.camDistanceScale < 1, "closer")
        for _ = 1, 30 do big.scripts.OnMouseWheel(big, -1) end
        assertTrue(big.camDistanceScale <= 3, "but only so far away")
    end)

    it("shows whichever boss is picked while it is open", function()
        local ns, env, model, view = withModels()
        click(env, model)
        ns.Window.SelectBoss(2)
        assertEqual(8808, view.model.display)
        assertEqual("Second Boss", view.title:GetText())
    end)

    it("closes for a pick with no model, and with its button", function()
        local ns, env, model, view = withModels()
        click(env, model)
        ns.Window.SelectBoss(3)
        assertFalse(view:IsShown(), "the third boss has no model")

        ns.Window.SelectBoss(1)
        click(env, model)
        view.close.scripts.OnClick(view.close, "LeftButton")
        assertFalse(view:IsShown())
    end)
end)

describe("close buttons", function()
    it("are all the same size: the game's own", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        for _, close in ipairs({ frame.fullMap.close, frame.modelView.close }) do
            assertEqual(frame.close:GetWidth(), close:GetWidth())
            assertEqual(frame.close:GetHeight(), close:GetHeight())
        end
    end)
end)

describe("the item loading bar's place", function()
    it("sits in the window's top row, where the big map does not cover it", function()
        local ns = opened()
        local frame = ns.Window.Frame()
        assertEqual(frame, frame.progress:GetParent())
        ns.Window.OpenMap()
        local _, _, _, _, barTop = frame.progress:GetPoint(1)
        local _, _, _, _, mapTop = frame.fullMap:GetPoint(1)
        assertTrue(barTop > mapTop, "above the map")
    end)

    it("keeps its text inside the bar, cut short if need be", function()
        local ns = opened()
        local text = ns.Window.Frame().progress.text
        assertEqual(false, text.wordWrap)
        assertEqual(2, #text.points, "held at both ends of the bar")
    end)
end)

describe("loading every item", function()
    -- The samples hold seven items: five in Test Depths, two in Low Spire,
    -- and the raid's one is also Test Depths' first.
    local function opened(loaded)
        local ns, env = helpers.loggedIn()
        for _, id in ipairs(loaded or {}) do env.__items[id] = { name = "Item " .. id, quality = 2 } end
        ns.Window.Open()
        return ns, env, ns.Window.Frame().allProgress
    end

    it("asks for every item once the window opens, behind the open instance's", function()
        local ns, env = opened()
        env.__runTimers()
        local position = {}
        for index, id in ipairs(env.__requestOrder) do position[id] = position[id] or index end
        assertTrue(position[3001] and position[3002], "Low Spire's too, though Test Depths is open")
        assertTrue(position[2001] < position[3001], "after Test Depths' own")
    end)

    it("counts every item on a bar of its own", function()
        local ns, env, bar = opened({ 1001, 3001 })
        assertTrue(bar:IsShown())
        assertEqual("All items 2 / 7", bar.text:GetText())
        assertEqual(bar:GetWidth() * 2 / 7, bar.fill:GetWidth())
    end)

    it("moves as items arrive, and is gone once all have", function()
        local ns, env, bar = opened({ 1001, 1002, 1003, 1004, 2001, 3001 })
        assertEqual("All items 6 / 7", bar.text:GetText())
        env.__items[3002] = { name = "Last", quality = 2 }
        bar.scripts.OnUpdate(bar, 1)
        assertFalse(bar:IsShown())
    end)

    it("leaves out the items of hidden instances", function()
        local ns, env, bar = opened({ 1001 })
        ns.Window.HideInstance("Spire")
        assertEqual("All items 1 / 5", bar.text:GetText())
        helpers.command(env, "unhide")
        assertEqual("All items 1 / 7", bar.text:GetText())
    end)

    it("says how many failed, and asks for them again on a click", function()
        local ns, env, bar = opened({ 1001 })
        env.__now = 100
        function env.GetTime() return env.__now end
        for _ = 1, 10 do
            env.__now = env.__now + 11
            env.__runTimers()
            env.__runTimers()
        end
        bar.scripts.OnUpdate(bar, 1)
        assertEqual("All items 1 / 7 (6 failed)", bar.text:GetText())
        local asked = env.__requestCount[3002]
        bar.scripts.OnClick(bar, "LeftButton")
        assertEqual(asked + 1, env.__requestCount[3002])
        assertEqual("All items 1 / 7", bar.text:GetText())
    end)
end)
