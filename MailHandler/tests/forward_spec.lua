local helpers = require("helpers")

local ALDIRA = "Aldira Moonclaw"

-- A mailbox with real bags of `size` slots.
local function box(size, prepare)
    return helpers.loadAddon(function(env)
        helpers.bags(env, size or 16)
        if prepare then prepare(env) end
    end)
end

local function parcel(env, name, count, extra)
    local item = { name = name, count = count }
    for key, value in pairs(extra or {}) do item[key] = value end
    return helpers.mail(env, ALDIRA, string.format("%s (%d)", name, count), 0, { [1] = item })
end

local function tick(ns, ...)
    local mails = ns.Inbox.Mails()
    for _, index in ipairs({ ... }) do
        ns.Ticks.Set(mails[index].key, true)
    end
end

local function forwardTicked(ns, env)
    local started = ns.Forwarder.ForwardTicked()
    env.__runAllTimers()
    return started
end

describe("Forward (N)", function()
    it("puts the ticked mails' items on the Send Mail tab, oldest first, and leaves the others", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        parcel(env, "Silk Cloth", 12)
        parcel(env, "Spider Ichor", 2)
        tick(ns, 1, 3)

        assertTrue(forwardTicked(ns, env))

        assertEqual(2, env.__tab)
        assertEqual("Spider Ichor x2, Linen Cloth x20", helpers.attached(env))
        assertEqual("Silk Cloth", env.__mails[2].items[1].name)
    end)

    it("leaves Send to the player, and the mail goes to the name typed", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)

        forwardTicked(ns, env)
        assertEqual(0, #env.__sent)

        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)

        assertEqual(1, #env.__sent)
        assertEqual("Brakka", env.__sent[1].to)
        assertEqual("Linen Cloth", env.__sent[1].items[1].name)
        assertEqual(20, env.__sent[1].items[1].count)
    end)

    it("sends the ticked mails' gold as gold, never as cash on delivery", function()
        local ns, env = box()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        helpers.sale(env, "Copper Bar", 60, 300)
        env.__money = 1000
        env.SendMailRadioButton_OnClick(2)
        tick(ns, 1, 3)

        forwardTicked(ns, env)
        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)

        assertEqual(400, env.__sent[1].money)
        assertEqual(0, env.__sent[1].cod)
        assertEqual(200, env.__mails[2].money)
    end)

    it("names the one mail forwarded in the subject, and its sender in the text", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)

        forwardTicked(ns, env)

        assertEqual("FW: Linen Cloth (20)", env.SendMailSubjectEditBox:GetText())
        assertEqual("From Aldira Moonclaw: Linen Cloth (20)", env.__body())
    end)

    it("counts several mails in the subject and lists each in the text", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        helpers.sale(env, "Copper Bar", 60, 300)
        tick(ns, 1, 2)

        forwardTicked(ns, env)

        assertEqual("FW: 2 mails", env.SendMailSubjectEditBox:GetText())
        assertEqual(
            "From Alliance Auction House: Auction successful: Copper Bar (60)\n"
                .. "From Aldira Moonclaw: Linen Cloth (20)",
            env.__body()
        )
    end)

    it("sends just the mail's count of an item that topped up a stack of the player's own", function()
        local ns, env = box(16, function(env)
            env.__give(1, "Linen Cloth", 15)
        end)
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)

        forwardTicked(ns, env)
        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)

        local sent = 0
        for _, item in ipairs(env.__sent[1].items) do
            assertEqual("Linen Cloth", item.name)
            sent = sent + item.count
        end
        assertEqual(20, sent)
        assertEqual(15, env.__held("Linen Cloth"))
        assertNil(next(env.__uiErrors))
    end)

    it("waits for a slow server at every step", function()
        local ns, env = box(16, function(env)
            env.__give(1, "Linen Cloth", 15)
            env.__slowServer = true
        end)
        parcel(env, "Linen Cloth", 20)
        helpers.sale(env, "Copper Bar", 60, 300)
        tick(ns, 1, 2)

        forwardTicked(ns, env)
        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)

        assertEqual(300, env.__sent[1].money)
        local sent = 0
        for _, item in ipairs(env.__sent[1].items) do sent = sent + item.count end
        assertEqual(20, sent)
        assertEqual(15, env.__held("Linen Cloth"))
    end)

    it("waits for an item to show in the bags, which can come after the mail shows it gone", function()
        local ns, env = box(16, function(env)
            env.__give(1, "Linen Cloth", 15)
            env.__bagsLag = true
        end)
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)

        forwardTicked(ns, env)
        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)

        local sent = 0
        for _, item in ipairs(env.__sent[1].items) do sent = sent + item.count end
        assertEqual(20, sent)
        assertEqual(15, env.__held("Linen Cloth"))
        assertFalse(helpers.printed(env):find("could not be mailed", 1, true))
    end)

    it("fills the next mail once one has gone, to the same name, twelve items a mail", function()
        local ns, env = box(20)
        for index = 1, 14 do
            parcel(env, "Stone " .. index, 1)
        end
        ns.Ticks.SetAll(true)

        forwardTicked(ns, env)
        local onTab = 0
        for index = 1, 12 do
            if env.HasSendMailItem(index) then onTab = onTab + 1 end
        end
        assertEqual(12, onTab)
        assertMatch("Send", helpers.printed(env))

        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)

        assertEqual("Stone 2 x1, Stone 1 x1", helpers.attached(env))
        assertEqual("Brakka", env.SendMailNameEditBox:GetText())
        assertEqual("FW: 2 mails", env.SendMailSubjectEditBox:GetText())

        helpers.pressSend(env)
        assertEqual(2, #env.__sent)
        assertEqual("Brakka", env.__sent[2].to)
        assertEqual(2, #env.__sent[2].items)
        assertFalse(ns.Forwarder.Running())
    end)

    it("fills a mail with what fits when the bags fill, and goes on once it has gone", function()
        local ns, env = box(2)
        parcel(env, "Dark Leather Cloak", 1, { stack = 1 })
        parcel(env, "Lean Wolf Flank", 4)
        parcel(env, "Spider Ichor", 2)
        ns.Ticks.SetAll(true)

        forwardTicked(ns, env)
        assertEqual("Spider Ichor x2, Lean Wolf Flank x4", helpers.attached(env))

        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)
        assertEqual("Dark Leather Cloak x1", helpers.attached(env))

        helpers.pressSend(env)
        assertEqual(2, #env.__sent)
        assertFalse(ns.Forwarder.Running())
    end)

    it("stops when the bags are full and nothing is on the tab to send", function()
        local ns, env = box(1, function(env)
            env.__give(1, "Hearthstone", 1, 1)
        end)
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)

        forwardTicked(ns, env)

        assertFalse(ns.Forwarder.Running())
        assertEqual("", helpers.attached(env))
        assertMatch("Bags are full", helpers.printed(env))
    end)

    it("skips a cash-on-delivery mail, and says so", function()
        local ns, env = box()
        helpers.mail(env, "Garrok", "Linen", 0, { [1] = { name = "Linen Cloth", count = 20 } }, 500)
        parcel(env, "Silk Cloth", 12)
        ns.Ticks.SetAll(true)

        forwardTicked(ns, env)
        assertEqual("Silk Cloth x12", helpers.attached(env))

        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)
        assertEqual("Linen Cloth", env.__mails[1].items[1].name)
        assertMatch("Skipped 1 cash%-on%-delivery mail", helpers.printed(env))
    end)

    it("leaves an item that cannot be mailed in the bags, and says so", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        parcel(env, "Tabard of the Hand", 1, { stack = 1, bound = true })
        ns.Ticks.SetAll(true)

        forwardTicked(ns, env)
        assertEqual("Linen Cloth x20", helpers.attached(env))
        assertFalse(env.CursorHasItem())

        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)
        assertEqual(1, env.__held("Tabard of the Hand"))
        assertMatch("1 item could not be mailed", helpers.printed(env))
    end)

    it("says what went, and to whom, once the last mail has gone", function()
        local ns, env = box()
        env.__money = 1000
        parcel(env, "Linen Cloth", 20)
        helpers.sale(env, "Copper Bar", 60, 400)
        ns.Ticks.SetAll(true)

        forwardTicked(ns, env)
        assertFalse(helpers.printed(env):find("Forwarded", 1, true))

        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)

        assertMatch("Forwarded 2 mails to Brakka: 4s, 1 item%.", helpers.printed(env))
    end)

    it("unticks each mail once forwarded", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        parcel(env, "Silk Cloth", 12)
        ns.Ticks.SetAll(true)

        forwardTicked(ns, env)

        assertEqual(0, ns.Ticks.Count())
    end)

    it("stops when the mailbox closes, and says how many are left", function()
        local ns, env = box(16, function(env)
            env.__slowServer = true
        end)
        parcel(env, "Linen Cloth", 20)
        parcel(env, "Silk Cloth", 12)
        parcel(env, "Spider Ichor", 2)
        ns.Ticks.SetAll(true)
        helpers.openMailbox(env)

        ns.Forwarder.ForwardTicked()
        env.__runTimers()
        helpers.closeMailbox(env)

        assertFalse(ns.Forwarder.Running())
        assertMatch("Mailbox closed: 3 mails left", helpers.printed(env))
    end)

    it("says, when the mailbox closes before Send, that what was taken is with the player", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)
        helpers.openMailbox(env)

        forwardTicked(ns, env)
        helpers.closeMailbox(env)

        assertFalse(ns.Forwarder.Running())
        assertMatch("Mailbox closed before the mail went", helpers.printed(env))
        assertMatch("in your bags", helpers.printed(env))
    end)

    it("says, when the mailbox closes between mails, how many are left and that what was taken is with the player", function()
        local ns, env = box(20)
        for index = 1, 14 do
            parcel(env, "Stone " .. index, 1)
        end
        ns.Ticks.SetAll(true)
        helpers.openMailbox(env)

        forwardTicked(ns, env)
        helpers.closeMailbox(env)

        assertMatch("Mailbox closed: 2 mails left%.", helpers.printed(env))
        assertMatch("in your bags", helpers.printed(env))
    end)

    it("says nothing was taken when the mailbox closes on a letter", function()
        local ns, env = box()
        local mail = helpers.mail(env, ALDIRA, "Hello")
        mail.text = "See you in Ironforge."
        helpers.openMailbox(env)
        helpers.openMail(env, 1)

        ns.Forwarder.ForwardOpen()
        env.__runAllTimers()
        helpers.closeMailbox(env)

        assertMatch("Mailbox closed before the mail went%.", helpers.printed(env))
        assertFalse(helpers.printed(env):find("in your bags", 1, true))
    end)

    it("writes in the name last forwarded to, on this character", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        parcel(env, "Silk Cloth", 12)
        tick(ns, 1)

        forwardTicked(ns, env)
        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)
        assertEqual("Brakka", env.MailHandlerCharDB.lastRecipient)

        tick(ns, 2)
        forwardTicked(ns, env)
        assertEqual("Brakka", env.SendMailNameEditBox:GetText())
    end)

    it("writes in the name saved from an earlier session", function()
        local ns, env = box(16, function(env)
            env.MailHandlerCharDB = { lastRecipient = "Brakka" }
        end)
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)

        forwardTicked(ns, env)

        assertEqual("Brakka", env.SendMailNameEditBox:GetText())
    end)

    it("keeps a name the player has typed already", function()
        local ns, env = box(16, function(env)
            env.MailHandlerCharDB = { lastRecipient = "Brakka" }
        end)
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)
        env.SendMailNameEditBox:SetText("Thorga")

        forwardTicked(ns, env)

        assertEqual("Thorga", env.SendMailNameEditBox:GetText())
    end)

    it("does not remember the name of a mail sent without forwarding", function()
        local _, env = box()

        env.SendMailNameEditBox:SetText("Thorga")
        helpers.pressSend(env)

        assertNil(env.MailHandlerCharDB and env.MailHandlerCharDB.lastRecipient)
    end)

    it("does nothing with no mail ticked", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)

        assertFalse(forwardTicked(ns, env))
        assertEqual(1, env.__tab)
    end)

    it("waits for Open to finish", function()
        local ns, env = box(16, function(env)
            env.__slowServer = true
        end)
        parcel(env, "Linen Cloth", 20)
        parcel(env, "Silk Cloth", 12)
        tick(ns, 1)
        ns.Opener.Start()
        tick(ns, 2)

        assertFalse(ns.Forwarder.ForwardTicked())
    end)

    it("keeps Open waiting until the forward has gone", function()
        local ns, env = box()
        parcel(env, "Linen Cloth", 20)
        parcel(env, "Silk Cloth", 12)
        tick(ns, 1)
        forwardTicked(ns, env)
        tick(ns, 2)

        assertFalse(ns.Opener.Start())
        assertEqual("Silk Cloth", env.__mails[2].items[1].name)
    end)

    it("puts the text in Forever's mail text box", function()
        local ns, env = box(16, helpers.forever)
        parcel(env, "Linen Cloth", 20)
        tick(ns, 1)

        forwardTicked(ns, env)

        assertEqual("From Aldira Moonclaw: Linen Cloth (20)", env.SendMailBodyEditBox:GetText())
    end)
end)

describe("Forward on an open mail", function()
    it("puts that mail's items on the Send Mail tab, with its text, whatever is ticked", function()
        local ns, env = box()
        parcel(env, "Silk Cloth", 12)
        local mail = parcel(env, "Linen Cloth", 20)
        mail.text = "Here you go."
        tick(ns, 1)
        helpers.openMail(env, 2)

        assertTrue(ns.Forwarder.ForwardOpen())
        env.__runAllTimers()

        assertEqual(2, env.__tab)
        assertEqual("Linen Cloth x20", helpers.attached(env))
        assertEqual("FW: Linen Cloth (20)", env.SendMailSubjectEditBox:GetText())
        assertEqual("From Aldira Moonclaw: Linen Cloth (20)\n\nHere you go.", env.__body())
    end)

    it("writes out what an auction house invoice says", function()
        local ns, env = box()
        local mail = helpers.mail(env, "Alliance Auction House", "Auction won: Bronze Tube", 0,
            { [1] = { name = "Bronze Tube", count = 1 } })
        mail.invoice = { type = "buyer", item = "Bronze Tube", player = "Eolem Sanctelame", bid = 470 }
        helpers.openMail(env, 1)

        ns.Forwarder.ForwardOpen()
        env.__runAllTimers()

        assertEqual(
            "From Alliance Auction House: Auction won: Bronze Tube\n\n"
                .. "Item Purchased: Bronze Tube\nSold By: Eolem Sanctelame",
            env.__body()
        )
    end)

    it("sends a mail with only text as a letter", function()
        local ns, env = box()
        local mail = helpers.mail(env, ALDIRA, "Hello")
        mail.text = "See you in Ironforge."
        helpers.openMail(env, 1)

        ns.Forwarder.ForwardOpen()
        env.__runAllTimers()
        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)

        assertEqual("FW: Hello", env.__sent[1].subject)
        assertEqual("From Aldira Moonclaw: Hello\n\nSee you in Ironforge.", env.__sent[1].body)
        assertFalse(ns.Forwarder.Running())
    end)

    it("will not forward a cash-on-delivery mail", function()
        local ns, env = box()
        helpers.mail(env, "Garrok", "Linen", 0, { [1] = { name = "Linen Cloth", count = 20 } }, 500)
        helpers.openMail(env, 1)

        assertFalse(ns.Forwarder.ForwardOpen())
        assertEqual(1, env.__tab)
    end)
end)
