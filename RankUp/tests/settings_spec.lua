local helpers = require("helpers")

--- Logged in, the page registered but not yet opened.
local function loggedIn(prepare)
    local ns, env = helpers.loadAddon(prepare)
    helpers.login(env)
    return ns, env
end

--- Logged in with the page on screen, as the options window shows it.
local function opened(prepare)
    local ns, env = loggedIn(prepare)
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

describe("the settings page", function()
    it("is a page in the game's options, named RankUp", function()
        local ns, env = loggedIn()
        assertEqual("RankUp", env.__settingsCategory.name)
    end)

    it("waits for login before claiming its place", function()
        local ns, env = helpers.loadAddon()
        assertNil(env.__settingsCategory)
        helpers.login(env)
        assertEqual("RankUp", env.__settingsCategory.name)
    end)

    it("stays off screen until the options window opens it", function()
        local ns, env = loggedIn()
        assertFalse(ns.SettingsPanel.panel:IsShown())
        assertNil(ns.SettingsPanel.check, "nothing built yet")
    end)

    it("heads the page with RankUp's own logo", function()
        local ns, env, panel = opened()
        assertEqual("Interface\\AddOns\\RankUp\\logo", panel.logo:GetTexture())
    end)

    it("shows the version from the .toc", function()
        local ns, env, panel = opened()
        assertEqual("Version 9.9.9", panel.version:GetText())
    end)

    it("says what it does and when it asks", function()
        local ns, env, panel = opened()
        local text = panel.about:GetText()
        assertMatch("highest rank", text)
        assertMatch("/rankup", text)
    end)

    it("still looks at login, with the page registered", function()
        local ns, env = helpers.loadAddon()
        helpers.place(env, 3, 5188)
        helpers.login(env)
        assertTrue(ns.Popup.IsShown())
        assertEqual("RankUp", env.__settingsCategory.name)
    end)
end)

describe("the Check my bars now button", function()
    it("is labelled so", function()
        local ns, env, panel = opened()
        assertEqual("Check my bars now", panel.check:GetText())
    end)

    it("offers the upgrade when a button holds an old rank, as /rankup does", function()
        local ns, env, panel = opened()
        helpers.place(env, 3, 5188)
        panel.check:Click()
        assertTrue(ns.Popup.IsShown())
    end)

    it("says so in chat when every button is current", function()
        local ns, env, panel = opened()
        helpers.place(env, 3, 5189)
        panel.check:Click()
        assertFalse(ns.Popup.IsShown())
        assertMatch("Every button already holds your highest rank", helpers.printed(env))
    end)

    it("waits for the fight to end, as /rankup does", function()
        local ns, env, panel = opened()
        helpers.place(env, 3, 5188)
        helpers.enterCombat(env)
        panel.check:Click()
        assertFalse(ns.Popup.IsShown())
        helpers.leaveCombat(env)
        assertTrue(ns.Popup.IsShown())
    end)
end)

describe("the page's layout", function()
    -- The paragraph wraps to as many lines as the font needs. Hung from it,
    -- the button stays clear of its last line however many there are.
    it("hangs the button off the bottom of the paragraph, with room to breathe", function()
        local ns, env, panel = opened()
        local point, relativeTo, relativePoint, x, y = table.unpack(panel.check.points[1])
        assertEqual("TOPLEFT", point)
        assertTrue(relativeTo == panel.about, "anchored to the paragraph")
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(0, x)
        assertTrue(y <= -16, "at least 16px below it")
    end)
end)
