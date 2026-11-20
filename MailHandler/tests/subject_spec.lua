local helpers = require("helpers")

-- A Send Mail tab, with real bags holding `stacks`: { name, count } each,
-- from the first slot on. Forever's unless `client` says "classic".
local function tab(stacks, client)
    local ns, env = helpers.loadAddon(function(env)
        if client ~= "classic" then
            helpers.forever(env)
        end
        helpers.bags(env, 16)
    end)
    for slot, stack in ipairs(stacks or {}) do
        env.__give(slot, stack[1], stack[2])
    end
    env.MailFrameTab_OnClick(nil, 2)
    return ns, env
end

local function subject(env)
    return env.SendMailSubjectEditBox:GetText()
end

local function attachAll(env, count)
    for slot = 1, count do
        helpers.attach(env, slot)
    end
end

describe("the subject of a mail you send", function()
    it("names the item on it, with its count, where Forever leaves the subject empty", function()
        local ns, env = tab({ { "Linen Cloth", 20 } })

        helpers.attach(env, 1)

        assertEqual("Linen Cloth (20)", subject(env))
    end)

    it("lets Send go once a name is typed", function()
        local ns, env = tab({ { "Linen Cloth", 20 } })
        helpers.attach(env, 1)

        env.SendMailNameEditBox:SetText("Brakka")
        assertTrue(env.SendMailMailButton:IsEnabled())
        helpers.pressSend(env)

        assertEqual(1, #env.__sent)
        assertEqual("Linen Cloth (20)", env.__sent[1].subject)
    end)

    it("names one of an item without a count", function()
        local ns, env = tab({ { "Hearthstone Rune", 1 } })

        helpers.attach(env, 1)

        assertEqual("Hearthstone Rune", subject(env))
    end)

    it("adds up the stacks of one item", function()
        local ns, env = tab({ { "Linen Cloth", 20 }, { "Linen Cloth", 5 } })

        attachAll(env, 2)

        assertEqual("Linen Cloth (25)", subject(env))
    end)

    it("names each item, in the order they went on", function()
        local ns, env = tab({ { "Silk Cloth", 12 }, { "Linen Cloth", 20 }, { "Spider Ichor", 1 } })

        attachAll(env, 3)

        assertEqual("Silk Cloth (12), Linen Cloth (20), Spider Ichor", subject(env))
    end)

    it("keeps to the 64 letters the box takes, and says how many more there are", function()
        local ns, env = tab({
            { "Chunk of Boar Meat", 3 }, { "Chunk of Boar Meat", 20 }, { "Chunk of Boar Meat", 20 },
            { "Chunk of Boar Meat", 5 }, { "Chunk of Boar Meat", 20 }, { "Chunk of Boar Meat", 9 },
            { "Lean Venison", 4 },
            { "Red Wolf Meat", 2 }, { "Red Wolf Meat", 14 }, { "Raptor Egg", 2 }, { "Red Wolf Meat", 20 },
        })

        attachAll(env, 11)

        assertEqual("Chunk of Boar Meat (77), Lean Venison (4) and 2 more", subject(env))
    end)

    it("says the gold of a mail that carries gold and no items", function()
        local ns, env = tab()

        helpers.typeMoney(env, 12345)

        assertEqual("1g 23s 45c", subject(env))
    end)

    it("names the items, not the gold, of a mail carrying both", function()
        local ns, env = tab({ { "Linen Cloth", 20 } })
        helpers.typeMoney(env, 500)

        helpers.attach(env, 1)

        assertEqual("Linen Cloth (20)", subject(env))
    end)

    it("follows the items as they come off, and is cleared with the last", function()
        local ns, env = tab({ { "Linen Cloth", 20 }, { "Silk Cloth", 12 } })
        attachAll(env, 2)
        env.SendMailNameEditBox:SetText("Brakka")

        env.__detach(1)
        assertEqual("Silk Cloth (12)", subject(env))

        env.__detach(2)
        assertEqual("", subject(env))
        assertFalse(env.SendMailMailButton:IsEnabled(), "no subject, no Send")
    end)

    it("leaves a letter's subject empty, for the player to write", function()
        local ns, env = tab()

        env.SendMailBodyEditBox:SetText("See you at the bank.")
        env.SendMailFrame_Update()

        assertEqual("", subject(env))
    end)

    it("leaves a subject the player typed, as items go on", function()
        local ns, env = tab({ { "Linen Cloth", 20 }, { "Silk Cloth", 12 } })
        env.SendMailSubjectEditBox:SetText("For your tailoring")

        attachAll(env, 2)
        helpers.typeMoney(env, 500)

        assertEqual("For your tailoring", subject(env))
    end)

    it("leaves a subject the player typed over its own", function()
        local ns, env = tab({ { "Linen Cloth", 20 }, { "Silk Cloth", 12 } })
        helpers.attach(env, 1)
        env.SendMailSubjectEditBox:SetText("Cloth")

        helpers.attach(env, 2)

        assertEqual("Cloth", subject(env))
    end)

    it("starts afresh once a mail has gone", function()
        local ns, env = tab({ { "Linen Cloth", 20 }, { "Silk Cloth", 12 } })
        helpers.typeMoney(env, 500)
        helpers.attach(env, 1)
        env.SendMailNameEditBox:SetText("Brakka")
        helpers.pressSend(env)
        assertEqual("", subject(env), "emptied with the tab")

        helpers.attach(env, 2)

        assertEqual("Silk Cloth (12)", subject(env))
    end)

    it("leaves the subject of a forward", function()
        local ns, env = tab()
        helpers.mail(env, "Aldira Moonclaw", "Linen Cloth (20)", 0, { [1] = { name = "Linen Cloth", count = 20 } })
        helpers.mail(env, "Aldira Moonclaw", "Silk Cloth (12)", 300, { [1] = { name = "Silk Cloth", count = 12 } })
        ns.Ticks.Set(ns.Inbox.Mails()[1].key, true)
        ns.Ticks.Set(ns.Inbox.Mails()[2].key, true)

        ns.Forwarder.ForwardTicked()
        env.__runAllTimers()

        assertEqual("FW: 2 mails", subject(env))
    end)

    describe("on Classic Era", function()
        it("names every item, where the game names only the first stack", function()
            local ns, env = tab({ { "Linen Cloth", 20 }, { "Silk Cloth", 12 }, { "Linen Cloth", 5 } }, "classic")

            attachAll(env, 3)

            assertEqual("Linen Cloth (25), Silk Cloth (12)", subject(env))
        end)

        it("leaves a subject the player typed", function()
            local ns, env = tab({ { "Linen Cloth", 20 } }, "classic")
            env.SendMailSubjectEditBox:SetText("For your tailoring")

            helpers.attach(env, 1)

            assertEqual("For your tailoring", subject(env))
        end)

        it("is cleared with the last item", function()
            local ns, env = tab({ { "Linen Cloth", 20 }, { "Silk Cloth", 12 } }, "classic")
            attachAll(env, 2)

            env.__detach(2)
            env.__detach(1)

            assertEqual("", subject(env))
        end)
    end)
end)
