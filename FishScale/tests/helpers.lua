local stub = require("wow_stub")

local M = {}

M.FILES = {
    "FishScale.lua",
    "Fishing.lua",
}

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable).
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}

    for _, path in ipairs(files or M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("FishScale", ns)
    end

    return ns, env
end

--- Fire an event on every frame registered for it.
function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do
        frames[index] = frame
    end

    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then
            frame:Fire(event, ...)
        end
    end
end

--- Run the real login sequence.
function M.login(ns, env)
    M.fire(env, "ADDON_LOADED", "FishScale")
    M.fire(env, "PLAYER_LOGIN")
end

function M.command(env, text)
    env.SlashCmdList.FISHSCALE(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
