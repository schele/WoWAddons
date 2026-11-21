local helpers = require("helpers")

local function opened(setup)
    local ns, env = helpers.loggedIn(setup)
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

local SWITCHES = { "shown", "combatOnly", "warn" }

describe("the settings page", function()
    it("is a page in the game's options, named ThreatForever", function()
        local _, env = helpers.loggedIn()
        assertEqual("ThreatForever", env.__settingsCategory.name)
    end)

    it("waits for login before claiming its place", function()
        local _, env = helpers.loadAddon()
        assertNil(env.__settingsCategory)
        helpers.login(env)
        assertEqual("ThreatForever", env.__settingsCategory.name)
    end)

    it("stays unbuilt until the options window opens it", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.SettingsPanel.panel:IsShown())
        assertNil(ns.SettingsPanel.hint, "nothing built yet")
    end)

    it("heads the page with ThreatForever's logo and the version from the .toc", function()
        local _, _, panel = opened()
        assertEqual("Interface\\AddOns\\ThreatForever\\logo", panel.logo:GetTexture())
        assertEqual("Version 9.9.9", panel.version:GetText())
    end)

    it("says what it shows, and what the game hides on a boss", function()
        local _, _, panel = opened()
        local text = panel.hint:GetText()
        assertMatch("threat", text)
        assertMatch("pulls aggro", text)
        assertMatch("boss", text)
    end)

    it("labels each switch", function()
        local _, _, panel = opened()
        assertEqual("Show the threat window", panel.labels.shown:GetText())
        assertEqual("Only in combat", panel.labels.combatOnly:GetText())
        assertEqual("Warn me before I pull aggro", panel.labels.warn:GetText())
    end)

    it("hangs the first row 16 pixels under the description", function()
        local _, _, panel = opened()
        local point, relativeTo, relativePoint, _, y = table.unpack(panel.checks.shown.points[#panel.checks.shown.points])
        assertEqual("TOPLEFT", point)
        assertEqual(panel.hint, relativeTo)
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(-16, y)
    end)

    it("shows what is saved", function()
        local _, _, panel = opened(function(env)
            env.ThreatForeverDB = { settings = { warn = false } }
        end)
        assertTrue(panel.checks.shown:GetChecked())
        assertTrue(panel.checks.combatOnly:GetChecked())
        assertFalse(panel.checks.warn:GetChecked())
    end)

    it("writes each switch's setting", function()
        local ns, _, panel = opened()
        for _, key in ipairs(SWITCHES) do
            click(panel.checks[key])
            assertFalse(ns.settings[key], key)
            click(panel.checks[key])
            assertTrue(ns.settings[key], key)
        end
    end)

    it("puts the window up at once when 'Only in combat' is turned off", function()
        local ns, _, panel = opened()
        assertFalse(ns.Window.frame:IsShown(), "out of combat")

        click(panel.checks.combatOnly)

        assertTrue(ns.Window.frame:IsShown())
    end)

    it("ticks the window's switch when /threat or the red X changes it", function()
        local ns, env, panel = opened()

        helpers.command(env, "")

        assertFalse(panel.checks.shown:GetChecked())
    end)

    it("has a button that shows the warning", function()
        local _, env, panel = opened()
        assertEqual("Test", panel.test:GetText())
        panel.test.scripts.OnClick(panel.test)
        assertEqual(1, #env.__warnings)
    end)
end)

describe("opening the page", function()
    it("is /threat settings", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)
end)
