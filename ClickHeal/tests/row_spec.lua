local helpers = require("helpers")

local FILES = { "ClickHeal.lua", "Anchors.lua", "Spells.lua", "Slots.lua", "Row.lua" }
local FILES_WITH_GROUP = { "ClickHeal.lua", "Anchors.lua", "Spells.lua", "Slots.lua", "Row.lua", "Group.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

--- Group.lua is what turns a drop's Slots.Set into a written attribute (it is
-- the only thing that knows to wait for combat to end), so the drag-and-drop
-- tests need it loaded alongside Row -- unlike the rest of this file, which
-- tests Row in isolation.
local function loggedInWithGroup()
    local ns, env = helpers.loadAddon(FILES_WITH_GROUP)
    helpers.login(ns, env)
    return ns, env
end

describe("building a row", function()
    it("builds every slot the maximum allows, not just the ones in use", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertEqual(ns.Slots.MAX, #row.buttons)
    end)

    it("makes every button a secure action button", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertEqual("SecureActionButtonTemplate", row.buttons[1].template)
    end)

    it("binds every button to the unit, once and for all", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party2", env.UIParent)

        for index = 1, ns.Slots.MAX do
            local attrs = helpers.attrs(row.buttons[index])
            assertEqual("spell", attrs.type, "button " .. index .. " casts a spell")
            assertEqual("party2", attrs.unit, "button " .. index .. " is bound to party2")
        end
    end)

    it("gives the row itself a unit attribute for RegisterUnitWatch", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party3", env.UIParent)

        assertEqual("party3", row:GetAttribute("unit"))
    end)

    it("starts with every button hidden, since no spell is applied yet", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertFalse(row.buttons[1]:IsShown())
    end)

    it("gives the health bar a texture, or it draws nothing at all", function()
        -- SetStatusBarColor tints whatever texture is set; a StatusBar with
        -- none set draws nothing, so the row would show a name, an empty
        -- gap, and the icons.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertEqual("Interface\\TargetingFrame\\UI-StatusBar", row.health:GetStatusBarTexture())
    end)

    it("gives each button its slot index and an icon texture", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            assertEqual(index, row.buttons[index].slot)
            assertTrue(row.buttons[index].icon ~= nil, "button " .. index .. " has an icon")
        end
    end)

    it("gives every button the action bar's own hover highlight", function()
        -- The same texture and blend Blizzard's action buttons use, so a
        -- ClickHeal button lights up under the cursor exactly as the ones
        -- beside it do. ADD is what makes it a glow rather than an opaque
        -- square laid over the icon.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            assertEqual(
                "Interface\\Buttons\\ButtonHilight-Square",
                row.buttons[index].highlightTexture,
                "button " .. index .. " highlights on hover"
            )
            assertEqual("ADD", row.buttons[index].highlightBlend)
        end
    end)

    it("never registers a button for drag, only for receiving one", function()
        -- RegisterForDrag is for STARTING a drag; wiring it on a button whose
        -- left-click casts a spell risks the drag swallowing that click.
        -- OnReceiveDrag alone is what a drop needs.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertNil(row.buttons[1].dragRegistered)
    end)

    it("reaches at least as far as the last button's right edge", function()
        -- WIDTH is Group's layout arithmetic; if it falls short here, every
        -- row Group tiles later has its last button overhanging the next.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        local lastButton = row.buttons[ns.Slots.MAX]

        local _, x = lastButton:GetPoint()
        local rightEdge = x + lastButton:GetWidth()

        assertTrue(
            ns.Row.WIDTH >= rightEdge,
            string.format("Row.WIDTH (%d) must reach the last button's right edge (%d)", ns.Row.WIDTH, rightEdge)
        )
    end)
end)

describe("applying spells", function()
    it("writes the spell a slot holds", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)
        assertEqual("Regrowth", helpers.attrs(row.buttons[1]).spell)
    end)

    it("never rewrites the unit while doing so", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)
        assertEqual("party1", helpers.attrs(row.buttons[1]).unit)
    end)

    it("shows only the configured number of buttons", function()
        local ns, env = loggedIn()
        ns.db.bar.slots = 2
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(2, "Rejuvenation")
        ns.Slots.Set(3, "Remove Curse")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)
        assertTrue(row.buttons[1]:IsShown())
        assertTrue(row.buttons[2]:IsShown())
        assertFalse(row.buttons[3]:IsShown(), "slot 3 is past the count")
    end)

    it("hides an empty slot inside the count", function()
        -- A button that looks pressable and does nothing is the same failure
        -- as one wired to a spell that does not exist.
        local ns, env = loggedIn()
        ns.db.bar.slots = 3
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(3, "Remove Curse")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)
        assertFalse(row.buttons[2]:IsShown())
    end)

    it("clears the spell attribute of a slot that was emptied", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        ns.Slots.Set(1, "")
        ns.Row.ApplySpells(row)

        assertNil(helpers.attrs(row.buttons[1]).spell)
    end)

    it("shows the spell's own icon", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertEqual(136085, row.buttons[1].icon:GetTexture())
        assertTrue(row.buttons[1].icon:IsShown())
    end)

    it("hides a slot holding a spell the player has not learned", function()
        -- The bar is a row of icons, and a spell the client will not draw an
        -- icon for has nothing to put there. Hiding it is also what keeps the
        -- icons that remain sitting together.
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Tranquility")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertFalse(row.buttons[1]:IsShown())
        assertNil(helpers.attrs(row.buttons[1]).spell, "and it must not stay castable")
    end)

    it("closes the gap a hidden slot leaves, rather than laying out around it", function()
        -- Buttons are created at a fixed offset per slot index, so a hidden
        -- slot in the middle would otherwise leave a hole.
        local ns, env = loggedIn()
        ns.db.bar.slots = 3
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(2, "Tranquility")
        ns.Slots.Set(3, "Remove Curse")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertFalse(row.buttons[2]:IsShown())

        local _, firstX = row.buttons[1]:GetPoint()
        local _, thirdX = row.buttons[3]:GetPoint()
        assertEqual(
            row.buttons[1]:GetWidth() + ns.Row.BUTTON_GAP,
            thirdX - firstX,
            "slot 3 must sit where slot 2 would have been"
        )
    end)

    it("leaves a resurrection off your own row, keeping its place", function()
        -- Rebirth and Revive cannot target the caster. The gap stays so
        -- Remove Curse sits in the same column as on every party row.
        local ns, env = loggedIn()
        env.__spells["Rebirth"] = true
        env.__spellTextures["Rebirth"] = 136080
        ns.db.bar.slots = 3
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(2, "Rebirth")
        ns.Slots.Set(3, "Remove Curse")
        local row = ns.Row.Create("player", env.UIParent)

        ns.Row.ApplySpells(row)

        assertFalse(row.buttons[2]:IsShown())
        assertNil(helpers.attrs(row.buttons[2]).spell, "and it must not stay castable")

        local _, firstX = row.buttons[1]:GetPoint()
        local _, thirdX = row.buttons[3]:GetPoint()
        assertEqual(
            2 * (row.buttons[1]:GetWidth() + ns.Row.BUTTON_GAP),
            thirdX - firstX,
            "slot 3 stays in its own column"
        )
    end)

    it("still offers a resurrection on a party member's row", function()
        local ns, env = loggedIn()
        env.__spells["Revive"] = true
        env.__spellTextures["Revive"] = 132132
        ns.Slots.Set(1, "Revive")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertTrue(row.buttons[1]:IsShown())
        assertEqual("Revive", helpers.attrs(row.buttons[1]).spell)
    end)

    it("does not size your row for a resurrection it left off the end", function()
        local ns, env = loggedIn()
        env.__spells["Revive"] = true
        env.__spellTextures["Revive"] = 132132
        ns.db.bar.slots = 2
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(2, "Revive")
        local mine = ns.Row.Create("player", env.UIParent)
        local theirs = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(mine)
        ns.Row.ApplySpells(theirs)

        assertTrue(mine:GetWidth() < theirs:GetWidth(), "one button narrower")
    end)

    it("keeps a known spell visible even when its icon cannot be looked up", function()
        -- Whether a button appears is decided by whether the player knows the
        -- spell, never by whether an icon lookup happened to succeed. On a
        -- client with no texture API at all the second rule would empty the
        -- whole bar, which is the one outcome that leaves a healer with
        -- nothing to click.
        local ns, env = loggedIn()
        env.C_Spell.GetSpellTexture = nil
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertTrue(row.buttons[1]:IsShown())
        assertEqual("Regrowth", helpers.attrs(row.buttons[1]).spell)
        assertEqual(
            "Interface\\Icons\\INV_Misc_QuestionMark",
            row.buttons[1].icon:GetTexture()
        )
    end)

    it("gives back exactly the width of a button it stops showing", function()
        -- Measured as a difference rather than against a computed total, so
        -- this says what it means -- a hidden button costs the row its own
        -- width -- without restating Row.WIDTH's arithmetic and agreeing
        -- with itself.
        local ns, env = loggedIn()
        ns.db.bar.slots = 3
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(2, "Rejuvenation")
        ns.Slots.Set(3, "Remove Curse")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)
        local threeButtons = row:GetWidth()

        ns.Slots.Set(2, "Tranquility")
        ns.Row.ApplySpells(row)

        assertEqual(
            threeButtons - (row.buttons[1]:GetWidth() + ns.Row.BUTTON_GAP),
            row:GetWidth()
        )
    end)

    it("hides the icon for an empty slot", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertFalse(row.buttons[1].icon:IsShown())
    end)

    it("applies the standard border crop to every button's icon", function()
        -- The idiom every action bar uses: without it, a default spell icon's
        -- own border shows up doubled, next to this button's.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        assertEqual(
            "0.07, 0.93, 0.07, 0.93",
            table.concat(row.buttons[1].icon.texCoord, ", ")
        )
    end)

    -- PreClick's click-suppression trick nils `type` out for the span of one
    -- click. If PostClick ever left it that way -- a stranded stash, present
    -- or future -- a button that can never cast again is the worst outcome
    -- this addon has, and every ApplyAll is a free chance to notice and fix it.
    it("restores a stranded type attribute on a slot holding a spell", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        row.buttons[1]:SetAttribute("type", nil)
        ns.Row.ApplySpells(row)

        assertEqual("spell", helpers.attrs(row.buttons[1]).type)
    end)

    it("restores a stranded type attribute on an empty slot too", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        row.buttons[1]:SetAttribute("type", nil)
        ns.Row.ApplySpells(row)

        assertEqual("spell", helpers.attrs(row.buttons[1]).type)
    end)
end)

describe("dropping a spell onto a button", function()
    it("stores the dropped spell in the button's slot, applies it, and clears the cursor", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        env.__cursor = { "spell", 5, "spell" }

        row.buttons[2].scripts.OnReceiveDrag(row.buttons[2])

        assertEqual("Regrowth", ns.Slots.Spell(2))
        assertEqual("Regrowth", helpers.attrs(row.buttons[2]).spell)
        assertNil(env.__cursor)
    end)

    it("does nothing at all, and leaves the cursor alone, for a non-spell drop", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        env.__cursor = { "item", 6948 }

        row.buttons[2].scripts.OnReceiveDrag(row.buttons[2])

        assertEqual("Healing Touch", ns.Slots.Spell(2), "the seeded spell is untouched")
        assertTrue(env.__cursor ~= nil, "the item is still on the cursor")
    end)

    it("prints the unlearned-spell warning that Slots.Set returns", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        env.__cursor = { "spell", 7, "spell" }

        row.buttons[3].scripts.OnReceiveDrag(row.buttons[3])

        assertEqual("Tranquility", ns.Slots.Spell(3))
        assertMatch("Tranquility", helpers.printed(env))
    end)

    it("stores the spell during combat but leaves the attribute unwritten until combat ends", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")

        env.__setCombat(true)
        env.__cursor = { "spell", 5, "spell" }
        row.buttons[2].scripts.OnReceiveDrag(row.buttons[2])

        assertEqual("Regrowth", ns.Slots.Spell(2), "stored despite combat")
        assertEqual(
            "Healing Touch",
            helpers.attrs(row.buttons[2]).spell,
            "not written yet -- the seeded spell is still there while combat is active"
        )

        env.__setCombat(false)

        assertEqual(
            "Regrowth",
            helpers.attrs(row.buttons[2]).spell,
            "applied the moment combat ends"
        )
    end)
end)

describe("clicking a spell onto a button", function()
    -- Most players assign a spell by clicking it in the spellbook, then
    -- clicking the button, not by dragging it. That is an ordinary click,
    -- which PreClick/PostClick intercept: nil the secure `type` attribute
    -- out for this one click, then restore it once the click has passed.

    it("assigns the spell and suppresses the cast when the cursor holds one", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        local button = row.buttons[2]
        env.__cursor = { "spell", 5, "spell" }

        button.scripts.PreClick(button)
        assertNil(button:GetAttribute("type"), "the secure handler must not cast on this click")

        button.scripts.PostClick(button)

        assertEqual("spell", button:GetAttribute("type"), "restored for the next real click")
        assertEqual("Regrowth", ns.Slots.Spell(2))
        assertEqual("Regrowth", helpers.attrs(button).spell)
    end)

    it("casts normally and assigns nothing when the cursor is empty", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        local button = row.buttons[2]
        env.__cursor = nil

        button.scripts.PreClick(button)
        assertEqual("spell", button:GetAttribute("type"), "an ordinary click must still be able to cast")

        button.scripts.PostClick(button)

        assertEqual("spell", button:GetAttribute("type"))
        assertEqual("Healing Touch", ns.Slots.Spell(2), "the seeded spell is untouched")
    end)

    it("casts normally and assigns nothing when the click lands during combat", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        local button = row.buttons[2]

        env.__setCombat(true)
        env.__cursor = { "spell", 5, "spell" }

        button.scripts.PreClick(button)
        assertEqual(
            "spell",
            button:GetAttribute("type"),
            "attributes cannot be written in combat, so the click must cast normally"
        )

        button.scripts.PostClick(button)

        assertEqual("spell", button:GetAttribute("type"))
        assertEqual("Healing Touch", ns.Slots.Spell(2), "nothing was assigned")
    end)

    it("clears the stash so a later ordinary click cannot replay the assignment", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        local button = row.buttons[3]
        -- Slot 7 is "Tranquility", unlearned, so a successful assignment
        -- prints a warning -- which is what makes a replay observable: the
        -- stored value would be identical either way, but a second print
        -- would not be.
        env.__cursor = { "spell", 7, "spell" }

        button.scripts.PreClick(button)
        button.scripts.PostClick(button)
        local _, firstCount = helpers.printed(env):gsub("Tranquility", "Tranquility")

        -- A second, ordinary click: nothing on the cursor this time. If the
        -- stash from the first click were still set, PostClick would find it
        -- and replay the assignment -- and its warning -- a second time.
        env.__cursor = nil
        button.scripts.PreClick(button)
        button.scripts.PostClick(button)
        local _, secondCount = helpers.printed(env):gsub("Tranquility", "Tranquility")

        assertEqual(firstCount, secondCount, "the warning must not print a second time")
        assertEqual("spell", button:GetAttribute("type"))
    end)

    it("clears the stash even if the shared assignment throws, before a later combat click can exploit it", function()
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        local button = row.buttons[3]
        -- Slot 7 is "Tranquility", unlearned, so assignSpellToSlot reaches
        -- its last call site, ns.Print(message) -- the one this test makes
        -- throw. Everything before it (Slots.Set, ClearCursor, ApplyAll,
        -- SettingsPanel.Refresh) has already run by the time it fires.
        env.__cursor = { "spell", 7, "spell" }

        button.scripts.PreClick(button)
        assertEqual("Tranquility", button.pendingAssign)

        local originalPrint = env.print
        env.print = function() error("boom") end

        local ok = pcall(button.scripts.PostClick, button)
        env.print = originalPrint

        assertFalse(ok, "the forced error must actually have propagated out of PostClick")
        assertNil(button.pendingAssign, "the stash must not survive the throw")
        assertEqual("Tranquility", ns.Slots.Spell(3), "Slots.Set itself had already run before the throw")

        -- A later, ordinary click landing mid-fight must find nothing left
        -- to exploit: no attribute write, no assignment.
        env.__setCombat(true)
        env.__cursor = nil
        local typeBefore = button:GetAttribute("type")

        button.scripts.PreClick(button)
        button.scripts.PostClick(button)

        assertEqual(typeBefore, button:GetAttribute("type"), "no attribute write happened")
        assertEqual("Tranquility", ns.Slots.Spell(3), "no further assignment ran")
    end)

    it("PostClick's own combat guard refuses to act, and still clears the stash", function()
        -- Contrived: PreClick already refuses to stash anything while in
        -- combat, so PostClick should never see a stash and be in combat at
        -- the same time from any path the addon itself takes. It must not
        -- lean on that alone.
        local ns, env = loggedInWithGroup()
        local row = helpers.rowFor(ns, "party1")
        local button = row.buttons[2]

        button.pendingAssign = "Regrowth"
        env.__setCombat(true)
        local typeBefore = button:GetAttribute("type")

        button.scripts.PostClick(button)

        assertEqual(typeBefore, button:GetAttribute("type"), "no attribute write in combat")
        assertNil(button.pendingAssign, "the stash is cleared regardless")
        assertEqual("Healing Touch", ns.Slots.Spell(2), "no assignment ran")
    end)
end)

describe("refreshing a row", function()
    it("shows the unit's name", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertEqual("Borgir", row.name:GetText())
    end)

    it("scales the health bar to the unit's maximum", function()
        local ns, env = loggedIn()
        env.units.party1.health = 30
        env.units.party1.healthMax = 120
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        local low, high = row.health:GetMinMaxValues()
        assertEqual(0, low)
        assertEqual(120, high)
        assertEqual(30, row.health:GetValue())
    end)

    it("colours the bar by class", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party2", env.UIParent)

        ns.Row.Refresh(row)
        assertTrue(row.health.barColor ~= nil, "a mage bar is a mage colour")
    end)

    it("leaves a full-strength row alone", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertEqual(1, row:GetAlpha())
    end)
end)

describe("dimming a row you cannot usefully click", function()
    -- Clicking a heal on someone dead or out of range burns a global cooldown
    -- and returns nothing at all.

    it("dims a dead unit", function()
        local ns, env = loggedIn()
        env.units.party1.dead = true
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertTrue(row:GetAlpha() < 1)
    end)

    it("dims an offline unit", function()
        local ns, env = loggedIn()
        env.units.party1.connected = false
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertTrue(row:GetAlpha() < 1)
    end)

    it("dims a unit out of range", function()
        local ns, env = loggedIn()
        env.units.party1.inRange = false
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertTrue(row:GetAlpha() < 1)
    end)

    it("brightens again when the unit comes back into range", function()
        local ns, env = loggedIn()
        env.units.party1.inRange = false
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.Refresh(row)

        env.units.party1.inRange = true
        ns.Row.Refresh(row)

        assertEqual(1, row:GetAlpha())
    end)

    it("treats a unit that cannot be range-checked as reachable", function()
        -- UnitInRange returns false, false -- not "false, true" -- for a unit
        -- the client cannot range-check at all, notably "player" while solo.
        -- That is "unknown", not "out of range", and must not read as one.
        local ns, env = loggedIn()
        env.units.party1.checkedRange = false
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.Refresh(row)
        assertEqual(1, row:GetAlpha())
    end)

    it("survives a unit that is not there at all", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party4", env.UIParent)
        -- Only the UnitExists guard returning early leaves these alone; any
        -- code path past it would reset them to (0, 1) and 0.
        row.health:SetMinMaxValues(0, 999)
        row.health:SetValue(555)

        ns.Row.Refresh(row)

        assertEqual("", row.name:GetText())
        local low, high = row.health:GetMinMaxValues()
        assertEqual(0, low)
        assertEqual(999, high, "the guard must return before touching the health bar")
        assertEqual(555, row.health:GetValue())
    end)
end)

describe("refreshing a row on a client that treats a value as secret", function()
    -- A client can hand tainted code (ours) a "secret" value: the API call
    -- that produced it succeeds, but branching on the result -- `if x then`,
    -- `not x`, `x or y` -- raises. Lua itself has no way to build a value
    -- that raises when its truthiness is tested, so these tests stand in for
    -- that by making the stubbed API call itself raise instead. Row.Reachable
    -- (see Row.lua) routes both shapes of failure through the same pcall, so
    -- this is exercising the real fallback path even though the trigger
    -- looks different from the one the game uses.

    it("does not error, and does not dim, when UnitInRange itself raises", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        env.UnitInRange = function() error("secret boolean value") end

        local ok = pcall(ns.Row.Refresh, row)

        assertTrue(ok, "Refresh must not propagate the raise")
        assertEqual(1, row:GetAlpha(), "cannot tell must not read as out of range")
    end)

    it("still dims a dead unit when UnitInRange raises", function()
        -- Range being unavailable must not cost the dead/offline dimming
        -- that does not depend on it -- the whole reason dead/offline and
        -- range are checked independently in Row.Reachable.
        local ns, env = loggedIn()
        env.units.party1.dead = true
        local row = ns.Row.Create("party1", env.UIParent)
        env.UnitInRange = function() error("secret boolean value") end

        ns.Row.Refresh(row)

        assertTrue(row:GetAlpha() < 1, "a dead unit must still dim")
    end)

    it("still dims an offline unit when UnitInRange raises", function()
        local ns, env = loggedIn()
        env.units.party1.connected = false
        local row = ns.Row.Create("party1", env.UIParent)
        env.UnitInRange = function() error("secret boolean value") end

        ns.Row.Refresh(row)

        assertTrue(row:GetAlpha() < 1, "an offline unit must still dim")
    end)

    it("does not crash when UnitHealthMax raises", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        env.UnitHealthMax = function() error("secret number value") end

        local ok = pcall(ns.Row.Refresh, row)

        assertTrue(ok, "Refresh must not propagate the raise")
    end)

    it("fills the row in anyway when UnitExists raises", function()
        -- Blanking a row for someone who is in fact standing there costs the
        -- healer a player they could have clicked; filling one in for someone
        -- who has left costs a stale name until the next roster event. So a
        -- unit we cannot check at all reads as present.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)
        env.UnitExists = function() error("secret boolean value") end

        local ok = pcall(ns.Row.Refresh, row)

        assertTrue(ok, "Refresh must not propagate the raise")
        assertTrue(row.name:GetText() ~= "", "the row must not blank itself")
    end)
end)

describe("which clicks a spell button asks for", function()
    it("registers for the button going down as well as coming up", function()
        -- Registered for "AnyUp" alone, these buttons did not cast at all.
        -- In-game tracing showed why: every hook fired, and the attributes
        -- read type=spell spell=Rejuvenation unit=player at click time, but
        -- only ever with down=false. The client performs the action on the
        -- press, not the release, so a button that never asks for the press
        -- hands the secure handler nothing it will act on.
        --
        -- The stub cannot reproduce that refusal -- it has no secure
        -- handler -- so this asserts the registration itself, which is the
        -- part that was wrong and the part a later tidy-up would undo.
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        local registered = {}
        for _, click in ipairs(row.buttons[1].clickRegistrations or {}) do
            registered[click] = true
        end

        assertTrue(registered.AnyDown, "must ask for the press, which is what casts")
        assertTrue(registered.AnyUp, "and keep the release, for clients that act on it")
    end)
end)

describe("the cooldown sweep on a button", function()
    local function armed(env, ns, slot, spell)
        ns.Slots.Set(slot, spell)
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)
        return row
    end

    it("draws the sweep the client reports for the button's own spell", function()
        local ns, env = loggedIn()
        local row = armed(env, ns, 1, "Rejuvenation")
        env.__spellCooldowns["Rejuvenation"] =
            { startTime = 100, duration = 1.5, isEnabled = true }

        ns.Row.RefreshCooldowns(row)

        local start, duration = row.buttons[1].cooldown:GetCooldownTimes()
        assertEqual(100, start)
        assertEqual(1.5, duration)
    end)

    it("clears the sweep once the spell is off cooldown", function()
        local ns, env = loggedIn()
        local row = armed(env, ns, 1, "Rejuvenation")
        env.__spellCooldowns["Rejuvenation"] =
            { startTime = 100, duration = 1.5, isEnabled = true }
        ns.Row.RefreshCooldowns(row)

        env.__spellCooldowns["Rejuvenation"] = nil
        ns.Row.RefreshCooldowns(row)

        local start, duration = row.buttons[1].cooldown:GetCooldownTimes()
        assertEqual(0, start, "a stale sweep would sit there for good")
        assertEqual(0, duration)
    end)

    it("draws no sweep for a cooldown the client says is not enabled", function()
        local ns, env = loggedIn()
        local row = armed(env, ns, 1, "Rejuvenation")
        env.__spellCooldowns["Rejuvenation"] =
            { startTime = 100, duration = 1.5, isEnabled = false }

        ns.Row.RefreshCooldowns(row)

        local _, duration = row.buttons[1].cooldown:GetCooldownTimes()
        assertEqual(0, duration)
    end)

    it("draws no sweep when the client will not disclose the numbers", function()
        -- The live crash of 2026-09-20, which ran 37 times before it was
        -- reported. `start and duration` waved both secret numbers straight
        -- through, because a secret number is truthy; `duration > 0` was what
        -- raised, and it took out every later button on every later row.
        local ns, env = loggedIn()
        local row = armed(env, ns, 1, "Rejuvenation")
        env.__spellCooldowns["Rejuvenation"] = {
            startTime = env.__secret(),
            duration = env.__secret(),
            isEnabled = true,
        }

        local ok, err = pcall(ns.Row.RefreshCooldowns, row)

        assertTrue(ok, "a withheld cooldown must cost the sweep, not the "
            .. "refresh: " .. tostring(err))
        local _, duration = row.buttons[1].cooldown:GetCooldownTimes()
        assertEqual(0, duration, "and nothing may be drawn from a number it "
            .. "was never allowed to read")
    end)

    it("keeps refreshing the rest of the row past a withheld cooldown", function()
        -- The damage was never one icon. RefreshCooldowns walks every slot in
        -- one loop, so raising on slot 1 meant slots 2..8 were never reached.
        local ns, env = loggedIn()
        ns.db.bar.slots = 2
        ns.Slots.Set(1, "Rejuvenation")
        ns.Slots.Set(2, "Healing Touch")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        env.__spellCooldowns["Rejuvenation"] = {
            startTime = env.__secret(),
            duration = env.__secret(),
            isEnabled = true,
        }
        env.__spellCooldowns["Healing Touch"] =
            { startTime = 100, duration = 1.5, isEnabled = true }

        ns.Row.RefreshCooldowns(row)

        local start, duration = row.buttons[2].cooldown:GetCooldownTimes()
        assertEqual(100, start, "slot 2 is past the unreadable one and must "
            .. "still get its sweep")
        assertEqual(1.5, duration)
    end)

    it("still builds a working button when the client has no cooldown template", function()
        -- The sweep is decoration; casting is the point. This client family
        -- has already dropped APIs the addon expected, and an unknown
        -- template raises rather than returning nil, so losing the template
        -- must cost the sweep and nothing else.
        local ns, env = loggedIn()
        env.__missingTemplates["CooldownFrameTemplate"] = true

        local row = armed(env, ns, 1, "Rejuvenation")

        assertEqual("Rejuvenation", row.buttons[1]:GetAttribute("spell"))
        assertEqual("spell", row.buttons[1]:GetAttribute("type"))
        assertNil(row.buttons[1].cooldown, "no template means no sweep frame")

        local ok = pcall(ns.Row.RefreshCooldowns, row)
        assertTrue(ok, "and refreshing must not trip over its absence")
    end)
end)

describe("dimming an icon its spell cannot reach", function()
    local function armed(env, ns, spells)
        ns.db.bar.slots = #spells
        for index, spell in ipairs(spells) do
            ns.Slots.Set(index, spell)
        end
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)
        return row
    end

    it("dims the icon of a spell that cannot reach the unit", function()
        local ns, env = loggedIn()
        local row = armed(env, ns, { "Rejuvenation" })
        env.__spellRanges["Rejuvenation:party1"] = false

        ns.Row.Refresh(row)

        assertTrue(row.buttons[1].icon.vertexColor[1] < 1)
    end)

    it("leaves an icon at full colour when the spell reaches", function()
        local ns, env = loggedIn()
        local row = armed(env, ns, { "Rejuvenation" })
        env.__spellRanges["Rejuvenation:party1"] = true

        ns.Row.Refresh(row)

        assertEqual(1, row.buttons[1].icon.vertexColor[1])
    end)

    it("leaves an icon alone when the client will not say", function()
        local ns, env = loggedIn()
        local row = armed(env, ns, { "Rejuvenation" })

        ns.Row.Refresh(row)

        assertEqual(1, row.buttons[1].icon.vertexColor[1])
    end)

    it("judges each spell separately, not the row as a whole", function()
        -- Spells differ in reach, which is the whole reason this is not the
        -- row-wide fade that dead and offline get -- those make every spell
        -- useless at once, and being out of reach does not.
        local ns, env = loggedIn()
        local row = armed(env, ns, { "Rejuvenation", "Mark of the Wild" })
        env.__spellRanges["Rejuvenation:party1"] = true
        env.__spellRanges["Mark of the Wild:party1"] = false

        ns.Row.Refresh(row)

        assertEqual(1, row.buttons[1].icon.vertexColor[1])
        assertTrue(row.buttons[2].icon.vertexColor[1] < 1)
    end)
end)

describe("hanging a row off Blizzard's unit frame", function()
    local function applied(ns, env, attached, spells)
        ns.db.bar.attached = attached
        ns.db.bar.slots = #spells
        for index, spell in ipairs(spells) do
            ns.Slots.Set(index, spell)
        end
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)
        return row
    end

    it("hides the row's own name and health bar", function()
        -- Blizzard's frame is already showing both. Ours would be a second
        -- copy of each, sitting right next to the first.
        local ns, env = loggedIn()
        local row = applied(ns, env, true, { "Rejuvenation" })

        assertFalse(row.name:IsShown())
        assertFalse(row.health:IsShown())
    end)

    it("shows them again on the standalone bar, which has neither", function()
        local ns, env = loggedIn()
        local row = applied(ns, env, false, { "Rejuvenation" })

        assertTrue(row.name:IsShown())
        assertTrue(row.health:IsShown())
    end)

    it("starts the buttons at the row's own left edge", function()
        local ns, env = loggedIn()
        local row = applied(ns, env, true, { "Rejuvenation" })

        local _, x = row.buttons[1]:GetPoint()
        assertEqual(0, x, "nothing sits to the left of the buttons any more")
    end)

    it("narrows the row to just its buttons", function()
        local ns, env = loggedIn()
        local row = applied(ns, env, true, { "Rejuvenation", "Regrowth" })

        assertEqual(
            2 * row.buttons[1]:GetWidth() + ns.Row.BUTTON_GAP,
            row:GetWidth(),
            "no room reserved for a name and bar that are not drawn"
        )
    end)

    it("stays on the bar when this UI has no unit frames to hang from", function()
        -- Raid-style party frames, or a unit-frame addon. Asking for the
        -- attached layout cannot conjure frames that are not there.
        local ns, env = loggedIn()
        ns.db.bar.attached = true
        env.PlayerFrame = nil

        assertFalse(ns.Row.Attached())
    end)
end)

describe("the remaining time under an icon", function()
    it("writes seconds, minutes and hours the way the game's buff frames do", function()
        local ns = loggedIn()

        -- Rounding up above a minute is what SecondsToTimeAbbrev does, and
        -- matching it is the point: our number sits on the same screen as
        -- the game's own for the same buff, and rounding down put the two a
        -- whole minute apart.
        assertEqual("7s", ns.Row.FormatDuration(6.2), "seconds round up, so a live buff never reads 0s")
        assertEqual("2m", ns.Row.FormatDuration(90), "as the game writes it")
        assertEqual("38m", ns.Row.FormatDuration(2280), "exactly 38 minutes is 38m, not 39m")
        assertEqual("57m", ns.Row.FormatDuration(56 * 60 + 30), "the case that did not match")
        assertEqual("2h", ns.Row.FormatDuration(3700))
    end)

    it("writes nothing at all when there is nothing to count", function()
        local ns = loggedIn()

        assertEqual("", ns.Row.FormatDuration(nil))
        assertEqual("", ns.Row.FormatDuration(0))
        assertEqual("", ns.Row.FormatDuration(-5))
    end)

    it("counts down the player's own buff on that row's unit", function()
        local ns, env = loggedIn()
        ns.db.bar.slots = 1
        ns.Slots.Set(1, "Rejuvenation")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007 } }

        ns.Row.Refresh(row)

        assertEqual("7s", row.buttons[1].timer:GetText())
    end)

    it("leaves the icon unlabelled when the buff is not on that unit", function()
        -- Blank is the signal to click: this person does not have it.
        local ns, env = loggedIn()
        ns.db.bar.slots = 1
        ns.Slots.Set(1, "Rejuvenation")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        env.__auras.party1 = { { name = "Mark of the Wild", expirationTime = 9999 } }

        ns.Row.Refresh(row)

        assertEqual("", row.buttons[1].timer:GetText())
    end)

    it("clears a number that has run out rather than leaving it frozen", function()
        local ns, env = loggedIn()
        ns.db.bar.slots = 1
        ns.Slots.Set(1, "Rejuvenation")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007 } }
        ns.Row.Refresh(row)

        env.__now = 1008
        ns.Row.Refresh(row)

        assertEqual("", row.buttons[1].timer:GetText())
    end)

    it("asks the client for a unit's auras once, not once per button", function()
        -- Eight buttons on each of five rows, five times a second, is
        -- thousands of calls into the client every second if each button
        -- asks for itself.
        local ns, env = loggedIn()
        ns.db.bar.slots = 3
        ns.Slots.Set(1, "Rejuvenation")
        ns.Slots.Set(2, "Regrowth")
        ns.Slots.Set(3, "Remove Curse")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        local asked = 0
        local real = env.C_UnitAuras.GetAuraDataByIndex
        env.C_UnitAuras.GetAuraDataByIndex = function(...)
            asked = asked + 1
            return real(...)
        end

        ns.Row.RefreshAuras(row)

        assertTrue(asked <= 2, "one walk that stops at the first gap, not one per button")
    end)
end)

describe("the icon size", function()
    local function applied(ns, env, size)
        ns.db.bar.iconSize = size
        ns.db.bar.slots = 2
        ns.Slots.Set(1, "Regrowth")
        ns.Slots.Set(2, "Rejuvenation")
        ns.Row.SyncSize()
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)
        return row
    end

    it("defaults to the size the buttons have always been", function()
        local ns = loggedIn()
        assertEqual(ns.Row.DEFAULT_BUTTON_SIZE, ns.db.bar.iconSize)
    end)

    it("sizes the buttons to it", function()
        local ns, env = loggedIn()
        local row = applied(ns, env, 32)

        assertEqual(32, row.buttons[1]:GetWidth())
        assertEqual(32, row.buttons[1]:GetHeight())
    end)

    it("resizes buttons that already exist, since rows outlive the setting", function()
        -- Rows can only be built out of combat, so rebuilding them is not
        -- something a settings change can rely on doing.
        local ns, env = loggedIn()
        local row = applied(ns, env, 22)

        ns.db.bar.iconSize = 40
        ns.Row.SyncSize()
        ns.Row.ApplySpells(row)

        assertEqual(40, row.buttons[1]:GetWidth())
    end)

    it("spaces the buttons by the new size", function()
        local ns, env = loggedIn()
        local row = applied(ns, env, 32)

        local _, first = row.buttons[1]:GetPoint()
        local _, second = row.buttons[2]:GetPoint()

        assertEqual(32 + ns.Row.BUTTON_GAP, second - first)
    end)

    it("grows the row's height and width with it", function()
        local ns, env = loggedIn()
        local small = applied(ns, env, 16)
        local narrow = small:GetWidth()
        local short = ns.Row.HEIGHT

        local big = applied(ns, env, 40)

        assertTrue(big:GetWidth() > narrow, "wider icons need a wider row")
        assertTrue(ns.Row.HEIGHT > short, "and a taller one")
    end)

    it("refuses a size outside the bounds, whatever the database says", function()
        -- A slider cannot produce one, but a saved variable edited by hand
        -- can, and a frame sized from a negative number is one the client
        -- complains about.
        local ns, env = loggedIn()

        local tiny = applied(ns, env, -50)
        assertEqual(ns.Row.MIN_BUTTON_SIZE, tiny.buttons[1]:GetWidth())

        local huge = applied(ns, env, 5000)
        assertEqual(ns.Row.MAX_BUTTON_SIZE, huge.buttons[1]:GetWidth())
    end)
end)

describe("what a row's buttons are holding", function()
    it("lists the spells in button order", function()
        local ns, env = loggedIn()
        ns.db.bar.slots = 2
        ns.Slots.Set(1, "Rejuvenation")
        ns.Slots.Set(2, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        local spells = ns.Row.AssignedSpells(row)

        assertEqual(2, #spells)
        assertEqual("Rejuvenation", spells[1])
        assertEqual("Regrowth", spells[2])
    end)

    it("leaves out a slot with no button on screen", function()
        -- A spell this character has not learned has no button, so a report
        -- listing it would be answering for an icon nobody can see.
        local ns, env = loggedIn()
        ns.db.bar.slots = 2
        ns.Slots.Set(1, "Rejuvenation")
        ns.Slots.Set(2, "Tranquility")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)

        local spells = ns.Row.AssignedSpells(row)

        assertEqual(1, #spells)
        assertEqual("Rejuvenation", spells[1])
    end)
end)

describe("whose cast the number under an icon is", function()
    local function rowWithRejuvenation(ns, env)
        ns.db.bar.slots = 1
        ns.Slots.Set(1, "Rejuvenation")
        local row = ns.Row.Create("party1", env.UIParent)
        ns.Row.ApplySpells(row)
        return row
    end

    it("counts down a buff somebody else cast, rather than leaving it blank", function()
        -- Re-casting over a Rejuvenation that is already running buys
        -- nothing, so a blank there would be asking for a wasted global.
        local ns, env = loggedIn()
        local row = rowWithRejuvenation(ns, env)
        env.__now = 1000
        env.__auras.party1 =
            { { name = "Rejuvenation", expirationTime = 1007, caster = "party2" } }

        ns.Row.Refresh(row)

        assertEqual("7s", row.buttons[1].timer:GetText())
    end)

    it("greys that number, because it is not a heal you have", function()
        local ns, env = loggedIn()
        local row = rowWithRejuvenation(ns, env)
        env.__now = 1000
        env.__auras.party1 =
            { { name = "Rejuvenation", expirationTime = 1007, caster = "party2" } }

        ns.Row.Refresh(row)

        local colour = row.buttons[1].timer.textColor
        assertTrue(colour and colour[1] < 1, "somebody else's number is greyed")
    end)

    it("leaves your own number at full strength", function()
        local ns, env = loggedIn()
        local row = rowWithRejuvenation(ns, env)
        env.__now = 1000
        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007 } }

        ns.Row.Refresh(row)

        assertEqual(1, row.buttons[1].timer.textColor[1])
    end)

    it("takes back the grey when the buff becomes yours again", function()
        -- Nothing else ever resets the colour, so a button that greyed once
        -- would stay grey over every cast that followed.
        local ns, env = loggedIn()
        local row = rowWithRejuvenation(ns, env)
        env.__now = 1000
        env.__auras.party1 =
            { { name = "Rejuvenation", expirationTime = 1007, caster = "party2" } }
        ns.Row.Refresh(row)

        env.__auras.party1 = { { name = "Rejuvenation", expirationTime = 1007 } }
        ns.Row.Refresh(row)

        assertEqual(1, row.buttons[1].timer.textColor[1])
    end)

    it("reads a buff on your own unit as yours, since this client will not say", function()
        local ns, env = loggedIn()
        ns.db.bar.slots = 1
        ns.Slots.Set(1, "Mark of the Wild")
        local row = ns.Row.Create("player", env.UIParent)
        ns.Row.ApplySpells(row)
        env.__now = 1000
        env.__auras.player =
            { { name = "Mark of the Wild", expirationTime = 3280, caster = false } }

        ns.Row.Refresh(row)

        assertEqual("38m", row.buttons[1].timer:GetText())
        assertEqual(1, row.buttons[1].timer.textColor[1])
    end)
end)
