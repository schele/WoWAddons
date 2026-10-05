local helpers = require("helpers")

local NOW = 1790000000

local function ids(ns)
    local list = {}
    for _, pin in ipairs(ns.MinimapPins.Shown()) do list[#list + 1] = tostring(pin.id) end
    table.sort(list)
    return table.concat(list, ",")
end

local function refreshed(setup)
    local ns, env = helpers.loggedIn(setup)
    ns.MinimapPins.Refresh()
    return ns, env
end

describe("the minimap pins", function()
    it("show the rares in the minimap's range", function()
        local ns = refreshed()
        assertEqual("520", ids(ns), "Vultros is 361 yards off")
    end)

    it("sit where the spawn is, on whole pixels", function()
        local ns, env = refreshed()
        local pin = ns.MinimapPins.Shown()[1]
        local point, relativeTo, relativePoint, x, y = pin:GetPoint(1)
        assertEqual("CENTER", point)
        assertEqual(env.Minimap, relativeTo)
        assertEqual("CENTER", relativePoint)
        assertEqual(-2, x, "-6 yards right at 0.3 pixels a yard, to the pixel")
        assertEqual(-2, y)
        assertEqual(14, pin:GetWidth())
    end)

    it("follow the player to another spot", function()
        local ns = refreshed(function(env)
            env.__position = { -10540, 1330, 0, 0 }
        end)
        assertEqual("462,520", ids(ns))
    end)

    it("follow the player as they move, between choices", function()
        local ns, env = refreshed()
        local pin = ns.MinimapPins.Shown()[1]
        env.__position = { -10607.8, 1154.0, 0, 0 }
        ns.MinimapPins.Place()
        local _, _, _, x, y = pin:GetPoint(1)
        assertEqual(-1, y, "4 yards closer from the south")
    end)

    it("show nothing with their setting off", function()
        local ns = helpers.loggedIn()
        ns.settings.minimapPins = false
        ns.MinimapPins.Refresh()
        assertEqual("", ids(ns))
    end)

    it("leave out the rares only in the database when asked", function()
        local ns = helpers.loggedIn()
        ns.settings.showUnseen = false
        ns.MinimapPins.Refresh()
        assertEqual("", ids(ns))
    end)

    it("show nothing where the client will not say where the player is", function()
        local ns = refreshed(function(env)
            env.__playerMap = nil
            env.__position = nil
        end)
        assertEqual("", ids(ns))
    end)

    it("are chosen five times a second by their own frame", function()
        local ns, env = helpers.loggedIn()
        assertEqual("", ids(ns))
        ns.MinimapPins.ticker.scripts.OnUpdate(ns.MinimapPins.ticker, 0.25)
        assertEqual("520", ids(ns))
    end)

    it("include a sighting's own spot", function()
        local ns = refreshed(helpers.withSightings({
            [777] = helpers.sighting("New Rare", 33, NOW, { helpers.place(0.84, 0.6) }),
        }))
        assertEqual("520,777", ids(ns))
    end)
end)
