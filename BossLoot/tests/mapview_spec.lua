local helpers = require("helpers")
local FILES = { "BossLoot.lua", "MapView.lua" }

-- A 4 by 2 map: two cells of floor at the top left, one at the bottom right.
local instance = {
    key = "T", name = "T", kind = "dungeon", levels = { 1, 2 },
    map = { cols = 4, rows = 2, runs = { 0, 0, 2, 1, 3, 1 } },
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

    it("draws a strip per run of floor, where the run is", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        assertEqual(2, shown(view.floor))
        local _, _, _, x, y = view.floor[2]:GetPoint(1)
        assertEqual(150, x, "column 3 of 4")
        assertEqual(-100, y, "row 1 of 2, below the top margin")
        assertEqual(50, view.floor[2]:GetWidth())
        assertEqual(50, view.floor[2]:GetHeight())
    end)

    it("outlines the floor by drawing it a cell wider underneath, in a lighter colour", function()
        local ns, env = helpers.loadAddon(FILES)
        local outline = ns.MapView.Outline(instance.map)
        assertEqual("0,0,4,1,0,4", table.concat(outline, ","))
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        assertEqual(2, shown(view.edges))
        assertTrue(view.edges[1].colorTexture[1] > view.floor[1].colorTexture[1])
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

    it("reuses its strips from one instance to the next", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        ns.MapView.Show(view, { map = { cols = 4, rows = 2, runs = { 0, 0, 1, 1, 1, 1 } }, bosses = {} })
        ns.MapView.Show(view, instance)
        assertEqual(2, #view.floor)
    end)

    it("shows nothing, and does not fail, for an instance without a map", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance)
        ns.MapView.Show(view, { bosses = {}, notable = {} })
        assertEqual(0, shown(view.floor))
        assertEqual(0, shown(view.edges))
        assertEqual(0, shown(view.pins))
        ns.MapView.Show(view, nil)
    end)
end)

describe("redrawing the same map", function()
    it("leaves the strips alone and only updates the pins", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 200, 200)
        ns.MapView.Show(view, instance, 1)
        ns.MapView.Show(view, instance, 3)
        assertEqual(1, view.floor[1].colorSets)
        assertTrue(view.pins[2].selected, "the new selection still shows")
    end)
end)

describe("the map's finish", function()
    local block = {
        name = "Block", map = { cols = 3, rows = 3, runs = { 0, 0, 3, 1, 0, 3, 2, 0, 3 } },
        entrance = { 0.1, 0.9 },
        bosses = {
            { name = "Left Boss", pin = { 0.2, 0.5 }, loot = {} },
            { name = "Right Boss", pin = { 0.9, 0.5 }, loot = {} },
        },
        notable = { trash = {}, objects = {} },
    }

    it("shades the floor inside its rim darker, so the walls stand up", function()
        local ns, env = helpers.loadAddon(FILES)
        assertEqual("1,1,1", table.concat(ns.MapView.Inner(block.map), ","))
        local view = ns.MapView.Create(env.UIParent, 300, 300)
        ns.MapView.Show(view, block)
        assertEqual(1, shown(view.inner))
        assertTrue(view.inner[1].colorTexture[1] < view.floor[1].colorTexture[1])
    end)

    it("writes each boss's name beside its pin on a map that wants labels", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 300, 300, { labels = true })
        ns.MapView.Show(view, block, 2)
        assertEqual("Left Boss", view.labels[1]:GetText())
        assertEqual("LEFT", view.labels[1].justifyH, "right of a pin on the left")
        assertEqual("RIGHT", view.labels[2].justifyH, "left of a pin near the right edge")
    end)

    it("does not write names on the small map", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 150, 84)
        ns.MapView.Show(view, block)
        assertEqual(0, shown(view.labels))
    end)

    it("moves a name that would sit on top of another", function()
        local ns, env = helpers.loadAddon(FILES)
        local crowded = {
            name = "Crowd", map = block.map,
            bosses = { { name = "One", pin = { 0.2, 0.5 }, loot = {} }, { name = "Two", pin = { 0.2, 0.51 }, loot = {} } },
        }
        local view = ns.MapView.Create(env.UIParent, 300, 300, { labels = true })
        ns.MapView.Show(view, crowded)
        local _, _, _, _, y1 = view.labels[1]:GetPoint(1)
        local _, _, _, _, y2 = view.labels[2]:GetPoint(1)
        assertTrue(math.abs(y1 - y2) >= 12, "one line apart at least")
    end)

    it("marks the entrance", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 300, 300, { labels = true })
        ns.MapView.Show(view, block)
        assertTrue(view.entrance:IsShown())
        assertEqual("Entrance", view.entranceLabel:GetText())
        ns.MapView.Show(view, { map = block.map, bosses = {} })
        assertFalse(view.entrance:IsShown(), "gone for an instance without one")
    end)

    it("names the boss when the cursor is on its pin", function()
        local ns, env = helpers.loadAddon(FILES)
        local view = ns.MapView.Create(env.UIParent, 300, 300, { labels = true, onPinClick = function() end })
        ns.MapView.Show(view, block)
        view.pins[2].scripts.OnEnter(view.pins[2])
        assertEqual("2. Right Boss", env.GameTooltip.text)
    end)
end)
