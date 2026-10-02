local addonName, ns = ...

-- Listening for groups: every chat channel but the defence ones, and guild
-- chat. Each message from someone else goes to the board, and may alert.
-- Rows past their ten minutes are swept out as time passes.

local Chat = {}
ns.Chat = Chat

-- Seconds between sweeps for rows that have run out.
Chat.SWEEP = 15

-- Channels whose messages are never groups, found in a channel's name.
local SKIPPED = { "localdefense", "worlddefense" }

local function classOf(guid)
    return ns.Guarded(function()
        if type(guid) == "string" and GetPlayerInfoByGUID then
            local _, class = GetPlayerInfoByGUID(guid)
            return type(class) == "string" and class or nil
        end
        return nil
    end, nil)
end

local function skippedChannel(baseName, fullName)
    local name = (type(baseName) == "string" and baseName ~= "") and baseName or fullName
    if type(name) ~= "string" then
        return false
    end
    name = name:lower():gsub("%s", "")
    for _, skipped in ipairs(SKIPPED) do
        if name:find(skipped, 1, true) then
            return true
        end
    end
    return false
end

--- One message, with the arguments CHAT_MSG_CHANNEL and CHAT_MSG_GUILD give.
function Chat.Heard(event, text, sender, _, channelName, _, _, _, _, channelBaseName, _, _, guid)
    ns.Guarded(function()
        if type(text) ~= "string" or type(sender) ~= "string" or ns.IsMe(sender) then
            return
        end
        local guild = event == "CHAT_MSG_GUILD"
        if not guild and skippedChannel(channelBaseName, channelName) then
            return
        end

        local row = ns.Posts.AddChat({ name = sender, class = classOf(guid), text = text, time = GetTime(), guild = guild })
        if row then
            ns.Alerts.Consider(ns.Posts.View(row))
        end
        ns.Changed()
    end)
end

local function sweep()
    ns.Posts.Expire(GetTime())
    ns.Changed()
    C_Timer.After(Chat.SWEEP, sweep)
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_CHANNEL")
events:RegisterEvent("CHAT_MSG_GUILD")
events:SetScript("OnEvent", function(_, event, ...)
    Chat.Heard(event, ...)
end)

ns.OnLogin(function()
    C_Timer.After(Chat.SWEEP, sweep)
end)
