local helpers = require("helpers")

--- Logged in, the page registered but not yet opened.
local function loggedIn(prepare)
    local ns, env = helpers.load(prepare)
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
    it("is a page in the game's options, named WardrobeForever", function()
        local _, env = loggedIn()
        assertEqual("WardrobeForever", env.__settingsCategory.name)
    end)

    it("waits for login before claiming its place", function()
        local _, env = helpers.load()
        assertNil(env.__settingsCategory)
        helpers.login(env)
        assertEqual("WardrobeForever", env.__settingsCategory.name)
    end)

    it("stays off screen until the options window opens it", function()
        local ns = loggedIn()
        assertFalse(ns.SettingsPanel.panel:IsShown())
        assertNil(ns.SettingsPanel.about, "nothing built yet")
    end)

    it("heads the page with WardrobeForever's own logo", function()
        local _, _, panel = opened()
        assertEqual("Interface\\AddOns\\WardrobeForever\\logo", panel.logo:GetTexture())
    end)

    it("shows the version from the .toc", function()
        local _, _, panel = opened()
        assertEqual("Version 9.9.9", panel.version:GetText())
    end)

    it("says what hovering a slot does, and that Alt still works", function()
        local _, _, panel = opened()
        local text = panel.about:GetText()
        assertMatch("Hover a slot on the character sheet", text)
        assertMatch("Alt", text)
    end)

    -- The page is how a player finds the addon in the AddOns list, so it is
    -- there even where the hovering has nothing to work with.
    it("is there on a client without Blizzard's equipment list", function()
        local _, env = loggedIn(function(env)
            env.EquipmentFlyoutFrame = nil
        end)
        assertEqual("WardrobeForever", env.__settingsCategory.name)
    end)

    it("leaves the hovering working", function()
        local _, env = loggedIn()
        helpers.fits(env, helpers.SLOT.LEGS, helpers.inBag(0, 1))
        helpers.moveTo(env, env.CharacterLegsSlot)
        assertTrue(helpers.flyoutOpenFor(env, env.CharacterLegsSlot))
    end)
end)
