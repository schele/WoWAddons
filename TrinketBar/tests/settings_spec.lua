local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)
    ns.SettingsPanel.EnsureBuilt()
    return ns, env
end

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

        assertTrue(controlFor(ns, "bar", "iconSize") ~= nil, "how big")
        assertTrue(controlFor(ns, "bar", "perRow") ~= nil, "how many across")
        assertTrue(controlFor(ns, "bar", "locked") ~= nil, "the lock")
    end)
end)

describe("the panel", function()
    it("registers itself with the game's options", function()
        local ns, env = loggedIn()
        assertTrue(env.__settingsCategory ~= nil)
    end)

    it("builds once, however often it is asked", function()
        local ns = loggedIn()
        local before = #ns.SettingsPanel.controls

        ns.SettingsPanel.EnsureBuilt()
        assertEqual(before, #ns.SettingsPanel.controls)
    end)

    it("opens from /tb settings", function()
        local ns, env = loggedIn()
        helpers.command(env, "settings")

        assertEqual("category-id", env.__openedCategory)
    end)

    it("shows the logo, not the AddOns list icon", function()
        -- The same glyph drawn twice. icon.tga carries the tile the AddOns
        -- list needs; logo.tga is the glyph alone on transparency, because
        -- a tile on a dark panel reads as a sticker pasted onto it.
        local ns = loggedIn()
        assertEqual(
            [[Interface\AddOns\TrinketBar\logo]],
            ns.SettingsPanel.logo:GetTexture()
        )
    end)
end)

describe("the sliders", function()
    it("writes through to the database", function()
        local ns = loggedIn()
        controlFor(ns, "bar", "iconSize").widget:SetValue(36)

        assertEqual(36, ns.db.bar.iconSize)
    end)

    it("applies the change to the buttons", function()
        local ns, env = loggedIn()
        env.__carry(0, 1, "Hand of Justice")
        ns.Bar.Apply()

        controlFor(ns, "bar", "iconSize").widget:SetValue(36)

        assertEqual(36, ns.Bar.Buttons()[1]:GetWidth())
    end)

    it("shows the stored value when it refreshes", function()
        local ns = loggedIn()
        ns.db.bar.perRow = 5

        ns.SettingsPanel.Refresh()
        assertEqual(5, controlFor(ns, "bar", "perRow").widget:GetValue())
    end)
end)

describe("the checkbox", function()
    it("writes through to the database", function()
        local ns = loggedIn()
        local control = controlFor(ns, "bar", "locked")

        control.widget:SetChecked(true)
        control.widget.scripts.OnClick(control.widget)

        assertTrue(ns.db.bar.locked)
    end)
end)
