local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)
    ns.SettingsPanel.EnsureBuilt()
    return ns, env
end

--- The control on the panel for a store and key.
local function controlFor(ns, store, key)
    for _, control in ipairs(ns.SettingsPanel.controls) do
        if control.setting.store == store and control.setting.key == key then
            return control
        end
    end
end

describe("the declared settings", function()
    it("declares one for each thing the panel offers", function()
        local ns = loggedIn()

        assertTrue(controlFor(ns, "chat", "rewrite") ~= nil, "the master switch")
        assertTrue(controlFor(ns, "chat", "shorten") ~= nil, "shortening")
        assertTrue(controlFor(ns, "history", "size") ~= nil, "the history size")
    end)

    it("puts the master switch first", function()
        local ns = loggedIn()
        assertEqual("rewrite", ns.SettingsPanel.controls[1].setting.key)
    end)
end)

describe("the panel", function()
    it("registers itself with the game's options", function()
        local ns, env = loggedIn()
        assertTrue(env.__settingsCategory ~= nil, "a category was registered")
    end)

    it("builds once, however often it is asked", function()
        local ns = loggedIn()
        local before = #ns.SettingsPanel.controls

        ns.SettingsPanel.EnsureBuilt()
        assertEqual(before, #ns.SettingsPanel.controls, "no second set of controls")
    end)

    it("shows the stored value when it refreshes", function()
        local ns = loggedIn()
        ns.db.chat.rewrite = false
        ns.SettingsPanel.Refresh()

        assertFalse(controlFor(ns, "chat", "rewrite").widget:GetChecked())
    end)

    it("writes a checkbox through to the database", function()
        local ns = loggedIn()
        local control = controlFor(ns, "chat", "shorten")

        control.widget:SetChecked(true)
        control.widget.scripts.OnClick(control.widget)

        assertTrue(ns.db.chat.shorten)
    end)

    it("opens from /url settings", function()
        local ns, env = loggedIn()
        helpers.command(env, "settings")

        assertEqual("category-id", env.__openedCategory)
    end)

    -- Opening the panel this way leaves the client queued to fall back to the
    -- game menu when it closes, which is not where the player came from.
    it("does not leave the game menu behind when it closes", function()
        local ns, env = loggedIn()

        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)

        -- The client shows the game menu as part of closing the panel. It has
        -- to go in the same frame, or the player sees it flash up first.
        env.GameMenuFrame:Show()

        assertFalse(env.GameMenuFrame:IsShown(), "gone before a frame is drawn")
    end)

    it("leaves the game menu alone when the player opened it themselves", function()
        local ns, env = loggedIn()

        -- Open and close once through our command, so the hook is in place
        -- and that close has finished settling.
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.__runTimers()

        -- Now the panel is reached through the game menu instead, so closing
        -- it should go back there as the client intends.
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.GameMenuFrame:Show()
        env.__runTimers()

        assertTrue(env.GameMenuFrame:IsShown(), "left where the client put it")
    end)
end)

describe("the history slider", function()
    it("writes through to the database", function()
        local ns = loggedIn()
        controlFor(ns, "history", "size").widget:SetValue(4)

        assertEqual(4, ns.db.history.size)
    end)

    it("trims the history at once, so the list matches the number shown", function()
        local ns, env = loggedIn()
        for index = 1, 8 do
            ns.History.Add("site" .. index .. ".com")
        end

        controlFor(ns, "history", "size").widget:SetValue(3)
        assertEqual(3, #ns.History.All())
    end)
end)

describe("the panel's heading", function()
    it("shows the logo, not the AddOns list icon", function()
        -- The same glyph drawn twice. icon.tga carries the tile the AddOns
        -- list needs; logo.tga is the glyph alone on transparency, because a
        -- tile on a dark panel reads as a sticker pasted onto it.
        local ns = loggedIn()
        assertEqual(
            [[Interface\AddOns\UrlCopy\logo]],
            ns.SettingsPanel.logo:GetTexture()
        )
    end)

    it("builds that path from the addon name, not a second copy of it", function()
        -- The .toc already names this folder. A path spelled out here as well
        -- is the one that goes stale when it is renamed.
        local ns = loggedIn()
        assertTrue(ns.SettingsPanel.logo:GetTexture():find("UrlCopy", 1, true) ~= nil)
        assertTrue(ns.SettingsPanel.logo:GetWidth() > 0, "and has a size to draw at")
    end)
end)

describe("the panel's layout", function()
    -- The hint wraps to as many lines as the font needs. Rows placed at a
    -- fixed height on the panel let its last line crowd the first checkbox.
    it("hangs the first row off the bottom of the hint, with room to breathe", function()
        local ns = loggedIn()
        local hint = ns.SettingsPanel.hint
        local point, relativeTo, relativePoint, x, y =
            ns.SettingsPanel.controls[1].widget:GetPoint(1)

        assertEqual("TOPLEFT", point)
        assertTrue(relativeTo == hint, "anchored to the hint")
        assertEqual("BOTTOMLEFT", relativePoint)
        assertEqual(0, x, "lined up with the hint's left edge")
        assertTrue(y <= -16, "at least 16px below the hint")
    end)

    it("keeps every row below the hint, in order", function()
        local ns = loggedIn()
        local previous = 0
        for _, control in ipairs(ns.SettingsPanel.controls) do
            local _, relativeTo, _, _, y = control.widget:GetPoint(1)
            assertTrue(relativeTo == ns.SettingsPanel.hint, control.setting.key)
            assertTrue(y < previous, control.setting.key .. " below the one before")
            previous = y
        end
    end)
end)

describe("the invert option", function()
    it("leaves an ordinary checkbox showing the stored value as it is", function()
        local ns = loggedIn()
        local control = controlFor(ns, "chat", "shorten")

        ns.db.chat.shorten = true
        ns.SettingsPanel.Refresh()
        assertTrue(control.widget:GetChecked())
        ns.db.chat.shorten = false
        ns.SettingsPanel.Refresh()
        assertFalse(control.widget:GetChecked())

        control.widget:SetChecked(false)
        control.widget.scripts.OnClick(control.widget)
        assertEqual(false, ns.db.chat.shorten)
        control.widget:SetChecked(true)
        control.widget.scripts.OnClick(control.widget)
        assertEqual(true, ns.db.chat.shorten)
    end)

    it("shows an inverted checkbox ticked while the stored value is false", function()
        local ns, env = helpers.loadAddon()
        ns.RegisterSetting({
            store = "chat", key = "shorten", type = "checkbox", invert = true, name = "Unshorten",
        })
        helpers.login(ns, env)
        ns.SettingsPanel.EnsureBuilt()
        local last = ns.SettingsPanel.controls[#ns.SettingsPanel.controls]
        assertEqual("Unshorten", last.setting.name)
        ns.db.chat.shorten = false
        ns.SettingsPanel.Refresh()
        assertTrue(last.widget:GetChecked(), "stored false shows ticked")

        ns.db.chat.shorten = true
        ns.SettingsPanel.Refresh()
        assertFalse(last.widget:GetChecked())

        last.widget:SetChecked(true)
        last.widget.scripts.OnClick(last.widget)
        assertEqual(false, ns.db.chat.shorten, "a tick stores the opposite")
    end)
end)
