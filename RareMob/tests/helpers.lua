local stub = require("wow_stub")

local M = {}

-- In .toc order, with the test data where the generated Data files go.
-- Files not written yet are skipped, so early specs run before later files.
M.FILES = {
    "RareMob.lua",
    "tests/fixture_data.lua",
    "Geometry.lua",
    "Rares.lua",
    "Spotter.lua",
    "Alert.lua",
    "Pins.lua",
    "WorldMap.lua",
    "MinimapPins.lua",
    "List.lua",
    "Minimap.lua",
    "Settings.lua",
}

local function exists(path)
    local file = io.open(path)
    if file then
        file:close()
        return true
    end
    return false
end

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable).
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}
    for _, path in ipairs(files or M.FILES) do
        if exists(path) then
            local chunk = assert(loadfile(path, "t", env))
            chunk("RareMob", ns)
        end
    end
    return ns, env
end

--- Fire an event on every frame registered for it.
function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do frames[index] = frame end
    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then frame:Fire(event, ...) end
    end
end

function M.login(ns, env)
    M.fire(env, "ADDON_LOADED", "RareMob")
    M.fire(env, "PLAYER_LOGIN")
end

--- Loaded, `setup(env, ns)` run if given, then logged in.
function M.loggedIn(setup)
    local ns, env = M.loadAddon()
    if setup then setup(env, ns) end
    M.login(ns, env)
    return ns, env
end

function M.command(env, text)
    env.SlashCmdList.RAREMOB(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

-- The player's recorder id in most specs.
M.ME = "me000001"

--- A saved sighting: `id`'s name and level, seen `count` times, last at
-- `last`, at the given places ({ map, x, y, time }).
function M.sighting(name, level, last, places, extra)
    local sighting = { name = name, level = level, elite = false, count = 1, last = last, places = places or {} }
    for key, value in pairs(extra or {}) do sighting[key] = value end
    return sighting
end

--- A setup for loggedIn: the player's own saved sightings.
function M.withSightings(sightings)
    return function(env)
        env.RareMobDB = { recorder = M.ME, sightings = sightings }
    end
end

-- A spot on the test Westfall (1436), as a map position.
function M.place(x, y, time)
    return { map = 1436, x = x, y = y, time = time or 1790000000 }
end

return M
