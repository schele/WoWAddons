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

local SWITCHES = { "sound", "screen", "chat" }

describe("the settings page", function()
    it("is a page in the game's options, named StealthWatch", function()
        local _, env = helpers.loggedIn()
        assertEqual("StealthWatch", env.__settingsCategory.name)
    end)

    it("waits for login before claiming its place", function()
        local _, env = helpers.loadAddon()
        assertNil(env.__settingsCategory)
        helpers.login(env)
        assertEqual("StealthWatch", env.__settingsCategory.name)
    end)

    it("stays unbuilt until the options window opens it", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.SettingsPanel.panel:IsShown())
        assertNil(ns.SettingsPanel.hint, "nothing built yet")
    end)

    it("heads the page with StealthWatch's logo and the version from the .toc", function()
        local _, _, panel = opened()
        assertEqual("Interface\\AddOns\\StealthWatch\\logo", panel.logo:GetTexture())
        assertEqual("Version 9.9.9", panel.version:GetText())
    end)

    it("says what it does, and that it needs enemy nameplates", function()
        local _, _, panel = opened()
        local text = panel.hint:GetText()
        assertMatch("enemy player", text)
        assertMatch("instant", text)
        assertMatch("nameplates", text)
    end)

    it("names the stealth spells it watches for, as the client calls them", function()
        local _, _, panel = opened()
        assertMatch("Watching for: Stealth, Vanish, Prowl, Shadowmeld, Lesser Invisibility, Invisibility%.",
            panel.hint:GetText())
    end)

    it("labels each switch", function()
        local _, _, panel = opened()
        assertEqual("Play a warning sound", panel.labels.sound:GetText())
        assertEqual("Show a warning in the middle of the screen", panel.labels.screen:GetText())
        assertEqual("Print a line in chat", panel.labels.chat:GetText())
    end)

    it("hangs the first row 16 pixels under the description", function()
        local _, _, panel = opened()
        local point, relativeTo, relativePoint, _, y = table.unpack(panel.checks.sound.points[#panel.checks.sound.points])
        assertEqual("TOPLEFT", point)
        assertEqual(panel.hint, relativeTo)
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(-16, y)
    end)

    it("shows what is saved", function()
        local _, _, panel = opened(function(env)
            env.StealthWatchDB = { settings = { sound = false } }
        end)
        assertFalse(panel.checks.sound:GetChecked())
        assertTrue(panel.checks.screen:GetChecked())
        assertTrue(panel.checks.chat:GetChecked())
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

    it("has a button that shows a test alert", function()
        local _, env, panel = opened()
        assertEqual("Test", panel.test:GetText())
        panel.test.scripts.OnClick(panel.test)
        assertEqual(1, #env.__warnings)
    end)
end)

describe("the page's nameplate line", function()
    it("says enemy nameplates are on", function()
        local _, _, panel = opened()
        assertEqual("Enemy nameplates are on.", panel.status:GetText())
    end)

    it("says when they are off, and how to show them", function()
        local _, _, panel = opened(function(env) env.__cvars.nameplateShowEnemies = "0" end)
        assertEqual("Enemy nameplates are off, so StealthWatch only sees your target. Press V to show them.",
            panel.status:GetText())
    end)

    it("is checked again each time the page opens", function()
        local _, env, panel = opened()
        panel.panel:Hide()
        env.__cvars.nameplateShowEnemies = "0"
        panel.panel:Show()
        assertMatch("are off", panel.status:GetText())
    end)
end)

describe("opening the page", function()
    it("is what a bare /sw does", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("is /sw settings too", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)
end)
