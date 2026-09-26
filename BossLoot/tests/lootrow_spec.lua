local helpers = require("helpers")

local FILES = { "BossLoot.lua", "Format.lua", "List.lua", "ItemCache.lua", "ItemData.lua", "LootRow.lua" }

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

    it("waits longer before each try after that", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__now = 100
        function env.GetTime() return env.__now end
        ns.LootRow.RequestLoad(999)
        ns.LootRow.Arrived(999, false)
        env.__now = 106
        env.__runTimers()
        ns.LootRow.Arrived(999, false)
        env.__now = 115
        env.__runTimers()
        assertEqual(2, env.__requestCount[999], "not after another five seconds")
        env.__now = 122
        env.__runTimers()
        assertEqual(3, env.__requestCount[999], "but after fifteen")
    end)
end)

describe("asking the server for items", function()
    local function count(env)
        local n = 0
        for _, c in pairs(env.__requestCount) do n = n + c end
        return n
    end

    it("asks one at a time, a moment apart", function()
        -- Eight at once, thirty-two a second, and the server refused most.
        local ns, env = helpers.loadAddon(FILES)
        for id = 5001, 5030 do ns.LootRow.RequestLoad(id) end
        assertEqual(1, count(env))
        env.__runTimers()
        assertEqual(2, count(env))
    end)

    it("keeps no more than a few requests out at once", function()
        local ns, env = helpers.loadAddon(FILES)
        for id = 5001, 5030 do ns.LootRow.RequestLoad(id) end
        for _ = 1, 10 do env.__runTimers() end
        assertEqual(ns.LootRow.MAX_IN_FLIGHT, count(env))
    end)

    it("asks for the next as soon as an answer frees a place", function()
        local ns, env = helpers.loadAddon(FILES)
        for id = 5001, 5030 do ns.LootRow.RequestLoad(id) end
        for _ = 1, 10 do env.__runTimers() end
        ns.LootRow.Arrived(5001, true)
        env.__runTimers()
        assertEqual(ns.LootRow.MAX_IN_FLIGHT + 1, count(env))
    end)

    it("asks for what is on screen before the rest", function()
        local ns, env = helpers.loadAddon(FILES)
        for id = 5001, 5030 do ns.LootRow.RequestLoad(id) end
        ns.LootRow.RequestLoad(9999, true)
        assertNil(env.__requestCount[9999], "one is already out this moment")
        env.__runTimers()
        assertEqual(1, env.__requestCount[9999])
        assertNil(env.__requestCount[5002], "ahead of the rest")
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
        for _ = 1, 20 do
            env.__now = env.__now + 11
            env.__runTimers()
            env.__runTimers()
        end
        assertEqual(ns.LootRow.MAX_TRIES, env.__requestCount[999])
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

describe("how far a list of items has loaded", function()
    -- Ask for an item until the server is given up on.
    local function giveUp(ns, env, itemID)
        env.__now = env.__now or 100
        function env.GetTime() return env.__now end
        ns.LootRow.RequestLoad(itemID)
        for _ = 1, 10 do
            env.__now = env.__now + 11
            env.__runTimers()
            env.__runTimers()
        end
    end

    it("counts the items loaded, still loading, and given up on", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__items[5001] = { name = "Here", quality = 2 }
        giveUp(ns, env, 5003)
        local status = ns.LootRow.Status({ 5001, 5002, 5003 })
        assertEqual(3, status.total)
        assertEqual(1, status.loaded)
        assertEqual(1, status.loading)
        assertEqual(1, status.failed)
    end)

    it("asks again for the items given up on", function()
        local ns, env = helpers.loadAddon(FILES)
        giveUp(ns, env, 5003)
        local asked = env.__requestCount[5003]
        ns.LootRow.Retry({ 5001, 5003 })
        assertEqual(asked + 1, env.__requestCount[5003])
        assertEqual(0, ns.LootRow.Status({ 5003 }).failed, "loading again")
    end)
end)

describe("a long wait for items", function()
    it("looks at only as many waiting items each moment as it can ask for", function()
        -- Every item in the game waiting: going over them all four times a
        -- second would stall the game.
        local ns, env = helpers.loadAddon(FILES)
        for id = 10001, 12000 do ns.LootRow.RequestLoad(id) end
        env.__infoCalls = 0
        env.__runTimers()
        assertTrue(env.__infoCalls < 100, "looked at " .. env.__infoCalls)
        local asked = 0
        for _ in pairs(env.__requestCount) do asked = asked + 1 end
        assertEqual(2, asked, "and still asks for the next")
    end)
end)

describe("what the queue is doing", function()
    it("counts what it asked for and what came back", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__now = 100
        function env.GetTime() return env.__now end
        for id = 5001, 5010 do ns.LootRow.RequestLoad(id) end
        for _ = 1, 3 do env.__runTimers() end -- 5001 to 5004 out
        ns.LootRow.Arrived(5001, true)
        ns.LootRow.Arrived(5002, false)
        env.__now = 111 -- 5003 and 5004 unanswered
        env.__runTimers()
        local activity = ns.LootRow.Activity()
        assertEqual(1, activity.answered)
        assertEqual(1, activity.empty)
        assertEqual(2, activity.noAnswer)
        assertEqual(5, activity.asked, "four, then 5005")
        assertEqual(1, activity.asking)
        assertEqual(8, activity.waiting, "5006 to 5010, then 5003, 5004 and 5002 again")
    end)
end)

describe("an item the addon knows without the server", function()
    -- A robe (armor, cloth, chest) and a maul (weapon, two-handed mace, two-hand).
    local function withBuiltIn()
        local ns, env = helpers.loadAddon(FILES)
        ns.AddItems({ [7001] = { "Test Robe", 3, 4, 1, 5 }, [7002] = { "Test Maul", 4, 2, 5, 17 } })
        return ns, env
    end

    it("shows at once, named and coloured, with its slot and kind", function()
        local ns, env = withBuiltIn()
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 7001, chance = 5 })
        assertEqual("|cff0070ddTest Robe|r", r.name:GetText())
        assertEqual("Chest, Cloth", r.detail:GetText())
        assertEqual(107001, r.icon:GetTexture(), "the icon from the client, which has it")
    end)

    it("names a weapon's kind as the game does", function()
        local ns, env = withBuiltIn()
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 7002, chance = 5 })
        assertEqual("Two-Hand, Two-Handed Maces", r.detail:GetText())
    end)

    it("still asks the server, and takes its copy when it comes", function()
        local ns, env = withBuiltIn()
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 7001, chance = 5 })
        assertEqual(1, env.__requestCount[7001])
        env.__items[7001] = { name = "Server Robe", quality = 3 }
        ns.LootRow.Render(r, { id = 7001, chance = 5 })
        assertEqual("|cff0070ddServer Robe|r", r.name:GetText())
    end)

    it("links in chat by its built-in name", function()
        local ns, env = withBuiltIn()
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 7001, chance = 5 })
        r.scripts.OnClick(r, "LeftButton")
        assertMatch("item:7001", env.__modifiedClicks[1])
        assertMatch("%[Test Robe%]", env.__modifiedClicks[1])
    end)

    it("uses the client's own names for kinds, when it has them", function()
        local ns, env = withBuiltIn()
        function env.GetItemSubClassInfo(class, subclass) return class == 4 and subclass == 1 and "Stoff" or nil end
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 7001, chance = 5 })
        assertEqual("Chest, Stoff", r.detail:GetText())
    end)
end)

describe("the rows around recorded loot", function()
    it("draws a heading with its note, no icon, and no clicks", function()
        local ns, env = helpers.loadAddon(FILES)
        local r = row(ns, env)
        ns.LootRow.Render(r, { heading = "Classic loot", note = "Not seen on WoW Forever yet" })
        assertMatch("Classic loot", r.name:GetText())
        assertEqual("Not seen on WoW Forever yet", r.detail:GetText())
        assertFalse(r.icon:IsShown())
        assertFalse(r.mouseEnabled)
        ns.LootRow.Render(r, { blank = true })
        assertEqual("", r.name:GetText())
    end)

    it("dims a classic row, and shows a recorded one's count", function()
        local ns, env = helpers.loadAddon(FILES)
        env.__items[1001] = { name = "One", quality = 2 }
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 1001, chance = 20, classic = true })
        assertEqual(0.45, r.alpha)
        ns.LootRow.Render(r, { id = 1001, seen = "3/5" })
        assertEqual(1, r.alpha)
        assertEqual("3/5", r.chance:GetText())
        assertTrue(r.icon:IsShown())
        assertTrue(r.mouseEnabled)
    end)
end)
