local stub = require("wow_stub")

local M = {}

M.FILES = {
    "MailHandler.lua",
    "Inbox.lua",
    "Ticks.lua",
    "Opener.lua",
    "Buttons.lua",
    "Settings.lua",
}

--- Load the addon's files into a stubbed client, in .toc order. `prepare`
-- sees the client first.
function M.loadAddon(prepare)
    local env = stub.newEnv()
    if prepare then prepare(env) end
    local ns = {}
    for _, path in ipairs(M.FILES) do
        local chunk = assert(loadfile(path, "t", env))
        chunk("MailHandler", ns)
    end
    return ns, env
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

--- A mail at the bottom of the box. `items` maps attachment slots to
-- { name, count }.
function M.mail(env, sender, subject, money, items, cod)
    local mail = { sender = sender, subject = subject, money = money or 0, cod = cod or 0, items = items or {} }
    table.insert(env.__mails, mail)
    return mail
end

function M.sale(env, item, count, money)
    return M.mail(env, "Alliance Auction House", string.format("Auction successful: %s (%d)", item, count), money)
end

--- An expired auction, its items in `slots` attachments of `count` each.
function M.expired(env, item, count, slots)
    local items = {}
    for slot = 1, slots or 1 do
        items[slot] = { name = item, count = count }
    end
    return M.mail(env, "Alliance Auction House", string.format("Auction expired: %s (%d)", item, count), 0, items)
end

M.forever = stub.useForeverInbox

--- The game redrawing its inbox, the way this client does it.
function M.redraw(env)
    if env.InboxFrame_Update then
        env.InboxFrame_Update()
    else
        env.InboxFrame:Update()
    end
end

function M.login(env)
    M.fire(env, "PLAYER_LOGIN")
end

function M.openMailbox(env)
    M.fire(env, "MAIL_SHOW")
    M.redraw(env)
end

function M.closeMailbox(env)
    M.fire(env, "MAIL_CLOSED")
end

function M.printed(env)
    return table.concat(env.__printed, "\n")
end

return M
