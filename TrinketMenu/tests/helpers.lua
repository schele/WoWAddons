local stub = require("wow_stub")

local M = {}

M.FILES = {
    "TrinketMenu.lua",
    "Items.lua",
    "Bar.lua",
    "Settings.lua",
}

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable).
-- Pass a shorter list while the later files do not exist yet.
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}

    for _, path in ipairs(files or M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("TrinketMenu", ns)
    end

    return ns, env
end

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

function M.login(ns, env)
    M.fire(env, "ADDON_LOADED", "TrinketMenu")
    M.fire(env, "PLAYER_LOGIN")
end

function M.command(env, text)
    env.SlashCmdList.TRINKETMENU(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- A button's secure attributes, as a plain table.
function M.attrs(button)
    return button.attributes
end

return M
