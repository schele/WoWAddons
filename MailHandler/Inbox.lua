local addonName, ns = ...

-- What is in the mailbox: each mail's sender, subject, gold, cash on
-- delivery and items, and a key that stays with the mail while its gold and
-- items are taken. Reading only.

local Inbox = {}
ns.Inbox = Inbox

local function maxAttachments()
    return ATTACHMENTS_MAX_RECEIVE or 12
end

local function lastBag()
    return NUM_BAG_SLOTS or 4
end

function Inbox.Count()
    return ns.Guarded(function()
        local count = GetInboxNumItems()
        return type(count) == "number" and count or 0
    end, 0)
end

local function header(index)
    return ns.Guarded(function()
        local _, _, sender, subject, money, cod, _, itemCount = GetInboxHeaderInfo(index)
        if sender == nil and subject == nil then
            return nil
        end
        local mail = {
            index = index,
            sender = type(sender) == "string" and sender or "",
            subject = type(subject) == "string" and subject or "",
            money = type(money) == "number" and money or 0,
            cod = type(cod) == "number" and cod or 0,
            items = type(itemCount) == "number" and itemCount or 0,
        }
        mail.base = mail.sender .. "|" .. mail.subject .. "|" .. mail.cod
        return mail
    end, nil)
end

--- The mail at `index`, without its key: what an opening looks at to see
-- whether its own mail, at a place that does not move, has changed.
function Inbox.Header(index)
    return header(index)
end

--- Every mail, top to bottom. A key is the mail's sender, subject and cash
-- on delivery, which taking its gold and items does not change, numbered
-- among the mails alike in those above it: two equal sales are #1 and #2.
function Inbox.Mails()
    local mails, seen = {}, {}
    for index = 1, Inbox.Count() do
        local mail = header(index)
        if mail then
            seen[mail.base] = (seen[mail.base] or 0) + 1
            mail.key = mail.base .. "#" .. seen[mail.base]
            mails[#mails + 1] = mail
        end
    end
    return mails
end

function Inbox.Find(key)
    for _, mail in ipairs(Inbox.Mails()) do
        if mail.key == key then
            return mail
        end
    end
    return nil
end

--- Whether a mail's attachment slot holds an item, asked as the game's own
-- mail frame asks it: an item the client has not loaded yet has no name,
-- but is there all the same.
function Inbox.HasAttachment(index, slot)
    return ns.Guarded(function()
        if HasInboxItem then
            return HasInboxItem(index, slot) and true or false
        end
        local name, itemID = GetInboxItem(index, slot)
        return (type(itemID) == "number" and itemID > 0) or (type(name) == "string" and name ~= "")
    end, false)
end

--- What to watch after a take, to see when the server has answered it: the
-- mail's key, and its place and the size of the box, to see whether the
-- game has removed it. `kind` is "money" or "item".
function Inbox.Watch(key, mail, kind, slot)
    return {
        key = key,
        base = mail.base,
        index = mail.index,
        count = Inbox.Count(),
        kind = kind,
        slot = slot,
        looks = 0,
        -- The gold a money take is for: counted once the take is answered.
        money = mail.money,
    }
end

--- Whether the take being watched has been answered: the gold or the item
-- is gone from the mail, or the mail itself is. Looked for at the mail's
-- place, not by its key: once the game removes it, the next alike mail
-- below takes over its key. Working bottom up, its place stays put while
-- its own mail is there. Sets `removed` when the mail has gone.
function Inbox.Answered(watch)
    if Inbox.Count() < watch.count then
        watch.removed = true
        return true
    end
    local mail = header(watch.index)
    if not mail or mail.base ~= watch.base then
        watch.removed = true
        return true
    end
    if watch.kind == "money" then
        return mail.money == 0
    end
    return not Inbox.HasAttachment(watch.index, watch.slot)
end

--- How many of its item an attachment holds; 0 when unknown.
function Inbox.AttachmentCount(index, slot)
    return ns.Guarded(function()
        local _, _, _, count = GetInboxItem(index, slot)
        return type(count) == "number" and count or 0
    end, 0)
end

function Inbox.FirstAttachment(index)
    for slot = 1, maxAttachments() do
        if Inbox.HasAttachment(index, slot) then
            return slot
        end
    end
    return nil
end

--- Free slots that take any item: the client's own count where it has one,
-- as its Open All uses; otherwise general bags only, since a quiver's or a
-- soul bag's free slots refuse a mail's items.
function Inbox.FreeSlots()
    if C_Container and C_Container.CalculateTotalNumberOfFreeBagSlots then
        local total = ns.Guarded(function()
            return C_Container.CalculateTotalNumberOfFreeBagSlots()
        end, nil)
        if type(total) == "number" then
            return total
        end
    end

    local free = 0
    for bag = 0, lastBag() do
        free = free + ns.Guarded(function()
            local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
            if not get then
                return 0
            end
            local slots, bagType = get(bag)
            if type(slots) ~= "number" or (type(bagType) == "number" and bagType ~= 0) then
                return 0
            end
            return slots
        end, 0)
    end
    return free
end
