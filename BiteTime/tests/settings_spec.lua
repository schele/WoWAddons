local helpers = require("helpers")

local RANK1 = 22568

local function opened(setup)
    local ns, env = helpers.loggedIn(function(env, ns)
        env.__place(1, RANK1)
        if setup then setup(env, ns) end
    end)
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

describe("the settings page", function()
    it("is a page in the game's options, named BiteTime", function()
        local _, env = helpers.loggedIn()
        assertEqual("BiteTime", env.__settingsCategory.name)
    end)

    it("waits for login before claiming its place", function()
        local _, env = helpers.loadAddon()
        assertNil(env.__settingsCategory)
        helpers.login(env)
        assertEqual("BiteTime", env.__settingsCategory.name)
    end)

    it("stays unbuilt until the options window opens it", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.SettingsPanel.panel:IsShown())
        assertNil(ns.SettingsPanel.hint, "nothing built yet")
    end)

    it("heads the page with BiteTime's logo and the version from the .toc", function()
        local _, _, panel = opened()
        assertEqual("Interface\\AddOns\\BiteTime\\logo", panel.logo:GetTexture())
        assertEqual("Version 9.9.9", panel.version:GetText())
    end)

    it("says what it does, and why it has no sound", function()
        local _, _, panel = opened()
        local text = panel.hint:GetText()
        assertMatch("Ferocious Bite", text)
        assertMatch("combo points", text)
        assertMatch("hides a mob's health from addons", text)
        assertMatch("no sound", text)
    end)

    it("labels each switch", function()
        local _, _, panel = opened()
        assertEqual("Glow on your Ferocious Bite buttons", panel.labels.buttons:GetText())
        assertEqual("Show the Bite icon above the middle of the screen", panel.labels.center:GetText())
    end)

    it("hangs the first row 16 pixels under the description", function()
        local _, _, panel = opened()
        local check = panel.checks.buttons
        local point, relativeTo, relativePoint, _, y = table.unpack(check.points[#check.points])
        assertEqual("TOPLEFT", point)
        assertEqual(panel.hint, relativeTo)
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(-16, y)
    end)

    it("shows what is saved", function()
        local _, _, panel = opened(function(env)
            env.BiteTimeDB = { settings = { center = false, share = 65 } }
        end)
        assertTrue(panel.checks.buttons:GetChecked())
        assertFalse(panel.checks.center:GetChecked())
        assertEqual(65, panel.share:GetValue())
        assertEqual("Count a Bite at 65% of its tooltip damage", panel.shareLabel:GetText())
    end)

    it("writes each switch's setting", function()
        local ns, _, panel = opened()
        for _, key in ipairs({ "buttons", "center" }) do
            click(panel.checks[key])
            assertFalse(ns.settings[key], key)
            click(panel.checks[key])
            assertTrue(ns.settings[key], key)
        end
    end)

    it("writes the share from the slider, in whole steps", function()
        local ns, _, panel = opened()
        panel.share:SetValue(71.6)
        assertEqual(70, ns.settings.share)
        assertEqual("Count a Bite at 70% of its tooltip damage", panel.shareLabel:GetText())
    end)

    it("runs the share from 50% to 100%", function()
        local _, _, panel = opened()
        local low, high = panel.share:GetMinMaxValues()
        assertEqual(50, low)
        assertEqual(100, high)
    end)

    it("has a button that lights everything for a test", function()
        local ns, env, panel = opened()
        assertEqual("Test", panel.test:GetText())
        panel.test.scripts.OnClick(panel.test)
        assertEqual(1, helpers.seen(env, ns.Glow.center))
    end)
end)

describe("the page's Bite line", function()
    it("says how many buttons hold a Bite", function()
        local _, _, panel = opened()
        assertEqual("Ferocious Bite is on 1 of your action buttons.", panel.status:GetText())
    end)

    it("says when none does", function()
        local _, _, panel = opened(function(env) env.__actions[1] = nil end)
        assertEqual("Ferocious Bite is on none of your action buttons, so only the icon in the middle can light.",
            panel.status:GetText())
    end)

    it("says when the character has not learned it", function()
        local _, _, panel = opened(function(env)
            env.__actions[1] = nil
            env.__known = {}
        end)
        assertEqual("You have not learned Ferocious Bite yet.", panel.status:GetText())
    end)

    it("is checked again each time the page opens", function()
        local _, env, panel = opened()
        panel.panel:Hide()
        env.__actions[1] = nil
        panel.panel:Show()
        assertMatch("on none", panel.status:GetText())
    end)
end)

describe("opening the page", function()
    it("is what a bare /bt does", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("is /bt settings too", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)
end)
