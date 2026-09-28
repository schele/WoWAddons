local helpers = require("helpers")

local C = "0:3764:-10610.0:1160.0"

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

local function refreshed(setup)
    local ns, env = helpers.loggedIn(setup)
    ns.MinimapPins.Refresh()
    return ns, env
end

describe("the minimap pins", function()
    it("show what is in the minimap's range", function()
        local ns = refreshed()
        assertEqual("1731,2843,3764,180582", entries(ns), "the far copper vein is 623 yards off")
    end)

    it("sit where their spawn is, north up and west left", function()
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
        assertEqual("1731,3764,180582", entries(ns), "the chest is 175 yards off")
    end)

    it("narrow indoors", function()
        local ns = refreshed(function(env) env.__indoors = true end)
        assertEqual("1731,3764,180582", entries(ns))
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
        local ns = helpers.loggedIn()
        ns.settings.minimap.kinds.ore = false
        ns.MinimapPins.Refresh()
        assertEqual("2843,180582", entries(ns))
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

    it("move five times a second, not every frame", function()
        local ns, env = helpers.loggedIn()
        local tick = ns.MinimapPins.ticker.scripts.OnUpdate
        tick(ns.MinimapPins.ticker, 0.1)
        assertEqual("", entries(ns), "not yet")
        tick(ns.MinimapPins.ticker, 0.1)
        assertEqual("1731,2843,3764,180582", entries(ns))
    end)

    it("draw one pin where several spawns share a spot", function()
        local ns = refreshed(function(env) env.__skills[3] = { "Mining", false, 100 } end)
        assertEqual("1731,2843,3764,180582", entries(ns), "the Silver Vein shares the Tin's pin")
        local pin = pinFor(ns, C)
        assertEqual(2, #pin.members)
        assertEqual("0:1733:-10610.0:1160.0", pin.members[2].key)
    end)

    it("draw the Silver Vein alone where the Tin is hidden", function()
        local ns = refreshed(function(env) env.__skills[3] = { "Mining", false, 100 } end)
        ns.settings.minimap.hidden["Tin Vein"] = true
        ns.MinimapPins.Refresh()
        assertEqual("1731,1733,2843,180582", entries(ns))
    end)

    it("mark not here on a Shift-right-click, and ignore a plain one", function()
        local ns, env = refreshed()
        local pin = pinFor(ns, "0:1731:-10603.8:1154.0")
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertNil(ns.db.missing["0:1731:-10603.8:1154.0"])
        assertEqual(0, env.__navigatedToParent, "the world map is not the minimap's")
        env.__modifiers.shift = true
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertEqual(env.__time, ns.db.missing["0:1731:-10603.8:1154.0"])
        assertEqual("LeftButton", pin.passThrough[1])
    end)

    it("stop at their limit", function()
        local ns = helpers.loggedIn()
        for index = 1, ns.MinimapPins.MAX + 20 do
            ns.Spawns.AddPoint(0, 1731, -10603.8 + index * 0.5, 1154.0)
        end
        ns.MinimapPins.Refresh()
        assertEqual(ns.MinimapPins.MAX, #ns.MinimapPins.Shown())
    end)
end)
