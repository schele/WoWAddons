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
        assertTrue(controlFor(ns, "bar", "attached") ~= nil, "where the icons live")
        assertTrue(controlFor(ns, "bar", "attachX") ~= nil, "how far across")
        assertTrue(controlFor(ns, "bar", "attachY") ~= nil, "how far up")
    end)

    it("lets the attach offsets go negative, so the icons can sit left of the frame", function()
        -- A slider that bottoms out at zero would only ever put the icons on
        -- one side of the unit frame.
        local ns = loggedIn()

        assertTrue(controlFor(ns, "bar", "attachX").setting.min < 0)
        assertTrue(controlFor(ns, "bar", "attachY").setting.min < 0)
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

    -- An EditBox grabs focus as it comes into existence, so SetAutoFocus(false)
    -- is a line too late to prevent it. Left alone, the last row built stays
    -- focused, and the player's next click anywhere silently re-stores its
    -- text and re-applies -- exactly the bug ForeverPanel's key table already
    -- guards against for the same reason.
    it("drops keyboard focus from every row as it is built", function()
        local ns = loggedIn()
        local boxes = controlFor(ns, "bar", "spells").boxes

        for index, box in ipairs(boxes) do
            assertFalse(box.focused, "row " .. index .. " does not hold focus")
        end
    end)

    it("stores what is typed into a row", function()
        local ns = loggedIn()
        local boxes = controlFor(ns, "bar", "spells").boxes

        -- A different spell than the seed already sitting in slot 2, so a
        -- store that never actually ran (e.g. because the box never regained
        -- focus, as EnsureBuilt now leaves it) cannot pass by coincidence.
        boxes[2]:SetFocus()
        boxes[2]:SetText("Healing Touch")
        boxes[2].scripts.OnEnterPressed(boxes[2])

        assertEqual("Healing Touch", ns.Slots.Spell(2))
    end)

    it("keeps a spell the character has not learned, and says so", function()
        local ns, env = loggedIn()
        local boxes = controlFor(ns, "bar", "spells").boxes

        boxes[3]:SetFocus()
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

        box:SetFocus()
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
        -- Boxes start unfocused since Fix 4 (Settings.lua's ClearFocus at
        -- build time); without simulating the player having clicked into
        -- this one first, OnEscapePressed's own ClearFocus() is a no-op and
        -- the reverting guard below is never actually exercised.
        box:SetFocus()

        box:SetText("Regrowth")
        local before = helpers.printed(env)

        box.scripts.OnEscapePressed(box)

        assertEqual("Tranquility", box:GetText(), "reverted to what was stored")
        assertEqual("Tranquility", ns.Slots.Spell(6), "the typed edit was discarded")
        assertEqual(before, helpers.printed(env), "no warning printed for the discarded edit")
    end)

    -- Without this, the box for the slot a drop just landed in still shows
    -- whatever was there before -- and losing focus afterward is exactly
    -- what stores that stale text back over the drop.
    it("refreshes so a stale box does not overwrite a drop that just landed", function()
        local ns, env = loggedIn()
        local box = controlFor(ns, "bar", "spells").boxes[2]

        local row = helpers.rowFor(ns, "party1")
        env.__cursor = { "spell", 5, "spell" }
        row.buttons[2].scripts.OnReceiveDrag(row.buttons[2])

        assertEqual("Regrowth", box:GetText(), "the box reflects the drop immediately")

        box.scripts.OnEditFocusLost(box)
        assertEqual("Regrowth", ns.Slots.Spell(2), "the drop survives the box losing focus afterward")
    end)
end)
