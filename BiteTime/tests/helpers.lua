local stub = require("wow_stub")

local M = {}

-- In .toc order. Files not written yet are skipped, so early specs run
-- before later files exist.
M.FILES = {
    "BiteTime.lua",
    "Bite.lua",
    "Kill.lua",
    "Gate.lua",
    "Glow.lua",
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
-- each chunk receiving (addonName, privateTable). `options` go to the stub
-- ({ era = true } for Classic Era).
function M.loadAddon(options)
    local env = stub.newEnv(options)
    local ns = {}
    for _, path in ipairs(M.FILES) do
        if exists(path) then
            local chunk = assert(loadfile(path, "t", env))
            chunk("BiteTime", ns)
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
    M.fire(env, "ADDON_LOADED", "BiteTime")
    M.fire(env, "PLAYER_LOGIN")
end

--- Loaded, `setup(env, ns)` run if given, then logged in. `options` go to
-- the stub.
function M.loggedIn(setup, options)
    local ns, env = M.loadAddon(options)
    if setup then setup(env, ns) end
    M.login(env)
    return ns, env
end

function M.command(env, text)
    env.SlashCmdList.BITETIME(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- Let `seconds` of game time pass: timers due by then run, and every
-- frame's OnUpdate hears the time go by.
function M.wait(env, seconds)
    env.__now = env.__now + seconds
    env.__runTimers()
    for _, frame in ipairs(env.__frames) do
        if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, seconds) end
    end
end

--- The player targets `unit`, or clears the target when `unit` is nil.
function M.target(env, unit)
    env.__units.target = unit
    M.fire(env, "PLAYER_TARGET_CHANGED")
end

--- The target's health changes to `health`.
function M.health(env, health)
    env.__units.target.health = health
    M.fire(env, "UNIT_HEALTH", "target")
end

--- The player has `points` combo points and `energy` energy.
function M.power(env, points, energy)
    env.__points = points
    if energy then env.__energy = energy end
    M.fire(env, "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
end

--- Spell `id` goes in action slot `slot`, as dragging it there does.
function M.place(env, slot, id)
    env.__place(slot, id)
    M.fire(env, "ACTIONBAR_SLOT_CHANGED", slot)
end

--- How much of `glow` (a button's border, or the icon in the middle) the
-- client draws: 0 when it is hidden, else how full it draws the status bars
-- the glow is made of, 1 when they are all full. They should agree.
function M.seen(env, glow)
    if not glow:IsShown() then
        return 0
    end
    local drawn
    for _, piece in ipairs(glow.gate.pieces) do
        local fill = piece:__drawn()
        assert(drawn == nil or fill == drawn, "the pieces of one glow are drawn differently")
        drawn = fill
    end
    return (drawn or 0) * env.__reveal(glow:GetAlpha())
end

return M
