local helpers = require("helpers")

local FILES = { "BossLoot.lua", "Format.lua", "List.lua", "ItemCache.lua", "LootRow.lua" }

local function row(ns, env)
    local list = ns.List.Create(env.UIParent, {
        width = 320, rowHeight = ns.LootRow.HEIGHT, rows = 1,
        createRow = ns.LootRow.Create, renderRow = ns.LootRow.Render,
    })
    return list.rows[1], list
end

describe("a loot row", function()
    it("shows a loaded item's icon, coloured name, type and chance", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__items[11684] = { name = "Ironfoe", quality = 4, type = "Weapon", subType = "Maces", equipLoc = "INVTYPE_2HWEAPON", icon = 5555 }
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        assertEqual(5555, r.icon:GetTexture())
        assertEqual("|cffa335eeIronfoe|r", r.name:GetText())
        assertEqual("Two-Hand, Maces", r.detail:GetText())
        assertEqual("1%", r.chance:GetText())
    end)

    it("says what drops a notable item instead of its type", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__items[2001] = { name = "Rare Ring", quality = 3 }
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 2001, chance = 0.9, sources = { "Anvilrage Overseer", "Anvilrage Guardsman" } })
        assertEqual("Anvilrage Overseer, Anvilrage Guardsman", r.detail:GetText())
    end)

    it("shows a placeholder, and asks for the item, when the client has not loaded it", function()
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        assertMatch("Loading", r.name:GetText())
        assertEqual(100999, r.icon:GetTexture(), "the icon lookup works without the item")
        assertTrue(env.__requested[999])
    end)

    it("fills in once the item has loaded and the row is drawn again", function()
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        env.__items[999] = { name = "Late Item", quality = 2 }
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        assertEqual("|cff1eff00Late Item|r", r.name:GetText())
    end)

    it("shows the item's tooltip on hover and hides it after", function()
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        r.scripts.OnEnter(r)
        assertEqual(999, env.GameTooltip.itemID)
        assertTrue(env.GameTooltip:IsShown())
        r.scripts.OnLeave(r)
        assertFalse(env.GameTooltip:IsShown())
    end)

    it("hands a click to the game's own modified-click handling, for linking and previewing", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__items[11684] = { name = "Ironfoe", quality = 4 }
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        r.scripts.OnClick(r, "LeftButton")
        assertMatch("item:11684", env.__modifiedClicks[1])
    end)

    it("ignores a click on an item that has not loaded", function()
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        r.scripts.OnClick(r, "LeftButton")
        assertEqual(0, #env.__modifiedClicks)
    end)
end)

describe("an item that will not load", function()
    it("is asked for once, however often its row is drawn", function()
        -- Every draw asking again, and every answer redrawing, is a loop
        -- for an item the server does not have.
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        assertEqual(1, env.__requestCount[999])
    end)

    it("says it is unknown once the server says it has no such item", function()
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        ns.LootRow.Arrived(999, false)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        assertMatch("999", r.name:GetText())
        assertMatch("not loaded", r.name:GetText())
    end)
end)

describe("a loot tile's text", function()
    it("keeps the name and the type line on one line each, so they cannot run into each other", function()
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        assertEqual(false, r.name.wordWrap)
        assertEqual(false, r.detail.wordWrap)
    end)
end)

describe("an item the server did not send", function()
    it("is asked for again after a moment, not given up on", function()
        -- Hundreds of items asked for at once, some answers come back empty;
        -- the item is real (its icon shows), so it is worth asking again.
        local ns, env = helpers.loadAddon(FILES)
        env.__now = 100
        function env.GetTime() return env.__now end
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        ns.LootRow.Arrived(999, false)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        env.__runTimers()
        assertEqual(1, env.__requestCount[999], "not straight away")
        env.__now = 106
        env.__runTimers()
        assertEqual(2, env.__requestCount[999], "again after a few seconds")
    end)
end)

describe("asking the server for items", function()
    local function count(env)
        local n = 0
        for _, c in pairs(env.__requestCount) do n = n + c end
        return n
    end

    it("asks a few at a time, not hundreds at once", function()
        -- Asked for a whole instance at once, the server drops most requests.
        local ns, env = helpers.loadAddon(FILES)
        for id = 5001, 5030 do ns.LootRow.RequestLoad(id) end
        assertEqual(8, count(env))
        env.__runTimers()
        assertEqual(16, count(env))
    end)

    it("asks for what is on screen before the rest", function()
        local ns, env = helpers.loadAddon(FILES)
        for id = 5001, 5030 do ns.LootRow.RequestLoad(id) end
        ns.LootRow.RequestLoad(9999, true)
        assertNil(env.__requestCount[9999], "the first few are already used")
        env.__runTimers()
        assertEqual(1, env.__requestCount[9999])
        assertNil(env.__requestCount[5030], "ahead of the rest")
    end)

    it("asks again for an item the server never answered", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__now = 100
        function env.GetTime() return env.__now end
        ns.LootRow.RequestLoad(999)
        env.__now = 111
        env.__runTimers()
        env.__runTimers()
        assertEqual(2, env.__requestCount[999])
    end)

    it("gives up after a few tries, and says so", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__now = 100
        function env.GetTime() return env.__now end
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        for _ = 1, 10 do
            env.__now = env.__now + 11
            env.__runTimers()
            env.__runTimers()
        end
        assertEqual(4, env.__requestCount[999])
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        assertMatch("not loaded", r.name:GetText())
    end)

    it("does not ask for an item it already has", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__items[5001] = { name = "Here", quality = 2 }
        ns.LootRow.RequestLoad(5001)
        assertNil(env.__requestCount[5001])
    end)
end)
