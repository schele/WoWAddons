local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)
    ns.SettingsPanel.EnsureBuilt()
    return ns, env
end

local function controlFor(ns, store, key)
    for _, control in ipairs(ns.SettingsPanel.controls) do
        if control.setting.store == store and control.setting.key == key then
            return control
        end
    end
end

describe("the declared settings", function()
    it("declares one for each thing the panel offers", function()
        local ns = loggedIn()

        assertTrue(controlFor(ns, "bar", "slots") ~= nil, "the count")
        assertTrue(controlFor(ns, "bar", "selfBottom") ~= nil, "where your row sits")
        assertTrue(controlFor(ns, "bar", "spells") ~= nil, "the spells")
        assertTrue(controlFor(ns, "bar", "locked") ~= nil, "the lock")
    end)
end)

describe("the panel", function()
    it("registers itself with the game's options", function()
        local ns, env = loggedIn()
        assertTrue(env.__settingsCategory ~= nil)
    end)

    it("builds once, however often it is asked", function()
        local ns = loggedIn()
        local before = #ns.SettingsPanel.controls

        ns.SettingsPanel.EnsureBuilt()
        assertEqual(before, #ns.SettingsPanel.controls)
    end)

    it("opens from /hc settings", function()
        local ns, env = loggedIn()
        helpers.command(env, "settings")

        assertEqual("category-id", env.__openedCategory)
    end)

    -- Opening the panel this way leaves the client queued to fall back to the
    -- game menu when it closes, which is not where the player came from.
    it("does not leave the game menu behind when it closes", function()
        local ns, env = loggedIn()

        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)

        -- The client would show the game menu as part of closing our panel;
        -- the backstop C_Timer.After queued above is what turns it away.
        env.__runTimers()

        assertFalse(env.GameMenuFrame:IsShown(), "turned away before a frame was drawn")
    end)

    it("leaves the game menu alone when the player opened it themselves", function()
        local ns, env = loggedIn()

        -- Open and close once through our own command, so the hook is set up
        -- and that close has already settled.
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.__runTimers()

        -- Now the panel is reached through the game menu instead: closing it
        -- must not touch the game menu, because openedByUs is false this time.
        env.GameMenuFrame:Show()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.__runTimers()

        assertTrue(env.GameMenuFrame:IsShown(), "left where the client put it")
    end)
end)

describe("the slot count slider", function()
    it("writes through to the database", function()
        local ns = loggedIn()
        controlFor(ns, "bar", "slots").widget:SetValue(6)

        assertEqual(6, ns.db.bar.slots)
    end)

    it("applies the change to the rows", function()
        local ns = loggedIn()
        ns.Slots.Set(6, "Regrowth")

        controlFor(ns, "bar", "slots").widget:SetValue(6)

        assertTrue(helpers.rowFor(ns, "party1").buttons[6]:IsShown())
    end)
end)

describe("the spell table", function()
    it("has a row for every slot the maximum allows", function()
        local ns = loggedIn()
        assertEqual(ns.Slots.MAX, #controlFor(ns, "bar", "spells").boxes)
    end)

    it("stores what is typed into a row", function()
        local ns = loggedIn()
        local boxes = controlFor(ns, "bar", "spells").boxes

        boxes[2]:SetText("Rejuvenation")
        boxes[2].scripts.OnEnterPressed(boxes[2])

        assertEqual("Rejuvenation", ns.Slots.Spell(2))
    end)

    it("keeps a spell the character has not learned, and says so", function()
        local ns, env = loggedIn()
        local boxes = controlFor(ns, "bar", "spells").boxes

        boxes[3]:SetText("Tranquility")
        boxes[3].scripts.OnEnterPressed(boxes[3])

        assertEqual("Tranquility", ns.Slots.Spell(3))
        assertMatch("Tranquility", helpers.printed(env))
    end)

    it("shows what is already configured when it refreshes", function()
        local ns = loggedIn()
        ns.Slots.Set(4, "Regrowth")

        ns.SettingsPanel.Refresh()
        assertEqual("Regrowth", controlFor(ns, "bar", "spells").boxes[4]:GetText())
    end)

    -- OnEnterPressed and OnEditFocusLost used to both be bound to the same
    -- store function, and store ended by clearing its own focus -- which the
    -- client turns straight back into an OnEditFocusLost. One Enter press ran
    -- the store logic twice.
    it("stores exactly once when Enter is pressed", function()
        local ns, env = loggedIn()
        local box = controlFor(ns, "bar", "spells").boxes[5]

        box:SetText("Tranquility")
        box.scripts.OnEnterPressed(box)

        local _, count = helpers.printed(env):gsub("Tranquility", "Tranquility")
        assertEqual(1, count, "the unlearned-spell warning printed exactly once")
    end)

    -- Escape's own revert-then-ClearFocus used to trigger the very store
    -- logic it was trying to avoid, so opening a row that already holds an
    -- unlearned spell and pressing Escape without changing anything spammed
    -- the warning and reapplied for no reason.
    it("discards an edit and prints nothing when Escape is pressed", function()
        local ns, env = loggedIn()
        ns.Slots.Set(6, "Tranquility")

        local box = controlFor(ns, "bar", "spells").boxes[6]
        ns.SettingsPanel.Refresh()

        box:SetText("Regrowth")
        local before = helpers.printed(env)

        box.scripts.OnEscapePressed(box)

        assertEqual("Tranquility", box:GetText(), "reverted to what was stored")
        assertEqual("Tranquility", ns.Slots.Spell(6), "the typed edit was discarded")
        assertEqual(before, helpers.printed(env), "no warning printed for the discarded edit")
    end)
end)
