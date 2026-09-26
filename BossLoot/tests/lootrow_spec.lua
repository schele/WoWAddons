local helpers = require("helpers")

local FILES = { "BossLoot.lua", "Format.lua", "List.lua", "LootRow.lua" }

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
        assertEqual("1.0%", r.chance:GetText())
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
