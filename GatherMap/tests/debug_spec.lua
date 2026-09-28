local helpers = require("helpers")

describe("/gmap debug", function()
    it("says what each step has, from the data to the pins", function()
        local ns, env = helpers.loggedIn(helpers.withGathers)
        env.WorldMapFrame:Show()
        ns.MinimapPins.Refresh()
        helpers.command(env, "debug")
        local printed = helpers.printed(env)
        assertMatch("Data: 7 node types listed; 7 places gathered: 6 Eastern Kingdoms, 1 Kalimdor", printed)
        assertMatch("Pins shown%. Skills: Herbalism 50, Mining 70%.", printed)
        assertMatch("Minimap pins: %d+", printed)
        assertMatch("World map: open=true map=1436 rect=continent 0", printed)
        assertMatch("First world map pin: ", printed)
    end)

    it("says a skill it cannot find is unknown", function()
        local ns, env = helpers.loggedIn(function(env)
            env.__skills = { { "Professions", true }, { "Mining", false, 70 } }
        end)
        helpers.command(env, "debug")
        assertMatch("Skills: Herbalism unknown, Mining 70%.", helpers.printed(env))
    end)

    it("keeps going when the client refuses", function()
        local ns, env = helpers.loggedIn()
        env.UnitPosition = function() error("secret") end
        env.WorldMapFrame = nil
        helpers.command(env, "debug")
        assertMatch("World map: no WorldMapFrame", helpers.printed(env))
    end)
end)
