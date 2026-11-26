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

describe("the Forms section", function()
    local CAT, MOONKIN = helpers.CAT, 24858

    --- A druid with sets "Cat" (1) and "Bear" (2), the page open.
    local function druidPage(extra)
        local ns, env = helpers.start(nil, function(env)
            helpers.druid(env)
            helpers.makeSet(env, 1, "Cat", {})
            helpers.makeSet(env, 2, "Bear", {})
            if extra then extra(env) end
        end)
        ns.SettingsPanel.panel:Show()
        return ns, env, ns.SettingsPanel
    end

    local function radioTexts(dropdown)
        local texts = {}
        for index, radio in ipairs(dropdown.radios) do
            texts[index] = radio.text
        end
        return table.concat(texts, ", ")
    end

    it("has a row for each form, named as the game names it", function()
        local _, _, panel = druidPage()
        assertEqual(4, #panel.forms)
        assertEqual("Bear Form", panel.forms[1].label:GetText())
        assertEqual("Cat Form", panel.forms[3].label:GetText())
    end)

    it("offers Leave gear alone and every set", function()
        local _, _, panel = druidPage()
        assertEqual("Leave gear alone, Cat, Bear", radioTexts(panel.forms[3].dropdown))
    end)

    it("shows Leave gear alone until a set is picked", function()
        local _, _, panel = druidPage()
        assertEqual("Leave gear alone", panel.forms[3].dropdown.selectionText)
    end)

    it("saves the set you pick for that form", function()
        local ns, _, panel = druidPage()
        panel.forms[3].dropdown:Pick(2)
        assertEqual(1, ns.Forms.GetSet(CAT))
        assertEqual("Cat", panel.forms[3].dropdown.selectionText)
    end)

    it("lets you go back to Leave gear alone", function()
        local ns, _, panel = druidPage()
        panel.forms[3].dropdown:Pick(2)
        panel.forms[3].dropdown:Pick(1)
        assertNil(ns.Forms.GetSet(CAT))
    end)

    it("hangs the first row 16px under the description", function()
        local _, _, panel = druidPage()
        local point = panel.forms[1].dropdown.points[1]
        assertEqual("TOPLEFT", point[1])
        assertEqual(panel.about, point[2])
        assertEqual("BOTTOMLEFT", point[3])
        assertEqual(-16, point[5])
    end)

    it("says so on a character without forms", function()
        local ns = helpers.start(nil)
        ns.SettingsPanel.panel:Show()
        local panel = ns.SettingsPanel
        assertEqual(0, #panel.forms)
        assertEqual("This character has no forms or stances.", panel.noForms:GetText())
        assertTrue(panel.noForms:IsShown())
    end)

    it("hides that line for a character with forms", function()
        local _, _, panel = druidPage()
        assertFalse(panel.noForms:IsShown())
    end)

    it("adds a form learned since the page was last open", function()
        local _, env, panel = druidPage()
        panel.panel:Hide()
        table.insert(env.__forms, { spellID = MOONKIN, name = "Moonkin Form" })
        panel.panel:Show()
        assertEqual(5, #panel.forms)
        assertEqual("Moonkin Form", panel.forms[5].label:GetText())
    end)

    it("says how forms and sets work", function()
        local _, _, panel = druidPage()
        local text = panel.about:GetText()
        assertMatch("shifting into the form puts it on", text)
        assertMatch("Equipment Manager", text)
    end)
end)
