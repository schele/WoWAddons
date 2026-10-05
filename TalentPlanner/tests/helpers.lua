local stub = require("wow_stub")

local M = {}

-- In .toc order.
M.FILES = {
    "TalentPlanner.lua",
    "Plan.lua",
    "Codec.lua",
    "Trees.lua",
    "Reminder.lua",
    "Planner.lua",
    "TalentFrame.lua",
    "Minimap.lua",
    "Settings.lua",
}

M.TREES = stub.TREES
M.useEasyMenu = stub.useEasyMenu
M.useNoMenu = stub.useNoMenu

--- Load the addon's files into a stubbed client, in .toc order, each chunk
-- receiving (addonName, privateTable). `prepare` sees the client first.
function M.loadAddon(saved, prepare)
    local env = stub.newEnv(saved)
    if prepare then prepare(env) end
    local ns = {}
    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("TalentPlanner", ns)
    end
    return ns, env
end

--- Load one pure file into an environment holding only Lua's own library:
-- any reach for the game raises.
function M.loadPure(path)
    local env = {
        string = string, table = table, math = math, type = type, tostring = tostring,
        tonumber = tonumber, ipairs = ipairs, pairs = pairs, select = select, next = next,
        error = error, pcall = pcall, setmetatable = setmetatable, unpack = table.unpack,
    }
    setmetatable(env, {
        __index = function(_, key) error("reached for the game: " .. tostring(key), 2) end,
    })
    local ns = {}
    local chunk = assert(loadfile(path, "t", env))
    chunk("TalentPlanner", ns)
    return ns
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

function M.login(env)
    M.fire(env, "ADDON_LOADED", "TalentPlanner")
    M.fire(env, "PLAYER_LOGIN")
end

function M.loggedIn(saved, prepare)
    local ns, env = M.loadAddon(saved, prepare)
    M.login(env)
    return ns, env
end

function M.command(env, text)
    env.SlashCmdList.TALENTPLANNER(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

function M.clearPrinted(env)
    env.__printed = {}
end

--- The stub's trees as Plan.lua sees them: what Trees.Read gives, built
-- here without the game so the pure specs need no client.
function M.trees(ranks)
    local trees = {}
    for tab, tree in ipairs(stub.TREES) do
        local talents = {}
        for index, talent in ipairs(tree.talents) do
            talents[index] = {
                name = talent[1], icon = "icon", tier = talent[2], column = talent[3],
                maxRank = talent[4], prereq = talent[5],
                rank = ranks and ranks[tab] and ranks[tab][index] or 0,
            }
        end
        trees[tab] = { name = tree.name, icon = "icon", spent = 0, talents = talents }
    end
    return trees
end

--- A list of points from "tab.index" words, repeated by count:
-- points("2.1x5", "2.3") is five Ferocity then a Thick Hide.
function M.points(...)
    local list = {}
    for _, word in ipairs({ ... }) do
        local tab, index, times = word:match("^(%d+)%.(%d+)x?(%d*)$")
        for _ = 1, tonumber(times) or 1 do
            list[#list + 1] = { tonumber(tab), tonumber(index) }
        end
    end
    return list
end

return M
