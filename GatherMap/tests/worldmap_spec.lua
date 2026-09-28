local helpers = require("helpers")

local A = "0:1731:-10603.8:1154.0"

local function opened(setup)
    local ns, env = helpers.loggedIn(setup)
    env.WorldMapFrame:Show()
    return ns, env
end

local function shownEntries(ns)
    local entries = {}
    for _, pin in ipairs(ns.WorldMap.Shown()) do
        entries[#entries + 1] = pin.spawn.entry
    end
    table.sort(entries)
    return table.concat(entries, ",")
end

local function pinFor(ns, key)
    for _, pin in ipairs(ns.WorldMap.Shown()) do
        if pin.spawn.key == key then return pin end
    end
end

describe("the world map", function()
    it("joins the map as a data provider", function()
        local ns, env = helpers.loggedIn()
        assertEqual(1, #env.__providers)
    end)

    it("draws every spawn inside the open map", function()
        local ns = opened()
        assertEqual("1731,1731,2843,3764,180582", shownEntries(ns), "Silverleaf lies off this map")
    end)

    it("puts a pin where its spawn is on the canvas", function()
        local ns, env = opened()
        local point, relativeTo, relativePoint, x, y = pinFor(ns, A):GetPoint(1)
        assertEqual("CENTER", point)
        assertEqual(env.WorldMapFrame:GetCanvas(), relativeTo)
        assertEqual("TOPLEFT", relativePoint)
        assertNear(846, x, 0.01)
        assertNear(-422.66, y, 0.01)
        assertEqual(12, pinFor(ns, A):GetWidth())
    end)

    it("keeps pins the same size on screen as the map zooms", function()
        local ns, env = opened()
        env.__zoomMap(2)
        local pin = pinFor(ns, A)
        assertNear(0.5, pin:GetScale())
        local _, _, _, x = pin:GetPoint(1)
        assertNear(1692, x, 0.01, "the offset is in the pin's own, halved, units")
    end)

    it("follows the filters", function()
        local ns = opened()
        ns.settings.worldmap.kinds.ore = false
        ns.Refresh()
        assertEqual("2843,180582", shownEntries(ns))
    end)

    it("shows nothing on a map it cannot place", function()
        local ns, env = opened()
        env.__changeMap(947)
        assertEqual("", shownEntries(ns))
    end)

    it("draws nothing while the map is closed", function()
        local ns, env = helpers.loggedIn()
        ns.Refresh()
        assertEqual("", shownEntries(ns))
    end)

    it("picks up a point gathered after the map was first opened", function()
        local ns, env = opened()
        env.__position = { -10300.0, 1500.0, 0, 0 }
        env.__lootSource = "GameObject-0-6782-0-79720-1731-00003A1A8E"
        helpers.fire(env, "LOOT_OPENED")
        assertEqual("1731,1731,1731,2843,3764,180582", shownEntries(ns))
    end)

    it("draws no more than its limit of pins", function()
        local ns = opened(function(env) end)
        for index = 1, ns.WorldMap.MAX + 50 do
            ns.Spawns.AddPoint(0, 1731, -10500 - index * 0.2, 1500)
        end
        ns.Refresh()
        assertEqual(ns.WorldMap.MAX, #ns.WorldMap.Shown())
    end)

    it("attaches when the world map loads after GatherMap", function()
        local ns, env = helpers.loadAddon()
        local map = env.WorldMapFrame
        env.WorldMapFrame = nil
        helpers.login(ns, env)
        assertEqual(0, #env.__providers)
        env.WorldMapFrame = map
        helpers.fire(env, "ADDON_LOADED", "Blizzard_WorldMap")
        assertEqual(1, #env.__providers)
        map:Show()
        assertEqual("1731,1731,2843,3764,180582", shownEntries(ns))
    end)

    it("loads on a client without the map framework", function()
        local ns, env = helpers.loggedIn(function(env) env.MapCanvasDataProviderMixin = nil end)
        assertEqual(0, #env.__providers)
        ns.Refresh()
    end)
end)

describe("a pin", function()
    it("shows its node's loot as its icon, or its kind's", function()
        local ns = opened()
        assertEqual(1000 + 2770, pinFor(ns, A).icon:GetTexture())
        assertEqual(ns.Pins.KIND_ICONS.chest, pinFor(ns, "0:2843:-10700.0:1300.0").icon:GetTexture())
    end)

    it("names the node, its skill in its colour, and that only the database has it", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        assertEqual("Copper Vein", env.GameTooltip.text)
        assertEqual("Mining 1", env.GameTooltip.lines[1].text)
        assertEqual(0.25, env.GameTooltip.lines[1].color[1], "green at 70")
        assertEqual("From the classic database, not seen in WoW Forever yet", env.GameTooltip.lines[2].text)
        assertEqual("Right-click: not here", env.GameTooltip.lines[3].text)
        assertFalse(pin.edge:IsShown())
        assertEqual(ns.Pins.DIM, pin:GetAlpha(), "a database guess is drawn dimmed")
    end)

    it("draws a spawn confirmed in the release at full strength", function()
        local ns, env = opened()
        local pin = pinFor(ns, "0:3764:-10610.0:1160.0")
        assertEqual(1, pin:GetAlpha())
        assertFalse(pin.edge:IsShown(), "the gold edge is for the player's own gathers")
        pin.scripts.OnEnter(pin)
        assertEqual("Confirmed in WoW Forever", env.GameTooltip.lines[2].text)
    end)

    it("marks its spawn not here on a right-click, and the pin goes", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertEqual(env.__time, ns.db.missing[A])
        assertEqual("1731,2843,3764,180582", shownEntries(ns))
        assertFalse(env.GameTooltip:IsShown(), "no tooltip left for a pin that has gone")
    end)

    it("shows marked spawns when asked, and a right-click takes the mark off", function()
        local ns, env = opened()
        ns.db.missing[A] = 1
        ns.settings.worldmap.showMissing = true
        ns.Refresh()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        assertEqual("Marked not here. Right-click to undo.", env.GameTooltip.lines[3].text)
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertNil(ns.db.missing[A])
        assertEqual("Right-click: not here", env.GameTooltip.lines[3].text, "the tooltip keeps up")
    end)

    it("ignores a left click", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnMouseUp(pin, "LeftButton")
        assertNil(ns.db.missing[A])
    end)

    it("says how often the player gathered there, with a gold edge", function()
        local ns, env = opened()
        ns.db.gathered[A] = { continent = 0, entry = 1731, x = -10603.8, y = 1154.0, count = 3 }
        ns.Refresh()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        assertEqual("Gathered here 3 times", env.GameTooltip.lines[2].text)
        assertTrue(pin.edge:IsShown())
    end)
end)

describe("/gmap where", function()
    it("prints the game's place for the player beside GatherMap's", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "where")
        assertMatch("Map 1436%. Game: 0%.846, 0%.604%. GatherMap: 0%.846, 0%.604%.", helpers.printed(env))
    end)

    it("says so where the game will not tell", function()
        local ns, env = helpers.loggedIn(function(env) env.__playerMap = 947 end)
        helpers.command(env, "where")
        assertMatch("will not say", helpers.printed(env))
    end)
end)
