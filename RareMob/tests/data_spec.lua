local helpers = require("helpers")

-- The real generated data, in place of the test fixture.
local function withRealData()
    local files = {}
    for _, path in ipairs(helpers.FILES) do
        if path == "tests/fixture_data.lua" then
            for _, data in ipairs({ "Data/Rares.lua", "Data/SpawnsEasternKingdoms.lua", "Data/SpawnsKalimdor.lua", "Data/Recorded.lua" }) do
                files[#files + 1] = data
            end
        else
            files[#files + 1] = path
        end
    end
    return helpers.loadAddon(files)
end

describe("the generated data", function()
    it("loads, with a few hundred rares", function()
        local ns = withRealData()
        local count = 0
        for _ in pairs(ns.rares) do count = count + 1 end
        assertTrue(count > 300 and count < 600, "rares: " .. count)
    end)

    it("knows Vultros, a level 26 rare of the Eastern Kingdoms", function()
        local ns = withRealData()
        local vultros = ns.rares[462]
        assertEqual("Vultros", vultros.name)
        assertEqual(26, vultros.minLevel)
        assertFalse(vultros.elite)
        local spawned = false
        for _, spawn in ipairs(ns.spawns[0]) do
            if spawn.id == 462 then spawned = true end
        end
        assertTrue(spawned, "in the Eastern Kingdoms")
    end)

    it("has spawns on both continents, each with a known rare", function()
        local ns = withRealData()
        for _, continent in ipairs({ 0, 1 }) do
            assertTrue(#ns.spawns[continent] > 100, "continent " .. continent)
            for _, spawn in ipairs(ns.spawns[continent]) do
                assertTrue(ns.rares[spawn.id] ~= nil, "spawn of unknown rare " .. spawn.id)
                assertEqual("number", type(spawn.x))
                assertEqual("number", type(spawn.y))
            end
        end
    end)

    it("marks the rare elites", function()
        local ns = withRealData()
        local elites = 0
        for _, rare in pairs(ns.rares) do
            if rare.elite then elites = elites + 1 end
        end
        assertTrue(elites > 50, "elites: " .. elites)
    end)
end)
