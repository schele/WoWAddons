local helpers = require("helpers")

local function tick(ns, ...)
    local mails = ns.Inbox.Mails()
    for _, index in ipairs({ ... }) do
        ns.Ticks.Set(mails[index].key, true)
    end
end

local function logged(env, entry)
    for _, line in ipairs(env.__log) do
        if line == entry then return true end
    end
    return false
end

describe("Open", function()
    it("takes the gold of the ticked mails only", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        helpers.sale(env, "Copper Bar", 60, 300)
        tick(ns, 1, 3)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(400, env.__money)
        assertEqual(200, env.__mails[2].money)
    end)

    it("takes every item of a ticked mail, one at a time, a pause apart", function()
        local ns, env = helpers.loadAddon()
        helpers.expired(env, "Bronze Bar", 12, 2)
        tick(ns, 1)

        ns.Opener.Start()
        assertEqual(1, #env.__log)
        assertEqual("item 1:1", env.__log[1])
        assertEqual(0.25, env.__timerDelays[1])

        env.__runTimers()
        assertEqual("item 1:2", env.__log[2])

        env.__runAllTimers()
        assertNil(next(env.__mails[1].items))
    end)

    it("takes the gold before the items", function()
        local ns, env = helpers.loadAddon()
        local mail = helpers.expired(env, "Bronze Bar", 12, 1)
        mail.money = 50
        tick(ns, 1)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual("money 1", env.__log[1])
        assertEqual("item 1:1", env.__log[2])
    end)

    it("never deletes a mail, and leaves an emptied one in the box", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.expired(env, "Bronze Bar", 12, 1)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(2, #env.__mails)
        for _, line in ipairs(env.__log) do
            assertFalse(line:find("delete", 1, true), line)
        end
    end)

    it("unticks each mail once it is opened", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(0, ns.Ticks.Count())
    end)

    it("works from the bottom up", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual("money 2", env.__log[1])
        assertEqual("money 1", env.__log[2])
    end)

    it("opens alike mails the game removes once empty, keeping the other's tick", function()
        local ns, env = helpers.loadAddon()
        env.__autoRemove = true
        helpers.sale(env, "Lodestone", 11, 900)
        helpers.sale(env, "Copper Bar", 20, 500)
        helpers.sale(env, "Copper Bar", 20, 500)
        tick(ns, 2, 3)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(1000, env.__money)
        assertEqual(1, #env.__mails)
        assertEqual(900, env.__mails[1].money)
    end)

    it("skips a cash-on-delivery mail and unticks it", function()
        local ns, env = helpers.loadAddon()
        helpers.mail(env, "Garrok", "Linen", 0, { [1] = { name = "Linen Cloth", count = 20 } }, 500)
        tick(ns, 1)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(0, #env.__log)
        assertEqual(0, ns.Ticks.Count())
        assertMatch("Skipped 1 cash%-on%-delivery mail%.", helpers.printed(env))
    end)

    it("stops when the bags are full, with the gold taken before", function()
        local ns, env = helpers.loadAddon()
        env.__freeSlots = 0
        helpers.expired(env, "Bronze Bar", 12, 1)
        helpers.sale(env, "Rough Stone", 46, 100)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(100, env.__money)
        assertFalse(logged(env, "item 1:1"))
        local printed = helpers.printed(env)
        assertMatch("Opened 1 mail: 1s%.", printed)
        assertMatch("Bags are full: 1 ticked mail left%.", printed)
    end)

    it("stops when the mailbox closes", function()
        local ns, env = helpers.loadAddon()
        helpers.expired(env, "Bronze Bar", 12, 2)
        helpers.expired(env, "Light Feather", 4, 2)
        tick(ns, 1, 2)

        ns.Opener.Start()
        ns.Opener.Stop()
        env.__runAllTimers()

        assertEqual(1, #env.__log)
        assertFalse(ns.Opener.Running())
        assertMatch("Mailbox closed: 2 ticked mails left%.", helpers.printed(env))
    end)

    it("waits for a server that answers late", function()
        local ns, env = helpers.loadAddon()
        env.__slowServer = true
        helpers.sale(env, "Rough Stone", 46, 100)
        helpers.sale(env, "Lodestone", 11, 200)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(300, env.__money)
        assertMatch("Opened 2 mails: 3s%.", helpers.printed(env))
    end)

    it("gives up a take the server never answers, and goes on", function()
        local ns, env = helpers.loadAddon()
        local lost = helpers.sale(env, "Rough Stone", 46, 100)
        lost.lost = true
        helpers.sale(env, "Lodestone", 11, 200)
        tick(ns, 1, 2)

        ns.Opener.Start()
        env.__runAllTimers()

        assertEqual(200, env.__money)
        assertFalse(ns.Opener.Running())
        assertTrue(ns.Ticks.Is(ns.Inbox.Mails()[1].key), "the mail given up stays ticked")
    end)

    it("says what it took in one line", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 10000)
        helpers.sale(env, "Lodestone", 11, 2304)
        helpers.expired(env, "Bronze Bar", 12, 1)
        helpers.expired(env, "Light Feather", 4, 2)
        tick(ns, 1, 2, 3, 4)

        ns.Opener.Start()
        env.__runAllTimers()

        assertMatch("^|cff66ccffMailHandler|r Opened 4 mails: 1g 23s 4c, 3 items%.$", helpers.printed(env))
    end)

    it("does nothing when Open is clicked while it runs", function()
        local ns, env = helpers.loadAddon()
        helpers.expired(env, "Bronze Bar", 12, 2)
        tick(ns, 1)

        assertTrue(ns.Opener.Start())
        assertFalse(ns.Opener.Start())

        assertEqual(1, #env.__log)
    end)
end)
