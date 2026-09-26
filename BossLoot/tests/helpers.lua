local stub = require("wow_stub")

local M = {}

-- Everything but the generated data, in .toc order. Specs add their own
-- instances; data_spec loads the real ones.
M.FILES = {
    "BossLoot.lua",
    "Format.lua",
    "Index.lua",
    "List.lua",
    "LootRow.lua",
    "Window.lua",
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

--- Load files into a fresh stubbed environment. Files that do not exist yet
-- are skipped, so early specs run before later files are written.
function M.loadAddon(files, setup)
    local env = stub.newEnv()
    local ns = {}
    if setup then setup(env, ns) end

    for _, path in ipairs(files or M.FILES) do
        if exists(path) then
            local chunk = assert(loadfile(path, "t", env))
            chunk("BossLoot", ns)
        end
    end

    return ns, env
end

function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do frames[index] = frame end
    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] then frame:Fire(event, ...) end
    end
end

function M.login(ns, env)
    M.fire(env, "ADDON_LOADED", "BossLoot")
    M.fire(env, "PLAYER_LOGIN")
end

function M.command(env, text)
    env.SlashCmdList.BOSSLOOT(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- Two small dungeons and a raid to test against: one dungeon with wings and
-- trash drops, one with a chest, and a raid with neither.
function M.sampleInstances(ns)
    ns.AddInstance({
        key = "Depths", name = "Test Depths", kind = "dungeon", levels = { 52, 60 },
        bosses = {
            { name = "First Boss", wing = "East", loot = { { 1001, 20 }, { 1002, 1.5 } } },
            { name = "Second Boss", wing = "East", loot = { { 1003, 100 } } },
            { name = "Third Boss", wing = "West", loot = { { 1004, 5 } } },
        },
        notable = {
            trash = { { 2001, 0.9, { "Anvilrage Overseer", "Anvilrage Guardsman" } } },
            objects = {},
        },
    })
    ns.AddInstance({
        key = "Spire", name = "Low Spire", kind = "dungeon", levels = { 55, 60 },
        bosses = { { name = "Spire Boss", loot = { { 3001, 10 } } } },
        notable = { trash = {}, objects = { { 3002, 100, { "Old Chest" } } } },
    })
    ns.AddInstance({
        key = "Core", name = "Molten Test", kind = "raid", levels = { 60, 60 },
        bosses = { { name = "Raid Boss", loot = { { 1001, 12 } } } },
        notable = { trash = {}, objects = {} },
    })
end

--- Logged in with the sample instances.
function M.loggedIn()
    local ns, env = M.loadAddon()
    M.sampleInstances(ns)
    M.login(ns, env)
    return ns, env
end

return M
