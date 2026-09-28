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

return M
