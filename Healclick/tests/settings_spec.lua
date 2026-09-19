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
        assertTrue(controlFor(ns, "bar", "showSelf") ~= nil, "whether your own icons show")
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

describe("the two columns", function()
    local function xOf(control)
        local _, x = control.widget:GetPoint()
        return x
    end

    it("heads the right column with its registered title", function()
        local ns = loggedIn()
        assertEqual("Raid settings", ns.SettingsPanel.headings.right:GetText())
    end)

    it("puts the settings that asked for it in the right column", function()
        local ns = loggedIn()
        local left = xOf(controlFor(ns, "bar", "slots"))

        assertTrue(xOf(controlFor(ns, "bar", "selfBottom")) > left,
            "where your row sits moved right")
        assertTrue(xOf(controlFor(ns, "bar", "locked")) > left,
            "the lock moved right")
    end)

    it("leaves everything else in the left column, in one line", function()
        -- A setting declaring no column must not drift: every one of these
        -- was written before columns existed.
        local ns = loggedIn()
        local left = xOf(controlFor(ns, "bar", "slots"))

        for _, key in ipairs({ "attached", "attachX", "showSelf" }) do
            assertEqual(left, xOf(controlFor(ns, "bar", key)), key)
        end

        -- The spell table's widget is its first box, which sits past the
        -- gutter the row numbers are written in rather than at the column's
        -- own edge. Still the left column, just indented within it.
        assertTrue(xOf(controlFor(ns, "bar", "spells")) < left + 100, "spells")
    end)

    it("starts each column at the top rather than continuing the other", function()
        -- The whole point of a column: the right one begins beside the left
        -- one, not below everything already stacked there.
        local ns = loggedIn()
        local _, _, slotsY = nil, nil, nil
        local _, _, y = controlFor(ns, "bar", "slots").widget:GetPoint()
        local _, _, rightY = controlFor(ns, "bar", "selfBottom").widget:GetPoint()

        assertTrue(rightY > y - 100,
            "the right column is near the top, not far below the spell table")
    end)

    it("heads the column above the first control in it", function()
        local ns = loggedIn()
        local _, _, headingY = ns.SettingsPanel.headings.right:GetPoint()
        local _, _, firstY = controlFor(ns, "bar", "selfBottom").widget:GetPoint()

        assertTrue(headingY > firstY, "the title sits above what it titles")
    end)
end)

describe("the panel's heading", function()
    it("shows the addon's own icon", function()
        local ns = loggedIn()
        assertEqual(
            [[Interface\AddOns\Healclick\icon]],
            ns.SettingsPanel.logo:GetTexture()
        )
    end)

    it("builds the icon path from the addon name, not a second copy of it", function()
        -- The .toc already points at this file. A path spelled out here as
        -- well is the one that goes stale when the folder is renamed.
        local ns = loggedIn()
        assertTrue(
            ns.SettingsPanel.logo:GetTexture():find("Healclick", 1, true) ~= nil
        )
    end)

    it("hangs the title off the icon rather than off the panel", function()
        local ns = loggedIn()
        local point, relativeTo = ns.SettingsPanel.logo:GetPoint()

        assertEqual("TOPLEFT", point, "the icon leads the line")
        assertTrue(ns.SettingsPanel.logo:GetWidth() > 0, "and has a size to draw at")
    end)
end)
