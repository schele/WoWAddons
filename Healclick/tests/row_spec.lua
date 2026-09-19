local helpers = require("helpers")

local FILES = { "Healclick.lua", "Slots.lua", "Row.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
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

    it("survives a unit that is not there at all", function()
        local ns, env = loggedIn()
        local row = ns.Row.Create("party4", env.UIParent)

        ns.Row.Refresh(row)
        assertEqual("", row.name:GetText())
    end)
end)
