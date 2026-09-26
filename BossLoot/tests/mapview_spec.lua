local helpers = require("helpers")
local FILES = { "BossLoot.lua", "MapView.lua" }

local instance = {
    key = "T", name = "T", kind = "dungeon", levels = { 1, 2 },
    map = { cols = 4, rows = 2, cells = { 0 * 4 + 0, 7 * 4 + 3 } },
    bosses = {
        { name = "A", pin = { 0.25, 0.5 }, loot = {} },
        { name = "Summoned", loot = {} },
        { name = "C", pin = { 1, 1 }, loot = {} },
    },
    notable = { trash = {}, objects = {} },
}

local function shown(list)
    local n = 0
    for _, item in ipairs(list) do if item:IsShown() then n = n + 1 end end
    return n
end

describe("the map view", function()
    it("scales a map to fit and centres it", function()
        local ns = helpers.loadAddon(FILES)
        local scale, ox, oy = ns.MapView.Layout({ cols = 4, rows = 2 }, 200, 200)
        assertEqual(50, scale); assertEqual(0, ox); assertEqual(50, oy)
    end)

    it("draws a square per filled cell, where the cell is", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        assertEqual(2, shown(view.cells))
        local _, _, _, x, y = view.cells[2]:GetPoint(1)
        assertEqual(175, x, "column 3 of 4, centred")
        assertEqual(-125, y, "row 1 of 2, below the top margin")
    end)

    it("colours higher cells lighter", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        assertTrue(view.cells[2].colorTexture[3] > view.cells[1].colorTexture[3])
    end)

    it("pins every boss that has a place, numbered by its place in the list", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance, 3)
        assertEqual(2, shown(view.pins))
        assertEqual("1", view.pins[1].text:GetText())
        assertEqual("3", view.pins[2].text:GetText())
        assertTrue(view.pins[2].selected)
        assertFalse(view.pins[1].selected)
    end)

    it("hands a pin click to its owner", function()
        local ns, env = helpers.loadAddon(FILES)
        local clicked
        local view = ns.MapView.Create(env.UIParent, 200, 200, { onPinClick = function(boss) clicked = boss end })
        ns.MapView.Show(view, instance)
        view.pins[2].scripts.OnClick(view.pins[2], "LeftButton")
        assertEqual(3, clicked)
    end)

    it("reuses its textures from one instance to the next", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        ns.MapView.Show(view, instance)
        assertEqual(2, #view.cells)
    end)

    it("shows nothing, and does not fail, for an instance without a map", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        ns.MapView.Show(view, { bosses = {}, notable = {} })
        assertEqual(0, shown(view.cells))
        assertEqual(0, shown(view.pins))
        ns.MapView.Show(view, nil)
    end)
end)
