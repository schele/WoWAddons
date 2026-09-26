local helpers = require("helpers")

local FILES = { "BossLoot.lua", "Format.lua", "List.lua", "ItemCache.lua", "LootRow.lua" }

local IRONFOE = { name = "Ironfoe", quality = 4, type = "Weapon", subType = "Maces", equipLoc = "INVTYPE_2HWEAPON", icon = 5555 }

-- One session: the addon loaded and logged in, with what was saved last time.
-- `stage` sets up the client (its language, its build) before login.
local function session(saved, stage)
    local ns, env = helpers.loadAddon(FILES, function(env)
        env.BossLootDB = saved
        if stage then stage(env) end
    end)
    helpers.login(ns, env)
    return ns, env
end

local function row(ns, env)
    local list = ns.List.Create(env.UIParent, {
        width = 320, rowHeight = ns.LootRow.HEIGHT, rows = 1,
        createRow = ns.LootRow.Create, renderRow = ns.LootRow.Render,
    })
    return list.rows[1]
end

-- A first session in which the client had Ironfoe; what it saved.
local function savedWithIronfoe(stage)
    local ns, env = session(nil, stage)
    env.__items[11684] = IRONFOE
    ns.LootRow.Render(row(ns, env), { id = 11684, chance = 1 })
    return env.BossLootDB
end

describe("an item loaded in an earlier session", function()
    it("shows straight away, without asking the server", function()
        local ns, env = session(savedWithIronfoe())
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        assertEqual("|cffa335eeIronfoe|r", r.name:GetText())
        assertEqual("Two-Hand, Maces", r.detail:GetText())
        assertEqual(5555, r.icon:GetTexture())
        env.__runTimers()
        assertNil(env.__requestCount[11684])
    end)

    it("links in chat with the link the client gave it", function()
        local ns, env = session(savedWithIronfoe())
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        r.scripts.OnClick(r, "LeftButton")
        assertEqual("|Hitem:11684|h[Ironfoe]|h", env.__modifiedClicks[1])
    end)

    it("is found by a search on its name", function()
        local saved = savedWithIronfoe()
        local ns, env = helpers.loadAddon(nil, function(env) env.BossLootDB = saved end)
        ns.AddInstance({
            key = "Depths", name = "Test Depths", kind = "dungeon", levels = { 52, 60 },
            bosses = { { name = "Emperor", loot = { { 11684, 4 } } } },
            notable = { trash = {}, objects = {} },
        })
        helpers.login(ns, env)
        local entries = ns.Window.InstanceEntries({ kind = "dungeon", instance = "" }, "ironfoe")
        assertEqual("|cffa335eeIronfoe|r", entries[2].text)
    end)
end)

describe("saving items", function()
    it("saves an item that arrives while it is not on screen", function()
        local ns, env = session(nil)
        ns.LootRow.RequestLoad(5001)
        env.__items[5001] = { name = "Background Item", quality = 2 }
        ns.LootRow.Arrived(5001, true)
        local laterNs, later = session(env.BossLootDB)
        laterNs.LootRow.RequestLoad(5001)
        later.__runTimers()
        assertNil(later.__requestCount[5001])
    end)

    it("still asks for an item it has never had", function()
        local ns, env = session(savedWithIronfoe())
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 999, chance = 5 })
        assertMatch("Loading", r.name:GetText())
        assertEqual(1, env.__requestCount[999])
    end)

    it("takes the client's copy over the saved one, and saves that", function()
        local ns, env = session(savedWithIronfoe())
        env.__items[11684] = { name = "Ironfoe Reforged", quality = 4 }
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        assertEqual("|cffa335eeIronfoe Reforged|r", r.name:GetText())

        local laterNs, later = session(env.BossLootDB)
        local laterRow = row(laterNs, later)
        laterNs.LootRow.Render(laterRow, { id = 11684, chance = 1 })
        assertEqual("|cffa335eeIronfoe Reforged|r", laterRow.name:GetText())
    end)
end)

describe("after a patch", function()
    local function patched(env) env.__build = "60001" end

    it("still shows the saved item, and asks the server about it again", function()
        local ns, env = session(savedWithIronfoe(), patched)
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        assertEqual("|cffa335eeIronfoe|r", r.name:GetText())
        env.__runTimers()
        assertEqual(1, env.__requestCount[11684])
    end)

    it("asks about it after the items on screen that have not loaded at all", function()
        local ns, env = session(savedWithIronfoe(), patched)
        for id = 5001, 5008 do ns.LootRow.RequestLoad(id) end
        for id = 9001, 9008 do ns.LootRow.RequestLoad(id, true) end
        ns.LootRow.Render(row(ns, env), { id = 11684, chance = 1 })
        -- The server answers each request as it comes.
        for _ = 1, 40 do
            env.__runTimers()
            for _, id in ipairs(env.__requestOrder) do ns.LootRow.Arrived(id, true) end
        end
        local position = {}
        for index, id in ipairs(env.__requestOrder) do position[id] = position[id] or index end
        assertTrue(position[11684], "the saved one is asked about in the end")
        for id = 9001, 9008 do
            assertTrue(position[id] < position[11684], "after the items with nothing to show")
        end
    end)

    it("keeps the saved copy when the server's answer comes back empty", function()
        local ns, env = session(savedWithIronfoe(), patched)
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        ns.LootRow.Arrived(11684, false)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        assertEqual("|cffa335eeIronfoe|r", r.name:GetText())
    end)

    it("does not ask again, once the server has answered, in later sessions of the same build", function()
        local ns, env = session(savedWithIronfoe(), patched)
        ns.LootRow.Render(row(ns, env), { id = 11684, chance = 1 })
        env.__items[11684] = IRONFOE
        ns.LootRow.Arrived(11684, true)

        local laterNs, later = session(env.BossLootDB, patched)
        laterNs.LootRow.Render(row(laterNs, later), { id = 11684, chance = 1 })
        later.__runTimers()
        assertNil(later.__requestCount[11684])
    end)
end)

describe("a change of language", function()
    it("starts afresh, so names in two languages never mix", function()
        local ns, env = session(savedWithIronfoe(), function(env) env.__locale = "deDE" end)
        local r = row(ns, env)
        ns.LootRow.Render(r, { id = 11684, chance = 1 })
        assertMatch("Loading", r.name:GetText())
        assertEqual(1, env.__requestCount[11684])
    end)
end)
