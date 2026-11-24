local helpers = require("helpers")

--- Log in as `name` (a warrior on Forever, Alliance, unless `who` says
-- otherwise), with the account's saved MailHandlerDB from before.
local function logIn(name, saved, who)
    local ns, env = helpers.loadAddon(function(env)
        env.__player.name = name
        for key, value in pairs(who or {}) do
            env.__player[key] = value
        end
        env.MailHandlerDB = saved
    end)
    helpers.login(env)
    return ns, env
end

--- An account where Bankalt (a priest) and Thorga (a druid) have logged
-- in before; then Skyler logs in.
local function account(setup)
    local _, first = logIn("Bankalt", nil, { class = "PRIEST" })
    local _, second = logIn("Thorga", first.MailHandlerDB, { class = "DRUID" })
    if setup then setup(second.MailHandlerDB) end
    return logIn("Skyler", second.MailHandlerDB)
end

local function names(list)
    local out = {}
    for index, character in ipairs(list) do
        out[index] = character.name
    end
    return table.concat(out, ", ")
end

local function openSendMail(env)
    helpers.openMailbox(env)
    env.MailFrameTab_OnClick(nil, 2)
end

local function arrow(ns)
    return ns.Recipient.button
end

local function openMenu(ns, env)
    arrow(ns):Click()
    return env.__menu
end

describe("your characters", function()
    it("are remembered as each logs in, and listed by name without you", function()
        local ns = account()

        assertEqual("Bankalt, Thorga", names(ns.Recipient.Characters()))
    end)

    it("are only those on your realm and side", function()
        local _, horde = logIn("Grukk", nil, { faction = "Horde" })
        local _, elsewhere = logIn("Faraway", horde.MailHandlerDB, { realm = "Other" })
        local ns = logIn("Skyler", elsewhere.MailHandlerDB)

        assertEqual("", names(ns.Recipient.Characters()))
    end)

    it("carry their class", function()
        local ns = account()

        assertEqual("PRIEST", ns.Recipient.Characters()[1].class)
    end)
end)

describe("names on WoW Forever", function()
    -- A Forever character has a first name and a surname, and a mail needs
    -- both: "Bankwoman Alyssa", not "Bankwoman".

    it("are noted in full, first name and surname", function()
        local _, bank = logIn("Bankwoman", nil, { surname = "Alyssa", class = "PRIEST" })
        local ns = logIn("Skyler", bank.MailHandlerDB, { surname = "Moonclaw" })

        assertEqual("Bankwoman Alyssa", names(ns.Recipient.Characters()))
    end)

    it("go in To in full", function()
        local _, bank = logIn("Bankwoman", nil, { surname = "Alyssa", class = "PRIEST" })
        local ns, env = logIn("Skyler", bank.MailHandlerDB, { surname = "Moonclaw" })
        openMenu(ns, env):Find("Bankwoman Alyssa").pick()

        openSendMail(env)

        assertEqual("Bankwoman Alyssa", env.SendMailNameEditBox:GetText())
    end)

    it("take the place of a first name noted before, and its default", function()
        -- Noted by an earlier MailHandler, which kept the first name only.
        local saved = {
            characters = { Forever = { Bankwoman = { faction = "Alliance", class = "PRIEST" } } },
            defaults = { ["Forever|Alliance"] = "Bankwoman" },
        }
        logIn("Bankwoman", saved, { surname = "Alyssa", class = "PRIEST" })
        local ns = logIn("Skyler", saved, { surname = "Moonclaw" })

        assertEqual("Bankwoman Alyssa", names(ns.Recipient.Characters()))
        assertEqual("Bankwoman Alyssa", ns.Recipient.Default())
    end)

    it("take the place of a first name noted before when the full name is picked from To", function()
        local saved = {
            characters = { Forever = { Bankwoman = { faction = "Alliance", class = "PRIEST" } } },
            defaults = { ["Forever|Alliance"] = "Bankwoman" },
        }
        local ns, env = logIn("Skyler", saved, { surname = "Moonclaw" })
        openSendMail(env)
        env.SendMailNameEditBox:SetText("Bankwoman Alyssa")

        openMenu(ns, env):Find("Bankwoman Alyssa").pick()

        assertEqual("Bankwoman Alyssa", names(ns.Recipient.Characters()), "one entry, in full")
        assertEqual("PRIEST", ns.Recipient.Characters()[1].class, "keeping its class")
        assertEqual("Bankwoman Alyssa", ns.Recipient.Default())
    end)

    it("never fill in your own, however it was noted", function()
        local saved = { defaults = { ["Forever|Alliance"] = "Bankwoman" } }
        local _, bank = logIn("Bankwoman", saved, { surname = "Alyssa", class = "PRIEST" })

        openSendMail(bank)

        assertEqual("", bank.SendMailNameEditBox:GetText())
    end)
end)

describe("the default", function()
    it("goes in To when the Send Mail tab opens", function()
        local ns, env = account()
        ns.Recipient.SetDefault("Bankalt")

        openSendMail(env)

        assertEqual("Bankalt", env.SendMailNameEditBox:GetText())
    end)

    it("is selected, so typing a name replaces it", function()
        local ns, env = account()
        ns.Recipient.SetDefault("Bankalt")

        openSendMail(env)

        assertTrue(env.SendMailNameEditBox.highlighted)
    end)

    it("leaves a name already in To", function()
        local ns, env = account()
        ns.Recipient.SetDefault("Bankalt")
        helpers.openMailbox(env)
        env.SendMailNameEditBox:SetText("Brakka")

        env.MailFrameTab_OnClick(nil, 2)

        assertEqual("Brakka", env.SendMailNameEditBox:GetText())
    end)

    it("goes in To again once a mail has gone", function()
        local ns, env = account()
        ns.Recipient.SetDefault("Bankalt")
        openSendMail(env)
        env.SendMailNameEditBox:SetText("Brakka")
        env.SendMailSubjectEditBox:SetText("Hello")

        helpers.pressSend(env)

        assertEqual("Brakka", env.__sent[1].to)
        assertEqual("Bankalt", env.SendMailNameEditBox:GetText())
    end)

    it("is shared by your characters on the realm", function()
        local _, env = account(function(saved) end)
        local ns = select(1, logIn("Skyler", env.MailHandlerDB))
        ns.Recipient.SetDefault("Bankalt")

        local other, otherEnv = logIn("Thorga", env.MailHandlerDB, { class = "DRUID" })
        openSendMail(otherEnv)

        assertEqual("Bankalt", otherEnv.SendMailNameEditBox:GetText())
    end)

    it("never fills in your own name", function()
        local _, env = account()
        local ns = logIn("Skyler", env.MailHandlerDB)
        ns.Recipient.SetDefault("Bankalt")

        local _, bank = logIn("Bankalt", env.MailHandlerDB, { class = "PRIEST" })
        openSendMail(bank)

        assertEqual("", bank.SendMailNameEditBox:GetText())
    end)

    it("leaves To empty when there is none", function()
        local _, env = account()

        openSendMail(env)

        assertEqual("", env.SendMailNameEditBox:GetText())
    end)
end)

describe("the arrow beside To", function()
    it("ends just before \"Postage:\", so it never covers it, whatever the postage", function()
        local ns, env = account()

        local point, relativeTo, relativePoint, x = arrow(ns):GetPoint(1)
        assertEqual("RIGHT", point)
        assertEqual(env.__postageLabel, relativeTo)
        assertEqual("LEFT", relativePoint)
        assertTrue(x < 0, "a gap before the label")
        assertTrue(arrow(ns):GetWidth() <= 18, "small enough to fit between the To box and the label")
    end)

    it("sits at the right end of the To box on a client without the postage label", function()
        local ns2, env2 = helpers.loadAddon(function(e)
            e.SendMailCostMoneyFrame = nil
        end)
        helpers.login(env2)

        local point, relativeTo, relativePoint = ns2.Recipient.button:GetPoint(1)
        assertEqual("LEFT", point)
        assertEqual(env2.SendMailNameEditBox, relativeTo)
        assertEqual("RIGHT", relativePoint)
    end)

    it("lists your characters, with the default picked", function()
        local ns, env = account()
        ns.Recipient.SetDefault("Thorga")

        local menu = openMenu(ns, env)

        assertTrue(menu:Find("Send new mail to") ~= nil, "titled")
        assertFalse(menu:Find("Bankalt").selected())
        assertTrue(menu:Find("Thorga").selected())
        assertFalse(menu:Find("Nobody").selected())
    end)

    it("writes each character in their class colour", function()
        local ns, env = account()

        local menu = openMenu(ns, env)

        assertMatch("^|cffffffffBankalt|r$", menu:Find("Bankalt").text)
        assertMatch("^|cffff7c0aThorga|r$", menu:Find("Thorga").text)
    end)

    it("makes the one you pick the default, and puts it in To", function()
        local ns, env = account()
        openSendMail(env)

        openMenu(ns, env):Find("Bankalt").pick()

        assertEqual("Bankalt", ns.Recipient.Default())
        assertEqual("Bankalt", env.SendMailNameEditBox:GetText())
    end)

    it("offers the name typed in To, for a character not seen yet", function()
        local ns, env = account()
        openSendMail(env)
        env.SendMailNameEditBox:SetText("Brakka")

        openMenu(ns, env):Find("Brakka").pick()

        assertEqual("Brakka", ns.Recipient.Default())
    end)

    it("leaves To empty by default when Nobody is picked", function()
        local ns, env = account()
        ns.Recipient.SetDefault("Bankalt")
        openSendMail(env)

        openMenu(ns, env):Find("Nobody").pick()

        assertNil(ns.Recipient.Default())
        assertEqual("", env.SendMailNameEditBox:GetText())
    end)

    it("says how to fill the list when no other character is known", function()
        local ns, env = logIn("Skyler")

        local menu = openMenu(ns, env)

        assertTrue(menu:Find("Log in on your other characters once, or type a name in To.") ~= nil)
    end)

    it("names the default on hover", function()
        local ns, env = account()
        ns.Recipient.SetDefault("Bankalt")

        arrow(ns):GetScript("OnEnter")(arrow(ns))

        assertEqual(arrow(ns), env.GameTooltip.owner)
        assertMatch("Bankalt", table.concat(env.GameTooltip.lines, "\n"))
    end)
end)

describe("forwarding", function()
    local function forwardOne(saved)
        local ns, env = helpers.loadAddon(function(env)
            helpers.bags(env, 16)
            env.MailHandlerDB = saved
        end)
        helpers.login(env)
        helpers.mail(env, "Aldira Moonclaw", "Linen Cloth (20)", 0, { [1] = { name = "Linen Cloth", count = 20 } })
        ns.Ticks.Set(ns.Inbox.Mails()[1].key, true)
        ns.Forwarder.ForwardTicked()
        env.__runAllTimers()
        return ns, env
    end

    it("goes to the default when this character has not forwarded before", function()
        local _, first = account()
        local ns = logIn("Skyler", first.MailHandlerDB)
        ns.Recipient.SetDefault("Bankalt")

        local _, env = forwardOne(first.MailHandlerDB)

        assertEqual("Bankalt", env.SendMailNameEditBox:GetText())
    end)

    it("goes to whom this character last forwarded to, default or not", function()
        local _, first = account()
        local ns = logIn("Skyler", first.MailHandlerDB)
        ns.Recipient.SetDefault("Bankalt")

        local fwd, env = helpers.loadAddon(function(env)
            helpers.bags(env, 16)
            env.MailHandlerDB = first.MailHandlerDB
            env.MailHandlerCharDB = { lastRecipient = "Brakka" }
        end)
        helpers.login(env)
        helpers.mail(env, "Aldira Moonclaw", "Linen Cloth (20)", 0, { [1] = { name = "Linen Cloth", count = 20 } })
        fwd.Ticks.Set(fwd.Inbox.Mails()[1].key, true)
        fwd.Forwarder.ForwardTicked()
        env.__runAllTimers()

        assertEqual("Brakka", env.SendMailNameEditBox:GetText())
    end)
end)

describe("the settings page", function()
    local function opened()
        local ns, env = account()
        ns.SettingsPanel.panel:Show()
        return ns, env, ns.SettingsPanel
    end

    it("names the default", function()
        local ns, env, panel = opened()
        ns.Recipient.SetDefault("Bankalt")

        assertEqual("New mail goes to:", panel.recipientLabel:GetText())
        assertEqual("Bankalt", panel.recipient:GetText())
    end)

    it("says Nobody without one", function()
        local _, _, panel = opened()

        assertEqual("Nobody", panel.recipient:GetText())
    end)

    it("changes it from the same list", function()
        local ns, env, panel = opened()

        panel.recipient:Click()
        env.__menu:Find("Thorga").pick()

        assertEqual("Thorga", ns.Recipient.Default())
        assertEqual("Thorga", panel.recipient:GetText())
    end)

    it("hangs the row 16 pixels under the description", function()
        local _, _, panel = opened()

        local point, relativeTo, relativePoint, _, y = panel.recipientLabel:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertEqual(panel.about, relativeTo)
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(-16, y)
    end)
end)
