local addonName, ns = ...

-- Forwarding: the ticked mails, or the one open, go out again as a new mail
-- from you. The game has no forward, so MailHandler makes one: it takes
-- each mail's gold and items as Open does, from the bottom up, puts each
-- item on the Send Mail tab as it lands in the bags, and fills in the
-- subject, the text and the gold. The player presses Send. Twelve items
-- fit in a mail; once one has gone, the next is filled, to the same name.

local Forwarder = {}
ns.Forwarder = Forwarder

-- How often to look whether the server has answered, and how many looks
-- (about two seconds) before it is given up.
Forwarder.LOOK = 0.25
Forwarder.MAX_LOOKS = 8

local SUBJECT_PREFIX = "FW: "

local run
-- The name the last mail went to, as the game's own Send passed it.
local lastSentTo

function Forwarder.Running()
    return run ~= nil
end

-- Saved per character: whom this character last forwarded to.
local function saved()
    if type(MailHandlerCharDB) ~= "table" then
        MailHandlerCharDB = {}
    end
    return MailHandlerCharDB
end

local function maxSend()
    return ATTACHMENTS_MAX_SEND or 12
end

--- The first free attachment slot on the Send Mail tab, or nil when full.
local function freeSendSlot()
    for index = 1, maxSend() do
        local taken = ns.Guarded(function()
            return HasSendMailItem(index) and true or false
        end, true)
        if not taken then
            return index
        end
    end
    return nil
end

local function setText(box, text)
    if box and box.SetText then
        box:SetText(text)
    end
end

local function textOf(box)
    local text = box and box.GetText and box:GetText()
    return type(text) == "string" and text or ""
end

-- Forever's mail text box is a plain one; Classic Era's scrolls.
local function bodyBox()
    return SendMailBodyEditBox or MailEditBox
end

--- The open mail: its text, and for an auction house invoice, what the
-- invoice says, as the game shows it.
local function letterOf(index)
    return ns.Guarded(function()
        local lines = {}
        local body, _, _, _, isInvoice = GetInboxText(index)
        if type(body) == "string" and body ~= "" then
            lines[#lines + 1] = body
        end
        if isInvoice and GetInboxInvoiceInfo then
            local kind, item, player = GetInboxInvoiceInfo(index)
            item = tostring(item or "")
            if kind == "buyer" then
                lines[#lines + 1] = (ITEM_PURCHASED_COLON or "Item Purchased:") .. " " .. item
                if player then
                    lines[#lines + 1] = (SOLD_BY_COLON or "Sold By:") .. " " .. tostring(player)
                end
            elseif kind == "seller" or kind == "seller_temp_invoice" then
                lines[#lines + 1] = (ITEM_SOLD_COLON or "Item Sold:") .. " " .. item
                if player then
                    lines[#lines + 1] = (PURCHASED_BY_COLON or "Purchased By:") .. " " .. tostring(player)
                end
            end
        end
        return table.concat(lines, "\n")
    end, "")
end

-- A mail to forward, as the new mail's subject and text name it.
local function about(mail)
    return { key = mail.key, sender = mail.sender, subject = mail.subject }
end

-- The mail being filled: the forwarded mails it carries, its gold, how
-- many of their items, and how many stacks are on the tab.
local function newBatch()
    return { mails = {}, carries = {}, gold = 0, items = 0, attachments = 0 }
end

local function join(batch, mail)
    if not batch.carries[mail.key] then
        batch.carries[mail.key] = true
        batch.mails[#batch.mails + 1] = mail
    end
end

local function subjectOf(batch)
    if #batch.mails == 1 then
        return SUBJECT_PREFIX .. batch.mails[1].subject
    end
    return SUBJECT_PREFIX .. ns.Count(#batch.mails, "mail")
end

local function bodyOf(current, batch)
    local lines = {}
    for _, mail in ipairs(batch.mails) do
        lines[#lines + 1] = string.format("From %s: %s", mail.sender, mail.subject)
    end
    if current.letter ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = current.letter
    end
    return table.concat(lines, "\n")
end

--- The Send Mail tab, filled for the mail made so far: the name if none
-- is typed, the subject, the text, and its gold as gold sent, never as
-- cash on delivery.
local function fill(current)
    local batch = current.batch
    if textOf(SendMailNameEditBox) == "" and current.to then
        setText(SendMailNameEditBox, current.to)
    end
    setText(SendMailSubjectEditBox, subjectOf(batch))
    setText(bodyBox(), bodyOf(current, batch))
    if SendMailRadioButton_OnClick then
        SendMailRadioButton_OnClick(1)
    end
    if MoneyInputFrame_SetCopper and SendMailMoney then
        MoneyInputFrame_SetCopper(SendMailMoney, batch.gold)
    end
end

local function left(current)
    return #current.targets - current.at + 1
end

local function report(current, stopped)
    local parts = {}

    if current.forwarded > 0 then
        local what = {}
        if current.gold > 0 then
            what[#what + 1] = ns.Money(current.gold)
        end
        if current.items > 0 then
            what[#what + 1] = ns.Count(current.items, "item")
        end
        local line = "Forwarded " .. ns.Count(current.forwarded, "mail")
        if current.to and current.to ~= "" then
            line = line .. " to " .. current.to
        end
        if #what > 0 then
            line = line .. ": " .. table.concat(what, ", ")
        end
        parts[#parts + 1] = line .. "."
    end

    if current.cod > 0 then
        parts[#parts + 1] = string.format("Skipped %s.", ns.Count(current.cod, "cash-on-delivery mail"))
    end
    if current.unmailable > 0 then
        parts[#parts + 1] = string.format("%s could not be mailed, and %s in your bags.",
            ns.Count(current.unmailable, "item"), current.unmailable == 1 and "is" or "are")
    end
    if current.unanswered > 0 then
        parts[#parts + 1] = string.format("%s did not answer.", ns.Count(current.unanswered, "mail"))
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

--- Hand the mail made so far to the player to send: the last one, or one
-- that cannot take more because the tab or the bags (`why`) are full.
-- With nothing in it, there is nothing to send: the forward ends.
local function ready(current, why, last)
    if #current.batch.mails == 0 then
        local stuck
        if why == "bags" then
            stuck = string.format("Bags are full: %s left.", ns.Count(left(current), "mail"))
        elseif why == "tab" then
            stuck = "The Send Mail tab is full."
        end
        finish(current, stuck)
        return
    end
    current.ready = true
    current.last = last
    fill(current)
    if why == "bags" then
        ns.Print("Bags are full: press Send, and MailHandler goes on once the mail has gone.")
    elseif not last then
        ns.Print("This mail is full: press Send, and MailHandler fills the next.")
    end
    ns.Changed()
end

-- An item taken from a mail, one stack or part of one, that will not go
-- on the tab. Counted once for the item it came from.
local function unmailable(current, arrival)
    if not arrival.take.failed then
        arrival.take.failed = true
        current.unmailable = current.unmailable + 1
    end
end

local function attached(current, arrival)
    local take = arrival.take
    take.attached = take.attached + 1
    current.batch.attachments = current.batch.attachments + 1
    if take.attached == take.parts and not take.failed then
        current.batch.items = current.batch.items + 1
    end
    join(current.batch, arrival.mail)
end

local step

local function later(current)
    C_Timer.After(Forwarder.LOOK, function()
        step(current)
    end)
end

--- Wait on something: looked at again each LOOK until it has happened,
-- or MAX_LOOKS have gone by.
local function wait(current, waiting)
    waiting.looks = waiting.looks or 0
    current.waiting = waiting
    later(current)
end

local function arrived(before)
    local total = 0
    for _, arrival in ipairs(ns.Bags.Arrivals(before)) do
        total = total + arrival.count
    end
    return total
end

local function check(waiting)
    local kind = waiting.kind
    if kind == "money" or kind == "item" then
        return ns.Inbox.Answered(waiting)
    elseif kind == "arrive" then
        local total = arrived(waiting.before)
        return total > 0 and total >= waiting.expected
    elseif kind == "split" then
        local item = ns.Bags.Item(waiting.bag, waiting.slot)
        return item ~= nil and item.id == waiting.arrival.id and item.count == waiting.arrival.count
            and not item.locked
    elseif kind == "attach" then
        return ns.Guarded(function()
            return HasSendMailItem(waiting.index) and true or false
        end, false)
    elseif kind == "unlock" then
        local item = ns.Bags.Item(waiting.arrival.bag, waiting.arrival.slot)
        return item == nil or not item.locked
    end
    return true
end

--- The items a take put in the bags, all of them or, when the bags never
-- caught up, what came: each stack it landed in, to go on the tab.
local function collect(current, arrive)
    local arrivals = ns.Bags.Arrivals(arrive.before)
    local take = { parts = #arrivals, attached = 0 }
    if #arrivals == 0 then
        unmailable(current, { take = take })
    end
    for _, arrival in ipairs(arrivals) do
        arrival.mail = arrive.mail
        arrival.take = take
        current.pending[#current.pending + 1] = arrival
    end
end

--- What an answer, or the lack of one, changes.
local function settle(current, waiting, done)
    local kind = waiting.kind
    if kind == "money" or kind == "item" then
        if not done then
            -- The server never answered: leave this mail, still ticked.
            current.unanswered = current.unanswered + 1
            current.at = current.at + 1
            return
        end
        if waiting.removed then
            -- Gone from the box: its tick goes, and the alike mails below
            -- move up a number with theirs.
            ns.Ticks.Removed(waiting.key)
            current.at = current.at + 1
        end
        if kind == "money" then
            current.batch.gold = current.batch.gold + waiting.money
            join(current.batch, waiting.mail)
            return
        end
        -- Gone from the mail, but the bags can show it a moment later.
        local arrive = { kind = "arrive", before = waiting.before, expected = waiting.expected, mail = waiting.mail }
        if check(arrive) then
            collect(current, arrive)
        else
            wait(current, arrive)
        end
        return
    end

    if kind == "arrive" then
        collect(current, waiting)
        return
    end

    local arrival = waiting.arrival
    if kind == "split" then
        table.remove(current.pending, 1)
        if done then
            -- The part split off is now a stack of its own, to put on whole.
            table.insert(current.pending, 1, {
                bag = waiting.bag, slot = waiting.slot, id = arrival.id, count = arrival.count,
                mail = arrival.mail, take = arrival.take,
            })
        else
            ns.Guarded(ClearCursor)
            unmailable(current, arrival)
        end
    elseif kind == "attach" then
        table.remove(current.pending, 1)
        if done then
            attached(current, arrival)
        else
            ns.Guarded(ClearCursor)
            unmailable(current, arrival)
        end
    elseif kind == "unlock" and not done then
        table.remove(current.pending, 1)
        unmailable(current, arrival)
    end
end

--- Put the first item still in the bags on the Send Mail tab: whole when
-- the stack is just what came, or split off first when the take topped up
-- a stack of the player's own. True when it is now waiting on something.
local function placeNext(current)
    local arrival = current.pending[1]
    local item = ns.Bags.Item(arrival.bag, arrival.slot)
    if not item or item.id ~= arrival.id or item.bound then
        -- Moved away, or soulbound: it stays in the bags.
        table.remove(current.pending, 1)
        unmailable(current, arrival)
        return false
    end
    if item.locked then
        wait(current, { kind = "unlock", arrival = arrival })
        return true
    end

    local index = freeSendSlot()
    if not index then
        ready(current, "tab")
        return true
    end

    if item.count > arrival.count then
        local bag, slot = ns.Bags.EmptySlot()
        if not bag then
            ready(current, "bags")
            return true
        end
        C_Container.SplitContainerItem(arrival.bag, arrival.slot, arrival.count)
        C_Container.PickupContainerItem(bag, slot)
        wait(current, { kind = "split", arrival = arrival, bag = bag, slot = slot })
        return true
    end

    C_Container.PickupContainerItem(arrival.bag, arrival.slot)
    ClickSendMailItemButton(index)
    if ns.Guarded(function() return CursorHasItem() end, false) then
        -- The game would not take it, and left it on the cursor.
        ns.Guarded(ClearCursor)
        table.remove(current.pending, 1)
        unmailable(current, arrival)
        return false
    end
    wait(current, { kind = "attach", arrival = arrival, index = index })
    return true
end

--- Take from the next mail: its gold, then each item. True when it is
-- now waiting on something.
local function takeNext(current)
    local key = current.targets[current.at]
    if not key then
        ready(current, nil, true)
        return true
    end

    local mail = ns.Inbox.Find(key)
    local slot = mail and ns.Inbox.FirstAttachment(mail.index)
    if not mail then
        current.at = current.at + 1
    elseif mail.cod > 0 then
        current.cod = current.cod + 1
        ns.Ticks.Set(key, false)
        current.at = current.at + 1
    elseif mail.money > 0 then
        current.touched[key] = true
        local watch = ns.Inbox.Watch(key, mail, "money")
        watch.mail = about(mail)
        TakeInboxMoney(mail.index)
        wait(current, watch)
        return true
    elseif slot then
        if not freeSendSlot() then
            ready(current, "tab")
            return true
        end
        if ns.Inbox.FreeSlots() <= 0 then
            ready(current, "bags")
            return true
        end
        current.touched[key] = true
        local watch = ns.Inbox.Watch(key, mail, "item", slot)
        watch.mail = about(mail)
        watch.before = ns.Bags.Snapshot()
        watch.expected = ns.Inbox.AttachmentCount(mail.index, slot)
        TakeInboxItem(mail.index, slot)
        wait(current, watch)
        return true
    else
        -- Nothing left in it. One that never held anything goes as a letter.
        if not current.touched[key] then
            join(current.batch, about(mail))
        end
        ns.Ticks.Set(key, false)
        current.at = current.at + 1
    end
    return false
end

step = function(current)
    if run ~= current or current.ready then
        return
    end

    local waiting = current.waiting
    if waiting then
        local done = check(waiting)
        if not done and waiting.looks < Forwarder.MAX_LOOKS then
            waiting.looks = waiting.looks + 1
            later(current)
            return
        end
        current.waiting = nil
        settle(current, waiting, done)
    end

    while run == current and not current.ready and not current.waiting do
        local busy
        if current.pending[1] then
            busy = placeNext(current)
        else
            busy = takeNext(current)
        end
        if busy then
            return
        end
    end
end

local function start(mails, letter)
    if ns.Busy() or #mails == 0 then
        return false
    end

    local targets = {}
    for index = #mails, 1, -1 do
        targets[#targets + 1] = mails[index].key
    end
    run = {
        targets = targets,
        at = 1,
        letter = letter or "",
        to = saved().lastRecipient,
        batch = newBatch(),
        pending = {},
        touched = {},
        counted = {},
        forwarded = 0,
        gold = 0,
        items = 0,
        cod = 0,
        unmailable = 0,
        unanswered = 0,
    }

    if MailFrameTab_OnClick then
        MailFrameTab_OnClick(nil, 2)
    end
    if textOf(SendMailNameEditBox) == "" and run.to then
        setText(SendMailNameEditBox, run.to)
    end
    ns.Changed()
    step(run)
    return true
end

--- The mail open beside the inbox, or nil.
function Forwarder.OpenMail()
    local index = InboxFrame and InboxFrame.openMailID
    if type(index) ~= "number" then
        return nil
    end
    for _, mail in ipairs(ns.Inbox.Mails()) do
        if mail.index == index then
            return mail
        end
    end
    return nil
end

--- Forward the ticked mails. False when nothing is ticked, or Open or a
-- forward is already going.
function Forwarder.ForwardTicked()
    return start(ns.Ticks.Mails())
end

--- Forward the open mail, with its text. False for a cash-on-delivery
-- mail, or when Open or a forward is already going.
function Forwarder.ForwardOpen()
    local mail = Forwarder.OpenMail()
    if not mail or mail.cod > 0 then
        return false
    end
    return start({ mail }, letterOf(mail.index))
end

--- A mail went. If it was the one a forward made, count it and fill the
-- next, or end.
local function sent(current)
    if not current.ready then
        return
    end
    local batch = current.batch
    if type(lastSentTo) == "string" and lastSentTo ~= "" then
        current.to = lastSentTo
        saved().lastRecipient = lastSentTo
    end
    for _, mail in ipairs(batch.mails) do
        if not current.counted[mail.key] then
            current.counted[mail.key] = true
            current.forwarded = current.forwarded + 1
        end
    end
    current.gold = current.gold + batch.gold
    current.items = current.items + batch.items
    current.batch = newBatch()
    current.ready = false
    if current.last then
        finish(current)
        return
    end
    -- After the game has emptied the tab.
    later(current)
end

--- The mailbox closed: stop, and say what is left, and that what was
-- taken for a mail never sent is with the player.
function Forwarder.Stop()
    if not run then
        return
    end
    local count = left(run)
    local unsent = run.batch.gold > 0 or run.batch.attachments > 0 or #run.pending > 0
    local parts = {}
    if count > 0 then
        parts[#parts + 1] = string.format("Mailbox closed: %s left.", ns.Count(count, "mail"))
    else
        parts[#parts + 1] = "Mailbox closed before the mail went."
    end
    if unsent then
        parts[#parts + 1] = "What was taken for it is in your bags and purse."
    end
    finish(run, table.concat(parts, " "))
end

if hooksecurefunc and SendMail then
    hooksecurefunc("SendMail", function(recipient)
        lastSentTo = recipient
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:SetScript("OnEvent", function()
    if run then
        sent(run)
    end
end)
