local helpers = require("helpers")

describe("the mailbox", function()
    it("gives each mail's sender, subject, gold, cash on delivery and items, top to bottom", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        helpers.expired(env, "Bronze Bar", 12, 2)

        local mails = ns.Inbox.Mails()

        assertEqual(2, #mails)
        assertEqual(1, mails[1].index)
        assertEqual("Alliance Auction House", mails[1].sender)
        assertEqual("Auction successful: Rough Stone (46)", mails[1].subject)
        assertEqual(1500, mails[1].money)
        assertEqual(0, mails[1].cod)
        assertEqual(0, mails[1].items)
        assertEqual(2, mails[2].items)
    end)

    it("gives each mail a key its gold and items do not change", function()
        local ns, env = helpers.loadAddon()
        local mail = helpers.expired(env, "Bronze Bar", 12, 2)
        mail.money = 100
        local before = ns.Inbox.Mails()[1].key

        mail.money = 0
        mail.items[1] = nil

        assertEqual(before, ns.Inbox.Mails()[1].key)
    end)

    it("tells alike mails apart by their order", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Copper Bar", 20, 500)
        helpers.sale(env, "Copper Bar", 20, 500)

        local mails = ns.Inbox.Mails()

        assertTrue(mails[1].key ~= mails[2].key)
        assertMatch("#1$", mails[1].key)
        assertMatch("#2$", mails[2].key)
    end)

    it("finds a mail by its key, and nothing for one that is gone", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        helpers.sale(env, "Lodestone", 11, 900)
        local key = ns.Inbox.Mails()[2].key

        assertEqual(2, ns.Inbox.Find(key).index)

        table.remove(env.__mails, 2)
        assertNil(ns.Inbox.Find(key))
    end)

    it("skips a mail it cannot read", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500).raises = true
        helpers.sale(env, "Lodestone", 11, 900)

        local mails = ns.Inbox.Mails()

        assertEqual(1, #mails)
        assertEqual(2, mails[1].index)
    end)

    it("finds a mail's first attachment, and none in an empty one", function()
        local ns, env = helpers.loadAddon()
        local mail = helpers.expired(env, "Bronze Bar", 12, 3)
        mail.items[1] = nil
        helpers.sale(env, "Lodestone", 11, 900)

        assertEqual(2, ns.Inbox.FirstAttachment(1))
        assertNil(ns.Inbox.FirstAttachment(2))
    end)

    it("counts free bag slots, through the old call too", function()
        local ns, env = helpers.loadAddon()
        env.__freeSlots = 7

        assertEqual(7, ns.Inbox.FreeSlots())

        local container = env.C_Container
        env.C_Container = nil
        env.GetContainerNumFreeSlots = container.GetContainerNumFreeSlots
        assertEqual(7, ns.Inbox.FreeSlots())
    end)
end)

describe("free bag slots", function()
    it("leave out a quiver's, which take only ammunition", function()
        local ns, env = helpers.loadAddon()
        env.__freeSlots = 0
        env.__quiverFree = 16

        assertEqual(0, ns.Inbox.FreeSlots())
    end)

    it("are the client's own count where it has one", function()
        local ns, env = helpers.loadAddon()
        env.C_Container.CalculateTotalNumberOfFreeBagSlots = function() return 3 end

        assertEqual(3, ns.Inbox.FreeSlots())
    end)
end)

describe("an attachment", function()
    it("is there by its item, whether or not its name has loaded", function()
        local ns, env = helpers.loadAddon()
        helpers.mail(env, "Garrok", "Stuff", 0, { [2] = { name = nil, count = 1 } })

        assertTrue(ns.Inbox.HasAttachment(1, 2))
        assertEqual(2, ns.Inbox.FirstAttachment(1))

        env.HasInboxItem = nil
        assertTrue(ns.Inbox.HasAttachment(1, 2), "by its item ID, on a client without HasInboxItem")
    end)
end)
