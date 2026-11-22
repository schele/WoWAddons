local addonName, ns = ...

-- Chat: each quest, item and spell link in a line people typed is shown by
-- this client's name for it. The link itself (what a click opens) is left
-- exactly as it came; only the text between the brackets changes.

ns.AddDefaults({
    -- On by default: it is the whole point, and a line it changes still
    -- opens the same thing when clicked.
    translate = true,
})

local Chat = {}
ns.Chat = Chat

-- What the sender's game called each link that was changed, by "quest:2945",
-- for the tooltip when the player points at it. This session only.
local originals = {}

-- |Htype:data|h[text]|h, the shape every one of these links has. Text holding
-- a | is something fancier than a plain name, and is left alone.
local LINK = "|H(%a+):([^|]*)|h%[([^|%]]*)%]|h"

--- The line with every link it can name put in this client's words, or nil
-- if nothing in it changed.
function Chat.Translate(message)
    if type(message) ~= "string" or not message:find("|H", 1, true) then
        return nil
    end

    local changed = false
    local translated = message:gsub(LINK, function(linkType, data, shown)
        local name = ns.Names.Get(linkType, data)
        if not name or name == shown then
            return nil -- gsub keeps the link as it was
        end
        originals[linkType .. ":" .. data:match("^(%d+)")] = shown
        changed = true
        return string.format("|H%s:%s|h[%s]|h", linkType, data, name)
    end)

    if changed then
        return translated
    end
    return nil
end

--- What the sender's game called the thing a link points at, if this session
-- changed its name in chat. `link` is the part a click hands over:
-- "quest:2945:28".
function Chat.Original(link)
    if type(link) ~= "string" then
        return nil
    end
    local linkType, id = link:match("^(%a+):(%d+)")
    if not linkType then
        return nil
    end
    return originals[linkType .. ":" .. id]
end

--- The chat filter. Returns false to leave a line alone, or false and the
-- changed line to replace it, which is the contract ChatFrame.lua expects.
function Chat.Filter(_, _, message, ...)
    if not (ns.settings and ns.settings.translate) then
        return false
    end

    local translated = ns.Guarded(function() return Chat.Translate(message) end)
    if not translated then
        return false
    end
    return false, translated, ...
end

-- Lines people type. System lines (quest accepted, and the like) are written
-- by the player's own client, in its own language already.
Chat.EVENTS = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
}

--- Every chat window, the temporary whisper windows among them.
function Chat.Frames()
    local frames = {}
    if type(CHAT_FRAMES) == "table" then
        for _, name in ipairs(CHAT_FRAMES) do
            local frame = _G[name]
            if frame then
                table.insert(frames, frame)
            end
        end
    else
        for index = 1, NUM_CHAT_WINDOWS or 10 do
            local frame = _G["ChatFrame" .. index]
            if frame then
                table.insert(frames, frame)
            end
        end
    end
    return frames
end

--- A name the client did not have when a line arrived has come: rewrite the
-- lines already in chat that link to it. Chat windows on this client accept
-- this from addons (TransformMessages); one without it keeps the line as it
-- came, and the next link to the same thing is translated.
function Chat.Retranslate(linkType, id)
    if not (ns.settings and ns.settings.translate) then
        return
    end

    local needle = string.format("|H%s:%d[:|]", linkType, id)
    local function holdsLink(message)
        return ns.Guarded(function()
            return type(message) == "string" and message:find(needle) ~= nil
        end, false)
    end
    local function translate(message, ...)
        return ns.Guarded(function() return Chat.Translate(message) end) or message, ...
    end

    for _, frame in ipairs(Chat.Frames()) do
        if frame.TransformMessages then
            ns.Guarded(function() frame:TransformMessages(holdsLink, translate) end)
        end
    end
end

ns.Names.OnLoaded(Chat.Retranslate)

local installed = false

--- Hook into chat. Idempotent: the same filter registered twice would run
-- twice for nothing.
function Chat.Install()
    if installed then
        return
    end
    installed = true

    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not addFilter then
        ns.Print("This client has no chat filters, so links in chat stay as they are sent.")
        return
    end

    for _, event in ipairs(Chat.EVENTS) do
        addFilter(event, Chat.Filter)
    end
end

ns.OnLogin(Chat.Install)

ns.RegisterCommand("on", "Translate links in chat", function()
    ns.settings.translate = true
    ns.Refresh()
    ns.Print("Links in chat are shown in your game's language.")
end)

ns.RegisterCommand("off", "Leave links in chat as they are sent", function()
    ns.settings.translate = false
    ns.Refresh()
    ns.Print("Links in chat are left as they are sent.")
end)
