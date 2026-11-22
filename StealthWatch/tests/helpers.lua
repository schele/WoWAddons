local stub = require("wow_stub")

local M = {}

-- In .toc order. Files not written yet are skipped, so early specs run
-- before later files exist.
M.FILES = {
    "StealthWatch.lua",
    "Watcher.lua",
    "Alert.lua",
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
-- each chunk receiving (addonName, privateTable).
function M.loadAddon()
    local env = stub.newEnv()
    local ns = {}
    for _, path in ipairs(M.FILES) do
        if exists(path) then
            local chunk = assert(loadfile(path, "t", env))
            chunk("StealthWatch", ns)
        end
    end
    return ns, env
end

--- Fire an event on every frame that hears it. A unit event reaches the
-- frames registered for that unit, and those registered for every unit.
function M.fire(env, event, ...)
    local unit = select(1, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do frames[index] = frame end
    for _, frame in ipairs(frames) do
        if frame:Hears(event, type(unit) == "string" and unit or nil) then
            frame:Fire(event, ...)
        end
    end
end

function M.login(env)
    M.fire(env, "ADDON_LOADED", "StealthWatch")
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
    env.SlashCmdList.STEALTHWATCH(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- Let `seconds` of game time pass.
function M.wait(env, seconds)
    env.__now = env.__now + seconds
end

--- A nameplate appears for `unit` as `token`.
function M.plateAdded(env, token, unit)
    env.__units[token] = unit
    M.fire(env, "NAME_PLATE_UNIT_ADDED", token)
end

--- The nameplate `token` goes: the event fires while the token still
-- answers, as the client's does, and then the token is empty.
function M.plateRemoved(env, token)
    M.fire(env, "NAME_PLATE_UNIT_REMOVED", token)
    env.__units[token] = nil
end

--- `token` finishes casting `spellID` (a secret from env.__secret() works).
-- With `castTime`, the cast started that many seconds before.
function M.cast(env, token, spellID, castTime)
    if castTime then
        M.fire(env, "UNIT_SPELLCAST_START", token, "Cast-1", spellID)
        M.wait(env, castTime)
    end
    M.fire(env, "UNIT_SPELLCAST_SUCCEEDED", token, "Cast-2", spellID)
end

--- The player targets `unit`, or clears the target when `unit` is nil.
function M.target(env, unit)
    env.__units.target = unit
    M.fire(env, "PLAYER_TARGET_CHANGED")
end

--- Every stealth the addon reported, as the listeners heard them.
function M.reports(ns)
    local heard = {}
    ns.OnStealth(function(info) table.insert(heard, info) end)
    return heard
end

return M
