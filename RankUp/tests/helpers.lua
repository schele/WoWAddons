local stub = require("wow_stub")

local M = {}

M.FILES = {
    "RankUp.lua",
    "Ranks.lua",
    "Swap.lua",
    "Popup.lua",
    "Settings.lua",
}

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable). `prepare`,
-- if given, sees the environment before any file loads.
function M.loadAddon(prepare)
    local env = stub.newEnv()
    if prepare then
        prepare(env)
    end

    local ns = {}
    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("RankUp", ns)
    end

    return ns, env
end

M.legacy = stub.useLegacySpellAPI

--- Put a spell on a slot by its ID; nil empties the slot.
function M.place(env, slot, spellID)
    env.__actions[slot] = spellID and { kind = "spell", id = spellID } or nil
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

--- Log in: the first loading screen, then the moment after it.
function M.login(env)
    M.fire(env, "PLAYER_LOGIN")
    M.fire(env, "PLAYER_ENTERING_WORLD", true, false)
    env.__runTimers()
end

function M.enterCombat(env)
    env.__inCombat = true
    M.fire(env, "PLAYER_REGEN_DISABLED")
end

function M.leaveCombat(env)
    env.__inCombat = false
    M.fire(env, "PLAYER_REGEN_ENABLED")
end

function M.command(env, text)
    env.SlashCmdList.RANKUP(text or "")
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
