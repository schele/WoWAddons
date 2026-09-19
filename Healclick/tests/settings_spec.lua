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
        assertTrue(controlFor(ns, "bar", "iconSize") ~= nil, "how big the icons are")
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
        -- Moved to a count the bar is not already on, so the change is a
        -- real one: setting a slider to the value it already holds is not
        -- a change, and nothing downstream runs.
        local ns = loggedIn()
        ns.Slots.Set(8, "Regrowth")

        controlFor(ns, "bar", "slots").widget:SetValue(8)

        assertTrue(helpers.rowFor(ns, "party1").buttons[8]:IsShown())
    end)
end)

describe("the spell table", function()
    local function slotRows(ns)
        return controlFor(ns, "bar", "spells").slotRows
    end

    it("has a row for every slot the maximum allows", function()
        local ns = loggedIn()
        assertEqual(ns.Slots.MAX, #slotRows(ns))
    end)

    it("shows the spell a slot holds by name", function()
        local ns = loggedIn()
        ns.Slots.Set(4, "Regrowth")

        ns.SettingsPanel.Refresh()
        assertEqual("Regrowth", slotRows(ns)[4].label:GetText())
    end)

    it("shows that spell's own icon beside the name", function()
        -- Which spell a slot holds reads faster from its icon than from its
        -- name, the same reason the buttons themselves show icons.
        local ns = loggedIn()
        ns.Slots.Set(4, "Regrowth")

        ns.SettingsPanel.Refresh()
        assertEqual(136085, slotRows(ns)[4].icon:GetTexture())
        assertTrue(slotRows(ns)[4].icon:IsShown())
    end)

    it("leaves an empty slot blank, with no icon", function()
        local ns = loggedIn()
        ns.Slots.Set(4, "")

        ns.SettingsPanel.Refresh()
        assertEqual("", slotRows(ns)[4].label:GetText())
        assertFalse(slotRows(ns)[4].icon:IsShown())
    end)

    it("keeps showing a spell the character has not learned", function()
        -- Seeded slots can hold one, and a drop can put one there. The
        -- picker will not offer it, but the panel must still say it is what
        -- the slot holds rather than showing the row as empty.
        local ns = loggedIn()
        ns.Slots.Set(4, "Tranquility")

        ns.SettingsPanel.Refresh()
        assertEqual("Tranquility", slotRows(ns)[4].label:GetText())
    end)

    it("catches up with a spell dropped onto a button while it was open", function()
        local ns, env = loggedIn()

        local row = helpers.rowFor(ns, "party1")
        env.__cursor = { "spell", 5, "spell" }
        row.buttons[2].scripts.OnReceiveDrag(row.buttons[2])

        assertEqual("Regrowth", slotRows(ns)[2].label:GetText(),
            "the row reflects the drop immediately")
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

describe("picking a spell instead of typing one", function()
    local function withSpellbook()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Rejuvenation", "Healing Touch", "Mark of the Wild" })
        -- Emptied, because the seed fills the first four slots and a slot's
        -- spell is no longer offered to the others. The uniqueness tests
        -- below put spells back deliberately.
        for index = 1, ns.Slots.MAX do
            ns.Slots.Set(index, "")
        end
        ns.SettingsPanel.EnsureBuilt()
        return ns, env
    end

    local function openOn(ns, slot)
        local control = controlFor(ns, "bar", "spells")
        control.picks[slot].scripts.OnClick(control.picks[slot])
        return ns.SettingsPanel.picker
    end

    it("gives every slot row a Pick button", function()
        local ns = withSpellbook()
        local picks = controlFor(ns, "bar", "spells").picks

        assertEqual(ns.Slots.MAX, #picks)
    end)

    it("lists the spells the player knows, in order", function()
        local ns = withSpellbook()
        local picker = openOn(ns, 3)

        assertTrue(picker:IsShown())
        -- Entry 1 empties the slot; the spellbook starts at 2.
        assertEqual("Healing Touch", picker.buttons[2].label:GetText())
        assertEqual("Mark of the Wild", picker.buttons[3].label:GetText())
        assertEqual("Rejuvenation", picker.buttons[4].label:GetText())
    end)

    it("shows each spell's own icon beside its name", function()
        local ns = withSpellbook()
        local picker = openOn(ns, 1)

        assertTrue(picker.buttons[3].icon:IsShown())
    end)

    it("stores the spell that is clicked, on the row that opened the list", function()
        local ns = withSpellbook()
        local picker = openOn(ns, 3)

        picker.buttons[2].scripts.OnClick(picker.buttons[2])

        assertEqual("Healing Touch", ns.Slots.Spell(3))
    end)

    it("shows the new spell on the row straight away", function()
        -- Picking has to leave the panel saying what it just did; the row is
        -- the only thing that tells the player the slot took it.
        local ns = withSpellbook()
        local picker = openOn(ns, 3)

        picker.buttons[2].scripts.OnClick(picker.buttons[2])

        local row = controlFor(ns, "bar", "spells").slotRows[3]
        assertEqual("Healing Touch", row.label:GetText())
        assertTrue(row.icon:IsShown(), "and its icon")
    end)

    it("closes once something is chosen", function()
        local ns = withSpellbook()
        local picker = openOn(ns, 2)

        picker.buttons[2].scripts.OnClick(picker.buttons[2])

        assertFalse(picker:IsShown())
    end)

    it("empties the slot from the first entry", function()
        local ns = withSpellbook()
        ns.Slots.Set(4, "Regrowth")
        local picker = openOn(ns, 4)

        picker.buttons[1].scripts.OnClick(picker.buttons[1])

        assertNil(ns.Slots.Spell(4))
    end)

    it("closes when the same row's button is clicked again", function()
        local ns = withSpellbook()
        local picker = openOn(ns, 5)
        assertTrue(picker:IsShown())

        openOn(ns, 5)

        assertFalse(picker:IsShown(), "a second click on an open list closes it")
    end)

    it("stays open and re-aims when a different row asks", function()
        local ns = withSpellbook()
        openOn(ns, 5)
        local picker = openOn(ns, 6)

        assertTrue(picker:IsShown())
        assertEqual(6, picker.slot)
    end)

    it("scrolls rather than hiding spells past the tenth", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        local many = {}
        for index = 1, 30 do
            many[index] = string.format("Spell %02d", index)
        end
        env.__learnSpells(many)
        ns.SettingsPanel.EnsureBuilt()

        local picker = openOn(ns, 1)
        local firstBefore = picker.buttons[1].label:GetText()

        picker.scripts.OnMouseWheel(picker, -1)

        assertTrue(picker.buttons[1].label:GetText() ~= firstBefore, "the list moved")
    end)

    it("does not scroll past the end of the list", function()
        local ns = withSpellbook()
        local picker = openOn(ns, 1)

        for _ = 1, 20 do
            picker.scripts.OnMouseWheel(picker, -1)
        end

        assertEqual(0, picker.offset, "four entries do not fill ten rows")
    end)
end)

describe("what the picker will and will not offer", function()
    local function pickerFor(ns, slot)
        local control = controlFor(ns, "bar", "spells")
        control.picks[slot].scripts.OnClick(control.picks[slot])
        return ns.SettingsPanel.picker
    end

    local function labels(picker)
        local seen = {}
        for _, button in ipairs(picker.buttons) do
            if button:IsShown() then
                seen[button.label:GetText()] = true
            end
        end
        return seen
    end

    local function ready(env, ns)
        for index = 1, ns.Slots.MAX do
            ns.Slots.Set(index, "")
        end
        ns.SettingsPanel.EnsureBuilt()
    end

    it("leaves out everything that is not cast on a friendly target", function()
        -- A spellbook is not a list of heals. Attack, Dodge, Armor
        -- Proficiency, Mining and every profession share it with them.
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Healing Touch", "Attack", "Mining", "Dodge" })
        env.__spellHelpful["Attack"] = false
        env.__spellHelpful["Mining"] = false
        env.__spellHelpful["Dodge"] = false
        ready(env, ns)

        local shown = labels(pickerFor(ns, 1))

        assertTrue(shown["Healing Touch"], "the heal stays")
        assertNil(shown["Attack"])
        assertNil(shown["Mining"])
        assertNil(shown["Dodge"])
    end)

    it("shows everything when the client will not classify spells at all", function()
        -- A filter that silently empties the picker is worse than one that
        -- lets a few passives through.
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Healing Touch", "Attack" })
        env.C_Spell.IsSpellHelpful = nil
        ready(env, ns)

        local shown = labels(pickerFor(ns, 1))

        assertTrue(shown["Healing Touch"])
        assertTrue(shown["Attack"], "unclassified is kept, not dropped")
    end)

    it("does not offer a spell another slot already holds", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Healing Touch", "Rejuvenation" })
        ready(env, ns)
        ns.Slots.Set(1, "Healing Touch")

        local shown = labels(pickerFor(ns, 2))

        assertNil(shown["Healing Touch"], "already on slot 1")
        assertTrue(shown["Rejuvenation"])
    end)

    it("still offers the slot its own spell, so it reads as what it holds", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Healing Touch", "Rejuvenation" })
        ready(env, ns)
        ns.Slots.Set(2, "Healing Touch")

        local shown = labels(pickerFor(ns, 2))

        assertTrue(shown["Healing Touch"])
    end)

    it("offers a spell again once the slot holding it is emptied", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Healing Touch", "Rejuvenation" })
        ready(env, ns)
        ns.Slots.Set(1, "Healing Touch")

        ns.Slots.Set(1, "")

        assertTrue(labels(pickerFor(ns, 2))["Healing Touch"])
    end)
end)

describe("slot rows following the button count", function()
    local function control(ns)
        return controlFor(ns, "bar", "spells")
    end

    it("shows a row for each button the bar is set to", function()
        local ns = loggedIn()
        ns.db.bar.slots = 4
        ns.SettingsPanel.Refresh()

        assertTrue(control(ns).slotRows[4]:IsShown())
        assertTrue(control(ns).picks[4]:IsShown())
    end)

    it("hides the rows past it, Pick button and number with them", function()
        -- A slot past the count has nowhere to appear on the bar, so
        -- offering to fill it is offering nothing.
        local ns = loggedIn()
        ns.db.bar.slots = 4
        ns.SettingsPanel.Refresh()

        assertFalse(control(ns).slotRows[5]:IsShown())
        assertFalse(control(ns).picks[5]:IsShown())
    end)

    it("brings rows back as the slider is dragged up", function()
        local ns = loggedIn()
        ns.db.bar.slots = 4
        ns.SettingsPanel.Refresh()
        assertFalse(control(ns).picks[6]:IsShown())

        controlFor(ns, "bar", "slots").widget:SetValue(6)

        assertTrue(control(ns).picks[6]:IsShown(), "the panel keeps up with the slider")
        assertFalse(control(ns).picks[7]:IsShown())
    end)

    it("survives the slider refreshing itself without looping", function()
        -- The slider's Refresh sets its own value, the client answers with
        -- OnValueChanged, and that onChange refreshes the panel again.
        local ns = loggedIn()

        local ok = pcall(ns.SettingsPanel.Refresh)

        assertTrue(ok, "a refresh must not start another that never ends")
    end)
end)

describe("marking the spell a slot already holds", function()
    local function openOn(ns, slot)
        local control = controlFor(ns, "bar", "spells")
        control.picks[slot].scripts.OnClick(control.picks[slot])
        return ns.SettingsPanel.picker
    end

    local function entryFor(picker, name)
        for _, button in ipairs(picker.buttons) do
            if button:IsShown() and button.label:GetText() == name then
                return button
            end
        end
    end

    it("highlights the slot's current spell in the list", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Healing Touch", "Rejuvenation" })
        ns.SettingsPanel.EnsureBuilt()
        -- Emptied first: the seed fills slots 1-4, and a spell another slot
        -- holds is not offered, so Rejuvenation would not be in the list to
        -- check against.
        for index = 1, ns.Slots.MAX do
            ns.Slots.Set(index, "")
        end
        ns.Slots.Set(1, "Healing Touch")

        local picker = openOn(ns, 1)

        assertTrue(entryFor(picker, "Healing Touch").selected:IsShown())
        assertFalse(entryFor(picker, "Rejuvenation").selected:IsShown())
    end)

    it("marks nothing when the slot is empty", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Healing Touch" })
        ns.SettingsPanel.EnsureBuilt()
        ns.Slots.Set(1, "")

        local picker = openOn(ns, 1)

        assertFalse(entryFor(picker, "Healing Touch").selected:IsShown())
        assertFalse(entryFor(picker, "(empty this slot)").selected:IsShown(),
            "emptying a slot is an action, not a thing a slot holds")
    end)
end)


describe("the picker rows taking the mouse", function()
    -- A Button made without a template does not arrive mouse-enabled. It
    -- looks entirely correct -- right size, right place, right text -- and
    -- takes no click and shows no mouseover. Both symptoms at once, and
    -- nothing in the frame to say why.
    it("enables the mouse on every row of the list", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        env.__learnSpells({ "Healing Touch" })
        ns.SettingsPanel.EnsureBuilt()

        local control = controlFor(ns, "bar", "spells")
        control.picks[1].scripts.OnClick(control.picks[1])

        for index, button in ipairs(ns.SettingsPanel.picker.buttons) do
            assertTrue(button.mouseEnabled, "row " .. index .. " takes the mouse")
        end
    end)

    it("gives every row a highlight to show while the cursor is on it", function()
        local ns = loggedIn()
        local control = controlFor(ns, "bar", "spells")
        control.picks[1].scripts.OnClick(control.picks[1])

        for _, button in ipairs(ns.SettingsPanel.picker.buttons) do
            assertEqual("HIGHLIGHT", button.highlight.drawLayer)
        end
    end)
end)

describe("closing the picker by clicking away", function()
    local function opened(ns)
        local control = controlFor(ns, "bar", "spells")
        control.picks[1].scripts.OnClick(control.picks[1])
        return ns.SettingsPanel.picker
    end

    it("closes on a click on the panel behind it", function()
        -- The panel, not a frame stretched over the screen. A covering frame
        -- has to be above everything to see a click and below the list so as
        -- not to take one, and getting that wrong left the list taking no
        -- clicks at all. The panel is the list's own ancestor, so the list is
        -- always above it.
        local ns = loggedIn()
        local picker = opened(ns)
        assertTrue(picker:IsShown())

        local panel = ns.SettingsPanel.panel
        panel.scripts.OnMouseDown(panel)

        assertFalse(picker:IsShown())
    end)

    it("leaves nothing covering the screen behind it", function()
        -- What the covering frame cost: while it was up, every click on the
        -- panel went to it rather than to what was clicked.
        local ns = loggedIn()
        opened(ns)

        assertNil(ns.SettingsPanel.picker.catcher)
    end)

    it("takes the mouse on the panel so the click has somewhere to land", function()
        local ns = loggedIn()
        opened(ns)

        assertTrue(ns.SettingsPanel.panel.mouseEnabled)
    end)
end)

describe("the picker rows answering a click", function()
    it("asks for both edges, as the spell buttons do", function()
        -- This client acts on the press where others act on the release.
        -- Choosing hides the list, so the second pass finds nothing to click
        -- and only one choice is ever made.
        local ns = loggedIn()
        local control = controlFor(ns, "bar", "spells")
        control.picks[1].scripts.OnClick(control.picks[1])

        local registered = {}
        for _, click in ipairs(ns.SettingsPanel.picker.buttons[1].clickRegistrations or {}) do
            registered[click] = true
        end

        assertTrue(registered.AnyDown, "the press, which is what this client acts on")
        assertTrue(registered.AnyUp)
    end)
end)
