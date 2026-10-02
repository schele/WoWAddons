local addonName, ns = ...

-- Which mails are ticked, by key: a tick stays with its mail across pages
-- and as the list moves. Forgotten when the mailbox closes.

local Ticks = {}
ns.Ticks = Ticks

local ticked = {}

function Ticks.Is(key)
    return key ~= nil and ticked[key] == true
end

function Ticks.Set(key, on)
    if key then
        ticked[key] = on and true or nil
    end
    ns.Changed()
end

function Ticks.Clear()
    ticked = {}
end

--- The ticked mails among `mails`, top to bottom: a tick whose mail has
-- gone is not counted.
function Ticks.Mails(mails)
    local list = {}
    for _, mail in ipairs(mails or ns.Inbox.Mails()) do
        if ticked[mail.key] then
            list[#list + 1] = mail
        end
    end
    return list
end

function Ticks.Count(mails)
    return #Ticks.Mails(mails)
end

function Ticks.AllTicked(mails)
    mails = mails or ns.Inbox.Mails()
    return #mails > 0 and Ticks.Count(mails) == #mails
end

function Ticks.SetAll(on)
    for _, mail in ipairs(ns.Inbox.Mails()) do
        ticked[mail.key] = on and true or nil
    end
    ns.Changed()
end
