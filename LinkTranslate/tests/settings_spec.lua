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

local SWITCHES = { "translate", "hover" }

describe("the settings page", function()
    it("is a page in the game's options, named LinkTranslate", function()
        local _, env = helpers.loggedIn()
        assertEqual("LinkTranslate", env.__settingsCategory.name)
    end)

    it("waits for login before claiming its place", function()
        local _, env = helpers.loadAddon()
        assertNil(env.__settingsCategory)
        helpers.login(env)
        assertEqual("LinkTranslate", env.__settingsCategory.name)
    end)

    it("stays unbuilt until the options window opens it", function()
        local ns = helpers.loggedIn()
        assertFalse(ns.SettingsPanel.panel:IsShown())
        assertNil(ns.SettingsPanel.hint, "nothing built yet")
    end)

    it("heads the page with LinkTranslate's logo and the version from the .toc", function()
        local _, _, panel = opened()
        assertEqual("Interface\\AddOns\\LinkTranslate\\logo", panel.logo:GetTexture())
        assertEqual("Version 9.9.9", panel.version:GetText())
    end)

    it("says what it does, and that what people type is left alone", function()
        local _, _, panel = opened()
        local text = panel.hint:GetText()
        assertMatch("quest, item or spell", text)
        assertMatch("%[Bride of the Embalmer%]", text)
        assertMatch("What people type is left as it is", text)
    end)

    it("labels each switch", function()
        local _, _, panel = opened()
        assertEqual("Show links in chat by your game's names", panel.labels.translate:GetText())
        assertEqual("Point at a changed link to see what the sender's game calls it", panel.labels.hover:GetText())
    end)

    it("hangs the first row 16 pixels under the description", function()
        local _, _, panel = opened()
        local check = panel.checks.translate
        local point, relativeTo, relativePoint, _, y = table.unpack(check.points[#check.points])
        assertEqual("TOPLEFT", point)
        assertEqual(panel.hint, relativeTo)
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(-16, y)
    end)

    it("starts with both switches on", function()
        local _, _, panel = opened()
        for _, key in ipairs(SWITCHES) do
            assertTrue(panel.checks[key]:GetChecked(), key)
        end
    end)

    it("shows what is saved", function()
        local _, _, panel = opened(function(env)
            env.LinkTranslateDB = { settings = { hover = false } }
        end)
        assertTrue(panel.checks.translate:GetChecked())
        assertFalse(panel.checks.hover:GetChecked())
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

    it("follows /lt off while it is open", function()
        local _, env, panel = opened()
        helpers.command(env, "off")
        assertFalse(panel.checks.translate:GetChecked())
    end)
end)

describe("opening the page", function()
    it("is what a bare /lt does", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("is /lt settings too", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)
end)

describe("/lt help", function()
    it("lists the commands", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "help")
        local text = helpers.printed(env)
        assertMatch("/lt %- Open the settings page", text)
        assertMatch("/lt on %- ", text)
        assertMatch("/lt off %- ", text)
    end)

    it("is what an unknown command gets", function()
        local _, env = helpers.loggedIn()
        helpers.command(env, "dance")
        local text = helpers.printed(env)
        assertMatch("Unknown command: dance", text)
        assertMatch("/lt on %- ", text)
    end)
end)
