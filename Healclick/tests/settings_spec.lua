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
end)
