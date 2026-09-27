local helpers = require("helpers")

--- Logged in as Carl, with Alt's bank saved too, and the page on screen.
local function opened()
    local ns, env = helpers.loggedIn()
    ns.db.characters["Stormwind-Carl"] = { name = "Carl", realm = "Stormwind", class = "DRUID", saved = env.__now - 7200, containers = {} }
    ns.db.characters["Stormwind-Alt"] = { name = "Alt", realm = "Stormwind", class = "MAGE", saved = env.__now - 60, containers = {} }
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

local function shownRows(panel)
    local n = 0
    for _, row in ipairs(panel.rows) do if row:IsShown() then n = n + 1 end end
    return n
end

describe("the settings page", function()
    it("is a page in the game's options, named BankBags", function()
        local ns, env = helpers.loggedIn()
        assertEqual("BankBags", env.__settingsCategory.name)
    end)

    it("opens from /bb settings", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("heads the page with BankBags' own sack", function()
        local ns, env, panel = opened()
        assertEqual("Interface\\AddOns\\BankBags\\minimap", panel.logo:GetTexture())
    end)

    it("opens the bank window from its button, closing the options over it", function()
        local ns, env, panel = opened()
        env.SettingsPanel:Show()
        panel.open.scripts.OnClick(panel.open)
        assertFalse(env.SettingsPanel:IsShown())
        assertTrue(ns.Window.Frame():IsShown())
        env.GameMenuFrame:Show()
        assertFalse(env.GameMenuFrame:IsShown(), "nor the game menu over it")
    end)

    it("hides and shows the minimap button, and follows /bb minimap", function()
        local ns, env, panel = opened()
        assertTrue(panel.minimap:GetChecked())
        click(panel.minimap)
        assertTrue(ns.db.minimap.hide)
        assertFalse(ns.MinimapButton.Button():IsShown())
        helpers.command(env, "minimap")
        assertTrue(panel.minimap:GetChecked())
        assertTrue(ns.MinimapButton.Button():IsShown())
    end)
end)

describe("the saved banks on the page", function()
    it("lists each character, the one played first, with when it was saved", function()
        local ns, env, panel = opened()
        assertEqual(2, shownRows(panel))
        assertMatch("Carl", panel.rows[1].label:GetText())
        assertMatch("Saved 2 hours ago", panel.rows[1].label:GetText())
        assertMatch("Alt", panel.rows[2].label:GetText())
    end)

    it("forgets a character from its row", function()
        local ns, env, panel = opened()
        panel.rows[2].forget.scripts.OnClick(panel.rows[2].forget)
        assertNil(ns.db.characters["Stormwind-Alt"])
        assertTrue(ns.db.characters["Stormwind-Carl"] ~= nil, "only that one")
        assertEqual(1, shownRows(panel))
    end)

    it("says how to save one when none is saved", function()
        local ns, env = helpers.loggedIn()
        local panel = ns.SettingsPanel
        panel.panel:Show()
        assertEqual(0, shownRows(panel))
        assertTrue(panel.none:IsShown())
        assertMatch("banker", panel.none:GetText())
    end)
end)
