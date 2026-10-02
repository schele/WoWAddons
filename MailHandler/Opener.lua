local addonName, ns = ...

-- Opening the ticked mails: gold first, then each item, one take at a
-- time, each waited for until the server answers. From the bottom up, so a
-- mail the game removes once empty never moves the ones still to do: a
-- mail's key counts only the mails above it.

local Opener = {}
ns.Opener = Opener

-- How often to look whether the server has answered a take, and how many
-- looks (about two seconds) before it is given up.
Opener.LOOK = 0.25
Opener.MAX_LOOKS = 8

local run

function Opener.Running()
    return run ~= nil
end

--- Whether the take a run is waiting on has been answered: the gold or the
-- item is gone from the mail, or the mail itself is.
local function answered(waiting)
    local mail = ns.Inbox.Find(waiting.key)
    if not mail then
        return true
    end
    if waiting.kind == "money" then
        return mail.money == 0
    end
    return not ns.Inbox.HasAttachment(mail.index, waiting.slot)
end

local function left(current)
    return #current.targets - current.at + 1
end

local function report(current, stopped)
    local parts = {}

    local opened = 0
    for _ in pairs(current.took) do
        opened = opened + 1
    end
    if opened > 0 then
        local what = {}
        local gained = math.max(0, (GetMoney() or 0) - current.startMoney)
        if gained > 0 then
            what[#what + 1] = ns.Money(gained)
        end
        if current.items > 0 then
            what[#what + 1] = ns.Count(current.items, "item")
        end
        local line = "Opened " .. ns.Count(opened, "mail")
        if #what > 0 then
            line = line .. ": " .. table.concat(what, ", ")
        end
        parts[#parts + 1] = line .. "."
    end

    if current.cod > 0 then
        parts[#parts + 1] = string.format("Skipped %s.", ns.Count(current.cod, "cash-on-delivery mail"))
    end
    if stopped then
        parts[#parts + 1] = stopped
    end
    if #parts > 0 then
        ns.Print(table.concat(parts, " "))
    end
end

local function finish(current, stopped)
    if run ~= current then
        return
    end
    run = nil
    report(current, stopped)
    ns.Changed()
end

local step

local function later(current)
    C_Timer.After(Opener.LOOK, function()
        step(current)
    end)
end

step = function(current)
    if run ~= current then
        return
    end

    local waiting = current.waiting
    if waiting then
        local done = answered(waiting)
        if not done and waiting.looks < Opener.MAX_LOOKS then
            waiting.looks = waiting.looks + 1
            later(current)
            return
        end
        current.waiting = nil
        if done then
            current.took[waiting.key] = true
            if waiting.kind == "item" then
                current.items = current.items + 1
            end
        else
            -- The server never answered: leave this mail, still ticked.
            current.at = current.at + 1
        end
    end

    while true do
        local key = current.targets[current.at]
        if not key then
            finish(current)
            return
        end

        local mail = ns.Inbox.Find(key)
        local slot = mail and ns.Inbox.FirstAttachment(mail.index)
        if mail and mail.cod > 0 then
            current.cod = current.cod + 1
            ns.Ticks.Set(key, false)
            current.at = current.at + 1
        elseif mail and mail.money > 0 then
            TakeInboxMoney(mail.index)
            current.waiting = { key = key, kind = "money", looks = 0 }
            later(current)
            return
        elseif slot then
            if ns.Inbox.FreeSlots() <= 0 then
                finish(current, string.format("Bags are full: %s left.", ns.Count(left(current), "ticked mail")))
                return
            end
            TakeInboxItem(mail.index, slot)
            current.waiting = { key = key, kind = "item", slot = slot, looks = 0 }
            later(current)
            return
        else
            -- Nothing left in it, or the game has removed it.
            ns.Ticks.Set(key, false)
            current.at = current.at + 1
        end
    end
end

--- Open the ticked mails, bottom up. False when a run is already going or
-- nothing is ticked.
function Opener.Start(mails)
    if run then
        return false
    end
    local ticked = ns.Ticks.Mails(mails)
    if #ticked == 0 then
        return false
    end

    local targets = {}
    for index = #ticked, 1, -1 do
        targets[#targets + 1] = ticked[index].key
    end
    run = {
        targets = targets,
        at = 1,
        startMoney = GetMoney() or 0,
        items = 0,
        cod = 0,
        took = {},
    }
    ns.Changed()
    step(run)
    return true
end

--- The mailbox closed: stop, and say what was done and what is left.
function Opener.Stop()
    if run then
        finish(run, string.format("Mailbox closed: %s left.", ns.Count(left(run), "ticked mail")))
    end
end
