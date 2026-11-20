local addonName, ns = ...

-- The subject of a mail you send, written for you: the game will not send
-- a mail without one. Classic Era writes the first stack's name in by
-- itself, but only where cash on delivery is allowed, and Forever does not
-- allow it, so there the subject stays empty until typed. MailHandler
-- writes what the mail carries: every item with its count, or else its
-- gold. It follows the tab while the subject is still the one it wrote;
-- one the player typed, a reply's or a forward's is left alone.

local Subject = {}
ns.Subject = Subject

-- As many letters as the game's subject box takes.
Subject.MAX_LETTERS = 64

-- The subject MailHandler last wrote, to tell it from one typed over it.
local written

local function maxSend()
    return ATTACHMENTS_MAX_SEND or 12
end

-- Letters, not bytes: UTF-8 writes some letters of an item's name in two
-- or three.
local function letters(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

local function textOf(box)
    local text = box and box.GetText and box:GetText()
    return type(text) == "string" and text or ""
end

--- The items on the Send Mail tab, each once with its stacks added up, in
-- the order they went on: { name, count }. And how many stacks there are,
-- named or not.
local function itemsOnTab()
    local kinds, byName, stacks = {}, {}, 0
    for index = 1, maxSend() do
        local present = ns.Guarded(function()
            return HasSendMailItem(index) and true or false
        end, false)
        if present then
            stacks = stacks + 1
            local item = ns.Guarded(function()
                local name, _, _, count = GetSendMailItem(index)
                if type(name) ~= "string" or name == "" then
                    return nil
                end
                return { name = name, count = type(count) == "number" and count or 1 }
            end, nil)
            if item then
                local kind = byName[item.name]
                if not kind then
                    kind = { name = item.name, count = 0 }
                    byName[item.name] = kind
                    kinds[#kinds + 1] = kind
                end
                kind.count = kind.count + item.count
            end
        end
    end
    return kinds, stacks
end

--- The gold typed in to send; none when it is a cash on delivery price.
local function moneyToSend()
    return ns.Guarded(function()
        if SendMailCODButton and SendMailCODButton:GetChecked() then
            return 0
        end
        local copper = MoneyInputFrame_GetCopper(SendMailMoney)
        return type(copper) == "number" and copper or 0
    end, 0)
end

--- The subject for a mail carrying `kinds` of item ({ name, count }, in
-- order) in `stacks` stacks, and `copper` gold: each item with its count,
-- as many as fit and then how many more; or the gold; or "" for a letter.
function Subject.For(kinds, stacks, copper)
    if #kinds > 0 then
        local parts = {}
        for index, kind in ipairs(kinds) do
            parts[index] = kind.count > 1 and string.format("%s (%d)", kind.name, kind.count) or kind.name
        end
        for shown = #parts, 1, -1 do
            local text = table.concat(parts, ", ", 1, shown)
            if shown < #parts then
                text = string.format("%s and %d more", text, #parts - shown)
            end
            if shown == 1 or letters(text) <= Subject.MAX_LETTERS then
                return text
            end
        end
    end
    if stacks > 0 then
        return ns.Count(stacks, "item")
    end
    if copper > 0 then
        return ns.PlainMoney(copper)
    end
    return ""
end

--- Whether the subject is one to write over: empty, the one MailHandler
-- wrote, or the one Classic Era wrote by itself.
local function writable(text)
    if text == "" or text == written then
        return true
    end
    local previous = SendMailFrame and SendMailFrame.previousItem
    return type(previous) == "string" and previous ~= "" and text == previous
end

--- Write the subject for what is on the tab, unless one was typed, or a
-- forward is filling the tab with its own.
function Subject.Update()
    local box = SendMailSubjectEditBox
    if not box or (ns.Forwarder and ns.Forwarder.Running()) then
        return
    end
    local current = textOf(box)
    if not writable(current) then
        return
    end
    local kinds, stacks = itemsOnTab()
    local text = Subject.For(kinds, stacks, moneyToSend())
    if text ~= current then
        box:SetText(text)
    end
    -- As the box holds it, cut to its length if need be.
    written = textOf(box)
end

-- The game redraws the tab when an item goes on or comes off. Typing gold
-- changes no item, so the gold boxes are followed as well.
local hooked = false

local function hook()
    if hooked or not hooksecurefunc or not SendMailFrame_Update then
        return
    end
    hooked = true
    hooksecurefunc("SendMailFrame_Update", Subject.Update)
    for _, name in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }) do
        local box = _G[name]
        if box and box.HookScript then
            box:HookScript("OnTextChanged", Subject.Update)
        end
    end
end

-- The mail frame is in place before addons load; should it not be, it is
-- by the time the mailbox opens.
hook()
local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:SetScript("OnEvent", hook)
