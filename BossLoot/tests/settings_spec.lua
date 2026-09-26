local helpers = require("helpers")

--- Logged in with the page on screen, as the options window shows it.
local function opened()
    local ns, env = helpers.loggedIn()
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

describe("the settings page", function()
    it("is a page in the game's options, named BossLoot", function()
        local ns, env = helpers.loggedIn()
        assertEqual("BossLoot", env.__settingsCategory.name)
    end)

    it("opens from /bl settings", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("heads the page with BossLoot's own chest", function()
        local ns, env, panel = opened()
        assertEqual("Interface\\AddOns\\BossLoot\\minimap", panel.logo:GetTexture())
    end)

    it("opens the loot window from its button, closing the options over it", function()
        local ns, env, panel = opened()
        env.SettingsPanel:Show()
        panel.open.scripts.OnClick(panel.open)
        assertFalse(env.SettingsPanel:IsShown())
        assertTrue(ns.Window.Frame():IsShown())
    end)

    -- Reached through the game menu, the options put it back as they close;
    -- over the window just opened, it would hide it.
    it("does not leave the game menu over the window it opened", function()
        local ns, env, panel = opened()
        env.SettingsPanel:Show()
        panel.open.scripts.OnClick(panel.open)
        env.GameMenuFrame:Show()
        assertFalse(env.GameMenuFrame:IsShown())
    end)
end)

describe("the page's switches", function()
    it("hide and show the minimap button", function()
        local ns, env, panel = opened()
        assertTrue(panel.minimap:GetChecked())
        click(panel.minimap)
        assertTrue(ns.db.minimap.hide)
        assertFalse(ns.MinimapButton.Button():IsShown())
        click(panel.minimap)
        assertFalse(ns.db.minimap.hide)
        assertTrue(ns.MinimapButton.Button():IsShown())
    end)

    it("follow /bl minimap while the page is open", function()
        local ns, env, panel = opened()
        helpers.command(env, "minimap")
        assertFalse(panel.minimap:GetChecked())
    end)

    it("turn the item loading details on and off", function()
        local ns, env, panel = opened()
        ns.Window.Open()
        click(panel.debug)
        assertTrue(ns.db.debug)
        assertTrue(ns.Window.Frame().debug:IsShown())
        click(panel.debug)
        assertFalse(ns.db.debug)
        assertFalse(ns.Window.Frame().debug:IsShown())
    end)

    it("bring back hidden instances, saying how many there are", function()
        local ns, env = helpers.loggedIn()
        ns.Window.HideInstance("Core")
        local panel = ns.SettingsPanel
        panel.panel:Show()
        assertMatch("1 hidden instance", panel.unhide:GetText())
        panel.unhide.scripts.OnClick(panel.unhide)
        assertNil(ns.db.hidden.Core)
        assertMatch("No hidden instances", panel.unhide:GetText())
    end)
end)

describe("closing the page", function()
    it("does not leave the game menu behind when opened by command", function()
        local ns, env = helpers.loggedIn()
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.GameMenuFrame:Show()
        assertFalse(env.GameMenuFrame:IsShown())
    end)
end)
