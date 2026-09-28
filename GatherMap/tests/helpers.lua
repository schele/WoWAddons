local stub = require("wow_stub")

local M = {}

-- In .toc order, with the test data where the generated Data files go.
-- Each task adds its own file here.
M.FILES = {
    "GatherMap.lua",
    "tests/fixture_data.lua",
    "Geometry.lua",
    "Spawns.lua",
    "Skills.lua",
    "Filter.lua",
    "Recorder.lua",
    "Pins.lua",
    "MinimapPins.lua",
    "WorldMap.lua",
    "Settings.lua",
    "Minimap.lua",
    "Debug.lua",
}

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable).
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}
    for _, path in ipairs(files or M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("GatherMap", ns)
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
    M.fire(env, "ADDON_LOADED", "GatherMap")
    M.fire(env, "PLAYER_LOGIN")
end

--- Loaded, `setup(env)` run on the stub if given, then logged in.
function M.loggedIn(setup)
    local ns, env = M.loadAddon()
    if setup then setup(env) end
    M.login(ns, env)
    return ns, env
end

function M.command(env, text)
    env.SlashCmdList.GATHERMAP(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

-- The player's saved gathers most specs start from, around the probe's spot
-- in Westfall (-10603.8, 1154.0), where the player stands.
M.A = "0:1731:-10603.8:1154.0"   -- Copper Vein under the player
M.B = "0:1731:-10000.0:1000.0"   -- Copper Vein 623 yards off, map 1436's corner
M.C = "0:3764:-10610.0:1160.0"   -- Tin Vein 8.6 yards off...
M.S = "0:1733:-10610.0:1160.0"   -- ...and Silver Vein at the same spot
M.D = "0:1617:-9000.0:500.0"     -- Silverleaf, off map 1436
M.E = "0:424242:-10700.0:1300.0" -- an ore the list does not know, 175 yards off
M.K = "1:1618:100.0:200.0"       -- Peacebloom on Kalimdor

--- A saved gather at `key`, gathered once, with `extra` fields merged in.
function M.point(key, extra)
    local continent, entry, x, y = key:match("^(%-?%d+):(%d+):(%-?[%d.]+):(%-?[%d.]+)$")
    local point = { continent = tonumber(continent), entry = tonumber(entry), x = tonumber(x), y = tonumber(y),
        count = 1, last = 1790000000 }
    for field, value in pairs(extra or {}) do point[field] = value end
    return point
end

--- The standard saved gathers, fresh each time.
function M.saved()
    local gathered = {}
    for _, key in ipairs({ M.A, M.B, M.C, M.S, M.D, M.K }) do
        gathered[key] = M.point(key)
    end
    gathered[M.E] = M.point(M.E, { kind = "ore", item = 9999, itemName = "Strange Ore" })
    return { gathered = gathered }
end

--- A setup for loggedIn: the standard saved gathers.
function M.withGathers(env)
    env.GatherMapDB = M.saved()
end

return M
