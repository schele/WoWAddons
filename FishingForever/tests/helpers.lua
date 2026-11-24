local stub = require("wow_stub")

local M = {}

M.FILES = {
    "FishingForever.lua",
    "Fishing.lua",
    "Skill.lua",
    "Water.lua",
    "Stats.lua",
    "SkillBar.lua",
    "StatsPanel.lua",
    "Settings.lua",
    "Minimap.lua",
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
-- in .toc order, each chunk receiving (addonName, privateTable). Files not
-- written yet are skipped.
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}

    for _, path in ipairs(files or M.FILES) do
        if exists(path) then
            local chunk = assert(loadfile(path, "t", env))
            chunk("FishingForever", ns)
        end
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
    M.fire(env, "ADDON_LOADED", "FishingForever")
    M.fire(env, "PLAYER_LOGIN")
end

function M.command(env, text)
    env.SlashCmdList.FISHINGFOREVER(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
