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
        return {
            index = index,
            sender = type(sender) == "string" and sender or "",
            subject = type(subject) == "string" and subject or "",
            money = type(money) == "number" and money or 0,
            cod = type(cod) == "number" and cod or 0,
            items = type(itemCount) == "number" and itemCount or 0,
        }
    end, nil)
end

--- Every mail, top to bottom. A key is the mail's sender, subject and cash
-- on delivery, which taking its gold and items does not change, numbered
-- among the mails alike in those above it: two equal sales are #1 and #2.
function Inbox.Mails()
    local mails, seen = {}, {}
    for index = 1, Inbox.Count() do
        local mail = header(index)
        if mail then
            local base = mail.sender .. "|" .. mail.subject .. "|" .. mail.cod
            seen[base] = (seen[base] or 0) + 1
            mail.key = base .. "#" .. seen[base]
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

function Inbox.HasAttachment(index, slot)
    return ns.Guarded(function()
        local name = GetInboxItem(index, slot)
        return type(name) == "string" and name ~= ""
    end, false)
end

function Inbox.FirstAttachment(index)
    for slot = 1, maxAttachments() do
        if Inbox.HasAttachment(index, slot) then
            return slot
        end
    end
    return nil
end

function Inbox.FreeSlots()
    local free = 0
    for bag = 0, lastBag() do
        free = free + ns.Guarded(function()
            local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
            local slots = get and get(bag)
            return type(slots) == "number" and slots or 0
        end, 0)
    end
    return free
end
