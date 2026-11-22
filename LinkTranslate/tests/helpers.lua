local stub = require("wow_stub")

local M = {}

-- In .toc order. Files not written yet are skipped, so early specs run
-- before later files exist.
M.FILES = {
    "LinkTranslate.lua",
    "Names.lua",
    "Chat.lua",
    "Hover.lua",
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
            chunk("LinkTranslate", ns)
        end
    end
    return ns, env
end

--- Fire an event on every frame that hears it.
function M.fire(env, event, ...)
    local frames = {}
    for index, frame in ipairs(env.__frames) do frames[index] = frame end
    for _, frame in ipairs(frames) do
        if frame:Hears(event) then
            frame:Fire(event, ...)
        end
    end
end

function M.login(env)
    M.fire(env, "ADDON_LOADED", "LinkTranslate")
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
    env.SlashCmdList.LINKTRANSLATE(text)
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- A link as it arrives in chat: |Htype:data|h[text]|h, coloured as the
-- client colours quest links.
function M.link(linkType, data, text)
    return string.format("|cffffff00|H%s:%s|h[%s]|h|r", linkType, data, text)
end

--- Someone says `message` on `event` (default General chat), into `frame`
-- (default ChatFrame1): every chat filter runs over it the way
-- ChatFrameFilters.lua does, and the line that comes out is added to the
-- window. Returns that line, or nil if a filter threw it away.
function M.say(env, message, event, frame)
    event = event or "CHAT_MSG_CHANNEL"
    frame = frame or env.ChatFrame1
    local args = table.pack(message, "Tranzalorr", "", "1. General - Duskwood")
    for _, filter in ipairs(env.__filters[event] or {}) do
        local results = table.pack(pcall(filter, frame, event, table.unpack(args, 1, args.n)))
        if results[1] then
            if results[2] then
                return nil
            end
            if results[3] then
                args = table.pack(table.unpack(results, 3, results.n))
            end
        end
    end
    frame:AddMessage(args[1], 1, 0.75, 0.75)
    return args[1]
end

--- The client finishes loading a name it was asked for: what was loadable
-- becomes known, and the load's event fires.
local LOAD_EVENTS = {
    quest = "QUEST_DATA_LOAD_RESULT",
    item = "ITEM_DATA_LOAD_RESULT",
    spell = "SPELL_DATA_LOAD_RESULT",
}

function M.finishLoad(env, linkType, id, success)
    if success ~= false then
        env.__names[linkType][id] = env.__loadable[linkType][id]
    end
    M.fire(env, LOAD_EVENTS[linkType], id, success ~= false)
end

--- The player points at a link in `frame`, then moves off it, Forever's
-- way: through EventRegistry.
function M.pointAt(env, frame, link)
    local callback = env.__callbacks["ChatFrame.OnHyperlinkEnter"]
    callback.fn(callback.owner, frame, link, "[text]")
end

function M.pointAway(env, frame)
    local callback = env.__callbacks["ChatFrame.OnHyperlinkLeave"]
    callback.fn(callback.owner, frame)
end

return M
