local helpers = require("helpers")

local A = helpers.A

--- A setup for loggedIn: the standard saved gathers, then `setup`, if given.
local function withGathers(setup)
    return function(env)
        helpers.withGathers(env)
        if setup then setup(env) end
    end
end

local function opened(setup)
    local ns, env = helpers.loggedIn(withGathers(setup))
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
        local ns, env = helpers.loggedIn(helpers.withGathers)
        assertEqual(1, #env.__providers)
    end)

    it("draws every place inside the open map", function()
        local ns = opened()
        assertEqual("1731,1731,3764,424242", shownEntries(ns), "Silverleaf lies off this map")
    end)

    it("puts a pin where its place is on the canvas", function()
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
        ns.settings.worldmap.hidden["Copper Vein"] = true
        ns.Refresh()
        assertEqual("3764,424242", shownEntries(ns))
        ns.settings.worldmap.kinds.ore = false
        ns.Refresh()
        assertEqual("", shownEntries(ns))
    end)

    it("shows nothing on a map it cannot place", function()
        local ns, env = opened()
        env.__changeMap(947)
        assertEqual("", shownEntries(ns))
    end)

    it("draws nothing while the map is closed", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        ns.Refresh()
        assertEqual("", shownEntries(ns))
    end)

    it("picks up a point gathered after the map was first opened", function()
        local ns, env = opened()
        env.__position = { -10300.0, 1500.0, 0, 0 }
        env.__lootSource = "GameObject-0-6782-0-79720-1731-00003A1A8E"
        helpers.fire(env, "LOOT_OPENED")
        assertEqual("1731,1731,1731,3764,424242", shownEntries(ns))
    end)

    it("draws no more than its limit of pins", function()
        local ns = opened(function(env) end)
        for index = 1, ns.WorldMap.MAX + 50 do
            ns.Spawns.AddPoint(0, 1731, -10500 - index * 0.2, 1500, { continent = 0, entry = 1731, kind = "ore", count = 1 })
        end
        ns.Refresh()
        assertEqual(ns.WorldMap.MAX, #ns.WorldMap.Shown())
    end)

    it("attaches when the world map loads after GatherMap", function()
        local ns, env = helpers.loadAddon()
        local map = env.WorldMapFrame
        env.WorldMapFrame = nil
        helpers.withGathers(env)
        helpers.login(ns, env)
        assertEqual(0, #env.__providers)
        env.WorldMapFrame = map
        helpers.fire(env, "ADDON_LOADED", "Blizzard_WorldMap")
        assertEqual(1, #env.__providers)
        map:Show()
        assertEqual("1731,1731,3764,424242", shownEntries(ns))
    end)

    it("draws its pins above the map's art, at the level the map gives points of interest", function()
        local ns, env = opened()
        local level = pinFor(ns, A):GetFrameLevel()
        assertEqual(2100, level)
        assertTrue(level > env.__pinLevels.PIN_FRAME_LEVEL_MAP_EXPLORATION, "above the explored-area overlay")
    end)

    it("draws its pins at a level of its own where the map will not give one", function()
        local ns = opened(function(env) env.WorldMapFrame.GetPinFrameLevelsManager = nil end)
        assertEqual(2200, pinFor(ns, A):GetFrameLevel())
        assertEqual(2200, ns.WorldMap.FALLBACK_LEVEL)
    end)

    it("keeps the minimap's pins just above the minimap", function()
        local ns, env = opened()
        ns.MinimapPins.Refresh()
        local pin = ns.MinimapPins.Shown()[1]
        assertEqual(env.Minimap:GetFrameLevel() + 5, pin:GetFrameLevel())
    end)

    it("loads on a client without the map framework", function()
        local ns, env = helpers.loggedIn(withGathers(function(env) env.MapCanvasDataProviderMixin = nil end))
        assertEqual(0, #env.__providers)
        ns.Refresh()
    end)
end)

describe("a pin", function()
    it("shows its node's loot as its icon, or its kind's", function()
        local ns = opened()
        assertEqual(1000 + 2770, pinFor(ns, A).icon:GetTexture())
        local key = ns.Spawns.AddPoint(0, 555, -10500.0, 1500.0, { continent = 0, entry = 555, kind = "herb", count = 1 }).key
        ns.Refresh()
        assertEqual(ns.Pins.KIND_ICONS.herb, pinFor(ns, key).icon:GetTexture(), "an unlisted herb whose loot is not known")
    end)

    it("names the node, its skill in its colour, and how often, with a gold edge", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        assertEqual("Copper Vein", env.GameTooltip.text)
        assertEqual("Mining 1", env.GameTooltip.lines[1].text)
        assertEqual(0.25, env.GameTooltip.lines[1].color[1], "green at 70")
        assertEqual("Gathered here 1 time", env.GameTooltip.lines[2].text)
        assertEqual("Shift-right-click: forget this place", env.GameTooltip.lines[3].text)
        assertEqual(3, #env.GameTooltip.lines)
        assertTrue(pin.edge:IsShown())
        assertEqual(1, pin:GetAlpha())
    end)

    it("forgets a spot on a Shift-right-click, and the pin and tooltip go", function()
        local ns, env = opened()
        local pin = pinFor(ns, helpers.A)
        pin.scripts.OnEnter(pin)
        env.__modifiers.shift = true
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertNil(ns.db.gathered[helpers.A])
        assertEqual("1731,3764,424242", shownEntries(ns))
        assertFalse(env.GameTooltip:IsShown())
    end)

    it("says how often and how to forget, and names an unlisted node after its loot", function()
        local ns, env = opened()
        local pin = pinFor(ns, helpers.E)
        pin.scripts.OnEnter(pin)
        assertEqual("Strange Ore", env.GameTooltip.text)
        assertEqual("Gathered here 1 time", env.GameTooltip.lines[1].text)
        assertEqual("Shift-right-click: forget this place", env.GameTooltip.lines[2].text)
        assertEqual(1000 + 9999, pin.icon:GetTexture())
        assertTrue(pin.edge:IsShown())
    end)

    it("ignores a left click, and lets the map have it", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnMouseUp(pin, "LeftButton")
        assertTrue(ns.db.gathered[A] ~= nil)
        assertEqual(1, pin.passThrough and #pin.passThrough)
        assertEqual("LeftButton", pin.passThrough[1])
        assertTrue(pin.mouseEnabled, "it still takes the mouse, for its tooltip")
    end)

    it("zooms the map out on a plain right-click, as the map would, and forgets nothing", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertEqual(1, env.__navigatedToParent)
        assertTrue(ns.db.gathered[A] ~= nil)
        env.__modifiers.shift = true
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertEqual(1, env.__navigatedToParent, "not with Shift held")
    end)

    it("does nothing on a plain right-click where the map cannot zoom out", function()
        local ns, env = opened()
        local pin = pinFor(ns, A)
        env.WorldMapFrame.NavigateToParentMap = nil
        pin.scripts.OnMouseUp(pin, "RightButton")
        env.WorldMapFrame.NavigateToParentMap = function() error("secret") end
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertTrue(ns.db.gathered[A] ~= nil)
    end)

    it("says how often the player gathered there", function()
        local ns, env = opened()
        ns.db.gathered[A].count = 3
        ns.Refresh()
        local pin = pinFor(ns, A)
        pin.scripts.OnEnter(pin)
        assertEqual("Gathered here 3 times", env.GameTooltip.lines[2].text)
    end)
end)

describe("a spot with several places", function()
    local C = helpers.C
    local S = helpers.S

    -- Mining 100, so the Silver Vein beside the Tin shows too.
    local function skilled(setup)
        return opened(function(env)
            env.__skills[3] = { "Mining", false, 100 }
            if setup then setup(env) end
        end)
    end

    local function pinsAtC(ns)
        local found = {}
        for _, pin in ipairs(ns.WorldMap.Shown()) do
            if pin.spawn.x == -10610.0 and pin.spawn.y == 1160.0 then found[#found + 1] = pin end
        end
        return found
    end

    it("is one pin, for the first member, carrying every member shown", function()
        local ns = skilled()
        local pins = pinsAtC(ns)
        assertEqual(1, #pins)
        assertEqual(S, pins[1].spawn.key, "saved gathers load in key order: the Silver, then the Tin")
        assertEqual(2, #pins[1].members)
        assertEqual(C, pins[1].members[2].key)
        assertEqual(4, #ns.WorldMap.Shown(), "pins, not places")
    end)

    it("names every member, each skill, and one line for the spot", function()
        local ns, env = skilled()
        local pin = pinsAtC(ns)[1]
        pin.scripts.OnEnter(pin)
        assertEqual("Silver Vein or Tin Vein", env.GameTooltip.text)
        assertEqual("Mining 75", env.GameTooltip.lines[1].text)
        assertEqual("Mining 65", env.GameTooltip.lines[2].text)
        assertEqual("Gathered here 2 times", env.GameTooltip.lines[3].text)
        assertEqual("Shift-right-click: forget this place", env.GameTooltip.lines[4].text)
        assertEqual(4, #env.GameTooltip.lines)
    end)

    it("names three as A, B or C, with no skill line for a member that has none", function()
        local ns, env = skilled()
        ns.Spawns.AddPoint(0, 424243, -10610.0, 1160.0,
            { continent = 0, entry = 424243, kind = "ore", count = 1, item = 9998, itemName = "Odd Ore" })
        ns.Refresh()
        local pin = pinsAtC(ns)[1]
        pin.scripts.OnEnter(pin)
        assertEqual("Silver Vein, Tin Vein or Odd Ore", env.GameTooltip.text)
        assertEqual("Mining 65", env.GameTooltip.lines[2].text)
        assertEqual("Gathered here 3 times", env.GameTooltip.lines[3].text)
        assertEqual(4, #env.GameTooltip.lines)
    end)

    it("leaves a Silver pin there when the Tin is hidden", function()
        local ns = skilled()
        ns.settings.worldmap.hidden["Tin Vein"] = true
        ns.Refresh()
        local pins = pinsAtC(ns)
        assertEqual(1, #pins)
        assertEqual(S, pins[1].spawn.key)
        assertEqual(1, #pins[1].members)
        assertEqual(1000 + 2775, pins[1].icon:GetTexture())
    end)

    it("leaves a Tin pin there when the Silver is beyond the skill", function()
        local ns = opened()
        local pins = pinsAtC(ns)
        assertEqual(1, #pins)
        assertEqual(C, pins[1].spawn.key)
        assertEqual(1, #pins[1].members)
        assertEqual(1000 + 2771, pins[1].icon:GetTexture())
    end)

    it("is not drawn when every member is hidden", function()
        local ns = skilled()
        ns.settings.worldmap.hidden["Tin Vein"] = true
        ns.settings.worldmap.hidden["Silver Vein"] = true
        ns.Refresh()
        assertEqual(0, #pinsAtC(ns))
    end)

    it("forgets every member shown on a Shift-right-click", function()
        local ns, env = skilled()
        env.__modifiers.shift = true
        local pin = pinsAtC(ns)[1]
        pin.scripts.OnEnter(pin)
        pin.scripts.OnMouseUp(pin, "RightButton")
        assertNil(ns.db.gathered[C])
        assertNil(ns.db.gathered[S])
        assertEqual(0, #pinsAtC(ns))
        assertFalse(env.GameTooltip:IsShown())
    end)

    it("counts a new gather of any member in the spot's total", function()
        local ns, env = skilled()
        env.__lootSource = "GameObject-0-6782-0-79720-1733-00003A1A8E"
        helpers.fire(env, "LOOT_OPENED")
        assertEqual(2, ns.db.gathered[S].count, "the Silver 8.6 yards off, not a new place")
        local pin = pinsAtC(ns)[1]
        pin.scripts.OnEnter(pin)
        assertEqual("Gathered here 3 times", env.GameTooltip.lines[3].text)
    end)

    it("adds up the counts of every member gathered", function()
        local ns, env = skilled(function(env)
            env.GatherMapDB = { gathered = {
                [C] = { continent = 0, entry = 3764, x = -10610.0, y = 1160.0, count = 2 },
                [S] = { continent = 0, entry = 1733, x = -10610.0, y = 1160.0, count = 3 },
            } }
        end)
        local pin = pinsAtC(ns)[1]
        pin.scripts.OnEnter(pin)
        assertEqual("Gathered here 5 times", env.GameTooltip.lines[3].text)
    end)
end)

describe("/gmap where", function()
    it("prints the game's place for the player beside GatherMap's", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        helpers.command(env, "where")
        assertMatch("Map 1436%. Game: 0%.846, 0%.604%. GatherMap: 0%.846, 0%.604%.", helpers.printed(env))
    end)

    it("says so where the game will not tell", function()
        local ns, env = helpers.loggedIn(withGathers(function(env) env.__playerMap = 947 end))
        helpers.command(env, "where")
        assertMatch("will not say", helpers.printed(env))
    end)
end)
