local helpers = require("helpers")

local POLE, STAFF = 6256, 1161

--- Logged in holding whatever is given in the main hand, a pole by default.
local function loggedIn(mainHand)
    local ns, env = helpers.loadAddon()
    env.__mainHand = mainHand or POLE
    helpers.login(ns, env)
    return ns, env
end

--- Logged in with the page on screen, as the options window shows it.
local function opened(mainHand)
    local ns, env = loggedIn(mainHand)
    ns.SettingsPanel.panel:Show()
    return ns, env, ns.SettingsPanel
end

--- Click a checkbox the way the player does: the tick flips, then OnClick.
local function click(checkbox)
    checkbox:SetChecked(not checkbox:GetChecked())
    checkbox.scripts.OnClick(checkbox)
end

local function press(button, key)
    button.scripts.OnKeyDown(button, key)
end

describe("the settings page", function()
    it("is a page in the game's options, named FishingForever", function()
        local ns, env = loggedIn()
        assertEqual("FishingForever", env.__settingsCategory.name)
    end)

    it("opens from /ff settings", function()
        local ns, env = loggedIn()
        helpers.command(env, "settings")
        assertEqual("category-id", env.__openedCategory)
    end)

    it("shows what is saved when it opens", function()
        local ns, env = loggedIn()
        ns.db.fishing.autoLoot = false
        ns.db.fishing.key = "SHIFT-G"
        local panel = ns.SettingsPanel
        panel.panel:Show()
        assertTrue(panel.enabled:GetChecked())
        assertFalse(panel.autoLoot:GetChecked())
        assertEqual("SHIFT-G", panel.key:GetText())
    end)

    it("heads the page with FishingForever's own icon", function()
        local ns, env, panel = opened()
        assertEqual("Interface\\AddOns\\FishingForever\\minimap", panel.logo:GetTexture())
    end)
end)

describe("the page's switches", function()
    it("turn FishingForever off, giving the key back, and on again", function()
        local ns, env, panel = opened()
        click(panel.enabled)
        assertFalse(ns.db.fishing.enabled)
        assertNil(env.__bindings.F)
        click(panel.enabled)
        assertTrue(ns.db.fishing.enabled)
        assertEqual("FishingForeverCastButton", env.__bindings.F.button)
    end)

    it("have no box to take the key without a pole", function()
        local ns, env, panel = opened(STAFF)
        assertNil(panel.withoutPole)
        assertNil(env.__bindings.F)
    end)

    it("give the player's own auto loot back when auto loot is turned off", function()
        local ns, env, panel = opened()
        assertEqual("1", env.__cvars.autoLootDefault, "on while fishing")
        click(panel.autoLoot)
        assertFalse(ns.db.fishing.autoLoot)
        assertEqual("0", env.__cvars.autoLootDefault)
    end)

    it("follow a change made by command while the page is open", function()
        local ns, env, panel = opened()
        helpers.command(env, "off")
        assertFalse(panel.enabled:GetChecked())
        helpers.command(env, "autoloot")
        assertFalse(panel.autoLoot:GetChecked())
        helpers.command(env, "key H")
        assertEqual("H", panel.key:GetText())
    end)
end)

describe("the fishing key button", function()
    it("shows the key, and does not listen for keys until clicked", function()
        local ns, env, panel = opened()
        assertEqual("F", panel.key:GetText())
        assertFalse(panel.key.keyboard or false)
    end)

    it("takes the next key pressed after a click", function()
        local ns, env, panel = opened()
        panel.key.scripts.OnClick(panel.key)
        assertMatch("[Pp]ress a key", panel.key:GetText())
        assertTrue(panel.key.keyboard)
        press(panel.key, "G")
        assertEqual("G", ns.db.fishing.key)
        assertEqual("G", panel.key:GetText())
        assertEqual("FishingForeverCastButton", env.__bindings.G.button)
        assertNil(env.__bindings.F, "the old key given back")
        assertFalse(panel.key.keyboard, "the keyboard let go")
    end)

    it("keeps the modifiers held with the key", function()
        local ns, env, panel = opened()
        panel.key.scripts.OnClick(panel.key)
        env.__modifiers.shift = true
        env.__modifiers.ctrl = true
        press(panel.key, "G")
        assertEqual("CTRL-SHIFT-G", ns.db.fishing.key)
    end)

    it("waits past a modifier pressed by itself", function()
        local ns, env, panel = opened()
        panel.key.scripts.OnClick(panel.key)
        press(panel.key, "LSHIFT")
        assertEqual("F", ns.db.fishing.key)
        assertTrue(panel.key.keyboard, "still waiting")
    end)

    it("leaves the key as it was on Escape", function()
        local ns, env, panel = opened()
        panel.key.scripts.OnClick(panel.key)
        press(panel.key, "ESCAPE")
        assertEqual("F", ns.db.fishing.key)
        assertEqual("F", panel.key:GetText())
        assertFalse(panel.key.keyboard)
    end)

    it("lets go of the keyboard when the page is hidden", function()
        local ns, env, panel = opened()
        panel.key.scripts.OnClick(panel.key)
        panel.panel:Hide()
        assertFalse(panel.key.keyboard)
        assertEqual("F", panel.key:GetText())
    end)
end)

describe("the recast key", function()
    it("has a box, ticked to begin with, that turns it off and on", function()
        local ns, env, panel = opened()
        assertTrue(panel.recast:GetChecked())
        click(panel.recast)
        assertFalse(ns.db.fishing.recast)
        assertNil(env.__bindings["SHIFT-F"])
        click(panel.recast)
        assertEqual("FishingForeverCastButton", env.__bindings["SHIFT-F"].button)
    end)

    it("has a key button that takes the next key pressed after a click", function()
        local ns, env, panel = opened()
        assertEqual("SHIFT-F", panel.recastKey:GetText())
        panel.recastKey.scripts.OnClick(panel.recastKey)
        assertMatch("[Pp]ress a key", panel.recastKey:GetText())
        env.__modifiers.ctrl = true
        press(panel.recastKey, "G")
        assertEqual("CTRL-G", ns.db.fishing.recastKey)
        assertEqual("CTRL-G", panel.recastKey:GetText())
        assertEqual("F", ns.db.fishing.key, "the fishing key left alone")
        assertFalse(panel.recastKey.keyboard, "the keyboard let go")
    end)

    it("greys its key button out while it is off", function()
        local ns, env, panel = opened()
        assertTrue(panel.recastKey:IsEnabled())
        click(panel.recast)
        assertFalse(panel.recastKey:IsEnabled())
    end)

    it("lets one key button listen at a time", function()
        local ns, env, panel = opened()
        panel.key.scripts.OnClick(panel.key)
        panel.recastKey.scripts.OnClick(panel.recastKey)
        assertFalse(panel.key.keyboard, "the first let go")
        assertEqual("F", panel.key:GetText())
        press(panel.recastKey, "G")
        assertEqual("F", ns.db.fishing.key)
        assertEqual("G", ns.db.fishing.recastKey)
    end)

    it("follows a change made by command while the page is open", function()
        local ns, env, panel = opened()
        helpers.command(env, "recast")
        assertFalse(panel.recast:GetChecked())
        helpers.command(env, "recast H")
        assertTrue(panel.recast:GetChecked())
        assertEqual("H", panel.recastKey:GetText())
    end)
end)

describe("closing the page", function()
    -- Opening a page by command leaves the client queued to fall back to the
    -- game menu when it closes, which is not where the player came from.
    it("does not leave the game menu behind", function()
        local ns, env = loggedIn()
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.GameMenuFrame:Show()
        assertFalse(env.GameMenuFrame:IsShown(), "gone before a frame is drawn")
    end)

    it("leaves the game menu alone when the player opened the page from it", function()
        local ns, env = loggedIn()
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.__runTimers()

        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.GameMenuFrame:Show()
        env.__runTimers()
        assertTrue(env.GameMenuFrame:IsShown(), "left where the client put it")
    end)
end)

describe("the page's layout", function()
    -- The hint wraps to three lines. Rows placed at a fixed height on the
    -- panel let its last line crowd the first checkbox.
    it("hangs the first row off the bottom of the hint, with room to breathe", function()
        local ns, env, panel = opened()
        local point, relativeTo, relativePoint, x, y = panel.enabled:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertTrue(relativeTo == panel.hint, "anchored to the hint")
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(0, x, "the checkbox lines up with the hint, as before")
        assertTrue(y <= -16, "at least 16px below the hint")
    end)

    it("keeps every row below it off the hint too, in order", function()
        local ns, env, panel = opened()
        local previous = 0
        for _, widget in ipairs({ panel.enabled, panel.key, panel.recast, panel.recastKey,
            panel.autoLoot, panel.minimap,
            panel.skillBar, panel.skillBarLocked, panel.skillBarStats, panel.skillBarReset }) do
            local _, relativeTo, _, _, y = widget:GetPoint(1)
            assertTrue(relativeTo == panel.hint, "anchored to the hint")
            assertTrue(y < previous, "below the row before")
            previous = y
        end
    end)
end)
