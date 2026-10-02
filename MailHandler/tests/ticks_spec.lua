local helpers = require("helpers")

describe("a tick", function()
    it("ticks and unticks a mail", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        local key = ns.Inbox.Mails()[1].key

        ns.Ticks.Set(key, true)
        assertTrue(ns.Ticks.Is(key))

        ns.Ticks.Set(key, false)
        assertFalse(ns.Ticks.Is(key))
    end)

    it("stays on its mail when a mail above it goes", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        helpers.sale(env, "Lodestone", 11, 900)
        helpers.sale(env, "Copper Bar", 60, 2400)
        ns.Ticks.Set(ns.Inbox.Mails()[3].key, true)

        table.remove(env.__mails, 1)

        local ticked = ns.Ticks.Mails()
        assertEqual(1, #ticked)
        assertEqual("Auction successful: Copper Bar (60)", ticked[1].subject)
        assertEqual(2, ticked[1].index)
    end)

    it("is counted only while its mail is in the box", function()
        local ns, env = helpers.loadAddon()
        helpers.sale(env, "Rough Stone", 46, 1500)
        ns.Ticks.Set(ns.Inbox.Mails()[1].key, true)

        table.remove(env.__mails, 1)

        assertEqual(0, ns.Ticks.Count())
    end)
end)

describe("Select all", function()
    local function box(env, count)
        for index = 1, count do
            helpers.sale(env, "Stone " .. index, 1, 100)
        end
    end

    it("ticks every mail, on every page, and unticks them again", function()
        local ns, env = helpers.loadAddon()
        box(env, 10)

        ns.Ticks.SetAll(true)
        assertEqual(10, ns.Ticks.Count())

        ns.Ticks.SetAll(false)
        assertEqual(0, ns.Ticks.Count())
    end)

    it("shows ticked only while every mail is", function()
        local ns, env = helpers.loadAddon()
        assertFalse(ns.Ticks.AllTicked(), "an empty box")

        box(env, 10)
        ns.Ticks.SetAll(true)
        assertTrue(ns.Ticks.AllTicked())

        ns.Ticks.Set(ns.Inbox.Mails()[4].key, false)
        assertFalse(ns.Ticks.AllTicked())
    end)

    it("is forgotten, with every tick, when cleared", function()
        local ns, env = helpers.loadAddon()
        box(env, 3)
        ns.Ticks.SetAll(true)

        ns.Ticks.Clear()

        assertEqual(0, ns.Ticks.Count())
    end)
end)
