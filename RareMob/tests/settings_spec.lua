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

local SWITCHES = { "worldPins", "minimapPins", "showUnseen", "alert" }

describe("the settings page", function()
    it("is a page in the game's options, named RareMob, with its logo", function()
        local ns, env, panel = opened()
        assertEqual("RareMob", env.__settingsCategory.name)
        assertEqual("Interface\\AddOns\\RareMob\\minimap", panel.logo:GetTexture())
    end)

    it("opens from /rm settings", function()
        local ns, env = helpers.loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("labels each switch as the spec words it", function()
        local ns, env, panel = opened()
        assertEqual("Show pins on the world map", panel.labels.worldPins:GetText())
        assertEqual("Show pins on the minimap", panel.labels.minimapPins:GetText())
        assertEqual("Show rares only in the database", panel.labels.showUnseen:GetText())
        assertEqual("Alert sound", panel.labels.alert:GetText())
        assertEqual("Show the minimap button", panel.minimapLabel:GetText())
    end)

    it("shows every switch on and pins of 14 at first", function()
        local ns, env, panel = opened()
        for _, key in ipairs(SWITCHES) do
            assertTrue(panel.checks[key]:GetChecked(), key)
        end
        assertTrue(panel.minimap:GetChecked())
        assertEqual(14, panel.size:GetValue())
    end)

    it("shows what is saved", function()
        local ns, env, panel = opened(function(env)
            env.RareMobDB = { settings = { alert = false, showUnseen = false, pinSize = 20, button = { hide = true } } }
        end)
        assertFalse(panel.checks.alert:GetChecked())
        assertFalse(panel.checks.showUnseen:GetChecked())
        assertTrue(panel.checks.worldPins:GetChecked())
        assertEqual(20, panel.size:GetValue())
        assertFalse(panel.minimap:GetChecked())
    end)
end)

describe("the page's switches", function()
    it("each write their setting and redraw", function()
        local ns, env, panel = opened()
        local count = 0
        ns.OnRefresh(function() count = count + 1 end)
        for _, key in ipairs(SWITCHES) do
            click(panel.checks[key])
            assertFalse(ns.settings[key], key)
            click(panel.checks[key])
            assertTrue(ns.settings[key], key)
        end
        assertEqual(8, count)
    end)

    it("set the pin size, 8 to 24, and redraw", function()
        local ns, env, panel = opened()
        assertEqual(8, panel.size.minValue)
        assertEqual(24, panel.size.maxValue)
        panel.size:SetValue(18.4)
        assertEqual(18, ns.settings.pinSize)
    end)

    it("hide and show the minimap button", function()
        local ns, env, panel = opened()
        click(panel.minimap)
        assertTrue(ns.settings.button.hide)
        assertFalse(ns.MinimapButton.Button():IsShown())
        click(panel.minimap)
        assertFalse(ns.settings.button.hide)
    end)

    it("follow a change made by command while the page is open", function()
        local ns, env, panel = opened()
        helpers.command(env, "minimap")
        assertFalse(panel.minimap:GetChecked())
    end)
end)

describe("the page's layout", function()
    it("hangs the first row off the bottom of the hint, with room to breathe", function()
        local ns, env, panel = opened()
        local point, relativeTo, relativePoint, x, y = panel.checks.worldPins:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertTrue(relativeTo == panel.hint, "anchored to the hint")
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(0, x)
        assertTrue(y <= -16, "at least 16px below the hint")
    end)

    it("keeps every row below it off the hint too, in order", function()
        local ns, env, panel = opened()
        local previous = 0
        local rows = { panel.checks.worldPins, panel.checks.minimapPins, panel.checks.showUnseen,
            panel.checks.alert, panel.size, panel.minimap }
        for _, widget in ipairs(rows) do
            local _, relativeTo, _, _, y = widget:GetPoint(1)
            assertTrue(relativeTo == panel.hint, "anchored to the hint")
            assertTrue(y < previous, "below the row before")
            previous = y
        end
    end)

    it("shows the scroll bar only when there is something to scroll", function()
        local ns, env, panel = opened()
        local scroll = panel.scroll
        scroll.scrollRange = 0
        scroll.scripts.OnScrollRangeChanged(scroll)
        assertFalse(scroll.ScrollBar:IsShown())
        scroll.scrollRange = 40
        scroll.scripts.OnScrollRangeChanged(scroll)
        assertTrue(scroll.ScrollBar:IsShown())
    end)
end)

describe("closing the page", function()
    it("does not leave the game menu behind", function()
        local ns, env = helpers.loggedIn()
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.GameMenuFrame:Show()
        assertFalse(env.GameMenuFrame:IsShown())
    end)
end)
