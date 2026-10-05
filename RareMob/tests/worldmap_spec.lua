local helpers = require("helpers")

local NOW = 1790000000

local function opened(setup)
    local ns, env = helpers.loggedIn(setup)
    env.WorldMapFrame:Show()
    return ns, env
end

local function shownIds(ns)
    local ids = {}
    for _, pin in ipairs(ns.WorldMap.Shown()) do ids[#ids + 1] = pin.id end
    table.sort(ids)
    local out = {}
    for index, id in ipairs(ids) do out[index] = tostring(id) end
    return table.concat(out, ",")
end

local function pinFor(ns, id)
    for _, pin in ipairs(ns.WorldMap.Shown()) do
        if pin.id == id then return pin end
    end
end

describe("the world map", function()
    it("joins the map as a data provider", function()
        local ns, env = helpers.loggedIn()
        assertEqual(1, #env.__providers)
    end)

    it("pins every rare spawned inside the open map", function()
        local ns = opened()
        assertEqual("1,462,520", shownIds(ns), "Morgaine lies off this map, the Kalimdor rare on another continent")
    end)

    it("puts a pin where its spawn is on the canvas", function()
        local ns, env = opened()
        local point, relativeTo, relativePoint, x, y = pinFor(ns, 462):GetPoint(1)
        assertEqual("CENTER", point)
        assertEqual(env.WorldMapFrame:GetCanvas(), relativeTo)
        assertEqual("TOPLEFT", relativePoint)
        assertNear(500, x)
        assertNear(-350, y)
        assertEqual(14, pinFor(ns, 462):GetWidth())
    end)

    it("keeps pins the same size on screen as the map zooms", function()
        local ns, env = opened()
        env.__zoomMap(2)
        local pin = pinFor(ns, 462)
        assertNear(0.5, pin:GetScale())
        local _, _, _, x = pin:GetPoint(1)
        assertNear(1000, x, 0.01, "the offset is in the pin's own, halved, units")
    end)

    it("draws its pins above the map's art", function()
        local ns, env = opened()
        assertEqual(2100, pinFor(ns, 462):GetFrameLevel())
    end)

    it("draws its pins at a level of its own where the map will not give one", function()
        local ns = opened(function(env) env.WorldMapFrame.GetPinFrameLevelsManager = nil end)
        assertEqual(2200, pinFor(ns, 462):GetFrameLevel())
    end)

    it("shows nothing on a map it cannot place", function()
        local ns, env = opened()
        env.__changeMap(947)
        assertEqual("", shownIds(ns))
    end)

    it("draws nothing while the map is closed", function()
        local ns = helpers.loggedIn()
        ns.Refresh()
        assertEqual("", shownIds(ns))
    end)

    it("draws nothing with its setting off", function()
        local ns = opened()
        ns.settings.worldPins = false
        ns.Refresh()
        assertEqual("", shownIds(ns))
    end)

    it("leaves out the rares only in the database when asked", function()
        local ns = opened(helpers.withSightings({ [462] = helpers.sighting("Vultros", 26, NOW) }))
        ns.settings.showUnseen = false
        ns.Refresh()
        assertEqual("462", shownIds(ns))
    end)

    it("gives a sighting with no database spawn a pin at its spot", function()
        local ns = opened(helpers.withSightings({
            [777] = helpers.sighting("New Rare", 33, NOW, { helpers.place(0.2, 0.3) }),
        }))
        local pin = pinFor(ns, 777)
        local _, _, _, x, y = pin:GetPoint(1)
        assertNear(200, x)
        assertNear(-210, y)
    end)

    it("draws a rare spotted now as soon as it is seen", function()
        local ns, env = opened()
        env.__units.target = env.__creature(777, "New Rare", 33, "rare")
        helpers.fire(env, "PLAYER_TARGET_CHANGED")
        assertTrue(pinFor(ns, 777) ~= nil)
        assertTrue(pinFor(ns, 777).pulsing)
    end)

    it("attaches when the world map loads after RareMob", function()
        local ns, env = helpers.loadAddon()
        local map = env.WorldMapFrame
        env.WorldMapFrame = nil
        helpers.login(ns, env)
        assertEqual(0, #env.__providers)
        env.WorldMapFrame = map
        helpers.fire(env, "ADDON_LOADED", "Blizzard_WorldMap")
        assertEqual(1, #env.__providers)
        map:Show()
        assertEqual("1,462,520", shownIds(ns))
    end)

    it("never raises into the map's own code", function()
        local ns, env = helpers.loggedIn()
        env.WorldMapFrame:GetCanvas().GetWidth = function() error("secret") end
        env.WorldMapFrame:Show()
        env.__changeMap(1436)
        env.__zoomMap(2)
        env.__providers[1]:RefreshAllData()
    end)

    it("loads on a client without the map framework", function()
        local ns, env = helpers.loggedIn(function(env) env.MapCanvasDataProviderMixin = nil end)
        assertEqual(0, #env.__providers)
        ns.Refresh()
    end)
end)

describe("showing a rare on the map", function()
    it("opens the map on the zone and makes that rare's pins glow", function()
        local ns, env = helpers.loggedIn()
        env.__worldMapID = 947
        ns.WorldMap.ShowRare(462, 1436)
        assertTrue(env.WorldMapFrame:IsShown())
        assertEqual(1436, env.__worldMapID)
        assertTrue(pinFor(ns, 462).glow:IsShown())
        assertFalse(pinFor(ns, 520).glow:IsShown())
    end)

    it("lets the glow go when the map closes", function()
        local ns, env = helpers.loggedIn()
        ns.WorldMap.ShowRare(462, 1436)
        env.WorldMapFrame:Hide()
        assertNil(ns.Pins.highlight)
    end)

    it("does nothing harmful without a world map", function()
        local ns, env = helpers.loggedIn()
        env.WorldMapFrame = nil
        ns.WorldMap.ShowRare(462, 1436)
    end)
end)
