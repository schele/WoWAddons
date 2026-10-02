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

--- The mail with `key` has left the box: its tick goes, and each alike
-- mail below it, now one number lower, keeps its own tick or lack of one.
function Ticks.Removed(key)
    local base, number = key:match("^(.*)#(%d+)$")
    ticked[key] = nil
    if not base then
        return
    end
    number = tonumber(number)
    local last = number
    for other in pairs(ticked) do
        local otherBase, otherNumber = other:match("^(.*)#(%d+)$")
        if otherBase == base and tonumber(otherNumber) > last then
            last = tonumber(otherNumber)
        end
    end
    for below = number + 1, last do
        ticked[base .. "#" .. (below - 1)] = ticked[base .. "#" .. below]
    end
    ticked[base .. "#" .. last] = nil
    ns.Changed()
end

function Ticks.SetAll(on)
    for _, mail in ipairs(ns.Inbox.Mails()) do
        ticked[mail.key] = on and true or nil
    end
    ns.Changed()
end
