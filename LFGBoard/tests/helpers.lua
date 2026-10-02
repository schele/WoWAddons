local stub = require("wow_stub")

local M = {}

M.FILES = {
    "LFGBoard.lua",
    "Activities.lua",
    "Parse.lua",
}

-- A filter that shows every row.
M.ALL = { tab = "all", roles = { tank = true, healer = true, dps = true }, nearLevel = false, level = 20 }

--- Load the addon's files into a stubbed client, in .toc order, each chunk
-- receiving (addonName, privateTable). `prepare` sees the client first.
function M.loadAddon(saved, prepare)
    local env = stub.newEnv(saved)
    if prepare then prepare(env) end
    local ns = {}
    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("LFGBoard", ns)
    end
    return ns, env
end

M.olderFinder = stub.useOlderFinder

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
    M.fire(env, "ADDON_LOADED", "LFGBoard")
    M.fire(env, "PLAYER_LOGIN")
end

function M.loggedIn(saved)
    local ns, env = M.loadAddon(saved)
    M.login(env)
    return ns, env
end

--- A channel message, with CHAT_MSG_CHANNEL's arguments in their places.
function M.say(env, sender, text, opts)
    opts = opts or {}
    M.fire(env, "CHAT_MSG_CHANNEL", text, sender, "Common", "2. Trade - City", sender, "", 0, 2,
        opts.channel or "Trade", 0, 1, opts.guid)
end

function M.guild(env, sender, text, guid)
    M.fire(env, "CHAT_MSG_GUILD", text, sender, "Common", "", sender, "", 0, 0, "", 0, 1, guid)
end

--- A group finder listing. `members` are { role = "TANK", class = "WARRIOR" }.
function M.list(env, id, leader, activityID, members, comment, delisted)
    env.__results[id] = {
        leader = leader,
        activityID = activityID,
        members = members,
        comment = comment or "",
        delisted = delisted,
    }
    table.insert(env.__resultOrder, id)
end

function M.searched(env)
    M.fire(env, "LFG_LIST_SEARCH_RESULTS_RECEIVED")
end

function M.later(env, seconds)
    env.__now = env.__now + seconds
end

function M.command(env, text)
    env.SlashCmdList.LFGBOARD(text or "")
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
