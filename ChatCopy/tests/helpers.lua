local stub = require("wow_stub")

local M = {}

M.FILES = {
    "ChatCopy.lua",
    "Detect.lua",
    "Popup.lua",
    "Chat.lua",
    "ChatText.lua",
    "Settings.lua",
    "Minimap.lua",
}

--- Load the addon's files into a stubbed environment, the way WoW would:
-- in .toc order, each chunk receiving (addonName, privateTable).
-- Pass a shorter list while the later files do not exist yet.
function M.loadAddon(files)
    local env = stub.newEnv()
    local ns = {}

    for _, path in ipairs(files or M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("ChatCopy", ns)
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
    M.fire(env, "ADDON_LOADED", "ChatCopy")
    M.fire(env, "PLAYER_LOGIN")
end

function M.command(env, text)
    env.SlashCmdList.CHATCOPY(text)
end

--- Say something in chat and return what the frame would show.
function M.say(env, message, event)
    return env.__say(event or "CHAT_MSG_SAY", message, "Someone")
end

--- Click a chat hyperlink, the way the client does.
function M.click(env, link)
    env.SetItemRef(link, "[link]", "LeftButton")
end

--- Everything the addon has printed, as one string.
function M.printed(env)
    return table.concat(env.__printed, "\n")
end

--- The first chatcopy link inside a rewritten message.
function M.linkIn(text)
    return (tostring(text):match("|H(chatcopy:[^|]+)|h"))
end

--- The copy box currently on screen.
function M.box(env)
    return env.__shownPopup and env.__shownPopup.editBox
end

return M
