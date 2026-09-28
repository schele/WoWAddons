local helpers = require("helpers")

describe("/gmap debug", function()
    it("says what each step has, from the data to the pins", function()
        local ns, env = helpers.loggedIn()
        env.WorldMapFrame:Show()
        ns.MinimapPins.Refresh()
        helpers.command(env, "debug")
        local printed = helpers.printed(env)
        assertMatch("Data: 9 node types; spawns 7 Eastern Kingdoms, 1 Kalimdor", printed)
        assertMatch("Pins shown%. Skills: Herbalism 50, Mining 70%.", printed)
        assertMatch("Minimap pins: %d+", printed)
        assertMatch("World map: open=true map=1436 rect=continent 0", printed)
        assertMatch("First world map pin: ", printed)
    end)

    it("keeps going when the client refuses", function()
        local ns, env = helpers.loggedIn()
        env.UnitPosition = function() error("secret") end
        env.WorldMapFrame = nil
        helpers.command(env, "debug")
        assertMatch("World map: no WorldMapFrame", helpers.printed(env))
    end)
end)
