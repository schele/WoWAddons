local stub = require("wow_stub")

local M = {}

-- In .toc order. Files not written yet are skipped, so early specs run
-- before later files exist.
M.FILES = {
    "ThreatForever.lua",
    "Threat.lua",
    "Window.lua",
    "Warn.lua",
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

--- Load the addon into a stubbed client the way WoW would: in .toc order,
-- each chunk receiving (addonName, privateTable). The player is a warrior
-- called Skyler, out of combat, alone.
function M.loadAddon()
    local env = stub.newEnv()
    env.__units.player = { name = "Skyler", classFile = "WARRIOR", guid = "Player-1" }
    local ns = {}
    for _, path in ipairs(M.FILES) do
        if exists(path) then
            local chunk = assert(loadfile(path, "t", env))
            chunk("ThreatForever", ns)
        end
    end
    return ns, env
end

--- Fire an event on every frame that hears it, then run what it queued.
function M.fire(env, event, ...)
    local unit = select(1, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do frames[index] = frame end
    for _, frame in ipairs(frames) do
        if frame:Hears(event, type(unit) == "string" and unit or nil) then
            frame:Fire(event, ...)
        end
    end
    env.__runTimers()
end

function M.login(env)
    M.fire(env, "ADDON_LOADED", "ThreatForever")
    M.fire(env, "PLAYER_LOGIN")
end

--- Loaded, `setup(env, ns)` run if given, then logged in.
function M.loggedIn(setup)
    local ns, env = M.loadAddon()
    if setup then setup(env, ns) end
    M.login(env)
    return ns, env
end

function M.command(env, text)
    env.SlashCmdList.THREATFOREVER(text)
    env.__runTimers()
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- A party member at `token` ("party1"), or the pet at "pet".
function M.member(env, token, name, classFile)
    env.__units[token] = { name = name, classFile = classFile, guid = "Player-" .. name }
    if token:match("^party%d$") then
        table.insert(env.__party, token)
    end
    return env.__units[token]
end

--- A hostile mob at `token`, with an empty threat list. `options.boss` makes
-- the game hide its threat numbers.
function M.mob(env, token, name, options)
    options = options or {}
    env.__units[token] = {
        name = name, guid = "Creature-" .. name, hostile = true, boss = options.boss, threat = {},
    }
    return env.__units[token]
end

--- Target `token` (nil clears the target).
function M.target(env, token)
    env.__units.target = token and env.__units[token] or nil
    M.fire(env, "PLAYER_TARGET_CHANGED")
end

--- Put `who` on the target's threat list at `scaled` percent of what it
-- takes to pull, with the game's status for it. With no status, the one at
-- 100 is tanking (3) and the rest are under the tank (0).
function M.threat(env, who, scaled, status)
    local mob = env.__units.target
    if status == nil then
        status = scaled >= 100 and 3 or 0
    end
    mob.threat[who] = { scaled = scaled, status = status, tanking = status >= 2 }
    M.fire(env, "UNIT_THREAT_LIST_UPDATE", "target")
end

function M.combat(env, on)
    env.__units.player.combat = on
    M.fire(env, on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

--- In combat with a target called Defias Pillager, `group` already in the
-- party as { token, name, classFile } and on its threat list as given in
-- `threat` (token -> scaled percent). `setup(env)` runs before login.
function M.fighting(threat, group, setup)
    local ns, env = M.loggedIn(function(env)
        for _, member in ipairs(group or {}) do
            M.member(env, member[1], member[2], member[3])
        end
        if setup then setup(env) end
    end)
    M.mob(env, "mob", "Defias Pillager")
    M.target(env, "mob")
    M.combat(env, true)
    for who, scaled in pairs(threat or {}) do
        M.threat(env, who, scaled)
    end
    return ns, env
end

return M
