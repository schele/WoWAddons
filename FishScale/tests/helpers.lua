local stub = require("wow_stub")

local M = {}

M.FILES = {
    "FishScale.lua",
    "Fishing.lua",
    "Settings.lua",
}

--- The panel's control for a setting, by its key.
function M.control(ns, key)
    for _, control in ipairs(ns.SettingsPanel.controls) do
        if control.setting.key == key then
            return control
        end
    end
end

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

--- Let `seconds` of game time pass, driving every frame's OnUpdate.
--
-- In one step by default, because the addon's poll only cares that its
-- interval has elapsed. A test wanting to watch something settle over several
-- ticks passes a smaller `step`.
function M.elapse(env, seconds, step)
    step = step or seconds
    local remaining = seconds

    while remaining > 0 do
        local slice = math.min(step, remaining)
        for _, frame in ipairs(env.__frames) do
            local handler = frame.scripts and frame.scripts.OnUpdate
            if handler then
                handler(frame, slice)
            end
        end
        remaining = remaining - slice
    end
end

function M.command(env, text)
    env.SlashCmdList.FISHSCALE(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
