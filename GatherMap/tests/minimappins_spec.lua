local helpers = require("helpers")

local A = helpers.A
local C = helpers.C

local function entries(ns)
    local list = {}
    for _, pin in ipairs(ns.MinimapPins.Shown()) do list[#list + 1] = pin.spawn.entry end
    table.sort(list)
    return table.concat(list, ",")
end

local function pinFor(ns, key)
    for _, pin in ipairs(ns.MinimapPins.Shown()) do
        if pin.spawn.key == key then return pin end
    end
end

--- Logged in with the standard saved gathers and `setup`, then drawn.
local function refreshed(setup)
    local ns, env = helpers.loggedIn(function(env)
        helpers.withGathers(env)
        if setup then setup(env) end
    end)
    ns.MinimapPins.Refresh()
    return ns, env
end

describe("the minimap pins", function()
    it("show what is in the minimap's range", function()
        local ns = refreshed()
        assertEqual("1731,3764,424242", entries(ns), "the far copper vein is 623 yards off")
    end)

    it("sit where their place is, north up and west left", function()
        local ns, env = refreshed()
        local point, relativeTo, relativePoint, x, y = pinFor(ns, C):GetPoint(1)
        assertEqual("CENTER", point)
        assertEqual(env.Minimap, relativeTo)
        assertEqual("CENTER", relativePoint)
        local scale = 140 / (466 + 2 / 3)
        assertNear(-6 * scale, x)
        assertNear(-6.2 * scale, y)
        assertEqual(10, pinFor(ns, C):GetWidth())
    end)

    it("narrow with the zoom", function()
        local ns = refreshed(function(env) env.__zoom = 5 end)
        assertEqual("1731,3764", entries(ns), "the strange ore is 175 yards off")
    end)

    it("narrow indoors", function()
        local ns = refreshed(function(env) env.__indoors = true end)
        assertEqual("1731,3764", entries(ns))
    end)

    it("turn with a turning minimap", function()
        local ns = refreshed(function(env)
            env.__cvars.rotateMinimap = "1"
            env.__facing = math.pi / 2
        end)
        local _, _, _, x, y = pinFor(ns, C):GetPoint(1)
        local scale = 140 / (466 + 2 / 3)
        assertNear(-6.2 * scale, x)
        assertNear(6 * scale, y)
    end)

    it("follow the minimap filters", function()
        local ns = refreshed()
        ns.settings.minimap.hidden["Copper Vein"] = true
        ns.MinimapPins.Refresh()
        assertEqual("3764,424242", entries(ns))
        ns.settings.minimap.kinds.ore = false
        ns.MinimapPins.Refresh()
        assertEqual("", entries(ns))
    end)

    it("hide while pins are off", function()
        local ns = refreshed()
        ns.SetEnabled(false)
        assertEqual("", entries(ns))
    end)

    it("hide when the client will not say where the player is", function()
        local ns, env = refreshed()
        env.__position = nil
        ns.MinimapPins.Refresh()
        assertEqual("", entries(ns))
        env.UnitPosition = function() error("secret") end
        ns.MinimapPins.Refresh()
        assertEqual("", entries(ns))
    end)

    it("are chosen afresh five times a second, not every frame", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        local tick = ns.MinimapPins.ticker.scripts.OnUpdate
        tick(ns.MinimapPins.ticker, 0.1)
        assertEqual("", entries(ns), "not yet")
        tick(ns.MinimapPins.ticker, 0.1)
        assertEqual("1731,3764,424242", entries(ns))
    end)

    it("follow the player every frame, between those choices", function()
        local ns, env = refreshed()
        local tick = ns.MinimapPins.ticker.scripts.OnUpdate
        local scale = 140 / (466 + 2 / 3)
        -- Ten yards north: the tin, 6.2 yards south of the player, is now
        -- 16.2 yards south, a frame later, long before the next choice.
        env.__position = { -10593.8, 1154.0, 0, 0 }
        tick(ns.MinimapPins.ticker, 0.016)
        local _, _, _, x, y = pinFor(ns, C):GetPoint(1)
        assertNear(-6 * scale, x)
        assertNear(-16.2 * scale, y)
        assertEqual(1, #pinFor(ns, C).points, "moved, not stacked with a second point")
    end)

    it("follow the map position, which moves every frame, not UnitPosition, which steps", function()
        local ns, env = refreshed()
        local tick = ns.MinimapPins.ticker.scripts.OnUpdate
        local scale = 140 / (466 + 2 / 3)
        -- The map position has the player 10 yards north already; UnitPosition
        -- has not caught up (probed 2026-09-29: it changes on 1 frame in 3-4).
        local mapNorth = env.CreateVector2D((1154.0 - 2000) / (1000 - 2000), (-10593.8 + 10000) / (-11000 + 10000))
        env.C_Map.GetPlayerMapPosition = function() return mapNorth end
        tick(ns.MinimapPins.ticker, 0.016)
        local _, _, _, x, y = pinFor(ns, C):GetPoint(1)
        assertNear(-6 * scale, x)
        assertNear(-16.2 * scale, y)
    end)

    it("fall back to UnitPosition where the game gives no map position", function()
        local ns, env = refreshed()
        env.C_Map.GetPlayerMapPosition = function() return nil end
        env.__position = { -10593.8, 1154.0, 0, 0 }
        ns.MinimapPins.ticker.scripts.OnUpdate(ns.MinimapPins.ticker, 0.016)
        local _, _, _, _, y = pinFor(ns, C):GetPoint(1)
        assertNear(-16.2 * 140 / (466 + 2 / 3), y)
    end)

    it("hide a pin that has slipped past the rim between choices", function()
        local ns, env = refreshed()
        local tick = ns.MinimapPins.ticker.scripts.OnUpdate
        -- 60 yards east: the unlisted ore 175 yards off is now past the rim.
        env.__position = { -10603.8, 1094.0, 0, 0 }
        tick(ns.MinimapPins.ticker, 0.016)
        assertFalse(pinFor(ns, helpers.E):IsShown())
        assertTrue(pinFor(ns, C):IsShown())
    end)

    it("draw one pin where several places share a spot", function()
        local ns = refreshed(function(env) env.__skills[3] = { "Mining", false, 100 } end)
        assertEqual("1731,1733,424242", entries(ns), "the Tin Vein shares the Silver's pin")
        local pin = pinFor(ns, helpers.S)
        assertEqual(2, #pin.members)
        assertEqual(C, pin.members[2].key)
    end)

    it("draw the Silver Vein alone where the Tin is hidden", function()
        local ns = refreshed(function(env) env.__skills[3] = { "Mining", false, 100 } end)
        ns.settings.minimap.hidden["Tin Vein"] = true
        ns.MinimapPins.Refresh()
        assertEqual("1731,1733,424242", entries(ns))
        assertEqual(1, #pinFor(ns, helpers.S).members)
    end)

    it("forget on a Shift-right-click, and ignore a plain one", function()
        local ns, env = refreshed()
        local pin = pinFor(ns, A)
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertTrue(ns.db.gathered[A] ~= nil)
        assertEqual(0, env.__navigatedToParent, "the world map is not the minimap's")
        env.__modifiers.shift = true
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertNil(ns.db.gathered[A])
        assertEqual("3764,424242", entries(ns))
        assertEqual("LeftButton", pin.passThrough[1])
    end)

    it("stop at their limit", function()
        local ns = helpers.loggedIn(helpers.withGathers)
        for index = 1, ns.MinimapPins.MAX + 20 do
            ns.Spawns.AddPoint(0, 1731, -10603.8 + index * 0.5, 1154.0, { continent = 0, entry = 1731, kind = "ore", count = 1 })
        end
        ns.MinimapPins.Refresh()
        assertEqual(ns.MinimapPins.MAX, #ns.MinimapPins.Shown())
    end)
end)
