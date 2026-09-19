local helpers = require("helpers")

local FILES = { "Healclick.lua", "Slots.lua", "Row.lua" }
local FILES_WITH_GROUP = { "Healclick.lua", "Slots.lua", "Row.lua", "Group.lua" }

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

    it("gives each button its slot index and an icon texture", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        for index = 1, ns.Slots.MAX do
            assertEqual(index, row.buttons[index].slot)
            assertTrue(row.buttons[index].icon ~= nil, "button " .. index .. " has an icon")
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

    it("shows the icon and clears the label when a texture is found", function()
        local ns, env = loggedIn()
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertEqual(136085, row.buttons[1].icon:GetTexture())
        assertTrue(row.buttons[1].icon:IsShown())
        assertEqual("", row.buttons[1].label:GetText())
    end)

    it("falls back to the label when no texture can be found", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellTexture = nil
        env.GetSpellTexture = nil
        ns.Slots.Set(1, "Regrowth")
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertFalse(row.buttons[1].icon:IsShown())
        assertEqual("Regr", row.buttons[1].label:GetText())
    end)

    it("hides the icon along with the label for an empty slot", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party1", env.UIParent)

        ns.Row.ApplySpells(row)

        assertFalse(row.buttons[1].icon:IsShown())
        assertEqual("", row.buttons[1].label:GetText())
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
end)

describe("resolving a spell's icon", function()
    it("uses C_Spell.GetSpellTexture when it exists", function()
        local ns = loggedIn()
        assertEqual(136085, ns.Row.SpellTexture("Regrowth"))
    end)

    it("falls back to the old global GetSpellTexture when C_Spell lacks it", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellTexture = nil

        assertEqual(136085, ns.Row.SpellTexture("Regrowth"))
    end)

    it("returns nil when neither API exists", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellTexture = nil
        env.GetSpellTexture = nil

        assertNil(ns.Row.SpellTexture("Regrowth"))
    end)

    it("returns nil for no spell at all", function()
        local ns = loggedIn()
        assertNil(ns.Row.SpellTexture(nil))
        assertNil(ns.Row.SpellTexture(""))
    end)
end)

describe("resolving what is on the cursor", function()
    it("returns nil when nothing is on the cursor", function()
        local ns, env = loggedIn()
        env.__cursor = nil

        assertNil(ns.Row.CursorSpell())
    end)

    it("returns nil for a non-spell, such as an item, and never touches it", function()
        local ns, env = loggedIn()
        env.__cursor = { "item", 6948 }

        assertNil(ns.Row.CursorSpell())
    end)

    it("resolves a spellID through C_Spell.GetSpellInfo", function()
        local ns, env = loggedIn()
        env.__cursor = { "spell", nil, nil, 8936, n = 4 }

        assertEqual("Rejuvenation", ns.Row.CursorSpell())
    end)

    it("falls back to the old GetSpellInfo when C_Spell lacks GetSpellInfo", function()
        local ns, env = loggedIn()
        env.C_Spell.GetSpellInfo = nil
        env.__cursor = { "spell", nil, nil, 8936, n = 4 }

        assertEqual("Rejuvenation", ns.Row.CursorSpell())
    end)

    it("resolves a spellbook index through C_SpellBook.GetSpellBookItemName", function()
        local ns, env = loggedIn()
        env.__cursor = { "spell", 5, "spell" }

        assertEqual("Regrowth", ns.Row.CursorSpell())
    end)

    it("falls back to the old GetSpellBookItemName when C_SpellBook lacks it", function()
        local ns, env = loggedIn()
        env.C_SpellBook.GetSpellBookItemName = nil
        env.__cursor = { "spell", 5, "spell" }

        assertEqual("Regrowth", ns.Row.CursorSpell())
    end)

    it("returns nil, never a number or a table, when nothing resolves a name", function()
        local ns, env = loggedIn()
        env.__cursor = { "spell", 999, "spell" }

        assertNil(ns.Row.CursorSpell())
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

        assertEqual("Rejuvenation", ns.Slots.Spell(2), "the seeded spell is untouched")
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
            "Rejuvenation",
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

describe("labelling a spell button", function()
    -- There is no icon, so this label is the only thing telling a healer
    -- which button is which. Two buttons reading the same thing under
    -- pressure is the wrong-spell-on-the-right-person failure this addon
    -- exists to prevent.

    it("takes the first four characters of a single-word name", function()
        local ns = loggedIn()
        assertEqual("Regr", ns.Row.Label("Regrowth"))
    end)

    it("takes the first four characters of another single-word name", function()
        local ns = loggedIn()
        assertEqual("Reju", ns.Row.Label("Rejuvenation"))
    end)

    it("takes the first letter of each significant word", function()
        local ns = loggedIn()
        assertEqual("RC", ns.Row.Label("Remove Curse"))
    end)

    it("drops short connective words like 'of' and 'the'", function()
        local ns = loggedIn()
        assertEqual("MW", ns.Row.Label("Mark of the Wild"))
    end)

    it("keeps a short word that is significant rather than filler", function()
        -- "Cat", "Ice" and "War" are exactly as short as "the", but dropping
        -- them the way a length rule would leaves a single letter that
        -- disambiguates nothing -- the whole reason Row.Label exists. Only a
        -- fixed stopword list, not word length, can tell these apart from
        -- "of" or "the".
        local ns = loggedIn()
        assertEqual("CF", ns.Row.Label("Cat Form"))
        assertEqual("IB", ns.Row.Label("Ice Block"))
        assertEqual("WS", ns.Row.Label("War Stomp"))
    end)

    it("strips punctuation before taking a word's first letter", function()
        local ns = loggedIn()
        assertEqual("PWF", ns.Row.Label("Power Word: Fortitude"))
    end)

    it("matches the rest of the worked examples", function()
        local ns = loggedIn()
        assertEqual("FL", ns.Row.Label("Flash of Light"))
        assertEqual("BF", ns.Row.Label("Bear Form"))
        assertEqual("CP", ns.Row.Label("Cure Poison"))
    end)

    it("returns an empty string for no spell at all", function()
        local ns = loggedIn()
        assertEqual("", ns.Row.Label(nil))
        assertEqual("", ns.Row.Label(""))
    end)

    it("gives the four shipped Druid seeds four distinct labels", function()
        local ns = loggedIn()
        local seeds = { "Regrowth", "Rejuvenation", "Remove Curse", "Mark of the Wild" }
        local seen = {}
        local uniqueCount = 0

        for _, spell in ipairs(seeds) do
            local label = ns.Row.Label(spell)
            if not seen[label] then
                seen[label] = true
                uniqueCount = uniqueCount + 1
            end
        end

        assertEqual(4, uniqueCount, "all four seeds must read differently on the button")
    end)

    it("never splits a multi-byte character in half", function()
        -- Five copies of U+3042 (Hiragana A), three bytes each in UTF-8. A
        -- byte-based sub(1, 4) would take one whole character plus one
        -- stray continuation byte of the next -- invalid UTF-8.
        local ns = loggedIn()
        local hiragana = "\227\129\130"
        local name = hiragana:rep(5)

        assertEqual(hiragana:rep(4), ns.Row.Label(name))
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
