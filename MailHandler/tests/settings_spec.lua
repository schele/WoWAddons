local helpers = require("helpers")

--- Logged in, the page registered but not yet opened.
local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(env)
    return ns, env
end

--- Logged in with the page on screen, as the options window shows it.
local function opened()
    local ns, env = loggedIn()
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

describe("the settings page", function()
    it("is a page in the game's options, named MailHandler", function()
        local ns, env = loggedIn()
        assertEqual("MailHandler", env.__settingsCategory.name)
    end)

    it("waits for login before claiming its place", function()
        local ns, env = helpers.loadAddon()
        assertNil(env.__settingsCategory)
        helpers.login(env)
        assertEqual("MailHandler", env.__settingsCategory.name)
    end)

    it("stays off screen until the options window opens it", function()
        local ns, env = loggedIn()
        assertFalse(ns.SettingsPanel.panel:IsShown())
        assertNil(ns.SettingsPanel.about, "nothing built yet")
    end)

    it("heads the page with MailHandler's own logo", function()
        local ns, env, panel = opened()
        assertEqual("Interface\\AddOns\\MailHandler\\logo", panel.logo:GetTexture())
    end)

    it("shows the version from the .toc", function()
        local ns, env, panel = opened()
        assertEqual("Version 9.9.9", panel.version:GetText())
    end)

    it("says how to use it: tick, then Open", function()
        local ns, env, panel = opened()
        local text = panel.about:GetText()
        assertMatch("[Tt]ick", text)
        assertMatch("Open %(N%)", text)
        assertMatch("Select all", text)
    end)

    it("says it never deletes a mail and never pays for one", function()
        local ns, env, panel = opened()
        local text = panel.about:GetText()
        assertMatch("[Nn]ever deletes", text)
        assertMatch("cash on delivery", text)
    end)

    it("builds once, however often it is opened", function()
        local ns, env, panel = opened()
        local about = panel.about
        panel.panel:Hide()
        panel.panel:Show()
        assertEqual(about, panel.about)
    end)
end)
